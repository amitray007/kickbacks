#!/usr/bin/env bun
import { BASE, CC_VERSION, DB_FILE, CONFIG_DIR, ACTIVITY_DIRS, ACTIVITY_WINDOW_MS, STALL_WINDOW_MS, POLL_SECONDS, LAUNCHD_LABEL, BAR_LAUNCHD_LABEL } from "./config";
import { startLogin, pollOnce, signout, loadTokens, saveTokens, clearTokens, makeAuthedRunner, AuthError } from "./auth";
import { fetchPortfolio, fetchEarnings, fetchRaw } from "./api";
import { openStore, type Store } from "./store";
import { ratePerHour } from "./derive";
import { renderDashboard, renderEarnings, renderStatus, palette, useColor } from "./ui";
import { runWatch } from "./watch";
import { loadModel } from "./tui";
import { runPoll } from "./poll";
import { isActive } from "./activity";
import { notify } from "./notify";
import { installAgent, uninstallAgent, agentInstalled, installBarAgent } from "./launchd";
import { buildMenuModel } from "./model";
import { buildHistory } from "./history";
import { mergeRecentAds, loadRecentAds, saveRecentAds, type RecentAd } from "./ads";
import { spawn } from "node:child_process";
import { dirname } from "node:path";
import { existsSync } from "node:fs";
import type { Portfolio, Earnings } from "./types";

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

