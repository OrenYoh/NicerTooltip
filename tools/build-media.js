// Builds the in-game textures in media/ from the source artwork in src/,
// and writes Media.lua with the measurements the addon needs.
//
//   cd tools && npm install && npm run build
//
// What it does:
// - logos: the Alliance and Horde icons from src/icons, trimmed and squared.
// - separator (one for all themes): the generated art has a semi-opaque grey "fake
//   transparency" box around it. Everything connected to the image border
//   through low-chroma (grey) pixels is keyed out; dark greys are kept as a
//   soft black shadow, light greys become fully transparent.
// - backgrounds: cropped to their fully opaque area (their edges fade into
//   the same grey haze); their left and bottom edges are faded into a flat
//   colour, so the art can sit in a corner of any size of tooltip, the rest
//   being filled with that colour.
// - frame: sliced into a small 9-slice atlas (top-left corner, top edge,
//   left edge; the other corners/edges are mirrored in Lua) and a 3-slice
//   healthbar slot.

const sharp = require("sharp");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const SRC = path.join(ROOT, "src");
const OUT = path.join(ROOT, "media");
const THEMES = ["alliance", "horde", "neutral", "creature_ally", "creature_enemy", "creature_neutral"];
// Background-only themes (no logo or separator).
const BG_THEMES = [...THEMES, "dead", "spell", "item", "herb", "mineral", "buff", "debuff"];

// Logos (faction only). clearTop: rows to blank at the top of the source.
const LOGOS = {
  alliance: {},
  horde: { clearTop: 12 },
};

// Per-theme background overrides:
// - file: source file in src/backgrounds (default background_<theme>.png)
// - crop: [x, y, w, h] of the clean art, for images whose "transparency" is
//   a painted checkerboard (no alpha channel); otherwise the crop is detected
// - fadeLeft: share of the width faded into the fill colour from the left
// - fadeBottom: where (share of the height) the fade to the bottom starts
const BACKGROUNDS = {
  alliance: { file: "background_alliance2.png", crop: [520, 0, 1016, 620], fadeLeft: 0.35, fadeBottom: 0.8 },
  horde: { file: "background_horde2.png", crop: [440, 0, 1096, 640], fadeLeft: 0.35, fadeBottom: 0.82 },
  creature_enemy: { file: "background_enemies2.png", crop: [340, 0, 1196, 640], fadeLeft: 0.35, fadeBottom: 0.78 },
  creature_ally: { file: "background_allies.png", crop: [300, 0, 1236, 640], fadeLeft: 0.35, fadeBottom: 0.8 },
  creature_neutral: { file: "background_neutral2.png", crop: [300, 0, 1236, 640], fadeLeft: 0.35, fadeBottom: 0.8 },
  neutral: { file: "background_neutral2.png", crop: [300, 0, 1236, 640], fadeLeft: 0.35, fadeBottom: 0.8 },
  dead: { crop: [360, 0, 1176, 660], fadeLeft: 0.35, fadeBottom: 0.78 },
  spell: { file: "background_spells.png", crop: [300, 0, 1236, 640], fadeLeft: 0.35, fadeBottom: 0.8 },
  item: { file: "background_items.png", crop: [300, 0, 1236, 640], fadeLeft: 0.35, fadeBottom: 0.8 },
  herb: { file: "background_herbs.png", crop: [300, 0, 1236, 640], fadeLeft: 0.35, fadeBottom: 0.8 },
  mineral: { file: "background_minerals.png", crop: [300, 0, 1236, 640], fadeLeft: 0.35, fadeBottom: 0.8 },
  buff: { file: "background_buffs.png", crop: [300, 0, 1236, 640], fadeLeft: 0.35, fadeBottom: 0.8 },
  debuff: { file: "background_debuffs.png", crop: [300, 0, 1236, 640], fadeLeft: 0.35, fadeBottom: 0.8 },
};

async function load(file) {
  const { data, info } = await sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  return { data, W: info.width, H: info.height };
}

function save(img, file) {
  return sharp(img.data, { raw: { width: img.W, height: img.H, channels: 4 } }).png({ compressionLevel: 9 }).toFile(file);
}

