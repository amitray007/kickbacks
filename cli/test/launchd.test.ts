// cli/test/launchd.test.ts
import { test, expect } from "bun:test";
import { plistContent, guiPlistContent } from "../src/launchd";

test("plistContent embeds label, program args, and interval", () => {
  const xml = plistContent("ai.kickbacks.poller", "/usr/local/bin/kickbacks", 180);
  expect(xml).toContain("<string>ai.kickbacks.poller</string>");
  expect(xml).toContain("<string>/usr/local/bin/kickbacks</string>");
  expect(xml).toContain("<string>poll</string>"); // runs `kickbacks poll`
  expect(xml).toContain("<integer>180</integer>"); // StartInterval
  expect(xml).toContain("<true/>"); // RunAtLoad
  expect(xml.startsWith("<?xml")).toBe(true);
});

test("guiPlistContent runs the binary at login in the Aqua session", () => {
  const xml = guiPlistContent("ai.kickbacks.bar", "/opt/homebrew/bin/kickbacks-bar");
  expect(xml).toContain("<string>ai.kickbacks.bar</string>");
  expect(xml).toContain("<string>/opt/homebrew/bin/kickbacks-bar</string>");
  expect(xml).toContain("<key>RunAtLoad</key><true/>");
  expect(xml).toContain("Aqua"); // LimitLoadToSessionType
  expect(xml).not.toContain("StartInterval"); // long-running, not interval
});
