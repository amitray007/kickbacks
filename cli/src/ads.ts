import type { Store } from "./store";

/** An ad we've been served, kept locally so the menu can show recent ones. */
export interface RecentAd { adId: string; text: string; url: string; icon: string }

/** Prepend the current ads (newest first), dedupe by adId (or text if no id), cap at
 *  `cap`. Result is the most-recently-seen distinct ads, current first. An empty
 *  `current` (a no-serve poll) preserves the existing list. */
export function mergeRecentAds(existing: RecentAd[], current: RecentAd[], cap = 3): RecentAd[] {
  const out: RecentAd[] = [];
  const seen = new Set<string>();
  for (const a of [...current, ...existing]) {
    const key = a.adId || a.text;
    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push(a);
    if (out.length >= cap) break;
  }
  return out;
}

const KEY = "recent_ads";

export function loadRecentAds(store: Store): RecentAd[] {
  const raw = store.getState(KEY);
  if (!raw) return [];
  try {
    const v = JSON.parse(raw);
    if (!Array.isArray(v)) return [];
    return v
      .filter((a) => a && typeof a.text === "string")
      .map((a) => ({ adId: String(a.adId ?? ""), text: String(a.text), url: String(a.url ?? ""), icon: String(a.icon ?? "") }));
  } catch {
    return [];
  }
}

export function saveRecentAds(store: Store, list: RecentAd[]): void {
  store.setState(KEY, JSON.stringify(list));
}
