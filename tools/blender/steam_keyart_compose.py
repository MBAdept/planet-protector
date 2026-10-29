"""Planet Protector Steam library artwork - 2-D composition (system python3: numpy, scipy, Pillow).

    python3 tools/blender/steam_keyart_compose.py --renders=DIR [--out=DIR] [--sheets=DIR]
                                                  [--only=logo,capsule,wide,header,hero,icon,sheets]

Normally started by tools/blender/steam_keyart.py. Reads the Blender element renders
(steam_keyart_render.py) and the game's logo (game/assets/sprites/ui/logo.png) and writes the six
assets into --out (default <repo>/steam-grid), plus contact_sheet.png / thumbnail_sheet.png into --sheets.

Per image (scene-linear float): sky (gradient, the game's blue / violet nebula, stars that keep clear of
the characters) -> Earth + analytic atmosphere -> far demons (hazed) -> fireballs -> backlight glow ->
lead demon (+ the game's cool outline for black enemies) -> laser + impact -> ship + exhaust -> bloom ->
the game's tone curve -> grade / vignette -> logo -> 8-bit sRGB with dither.
"""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

import steam_keyart_layout as LY  # noqa: E402
import steam_keyart_post as P  # noqa: E402

F32 = np.float32
LOGO_SRC = os.path.join(P.REPO, "game", "assets", "sprites", "ui", "logo.png")
FONT_DIR = os.path.join(P.REPO, "game", "assets", "fonts")
# palette: the game's nebula pushed to cool blue with a little more violet, hot orange fight
NEB1 = (0.035, 0.085, 0.21)
NEB2 = (0.085, 0.04, 0.175)
WARM = (0.6, 0.2, 0.05)
COOL_POOL = (0.05, 0.13, 0.32)
EXPOSURE = 1.1      # a brighter grade than the first pass so the capsule does not sink in a dark grid
MIDS = 0.035


def _args():
	o = {"renders": None, "out": os.path.join(P.REPO, "steam-grid"), "sheets": None, "only": None}
	for a in sys.argv[1:]:
		if a.startswith("--renders="):
			o["renders"] = os.path.abspath(a[10:])
		elif a.startswith("--out="):
			o["out"] = os.path.abspath(a[6:])
		elif a.startswith("--sheets="):
			o["sheets"] = os.path.abspath(a[9:])
		elif a.startswith("--only="):
			o["only"] = [s for s in a[7:].split(",") if s]
	if not o["renders"]:
		sys.exit("steam_keyart_compose.py: --renders=DIR is required")
	o["sheets"] = o["sheets"] or os.path.join(os.path.dirname(o["renders"]), "sheets")
	return o


# ------------------------------------------------------------------------------------------------
# elements
# ------------------------------------------------------------------------------------------------
class Elements:
	def __init__(self, d):
		self.d = d
		self.cache = {}

	def raw(self, name):
		if name not in self.cache:
			p = P.load_npy(os.path.join(self.d, name + ".npy"))
			mp = os.path.join(self.d, name + ".json")
			meta = P.load_meta(mp) if os.path.exists(mp) else {}
			g = os.path.join(self.d, name + "_glow.npy")
			glow = P.load_npy(g) if os.path.exists(g) else None
			self.cache[name] = (p, meta, glow)
		return self.cache[name]


def _anchor_list(meta):
	out = {}
	for k in ("eyes", "chest", "mouth", "muzzle", "ahead40", "nozzles"):
		v = meta.get(k)
		if v is None:
			continue
		out[k] = [list(map(float, q)) for q in v] if isinstance(v[0], list) else [list(map(float, v))]
	return out


