import type { Portfolio, Earnings, Sample } from "./types";
import type { Store } from "./store";
import { ratePerHour, earningState, fmtUsd, fmtDuration, projectSecondsToCap, type EarningState } from "./derive";
import { sparkline } from "./ui";
import { BoxRenderable, TextRenderable, t, fg, type CliRenderer } from "@opentui/core";

export interface WatchModel {
  p: Portfolio;
  e: Earnings | null;
  rate: number;
  state: EarningState;
  samples: Sample[]; // recent (last 24h), for the sparkline
  ts: number; // when this model was loaded (unix ms)
}

export interface LoadDeps {
  fetchPortfolio: () => Promise<Portfolio>;
  fetchEarnings: () => Promise<Earnings>;
  store: Store;
  now: number;
}

/** Fetch portfolio (required) + earnings (optional), record a sample, derive rate/state.
 *  Pure of auth/renderer concerns — the caller injects already-authed fetchers and the
 *  store, which keeps this unit-testable with fakes + an in-memory store. */
export async function loadModel(d: LoadDeps): Promise<WatchModel> {
  const p = await d.fetchPortfolio();
  const e = await d.fetchEarnings().catch(() => null);
  d.store.insertSample({
    ts: d.now, lifetimeUsd: p.lifetimeUsd, todayUsd: p.todayUsd,
    adId: p.ads[0]?.adId ?? "", kill: p.kill,
  });
  const samples = d.store.recentSince(d.now - 24 * 3_600_000);
  return { p, e, rate: ratePerHour(samples), state: earningState(p, e), samples, ts: d.now };
}

const COL = { green: "#3fb950", dim: "#6e7681", red: "#f85149", yellow: "#d29922", cyan: "#58a6ff", fg: "#c9d1d9" } as const;

const BADGE: Record<EarningState, { glyph: string; label: string; color: string }> = {
  earning: { glyph: "●", label: "Earning", color: COL.green },
  killed: { glyph: "⊘", label: "Killswitch on", color: COL.red },
  cap: { glyph: "◐", label: "Cap reached", color: COL.yellow },
  "no-serve": { glyph: "○", label: "No ad serving", color: COL.dim },
};

const barGlyphs = (value: number, max: number, width = 14): string => {
  const filled = max > 0 ? Math.round(Math.max(0, Math.min(1, value / max)) * width) : 0;
  return "▰".repeat(filled) + "▱".repeat(Math.max(0, width - filled));
};

/** Build the framed OpenTUI dashboard tree for `kickback watch` (design §15.2). A pure
 *  view over the same model the static renderer uses; verified headless via createTestRenderer. */
export function buildDashboardTree(renderer: CliRenderer, m: WatchModel): BoxRenderable {
  const b = BADGE[m.state];
  const box = new BoxRenderable(renderer, {
    id: "dash", border: true, borderStyle: "rounded", borderColor: b.color,
    padding: 1, flexDirection: "column", width: 62,
    title: ` kickback   ${b.glyph} ${b.label} `, titleAlignment: "left",
  });
  const line = (id: string, content: string | ReturnType<typeof t>) =>
    box.add(new TextRenderable(renderer, { id, content, fg: COL.fg }));

  line("bal", t`${fg(COL.dim)("Today    ")}${fg(COL.green)(fmtUsd(m.p.todayUsd))}     ${fg(COL.dim)("Lifetime  ")}${fg(COL.green)(fmtUsd(m.p.lifetimeUsd))}`);
  if (m.rate > 0) {
    line("rate", t`${fg(COL.dim)("Rate     ")}${fg(COL.green)(`${fmtUsd(m.rate)}/hr ▴`)}${fg(COL.dim)("  (last 6h)")}`);
  }
  if (m.e?.cap) {
    const { capUsd, resetSeconds, scope } = m.e.cap;
    const pct = capUsd > 0 ? Math.min(100, Math.round((m.p.todayUsd / capUsd) * 100)) : 0;
    const label = scope.charAt(0).toUpperCase() + scope.slice(1);
    line("cap", t`${fg(COL.dim)(`${label} cap `)}${fg(COL.green)(barGlyphs(m.p.todayUsd, capUsd))}${fg(COL.dim)(`  ${pct}%  ·  ${fmtUsd(m.p.todayUsd)} / ${fmtUsd(capUsd)}  ·  resets ${fmtDuration(resetSeconds)}`)}`);
    const eta = projectSecondsToCap(m.p.todayUsd, capUsd, m.rate);
    if (eta !== null && eta > 0) line("eta", t`${fg(COL.dim)("Projected")} hits cap in ~${fmtDuration(eta)}`);
  }
  const spark = sparkline(m.samples.map((s) => s.todayUsd));
  line("spark", spark
    ? t`${fg(COL.dim)("24h       ")}${fg(COL.green)(spark)}`
    : t`${fg(COL.dim)("24h        collecting history…")}`);
  const ad = m.p.ads[0];
  line("ad", ad
    ? t`${fg(COL.cyan)(" ▸ ")}${ad.text}${ad.clickUrl ? fg(COL.dim)(`  ↗ ${ad.clickUrl}`) : ""}`
    : t`${fg(COL.dim)('   (no ad serving — "your ad here")')}`);
  line("keys", t`${fg(COL.dim)("r refresh · q quit")}`);
  return box;
}
