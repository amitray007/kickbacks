// cli/test/tui.test.ts
import { test, expect } from "bun:test";
import { loadModel } from "../src/tui";
import { openStore } from "../src/store";
import type { Portfolio, Earnings } from "../src/types";

const P: Portfolio = {
  lifetimeUsd: 12.34, todayUsd: 0.56, viewThresholdSeconds: 15, kill: false,
  ads: [{ adId: "552e20ec", campaignId: "23f8444b", text: "Inflowpay", clickUrl: "https://x.test", bannerEnabled: true }],
};
const E: Earnings = { cap: { scope: "daily", capUsd: 1, resetSeconds: 15120 } };

test("loadModel fetches, records a sample, and derives state", async () => {
  const store = openStore(":memory:");
  const m = await loadModel({
    fetchPortfolio: async () => P,
    fetchEarnings: async () => E,
    store, now: 1_000_000,
  });
  expect(m.p.todayUsd).toBe(0.56);
  expect(m.e?.cap?.scope).toBe("daily");
  expect(m.state).toBe("earning");
  expect(store.latest()?.todayUsd).toBe(0.56); // sample recorded
  expect(m.samples.length).toBe(1);
});

test("loadModel tolerates an earnings failure (cap is optional)", async () => {
  const store = openStore(":memory:");
  const m = await loadModel({
    fetchPortfolio: async () => P,
    fetchEarnings: async () => { throw new Error("boom"); },
    store, now: 1_000_000,
  });
  expect(m.e).toBeNull();
  expect(m.p.todayUsd).toBe(0.56);
});
