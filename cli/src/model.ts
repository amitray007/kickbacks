import type { Portfolio, Earnings } from "./types";
import type { Store } from "./store";
import { ratePerHour, projectSecondsToCap, earningState, isStalled, fmtUsd, fmtDuration } from "./derive";
import { sparkline } from "./ui";

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
}

export interface MenuInput {
  p: Portfolio | null;
  e: Earnings | null;
  store: Store;
  now: number;
  signedIn: boolean;
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
    };
  }
  const p = i.p, e = i.e;
  const samples = i.store.recentSince(i.now - 24 * 3_600_000);
  const rate = ratePerHour(samples.filter((s) => s.ts >= i.now - 6 * 3_600_000));
  const latest = samples[samples.length - 1];
  const prev = samples[samples.length - 2];
  const trend: "up" | "down" | "flat" = !latest || !prev
    ? (rate > 0 ? "up" : "flat")
    : latest.todayUsd > prev.todayUsd ? "up" : latest.todayUsd < prev.todayUsd ? "down" : "flat";
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
  };
}
