"""Procedural player-ship and rocket models (Blender bpy). See ships.py for the render driver.

Units: 1 Blender unit = 10 sprite px = 5 game px. Nose points to +Y. Canvas = 16 x 11.2 units.
Gun muzzles: single ships at x = 0, double ships at x = +-2.4 (= +-24 sprite px = +-12 game px).
Every builder returns (objects, plumes); plumes = list of (x, y_exit, z, radius) for the glow pass.
"""
from __future__ import annotations

import ships_lib as L

# Linear-space accent colours (ShipData accents, a little more saturated for rendering).
ACCENTS = {
	"interceptor": (0.03, 0.22, 1.0),
	"fighter": (0.06, 0.72, 0.1),
	"double_dart": (0.0, 0.62, 0.95),
	"double_hunter": (1.0, 0.3, 0.015),
	"blaster": (0.95, 0.03, 0.02),
	"hunter": (0.42, 0.06, 1.0),
}
# Exhaust colours (linear) – hot, accent tinted.
EXHAUST = {
	"interceptor": (0.1, 0.35, 1.0),
	"fighter": (0.15, 1.0, 0.25),
	"double_dart": (0.05, 0.75, 1.0),
	"double_hunter": (1.0, 0.4, 0.05),
	"blaster": (1.0, 0.18, 0.06),
	"hunter": (0.6, 0.2, 1.0),
}


def _lighten(c, k):
	return tuple(min(1.0, v + (1.0 - v) * k) for v in c)


def _scale(c, k):
	return tuple(v * k for v in c)


# Hull greys (linear): light top plating, mid structure, dark gunmetal.
HULL_L = (0.6, 0.62, 0.66)
HULL_M = (0.34, 0.35, 0.38)
HULL_D = (0.1, 0.105, 0.12)
_TINT = [HULL_L]  # light hull of the ship being built, slightly tinted towards its accent (set by Kit)


class Kit:
	"""Material palette for one ship."""

	def __init__(self, key: str):
		acc = ACCENTS[key]
		exh = EXHAUST[key]
		self.accent = acc
		self.exhaust = exh
		_TINT[0] = tuple(h * (0.92 + 0.16 * a) for h, a in zip(HULL_L, acc))
		self.hull = L.mat_hull(key + "_hull", (0.6, 0.62, 0.66), metallic=0.7, rough=0.3)
		self.hull_dark = L.mat_hull(key + "_hull_d", (0.16, 0.17, 0.2), metallic=0.85, rough=0.35, panel=0.5)
		self.metal = L.mat_basic(key + "_metal", (0.8, 0.81, 0.84), metallic=1.0, rough=0.2, aniso=0.6)
		self.gun = L.mat_basic(key + "_gun", (0.22, 0.23, 0.26), metallic=1.0, rough=0.28)
		self.black = L.mat_basic(key + "_black", (0.015, 0.016, 0.02), rough=0.55)
		self.paint = L.mat_basic(key + "_paint", acc, metallic=0.4, rough=0.25, coat=1.0)
		self.light = L.mat_emit(key + "_light", acc, 2.8)
		self.light_soft = L.mat_emit(key + "_light_s", acc, 1.4)
		self.glass = L.mat_glass(key + "_glass", (0.1, 0.35, 0.8), 0.05)
		self.hot = L.mat_emit(key + "_hot", _lighten(exh, 0.3), 4.0)
		self.nozzle_mats = [self.gun, self.black, self.hot]


# ------------------------------------------------------------------------------------------------
# Ships
# ------------------------------------------------------------------------------------------------
def _u(y, y0, y1):
	return (y0 - y) / (y0 - y1)


