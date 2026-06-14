// cli/test/history.test.ts
import { test, expect } from "bun:test";
import { localDayKey, dailyBuckets } from "../src/history";
import type { Sample } from "../src/types";

// noon-local on a given Y/M/D (month is 1-based here for readability)
const day = (y: number, m: number, d: number, h = 12): number => new Date(y, m - 1, d, h).getTime();
const s = (ts: number, todayUsd: number, over: Partial<Sample> = {}): Sample =>
  ({ ts, todayUsd, lifetimeUsd: todayUsd, adId: "a", kill: false, ...over });

test("localDayKey is the local Y-M-D", () => {
  expect(localDayKey(day(2026, 6, 9, 1))).toBe("2026-06-09");
  expect(localDayKey(day(2026, 6, 9, 23))).toBe("2026-06-09");
});

test("dailyBuckets: one bucket per local day, usd = max today_usd that day", () => {
  const samples = [
    s(day(2026, 6, 9, 9), 2), s(day(2026, 6, 9, 17), 5),   // day 1 peaks at 5
    s(day(2026, 6, 10, 10), 3),                            // day 2 peaks at 3
  ];
  const b = dailyBuckets(samples);
  expect(b.map((x) => x.date)).toEqual(["2026-06-09", "2026-06-10"]);
  expect(b.map((x) => x.usd)).toEqual([5, 3]);
});

test("dailyBuckets: hitCap when a sample reached its cap that day", () => {
  const samples = [
    s(day(2026, 6, 9, 9), 1, { capUsd: 2 }),
    s(day(2026, 6, 9, 18), 2, { capUsd: 2 }),  // reached cap
  ];
  expect(dailyBuckets(samples)[0]!.hitCap).toBe(true);
});

import { summarize } from "../src/history";

test("summarize: best day, average, and rolling week/month windows", () => {
  const now = day(2026, 6, 30, 12);
  const buckets = [
    { date: "2026-06-01", usd: 4, hitCap: false },   // >7 and <=30 days ago
    { date: "2026-06-28", usd: 10, hitCap: false },  // within 7
    { date: "2026-06-30", usd: 6, hitCap: false },   // today, within 7
  ];
  const sum = summarize(buckets, now);
  expect(sum.daysTracked).toBe(3);
  expect(sum.bestDay).toEqual({ date: "2026-06-28", usd: 10 });
  expect(sum.avgPerDayUsd).toBeCloseTo((4 + 10 + 6) / 3, 5);
  expect(sum.thisWeekUsd).toBe(16);    // 10 + 6
  expect(sum.thisMonthUsd).toBe(20);   // 4 + 10 + 6
});

test("summarize: empty input", () => {
  const sum = summarize([], day(2026, 6, 30));
  expect(sum.daysTracked).toBe(0);
  expect(sum.bestDay).toBeNull();
  expect(sum.avgPerDayUsd).toBe(0);
});

import { lastEarnedAgoSeconds } from "../src/history";

test("lastEarnedAgoSeconds: time since today_usd last increased", () => {
  const now = 1_000_000;
  const samples = [
    s(now - 600_000, 1.0), // -10m
    s(now - 300_000, 1.5), // -5m  earned
    s(now - 60_000, 1.5),  // -1m  flat
  ];
  expect(lastEarnedAgoSeconds(samples, now)).toBe(300); // last increase was 5m ago
});

test("lastEarnedAgoSeconds: null when never increased", () => {
  const now = 1_000_000;
  expect(lastEarnedAgoSeconds([s(now - 60_000, 2), s(now, 2)], now)).toBeNull();
});
