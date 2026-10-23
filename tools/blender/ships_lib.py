"""Shared Blender helpers for the art-ships package (ships, rockets, logo, icon).

Runs inside Blender's Python (bpy). Geometry is built procedurally from numpy-free math so the
scripts are reproducible from scratch:  scene reset -> build -> render EXR -> dump float RGBA (.npy).

Conventions
- 1 Blender unit = 10 sprite px (= 5 game px) for ships and rockets.
- Top-down orthographic camera looking down -Z, image up = +Y (ship nose points to +Y).
- Renders are scene-linear, premultiplied RGBA float. Tone mapping, down-sampling and PNG
  encoding happen in ships_post.py (system python3 with Pillow).
"""
from __future__ import annotations

import math
import os
import warnings

import bpy  # noqa: I001  (bpy must be imported before bmesh)
import bmesh
import numpy as np
from mathutils import Vector

UNIT_PX = 10.0  # sprite px per Blender unit


# ------------------------------------------------------------------------------------------------
# Scene / render
# ------------------------------------------------------------------------------------------------
def reset_scene() -> bpy.types.Scene:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	return bpy.context.scene


def setup_render(res_x: int, res_y: int, samples: int = 96, denoise: bool = True, bounces: int = 6) -> None:
	sc = bpy.context.scene
	sc.render.engine = "CYCLES"
	sc.cycles.device = "CPU"
	sc.cycles.samples = samples
	sc.cycles.use_adaptive_sampling = True
	sc.cycles.adaptive_threshold = 0.01
	sc.cycles.use_denoising = denoise
	try:
		sc.cycles.denoiser = "OPENIMAGEDENOISE"
		sc.cycles.denoising_input_passes = "RGB_ALBEDO_NORMAL"
	except Exception:  # pragma: no cover - depends on build
		pass
	sc.cycles.max_bounces = bounces
	sc.cycles.diffuse_bounces = 3
	sc.cycles.glossy_bounces = 4
	sc.cycles.transmission_bounces = 4
	sc.cycles.transparent_max_bounces = 12
	sc.cycles.caustics_reflective = False
	sc.cycles.caustics_refractive = False
	sc.cycles.filter_width = 1.5
	sc.render.threads_mode = "FIXED"
	sc.render.threads = int(os.environ.get("ART_THREADS", "2"))
	sc.render.film_transparent = True
	sc.render.resolution_x = res_x
	sc.render.resolution_y = res_y
	sc.render.resolution_percentage = 100
	sc.view_settings.view_transform = "Standard"
	sc.view_settings.look = "None"
	sc.render.image_settings.file_format = "OPEN_EXR"
	sc.render.image_settings.color_mode = "RGBA"
	sc.render.image_settings.color_depth = "32"


def render_to_npy(npy_path: str) -> np.ndarray:
	"""Renders the scene and stores premultiplied linear RGBA float32 (rows top->bottom)."""
	sc = bpy.context.scene
	npy_path = os.path.abspath(npy_path)
	os.makedirs(os.path.dirname(npy_path), exist_ok=True)
	exr = npy_path[:-4] + ".exr"
	sc.render.filepath = exr
	bpy.ops.render.render(write_still=True)
	img = bpy.data.images.load(exr)
	w, h = img.size
	buf = np.empty(w * h * 4, dtype=np.float32)
	img.pixels.foreach_get(buf)
	bpy.data.images.remove(img)
	arr = buf.reshape(h, w, 4)[::-1].copy()
	np.save(npy_path, arr)
	try:
		os.remove(exr)
	except OSError:
		pass
	return arr


def camera_top(ortho_width: float, center=(0.0, 0.0), z: float = 40.0) -> bpy.types.Object:
	cam = bpy.data.cameras.new("cam")
	cam.type = "ORTHO"
	cam.sensor_fit = "HORIZONTAL"  # ortho_scale is always the canvas WIDTH
	cam.ortho_scale = ortho_width
	cam.clip_start = 0.1
	cam.clip_end = 200.0
	ob = bpy.data.objects.new("cam", cam)
	bpy.context.scene.collection.objects.link(ob)
	ob.location = (center[0], center[1], z)
	ob.rotation_euler = (0.0, 0.0, 0.0)
	bpy.context.scene.camera = ob
	return ob


def sun(name: str, from_dir, strength: float, color=(1, 1, 1), angle_deg: float = 6.0) -> bpy.types.Object:
	"""Sun lamp whose light comes FROM direction `from_dir` (vector pointing towards the light)."""
	lt = bpy.data.lights.new(name, type="SUN")
	lt.energy = strength
	lt.color = color
	lt.angle = math.radians(angle_deg)
	ob = bpy.data.objects.new(name, lt)
	bpy.context.scene.collection.objects.link(ob)
	d = Vector(from_dir).normalized()
	ob.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
	return ob


