import { test, expect } from "bun:test";
import { mergeRecentAds, loadRecentAds, saveRecentAds, type RecentAd } from "../src/ads";
import { openStore } from "../src/store";

const ad = (id: string, text = id): RecentAd => ({ adId: id, text, url: "", icon: "" });

test("mergeRecentAds: current first, then existing", () => {
  expect(mergeRecentAds([ad("b"), ad("c")], [ad("a")]).map((a) => a.adId)).toEqual(["a", "b", "c"]);
});

test("mergeRecentAds: a repeat moves to front (no duplicate)", () => {
  expect(mergeRecentAds([ad("a"), ad("b")], [ad("b")]).map((a) => a.adId)).toEqual(["b", "a"]);
});

test("mergeRecentAds: caps the length", () => {
  expect(mergeRecentAds([ad("b"), ad("c"), ad("d")], [ad("a")], 3).map((a) => a.adId)).toEqual(["a", "b", "c"]);
});

test("mergeRecentAds: empty current preserves existing", () => {
  expect(mergeRecentAds([ad("a"), ad("b")], []).map((a) => a.adId)).toEqual(["a", "b"]);
});

test("loadRecentAds/saveRecentAds round-trip; bad json → []", () => {
  const store = openStore(":memory:");
  expect(loadRecentAds(store)).toEqual([]);
  saveRecentAds(store, [ad("a", "Acme")]);
  expect(loadRecentAds(store)[0]!.text).toBe("Acme");
  store.setState("recent_ads", "not json");
  expect(loadRecentAds(store)).toEqual([]);
});
