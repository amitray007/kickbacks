import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import type { Sample } from "./types";

export interface Store {
  insertSample(s: Sample): void;
  latest(): Sample | null;
  recentSince(ts: number): Sample[];
  getState(key: string): string | null;
  setState(key: string, value: string): void;
  userVersion(): number;
  close(): void;
}

export function openStore(path: string): Store {
  if (path !== ":memory:") { try { mkdirSync(dirname(path), { recursive: true, mode: 0o700 }); } catch {} }
  const db = new Database(path);
  db.run(`CREATE TABLE IF NOT EXISTS samples (
    ts INTEGER PRIMARY KEY, lifetime_usd REAL, today_usd REAL, ad_id TEXT, kill INTEGER
  )`);
  const readVersion = (): number =>
    Number((db.query("PRAGMA user_version").get() as any)?.user_version ?? 0);
  const hasColumn = (table: string, col: string): boolean =>
    (db.query(`PRAGMA table_info(${table})`).all() as any[]).some((c) => c.name === col);
  // Forward-only migrations. v1: base table. v2: poller's cap/active columns (design §5).
  if (readVersion() < 1) db.run("PRAGMA user_version = 1");
  if (readVersion() < 2) {
    for (const [col, type] of [["cap_scope", "TEXT"], ["cap_usd", "REAL"], ["cap_reset_s", "INTEGER"], ["active", "INTEGER"]] as const) {
      if (!hasColumn("samples", col)) db.run(`ALTER TABLE samples ADD COLUMN ${col} ${type}`);
    }
    db.run("PRAGMA user_version = 2");
  }
  db.run("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT)");

  const rowToSample = (r: any): Sample => ({
    ts: r.ts, lifetimeUsd: r.lifetime_usd, todayUsd: r.today_usd, adId: r.ad_id, kill: !!r.kill,
    active: r.active == null ? null : !!r.active,
    capScope: r.cap_scope ?? null,
    capUsd: r.cap_usd ?? null,
    capResetS: r.cap_reset_s ?? null,
  });
  return {
    insertSample(s) {
      db.run(
        "INSERT OR REPLACE INTO samples (ts, lifetime_usd, today_usd, ad_id, kill, active, cap_scope, cap_usd, cap_reset_s) VALUES (?,?,?,?,?,?,?,?,?)",
        [s.ts, s.lifetimeUsd, s.todayUsd, s.adId, s.kill ? 1 : 0,
          s.active == null ? null : s.active ? 1 : 0, s.capScope ?? null, s.capUsd ?? null, s.capResetS ?? null],
      );
    },
    latest() {
      const r = db.query("SELECT * FROM samples ORDER BY ts DESC LIMIT 1").get() as any;
      return r ? rowToSample(r) : null;
    },
    recentSince(ts) {
      return (db.query("SELECT * FROM samples WHERE ts >= ? ORDER BY ts ASC").all(ts) as any[]).map(rowToSample);
    },
    getState(key) { const r = db.query("SELECT value FROM kv WHERE key=?").get(key) as any; return r ? r.value : null; },
    setState(key, value) { db.run("INSERT OR REPLACE INTO kv VALUES (?,?)", [key, value]); },
    userVersion() { return readVersion(); },
    close() { db.close(); },
  };
}
