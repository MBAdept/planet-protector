"""The six demon designs (one per planet). Each design builds the body parts into ctx and returns its wing specs.

Coordinates in game pixels: frame center = (0, 0) = logical enemy center, X right, Z up, camera at -Y.
Frame = 128 x 80 game px (x in [-64, 64], z in [-40, 40]); keep everything inside |z| <= 36.
Right-side parts are built for x > 0 and mirrored with ctx.add_mirrored().
"""
import math

import numpy as np

import enemies_geom as G
from enemies_geom import WingSpec, ellipsoid, horn, plate, spline, tube, v3


def _eyes(ctx, surf, x, z, rx, rz, slant, depth=0.45, inset=0.25, mat="eye"):
	p = surf.front(x, z)
	if p is None:
		raise RuntimeError("no head surface at %.1f %.1f" % (x, z))
	c = p + np.array([0.0, inset, 0.0])
	ctx.add_mirrored(ellipsoid(c, (rx, depth, rz), rot=(0.0, -slant, 0.0), seg=24, rings=12), mat)
	return c


def _wedge_eyes(ctx, surf, x, z, w, h, tilt=0.25, fwd=0.85, curve=0.7, mat="eye"):
	"""Angry wedge-shaped eyes (outer corner pointing up and out), right eye at (x, z), mirrored."""
	shape = np.array([(-1.0, -0.05), (-0.55, 0.3), (0.1, 0.55), (0.75, 0.75), (1.05, 0.95), (0.85, 0.3), (0.45, -0.1),
		(-0.1, -0.38), (-0.7, -0.35)])
	c, sn = math.cos(tilt), math.sin(tilt)
	pts = np.stack([shape[:, 0] * w * c - shape[:, 1] * h * sn, shape[:, 0] * w * sn + shape[:, 1] * h * c], axis=1)
	pts = pts + np.array([x, z])
	p = surf.front(x, z)
	if p is None:
		raise RuntimeError("no head surface at %.1f %.1f" % (x, z))
	# front of the eye ends `fwd` in front of the skin at its centre; the back reaches into the head
	thick, bevel, dome = 0.5, 0.12, 0.25
	yb = p[1] - fwd + thick + bevel * 0.7 + dome
	part = G.slab(pts, yb, thick=thick, dome=dome, bevel=bevel, spacing=0.12, tension=0.35, curve=curve)
	ctx.add_mirrored(part, mat)


def _front(surf, x, z, inset=0.0):
	p = surf.front(x, z)
	if p is None:
		raise RuntimeError("no surface at %.1f %.1f" % (x, z))
	return p + np.array([0.0, inset, 0.0])


def _on_surface(surf, pts2, inset=-0.12):
	"""Projects (x, z) points onto the front surface; returns (N,3) slightly in front (inset < 0)."""
	out = []
	for x, z in pts2:
		p = surf.front(x, z)
		if p is None:
			raise RuntimeError("no surface at %.1f %.1f" % (x, z))
		out.append(p + np.array([0.0, inset, 0.0]))
	return np.array(out)


def _glyph(ctx, surf, pts2, r=0.22, mat="glow_soft", inset=-0.1, mirrored=False, spacing=0.35):
	path = G.spline(np.asarray(pts2, float), spacing=spacing)
	p3 = _on_surface(surf, path, inset)
	part = tube(p3, r, sides=8)
	if mirrored:
		ctx.add_mirrored(part, mat)
	else:
		ctx.add(part, mat)


def _talons(ctx, foot, n=3, length=3.0, r=0.55, spread=1.0, mat="claw", mirrored=True):
	foot = np.asarray(foot, float)
	parts = []
	for k in range(n):
		o = (k - (n - 1) / 2.0) * spread
		pts = [foot + (o * 0.7, -0.4, 0.2), foot + (o * 1.25, -1.5, -length * 0.45),
			foot + (o * 1.45, -1.2, -length * 0.9), foot + (o * 1.3, -0.4, -length)]
		parts.append(horn(pts, r, 0.02, sides=8))
	part = G.Part.merge(parts)
	if mirrored:
		ctx.add_mirrored(part, mat)
	else:
		ctx.add(part, mat)


def _hook(base, direction, length, curl=1.0, r=0.6, up=(0.0, 0.0, 1.0)):
	"""Curved claw hook starting at base, pointing along direction (x, z), curling clockwise by curl."""
	base = np.asarray(v3(base) if len(base) == 2 else base, float)
	d = np.array([direction[0], 0.0, direction[1]], float)
	d /= np.linalg.norm(d)
	n = np.array([d[2], 0.0, -d[0]])  # rotate -90 deg (clockwise in the x-z plane)
	pts = [base, base + d * length * 0.45 + n * length * 0.05 * curl,
		base + d * length * 0.85 + n * length * 0.3 * curl, base + d * length * 0.9 + n * length * 0.7 * curl]
	return horn(pts, r, 0.02, sides=8)


def crown_band(center, r_bot, r_top, h, thick=0.6, n=56):
	"""Open conical crown band (outer + inner wall + rims), axis = Z."""
	cx, cy, cz = center
	ang = np.linspace(0.0, 2 * math.pi, n, endpoint=False)
	rings = [(r_bot, 0.0), (r_bot + thick * 0.25, -0.15), (r_top + thick * 0.4, h * 0.35), (r_top + thick * 0.25, h * 0.8),
		(r_top + 0.3, h), (r_top - thick * 0.5, h), (r_bot - thick * 0.6, 0.0)]
	verts = []
	for r, z in rings:
		for a in ang:
			verts.append((cx + r * math.sin(a), cy - r * math.cos(a), cz + z))
	faces = []
	nr = len(rings)
	for i in range(nr):
		j = (i + 1) % nr
		for k in range(n):
			k2 = (k + 1) % n
			faces.append((i * n + k, i * n + k2, j * n + k2, j * n + k))
	V = np.array(verts)
	return G.Part(V, faces, np.repeat(np.array([[cx, cy, cz]]), len(V), axis=0))


