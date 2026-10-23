"""Shared numpy helpers for the planet textures and ground strips (package art-planets).

Pure numpy (+ scipy where noted). Runs with the system python3, NOT inside Blender.
Everything is deterministic (fixed seeds) so re-running the scripts reproduces the assets.
"""
from __future__ import annotations

import math

import numpy as np

F32 = np.float32


class Perlin3:
	"""Vectorised 3D gradient (Perlin) noise. Output roughly in [-1, 1], std ~0.2."""

	def __init__(self, seed: int = 0) -> None:
		rng = np.random.default_rng(seed)
		p = rng.permutation(256).astype(np.int32)
		self.perm = np.concatenate([p, p, p])
		g = rng.normal(size=(256, 3))
		g /= np.linalg.norm(g, axis=1, keepdims=True)
		self.gx = g[:, 0].astype(F32)
		self.gy = g[:, 1].astype(F32)
		self.gz = g[:, 2].astype(F32)

	def __call__(self, x, y, z):
		x = np.asarray(x, F32)
		y = np.asarray(y, F32)
		z = np.asarray(z, F32)
		fx0 = np.floor(x)
		fy0 = np.floor(y)
		fz0 = np.floor(z)
		fx = x - fx0
		fy = y - fy0
		fz = z - fz0
		xi = fx0.astype(np.int32) & 255
		yi = fy0.astype(np.int32) & 255
		zi = fz0.astype(np.int32) & 255
		del fx0, fy0, fz0
		u = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
		v = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
		w = fz * fz * fz * (fz * (fz * 6 - 15) + 10)
		perm = self.perm
		a = perm[xi] + yi
		b = perm[xi + 1] + yi
		aa = perm[a] + zi
		ab = perm[a + 1] + zi
		ba = perm[b] + zi
		bb = perm[b + 1] + zi
		del a, b, xi, yi, zi
		gx, gy, gz = self.gx, self.gy, self.gz

		def gd(h, dx, dy, dz):
			hh = perm[h]
			return gx[hh] * dx + gy[hh] * dy + gz[hh] * dz

		fx1 = fx - 1
		fy1 = fy - 1
		fz1 = fz - 1
		x1 = gd(aa, fx, fy, fz)
		x2 = gd(ba, fx1, fy, fz)
		y1 = x1 + u * (x2 - x1)
		x1 = gd(ab, fx, fy1, fz)
		x2 = gd(bb, fx1, fy1, fz)
		y2 = x1 + u * (x2 - x1)
		z1 = y1 + v * (y2 - y1)
		x1 = gd(aa + 1, fx, fy, fz1)
		x2 = gd(ba + 1, fx1, fy, fz1)
		y1 = x1 + u * (x2 - x1)
		x1 = gd(ab + 1, fx, fy1, fz1)
		x2 = gd(bb + 1, fx1, fy1, fz1)
		y2 = x1 + u * (x2 - x1)
		z2 = y1 + v * (y2 - y1)
		return z1 + w * (z2 - z1)


def fbm(noise: Perlin3, x, y, z, octaves: int = 5, lacunarity: float = 2.0, gain: float = 0.5,
		ridged: bool = False):
	"""Fractal sum, normalised so the result has std ~1 (roughly in [-3, 3])."""
	total = np.zeros(np.shape(x), F32)
	amp = 1.0
	freq = 1.0
	norm = 0.0
	for o in range(octaves):
		# offset each octave so the lattice points don't line up
		off = 17.13 * o
		n = noise(x * freq + off, y * freq - off * 0.7, z * freq + off * 1.3)
		if ridged:
			n = 0.45 - np.abs(n)
		total += F32(amp) * n
		norm += amp * amp
		amp *= gain
		freq *= lacunarity
	return total / F32(0.21 * math.sqrt(norm))


def chunked(fn, shape, rows_per_chunk: int = 256, channels: int = 0):
	"""Evaluate fn(row_slice) -> array for row blocks and stack (keeps peak memory low)."""
	h = shape[0]
	out = None
	for r0 in range(0, h, rows_per_chunk):
		sl = slice(r0, min(h, r0 + rows_per_chunk))
		block = fn(sl)
		if out is None:
			out = np.zeros((h,) + block.shape[1:], block.dtype)
		out[sl] = block
	return out


class SphereGrid:
	"""Equirectangular grid: column -> longitude (-180..180, east = right), row 0 = north pole."""

	def __init__(self, w: int, h: int) -> None:
		self.w = w
		self.h = h
		self.lon = ((np.arange(w, dtype=np.float64) + 0.5) / w * 2.0 - 1.0) * math.pi
		self.lat = (0.5 - (np.arange(h, dtype=np.float64) + 0.5) / h) * math.pi

	def rows(self, sl: slice):
		"""Returns lon, lat (radians, 2D float32) and unit vectors x, y, z for a row slice."""
		lat = self.lat[sl][:, None]
		lon = self.lon[None, :]
		cl = np.cos(lat)
		x = (cl * np.cos(lon)).astype(F32)
		y = (cl * np.sin(lon)).astype(F32)
		z = np.broadcast_to(np.sin(lat), x.shape).astype(F32)
		lon2 = np.broadcast_to(lon, x.shape).astype(F32)
		lat2 = np.broadcast_to(lat, x.shape).astype(F32)
		return lon2, lat2, x, y, z


