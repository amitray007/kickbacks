import { homedir } from "node:os";
import { join } from "node:path";

export const BASE =
  (process.env.KICKBACKS_BASE || "https://kickbacks-backend-gmdaqm2c7q-uw.a.run.app")
    .replace(/\/+$/, "");
export const CC_VERSION = process.env.KICKBACKS_CC_VERSION || "2.1.177";

export const CONFIG_DIR =
  process.env.KICKBACKS_CONFIG_DIR || join(homedir(), ".config", "kickbacks");
export const AUTH_FILE = join(CONFIG_DIR, "auth.json");
export const DB_FILE = join(CONFIG_DIR, "history.db");

// The Kickbacks VS Code extension caches the ad it's serving right now here. We read it
// (read-only) to show the *actual* live ad + its real icon, falling back to the API ad
// when it's absent/stale. Overridable for tests / non-default installs.
export const LIVE_AD_FILE =
  process.env.KICKBACKS_LIVE_AD_FILE || join(homedir(), ".vibe-ads", "cli-ad.json");
export const LIVE_AD_FRESH_MS = Math.max(0, Number(process.env.KICKBACKS_LIVE_AD_FRESH_MS) || 30 * 60_000);

// --- Plan 3 poller / watchdog ---
export const POLL_SECONDS = Math.max(30, Number(process.env.KICKBACKS_POLL_SECONDS) || 180);
export const ACTIVITY_DIRS = (process.env.KICKBACKS_ACTIVITY_DIRS || join(homedir(), ".claude", "projects"))
  .split(":").filter(Boolean);
export const ACTIVITY_WINDOW_MS = 5 * 60_000;  // "active" = a transcript touched in the last 5 min
export const STALL_WINDOW_MS = 10 * 60_000;    // flat earnings over 10 min while active = stall
export const LAUNCHD_LABEL = "ai.kickbacks.poller";
export const BAR_LAUNCHD_LABEL = "ai.kickbacks.bar";
