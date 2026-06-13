import { homedir } from "node:os";
import { join } from "node:path";

export const BASE =
  (process.env.KICKER_BASE || "https://kickbacks-backend-gmdaqm2c7q-uw.a.run.app")
    .replace(/\/+$/, "");
export const CC_VERSION = process.env.KICKER_CC_VERSION || "2.1.177";

export const CONFIG_DIR =
  process.env.KICKER_CONFIG_DIR || join(homedir(), ".config", "kicker");
export const AUTH_FILE = join(CONFIG_DIR, "auth.json");
export const DB_FILE = join(CONFIG_DIR, "history.db");
