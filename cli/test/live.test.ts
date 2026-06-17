import { test, expect } from "bun:test";
import { parseLiveAd, loadLiveAd } from "../src/live";
import { writeFileSync, mkdtempSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

const NOW = 1_000_000_000_000;
const FRESH = 30 * 60_000; // 30 min

const json = (o: unknown) => JSON.stringify(o);

test("returns the live ad when present and fresh", () => {
  const raw = json({ adText: "UptimeRobot — the #1 uptime monitor", clickUrl: "https://uptimerobot.com/", iconUrl: "data:image/png;base64,AAAA", ts: NOW - 5_000 });
  expect(parseLiveAd(raw, NOW, FRESH)).toEqual({
    text: "UptimeRobot — the #1 uptime monitor",
    url: "https://uptimerobot.com/",
    icon: "data:image/png;base64,AAAA",
    ts: NOW - 5_000,
  });
});

test("returns null when the ad is stale (older than freshMs)", () => {
  const raw = json({ adText: "Old ad", clickUrl: "https://x.com/", iconUrl: "", ts: NOW - FRESH - 1 });
  expect(parseLiveAd(raw, NOW, FRESH)).toBeNull();
});

test("treats a future ts (clock skew) as fresh", () => {
  const raw = json({ adText: "Skewed", clickUrl: "https://x.com/", iconUrl: "", ts: NOW + 10_000 });
  expect(parseLiveAd(raw, NOW, FRESH)?.text).toBe("Skewed");
});

test("returns null when adText is empty or missing", () => {
  expect(parseLiveAd(json({ adText: "", clickUrl: "https://x.com/", ts: NOW }), NOW, FRESH)).toBeNull();
  expect(parseLiveAd(json({ clickUrl: "https://x.com/", ts: NOW }), NOW, FRESH)).toBeNull();
});

test("returns null on malformed JSON", () => {
  expect(parseLiveAd("{not json", NOW, FRESH)).toBeNull();
  expect(parseLiveAd("", NOW, FRESH)).toBeNull();
});

test("returns null when ts is missing or not a number (can't judge freshness)", () => {
  expect(parseLiveAd(json({ adText: "No ts", clickUrl: "https://x.com/" }), NOW, FRESH)).toBeNull();
  expect(parseLiveAd(json({ adText: "Bad ts", clickUrl: "https://x.com/", ts: "soon" }), NOW, FRESH)).toBeNull();
});

test("defaults url and icon to empty strings when absent", () => {
  const raw = json({ adText: "Bare ad", ts: NOW });
  expect(parseLiveAd(raw, NOW, FRESH)).toEqual({ text: "Bare ad", url: "", icon: "", ts: NOW });
});

test("loadLiveAd reads and parses a fresh cache file", () => {
  const dir = mkdtempSync(join(tmpdir(), "kb-live-"));
  const file = join(dir, "cli-ad.json");
  writeFileSync(file, json({ adText: "From disk", clickUrl: "https://x.com/", iconUrl: "data:image/png;base64,Z", ts: NOW - 1000 }));
  expect(loadLiveAd(file, NOW, FRESH)).toEqual({ text: "From disk", url: "https://x.com/", icon: "data:image/png;base64,Z", ts: NOW - 1000 });
});

test("loadLiveAd returns null when the file is missing (the fallback path)", () => {
  expect(loadLiveAd(join(tmpdir(), "definitely-not-here-kb.json"), NOW, FRESH)).toBeNull();
});
