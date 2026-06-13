import { spawn } from "node:child_process";

export type Notifier = (title: string, body: string) => void;

/** Fire a macOS notification via osascript. No-op off darwin; best-effort (never throws).
 *  JSON.stringify gives safely-quoted/escaped AppleScript string literals. */
export const notify: Notifier = (title, body) => {
  if (process.platform !== "darwin") return;
  const script = `display notification ${JSON.stringify(body)} with title ${JSON.stringify(title)}`;
  try { spawn("osascript", ["-e", script], { stdio: "ignore", detached: true }).unref(); } catch { /* ignore */ }
};