def _node_tree(idblock):
	if idblock.node_tree is None:
		with warnings.catch_warnings():
			warnings.simplefilter("ignore")
			idblock.use_nodes = True
	return idblock.node_tree


def studio_world(key_dir=(-0.55, 0.5, 0.68), strength: float = 1.0, warm=(1.25, 1.17, 1.05),
		cool=(0.05, 0.09, 0.2), zenith=(0.16, 0.17, 0.2)) -> None:
	"""Directional gradient environment: bright soft-box towards the key side, cool dark opposite.
	Metallic surfaces pick their brightness from this, so beveled edges read clearly."""
	w = bpy.data.worlds.new("studio")
	bpy.context.scene.world = w
	nt = _node_tree(w)
	nodes, links = nt.nodes, nt.links
	nodes.clear()
	tc = nodes.new("ShaderNodeTexCoord")
	dot = nodes.new("ShaderNodeVectorMath")
	dot.operation = "DOT_PRODUCT"
	dot.inputs[1].default_value = Vector(key_dir).normalized()
	links.new(tc.outputs["Generated"], dot.inputs[0])
	mr = nodes.new("ShaderNodeMapRange")
	mr.inputs["From Min"].default_value = -1.0
	mr.inputs["From Max"].default_value = 1.0
	links.new(dot.outputs["Value"], mr.inputs["Value"])
	ramp = nodes.new("ShaderNodeValToRGB")
	cr = ramp.color_ramp
	cr.interpolation = "B_SPLINE"
	cr.elements[0].position = 0.0
	cr.elements[0].color = (*cool, 1)
	cr.elements[1].position = 1.0
	cr.elements[1].color = (*warm, 1)
	e = cr.elements.new(0.55)
	e.color = (*zenith, 1)
	e = cr.elements.new(0.86)
	e.color = (0.45, 0.45, 0.47, 1)
	links.new(mr.outputs["Result"], ramp.inputs["Fac"])
	bg = nodes.new("ShaderNodeBackground")
	bg.inputs["Strength"].default_value = strength
	links.new(ramp.outputs["Color"], bg.inputs["Color"])
	out = nodes.new("ShaderNodeOutputWorld")
	links.new(bg.outputs["Background"], out.inputs["Surface"])


def flat_world(color=(0, 0, 0), strength: float = 1.0) -> None:
	w = bpy.data.worlds.new("flat")
	bpy.context.scene.world = w
	nt = _node_tree(w)
	bg = nt.nodes.get("Background")
	if bg is None:
		nt.nodes.clear()
		bg = nt.nodes.new("ShaderNodeBackground")
		out = nt.nodes.new("ShaderNodeOutputWorld")
		nt.links.new(bg.outputs[0], out.inputs[0])
	bg.inputs["Color"].default_value = (*color, 1)
	bg.inputs["Strength"].default_value = strength


# ------------------------------------------------------------------------------------------------
# Materials
# ------------------------------------------------------------------------------------------------
def _principled(mat):
	nt = _node_tree(mat)
	bs = nt.nodes.get("Principled BSDF")
	if bs is None:
		nt.nodes.clear()
		bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
		out = nt.nodes.new("ShaderNodeOutputMaterial")
		nt.links.new(bs.outputs[0], out.inputs[0])
	return nt, bs


def mat_basic(name: str, base, metallic: float = 0.0, rough: float = 0.4, coat: float = 0.0,
		emission=None, emit: float = 0.0, spec: float = 0.5, aniso: float = 0.0) -> bpy.types.Material:
	m = bpy.data.materials.new(name)
	nt, bs = _principled(m)
	bs.inputs["Base Color"].default_value = (*base, 1)
	bs.inputs["Metallic"].default_value = metallic
	bs.inputs["Roughness"].default_value = rough
	bs.inputs["Coat Weight"].default_value = coat
	bs.inputs["Coat Roughness"].default_value = 0.08
	bs.inputs["Specular IOR Level"].default_value = spec
	if aniso > 0.0:
		bs.inputs["Anisotropic"].default_value = aniso
		tg = nt.nodes.new("ShaderNodeTangent")
		tg.direction_type = "RADIAL"
		tg.axis = "X"
		nt.links.new(tg.outputs["Tangent"], bs.inputs["Tangent"])
	if emission is not None:
		bs.inputs["Emission Color"].default_value = (*emission, 1)
		bs.inputs["Emission Strength"].default_value = emit
	return m


