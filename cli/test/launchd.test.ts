// cli/test/launchd.test.ts
import { test, expect } from "bun:test";
import { plistContent } from "../src/launchd";

test("plistContent embeds label, program args, and interval", () => {
  const xml = plistContent("ai.kickback.poller", "/usr/local/bin/kickback", 180);
  expect(xml).toContain("<string>ai.kickback.poller</string>");
  expect(xml).toContain("<string>/usr/local/bin/kickback</string>");
  expect(xml).toContain("<string>poll</string>"); // runs `kickback poll`
  expect(xml).toContain("<integer>180</integer>"); // StartInterval
  expect(xml).toContain("<true/>"); // RunAtLoad
  expect(xml.startsWith("<?xml")).toBe(true);
});