class Sprite:
	"""A scaled (optionally mirrored / rotated / hazed / brightened) element with its anchors.
	Construct first, then place(): the scene knows every box before it paints the sky."""

	def __init__(self, el: Elements, name, width, flip=False, rot=0.0, haze=0.0, fog=(0.02, 0.03, 0.07),
			bright=1.0, sat=1.0, glow_blur=0.0):
		p, meta, glow = el.raw(name)
		anchors = _anchor_list(meta)
		# crop to the element's coverage, including its additive glow layer (exhaust plume)
		cov = p[..., 3]
		if glow is not None:
			cov = np.maximum(cov, glow[..., :3].max(-1))
		ys, xs = np.where(cov > 0.004)
		m = 6
		ox, oy = max(0, int(xs.min()) - m), max(0, int(ys.min()) - m)
		x1, y1 = min(p.shape[1], int(xs.max()) + 1 + m), min(p.shape[0], int(ys.max()) + 1 + m)
		img = p[oy:y1, ox:x1]
		if glow is not None:
			glow = glow[oy:y1, ox:x1]
		for k in anchors:
			anchors[k] = [[x - ox, y - oy] for x, y in anchors[k]]
		if flip:
			img = img[:, ::-1].copy()
			if glow is not None:
				glow = glow[:, ::-1].copy()
			W0 = img.shape[1]
			for k in anchors:
				anchors[k] = [[W0 - x, y] for x, y in anchors[k]]
		s = width / img.shape[1]
		img = P.resize(img, width, img.shape[0] * s)
		if glow is not None:
			glow = P.resize(glow, img.shape[1], img.shape[0])
		for k in anchors:
			anchors[k] = [[x * s, y * s] for x, y in anchors[k]]
		if rot:
			h0, w0 = img.shape[:2]
			img = P.rotate(img, rot)
			if glow is not None:
				glow = P.rotate(glow, rot)
			h1, w1 = img.shape[:2]
			a = math.radians(rot)
			ca, sa = math.cos(a), math.sin(a)
			for k in anchors:
				pts = []
				for x, y in anchors[k]:
					dx, dy = x - w0 / 2.0, y - h0 / 2.0
					# PIL rotates counter-clockwise for positive angles (y down image coords)
					pts.append([w1 / 2.0 + dx * ca + dy * sa, h1 / 2.0 - dx * sa + dy * ca])
				anchors[k] = pts
		if haze > 0:
			fogc = np.array(fog, F32)
			img[..., :3] = img[..., :3] * (1 - haze) + fogc * img[..., 3:4] * haze
		if sat != 1.0:
			a_ = np.maximum(img[..., 3:4], 1e-5)
			c_ = img[..., :3] / a_
			lum = (c_ * np.array([0.2126, 0.7152, 0.0722], F32)).sum(-1, keepdims=True)
			img[..., :3] = np.clip(lum + (c_ - lum) * sat, 0, None) * img[..., 3:4]
		if bright != 1.0:
			img[..., :3] *= bright
		if glow is not None and glow_blur > 0:
			# soften the rendered exhaust cone into a glow (keeps a sharp core, adds a soft halo)
			glow = glow * 0.75 + P.blur(glow, glow_blur) * 0.6 + P.blur(glow, glow_blur * 3.0) * 0.35
		self.img, self.glow, self.anchors = img, glow, anchors
		self.w, self.h = img.shape[1], img.shape[0]
		# opaque bbox relative to the centre (for keep-clear tests and frame fitting)
		ys, xs = np.where(img[..., 3] > 0.03)
		self.bx0, self.by0 = xs.min() - self.w / 2.0, ys.min() - self.h / 2.0
		self.bx1, self.by1 = xs.max() + 1 - self.w / 2.0, ys.max() + 1 - self.h / 2.0
		self.cx = self.cy = None

	def at(self, cx, cy, frame=None, margin=12.0):
		"""Sets the centre; with frame=(W, H) the opaque part is pulled fully inside, margin px clear."""
		if frame is not None:
			W, H = frame
			cx = min(max(cx, margin - self.bx0), W - margin - self.bx1)
			cy = min(max(cy, margin - self.by0), H - margin - self.by1)
		self.cx, self.cy = float(cx), float(cy)
		return self

	def box(self, pad=0.0):
		return (self.cx + self.bx0 - pad, self.cy + self.by0 - pad, self.cx + self.bx1 + pad, self.cy + self.by1 + pad)

	def anchors_at(self):
		x0, y0 = round(self.cx - self.w / 2.0), round(self.cy - self.h / 2.0)
		return {k: [[x + x0, y + y0] for x, y in v] for k, v in self.anchors.items()}

	def place(self, canvas, glow_k=1.0, cov=None):
		"""Paints the sprite; cov (canvas-sized float) accumulates its coverage. Returns canvas anchors."""
		x0, y0 = round(self.cx - self.w / 2.0), round(self.cy - self.h / 2.0)
		P.over(canvas, self.img, x0, y0)
		if self.glow is not None and glow_k > 0:
			P.add(canvas, self.glow[..., :3], x0, y0, glow_k)
		if cov is not None:
			r = P._region(cov.shape, self.img.shape, x0, y0)
			if r is not None:
				d, s = r
				cov[d] = 1.0 - (1.0 - cov[d]) * (1.0 - self.img[s][..., 3])
		return self.anchors_at()


def keep_clear(boxes, pad):
	"""avoid(x, y) for the star layer: True inside any (padded) character box."""
	bx = [(x0 - pad, y0 - pad, x1 + pad, y1 + pad) for x0, y0, x1, y1 in boxes]

	def avoid(x, y):
		return any(x0 <= x <= x1 and y0 <= y <= y1 for x0, y0, x1, y1 in bx)
	return avoid


def far_demon(canvas, sp: Sprite, eye_r, eye_k=1.0, haze=0.0):
	"""A formation member: hazed with distance, but its glowing eyes still cut through the haze."""
	a = sp.place(canvas)
	if a.get("eyes"):
		eye_glow(canvas, a["eyes"], eye_r, k=eye_k * (1.0 - 0.6 * haze))
	return a


# ------------------------------------------------------------------------------------------------
# shared painting
# ------------------------------------------------------------------------------------------------
def eye_glow(canvas, eyes, r, k=1.0):
	"""Extra bloom-y glow on the demon eyes (the game's EYE_COLOR_BLACK)."""
	for x, y in eyes:
		P.glow_dot(canvas, x, y, r, (1.0, 0.28, 0.08), 0.9 * k)
		P.glow_dot(canvas, x, y, r * 0.35, (1.0, 0.6, 0.3), 1.2 * k)


def outline(canvas, cov, sigma, k, color=None):
	"""The game draws black enemies with a subtle cool outline (enemy.gdshader outline_color); here a
	soft version of it around the lead demon, so the dark silhouette reads at thumbnail size."""
	m = P.rim_glow(cov, sigma, inside=0.35)
	col = P.OUTLINE if color is None else np.array(color, F32)
	canvas += col[None, None, :] * (m * k)[..., None]


def laser_shot(canvas, muzzle, target, w_near, w_far, flash_r, k=1.0, impact=True, muzzle_flash=True):
	P.beam(canvas, muzzle, target, w_near, w_far, k=k, fade0=0.02)
	if muzzle_flash:
		P.flash(canvas, muzzle[0], muzzle[1], flash_r * 0.45, color=(0.3, 0.6, 1.0), core=(0.85, 0.95, 1.0), k=0.9 * k,
			rays=6, seed=11, ray_len=1.2)
	if impact:
		P.flash(canvas, target[0], target[1], flash_r, color=(1.0, 0.5, 0.16), k=0.9 * k, rays=12, seed=7, ray_len=2.2)
		P.flash(canvas, target[0], target[1], flash_r * 0.5, color=(0.35, 0.65, 1.0), core=(0.9, 0.97, 1.0), k=0.45 * k,
			rays=0, seed=8)


