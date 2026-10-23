"""Title logo ("PLANET PROTECTOR", 3D extruded molten-chrome letters) and the app icon. SPEC §16.6.

Logo: two lines set in Orbitron (thickened with offset + bevel), seen by a slightly tilted orthographic
camera so the glowing extrusion is visible below every letter. Faces are split by normal into
front (dark chrome with a reflected horizon band and a molten glow rising from the bottom),
bevel (hot emissive rim) and sides (red-hot metal fading to the back).
The outer glow halo is added in ships_post_logo.py.
"""
from __future__ import annotations

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

import ships_lib as L
import ships_models as M

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FONT = os.path.join(ROOT, "game", "assets", "fonts", "Orbitron.ttf")
LOGO_W, LOGO_H = 1600, 420


# ------------------------------------------------------------------------------------------------
# Text geometry
# ------------------------------------------------------------------------------------------------
def _text_mesh(name: str, body: str, size: float, extrude: float, offset: float, bevel: float,
		spacing: float) -> bpy.types.Object:
	fnt = bpy.data.fonts.load(FONT, check_existing=True)
	cu = bpy.data.curves.new(name, "FONT")
	cu.body = body
	cu.font = fnt
	cu.size = size
	cu.align_x = "CENTER"
	cu.align_y = "CENTER"
	cu.space_character = spacing
	cu.extrude = extrude
	cu.offset = offset
	cu.bevel_depth = bevel
	cu.bevel_resolution = 4
	cu.resolution_u = 24
	tob = bpy.data.objects.new(name + "_txt", cu)
	bpy.context.scene.collection.objects.link(tob)
	dg = bpy.context.evaluated_depsgraph_get()
	me = bpy.data.meshes.new_from_object(tob.evaluated_get(dg))
	bpy.data.objects.remove(tob)
	ob = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(ob)
	return ob


def _assign_by_normal(ob: bpy.types.Object) -> None:
	"""material 0 = front (normal +Z), 1 = bevel, 2 = side/back."""
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	bm.normal_update()
	for f in bm.faces:
		nz = f.normal.z
		f.material_index = 0 if nz > 0.97 else (1 if nz > 0.12 else 2)
		f.smooth = 0.12 < nz <= 0.97
	bm.to_mesh(ob.data)
	bm.free()


def _local_bbox(ob):
	xs = [v.co.x for v in ob.data.vertices]
	ys = [v.co.y for v in ob.data.vertices]
	zs = [v.co.z for v in ob.data.vertices]
	return min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)


# ------------------------------------------------------------------------------------------------
# Materials
# ------------------------------------------------------------------------------------------------
def _ramp(nt, stops, interp="LINEAR"):
	r = nt.nodes.new("ShaderNodeValToRGB")
	cr = r.color_ramp
	cr.interpolation = interp
	cr.elements[0].position = stops[0][0]
	cr.elements[0].color = (*stops[0][1], 1)
	cr.elements[1].position = stops[-1][0]
	cr.elements[1].color = (*stops[-1][1], 1)
	for p, c in stops[1:-1]:
		e = cr.elements.new(p)
		e.color = (*c, 1)
	return r


def _ty(nt, y0: float, y1: float, axis: str = "Y"):
	"""0 at y0 (bottom of the line) -> 1 at y1 (top), from object coordinates."""
	tc = nt.nodes.new("ShaderNodeTexCoord")
	sep = nt.nodes.new("ShaderNodeSeparateXYZ")
	nt.links.new(tc.outputs["Object"], sep.inputs[0])
	mr = nt.nodes.new("ShaderNodeMapRange")
	mr.inputs["From Min"].default_value = y0
	mr.inputs["From Max"].default_value = y1
	nt.links.new(sep.outputs[axis], mr.inputs["Value"])
	return mr.outputs["Result"]


def _molten(nt, color_socket, scale: float):
	"""Multiplies an emission colour by a soft turbulent noise (lava-like brightness variation)."""
	tc = nt.nodes.new("ShaderNodeTexCoord")
	nz = nt.nodes.new("ShaderNodeTexNoise")
	nz.inputs["Scale"].default_value = scale
	nz.inputs["Detail"].default_value = 6.0
	nz.inputs["Roughness"].default_value = 0.6
	nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
	mr = nt.nodes.new("ShaderNodeMapRange")
	mr.inputs["From Min"].default_value = 0.3
	mr.inputs["From Max"].default_value = 0.7
	mr.inputs["To Min"].default_value = 0.6
	mr.inputs["To Max"].default_value = 1.25
	nt.links.new(nz.outputs["Fac"], mr.inputs["Value"])
	mul = nt.nodes.new("ShaderNodeVectorMath")
	mul.operation = "SCALE"
	nt.links.new(color_socket, mul.inputs[0])
	nt.links.new(mr.outputs["Result"], mul.inputs["Scale"])
	return mul.outputs[0]