def build_interceptor(k: Kit):
	"""Sleek needle: long pointed fuselage, single central laser, strongly swept wings, blue."""
	o = []
	acc = k.accent
	y0, y1 = 3.95, -3.7
	fus = L.mat_part("int_fus", HULL_L, metallic=0.8, rough=0.24,
		u_lines=[_u(-1.0, y0, y1), _u(-2.6, y0, y1)], v_lines=[0.14, 0.36], line_w=0.008,
		zones=[(0.0, _u(3.3, y0, y1), 0, 1, _scale(acc, 0.5), 0.5, 0.3)])
	o.append(L.loft("fuselage", [
		(3.95, 0.06, 0.48, 0.56, 2.0),
		(3.6, 0.3, 0.3, 0.78, 2.2),
		(2.8, 0.56, 0.16, 1.0, 2.4),
		(1.6, 0.78, 0.1, 1.14, 2.6),
		(0.0, 0.9, 0.1, 1.2, 2.8),
		(-2.0, 0.95, 0.1, 1.16, 3.0),
		(-3.3, 0.88, 0.12, 1.06, 3.0),
		(-3.7, 0.72, 0.16, 0.96, 3.0),
	], [fus], cap_front=0, cap_back=0))
	# laser: shroud + barrel + emissive muzzle
	o.append(L.tube_y("shroud", 0, 0.58, 4.1, 3.3, 0.21, 0.26, [k.gun], caps=0))
	o.append(L.tube_y("barrel", 0, 0.58, 4.82, 4.0, 0.12, mats=[k.metal], caps=0))
	o.append(L.tube_y("muzzle", 0, 0.58, 4.95, 4.78, 0.16, mats=[k.light], caps=0))
	# canopy
	o.append(L.loft("canopy", [
		(2.55, 0.05, 0.95, 1.0, 2.0),
		(2.15, 0.36, 0.9, 1.36, 2.0),
		(1.2, 0.52, 0.92, 1.56, 2.0),
		(0.1, 0.48, 0.96, 1.52, 2.0),
		(-0.55, 0.28, 1.0, 1.4, 2.0),
		(-0.85, 0.04, 1.1, 1.22, 2.0),
	], [k.glass], cap_front=0, cap_back=0))
	# swept wings (airfoil), blue leading edge band, darker flaps
	wm = L.mat_part("int_wing", HULL_L, metallic=0.8, rough=0.26,
		u_lines=[0.36, 0.68], v_lines=[0.7], line_w=0.012,
		zones=[(0.36, 0.92, 0.7, 1.0, HULL_D, 0.9, 0.35),
			(0.2, 1.0, 0.0, 0.24, acc, 0.45, 0.2),
			(0.2, 1.0, 0.24, 0.28, HULL_D, 0.9, 0.35)],
		grad=("u", 1.0, 0.8))
	o.append(L.wing("wings", (0.7, 1.35), (0.7, -2.55), (6.7, -2.6), (6.75, -3.35), 0.28, 0.5, 0.12, [wm],
		mirror=True, z_tip=0.35))
	# wing-tip pods with lights
	o.append(L.loft("tip_pod", [
		(-1.55, 0.03, 0.4, 0.48, 2.0),
		(-1.85, 0.17, 0.27, 0.62, 2.0),
		(-2.2, 0.2, 0.24, 0.66, 2.0),
		(-3.55, 0.2, 0.24, 0.66, 2.0),
		(-3.75, 0.14, 0.3, 0.6, 2.0),
	], [k.gun], x=6.68, mirror=True, cap_back=0))
	o.append(L.ellipsoid("tip_light_r", (6.68, -1.95, 0.6), (0.13, 0.22, 0.1), k.light))
	o.append(L.ellipsoid("tip_light_l", (-6.68, -1.95, 0.6), (0.13, 0.22, 0.1), k.light))
	# canards
	cm = L.mat_part("int_can", HULL_L, metallic=0.8, rough=0.26, zones=[(0.55, 1.0, 0, 1, acc, 0.4, 0.22)])
	o.append(L.wing("canards", (0.5, 2.75), (0.5, 1.85), (2.05, 1.75), (2.1, 1.42), 0.42, 0.26, 0.06, [cm],
		mirror=True))
	# side intakes + spine
	o.append(L.slab("intakes", [(0.82, 0.2), (1.15, -0.1), (1.15, -1.6), (0.88, -1.8)], 0.3, 0.95, k.hull_dark,
		bevel=0.08, segs=2, mirror=True))
	o.append(L.slab("spine", [(0.0, -0.9), (0.32, -1.2), (0.32, -3.1), (0.0, -3.35), (-0.32, -3.1), (-0.32, -1.2)],
		1.0, 1.24, k.hull_dark, bevel=0.06, segs=2))
	o.append(L.slab("spine_light", [(0.0, -1.35), (0.09, -1.5), (0.09, -2.7), (0.0, -2.85), (-0.09, -2.7), (-0.09, -1.5)],
		1.18, 1.27, k.light_soft, bevel=0.0))
	o.append(L.slab("fus_stripe", [(0.62, 2.0), (0.82, 1.1), (0.86, 0.5), (0.72, 0.5), (0.5, 1.9)], 0.9, 1.16,
		k.paint, bevel=0.03, segs=1, mirror=True))
	# engine
	o.append(L.nozzle("nozzle", 0, 0.6, -3.45, 0.95, 0.55, k.nozzle_mats))
	return o, [(0.0, -4.4, 0.6, 0.42)]


def _hm(name, **kw):
	"""UV panel material; default base = light hull, tinted very slightly towards the ship accent."""
	kw.setdefault("metallic", 0.65)
	kw.setdefault("rough", 0.27)
	return L.mat_part(name, kw.pop("base", _TINT[0]), **kw)