def mat_emit(name: str, color, strength: float) -> bpy.types.Material:
	m = bpy.data.materials.new(name)
	nt = _node_tree(m)
	nt.nodes.clear()
	em = nt.nodes.new("ShaderNodeEmission")
	em.inputs["Color"].default_value = (*color, 1)
	em.inputs["Strength"].default_value = strength
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	nt.links.new(em.outputs[0], out.inputs[0])
	return m


def mat_hull(name: str, base, metallic: float = 0.75, rough: float = 0.3, panel: float = 0.45,
		brick=(2.2, 0.95), mortar: float = 0.05, coat: float = 0.35) -> bpy.types.Material:
	"""Brushed metal hull with darker panel lines (brick pattern in mirrored object space)."""
	m = bpy.data.materials.new(name)
	nt, bs = _principled(m)
	n, L = nt.nodes, nt.links
	tc = n.new("ShaderNodeTexCoord")
	sep = n.new("ShaderNodeSeparateXYZ")
	L.new(tc.outputs["Object"], sep.inputs[0])
	ab = n.new("ShaderNodeMath")
	ab.operation = "ABSOLUTE"
	L.new(sep.outputs["X"], ab.inputs[0])
	comb = n.new("ShaderNodeCombineXYZ")
	L.new(ab.outputs[0], comb.inputs["X"])
	L.new(sep.outputs["Y"], comb.inputs["Y"])
	L.new(sep.outputs["Z"], comb.inputs["Z"])
	br = n.new("ShaderNodeTexBrick")
	br.offset = 0.5
	br.inputs["Scale"].default_value = 1.0
	br.inputs["Brick Width"].default_value = brick[0]
	br.inputs["Row Height"].default_value = brick[1]
	br.inputs["Mortar Size"].default_value = mortar
	br.inputs["Mortar Smooth"].default_value = 0.2
	br.inputs["Color1"].default_value = (1, 1, 1, 1)
	br.inputs["Color2"].default_value = (0.93, 0.93, 0.93, 1)
	br.inputs["Mortar"].default_value = (1.0 - panel, 1.0 - panel, 1.0 - panel, 1)
	L.new(comb.outputs[0], br.inputs["Vector"])
	# brushed streaks along the ship axis
	nz = n.new("ShaderNodeTexNoise")
	nz.inputs["Scale"].default_value = 1.0
	nz.inputs["Detail"].default_value = 4.0
	mp = n.new("ShaderNodeMapping")
	mp.inputs["Scale"].default_value = (30.0, 1.5, 30.0)
	L.new(comb.outputs[0], mp.inputs["Vector"])
	L.new(mp.outputs[0], nz.inputs["Vector"])
	nr = n.new("ShaderNodeMapRange")
	nr.inputs["To Min"].default_value = 0.9
	nr.inputs["To Max"].default_value = 1.08
	L.new(nz.outputs["Fac"], nr.inputs["Value"])
	mul = n.new("ShaderNodeMix")
	mul.data_type = "RGBA"
	mul.blend_type = "MULTIPLY"
	mul.inputs["Factor"].default_value = 1.0
	L.new(br.outputs["Color"], mul.inputs["A"])
	mul.inputs["B"].default_value = (*base, 1)
	mul2 = n.new("ShaderNodeVectorMath")
	mul2.operation = "SCALE"
	L.new(mul.outputs["Result"], mul2.inputs[0])
	L.new(nr.outputs["Result"], mul2.inputs["Scale"])
	L.new(mul2.outputs[0], bs.inputs["Base Color"])
	rr = n.new("ShaderNodeMapRange")
	rr.inputs["To Min"].default_value = rough * 0.8
	rr.inputs["To Max"].default_value = rough * 1.25
	L.new(nz.outputs["Fac"], rr.inputs["Value"])
	L.new(rr.outputs["Result"], bs.inputs["Roughness"])
	bs.inputs["Metallic"].default_value = metallic
	bs.inputs["Coat Weight"].default_value = coat
	bs.inputs["Coat Roughness"].default_value = 0.1
	bs.inputs["Anisotropic"].default_value = 0.35
	tg = n.new("ShaderNodeTangent")
	tg.direction_type = "RADIAL"
	tg.axis = "X"
	L.new(tg.outputs["Tangent"], bs.inputs["Tangent"])
	return m


