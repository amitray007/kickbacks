// kicker/test/ui.test.ts
import { test, expect } from "bun:test";
import { palette, bar, badge, renderDashboard, renderEarnings, renderStatus } from "../src/ui";
import type { Portfolio, Earnings } from "../src/types";

const P: Portfolio = {
  lifetimeUsd: 12.34, todayUsd: 0.56, viewThresholdSeconds: 15, kill: false,
  ads: [{ adId: "552e20ec", campaignId: "23f8444b", text: "Inflowpay: Global sales", clickUrl: "https://inflowpay.test", bannerEnabled: true }],
};
const E: Earnings = { cap: { scope: "daily", capUsd: 1.0, resetSeconds: 15120 } }; // 4h12m

test("palette(false) is identity; palette(true) wraps ANSI", () => {
  expect(palette(false).green("x")).toBe("x");
  expect(palette(true).green("x")).toBe("\x1b[32mx\x1b[0m");
});

test("bar fills proportionally and clamps (plain glyphs)", () => {
  expect(bar(0.5, 1, 10)).toBe("▰▰▰▰▰▱▱▱▱▱");
  expect(bar(0, 1, 4)).toBe("▱▱▱▱");
  expect(bar(2, 1, 4)).toBe("▰▰▰▰"); // over-cap clamps to full
});

test("badge maps each state to its glyph + label", () => {
  expect(badge("earning")).toBe("● Earning");
  expect(badge("killed")).toBe("⊘ Killswitch on");
  expect(badge("cap")).toBe("◐ Cap reached");
  expect(badge("no-serve")).toBe("○ No ad serving");
});

test("renderDashboard shows the unified model (plain)", () => {
  const out = renderDashboard(P, E, 0.18, false);
  expect(out).toContain("● Earning");
  expect(out).toContain("$0.56");
  expect(out).toContain("$12.34");
  expect(out).toContain("$0.18/hr");
  expect(out).toContain("Daily cap");
  expect(out).toContain("56%");
  expect(out).toContain("resets 4h12m");
  expect(out).toContain("Inflowpay: Global sales");
  expect(out).toContain("campaign 23f8444b");
  // no ANSI escapes when color is off
  expect(out).not.toContain("\x1b[");
});

test("renderDashboard badge reflects killed / no-serve", () => {
  expect(renderDashboard({ ...P, kill: true }, E, 0, false)).toContain("⊘ Killswitch on");
  expect(renderDashboard({ ...P, ads: [] }, E, 0, false)).toContain("○ No ad serving");
});

test("renderEarnings and renderStatus render the essentials (plain)", () => {
  const e = renderEarnings(P, E, 0.18, false);
  expect(e).toContain("$12.34");
  expect(e).toContain("Daily cap");
  expect(e).toContain("resets 4h12m");
  const s = renderStatus({ signedIn: true, base: "https://b", configDir: "/tmp/k", dbFile: "/tmp/k/history.db", color: false });
  expect(s).toContain("signed in  yes");
  expect(s).toContain("https://b");
  expect(s).toContain("/tmp/k/history.db");
});

test("renderDashboard badge reflects cap reached", () => {
  expect(renderDashboard({ ...P, todayUsd: 1.0 }, E, 0, false)).toContain("◐ Cap reached");
});

test("renderDashboard shows the empty-ads placeholder", () => {
  expect(renderDashboard({ ...P, ads: [] }, E, 0, false)).toContain("(no ad being served");
});

test("renderDashboard with null earnings omits the cap section", () => {
  const out = renderDashboard(P, null, 0, false);
  expect(out).not.toContain("Daily cap");
  expect(out).toContain("$0.56"); // balances still render
});
