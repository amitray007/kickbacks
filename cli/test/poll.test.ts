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

test("runPoll records an active sample and fires stall when active + flat across cycles", async () => {
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
  expect(fired.some((t) => /Kickback/.test(t))).toBe(true);
});

test("runPoll does not fire stall when inactive", async () => {
  const store = openStore(":memory:");
  const now0 = 1_000_000;
  const fired: string[] = [];
  const base = {
    fetchPortfolio: async () => P,
    fetchEarnings: async () => E,
    store,
    isActive: () => false,
    notify: (t: string) => { fired.push(t); },
    stallWindowMs: 300_000,
  };
  await runPoll({ ...base, now: now0 - 240_000 });
  await runPoll({ ...base, now: now0 });
  expect(fired.length).toBe(0);
});
