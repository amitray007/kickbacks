// cli/src/history.ts
import type { Sample } from "./types";
import type { Store } from "./store";

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

export interface Summary {
  thisWeekUsd: number; thisMonthUsd: number; bestDay: BestDay | null;
  avgPerDayUsd: number; daysTracked: number;
}

/** Rolling windows: thisWeek = last 7 local days incl. today, thisMonth = last 30. */
export function summarize(daily: DayBucket[], now: number): Summary {
  const daysTracked = daily.length;
  const bestDay = daily.reduce<BestDay | null>(
    (b, d) => (!b || d.usd > b.usd ? { date: d.date, usd: d.usd } : b), null);
  const total = daily.reduce((a, d) => a + d.usd, 0);
  const avgPerDayUsd = daysTracked > 0 ? total / daysTracked : 0;
  const lastNDays = (n: number): Set<string> => {
    const set = new Set<string>();
    for (let i = 0; i < n; i++) set.add(localDayKey(now - i * 86_400_000));
    return set;
  };
  const week = lastNDays(7), month = lastNDays(30);
  const sumIn = (set: Set<string>) => daily.filter((d) => set.has(d.date)).reduce((a, d) => a + d.usd, 0);
  return { thisWeekUsd: sumIn(week), thisMonthUsd: sumIn(month), bestDay, avgPerDayUsd, daysTracked };
}

/** Seconds since today_usd last increased (an earning event), or null if never. */
export function lastEarnedAgoSeconds(samples: Sample[], now: number): number | null {
  const sorted = [...samples].sort((a, b) => a.ts - b.ts);
  let lastTs: number | null = null;
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i]!.todayUsd > sorted[i - 1]!.todayUsd) lastTs = sorted[i]!.ts;
  }
  return lastTs == null ? null : Math.max(0, Math.round((now - lastTs) / 1000));
}

export interface HistoryJson extends Summary {
  lifetimeUsd: number;
  sinceInstallUsd: number;
  firstSampleTs: number | null;
  daily: DayBucket[];
  capHitsLast7: number;
  campaignsSeen: number;
  activeHours: number;
}

export function buildHistory(store: Store, now: number): HistoryJson {
  const samples = [...store.recentSince(0)].sort((a, b) => a.ts - b.ts);
  const daily = dailyBuckets(samples);
  const sum = summarize(daily, now);
  const first = samples[0] ?? null;
  const last = samples[samples.length - 1] ?? null;
  const lifetimeUsd = last?.lifetimeUsd ?? 0;
  const sinceInstallUsd = first && last ? Math.max(0, last.lifetimeUsd - first.lifetimeUsd) : 0;

  const week = new Set<string>();
  for (let i = 0; i < 7; i++) week.add(localDayKey(now - i * 86_400_000));
  const capHitsLast7 = daily.filter((d) => d.hitCap && week.has(d.date)).length;
  const campaignsSeen = new Set(samples.map((s) => s.adId).filter((a) => a !== "")).size;

  // active hours: sum gaps that follow an active sample, ignoring gaps > 30m (app/poller was off)
  let activeMs = 0;
  for (let i = 1; i < samples.length; i++) {
    if (samples[i - 1]!.active === true) {
      const gap = samples[i]!.ts - samples[i - 1]!.ts;
      if (gap > 0 && gap < 30 * 60_000) activeMs += gap;
    }
  }
  const activeHours = Math.round((activeMs / 3_600_000) * 10) / 10;

  return { ...sum, lifetimeUsd, sinceInstallUsd, firstSampleTs: first?.ts ?? null, daily, capHitsLast7, campaignsSeen, activeHours };
}