def build_fighter(k: Kit):
	"""Delta wing, single central rocket rail on the nose, twin engines, green."""
	o = []
	acc = k.accent
	y0, y1 = 3.9, -3.55
	fus = _hm("fig_fus", u_lines=[_u(1.45, y0, y1), _u(-1.2, y0, y1)], v_lines=[0.12, 0.38], line_w=0.008)
	o.append(L.loft("fuselage", [
		(3.9, 0.1, 0.38, 0.5, 2.0),
		(3.4, 0.5, 0.2, 0.86, 2.4),
		(2.4, 0.95, 0.12, 1.1, 2.6),
		(0.8, 1.22, 0.1, 1.25, 2.8),
		(-1.5, 1.3, 0.1, 1.22, 3.0),
		(-3.2, 1.25, 0.12, 1.1, 3.2),
		(-3.55, 1.12, 0.16, 1.0, 3.2),
	], [fus]))
	# rocket rail on the nose: housing, dark channel, guide lights
	o.append(L.slab("rail", [(0.42, 4.55), (0.46, 1.2), (-0.46, 1.2), (-0.42, 4.55)], 0.55, 1.32, k.hull_dark,
		bevel=0.1, segs=2))
	o.append(L.slab("rail_ch", [(0.16, 4.62), (0.16, 1.45), (-0.16, 1.45), (-0.16, 4.62)], 1.0, 1.36, k.black,
		bevel=0.03, segs=1))
	for i, yy in enumerate((4.1, 3.2, 2.3)):
		o.append(L.ellipsoid("rail_led%d" % i, (0.31, yy, 1.33), (0.05, 0.22, 0.04), k.light))
		o.append(L.ellipsoid("rail_led%db" % i, (-0.31, yy, 1.33), (0.05, 0.22, 0.04), k.light))
	o.append(L.slab("rail_tip", [(0.44, 4.72), (0.44, 4.5), (-0.44, 4.5), (-0.44, 4.72)], 0.6, 1.3, k.paint,
		bevel=0.05, segs=1))
	# canopy
	o.append(L.loft("canopy", [
		(1.15, 0.05, 1.1, 1.15, 2.0),
		(0.8, 0.42, 1.0, 1.5, 2.0),
		(0.0, 0.58, 1.0, 1.66, 2.0),
		(-0.9, 0.5, 1.05, 1.58, 2.0),
		(-1.45, 0.05, 1.15, 1.25, 2.0),
	], [k.glass]))
	# delta wing
	wm = _hm("fig_wing", u_lines=[0.3, 0.6], v_lines=[0.76], line_w=0.012,
		zones=[(0.18, 0.6, 0.76, 1.0, HULL_D, 0.9, 0.35),
			(0.66, 1.0, 0.0, 1.0, acc, 0.45, 0.2),
			(0.6, 0.66, 0.0, 1.0, HULL_D, 0.9, 0.35)],
		emit_zones=[(0.62, 0.64, 0.05, 0.95, acc, 2.2), (0.14, 0.6, 0.1, 0.125, acc, 2.0)],
		grad=("u", 1.0, 0.85))
	o.append(L.wing("delta", (1.0, 2.7), (1.0, -3.35), (6.6, -2.55), (6.7, -3.4), 0.24, 0.62, 0.1, [wm],
		mirror=True, z_tip=0.25))
	o.append(L.ellipsoid("tip_r", (6.62, -2.95, 0.42), (0.1, 0.3, 0.1), k.light))
	o.append(L.ellipsoid("tip_l", (-6.62, -2.95, 0.42), (0.1, 0.3, 0.1), k.light))
	# intakes and twin tail fins
	o.append(L.slab("intakes", [(1.05, 1.5), (1.45, 1.1), (1.45, -0.6), (1.1, -0.9)], 0.4, 1.02, k.hull_dark,
		bevel=0.08, segs=2, mirror=True))
	o.append(L.slab("intake_mouth", [(1.12, 1.42), (1.4, 1.12), (1.4, 0.95), (1.12, 1.2)], 0.9, 1.06, k.black,
		bevel=0.02, segs=1, mirror=True))
	fin = _hm("fig_fin", base=HULL_M, zones=[(0.0, 1.0, 0.0, 0.3, acc, 0.45, 0.2)])
	o.append(L.wing("fins", (1.55, -1.3), (1.55, -3.3), (2.25, -2.45), (2.3, -3.35), 0.9, 0.35, 0.08, [fin],
		mirror=True, z_tip=0.5))
	# engines
	o.append(L.nozzle("nozzle", 0.68, 0.62, -3.3, 0.85, 0.5, k.nozzle_mats, mirror=True))
	return o, [(0.68, -4.15, 0.62, 0.4), (-0.68, -4.15, 0.62, 0.4)]


