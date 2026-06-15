import { homedir } from "node:os";
import { join } from "node:path";
import { existsSync, renameSync } from "node:fs";

export const BASE =
  (process.env.KICKBACKS_BASE || "https://kickbacks-backend-gmdaqm2c7q-uw.a.run.app")
    .replace(/\/+$/, "");
export const CC_VERSION = process.env.KICKBACKS_CC_VERSION || "2.1.177";

export const CONFIG_DIR =
  process.env.KICKBACKS_CONFIG_DIR || join(homedir(), ".config", "kickbacks");
export const AUTH_FILE = join(CONFIG_DIR, "auth.json");
export const DB_FILE = join(CONFIG_DIR, "history.db");

// --- Plan 3 poller / watchdog ---
export const POLL_SECONDS = Math.max(30, Number(process.env.KICKBACKS_POLL_SECONDS) || 180);
export const ACTIVITY_DIRS = (process.env.KICKBACKS_ACTIVITY_DIRS || join(homedir(), ".claude", "projects"))
  .split(":").filter(Boolean);
export const ACTIVITY_WINDOW_MS = 5 * 60_000;  // "active" = a transcript touched in the last 5 min
export const STALL_WINDOW_MS = 10 * 60_000;    // flat earnings over 10 min while active = stall
export const LAUNCHD_LABEL = "ai.kickbacks.poller";
export const BAR_LAUNCHD_LABEL = "ai.kickbacks.bar";

/** One-time migration: the tool was renamed kickback → kickbacks. Move the legacy data dir
 *  (~/.config/kickback → ~/.config/kickbacks) so existing users keep their tokens + accrued
 *  history. Called once at CLI startup — never at import, so `bun test` can't move real data. */
export function migrateLegacyConfigDir(): void {
  if (process.env.KICKBACKS_CONFIG_DIR) return;
  const legacy = join(homedir(), ".config", "kickback");
  if (existsSync(legacy) && !existsSync(CONFIG_DIR)) {
    try { renameSync(legacy, CONFIG_DIR); } catch { /* a fresh dir is created on first write */ }
  }
}
