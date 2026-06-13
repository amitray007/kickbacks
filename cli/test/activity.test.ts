// cli/test/activity.test.ts
import { test, expect } from "bun:test";
import { isActive } from "../src/activity";
import { mkdtempSync, writeFileSync, utimesSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

test("isActive true iff a file under dirs was modified within the window", () => {
  const dir = mkdtempSync(join(tmpdir(), "kb-act-"));
  const f = join(dir, "session.jsonl");
  writeFileSync(f, "x");
  const now = 1_700_000_000_000;

  utimesSync(f, new Date(now - 60_000), new Date(now - 60_000)); // 1 min ago
  expect(isActive([dir], now, 300_000)).toBe(true);              // within 5 min

  utimesSync(f, new Date(now - 600_000), new Date(now - 600_000)); // 10 min ago
  expect(isActive([dir], now, 300_000)).toBe(false);

  expect(isActive(["/no/such/dir"], now, 300_000)).toBe(false);  // missing dir → false
});