def build_double_dart(k: Kit):
	"""Twin forward prongs with laser muzzles at +-2.4, forward-swept wings, cyan."""
	o = []
	acc = k.accent
	y0, y1 = 2.6, -3.5
	fus = _hm("dd_fus", u_lines=[_u(-0.6, y0, y1), _u(-2.2, y0, y1)], v_lines=[0.15, 0.35], line_w=0.009)
	o.append(L.loft("fuselage", [
		(2.6, 0.1, 0.45, 0.6, 2.0),
		(2.2, 0.55, 0.25, 1.0, 2.4),
		(1.2, 0.9, 0.12, 1.2, 2.6),
		(-1.0, 1.0, 0.1, 1.24, 2.8),
		(-3.1, 0.95, 0.12, 1.12, 3.0),
		(-3.5, 0.82, 0.16, 1.02, 3.0),
	], [fus]))
	o.append(L.loft("canopy", [
		(2.15, 0.05, 0.85, 0.9, 2.0),
		(1.8, 0.36, 0.8, 1.3, 2.0),
		(1.0, 0.5, 0.9, 1.5, 2.0),
		(0.0, 0.42, 0.98, 1.45, 2.0),
		(-0.5, 0.05, 1.1, 1.2, 2.0),
	], [k.glass]))
	# prongs (mirrored lofts) with laser muzzles at x = +-2.4
	py0, py1 = 4.45, -3.15
	pm = _hm("dd_prong", u_lines=[_u(2.6, py0, py1), _u(-0.4, py0, py1)], v_lines=[0.25], line_w=0.01,
		zones=[(_u(3.9, py0, py1), _u(2.6, py0, py1), 0.0, 1.0, acc, 0.45, 0.2),
			(_u(-1.6, py0, py1), 1.0, 0.0, 1.0, HULL_D, 0.9, 0.35)],
		emit_zones=[(_u(1.9, py0, py1), _u(0.0, py0, py1), 0.24, 0.26, acc, 2.2)])
	o.append(L.loft("prong", [
		(4.45, 0.08, 0.5, 0.62, 2.0),
		(4.1, 0.3, 0.32, 0.86, 2.3),
		(3.0, 0.46, 0.2, 1.0, 2.6),
		(0.0, 0.52, 0.16, 1.04, 2.8),
		(-2.6, 0.5, 0.16, 1.0, 2.8),
		(-3.15, 0.38, 0.22, 0.9, 2.8),
	], [pm], x=2.4, mirror=True))
	o.append(L.tube_y("barrel", 2.4, 0.58, 4.85, 4.0, 0.1, mats=[k.metal], mirror=True))
	o.append(L.tube_y("muzzle", 2.4, 0.58, 4.98, 4.8, 0.14, mats=[k.light], mirror=True))
	# bridge between body and prongs
	bm = _hm("dd_bridge", base=HULL_M, v_lines=[0.5], line_w=0.02)
	o.append(L.wing("bridge", (0.8, 1.3), (0.8, -2.9), (2.0, 1.7), (2.0, -2.5), 0.3, 0.35, 0.3, [bm], mirror=True))
	# forward swept outer wings
	wm = _hm("dd_wing", u_lines=[0.4, 0.72], v_lines=[0.7], line_w=0.012,
		zones=[(0.0, 0.72, 0.7, 1.0, HULL_D, 0.9, 0.35),
			(0.4, 1.0, 0.0, 0.26, acc, 0.45, 0.2)],
		grad=("u", 1.0, 0.85))
	o.append(L.wing("wings", (2.75, -0.5), (2.75, -2.75), (6.65, 1.25), (6.75, 0.35), 0.3, 0.42, 0.1, [wm],
		mirror=True, z_tip=0.3))
	o.append(L.ellipsoid("tip_r", (6.68, 1.05, 0.62), (0.11, 0.24, 0.09), k.light))
	o.append(L.ellipsoid("tip_l", (-6.68, 1.05, 0.62), (0.11, 0.24, 0.09), k.light))
	o.append(L.slab("spine", [(0.0, -0.6), (0.3, -0.9), (0.3, -2.9), (-0.3, -2.9), (-0.3, -0.9)], 1.0, 1.3,
		k.hull_dark, bevel=0.06, segs=2))
	# engines: two in the body, small ones in the prongs
	o.append(L.nozzle("nozzle", 0.48, 0.62, -3.3, 0.8, 0.42, k.nozzle_mats, mirror=True))
	o.append(L.nozzle("pnozzle", 2.4, 0.6, -3.0, 0.55, 0.3, k.nozzle_mats, mirror=True))
	return o, [(0.48, -4.1, 0.62, 0.34), (-0.48, -4.1, 0.62, 0.34), (2.4, -3.55, 0.6, 0.24), (-2.4, -3.55, 0.6, 0.24)]


