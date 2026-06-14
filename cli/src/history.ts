// cli/src/history.ts
import type { Sample } from "./types";

export interface DayBucket { date: string; usd: number; hitCap: boolean }
export interface BestDay { date: string; usd: number }

/** Local-day key "YYYY-MM-DD" for a unix-ms timestamp. */
export function localDayKey(ts: number): string {
  const d = new Date(ts);
  const mm = `${d.getMonth() + 1}`.padStart(2, "0");
  const dd = `${d.getDate()}`.padStart(2, "0");
  return `${d.getFullYear()}-${mm}-${dd}`;
}

/** Per-local-day earnings. A day's earnings = max today_usd that day (today_usd
 *  resets at local midnight). hitCap = any sample that day at/above its cap.
 *  Sorted by date ascending. */
export function dailyBuckets(samples: Sample[]): DayBucket[] {
  const by = new Map<string, { usd: number; hitCap: boolean }>();
  for (const s of samples) {
    const k = localDayKey(s.ts);
    const cur = by.get(k) ?? { usd: 0, hitCap: false };
    cur.usd = Math.max(cur.usd, s.todayUsd);
    if (s.capUsd != null && s.capUsd > 0 && s.todayUsd >= s.capUsd) cur.hitCap = true;
    by.set(k, cur);
  }
  return [...by.entries()]
    .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .map(([date, v]) => ({ date, usd: v.usd, hitCap: v.hitCap }));
}
