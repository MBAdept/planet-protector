"""Procedural equirectangular planet textures (package art-planets, docs/SPEC.md §15/§16.3).

Run with the system python3 (numpy + scipy + PIL), NOT inside Blender:
    python3 tools/blender/planets_textures.py <workdir> [planet ...]

Writes into <workdir>/tex/:
    <planet>_albedo.png   sRGB colour, 2:1 equirect (column 0 = lon -180, row 0 = north pole)
    <planet>_height.png   16 bit height map (mars, earth) for bump mapping
    <planet>_rough.png    roughness (earth: oceans glossy)
    <planet>_clouds.png   cloud coverage (earth)
    <planet>_ring.png     radial ring profile, RGBA, 1 row (saturn, uranus); u = (r - r_in) / (r_out - r_in)
Everything is deterministic.
"""
from __future__ import annotations

import math
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from planets_noise import (F32, Perlin3, SphereGrid, blur_wrap, fbm, hexcol, lonlat_to_xyz, ramp,  # noqa: E402
	save_png, save_png16_gray, smoothstep, sphere_field, wrap_deg)

TEX_W = 4096
TEX_H = 2048

# Ring radii in planet radii (also used by planets.py for the ring mesh).
RINGS = {
	"saturn": (1.22, 2.36),
	"uranus": (1.58, 2.06),
}


# ------------------------------------------------------------------------------------------------
# helpers
# ------------------------------------------------------------------------------------------------
def grid_deg(w: int, h: int):
	g = SphereGrid(w, h)
	lon = np.broadcast_to(np.degrees(g.lon)[None, :], (h, w)).astype(F32)
	lat = np.broadcast_to(np.degrees(g.lat)[:, None], (h, w)).astype(F32)
	return lon.copy(), lat.copy()


def vortex_warp(slon, slat, lon_c, lat_c, rx, ry, angle, falloff=1.6, reach=3.2):
	"""Rotates the sampling position around (lon_c, lat_c) inside an elliptical region (in place).
	rx is in 'local' degrees (already multiplied by cos(lat)), ry in latitude degrees."""
	h, w = slat.shape
	coslat = max(0.15, math.cos(math.radians(lat_c)))
	half_lon = min(180.0, reach * rx / coslat)
	r0 = max(0, int((90.0 - (lat_c + reach * ry)) / 180.0 * h) - 2)
	r1 = min(h, int((90.0 - (lat_c - reach * ry)) / 180.0 * h) + 3)
	c_center = (lon_c + 180.0) / 360.0 * w
	c_half = half_lon / 360.0 * w + 3
	cols = np.arange(int(c_center - c_half), int(c_center + c_half) + 1) % w
	cols = np.unique(cols)
	if r1 <= r0:
		return
	sub_lon = slon[r0:r1][:, cols]
	sub_lat = slat[r0:r1][:, cols]
	dx = wrap_deg(sub_lon - lon_c) * coslat / rx
	dy = (sub_lat - lat_c) / ry
	a = angle * np.exp(-(dx * dx + dy * dy) * falloff)
	ca = np.cos(a)
	sa = np.sin(a)
	nx = dx * ca - dy * sa
	ny = dx * sa + dy * ca
	slon[r0:r1, cols] = (lon_c + nx * rx / coslat).astype(F32)
	slat[r0:r1, cols] = (lat_c + ny * ry).astype(F32)


def ellipse_dist(lon, lat, lon_c, lat_c, rx, ry):
	coslat = max(0.15, math.cos(math.radians(lat_c)))
	dx = wrap_deg(lon - lon_c) * coslat / rx
	dy = (lat - lat_c) / ry
	return np.sqrt(dx * dx + dy * dy)


def noise_at(noise: Perlin3, slon, slat, freq, octaves, stretch_z=1.0, gain=0.5, ridged=False, rows=256):
	"""fbm sampled at (warped) lon/lat positions; stretch_z > 1 makes features elongated east-west."""
	out = np.empty(slon.shape, F32)
	for r0 in range(0, slon.shape[0], rows):
		sl = slice(r0, r0 + rows)
		x, y, z = lonlat_to_xyz(slon[sl], slat[sl])
		out[sl] = fbm(noise, x * freq, y * freq, z * freq * stretch_z, octaves, gain=gain, ridged=ridged)
	return out


def mix(a, b, t):
	"""Linear blend of colour images / colours; t is a scalar or a 2D (h, w) weight image."""
	t = np.asarray(t, F32)
	if t.ndim == 2:
		t = t[..., None]
	return a + (b - a) * t


def band_stops(bands, soft=1.2):
	"""bands = [(lat_top, lat_bottom, colour)] north->south -> ramp stops on latitude (ascending)."""
	stops = []
	for top, bot, col in bands:
		c = hexcol(col) if isinstance(col, str) else col
		lo = min(top, bot)
		hi = max(top, bot)
		stops.append((lo + soft, c))
		stops.append((hi - soft, c))
	stops.sort(key=lambda s: s[0])
	return stops


def log(*a):
	print("[planets_textures]", *a, flush=True)


# ------------------------------------------------------------------------------------------------
# Jupiter
# ------------------------------------------------------------------------------------------------
JUPITER_GRS = (-22.0, -22.5)   # lon, lat of the Great Red Spot


