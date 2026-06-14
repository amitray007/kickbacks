// Parametric generator for the Kickback app icon.
// Emits AppIcon.svg (source of truth) + an .iconset of PNGs (for iconutil).
// Run via scripts/gen-icon.sh (which provides the @resvg/resvg-js rasterizer).
//   bun run gen-icon.ts <svgOutDir> <iconsetDir>
//
// Design: a bright emerald squircle (Kickbacks.ai colour family) with a white
// "cashback" mark — a circular arrow hugging a coin (the literal meaning of a
// kickback). Original artwork: same colour family as Kickbacks.ai, deliberately
// NOT their "K$" lettermark — a companion, not the brand itself.
import { Resvg } from "@resvg/resvg-js";
import { writeFileSync, mkdirSync, rmSync } from "fs";

const SIZE = 1024;
const C = SIZE / 2;

// Cashback glyph: circular arrow (opening at top) around a centred coin.
const R = 168;   // ring centerline radius
const SW = 52;   // ring stroke width
const GAP = 60;  // angular opening at top (deg)
const TOP = 270; // straight up (y-down)

const rad = (d: number) => (d * Math.PI) / 180;
const P = (deg: number, r = R) => [C + r * Math.cos(rad(deg)), C + r * Math.sin(rad(deg))] as const;
const f = (n: number) => n.toFixed(1);

const [tx, ty] = P(TOP + GAP / 2); // round-cap tail (upper-right)
const [hx, hy] = P(TOP - GAP / 2); // arrowhead (upper-left)
const arc = `M ${f(tx)} ${f(ty)} A ${R} ${R} 0 1 1 ${f(hx)} ${f(hy)}`; // large, clockwise

const t = rad(TOP - GAP / 2);
const T = [-Math.sin(t), Math.cos(t)] as const; // unit tangent (clockwise)
const N = [-T[1], T[0]] as const;
const AH_LEN = 96, AH_HALF = 58, AH_BACK = 14;
const tip = [hx + T[0] * AH_LEN, hy + T[1] * AH_LEN];
const bc = [hx - T[0] * AH_BACK, hy - T[1] * AH_BACK];
const a1 = [bc[0] + N[0] * AH_HALF, bc[1] + N[1] * AH_HALF];
const a2 = [bc[0] - N[0] * AH_HALF, bc[1] - N[1] * AH_HALF];
const arrow = `${f(tip[0])},${f(tip[1])} ${f(a1[0])},${f(a1[1])} ${f(a2[0])},${f(a2[1])}`;

const COIN_R = 112, RIM_R = 80;

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}">
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0" stop-color="#4ECB72"/>
      <stop offset="1" stop-color="#2A9450"/>
    </linearGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.18"/>
      <stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <rect x="80" y="80" width="864" height="864" rx="200" ry="200" fill="url(#tile)"/>
  <rect x="80" y="80" width="864" height="864" rx="200" ry="200" fill="url(#sheen)"/>
  <rect x="81.5" y="81.5" width="861" height="861" rx="198" ry="198" fill="none" stroke="#ffffff" stroke-opacity="0.10" stroke-width="3"/>
  <path d="${arc}" fill="none" stroke="#ffffff" stroke-width="${SW}" stroke-linecap="round"/>
  <polygon points="${arrow}" fill="#ffffff"/>
  <circle cx="${C}" cy="${C}" r="${COIN_R}" fill="#ffffff"/>
  <circle cx="${C}" cy="${C}" r="${RIM_R}" fill="none" stroke="#2A9450" stroke-opacity="0.5" stroke-width="9"/>
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