# ==================================================================================================
# NEPTUNE – slender, elegant
# ==================================================================================================
def neptune(ctx):
	b = ctx.meta("body")
	b.ell((0, 0.2, 3.0), 6.0, 4.2, 7.8)            # rib cage
	b.ell((2.5, -2.2, 5.0), 2.8, 1.9, 2.4)          # pecs
	b.ell((-2.5, -2.2, 5.0), 2.8, 1.9, 2.4)
	b.ell((0, -0.3, -4.4), 3.4, 3.0, 5.0)           # abdomen
	b.ell((1.5, -2.4, -2.6), 1.3, 1.0, 1.2)         # abdominal plates
	b.ell((-1.5, -2.4, -2.6), 1.3, 1.0, 1.2)
	b.ell((1.3, -2.2, -5.6), 1.1, 0.9, 1.1)
	b.ell((-1.3, -2.2, -5.6), 1.1, 0.9, 1.1)
	b.ell((0, 0.0, -10.0), 3.1, 2.7, 2.7)           # pelvis
	b.ball((7.0, 0.6, 7.2), 3.1)                     # shoulders
	b.ball((-7.0, 0.6, 7.2), 3.1)
	b.capsule((0, 0.5, 9.5), (0, 0.0, 13.0), 2.2)   # neck
	b.ell((0, -0.3, 16.9), 4.7, 4.4, 5.4)           # skull
	b.ell((0, -1.5, 12.7), 2.6, 2.7, 2.5)           # long chin
	b.ell((2.8, -2.3, 15.1), 1.7, 1.3, 1.2)         # cheekbones
	b.ell((-2.8, -2.3, 15.1), 1.7, 1.3, 1.2)
	b.ell((2.1, -3.5, 18.2), 2.4, 1.0, 0.85, rot=(0, -0.45, 0))   # brows (angry V)
	b.ell((-2.1, -3.5, 18.2), 2.4, 1.0, 0.85, rot=(0, 0.45, 0))
	tail = spline([v3((0, 1.0, -11.0)), v3((1.8, 1.2, -17.5)), v3((5.0, 1.4, -22.5)), v3((4.6, 1.4, -27.5)),
		v3((1.4, 1.2, -30.5))], spacing=0.5)
	b.chain([tuple(p) for p in tail[::4]], np.linspace(1.7, 0.55, len(tail[::4])))
	surf = ctx.surface()
	tip = tail[-1]
	ctx.add(horn([tip + (0.4, 0, 0.6), tip + (-1.3, -0.1, -0.6), tip + (-2.8, -0.2, -2.6)], 1.5, 0.02, sides=10), "horn")
	ctx.add(horn([tip + (0.3, 0, 0.3), tip + (1.9, -0.1, -0.4), tip + (2.1, -0.2, -2.1)], 1.1, 0.02, sides=10), "horn")
	_wedge_eyes(ctx, surf, 2.3, 16.8, 1.8, 1.5, tilt=0.22)
	gp = _front(surf, 0.0, 19.6, 0.15)
	ctx.add(ellipsoid(gp, (0.55, 0.35, 0.95)), "glow")
	mp = _front(surf, 0.0, 13.2, 0.25)
	ctx.add(ellipsoid(mp, (1.7, 0.35, 0.32)), "dark")
	ctx.add_mirrored(horn([mp + (0.95, -0.1, 0.1), mp + (1.0, -0.2, -0.9), mp + (0.8, -0.2, -1.5)], 0.36, 0.02, sides=8), "claw")
	hp = _front(surf, 2.8, 20.6, 1.4)
	ctx.add_mirrored(horn([hp, hp + (1.4, 0.8, 4.4), hp + (4.6, 1.6, 8.6), hp + (9.4, 2.2, 10.6), hp + (12.4, 2.4, 10.4)],
		1.15, 0.02, sides=12, ribs=8, rib_amp=0.2), "horn")
	ep = _front(surf, 4.3, 16.6, 1.6)
	ctx.add_mirrored(horn([ep, ep + (2.4, 0.4, 1.2), ep + (4.6, 0.6, 3.2)], 0.85, 0.02, sides=8), "skin")

	w = WingSpec(
		name="wing", pivot=(7.0, 7.2), y=2.2,
		arm=[(6.4, 7.2), (17.0, 14.4), (28.5, 12.8)], arm_r=[1.5, 1.05, 0.8],
		fingers=[
			{"pts": [(28.5, 12.8), (37.5, 14.4), (46.0, 13.6)], "r0": 0.62, "r1": 0.14},
			{"pts": [(28.5, 12.8), (35.5, 3.0), (41.0, -5.5)], "r0": 0.55, "r1": 0.14},
			{"pts": [(28.5, 12.8), (27.2, 0.0), (22.6, -11.6)], "r0": 0.52, "r1": 0.14},
		],
		edges=[{"depth": 0.42}, {"depth": 0.3}, {"depth": 0.22}],
		attach=[(4.8, -8.5), (4.2, -2.0), (6.4, 7.2)],
		mean1=8.0, amp1=28.0, mean2=-2.0, amp2=20.0, lag=70.0, sweep=14.0, pitch=16.0, billow=1.6, cup=4.0,
	)
	wr = np.array([28.5, 1.8, 12.8])
	w.extra.append((horn([wr + (0, -0.2, 0.5), wr + (0.3, -0.5, 2.2), wr + (-0.7, -0.6, 3.3)], 0.55, 0.02, sides=8), "claw"))
	return [w]