def mat_glass(name: str, tint, glow: float = 0.0) -> bpy.types.Material:
	"""Dark glossy canopy; slightly lighter towards the front (object +Y) plus optional inner tint."""
	m = bpy.data.materials.new(name)
	nt, bs = _principled(m)
	bs.inputs["Base Color"].default_value = (0.012, 0.018, 0.03, 1)
	bs.inputs["Metallic"].default_value = 0.0
	bs.inputs["Roughness"].default_value = 0.06
	bs.inputs["Coat Weight"].default_value = 1.0
	bs.inputs["Coat Roughness"].default_value = 0.03
	bs.inputs["Specular IOR Level"].default_value = 0.8
	bs.inputs["Emission Color"].default_value = (*tint, 1)
	bs.inputs["Emission Strength"].default_value = glow
	return m


def mat_plume(name: str, color, strength: float, length: float, fade_pow: float = 1.6) -> bpy.types.Material:
	"""Soft exhaust: emission fading along object -Y (0 at origin -> 1 at -length) and at grazing edges."""
	m = bpy.data.materials.new(name)
	nt = _node_tree(m)
	n, L = nt.nodes, nt.links
	n.clear()
	tc = n.new("ShaderNodeTexCoord")
	sep = n.new("ShaderNodeSeparateXYZ")
	L.new(tc.outputs["Object"], sep.inputs[0])
	t = n.new("ShaderNodeMapRange")
	t.inputs["From Min"].default_value = 0.0
	t.inputs["From Max"].default_value = -length
	t.inputs["To Min"].default_value = 1.0
	t.inputs["To Max"].default_value = 0.0
	L.new(sep.outputs["Y"], t.inputs["Value"])
	pw = n.new("ShaderNodeMath")
	pw.operation = "POWER"
	pw.inputs[1].default_value = fade_pow
	L.new(t.outputs["Result"], pw.inputs[0])
	lw = n.new("ShaderNodeLayerWeight")
	lw.inputs["Blend"].default_value = 0.5
	inv = n.new("ShaderNodeMath")
	inv.operation = "SUBTRACT"
	inv.inputs[0].default_value = 1.0
	L.new(lw.outputs["Facing"], inv.inputs[1])
	pw2 = n.new("ShaderNodeMath")
	pw2.operation = "POWER"
	pw2.inputs[1].default_value = 1.5
	L.new(inv.outputs[0], pw2.inputs[0])
	fac = n.new("ShaderNodeMath")
	fac.operation = "MULTIPLY"
	L.new(pw.outputs[0], fac.inputs[0])
	L.new(pw2.outputs[0], fac.inputs[1])
	em = n.new("ShaderNodeEmission")
	em.inputs["Color"].default_value = (*color, 1)
	em.inputs["Strength"].default_value = strength
	tr = n.new("ShaderNodeBsdfTransparent")
	mix = n.new("ShaderNodeMixShader")
	L.new(fac.outputs[0], mix.inputs["Fac"])
	L.new(tr.outputs[0], mix.inputs[1])
	L.new(em.outputs[0], mix.inputs[2])
	out = n.new("ShaderNodeOutputMaterial")
	L.new(mix.outputs[0], out.inputs[0])
	return m


# ------------------------------------------------------------------------------------------------
# Geometry
# ------------------------------------------------------------------------------------------------
def _link(ob: bpy.types.Object) -> bpy.types.Object:
	bpy.context.scene.collection.objects.link(ob)
	return ob


def _finish_bmesh(name: str, bm: bmesh.types.BMesh, mats, smooth: bool) -> bpy.types.Object:
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	for p in me.polygons:
		p.use_smooth = smooth
	for mt in mats:
		me.materials.append(mt)
	ob = bpy.data.objects.new(name, me)
	return _link(ob)


def _mirror_poly(poly):
	return [(-x, y) for (x, y) in reversed(poly)]


def slab(name: str, polys, zb: float, zt: float, mat, bevel: float = 0.1, segs: int = 3,
		mirror: bool = False, profile: float = 0.5, angle: float = 35.0, loc=(0, 0, 0)) -> bpy.types.Object:
	"""Extruded 2-D polygon(s) (x, y) between zb and zt with rounded (beveled) edges.
	`polys` is one polygon or a list of polygons; `mirror` adds the x-mirrored copy of each."""
	if polys and isinstance(polys[0][0], (int, float)):
		polys = [polys]
	all_polys = list(polys)
	if mirror:
		all_polys += [_mirror_poly(p) for p in polys]
	bm = bmesh.new()
	for poly in all_polys:
		vs = [bm.verts.new((x, y, zb)) for (x, y) in poly]
		f = bm.faces.new(vs)
		ret = bmesh.ops.extrude_face_region(bm, geom=[f])
		vx = [e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert)]
		bmesh.ops.translate(bm, vec=(0, 0, zt - zb), verts=vx)
	ob = _finish_bmesh(name, bm, [mat] if mat else [], True)
	ob.location = loc
	if bevel > 0:
		md = ob.modifiers.new("bevel", "BEVEL")
		md.width = bevel
		md.segments = segs
		md.limit_method = "ANGLE"
		md.angle_limit = math.radians(angle)
		md.profile = profile
		md.use_clamp_overlap = True
		md.harden_normals = True
		md.miter_outer = "MITER_ARC"
	return ob