def tex_jupiter(w: int, h: int):
	t0 = time.time()
	lon, lat = grid_deg(w, h)
	n1, n2, n3, n4, n5 = (Perlin3(s) for s in (101, 102, 103, 104, 105))
	# large wavy displacement of the band edges (streaky east-west)
	wl = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n1, x * 2.5, y * 2.5, z * 11.0, 5), factor=4)
	wl2 = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n2, x * 7.0, y * 7.0, z * 30.0, 4), factor=2)
	wlo = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n3, x * 3.0, y * 3.0, z * 9.0, 4), factor=4)
	edges = [62, 55, 48, 43, 37, 31, 24.5, 18, 7.5, -7.0, -19.5, -27.0, -34.0, -42.0, -48.0, -55.0, -62.0]
	e_dist = np.min(np.abs(lat[..., None] - np.array(edges, F32)[None, None, :]), axis=2)
	near_edge = np.exp(-(e_dist / 2.6) ** 2)
	wl3 = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n5, x * 12.0, y * 12.0, z * 34.0, 4), factor=1)
	slat = lat + 0.65 * wl + (0.18 + 0.75 * near_edge) * wl2 + 0.45 * near_edge * wl3
	slon = lon + 4.0 * wlo
	del wl, wl2, wlo, wl3, e_dist

	rng = np.random.default_rng(7)
	# eddies along the band edges (turbulent boundaries)
	for e in edges:
		count = int(rng.integers(10, 18)) if abs(e) < 40 else int(rng.integers(7, 12))
		for _ in range(count):
			lc = float(rng.uniform(-180, 180))
			rx = float(rng.uniform(2.0, 5.5))
			ry = float(rng.uniform(1.0, 2.2))
			ang = float(rng.uniform(1.4, 3.6)) * (1 if rng.random() < 0.5 else -1)
			vortex_warp(slon, slat, lc, e + float(rng.uniform(-1.0, 1.0)), rx, ry, ang)
	# GRS anticyclone + its turbulent wake
	gl, gb = JUPITER_GRS
	vortex_warp(slon, slat, gl, gb, 12.5, 6.5, 5.0, falloff=0.9, reach=3.0)
	for k in range(6):
		vortex_warp(slon, slat, gl - 14 - k * 7 + float(rng.uniform(-2, 2)), gb + float(rng.uniform(-3, 3)),
			float(rng.uniform(2.5, 4.5)), float(rng.uniform(1.5, 2.5)), float(rng.uniform(-3, 3)))
	# white ovals
	ovals = [(gl + 48, -33.0, 3.4, 2.2), (gl + 95, -40.5, 2.2, 1.5), (gl + 125, -40.5, 2.0, 1.4),
		(gl - 70, -40.5, 2.0, 1.4), (gl - 110, -33.5, 2.6, 1.7), (gl + 30, 41.0, 1.8, 1.3), (gl + 170, 41.0, 2.0, 1.4)]
	for (ol, ob, rx, ry) in ovals:
		vortex_warp(slon, slat, ol, ob, rx * 1.5, ry * 1.5, 3.0, falloff=1.0)
	log("jupiter warp", round(time.time() - t0, 1))

	bands = [
		(90, 63, "76634f"), (63, 57, "8f7759"), (57, 52, "a8906e"), (52, 46, "8e6f50"), (46, 41, "bba07a"),
		(41, 36.5, "906545"), (36.5, 31, "cfb48c"), (31, 25, "7d4d30"), (25, 18.5, "dcc39b"),
		(18.5, 13, "8c4a26"), (13, 7.5, "aa6234"), (7.5, 3, "e3c99c"), (3, -3, "dfb684"), (-3, -7.5, "e8d0a6"),
		(-7.5, -12, "9e5f39"), (-12, -15, "bb7f52"), (-15, -19.5, "915532"), (-19.5, -27, "dfc8a2"),
		(-27, -33.5, "8c5d3e"), (-33.5, -41, "c7aa82"), (-41, -46, "936f52"), (-46, -52, "b49a78"),
		(-52, -57, "8d735a"), (-57, -63, "9e866b"), (-63, -90, "726150"),
	]
	col = ramp(slat, band_stops(bands, 1.0))
	det = noise_at(n4, slon, slat, 9.0, 5, stretch_z=4.0)
	det2 = noise_at(n5, slon, slat, 22.0, 3, stretch_z=2.0)
	log("jupiter detail noise", round(time.time() - t0, 1))
	# belts are more structured than zones
	belt = smoothstep(0.62, 0.45, col.mean(axis=2))
	col *= (1.0 + (0.07 + 0.06 * belt) * det + 0.035 * det2)[..., None]
	# dark barges in the NEB and brownish knots
	for _ in range(9):
		bl = float(rng.uniform(-180, 180))
		d = ellipse_dist(lon, lat, bl, float(rng.uniform(13.5, 16.5)), float(rng.uniform(3, 5)), 1.3)
		col = mix(col, np.array(hexcol("5e3420"), F32), 0.7 * smoothstep(1.0, 0.55, d))
	# festoons: blue-grey plumes from the NEB edge into the equatorial zone
	for k in range(14):
		c = -180 + k * 360 / 14 + float(rng.uniform(-6, 6))
		depth = float(rng.uniform(4.5, 7.0))
		t = np.clip((7.2 - slat) / depth, 0, 1)
		center = c - 7.5 * t - 3.0 * t * t
		m = np.exp(-(wrap_deg(slon - center) / (1.0 + 0.8 * t)) ** 2) * smoothstep(0, 0.15, t) * smoothstep(1.0, 0.6, t)
		m *= (slat < 8.0)
		col = mix(col, np.array(hexcol("6b6566"), F32), 0.55 * m)
	# polar mottling
	pole = smoothstep(48, 72, np.abs(lat))
	mott = noise_at(n2, slon, slat, 12.0, 4, stretch_z=1.3)
	col *= (1.0 + pole * 0.10 * mott)[..., None]
	col = mix(col, col * np.array([0.86, 0.82, 0.78], F32), pole * 0.6)

	# Great Red Spot: red-orange core with spiral structure and pale collar ("Red Spot Hollow")
	d = ellipse_dist(lon, lat, gl, gb, 11.5, 6.0)
	sw = noise_at(n1, slon, slat, 14.0, 4, stretch_z=1.0)
	grs = ramp(np.clip(0.5 + 0.28 * sw + 0.35 * (d - 0.5), 0, 1),
		[(0.0, hexcol("c4603a")), (0.35, hexcol("b4533a")), (0.6, hexcol("c86c45")), (0.85, hexcol("a24a32")), (1.0, hexcol("8f4430"))])
	collar = smoothstep(1.45, 1.12, d) * smoothstep(0.95, 1.08, d)
	col = mix(col, np.array(hexcol("e8d8bb"), F32) * (1 + 0.04 * sw[..., None]), 0.35 * collar)
	col = mix(col, grs, smoothstep(1.05, 0.80, d))
	# ovals: soft white with a faint darker outline
	for (ol, ob, rx, ry) in ovals:
		d = ellipse_dist(lon, lat, ol, ob, rx, ry)
		col = mix(col, col * 0.85, 0.5 * smoothstep(1.35, 1.1, d) * smoothstep(0.9, 1.1, d))
		col = mix(col, np.array(hexcol("ece2cf"), F32) * (1 + 0.04 * sw[..., None]), 0.8 * smoothstep(1.0, 0.45, d))
	log("jupiter done", round(time.time() - t0, 1))
	return {"albedo": np.clip(col, 0, 1)}


