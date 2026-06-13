import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import type { Sample } from "./types";

export interface Store {
  insertSample(s: Sample): void;
  latest(): Sample | null;
  recentSince(ts: number): Sample[];
  userVersion(): number;
  close(): void;
}

export function openStore(path: string): Store {
  if (path !== ":memory:") { try { mkdirSync(dirname(path), { recursive: true }); } catch {} }
  const db = new Database(path);
  db.run(`CREATE TABLE IF NOT EXISTS samples (
    ts INTEGER PRIMARY KEY, lifetime_usd REAL, today_usd REAL, ad_id TEXT, kill INTEGER
  )`);
  // Schema version stamp so Plan 3's watchdog columns (active, cap_*) can migrate cleanly.
  if (((db.query("PRAGMA user_version").get() as any)?.user_version ?? 0) < 1) {
    db.run("PRAGMA user_version = 1");
  }
  const rowToSample = (r: any): Sample => ({
    ts: r.ts, lifetimeUsd: r.lifetime_usd, todayUsd: r.today_usd,
    adId: r.ad_id, kill: !!r.kill,
  });
  return {
    insertSample(s) {
      db.run("INSERT OR REPLACE INTO samples VALUES (?,?,?,?,?)",
        [s.ts, s.lifetimeUsd, s.todayUsd, s.adId, s.kill ? 1 : 0]);
    },
    latest() {
      const r = db.query("SELECT * FROM samples ORDER BY ts DESC LIMIT 1").get() as any;
      return r ? rowToSample(r) : null;
    },
    recentSince(ts) {
      return (db.query("SELECT * FROM samples WHERE ts >= ? ORDER BY ts ASC").all(ts) as any[])
        .map(rowToSample);
    },
    userVersion() { return (db.query("PRAGMA user_version").get() as any).user_version as number; },
    close() { db.close(); },
  };
}
