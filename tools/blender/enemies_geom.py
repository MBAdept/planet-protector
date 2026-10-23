"""Geometry, material and rig helpers for the enemy renders (see tools/blender/enemies.py).

Units: 1 Blender unit = 1 game pixel (= 2 sprite pixels). The creature faces the camera, which looks along +Y
from negative Y. X = right, Z = up. The logical enemy center (frame center) is the origin.
"""
import math

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import delaunay_2d_cdt

MB_K = 0.575  # visible radius / element radius of an isolated metaball (stiffness 2, threshold 0.6)


# --------------------------------------------------------------------------------------------------
# small math helpers
# --------------------------------------------------------------------------------------------------
def smoothstep(e0, e1, x):
	t = np.clip((np.asarray(x, dtype=float) - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


def v3(p):
	"""(x, z) or (x, y, z) -> np.array([x, y, z])."""
	p = tuple(p)
	if len(p) == 2:
		return np.array([p[0], 0.0, p[1]], dtype=float)
	return np.array(p, dtype=float)


def spline(points, n_out=None, spacing=None, per_seg=24):
	"""Uniform Catmull-Rom spline through points (k, D), resampled evenly by arc length."""
	P = np.asarray(points, dtype=float)
	if len(P) < 2:
		return P.copy()
	ext = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
	dense = []
	for i in range(len(P) - 1):
		p0, p1, p2, p3 = ext[i], ext[i + 1], ext[i + 2], ext[i + 3]
		ts = np.linspace(0.0, 1.0, per_seg, endpoint=False)[:, None]
		dense.append(0.5 * ((2 * p1) + (-p0 + p2) * ts + (2 * p0 - 5 * p1 + 4 * p2 - p3) * ts ** 2
			+ (-p0 + 3 * p1 - 3 * p2 + p3) * ts ** 3))
	dense.append(P[-1:])
	dense = np.vstack(dense)
	seg = np.linalg.norm(np.diff(dense, axis=0), axis=1)
	cum = np.concatenate([[0.0], np.cumsum(seg)])
	total = cum[-1]
	if n_out is None:
		n_out = max(2, int(math.ceil(total / (spacing or 1.0))) + 1)
	targets = np.linspace(0.0, total, n_out)
	out = np.empty((n_out, P.shape[1]))
	for d in range(P.shape[1]):
		out[:, d] = np.interp(targets, cum, dense[:, d])
	return out


def closed_spline(points, spacing=0.5, per_seg=24, tension=0.5):
	"""Closed Catmull-Rom loop through points, resampled evenly (no duplicate end point)."""
	P = np.asarray(points, dtype=float)
	n = len(P)
	dense = []
	ts = np.linspace(0.0, 1.0, per_seg, endpoint=False)[:, None]
	for i in range(n):
		p0, p1, p2, p3 = P[(i - 1) % n], P[i], P[(i + 1) % n], P[(i + 2) % n]
		m1 = (p2 - p0) * tension
		m2 = (p3 - p1) * tension
		h00 = 2 * ts ** 3 - 3 * ts ** 2 + 1
		h10 = ts ** 3 - 2 * ts ** 2 + ts
		h01 = -2 * ts ** 3 + 3 * ts ** 2
		h11 = ts ** 3 - ts ** 2
		dense.append(h00 * p1 + h10 * m1 + h01 * p2 + h11 * m2)
	dense = np.vstack(dense + [P[:1]])
	seg = np.linalg.norm(np.diff(dense, axis=0), axis=1)
	cum = np.concatenate([[0.0], np.cumsum(seg)])
	m = max(8, int(cum[-1] / spacing))
	tt = np.linspace(0.0, cum[-1], m, endpoint=False)
	return np.stack([np.interp(tt, cum, dense[:, d]) for d in range(P.shape[1])], axis=1)


def quadratic(a, c, b, n):
	a, b, c = np.asarray(a, float), np.asarray(b, float), np.asarray(c, float)
	t = np.linspace(0.0, 1.0, n)[:, None]
	return (1 - t) ** 2 * a + 2 * (1 - t) * t * c + t ** 2 * b


def rot_y(points, center, ang):
	"""Rotate (N,3) points about the axis parallel to Y through center by ang (array or scalar), in the X-Z plane.
	Positive angle = counter-clockwise when looking at the X-Z plane with Z up (raises a right wing)."""
	c = np.cos(ang)
	s = np.sin(ang)
	dx = points[:, 0] - center[0]
	dz = points[:, 2] - center[2]
	out = points.copy()
	out[:, 0] = center[0] + dx * c - dz * s
	out[:, 2] = center[2] + dx * s + dz * c
	return out


def rot_x(points, center, ang):
	"""Rotate about the axis parallel to X through center (tilts points below/above toward/away from camera)."""
	c = np.cos(ang)
	s = np.sin(ang)
	dy = points[:, 1] - center[1]
	dz = points[:, 2] - center[2]
	out = points.copy()
	out[:, 1] = center[1] + dy * c - dz * s
	out[:, 2] = center[2] + dy * s + dz * c
	return out


def rot_z(points, center, ang):
	"""Rotate about the vertical axis through center (sweeps a wing toward (-Y) / away from the camera)."""
	c = np.cos(ang)
	s = np.sin(ang)
	dx = points[:, 0] - center[0]
	dy = points[:, 1] - center[1]
	out = points.copy()
	out[:, 0] = center[0] + dx * c + dy * s
	out[:, 1] = center[1] - dx * s + dy * c
	return out


def seg_distance(pts2, polyline2):
	"""Distance from (N,2) points to a (M,2) polyline."""
	best = np.full(len(pts2), np.inf)
	for a, b in zip(polyline2[:-1], polyline2[1:]):
		ab = b - a
		L2 = float(ab @ ab) or 1e-9
		t = np.clip(((pts2 - a) @ ab) / L2, 0.0, 1.0)
		d = np.linalg.norm(pts2 - (a + t[:, None] * ab), axis=1)
		best = np.minimum(best, d)
	return best


def inside_polygon(pts2, poly2):
	x = pts2[:, 0][:, None]
	y = pts2[:, 1][:, None]
	x1, y1 = poly2[:, 0][None, :], poly2[:, 1][None, :]
	x2, y2 = np.roll(poly2[:, 0], -1)[None, :], np.roll(poly2[:, 1], -1)[None, :]
	cond = (y1 > y) != (y2 > y)
	with np.errstate(divide="ignore", invalid="ignore"):
		xint = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
	cross = cond & (x < xint)
	return (np.count_nonzero(cross, axis=1) % 2) == 1


# --------------------------------------------------------------------------------------------------
# mesh builders -> (verts (N,3), faces [tuple], anchors (N,3))
# --------------------------------------------------------------------------------------------------
class Part:
	"""Geometry chunk: vertices, faces, per-vertex rigid anchors, optional per-vertex bulge weight."""

	def __init__(self, verts, faces, anchors=None, bulge=None, uv=None):
		self.verts = np.asarray(verts, dtype=float)
		self.faces = [tuple(f) for f in faces]
		self.anchors = self.verts.copy() if anchors is None else np.asarray(anchors, dtype=float)
		self.bulge = np.zeros(len(self.verts)) if bulge is None else np.asarray(bulge, dtype=float)
		self.uv = uv

	@staticmethod
	def merge(parts):
		verts, faces, anchors, bulge = [], [], [], []
		off = 0
		for p in parts:
			verts.append(p.verts)
			anchors.append(p.anchors)
			bulge.append(p.bulge)
			faces.extend(tuple(i + off for i in f) for f in p.faces)
			off += len(p.verts)
		return Part(np.vstack(verts), faces, np.vstack(anchors), np.concatenate(bulge))


def tube(path, radii, sides=10, cap0=True, cap1=True, ref=(0.0, -1.0, 0.0), squash=1.0, twist=0.0):
	"""Sweep a circle along path (N,3). radii scalar or (N,). squash scales the cross-section along the
	reference direction (default: towards the camera)."""
	P = np.asarray(path, dtype=float)
	n = len(P)
	R = np.broadcast_to(np.asarray(radii, dtype=float), (n,)).copy()
	T = np.gradient(P, axis=0)
	T /= np.linalg.norm(T, axis=1)[:, None] + 1e-12
	ref = np.asarray(ref, dtype=float)
	N0 = ref - T[0] * (ref @ T[0])
	if np.linalg.norm(N0) < 1e-6:
		N0 = np.cross(T[0], [0.0, 0.0, 1.0])
	N0 /= np.linalg.norm(N0)
	normals = [N0]
	for i in range(1, n):
		Nprev = normals[-1]
		Nn = Nprev - T[i] * (Nprev @ T[i])
		ln = np.linalg.norm(Nn)
		Nn = Nn / ln if ln > 1e-9 else normals[-1]
		normals.append(Nn)
	normals = np.array(normals)
	binorm = np.cross(T, normals)
	ang = np.linspace(0.0, 2 * math.pi, sides, endpoint=False)
	verts, anchors = [], []
	for i in range(n):
		a = ang + twist * i / max(1, n - 1)
		ring = P[i] + R[i] * (np.cos(a)[:, None] * normals[i] * squash + np.sin(a)[:, None] * binorm[i])
		verts.append(ring)
		anchors.append(np.repeat(P[i][None, :], sides, axis=0))
	verts = np.vstack(verts)
	anchors = np.vstack(anchors)
	faces = []
	for i in range(n - 1):
		for j in range(sides):
			a = i * sides + j
			b = i * sides + (j + 1) % sides
			c = (i + 1) * sides + (j + 1) % sides
			d = (i + 1) * sides + j
			faces.append((a, b, c, d))
	extra_v, extra_a = [], []
	nv = len(verts)
	if cap0:
		extra_v.append(P[0] - T[0] * R[0] * 0.3)
		extra_a.append(P[0])
		for j in range(sides):
			faces.append((nv, (j + 1) % sides, j))
		nv += 1
	if cap1:
		extra_v.append(P[-1] + T[-1] * R[-1] * 0.3)
		extra_a.append(P[-1])
		base = (n - 1) * sides
		for j in range(sides):
			faces.append((nv, base + j, base + (j + 1) % sides))
		nv += 1
	if extra_v:
		verts = np.vstack([verts, np.array(extra_v)])
		anchors = np.vstack([anchors, np.array(extra_a)])
	return Part(verts, faces, anchors)


def taper(n, r0, r1, power=1.0, bulb=0.0):
	t = np.linspace(0.0, 1.0, n)
	r = r0 + (r1 - r0) * t ** power
	if bulb:
		r = r * (1.0 + bulb * np.sin(np.pi * t))
	return r


def horn(points, r0, r1=0.02, sides=10, n=None, ribs=0, rib_amp=0.12, power=1.0, spacing=0.5):
	"""Curved tapered spike through control points (3D). ribs adds ring ridges."""
	path = spline(points, n_out=n, spacing=spacing)
	m = len(path)
	r = taper(m, r0, r1, power)
	if ribs:
		t = np.linspace(0.0, 1.0, m)
		r = r * (1.0 + rib_amp * np.maximum(0.0, np.sin(t * ribs * 2 * np.pi)) ** 2 * (1 - t))
	return tube(path, r, sides=sides, cap0=True, cap1=True)


def ellipsoid(center, radii, rot=(0.0, 0.0, 0.0), seg=20, rings=12):
	"""UV ellipsoid. rot = euler XYZ radians."""
	verts = []
	for i in range(1, rings):
		th = math.pi * i / rings
		for j in range(seg):
			ph = 2 * math.pi * j / seg
			verts.append((math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)))
	verts = [(0.0, 0.0, 1.0)] + verts + [(0.0, 0.0, -1.0)]
	V = np.array(verts) * np.asarray(radii, float)
	faces = []
	for j in range(seg):
		faces.append((0, 1 + j, 1 + (j + 1) % seg))
	for i in range(rings - 2):
		for j in range(seg):
			a = 1 + i * seg + j
			b = 1 + i * seg + (j + 1) % seg
			c = 1 + (i + 1) * seg + (j + 1) % seg
			d = 1 + (i + 1) * seg + j
			faces.append((a, d, c, b))
	last = len(V) - 1
	base = 1 + (rings - 2) * seg
	for j in range(seg):
		faces.append((last, base + (j + 1) % seg, base + j))
	V = _apply_rot(V, rot) + np.asarray(center, float)
	c = np.asarray(center, float)
	return Part(V, faces, np.repeat(c[None, :], len(V), axis=0))


def _apply_rot(V, rot):
	from mathutils import Euler
	M = np.array(Euler(rot, "XYZ").to_matrix())
	return V @ M.T


def plate(center, w, h, thick=0.8, dome=0.6, rot=(0.0, 0.0, 0.0), sq=3.0, n=48, taper_top=0.0, curve=0.0,
		point=0.0, bevel=0.22):
	"""Hard armour plate facing the camera (-Y): superellipse outline (half sizes w, h), side wall, chamfer and a
	slightly domed face, with split vertices at the creases so the edges stay crisp.
	taper_top > 0 narrows the top, < 0 the bottom (shield); point > 0 pulls the bottom into a point (scale);
	curve bends the plate around the vertical axis (edges go back, +Y)."""
	ang = np.linspace(0.0, 2 * math.pi, n, endpoint=False) - math.pi / 2
	cx = np.sign(np.cos(ang)) * np.abs(np.cos(ang)) ** (2.0 / sq)
	cz = np.sign(np.sin(ang)) * np.abs(np.sin(ang)) ** (2.0 / sq)
	cx = cx * (1.0 - taper_top * (cz * 0.5 + 0.5))
	if point > 0.0:
		low = cz < 0.0
		cx[low] = cx[low] * (1.0 - point * np.abs(cz[low]) ** 0.8)
		cz[low] = cz[low] * (1.0 + 0.45 * point)
	ch = min(bevel, 0.45) * min(w, h)
	sw = 1.0 - ch / max(w, 1e-6)
	sh = 1.0 - ch / max(h, 1e-6)
	# (scale_x, scale_z, y) per ring; rings in the same group share vertices, groups are split (crease)
	groups = [
		[(1.0, 1.0, 0.25), (1.0, 1.0, -thick)],                                    # side wall
		[(1.0, 1.0, -thick), (sw, sh, -thick - ch * 0.8)],                         # chamfer
		[(sw, sh, -thick - ch * 0.8), (sw * 0.72, sh * 0.72, -thick - ch * 0.8 - dome * 0.5),
			(sw * 0.42, sh * 0.42, -thick - ch * 0.8 - dome * 0.85), (sw * 0.14, sh * 0.14, -thick - ch * 0.8 - dome)],
	]
	verts, faces = [], []
	for g in groups:
		base = len(verts)
		for sx, sz, y in g:
			for i in range(n):
				verts.append((cx[i] * w * sx, y, cz[i] * h * sz))
		for r in range(len(g) - 1):
			for i in range(n):
				a = base + r * n + i
				b = base + r * n + (i + 1) % n
				c = base + (r + 1) * n + (i + 1) % n
				d = base + (r + 1) * n + i
				faces.append((a, b, c, d))
	last = len(verts) - n
	verts.append((0.0, -thick - ch * 0.8 - dome, 0.0))
	fc = len(verts) - 1
	for i in range(n):
		faces.append((last + i, last + (i + 1) % n, fc))
	verts.append((0.0, 0.25, 0.0))
	bc = len(verts) - 1
	for i in range(n):
		faces.append(((i + 1) % n, i, bc))
	verts = np.array(verts)
	verts[:, 1] += curve * (verts[:, 0] / max(w, 1e-6)) ** 2
	V = _apply_rot(verts, rot) + np.asarray(center, float)
	c = np.asarray(center, float)
	return Part(V, faces, np.repeat(c[None, :], len(V), axis=0))


def slab(outline2, y, thick=0.8, dome=0.2, bevel=0.5, spacing=0.5, round_corners=True, tension=0.3, curve=0.0):
	"""Armour slab from an arbitrary (convex-ish) outline in the X-Z plane (absolute coords, any winding).
	Back face at y + 0.2, front face at y - thick - dome (towards the camera). Crisp creases (split vertices)
	between wall, chamfer and face. Vertices are their own anchors (the slab deforms like the membrane)."""
	O = np.asarray(outline2, dtype=float)
	if round_corners:
		loop = closed_spline(O, spacing, tension=tension)
	else:
		closed = np.vstack([O, O[:1]])
		seg = np.linalg.norm(np.diff(closed, axis=0), axis=1)
		cum = np.concatenate([[0.0], np.cumsum(seg)])
		tt = np.arange(0.0, cum[-1], spacing)
		loop = np.stack([np.interp(tt, cum, closed[:, 0]), np.interp(tt, cum, closed[:, 1])], axis=1)
	c = loop.mean(axis=0)
	n = len(loop)
	rad = np.linalg.norm(loop - c, axis=1).mean()
	sb = max(0.0, 1.0 - bevel / max(rad, 1e-6))

	def ring(sc, yy):
		p = c + (loop - c) * sc
		return [(px, yy, pz) for px, pz in p]

	groups = [
		[(1.0, y + 0.2), (1.0, y - thick)],
		[(1.0, y - thick), (sb, y - thick - bevel * 0.7)],
		[(sb, y - thick - bevel * 0.7), (sb * 0.7, y - thick - bevel * 0.7 - dome * 0.5),
			(sb * 0.4, y - thick - bevel * 0.7 - dome * 0.85), (sb * 0.12, y - thick - bevel * 0.7 - dome)],
	]
	verts, faces = [], []
	for g in groups:
		base = len(verts)
		for sc, yy in g:
			verts.extend(ring(sc, yy))
		for r in range(len(g) - 1):
			for i in range(n):
				a = base + r * n + i
				b = base + r * n + (i + 1) % n
				cc = base + (r + 1) * n + (i + 1) % n
				d = base + (r + 1) * n + i
				faces.append((a, b, cc, d))
	last = len(verts) - n
	verts.append((c[0], y - thick - bevel * 0.7 - dome, c[1]))
	fc = len(verts) - 1
	for i in range(n):
		faces.append((last + i, last + (i + 1) % n, fc))
	verts.append((c[0], y + 0.2, c[1]))
	bc = len(verts) - 1
	for i in range(n):
		faces.append(((i + 1) % n, i, bc))
	V = np.array(verts)
	if curve:
		V[:, 1] += curve * ((V[:, 0] - c[0]) / max(rad, 1e-6)) ** 2
	return Part(V, faces, V.copy())


def offset_loop(loop, d, min_cos=0.35):
	"""Inward offset (miter, clamped) of a counter-clockwise closed loop (N,2) by distance d."""
	prev = np.roll(loop, 1, axis=0)
	nxt = np.roll(loop, -1, axis=0)
	e1 = loop - prev
	e2 = nxt - loop
	e1 /= np.linalg.norm(e1, axis=1)[:, None] + 1e-12
	e2 /= np.linalg.norm(e2, axis=1)[:, None] + 1e-12
	n1 = np.stack([-e1[:, 1], e1[:, 0]], axis=1)
	n2 = np.stack([-e2[:, 1], e2[:, 0]], axis=1)
	m = n1 + n2
	m /= np.linalg.norm(m, axis=1)[:, None] + 1e-12
	cos = np.sum(m * n1, axis=1)
	return loop + m * (d / np.maximum(cos, min_cos))[:, None]


def armor_plate(outline2, y, thick=0.8, bevel=0.45, dome=0.35, dome_in=0.9, spacing=0.4, lift=None, pillow=0.0,
		pillow_r=3.0, grid=0.6, profile="round"):
	"""Hard armour plate with an ANGULAR outline (sharp corners, polygon in the X-Z plane, absolute coords).
	Back face at y + 0.2, crisp side wall, a chamfer inset by `bevel` (true polygon offset, so long thin plates get
	an even rim) and a slightly domed face (raised by `dome` over an inset of `dome_in`). Creases are split vertices.
	pillow: the inner face bulges further toward the camera by up to this much with a rounded profile over the distance
	pillow_r from its border (long lames get a cylinder-like cross-section: lit top half, shaded bottom half);
	profile="roof" makes the bulge linear instead, i.e. flat facets meeting in a crisp ridge along the medial axis.
	lift: optional (dir2, amount): the face is tilted toward the camera along dir2 (e.g. the lower edge of a shingle
	lifts off the plate below it). Vertices are their own anchors (the plate bends with the wing like the membrane)."""
	O = np.asarray(outline2, dtype=float)
	closed = np.vstack([O, O[:1]])
	seg = np.linalg.norm(np.diff(closed, axis=0), axis=1)
	# resample every edge separately so that every corner stays a vertex
	loop = []
	for i in range(len(O)):
		n = max(1, int(math.ceil(seg[i] / spacing)))
		t = np.arange(n)[:, None] / n
		loop.append(O[i] + (closed[i + 1] - O[i]) * t)
	loop = np.vstack(loop)
	area = 0.5 * np.sum(loop[:, 0] * np.roll(loop[:, 1], -1) - np.roll(loop[:, 0], -1) * loop[:, 1])
	if area < 0:
		loop = loop[::-1]
	n = len(loop)
	ch = offset_loop(loop, bevel)
	inner = offset_loop(loop, bevel + dome_in)
	yf = y - thick - bevel * 0.7
	rings = [  # groups of (loop2, y); rings in a group share vertices, groups are split (crease)
		[(loop, y + 0.2), (loop, y - thick)],
		[(loop, y - thick), (ch, yf)],
		[(ch, yf), (inner, yf - dome)],
	]
	verts, faces = [], []
	for g in rings:
		base = len(verts)
		for lp, yy in g:
			verts.extend((px, yy, pz) for px, pz in lp)
		for r in range(len(g) - 1):
			for i in range(n):
				a = base + r * n + i
				b = base + r * n + (i + 1) % n
				c = base + (r + 1) * n + (i + 1) % n
				d = base + (r + 1) * n + i
				faces.append((a, b, c, d))
	# inner face: constrained triangulation of the inner ring (+ interior grid for the pillow bulge); own vertices
	pts = inner
	if pillow > 0.0:
		lo, hi = inner.min(axis=0), inner.max(axis=0)
		gx, gz = [], []
		row = 0
		zz = lo[1]
		while zz <= hi[1]:
			xs = np.arange(lo[0] + (grid * 0.5 if row % 2 else 0.0), hi[0], grid)
			gx.append(xs)
			gz.append(np.full(len(xs), zz))
			zz += grid * 0.866
			row += 1
		g = np.stack([np.concatenate(gx), np.concatenate(gz)], axis=1)
		g = g[inside_polygon(g, inner)]
		g = g[seg_distance(g, np.vstack([inner, inner[:1]])) > grid * 0.45]
		pts = np.vstack([inner, g])
	res = delaunay_2d_cdt([Vector((float(px), float(pz))) for px, pz in pts], [], [list(range(n))], 1, 1e-6)
	out2 = np.array([(v[0], v[1]) for v in res[0]])
	face_y = np.full(len(out2), yf - dome)
	if pillow > 0.0:
		dist = seg_distance(out2, np.vstack([inner, inner[:1]]))
		u = np.clip(dist / pillow_r, 0.0, 1.0)
		face_y -= pillow * (u if profile == "roof" else 1.0 - (1.0 - u) ** 2)
	base = len(verts)
	verts.extend((px, fy, pz) for (px, pz), fy in zip(out2, face_y))
	for f in res[2]:
		if len(f) >= 3:
			faces.append(tuple(base + i for i in f))
	# back cap
	c = loop.mean(axis=0)
	verts.append((c[0], y + 0.2, c[1]))
	bc = len(verts) - 1
	for i in range(n):
		faces.append(((i + 1) % n, i, bc))
	V = np.array(verts, dtype=float)
	if lift is not None:
		d2 = np.asarray(lift[0], float)
		d2 /= np.linalg.norm(d2)
		proj = (V[:, 0] - c[0]) * d2[0] + (V[:, 2] - c[1]) * d2[1]
		p0, p1 = float(proj.min()), float(proj.max())
		V[:, 1] -= lift[1] * (proj - p0) / max(1e-6, p1 - p0)
	return Part(V, faces, V.copy())


def sickle(base, heading, length, bend=150.0, r0=1.0, r1=0.03, n=14, power=1.6, y_drift=0.0, sides=10, thick=1.8):
	"""Claw hook / scythe in the X-Z plane: starts at base (x, y, z), initially pointing along heading (x, z),
	then turns by `bend` degrees (positive = clockwise as seen by the camera) with the curvature growing toward
	the tip, like a raptor talon."""
	base = np.asarray(base, float)
	h0 = math.atan2(heading[1], heading[0])
	step = length / n
	pts = [base.copy()]
	p = base.copy()
	for i in range(1, n + 1):
		ang = h0 - math.radians(bend) * (i / n) ** power
		p = p + np.array([math.cos(ang) * step, y_drift / n, math.sin(ang) * step])
		pts.append(p.copy())
	path = spline(np.array(pts), spacing=0.3)
	# claw profile: stays heavy for most of its length, then narrows quickly to a sharp tip
	return tube(path, taper(len(path), r0, r1, thick), sides=sides)


# --------------------------------------------------------------------------------------------------
# Blender object helpers
# --------------------------------------------------------------------------------------------------
def mesh_object(name, part, mat, parent=None, smooth=True, uv=None):
	me = bpy.data.meshes.new(name)
	me.from_pydata(part.verts.tolist(), [], part.faces)
	me.validate(clean_customdata=False)
	if smooth:
		me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
	if uv is not None:
		layer = me.uv_layers.new(name="UVMap")
		loop_vi = np.zeros(len(me.loops), dtype=np.int32)
		me.loops.foreach_get("vertex_index", loop_vi)
		layer.data.foreach_set("uv", np.asarray(uv, dtype=np.float32)[loop_vi].ravel())
	me.materials.append(mat)
	ob = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(ob)
	if parent is not None:
		ob.parent = parent
	return ob


def set_mesh_verts(ob, verts):
	me = ob.data
	me.vertices.foreach_set("co", np.asarray(verts, dtype=np.float32).ravel())
	me.update()


class Meta:
	"""Metaball family. Sizes are VISIBLE radii (approx., isolated element)."""

	def __init__(self, name, mat, parent=None, res=0.32):
		self.mb = bpy.data.metaballs.new(name)
		self.mb.resolution = res
		self.mb.render_resolution = res
		self.mb.threshold = 0.6
		self.mb.materials.append(mat)
		self.ob = bpy.data.objects.new(name, self.mb)
		bpy.context.scene.collection.objects.link(self.ob)
		if parent is not None:
			self.ob.parent = parent

	def _el(self, typ, co, r, stiff, neg):
		e = self.mb.elements.new()
		e.type = typ
		e.co = tuple(v3(co))
		e.radius = r / MB_K
		e.stiffness = stiff
		e.use_negative = neg
		return e

	def ball(self, co, r, stiff=2.0, neg=False):
		return self._el("BALL", co, r, stiff, neg)

	def ell(self, co, rx, ry, rz, rot=(0.0, 0.0, 0.0), stiff=2.0, neg=False):
		m = max(rx, ry, rz)
		e = self._el("ELLIPSOID", co, m, stiff, neg)
		e.size_x, e.size_y, e.size_z = rx / m, ry / m, rz / m
		from mathutils import Euler
		e.rotation = Euler(rot, "XYZ").to_quaternion()
		return e

	def capsule(self, a, b, r, stiff=2.0, neg=False):
		a, b = v3(a), v3(b)
		d = b - a
		L = float(np.linalg.norm(d))
		e = self._el("CAPSULE", (a + b) / 2, r, stiff, neg)
		# size_x of a CAPSULE element is the ABSOLUTE half-length of its core segment (it is not scaled by the
		# radius), so the visible capsule spans a..b plus the visible radius r at both ends.
		e.size_x = L / 2.0
		e.rotation = Vector((1.0, 0.0, 0.0)).rotation_difference(Vector(d / max(L, 1e-9)))
		return e

	def chain(self, points, radii, stiff=2.0, step=None):
		"""Capsules along a polyline with varying radius (balls placed densely)."""
		pts = spline([v3(p) for p in points], spacing=step or 0.8)
		rr = np.interp(np.linspace(0, 1, len(pts)), np.linspace(0, 1, len(radii)), radii)
		for p, r in zip(pts, rr):
			self.ball(p, r, stiff)


class Surface:
	"""Ray casts against evaluated objects (front surface lookup, camera direction +Y)."""

	def __init__(self, objects):
		dg = bpy.context.evaluated_depsgraph_get()
		verts, polys = [], []
		off = 0
		for ob in objects:
			ev = ob.evaluated_get(dg)
			me = ev.to_mesh()
			M = ob.matrix_world
			vs = [tuple(M @ v.co) for v in me.vertices]
			verts.extend(vs)
			polys.extend([tuple(i + off for i in p.vertices) for p in me.polygons])
			off += len(vs)
			ev.to_mesh_clear()
		self.bvh = BVHTree.FromPolygons(verts, polys)
		self.verts = np.array(verts) if verts else np.zeros((0, 3))

	def front(self, x, z, inset=0.0):
		"""Front surface point at (x, z) (smallest y); returns np.array or None."""
		hit = self.bvh.ray_cast(Vector((x, -200.0, z)), Vector((0.0, 1.0, 0.0)))
		if hit[0] is None:
			return None
		return np.array(hit[0]) + np.array([0.0, inset, 0.0])

	def normal(self, x, z):
		hit = self.bvh.ray_cast(Vector((x, -200.0, z)), Vector((0.0, 1.0, 0.0)))
		return None if hit[0] is None else np.array(hit[1])


# --------------------------------------------------------------------------------------------------
# materials
# --------------------------------------------------------------------------------------------------
def _nodes(mat):
	if hasattr(mat, "use_nodes") and not mat.use_nodes:
		mat.use_nodes = True
	return mat.node_tree.nodes, mat.node_tree.links


def mat_surface(name, albedo=1.0, rough=0.45, spec=0.5, bump=0.0, bump_scale=0.35, bump_detail=3.0,
		coords="Object", coat=0.0, voronoi=0.0):
	"""White(ish) principled material. bump: strength of a noise bump (skin/leather)."""
	mat = bpy.data.materials.new(name)
	nodes, links = _nodes(mat)
	bsdf = nodes.get("Principled BSDF")
	bsdf.inputs["Base Color"].default_value = (albedo, albedo, albedo, 1.0)
	bsdf.inputs["Roughness"].default_value = rough
	bsdf.inputs["Specular IOR Level"].default_value = spec
	if coat > 0.0:
		bsdf.inputs["Coat Weight"].default_value = coat
		bsdf.inputs["Coat Roughness"].default_value = 0.15
	if bump > 0.0:
		tc = nodes.new("ShaderNodeTexCoord")
		noise = nodes.new("ShaderNodeTexNoise")
		noise.inputs["Scale"].default_value = bump_scale
		noise.inputs["Detail"].default_value = bump_detail
		noise.inputs["Roughness"].default_value = 0.55
		links.new(tc.outputs[coords], noise.inputs["Vector"])
		height = noise.outputs["Fac"]
		if voronoi > 0.0:
			vor = nodes.new("ShaderNodeTexVoronoi")
			vor.feature = "DISTANCE_TO_EDGE"
			vor.inputs["Scale"].default_value = voronoi
			links.new(tc.outputs[coords], vor.inputs["Vector"])
			mix = nodes.new("ShaderNodeMath")
			mix.operation = "ADD"
			sm = nodes.new("ShaderNodeMath")
			sm.operation = "MINIMUM"
			sm.inputs[1].default_value = 0.08
			links.new(vor.outputs["Distance"], sm.inputs[0])
			links.new(noise.outputs["Fac"], mix.inputs[0])
			mul = nodes.new("ShaderNodeMath")
			mul.operation = "MULTIPLY"
			mul.inputs[1].default_value = 4.0
			links.new(sm.outputs[0], mul.inputs[0])
			links.new(mul.outputs[0], mix.inputs[1])
			height = mix.outputs[0]
		bnode = nodes.new("ShaderNodeBump")
		bnode.inputs["Strength"].default_value = bump
		bnode.inputs["Distance"].default_value = 0.3
		links.new(height, bnode.inputs["Height"])
		links.new(bnode.outputs["Normal"], bsdf.inputs["Normal"])
	return mat


def mat_emission(name, strength=1.0):
	mat = bpy.data.materials.new(name)
	nodes, links = _nodes(mat)
	for n in list(nodes):
		nodes.remove(n)
	out = nodes.new("ShaderNodeOutputMaterial")
	em = nodes.new("ShaderNodeEmission")
	em.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
	em.inputs["Strength"].default_value = strength
	links.new(em.outputs["Emission"], out.inputs["Surface"])
	return mat


def mat_eye(name, strength=1.0):
	"""Emissive eye whose centre is hot (B=1) and whose rim falls off a little (B~0.65) for a rounded glow."""
	mat = bpy.data.materials.new(name)
	nodes, links = _nodes(mat)
	for n in list(nodes):
		nodes.remove(n)
	out = nodes.new("ShaderNodeOutputMaterial")
	em = nodes.new("ShaderNodeEmission")
	lw = nodes.new("ShaderNodeLayerWeight")
	lw.inputs["Blend"].default_value = 0.35
	ramp = nodes.new("ShaderNodeMapRange")
	ramp.inputs["From Min"].default_value = 0.0
	ramp.inputs["From Max"].default_value = 1.0
	ramp.inputs["To Min"].default_value = strength
	ramp.inputs["To Max"].default_value = strength * 0.6
	links.new(lw.outputs["Facing"], ramp.inputs["Value"])
	links.new(ramp.outputs["Result"], em.inputs["Strength"])
	links.new(em.outputs["Emission"], out.inputs["Surface"])
	return mat


# --------------------------------------------------------------------------------------------------
# wing rig
# --------------------------------------------------------------------------------------------------
class WingSpec:
	"""Right wing description in rest pose (X-Z plane). Left wing is mirrored.

	arm:      [(x, z), ...] root -> elbow -> wrist (leading edge bone), arm_r radii per point
	fingers:  list of dicts {pts: [(x, z), ...] starting at the wrist, r0, r1}
	edges:    list (len(fingers)) of dicts {depth, n, jag, notch}: trailing edge after finger k
	          (between tip k and tip k+1, the last one between the last tip and attach[0])
	attach:   [(x, z), ...] body side of the membrane, from the hip back up to near the root
	"""

	def __init__(self, **kw):
		self.name = kw.get("name", "wing")
		self.pivot = v3(kw["pivot"])
		self.y = kw.get("y", 2.0)
		self.arm = [v3(p) for p in kw["arm"]]
		self.arm_r = kw.get("arm_r", [1.6, 1.3, 1.0])
		self.fingers = kw["fingers"]
		self.edges = kw["edges"]
		self.attach = [v3(p) for p in kw["attach"]]
		self.membrane_spacing = kw.get("spacing", 0.9)
		self.billow = kw.get("billow", 1.2)
		self.hem = kw.get("hem", 0.2)            # thickened trailing edge (catches rim light)
		self.bone_y = kw.get("bone_y", None)
		# flap parameters (degrees)
		self.mean1 = kw.get("mean1", 6.0)
		self.amp1 = kw.get("amp1", 28.0)
		self.mean2 = kw.get("mean2", 0.0)
		self.amp2 = kw.get("amp2", 20.0)
		self.lag = math.radians(kw.get("lag", 70.0))
		self.phase = kw.get("phase", 0.0)
		self.sweep = math.radians(kw.get("sweep", 14.0))
		self.pitch = math.radians(kw.get("pitch", 16.0))
		self.pitch_mean = math.radians(kw.get("pitch_mean", 8.0))
		self.cup = kw.get("cup", 4.0)            # tips come toward the camera by this much (game px)
		self.cup_len = kw.get("cup_len", 40.0)
		self.fan = kw.get("fan", (-115.0, -45.0))
		self.outer = kw.get("outer", (55.0, 120.0))
		self.extra = []          # list of (Part, material key)

	@property
	def wrist(self):
		return self.arm[-1]

	# ---------------------------------------------------------------------------------------------
	def outline(self):
		"""Closed membrane outline (list of (x, z)) and the bone polylines (for bulge weights)."""
		arm_line = spline([(p[0], p[2]) for p in self.arm], spacing=0.6)
		pts = [arm_line]
		bones = [arm_line]
		tips = []
		for f in self.fingers:
			line = spline([(p[0], p[1]) for p in f["pts"]], spacing=0.6)
			bones.append(line)
			tips.append(line[-1])
		f0 = bones[1]
		pts.append(f0[1:])
		self._edge_curves = []
		ends = tips + [np.array([self.attach[0][0], self.attach[0][2]])]
		for k, e in enumerate(self.edges):
			a = ends[k]
			b = ends[k + 1]
			curve = self._edge(a, b, e)
			self._edge_curves.append(curve)
			pts.append(curve[1:])
		att = [(p[0], p[2]) for p in self.attach]
		if len(att) > 1:
			pts.append(spline(att, spacing=0.8)[1:])
		poly = np.vstack(pts)
		# drop the closing duplicate if the attach ends at the arm root
		if np.linalg.norm(poly[-1] - poly[0]) < 0.3:
			poly = poly[:-1]
		return poly, bones

	def _edge(self, a, b, e):
		a = np.asarray(a, float)
		b = np.asarray(b, float)
		w = np.array([self.wrist[0], self.wrist[2]])
		mid = (a + b) / 2
		L = np.linalg.norm(b - a)
		depth = e.get("depth", 0.25)
		inward = w - mid
		inward /= np.linalg.norm(inward) + 1e-9
		if "pts" in e:
			# angular polyline a -> pts... -> b (sharp corners, e.g. stepped armour-plate edges)
			poly = np.vstack([a[None, :], np.asarray(e["pts"], float), b[None, :]])
			seg = np.linalg.norm(np.diff(poly, axis=0), axis=1)
			cum = np.concatenate([[0.0], np.cumsum(seg)])
			n = max(8, int(cum[-1] / 0.5))
			tt = np.linspace(0.0, cum[-1], n)
			return np.stack([np.interp(tt, cum, poly[:, 0]), np.interp(tt, cum, poly[:, 1])], axis=1)
		if "control" in e:
			c = np.asarray(e["control"], float)
		else:
			c = mid + inward * depth * L
		n = max(8, int(L / 0.6))
		curve = quadratic(a, c, b, n)
		notch = e.get("notch", 0.0)
		if notch:
			# sharp V notch at the middle of the edge (forked tips)
			t = np.linspace(0, 1, n)
			curve += inward[None, :] * notch * L * np.maximum(0.0, 1.0 - np.abs(t - 0.5) / 0.22)[:, None] ** 1.6
		jag = e.get("jag", 0.0)
		if jag:
			t = np.linspace(0, 1, n)
			teeth = e.get("teeth", 4)
			saw = np.abs(((t * teeth) % 1.0) - 0.5) * 2.0  # 1 at ends of each tooth, 0 middle
			curve += inward[None, :] * jag * (1.0 - saw)[:, None] * np.sin(np.pi * t)[:, None]
		return curve

	# ---------------------------------------------------------------------------------------------
	def membrane(self):
		poly, bones = self.outline()
		# resample outline evenly
		closed = np.vstack([poly, poly[:1]])
		seg = np.linalg.norm(np.diff(closed, axis=0), axis=1)
		cum = np.concatenate([[0], np.cumsum(seg)])
		sp = self.membrane_spacing * 0.8
		n = int(cum[-1] / sp)
		tt = np.linspace(0, cum[-1], n, endpoint=False)
		bnd = np.stack([np.interp(tt, cum, closed[:, 0]), np.interp(tt, cum, closed[:, 1])], axis=1)
		area = 0.5 * np.sum(bnd[:, 0] * np.roll(bnd[:, 1], -1) - np.roll(bnd[:, 0], -1) * bnd[:, 1])
		if area < 0:
			bnd = bnd[::-1]
		# interior hex grid
		s = self.membrane_spacing
		xmin, zmin = bnd.min(0)
		xmax, zmax = bnd.max(0)
		gx, gz = [], []
		row = 0
		z = zmin
		while z <= zmax:
			x0 = xmin + (s * 0.5 if row % 2 else 0.0)
			xs = np.arange(x0, xmax, s)
			gx.append(xs)
			gz.append(np.full(len(xs), z))
			z += s * 0.866
			row += 1
		grid = np.stack([np.concatenate(gx), np.concatenate(gz)], axis=1)
		inside = inside_polygon(grid, bnd)
		grid = grid[inside]
		dist = seg_distance(grid, np.vstack([bnd, bnd[:1]]))
		grid = grid[dist > s * 0.55]
		allp = np.vstack([bnd, grid])
		vin = [Vector((float(x), float(z))) for x, z in allp]
		face = list(range(len(bnd)))
		res = delaunay_2d_cdt(vin, [], [face], 1, 1e-5)
		vout = np.array([(v[0], v[1]) for v in res[0]])
		faces = [tuple(f) for f in res[2] if len(f) >= 3]
		# bulge weight: distance to bones
		dmin = np.full(len(vout), np.inf)
		for b in bones:
			dmin = np.minimum(dmin, seg_distance(vout, b))
		bulge = smoothstep(0.0, 7.0, dmin)
		verts = np.stack([vout[:, 0], np.full(len(vout), self.y), vout[:, 1]], axis=1)
		uv = vout / 50.0
		part = Part(verts, faces, None, bulge)
		part.uv = uv
		return part

	def bones(self, sides=10):
		parts = []
		by = self.y - 0.25 if self.bone_y is None else self.bone_y
		arm = spline([(p[0], by, p[2]) for p in self.arm], spacing=0.5)
		ar = np.interp(np.linspace(0, 1, len(arm)), np.linspace(0, 1, len(self.arm_r)), self.arm_r)
		parts.append(tube(arm, ar, sides=sides))
		for f in self.fingers:
			pts = [(p[0], by, p[1]) for p in f["pts"]]
			line = spline(pts, spacing=0.5)
			r = taper(len(line), f.get("r0", 0.7), f.get("r1", 0.25), f.get("power", 1.0))
			parts.append(tube(line, r, sides=sides))
		if self.hem > 0.0:
			if not hasattr(self, "_edge_curves"):
				self.outline()
			for k, curve in enumerate(self._edge_curves):
				# skip the last edge's root end (hidden behind the body)
				c = curve if k < len(self._edge_curves) - 1 else curve[: max(2, int(len(curve) * 0.75))]
				p3 = np.stack([c[:, 0], np.full(len(c), self.y - 0.05), c[:, 1]], axis=1)
				parts.append(tube(p3, self.hem, sides=6))
		return parts


class WingRig:
	"""Builds the meshes of a wing (membrane + bone/extra objects), mirrored left/right, and deforms them."""

	def __init__(self, spec, mats, parent):
		self.spec = spec
		self.parts = {}  # material key -> Part
		mem = spec.membrane()
		self.membrane_uv = mem.uv
		self.groups = [("membrane", mem)]
		bone_parts = spec.bones()
		self.groups.append(("bone", Part.merge(bone_parts)))
		extra = {}
		for part, key in spec.extra:
			extra.setdefault(key, []).append(part)
		for key, plist in extra.items():
			self.groups.append((key, Part.merge(plist)))
		self.mats = mats
		self.parent = parent
		self.objects = []

	def fit_span(self, half_span, frames=16, iters=4):
		"""Scale the rest geometry about the pivot so that the widest pose reaches half_span (|x|)."""
		P = self.spec.pivot
		for _ in range(iters):
			mx = self.max_extent(frames)[0]
			k = half_span / mx
			if abs(k - 1.0) < 1e-4:
				break
			for _key, part in self.groups:
				part.verts = P + (part.verts - P) * k
				part.anchors = P + (part.anchors - P) * k
			self.spec.arm = [P + (p - P) * k for p in self.spec.arm]
		return self.max_extent(frames)

	def max_extent(self, frames=16):
		mx = 0.0
		zmin, zmax = 1e9, -1e9
		for f in range(frames):
			t = f / frames
			for _key, part in self.groups:
				d = self.deform(part, t)
				mx = max(mx, float(np.abs(d[:, 0]).max()))
				zmin = min(zmin, float(d[:, 2].min()))
				zmax = max(zmax, float(d[:, 2].max()))
		return mx, zmin, zmax

	def build(self):
		for key, part in self.groups:
			mat = self.mats[key]
			uv = self.membrane_uv if key == "membrane" else None
			obr = mesh_object("%s_%s_R" % (self.spec.name, key), part, mat, self.parent, uv=uv)
			obl = bpy.data.objects.new("%s_%s_L" % (self.spec.name, key), obr.data)
			bpy.context.scene.collection.objects.link(obl)
			obl.parent = self.parent
			obl.scale = (-1.0, 1.0, 1.0)
			self.objects.append((obr, part))

	def update(self, t):
		for ob, part in self.objects:
			set_mesh_verts(ob, self.deform(part, t))

	# ---------------------------------------------------------------------------------------------
	def angles(self, t):
		sp = self.spec
		w = 2 * math.pi * (t + sp.phase)
		a1 = math.radians(sp.mean1 + sp.amp1 * math.cos(w))
		a2 = math.radians(sp.mean2 + sp.amp2 * math.cos(w - sp.lag))
		sweep = sp.sweep * math.sin(w)
		pitch = sp.pitch_mean + sp.pitch * math.sin(w - 0.4)
		billow = 0.6 + 0.5 * math.sin(w - 0.3)
		return a1, a2, sweep, pitch, billow

	def weights(self, anchors):
		sp = self.spec
		P = sp.pivot
		W = sp.wrist
		# root fan weight: polar angle around the pivot
		phi = np.degrees(np.arctan2(anchors[:, 2] - P[2], anchors[:, 0] - P[0]))
		g = smoothstep(sp.fan[0], sp.fan[1], phi) * (1.0 - smoothstep(100.0, 150.0, phi))
		# outer weight: angular distance from the direction wrist->pivot
		th_in = math.degrees(math.atan2(P[2] - W[2], P[0] - W[0]))
		psi = np.degrees(np.arctan2(anchors[:, 2] - W[2], anchors[:, 0] - W[0]))
		delta = np.abs((psi - th_in + 180.0) % 360.0 - 180.0)
		h = smoothstep(sp.outer[0], sp.outer[1], delta)
		rw = np.hypot(anchors[:, 2] - W[2], anchors[:, 0] - W[0])
		h = h * smoothstep(0.0, 3.0, rw) + (1.0 - smoothstep(0.0, 3.0, rw)) * 0.5 * h
		return g, h

	def deform(self, part, t):
		sp = self.spec
		a1, a2, sweep, pitch, billow = self.angles(t)
		V = part.verts.copy()
		A = part.anchors.copy()
		g, h = self.weights(part.anchors)
		P = sp.pivot.copy()
		W = sp.wrist.copy()
		# membrane billow (camera-facing offset), strongest between the bones
		V[:, 1] += part.bulge * sp.billow * billow
		# cupping: outer wing comes toward the camera (rigid per anchor)
		cupd = -sp.cup * np.clip((part.anchors[:, 0] - P[0]) / sp.cup_len, 0.0, 1.5) ** 2
		V[:, 1] += cupd
		A[:, 1] += cupd
		# pitch about the X axis through the pivot (trailing parts tilt toward/away from camera)
		ang = pitch * g
		V = rot_x(V, P, ang)
		A = rot_x(A, P, ang)
		W = rot_x(W[None, :], P, pitch)[0]
		# outer segment lag bend about the wrist
		ang = a2 * h
		V = rot_y(V, W, ang)
		A = rot_y(A, W, ang)
		# root fan about the pivot
		ang = a1 * g
		V = rot_y(V, P, ang)
		A = rot_y(A, P, ang)
		# sweep about the vertical axis through the pivot
		ang = sweep * g
		V = rot_z(V, P, ang)
		return V