# ==================================================================================================
# URANUS – sickle-shaped wings
# ==================================================================================================
def uranus(ctx):
	b = ctx.meta("body")
	b.ell((0, 0.2, 2.6), 7.0, 4.7, 7.6)             # rib cage
	b.ell((3.0, -2.5, 4.6), 3.4, 2.2, 2.8)          # pecs
	b.ell((-3.0, -2.5, 4.6), 3.4, 2.2, 2.8)
	b.ell((0, -0.4, -4.6), 4.3, 3.4, 5.0)           # abdomen
	for zz, xx in ((-2.3, 1.6), (-5.4, 1.4), (-8.0, 1.2)):
		b.ell((xx, -2.5, zz), 1.4, 1.0, 1.1)
		b.ell((-xx, -2.5, zz), 1.4, 1.0, 1.1)
	b.ell((0, 0.0, -10.0), 3.4, 2.9, 2.8)           # pelvis
	b.ball((7.6, 0.4, 7.4), 3.5)                     # shoulders
	b.ball((-7.6, 0.4, 7.4), 3.5)
	b.capsule((0, 0.4, 8.5), (0, -0.4, 12.0), 2.6)  # hunched neck
	b.ell((0, -0.9, 15.0), 5.0, 4.6, 4.7)           # skull
	b.ell((0, -2.6, 11.6), 3.3, 2.8, 2.5)           # heavy jaw / snout
	b.ell((3.0, -2.8, 13.6), 1.8, 1.3, 1.3)         # cheekbones
	b.ell((-3.0, -2.8, 13.6), 1.8, 1.3, 1.3)
	b.ell((2.3, -4.1, 16.3), 2.6, 1.1, 0.95, rot=(0, -0.5, 0))   # brows
	b.ell((-2.3, -4.1, 16.3), 2.6, 1.1, 0.95, rot=(0, 0.5, 0))
	# legs
	for sx in (1, -1):
		b.capsule((sx * 2.6, 0.4, -9.8), (sx * 4.8, -0.8, -15.6), 1.9)
		b.capsule((sx * 4.8, -0.8, -15.6), (sx * 3.9, 0.2, -22.2), 1.4)
		b.ball((sx * 3.9, -0.3, -22.6), 1.4)
	surf = ctx.surface()
	_talons(ctx, (3.9, -0.6, -22.8), n=3, length=3.4, r=0.58, spread=1.0)
	_wedge_eyes(ctx, surf, 2.45, 15.0, 1.9, 1.55, tilt=0.28)
	mp = _front(surf, 0.0, 11.0, 0.3)
	ctx.add(ellipsoid(mp, (2.2, 0.4, 0.38)), "dark")
	fangs = []
	for xx in (-1.3, -0.45, 0.45, 1.3):
		ln = 1.7 if abs(xx) > 1 else 1.0
		fangs.append(horn([mp + (xx, -0.3, 0.2), mp + (xx * 1.02, -0.45, -ln * 0.6), mp + (xx * 0.95, -0.4, -ln)], 0.36, 0.02, sides=8))
	ctx.add(G.Part.merge(fangs), "claw")
	# crescent (sickle) horns enclosing the head
	hp = _front(surf, 3.8, 17.6, 1.6)
	ctx.add_mirrored(horn([hp, hp + (3.0, 0.8, 1.2), hp + (6.4, 1.4, 4.4), hp + (6.6, 1.6, 9.4), hp + (4.4, 1.2, 12.6),
		hp + (1.6, 0.8, 13.6)], 1.45, 0.02, sides=12, ribs=9, rib_amp=0.16), "horn")
	# crescent glyph on the chest
	ang = np.linspace(math.radians(200), math.radians(340), 14)
	pts = [(1.9 * math.cos(a), 5.4 + 1.9 * math.sin(a) + 1.2) for a in ang]
	_glyph(ctx, surf, pts, r=0.34, mat="glow_soft")
	_glyph(ctx, surf, [(0.0, 3.6), (0.0, 1.6)], r=0.3, mat="glow_soft")

	w = WingSpec(
		name="wing", pivot=(7.6, 7.6), y=2.3,
		arm=[(7.0, 7.6), (15.0, 16.6), (26.0, 20.8)], arm_r=[1.75, 1.3, 1.0],
		fingers=[
			{"pts": [(26.0, 20.8), (35.5, 19.2), (42.5, 13.0), (46.0, 4.0), (44.6, -4.0), (41.0, -9.5)], "r0": 0.85, "r1": 0.15},
			{"pts": [(26.0, 20.8), (31.0, 13.0), (34.0, 6.6)], "r0": 0.55, "r1": 0.3},
		],
		edges=[{"control": (41.0, 1.0)}, {"control": (21.0, 10.5)}],
		attach=[(6.4, -7.2), (5.0, -1.0), (7.0, 7.6)],
		mean1=6.0, amp1=28.0, mean2=-2.0, amp2=20.0, lag=70.0, sweep=14.0, pitch=16.0, billow=1.3, cup=3.5,
	)
	by = w.y - 0.2
	ribs = [
		[(26.0, by, 20.8), (33.0, by, 16.8), (38.6, by, 10.0), (40.4, by, 2.0)],
		[(22.0, by, 19.6), (19.6, by, 13.4), (16.4, by, 7.0)],
		[(16.0, by, 16.6), (12.6, by, 10.0), (10.0, by, 3.0)],
	]
	parts = []
	for r_ in ribs:
		line = spline(r_, spacing=0.5)
		parts.append(tube(line, np.linspace(0.45, 0.16, len(line)), sides=8))
	w.extra.append((G.Part.merge(parts), "bone"))
	wr = np.array([26.0, 1.9, 20.8])
	w.extra.append((horn([wr + (0, -0.2, 0.4), wr + (-0.2, -0.5, 2.6), wr + (-1.6, -0.6, 3.8)], 0.65, 0.02, sides=8), "claw"))
	return [w]