# ------------------------------------------------------------------------------------------------
# Saturn
# ------------------------------------------------------------------------------------------------
def tex_saturn(w: int, h: int):
	t0 = time.time()
	lon, lat = grid_deg(w, h)
	n1, n2, n3, n4 = (Perlin3(s) for s in (201, 202, 203, 204))
	wl = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n1, x * 2.5, y * 2.5, z * 12.0, 5), factor=4)
	wlo = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n2, x * 3.0, y * 3.0, z * 8.0, 4), factor=4)
	slat = lat + 0.32 * wl
	slon = lon + 3.0 * wlo
	del wl, wlo
	rng = np.random.default_rng(17)
	for e in [60, 47, 38, 27, 19, 9, -9, -19, -27, -38, -47]:
		for _ in range(int(rng.integers(3, 6))):
			vortex_warp(slon, slat, float(rng.uniform(-180, 180)), e + float(rng.uniform(-0.8, 0.8)),
				float(rng.uniform(3.0, 6.0)), float(rng.uniform(0.8, 1.4)), float(rng.uniform(-1.4, 1.4)))
	bands = [
		(90, 80, "7d8282"), (80, 74, "9a9178"), (74, 66, "b19e78"), (66, 58, "c2aa7c"), (58, 52, "ad9168"),
		(52, 45, "cdb385"), (45, 39, "b8986a"), (39, 33, "d9bf90"), (33, 26, "bf985f"), (26, 20, "e3c996"),
		(20, 13, "c9a066"), (13, 8, "ddb97e"), (8, -8, "efd8a6"), (-8, -13, "dab47a"), (-13, -20, "c59c62"),
		(-20, -26, "e2c794"), (-26, -33, "bd9862"), (-33, -40, "d6bb8b"), (-40, -48, "b99a6c"),
		(-48, -60, "c9ad80"), (-60, -75, "ad9774"), (-75, -90, "908774"),
	]
	col = ramp(slat, band_stops(bands, 2.2))
	det = noise_at(n3, slon, slat, 7.0, 4, stretch_z=7.0)
	det2 = noise_at(n4, slon, slat, 26.0, 2, stretch_z=4.0)
	col *= (1.0 + 0.025 * det + 0.008 * det2)[..., None]
	# north polar hexagon (blue-grey) with dark central vortex
	colat = 90.0 - lat
	theta = np.radians(lon + 15.0)
	ang = np.mod(theta, math.pi / 3.0) - math.pi / 6.0
	r_hex = 12.5 / np.cos(ang)
	hexm = smoothstep(r_hex + 0.9, r_hex - 0.6, colat)
	edge = smoothstep(r_hex + 1.6, r_hex + 0.2, colat) * smoothstep(r_hex - 2.0, r_hex - 0.3, colat)
	col = mix(col, np.array(hexcol("8e9286"), F32) * (1 + 0.03 * det[..., None]), 0.45 * hexm)
	col = mix(col, np.array(hexcol("857558"), F32), 0.35 * edge)
	col = mix(col, np.array(hexcol("5d625e"), F32), 0.7 * smoothstep(3.0, 0.5, colat))
	# a few small white storms
	for _ in range(4):
		ol = float(rng.uniform(-180, 180))
		ob = float(rng.choice([41.0, 33.0, -36.0]))
		d = ellipse_dist(lon, lat, ol, ob, 1.8, 1.2)
		col = mix(col, np.array(hexcol("f1e8d2"), F32), 0.7 * smoothstep(1.0, 0.5, d))
	log("saturn done", round(time.time() - t0, 1))
	return {"albedo": np.clip(col, 0, 1)}


def ring_saturn(n: int = 4096):
	r_in, r_out = RINGS["saturn"]
	r = r_in + (np.arange(n) + 0.5) / n * (r_out - r_in)
	rng = np.random.default_rng(5)
	# fine ringlet structure: sum of many narrow random modulations
	fine = np.zeros(n)
	for _ in range(160):
		c = rng.uniform(r_in, r_out)
		wdt = rng.uniform(0.002, 0.02)
		fine += rng.normal(0, 1) * np.exp(-((r - c) / wdt) ** 2)
	fine /= np.abs(fine).max()
	col = np.zeros((n, 3))
	alpha = np.zeros(n)

	def seg(a, b):
		return (r >= a) & (r < b)

	def lerp_t(a, b):
		return np.clip((r - a) / (b - a), 0, 1)

	# Colours: realistic but clearly multi-coloured (SPEC §15) - a cool blue-grey C ring, a warm
	# peach / salmon B ring and a neutral grey A ring, separated by the dark Cassini division.
	# D ring (very faint)
	m = seg(1.22, 1.24)
	col[m] = hexcol("6c7482")
	alpha[m] = 0.04
	# C ring: cool blue-grey, semi-transparent with ringlets
	m = seg(1.24, 1.527)
	t = lerp_t(1.24, 1.527)
	col[m] = (ramp(t, [(0, hexcol("5a6678")), (0.6, hexcol("75829a")), (1, hexcol("8f909a"))]))[m]
	alpha[m] = (0.16 + 0.20 * t + 0.08 * fine)[m]
	# B ring: bright warm peach / salmon / cream, nearly opaque
	m = seg(1.527, 1.95)
	t = lerp_t(1.527, 1.95)
	col[m] = ramp(t, [(0, hexcol("a88674")), (0.18, hexcol("d1a088")), (0.4, hexcol("eecbb0")),
		(0.62, hexcol("f5dfc2")), (0.8, hexcol("f1d3ab")), (0.92, hexcol("e1b092")), (1.0, hexcol("cb9c80"))])[m]
	alpha[m] = np.clip(0.62 + 0.45 * smoothstep(0.0, 0.25, t) + 0.10 * fine, 0, 1)[m]
	# Cassini division: dark, mostly transparent
	m = seg(1.95, 2.025)
	col[m] = hexcol("3b3e46")
	alpha[m] = 0.10 + 0.05 * np.abs(fine[m])
	# A ring: neutral grey (slightly cool towards the outer edge), medium opacity, Encke + Keeler gaps
	m = seg(2.025, 2.27)
	t = lerp_t(2.025, 2.27)
	col[m] = ramp(t, [(0, hexcol("bdbab4")), (0.5, hexcol("adaeb0")), (1.0, hexcol("9499a3"))])[m]
	alpha[m] = (0.70 - 0.12 * t + 0.08 * fine)[m]
	gap = np.exp(-((r - 2.214) / 0.0045) ** 2) + np.exp(-((r - 2.262) / 0.0022) ** 2)
	alpha *= 1.0 - 0.92 * np.clip(gap, 0, 1)
	# F ring: thin bright line
	f = np.exp(-((r - 2.326) / 0.004) ** 2)
	col = col * (1 - f[:, None]) + np.array(hexcol("d2d4d8")) * f[:, None]
	alpha = np.maximum(alpha, 0.55 * f)
	# soft fall-off at the inner/outer edges (anti-aliasing in r)
	col *= (1.0 + 0.06 * fine)[:, None]
	return np.clip(np.concatenate([col, alpha[:, None]], axis=1), 0, 1)[None, :, :]


# ------------------------------------------------------------------------------------------------
# Uranus
# ------------------------------------------------------------------------------------------------
def tex_uranus(w: int, h: int):
	lon, lat = grid_deg(w, h)
	n1, n2 = Perlin3(301), Perlin3(302)
	wl = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n1, x * 2.0, y * 2.0, z * 9.0, 4), factor=4)
	slat = lat + 1.5 * wl
	bands = [
		(90, 62, "c9eaea"), (62, 50, "b2e1e3"), (50, 38, "a5d8dc"), (38, 22, "9dd2d8"), (22, 8, "a2d5da"),
		(8, -8, "98cdd4"), (-8, -22, "9fd2d8"), (-22, -40, "a4d6db"), (-40, -60, "aedbdf"), (-60, -90, "b9e2e4"),
	]
	col = ramp(slat, band_stops(bands, 3.0))
	det = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n2, x * 6.0, y * 6.0, z * 26.0, 4), factor=2)
	col *= (1.0 + 0.018 * det)[..., None]
	# soft bright polar hood
	col = mix(col, np.array(hexcol("dff3f1"), F32), 0.55 * smoothstep(55, 80, lat))
	# two faint bright cloud features
	for ol, ob, rx, ry in [(10.0, 32.0, 3.5, 1.6), (-35.0, 28.0, 2.5, 1.2)]:
		d = ellipse_dist(lon, lat, ol, ob, rx, ry)
		col = mix(col, np.array(hexcol("e9fbf9"), F32), 0.5 * smoothstep(1.0, 0.3, d))
	return {"albedo": np.clip(col, 0, 1)}


