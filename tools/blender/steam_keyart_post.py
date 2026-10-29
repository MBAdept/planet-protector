"""Planet Protector Steam library artwork - 2-D compositing library (system python3: numpy, scipy, Pillow).

All layers are scene-linear float32. Rendered elements are premultiplied RGBA; the canvas is linear RGB.
Uses the game's own post helpers (tools/blender/ships_post.py: ring-free down-sampling, tone curve).
Every painted glow (flashes, beams, sparks, stars, fireballs) fades to exactly zero inside its own
box, so no glow tail can end in a visible edge on dark surfaces.
"""
from __future__ import annotations

import json
import math
import os
import sys

sys.dont_write_bytecode = True  # keep tools/blender free of __pycache__ from these runs

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
from scipy import ndimage  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
# the game repo (default: this file lives in <repo>/tools/blender); PP_REPO overrides it
REPO = os.environ.get("PP_REPO") or os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(REPO, "tools", "blender")
if TOOLS not in sys.path:
	sys.path.insert(0, TOOLS)
import ships_post as SP  # noqa: E402

F32 = np.float32

# game colour language (linear-ish values as used by the game's draw code)
LASER_GLOW = np.array([0.16, 0.48, 1.0], F32)
LASER_BODY = np.array([0.38, 0.74, 1.0], F32)
LASER_CORE = np.array([0.88, 0.97, 1.0], F32)
FIRE_HALO = np.array([1.0, 0.32, 0.06], F32)
FIRE_TAIL = np.array([1.0, 0.36, 0.06], F32)
FIRE_TAIL_END = np.array([0.9, 0.12, 0.02], F32)
FIRE_INNER = np.array([1.0, 0.86, 0.45], F32)
FIRE_CORE = np.array([1.0, 0.74, 0.28], F32)
ATMO = np.array([0.42, 0.68, 1.0], F32)
NEB_BLUE = np.array([0.045, 0.08, 0.19], F32)
NEB_VIOLET = np.array([0.11, 0.035, 0.15], F32)
OUTLINE = np.array([0.42, 0.47, 0.62], F32)   # game: enemy.gdshader outline_color of black enemies


# ------------------------------------------------------------------------------------------------
# basics
# ------------------------------------------------------------------------------------------------
def srgb_to_lin(c):
	c = np.clip(c, 0.0, 1.0)
	return np.where(c <= 0.04045, c / 12.92, np.power((c + 0.055) / 1.055, 2.4)).astype(F32)


def lin_to_srgb(c):
	c = np.clip(c, 0.0, 1.0)
	return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055).astype(F32)


def load_npy(path):
	return np.load(path).astype(F32)


def load_meta(path):
	with open(path) as f:
		return json.load(f)


def resize(p, w, h):
	"""High quality resize of a premultiplied RGBA (or RGB) float image (ring-free when shrinking)."""
	w, h = max(1, int(round(w))), max(1, int(round(h)))
	if p.shape[2] == 3:
		p = np.concatenate([p, np.ones(p.shape[:2] + (1,), F32)], axis=-1)
		return resize(p, w, h)[..., :3]
	if w <= p.shape[1] and h <= p.shape[0]:
		return SP.downsample(p, w, h).astype(F32)
	return SP.resize(p, w, h, Image.Resampling.LANCZOS, premult_clamp=False).astype(F32)


def scale_to_width(p, w):
	return resize(p, w, p.shape[0] * w / p.shape[1])


def rotate(p, deg):
	"""Rotates a premultiplied RGBA float image about its centre (canvas grows)."""
	if abs(deg) < 1e-3:
		return p
	ch = []
	for i in range(p.shape[2]):
		im = Image.fromarray(np.ascontiguousarray(p[..., i]), mode="F")
		ch.append(np.asarray(im.rotate(deg, resample=Image.Resampling.BICUBIC, expand=True), F32))
	out = np.stack(ch, -1)
	out[..., 3] = np.clip(out[..., 3], 0, 1)
	out[..., :3] = np.clip(out[..., :3], 0, None)
	return out


def alpha_bbox(p, thr=0.02):
	ys, xs = np.where(p[..., 3] > thr)
	return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def crop_to_alpha(p, margin=4, thr=0.004):
	x0, y0, x1, y1 = alpha_bbox(p, thr)
	x0, y0 = max(0, x0 - margin), max(0, y0 - margin)
	x1, y1 = min(p.shape[1], x1 + margin), min(p.shape[0], y1 + margin)
	return p[y0:y1, x0:x1], (x0, y0)


