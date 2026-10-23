"""art-ships post-processing (system python3 with numpy + Pillow + scipy).

Turns the float renders written by ships.py (scene-linear, premultiplied RGBA .npy) into the final
straight-alpha 8-bit PNG assets, and builds the preview contact sheet docs/previews/ships_sheet.png.

    python3 tools/blender/ships_post.py --work=<render dir> [--root=<project root>]

Pipeline per image: hue-preserving tone curve (soft shoulder, very hot emission desaturates to white)
-> down-sampling in linear premultiplied space (Lanczos clamped to each output pixel's source
footprint = no ringing / ghost outline; faint edge pixels take the exact area-average colour)
-> un-premultiply -> sRGB -> 8 bit -> colour bleed into the transparent pixels around the silhouette.
Glow images are additive: rgb * a == glow colour over black (a = max channel).
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

SHIP_KEYS = ["interceptor", "fighter", "double_dart", "double_hunter", "blaster", "hunter"]
SHIP_NAMES = {"interceptor": "INTERCEPTOR", "fighter": "FIGHTER", "double_dart": "DOUBLE DART",
	"double_hunter": "DOUBLE HUNTER", "blaster": "BLASTER", "hunter": "HUNTER"}


# ------------------------------------------------------------------------------------------------
# Colour helpers
# ------------------------------------------------------------------------------------------------
def tonemap(c: np.ndarray, shoulder: float = 0.78, w_start: float = 2.5, w_range: float = 8.0,
		w_max: float = 0.8) -> np.ndarray:
	"""Hue preserving soft shoulder on the max channel. Only really hot emission (max channel above
	w_start) converges towards white, so coloured lights stay saturated."""
	m = c.max(axis=-1, keepdims=True)
	s = shoulder
	m2 = np.where(m > s, s + (1.0 - s) * (1.0 - np.exp(-(m - s) / (1.0 - s))), m)
	out = c * (m2 / np.maximum(m, 1e-6))
	w = np.clip((m - w_start) / w_range, 0.0, 1.0) * w_max
	return out + (m2 - out) * w


def lin_to_srgb(c: np.ndarray) -> np.ndarray:
	c = np.clip(c, 0.0, 1.0)
	return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def srgb_to_lin(c: np.ndarray) -> np.ndarray:
	c = np.clip(c, 0.0, 1.0)
	return np.where(c <= 0.04045, c / 12.92, np.power((c + 0.055) / 1.055, 2.4))


def load(path: str) -> np.ndarray:
	return np.load(path).astype(np.float32)


def tonemap_premult(p: np.ndarray, **kw) -> np.ndarray:
	a = p[..., 3:4]
	c = p[..., :3] / np.maximum(a, 1e-6)
	c = tonemap(c, **kw)
	out = np.concatenate([c * a, a], axis=-1)
	out[..., :3] = np.where(a > 1e-6, out[..., :3], 0.0)
	return out


def resize(p: np.ndarray, w: int, h: int, method=Image.Resampling.LANCZOS, premult_clamp: bool = True) -> np.ndarray:
	chans = []
	for i in range(p.shape[2]):
		im = Image.fromarray(np.ascontiguousarray(p[..., i]), mode="F")
		chans.append(np.asarray(im.resize((w, h), method), dtype=np.float32))
	out = np.stack(chans, axis=-1)
	out[..., 3] = np.clip(out[..., 3], 0.0, 1.0)
	out[..., :3] = np.clip(out[..., :3], 0.0, None)
	if premult_clamp:
		out[..., :3] = np.minimum(out[..., :3], out[..., 3:4])  # premultiplied: colour <= alpha after tone map
	return out


def footprint_minmax(p: np.ndarray, w: int, h: int):
	"""Per output pixel: min / max of the source samples inside its footprint (all channels).
	Exact block reduction for whole-number factors, otherwise a min/max filter window that covers the
	footprint, sampled at the footprint centre."""
	H, W = p.shape[:2]
	fy, fx = H / h, W / w
	if abs(fy - round(fy)) < 1e-6 and abs(fx - round(fx)) < 1e-6:
		ky, kx = int(round(fy)), int(round(fx))
		b = p[:h * ky, :w * kx].reshape(h, ky, w, kx, p.shape[2])
		return b.min(axis=(1, 3)), b.max(axis=(1, 3))
	size = (int(np.ceil(fy)) + 1, int(np.ceil(fx)) + 1)
	mn = np.stack([ndimage.minimum_filter(p[..., i], size=size) for i in range(p.shape[2])], -1)
	mx = np.stack([ndimage.maximum_filter(p[..., i], size=size) for i in range(p.shape[2])], -1)
	cy = np.clip(((np.arange(h) + 0.5) * fy).astype(int), 0, H - 1)
	cx = np.clip(((np.arange(w) + 0.5) * fx).astype(int), 0, W - 1)
	return mn[cy][:, cx], mx[cy][:, cx]


def downsample(p: np.ndarray, w: int, h: int) -> np.ndarray:
	"""Sharp but ring-free reduction of a premultiplied linear RGBA render.

	Lanczos keeps the edges crisp, but its negative lobes leave a faint 'ghost' outline (alpha 1..8)
	1-2 px outside every silhouette and clip the colour of the outermost edge pixels to black. So:
	1. every channel of the Lanczos result is clamped to the min/max of the source samples inside the
	   output pixel's footprint (anti-ringing: a pixel whose footprint is empty stays exactly empty,
	   pixels that straddle an edge keep the Lanczos value);
	2. for faint edge pixels the colour comes from the exact area average (BOX), which is always a real
	   average of the covered sub-pixels, blended into the Lanczos colour by alpha.
	"""
	lz = resize(p, w, h, Image.Resampling.LANCZOS, premult_clamp=False)
	mn, mx = footprint_minmax(p, w, h)
	lz = np.clip(lz, mn, mx)
	box = resize(p, w, h, Image.Resampling.BOX, premult_clamp=False)
	a = lz[..., 3:4]
	c_lz = lz[..., :3] / np.maximum(a, 1e-6)
	c_box = box[..., :3] / np.maximum(box[..., 3:4], 1e-6)
	t = np.clip((a - 0.04) / (0.3 - 0.04), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	c = c_box + (c_lz - c_box) * t
	c = np.minimum(c, 1.0)  # straight colour of a tone-mapped image never exceeds 1
	out = np.concatenate([c * a, a], axis=-1)
	out[..., :3] = np.where(a > 0.0, out[..., :3], 0.0)
	return out


def bleed_rgb(rgba8: np.ndarray, radius: float = 3.0, thr: int = 24) -> np.ndarray:
	"""Gives faint / transparent pixels near the silhouette the colour of the nearest solid pixel
	(alpha >= thr), like Godot's fix_alpha_border, so straight-alpha bilinear filtering never pulls a
	dark fringe in. Pixels that already carry a real colour (alpha >= thr) are untouched."""
	solid = rgba8[..., 3] >= thr
	if not solid.any():
		return rgba8
	dist, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
	out = rgba8.copy()
	fill = (~solid) & (dist <= radius) & (rgba8[..., 3] == 0)
	out[fill, :3] = rgba8[iy[fill], ix[fill], :3]
	return out


def premult_linear_to_rgba8(p: np.ndarray, bleed: bool = False) -> np.ndarray:
	a = p[..., 3:4]
	c = p[..., :3] / np.maximum(a, 1e-6)
	c = lin_to_srgb(c)
	a8 = np.round(np.clip(a, 0, 1) * 255.0)
	c8 = np.round(c * 255.0)
	c8 = np.where(a8 > 0, c8, 0)
	out = np.concatenate([c8, a8], axis=-1).astype(np.uint8)
	return bleed_rgb(out) if bleed else out


def glow_to_rgba8(p: np.ndarray) -> np.ndarray:
	"""Additive glow: display colour D over black; store a = max(D), rgb = D / a."""
	d = lin_to_srgb(p[..., :3])
	a = d.max(axis=-1, keepdims=True)
	rgb = np.where(a > 1e-4, d / np.maximum(a, 1e-4), 0.0)
	out = np.concatenate([rgb, a], axis=-1)
	return np.round(np.clip(out, 0, 1) * 255.0).astype(np.uint8)


def save_png(rgba8: np.ndarray, path: str) -> None:
	os.makedirs(os.path.dirname(path), exist_ok=True)
	Image.fromarray(rgba8, "RGBA").save(path, optimize=True)


def alpha_bbox(rgba8: np.ndarray, thr: int = 24):
	ys, xs = np.nonzero(rgba8[..., 3] >= thr)
	if len(xs) == 0:
		return (0, 0, 0, 0)
	return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


def blur_premult(p: np.ndarray, sigma: float) -> np.ndarray:
	return np.stack([ndimage.gaussian_filter(p[..., i], sigma) for i in range(p.shape[2])], axis=-1)


# ------------------------------------------------------------------------------------------------
# Assets
# ------------------------------------------------------------------------------------------------
def publish_ship_meta(work: str, root: str, key: str) -> None:
	"""game/assets/sprites/ships/<key>.json – exact engine nozzle exits from the model builders, so the
	game can attach its procedural flames to every nozzle (3- and 4-engine ships included).
	engines: [[x, y], ...] game px relative to the ship centre (= canvas centre), +y down, sorted by x;
	engine_radius: nozzle exit radius per engine (game px)."""
	src = os.path.join(work, "ships", key + ".json")
	if not os.path.exists(src):
		return
	with open(src) as f:
		info = json.load(f)
	if "engines" not in info:
		return
	meta = {"canvas": [160, 112], "px_per_game_px": 2.0, "engines": info["engines"],
		"engine_radius": info["engine_radius"]}
	dst = os.path.join(root, "game", "assets", "sprites", "ships", key + ".json")
	os.makedirs(os.path.dirname(dst), exist_ok=True)
	with open(dst, "w") as f:
		f.write(json.dumps(meta) + "\n")
	print("[post] %-14s engines %s" % (key, meta["engines"]))


def process_ship(work: str, root: str, key: str) -> dict:
	publish_ship_meta(work, root, key)
	src = os.path.join(work, "ships", key + ".npy")
	if not os.path.exists(src):
		return {}
	p = load(src)
	p = tonemap_premult(p)
	small = downsample(p, 160, 112)
	rgba = premult_linear_to_rgba8(small, bleed=True)
	out_dir = os.path.join(root, "game", "assets", "sprites", "ships")
	save_png(rgba, os.path.join(out_dir, key + ".png"))
	# glow: plume + bloom, faded towards the canvas border so nothing is cut hard
	gsrc = os.path.join(work, "ships", key + "_glow.npy")
	if os.path.exists(gsrc):
		g = load(gsrc)
		ss = g.shape[0] // 112
		bloom = blur_premult(g, 5.0 * ss) * 0.6 + blur_premult(g, 1.6 * ss) * 0.35
		g = g + bloom
		g[..., :3] = tonemap(g[..., :3], shoulder=0.7, w_start=1.5, w_range=6.0, w_max=0.45)
		gs = resize(g, 160, 112, Image.Resampling.BOX, premult_clamp=False)
		h = gs.shape[0]
		fade = np.clip((h - 1 - np.arange(h)) / 5.0, 0.0, 1.0)[:, None, None]
		gs[..., :3] *= fade
		save_png(glow_to_rgba8(gs), os.path.join(out_dir, key + "_glow.png"))
	bb = alpha_bbox(rgba)
	info = {"key": key, "bbox": bb, "w": bb[2] - bb[0], "h": bb[3] - bb[1]}
	print("[post] %-14s visual %3dx%3d sprite px  bbox=%s" % (key, info["w"], info["h"], bb))
	return info


def process_simple(work: str, src_rel: str, dst: str, size) -> dict:
	src = os.path.join(work, src_rel)
	if not os.path.exists(src):
		return {}
	p = tonemap_premult(load(src))
	rgba = premult_linear_to_rgba8(downsample(p, size[0], size[1]), bleed=True)
	save_png(rgba, dst)
	bb = alpha_bbox(rgba)
	print("[post] %-30s %dx%d visual bbox=%s" % (os.path.basename(dst), size[0], size[1], bb))
	return {"bbox": bb}


# ------------------------------------------------------------------------------------------------
# Contact sheet
# ------------------------------------------------------------------------------------------------
def starfield(w: int, h: int, seed: int = 7) -> Image.Image:
	rng = np.random.default_rng(seed)
	yy = np.linspace(0, 1, h)[:, None]
	bg = np.zeros((h, w, 3), np.float32)
	bg[..., 0] = 0.002 + 0.002 * yy
	bg[..., 1] = 0.0025 + 0.003 * yy
	bg[..., 2] = 0.007 + 0.008 * yy
	img = bg.copy()
	n = int(w * h / 900)
	xs = rng.integers(0, w, n)
	ys = rng.integers(0, h, n)
	br = rng.random(n) ** 3
	tint = rng.choice([0, 1, 2], n, p=[0.6, 0.25, 0.15])
	cols = np.array([[1, 1, 1], [0.75, 0.85, 1.0], [1.0, 0.88, 0.7]], np.float32)
	stars = np.zeros_like(img)
	for x, y, b, t in zip(xs, ys, br, tint):
		stars[y, x] += cols[t] * (0.15 + 0.85 * b)
	halo = np.stack([ndimage.gaussian_filter(stars[..., i], 1.2) for i in range(3)], -1) * 2.0
	img = img + stars * 0.9 + halo * 0.6
	return Image.fromarray(np.round(lin_to_srgb(img) * 255).astype(np.uint8), "RGB")


def add_glow(base: Image.Image, glow: Image.Image, pos) -> None:
	"""Additive composite of a straight-alpha glow PNG (rgb*a) onto an RGB image."""
	region = base.crop((pos[0], pos[1], pos[0] + glow.width, pos[1] + glow.height))
	b = np.asarray(region, np.float32) / 255.0
	g = np.asarray(glow, np.float32) / 255.0
	b = np.clip(b + g[..., :3] * g[..., 3:4], 0, 1)
	base.paste(Image.fromarray(np.round(b * 255).astype(np.uint8), "RGB"), pos)


def scaled(img: Image.Image, f: float) -> Image.Image:
	w, h = max(1, round(img.width * f)), max(1, round(img.height * f))
	if f < 1:
		# emulate the game: premultiplied bilinear-ish reduction
		a = np.asarray(img, np.float32) / 255.0
		pm = a.copy()
		pm[..., :3] *= pm[..., 3:4]
		r = resize(pm, w, h, Image.Resampling.BOX)
		c = np.where(r[..., 3:4] > 1e-4, r[..., :3] / np.maximum(r[..., 3:4], 1e-4), 0)
		return Image.fromarray(np.round(np.concatenate([c, r[..., 3:4]], -1) * 255).astype(np.uint8), "RGBA")
	return img.resize((w, h), Image.Resampling.NEAREST if f >= 2 else Image.Resampling.BICUBIC)


def font(size: int):
	for path in ("game/assets/fonts/Orbitron.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
		p = os.path.join(ROOT, path) if not path.startswith("/") else path
		if os.path.exists(p):
			try:
				return ImageFont.truetype(p, size)
			except OSError:
				pass
	return ImageFont.load_default()


def contact_sheet(root: str, infos: dict) -> None:
	sp = os.path.join(root, "game", "assets", "sprites")
	W, H = 1280, 1330
	sheet = starfield(W, H)
	dr = ImageDraw.Draw(sheet)
	f_small = font(13)
	f_big = font(18)
	dr.text((20, 14), "art-ships contact sheet  -  1x = game scale (80x56), 2x = sprite px", font=f_big,
		fill=(200, 215, 240))
	# ships: 2 columns x 3 rows
	for i, key in enumerate(SHIP_KEYS):
		path = os.path.join(sp, "ships", key + ".png")
		if not os.path.exists(path):
			continue
		col, row = i % 2, i // 2
		x0, y0 = 20 + col * 630, 50 + row * 200
		ship = Image.open(path).convert("RGBA")
		gpath = os.path.join(sp, "ships", key + "_glow.png")
		glow = Image.open(gpath).convert("RGBA") if os.path.exists(gpath) else None
		dr.text((x0, y0), SHIP_NAMES[key], font=f_small, fill=(170, 190, 220))
		inf = infos.get(key, {})
		if inf:
			dr.text((x0 + 150, y0), "%dx%d px" % (inf["w"], inf["h"]), font=f_small, fill=(110, 125, 150))
		# 1x with glow
		s1 = scaled(ship, 0.5)
		pos = (x0 + 10, y0 + 70)
		if glow:
			add_glow(sheet, scaled(glow, 0.5), pos)
		sheet.paste(s1, pos, s1)
		# 2x with glow
		pos = (x0 + 110, y0 + 25)
		if glow:
			add_glow(sheet, glow, pos)
		sheet.paste(ship, pos, ship)
		# muzzle markers under the 2x image
		k = ("double_dart", "double_hunter").count(key)
		for off in ([-24, 24] if k else [0]):
			mx = pos[0] + 80 + off
			dr.line([(mx, pos[1] - 6), (mx, pos[1] - 1)], fill=(255, 80, 80))
		# 3x nearest (detail)
		s3 = ship.resize((240, 168), Image.Resampling.NEAREST)
		pos = (x0 + 300, y0 + 0)
		if glow:
			add_glow(sheet, glow.resize((240, 168), Image.Resampling.NEAREST), pos)
		sheet.paste(s3, pos, s3)
	# rockets: 1x (game), 2x (sprite px), 4x (detail)
	y0 = 650
	dr.text((20, y0), "ROCKETS  1x / 2x / 4x", font=f_small, fill=(170, 190, 220))
	x = 30
	for name in ("rocket", "rocket_heavy"):
		path = os.path.join(sp, "projectiles", name + ".png")
		if not os.path.exists(path):
			continue
		r = Image.open(path).convert("RGBA")
		for f in (0.5, 1, 4):
			im = scaled(r, f)
			sheet.paste(im, (x, y0 + 30), im)
			x += im.width + 24
		x += 40
	# logo (at its in-game width) + icon (256 / 64 / 32)
	lp = os.path.join(sp, "ui", "logo.png")
	if os.path.exists(lp):
		logo = Image.open(lp).convert("RGBA")
		lw = 760
		logo_s = logo.resize((lw, round(logo.height * lw / logo.width)), Image.Resampling.LANCZOS)
		dr.text((20, 1000), "LOGO @ 760 px", font=f_small, fill=(170, 190, 220))
		sheet.paste(logo_s, (20, 1030), logo_s)
	ip = os.path.join(root, "game", "icon.png")
	if os.path.exists(ip):
		icon = Image.open(ip).convert("RGBA")
		dr.text((W - 290, 650), "ICON 256 / 64 / 32", font=f_small, fill=(170, 190, 220))
		sheet.paste(icon, (W - 290, 680), icon)
		ic = icon.resize((64, 64), Image.Resampling.LANCZOS)
		sheet.paste(ic, (W - 290, 950), ic)
		ic = icon.resize((32, 32), Image.Resampling.LANCZOS)
		sheet.paste(ic, (W - 210, 966), ic)
	out = os.path.join(root, "docs", "previews", "ships_sheet.png")
	os.makedirs(os.path.dirname(out), exist_ok=True)
	sheet.save(out)
	print("[post] contact sheet ->", out)


ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def main() -> None:
	global ROOT
	work = None
	for a in sys.argv[1:]:
		if a.startswith("--work="):
			work = os.path.abspath(a[7:])
		elif a.startswith("--root="):
			ROOT = os.path.abspath(a[7:])
	if work is None:
		import tempfile
		work = os.path.join(tempfile.gettempdir(), "planet_protector_art_ships")
	infos = {}
	for key in SHIP_KEYS:
		inf = process_ship(work, ROOT, key)
		if inf:
			infos[key] = inf
	sp = os.path.join(ROOT, "game", "assets", "sprites")
	process_simple(work, "rockets/rocket.npy", os.path.join(sp, "projectiles", "rocket.png"), (24, 64))
	process_simple(work, "rockets/rocket_heavy.npy", os.path.join(sp, "projectiles", "rocket_heavy.png"), (40, 72))
	try:
		import ships_post_logo as X  # logo / icon composition
		X.process(work, ROOT)
	except ImportError:
		pass
	contact_sheet(ROOT, infos)


if __name__ == "__main__":
	sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
	main()
