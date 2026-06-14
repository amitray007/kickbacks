// cli/test/model.test.ts
import { test, expect } from "bun:test";
import { buildMenuModel } from "../src/model";
import { openStore } from "../src/store";
import type { Portfolio, Earnings } from "../src/types";

const P: Portfolio = {
  lifetimeUsd: 12.34, todayUsd: 0.56, viewThresholdSeconds: 15, kill: false,
  ads: [{ adId: "552e20ec", campaignId: "23f8444b", text: "Inflowpay", clickUrl: "https://x.test", bannerEnabled: true, iconUrl: "https://x.test/icon.png" }],
};
const E: Earnings = { cap: { scope: "daily", capUsd: 1, resetSeconds: 15120 } };

test("buildMenuModel produces display-ready fields", () => {
  const store = openStore(":memory:");
  store.insertSample({ ts: 1, lifetimeUsd: 12.0, todayUsd: 0.5, adId: "x", kill: false });
  const m = buildMenuModel({ p: P, e: E, store, now: 3_600_001, signedIn: true });
  expect(m.signedIn).toBe(true);
  expect(m.today).toBe("$0.56");
  expect(m.lifetime).toBe("$12.34");
  expect(m.title).toContain("$0.56");
  expect(m.cap).toBe("$0.56 / $1.00");
  expect(m.capPct).toBe(56);
  expect(m.resets).toBe("4h12m");
  expect(m.ad).toBe("Inflowpay");
  expect(m.adUrl).toBe("https://x.test");
  expect(["earning", "cap", "killed", "no-serve", "stalled"]).toContain(m.state);
});

test("buildMenuModel signed-out shows the brand title", () => {
  const store = openStore(":memory:");
  const m = buildMenuModel({ p: null, e: null, store, now: 1, signedIn: false });
  expect(m.signedIn).toBe(false);
  expect(m.state).toBe("signed-out");
  expect(m.title).toBe("kickback");
});

test("buildMenuModel treats signed-in-but-no-portfolio as signed-out (transient handled upstream)", () => {
  const store = openStore(":memory:");
  expect(buildMenuModel({ p: null, e: null, store, now: 1, signedIn: true }).state).toBe("signed-out");
});

test("buildMenuModel reflects killed / no-serve states", () => {
  const store = openStore(":memory:");
  expect(buildMenuModel({ p: { ...P, kill: true }, e: null, store, now: 1, signedIn: true }).state).toBe("killed");
  expect(buildMenuModel({ p: { ...P, ads: [] }, e: null, store, now: 1, signedIn: true }).state).toBe("no-serve");
});

test("buildMenuModel adds menuValue, ads, threshold, collecting", () => {
  const store = openStore(":memory:");
  // one sample only → collecting (need >=2 for a trend)
  store.insertSample({ ts: 1, lifetimeUsd: 12.0, todayUsd: 0.5, adId: "x", kill: false });
  const m = buildMenuModel({ p: P, e: E, store, now: 3_600_001, signedIn: true });
  expect(m.menuValue).toBe("0.56");                 // today without the "$"
  expect(m.viewThresholdSeconds).toBe(15);
  expect(m.ads).toEqual([{ text: "Inflowpay", url: "https://x.test", icon: "https://x.test/icon.png" }]);
  expect(m.collecting).toBe(true);                  // <2 samples
});

test("buildMenuModel signed-out menuValue is the dash", () => {
  const store = openStore(":memory:");
  const m = buildMenuModel({ p: null, e: null, store, now: 1, signedIn: false });
  expect(m.menuValue).toBe("—");
  expect(m.ads).toEqual([]);
  expect(m.collecting).toBe(false);
  expect(m.recentAds).toEqual([]);
});

test("buildMenuModel surfaces recentAds from input (text/url/icon only)", () => {
  const store = openStore(":memory:");
  const m = buildMenuModel({
    p: P, e: E, store, now: 1, signedIn: true,
    recentAds: [{ adId: "a", text: "Acme", url: "u", icon: "i" }],
  });
  expect(m.recentAds).toEqual([{ text: "Acme", url: "u", icon: "i" }]);
});