def smoothstep(e0, e1, x):
	t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


def ramp(t, stops):
	"""Piecewise-linear colour ramp. stops = [(pos, (r, g, b)), ...] sorted by pos. Returns (..., 3)."""
	pos = np.array([s[0] for s in stops], np.float64)
	cols = np.array([s[1] for s in stops], np.float64)
	out = np.empty(np.shape(t) + (3,), F32)
	for c in range(3):
		out[..., c] = np.interp(t, pos, cols[:, c])
	return out


def srgb_to_linear(c):
	c = np.asarray(c, np.float64)
	return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
	c = np.clip(np.asarray(c, np.float64), 0.0, None)
	return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def hexcol(s: str):
	s = s.lstrip("#")
	return tuple(int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def to_u8(img, dither_seed: int | None = 1):
	"""float [0,1] -> uint8 with optional tiny dither (avoids banding in smooth gradients)."""
	a = np.asarray(img, np.float64) * 255.0
	if dither_seed is not None:
		rng = np.random.default_rng(dither_seed)
		a = a + rng.uniform(-0.5, 0.5, a.shape)
	return np.clip(np.round(a), 0, 255).astype(np.uint8)


def save_png(path: str, img, mode: str | None = None, dither_seed: int | None = 1) -> None:
	from PIL import Image
	arr = to_u8(img, dither_seed)
	if arr.ndim == 2:
		Image.fromarray(arr, "L").save(path, optimize=True)
	else:
		Image.fromarray(arr, mode or ("RGBA" if arr.shape[2] == 4 else "RGB")).save(path, optimize=True)


def save_png16_gray(path: str, img) -> None:
	"""16-bit greyscale PNG (height maps). img in [0, 1]."""
	from PIL import Image
	arr = np.clip(np.round(np.asarray(img, np.float64) * 65535.0), 0, 65535).astype(np.uint16)
	Image.fromarray(arr, "I;16").save(path)


def upsample(a, factor: int):
	"""Bilinear upsample of an equirect field by an integer factor (periodic in x, clamped in y).
	Pixel centres are aligned (cell-centred grids)."""
	from scipy.ndimage import map_coordinates
	h, w = a.shape[:2]
	p = np.concatenate([a[:, -1:], a, a[:, :1]], axis=1)
	p = np.concatenate([p[:1], p, p[-1:]], axis=0)
	H, W = h * factor, w * factor
	yy = (np.arange(H) + 0.5) / factor - 0.5 + 1.0
	xx = (np.arange(W) + 0.5) / factor - 0.5 + 1.0
	if a.ndim == 2:
		return map_coordinates(p, np.meshgrid(yy, xx, indexing="ij"), order=1, mode="nearest").astype(a.dtype)
	out = np.empty((H, W) + a.shape[2:], a.dtype)
	coords = np.meshgrid(yy, xx, indexing="ij")
	for c in range(a.shape[2]):
		out[..., c] = map_coordinates(p[..., c], coords, order=1, mode="nearest")
	return out


def sphere_field(w: int, h: int, fn, factor: int = 1, rows_per_chunk: int = 128):
	"""Evaluate fn(lon, lat, x, y, z) on a (w/factor x h/factor) grid and upsample to (w x h)."""
	g = SphereGrid(w // factor, h // factor)
	a = chunked(lambda sl: fn(*g.rows(sl)), (h // factor, w // factor), rows_per_chunk)
	return a if factor == 1 else upsample(a, factor)


def wrap_deg(d):
	"""Wrap degrees into [-180, 180)."""
	return (d + 180.0) % 360.0 - 180.0


def lonlat_to_xyz(lon_deg, lat_deg):
	lo = np.radians(lon_deg)
	la = np.radians(lat_deg)
	cl = np.cos(la)
	return (cl * np.cos(lo)).astype(F32), (cl * np.sin(lo)).astype(F32), np.sin(la).astype(F32)


def blur_wrap(a, sigma_y: float, sigma_x: float | None = None):
	"""Gaussian blur, periodic in x (longitude / tileable strips), reflect in y."""
	from scipy.ndimage import gaussian_filter
	if sigma_x is None:
		sigma_x = sigma_y
	if a.ndim == 2:
		return gaussian_filter(a, (sigma_y, sigma_x), mode=("reflect", "wrap"))
	return gaussian_filter(a, (sigma_y, sigma_x, 0), mode=("reflect", "wrap", "reflect"))