def loft(name: str, stations, mats, n: int = 40, x: float = 0.0, cap_front: int = 0, cap_back: int = 0,
		smooth: bool = True, mirror: bool = False) -> bpy.types.Object:
	"""Lofted body along Y. stations: (y, half_w, z_bot, z_top, exponent[, mat_index]) from front to back.
	Cross-sections are super-ellipses (exponent 2 = ellipse, larger = boxier). mat_index applies to the
	faces between this station and the next. cap_front/cap_back: material index of the end caps (-1 = open)."""
	bm = bmesh.new()
	uvl = bm.loops.layers.uv.new("UVMap")
	xs = [x, -x] if (mirror and x != 0.0) else [x]
	for cx in xs:
		rings = []
		for st in stations:
			y, hw, zb, zt, p = st[:5]
			zc = 0.5 * (zb + zt)
			hh = 0.5 * (zt - zb)
			ring = []
			for i in range(n):
				t = 2.0 * math.pi * i / n
				c, s = math.cos(t), math.sin(t)
				px = hw * math.copysign(abs(c) ** (2.0 / p), c)
				pz = zc + hh * math.copysign(abs(s) ** (2.0 / p), s)
				ring.append(bm.verts.new((cx + px, y, pz)))
			rings.append(ring)
		y0, y1 = stations[0][0], stations[-1][0]
		span = (y0 - y1) if abs(y0 - y1) > 1e-6 else 1.0
		for k in range(len(rings) - 1):
			mi = stations[k][5] if len(stations[k]) > 5 else 0
			a, b = rings[k], rings[k + 1]
			ua, ub = (y0 - stations[k][0]) / span, (y0 - stations[k + 1][0]) / span
			for i in range(n):
				j = (i + 1) % n
				f = bm.faces.new((a[i], a[j], b[j], b[i]))
				f.material_index = mi
				f.smooth = smooth
				va, vb = i / n, (i + 1) / n
				for loop, uv in zip(f.loops, ((ua, va), (ua, vb), (ub, vb), (ub, va))):
					loop[uvl].uv = uv
		for cap, ring, st in ((cap_front, rings[0], stations[0]), (cap_back, rings[-1], stations[-1])):
			if cap < 0:
				continue
			if st[1] < 1e-4:
				continue
			c = bm.verts.new((cx, st[0], 0.5 * (st[2] + st[3])))
			for i in range(n):
				f = bm.faces.new((ring[i], ring[(i + 1) % n], c))
				f.material_index = cap
				f.smooth = False
	bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	for mt in (mats if isinstance(mats, (list, tuple)) else [mats]):
		me.materials.append(mt)
	ob = bpy.data.objects.new(name, me)
	return _link(ob)


def tube_y(name: str, x: float, z: float, y0: float, y1: float, r0: float, r1: float | None = None,
		mats=None, n: int = 32, mirror: bool = False, caps: int = 0) -> bpy.types.Object:
	"""Cylinder / cone along Y (y0 front, y1 back)."""
	r1 = r0 if r1 is None else r1
	st = [(y0, r0, z - r0, z + r0, 2.0, 0), (y1, r1, z - r1, z + r1, 2.0, 0)]
	return loft(name, st, mats, n=n, x=x, cap_front=caps, cap_back=caps, mirror=mirror)


def nozzle(name: str, x: float, z: float, y_front: float, length: float, r_out: float, mats,
		mirror: bool = False, n: int = 36) -> bpy.types.Object:
	"""Engine bell along -Y: mats = [shell, inner_dark, hot_core]. Inner core faces -Y (towards exhaust)."""
	y0, y1 = y_front, y_front - length
	ri = r_out * 0.72
	st = [
		(y0, r_out * 0.86, z - r_out * 0.86, z + r_out * 0.86, 2.0, 0),
		(y0 - length * 0.35, r_out * 0.95, z - r_out * 0.95, z + r_out * 0.95, 2.0, 0),
		(y1, r_out, z - r_out, z + r_out, 2.0, 0),
		(y1 - 0.0001, ri, z - ri, z + ri, 2.0, 1),
		(y1 + length * 0.55, ri * 0.8, z - ri * 0.8, z + ri * 0.8, 2.0, 1),
	]
	return loft(name, st, mats, n=n, x=x, cap_front=0, cap_back=2, mirror=mirror)