def _streak(canvas, p0, p1, w, color, k):
	H, W = canvas.shape[:2]
	m = w * 7 + 3
	bx0, by0 = int(max(0, min(p0[0], p1[0]) - m)), int(max(0, min(p0[1], p1[1]) - m))
	bx1, by1 = int(min(W, max(p0[0], p1[0]) + m)), int(min(H, max(p0[1], p1[1]) + m))
	if bx1 <= bx0 or by1 <= by0:
		return
	yy, xx = np.mgrid[by0:by1, bx0:bx1].astype(F32)
	d, t = P._seg_dist(xx + 0.5, yy + 0.5, p0, p1)
	g = np.exp(-(d / w) ** 2) * (1 - t) ** 1.5 * 1.6 + np.exp(-(d / (w * 3)) ** 2) * (1 - t) * 0.25
	g *= P.fade_out(d, m - 1.0, 0.6)
	canvas[by0:by1, bx0:bx1] += np.array(color, F32)[None, None, :] * (g * k)[..., None]


def sparks(canvas, x, y, n, spread, length, seed, color=(1.0, 0.6, 0.2), k=1.0, dir_deg=None, cone=180.0):
	"""Short hot streaks flying out of an impact."""
	rng = np.random.default_rng(seed)
	for _ in range(n):
		a = math.radians((dir_deg if dir_deg is not None else 0.0) + rng.uniform(-cone, cone))
		d = rng.uniform(0.25, 1.0) * spread
		x0, y0 = x + math.cos(a) * d * 0.4, y + math.sin(a) * d * 0.4
		ln = length * rng.uniform(0.4, 1.0)
		x1, y1 = x0 + math.cos(a) * ln, y0 + math.sin(a) * ln
		w = max(0.6, length * 0.035)
		_streak(canvas, (x0, y0), (x1, y1), w, color, k * rng.uniform(0.5, 1.0))


def embers(canvas, box, n, seed, size=(1.0, 3.0), k=1.0, drift=(0.35, -1.0), streak=5.0):
	"""Sparse glowing embers drifting through the scene (most tiny, a few bigger)."""
	rng = np.random.default_rng(seed)
	x0, y0, x1, y1 = box
	d = np.array(drift, F32)
	d /= np.linalg.norm(d)
	for _ in range(n):
		x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
		r = size[0] + (size[1] - size[0]) * rng.uniform(0, 1) ** 3
		col = (1.0, rng.uniform(0.38, 0.7), rng.uniform(0.08, 0.2))
		ln = streak * r * rng.uniform(0.5, 1.5)
		_streak(canvas, (x, y), (x - d[0] * ln, y - d[1] * ln), r * 0.6, col, k * rng.uniform(0.4, 1.0) * (1.6 / r) ** 0.5)
		P.glow_dot(canvas, x, y, r, col, k * rng.uniform(0.3, 0.8) * (1.4 / r) ** 0.5)


def engine_trail(canvas, anchors, length, width, k=1.0):
	"""Faint exhaust trail from the nozzle(s), straight back along the ship's axis (away from the nose)."""
	mz = anchors["muzzle"][0]
	ah = anchors["ahead40"][0]
	d = np.array([mz[0] - ah[0], mz[1] - ah[1]], F32)
	d /= np.linalg.norm(d) + 1e-9
	H, W = canvas.shape[:2]
	for nz in anchors.get("nozzles", []):
		p1 = (nz[0] + d[0] * length, nz[1] + d[1] * length)
		m = width * 9
		bx0, by0 = int(max(0, min(nz[0], p1[0]) - m)), int(max(0, min(nz[1], p1[1]) - m))
		bx1, by1 = int(min(W, max(nz[0], p1[0]) + m)), int(min(H, max(nz[1], p1[1]) + m))
		if bx1 <= bx0 or by1 <= by0:
			continue
		yy, xx = np.mgrid[by0:by1, bx0:bx1].astype(F32)
		dist, t = P._seg_dist(xx + 0.5, yy + 0.5, nz, p1)
		w = width * (1.0 + 2.5 * t)
		g = np.exp(-(dist / w) ** 2) * (1.0 - t) ** 1.6 * P.smoothstep(0.0, 0.08, t) * P.fade_out(dist, m - 1.0, 0.6)
		canvas[by0:by1, bx0:bx1] += np.array([0.25, 0.55, 1.0], F32)[None, None, :] * (g * 0.35 * k)[..., None]


def finish(canvas, bloom_scale=1.0, bloom_k=1.0, vignette=0.35, vig_center=(0.5, 0.5), vig_aspect=1.0, sat=1.08,
		contrast=1.12, thr=0.85, exposure=EXPOSURE, mids=MIDS):
	img = P.bloom(canvas * exposure, thr=thr, scale=bloom_scale, k=bloom_k)
	img = P.tonemap(img)
	img = P.grade(img, sat=sat, contrast=contrast, vignette=vignette, vig_center=vig_center, vig_aspect=vig_aspect,
		mids=mids)
	return img


def load_logo():
	return P.load_logo_png(LOGO_SRC)