def ring_uranus(n: int = 4096):
	r_in, r_out = RINGS["uranus"]
	r = r_in + (np.arange(n) + 0.5) / n * (r_out - r_in)
	alpha = np.zeros(n)
	# (radius in planet radii, half width, opacity) – widths exaggerated so the system reads at small sizes
	for rc, wd, a in [(1.637, 0.0045, 0.45), (1.652, 0.0045, 0.45), (1.666, 0.0045, 0.5), (1.750, 0.0075, 0.7),
			(1.786, 0.0070, 0.65), (1.834, 0.0050, 0.55), (1.863, 0.0060, 0.6), (1.900, 0.0070, 0.7),
			(1.958, 0.0040, 0.45), (2.000, 0.0170, 0.95)]:
		alpha = np.maximum(alpha, a * smoothstep(wd * 1.3, wd * 0.55, np.abs(r - rc)))
	# faint dusty sheet between the ringlets
	alpha = np.maximum(alpha, 0.10 * smoothstep(1.60, 1.64, r) * smoothstep(2.03, 1.99, r))
	col = np.zeros((n, 3))
	col[:] = hexcol("a9b9bf")
	eps = smoothstep(0.03, 0.0, np.abs(r - 2.0))
	col = col * (1 - eps[:, None]) + np.array(hexcol("d3e0e3")) * eps[:, None]
	return np.clip(np.concatenate([col, alpha[:, None]], axis=1), 0, 1)[None, :, :]


# ------------------------------------------------------------------------------------------------
# Neptune
# ------------------------------------------------------------------------------------------------
NEPTUNE_GDS = (-18.0, -21.0)


def tex_neptune(w: int, h: int):
	lon, lat = grid_deg(w, h)
	n1, n2, n3, n4 = (Perlin3(s) for s in (401, 402, 403, 404))
	wl = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n1, x * 2.5, y * 2.5, z * 10.0, 5), factor=4)
	wlo = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n2, x * 3.0, y * 3.0, z * 7.0, 4), factor=4)
	slat = lat + 1.6 * wl
	slon = lon + 4.0 * wlo
	del wl, wlo
	gl, gb = NEPTUNE_GDS
	vortex_warp(slon, slat, gl, gb, 12.0, 6.5, -3.5, falloff=1.0)
	bands = [
		(90, 72, "3f6fd0"), (72, 58, "355fc4"), (58, 42, "3a66c9"), (42, 25, "3361c6"), (25, 8, "2f5bc0"),
		(8, -8, "2b55b8"), (-8, -18, "315cc0"), (-18, -32, "3967c8"), (-32, -44, "3260c2"),
		(-44, -60, "203f9c"), (-60, -70, "2a4fb0"), (-70, -90, "4677d2"),
	]
	col = ramp(slat, band_stops(bands, 2.5))
	det = noise_at(n3, slon, slat, 7.0, 5, stretch_z=4.0)
	col *= (1.0 + 0.05 * det)[..., None]
	# bright high-altitude methane streaks (elongated white clouds)
	sx, sy, sz = lonlat_to_xyz(lon + 2.0 * (slon - lon), lat + 0.4 * (slat - lat))
	streak = fbm(n4, sx * 5.0, sy * 5.0, sz * 55.0, 3, gain=0.45)
	del sx, sy, sz
	lat_mask = (np.exp(-((lat - 28) / 7.0) ** 2) + 0.8 * np.exp(-((lat + 42) / 4.0) ** 2)
		+ 0.6 * np.exp(-((lat - 45) / 5.0) ** 2) + 0.7 * np.exp(-((lat + 70) / 4.0) ** 2))
	s = smoothstep(1.0, 2.1, streak) * lat_mask
	col = mix(col, np.array(hexcol("e8f2ff"), F32), np.clip(s, 0, 0.9))
	# Great Dark Spot with bright companion clouds
	# soft oval with a slightly ragged outline (no hard edges)
	d = ellipse_dist(lon, lat, gl, gb, 13.0, 6.5) + 0.10 * det
	col = mix(col, np.array(hexcol("15296f"), F32) * (1 + 0.08 * det[..., None]), smoothstep(1.05, 0.35, d) * 0.92)
	col = mix(col, np.array(hexcol("1d3789"), F32), 0.35 * smoothstep(1.5, 1.0, d) * smoothstep(0.6, 1.05, d))
	comp = ellipse_dist(lon, lat, gl + 3.0, gb - 8.0, 11.0, 1.7)
	col = mix(col, np.array(hexcol("f2f7ff"), F32), 0.85 * smoothstep(1.0, 0.3, comp))
	comp2 = ellipse_dist(lon, lat, gl - 6.0, gb + 7.0, 7.0, 1.1)
	col = mix(col, np.array(hexcol("dce8ff"), F32), 0.6 * smoothstep(1.0, 0.3, comp2))
	# 'Scooter' and small dark spot D2 with a bright core
	sc = ellipse_dist(lon, lat, gl + 55.0, -42.0, 3.0, 1.6)
	col = mix(col, np.array(hexcol("f4f8ff"), F32), 0.85 * smoothstep(1.0, 0.3, sc))
	d2 = ellipse_dist(lon, lat, gl + 25.0, -55.0, 4.2, 2.5)
	col = mix(col, np.array(hexcol("15297a"), F32), 0.85 * smoothstep(1.0, 0.6, d2))
	col = mix(col, np.array(hexcol("d9e6ff"), F32), 0.8 * smoothstep(0.35, 0.0, d2))
	return {"albedo": np.clip(col, 0, 1)}


# ------------------------------------------------------------------------------------------------
# Mars
# ------------------------------------------------------------------------------------------------
# Valles Marineris chasmata as polylines of (lon, lat, half width) in degrees, plus a depth factor.
MARS_CHASMATA = [
	# Ius - Melas - Coprates - Eos/Capri (the main trough, widest in the central Melas section)
	([(-99, -6.6, 0.9), (-91, -7.0, 1.3), (-83, -7.8, 1.55), (-77, -9.0, 2.3), (-72, -10.0, 3.0),
		(-67, -11.2, 2.5), (-62, -12.6, 1.7), (-55, -13.3, 1.6), (-49, -13.0, 2.0), (-43, -11.6, 2.6),
		(-38, -9.8, 2.8)], 1.0),
	([(-97, -4.2, 0.6), (-88, -4.4, 0.8), (-80, -5.0, 1.0)], 0.75),                 # Tithonium
	([(-79, -6.2, 1.6), (-73, -6.4, 2.4), (-68, -6.0, 2.0), (-64, -4.4, 1.2)], 0.9),  # Candor / Ophir
	([(-52, -8.9, 0.7), (-47, -8.2, 1.3), (-42, -7.2, 1.7), (-37, -6.4, 1.2)], 0.8),  # Ganges -> chaos
	([(-77, -1.0, 0.55), (-74, -1.3, 0.95), (-71, -1.1, 0.6)], 0.55),               # Hebes
]