function crop(img, x, y, w, h) {
  const data = Buffer.alloc(w * h * 4);
  for (let j = 0; j < h; j++) img.data.copy(data, j * w * 4, ((y + j) * img.W + x) * 4, ((y + j) * img.W + x + w) * 4);
  return { data, W: w, H: h };
}

async function resize(img, w, h) {
  const { data, info } = await sharp(img.data, { raw: { width: img.W, height: img.H, channels: 4 } })
    .resize(w, h, { fit: "fill", kernel: "lanczos3" }).raw().toBuffer({ resolveWithObject: true });
  return { data, W: info.width, H: info.height };
}

// Paste img into a transparent canvas of size w x h at (x, y).
function canvas(w, h, pieces) {
  const data = Buffer.alloc(w * h * 4);
  for (const [img, x, y] of pieces)
    for (let j = 0; j < img.H; j++) img.data.copy(data, ((y + j) * w + x) * 4, j * img.W * 4, (j + 1) * img.W * 4);
  return { data, W: w, H: h };
}

const smooth = (e0, e1, v) => { const t = Math.min(1, Math.max(0, (v - e0) / (e1 - e0))); return t * t * (3 - 2 * t); };

function removeHaze(img) {
  const { data, W, H } = img;
  const chroma = (i) => Math.max(data[i], data[i + 1], data[i + 2]) - Math.min(data[i], data[i + 1], data[i + 2]);
  const lum = (i) => 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];

  // Matte colour: average of the border pixels.
  let mL = 0, n = 0;
  for (let x = 0; x < W; x++) for (const y of [0, H - 1]) { mL += lum((y * W + x) * 4); n++; }
  for (let y = 0; y < H; y++) for (const x of [0, W - 1]) { mL += lum((y * W + x) * 4); n++; }
  mL /= n;

  // Flood fill from the border through grey pixels.
  const C0 = 22, C1 = 48;
  const seen = new Uint8Array(W * H);
  const stack = [];
  const push = (x, y) => { const p = y * W + x; if (!seen[p] && chroma(p * 4) < C1) { seen[p] = 1; stack.push(p); } };
  for (let x = 0; x < W; x++) { push(x, 0); push(x, H - 1); }
  for (let y = 0; y < H; y++) { push(0, y); push(W - 1, y); }
  while (stack.length) {
    const p = stack.pop(), x = p % W, y = (p / W) | 0;
    if (x > 0) push(x - 1, y); if (x < W - 1) push(x + 1, y);
    if (y > 0) push(x, y - 1); if (y < H - 1) push(x, y + 1);
  }

  for (let p = 0; p < W * H; p++) {
    if (!seen[p]) continue;
    const i = p * 4, a = data[i + 3];
    const keep = smooth(C0, C1, chroma(i)); // 0 = pure grey haze/shadow, 1 = real art
    const shadowA = a * Math.min(1, Math.max(0, 1 - lum(i) / mL)) * 0.9;
    const outA = shadowA * (1 - keep) + a * keep;
    const f = outA > 0 ? (a * keep) / outA : 0; // share of the original colour
    for (let c = 0; c < 3; c++) data[i + c] = Math.round(data[i + c] * f);
    data[i + 3] = outA < 6 ? 0 : Math.round(outA);
  }
  return img;
}

function bbox(img, test) {
  let x0 = img.W, y0 = img.H, x1 = -1, y1 = -1;
  for (let y = 0; y < img.H; y++) for (let x = 0; x < img.W; x++)
    if (test((y * img.W + x) * 4)) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
  return { x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1 };
}

const r3 = (v) => Math.round(v * 1000) / 1000;

