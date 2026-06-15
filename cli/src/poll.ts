import type { Portfolio, Earnings } from "./types";
import type { Store } from "./store";
import { decideAlerts } from "./alerts";
import type { Notifier } from "./notify";

export interface PollDeps {
  fetchPortfolio: () => Promise<Portfolio>;
  fetchEarnings: () => Promise<Earnings>;
  store: Store;
  isActive: () => boolean;
  notify: Notifier;
  now: number;
  stallWindowMs: number;
}

/** One poll cycle: fetch, detect activity, record a full sample, decide + fire alerts,
 *  persist de-dup state. Pure of auth/launchd — the caller injects authed fetchers, the
 *  activity probe, and the notifier, which keeps it unit-testable end to end. */
export async function runPoll(d: PollDeps): Promise<void> {
  const p = await d.fetchPortfolio();
  const e = await d.fetchEarnings().catch(() => null);
  const active = d.isActive();
  d.store.insertSample({
    ts: d.now, lifetimeUsd: p.lifetimeUsd, todayUsd: p.todayUsd, adId: p.ads[0]?.adId ?? "", kill: p.kill,
    active, capScope: e?.cap?.scope ?? null, capUsd: e?.cap?.capUsd ?? null, capResetS: e?.cap?.resetSeconds ?? null,
  });
  const samples = d.store.recentSince(d.now - 24 * 3_600_000);
  const a = decideAlerts({
    samples, earnings: e, now: d.now, stallWindowMs: d.stallWindowMs,
    state: { stallActive: d.store.getState("stallActive") ?? "", capFired: d.store.getState("capFired") ?? undefined },
  });
  // Stall alerting removed — the active+flat heuristic was unreliable. Cap alerts remain.
  if (a.cap) d.notify("Kickback — cap reached", `Your ${a.cap.scope} cap is hit; no more earning until it resets.`);
  d.store.setState("stallActive", a.state.stallActive);
  if (a.state.capFired !== null) d.store.setState("capFired", a.state.capFired);
  // No explicit cap re-arm: the period-bucket key in decideAlerts changes each reset
  // period, so the next period's cap-hit fires on its own.
}