function recordSample(store: Store, p: Portfolio, active: boolean | null = null): void {
  store.insertSample({ ts: Date.now(), lifetimeUsd: p.lifetimeUsd, todayUsd: p.todayUsd,
    adId: p.ads[0]?.adId ?? "", kill: p.kill, active });
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

// One poll cycle for the launchd agent (also runnable by hand): sample + stall/cap alerts.
async function cmdPoll() {
  if (!loadTokens()) { console.error("Not signed in. Run: kickback login"); process.exit(1); }
  const store = openStore(DB_FILE);
  const now = Date.now();
  try {
    await runPoll({
      fetchPortfolio: () => runAuthed((tk) => fetchPortfolio(deps(tk))),
      fetchEarnings: () => runAuthed((tk) => fetchEarnings(deps(tk))),
      store,
      isActive: () => isActive(ACTIVITY_DIRS, now, ACTIVITY_WINDOW_MS),
      notify,
      now,
      stallWindowMs: STALL_WINDOW_MS,
    });
  } finally { store.close(); }
}

// Manage the launchd agent that runs `kickback poll` periodically. `install` must be
// run from the standalone binary (not `bun run`) — launchd needs the binary's own path.
async function cmdPoller() {
  const sub = (process.argv[3] || "status").toLowerCase();
  if (sub === "install") {
    if (process.argv[1]?.endsWith(".ts")) { // running via `bun run`, not the standalone binary
      console.error("`poller install` needs the standalone `kickback` binary (build with `bun run build`), not `bun run`.");
      process.exit(1);
    }
    const path = installAgent(LAUNCHD_LABEL, process.execPath, POLL_SECONDS);
    console.log(`Installed launchd agent → ${path}\nPolling every ${POLL_SECONDS}s. Uninstall with: kickback poller uninstall`);
  } else if (sub === "uninstall") {
    uninstallAgent(LAUNCHD_LABEL);
    console.log("Poller uninstalled.");
  } else {
    console.log(`Poller ${agentInstalled(LAUNCHD_LABEL) ? "installed" : "not installed"}  (${LAUNCHD_LABEL})`);
  }
}

// Emit the local earnings history as JSON for the menu-bar app's History window.
// Read-only; works signed-in or out (it only reads the local SQLite history).
function cmdHistory() {
  const store = openStore(DB_FILE);
  try { console.log(JSON.stringify(buildHistory(store, Date.now()))); }
  finally { store.close(); }
}

// Emit the menu model as JSON for the Swift menu-bar app (live fetch → last-known on
// failure). Read-only; records a sample when the fetch succeeds.
async function cmdModel() {
  let signedIn = !!loadTokens();
  const store = openStore(DB_FILE);
  const now = Date.now();
  let p: Portfolio | null = null;
  let e: Earnings | null = null;
  let recentAds: RecentAd[] = [];
  if (signedIn) {
    try {
      p = await runAuthed((tk) => fetchPortfolio(deps(tk)));
      e = await runAuthed((tk) => fetchEarnings(deps(tk))).catch(() => null);
      recordSample(store, p, isActive(ACTIVITY_DIRS, now, ACTIVITY_WINDOW_MS));   // record activity → in-app stall detection
      const current: RecentAd[] = p.ads.map((a) => ({ adId: a.adId, text: a.text, url: a.clickUrl, icon: a.iconUrl }));
      recentAds = mergeRecentAds(loadRecentAds(store), current);
      saveRecentAds(store, recentAds);
    } catch (err) {
      if (err instanceof AuthError) signedIn = false; // refresh failed → re-login → signed-out model
      else { store.close(); process.exit(1); }        // transient network/API → no output; the app keeps its last model
    }
  }
  console.log(JSON.stringify(buildMenuModel({ p, e, store, now, signedIn, recentAds })));
  store.close();
}

// Manage the menu-bar app's login agent (the `kickback-bar` binary installed alongside).
// Run from the installed binary (brew), not `bun run`.
async function cmdBar() {
  const sub = (process.argv[3] || "status").toLowerCase();
  if (sub === "install") {
    if (process.argv[1]?.endsWith(".ts")) { console.error("`bar install` needs the installed binaries (brew), not `bun run`."); process.exit(1); }
    const barBin = `${dirname(process.execPath)}/kickback-bar`;
    if (!existsSync(barBin)) { console.error(`kickback-bar not found at ${barBin} — install via brew.`); process.exit(1); }
    const path = installBarAgent(BAR_LAUNCHD_LABEL, barBin);
    console.log(`Installed menu-bar agent → ${path}\nThe menu bar now starts at login. Uninstall: kickback bar uninstall`);
  } else if (sub === "uninstall") {
    uninstallAgent(BAR_LAUNCHD_LABEL);
    console.log("Menu-bar agent uninstalled.");
  } else {
    console.log(`Menu-bar agent ${agentInstalled(BAR_LAUNCHD_LABEL) ? "installed" : "not installed"}  (${BAR_LAUNCHD_LABEL})`);
  }
}

// Live framed dashboard. Non-TTY (piped) → one static render so it stays scriptable.
// Interval via KICKBACK_WATCH_SECONDS (default 30, min 5).
async function cmdWatch() {
  if (!process.stdout.isTTY) { await cmdPortfolio(); return; }
  if (!loadTokens()) { console.error("Not signed in. Run: kickback login"); process.exit(1); } // don't enter the alt-screen unauthenticated
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
  clearTokens();   // clear locally first → app reads signed-out instantly; server revoke is best-effort
  if (t?.refresh_token) await signout({ fetch, base: BASE }, t.refresh_token).catch(() => {});
  console.log(c.dim(`\n  Signed out${t?.refresh_token ? " — local tokens cleared, server session revoked." : " — local tokens cleared."}\n`));
}

const cmd = (process.argv[2] || "portfolio").toLowerCase();
const table: Record<string, () => unknown> = {
  login: cmdLogin, portfolio: cmdPortfolio, watch: cmdWatch, earnings: cmdEarnings,
  raw: cmdRaw, status: cmdStatus, logout: cmdLogout, poll: cmdPoll, poller: cmdPoller, model: cmdModel, bar: cmdBar, history: cmdHistory,
};
const fn = table[cmd];
if (!fn) { console.error("commands: login | portfolio | watch | earnings | raw | status | logout | poll | poller <…> | model | bar <install|uninstall|status> | history"); process.exit(2); }
try {
  await fn();
} catch (e) {
  console.error("error:", e instanceof Error ? e.message : e);
  process.exit(1);
}