def lead_backlight(canvas, sp: Sprite, a, k, power=1.0):
	"""Warm-red-to-violet glow behind the lead demon's head and wings (~1.3x its wingspan)."""
	eyes = a["eyes"]
	ex = sum(p[0] for p in eyes) / len(eyes)
	ey = sum(p[1] for p in eyes) / len(eyes)
	span = sp.bx1 - sp.bx0
	P.backlight(canvas, ex, ey - 0.02 * span, 0.65 * span, 0.36 * span, k=k, power=power)


# ------------------------------------------------------------------------------------------------
# scenes
# ------------------------------------------------------------------------------------------------
def scene_capsule(el, W=600, H=900):
	"""Portrait capsule: one vertical axis - the crowned demon (eyes + impact) above, the Interceptor
	firing up from the bottom, the cyclone-lit Earth below; the logo across the top."""
	e = LY.EARTH["capsule"]
	fr = (W, H)
	lead = Sprite(el, "demon_lead", 620).at(304, 436)
	far_r = Sprite(el, "demon_d", 128, haze=0.42, flip=True, rot=-8).at(530, 238, fr, 10)
	far_l = Sprite(el, "demon_c", 124, haze=0.46, rot=6).at(70, 250, fr, 10)
	ship = Sprite(el, "ship", 340, glow_blur=3.0, bright=1.15, sat=1.12).at(234, 728)
	boxes = [s.box() for s in (lead, far_r, far_l, ship)] + [(0, 0, W, 205)]   # + the logo band
	canvas = P.sky(H, W, seed=31, scale=0.55, neb=1.2, c1=NEB1, c2=NEB2,
		warm=[(310, 430, 360, 250, WARM, 0.26)], cool=[(330, 720, 520, 200, COOL_POOL, 0.2)])
	canvas += P.stars(H, W, seed=32, density=1.1, scale=0.6, bright=6, spikes=2, avoid=keep_clear(boxes, 14))
	earth, emeta, _ = el.raw("earth_capsule")
	P.earth_layer(canvas, earth, emeta, e["cx"], e["cy"], e["R"], LY.SUN_IMG)
	far_demon(canvas, far_r, 1.8, haze=0.42)
	far_demon(canvas, far_l, 1.6, haze=0.46)
	for (x, y, vx, vy, sz, sd) in ((128, 600, -0.3, 1, 1.25, 1), (488, 600, 0.25, 1, 1.45, 2), (436, 505, 0.1, 1, 0.95, 3)):
		P.fireball(canvas, x, y, vx, vy, sz, seed=sd)
	la = lead.anchors_at()
	lead_backlight(canvas, lead, la, k=0.11)
	cov = np.zeros((H, W), F32)
	lead.place(canvas, cov=cov)
	outline(canvas, cov, 2.2, 0.10)
	eye_glow(canvas, la["eyes"], 9.6, k=1.9)
	sa = ship.place(canvas)
	engine_trail(canvas, sa, 170, 4.2)
	target = la["chest"][0]
	laser_shot(canvas, sa["muzzle"][0], target, 3.2, 1.9, 18)
	sparks(canvas, target[0], target[1], 14, 18, 44, seed=4, k=1.1)
	embers(canvas, (20, 330, 590, 700), 16, seed=62, size=(0.6, 2.2), k=0.7)
	return canvas


def make_capsule(el, out, logo):
	c = scene_capsule(el)
	img = finish(c, bloom_scale=0.5, vignette=0.42)
	P.logo_over(img, logo, 18, 22, 564, shadow=0.8)
	P.save_rgb(img, os.path.join(out, "capsule_600x900.png"))
	return img


def scene_wide(el, W=920, H=430, header=False):
	"""Wide capsule scene (also the source of the header: there the action sits further right and the
	ship is larger, so the relatively larger header logo stays clear and the ship still reads)."""
	e = LY.EARTH["wide"]
	fr = (W, H)
	dx = 34 if header else 0
	lead = Sprite(el, "demon_lead", 392 if not header else 384).at(704 + dx, 182)
	far_r = Sprite(el, "demon_d", 82, haze=0.5, flip=True, rot=-6).at(872 + dx * 0.3, 40, fr, 14)
	far_m = Sprite(el, "demon_c", 100, haze=0.45, rot=6).at(476 + dx * 0.5, 56, fr, 14)
	ship = Sprite(el, "ship", 216 if not header else 236, glow_blur=2.0, bright=1.15, sat=1.12).at(
		572 + dx, 353 if not header else 338)
	boxes = [s.box() for s in (lead, far_r, far_m, ship)] + [(0, 95, 500, 260)]   # + the logo
	canvas = P.sky(H, W, seed=41, scale=0.6, neb=1.15, c1=NEB1, c2=NEB2,
		warm=[(705 + dx, 175, 300, 210, WARM, 0.24)], cool=[(600, 420, 700, 160, COOL_POOL, 0.2)])
	canvas += P.stars(H, W, seed=42, density=1.0, scale=0.6, bright=6, spikes=2, avoid=keep_clear(boxes, 12))
	earth, emeta, _ = el.raw("earth_wide")
	P.earth_layer(canvas, earth, emeta, e["cx"], e["cy"], e["R"], LY.SUN_IMG, haze=0.6, sat=1.12, gamma=1.06)
	far_demon(canvas, far_r, 1.4, haze=0.5)
	far_demon(canvas, far_m, 1.4, haze=0.45)
	for (x, y, vx, vy, sz, sd) in ((560 + dx, 290, -0.3, 1, 1.05, 1), (858, 330, 0.25, 1, 1.2, 2)):
		P.fireball(canvas, x, y, vx, vy, sz, seed=sd)
	la = lead.anchors_at()
	lead_backlight(canvas, lead, la, k=0.12 if not header else 0.16)
	cov = np.zeros((H, W), F32)
	lead.place(canvas, cov=cov)
	outline(canvas, cov, 1.6 if not header else 2.2, 0.11 if not header else 0.2)
	eye_glow(canvas, la["eyes"], 7.0, k=1.8)
	sa = ship.place(canvas)
	engine_trail(canvas, sa, 100, 2.9)
	target = la["chest"][0]
	laser_shot(canvas, sa["muzzle"][0], target, 2.4, 1.5, 13)
	sparks(canvas, target[0], target[1], 12, 14, 30, seed=5)
	return canvas