def build_double_hunter(k: Kit):
	"""Two fat rocket pods at +-2.4 with warheads peeking out, stubby wings, orange."""
	o = []
	acc = k.accent
	y0, y1 = 3.4, -3.65
	fus = _hm("dh_fus", u_lines=[_u(0.3, y0, y1), _u(-1.9, y0, y1)], v_lines=[0.13, 0.37], line_w=0.009)
	o.append(L.loft("fuselage", [
		(3.4, 0.12, 0.42, 0.56, 2.0),
		(2.9, 0.6, 0.22, 1.0, 2.4),
		(1.8, 0.98, 0.12, 1.22, 2.7),
		(-0.5, 1.1, 0.1, 1.28, 3.0),
		(-3.3, 1.05, 0.12, 1.15, 3.2),
		(-3.65, 0.9, 0.16, 1.05, 3.2),
	], [fus]))
	o.append(L.loft("canopy", [
		(2.55, 0.05, 0.95, 1.0, 2.0),
		(2.2, 0.4, 0.9, 1.4, 2.0),
		(1.3, 0.55, 0.95, 1.6, 2.0),
		(0.4, 0.46, 1.0, 1.52, 2.0),
		(-0.1, 0.05, 1.15, 1.25, 2.0),
	], [k.glass]))
	# rocket pods (boxy tubes) at +-2.4
	py0, py1 = 4.1, -2.75
	pod = _hm("dh_pod", base=HULL_M, u_lines=[_u(1.0, py0, py1), _u(-1.2, py0, py1)], v_lines=[0.25], line_w=0.01,
		zones=[(0.0, _u(3.75, py0, py1), 0.0, 1.0, HULL_D, 0.9, 0.3),
			(_u(3.55, py0, py1), _u(2.85, py0, py1), 0.0, 1.0, acc, 0.45, 0.2),
			(_u(-1.2, py0, py1), 1.0, 0.0, 1.0, HULL_D, 0.9, 0.35)],
		emit_zones=[(_u(0.8, py0, py1), _u(-0.9, py0, py1), 0.23, 0.27, acc, 2.2)])
	o.append(L.loft("pod", [
		(4.1, 0.6, 0.12, 1.28, 3.0),
		(3.9, 0.78, 0.0, 1.42, 3.2),
		(-2.4, 0.78, 0.0, 1.42, 3.2),
		(-2.75, 0.62, 0.12, 1.28, 3.0),
	], [pod], x=2.4, mirror=True, cap_front=0, cap_back=0))
	# warheads peeking out of the pods (match the rocket sprite)
	wh = L.mat_basic("dh_wh", (0.85, 0.85, 0.88), metallic=0.9, rough=0.2)
	o.append(L.loft("warhead", [
		(4.75, 0.04, 0.68, 0.76, 2.0),
		(4.55, 0.2, 0.52, 0.92, 2.0),
		(4.25, 0.32, 0.4, 1.04, 2.0),
		(4.0, 0.34, 0.38, 1.06, 2.0),
	], [wh], x=2.4, mirror=True))
	o.append(L.tube_y("warhead_band", 2.4, 0.72, 4.15, 4.02, 0.36, mats=[k.paint], mirror=True))
	# connectors + stubby wings
	cm = _hm("dh_con", base=HULL_M, v_lines=[0.5], line_w=0.02)
	o.append(L.wing("conn", (0.95, 1.6), (0.95, -2.9), (1.7, 1.6), (1.7, -2.4), 0.3, 0.4, 0.4, [cm], mirror=True))
	wm = _hm("dh_wing", u_lines=[0.45], v_lines=[0.72], line_w=0.014,
		zones=[(0.0, 0.85, 0.72, 1.0, HULL_D, 0.9, 0.35),
			(0.62, 1.0, 0.0, 0.72, acc, 0.45, 0.2)],
		grad=("u", 1.0, 0.85))
	o.append(L.wing("wings", (3.1, 0.6), (3.1, -2.3), (6.65, -0.9), (6.75, -2.5), 0.3, 0.45, 0.14, [wm],
		mirror=True, z_tip=0.3))
	o.append(L.ellipsoid("tip_r", (6.7, -1.1, 0.68), (0.1, 0.22, 0.09), k.light))
	o.append(L.ellipsoid("tip_l", (-6.7, -1.1, 0.68), (0.1, 0.22, 0.09), k.light))
	# engines
	o.append(L.nozzle("nozzle", 0.52, 0.62, -3.4, 0.85, 0.46, k.nozzle_mats, mirror=True))
	o.append(L.nozzle("pnozzle", 2.4, 0.7, -2.7, 0.55, 0.36, k.nozzle_mats, mirror=True))
	return o, [(0.52, -4.25, 0.62, 0.36), (-0.52, -4.25, 0.62, 0.36), (2.4, -3.25, 0.7, 0.28), (-2.4, -3.25, 0.7, 0.28)]