# ==================================================================================================
# SATURN – forked insect-like (split wing tips, mandibles)
# ==================================================================================================
def saturn(ctx):
	ctx.mats["membrane"] = G.mat_surface("membrane_insect", albedo=0.62, rough=0.28, spec=0.9, bump=0.05, bump_scale=4.0,
		bump_detail=1.0, coords="UV")
	b = ctx.meta("thorax")
	b.ell((0, 0.0, 4.0), 6.6, 4.8, 6.0)             # thorax
	b.ell((0, -2.2, 5.6), 4.6, 2.6, 3.6)            # prothorax shield
	b.ball((6.4, 0.5, 7.0), 2.8)                    # wing bases
	b.ball((-6.4, 0.5, 7.0), 2.8)
	b.ball((5.6, 0.8, 1.2), 2.3)
	b.ball((-5.6, 0.8, 1.2), 2.3)
	b.capsule((0, 0.3, 7.8), (0, -0.3, 11.5), 2.2)
	hd = ctx.meta("head")
	hd.ell((0, -0.8, 14.6), 5.6, 4.4, 4.4)          # wide insect head
	hd.ell((0, -2.6, 12.0), 3.0, 2.4, 2.2)          # clypeus
	hd.ell((2.6, -3.2, 16.6), 2.4, 1.0, 0.8, rot=(0, -0.5, 0))   # brow ridges
	hd.ell((-2.6, -3.2, 16.6), 2.4, 1.0, 0.8, rot=(0, 0.5, 0))
	# segmented abdomen (separate families -> visible segment seams)
	segs = [(-3.0, 4.6, 2.9), (-7.4, 4.2, 2.6), (-11.4, 3.6, 2.3), (-15.0, 2.9, 2.0), (-18.2, 2.2, 1.7), (-21.0, 1.5, 1.4)]
	for i, (zz, rx, rz) in enumerate(segs):
		m = ctx.meta("seg%d" % i, "armor")
		m.ell((0, 0.6, zz), rx, rx * 0.8, rz)
	surf = ctx.surface()
	# stinger
	ctx.add(horn([(0, 0.6, -22.0), (0, 0.4, -24.5), (0.6, 0.2, -27.0), (1.6, 0.0, -28.4)], 0.9, 0.02, sides=10), "claw")
	# four eyes: big upper pair + small lower pair
	_eyes(ctx, surf, 2.75, 15.4, 1.9, 1.0, 0.42)
	_eyes(ctx, surf, 1.55, 13.3, 0.9, 0.52, 0.3)
	# mandibles (pincers curving inward)
	mp = _front(surf, 1.8, 11.4, 0.6)
	ctx.add_mirrored(horn([mp, mp + (1.6, -0.6, -1.6), mp + (1.4, -0.9, -4.2), mp + (-0.2, -0.9, -5.8), mp + (-1.4, -0.7, -5.9)],
		0.85, 0.05, sides=10, ribs=3, rib_amp=0.15), "claw")
	# antennae
	ap = _front(surf, 1.6, 17.6, 1.0)
	ctx.add_mirrored(horn([ap, ap + (0.8, 0.6, 3.6), ap + (3.8, 1.0, 8.6), ap + (8.8, 1.2, 11.4), ap + (12.4, 1.2, 11.0)],
		0.5, 0.18, sides=8, ribs=12, rib_amp=0.25), "horn")
	ctx.add_mirrored(ellipsoid(ap + (12.6, 1.2, 10.9), (0.7, 0.6, 0.6)), "glow")
	# thin insect legs (two pairs) hanging below the thorax
	for (x0, z0), (x1, z1), (x2, z2) in (((4.6, 0.0), (8.4, -5.0), (7.2, -12.0)), ((3.4, -2.6), (6.2, -8.8), (4.4, -15.6))):
		leg = spline([v3((x0, -0.5, z0)), v3((x1, -1.2, z1)), v3((x2, -1.0, z2))], spacing=0.4)
		ctx.add_mirrored(tube(leg, np.linspace(0.75, 0.32, len(leg)), sides=8), "armor")
		ctx.add_mirrored(_hook((x2, -1.0, z2), (0.3, -1.0), 2.2, curl=-0.8, r=0.38), "claw")
	# bioluminescent spots on the abdomen
	for zz, xx in ((-7.4, 2.4), (-11.4, 2.0), (-15.0, 1.6)):
		p = _front(surf, xx, zz, 0.2)
		ctx.add_mirrored(ellipsoid(p, (0.45, 0.3, 0.45)), "glow_soft")

	fore = WingSpec(
		name="fore", pivot=(6.6, 7.0), y=2.2,
		arm=[(6.0, 7.0), (17.0, 13.4), (30.0, 15.6)], arm_r=[1.2, 0.8, 0.6],
		fingers=[
			{"pts": [(30.0, 15.6), (39.0, 16.4), (47.0, 16.0)], "r0": 0.5, "r1": 0.13},
			{"pts": [(30.0, 15.6), (38.0, 9.4), (45.0, 4.0)], "r0": 0.45, "r1": 0.13},
		],
		edges=[{"depth": 0.05, "notch": 0.55}, {"depth": -0.12}],
		attach=[(7.0, 1.0), (6.0, 7.0)],
		mean1=2.0, amp1=26.0, mean2=0.0, amp2=14.0, lag=60.0, sweep=12.0, pitch=14.0, billow=0.8, cup=3.0,
		fan=(-140.0, -60.0),
	)
	hind = WingSpec(
		name="hind", pivot=(5.6, 1.0), y=3.0,
		arm=[(5.0, 1.0), (14.0, -1.6), (24.0, -4.4)], arm_r=[1.0, 0.7, 0.5],
		fingers=[
			{"pts": [(24.0, -4.4), (31.0, -5.6), (38.0, -6.6)], "r0": 0.42, "r1": 0.12},
			{"pts": [(24.0, -4.4), (29.0, -10.6), (33.0, -16.0)], "r0": 0.4, "r1": 0.12},
		],
		edges=[{"depth": 0.05, "notch": 0.55}, {"depth": -0.1}],
		attach=[(5.0, -5.6), (5.0, 1.0)],
		mean1=-4.0, amp1=24.0, mean2=-2.0, amp2=14.0, lag=60.0, sweep=10.0, pitch=12.0, billow=0.7, cup=2.0,
		phase=-0.07, fan=(-170.0, -100.0),
	)
	# insect veins (cells)
	for wing, veins in ((fore, [[(7.5, 5.0), (18.0, 9.6), (30.0, 11.0), (40.0, 9.0)], [(7.5, 3.0), (17.0, 5.4), (27.0, 6.4), (38.0, 3.2)],
			[(14.0, 10.6), (17.0, 5.4), (16.0, 2.6)], [(24.0, 14.6), (24.0, 10.4), (27.0, 6.4), (26.0, 3.2)],
			[(33.0, 11.4), (34.0, 7.4)]]),
			(hind, [[(6.5, -1.0), (16.0, -4.6), (27.0, -7.6), (32.0, -11.0)], [(12.0, -2.6), (13.0, -6.0)],
			[(20.0, -3.8), (21.0, -6.2), (22.0, -8.6)]])):
		by = wing.y - 0.15
		parts = []
		for v in veins:
			line = spline([(x, by, z) for x, z in v], spacing=0.4)
			parts.append(tube(line, np.linspace(0.32, 0.18, len(line)), sides=6))
		wing.extra.append((G.Part.merge(parts), "bone"))
	return [fore, hind]


