#!/usr/bin/env bun
import { BASE, CC_VERSION, DB_FILE } from "./config";
import { startLogin, pollOnce, refresh, signout, loadTokens, saveTokens, clearTokens } from "./auth";
import { fetchPortfolio, fetchEarnings, fetchRaw } from "./api";
import { openStore } from "./store";
import { ratePerHour, projectSecondsToCap, fmtUsd, fmtDuration } from "./derive";
import { spawn } from "node:child_process";
import type { Tokens, Portfolio } from "./types";

const deps = (token: string) => ({ fetch, token, base: BASE, ccVersion: CC_VERSION });

function openBrowser(url: string) {
  const cmd = process.platform === "darwin" ? "open" : process.platform === "win32" ? "start" : "xdg-open";
  try { spawn(cmd, [url], { stdio: "ignore", detached: true }).unref(); } catch {}
}

async function withToken(): Promise<Tokens> {
  const t = loadTokens();
  if (!t) { console.error("Not signed in. Run: kicker login"); process.exit(1); }
  return t;
}

// GET with auto-refresh on 401 (refresh consumes the CLI's own rotating token).
async function authed<T>(call: (token: string) => Promise<T>): Promise<T> {
  const t = await withToken();
  try { return await call(t.access_token); }
  catch (e: any) {
    if (!String(e?.message).includes("HTTP 401") || !t.refresh_token) throw e;
    const nt = await refresh({ fetch, base: BASE }, t.refresh_token);
    if (!nt) { console.error("Session expired. Run: kicker login"); process.exit(1); }
    saveTokens({ ...t, ...nt });
    return call(nt.access_token);
  }
}

function recordSample(p: Portfolio) {
  const store = openStore(DB_FILE);
  store.insertSample({ ts: Date.now(), lifetimeUsd: p.lifetimeUsd, todayUsd: p.todayUsd,
    adId: p.ads[0]?.adId ?? "", kill: p.kill });
  return store;
}

async function cmdLogin() {
  const { url, state } = await startLogin({ fetch, base: BASE });
  console.log("\n  Sign in with Google:\n\n    " + url + "\n");
  openBrowser(url);
  process.stdout.write("  waiting");
  for (let i = 0; i < 120; i++) {
    await new Promise((r) => setTimeout(r, 1500));
    process.stdout.write(".");
    const t = await pollOnce({ fetch, base: BASE }, state).catch(() => null);
    if (t) { saveTokens(t); console.log("\n\n  ✓ signed in.\n"); return; }
  }
  console.error("\n\n  timed out.\n"); process.exit(1);
}

async function cmdPortfolio() {
  const p = await authed((tk) => fetchPortfolio(deps(tk)));
  const store = recordSample(p);
  const since = store.recentSince(Date.now() - 6 * 3_600_000);
  const rate = ratePerHour(since);
  console.log("\n  Kicker — portfolio");
  console.log("  " + "-".repeat(40));
  console.log(`  Balance   ${fmtUsd(p.lifetimeUsd)} lifetime  ·  ${fmtUsd(p.todayUsd)} today`);
  if (rate > 0) console.log(`  Rate      ${fmtUsd(rate)}/hr (last 6h)`);
  console.log(`  Killswitch ${p.kill ? "ON" : "off"}   View gate ${p.viewThresholdSeconds ?? "?"}s`);
  console.log(`\n  Served ads (${p.ads.length})`);
  p.ads.forEach((a, i) => console.log(`   ${i + 1}. ${a.text}${a.clickUrl ? "  → " + a.clickUrl : ""}`));
  console.log("");
}

async function cmdEarnings() {
  const [p, e] = await Promise.all([
    authed((tk) => fetchPortfolio(deps(tk))),
    authed((tk) => fetchEarnings(deps(tk))),
  ]);
  const rate = ratePerHour(openStore(DB_FILE).recentSince(Date.now() - 6 * 3_600_000));
  console.log("\n  Earnings");
  console.log(`  lifetime ${fmtUsd(p.lifetimeUsd)}  ·  today ${fmtUsd(p.todayUsd)}`);
  if (e.cap) {
    console.log(`  cap      ${e.cap.scope} ${fmtUsd(e.cap.capUsd)} (resets ${fmtDuration(e.cap.resetSeconds)})`);
    const eta = projectSecondsToCap(p.todayUsd, e.cap.capUsd, rate);
    if (eta !== null) console.log(`  to cap   ~${fmtDuration(eta)} at current rate`);
  }
  console.log("");
}

async function cmdRaw() {
  const [portfolio, earnings] = await Promise.all([
    authed((tk) => fetchRaw(deps(tk), `/v1/portfolio?claude_code_version=${encodeURIComponent(CC_VERSION)}`)),
    authed((tk) => fetchRaw(deps(tk), "/v1/earnings")),
  ]);
  console.log(JSON.stringify({ portfolio, earnings }, null, 2));
}

function cmdStatus() {
  const t = loadTokens();
  console.log("\n  kicker status");
  console.log("  backend    " + BASE);
  console.log("  signed in  " + (t ? "yes" : "no"));
  console.log("  history db " + DB_FILE + "\n");
}

async function cmdLogout() {
  const t = loadTokens();
  if (t?.refresh_token) await signout({ fetch, base: BASE }, t.refresh_token).catch(() => {});
  clearTokens();
  console.log("signed out.");
}

const cmd = (process.argv[2] || "portfolio").toLowerCase();
const table: Record<string, () => unknown> = {
  login: cmdLogin, portfolio: cmdPortfolio, earnings: cmdEarnings,
  raw: cmdRaw, status: cmdStatus, logout: cmdLogout,
};
const fn = table[cmd];
if (!fn) { console.error("commands: login | portfolio | earnings | raw | status | logout"); process.exit(2); }
await (async () => fn())().catch((e: any) => { console.error("error:", e?.message ?? e); process.exit(1); });
