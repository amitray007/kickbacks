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