def make_wide(el, out, logo):
	c = scene_wide(el)
	img = finish(c, bloom_scale=0.5, vignette=0.34, vig_center=(0.62, 0.5), vig_aspect=2.1)
	P.logo_over(img, logo, 18, 112, 470, shadow=0.85)
	P.save_rgb(img, os.path.join(out, "capsule_wide_920x430.png"))
	return img


def make_header(el, out, logo):
	"""Derived from the wide capsule: the same scene composed at 920 x 430 (action shifted right, ship
	larger), reduced to 460 x 215; the logo is re-set larger relative to the frame so it stays legible."""
	c = scene_wide(el, header=True)
	art = finish(c, bloom_scale=0.5, vignette=0.34, vig_center=(0.64, 0.5), vig_aspect=2.1)
	art = P.resize(np.concatenate([art, np.ones(art.shape[:2] + (1,), F32)], -1), 460, 215)[..., :3]
	P.logo_over(art, logo, 6, 50, 262, shadow=0.85)
	P.save_rgb(art, os.path.join(out, "header_460x215.png"))
	return art


def scene_hero(el, W=3840, H=1240):
	"""Library hero: no text. The left ~40 % stays calm (Steam lays the logo over the lower left), the
	action sits centre-right and survives the side crops of narrower windows."""
	S = W / 3840.0
	e = LY.EARTH["hero"]
	fr = (W, H)
	lead = Sprite(el, "demon_lead", 1000 * S).at(2700 * S, 455 * S)
	far = [  # (sprite, eye radius, haze): four different attitudes around the leader
		(Sprite(el, "demon_c", 270 * S, haze=0.55, rot=-3).at(2150 * S, 118 * S, fr, 20 * S), 3.0 * S, 0.55),
		(Sprite(el, "demon_e", 250 * S, haze=0.42, flip=True, rot=4).at(1925 * S, 400 * S, fr, 20 * S), 4.0 * S, 0.42),
		(Sprite(el, "demon_b", 420 * S, haze=0.32, flip=True, rot=-6).at(3340 * S, 270 * S, fr, 20 * S), 5.0 * S, 0.32),
		(Sprite(el, "demon_d", 300 * S, haze=0.3, rot=6).at(3470 * S, 720 * S, fr, 20 * S), 4.0 * S, 0.3),
	]
	ship = Sprite(el, "ship", 600 * S, glow_blur=6 * S, bright=1.12, sat=1.1).at(2300 * S, 985 * S)
	boxes = [s.box() for s in [lead, ship] + [f[0] for f in far]]
	canvas = P.sky(H, W, seed=21, scale=S * 1.6, neb=1.1, c1=NEB1, c2=NEB2,
		warm=[(2700 * S, 420 * S, 950 * S, 520 * S, WARM, 0.18)],
		cool=[(2600 * S, 1000 * S, 2600 * S, 380 * S, COOL_POOL, 0.2)], dust=0.75)
	canvas += P.stars(H, W, seed=22, density=1.0, scale=S * 1.6, bright=12, spikes=3, spike_len=0.6,
		avoid=keep_clear(boxes, 60 * S))
	earth, emeta, _ = el.raw("earth_hero")
	P.earth_layer(canvas, earth, emeta, e["cx"] * S, e["cy"] * S, e["R"] * S, LY.SUN_IMG, haze=0.55, sat=1.12, gamma=1.06)
	for sp, er, hz in far:
		far_demon(canvas, sp, er, haze=hz)
	for (x, y, vx, vy, sz, sd) in ((2240, 700, -0.35, 1, 2.3, 1), (3140, 880, 0.3, 1, 2.6, 2), (1765, 700, -0.2, 1, 1.7, 3),
			(3670, 430, 0.15, 1, 1.8, 4), (2640, 1010, -0.1, 1, 2.0, 5)):
		P.fireball(canvas, x * S, y * S, vx, vy, sz * S, seed=sd)
	la = lead.anchors_at()
	lead_backlight(canvas, lead, la, k=0.085)
	cov = np.zeros((H, W), F32)
	lead.place(canvas, cov=cov)
	outline(canvas, cov, 3.5 * S, 0.09)
	eye_glow(canvas, la["eyes"], 13 * S, k=1.8)
	sa = ship.place(canvas)
	engine_trail(canvas, sa, 420 * S, 9 * S)
	target = la["chest"][0]
	laser_shot(canvas, sa["muzzle"][0], target, 7 * S, 4 * S, 36 * S)
	sparks(canvas, target[0], target[1], 22, 50 * S, 120 * S, seed=3, k=1.2)
	embers(canvas, (2200 * S, 250 * S, 3800 * S, 1240 * S), 40, seed=61, size=(1.2 * S, 5.0 * S), k=0.8)
	return canvas