def build_blaster(k: Kit):
	"""Heavy armoured body, one big central cannon with energy coils, three engines, red."""
	o = []
	acc = k.accent
	y0, y1 = 2.5, -3.9
	hull = _hm("bl_hull", base=(0.46, 0.47, 0.5), u_lines=[_u(0.9, y0, y1), _u(-1.6, y0, y1), _u(-3.0, y0, y1)],
		v_lines=[0.1, 0.4], line_w=0.008, zones=[(0.0, _u(1.6, y0, y1), 0.0, 1.0, acc, 0.45, 0.2)])
	o.append(L.loft("hull", [
		(2.5, 1.3, 0.3, 0.9, 3.0),
		(2.2, 1.9, 0.15, 1.3, 3.0),
		(1.2, 2.55, 0.1, 1.48, 3.0),
		(-0.8, 2.9, 0.1, 1.55, 3.2),
		(-3.0, 2.85, 0.1, 1.45, 3.4),
		(-3.6, 2.5, 0.15, 1.3, 3.4),
		(-3.9, 2.1, 0.25, 1.1, 3.4),
	], [hull]))
	# armour wings (heavy slabs) with red armour plates
	wing = [(2.6, 0.7), (6.35, -0.85), (6.8, -1.35), (6.8, -3.0), (6.35, -3.45), (2.6, -3.55)]
	o.append(L.slab("armwing", wing, 0.2, 0.75, k.hull, bevel=0.18, segs=3, mirror=True))
	plate = [(3.3, 0.15), (6.1, -1.05), (6.4, -1.45), (6.4, -2.2), (3.3, -1.75)]
	o.append(L.slab("plate", plate, 0.65, 0.88, k.paint, bevel=0.07, segs=2, mirror=True))
	o.append(L.slab("plate2", [(3.3, -2.15), (6.4, -2.6), (6.4, -2.95), (6.1, -3.15), (3.3, -3.15)], 0.62, 0.84,
		k.hull_dark, bevel=0.06, segs=2, mirror=True))
	o.append(L.ellipsoid("tip_r", (6.75, -2.2, 0.62), (0.09, 0.42, 0.1), k.light))
	o.append(L.ellipsoid("tip_l", (-6.75, -2.2, 0.62), (0.09, 0.42, 0.1), k.light))
	# cannon: housing, barrel, coils, muzzle brake
	hm = _hm("bl_house", base=HULL_D, metallic=0.9, u_lines=[0.55], v_lines=[0.25], line_w=0.012,
		zones=[(0.0, 0.1, 0, 1, acc, 0.45, 0.2)])
	o.append(L.loft("housing", [
		(3.3, 0.75, 0.9, 1.8, 3.0),
		(2.95, 1.12, 0.8, 2.05, 3.2),
		(0.9, 1.2, 0.8, 2.1, 3.2),
		(0.5, 0.95, 0.9, 1.95, 3.0),
	], [hm]))
	o.append(L.tube_y("barrel", 0, 1.6, 4.5, 3.0, 0.42, mats=[k.metal]))
	for i, yy in enumerate((4.1, 3.72, 3.34)):
		o.append(L.tube_y("coil%d" % i, 0, 1.6, yy, yy - 0.18, 0.5, mats=[k.light]))
	o.append(L.loft("brake", [
		(5.0, 0.5, 1.12, 2.08, 2.0),
		(4.92, 0.6, 1.0, 2.2, 2.0),
		(4.45, 0.6, 1.0, 2.2, 2.0),
		(4.38, 0.5, 1.1, 2.1, 2.0),
	], [k.gun], cap_front=0, cap_back=0))
	o.append(L.slab("brake_slot", [(0.62, 4.82), (0.62, 4.6), (-0.62, 4.6), (-0.62, 4.82)], 1.3, 1.95, k.black,
		bevel=0.0))
	# armour plates either side of the canopy
	o.append(L.slab("top_plate", [(1.0, 0.7), (2.3, 0.4), (2.5, -1.4), (1.0, -1.6)], 1.2, 1.62, k.hull_dark,
		bevel=0.08, segs=2, mirror=True))
	o.append(L.slab("top_stripe", [(1.15, 0.45), (2.25, 0.2), (2.3, -0.05), (1.15, 0.2)], 1.5, 1.66, k.paint,
		bevel=0.03, segs=1, mirror=True))
	# canopy (wide, low) behind the cannon
	o.append(L.loft("canopy", [
		(0.55, 0.05, 1.35, 1.4, 2.0),
		(0.3, 0.55, 1.3, 1.75, 2.0),
		(-0.5, 0.75, 1.3, 1.9, 2.0),
		(-1.3, 0.62, 1.35, 1.82, 2.0),
		(-1.7, 0.05, 1.45, 1.55, 2.0),
	], [k.glass]))
	o.append(L.slab("vents", [(1.4, -1.9), (2.3, -1.9), (2.3, -2.9), (1.4, -2.9)], 1.0, 1.52, k.hull_dark,
		bevel=0.06, segs=2, mirror=True))
	for i in range(4):
		yy = -2.05 - i * 0.24
		o.append(L.slab("vent%d" % i, [(1.5, yy), (2.2, yy), (2.2, yy - 0.1), (1.5, yy - 0.1)], 1.45, 1.56,
			k.light_soft, bevel=0.0, mirror=True))
	# three engines
	o.append(L.nozzle("nozzle_c", 0.0, 0.7, -3.7, 0.8, 0.52, k.nozzle_mats))
	o.append(L.nozzle("nozzle_s", 1.55, 0.65, -3.65, 0.75, 0.46, k.nozzle_mats, mirror=True))
	return o, [(0.0, -4.5, 0.7, 0.4), (1.55, -4.4, 0.65, 0.36), (-1.55, -4.4, 0.65, 0.36)]


