import { readdirSync, statSync, type Dirent } from "node:fs";
import { join } from "node:path";

/** Newest mtime (unix ms) of any file under `dir`, recursing a few levels; 0 if
 *  unreadable/empty. */
function newestMtime(dir: string, depth = 3): number {
  let newest = 0;
  let entries: Dirent[] = [];
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return 0; }
  for (const e of entries) {
    const p = join(dir, e.name);
    try {
      if (e.isDirectory()) { if (depth > 0) newest = Math.max(newest, newestMtime(p, depth - 1)); }
      else newest = Math.max(newest, statSync(p).mtimeMs);
    } catch { /* skip unreadable entries */ }
  }
  return newest;
}

/** True if any file under any dir was modified within `windowMs` before `now` — a
 *  heuristic for "the user is actively coding" (editor transcript writes). Fail-safe:
 *  unsure → false, so the stall watchdog never raises a false alarm. The small forward
 *  tolerance absorbs clock skew between the file mtime and `now`. */
export function isActive(dirs: string[], now: number, windowMs: number): boolean {
  return dirs.some((d) => {
    const m = newestMtime(d);
    return m > 0 && m >= now - windowMs && m <= now + 60_000;
  });
}
