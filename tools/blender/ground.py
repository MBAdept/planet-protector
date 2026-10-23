"""Ground strips for Planet Protector (package art-planets, docs/SPEC.md §15, §16.4).

Writes game/assets/sprites/ground/<planet>.png: 1920 x 70 px RGBA (= 960 x 35 game px, drawn at
y 685..720). Row 0 is the surface line (flat, with a subtle bright rim); the strip tiles
horizontally (every noise field and every rock is periodic in x).

Look: a front view of the planet's crust. A textured matrix (ice, sandstone strata, basalt, dust,
soil) with individually shaded boulders / ice blocks / crystals that overlap and cast soft shadows,
lit from the upper left like the planets, under a lit top ledge (frost, sand, dust, crust, grass).
Rendered as a small 2.5D shader in numpy, supersampled 2x. Deterministic.

Usage: python3 tools/blender/ground.py [planet ...] [--out=DIR] [--no-sheet]
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from planets_noise import F32, Perlin3, hexcol, linear_to_srgb, smoothstep, srgb_to_linear  # noqa: E402

OUT_DEFAULT = os.path.join(ROOT, "game", "assets", "sprites", "ground")
ORDER = ["neptune", "uranus", "saturn", "jupiter", "mars", "earth"]
W_OUT, H_OUT = 1920, 70
SS = 2
W, H = W_OUT * SS, H_OUT * SS
LIGHT = np.array([-0.55, -0.60, 0.58])   # x right, y down, z towards the viewer -> upper left
LIGHT /= np.linalg.norm(LIGHT)
HALF = LIGHT + np.array([0.0, 0.0, 1.0])
HALF /= np.linalg.norm(HALF)

YY, XX = np.mgrid[0:H, 0:W].astype(F32)


# ------------------------------------------------------------------------------------------------
# primitives
# ------------------------------------------------------------------------------------------------
def lin(c):
	return srgb_to_linear(np.array(hexcol(c) if isinstance(c, str) else c, np.float64))


def mixc(a, b, t):
	t = np.asarray(t, np.float64)
	if t.ndim == 2:
		t = t[..., None]
	return a + (b - a) * t


def ramp(t, stops):
	t = np.asarray(t, np.float64)
	pos = [p for p, _ in stops]
	cols = np.array([lin(c) for _, c in stops])
	out = np.empty(t.shape + (3,))
	for k in range(3):
		out[..., k] = np.interp(t, pos, cols[:, k])
	return out


def pnoise(seed: int, scale_x: float, scale_y: float, octaves: int = 4, gain: float = 0.5,
		ridged: bool = False, x=None, y=None):
	"""Tileable (period W in x) fbm noise, std ~1. scale_* = feature size in supersampled px."""
	n = Perlin3(seed)
	x = XX if x is None else x
	y = YY if y is None else y
	rc = W / (2.0 * math.pi * scale_x)
	ang = x * (2.0 * math.pi / W)
	cx = np.cos(ang) * rc
	cy = np.sin(ang) * rc
	cz = y / scale_y
	out = np.zeros(np.shape(x), F32)
	amp, norm = 1.0, 0.0
	for o in range(octaves):
		f = 2.0 ** o
		v = n(cx * f + 31.7 * o, cy * f - 11.3 * o, cz * f + 7.1 * o)
		if ridged:
			v = 0.45 - np.abs(v)
		out += F32(amp) * v
		norm += amp * amp
		amp *= gain
	return out / F32(0.21 * math.sqrt(norm))


def pridge(seed: int, scale_x: float, scale_y: float, octaves: int = 3, width: float = 0.10):
	"""Tileable thin ridge lines in [0, 1] (1 on the zero crossings of the noise)."""
	n = Perlin3(seed)
	rc = W / (2.0 * math.pi * scale_x)
	ang = XX * (2.0 * math.pi / W)
	cx = np.cos(ang) * rc
	cy = np.sin(ang) * rc
	cz = YY / scale_y
	out = np.zeros(XX.shape, F32)
	amp, tot = 1.0, 0.0
	for o in range(octaves):
		f = 2.0 ** o
		v = n(cx * f + 13.1 * o, cy * f + 5.3 * o, cz * f - 9.7 * o)
		out += F32(amp) * np.clip(1.0 - np.abs(v) / width, 0, 1) ** 2
		tot += amp
		amp *= 0.55
	return out / F32(tot)


def normals(h, strength: float, periodic: bool = True):
	gy, gx = np.gradient(h.astype(np.float64))
	if periodic and h.shape[1] == W:
		gx[:, 0] = (h[:, 1] - h[:, -1]) * 0.5
		gx[:, -1] = (h[:, 0] - h[:, -2]) * 0.5
	nx = -gx * strength
	ny = -gy * strength
	ln = np.sqrt(nx * nx + ny * ny + 1.0)
	return nx / ln, ny / ln, 1.0 / ln


def light(albedo, nx, ny, nz, ambient=0.30, spec=0.0, spec_pow=30.0, spec_col=(1, 1, 1), wrap=0.1):
	ndl = nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]
	diff = np.clip((ndl + wrap) / (1 + wrap), 0, 1)
	ndh = np.clip(nx * HALF[0] + ny * HALF[1] + nz * HALF[2], 0, 1)
	sp = spec * ndh ** spec_pow
	return albedo * (ambient + (1.0 - ambient) * 1.3 * diff)[..., None] + sp[..., None] * np.asarray(spec_col)[None, None, :]


# ------------------------------------------------------------------------------------------------
# rocks: individually shaded polygons with drop shadows, composited back to front
# ------------------------------------------------------------------------------------------------
class Style:
	def __init__(self, **kw):
		self.dark = "333333"
		self.light = "999999"
		self.facet = False         # True: chamfered planar facets (ice, crystals); False: rounded boulders
		self.bevel = 0.55          # bevel width relative to the rock's minor radius
		self.strength = 2.2        # normal strength
		self.spec = 0.15
		self.spec_pow = 18.0
		self.spec_col = (1.0, 1.0, 1.0)
		self.ambient = 0.30
		self.grain = 0.10          # surface grain amplitude
		self.grain_scale = 3.0
		self.shadow = 0.6
		self.inner_glow = None     # (colour, strength) for translucent ice
		self.vertices = (7, 11)
		self.squash = (0.45, 0.8)  # ry / rx
		self.flat_bottom = 0.0
		self.__dict__.update(kw)


def rock_polygon(rng, cx, cy, rx, ry, nv, irregular=0.22):
	a0 = rng.uniform(0, 2 * math.pi)
	angs = np.sort((a0 + np.arange(nv) * 2 * math.pi / nv + rng.uniform(-0.35, 0.35, nv) * 2 * math.pi / nv) % (2 * math.pi))
	rad = 1.0 - rng.uniform(0, irregular, nv)
	return [(cx + rx * r * math.cos(a), cy + ry * r * math.sin(a)) for a, r in zip(angs, rad)]


def draw_rocks(img, rocks, style: Style, seed: int, grain_field=None):
	"""rocks: list of (cx, cy, rx, ry). Drawn in the given order (later = in front)."""
	from PIL import Image, ImageDraw
	from scipy.ndimage import distance_transform_edt, gaussian_filter
	rng = np.random.default_rng(seed)
	grain = pnoise(seed + 7, style.grain_scale, style.grain_scale, 3) if grain_field is None else grain_field
	tone_noise = pnoise(seed + 8, 25, 18, 3)
	c_dark = lin(style.dark)
	c_light = lin(style.light)
	for (cx, cy, rx, ry) in rocks:
		nv = int(rng.integers(style.vertices[0], style.vertices[1] + 1))
		poly0 = rock_polygon(rng, 0.0, 0.0, rx, ry, nv)
		tone = rng.uniform(0.0, 1.0)
		tilt = rng.uniform(-0.25, 0.25, 2)
		height = rng.uniform(0.8, 1.2)
		pad = 12
		x0 = int(math.floor(cx - rx - pad))
		y0 = int(math.floor(cy - ry - pad))
		bw = int(2 * rx + 2 * pad) + 2
		bh = int(2 * ry + 2 * pad) + 2
		m = Image.new("L", (bw * 2, bh * 2), 0)   # extra 2x for a clean anti-aliased edge
		ImageDraw.Draw(m).polygon([((px + cx - x0) * 2, (py + cy - y0) * 2) for px, py in poly0], fill=255)
		mask_hi = np.asarray(m, np.float64) / 255.0
		mask = mask_hi.reshape(bh, 2, bw, 2).mean(axis=(1, 3))
		inside = mask_hi > 0.5
		dist = distance_transform_edt(inside).reshape(bh, 2, bw, 2).mean(axis=(1, 3)) * 0.5
		bev = max(2.0, style.bevel * min(rx, ry))
		t = np.clip(dist / bev, 0, 1)
		ly, lx = np.mgrid[0:bh, 0:bw].astype(np.float64)
		lx = (lx + x0 - cx) / rx
		ly = (ly + y0 - cy) / ry
		if style.facet:
			hgt = t * bev * 0.9 * height + (lx * tilt[0] + ly * tilt[1]) * bev * 0.6 * t
		else:
			hgt = np.sqrt(1 - (1 - t) ** 2) * bev * 0.9 * height + (lx * tilt[0] + ly * tilt[1]) * bev * 0.3 * t
			hgt = gaussian_filter(hgt, 0.8)
		for copy_dx in (-W, 0, W):
			gx0 = x0 + copy_dx
			if gx0 + bw <= 0 or gx0 >= W:
				continue
			xs0, xs1 = max(0, gx0), min(W, gx0 + bw)
			ys0, ys1 = max(0, y0), min(H, y0 + bh)
			if ys1 <= ys0:
				continue
			sx = slice(xs0 - gx0, xs1 - gx0)
			sy = slice(ys0 - y0, ys1 - y0)
			g = grain[ys0:ys1, xs0:xs1]
			tn = tone_noise[ys0:ys1, xs0:xs1]
			h_loc = hgt[sy, sx] + style.grain * g * bev * 0.25 * np.clip(t[sy, sx] * 3, 0, 1)
			nx, ny, nz = normals(h_loc, style.strength / max(bev, 1.0) * 1.6, periodic=False)
			alb = mixc(c_dark, c_light, np.clip(tone + 0.25 * tn, 0, 1))
			alb = alb * (1.0 + 0.10 * g)[..., None]
			lit = light(alb, nx, ny, nz, style.ambient, style.spec, style.spec_pow, style.spec_col)
			# edge occlusion
			ao = 0.35 + 0.65 * smoothstep(0.0, 3.5, dist[sy, sx])
			lit = lit * ao[..., None]
			if style.inner_glow is not None:
				gc, gs = style.inner_glow
				lit = lit + lin(gc)[None, None, :] * (gs * smoothstep(0.3, 1.0, t[sy, sx]) * (0.6 + 0.4 * tn))[..., None]
			a = mask[sy, sx]
			# drop shadow towards the lower right (opposite the light)
			sh = np.zeros((bh + 16, bw + 16))
			sh[10:10 + bh, 8:8 + bw] = mask
			sh = gaussian_filter(sh, 3.0)[8:8 + bh, 8:8 + bw]
			region = img[ys0:ys1, xs0:xs1]
			region *= (1.0 - style.shadow * sh[sy, sx] * (1 - a))[..., None]
			region[:] = region * (1 - a[..., None]) + lit * a[..., None]


def scatter(seed, count, y_range, rx_range, squash, min_gap=0.0):
	"""Random rock placements (periodic in x), sorted back to front by size (big first)."""
	rng = np.random.default_rng(seed)
	rocks = []
	tries = 0
	while len(rocks) < count and tries < count * 40:
		tries += 1
		rx = rng.uniform(*rx_range)
		ry = rx * rng.uniform(*squash)
		cx = rng.uniform(0, W)
		cy = rng.uniform(*y_range)
		ok = True
		if min_gap > 0:
			for (ox, oy, orx, ory) in rocks:
				dx = abs(cx - ox)
				dx = min(dx, W - dx)
				if (dx / (rx + orx)) ** 2 + ((cy - oy) / (ry + ory)) ** 2 < min_gap ** 2:
					ok = False
					break
		if ok:
			rocks.append((cx, cy, rx, ry))
	rocks.sort(key=lambda r: -r[2] * r[3])
	return rocks


def crystals(img, seed, count, y_range, size_range, c_dark, c_mid, c_light, glow_col, glow=0.35, tilt=0.55):
	"""Faceted crystal prisms (2-3 per cluster) growing out of the face, with a soft glow."""
	from PIL import Image, ImageDraw
	from scipy.ndimage import gaussian_filter
	rng = np.random.default_rng(seed)
	layer = Image.new("RGBA", (W * 2, H * 2), (0, 0, 0, 0))   # 2x for crisp edges
	dr = ImageDraw.Draw(layer)
	glow_mask = np.zeros((H, W))
	to8 = lambda c: tuple(int(round(v * 255)) for v in np.clip(linear_to_srgb(c), 0, 1))  # noqa: E731
	cols = [to8(lin(c)) for c in (c_dark, c_mid, c_light)]
	for _ in range(count):
		cx = rng.uniform(0, W)
		cy = rng.uniform(*y_range)
		size = rng.uniform(*size_range)
		base_ang = rng.uniform(-tilt, tilt)
		for k in range(int(rng.integers(2, 4))):
			ang = base_ang + (rng.uniform(-0.7, 0.7) if k else 0.0) - math.pi / 2
			ln = size * (1.0 if k == 0 else rng.uniform(0.45, 0.75))
			wd = ln * rng.uniform(0.30, 0.38)
			ox = cx + (rng.uniform(-0.5, 0.5) * wd if k else 0.0)
			dx, dy = math.cos(ang), math.sin(ang)
			px, py = -dy, dx
			tip = wd * 0.75
			for shift in (-W, 0, W):
				bx, by = ox + shift, cy
				if bx + ln < -10 or bx - ln > W + 10:
					continue
				P = lambda u, v: ((bx + dx * u + px * v) * 2, (by + dy * u + py * v) * 2)  # noqa: E731
				hw = wd * 0.5
				# three visible faces of a hexagonal prism + pyramidal tip
				left = [P(0, -hw), P(ln - tip, -hw), P(ln - tip * 0.8, -hw * 0.25), P(0, -hw * 0.25)]
				mid = [P(0, -hw * 0.25), P(ln - tip * 0.8, -hw * 0.25), P(ln - tip * 0.8, hw * 0.3), P(0, hw * 0.3)]
				right = [P(0, hw * 0.3), P(ln - tip * 0.8, hw * 0.3), P(ln - tip, hw), P(0, hw)]
				t_l = [P(ln - tip, -hw), P(ln, 0), P(ln - tip * 0.8, -hw * 0.25)]
				t_m = [P(ln - tip * 0.8, -hw * 0.25), P(ln, 0), P(ln - tip * 0.8, hw * 0.3)]
				t_r = [P(ln - tip * 0.8, hw * 0.3), P(ln, 0), P(ln - tip, hw)]
				lit_left = (px * LIGHT[0] + py * LIGHT[1]) > 0
				cl, cm, cr = (cols[2], cols[1], cols[0]) if not lit_left else (cols[0], cols[1], cols[2])
				dr.polygon(left, fill=cl + (255,))
				dr.polygon(mid, fill=cm + (255,))
				dr.polygon(right, fill=cr + (255,))
				dr.polygon(t_l, fill=cl + (255,))
				dr.polygon(t_m, fill=tuple(min(255, int(v * 1.12)) for v in cm) + (255,))
				dr.polygon(t_r, fill=cr + (255,))
				# bright edge on the ridge facing the light
				ridge = [P(0, -hw * 0.25), P(ln - tip * 0.8, -hw * 0.25), P(ln, 0)] if not lit_left else [P(0, hw * 0.3), P(ln - tip * 0.8, hw * 0.3), P(ln, 0)]
				dr.line(ridge, fill=(255, 255, 255, 200), width=2)
				gx = int(bx + dx * ln * 0.45)
				gy = int(by + dy * ln * 0.45)
				r = int(ln * 0.9)
				yy0, yy1 = max(0, gy - r), min(H, gy + r)
				xx0, xx1 = max(0, gx - r), min(W, gx + r)
				if yy1 > yy0 and xx1 > xx0:
					d2 = ((XX[yy0:yy1, xx0:xx1] - gx) ** 2 + (YY[yy0:yy1, xx0:xx1] - gy) ** 2) / float(r * r)
					glow_mask[yy0:yy1, xx0:xx1] = np.maximum(glow_mask[yy0:yy1, xx0:xx1], np.exp(-d2 * 3.0))
	lay = np.asarray(layer, np.float64) / 255.0
	lay = lay.reshape(H, 2, W, 2, 4)
	a = lay[..., 3].mean(axis=(1, 3))
	rgb = srgb_to_linear((lay[..., :3] * lay[..., 3:4]).mean(axis=(1, 3)) / np.maximum(a, 1e-6)[..., None])
	# glow first (behind), then the crystals; a little drop shadow
	img += (glow * glow_mask)[..., None] * lin(glow_col)[None, None, :]
	sh = gaussian_filter(np.roll(np.roll(a, 5, axis=0), 4, axis=1), 2.5, mode=("nearest", "wrap"))
	img *= (1 - 0.45 * sh * (1 - a))[..., None]
	img[:] = img * (1 - a[..., None]) + rgb * a[..., None]


# ------------------------------------------------------------------------------------------------
# top ledge, rim, depth
# ------------------------------------------------------------------------------------------------
def ledge(img, seed, depth, amp, c_top, c_bottom, tex=None, edge_light=0.35, shadow=0.6, shadow_len=10.0):
	"""Lit top surface band of ~depth px (supersampled) with an irregular lower edge."""
	bd = depth + amp * pnoise(seed, 40, 40, 4, x=XX[0], y=np.zeros(W, F32))
	bd = bd[None, :]
	t = np.clip(YY / np.maximum(bd, 1.0), 0, 1)
	col = ramp(t, [(0.0, c_top), (1.0, c_bottom)])
	if tex is not None:
		col = col * (1.0 + tex)[..., None]
	# lower edge: a bright lip (faces the light) and a cast shadow below it
	lip = np.exp(-((YY - (bd - 2.0)) / 1.6) ** 2)
	col = col + (edge_light * lip)[..., None] * col
	below = YY - bd
	sh = smoothstep(-1.0, 1.5, below) * np.exp(-np.maximum(below, 0) / shadow_len)
	img *= (1 - shadow * sh)[..., None]
	inside = smoothstep(bd + 1.2, bd - 1.2, YY)
	img[:] = img * (1 - inside[..., None]) + col * inside[..., None]
	return bd


def rim(img, c_rim, strength=0.8, width=2.2):
	t = np.exp(-(YY / width) ** 2) * strength
	img[:] = img * (1 - t[..., None]) + lin(c_rim)[None, None, :] * t[..., None]


def depth_fade(img, start=0.3, k=0.55):
	t = smoothstep(start * H, H, YY)
	img *= (1.0 - k * t)[..., None]


def matrix_rock(seed, c0, c1, scale=(30, 14), strength=1.4, spec=0.05, ridged=False, ambient=0.35, fine=0.35,
		octaves=5, spec_col=(1.0, 1.0, 1.0), spec_pow=16.0):
	h = pnoise(seed, *scale, octaves, ridged=ridged) + fine * pnoise(seed + 1, 4, 3, 3)
	tone = np.clip(0.5 + 0.22 * pnoise(seed + 2, 60, 22, 3), 0, 1)
	alb = ramp(tone, [(0.0, c0), (1.0, c1)])
	nx, ny, nz = normals(h * 3.0, strength * 0.6)
	return light(alb, nx, ny, nz, ambient, spec, spec_pow, spec_col)


# ------------------------------------------------------------------------------------------------
# planets
# ------------------------------------------------------------------------------------------------
def make_neptune():
	img = matrix_rock(1001, "0b1a46", "1c3a7e", scale=(60, 20), strength=0.55, spec=0.22, fine=0.04, octaves=3,
		spec_col=(0.35, 0.6, 1.0), spec_pow=30)
	img *= (1.0 + 0.12 * pnoise(1009, 160, 14, 3))[..., None]   # layered ice
	# glowing veins inside the ice
	vein = smoothstep(0.25, 0.8, pridge(1002, 90, 30, 3))
	img += (0.12 * vein)[..., None] * lin("4fb8ff")[None, None, :]
	st = Style(dark="163170", light="4f83dc", facet=True, bevel=0.42, strength=3.2, spec=0.8, spec_pow=40,
		spec_col=(0.75, 0.88, 1.0), ambient=0.22, grain=0.05, inner_glow=("2c62c8", 0.10), vertices=(5, 8),
		squash=(0.5, 0.85), shadow=0.65)
	draw_rocks(img, scatter(1003, 120, (30, H + 15), (18, 46), st.squash, 0.48), st, 1004)
	crystals(img, 1005, 14, (H * 0.40, H * 0.95), (26, 58), "1b4fa6", "5fb6f2", "d4f6ff", "3fb0ff", glow=0.30)
	depth_fade(img, 0.35, 0.55)
	tex = 0.10 * pnoise(1006, 6, 3, 3) + 0.25 * smoothstep(0.93, 1.0, 0.5 + 0.5 * pnoise(1007, 1.8, 1.8, 2))
	ledge(img, 1008, 20.0, 3.5, "d6ecff", "6f9fe6", tex, edge_light=0.25, shadow=0.65)
	rim(img, "f0faff", 0.75, 2.4)
	return img


def make_uranus():
	img = matrix_rock(2001, "1f4c56", "3f7f87", scale=(60, 20), strength=0.55, spec=0.18, fine=0.04, octaves=3,
		spec_col=(0.55, 0.95, 1.0), spec_pow=30)
	img *= (1.0 + 0.10 * pnoise(2009, 160, 14, 3))[..., None]   # layered ice
	vein = smoothstep(0.3, 0.85, pridge(2002, 110, 35, 3))
	img += (0.10 * vein)[..., None] * lin("9ff4ff")[None, None, :]
	st = Style(dark="4a929c", light="aee6e8", facet=True, bevel=0.5, strength=2.6, spec=0.55, spec_pow=30,
		spec_col=(0.85, 1.0, 1.0), ambient=0.26, grain=0.06, inner_glow=("7fd6dc", 0.06), vertices=(7, 10),
		squash=(0.45, 0.75), shadow=0.55)
	draw_rocks(img, scatter(2003, 110, (32, H + 15), (18, 48), st.squash, 0.48), st, 2004)
	crystals(img, 2005, 8, (H * 0.45, H * 0.95), (20, 40), "4a98a4", "a6e9ec", "f2ffff", "b6fbff", glow=0.18)
	depth_fade(img, 0.35, 0.5)
	tex = 0.05 * pnoise(2006, 8, 4, 3) + 0.2 * smoothstep(0.94, 1.0, 0.5 + 0.5 * pnoise(2007, 1.8, 1.8, 2))
	ledge(img, 2008, 22.0, 4.0, "f6ffff", "a9e0e2", tex, edge_light=0.2, shadow=0.5)
	rim(img, "ffffff", 0.7, 2.2)
	return img


def make_saturn():
	# sandstone strata: wavy horizontal layers of different tones, slightly recessed seams
	wy = YY + 7.0 * pnoise(3001, 200, 70, 3) + 2.0 * pnoise(3002, 30, 20, 2)
	layer_id = np.floor(wy / 15.0)
	rng = np.random.default_rng(3003)
	tones = rng.uniform(0, 1, 64)
	tone = tones[(layer_id.astype(int) + 32) % 64]
	frac = wy / 15.0 - layer_id
	tone = np.clip(tone + 0.15 * pnoise(3004, 50, 8, 3), 0, 1)
	alb = ramp(tone, [(0.0, "7a5a36"), (0.5, "a8835a"), (1.0, "c9a878")])
	seam = smoothstep(0.12, 0.0, frac) + smoothstep(0.88, 1.0, frac)
	h = -1.2 * seam + 0.5 * pnoise(3005, 6, 3, 3) + 0.4 * smoothstep(0.0, 0.5, frac)
	nx, ny, nz = normals(h * 3.0, 0.9)
	img = light(alb, nx, ny, nz, 0.36, 0.04, 12.0)
	img *= (1 - 0.35 * seam)[..., None]
	st = Style(dark="6f4a2a", light="d3a46c", facet=False, bevel=0.7, strength=2.6, spec=0.14, spec_pow=12,
		spec_col=(1.0, 0.95, 0.85), ambient=0.26, grain=0.14, grain_scale=2.5, vertices=(8, 11),
		squash=(0.45, 0.7), shadow=0.55)
	draw_rocks(img, scatter(3006, 60, (40, H + 12), (14, 40), st.squash, 0.6), st, 3007)
	depth_fade(img, 0.35, 0.5)
	rip = 0.5 + 0.5 * np.sin(XX / 6.5 + 2.5 * pnoise(3008, 80, 30, 2))
	tex = 0.07 * (rip - 0.5) + 0.04 * pnoise(3009, 2.5, 2.5, 2)
	ledge(img, 3010, 22.0, 4.0, "f7e2b4", "c39d68", tex, edge_light=0.25, shadow=0.55)
	rim(img, "fff4dc", 0.65, 2.2)
	return img


def make_jupiter():
	img = matrix_rock(4001, "1a0c06", "33190c", scale=(22, 12), strength=1.4, ridged=True)
	# thin glowing magma seams deep in the matrix
	ember = smoothstep(0.3, 0.85, pridge(4002, 70, 26, 3, 0.08))
	img += (0.8 * ember * smoothstep(30, 100, YY))[..., None] * lin("ff6a14")[None, None, :]
	st = Style(dark="54290f", light="b8682c", facet=True, bevel=0.45, strength=3.0, spec=0.22, spec_pow=16,
		spec_col=(1.0, 0.85, 0.65), ambient=0.22, grain=0.18, grain_scale=2.2, vertices=(5, 8),
		squash=(0.5, 0.85), shadow=0.7)
	draw_rocks(img, scatter(4003, 120, (28, H + 15), (16, 44), st.squash, 0.48), st, 4004)
	depth_fade(img, 0.35, 0.55)
	tex = 0.12 * pnoise(4006, 4, 3, 3)
	ledge(img, 4007, 19.0, 3.5, "d88a4c", "7e4020", tex, edge_light=0.25, shadow=0.7)
	rim(img, "ffd9aa", 0.7, 2.2)
	return img


def make_mars():
	img = matrix_rock(5001, "4a1a0b", "7a2f15", scale=(26, 14), strength=1.2)
	st = Style(dark="6a250d", light="c85d2e", facet=False, bevel=0.5, strength=2.8, spec=0.15, spec_pow=14,
		spec_col=(1.0, 0.8, 0.65), ambient=0.24, grain=0.16, grain_scale=2.4, vertices=(6, 10),
		squash=(0.5, 0.8), shadow=0.65)
	draw_rocks(img, scatter(5002, 125, (30, H + 15), (12, 40), st.squash, 0.48), st, 5003)
	bas = Style(dark="2e1d19", light="6a463a", facet=True, bevel=0.45, strength=2.2, spec=0.2, spec_pow=20,
		spec_col=(1.0, 0.85, 0.8), ambient=0.28, grain=0.12, vertices=(5, 8), squash=(0.5, 0.8), shadow=0.65)
	draw_rocks(img, scatter(5004, 14, (45, H + 5), (10, 22), bas.squash, 0.5), bas, 5005)
	# fine dust settled on top of the rocks (lighter towards up-facing surfaces)
	dust = smoothstep(0.4, 0.9, 0.5 + 0.5 * pnoise(5006, 10, 6, 3)) * smoothstep(80, 30, YY)
	img[:] = mixc(img, lin("b2532a")[None, None, :], dust * 0.25)
	depth_fade(img, 0.35, 0.55)
	peb = smoothstep(0.80, 0.97, 0.5 + 0.5 * pnoise(5007, 2.6, 2.0, 2))
	tex = 0.08 * pnoise(5008, 5, 3, 3) - 0.3 * peb * smoothstep(6, 14, YY)
	ledge(img, 5009, 22.0, 4.0, "eb9564", "a0441f", tex, edge_light=0.25, shadow=0.6)
	rim(img, "ffcfae", 0.65, 2.2)
	return img


def make_earth():
	# soil: brown with darker clumps and small pebbles
	soil_t = np.clip(0.5 + 0.3 * pnoise(6001, 14, 9, 4), 0, 1)
	alb = ramp(soil_t, [(0.0, "2e1b0e"), (0.5, "4a2f19"), (1.0, "6a4526")])
	h = pnoise(6002, 5, 4, 4) + 0.6 * pnoise(6003, 16, 10, 3)
	nx, ny, nz = normals(h * 3.0, 0.9)
	img = light(alb, nx, ny, nz, 0.36, 0.02, 10.0)
	# roots
	root = smoothstep(0.3, 0.8, pridge(6004, 26, 60, 3, 0.07)) * smoothstep(100, 30, YY)
	img[:] = mixc(img, lin("8a6440")[None, None, :] * 0.75, root * 0.55)
	st = Style(dark="534b44", light="a89e90", facet=False, bevel=0.65, strength=2.6, spec=0.14, spec_pow=16,
		ambient=0.26, grain=0.14, grain_scale=2.2, vertices=(7, 10), squash=(0.5, 0.75), shadow=0.6)
	draw_rocks(img, scatter(6005, 60, (50, H + 14), (10, 38), st.squash, 0.65), st, 6006)
	depth_fade(img, 0.35, 0.55)
	# grass: blades with highlights, jagged lower edge hanging over the soil
	bd = 22.0 + 3.0 * pnoise(6007, 40, 40, 3, x=XX[0], y=np.zeros(W, F32))
	blade = 0.5 + 0.5 * pnoise(6008, 1.4, 10.0, 3)
	tips = bd[None, :] + 7.0 * (blade - 0.5) + 2.5 * np.sin(XX * 0.6 + 6.0 * pnoise(6009, 20, 20, 2))
	below = YY - tips
	sh = smoothstep(-1.0, 1.5, below) * np.exp(-np.maximum(below, 0) / 9.0)
	img *= (1 - 0.7 * sh)[..., None]
	t = np.clip(YY / np.maximum(tips, 1.0), 0, 1)
	grass = ramp(t, [(0.0, "a6e35e"), (0.35, "6cbf3c"), (1.0, "24601a")])
	stripes = 0.5 + 0.5 * np.sin(XX * 1.3 + 4 * pnoise(6010, 12, 30, 2))
	grass = grass * (0.82 + 0.25 * blade + 0.12 * stripes)[..., None]
	flowers = smoothstep(0.955, 1.0, 0.5 + 0.5 * pnoise(6011, 1.6, 1.6, 2)) * smoothstep(5, 8, YY) * smoothstep(16, 11, YY)
	grass = mixc(grass, lin("fff6c8")[None, None, :], flowers * 0.8)
	inside = smoothstep(tips + 1.2, tips - 1.2, YY)
	img[:] = img * (1 - inside[..., None]) + grass * inside[..., None]
	rim(img, "dcff9e", 0.6, 2.2)
	return img


MAKERS = {"neptune": make_neptune, "uranus": make_uranus, "saturn": make_saturn,
	"jupiter": make_jupiter, "mars": make_mars, "earth": make_earth}


def finish(lin_rgb, name, out_dir):
	from PIL import Image
	lin_d = np.clip(lin_rgb, 0, None).reshape(H_OUT, SS, W_OUT, SS, 3).mean(axis=(1, 3))
	out = np.clip(linear_to_srgb(lin_d), 0, 1)
	rng = np.random.default_rng(5)
	u8 = np.clip(np.round(out * 255 + rng.uniform(-0.5, 0.5, out.shape)), 0, 255).astype(np.uint8)
	rgba = np.concatenate([u8, np.full((H_OUT, W_OUT, 1), 255, np.uint8)], axis=2)
	os.makedirs(out_dir, exist_ok=True)
	path = os.path.join(out_dir, f"{name}.png")
	Image.fromarray(rgba, "RGBA").save(path, optimize=True)
	return path


def seam_ratio(path: str) -> float:
	"""Mean colour step across the wrap seam relative to the mean step between neighbouring columns."""
	from PIL import Image
	a = np.asarray(Image.open(path).convert("RGB"), np.float64)
	seam = np.abs(a[:, 0] - a[:, -1]).mean()
	inner = np.abs(a[:, 1:] - a[:, :-1]).mean()
	return seam / max(inner, 1e-6)


if __name__ == "__main__":
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	opts = {a.split("=")[0]: (a.split("=", 1)[1] if "=" in a else True) for a in sys.argv[1:] if a.startswith("--")}
	out = opts.get("--out", OUT_DEFAULT)
	for p in args or ORDER:
		path = finish(MAKERS[p](), p, out)
		print(f"[ground] {p} -> {path} (seam/neighbour step ratio {seam_ratio(path):.2f})", flush=True)
	if not opts.get("--no-sheet") and out == OUT_DEFAULT:
		from planets_post import build_mocks, build_sheet
		build_sheet()
		build_mocks()