def _polyline_depth(lon, lat, pts, fine):
	"""Canyon depth (0..1) for one chasma: flat floor, steep walls with spurs and alcoves."""
	coslat = np.cos(np.radians(lat))
	q = np.full(lon.shape, 9.0, F32)
	for (l0, b0, w0), (l1, b1, w1) in zip(pts[:-1], pts[1:]):
		vx = (l1 - l0)
		vy = (b1 - b0)
		px = wrap_deg(lon - l0)
		py = lat - b0
		# local x scaled by cos(lat): segment and point measured in the same local frame
		c = coslat
		t = np.clip((px * c * vx * c + py * vy) / ((vx * c) ** 2 + vy * vy), 0.0, 1.0)
		d = np.sqrt((px * c - t * vx * c) ** 2 + (py - t * vy) ** 2)
		hw = w0 + (w1 - w0) * t
		q = np.minimum(q, (d / hw).astype(F32))
	q = q + 0.30 * fine                                       # spurs / alcoves along the walls
	return smoothstep(1.0, 0.42, q)


def mars_canyons(lon, lat, fine, mid):
	"""Valles Marineris + Noctis Labyrinthus + the eastern chaos terrain, depth 0..1."""
	h, w = lon.shape
	# work on the bounding box only (lon -112..-22, lat -22..+6)
	r0 = int((90 - 6) / 180 * h)
	r1 = int((90 + 22) / 180 * h) + 1
	c0 = int((-112 + 180) / 360 * w)
	c1 = int((-22 + 180) / 360 * w) + 1
	sl = (slice(r0, r1), slice(c0, c1))
	lo, la, fi, mi = lon[sl], lat[sl], fine[sl], mid[sl]
	depth = np.zeros(lo.shape, F32)
	for pts, dep in MARS_CHASMATA:
		depth = np.maximum(depth, dep * _polyline_depth(lo, la, pts, fi))
	# Noctis Labyrinthus: troughs along the cell edges of a small Voronoi pattern (a blocky maze)
	rng = np.random.default_rng(77)
	seeds = np.stack([rng.uniform(-109.0, -95.0, 30), rng.uniform(-12.5, 0.5, 30)], axis=1)
	c = np.cos(np.radians(la))
	d1 = np.full(lo.shape, 99.0, F32)
	d2 = np.full(lo.shape, 99.0, F32)
	for sx, sy in seeds:
		d = np.sqrt((wrap_deg(lo - sx) * c) ** 2 + (la - sy) ** 2).astype(F32)
		d2 = np.minimum(d2, np.maximum(d1, d))
		d1 = np.minimum(d1, d)
	edge = smoothstep(0.95, 0.35, (d2 - d1) + 0.15 * fi)      # ~0.4 deg wide troughs on the cell borders
	region = smoothstep(1.0, 0.55, ellipse_dist(lo, la, -101.5, -6.2, 6.0, 4.6) + 0.25 * mi)
	depth = np.maximum(depth, (0.62 * edge * region).astype(F32))
	# chaos terrain where the canyon opens to the east: a sunken plain broken into mesas
	e = smoothstep(1.0, 0.55, ellipse_dist(lo, la, -33.0, -6.0, 6.5, 5.0))
	knobs = smoothstep(-0.05, 0.25, fi + 0.5 * mi)
	depth = np.maximum(depth, (0.7 * e * (0.35 + 0.65 * knobs)).astype(F32))
	# a little relief on the floors (landslides, layered deposits)
	depth *= (0.9 + 0.1 * smoothstep(-0.5, 0.5, mi)).astype(F32)
	out = np.zeros(lon.shape, F32)
	out[sl] = depth
	return out


def mars_volcanoes(lon, lat, fine):
	"""Tharsis volcanoes: (height, darkness). Olympus Mons with its basal escarpment, the three
	Tharsis Montes in a row, Alba Mons as a low shield; summit calderas."""
	hgt = np.zeros(lon.shape, F32)
	dark = np.zeros(lon.shape, F32)
	hgt += 0.22 * np.exp(-((wrap_deg(lon + 108) * 0.9 / 28) ** 2 + ((lat - 2) / 24) ** 2))   # Tharsis rise
	for vl, vb, vr, vh, cr in [(-134, 18.5, 5.6, 0.70, 0.16), (-121, -8.5, 3.6, 0.42, 0.22),
			(-113, 1.0, 3.2, 0.38, 0.16), (-104.5, 11.5, 3.3, 0.40, 0.14), (-110, 40.5, 7.0, 0.12, 0.10)]:
		q = ellipse_dist(lon, lat, vl, vb, vr, vr) + 0.05 * fine
		shield = vh * np.clip(1.0 - q, 0.0, 1.0) ** 1.25
		if vl == -134:   # Olympus Mons: a plateau-like shield ringed by a steep cliff
			shield = vh * (0.45 * smoothstep(1.02, 0.9, q) + 0.55 * np.clip(1.0 - q, 0.0, 1.0) ** 1.1)
		caldera = -0.5 * vh * smoothstep(cr, cr * 0.55, q)
		hgt += (shield + caldera).astype(F32)
		if vh > 0.2:   # lava-covered flanks are darker than the dusty plains, summits a bit lighter
			dark = np.maximum(dark, (smoothstep(1.05, 0.55, q) * (1.0 - 0.6 * smoothstep(0.3, 0.1, q))).astype(F32))
	return hgt, dark


def mars_hillshade(rel, lat):
	"""Multiplicative slope shading (equirect height field, light from the north-west)."""
	h, w = rel.shape
	g_row, g_col = np.gradient(rel.astype(np.float64))
	d_lat = -g_row * (h / 180.0)                               # per degree latitude (rows run north->south)
	d_lon = g_col * (w / 360.0) / np.maximum(np.cos(np.radians(lat)), 0.2)
	# n ~ (-dH/dlon, -dH/dlat, 1), horizontal light direction L ~ (-0.70 east, +0.71 north)
	s = 0.70 * d_lon - 0.71 * d_lat
	s = np.tanh(s / 0.25)                                      # canyon walls saturate, shield flanks stay soft
	return (1.0 + 0.38 * s).astype(F32)


