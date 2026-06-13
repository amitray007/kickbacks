// kicker/test/derive.test.ts
import { test, expect } from "bun:test";
import { ratePerHour, projectSecondsToCap, isStalled, fmtUsd, fmtDuration, earningState } from "../src/derive";
import type { Sample, Portfolio, Earnings } from "../src/types";

const s = (ts: number, todayUsd: number): Sample =>
  ({ ts, todayUsd, lifetimeUsd: todayUsd, adId: "a", kill: false });

const pf = (over: Partial<Portfolio> = {}): Portfolio => ({
  lifetimeUsd: 1, todayUsd: 0.5, viewThresholdSeconds: 15, kill: false,
  ads: [{ adId: "a", campaignId: "c", text: "x", clickUrl: "", bannerEnabled: false }],
  ...over,
});

test("ratePerHour computes $/hr over the window", () => {
  const samples = [s(0, 0), s(3_600_000, 0.5)]; // +$0.50 over 1h
  expect(ratePerHour(samples)).toBeCloseTo(0.5, 5);
});

test("ratePerHour is 0 with <2 samples or no gain", () => {
  expect(ratePerHour([s(0, 1)])).toBe(0);
  expect(ratePerHour([s(0, 1), s(3_600_000, 1)])).toBe(0);
});

test("projectSecondsToCap returns remaining/rate", () => {
  expect(projectSecondsToCap(0.5, 1.0, 0.5)).toBeCloseTo(3600, 5); // $0.50 left at $0.50/h
  expect(projectSecondsToCap(1.0, 1.0, 0.5)).toBe(0);              // already at cap
  expect(projectSecondsToCap(0.5, 1.0, 0)).toBeNull();            // no rate → unknown
});

test("isStalled true when active and today flat across window", () => {
  const now = 1_000_000;
  // both samples inside the 5-min window so "flat across window" is actually exercised
  const samples = [s(now - 240_000, 0.4), s(now - 60_000, 0.4)];
  expect(isStalled({ samples, now, windowMs: 300_000, active: true })).toBe(true);
});

test("isStalled false when inactive or earnings moved", () => {
  const now = 1_000_000;
  const flat = [s(now - 240_000, 0.4), s(now - 60_000, 0.4)];
  expect(isStalled({ samples: flat, now, windowMs: 300_000, active: false })).toBe(false);
  const moved = [s(now - 240_000, 0.4), s(now - 60_000, 0.5)];
  expect(isStalled({ samples: moved, now, windowMs: 300_000, active: true })).toBe(false);
});

test("formatters", () => {
  expect(fmtUsd(1.5)).toBe("$1.50");
  expect(fmtDuration(3661)).toBe("1h1m");
  expect(fmtDuration(45)).toBe("45s");
});

test("earningState reflects kill / cap / no-serve / earning", () => {
  const cap: Earnings = { cap: { scope: "daily", capUsd: 0.5, resetSeconds: 100 } };
  expect(earningState(pf(), null)).toBe("earning");
  expect(earningState(pf({ kill: true }), null)).toBe("killed");
  expect(earningState(pf({ ads: [] }), null)).toBe("no-serve");
  expect(earningState(pf({ todayUsd: 0.5 }), cap)).toBe("cap");     // at cap
  expect(earningState(pf({ todayUsd: 0.2 }), cap)).toBe("earning"); // under cap
});