def _region(dst_shape, src_shape, x, y):
	H, W = dst_shape[:2]
	h, w = src_shape[:2]
	x0, y0 = max(0, x), max(0, y)
	x1, y1 = min(W, x + w), min(H, y + h)
	if x1 <= x0 or y1 <= y0:
		return None
	return (slice(y0, y1), slice(x0, x1)), (slice(y0 - y, y1 - y), slice(x0 - x, x1 - x))


def over(canvas, src, x, y, opacity=1.0):
	"""canvas RGB (linear) <- premultiplied RGBA src at integer top-left (x, y)."""
	r = _region(canvas.shape, src.shape, int(round(x)), int(round(y)))
	if r is None:
		return
	d, s = r
	sp = src[s]
	a = sp[..., 3:4] * opacity
	canvas[d] = canvas[d] * (1.0 - a) + sp[..., :3] * opacity


def add(canvas, src_rgb, x, y, k=1.0):
	r = _region(canvas.shape, src_rgb.shape, int(round(x)), int(round(y)))
	if r is None:
		return
	d, s = r
	canvas[d] += src_rgb[s][..., :3] * k


def place_centered(canvas, src, cx, cy, opacity=1.0):
	over(canvas, src, cx - src.shape[1] / 2.0, cy - src.shape[0] / 2.0, opacity)