def make_hero(el, out):
	c = scene_hero(el)
	img = finish(c, bloom_scale=1.0, vignette=0.34, vig_center=(0.6, 0.45), vig_aspect=3.1)
	P.save_rgb(img, os.path.join(out, "hero_3840x1240.png"))
	return img


def make_logo(out):
	"""logo.png: the game's logo (game/assets/sprites/ui/logo.png, no tagline) tightly cropped to the
	letters plus their inner glow, 1280 px wide, transparent. The faint outer halo is cut where it drops
	below ~2.5 % opacity and faded over the last pixels so it never ends in a visible edge."""
	src = np.asarray(Image.open(LOGO_SRC).convert("RGBA")).astype(F32) / 255.0
	a = src[..., 3]
	ys, xs = np.where(a > 6.0 / 255.0)
	x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
	crop = src[y0:y1, x0:x1].copy()
	h, w = crop.shape[:2]
	fade = 8.0
	fy = np.clip(np.minimum(np.arange(h), h - 1 - np.arange(h)) / fade, 0, 1)
	fx = np.clip(np.minimum(np.arange(w), w - 1 - np.arange(w)) / fade, 0, 1)
	crop[..., 3] *= (fy[:, None] * fx[None, :]) ** 0.75
	lin = P.srgb_to_lin(crop[..., :3])
	pm = np.concatenate([lin * crop[..., 3:4], crop[..., 3:4]], -1)
	W = 1280
	H = int(round(pm.shape[0] * W / pm.shape[1]))
	r = P.resize(pm, W, H)
	al = np.clip(r[..., 3:4], 0, 1)
	c = np.where(al > 1e-5, r[..., :3] / np.maximum(al, 1e-5), 0)
	rgba = np.concatenate([P.lin_to_srgb(c), al], -1)
	u8 = np.clip(np.round(rgba * 255), 0, 255).astype(np.uint8)
	u8[u8[..., 3] == 0, :3] = 0
	P.save_png(u8, os.path.join(out, "logo.png"))
	return u8


def scene_icon(el, N=512):
	"""Square icon (the game icon's idea, re-rendered): the crowned demon with glowing eyes on a red glow,
	the Interceptor in front firing up into it, a dark Earth limb with a thin bright rim below."""
	e = LY.EARTH["icon"]
	yy, xx = np.mgrid[0:N, 0:N].astype(F32) / N
	# like game/icon.png: deep violet -> black, red glow behind the demon (plus a little nebula)
	canvas = np.zeros((N, N, 3), F32)
	canvas[..., 0] = 0.012 + 0.02 * (1 - yy)
	canvas[..., 1] = 0.006 + 0.008 * (1 - yy)
	canvas[..., 2] = 0.03 + 0.05 * (1 - yy)
	canvas += P.sky(N, N, seed=51, scale=0.45, neb=0.22, c1=NEB1, c2=NEB2, base_top=(0, 0, 0), base_bottom=(0, 0, 0))
	r2 = ((xx - 0.5) / 0.55) ** 2 + ((yy - 0.33) / 0.42) ** 2
	canvas += np.exp(-r2 * 2.2)[..., None] * np.array([0.44, 0.05, 0.022], F32)
	r3 = ((xx - 0.5) / 0.7) ** 2 + ((yy - 0.36) / 0.55) ** 2
	canvas += np.exp(-r3 * 2.0)[..., None] * np.array([0.03, 0.008, 0.032], F32)
	canvas += P.stars(N, N, seed=52, density=0.5, scale=0.5, bright=0, spikes=0)
	earth, emeta, _ = el.raw("earth_icon")
	P.earth_layer(canvas, earth, emeta, e["cx"], e["cy"], e["R"], LY.SUN_IMG, gain=0.45, sat=0.8, haze=0.5, halo=0.6)
	d = Sprite(el, "icon_demon", 488).at(256, 168)
	da = d.anchors_at()
	cov = np.zeros((N, N), F32)
	d.place(canvas, cov=cov)
	outline(canvas, cov, 2.0, 0.12)
	eye_glow(canvas, da["eyes"], 10.8, k=2.0)
	s = Sprite(el, "icon_ship", 290, glow_blur=2.5, bright=1.12, sat=1.1).at(256, 396)
	sa = s.place(canvas)
	target = da["chest"][0]
	laser_shot(canvas, sa["muzzle"][0], target, 3.2, 2.4, 15, k=0.9)
	return canvas


def icon_frame(img_disp, N=512):
	"""The frame of game/icon.png (ships_post_logo.process_icon) at 512 px: rounded tile with radius
	0.18 N, a thin violet rim, transparent outside. Returns straight-alpha RGBA in display-linear."""
	import ships_post_logo as SPL  # noqa: E402  (game: tools/blender)
	r = 46.0 / 256.0 * N
	rim_w = 2.0 / 256.0 * N
	mask = SPL._rounded_mask(N, r)
	shrink = np.zeros_like(mask)
	k = int(round(rim_w))
	shrink[k:-k, k:-k] = SPL._rounded_mask(N - 2 * k, r - rim_w)
	rim = np.clip(mask - shrink, 0, 1)[..., None]
	c = img_disp * (1 - rim) + rim * np.array([0.35, 0.12, 0.5], F32) * 0.8
	return np.concatenate([c, mask[..., None]], -1)


