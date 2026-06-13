// cli/test/alerts.test.ts
import { test, expect } from "bun:test";
import { decideAlerts } from "../src/alerts";
import type { Sample, Earnings } from "../src/types";

const s = (ts: number, todayUsd: number, active: boolean): Sample =>
  ({ ts, todayUsd, lifetimeUsd: todayUsd, adId: "a", kill: false, active });

test("stall fires once: active + flat across window, then suppressed while still stalled", () => {
  const now = 1_000_000;
  const flat = [s(now - 240_000, 0.4, true), s(now - 60_000, 0.4, true)];
  const noCap: Earnings = { cap: null };
  const a1 = decideAlerts({ samples: flat, earnings: noCap, now, stallWindowMs: 300_000, state: {} });
  expect(a1.stall).toBe(true);
  expect(a1.state.stallActive).toBe("1");
  const a2 = decideAlerts({ samples: flat, earnings: noCap, now, stallWindowMs: 300_000, state: { stallActive: "1" } });
  expect(a2.stall).toBe(false); // already firing → no repeat
});

test("no stall when inactive even if flat", () => {
  const now = 1_000_000;
  const flatIdle = [s(now - 240_000, 0.4, false), s(now - 60_000, 0.4, false)];
  const a = decideAlerts({ samples: flatIdle, earnings: { cap: null }, now, stallWindowMs: 300_000, state: {} });
  expect(a.stall).toBe(false);
});

test("cap fires once per period (keyed by scope + reset bucket)", () => {
  const now = 1_000_000;
  const samples = [s(now - 60_000, 1.0, true)];
  const e: Earnings = { cap: { scope: "daily", capUsd: 1.0, resetSeconds: 3600 } };
  const a1 = decideAlerts({ samples, earnings: e, now, stallWindowMs: 300_000, state: {} });
  expect(a1.cap?.scope).toBe("daily");
  const a2 = decideAlerts({ samples, earnings: e, now, stallWindowMs: 300_000, state: { capFired: a1.cap!.key } });
  expect(a2.cap).toBeUndefined(); // same period → no repeat
});

test("no cap alert below the cap", () => {
  const now = 1_000_000;
  const samples = [s(now - 60_000, 0.5, true)];
  const e: Earnings = { cap: { scope: "daily", capUsd: 1.0, resetSeconds: 3600 } };
  expect(decideAlerts({ samples, earnings: e, now, stallWindowMs: 300_000, state: {} }).cap).toBeUndefined();
});

test("stall re-arms after earning resumes", () => {
  const now = 1_000_000;
  const moved = [s(now - 240_000, 0.4, true), s(now - 60_000, 0.6, true)]; // earnings moved → not stalled
  const a = decideAlerts({ samples: moved, earnings: { cap: null }, now, stallWindowMs: 300_000, state: { stallActive: "1" } });
  expect(a.stall).toBe(false);
  expect(a.state.stallActive).toBe(""); // cleared → a later flat episode can fire again
});
