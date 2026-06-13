import type { Portfolio, Earnings, Sample } from "./types";
import type { Store } from "./store";
import { ratePerHour, earningState, type EarningState } from "./derive";

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