def make_icon(el, out):
	c = scene_icon(el)
	img = finish(c, bloom_scale=0.45, vignette=0.3, exposure=1.0, mids=0.0, sat=1.0)
	rgba = icon_frame(img)
	s = P.lin_to_srgb(np.clip(rgba[..., :3], 0, 1))
	rng = np.random.default_rng(9)
	s = s * 255.0 + rng.uniform(-0.5, 0.5, s.shape).astype(F32)
	u8 = np.concatenate([np.clip(np.round(s), 0, 255), np.clip(np.round(rgba[..., 3:4] * 255), 0, 255)], -1).astype(np.uint8)
	u8[u8[..., 3] == 0, :3] = 0
	P.save_png(u8, os.path.join(out, "icon_512.png"))
	return img


# ------------------------------------------------------------------------------------------------
# review sheets
# ------------------------------------------------------------------------------------------------
def _font(size):
	for f in ("Exo2.ttf", "Exo2-Regular.ttf", "Orbitron.ttf"):
		p = os.path.join(FONT_DIR, f)
		if os.path.exists(p):
			try:
				return ImageFont.truetype(p, size)
			except OSError:
				pass
	return ImageFont.load_default()


def _checker(size, a=(60, 60, 66), b=(72, 72, 78), cell=12):
	ck = Image.new("RGB", size, a)
	cd = ImageDraw.Draw(ck)
	for yy in range(0, size[1], cell):
		for xx in range(0, size[0], cell):
			if (xx // cell + yy // cell) % 2:
				cd.rectangle([xx, yy, xx + cell - 1, yy + cell - 1], fill=b)
	return ck


def contact_sheet(out, sheets):
	ims = {f: Image.open(os.path.join(out, f)) for f in ("capsule_600x900.png", "capsule_wide_920x430.png",
		"header_460x215.png", "icon_512.png", "logo.png", "hero_3840x1240.png")}
	pad = 40
	f_lbl = _font(22)
	W = pad + 600 + pad + 920 + pad + 512 + pad
	hero_w = W - 2 * pad
	hero = ims["hero_3840x1240.png"].resize((hero_w, round(1240 * hero_w / 3840)), Image.LANCZOS)
	H = pad + 36 + 900 + pad + 36 + hero.height + pad
	sheet = Image.new("RGB", (W, H), (38, 39, 43))
	d = ImageDraw.Draw(sheet)
	x, y = pad, pad + 36
	sheet.paste(ims["capsule_600x900.png"], (x, y))
	d.text((x, y - 30), "capsule_600x900.png", fill=(200, 200, 205), font=f_lbl)
	x2 = x + 600 + pad
	sheet.paste(ims["capsule_wide_920x430.png"], (x2, y))
	d.text((x2, y - 30), "capsule_wide_920x430.png", fill=(200, 200, 205), font=f_lbl)
	y2 = y + 430 + pad + 36
	sheet.paste(ims["header_460x215.png"], (x2, y2))
	d.text((x2, y2 - 30), "header_460x215.png", fill=(200, 200, 205), font=f_lbl)
	lg = ims["logo.png"]
	lw = 920 - 460 - pad
	lg_s = lg.resize((lw, round(lg.height * lw / lg.width)), Image.LANCZOS)
	lx = x2 + 460 + pad
	ck = _checker(lg_s.size)
	ck.paste(lg_s, (0, 0), lg_s)
	sheet.paste(ck, (lx, y2))
	d.text((lx, y2 - 30), "logo.png (1280 px, transparent)", fill=(200, 200, 205), font=f_lbl)
	x3 = x2 + 920 + pad
	ic = ims["icon_512.png"]
	ck = _checker(ic.size)
	ck.paste(ic, (0, 0), ic)
	sheet.paste(ck, (x3, y))
	d.text((x3, y - 30), "icon_512.png", fill=(200, 200, 205), font=f_lbl)
	y3 = y + 900 + pad + 36
	sheet.paste(hero, (pad, y3))
	d.text((pad, y3 - 30), "hero_3840x1240.png (shown at %d px)" % hero_w, fill=(200, 200, 205), font=f_lbl)
	sheet.save(os.path.join(sheets, "contact_sheet.png"), optimize=True)


def thumbnail_sheet(out, sheets):
	"""How the assets appear small in the Steam library: grid capsules at 150 / 200 px among grey
	dummies, a greyscale value check (capsule 150 px, icon 64 / 32 px), the wide capsule at 300 px, the
	header at 230 px, the icon at 64 / 32 / 16 px, the hero at 1280 px with the logo overlaid bottom-left
	(Steam's default) and centre crops of narrower windows."""
	pad = 28
	bg = (27, 40, 56)   # Steam library blue-grey
	dummy = (58, 66, 78)
	f_lbl = _font(16)
	cap = Image.open(os.path.join(out, "capsule_600x900.png"))
	wide = Image.open(os.path.join(out, "capsule_wide_920x430.png"))
	head = Image.open(os.path.join(out, "header_460x215.png"))
	hero = Image.open(os.path.join(out, "hero_3840x1240.png"))
	logo = Image.open(os.path.join(out, "logo.png"))
	icon = Image.open(os.path.join(out, "icon_512.png"))
	W = pad * 2 + 1280
	crop_h = 280
	H = (pad + 24 + 225) + (pad + 24 + 300) + (pad + 24 + 225) + (pad + 24 + 141) + (pad + 24 + 413) + (pad + 24 + crop_h) + pad
	sheet = Image.new("RGB", (W, H), bg)
	d = ImageDraw.Draw(sheet)
	y = pad
	d.text((pad, y), "Library grid, capsule at 150 px (among other games)", fill=(190, 200, 212), font=f_lbl)
	y += 24
	x = pad
	for i in range(7):
		if i == 2:
			sheet.paste(cap.resize((150, 225), Image.LANCZOS), (x, y))
		else:
			d.rectangle([x, y, x + 149, y + 224], fill=dummy)
		x += 150 + 14
	y += 225 + pad
	d.text((pad, y), "Library grid, capsule at 200 px", fill=(190, 200, 212), font=f_lbl)
	y += 24
	x = pad
	for i in range(6):
		if i == 1:
			sheet.paste(cap.resize((200, 300), Image.LANCZOS), (x, y))
		else:
			d.rectangle([x, y, x + 199, y + 299], fill=dummy)
		x += 200 + 14
	y += 300 + pad
	d.text((pad, y), "Value check in greyscale: capsule at 150 px, icon at 64 / 32 px, header at 230 px", fill=(190, 200, 212),
		font=f_lbl)
	y += 24
	x = pad
	sheet.paste(cap.resize((150, 225), Image.LANCZOS).convert("L").convert("RGB"), (x, y))
	x += 150 + 24
	for s in (64, 32):
		ic = icon.resize((s, s), Image.LANCZOS)
		g = Image.new("RGB", (s, s), bg)
		g.paste(ic, (0, 0), ic)
		sheet.paste(g.convert("L").convert("RGB"), (x, y))
		x += s + 14
	x += 10
	sheet.paste(head.resize((230, 107), Image.LANCZOS).convert("L").convert("RGB"), (x, y))
	y += 225 + pad
	d.text((pad, y), "Wide capsule at 300 px, header at 230 px, icon at 64 / 32 / 16 px", fill=(190, 200, 212), font=f_lbl)
	y += 24
	x = pad
	sheet.paste(wide.resize((300, 140), Image.LANCZOS), (x, y))
	x += 300 + 24
	d.rectangle([x, y, x + 299, y + 139], fill=dummy)
	x += 300 + 24
	sheet.paste(head.resize((230, 107), Image.LANCZOS), (x, y))
	x += 230 + 24
	for s in (64, 32, 16):
		ic = icon.resize((s, s), Image.LANCZOS)
		sheet.paste(ic, (x, y), ic)
		x += s + 14
	y += 141 + pad
	d.text((pad, y), "Library hero at 1280 px with the logo overlaid bottom-left (Steam default)", fill=(190, 200, 212),
		font=f_lbl)
	y += 24
	hsm = hero.resize((1280, 413), Image.LANCZOS)
	lw = 470
	lsm = logo.resize((lw, round(logo.height * lw / logo.width)), Image.LANCZOS)
	hsm.paste(lsm, (int(1280 * 0.035), 413 - lsm.height - int(413 * 0.12)), lsm)
	sheet.paste(hsm, (pad, y))
	y += 413 + pad
	d.text((pad, y), "Hero cropped like narrower Steam windows: centre 80 % and centre 60 % (with logo)", fill=(190, 200, 212),
		font=f_lbl)
	y += 24
	x = pad
	for frac in (0.8, 0.6):
		cw = int(3840 * frac)
		cx0 = (3840 - cw) // 2
		tw = int(cw * crop_h / 1240)
		crop = hero.crop((cx0, 0, cx0 + cw, 1240)).resize((tw, crop_h), Image.LANCZOS)
		lw2 = int(tw * 0.42)
		l2 = logo.resize((lw2, round(logo.height * lw2 / logo.width)), Image.LANCZOS)
		crop.paste(l2, (int(tw * 0.035), crop_h - l2.height - int(crop_h * 0.12)), l2)
		sheet.paste(crop, (x, y))
		x += tw + 16
	sheet.save(os.path.join(sheets, "thumbnail_sheet.png"), optimize=True)


EXPECT = {"capsule_600x900.png": ((600, 900), "RGB"), "capsule_wide_920x430.png": ((920, 430), "RGB"),
	"header_460x215.png": ((460, 215), "RGB"), "hero_3840x1240.png": ((3840, 1240), "RGB"),
	"logo.png": ((1280, None), "RGBA"), "icon_512.png": ((512, 512), "RGBA")}


def check(out):
	"""Exact pixel sizes and modes of the six assets (printed; returns False if anything is off)."""
	ok_all = True
	for f, ((w, h), mode) in EXPECT.items():
		p = os.path.join(out, f)
		if not os.path.exists(p):
			print("[check] MISSING", f)
			ok_all = False
			continue
		im = Image.open(p)
		ok = im.width == w and (h is None or im.height == h) and im.mode == mode
		ok_all &= ok
		print("[check] %-26s %4dx%-4d %-4s %6.0f KB  %s" % (f, im.width, im.height, im.mode, os.path.getsize(p) / 1024,
			"ok" if ok else "WRONG"))
	return ok_all


def run(renders, out, sheets, only=None):
	el = Elements(renders)
	os.makedirs(out, exist_ok=True)
	only = only or ["logo", "capsule", "wide", "header", "hero", "icon", "sheets"]
	logo = load_logo()
	if "logo" in only:
		make_logo(out)
	if "capsule" in only:
		make_capsule(el, out, logo)
	if "wide" in only:
		make_wide(el, out, logo)
	if "header" in only:
		make_header(el, out, logo)
	if "hero" in only:
		make_hero(el, out)
	if "icon" in only:
		make_icon(el, out)
	if "sheets" in only:
		os.makedirs(sheets, exist_ok=True)
		contact_sheet(out, sheets)
		thumbnail_sheet(out, sheets)
	ok = check(out)
	print("[compose] done ->", out, "(sheets:", sheets + ")")
	return ok


def main():
	o = _args()
	sys.exit(0 if run(o["renders"], o["out"], o["sheets"], o["only"]) else 1)


if __name__ == "__main__":
	main()
