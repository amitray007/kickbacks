import { writeFileSync, rmSync, existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

/** A launchd user-agent plist that runs `<binPath> poll` every `seconds`. Pure. */
export function plistContent(label: string, binPath: string, seconds: number): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key><array><string>${binPath}</string><string>poll</string></array>
  <key>StartInterval</key><integer>${seconds}</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>${join(homedir(), "Library/Logs", label + ".log")}</string>
</dict></plist>
`;
}

const plistPath = (label: string): string => join(homedir(), "Library/LaunchAgents", `${label}.plist`);

/** Write the plist and (re)load it via launchctl. Side-effecting — system change. */
export function installAgent(label: string, binPath: string, seconds: number): string {
  const path = plistPath(label);
  mkdirSync(join(homedir(), "Library/LaunchAgents"), { recursive: true });
  writeFileSync(path, plistContent(label, binPath, seconds));
  spawnSync("launchctl", ["unload", path], { stdio: "ignore" }); // in case it was loaded
  spawnSync("launchctl", ["load", path], { stdio: "ignore" });
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