# ==================================================================================================
# JUPITER – broad armour plates on wings and body
# ==================================================================================================
def jupiter(ctx):
	b = ctx.meta("body")
	b.ell((0, 0.3, 2.4), 8.2, 5.2, 8.2)             # broad torso
	b.ell((0, -0.2, -5.2), 5.4, 3.8, 5.0)           # belly
	b.ell((0, 0.2, -10.6), 4.2, 3.2, 3.0)           # pelvis
	b.ball((8.6, 0.6, 7.6), 3.8)                     # shoulders
	b.ball((-8.6, 0.6, 7.6), 3.8)
	b.capsule((0, 0.5, 9.0), (0, -0.2, 12.2), 3.0)  # thick neck
	b.ell((0, -0.9, 15.2), 5.0, 4.6, 4.6)           # skull
	b.ell((0, -2.5, 11.9), 3.8, 3.0, 2.4)           # jaw
	for sx in (1, -1):
		b.capsule((sx * 3.0, 0.4, -10.4), (sx * 5.4, -0.8, -16.0), 2.3)
		b.capsule((sx * 5.4, -0.8, -16.0), (sx * 4.6, 0.2, -21.4), 1.7)
		b.ball((sx * 4.6, -0.3, -22.0), 1.6)
	surf = ctx.surface()
	_talons(ctx, (4.6, -0.6, -22.2), n=3, length=3.0, r=0.6, spread=1.1)
	# armour: breast plates, belly bands, pauldrons, knee plates, helmet
	for sx in (1, -1):
		cp = _front(surf, sx * 3.4, 4.6, 0.6)
		ctx.add(plate(cp, 3.6, 3.6, thick=0.7, dome=0.5, sq=3.2, taper_top=-0.35, rot=(0.0, sx * 0.12, 0.0), curve=0.9,
			bevel=0.16), "armor")
	for i, zz in enumerate((-2.2, -5.0, -7.7)):
		p = _front(surf, 0.0, zz, 0.6)
		ctx.add(plate(p, 4.4 - i * 0.55, 1.15, thick=0.55, dome=0.3, sq=4.0, curve=1.6, bevel=0.3), "armor")
	for k, (dx, dz, ww, hh, rr) in enumerate(((0.0, 2.4, 5.0, 3.0, 0.38), (1.6, -0.8, 4.2, 2.4, 0.55), (2.8, -3.4, 3.2, 2.0, 0.72))):
		sp = np.array([8.6 + dx, -2.6 + k * 0.6, 7.8 + dz])
		ctx.add_mirrored(plate(sp, ww, hh, thick=0.7, dome=0.3, sq=3.4, rot=(0.0, rr, 0.0), curve=1.6, bevel=0.18,
			point=0.25), "armor")
	kp = _front(surf, 5.4, -16.0, 0.5)
	ctx.add_mirrored(plate(kp, 2.3, 2.2, thick=0.6, dome=0.5, sq=2.6, point=0.4), "armor")
	hp = _front(surf, 0.0, 18.0, 0.8)
	ctx.add(plate(hp, 4.8, 1.8, thick=0.7, dome=0.4, sq=3.0, taper_top=0.3, curve=2.6, point=0.5, bevel=0.25), "armor")
	_wedge_eyes(ctx, surf, 2.4, 14.9, 1.9, 1.5, tilt=0.25)
	ctx.add(ellipsoid(_front(surf, 0.0, 15.2, 0.2), (0.6, 0.8, 1.7)), "armor")    # nasal guard
	mp = _front(surf, 0.0, 11.0, 0.3)
	ctx.add(ellipsoid(mp, (2.3, 0.4, 0.4)), "dark")
	ctx.add_mirrored(horn([mp + (1.5, -0.2, 0.1), mp + (1.6, -0.4, -1.0), mp + (1.3, -0.4, -1.9)], 0.48, 0.02, sides=8), "claw")
	# thick horns
	hp2 = _front(surf, 4.0, 17.2, 1.4)
	ctx.add_mirrored(horn([hp2, hp2 + (2.6, -0.4, 1.2), hp2 + (5.2, -1.2, 3.6), hp2 + (6.2, -1.8, 6.8)], 1.9, 0.05,
		sides=12, ribs=6, rib_amp=0.16), "horn")
	# glowing seams between the belly bands + emblem slit between the breast plates
	for zz, ww in ((-0.6, 3.4), (-3.6, 3.0), (-6.4, 2.6)):
		_glyph(ctx, surf, [(-ww, zz), (ww, zz)], r=0.3, mat="glow_soft", inset=-0.25)
	_glyph(ctx, surf, [(0.0, 7.4), (0.0, 1.8)], r=0.32, mat="glow_soft", inset=-0.3)

	# The wing is a stack of four broad armour lames (top one in front) with blunt, chamfered outer ends that all reach
	# far out: a broad, blocky wing with an angular, stepped, almost vertical trailing edge instead of the diagonal
	# scalloped bat wing. The membrane underneath is completely covered (it only backs the lames).
	w = WingSpec(
		name="wing", pivot=(8.6, 8.0), y=2.4,
		arm=[(8.0, 8.0), (18.0, 15.0), (29.0, 14.6)], arm_r=[2.0, 1.5, 1.1],
		fingers=[
			{"pts": [(29.0, 14.6), (38.5, 13.6), (47.6, 11.4)], "r0": 0.85, "r1": 0.28},
			{"pts": [(29.0, 14.6), (38.5, 6.6), (46.4, 0.8)], "r0": 0.75, "r1": 0.26},
			{"pts": [(29.0, 14.6), (36.5, 2.0), (43.6, -7.2)], "r0": 0.7, "r1": 0.26},
			{"pts": [(29.0, 14.6), (32.0, -0.4), (37.6, -13.2)], "r0": 0.65, "r1": 0.26},
		],
		edges=[{"pts": [(43.0, 7.6)]}, {"pts": [(40.6, -1.6)]}, {"pts": [(36.0, -9.4)]}, {"pts": [(24.0, -13.6)]}],
		attach=[(7.4, -11.0), (5.8, -1.0), (8.0, 8.0)], hem=0.0,
		mean1=8.0, amp1=26.0, mean2=-2.0, amp2=18.0, lag=70.0, sweep=12.0, pitch=14.0, billow=0.6, cup=3.5,
	)
	lames = [  # (outline, y, index where the lower edge starts): the upper lame lies in front of the one below
		([(7.4, 12.2), (17.6, 18.4), (29.4, 17.8), (39.0, 15.8), (48.6, 13.2), (49.0, 9.6), (42.0, 5.2), (30.0, 8.4),
			(18.6, 9.0), (8.2, 5.4)], 0.2, 5),
		([(8.0, 8.6), (18.4, 11.8), (30.0, 11.4), (42.4, 8.6), (48.0, 2.6), (47.6, -1.0), (38.4, -3.6), (24.0, -0.6),
			(15.6, 0.0), (7.8, -0.8)], 0.65, 5),
		([(7.8, 1.0), (16.0, 2.6), (24.4, 2.2), (39.0, -0.6), (45.4, -6.2), (44.6, -9.4), (34.0, -10.6), (17.0, -6.8),
			(7.6, -6.6)], 1.1, 5),
		([(7.6, -4.6), (17.0, -5.0), (33.0, -8.0), (39.8, -12.0), (38.6, -15.0), (26.0, -15.6), (16.4, -11.6),
			(7.0, -11.8)], 1.55, 4),
	]
	parts = [G.armor_plate(o, yy, thick=0.6, bevel=0.6, dome=0.1, dome_in=0.4, pillow=1.0, pillow_r=3.2, grid=0.45,
		profile="roof", lift=((0.25, -1.0), 1.0)) for o, yy, _lo in lames]
	# rivets along the visible upper part of every lame (just below the lame above it); they catch the light like studs
	for k, xs in enumerate(((13.0, 23.0, 33.0, 42.0), (14.0, 24.0, 34.0, 43.0), (13.0, 22.0, 31.0, 40.0), (12.0, 21.0, 30.0))):
		o, yy, _lo = lames[k]
		if k == 0:
			edge = np.asarray(o[:5], float)                      # own top edge
			dz = -1.9
		else:
			prev, _y, lo = lames[k - 1]
			edge = np.asarray(prev[lo:], float)                  # lower edge of the lame above
			dz = -1.5
		order = np.argsort(edge[:, 0])
		pv = parts[k].verts
		for x in xs:
			z = float(np.interp(x, edge[order, 0], edge[order, 1])) + dz
			near = np.hypot(pv[:, 0] - x, pv[:, 2] - z) < 0.9
			yf = float(pv[near, 1].min()) if np.any(near) else yy - 1.5
			parts.append(ellipsoid((x, yf - 0.05, z), (0.55, 0.35, 0.55), seg=12, rings=8))
	w.extra.append((G.Part.merge(parts), "armor"))
	wr = np.array([29.0, 0.2, 17.0])
	w.extra.append((horn([wr + (0, 0.0, -0.6), wr + (0.6, -0.4, 1.8), wr + (-0.2, -0.5, 3.6)], 0.95, 0.02, sides=8), "claw"))
	return [w]