def mat_front(name: str, y0: float, y1: float) -> bpy.types.Material:
	m = bpy.data.materials.new(name)
	nt, bs = L._principled(m)
	t = _ty(nt, y0, y1)
	col = _ramp(nt, [
		(0.0, (0.55, 0.16, 0.04)),
		(0.16, (0.16, 0.1, 0.1)),
		(0.4, (0.05, 0.05, 0.065)),
		(0.53, (0.55, 0.56, 0.62)),
		(0.58, (0.85, 0.86, 0.9)),
		(0.66, (0.16, 0.17, 0.2)),
		(1.0, (0.3, 0.31, 0.36)),
	])
	nt.links.new(t, col.inputs["Fac"])
	nt.links.new(col.outputs["Color"], bs.inputs["Base Color"])
	bs.inputs["Metallic"].default_value = 1.0
	bs.inputs["Roughness"].default_value = 0.16
	bs.inputs["Coat Weight"].default_value = 0.6
	em = _ramp(nt, [
		(0.0, (1.0, 0.32, 0.03)),
		(0.12, (0.7, 0.12, 0.01)),
		(0.34, (0.0, 0.0, 0.0)),
		(1.0, (0.0, 0.0, 0.0)),
	], "EASE")
	nt.links.new(t, em.inputs["Fac"])
	nt.links.new(_molten(nt, em.outputs["Color"], 7.0), bs.inputs["Emission Color"])
	bs.inputs["Emission Strength"].default_value = 1.6
	return m


def mat_bevel(name: str, y0: float, y1: float) -> bpy.types.Material:
	m = bpy.data.materials.new(name)
	nt, bs = L._principled(m)
	t = _ty(nt, y0, y1)
	bs.inputs["Base Color"].default_value = (0.3, 0.12, 0.06, 1)
	bs.inputs["Metallic"].default_value = 1.0
	bs.inputs["Roughness"].default_value = 0.2
	em = _ramp(nt, [
		(0.0, (1.0, 0.62, 0.16)),
		(0.35, (1.0, 0.36, 0.04)),
		(1.0, (0.9, 0.12, 0.02)),
	])
	nt.links.new(t, em.inputs["Fac"])
	nt.links.new(em.outputs["Color"], bs.inputs["Emission Color"])
	bs.inputs["Emission Strength"].default_value = 2.4
	return m


def mat_side(name: str, z_front: float, z_back: float, y0: float, y1: float) -> bpy.types.Material:
	m = bpy.data.materials.new(name)
	nt, bs = L._principled(m)
	tz = _ty(nt, z_back, z_front, "Z")
	bs.inputs["Base Color"].default_value = (0.12, 0.06, 0.05, 1)
	bs.inputs["Metallic"].default_value = 0.9
	bs.inputs["Roughness"].default_value = 0.35
	em = _ramp(nt, [
		(0.0, (0.08, 0.005, 0.0)),
		(0.55, (0.55, 0.06, 0.01)),
		(1.0, (1.0, 0.25, 0.03)),
	], "EASE")
	nt.links.new(tz, em.inputs["Fac"])
	nt.links.new(_molten(nt, em.outputs["Color"], 9.0), bs.inputs["Emission Color"])
	bs.inputs["Emission Strength"].default_value = 1.8
	return m


# ------------------------------------------------------------------------------------------------
# Logo
# ------------------------------------------------------------------------------------------------
def _logo_world() -> None:
	"""Dark environment with a warm low horizon (for the chrome) and a cool top."""
	w = bpy.data.worlds.new("logo")
	bpy.context.scene.world = w
	nt = L._node_tree(w)
	nt.nodes.clear()
	tc = nt.nodes.new("ShaderNodeTexCoord")
	sep = nt.nodes.new("ShaderNodeSeparateXYZ")
	nt.links.new(tc.outputs["Generated"], sep.inputs[0])
	mr = nt.nodes.new("ShaderNodeMapRange")
	mr.inputs["From Min"].default_value = -1.0
	mr.inputs["From Max"].default_value = 1.0
	nt.links.new(sep.outputs["Y"], mr.inputs["Value"])
	r = _ramp(nt, [
		(0.0, (0.6, 0.12, 0.02)),
		(0.42, (0.05, 0.02, 0.02)),
		(0.5, (0.01, 0.01, 0.015)),
		(0.62, (0.08, 0.1, 0.16)),
		(1.0, (0.35, 0.42, 0.6)),
	])
	nt.links.new(mr.outputs["Result"], r.inputs["Fac"])
	bg = nt.nodes.new("ShaderNodeBackground")
	bg.inputs["Strength"].default_value = 1.0
	nt.links.new(r.outputs["Color"], bg.inputs["Color"])
	out = nt.nodes.new("ShaderNodeOutputWorld")
	nt.links.new(bg.outputs[0], out.inputs[0])


