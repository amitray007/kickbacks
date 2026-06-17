import { readFileSync } from "node:fs";

/** The ad the extension is actually serving right now, cached locally by the
 *  Kickbacks VS Code extension. Read-only, best-effort: any failure → null, and the
 *  caller falls back to the API's portfolio ad. We read the stable JSON cache only —
 *  never the debug log, whose shape is not a contract. */
export interface LiveAd { text: string; url: string; icon: string; ts: number }

/** Read the extension's local ad cache and return the fresh ad, or null on any
 *  failure (file absent, unreadable, malformed, stale) — the signal to fall back to
 *  the API ad. Never throws. */
export function loadLiveAd(file: string, now: number, freshMs: number): LiveAd | null {
  try { return parseLiveAd(readFileSync(file, "utf8"), now, freshMs); }
  catch { return null; }
}

/** Parse the extension's `cli-ad.json` payload. Returns the ad only when it is
 *  well-formed and fresh (served within `freshMs`); otherwise null so the caller
 *  uses the API ad instead. A future `ts` (clock skew) counts as fresh. */
export function parseLiveAd(raw: string, now: number, freshMs: number): LiveAd | null {
  let o: any;
  try { o = JSON.parse(raw); } catch { return null; }
  if (!o || typeof o.adText !== "string" || o.adText.length === 0) return null;
  if (typeof o.ts !== "number" || !Number.isFinite(o.ts)) return null;
  if (now - o.ts > freshMs) return null;
  return {
    text: o.adText,
    url: typeof o.clickUrl === "string" ? o.clickUrl : "",
    icon: typeof o.iconUrl === "string" ? o.iconUrl : "",
    ts: o.ts,
  };
}