# ==================================================================================================
# MARS – hooked wings (claw hooks at the wing edges)
# ==================================================================================================
def mars(ctx):
	b = ctx.meta("body")
	b.ell((0, 0.2, 3.0), 7.2, 4.6, 7.6)             # lean rib cage
	b.ell((3.1, -2.4, 4.8), 3.4, 2.1, 2.8)          # pecs
	b.ell((-3.1, -2.4, 4.8), 3.4, 2.1, 2.8)
	b.ell((0, -0.3, -4.6), 3.8, 3.1, 5.2)           # narrow waist
	for zz, xx in ((-2.2, 1.5), (-5.2, 1.3), (-8.0, 1.1)):
		b.ell((xx, -2.4, zz), 1.3, 0.9, 1.1)
		b.ell((-xx, -2.4, zz), 1.3, 0.9, 1.1)
	b.ell((0, 0.0, -10.4), 3.4, 2.8, 2.8)           # pelvis
	b.ball((7.8, 0.4, 7.6), 3.4)                     # shoulders
	b.ball((-7.8, 0.4, 7.6), 3.4)
	b.capsule((0, 0.4, 9.0), (0, -0.4, 12.4), 2.4)
	b.ell((0, -0.7, 15.6), 4.6, 4.4, 5.0)           # skull
	b.ell((0, -2.4, 11.8), 3.2, 2.8, 2.4)           # jaw
	b.ell((3.0, -2.8, 13.8), 1.6, 1.2, 1.2)         # cheekbones (gaunt)
	b.ell((-3.0, -2.8, 13.8), 1.6, 1.2, 1.2)
	b.ell((2.3, -4.0, 17.0), 2.7, 1.1, 0.9, rot=(0, -0.55, 0))   # heavy brows
	b.ell((-2.3, -4.0, 17.0), 2.7, 1.1, 0.9, rot=(0, 0.55, 0))
	# long arms with hooked claws
	for sx in (1, -1):
		b.capsule((sx * 8.4, -0.4, 5.6), (sx * 10.6, -1.6, -1.6), 1.5)
		b.capsule((sx * 10.6, -1.6, -1.6), (sx * 10.0, -2.8, -8.2), 1.2)
		b.ball((sx * 10.0, -2.8, -8.8), 1.4)
		b.capsule((sx * 2.8, 0.4, -10.2), (sx * 4.6, -0.8, -15.8), 1.8)
		b.capsule((sx * 4.6, -0.8, -15.8), (sx * 3.8, 0.2, -21.2), 1.3)
		b.ball((sx * 3.8, -0.3, -21.6), 1.3)
	surf = ctx.surface()
	_talons(ctx, (10.0, -3.2, -9.2), n=3, length=3.6, r=0.5, spread=1.0)
	_talons(ctx, (3.8, -0.6, -21.8), n=3, length=3.0, r=0.5, spread=1.0)
	# barbed tail
	tail = spline([v3((0, 1.4, -11.0)), v3((-2.4, 1.6, -16.0)), v3((-6.0, 1.8, -19.6)), v3((-9.4, 1.8, -23.0)), v3((-9.0, 1.6, -27.6))],
		spacing=0.5)
	ctx.add(tube(tail, np.linspace(1.5, 0.45, len(tail)), sides=10), "skin")
	tp = tail[-1]
	ctx.add(horn([tp + (0, 0, 0.6), tp + (0.3, -0.1, -1.6), tp + (1.8, -0.2, -3.2)], 1.1, 0.02, sides=8), "claw")
	ctx.add(horn([tp + (0, 0, 0.5), tp + (-1.6, -0.1, -0.4), tp + (-2.6, -0.2, -2.2)], 0.9, 0.02, sides=8), "claw")
	_wedge_eyes(ctx, surf, 2.45, 15.5, 2.0, 1.55, tilt=0.32)
	mp = _front(surf, 0.0, 11.2, 0.3)
	ctx.add(ellipsoid(mp, (2.4, 0.4, 0.55)), "dark")
	teeth = []
	for xx in (-1.7, -0.9, 0.0, 0.9, 1.7):
		ln = 1.9 if abs(xx) > 1.5 else 1.1
		teeth.append(horn([mp + (xx, -0.3, 0.4), mp + (xx, -0.45, -ln * 0.5), mp + (xx * 0.96, -0.4, -ln)], 0.34, 0.02, sides=8))
	for xx in (-1.3, 1.3):
		teeth.append(horn([mp + (xx, -0.3, -0.5), mp + (xx, -0.45, 0.5), mp + (xx * 0.95, -0.4, 1.1)], 0.3, 0.02, sides=8))
	ctx.add(G.Part.merge(teeth), "claw")
	# hooked horns: out, then down like a claw
	hp = _front(surf, 3.6, 18.4, 1.4)
	ctx.add_mirrored(horn([hp, hp + (2.0, 0.5, 2.6), hp + (5.4, 0.8, 4.8), hp + (9.0, 0.6, 5.0), hp + (11.0, 0.0, 3.0),
		hp + (10.6, -0.6, 0.6)], 1.8, 0.02, sides=12, ribs=8, rib_amp=0.15), "horn")
	# shoulder spikes
	ctx.add_mirrored(horn([(8.4, -0.6, 10.4), (9.6, -0.6, 13.4), (11.2, -0.4, 14.6)], 0.9, 0.02, sides=8), "horn")
	# glowing claw-mark scars on the chest
	for dx in (-1.4, 0.0, 1.4):
		_glyph(ctx, surf, [(dx - 1.6, 7.6), (dx - 0.4, 4.6), (dx + 0.7, 1.4)], r=0.3, mat="glow_soft")

	w = WingSpec(
		name="wing", pivot=(7.8, 7.8), y=2.3,
		arm=[(7.2, 7.8), (17.0, 15.2), (28.0, 14.6)], arm_r=[1.7, 1.2, 0.9],
		fingers=[
			{"pts": [(28.0, 14.6), (37.0, 14.8), (45.0, 11.0)], "r0": 0.7, "r1": 0.3},
			{"pts": [(28.0, 14.6), (36.0, 5.0), (41.5, -3.8)], "r0": 0.6, "r1": 0.28},
			{"pts": [(28.0, 14.6), (31.0, 1.0), (31.6, -10.0)], "r0": 0.58, "r1": 0.28},
			{"pts": [(28.0, 14.6), (24.0, 0.0), (19.6, -10.6)], "r0": 0.54, "r1": 0.28},
		],
		edges=[{"depth": 0.38}, {"depth": 0.36}, {"depth": 0.34}, {"depth": 0.22}],
		attach=[(6.0, -9.0), (5.0, -2.0), (7.2, 7.8)],
		mean1=8.0, amp1=28.0, mean2=-2.0, amp2=20.0, lag=70.0, sweep=14.0, pitch=16.0, billow=1.5, cup=4.0,
	)
	# the signature: big sickle claws curling from every finger tip and a scythe hook on the wrist
	cy = w.y - 0.3
	hooks = [
		G.sickle((43.8, cy, 11.2), (0.8, 0.6), 9.4, bend=140.0, r0=1.75),
		G.sickle((40.8, cy, -2.8), (0.95, -0.15), 8.6, bend=135.0, r0=1.6),
		G.sickle((31.4, cy, -9.0), (0.5, -0.87), 8.0, bend=130.0, r0=1.55),
		G.sickle((19.9, cy, -9.6), (0.08, -1.0), 7.2, bend=125.0, r0=1.45),
		G.sickle((27.4, cy - 0.4, 13.8), (0.25, 1.0), 9.6, bend=150.0, r0=1.9),      # scythe on the wrist
	]
	w.extra.append((G.Part.merge(hooks), "claw"))
	# glowing veins: one main vein per membrane panel
	vy = w.y - 0.12
	veins = [
		[(29.5, 12.2), (34.5, 9.4), (38.6, 7.6)],
		[(29.0, 10.0), (32.6, 3.6), (34.0, -1.2)],
		[(27.0, 9.0), (27.0, 2.0), (25.4, -4.4)],
		[(23.6, 10.6), (18.6, 4.4), (13.4, -0.6)],
	]
	parts = []
	for v in veins:
		line = spline([(x, vy, z) for x, z in v], spacing=0.35)
		parts.append(tube(line, np.linspace(0.36, 0.2, len(line)), sides=8))
	w.extra.append((G.Part.merge(parts), "vein"))
	return [w]