def tex_mars(w: int, h: int):
	t0 = time.time()
	lon, lat = grid_deg(w, h)
	n = [Perlin3(500 + i) for i in range(8)]
	big = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n[0], x * 1.6, y * 1.6, z * 1.6, 6), factor=4)
	mid = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n[1], x * 5.0, y * 5.0, z * 5.0, 5), factor=2)
	fine = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n[2], x * 24.0, y * 24.0, z * 24.0, 4), factor=1)
	log("mars noise", round(time.time() - t0, 1))
	# warped coordinates for the albedo features (natural ragged outlines)
	wx = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n[3], x * 4.0, y * 4.0, z * 4.0, 4), factor=4)
	wy = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n[4], x * 4.0, y * 4.0, z * 4.0, 4), factor=4)
	slon = lon + 4.5 * wx
	slat = lat + 3.5 * wy

	# --- dark albedo regions (roughly after the classic Valles-Marineris facing hemisphere) ---
	dark = np.zeros((h, w), F32)

	def blob(lc, bc, rx, ry, s=1.0):
		d = ellipse_dist(slon, slat, lc, bc, rx, ry)
		return s * smoothstep(1.0, 0.35, d)

	dark = np.maximum(dark, blob(-30, 47, 26, 12))          # Mare Acidalium
	dark = np.maximum(dark, blob(-10, 58, 30, 6, 0.7))       # north dark collar
	dark = np.maximum(dark, blob(-40, -22, 28, 9))           # Mare Erythraeum
	dark = np.maximum(dark, blob(-5, -5, 18, 5.5))           # Sinus Meridiani
	dark = np.maximum(dark, blob(-25, -10, 14, 6, 0.8))      # Margaritifer
	dark = np.maximum(dark, blob(-87, -26, 8, 5.5))          # Solis Lacus ("Eye of Mars")
	dark = np.maximum(dark, blob(-70, -38, 18, 6, 0.75))     # Thaumasia / Nectar
	dark = np.maximum(dark, blob(30, -18, 22, 8))            # Sabaeus / Tyrrhenum
	dark = np.maximum(dark, blob(70, 8, 10, 17))             # Syrtis Major
	dark = np.maximum(dark, blob(110, -20, 30, 8, 0.8))      # Cimmerium
	dark = np.maximum(dark, blob(-160, -25, 30, 8, 0.75))    # Sirenum
	dark = np.maximum(dark, blob(-170, 35, 20, 8, 0.5))
	dark = np.maximum(dark, blob(150, 40, 25, 8, 0.45))
	dark *= smoothstep(-1.3, 0.3, mid + 0.4)                 # break up the outlines
	dark = np.clip(dark + 0.18 * smoothstep(0.3, 1.5, big) * smoothstep(10, -15, lat), 0, 1)

	# --- height: low-frequency terrain, craters, Valles Marineris, Tharsis volcanoes ---
	hgt = 0.18 * big + 0.05 * mid + 0.012 * fine
	hgt += 0.25 * smoothstep(5, -25, lat)                    # southern highlands higher
	rng = np.random.default_rng(42)
	coslat = np.cos(np.radians(lat))
	crater_count = 900
	sizes = 0.6 * (rng.pareto(1.6, crater_count) + 1.0)
	sizes = np.clip(sizes, 0.6, 9.0)
	for i in range(crater_count):
		cl = float(rng.uniform(-180, 180))
		cb = float(np.degrees(np.arcsin(rng.uniform(-0.98, 0.98))))
		if cb > 0 and rng.random() < 0.55:                    # fewer craters in the northern lowlands
			continue
		r = float(sizes[i])
		cosc = max(0.2, math.cos(math.radians(cb)))
		r0 = max(0, int((90 - cb - 2.2 * r) / 180 * h))
		r1 = min(h, int((90 - cb + 2.2 * r) / 180 * h) + 1)
		c0 = int((cl + 180 - 2.2 * r / cosc) / 360 * w)
		c1 = int((cl + 180 + 2.2 * r / cosc) / 360 * w) + 1
		cols = np.arange(c0, c1) % w
		sub_lon = lon[r0:r1][:, cols]
		sub_lat = lat[r0:r1][:, cols]
		dx = wrap_deg(sub_lon - cl) * np.cos(np.radians(sub_lat))
		dy = sub_lat - cb
		q = np.sqrt(dx * dx + dy * dy) / r
		bowl = -(1.0 - np.clip(q, 0, 1) ** 2) * 0.9
		rim = 0.35 * np.exp(-((q - 1.0) / 0.16) ** 2)
		ejecta = 0.08 * np.exp(-((q - 1.0) / 0.6) ** 2) * (q > 1)
		depth = 0.035 * min(r, 4.0) ** 0.75
		hgt[r0:r1, cols] += (depth * (bowl + rim + ejecta)).astype(F32)
		# crater floors slightly darker, fresh rims slightly brighter
		if r > 1.2:
			dark[r0:r1, cols] = np.maximum(dark[r0:r1, cols], (0.08 * smoothstep(0.8, 0.2, q)).astype(F32))
	log("mars craters", round(time.time() - t0, 1))
	# Valles Marineris (wide chasma system with flat floors and steep walls) + Tharsis volcanoes
	cl = lon + 0.7 * wx                                       # lightly warped: ragged canyon walls
	cb = lat + 0.5 * wy
	vm = mars_canyons(cl, cb, fine, mid)
	hgt -= 0.42 * vm
	volc, volc_dark = mars_volcanoes(lon, lat, fine)
	hgt += volc
	feat = volc - 0.42 * vm                                   # relief used for the baked wall shading
	dark = np.maximum(dark, 0.42 * volc_dark)
	floor = smoothstep(0.35, 0.9, vm)
	dark = np.maximum(dark, 0.72 * floor * (0.8 + 0.2 * smoothstep(-0.4, 0.4, mid)))
	# --- albedo ---
	bright = ramp(np.clip(0.5 + 0.22 * big + 0.06 * mid, 0, 1),
		[(0.0, hexcol("b4592f")), (0.45, hexcol("c96a3a")), (0.8, hexcol("d6824e")), (1.0, hexcol("df9a66"))])
	darkc = ramp(np.clip(0.5 + 0.3 * mid, 0, 1), [(0.0, hexcol("3e2720")), (0.6, hexcol("5a3326")), (1.0, hexcol("6e3f2c"))])
	col = mix(bright, darkc, np.clip(dark * 1.15, 0, 1) * 0.9)
	col *= (1.0 + 0.035 * fine)[..., None]
	# baked slope shading of the big relief features (light from the upper left = north-west):
	# keeps the canyon walls and volcano flanks readable when the planet is shown small
	col *= mars_hillshade(feat, lat)[..., None]
	# polar caps: small north cap with spiral troughs, smaller south cap
	sp = np.radians(lon) * 1.0 + np.radians(90 - lat) * 9.0
	trough = 0.5 + 0.5 * np.sin(sp * 3.0 + 1.5 * mid)
	ncap = smoothstep(80.0, 83.0, lat + 2.0 * mid + 1.2 * fine)
	scap = smoothstep(-84.5, -87.0, lat + 1.5 * mid)
	cap = np.maximum(ncap * (0.8 + 0.2 * trough), scap)
	frost = smoothstep(74, 80, lat + 3.0 * mid) * 0.25
	col = mix(col, np.array(hexcol("efe9e2"), F32), np.clip(np.maximum(cap, frost), 0, 1))
	hgt += 0.06 * ncap
	hgt = (hgt - hgt.min()) / (hgt.max() - hgt.min())
	log("mars done", round(time.time() - t0, 1))
	return {"albedo": np.clip(col, 0, 1), "height": hgt}