def ellipsoid(name: str, loc, size, mat, segs: int = 32, rings: int = 16) -> bpy.types.Object:
	bm = bmesh.new()
	bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
	for v in bm.verts:
		v.co.x = v.co.x * size[0] + loc[0]
		v.co.y = v.co.y * size[1] + loc[1]
		v.co.z = v.co.z * size[2] + loc[2]
	return _finish_bmesh(name, bm, [mat] if mat else [], True)


def world_bbox(objs):
	mn = Vector((1e9, 1e9, 1e9))
	mx = Vector((-1e9, -1e9, -1e9))
	dg = bpy.context.evaluated_depsgraph_get()
	for ob in objs:
		if ob.type != "MESH":
			continue
		ev = ob.evaluated_get(dg)
		me = ev.to_mesh()
		for v in me.vertices:
			p = ob.matrix_world @ v.co
			mn = Vector((min(mn.x, p.x), min(mn.y, p.y), min(mn.z, p.z)))
			mx = Vector((max(mx.x, p.x), max(mx.y, p.y), max(mx.z, p.z)))
		ev.to_mesh_clear()
	return mn, mx


def shift_objects(objs, dx: float, dy: float) -> None:
	for ob in objs:
		ob.location.x += dx
		ob.location.y += dy


def _airfoil(v: float) -> float:
	"""Normalised thickness distribution (max 1 at ~30 % chord, 0 at both edges)."""
	t = 0.2969 * math.sqrt(max(v, 0.0)) - 0.126 * v - 0.3516 * v * v + 0.2843 * v ** 3 - 0.1036 * v ** 4
	return max(t, 0.0) / 0.0600


def wing(name: str, root_le, root_te, tip_le, tip_te, zb: float, t_root: float, t_tip: float, mats,
		mirror: bool = False, edge: float = 0.05, nu: int = 14, nv: int = 18, tip_round: float = 0.0,
		z_tip: float = 0.0) -> bpy.types.Object:
	"""Parametric wing panel with an airfoil top (chord-wise light gradient) and flat bottom.
	Corners are (x, y). UV: u = span (0 root -> 1 tip), v = chord (0 leading -> 1 trailing edge).
	z_tip lifts the tip (dihedral). tip_round > 0 thins the outer tip so it reads rounded."""
	bm = bmesh.new()
	uvl = bm.loops.layers.uv.new("UVMap")
	sides = [1.0, -1.0] if mirror else [1.0]
	for sx in sides:
		grid_t, grid_b = [], []
		for iu in range(nu + 1):
			u = iu / nu
			le = (root_le[0] + (tip_le[0] - root_le[0]) * u, root_le[1] + (tip_le[1] - root_le[1]) * u)
			te = (root_te[0] + (tip_te[0] - root_te[0]) * u, root_te[1] + (tip_te[1] - root_te[1]) * u)
			T = t_root + (t_tip - t_root) * u
			if tip_round > 0.0:
				T *= math.sqrt(max(0.0, 1.0 - (u ** (1.0 / max(tip_round, 1e-3))) ** 6)) if u > 0 else 1.0
			z0 = zb + z_tip * u
			rt, rb = [], []
			for iv in range(nv + 1):
				v = iv / nv
				# cosine spacing: more rows near the edges
				vv = 0.5 - 0.5 * math.cos(math.pi * v)
				x = le[0] + (te[0] - le[0]) * vv
				y = le[1] + (te[1] - le[1]) * vv
				zt = z0 + edge + T * _airfoil(vv)
				rt.append(bm.verts.new((sx * x, y, zt)))
				rb.append(bm.verts.new((sx * x, y, z0)))
			grid_t.append(rt)
			grid_b.append(rb)
		def vparam(iv):
			return 0.5 - 0.5 * math.cos(math.pi * iv / nv)
		for iu in range(nu):
			for iv in range(nv):
				a, b = grid_t[iu][iv], grid_t[iu + 1][iv]
				c, d = grid_t[iu + 1][iv + 1], grid_t[iu][iv + 1]
				f = bm.faces.new((a, b, c, d))
				f.smooth = True
				uvs = ((iu / nu, vparam(iv)), ((iu + 1) / nu, vparam(iv)), ((iu + 1) / nu, vparam(iv + 1)),
					(iu / nu, vparam(iv + 1)))
				for loop, uv in zip(f.loops, uvs):
					loop[uvl].uv = uv
				a, b = grid_b[iu][iv], grid_b[iu + 1][iv]
				c, d = grid_b[iu + 1][iv + 1], grid_b[iu][iv + 1]
				f = bm.faces.new((d, c, b, a))
				f.smooth = False
		# rims
		for iu in range(nu):
			for iv in (0, nv):
				f = bm.faces.new((grid_t[iu][iv], grid_b[iu][iv], grid_b[iu + 1][iv], grid_t[iu + 1][iv]))
				f.smooth = False
		for iu in (0, nu):
			for iv in range(nv):
				f = bm.faces.new((grid_t[iu][iv], grid_t[iu][iv + 1], grid_b[iu][iv + 1], grid_b[iu][iv]))
				f.smooth = False
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	for mt in (mats if isinstance(mats, (list, tuple)) else [mats]):
		me.materials.append(mt)
	ob = bpy.data.objects.new(name, me)
	return _link(ob)