def build_hunter(k: Kit):
	"""Bulky beetle hull, two heavy launchers side by side near the centre (+-1.2), purple."""
	o = []
	acc = k.accent
	y0, y1 = 2.2, -3.8
	hull = _hm("hu_hull", u_lines=[_u(-0.2, y0, y1), _u(-2.2, y0, y1)], v_lines=[0.08, 0.42], line_w=0.008,
		zones=[(_u(-2.6, y0, y1), 1.0, 0.0, 1.0, HULL_D, 0.9, 0.35),
			(_u(1.2, y0, y1), _u(-2.6, y0, y1), 0.0, 0.12, HULL_M, 0.85, 0.3),
			(_u(1.2, y0, y1), _u(-2.6, y0, y1), 0.38, 0.5, HULL_M, 0.85, 0.3),
			(_u(1.2, y0, y1), _u(-2.6, y0, y1), 0.12, 0.135, acc, 0.45, 0.2),
			(_u(1.2, y0, y1), _u(-2.6, y0, y1), 0.365, 0.38, acc, 0.45, 0.2)])
	o.append(L.loft("hull", [
		(2.2, 1.0, 0.4, 1.0, 2.2),
		(1.7, 2.0, 0.2, 1.4, 2.3),
		(0.4, 2.75, 0.1, 1.65, 2.4),
		(-1.5, 2.95, 0.1, 1.7, 2.5),
		(-3.1, 2.6, 0.12, 1.5, 2.6),
		(-3.8, 1.8, 0.2, 1.2, 2.6),
	], [hull]))
	# claw wings, swept back and curving down
	wm = _hm("hu_wing", u_lines=[0.5], v_lines=[0.7], line_w=0.014,
		zones=[(0.0, 1.0, 0.7, 1.0, HULL_D, 0.9, 0.35),
			(0.55, 1.0, 0.0, 0.7, acc, 0.45, 0.2)],
		emit_zones=[(0.52, 0.55, 0.05, 0.68, acc, 2.2)],
		grad=("u", 1.0, 0.85))
	o.append(L.wing("wings", (2.4, 0.9), (2.4, -2.6), (6.55, -1.9), (6.75, -3.9), 0.25, 0.65, 0.16, [wm],
		mirror=True, z_tip=0.1))
	# bulky armour nacelles on the wings
	nm = _hm("hu_nac", base=HULL_M, u_lines=[0.5], v_lines=[0.25], line_w=0.012,
		zones=[(0.0, 0.2, 0, 1, acc, 0.45, 0.2), (0.78, 1.0, 0, 1, HULL_D, 0.9, 0.35)],
		emit_zones=[(0.25, 0.75, 0.235, 0.265, acc, 2.2)])
	o.append(L.loft("nacelle", [
		(0.15, 0.1, 0.55, 0.75, 2.0),
		(-0.25, 0.42, 0.3, 1.15, 2.6),
		(-0.8, 0.55, 0.25, 1.25, 3.0),
		(-2.9, 0.55, 0.25, 1.25, 3.0),
		(-3.4, 0.42, 0.35, 1.1, 3.0),
	], [nm], x=4.35, mirror=True))
	o.append(L.ellipsoid("tip_r", (6.68, -3.5, 0.45), (0.1, 0.3, 0.1), k.light))
	o.append(L.ellipsoid("tip_l", (-6.68, -3.5, 0.45), (0.1, 0.3, 0.1), k.light))
	# two heavy launchers at x = +-1.2
	ly0, ly1 = 4.15, 0.3
	lm = _hm("hu_launch", base=HULL_M, u_lines=[_u(2.4, ly0, ly1)], v_lines=[0.25], line_w=0.012,
		zones=[(0.0, _u(3.75, ly0, ly1), 0, 1, HULL_D, 0.9, 0.3),
			(_u(3.55, ly0, ly1), _u(2.95, ly0, ly1), 0, 1, acc, 0.45, 0.2)])
	o.append(L.loft("launcher", [
		(4.15, 0.48, 0.75, 1.75, 3.5),
		(4.0, 0.58, 0.65, 1.85, 3.5),
		(0.6, 0.58, 0.65, 1.85, 3.5),
		(0.3, 0.48, 0.75, 1.75, 3.5),
	], [lm], x=1.2, mirror=True))
	wh = L.mat_basic("hu_wh", _lighten(acc, 0.55), metallic=0.85, rough=0.22)
	o.append(L.loft("warhead", [
		(4.75, 0.06, 1.2, 1.32, 2.0),
		(4.6, 0.3, 1.0, 1.5, 2.0),
		(4.35, 0.42, 0.88, 1.62, 2.0),
		(4.1, 0.44, 0.86, 1.64, 2.0),
	], [wh], x=1.2, mirror=True))
	o.append(L.slab("launch_led", [(0.95, 2.6), (1.45, 2.6), (1.45, 2.45), (0.95, 2.45)], 1.8, 1.9, k.light,
		bevel=0.0, mirror=True))
	# canopy behind the launchers
	o.append(L.loft("canopy", [
		(0.25, 0.05, 1.6, 1.65, 2.0),
		(0.0, 0.5, 1.5, 1.95, 2.0),
		(-0.8, 0.66, 1.5, 2.1, 2.0),
		(-1.6, 0.5, 1.55, 1.98, 2.0),
		(-2.0, 0.05, 1.62, 1.7, 2.0),
	], [k.glass]))
	o.append(L.slab("spine", [(0.0, -2.0), (0.35, -2.25), (0.35, -3.4), (-0.35, -3.4), (-0.35, -2.25)], 1.3, 1.6,
		k.hull_dark, bevel=0.06, segs=2))
	o.append(L.slab("spine_l", [(0.0, -2.35), (0.1, -2.45), (0.1, -3.2), (-0.1, -3.2), (-0.1, -2.45)], 1.56, 1.63,
		k.light_soft, bevel=0.0))
	# engines
	o.append(L.nozzle("nozzle", 1.25, 0.7, -3.5, 0.85, 0.55, k.nozzle_mats, mirror=True))
	return o, [(1.25, -4.35, 0.7, 0.42), (-1.25, -4.35, 0.7, 0.42)]


