// kickback/test/auth.test.ts
import { test, expect } from "bun:test";
import { startLogin, pollOnce, refresh, signout } from "../src/auth";

const base = "https://b";

test("startLogin parses location + state from the 307", async () => {
  const fakeFetch = async () => new Response(null, {
    status: 307,
    headers: { location: "https://accounts.google.com/o/oauth2/v2/auth?state=XYZ" },
  });
  const r = await startLogin({ fetch: fakeFetch as any, base });
  expect(r.state).toBe("XYZ");
  expect(r.url).toContain("accounts.google.com");
});

test("startLogin rejects a non-https redirect (no OS opener abuse)", async () => {
  const fakeFetch = async () => new Response(null, {
    status: 307,
    headers: { location: "file:///etc/passwd?state=XYZ" },
  });
  await expect(startLogin({ fetch: fakeFetch as any, base })).rejects.toThrow("https");
});

test("pollOnce returns tokens when access_token present, else null", async () => {
  const withTokens = async () => new Response(JSON.stringify({ access_token: "AT", refresh_token: "RT" }), { status: 200 });
  const empty = async () => new Response(JSON.stringify({}), { status: 200 });
  expect(await pollOnce({ fetch: withTokens as any, base }, "S")).toEqual({ access_token: "AT", refresh_token: "RT" });
  expect(await pollOnce({ fetch: empty as any, base }, "S")).toBeNull();
});

test("refresh posts the refresh_token and returns new tokens", async () => {
  let body = "";
  const fakeFetch = async (_url: string, init: any) => { body = init.body;
    return new Response(JSON.stringify({ access_token: "AT2", refresh_token: "RT2" }), { status: 200 }); };
  const t = await refresh({ fetch: fakeFetch as any, base }, "RT1");
  expect(JSON.parse(body)).toEqual({ refresh_token: "RT1" });
  expect(t?.access_token).toBe("AT2");
});

test("signout posts the refresh_token to /v1/auth/signout", async () => {
  let url = "", body = "";
  const fakeFetch = async (u: string, init: any) => { url = u; body = init.body;
    return new Response(null, { status: 200 }); };
  await signout({ fetch: fakeFetch as any, base }, "RT");
  expect(url).toBe("https://b/v1/auth/signout");
  expect(JSON.parse(body)).toEqual({ refresh_token: "RT" });
});