# ------------------------------------------------------------------------------------------------
# UV driven "part" material: panel lines + paint zones + emissive zones
# ------------------------------------------------------------------------------------------------
class _NB:
	"""Tiny node-building helper."""

	def __init__(self, nt):
		self.nt = nt
		self.n = nt.nodes
		self.L = nt.links

	def val(self, x):
		return x

	def _in(self, node, idx, x):
		if isinstance(x, (int, float)):
			node.inputs[idx].default_value = float(x)
		else:
			self.L.new(x, node.inputs[idx])

	def math(self, op, a, b=0.0, clamp=False):
		m = self.n.new("ShaderNodeMath")
		m.operation = op
		m.use_clamp = clamp
		self._in(m, 0, a)
		self._in(m, 1, b)
		return m.outputs[0]

	def smooth_step(self, x, e0, e1):
		m = self.n.new("ShaderNodeMapRange")
		m.interpolation_type = "SMOOTHSTEP"
		self._in(m, 0, x)
		m.inputs["From Min"].default_value = e0
		m.inputs["From Max"].default_value = e1
		return m.outputs["Result"]

	def mix_rgb(self, fac, a, b):
		m = self.n.new("ShaderNodeMix")
		m.data_type = "RGBA"
		if isinstance(fac, (int, float)):
			m.inputs["Factor"].default_value = fac
		else:
			self.L.new(fac, m.inputs["Factor"])
		for sock, v in ((m.inputs["A"], a), (m.inputs["B"], b)):
			if isinstance(v, tuple):
				sock.default_value = (*v[:3], 1.0)
			else:
				self.L.new(v, sock)
		return m.outputs["Result"]

	def mix_f(self, fac, a, b):
		# a + (b - a) * fac
		d = self.math("SUBTRACT", b, a) if not (isinstance(a, float) and isinstance(b, float)) else (b - a)
		return self.math("ADD", a, self.math("MULTIPLY", d, fac)) if not isinstance(d, float) else \
			self.math("ADD", a, self.math("MULTIPLY", fac, d))