(async () => {
  const meta = { backgrounds: {} };

  // ---------------------------------------------------------------- logos
  // Faction logos only, from src/icons (real transparency, no haze).
  for (const [t, cfg] of Object.entries(LOGOS)) {
    const img = await load(path.join(SRC, "icons", `icon_${t}.png`));
    // Blank rows that hold stray content (e.g. text left from a screenshot).
    for (let y = 0; y < (cfg.clearTop || 0); y++) img.data.fill(0, y * img.W * 4, (y + 1) * img.W * 4);
    const b = bbox(img, (i) => img.data[i + 3] > 24);
    const side = Math.max(b.w, b.h);
    const sq = canvas(side, side, [[crop(img, b.x, b.y, b.w, b.h), ((side - b.w) / 2) | 0, ((side - b.h) / 2) | 0]]);
    await save(await resize(sq, 64, 64), path.join(OUT, `logo_${t}.png`));
  }

  // ----------------------------------------------------------- separators
  // One separator for every theme.
  {
    const img = removeHaze(await load(path.join(SRC, "separators", "separator_alliance.png")));
    const b = bbox(img, (i) => img.data[i + 3] > 24);
    const c = crop(img, b.x, b.y, b.w, b.h);
    // Medallion columns: much more opaque material than the thin line.
    const col = [];
    for (let x = 0; x < c.W; x++) { let s = 0; for (let y = 0; y < c.H; y++) s += c.data[(y * c.W + x) * 4 + 3]; col.push(s); }
    const sorted = [...col].sort((a, b) => a - b), median = sorted[sorted.length >> 1];
    const mid = c.W >> 1;
    let l = mid, r = mid;
    while (l > 0 && col[l - 1] > median * 2.2) l--;
    while (r < c.W - 1 && col[r + 1] > median * 2.2) r++;
    const pad = 2; l = Math.max(0, l - pad); r = Math.min(c.W - 1, r + pad);
    // 256 x 64 texture, separator scaled to 256 wide, vertically centred.
    const h = Math.round(c.H * 256 / c.W);
    const sc = await resize(c, 256, h);
    await save(canvas(256, 64, [[sc, 0, (64 - h) >> 1]]), path.join(OUT, "separator.png"));
    meta.separator = { top: r3(((64 - h) >> 1) / 64), bottom: r3((((64 - h) >> 1) + h) / 64), left: r3(l / c.W), right: r3((r + 1) / c.W), aspect: r3(256 / h), medallion: r3((r + 1 - l) / c.W) };
  }

  // ---------------------------------------------------------- backgrounds
  for (const t of BG_THEMES) {
    const cfg = BACKGROUNDS[t] || {};
    const img = await load(path.join(SRC, "backgrounds", cfg.file || `background_${t}.png`));
    const fadeLeft = cfg.fadeLeft || 0.4, fadeBottom = cfg.fadeBottom || 0.55;
    // The panels fade into a light grey rim (low alpha, high luminance).
    // Columns/rows are kept once they are opaque and no brighter than the
    // middle of the image (sampled over the middle half).
    const px = (x, y) => (y * img.W + x) * 4;
    const lum = (i) => 0.299 * img.data[i] + 0.587 * img.data[i + 1] + 0.114 * img.data[i + 2];
    const stats = (xs, ys) => { let L = 0, A = 0, n = 0; for (const y of ys) for (const x of xs) { const i = px(x, y); L += lum(i); A += img.data[i + 3]; n++; } return { L: L / n, A: A / n }; };
    const range = (a, b) => Array.from({ length: b - a }, (_, k) => a + k);
    const midX = range(img.W >> 2, (img.W * 3) >> 2), midY = range(img.H >> 2, (img.H * 3) >> 2);
    const core = stats(midX, midY);
    const ok = (s) => s.A >= 240 && s.L <= core.L * 1.12;
    let x0 = 0, x1 = img.W - 1, y0 = 0, y1 = img.H - 1;
    while (x0 < img.W >> 2 && !ok(stats([x0], midY))) x0++;
    while (x1 > (img.W * 3) >> 2 && !ok(stats([x1], midY))) x1--;
    while (y0 < img.H >> 2 && !ok(stats(midX, [y0]))) y0++;
    while (y1 > (img.H * 3) >> 2 && !ok(stats(midX, [y1]))) y1--;
    x0 += 2; x1 -= 2; y0 += 2; y1 -= 2;
    const c = cfg.crop ? crop(img, ...cfg.crop) : crop(img, x0, y0, x1 - x0 + 1, y1 - y0 + 1);
    // Fill colour: average of the whole panel, a bit darker so the art stands out.
    let R = 0, G = 0, B = 0, n = 0;
    for (let i = 0; i < c.data.length; i += 4) { R += c.data[i]; G += c.data[i + 1]; B += c.data[i + 2]; n++; }
    R = R / n * 0.85; G = G / n * 0.85; B = B / n * 0.85;
    // The art sits in the top-right corner of the tooltip: fade its left and
    // bottom edges into the fill colour (the tooltip is filled with it
    // everywhere else), force full opacity.
    for (let y = 0; y < c.H; y++) {
      const fy = smooth(fadeBottom, 1, y / (c.H - 1));
      for (let x = 0; x < c.W; x++) {
        const f = Math.max(fy, smooth(fadeLeft, 0, x / (c.W - 1)));
        const i = (y * c.W + x) * 4;
        c.data[i] = Math.round(c.data[i] * (1 - f) + R * f);
        c.data[i + 1] = Math.round(c.data[i + 1] * (1 - f) + G * f);
        c.data[i + 2] = Math.round(c.data[i + 2] * (1 - f) + B * f);
        c.data[i + 3] = 255;
      }
    }
    await save(await resize(c, 512, 256), path.join(OUT, `background_${t}.png`));
    meta.backgrounds[t] = { aspect: r3(c.W / c.H), fill: [r3(R / 255), r3(G / 255), r3(B / 255)] };
  }

  // ---------------------------------------------------------------- frame
  {
    const img = await load(path.join(SRC, "frames", "frame_universal_healthbar_slot.png"));
    // Source measurements (1622x800): border outer edge at x=10/y=11,
    // border ~29px thick, corner ornaments fit in 160x160. The box ends at
    // y=697, the healthbar slot runs from y=697 to the bottom.
    const corner = await resize(crop(img, 0, 0, 160, 160), 64, 64);
    const top = await resize(crop(img, 500, 0, 80, 160), 32, 64);
    const left = await resize(crop(img, 0, 300, 160, 80), 64, 32);
    await save(canvas(128, 128, [[corner, 0, 0], [top, 64, 0], [left, 0, 64]]), path.join(OUT, "frame.png"));

    const capSrc = crop(img, 0, 697, 80, 100), midSrc = crop(img, 500, 697, 80, 100);
    const cap = await resize(capSrc, 32, 40), midP = await resize(midSrc, 32, 40);
    await save(canvas(64, 64, [[cap, 0, 0], [midP, 32, 0]]), path.join(OUT, "slot.png"));
    // Inner (transparent) area of the slot in source: x>=41, y 716..769.
    meta.slot = { height: r3(40 / 64), innerLeft: r3(41 / 80), innerTop: r3((716 - 697) / 100), innerBottom: r3((769 - 697) / 100) };
    meta.frame = { border: r3(30 / 160) }; // border thickness relative to the corner size
  }

  // ------------------------------------------------------------- Media.lua
  const lua = [];
  lua.push("-- Generated by tools/build-media.js, do not edit by hand.", "local _, ns = ...", "", "ns.Media = {");
  lua.push(`  frame = { border = ${meta.frame.border} },`);
  lua.push(`  slot = { height = ${meta.slot.height}, innerLeft = ${meta.slot.innerLeft}, innerTop = ${meta.slot.innerTop}, innerBottom = ${meta.slot.innerBottom} },`);
  lua.push("  backgrounds = {");
  for (const t of BG_THEMES) { const m = meta.backgrounds[t]; lua.push(`    ${t} = { aspect = ${m.aspect}, fill = { ${m.fill.join(", ")} } },`); }
  const m = meta.separator;
  lua.push("  },", `  separator = { top = ${m.top}, bottom = ${m.bottom}, left = ${m.left}, right = ${m.right}, aspect = ${m.aspect}, medallion = ${m.medallion} },`);
  lua.push("}", "");
  fs.writeFileSync(path.join(ROOT, "Media.lua"), lua.join("\n"));
  console.log(JSON.stringify(meta, null, 1));
})();