# ------------------------------------------------------------------------------------------------
# Earth (continents from hand-made coarse outlines, roughened procedurally)
# ------------------------------------------------------------------------------------------------
from planets_earth_shapes import GREENLAND, LAND, MOUNTAINS, WATER  # noqa: E402


def _raster_polys(polys, w, h, ss=1):
	from PIL import Image, ImageDraw
	img = Image.new("L", (w * ss, h * ss), 0)
	dr = ImageDraw.Draw(img)
	for poly in polys:
		pts = [((lo + 180.0) / 360.0 * w * ss, (90.0 - la) / 180.0 * h * ss) for lo, la in poly]
		dr.polygon(pts, fill=255)
	a = np.asarray(img, np.float32) / 255.0
	if ss > 1:
		a = a.reshape(h, ss, w, ss).mean(axis=(1, 3))
	return a


def tex_earth(w: int, h: int):
	t0 = time.time()
	from scipy.ndimage import map_coordinates
	lon, lat = grid_deg(w, h)
	n = [Perlin3(600 + i) for i in range(10)]
	land0 = _raster_polys(LAND, w, h, 1)
	water0 = _raster_polys(WATER, w, h, 1)
	base = np.clip(land0 - water0, 0, 1)
	# domain-warp the outlines (wiggly natural coasts, shapes stay recognisable)
	wx = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n[0], x * 9.0, y * 9.0, z * 9.0, 5), factor=2)
	wy = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n[1], x * 9.0, y * 9.0, z * 9.0, 5), factor=2)
	px_per_deg = w / 360.0
	yy, xx = np.mgrid[0:h, 0:w].astype(F32)
	xs = (xx + wx * 0.55 * px_per_deg) % w
	ys = np.clip(yy + wy * 0.55 * px_per_deg, 0, h - 1)
	warped = map_coordinates(base, [ys, xs], order=1, mode="nearest").astype(F32)
	green_land = map_coordinates(_raster_polys([GREENLAND], w, h, 1), [ys, xs], order=1, mode="nearest").astype(F32)
	del xs, ys, yy, xx
	coast = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n[2], x * 40.0, y * 40.0, z * 40.0, 4), factor=1)
	s = blur_wrap(warped, 2.0) - 0.5 + 0.13 * coast
	# Antarctica: everything south of ~ -70 (+ peninsula from the polygon list), Arctic sea ice handled in colour
	ant = (lat < -70.5 + 2.2 * wx) | (lat < -78)
	land = np.clip(s * 6.0 + 0.5, 0, 1)
	land = np.maximum(land, ant.astype(F32))
	land_hard = (land > 0.5).astype(F32)
	log("earth land mask", round(time.time() - t0, 1))

	# --- climate fields ---
	big = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n[3], x * 3.0, y * 3.0, z * 3.0, 5), factor=4)
	mid = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n[4], x * 10.0, y * 10.0, z * 10.0, 5), factor=2)
	fine = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n[5], x * 45.0, y * 45.0, z * 45.0, 3), factor=1)

	rlon = lon + 5.0 * wx
	rlat = lat + 3.0 * wy

	def region(l0, l1, b0, b1, soft=4.0, warped=True):
		"""Soft box in lon/lat (outline perturbed by noise so no straight edges show)."""
		lo_ = rlon if warped else lon
		la_ = rlat if warped else lat
		soft = soft * 1.6
		a0 = wrap_deg(lo_ - l0)
		a1 = wrap_deg(lo_ - l1)
		dlon = np.where((a0 >= 0) & (a1 <= 0), 0, np.minimum(np.abs(a0), np.abs(a1)))
		dlat = np.where((la_ >= b0) & (la_ <= b1), 0, np.minimum(np.abs(la_ - b0), np.abs(la_ - b1)))
		return smoothstep(soft, 0, np.sqrt(dlon * dlon + dlat * dlat))

	desert = np.zeros((h, w), F32)
	for l0, l1, b0, b1, s_, k in [(-17, 33, 16, 30, 5, 1.0), (33, 58, 15, 31, 4, 1.0), (24, 33, 20, 31, 3, 1.0),
			(48, 68, 26, 38, 4, 0.75), (55, 80, 38, 46, 4, 0.55), (90, 112, 37, 46, 4, 0.7), (75, 90, 36, 42, 3, 0.6),
			(12, 22, -29, -17, 4, 0.8), (14, 17, -27, -18, 2, 0.9), (118, 142, -31, -20, 5, 0.85),
			(-116, -104, 26, 37, 3, 0.6), (-72, -68, -30, -17, 2, 0.85), (-70, -65, -50, -38, 3, 0.55),
			(64, 72, 24, 29, 2, 0.6), (-8, 0, 17, 26, 3, 1.0), (40, 51, 3, 11, 2, 0.6)]:
		desert = np.maximum(desert, k * region(l0, l1, b0, b1, s_))
	desert = np.clip(desert + 0.25 * mid * desert, 0, 1)
	# vegetation: wet tropics + temperate zones, dry subtropics
	alat = np.abs(lat)
	tropic = np.exp(-((lat - 2) / 9.0) ** 2)
	temperate = smoothstep(35, 45, alat) * smoothstep(62, 54, alat)
	boreal = smoothstep(52, 58, alat) * smoothstep(70, 64, alat)
	tundra = smoothstep(64, 70, alat)
	sav = np.exp(-((alat - 13) / 6.0) ** 2)

	c_trop = np.array(hexcol("1f4a16"), F32)
	c_temp = np.array(hexcol("3f6a26"), F32)
	c_bor = np.array(hexcol("27452a"), F32)
	c_tun = np.array(hexcol("7a7464"), F32)
	c_sav = np.array(hexcol("8a8a45"), F32)
	c_steppe = np.array(hexcol("9a8d5a"), F32)
	c_des = np.array(hexcol("dfbf8a"), F32)
	c_des2 = np.array(hexcol("cf9a62"), F32)
	c_ice = np.array(hexcol("f4f7fa"), F32)

	col = np.broadcast_to(c_steppe, (h, w, 3)).copy()
	col = mix(col, c_temp, np.clip(temperate * 0.9 + 0.2 * mid, 0, 1))
	col = mix(col, c_sav, sav * 0.8)
	col = mix(col, c_trop, np.clip(tropic * 1.1 + 0.15 * mid, 0, 1))
	col = mix(col, c_bor, boreal)
	col = mix(col, c_tun, tundra)
	dcol = mix(c_des, c_des2, np.clip(0.5 + 0.5 * mid + 0.3 * big, 0, 1))
	col = mix(col, dcol, np.clip(desert * (1.1 + 0.2 * big), 0, 1))
	col *= (1.0 + 0.07 * mid + 0.035 * fine)[..., None]

	# mountains (height + darker/brownish + snow on the highest)
	mount = np.zeros((h, w), F32)
	for path, width, height in MOUNTAINS:
		for (l0, b0), (l1, b1) in zip(path[:-1], path[1:]):
			# distance to the segment in degrees (local flat approximation)
			cosb = math.cos(math.radians((b0 + b1) * 0.5))
			ax, ay = l0 * cosb, b0
			bx, by = l1 * cosb, b1
			r0 = max(0, int((90 - max(b0, b1) - 3 * width) / 180 * h))
			r1 = min(h, int((90 - min(b0, b1) + 3 * width) / 180 * h) + 1)
			c0 = int((min(l0, l1) + 180 - 3 * width / cosb) / 360 * w)
			c1 = int((max(l0, l1) + 180 + 3 * width / cosb) / 360 * w) + 1
			cols = np.arange(c0, c1) % w
			px = lon[r0:r1][:, cols] * cosb
			py = lat[r0:r1][:, cols]
			vx, vy = bx - ax, by - ay
			t = np.clip(((px - ax) * vx + (py - ay) * vy) / max(vx * vx + vy * vy, 1e-6), 0, 1)
			dd = np.hypot(px - (ax + t * vx), py - (ay + t * vy))
			mount[r0:r1, cols] = np.maximum(mount[r0:r1, cols], (height * np.exp(-(dd / width) ** 2)).astype(F32))
	ridges = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n[6], x * 30.0, y * 30.0, z * 30.0, 4, ridged=True), factor=1)
	mnt = mount * np.clip(0.55 + 0.45 * ridges, 0, 1.5) * land_hard
	col = mix(col, np.array(hexcol("6e5a44"), F32) * (1 + 0.1 * ridges[..., None]), np.clip(mnt * 0.8, 0, 0.75))
	snow = 0.75 * smoothstep(0.95, 1.3, mnt + 0.25 * fine + 0.1 * mid)
	col = mix(col, c_ice, snow)
	log("earth biomes", round(time.time() - t0, 1))

	# ice: Greenland (land north of ~60 at its longitudes), Antarctica, Arctic sea ice
	green = smoothstep(0.2, 0.6, blur_wrap(green_land, 3.0))
	icecap = np.maximum(green * land, ant.astype(F32))
	icecap = np.maximum(icecap, smoothstep(76, 80, lat + 2.0 * mid) * land_hard)
	col = mix(col, c_ice * (1 - 0.04 * fine[..., None]), np.clip(icecap, 0, 1))

	# oceans: deep blue, lighter on the continental shelves
	shelf = blur_wrap(land_hard, 7.0)
	shelf2 = blur_wrap(land_hard, 22.0)
	oc = ramp(np.clip(0.55 * shelf + 0.45 * shelf2 + 0.08 * mid, 0, 1),
		[(0.0, hexcol("0b2251")), (0.25, hexcol("0f2d63")), (0.55, hexcol("16407a")), (0.85, hexcol("1d5b8c")), (1.0, hexcol("2a6f98"))])
	oc *= (1.0 + 0.05 * big)[..., None]
	seaice = smoothstep(79, 84, lat + 2.5 * mid) + smoothstep(-66, -70, lat + 1.5 * mid)
	oc = mix(oc, np.array(hexcol("dfe8ee"), F32), np.clip(seaice, 0, 0.95))
	col = mix(oc, col, land)

	# height (bump): land plateau + mountains
	hgt = 0.15 * land + 0.85 * np.clip(mnt, 0, 1) + 0.03 * fine * land
	hgt = (hgt - hgt.min()) / max(1e-6, hgt.max() - hgt.min())
	rough = 0.38 + 0.52 * land + 0.1 * np.clip(seaice, 0, 1)

	# --- clouds ---
	cw = sphere_field(w, h, lambda lo, la, x, y, z: fbm(n[7], x * 2.2, y * 2.2, z * 2.2, 4), factor=4)
	clon = lon + 4.0 * cw
	clat = lat + 1.8 * cw
	# cyclones: spiral warps in the storm tracks
	for cl_, cb_, rr, ang in [(-32, 54, 9, 3.2), (-48, -48, 10, -3.0), (25, -50, 10, -3.4), (72, -46, 9, -3.0),
			(-150, 48, 10, 3.0), (160, 45, 9, 3.2), (-8, 62, 7, 2.6), (120, -52, 9, -3.2), (-100, -55, 9, -3.0)]:
		vortex_warp(clon, clat, cl_, cb_, rr, rr * 0.8, ang * 0.75, falloff=0.8, reach=3.0)
	cn = noise_at(n[8], clon, clat, 4.0, 7, stretch_z=2.0, gain=0.6)
	cn2 = noise_at(n[9], clon, clat, 20.0, 3, stretch_z=1.0)
	clim = (0.55 * np.exp(-((lat - 6) / 6.0) ** 2) - 0.55 * np.exp(-((alat - 24) / 9.0) ** 2)
		+ 0.45 * np.exp(-((alat - 55) / 11.0) ** 2) - 0.25)
	clim -= 0.9 * desert
	itcz = np.exp(-((lat - 6) / 7.0) ** 2)
	cv = cn * 0.5 + cn2 * (0.12 + 0.2 * itcz) + clim
	clouds = smoothstep(-0.05, 0.9, cv) ** 1.3
	clouds = np.clip(clouds * (0.85 + 0.15 * cn2) * 0.95, 0, 1)
	log("earth done", round(time.time() - t0, 1))
	return {"albedo": np.clip(col, 0, 1), "height": hgt, "rough": np.clip(rough, 0, 1), "clouds": clouds}


