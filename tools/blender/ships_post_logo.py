"""Post-processing for the title logo and the app icon (system python3: numpy + Pillow + scipy).

Called by ships_post.py:  process(work_dir, project_root)
- logo.png (1600 x 420): tone-mapped letters + a soft orange outer-glow halo (premultiplied add,
  stored as straight alpha so it reads as glow over the dark title background).
- icon.png (256 x 256): rounded dark tile, red nebula glow, Blender-rendered demon silhouette and the
  Interceptor (with exhaust) in front; transparent outside the rounded corners.
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image

import ships_post as P


def _halo(p: np.ndarray, thr: float, sigmas, weights, tint=None) -> np.ndarray:
	c = p[..., :3]
	bright = np.clip(c - thr, 0.0, None)
	if tint is not None:
		lum = bright.max(axis=-1, keepdims=True)
		bright = lum * np.asarray(tint, np.float32)
	h = np.zeros_like(bright)
	for s, w in zip(sigmas, weights):
		h += P.blur_premult(bright, s) * w
	return h


def _over_halo(letters: np.ndarray, halo_rgb: np.ndarray) -> np.ndarray:
	"""letters: premult linear RGBA (already tone-mapped); halo: linear rgb (additive light)."""
	a = letters[..., 3:4]
	ha = np.clip(halo_rgb.max(axis=-1, keepdims=True), 0.0, 1.0)
	h = np.clip(halo_rgb, 0.0, 1.0)
	rgb = letters[..., :3] + h * (1.0 - a)
	alpha = a + ha * (1.0 - a)
	return np.concatenate([np.minimum(rgb, alpha), alpha], axis=-1)


def process_logo(work: str, root: str) -> None:
	src = os.path.join(work, "logo", "logo.npy")
	if not os.path.exists(src):
		return
	p = P.load(src)
	halo = _halo(p, 0.45, (6.0, 18.0), (0.6, 0.45), tint=(1.0, 0.32, 0.06))
	# fade the halo out towards the canvas border so no hard edge can show over the background
	h, w = halo.shape[:2]
	fy = np.clip(np.minimum(np.arange(h), h - 1 - np.arange(h)) / 34.0, 0.0, 1.0)
	fx = np.clip(np.minimum(np.arange(w), w - 1 - np.arange(w)) / 34.0, 0.0, 1.0)
	win = (fy[:, None] * fx[None, :]) ** 1.5
	halo = halo * (win * win * (3.0 - 2.0 * win))[..., None]
	letters = P.tonemap_premult(p)
	out = _over_halo(letters, halo)
	rgba = P.premult_linear_to_rgba8(out)
	dst = os.path.join(root, "game", "assets", "sprites", "ui", "logo.png")
	P.save_png(rgba, dst)
	print("[post] logo.png %dx%d visual bbox=%s" % (rgba.shape[1], rgba.shape[0], P.alpha_bbox(rgba, 128)))


def _rounded_mask(n: int, r: float, ss: int = 4) -> np.ndarray:
	m = n * ss
	yy, xx = np.mgrid[0:m, 0:m].astype(np.float32) / ss + 0.5 / ss
	cx = np.clip(xx, r, n - r)
	cy = np.clip(yy, r, n - r)
	d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
	inside = (d <= r).astype(np.float32)
	return inside.reshape(n, ss, n, ss).mean(axis=(1, 3))


def _place(dst: np.ndarray, src: np.ndarray, x: int, y: int) -> None:
	"""Premultiplied 'over' of src (h,w,4) at integer position."""
	h, w = src.shape[:2]
	H, W = dst.shape[:2]
	x0, y0 = max(0, x), max(0, y)
	x1, y1 = min(W, x + w), min(H, y + h)
	if x1 <= x0 or y1 <= y0:
		return
	s = src[y0 - y:y1 - y, x0 - x:x1 - x]
	d = dst[y0:y1, x0:x1]
	d[..., :3] = s[..., :3] + d[..., :3] * (1.0 - s[..., 3:4])
	d[..., 3:4] = s[..., 3:4] + d[..., 3:4] * (1.0 - s[..., 3:4])


def process_icon(work: str, root: str) -> None:
	dsrc = os.path.join(work, "icon", "demon.npy")
	ssrc = os.path.join(work, "icon", "ship.npy")
	if not (os.path.exists(dsrc) and os.path.exists(ssrc)):
		return
	N = 256
	SS = 2
	n = N * SS
	# background: deep violet -> black with a red glow behind the demon, faint stars
	yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
	bg = np.zeros((n, n, 4), np.float32)
	bg[..., 0] = 0.012 + 0.02 * (1 - yy)
	bg[..., 1] = 0.006 + 0.008 * (1 - yy)
	bg[..., 2] = 0.03 + 0.05 * (1 - yy)
	r2 = ((xx - 0.5) / 0.55) ** 2 + ((yy - 0.36) / 0.42) ** 2
	glow = np.exp(-r2 * 2.2)[..., None] * np.array([0.5, 0.06, 0.02], np.float32)
	bg[..., :3] += glow
	rng = np.random.default_rng(3)
	for _ in range(70):
		sx, sy = rng.integers(0, n), rng.integers(0, n)
		b = 0.15 + 0.6 * rng.random() ** 3
		bg[sy, sx, :3] += b
	bg[..., :3] = np.stack([P.ndimage.gaussian_filter(bg[..., i], 0.6) for i in range(3)], -1)
	bg[..., 3] = 1.0
	# demon (upper part)
	demon = P.tonemap_premult(P.load(dsrc))
	dw = int(n * 1.0)
	demon = P.resize(demon, dw, dw)
	_place(bg, demon, (n - dw) // 2, int(-0.02 * n))
	# ship (lower part) with additive exhaust
	ship = P.tonemap_premult(P.load(ssrc))
	sw = int(n * 0.8)
	ship = P.downsample(ship, sw, sw)
	_place(bg, ship, (n - sw) // 2, int(0.27 * n))
	# rounded tile + subtle inner rim
	img = P.downsample(bg, N, N)
	mask = _rounded_mask(N, 46.0)
	inner = _rounded_mask(N, 44.0)
	shrink = np.zeros_like(inner)
	shrink[2:-2, 2:-2] = _rounded_mask(N - 4, 44.0)
	rim = np.clip(mask - shrink, 0, 1)[..., None]
	img[..., :3] = img[..., :3] * (1 - rim) + rim * np.array([0.35, 0.12, 0.5], np.float32) * 0.8
	img[..., :3] *= mask[..., None]
	img[..., 3] = mask
	rgba = P.premult_linear_to_rgba8(img)
	dst = os.path.join(root, "game", "icon.png")
	P.save_png(rgba, dst)
	print("[post] icon.png 256x256")


def process(work: str, root: str) -> None:
	process_logo(work, root)
	process_icon(work, root)