BUILDERS = {
	"interceptor": build_interceptor,
	"fighter": build_fighter,
	"double_dart": build_double_dart,
	"double_hunter": build_double_hunter,
	"blaster": build_blaster,
	"hunter": build_hunter,
}


# ------------------------------------------------------------------------------------------------
# Exhaust plume (glow pass only)
# ------------------------------------------------------------------------------------------------
def plume(name: str, x: float, y: float, z: float, r: float, color, length: float = 1.9):
	"""Soft emissive exhaust cone starting at the nozzle exit (x, y, z) and pointing to -Y."""
	outer = L.mat_plume(name + "_o", color, 2.6, length, 1.4)
	core = L.mat_plume(name + "_c", _lighten(color, 0.15), 3.2, length * 0.55, 1.2)
	o1 = L.loft(name, [
		(0.05, r * 0.85, -r * 0.85, r * 0.85, 2.0),
		(-0.25 * length, r * 1.12, -r * 1.12, r * 1.12, 2.0),
		(-0.65 * length, r * 0.7, -r * 0.7, r * 0.7, 2.0),
		(-length, r * 0.12, -r * 0.12, r * 0.12, 2.0),
	], [outer], cap_front=0, cap_back=0)
	o1.location = (x, y, z)
	o2 = L.loft(name + "_core", [
		(0.05, r * 0.55, -r * 0.55, r * 0.55, 2.0),
		(-0.2 * length, r * 0.6, -r * 0.6, r * 0.6, 2.0),
		(-0.55 * length, r * 0.1, -r * 0.1, r * 0.1, 2.0),
	], [core], cap_front=0, cap_back=0)
	o2.location = (x, y, z + 0.02)
	return [o1, o2]
