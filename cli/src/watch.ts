import { createCliRenderer, TextRenderable, type KeyEvent, type Renderable } from "@opentui/core";
import { buildDashboardTree, type WatchModel } from "./tui";

export interface WatchDeps {
  load: (now: number) => Promise<WatchModel>; // injected: authed fetch + record + derive
  intervalMs: number;
  now: () => number;
}

/** Owns the renderer, the refresh timer, and key input for `kickback watch`. Rebuilds
 *  the tree each refresh (cheap at this cadence). `q`/Ctrl-C quit; `r` refreshes now.
 *  Load errors render inline instead of crashing the terminal. Not unit-tested (needs a
 *  TTY) — the view is covered by buildDashboardTree's snapshot test; this is verified by
 *  a manual run in a real terminal. */
export async function runWatch(d: WatchDeps): Promise<void> {
  const renderer = await createCliRenderer({ exitOnCtrlC: true });
  let current: Renderable | null = null;

  const paint = (build: () => Renderable) => {
    if (current) { renderer.root.remove(current.id); current.destroy(); }
    current = build();
    renderer.root.add(current);
    renderer.requestRender();
  };

  const refresh = async () => {
    try {
      const model = await d.load(d.now());
      paint(() => buildDashboardTree(renderer, model));
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      paint(() => new TextRenderable(renderer, { content: `  ${msg}\n  (press q to quit)`, fg: "#f85149" }));
    }
  };

  renderer.keyInput.on("keypress", (k: KeyEvent) => {
    if (k.name === "q") renderer.destroy();
    else if (k.name === "r") void refresh();
  });

  const timer = setInterval(() => void refresh(), d.intervalMs);
  await refresh(); // initial paint
  // Resolve only once the renderer is destroyed (q / Ctrl-C) so the caller can clean
  // up (e.g. close the store) after the session ends, not while it's still refreshing.
  await new Promise<void>((resolve) => {
    renderer.on("destroy", () => { clearInterval(timer); resolve(); });
  });
}
