#!/usr/bin/env bun
import { BASE, CC_VERSION, DB_FILE, CONFIG_DIR } from "./config";
import { startLogin, pollOnce, signout, loadTokens, saveTokens, clearTokens, makeAuthedRunner, AuthError } from "./auth";
import { fetchPortfolio, fetchEarnings, fetchRaw } from "./api";
import { openStore, type Store } from "./store";
import { ratePerHour } from "./derive";
import { renderDashboard, renderEarnings, renderStatus, palette, useColor } from "./ui";
import { runWatch } from "./watch";
import { loadModel } from "./tui";
import { spawn } from "node:child_process";
import type { Portfolio } from "./types";

const deps = (token: string) => ({ fetch, token, base: BASE, ccVersion: CC_VERSION });
const runAuthed = makeAuthedRunner({ fetch, base: BASE });

function openBrowser(url: string): boolean {
  const cmd = process.platform === "darwin" ? "open" : process.platform === "win32" ? "start" : "xdg-open";
  try { spawn(cmd, [url], { stdio: "ignore", detached: true }).unref(); return true; } catch { return false; }
}

// Authed GET with auto-refresh on 401; exits with a friendly message if signed out.
// Call these sequentially, not in parallel: two concurrent 401s would each try to
// spend the same single-use refresh token and the second would spuriously fail.
async function authed<T>(call: (token: string) => Promise<T>): Promise<T> {
  try { return await runAuthed(call); }
  catch (e) {
    if (e instanceof AuthError) { console.error(e.message); process.exit(1); }
    throw e;
  }
}

function recordSample(store: Store, p: Portfolio): void {
  store.insertSample({ ts: Date.now(), lifetimeUsd: p.lifetimeUsd, todayUsd: p.todayUsd,
    adId: p.ads[0]?.adId ?? "", kill: p.kill });
}

function rateLast6h(): number {
  const store = openStore(DB_FILE);
  try { return ratePerHour(store.recentSince(Date.now() - 6 * 3_600_000)); }
  finally { store.close(); }
}

async function cmdLogin() {
  const c = palette(useColor());
  const { url, state } = await startLogin({ fetch, base: BASE });
  console.log(`\n  ${c.bold("Sign in to Kickbacks with Google")}\n`);
  console.log(`    ${c.cyan(url)}\n`);
  const opened = openBrowser(url);
  console.log(c.dim(opened
    ? "  Opening your browser… (paste the link above if it doesn't appear)"
    : "  Open the link above in your browser to continue."));
  process.stdout.write(c.dim("\n  Waiting for sign-in"));
  for (let i = 0; i < 120; i++) {
    await new Promise((r) => setTimeout(r, 1500));
    process.stdout.write(c.dim("."));
    const t = await pollOnce({ fetch, base: BASE }, state).catch(() => null);
    if (t) { saveTokens(t); console.log(c.green("\n\n  ✓ Signed in.") + c.dim("  Run 'kickback' to see your earnings.\n")); return; }
  }
  console.error(c.yellow("\n\n  Timed out. Run 'kickback login' to try again.\n")); process.exit(1);
}

async function cmdPortfolio() {
  const p = await authed((tk) => fetchPortfolio(deps(tk)));
  const e = await authed((tk) => fetchEarnings(deps(tk))).catch(() => null); // cap is optional in the dashboard
  const store = openStore(DB_FILE);
  let rate = 0;
  try {
    recordSample(store, p);
    rate = ratePerHour(store.recentSince(Date.now() - 6 * 3_600_000));
  } finally {
    store.close();
  }
  console.log(renderDashboard(p, e, rate, useColor()));
}

async function cmdEarnings() {
  const p = await authed((tk) => fetchPortfolio(deps(tk)));
  const e = await authed((tk) => fetchEarnings(deps(tk)));
  console.log(renderEarnings(p, e, rateLast6h(), useColor()));
}

// Live framed dashboard. Non-TTY (piped) → one static render so it stays scriptable.
// Interval via KICKBACK_WATCH_SECONDS (default 30, min 5).
async function cmdWatch() {
  if (!process.stdout.isTTY) { await cmdPortfolio(); return; }
  const seconds = Math.max(5, Number(process.env.KICKBACK_WATCH_SECONDS) || 30);
  const store = openStore(DB_FILE);
  try {
    await runWatch({
      now: () => Date.now(),
      intervalMs: seconds * 1000,
      load: (now) => loadModel({
        fetchPortfolio: () => runAuthed((tk) => fetchPortfolio(deps(tk))),
        fetchEarnings: () => runAuthed((tk) => fetchEarnings(deps(tk))),
        store, now,
      }),
    });
  } finally {
    store.close();
  }
}

async function cmdRaw() {
  const portfolio = await authed((tk) => fetchRaw(deps(tk), `/v1/portfolio?claude_code_version=${encodeURIComponent(CC_VERSION)}`));
  const earnings = await authed((tk) => fetchRaw(deps(tk), "/v1/earnings"));
  console.log(JSON.stringify({ portfolio, earnings }, null, 2));
}

function cmdStatus() {
  const t = loadTokens();
  console.log(renderStatus({ signedIn: !!t, base: BASE, configDir: CONFIG_DIR, dbFile: DB_FILE, color: useColor() }));
}

async function cmdLogout() {
  const c = palette(useColor());
  const t = loadTokens();
  if (t?.refresh_token) await signout({ fetch, base: BASE }, t.refresh_token).catch(() => {});
  clearTokens();
  console.log(c.dim(`\n  Signed out${t?.refresh_token ? " — server session revoked, local tokens cleared." : " — local tokens cleared."}\n`));
}

const cmd = (process.argv[2] || "portfolio").toLowerCase();
const table: Record<string, () => unknown> = {
  login: cmdLogin, portfolio: cmdPortfolio, watch: cmdWatch, earnings: cmdEarnings,
  raw: cmdRaw, status: cmdStatus, logout: cmdLogout,
};
const fn = table[cmd];
if (!fn) { console.error("commands: login | portfolio | watch | earnings | raw | status | logout"); process.exit(2); }
try {
  await fn();
} catch (e) {
  console.error("error:", e instanceof Error ? e.message : e);
  process.exit(1);
}
