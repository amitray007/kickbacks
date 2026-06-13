import { writeFileSync, rmSync, existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const xmlEscape = (s: string): string =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/** A launchd user-agent plist that runs `<binPath> poll` every `seconds`. Pure.
 *  Interpolated values are XML-escaped (paths may legally contain `&`). */
export function plistContent(label: string, binPath: string, seconds: number): string {
  const logPath = join(homedir(), "Library/Logs", label + ".log");
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${xmlEscape(label)}</string>
  <key>ProgramArguments</key><array><string>${xmlEscape(binPath)}</string><string>poll</string></array>
  <key>StartInterval</key><integer>${seconds}</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>${xmlEscape(logPath)}</string>
</dict></plist>
`;
}

const plistPath = (label: string): string => join(homedir(), "Library/LaunchAgents", `${label}.plist`);

/** Write the plist and (re)load it via launchctl. Side-effecting — system change. */
export function installAgent(label: string, binPath: string, seconds: number): string {
  const path = plistPath(label);
  mkdirSync(join(homedir(), "Library/LaunchAgents"), { recursive: true });
  writeFileSync(path, plistContent(label, binPath, seconds));
  spawnSync("launchctl", ["unload", path], { stdio: "ignore" }); // in case it was already loaded
  const r = spawnSync("launchctl", ["load", path], { stdio: "pipe", encoding: "utf8" });
  if (r.status !== 0) throw new Error(`launchctl load failed: ${(r.stderr || "").trim() || "unknown error"}`);
  return path;
}

export function uninstallAgent(label: string): void {
  const path = plistPath(label);
  spawnSync("launchctl", ["unload", path], { stdio: "ignore" });
  try { rmSync(path); } catch { /* already gone */ }
}

export function agentInstalled(label: string): boolean {
  return existsSync(plistPath(label));
}
