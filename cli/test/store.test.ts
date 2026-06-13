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

test("openStore stamps schema version 1 (migration hook for Plan 3)", () => {
  expect(openStore(":memory:").userVersion()).toBe(1);
});