def _cam_bbox(cam_ob, objs):
	bpy.context.view_layer.update()
	inv = cam_ob.matrix_world.inverted()
	xs, ys = [], []
	dg = bpy.context.evaluated_depsgraph_get()
	for ob in objs:
		me = ob.evaluated_get(dg).to_mesh()
		for v in me.vertices:
			p = inv @ (ob.matrix_world @ v.co)
			xs.append(p.x)
			ys.append(p.y)
		ob.evaluated_get(dg).to_mesh_clear()
	return min(xs), max(xs), min(ys), max(ys)


def _content_aspect(cam_ob, objs) -> float:
	x0, x1, y0, y1 = _cam_bbox(cam_ob, objs)
	return (x1 - x0) / (y1 - y0)


def _frame_camera(cam_ob, objs, res_x: int, res_y: int, margin_px: float) -> None:
	"""Adjusts ortho scale + position so all vertices fit tightly (plus a margin) in the frame."""
	bpy.context.view_layer.update()
	inv = cam_ob.matrix_world.inverted()
	xs, ys = [], []
	dg = bpy.context.evaluated_depsgraph_get()
	for ob in objs:
		me = ob.evaluated_get(dg).to_mesh()
		for v in me.vertices:
			p = inv @ (ob.matrix_world @ v.co)
			xs.append(p.x)
			ys.append(p.y)
		ob.evaluated_get(dg).to_mesh_clear()
	x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
	aspect = res_x / res_y
	cw, ch = x1 - x0, y1 - y0
	# scale so the content fits inside (res - 2*margin)
	sx = cw / (res_x - 2 * margin_px) * res_x
	sy = ch / (res_y - 2 * margin_px) * res_y * aspect
	cam_ob.data.ortho_scale = max(sx, sy)
	c = Vector(((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.0))
	cam_ob.location = cam_ob.matrix_world @ c
	print("[logo] content aspect %.2f (canvas %.2f), ortho %.3f" % (cw / ch, aspect, cam_ob.data.ortho_scale))


def build_logo_objects():
	ext, off, bev = 0.16, 0.022, 0.03
	lines = []
	for name, body, size, sp, y in (("planet", "PLANET", 1.0, 1.14, 0.62), ("protector", "PROTECTOR", 1.0, 1.2, -0.62)):
		ob = _text_mesh(name, body, size, ext, off, bev, sp)
		_assign_by_normal(ob)
		x0, x1, y0, y1, z0, z1 = _local_bbox(ob)
		print("[logo] %s bbox w=%.3f h=%.3f" % (body, x1 - x0, y1 - y0))
		ob.data.materials.append(mat_front(name + "_front", y0, y1))
		ob.data.materials.append(mat_bevel(name + "_bevel", y0, y1))
		ob.data.materials.append(mat_side(name + "_side", z1, z0, y0, y1))
		lines.append((ob, x1 - x0, y1 - y0, y))
	# match the line widths: scale "PLANET" up so both lines are equally wide
	w_ref = lines[1][1]
	for ob, w, h, y in lines:
		k = w_ref / w
		ob.scale = (k, k, 1.0)
	# stack: PLANET on top, PROTECTOR below, small gap
	h_top = lines[0][2] * (w_ref / lines[0][1])
	h_bot = lines[1][2]
	gap = 0.17
	lines[0][0].location = (0, 0.5 * (h_bot + gap), 0)
	lines[1][0].location = (0, -0.5 * (h_top + gap), 0)
	return [l[0] for l in lines]


def render_logo(work: str, samples: int) -> None:
	L.reset_scene()
	L.setup_render(LOGO_W, LOGO_H, max(64, samples))
	objs = build_logo_objects()
	cam = L.camera_top(10.0)
	cam.location = (0, 0, 30)
	tilt = math.radians(17.0)
	cam.rotation_euler = (tilt, 0.0, 0.0)
	cam.location = Matrix.Rotation(tilt, 3, "X") @ Vector((0, 0, 30))
	# widen the letters (extended look) until the block matches the canvas aspect
	for _ in range(3):
		asp = _content_aspect(cam, objs)
		k = (LOGO_W - 2 * 40) / (LOGO_H - 2 * 40) / asp
		for ob in objs:
			ob.scale.x *= k
	_frame_camera(cam, objs, LOGO_W, LOGO_H, margin_px=40)
	_logo_world()
	L.sun("key", (-0.5, 0.35, 0.8), 3.0, (1.0, 0.92, 0.85), 6.0)
	L.sun("rim", (0.6, 0.7, -0.2), 4.0, (1.0, 0.45, 0.15), 4.0)
	L.render_to_npy(os.path.join(work, "logo", "logo.npy"))
	print("[logo] done")


# ------------------------------------------------------------------------------------------------
# Icon: demon silhouette behind a ship, rendered as separate layers and composited in post
# ------------------------------------------------------------------------------------------------
def _demon_poly():
	"""Right half of a winged demon silhouette (x >= 0), in units; mirrored for the left half."""
	return [
		(0.0, 2.05),     # forehead dip between horns
		(0.42, 2.25),
		(0.8, 3.15),     # horn tip
		(0.82, 2.35),
		(1.05, 1.75),    # side of head
		(1.25, 1.55),    # shoulder
		(2.4, 2.45),     # wing upper joint
		(3.9, 3.0),      # wing tip
		(3.55, 2.35),
		(3.75, 1.7),     # scallops of the wing edge
		(3.05, 1.65),
		(3.15, 0.95),
		(2.35, 1.05),
		(2.3, 0.3),
		(1.55, 0.55),
		(1.0, -0.6),     # body tapering to a tail
		(0.45, -1.3),
		(0.0, -1.55),
	]


def render_icon(work: str, samples: int) -> None:
	# layer 1: demon silhouette (dark armour with rim light, glowing eyes)
	L.reset_scene()
	res = 512
	L.setup_render(res, res, max(64, samples))
	L.camera_top(9.0, center=(0.0, 0.9))
	half = _demon_poly()
	poly = [(-x, y) for (x, y) in reversed(half[1:-1])] + half
	body = L.mat_basic("demon", (0.03, 0.012, 0.025), metallic=0.5, rough=0.45, coat=0.15)
	L.slab("demon", poly, 0.0, 0.5, body, bevel=0.22, segs=4)
	eye = L.mat_emit("eye", (1.0, 0.75, 0.1), 7.0)
	for sx in (-1, 1):
		L.slab("eye%d" % sx, [(sx * 0.14, 1.52), (sx * 0.7, 1.86), (sx * 0.62, 1.58), (sx * 0.2, 1.38)][::sx],
			0.5, 0.62, eye, bevel=0.0)
	L.flat_world((0.02, 0.0, 0.02), 0.2)
	L.sun("rim", (0.0, 0.75, 0.3), 9.0, (1.0, 0.2, 0.05), 5.0)
	L.sun("rim2", (-0.75, -0.3, 0.3), 3.0, (0.55, 0.15, 1.0), 6.0)
	L.render_to_npy(os.path.join(work, "icon", "demon.npy"))
	# layer 2: the interceptor, seen slightly from behind (perspective-free ortho, tilted)
	L.reset_scene()
	L.setup_render(res, res, max(64, samples))
	cam = L.camera_top(15.0)
	tilt = math.radians(28.0)
	cam.rotation_euler = (tilt, 0.0, 0.0)
	cam.location = Matrix.Rotation(tilt, 3, "X") @ Vector((0, 0, 40))
	L.studio_world(strength=0.6)
	L.sun("key", (-0.62, 0.55, 0.75), 4.4, (1.0, 0.95, 0.88), 8.0)
	L.sun("rim", (0.8, -0.5, 0.28), 4.5, (0.35, 0.6, 1.0), 5.0)
	L.sun("demonlight", (0.0, 1.0, 0.3), 2.5, (1.0, 0.3, 0.1), 6.0)
	kit = M.Kit("interceptor")
	objs, plumes = M.build_interceptor(kit)
	mn, mx = L.world_bbox(objs)
	L.shift_objects(objs, -0.5 * (mn.x + mx.x), -0.5 * (mn.y + mx.y))
	for i, (px, py, pz, pr) in enumerate(plumes):
		M.plume("plume%d" % i, px, py - 0.5 * (mn.y + mx.y), pz, pr, kit.exhaust, length=2.6)
	L.render_to_npy(os.path.join(work, "icon", "ship.npy"))
	print("[icon] layers done")
