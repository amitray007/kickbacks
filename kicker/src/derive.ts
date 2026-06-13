import type { Sample } from "./types";

/** Average $/hr of today_usd growth across the provided samples (sorted or not).
 *  Returns 0 with <2 samples, no positive gain, or a zero time span. A midday
 *  reset (today_usd drops) yields 0 for that window — acceptable for a rate hint. */
export function ratePerHour(samples: Sample[]): number {
  if (samples.length < 2) return 0;
  const sorted = [...samples].sort((a, b) => a.ts - b.ts);
  const first = sorted[0]!, last = sorted[sorted.length - 1]!;
  const hours = (last.ts - first.ts) / 3_600_000;
  if (hours <= 0) return 0;
  const gain = last.todayUsd - first.todayUsd;
  return gain > 0 ? gain / hours : 0;
}

/** Seconds until today_usd reaches capUsd at ratePerHour. null when rate is 0
 *  (unknown), 0 when already at/over the cap. */
export function projectSecondsToCap(todayUsd: number, capUsd: number, rate: number): number | null {
  if (rate <= 0) return null;
  const remaining = capUsd - todayUsd;
  if (remaining <= 0) return 0;
  return (remaining / rate) * 3600;
}

export interface StallInput {
  samples: Sample[];
  now: number;
  windowMs: number;
  active: boolean;
}

/** True when the user is actively coding but today_usd hasn't moved across the
 *  recent window — the silent-injection-broke signal. */
export function isStalled({ samples, now, windowMs, active }: StallInput): boolean {
  if (!active) return false;
  const recent = samples.filter((s) => s.ts >= now - windowMs && s.ts <= now);
  if (recent.length < 2) return false;
  const min = Math.min(...recent.map((s) => s.todayUsd));
  const max = Math.max(...recent.map((s) => s.todayUsd));
  return max - min === 0;
}

export const fmtUsd = (n: number): string => `$${(Number.isFinite(n) ? n : 0).toFixed(2)}`;

export function fmtDuration(sec: number): string {
  sec = Math.max(0, Math.floor(sec));
  if (sec >= 3600) return `${Math.floor(sec / 3600)}h${Math.floor((sec % 3600) / 60)}m`;
  if (sec >= 60) return `${Math.floor(sec / 60)}m`;
  return `${sec}s`;
}