# ------------------------------------------------------------------------------------------------
GENERATORS = {
	"neptune": tex_neptune,
	"uranus": tex_uranus,
	"saturn": tex_saturn,
	"jupiter": tex_jupiter,
	"mars": tex_mars,
	"earth": tex_earth,
}
RING_GENERATORS = {"saturn": ring_saturn, "uranus": ring_uranus}


def generate(workdir: str, planets, w: int = TEX_W, h: int = TEX_H, force: bool = False) -> None:
	tex_dir = os.path.join(workdir, "tex")
	os.makedirs(tex_dir, exist_ok=True)
	for p in planets:
		albedo_path = os.path.join(tex_dir, f"{p}_albedo.png")
		if p in RING_GENERATORS:   # cheap, always regenerated
			save_png(os.path.join(tex_dir, f"{p}_ring.png"), RING_GENERATORS[p](), dither_seed=None)
		if os.path.exists(albedo_path) and not force:
			log(p, "cached")
			continue
		t0 = time.time()
		res = GENERATORS[p](w, h)
		for key, img in res.items():
			path = os.path.join(tex_dir, f"{p}_{key}.png")
			if key == "height":
				save_png16_gray(path, img)
			else:
				save_png(path, img, dither_seed=None if key != "albedo" else 3)
		# small preview
		from PIL import Image
		Image.open(albedo_path).resize((1024, 512), Image.LANCZOS).save(os.path.join(tex_dir, f"{p}_preview.png"))
		log(p, "written in", round(time.time() - t0, 1), "s")


if __name__ == "__main__":
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	if not args:
		print(__doc__)
		sys.exit(1)
	res = [a for a in sys.argv[1:] if a.startswith("--res=")]
	tw = int(res[0].split("=")[1]) if res else TEX_W
	generate(args[0], args[1:] or list(GENERATORS), tw, tw // 2, force="--force" in sys.argv)
