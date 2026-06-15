import { readFileSync, writeFileSync, mkdirSync, rmSync, chmodSync } from "node:fs";
import { dirname } from "node:path";
import { AUTH_FILE } from "./config";
import { HttpError } from "./api";
import type { Tokens } from "./types";

export interface AuthDeps { fetch: typeof fetch; base: string; }

export async function startLogin(d: AuthDeps): Promise<{ url: string; state: string }> {
  const r = await d.fetch(`${d.base}/v1/auth/extension/start`, { redirect: "manual" });
  const loc = r.headers.get("location");
  if (!loc) throw new Error("no redirect from /start (need Bun/Node ≥18)");
  // The redirect URL is handed to the OS opener (open/xdg-open/start), so reject any
  // non-https scheme (file:, custom handlers) a drifted or MITM'd backend might return.
  if (!loc.startsWith("https://")) throw new Error("login redirect must be https");
  const state = new URL(loc).searchParams.get("state");
  if (!state) throw new Error("no state in redirect URL");
  return { url: loc, state };
}

export async function pollOnce(d: AuthDeps, state: string): Promise<Tokens | null> {
  const r = await d.fetch(`${d.base}/v1/auth/extension/poll?state=${encodeURIComponent(state)}`);
  const j: any = await r.json().catch(() => ({}));
  return j?.access_token ? { access_token: j.access_token, refresh_token: j.refresh_token } : null;
}

export async function refresh(d: AuthDeps, refreshToken: string): Promise<Tokens | null> {
  const r = await d.fetch(`${d.base}/v1/auth/refresh`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  if (!r.ok) return null;
  const j: any = await r.json().catch(() => ({}));
  return j?.access_token ? { access_token: j.access_token, refresh_token: j.refresh_token } : null;
}

export class AuthError extends Error {
  constructor(message: string) { super(message); this.name = "AuthError"; }
}

/** Runs an authed call, refreshing + retrying once on 401. Throws AuthError when there
 *  is no token or the refresh fails — the caller decides whether to exit (one-shot CLI)
 *  or show it and clean up (the TUI). No process side-effects. */
export function makeAuthedRunner(d: AuthDeps) {
  return async function run<T>(call: (token: string) => Promise<T>): Promise<T> {
    const t = loadTokens();
    if (!t) throw new AuthError("Not signed in. Run: kickbacks login");
    try { return await call(t.access_token); }
    catch (e) {
      if (!(e instanceof HttpError) || e.status !== 401 || !t.refresh_token) throw e;
      const nt = await refresh(d, t.refresh_token);
      if (!nt) throw new AuthError("Session expired. Run: kickbacks login");
      saveTokens({ ...t, ...nt });
      return call(nt.access_token);
    }
  };
}

// Best-effort server-side session revoke (matches the prototype). Auth lifecycle
// only — never a billing/metrics call. cli.cmdLogout swallows failures.
export async function signout(d: AuthDeps, refreshToken: string): Promise<void> {
  await d.fetch(`${d.base}/v1/auth/signout`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
}

// --- token file (chmod 600 inside a 700 dir). Keychain storage is a Plan 3+ enhancement. ---
export function loadTokens(): Tokens | null {
  try { return JSON.parse(readFileSync(AUTH_FILE, "utf8")); } catch { return null; }
}
export function saveTokens(t: Tokens): void {
  const dir = dirname(AUTH_FILE);
  try { mkdirSync(dir, { recursive: true, mode: 0o700 }); } catch {}
  // mkdir's mode is ignored when the dir already exists (and is umask-masked), so
  // enforce 0700 explicitly — this directory holds OAuth tokens.
  try { chmodSync(dir, 0o700); } catch {}
  writeFileSync(AUTH_FILE, JSON.stringify(t, null, 2) + "\n", { mode: 0o600 });
}
export function clearTokens(): void { try { rmSync(AUTH_FILE); } catch {} }
