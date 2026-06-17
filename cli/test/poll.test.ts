// cli/test/poll.test.ts
import { test, expect } from "bun:test";
import { runPoll } from "../src/poll";
import { openStore } from "../src/store";
import type { Portfolio, Earnings } from "../src/types";

const P: Portfolio = {
  lifetimeUsd: 1, todayUsd: 0.4, viewThresholdSeconds: 15, kill: false,
  ads: [{ adId: "a", campaignId: "c", text: "x", clickUrl: "", bannerEnabled: false, iconUrl: "" }],
};
const E: Earnings = { cap: null };

test("runPoll records an active sample (stall alerting removed)", async () => {
  const store = openStore(":memory:");
  const now0 = 1_000_000;
  const fired: string[] = [];
  const base = {
    fetchPortfolio: async () => P,
    fetchEarnings: async () => E,
    store,
    isActive: () => true,
    notify: (t: string) => { fired.push(t); },
    stallWindowMs: 300_000,
  };
  await runPoll({ ...base, now: now0 - 240_000 }); // first flat sample (only 1 → not stalled yet)
  await runPoll({ ...base, now: now0 });           // second flat sample → stall
  expect(store.latest()!.active).toBe(true);
  expect(fired.length).toBe(0);   // stall alerting removed; no cap in this scenario
});

test("runPoll skips API fetch entirely when inactive (no samples written)", async () => {
  const store = openStore(":memory:");
  let fetchCalls = 0;
  await runPoll({
    fetchPortfolio: async () => { fetchCalls++; return P; },
    fetchEarnings: async () => E,
    store,
    isActive: () => false,
    notify: () => {},
    now: 1_000_000,
    stallWindowMs: 300_000,
  });
  expect(fetchCalls).toBe(0);          // no network call when idle
  expect(store.latest()).toBeNull();    // no sample written
});
