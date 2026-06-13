import type { Sample, Earnings } from "./types";
import { isStalled } from "./derive";

export interface AlertInput {
  samples: Sample[];
  earnings: Earnings | null;
  now: number;
  stallWindowMs: number;
  state: { stallActive?: string; capFired?: string };
}

export interface Alerts {
  stall: boolean;                       // edge-triggered: true only on the cycle a stall begins
  cap?: { scope: string; key: string }; // present only on the cycle a cap period is first hit
  state: { stallActive: string; capFired: string | null }; // kv markers the caller persists
}

/** Decide which alerts to fire this cycle, de-duped against prior kv markers. Pure.
 *  Stall is edge-triggered (fires once per episode, re-arms when earning resumes); the
 *  cap alert is keyed by scope + reset-period bucket so it fires once per cap period. */
export function decideAlerts(i: AlertInput): Alerts {
  const recent = [...i.samples].sort((a, b) => a.ts - b.ts);
  const latest = recent[recent.length - 1];
  const active = latest?.active === true;
  const stalledNow = isStalled({ samples: recent, now: i.now, windowMs: i.stallWindowMs, active });
  const wasStalled = i.state.stallActive === "1";

  const out: Alerts = {
    stall: stalledNow && !wasStalled,
    state: { stallActive: stalledNow ? "1" : "", capFired: i.state.capFired ?? null },
  };

  const cap = i.earnings?.cap;
  const today = latest?.todayUsd ?? 0;
  if (cap && today >= cap.capUsd) {
    // Period bucket, UTC-epoch-aligned (may lag the server's real reset by < 1 period).
    const key = `${cap.scope}:${Math.floor(i.now / Math.max(1000, cap.resetSeconds * 1000))}`;
    if (i.state.capFired !== key) {
      out.cap = { scope: cap.scope, key };
      out.state.capFired = key;
    }
  }
  return out;
}
