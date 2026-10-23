"""Post-processing for the rendered planets + contact sheet (package art-planets).

Run with the system python3 (numpy + PIL):
    python3 tools/blender/planets_post.py <workdir> [planet ...] [--out=DIR] [--sheet-only]

Reads <workdir>/render/<planet>.npy (linear, premultiplied RGBA float, rows top-down, sphere centred,
radius SPHERE_RADIUS_PX), adds the atmosphere rim/haze analytically, tone-maps to sRGB, crops to the
content (portrait crops are padded to a square canvas, SPEC §16.3) and writes
<out>/<planet>.png (RGBA, straight alpha) + <planet>.json {"sphere_diameter_px": D, "center": [x, y]}.
Afterwards a contact sheet (planets at 174 and 600 px, ground strips at 1x) is built from the
planets in <out>: for the default output (game/assets/sprites/planets) it is
docs/previews/planets_sheet.png (+ docs/previews/planets_mock.png); with --out=DIR it is written to
DIR/planets_sheet.png and the project previews stay untouched.
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from planets_config import LIGHT_DIR, PLANETS, SPHERE_RADIUS_PX  # noqa: E402
from planets_noise import linear_to_srgb, smoothstep  # noqa: E402

OUT_DEFAULT = os.path.join(ROOT, "game", "assets", "sprites", "planets")
GROUND_DIR = os.path.join(ROOT, "game", "assets", "sprites", "ground")
SHEET = os.path.join(ROOT, "docs", "previews", "planets_sheet.png")
ORDER = ["neptune", "uranus", "saturn", "jupiter", "mars", "earth"]


def light_image_space():
	"""LIGHT_DIR (Blender: x right, y away, z up) -> image space (x right, y down, z towards viewer)."""
	x, y, z = LIGHT_DIR
	v = np.array([x, -z, -y], np.float64)
	return v / np.linalg.norm(v)


def tonemap(x):
	"""Linear -> display linear with a soft shoulder above 0.8 (no hard clipping of highlights)."""
	k = 0.8
	return np.where(x <= k, x, k + (1 - k) * (1 - np.exp(-(x - k) / (1 - k))))


def process(name: str, work: str, out_dir: str) -> None:
	cfg = PLANETS[name]
	a = np.load(os.path.join(work, "render", f"{name}.npy")).astype(np.float64)
	h, w = a.shape[:2]
	R = float(SPHERE_RADIUS_PX)
	cx, cy = w / 2.0, h / 2.0
	yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
	dx = (xx + 0.5 - cx) / R
	dy = (yy + 0.5 - cy) / R
	r = np.sqrt(dx * dx + dy * dy)
	L = light_image_space()
	at = cfg["atmo"]
	col = np.array(at["color"], np.float64)
	# limb normal (outside) / surface normal (inside)
	rr = np.maximum(r, 1e-6)
	mu = np.sqrt(np.clip(1.0 - r * r, 0.0, 1.0))
	nl_out = (dx / rr) * L[0] + (dy / rr) * L[1]
	nl_in = dx * L[0] + dy * L[1] + mu * L[2]
	lit_out = smoothstep(-0.30, 0.55, nl_out)
	lit_in = smoothstep(-0.15, 0.45, nl_in)
	width = at["width"]
	# outer glow: exponential fall-off from the limb, only where the limb is lit
	g_out = at["outer"] * np.exp(-np.maximum(r - 1.0, 0.0) / width) * lit_out * (r >= 1.0 - 1.5 / R)
	g_out *= smoothstep(1.0 - 1.5 / R, 1.0 + 0.5 / R, r)   # fade in across the anti-aliased edge
	# inner haze: grows towards the limb (long path through the atmosphere)
	g_in = at["inner"] * np.exp(-mu / at["inner_width"]) * lit_in * (r < 1.0)
	rgb = a[..., :3].copy()
	alpha = a[..., 3].copy()
	# inner haze is added on top of the (premultiplied) planet colour
	rgb += col[None, None, :] * (g_in * alpha)[..., None]
	# outer glow lies behind the planet (and rings): composite under
	g = np.clip(g_out, 0.0, 1.0)
	rgb = rgb + col[None, None, :] * (g * (1.0 - alpha))[..., None]
	alpha = alpha + g * (1.0 - alpha)
	# straight colour, tone map, sRGB
	straight = rgb / np.maximum(alpha, 1e-6)[..., None]
	straight = linear_to_srgb(tonemap(straight))
	alpha = np.clip(alpha, 0.0, 1.0)
	straight[alpha <= 0.0] = 0.0
	# crop to content (+ margin)
	ys, xs = np.where(alpha > 1.0 / 255.0)
	m = 4
	x0, x1 = max(0, xs.min() - m), min(w, xs.max() + 1 + m)
	y0, y1 = max(0, ys.min() - m), min(h, ys.max() + 1 + m)
	img = np.concatenate([straight, alpha[..., None]], axis=2)[y0:y1, x0:x1]
	# SPEC §16.3: "square or wide canvas" -> a portrait crop (strongly tilted rings, e.g. Uranus) is
	# padded with transparent columns on both sides; the sphere centre moves along.
	pad_l = 0
	if img.shape[0] > img.shape[1]:
		pad = img.shape[0] - img.shape[1]
		pad_l = pad // 2
		img = np.pad(img, ((0, 0), (pad_l, pad - pad_l), (0, 0)))
	rng = np.random.default_rng(11)
	u8 = np.clip(np.round(img * 255.0 + rng.uniform(-0.5, 0.5, img.shape) * (img[..., 3:4] > 0)), 0, 255).astype(np.uint8)
	u8[..., 3] = np.clip(np.round(img[..., 3] * 255.0), 0, 255).astype(np.uint8)
	u8[u8[..., 3] == 0, :3] = 0
	from PIL import Image
	os.makedirs(out_dir, exist_ok=True)
	Image.fromarray(u8, "RGBA").save(os.path.join(out_dir, f"{name}.png"), optimize=True)
	meta = {"sphere_diameter_px": int(round(2 * R)), "center": [float(round(cx - x0 + pad_l, 2)), float(round(cy - y0, 2))]}
	with open(os.path.join(out_dir, f"{name}.json"), "w") as f:
		json.dump(meta, f)
		f.write("\n")
	print(f"[planets_post] {name}: {img.shape[1]}x{img.shape[0]} px, {meta}", flush=True)


# ------------------------------------------------------------------------------------------------
# contact sheet
# ------------------------------------------------------------------------------------------------
def _scaled_planet(name: str, diameter: float, src_dir: str):
	from PIL import Image
	img = Image.open(os.path.join(src_dir, f"{name}.png")).convert("RGBA")
	with open(os.path.join(src_dir, f"{name}.json")) as f:
		meta = json.load(f)
	k = diameter / float(meta["sphere_diameter_px"])
	size = (max(1, round(img.width * k)), max(1, round(img.height * k)))
	pm = img.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
	c = meta["center"]
	return pm, (c[0] * k, c[1] * k)


def _space_bg(w: int, h: int, seed: int = 3):
	from PIL import Image
	rng = np.random.default_rng(seed)
	bg = np.zeros((h, w, 3), np.float64)
	bg[:] = np.array([4, 6, 14]) / 255.0
	n = w * h // 900
	ys = rng.integers(0, h, n)
	xs = rng.integers(0, w, n)
	b = rng.uniform(0.15, 0.8, n) ** 2
	bg[ys, xs] += b[:, None] * np.array([0.9, 0.95, 1.0])
	return Image.fromarray((np.clip(bg, 0, 1) * 255).astype(np.uint8), "RGB").convert("RGBA")


def build_sheet(src_dir: str = OUT_DEFAULT, path: str = SHEET) -> None:
	from PIL import Image, ImageDraw
	planets = [p for p in ORDER if os.path.exists(os.path.join(src_dir, f"{p}.png"))]
	grounds = [p for p in ORDER if os.path.exists(os.path.join(GROUND_DIR, f"{p}.png"))]
	W = 1920
	pad = 16
	def trimmed(p, d):
		# drop transparent canvas margins (e.g. the square padding of Uranus) for a compact layout
		im, (cxp, cyp) = _scaled_planet(p, d, src_dir)
		bb = im.getchannel("A").getbbox() or (0, 0, im.width, im.height)
		return im.crop(bb), (cxp - bb[0], cyp - bb[1])

	small = [(p,) + trimmed(p, 174.0) for p in planets]
	big = [(p,) + trimmed(p, 600.0) for p in planets]
	# layout: row of small planets, rows of big ones (wrapped), then ground strips
	h_small = max([im.height for _, im, _ in small] + [0]) + 2 * pad + 20
	rows = []
	cur, cur_w = [], pad
	for item in big:
		iw = item[1].width
		if cur and cur_w + iw + pad > W:
			rows.append(cur)
			cur, cur_w = [], pad
		cur.append(item)
		cur_w += iw + pad
	if cur:
		rows.append(cur)
	h_big = sum(max(it[1].height for it in row) + pad + 20 for row in rows)
	h_ground = len(grounds) * (70 + 28) + pad
	H = 30 + h_small + h_big + h_ground + pad
	sheet = _space_bg(W, H)
	dr = ImageDraw.Draw(sheet)
	y = 8
	dr.text((pad, y), "planets at 174 px sphere diameter (zoom stage 1)", fill=(200, 210, 230, 255))
	y += 22
	x = pad
	for name, im, (cxp, cyp) in small:
		sheet.alpha_composite(im, (int(x), int(y + pad)))
		dr.text((x, y + pad + im.height + 2), name, fill=(170, 180, 200, 255))
		x += im.width + 2 * pad
	y += h_small
	dr.text((pad, y - 14), "planets at 600 px sphere diameter (arrival zoom)", fill=(200, 210, 230, 255))
	for row in rows:
		x = pad
		rh = max(it[1].height for it in row)
		for name, im, _ in row:
			sheet.alpha_composite(im, (int(x), int(y + (rh - im.height) // 2)))
			dr.text((x, y + rh + 2), name, fill=(170, 180, 200, 255))
			x += im.width + pad
		y += rh + pad + 20
	for g in grounds:
		dr.text((pad, y + 4), f"ground/{g}.png (1x, 1920x70)", fill=(200, 210, 230, 255))
		gi = Image.open(os.path.join(GROUND_DIR, f"{g}.png")).convert("RGBA")
		sheet.alpha_composite(gi, (0, y + 22))
		y += 70 + 28
	os.makedirs(os.path.dirname(path), exist_ok=True)
	sheet.convert("RGB").save(path, optimize=True)
	print(f"[planets_post] contact sheet {W}x{H} -> {path}", flush=True)


def build_mocks(src_dir: str = OUT_DEFAULT, path: str = os.path.join(ROOT, "docs", "previews", "planets_mock.png")) -> None:
	"""Rough in-game impression: 960x720 screens with the planet top right (stage 1/3) and the ground strip."""
	from PIL import Image, ImageDraw
	tiles = []
	for i, p in enumerate(ORDER):
		if not os.path.exists(os.path.join(src_dir, f"{p}.png")):
			continue
		scr = _space_bg(960, 720, seed=20 + i)
		stage_d = 174.0 if i % 2 == 0 else 174.0 * 275.0 / 192.0
		im, (cx, cy) = _scaled_planet(p, stage_d, src_dir)
		scr.alpha_composite(im, (int(round(800 - cx)), int(round(150 - cy))))
		gp = os.path.join(GROUND_DIR, f"{p}.png")
		if os.path.exists(gp):
			g = Image.open(gp).convert("RGBA").resize((960, 35), Image.LANCZOS)
			scr.alpha_composite(g, (0, 685))
		ImageDraw.Draw(scr).text((12, 8), f"{p} (sphere {stage_d:.0f} px)", fill=(200, 210, 230, 255))
		tiles.append(scr)
	if not tiles:
		return
	sheet = Image.new("RGBA", (960 * 2, 720 * ((len(tiles) + 1) // 2)), (0, 0, 0, 255))
	for k, t in enumerate(tiles):
		sheet.alpha_composite(t, ((k % 2) * 960, (k // 2) * 720))
	sheet.convert("RGB").save(path, optimize=True)
	print(f"[planets_post] mock screens -> {path}", flush=True)


if __name__ == "__main__":
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	opts = {a.split("=")[0]: (a.split("=", 1)[1] if "=" in a else True) for a in sys.argv[1:] if a.startswith("--")}
	out = os.path.realpath(str(opts.get("--out", OUT_DEFAULT)))
	if not opts.get("--sheet-only"):
		work = args[0]
		for p in args[1:] or ORDER:
			process(p, work, out)
	if out == os.path.realpath(OUT_DEFAULT):
		# only a build into the game assets refreshes the project previews
		build_sheet(out, SHEET)
		build_mocks(out)
	else:
		# trial / scratch builds (--out=DIR) never touch docs/previews: their sheet goes next to them
		build_sheet(out, os.path.join(out, "planets_sheet.png"))
