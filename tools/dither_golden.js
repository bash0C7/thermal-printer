const W = 368;
const H = 32;

const CASES = {
  neutral: { bri: 0, con: 1, gam: 1 },
  adjusted: { bri: 20, con: 1.3, gam: 0.8 },
};

function synthetic(x, y) {
  return Math.floor((x * 223) / 383) + Math.abs((y * 9) % 64 - 32);
}

function adjust(bri, con, gam) {
  const v = new Float32Array(W * H);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      let l = synthetic(x, y);
      l = 255 * Math.pow(l / 255, gam);
      l = (l - 128) * con + 128 + bri;
      v[y * W + x] = l;
    }
  }
  return v;
}

function diffuse(v0, h, kernel, div) {
  const v = Float32Array.from(v0);
  const out = new Uint8Array(W * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < W; x++) {
    const i = y * W + x;
    const o = v[i] < 128 ? 0 : 255;
    out[i] = o === 0 ? 1 : 0;
    const err = (v[i] - o) / div;
    for (const [dx, dy, w] of kernel) {
      const xx = x + dx, yy = y + dy;
      if (xx >= 0 && xx < W && yy < h) v[yy * W + xx] += err * w;
    }
  }
  return out;
}

function hexRows(bits) {
  const rows = [];
  for (let y = 0; y < H; y++) {
    let hex = "";
    for (let b = 0; b < 48; b++) {
      let byte = 0;
      for (let k = 0; k < 8; k++) { const x = b * 8 + k; byte = (byte << 1) | (x < W ? bits[y * W + x] : 0); }
      hex += byte.toString(16).padStart(2, "0");
    }
    rows.push(hex);
  }
  return rows;
}

const name = process.argv[2];
const c = CASES[name];
if (!c) {
  process.stderr.write("usage: node tools/dither_golden.js " + Object.keys(CASES).join("|") + "\n");
  process.exit(2);
}
const bits = diffuse(adjust(c.bri, c.con, c.gam), H, [[1, 0, 7], [-1, 1, 3], [0, 1, 5], [1, 1, 1]], 16);
process.stdout.write(hexRows(bits).join("\n") + "\n");
