// kickback/test/api.test.ts
import { test, expect } from "bun:test";
import { parsePortfolio, parseEarnings, fetchPortfolio, fetchRaw } from "../src/api";

test("parsePortfolio normalizes server fields", () => {
  const p = parsePortfolio({
    kill: false,
    balances: { lifetime_usd: "1.50", today_usd: "0.25" },
    view_threshold_seconds: 15,
    ads: [{ ad_id: "a1", campaign_id: "c1", title_text: "Buy X",
            click_url: "https://x.test", banner_enabled: true }],
  });
  expect(p.lifetimeUsd).toBe(1.5);
  expect(p.todayUsd).toBe(0.25);
  expect(p.kill).toBe(false);
  expect(p.viewThresholdSeconds).toBe(15);
  expect(p.ads[0]).toEqual({ adId: "a1", campaignId: "c1", text: "Buy X",
    clickUrl: "https://x.test", bannerEnabled: true });
});

test("parsePortfolio tolerates missing fields", () => {
  const p = parsePortfolio({});
  expect(p.lifetimeUsd).toBe(0);
  expect(p.todayUsd).toBe(0);
  expect(p.ads).toEqual([]);
  expect(p.kill).toBe(false);
});

test("parsePortfolio accepts camelCase ad fields", () => {
  const p = parsePortfolio({ ads: [{ adId: "a2", campaignId: "c2", adText: "Buy Y",
    clickUrl: "https://y.test", bannerEnabled: true }] });
  expect(p.ads[0]).toEqual({ adId: "a2", campaignId: "c2", text: "Buy Y",
    clickUrl: "https://y.test", bannerEnabled: true });
});

test("parseEarnings reads the cap", () => {
  const e = parseEarnings({ cap: { scope: "daily", cap_usd: "1.00", reset_seconds: 3600 } });
  expect(e.cap).toEqual({ scope: "daily", capUsd: 1, resetSeconds: 3600 });
});

test("fetchPortfolio sends bearer + cc version and parses", async () => {
  let seenUrl = ""; let seenAuth = "";
  const fakeFetch = async (url: string, init: any) => {
    seenUrl = url; seenAuth = init.headers.authorization;
    return new Response(JSON.stringify({ balances: { lifetime_usd: "2", today_usd: "1" } }),
      { status: 200 });
  };
  const p = await fetchPortfolio({ fetch: fakeFetch as any, token: "TK", base: "https://b", ccVersion: "9" });
  expect(seenUrl).toContain("/v1/portfolio?claude_code_version=9");
  expect(seenAuth).toBe("Bearer TK");
  expect(p.lifetimeUsd).toBe(2);
});

test("fetchRaw returns unparsed server JSON (drift debugging)", async () => {
  const fakeFetch = async () => new Response(JSON.stringify({ weird_new_field: 1 }), { status: 200 });
  const j: any = await fetchRaw({ fetch: fakeFetch as any, token: "TK", base: "https://b", ccVersion: "9" }, "/v1/portfolio");
  expect(j.weird_new_field).toBe(1);
});
