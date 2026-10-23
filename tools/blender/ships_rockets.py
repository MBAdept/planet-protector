"""Rocket sprites (no flame - flames are procedural in Godot). SPEC §16.5.

rocket.png       canvas 24 x 64 px  (visual ~12 x 52 px): slim missile, silver body, red-orange fins.
rocket_heavy.png canvas 40 x 72 px  (visual ~22 x 62 px): fat purple warhead (Hunter), heavy fins.
1 Blender unit = 10 sprite px, nose points to +Y, rendered top-down at 8x and down-sampled.
"""
from __future__ import annotations

import os

import ships_lib as L

SS = 8
FIN = (1.0, 0.22, 0.03)
PURPLE = (0.42, 0.06, 1.0)


def _lights() -> None:
	L.studio_world(strength=0.6)
	L.sun("key", (-0.62, 0.55, 0.75), 4.4, (1.0, 0.95, 0.88), 8.0)
	L.sun("rim", (0.8, -0.5, 0.28), 4.5, (0.35, 0.6, 1.0), 5.0)


def _center(objs) -> None:
	mn, mx = L.world_bbox(objs)
	L.shift_objects(objs, -0.5 * (mn.x + mx.x), -0.5 * (mn.y + mx.y))


def build_rocket():
	o = []
	y0, y1 = 2.6, -2.35
	body = L.mat_part("rk_body", (0.82, 0.83, 0.86), metallic=0.85, rough=0.22, coat=0.6,
		u_lines=[0.36, 0.7], line_w=0.008,
		zones=[(0.0, 0.07, 0, 1, FIN, 0.4, 0.2),
			(0.27, 0.33, 0, 1, (0.05, 0.05, 0.06), 0.6, 0.35),
			(0.86, 1.0, 0, 1, (0.18, 0.19, 0.21), 0.9, 0.3)],
		brushed=False)
	o.append(L.loft("body", [
		(2.6, 0.015, -0.015, 0.015, 2.0),
		(2.42, 0.1, -0.1, 0.1, 2.0),
		(2.15, 0.19, -0.19, 0.19, 2.0),
		(1.75, 0.26, -0.26, 0.26, 2.0),
		(1.3, 0.29, -0.29, 0.29, 2.0),
		(-1.95, 0.29, -0.29, 0.29, 2.0),
		(-2.2, 0.25, -0.25, 0.25, 2.0),
		(-2.35, 0.24, -0.24, 0.24, 2.0),
	], [body], n=40))
	gun = L.mat_basic("rk_noz", (0.2, 0.2, 0.22), metallic=1.0, rough=0.3)
	o.append(L.loft("nozzle", [
		(-2.3, 0.18, -0.18, 0.18, 2.0),
		(-2.62, 0.22, -0.22, 0.22, 2.0),
	], [gun], n=32))
	fin = L.mat_part("rk_fin", FIN, metallic=0.4, rough=0.22, coat=1.0,
		zones=[(0.0, 1.0, 0.82, 1.0, (0.06, 0.06, 0.07), 0.5, 0.35)], brushed=False)
	# lateral tail fins (seen from the top) + small canards
	o.append(L.wing("fins", (0.22, -1.05), (0.22, -2.2), (0.64, -1.85), (0.64, -2.42), -0.04, 0.09, 0.04, [fin],
		mirror=True, edge=0.03, nu=6, nv=8))
	o.append(L.wing("canards", (0.24, 0.95), (0.24, 0.45), (0.46, 0.62), (0.46, 0.38), -0.03, 0.06, 0.03, [fin],
		mirror=True, edge=0.03, nu=4, nv=6))
	# dorsal fin, edge-on from the top: a thin coloured ridge
	o.append(L.slab("dorsal", [(0.035, -1.05), (0.035, -2.25), (-0.035, -2.25), (-0.035, -1.05)], 0.0, 0.62, fin,
		bevel=0.015, segs=1))
	return o


def build_heavy():
	o = []
	wh_col = (0.36, 0.2, 0.75)
	war = L.mat_part("hv_war", wh_col, metallic=0.8, rough=0.2, coat=0.8,
		u_lines=[0.55], line_w=0.012,
		zones=[(0.0, 0.1, 0, 1, (0.85, 0.82, 0.95), 0.9, 0.18),
			(0.8, 1.0, 0, 1, (0.08, 0.08, 0.1), 0.8, 0.3)],
		emit_zones=[(0.66, 0.74, 0, 1, PURPLE, 2.4)], brushed=False)
	o.append(L.loft("warhead", [
		(3.15, 0.02, -0.02, 0.02, 2.0),
		(2.92, 0.22, -0.22, 0.22, 2.0),
		(2.6, 0.46, -0.46, 0.46, 2.0),
		(2.15, 0.68, -0.68, 0.68, 2.0),
		(1.65, 0.82, -0.82, 0.82, 2.0),
		(1.25, 0.82, -0.82, 0.82, 2.0),
		(0.95, 0.56, -0.56, 0.56, 2.0),
	], [war], n=48))
	body = L.mat_part("hv_body", (0.62, 0.63, 0.67), metallic=0.85, rough=0.25, coat=0.5,
		u_lines=[0.45], line_w=0.01,
		zones=[(0.0, 0.08, 0, 1, (0.08, 0.08, 0.1), 0.8, 0.3),
			(0.82, 1.0, 0, 1, (0.16, 0.17, 0.19), 0.9, 0.3)], brushed=False)
	o.append(L.loft("body", [
		(1.0, 0.5, -0.5, 0.5, 2.0),
		(-2.2, 0.5, -0.5, 0.5, 2.0),
		(-2.45, 0.42, -0.42, 0.42, 2.0),
		(-2.55, 0.4, -0.4, 0.4, 2.0),
	], [body], n=40))
	gun = L.mat_basic("hv_noz", (0.2, 0.2, 0.22), metallic=1.0, rough=0.3)
	o.append(L.loft("nozzle", [
		(-2.5, 0.3, -0.3, 0.3, 2.0),
		(-2.95, 0.36, -0.36, 0.36, 2.0),
	], [gun], n=32))
	fin = L.mat_part("hv_fin", PURPLE, metallic=0.45, rough=0.22, coat=1.0,
		zones=[(0.0, 1.0, 0.8, 1.0, (0.05, 0.05, 0.06), 0.5, 0.35)], brushed=False)
	o.append(L.wing("fins", (0.38, -0.9), (0.38, -2.4), (1.05, -1.95), (1.05, -2.72), -0.06, 0.14, 0.06, [fin],
		mirror=True, edge=0.04, nu=6, nv=8))
	o.append(L.slab("dorsal", [(0.05, -0.9), (0.05, -2.45), (-0.05, -2.45), (-0.05, -0.9)], 0.0, 0.95, fin,
		bevel=0.02, segs=1))
	return o


def render_rockets(work: str, samples: int) -> None:
	for name, builder, (w, h) in (("rocket", build_rocket, (24, 64)), ("rocket_heavy", build_heavy, (40, 72))):
		L.reset_scene()
		L.setup_render(w * SS, h * SS, samples)
		L.camera_top(w / L.UNIT_PX)
		_lights()
		objs = builder()
		_center(objs)
		L.render_to_npy(os.path.join(work, "rockets", name + ".npy"))
		print("[rockets] %s done" % name)
