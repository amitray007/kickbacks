// Parametric generator for the Kickbacks app icon.
// Emits AppIcon.svg (source of truth) + an .iconset of PNGs (for iconutil).
// Run via scripts/gen-icon.sh (which provides the @resvg/resvg-js rasterizer).
//   bun run gen-icon.ts <svgOutDir> <iconsetDir>
//
// Design: a macOS-ready version of the Kickbacks.ai mark: the public green
// gradient tile with a bold white "K$" lettermark, plus subtle app-icon depth.
import { Resvg } from "@resvg/resvg-js";
import { writeFileSync, mkdirSync, rmSync } from "fs";

const SIZE = 1024;
const C = SIZE / 2;

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}">
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#2AA44F"/>
      <stop offset="1" stop-color="#147A34"/>
    </linearGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.24"/>
      <stop offset="0.45" stop-color="#ffffff" stop-opacity="0.04"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <radialGradient id="lift" cx="30%" cy="18%" r="78%">
      <stop offset="0" stop-color="#53D77A" stop-opacity="0.75"/>
      <stop offset="0.55" stop-color="#2AA44F" stop-opacity="0"/>
      <stop offset="1" stop-color="#0B4F22" stop-opacity="0.32"/>
    </radialGradient>
    <filter id="markShadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="16" stdDeviation="14" flood-color="#0A3D1A" flood-opacity="0.22"/>
    </filter>
  </defs>
  <rect x="80" y="80" width="864" height="864" rx="200" ry="200" fill="url(#tile)"/>
  <rect x="80" y="80" width="864" height="864" rx="200" ry="200" fill="url(#lift)"/>
  <rect x="80" y="80" width="864" height="864" rx="200" ry="200" fill="url(#sheen)"/>
  <rect x="81.5" y="81.5" width="861" height="861" rx="198" ry="198" fill="none" stroke="#ffffff" stroke-opacity="0.14" stroke-width="3"/>
  <text x="${C}" y="664" text-anchor="middle"
    font-family="Montserrat, Avenir Next, Arial, sans-serif"
    font-weight="800" font-size="456" letter-spacing="-24"
    fill="#ffffff" filter="url(#markShadow)">K$</text>
</svg>`;

const svgDir = process.argv[2] || ".";
const setDir = process.argv[3] || `${svgDir}/AppIcon.iconset`;
writeFileSync(`${svgDir}/AppIcon.svg`, svg);

rmSync(setDir, { recursive: true, force: true });
mkdirSync(setDir, { recursive: true });
const targets: [string, number][] = [
  ["icon_16x16.png", 16], ["icon_16x16@2x.png", 32],
  ["icon_32x32.png", 32], ["icon_32x32@2x.png", 64],
  ["icon_128x128.png", 128], ["icon_128x128@2x.png", 256],
  ["icon_256x256.png", 256], ["icon_256x256@2x.png", 512],
  ["icon_512x512.png", 512], ["icon_512x512@2x.png", 1024],
];
for (const [name, px] of targets) {
  const r = new Resvg(svg, { fitTo: { mode: "width", value: px } });
  writeFileSync(`${setDir}/${name}`, r.render().asPng());
}
console.log(`wrote ${svgDir}/AppIcon.svg + ${targets.length} pngs -> ${setDir}`);