# ------------------------------------------------------------------------------------------------
# blur / noise
# ------------------------------------------------------------------------------------------------
def blur(img, sigma):
	"""Gaussian blur (per channel); large sigmas via a down-sampled pyramid step."""
	if sigma <= 0.3:
		return img.copy()
	if img.ndim == 2:
		return blur(img[..., None], sigma)[..., 0]
	h, w = img.shape[:2]
	if sigma > 6.0:
		k = int(sigma / 3.0)
		sw, sh = max(2, w // k), max(2, h // k)
		small = np.stack([np.asarray(Image.fromarray(np.ascontiguousarray(img[..., i])).resize((sw, sh), Image.Resampling.BOX), F32)
			for i in range(img.shape[2])], -1)
		small = np.stack([ndimage.gaussian_filter(small[..., i], sigma * sw / w, mode="nearest") for i in range(img.shape[2])], -1)
		return np.stack([np.asarray(Image.fromarray(np.ascontiguousarray(small[..., i])).resize((w, h), Image.Resampling.BICUBIC), F32)
			for i in range(img.shape[2])], -1)
	return np.stack([ndimage.gaussian_filter(img[..., i], sigma, mode="nearest") for i in range(img.shape[2])], -1).astype(F32)


def value_noise(h, w, cell, rng):
	"""Smooth value noise in [-1, 1] with feature size ~cell px."""
	gh, gw = int(math.ceil(h / cell)) + 4, int(math.ceil(w / cell)) + 4
	g = rng.standard_normal((gh, gw)).astype(F32)
	z = ndimage.zoom(g, cell, order=3, mode="grid-wrap")
	oy, ox = int(rng.integers(0, cell)), int(rng.integers(0, cell))
	z = z[oy:oy + h, ox:ox + w]
	return z / (np.std(z) + 1e-6) * 0.5


def fbm(h, w, cell, octaves, seed, gain=0.5, lac=2.0):
	rng = np.random.default_rng(seed)
	out = np.zeros((h, w), F32)
	amp, c, tot = 1.0, float(cell), 0.0
	for _ in range(octaves):
		if c < 1.5:
			break
		out += amp * value_noise(h, w, max(2, int(round(c))), rng)
		tot += amp
		amp *= gain
		c /= lac
	return out / max(tot, 1e-6)


def smoothstep(e0, e1, x):
	t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


def fade_out(dist, edge, start=0.65):
	"""1 inside, smoothly 0 at dist >= edge: multiplied into every painted glow so that its tail ends
	inside its box instead of at the box border (no seams on dark surfaces)."""
	return 1.0 - smoothstep(start * edge, edge, dist)


# ------------------------------------------------------------------------------------------------
# sky
# ------------------------------------------------------------------------------------------------
def sky(h, w, seed=1, base_top=(0.004, 0.006, 0.02), base_bottom=(0.012, 0.016, 0.042), neb=1.0, scale=1.0,
		warm=None, cool=None, dust=0.6, c1=None, c2=None):
	"""Deep space: vertical gradient + the game's two nebula tints (blue / violet) + dust lanes.
	warm / cool: optional lists of (cx, cy, rx, ry, colour, strength) soft light pools (canvas px)."""
	yy = np.linspace(0, 1, h, dtype=F32)[:, None, None]
	img = np.array(base_top, F32) * (1 - yy) + np.array(base_bottom, F32) * yy
	img = np.broadcast_to(img, (h, w, 3)).copy()
	cell = 420.0 * scale
	n1 = fbm(h, w, cell, 7, seed)
	n2 = fbm(h, w, cell * 0.8, 7, seed + 1)
	d = fbm(h, w, cell * 0.45, 6, seed + 2)
	m1 = smoothstep(-0.15, 0.75, n1) ** 1.6
	m2 = smoothstep(-0.05, 0.8, n2) ** 1.8
	lanes = 1.0 - dust * smoothstep(0.05, 0.6, d) * 0.85
	k1 = NEB_BLUE if c1 is None else np.array(c1, F32)
	k2 = NEB_VIOLET if c2 is None else np.array(c2, F32)
	img += (k1[None, None, :] * m1[..., None] * 1.6 + k2[None, None, :] * m2[..., None] * 1.4) * neb * lanes[..., None]
	yy2, xx2 = np.mgrid[0:h, 0:w].astype(F32)
	for pools, sgn in ((warm or [], 1.0), (cool or [], 1.0)):
		for (cx, cy, rx, ry, col, k) in pools:
			r2 = ((xx2 - cx) / rx) ** 2 + ((yy2 - cy) / ry) ** 2
			g = np.exp(-r2 * 1.6) * (0.55 + 0.45 * smoothstep(-0.4, 0.8, n1 + 0.3 * n2))
			img += np.array(col, F32)[None, None, :] * (g * k * lanes)[..., None]
	return img


def stars(h, w, seed=3, density=1.0, scale=1.0, bright=12, spikes=3, avoid=None, spike_len=0.6):
	"""Additive star layer (linear RGB): many faint points, some medium, a few bright with soft halos;
	only the first `spikes` bright stars get thin four-point spikes (like the game's sparkle stars),
	`spike_len` times the classic length. avoid(x, y) -> True keeps bright stars away from the characters
	(their halo and spikes would otherwise show through anti-aliased edges and bloom over them)."""
	rng = np.random.default_rng(seed)
	out = np.zeros((h, w, 3), F32)
	tints = np.array([(1.0, 1.0, 1.0), (0.8, 0.88, 1.0), (0.7, 0.82, 1.0), (1.0, 0.92, 0.8), (1.0, 0.82, 0.66)], F32)
	tw = np.array([0.42, 0.26, 0.12, 0.14, 0.06])
	n = int(w * h / 900 * density)
	# clustered: half follow a noise density map
	dens = smoothstep(-0.2, 0.9, fbm(h, w, 300 * scale, 4, seed + 7)) + 0.25
	xs = rng.uniform(0, w, n * 2)
	ys = rng.uniform(0, h, n * 2)
	keep = rng.uniform(0, 1.25, n * 2) < dens[ys.astype(int).clip(0, h - 1), xs.astype(int).clip(0, w - 1)]
	xs, ys = xs[keep][:n], ys[keep][:n]
	b = (rng.uniform(0, 1, len(xs)) ** 3.2) * 0.9 + 0.03
	cols = tints[rng.choice(len(tints), len(xs), p=tw / tw.sum())]
	# bilinear splat (sub-pixel positions)
	x0 = np.floor(xs).astype(int)
	y0 = np.floor(ys).astype(int)
	fx, fy = xs - x0, ys - y0
	for dx, dy, wgt in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
		xx, yy = np.clip(x0 + dx, 0, w - 1), np.clip(y0 + dy, 0, h - 1)
		np.add.at(out, (yy, xx), cols * (b * wgt)[:, None])
	out = out + blur(out, 0.6 * scale) * 0.6
	# bright stars with halo + spikes
	for i in range(bright):
		ok = False
		for _try in range(60):
			x, y = rng.uniform(0.03, 0.97) * w, rng.uniform(0.03, 0.97) * h
			if avoid is None or not avoid(x, y):
				ok = True
				break
		col = tints[rng.choice(len(tints), p=tw / tw.sum())]
		size = rng.uniform(0.6, 1.4) * scale
		k = rng.uniform(0.5, 1.2)
		if ok:
			star_sprite(out, x, y, size, col, k, spikes=i < spikes, spike_len=spike_len)
	return out


def star_sprite(out, x, y, size, col, k=1.0, spikes=True, spike_len=1.0):
	h, w = out.shape[:2]
	R = int(40 * size) + 2
	x0, y0 = int(x) - R, int(y) - R
	yy, xx = np.mgrid[y0:y0 + 2 * R + 1, x0:x0 + 2 * R + 1].astype(F32)
	dx, dy = xx - x, yy - y
	r = np.sqrt(dx * dx + dy * dy)
	g = 1.4 * np.exp(-(r / (1.1 * size)) ** 2) + 0.12 * np.exp(-r / (5.0 * size))
	if spikes:
		L = 11.0 * size * spike_len
		sx = np.exp(-(dy / (0.55 * size)) ** 2) * np.exp(-np.abs(dx) / L)
		sy = np.exp(-(dx / (0.55 * size)) ** 2) * np.exp(-np.abs(dy) / L)
		g += 0.35 * (sx + sy)
	g *= k * fade_out(r, R)
	src = g[..., None] * np.array(col, F32)[None, None, :]
	add(out, src, x0, y0)


# ------------------------------------------------------------------------------------------------
# Earth + atmosphere
# ------------------------------------------------------------------------------------------------
def earth_layer(canvas, earth, meta, cx, cy, R, to_sun_img, atmo=ATMO, rim=1.0, halo=1.0, haze=1.0,
		night_rim=0.18, twilight=(1.0, 0.45, 0.2), twilight_k=0.35, sat=1.0, gamma=1.0, gain=1.0):
	"""Places the rendered Earth (window render, meta from steam_keyart_models.render_earth) with centre
	(cx, cy) and radius R (canvas px) and adds the atmosphere analytically. to_sun_img: (x right, y down,
	z to viewer)."""
	H, W = canvas.shape[:2]
	s = R / meta["r_px"]
	x0, x1, y0, y1 = meta["window"]
	left = cx + x0 * R
	top = cy - y1 * R
	ew = (x1 - x0) * R
	eh = (y1 - y0) * R
	# only the part that is on the canvas
	cl, ct = max(0.0, left), max(0.0, top)
	cr, cb = min(float(W), left + ew), min(float(H), top + eh)
	if cr > cl and cb > ct:
		sx0 = (cl - left) / s
		sy0 = (ct - top) / s
		sx1 = (cr - left) / s
		sy1 = (cb - top) / s
		pad = 4
		ix0, iy0 = max(0, int(sx0) - pad), max(0, int(sy0) - pad)
		ix1, iy1 = min(earth.shape[1], int(math.ceil(sx1)) + pad), min(earth.shape[0], int(math.ceil(sy1)) + pad)
		sub = earth[iy0:iy1, ix0:ix1]
		tw_, th_ = (ix1 - ix0) * s, (iy1 - iy0) * s
		sub = resize(sub, tw_, th_)
		if sat != 1.0 or gamma != 1.0 or gain != 1.0:
			a_ = sub[..., 3:4]
			c_ = sub[..., :3] / np.maximum(a_, 1e-5)
			lum = (c_ * np.array([0.2126, 0.7152, 0.0722], F32)).sum(-1, keepdims=True)
			c_ = np.clip(lum + (c_ - lum) * sat, 0, None)
			c_ = np.power(c_, gamma) * gain
			sub = np.concatenate([c_ * a_, a_], -1).astype(F32)
		over(canvas, sub, left + ix0 * s, top + iy0 * s)
	# atmosphere
	L = np.array(to_sun_img, F32)
	L /= np.linalg.norm(L)
	yy, xx = np.mgrid[0:H, 0:W].astype(F32)
	dx = (xx + 0.5 - cx) / R
	dy = (yy + 0.5 - cy) / R
	r = np.sqrt(dx * dx + dy * dy)
	rr = np.maximum(r, 1e-6)
	mu = np.sqrt(np.clip(1.0 - r * r, 0.0, 1.0))
	nl_out = (dx / rr) * L[0] + (dy / rr) * L[1] + 0.0 * L[2]
	nl_in = dx * L[0] + dy * L[1] + mu * L[2]
	lit_out = smoothstep(-0.35, 0.6, nl_out)
	lit_in = smoothstep(-0.2, 0.5, nl_in)
	px = 1.0 / R
	outside = smoothstep(1.0 - 1.2 * px, 1.0 + 0.8 * px, r)
	d = np.maximum(r - 1.0, 0.0)
	# thin bright rim + soft wide halo; faint blue rim also on the night side (scattered light)
	glow = (rim * (np.exp(-d / 0.0045) * 0.9 + np.exp(-d / 0.014) * 0.55) + halo * np.exp(-d / 0.055) * 0.35)
	glow *= (night_rim + (1.0 - night_rim) * lit_out) * outside
	# inner haze toward the limb (long path through the air), only on the day side
	g_in = haze * 0.85 * np.exp(-mu / 0.16) * lit_in * (r < 1.0)
	col = np.array(atmo, F32)
	canvas += col[None, None, :] * glow[..., None]
	canvas += col[None, None, :] * g_in[..., None] * 0.9
	# twilight: warm tint of the rim just around the terminator
	if twilight_k > 0:
		tl = np.exp(-((nl_out - 0.02) / 0.16) ** 2) * np.exp(-d / 0.02) * outside
		canvas += np.array(twilight, F32)[None, None, :] * (tl * twilight_k)[..., None]
	return r


# ------------------------------------------------------------------------------------------------
# lasers, fireballs, flashes
# ------------------------------------------------------------------------------------------------
def _seg_dist(xx, yy, p0, p1):
	px, py = p1[0] - p0[0], p1[1] - p0[1]
	L2 = px * px + py * py
	t = np.clip(((xx - p0[0]) * px + (yy - p0[1]) * py) / max(L2, 1e-6), 0.0, 1.0)
	cxp, cyp = p0[0] + t * px, p0[1] + t * py
	return np.sqrt((xx - cxp) ** 2 + (yy - cyp) ** 2), t


def beam(canvas, p0, p1, w0, w1, k=1.0, glow=1.0, core=1.0, fade0=0.0, fade1=0.0):
	"""Laser bolt from p0 to p1 (canvas px), half-width w0 at p0 -> w1 at p1 (perspective taper).
	Bright white-blue core, blue body, wide soft blue glow (game colours)."""
	H, W = canvas.shape[:2]
	m = 40.0 * max(w0, w1) + 4
	bx0, by0 = int(max(0, min(p0[0], p1[0]) - m)), int(max(0, min(p0[1], p1[1]) - m))
	bx1, by1 = int(min(W, max(p0[0], p1[0]) + m)), int(min(H, max(p0[1], p1[1]) + m))
	if bx1 <= bx0 or by1 <= by0:
		return
	yy, xx = np.mgrid[by0:by1, bx0:bx1].astype(F32)
	dist, t = _seg_dist(xx + 0.5, yy + 0.5, p0, p1)
	wid = w0 + (w1 - w0) * t
	u = dist / np.maximum(wid, 1e-3)
	# the fades along the bolt shape only its narrow core and body: applied to the wide glow they would cut
	# it along a straight line through the end point (a visible seam across whatever lies there); the glow
	# simply rounds off around both ends (capsule distance)
	along = np.ones_like(t)
	if fade0 > 0:
		along *= smoothstep(0.0, fade0, t)
	if fade1 > 0:
		along *= 1.0 - smoothstep(1.0 - fade1, 1.0, t)
	c_core = np.exp(-(u / 0.42) ** 2) * 2.6 * core * along
	c_body = np.exp(-(u / 1.0) ** 2) * 1.2 * along
	c_glow = (np.exp(-(u / 3.2) ** 2) * 0.45 + np.exp(-u / 9.0) * 0.12) * glow * fade_out(dist, m - 2.0)
	img = (LASER_CORE[None, None, :] * c_core[..., None] + LASER_BODY[None, None, :] * c_body[..., None]
		+ LASER_GLOW[None, None, :] * c_glow[..., None]) * k
	canvas[by0:by1, bx0:bx1] += img


def flash(canvas, x, y, radius, color=(1.0, 0.62, 0.25), k=1.0, core=(1.0, 0.95, 0.85), rays=10, seed=5,
		ray_len=1.6, ring=0.0):
	"""Impact burst: hot core, coloured glow, thin rays."""
	H, W = canvas.shape[:2]
	R = int(radius * (ray_len + 4.0)) + 2
	x0, y0 = int(x) - R, int(y) - R
	yy, xx = np.mgrid[y0:y0 + 2 * R + 1, x0:x0 + 2 * R + 1].astype(F32)
	dx, dy = xx + 0.5 - x, yy + 0.5 - y
	win = fade_out(np.sqrt(dx * dx + dy * dy), R - 1.0, 0.55)
	r = np.sqrt(dx * dx + dy * dy) / radius
	a = np.arctan2(dy, dx)
	g = np.exp(-(r / 0.22) ** 2) * 3.0
	c = np.exp(-(r / 0.6) ** 2) * 1.1 + np.exp(-r / 1.1) * 0.35
	rng = np.random.default_rng(seed)
	ray = np.zeros_like(r)
	for _ in range(rays):
		ang = rng.uniform(-math.pi, math.pi)
		ln = rng.uniform(0.6, 1.0) * ray_len
		wd = rng.uniform(0.012, 0.03)
		da = np.abs(np.angle(np.exp(1j * (a - ang))))
		ray += np.exp(-(da / wd) ** 2) * np.exp(-r / (0.45 * ln)) * smoothstep(0.05, 0.25, r) * rng.uniform(0.5, 1.0)
	if ring > 0:
		c += ring * np.exp(-((r - 1.25) / 0.06) ** 2) * 0.5
	img = np.array(core, F32)[None, None, :] * g[..., None] + np.array(color, F32)[None, None, :] * (c + 0.8 * ray)[..., None]
	add(canvas, img * (k * win)[..., None], x0, y0)


def fireball(canvas, x, y, vx, vy, size, k=1.0, seed=0, tail=1.0):
	"""A falling fireball in the game's colours (ProjectileArt.draw_enemy_bullet), drawn as a comet for
	the key art: white-hot core, orange halo, long tapered flame trail (yellow -> orange -> deep red)
	opposite to the motion, a faint wide heat trail and embers. size ~ the game's scale factor."""
	s = size
	d = np.array([vx, vy], F32)
	d /= np.linalg.norm(d) + 1e-9
	back = -d
	side = np.array([-back[1], back[0]], F32)
	L = 95.0 * s * tail
	R = int(L + 30 * s) + 4
	x0, y0 = int(x) - R, int(y) - R
	yy, xx = np.mgrid[y0:y0 + 2 * R + 1, x0:x0 + 2 * R + 1].astype(F32)
	px, py = xx + 0.5 - x, yy + 0.5 - y
	u = px * back[0] + py * back[1]          # along the trail (> 0 behind the head)
	v = px * side[0] + py * side[1]
	r = np.sqrt(px * px + py * py)
	rng = np.random.default_rng(seed)
	img = np.zeros(r.shape + (3,), F32)
	t = np.clip(u / L, 0.0, 1.0)
	behind = smoothstep(-2.5 * s, 1.5 * s, u) * (u < L)
	# slight wobble of the trail
	ph = rng.uniform(0, 6.28)
	wob = (np.sin(t * 7.0 + ph) * 0.9 + np.sin(t * 13.0 + ph * 1.7) * 0.4) * s * t
	vv = v - wob
	# main flame: width tapers from the head, colour runs yellow -> orange -> red
	half = (5.2 * s) * (1.0 - t) ** 0.65 + 0.35
	flame = np.exp(-(vv / half) ** 2 * 1.6) * behind * (1.0 - t) ** 1.2
	c_head = np.array([1.0, 0.78, 0.32], F32)
	c_mid = FIRE_TAIL
	c_end = FIRE_TAIL_END
	tc = t[..., None]
	col = np.where(tc < 0.25, c_head * (1 - tc / 0.25) + c_mid * (tc / 0.25),
		c_mid * (1 - (tc - 0.25) / 0.75) + c_end * ((tc - 0.25) / 0.75))
	img += col * (flame * 1.5)[..., None]
	# inner hot streak
	half2 = (2.2 * s) * (1.0 - t) ** 0.8 + 0.25
	inner = np.exp(-(vv / half2) ** 2 * 1.8) * behind * np.clip(1.0 - t / 0.45, 0, 1) ** 1.5
	img += FIRE_INNER * (inner * 1.6)[..., None]
	# wide heat glow around the trail
	wide = np.exp(-(vv / (14.0 * s * (0.4 + t))) ** 2) * behind * (1.0 - t) ** 2.0
	img += np.array([1.0, 0.28, 0.05], F32) * (wide * 0.35)[..., None]
	# embers along the trail
	for _ in range(int(10 * tail) + 4):
		eu = rng.uniform(0.15, 1.05) * L
		ev = rng.normal(0, 4.0 * s) * (0.5 + eu / L)
		er = rng.uniform(0.5, 1.1) * s
		e = np.exp(-(((u - eu) ** 2 + (v - ev) ** 2) / (er * er)))
		img += np.array([1.0, 0.55, 0.15], F32) * (e * rng.uniform(0.5, 1.2) * (1.0 - 0.8 * eu / L))[..., None]
	# head: halo + core
	img += FIRE_HALO * (np.exp(-(r / (13.0 * s)) ** 2) * 0.45 + np.exp(-r / (15.0 * s)) * 0.12)[..., None]
	img += np.array([1.0, 0.42, 0.08], F32) * (np.exp(-(r / (6.0 * s)) ** 2) * 1.5)[..., None]
	img += FIRE_CORE * (np.exp(-(r / (3.8 * s)) ** 2) * 2.0)[..., None]
	img += np.array([1.0, 0.98, 0.88], F32) * (np.exp(-(r / (2.2 * s)) ** 2) * 3.0)[..., None]
	add(canvas, img * (k * fade_out(r, R - 1.0, 0.8))[..., None], x0, y0)


def glow_dot(canvas, x, y, radius, color, k=1.0):
	R = int(radius * 5) + 2
	x0, y0 = int(x) - R, int(y) - R
	yy, xx = np.mgrid[y0:y0 + 2 * R + 1, x0:x0 + 2 * R + 1].astype(F32)
	rp = np.sqrt((xx + 0.5 - x) ** 2 + (yy + 0.5 - y) ** 2)
	r = rp / radius
	g = (np.exp(-r * r) + 0.25 * np.exp(-r)) * fade_out(rp, R - 1.0, 0.6)
	add(canvas, np.array(color, F32)[None, None, :] * (g * k)[..., None], x0, y0)


def backlight(canvas, cx, cy, rx, ry, inner=(0.9, 0.22, 0.12), outer=(0.36, 0.1, 0.5), k=1.0, power=1.0):
	"""Light-behind-dark staging (like the red glow behind the demon of game/icon.png): a soft elliptical
	glow, warm red in the middle fading through violet, painted BEHIND a dark character so its
	silhouette separates by value as well as by hue."""
	H, W = canvas.shape[:2]
	x0, x1 = int(max(0, cx - 2.2 * rx)), int(min(W, cx + 2.2 * rx))
	y0, y1 = int(max(0, cy - 2.2 * ry)), int(min(H, cy + 2.2 * ry))
	if x1 <= x0 or y1 <= y0:
		return
	yy, xx = np.mgrid[y0:y1, x0:x1].astype(F32)
	q = np.sqrt(((xx + 0.5 - cx) / rx) ** 2 + ((yy + 0.5 - cy) / ry) ** 2)
	g = np.exp(-(q ** 2) * 1.6) ** power
	t = np.clip(q / 1.3, 0, 1)[..., None]
	col = np.array(inner, F32) * (1 - t) + np.array(outer, F32) * t
	canvas[y0:y1, x0:x1] += col * (g * k * fade_out(q, 2.15, 0.7))[..., None]


def rim_glow(alpha, sigma, inside=0.0):
	"""Soft outline mask of a character from its (canvas-sized) coverage: the part of a small blur that
	falls outside the silhouette (+ `inside` times the part just inside the edge)."""
	b = blur(alpha[..., None], sigma)[..., 0]
	out = np.clip(b - alpha, 0, 1)
	if inside > 0:
		er = blur((1.0 - alpha)[..., None], sigma)[..., 0] * alpha
		out = out + inside * er
	return out


# ------------------------------------------------------------------------------------------------
# finishing
# ------------------------------------------------------------------------------------------------
def bloom(img, thr=0.9, levels=((4, 0.5), (14, 0.35), (40, 0.25), (110, 0.12)), k=1.0, scale=1.0):
	b = np.clip(img - thr, 0.0, None)
	m = b.max(axis=-1, keepdims=True)
	out = img.copy()
	for s, w in levels:
		out += blur(b, s * scale) * w * k
	return out


def tonemap(img):
	return SP.tonemap(np.clip(img, 0.0, None)).astype(F32)


def grade(img, lift=(0.0, 0.004, 0.012), gain=(1.0, 1.0, 1.0), sat=1.08, contrast=1.06, vignette=0.35,
		vig_center=(0.5, 0.5), vig_aspect=1.0, warm_hi=0.0, mids=0.0):
	"""Display-linear (0..1, after tone map) grading: lift/gain, saturation, mild S contrast in sRGB space,
	mid-tone lift (`mids`: sRGB value += mids * 4 v (1 - v), i.e. +mids at mid grey, 0 at black / white),
	elliptical vignette."""
	h, w = img.shape[:2]
	c = img * np.array(gain, F32) + np.array(lift, F32) * (1 - img)
	lum = (c * np.array([0.2126, 0.7152, 0.0722], F32)).sum(-1, keepdims=True)
	c = lum + (c - lum) * sat
	if warm_hi > 0:
		c += warm_hi * np.clip(lum - 0.5, 0, 1) * np.array([0.06, 0.02, -0.04], F32)
	s = lin_to_srgb(np.clip(c, 0, 1))
	s = np.clip(0.5 + (s - 0.5) * contrast, 0, 1)
	if mids:
		s = np.clip(s + mids * 4.0 * s * (1.0 - s), 0, 1)
	if vignette > 0:
		yy, xx = np.mgrid[0:h, 0:w].astype(F32)
		dx = (xx / w - vig_center[0]) * vig_aspect
		dy = (yy / h - vig_center[1])
		r = np.sqrt(dx * dx + dy * dy) / 0.75
		s *= (1.0 - vignette * smoothstep(0.35, 1.1, r) ** 1.4)[..., None]
	return srgb_to_lin(s)


def to_u8(img_lin, seed=9):
	s = lin_to_srgb(np.clip(img_lin, 0, 1))
	rng = np.random.default_rng(seed)
	s = s * 255.0 + rng.uniform(-0.5, 0.5, s.shape).astype(F32)
	return np.clip(np.round(s), 0, 255).astype(np.uint8)


def save_png(u8, path):
	"""8-bit RGB / RGBA (straight alpha) PNG, tagged sRGB (sRGB chunk), maximum zlib compression."""
	from PIL import PngImagePlugin
	os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
	info = PngImagePlugin.PngInfo()
	info.add(b"sRGB", b"\x00")   # rendering intent: perceptual
	Image.fromarray(u8, "RGBA" if u8.shape[2] == 4 else "RGB").save(path, optimize=True, pnginfo=info)


def save_rgb(img_lin, path):
	save_png(to_u8(img_lin), path)


# ------------------------------------------------------------------------------------------------
# logo
# ------------------------------------------------------------------------------------------------
def load_logo_png(path):
	"""Game logo (sRGB, straight alpha) -> premultiplied linear RGBA float."""
	a = np.asarray(Image.open(path).convert("RGBA")).astype(F32) / 255.0
	c = srgb_to_lin(a[..., :3])
	return np.concatenate([c * a[..., 3:4], a[..., 3:4]], -1)


def logo_over(canvas_disp, logo, x, y, width, shadow=0.75, shadow_sigma=None, shadow_grow=1.0):
	"""Composites the logo (premult linear RGBA) onto a DISPLAY-linear canvas (after tone map/grade),
	with a soft dark backing shadow for legibility on busy art."""
	lg = scale_to_width(logo, width)
	h, w = lg.shape[:2]
	if shadow > 0:
		sig = shadow_sigma or max(2.0, width * 0.018)
		a = lg[..., 3]
		pad = int(sig * 4)
		big = np.pad(a, pad)
		if shadow_grow > 0:
			big = ndimage.grey_dilation(big, size=(int(sig * shadow_grow) * 2 + 1,) * 2)
		sh = blur(big[..., None], sig)[..., 0]
		sh = np.clip(sh * 1.3, 0, 1) * shadow
		r = _region(canvas_disp.shape, sh.shape, int(round(x)) - pad, int(round(y)) - pad)
		if r is not None:
			d, s = r
			canvas_disp[d] *= (1.0 - sh[s])[..., None]
	over(canvas_disp, lg, x, y)
	return w, h