def mat_part(name: str, base, metallic: float = 0.7, rough: float = 0.3, coat: float = 0.35,
		u_lines=(), v_lines=(), line_w: float = 0.012, line_dark: float = 0.5, zones=(), emit_zones=(),
		brushed: bool = True, grad=None) -> bpy.types.Material:
	"""Principled material driven by the mesh UVs.
	zones: (u0, u1, v0, v1, color, metallic, roughness) painted rectangles (later ones on top).
	emit_zones: (u0, u1, v0, v1, color, strength).
	grad: (axis 'u'|'v', k0, k1) multiplies the base colour from k0 (at 0) to k1 (at 1)."""
	m = bpy.data.materials.new(name)
	nt, bs = _principled(m)
	B = _NB(nt)
	uvn = nt.nodes.new("ShaderNodeUVMap")
	uvn.uv_map = "UVMap"
	sep = nt.nodes.new("ShaderNodeSeparateXYZ")
	B.L.new(uvn.outputs["UV"], sep.inputs[0])
	U, V = sep.outputs["X"], sep.outputs["Y"]
	col = (*base,)
	met = float(metallic)
	rgh = float(rough)
	col_s = None

	def box(u0, u1, v0, v1, soft=0.004):
		a = B.math("MULTIPLY", B.smooth_step(U, u0 - soft, u0 + soft), B.math("SUBTRACT", 1.0, B.smooth_step(U, u1 - soft, u1 + soft)))
		b = B.math("MULTIPLY", B.smooth_step(V, v0 - soft, v0 + soft), B.math("SUBTRACT", 1.0, B.smooth_step(V, v1 - soft, v1 + soft)))
		return B.math("MULTIPLY", a, b)

	col_s = B.mix_rgb(0.0, col, col)
	met_s = B.math("ADD", met, 0.0)
	rgh_s = B.math("ADD", rgh, 0.0)
	for (u0, u1, v0, v1, zc, zm, zr) in zones:
		mk = box(u0, u1, v0, v1)
		col_s = B.mix_rgb(mk, col_s, tuple(zc))
		met_s = B.math("ADD", met_s, B.math("MULTIPLY", mk, B.math("SUBTRACT", zm, met_s)))
		rgh_s = B.math("ADD", rgh_s, B.math("MULTIPLY", mk, B.math("SUBTRACT", zr, rgh_s)))
	for (u0, u1, v0, v1, _ec, _es) in emit_zones:
		# emissive strips sit on a black base so their colour stays saturated
		mk = box(u0 - 0.004, u1 + 0.004, v0 - 0.006, v1 + 0.006)
		col_s = B.mix_rgb(mk, col_s, (0.015, 0.015, 0.02))
		met_s = B.math("MULTIPLY", met_s, B.math("SUBTRACT", 1.0, mk))
	# panel lines
	line = None
	for axis, lines in ((U, u_lines), (V, v_lines)):
		for p in lines:
			d = B.math("ABSOLUTE", B.math("SUBTRACT", axis, p))
			mk = B.math("SUBTRACT", 1.0, B.smooth_step(d, line_w * 0.35, line_w))
			line = mk if line is None else B.math("MAXIMUM", line, mk)
	shade = 1.0
	if line is not None:
		shade = B.math("SUBTRACT", 1.0, B.math("MULTIPLY", line, line_dark))
	if grad is not None:
		ax = U if grad[0] == "u" else V
		g = B.math("ADD", grad[1], B.math("MULTIPLY", ax, grad[2] - grad[1]))
		shade = B.math("MULTIPLY", shade, g) if not isinstance(shade, float) else g
	if brushed:
		tc = nt.nodes.new("ShaderNodeTexCoord")
		mp = nt.nodes.new("ShaderNodeMapping")
		mp.inputs["Scale"].default_value = (2.0, 40.0, 1.0)
		B.L.new(uvn.outputs["UV"], mp.inputs["Vector"])
		nz = nt.nodes.new("ShaderNodeTexNoise")
		nz.inputs["Scale"].default_value = 3.0
		nz.inputs["Detail"].default_value = 3.0
		B.L.new(mp.outputs[0], nz.inputs["Vector"])
		nf = B.smooth_step(nz.outputs["Fac"], 0.2, 0.8)
		k = B.math("ADD", 0.93, B.math("MULTIPLY", nf, 0.12))
		shade = B.math("MULTIPLY", shade, k) if not isinstance(shade, float) else k
		rgh_s = B.math("MULTIPLY", rgh_s, B.math("ADD", 0.85, B.math("MULTIPLY", nf, 0.3)))
	if not isinstance(shade, float):
		sc = nt.nodes.new("ShaderNodeVectorMath")
		sc.operation = "SCALE"
		B.L.new(col_s, sc.inputs[0])
		B.L.new(shade, sc.inputs["Scale"])
		B.L.new(sc.outputs[0], bs.inputs["Base Color"])
	else:
		B.L.new(col_s, bs.inputs["Base Color"])
	B.L.new(met_s, bs.inputs["Metallic"])
	B.L.new(rgh_s, bs.inputs["Roughness"])
	bs.inputs["Coat Weight"].default_value = coat
	bs.inputs["Coat Roughness"].default_value = 0.08
	if line is not None:
		# panel seams are less glossy
		B.L.new(B.math("SUBTRACT", coat, B.math("MULTIPLY", line, coat)), bs.inputs["Coat Weight"])
	if emit_zones:
		em = None
		for (u0, u1, v0, v1, ec, es) in emit_zones:
			mk = box(u0, u1, v0, v1, 0.003)
			cc = B.mix_rgb(mk, (0, 0, 0), tuple(c * es for c in ec))
			if em is None:
				em = cc
			else:
				add = nt.nodes.new("ShaderNodeVectorMath")
				add.operation = "ADD"
				B.L.new(em, add.inputs[0])
				B.L.new(cc, add.inputs[1])
				em = add.outputs[0]
		B.L.new(em, bs.inputs["Emission Color"])
		bs.inputs["Emission Strength"].default_value = 1.0
	return m
