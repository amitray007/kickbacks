// cli/test/cli.integration.test.ts
//
// End-to-end QA: drives the real CLI (`bun run src/cli.ts <cmd>`) against a mock
// backend on localhost and a throwaway config dir. Covers every command EXCEPT
// `login` (interactive Google OAuth — human-in-the-loop, design §13.5).
// Never touches the real account, real backend, or ~/.config/kickback.
import { test, expect, beforeAll, afterAll, beforeEach, afterEach } from "bun:test";
import { Database } from "bun:sqlite";
import { mkdtempSync, writeFileSync, rmSync, existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const cliDir = join(import.meta.dir, "..");

const PORTFOLIO = {
  kill: false,
  balances: { lifetime_usd: "12.34", today_usd: "0.56" },
  view_threshold_seconds: 15,
  ads: [{
    ad_id: "552e20ec", campaign_id: "23f8444b",
    title_text: "Inflowpay: Global sales, 50% less fees",
    click_url: "https://inflowpay.test", banner_enabled: true,
  }],
};
const EARNINGS = { cap: { scope: "daily", cap_usd: "1.00", reset_seconds: 15120 } }; // 4h12m

const mock = { portfolio401ForToken: null as string | null, refreshCalled: false, signoutCalled: false };

let server: ReturnType<typeof Bun.serve>;
let baseUrl = "";

beforeAll(() => {
  server = Bun.serve({
    port: 0,
    fetch(req) {
      const url = new URL(req.url);
      const auth = req.headers.get("authorization") ?? "";
      if (url.pathname === "/v1/portfolio") {
        if (mock.portfolio401ForToken && auth === `Bearer ${mock.portfolio401ForToken}`)
          return new Response("unauthorized", { status: 401 });
        return Response.json(PORTFOLIO);
      }
      if (url.pathname === "/v1/earnings") return Response.json(EARNINGS);
      if (url.pathname === "/v1/auth/refresh") {
        mock.refreshCalled = true;
        return Response.json({ access_token: "AT2", refresh_token: "RT2" });
      }
      if (url.pathname === "/v1/auth/signout") {
        mock.signoutCalled = true;
        return new Response(null, { status: 200 });
      }
      return new Response("not found", { status: 404 });
    },
  });
  baseUrl = `http://localhost:${server.port}`;
});

afterAll(() => server.stop(true));

let cfgDir = "";
beforeEach(() => {
  mock.portfolio401ForToken = null;
  mock.refreshCalled = false;
  mock.signoutCalled = false;
  cfgDir = mkdtempSync(join(tmpdir(), "kickback-qa-"));
  writeFileSync(join(cfgDir, "auth.json"), JSON.stringify({ access_token: "AT", refresh_token: "RT" }));
});
afterEach(() => rmSync(cfgDir, { recursive: true, force: true }));

async function runCli(args: string[]) {
  const proc = Bun.spawn([process.execPath, "run", "src/cli.ts", ...args], {
    cwd: cliDir,
    env: { ...process.env, KICKBACK_CONFIG_DIR: cfgDir, KICKBACK_BASE: baseUrl, NO_COLOR: "1" },
    stdout: "pipe", stderr: "pipe",
  });
  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  const exitCode = await proc.exited;
  return { stdout, stderr, exitCode };
}

test("dashboard renders the unified model + served ad and records a history sample", async () => {
  const { stdout, exitCode } = await runCli(["portfolio"]);
  expect(exitCode).toBe(0);
  expect(stdout).toContain("Earning");      // state badge (● stripped by NO_COLOR-safe assert)
  expect(stdout).toContain("$0.56");
  expect(stdout).toContain("$12.34");
  expect(stdout).toContain("Daily cap");     // earnings pulled into the default view
  expect(stdout).toContain("resets 4h12m");
  expect(stdout).toContain("Inflowpay: Global sales, 50% less fees");
  expect(stdout).toContain("https://inflowpay.test");

  const db = new Database(join(cfgDir, "history.db"));
  const row = db.query("SELECT today_usd, ad_id, kill FROM samples ORDER BY ts DESC LIMIT 1").get() as any;
  db.close();
  expect(row.today_usd).toBeCloseTo(0.56, 5);
  expect(row.ad_id).toBe("552e20ec");
  expect(row.kill).toBe(0);
});

test("earnings renders the daily cap and reset countdown", async () => {
  const { stdout, exitCode } = await runCli(["earnings"]);
  expect(exitCode).toBe(0);
  expect(stdout).toContain("Daily cap");
  expect(stdout).toContain("$1.00");
  expect(stdout).toContain("resets 4h12m");
});

test("raw dumps unparsed server JSON verbatim", async () => {
  const { stdout, exitCode } = await runCli(["raw"]);
  expect(exitCode).toBe(0);
  const j = JSON.parse(stdout);
  expect(j.portfolio.balances.lifetime_usd).toBe("12.34"); // unparsed string, not normalized
  expect(j.portfolio.ads[0].title_text).toBe("Inflowpay: Global sales, 50% less fees");
  expect(j.earnings.cap.scope).toBe("daily");
});

test("status reports signed-in when a token file exists", async () => {
  const { stdout, exitCode } = await runCli(["status"]);
  expect(exitCode).toBe(0);
  expect(stdout).toContain("signed in  yes");
});

test("logout revokes server-side then clears the local token", async () => {
  const { stdout, exitCode } = await runCli(["logout"]);
  expect(exitCode).toBe(0);
  expect(stdout).toContain("Signed out");
  expect(mock.signoutCalled).toBe(true);
  expect(existsSync(join(cfgDir, "auth.json"))).toBe(false);
});

test("a 401 triggers a token refresh and a successful retry", async () => {
  mock.portfolio401ForToken = "AT"; // the stale token 401s; refreshed AT2 succeeds
  const { stdout, exitCode } = await runCli(["portfolio"]);
  expect(exitCode).toBe(0);
  expect(mock.refreshCalled).toBe(true);
  expect(stdout).toContain("$12.34");
  const saved = JSON.parse(readFileSync(join(cfgDir, "auth.json"), "utf8"));
  expect(saved.access_token).toBe("AT2"); // rotated token persisted
});
