import type { Portfolio, Earnings } from "./types";
import { fmtUsd, fmtDuration, projectSecondsToCap, earningState, type EarningState } from "./derive";

type Paint = (s: string | number) => string;
export interface Palette {
  bold: Paint; dim: Paint; green: Paint; red: Paint; yellow: Paint; cyan: Paint;
}

/** ANSI palette. When `color` is false every paint is the identity (plain text),
 *  which keeps renderers fully testable and keeps piped/non-TTY output clean. */
export function palette(color: boolean): Palette {
  const w = (code: number): Paint => (s) => (color ? `\x1b[${code}m${s}\x1b[0m` : String(s));
  return { bold: w(1), dim: w(2), green: w(32), red: w(31), yellow: w(33), cyan: w(36) };
}

/** Emit color only on a TTY that hasn't opted out via NO_COLOR. */
export const useColor = (): boolean => !!process.stdout.isTTY && !process.env.NO_COLOR;

/** A ▰▰▱▱ progress bar. `c` colors filled vs empty; pass palette(false) for plain glyphs. */
export function bar(value: number, max: number, width = 12, c: Palette = palette(false)): string {
  const ratio = max > 0 ? Math.max(0, Math.min(1, value / max)) : 0;
  const filled = Math.round(ratio * width);
  return c.green("▰".repeat(filled)) + c.dim("▱".repeat(Math.max(0, width - filled)));
}

const BADGES: Record<EarningState, { glyph: string; label: string; paint: keyof Palette }> = {
  earning:    { glyph: "●", label: "Earning",        paint: "green" },
  killed:     { glyph: "⊘", label: "Killswitch on",  paint: "red" },
  cap:        { glyph: "◐", label: "Cap reached",    paint: "yellow" },
  "no-serve": { glyph: "○", label: "No ad serving",  paint: "dim" },
};

export function badge(state: EarningState, c: Palette = palette(false)): string {
  const b = BADGES[state];
  return c[b.paint](`${b.glyph} ${b.label}`);
}

// Only ever called when rate > 0; the "—" branch makes the call contract explicit.
const trend = (rate: number): "▴" | "—" => (rate > 0 ? "▴" : "—");
const capitalize = (s: string): string => s.charAt(0).toUpperCase() + s.slice(1);

/** The default `kicker` view — the unified earnings model (design §15.2) as static
 *  colored text. The live framed/animated TUI is Plan 2 (OpenTUI). */
export function renderDashboard(p: Portfolio, e: Earnings | null, rate: number, color: boolean): string {
  const c = palette(color);
  const L: string[] = ["", `  ${c.bold("kicker")}   ${badge(earningState(p, e), c)}`, `  ${c.dim("─".repeat(52))}`];
  L.push(`  ${c.dim("Today    ")}${c.green(fmtUsd(p.todayUsd))}     ${c.dim("Lifetime  ")}${c.green(fmtUsd(p.lifetimeUsd))}`);
  if (rate > 0) L.push(`  ${c.dim("Rate     ")}${c.green(`${fmtUsd(rate)}/hr`)} ${c.green(trend(rate))}${c.dim("  (last 6h)")}`);
  if (e?.cap) {
    const { capUsd, resetSeconds, scope } = e.cap;
    const pct = capUsd > 0 ? Math.min(100, Math.round((p.todayUsd / capUsd) * 100)) : 0;
    L.push(`  ${c.dim(`${capitalize(scope)} cap `)}${bar(p.todayUsd, capUsd, 12, c)}${c.dim(`  ${pct}%  ·  ${fmtUsd(p.todayUsd)} / ${fmtUsd(capUsd)}  ·  resets ${fmtDuration(resetSeconds)}`)}`);
    const eta = projectSecondsToCap(p.todayUsd, capUsd, rate);
    if (eta !== null && eta > 0) L.push(`  ${c.dim("Projected")} hits cap in ~${fmtDuration(eta)}${c.dim(" at this rate")}`);
  }
  // "ON" is intentionally shouty vs "off" — the dangerous state should catch the eye.
  L.push(`  ${c.dim(`Killswitch ${p.kill ? "ON" : "off"}   ·   View gate ${p.viewThresholdSeconds ?? "?"}s`)}`);
  L.push("", `  ${c.dim(`Now showing (${p.ads.length})`)}`);
  if (p.ads.length === 0) L.push(`  ${c.dim('   (no ad being served — "your ad here")')}`);
  for (const a of p.ads) {
    L.push(`  ${c.cyan(" ▸")} ${a.text}${a.clickUrl ? c.dim(`  ↗ ${a.clickUrl}`) : ""}`);
    const ids = [
      a.campaignId ? `campaign ${a.campaignId.slice(0, 8)}` : "",
      a.adId ? `ad ${a.adId.slice(0, 8)}` : "",
    ].filter(Boolean).join(" · ");
    if (ids) L.push(`     ${c.dim(ids)}`);
  }
  L.push("");
  return L.join("\n");
}

/** Focused `kicker earnings` view (balances + cap + projection). */
export function renderEarnings(p: Portfolio, e: Earnings | null, rate: number, color: boolean): string {
  const c = palette(color);
  const L: string[] = ["", `  ${c.bold("Earnings")}`, `  ${c.dim("─".repeat(30))}`];
  L.push(`  ${c.dim("Lifetime ")}${c.green(fmtUsd(p.lifetimeUsd))}`);
  L.push(`  ${c.dim("Today    ")}${c.green(fmtUsd(p.todayUsd))}`);
  if (rate > 0) L.push(`  ${c.dim("Rate     ")}${c.green(`${fmtUsd(rate)}/hr`)} ${c.green(trend(rate))}`);
  if (e?.cap) {
    const { capUsd, resetSeconds, scope } = e.cap;
    L.push(`  ${c.dim(`${capitalize(scope)} cap `)}${bar(p.todayUsd, capUsd, 12, c)}${c.dim(`  ${fmtUsd(p.todayUsd)} / ${fmtUsd(capUsd)} · resets ${fmtDuration(resetSeconds)}`)}`);
    const eta = projectSecondsToCap(p.todayUsd, capUsd, rate);
    if (eta !== null && eta > 0) L.push(`  ${c.dim("To cap   ")}~${fmtDuration(eta)}${c.dim(" at this rate")}`);
  } else {
    L.push(`  ${c.dim("(no cap reported)")}`);
  }
  L.push("");
  return L.join("\n");
}

export function renderStatus(o: { signedIn: boolean; base: string; configDir: string; dbFile: string; color: boolean }): string {
  const c = palette(o.color);
  return [
    "",
    `  ${c.bold("kicker status")}`,
    `  ${c.dim("─".repeat(30))}`,
    `  ${c.dim("signed in  ")}${o.signedIn ? c.green("yes") : c.yellow("no")}`,
    `  ${c.dim("backend    ")}${o.base}`,
    `  ${c.dim("config     ")}${o.configDir}`,
    `  ${c.dim("history db ")}${o.dbFile}`,
    "",
  ].join("\n");
}
