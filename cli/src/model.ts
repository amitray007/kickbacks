import type { Portfolio, Earnings } from "./types";
import type { Store } from "./store";
import { ratePerHour, projectSecondsToCap, earningState, isStalled, fmtUsd, fmtDuration } from "./derive";
import { sparkline } from "./ui";
import { lastEarnedAgoSeconds } from "./history";
import type { RecentAd } from "./ads";

export type MenuState = "signed-out" | "killed" | "cap" | "stalled" | "no-serve" | "earning";

export interface MenuModel {
  signedIn: boolean;
  state: MenuState;
  title: string;
  today: string;
  lifetime: string;
  rate: string;
  trend: "up" | "down" | "flat";
  cap: string;
  capPct: number;
  resets: string;
  projection: string;
  spark: string;
  ad: string;
  adUrl: string;
  status: string;
  ageSeconds: number;
  menuValue: string;
  viewThresholdSeconds: number | null;
  ads: { text: string; url: string; icon: string }[];
  lastEarnedAgoSeconds: number | null;
  collecting: boolean;
  recentAds: { text: string; url: string; icon: string }[];
}

export interface MenuInput {
  p: Portfolio | null;
  e: Earnings | null;
  store: Store;
  now: number;
  signedIn: boolean;
  recentAds?: RecentAd[];
}

const STATUS: Record<MenuState, string> = {
  "signed-out": "Signed out", killed: "Killswitch on", cap: "Cap reached",
  stalled: "Stalled — not earning", "no-serve": "No ad serving", earning: "Earning",
};

/** Build the display-ready menu model from live portfolio/earnings + local history.
 *  Pure (reuses derive/ui formatters) — the CLI's `model` command does the fetch and
 *  passes results here; the Swift menu app just renders the JSON. */
export function buildMenuModel(i: MenuInput): MenuModel {
  if (!i.signedIn || !i.p) {
    return {
      signedIn: false, state: "signed-out", title: "kickback",
      today: "$0.00", lifetime: "$0.00", rate: "", trend: "flat", cap: "", capPct: 0,
      resets: "", projection: "", spark: "", ad: "", adUrl: "", status: STATUS["signed-out"], ageSeconds: 0,
      menuValue: "—", viewThresholdSeconds: null, ads: [], lastEarnedAgoSeconds: null, collecting: false,
      recentAds: [],
    };
  }
  const p = i.p, e = i.e;
  const samples = i.store.recentSince(i.now - 24 * 3_600_000); // 24h window for the sparkline
  const latest = samples[samples.length - 1];
  const r6 = samples.filter((s) => s.ts >= i.now - 6 * 3_600_000); // 6h window for rate + trend (aligned)
  const rate = ratePerHour(r6);
  const a = r6[r6.length - 1], b = r6[r6.length - 2];
  const trend: "up" | "down" | "flat" = !a || !b
    ? (rate > 0 ? "up" : "flat")
    : a.todayUsd > b.todayUsd ? "up" : a.todayUsd < b.todayUsd ? "down" : "flat";
  // `active` is from the latest stored sample (poll cadence; null on pre-Plan-3 samples → inactive).
  const active = latest?.active === true;
  const stalled = isStalled({ samples, now: i.now, windowMs: 10 * 60_000, active });
  const base = earningState(p, e); // killed | cap | no-serve | earning
  const state: MenuState = base === "earning" && stalled ? "stalled" : base;

  const arrow = trend === "up" ? "▴" : trend === "down" ? "▾" : "—";
  const cap = e?.cap ?? null;
  const eta = cap ? projectSecondsToCap(p.todayUsd, cap.capUsd, rate) : null;
  const ad = p.ads[0];
  return {
    signedIn: true, state,
    title: `${fmtUsd(p.todayUsd)} ${arrow}`,
    today: fmtUsd(p.todayUsd), lifetime: fmtUsd(p.lifetimeUsd),
    rate: rate > 0 ? `${fmtUsd(rate)}/hr` : "", trend,
    cap: cap ? `${fmtUsd(p.todayUsd)} / ${fmtUsd(cap.capUsd)}` : "",
    capPct: cap && cap.capUsd > 0 ? Math.min(100, Math.round((p.todayUsd / cap.capUsd) * 100)) : 0,
    resets: cap ? fmtDuration(cap.resetSeconds) : "",
    projection: eta !== null && eta > 0 ? `~${fmtDuration(eta)}` : "",
    spark: samples.length >= 2 ? sparkline(samples.map((s) => s.todayUsd)) : "",
    ad: ad?.text ?? "", adUrl: ad?.clickUrl ?? "",
    status: STATUS[state],
    ageSeconds: latest ? Math.max(0, Math.round((i.now - latest.ts) / 1000)) : 0,
    menuValue: p.todayUsd.toFixed(2),
    viewThresholdSeconds: p.viewThresholdSeconds,
    ads: p.ads.map((a) => ({ text: a.text, url: a.clickUrl, icon: a.iconUrl })),
    lastEarnedAgoSeconds: lastEarnedAgoSeconds(samples, i.now),
    collecting: samples.length < 2,
    recentAds: (i.recentAds ?? []).map((a) => ({ text: a.text, url: a.url, icon: a.icon })),
  };
}