# ==================================================================================================
# EARTH – heavy crown, massive, the most threatening
# ==================================================================================================
def earth(ctx):
	ctx.mats["membrane"] = G.mat_surface("membrane_earth", albedo=0.8, rough=0.38, spec=0.8, bump=0.08, bump_scale=6.0,
		bump_detail=1.0, coords="UV")
	b = ctx.meta("body")
	b.ell((0, 0.3, 2.6), 8.8, 5.8, 8.8)             # massive torso
	b.ell((3.6, -2.9, 5.0), 4.2, 2.6, 3.4)          # pecs
	b.ell((-3.6, -2.9, 5.0), 4.2, 2.6, 3.4)
	b.ell((0, -0.2, -5.0), 5.4, 4.0, 5.6)           # belly
	for zz, xx in ((-2.6, 1.8), (-5.8, 1.6), (-8.8, 1.4)):
		b.ell((xx, -3.0, zz), 1.6, 1.1, 1.3)
		b.ell((-xx, -3.0, zz), 1.6, 1.1, 1.3)
	b.ell((0, 0.2, -11.0), 4.4, 3.4, 3.0)           # pelvis
	b.ball((9.6, 0.4, 8.2), 4.5)                     # huge shoulders
	b.ball((-9.6, 0.4, 8.2), 4.5)
	b.ell((0, 0.6, 10.6), 5.4, 3.6, 3.0)            # trapezius / thick neck
	b.ell((0, -1.2, 15.0), 5.6, 5.0, 5.0)           # big skull
	b.ell((0, -3.0, 11.4), 4.4, 3.2, 2.8)           # heavy jaw
	b.ell((3.6, -3.2, 13.4), 2.0, 1.4, 1.5)         # cheekbones
	b.ell((-3.6, -3.2, 13.4), 2.0, 1.4, 1.5)
	b.ell((2.6, -4.6, 16.4), 3.0, 1.3, 1.1, rot=(0, -0.5, 0))   # brutal brows
	b.ell((-2.6, -4.6, 16.4), 3.0, 1.3, 1.1, rot=(0, 0.5, 0))
	for sx in (1, -1):
		b.capsule((sx * 10.4, -0.6, 5.6), (sx * 12.8, -1.8, -2.2), 2.2)   # thick arms
		b.capsule((sx * 12.8, -1.8, -2.2), (sx * 12.0, -3.4, -8.8), 1.8)
		b.ball((sx * 12.0, -3.4, -9.6), 2.0)
		b.capsule((sx * 3.4, 0.4, -11.0), (sx * 6.0, -0.8, -17.0), 2.6)   # thick legs
		b.capsule((sx * 6.0, -0.8, -17.0), (sx * 5.2, 0.2, -22.6), 2.0)
		b.ball((sx * 5.2, -0.3, -23.2), 1.9)
	surf = ctx.surface()
	_talons(ctx, (12.0, -4.0, -10.4), n=3, length=4.0, r=0.7, spread=1.3)
	_talons(ctx, (5.2, -0.8, -23.6), n=3, length=3.4, r=0.65, spread=1.2)
	# shoulder spikes
	spikes = []
	for (dx, dz, ex, ez, r) in ((-1.6, 2.6, 0.8, 6.4, 1.1), (1.2, 2.0, 3.6, 5.0, 1.0), (3.0, 0.0, 6.2, 2.0, 0.85)):
		base = np.array([9.6 + dx, -1.4, 8.2 + dz])
		spikes.append(horn([base, base + (ex * 0.5, -0.3, ez * 0.5), base + (ex, -0.2, ez)], r, 0.02, sides=8))
	ctx.add_mirrored(G.Part.merge(spikes), "horn")
	_wedge_eyes(ctx, surf, 2.8, 14.9, 2.3, 1.75, tilt=0.3)
	# open maw: dark mouth with glowing throat, fangs top and bottom
	mp = _front(surf, 0.0, 11.0, 0.5)
	ctx.add(ellipsoid(mp, (2.8, 0.5, 1.1)), "dark")
	ctx.add(ellipsoid(mp + (0.0, 0.25, -0.1), (1.7, 0.3, 0.55)), "glow_soft")
	teeth = []
	for xx in (-2.2, -1.2, 1.2, 2.2):
		ln = 2.1 if abs(xx) > 2 else 1.3
		teeth.append(horn([mp + (xx, -0.4, 1.0), mp + (xx, -0.6, 1.0 - ln * 0.5), mp + (xx * 0.95, -0.55, 1.0 - ln)], 0.42, 0.02, sides=8))
	for xx in (-1.8, 1.8):
		teeth.append(horn([mp + (xx, -0.4, -1.0), mp + (xx, -0.6, 0.0), mp + (xx * 0.93, -0.55, 0.7)], 0.4, 0.02, sides=8))
	ctx.add(G.Part.merge(teeth), "claw")
	# massive horns sweeping out and up from under the crown
	hp = _front(surf, 4.8, 17.6, 1.8)
	ctx.add_mirrored(horn([hp, hp + (3.0, 0.6, 0.2), hp + (6.6, 1.0, 1.2), hp + (9.6, 0.8, 4.2), hp + (10.8, 0.4, 8.4),
		hp + (10.0, 0.0, 11.2)], 2.1, 0.03, sides=12, ribs=10, rib_amp=0.14), "horn")
	# heavy crown: band, five big spikes, glowing jewels
	cc = np.array([0.0, -1.0, 18.4])
	ctx.add(crown_band(cc, 5.3, 6.4, 3.6, thick=0.9), "gold")
	spikes = []
	for k, a in enumerate(np.radians([-62, -31, 0, 31, 62])):
		hgt = (7.0, 9.0, 11.6, 9.0, 7.0)[k]
		r = 6.4
		base = cc + (r * math.sin(a), -r * math.cos(a), 3.2)
		out = np.array([math.sin(a), -math.cos(a), 0.0])
		spikes.append(horn([base, base + out * 0.5 + (0, 0, hgt * 0.5), base + out * 0.9 + (0, 0, hgt)], 1.45, 0.02, sides=10))
		spikes.append(ellipsoid(base + out * 0.9 + (0, 0, hgt + 0.2), (0.55, 0.55, 0.55)))
	ctx.add(G.Part.merge(spikes), "gold")
	jewels = []
	for a in np.radians([-46, 0, 46]):
		p = cc + (6.9 * math.sin(a), -6.9 * math.cos(a), 1.7)
		big = abs(a) < 0.01
		jewels.append(ellipsoid(p, (0.85 if big else 0.6, 0.5, 1.05 if big else 0.7)))
	ctx.add(G.Part.merge(jewels), "glow")
	# glowing sigil on the chest (ring + crossed strokes)
	ang = np.linspace(0, 2 * math.pi, 40)
	_glyph(ctx, surf, [(2.3 * math.cos(a), 3.4 + 2.3 * math.sin(a)) for a in ang], r=0.32, mat="glow_soft")
	_glyph(ctx, surf, [(0.0, 6.6), (0.0, 0.2)], r=0.32, mat="glow_soft")
	_glyph(ctx, surf, [(-2.4, 4.8), (0.0, 2.4), (2.4, 4.8)], r=0.3, mat="glow_soft")

	w = WingSpec(
		name="wing", pivot=(9.4, 9.0), y=2.6,
		arm=[(8.8, 9.0), (19.0, 16.8), (30.0, 15.8)], arm_r=[2.3, 1.6, 1.2],
		fingers=[
			{"pts": [(30.0, 15.8), (40.0, 16.2), (49.0, 12.6)], "r0": 0.85, "r1": 0.32},
			{"pts": [(30.0, 15.8), (39.6, 7.2), (46.0, -1.0)], "r0": 0.75, "r1": 0.3},
			{"pts": [(30.0, 15.8), (35.0, 2.0), (37.0, -9.4)], "r0": 0.7, "r1": 0.3},
			{"pts": [(30.0, 15.8), (29.0, 1.0), (27.0, -12.6)], "r0": 0.66, "r1": 0.3},
			{"pts": [(30.0, 15.8), (23.0, 0.0), (17.0, -11.4)], "r0": 0.62, "r1": 0.3},
		],
		edges=[{"depth": 0.34, "jag": 0.9, "teeth": 3}, {"depth": 0.32, "jag": 0.9, "teeth": 3},
			{"depth": 0.32, "jag": 0.9, "teeth": 3}, {"depth": 0.3, "jag": 0.8, "teeth": 3}, {"depth": 0.2, "jag": 0.6, "teeth": 3}],
		attach=[(7.6, -10.0), (6.4, -2.0), (8.8, 9.0)],
		mean1=8.0, amp1=26.0, mean2=-2.0, amp2=18.0, lag=70.0, sweep=12.0, pitch=14.0, billow=1.6, cup=4.0,
	)
	# thorned dragon wing: every finger bone runs out past the ragged membrane as a long straight spine
	cy = w.y - 0.3
	parts = []
	for f, ln, r in zip(w.fingers, (4.0, 5.8, 6.4, 6.0, 5.2), (1.0, 0.95, 0.92, 0.88, 0.84)):
		tip = np.array(f["pts"][-1], float)
		d = tip - np.array(f["pts"][-2], float)
		a = math.atan2(d[1], d[0]) - math.radians(16.0)                 # droop a little (keeps the span for the wing)
		d = np.array([math.cos(a), math.sin(a)])
		o = tip - d * 1.2
		parts.append(horn([(o[0], cy, o[1]), (tip[0] + d[0] * ln * 0.5, cy - 0.1, tip[1] + d[1] * ln * 0.5),
			(tip[0] + d[0] * ln, cy - 0.15, tip[1] + d[1] * ln)], r, 0.02, sides=8))
	wb = np.array([30.0, cy - 0.4, 15.0])                                  # straight horn spike on the wrist
	parts.append(horn([wb, wb + (1.0, -0.2, 3.2), wb + (2.4, -0.3, 6.4)], 1.35, 0.02, sides=10, ribs=4, rib_amp=0.12))
	# spikes along the leading edge
	for x, z, ln in ((13.0, 13.6, 2.6), (17.6, 17.0, 3.0), (22.6, 17.8, 2.8), (35.0, 16.8, 2.4), (40.0, 16.8, 2.2)):
		base = np.array([x, cy - 0.2, z - 0.6])
		parts.append(horn([base, base + (0.6, -0.1, ln * 0.6), base + (1.4, -0.1, ln)], 0.75, 0.02, sides=8))
	w.extra.append((G.Part.merge(parts), "claw"))
	vy = w.y - 0.12
	veins = [[(31.0, 13.0), (37.0, 9.0), (42.0, 7.0)], [(37.0, 9.0), (40.0, 11.6)], [(30.0, 11.0), (33.0, 2.0), (34.6, -4.0)],
		[(33.0, 2.0), (37.6, 0.6)], [(28.0, 10.0), (26.0, 0.0), (22.0, -7.0)], [(26.0, 0.0), (29.4, -5.0)],
		[(22.0, 12.0), (16.0, 4.0), (12.0, -3.0)], [(16.0, 4.0), (19.6, -2.6)], [(14.0, 11.0), (10.0, 6.0)]]
	vparts = []
	for v in veins:
		line = spline([(x, vy, z) for x, z in v], spacing=0.35)
		vparts.append(tube(line, np.linspace(0.34, 0.18, len(line)), sides=8))
	w.extra.append((G.Part.merge(vparts), "vein"))
	return [w]


DESIGNS = {
	"neptune": neptune,
	"uranus": uranus,
	"saturn": saturn,
	"jupiter": jupiter,
	"mars": mars,
	"earth": earth,
}
