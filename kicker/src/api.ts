import type { Portfolio, Earnings, Cap, Ad } from "./types";

const num = (v: unknown): number => {
  const n = typeof v === "string" ? parseFloat(v) : typeof v === "number" ? v : NaN;
  return Number.isFinite(n) ? n : 0;
};

export function parsePortfolio(j: any): Portfolio {
  const b = j?.balances ?? {};
  const ads: Ad[] = Array.isArray(j?.ads) ? j.ads.map((a: any) => ({
    adId: String(a?.ad_id ?? a?.adId ?? ""),
    campaignId: String(a?.campaign_id ?? a?.campaignId ?? ""),
    text: String(a?.title_text ?? a?.adText ?? ""),
    clickUrl: typeof (a?.click_url ?? a?.clickUrl) === "string" ? (a.click_url ?? a.clickUrl) : "",
    bannerEnabled: (a?.banner_enabled ?? a?.bannerEnabled) === true,
  })) : [];
  return {
    lifetimeUsd: num(b.lifetime_usd),
    todayUsd: num(b.today_usd),
    ads,
    viewThresholdSeconds: typeof j?.view_threshold_seconds === "number"
      ? j.view_threshold_seconds : null,
    kill: j?.kill === true,
  };
}

export function parseEarnings(j: any): Earnings {
  const c = j?.cap;
  let cap: Cap | null = null;
  if (c && (c.scope === "hourly" || c.scope === "daily")
      && typeof c.cap_usd !== "undefined" && typeof c.reset_seconds === "number") {
    cap = { scope: c.scope, capUsd: num(c.cap_usd), resetSeconds: Math.max(0, Math.floor(c.reset_seconds)) };
  }
  return { cap };
}

export interface ApiDeps {
  fetch: typeof fetch;
  token: string;
  base: string;
  ccVersion: string;
}

export async function fetchPortfolio(d: ApiDeps): Promise<Portfolio> {
  const url = `${d.base}/v1/portfolio?claude_code_version=${encodeURIComponent(d.ccVersion)}`;
  const r = await d.fetch(url, { headers: { authorization: `Bearer ${d.token}` } });
  if (!r.ok) throw new Error(`portfolio HTTP ${r.status}`);
  return parsePortfolio(await r.json());
}

export async function fetchEarnings(d: ApiDeps): Promise<Earnings> {
  const r = await d.fetch(`${d.base}/v1/earnings`, { headers: { authorization: `Bearer ${d.token}` } });
  if (!r.ok) throw new Error(`earnings HTTP ${r.status}`);
  return parseEarnings(await r.json());
}

// Unparsed passthrough for `kicker raw` — surfaces server fields verbatim so an
// API-shape drift is visible instead of silently normalized away.
export async function fetchRaw(d: ApiDeps, path: string): Promise<unknown> {
  const r = await d.fetch(`${d.base}${path}`, { headers: { authorization: `Bearer ${d.token}` } });
  if (!r.ok) throw new Error(`raw HTTP ${r.status}`);
  return r.json();
}
