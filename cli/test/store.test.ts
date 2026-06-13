// kickback/test/store.test.ts
import { test, expect } from "bun:test";
import { openStore } from "../src/store";

test("insert + latest + recentSince round-trip", () => {
  const store = openStore(":memory:");
  store.insertSample({ ts: 1000, lifetimeUsd: 1, todayUsd: 0.1, adId: "a", kill: false });
  store.insertSample({ ts: 2000, lifetimeUsd: 1.2, todayUsd: 0.2, adId: "b", kill: false });
  expect(store.latest()?.todayUsd).toBe(0.2);
  expect(store.recentSince(1500).length).toBe(1);
  expect(store.recentSince(0).length).toBe(2);
});

test("latest returns null on empty store", () => {
  expect(openStore(":memory:").latest()).toBeNull();
});

test("openStore migrates to schema v2 (cap_*/active) and round-trips them", () => {
  const store = openStore(":memory:");
  expect(store.userVersion()).toBe(2);
  store.insertSample({ ts: 1, lifetimeUsd: 1, todayUsd: 0.5, adId: "a", kill: false,
    active: true, capScope: "daily", capUsd: 1, capResetS: 3600 });
  const r = store.latest()!;
  expect(r.active).toBe(true);
  expect(r.capScope).toBe("daily");
  expect(r.capResetS).toBe(3600);
});

test("samples without poller fields store null (Plan 1/2 compatibility)", () => {
  const store = openStore(":memory:");
  store.insertSample({ ts: 1, lifetimeUsd: 1, todayUsd: 0.1, adId: "a", kill: false });
  expect(store.latest()!.active).toBeNull();
  expect(store.latest()!.capScope).toBeNull();
});

test("kv state round-trips", () => {
  const store = openStore(":memory:");
  expect(store.getState("k")).toBeNull();
  store.setState("k", "v");
  expect(store.getState("k")).toBe("v");
});
