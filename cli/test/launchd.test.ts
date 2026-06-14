// cli/test/launchd.test.ts
import { test, expect } from "bun:test";
import { plistContent, guiPlistContent } from "../src/launchd";

test("plistContent embeds label, program args, and interval", () => {
  const xml = plistContent("ai.kickback.poller", "/usr/local/bin/kickback", 180);
  expect(xml).toContain("<string>ai.kickback.poller</string>");
  expect(xml).toContain("<string>/usr/local/bin/kickback</string>");
  expect(xml).toContain("<string>poll</string>"); // runs `kickback poll`
  expect(xml).toContain("<integer>180</integer>"); // StartInterval
  expect(xml).toContain("<true/>"); // RunAtLoad
  expect(xml.startsWith("<?xml")).toBe(true);
});

test("guiPlistContent runs the binary at login in the Aqua session", () => {
  const xml = guiPlistContent("ai.kickback.bar", "/opt/homebrew/bin/kickback-bar");
  expect(xml).toContain("<string>ai.kickback.bar</string>");
  expect(xml).toContain("<string>/opt/homebrew/bin/kickback-bar</string>");
  expect(xml).toContain("<key>RunAtLoad</key><true/>");
  expect(xml).toContain("Aqua"); // LimitLoadToSessionType
  expect(xml).not.toContain("StartInterval"); // long-running, not interval
});
