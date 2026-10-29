"""Planet Protector Steam library artwork - the game's models, set up for the key art (bpy, Cycles CPU).

  demon   the crowned Earth demon of the game (enemies_designs.earth + the game's WingRig) with key-art
          materials: glossy black skin, dark leathery membrane (deep red when backlit), dark bronze crown,
          glowing eyes in the game's EYE_COLOR_BLACK. As in the game's final levels 19/20 only the eyes
          glow; no veins, sigil or crown jewels (tests/test_audit_data.gd: black Earth enemies emit only
          at the eyes). Geometry units are the game's (1 unit = 1 game px, creature faces -Y, Z up).
  ship    the Interceptor (ships_models.build_interceptor with its Kit materials) + exhaust plumes.
          Units: 1 Blender unit = 10 sprite px; nose +Y, top +Z (ships_lib.py).
  earth   the game's Earth (planets.py materials + planets_textures.py textures) rendered through an
          orthographic window in disk units (sphere radius 1, +x right, +y up), so only the visible part
          of a very large disk is rendered. Large renders get procedural sub-texel cloud detail.
          The atmosphere is painted analytically in the 2-D step (like planets_post.py does for the game).
"""
from __future__ import annotations

import math

import bpy
import numpy as np

import steam_keyart_bpy as K
import enemies_designs  # noqa: E402  (game: tools/blender)
import enemies_geom as G  # noqa: E402
import planets as PL  # noqa: E402  (bpy present -> no re-exec)
import ships_lib as SL  # noqa: E402
import ships_models as SM  # noqa: E402
from enemies import WIDTH_FACTOR, Ctx  # noqa: E402
from planets_config import PLANETS  # noqa: E402

EYE = (1.0, 0.28, 0.08)        # game: LevelData.EYE_COLOR_BLACK
EYE_HOT = (1.0, 0.62, 0.22)


# ================================================================================================
# demon
# ================================================================================================
def _eye_material(name: str, strength: float):
	"""Hot core, deeper orange rim (facing ramp), very bright so it blooms in post."""
	m = bpy.data.materials.new(name)
	nt = K._tree(m)
	n, L = nt.nodes, nt.links
	n.clear()
	lw = n.new("ShaderNodeLayerWeight")
	lw.inputs["Blend"].default_value = 0.45
	mix = n.new("ShaderNodeMix")
	mix.data_type = "RGBA"
	L.new(lw.outputs["Facing"], mix.inputs["Factor"])
	mix.inputs["A"].default_value = (*EYE_HOT, 1)
	mix.inputs["B"].default_value = (*EYE, 1)
	em = n.new("ShaderNodeEmission")
	L.new(mix.outputs["Result"], em.inputs["Color"])
	em.inputs["Strength"].default_value = strength
	out = n.new("ShaderNodeOutputMaterial")
	L.new(em.outputs[0], out.inputs[0])
	return m


def membrane_material(translucent: float, tint=(0.5, 0.07, 0.02), spec: float = 0.5, rough: float = 0.55):
	"""Dark glossy leather; with translucent > 0 light from behind shines through it (deep red)."""
	m = K.principled("ka_membrane", (0.02, 0.012, 0.013), rough=rough, spec=spec, coat=0.05, coat_rough=0.3)
	K.add_noise_bump(m, 6.0, 0.12, 0.3, 1.0, coords="UV")
	if translucent <= 0:
		return m
	nt = K._tree(m)
	n, L = nt.nodes, nt.links
	bs = n.get("Principled BSDF")
	out = n.get("Material Output")
	tr = n.new("ShaderNodeBsdfTranslucent")
	tr.inputs["Color"].default_value = (*tint, 1)
	# veining: darker where a cell edge is near, so the backlight is not a flat sheet
	tc = n.new("ShaderNodeTexCoord")
	vz = n.new("ShaderNodeTexVoronoi")
	vz.feature = "DISTANCE_TO_EDGE"
	vz.inputs["Scale"].default_value = 9.0
	L.new(tc.outputs["UV"], vz.inputs["Vector"])
	mr = n.new("ShaderNodeMapRange")
	mr.inputs["From Min"].default_value = 0.0
	mr.inputs["From Max"].default_value = 0.08
	mr.inputs["To Min"].default_value = 0.55
	mr.inputs["To Max"].default_value = 1.0
	L.new(vz.outputs["Distance"], mr.inputs["Value"])
	k = n.new("ShaderNodeMath")
	k.operation = "MULTIPLY"
	k.inputs[1].default_value = translucent
	L.new(mr.outputs["Result"], k.inputs[0])
	mix = n.new("ShaderNodeMixShader")
	L.new(k.outputs[0], mix.inputs["Fac"])
	L.new(bs.outputs[0], mix.inputs[1])
	L.new(tr.outputs[0], mix.inputs[2])
	L.new(mix.outputs[0], out.inputs["Surface"])
	return m


def demon_materials(eye: float = 14.0, throat: float = 3.0, skin_tint=(0.016, 0.015, 0.02),
		translucent: float = 0.0, membrane_tint=(0.5, 0.07, 0.02), membrane_spec: float = 0.5,
		membrane_rough: float = 0.55):
	m = {}
	m["skin"] = K.principled("ka_skin", skin_tint, rough=0.42, spec=0.6, coat=0.15, coat_rough=0.22)
	K.add_noise_bump(m["skin"], 0.35, 0.12, 0.3, 2.0)
	m["membrane"] = membrane_material(translucent, membrane_tint, membrane_spec, membrane_rough)
	m["bone"] = K.principled("ka_bone", (0.03, 0.028, 0.032), rough=0.3, spec=0.65, coat=0.3)
	m["horn"] = K.principled("ka_horn", (0.04, 0.034, 0.033), rough=0.28, spec=0.65, coat=0.2, coat_rough=0.18)
	K.add_noise_bump(m["horn"], 1.5, 0.08, 0.3, 2.0)
	m["claw"] = K.principled("ka_claw", (0.045, 0.04, 0.038), rough=0.34, spec=0.5, coat=0.08, coat_rough=0.3)
	m["armor"] = K.principled("ka_armor", (0.035, 0.034, 0.04), rough=0.24, spec=0.8, coat=0.4)
	m["gold"] = K.principled("ka_gold", (0.32, 0.2, 0.1), metallic=1.0, rough=0.28, coat=0.2)
	m["dark"] = K.principled("ka_dark", (0.004, 0.002, 0.002), rough=0.6, spec=0.2)
	m["eye"] = _eye_material("ka_eye", eye)
	# black Earth demons (levels 19/20) glow only at the eyes: jewels / sigil / veins stay dark material
	m["glow"] = m["gold"]
	m["glow_soft"] = K.emission("ka_throat", (1.0, 0.35, 0.08), throat)   # the open maw (fiery throat)
	m["sigil"] = m["skin"]
	m["vein"] = m["membrane"]
	return m


def build_demon(t: float = 0.0, mats=None, meta_res: float = 0.2, subdiv: int = 1):
	"""Builds the demon under an empty 'demon_root' (returned with ctx, rigs). t = wing flap phase
	(0 = wings up, 0.5 = down)."""
	mats = mats or demon_materials()
	root = bpy.data.objects.new("demon_root", None)
	bpy.context.scene.collection.objects.link(root)
	ctx = Ctx("earth", mats, root)
	membrane = mats["membrane"]
	wing_specs = enemies_designs.DESIGNS["earth"](ctx)
	# the design swaps in its own (white, channel-pack) membrane: put the key-art one back
	ctx.mats["membrane"] = membrane
	# the "glow_soft" parts: the first one is the throat, the rest (chest sigil) becomes plain skin
	soft = [ob for ob in ctx.objects if ob.data.materials and ob.data.materials[0].name.startswith("ka_throat")]
	for ob in soft[1:]:
		ob.data.materials[0] = mats["skin"]
	ctx.throat_objects = soft[:1]    # anchors for the 2-D step (mouth, chest = where the laser hits)
	ctx.sigil_objects = soft[1:]
	ctx.eye_objects = [ob for ob in ctx.objects if ob.data.materials and ob.data.materials[0] == mats["eye"]]
	for mb in ctx.metas:
		mb.mb.render_resolution = meta_res
		mb.mb.resolution = meta_res
	wf = WIDTH_FACTOR["earth"]
	rigs = [G.WingRig(spec, mats, root) for spec in wing_specs]
	frames = 16
	main = rigs[0]
	main.max_extent(frames)
	main.fit_span(45.0 * wf, frames)
	for rig in rigs:
		rig.build()
		rig.update(t)
	if subdiv > 0:
		for ob in bpy.context.scene.objects:
			if ob.parent is root and ob.type == "MESH" and "membrane" in ob.name and not ob.modifiers.get("sub"):
				md = ob.modifiers.new("sub", "SUBSURF")
				md.levels = subdiv
				md.render_levels = subdiv
	return root, ctx, rigs


def pose(root, pitch_deg: float = 25.0, roll_deg: float = 0.0, yaw_deg: float = 0.0, loc=(0.0, 0.0, 0.0),
		scale: float = 1.0) -> None:
	"""pitch > 0 tips the head towards the camera (-Y): a dive at the viewer."""
	root.rotation_mode = "XYZ"
	root.rotation_euler = (math.radians(pitch_deg), math.radians(yaw_deg), math.radians(roll_deg))
	root.location = loc
	root.scale = (scale, scale, scale)


def bbox_points(root):
	"""World-space vertices of everything under root (for framing)."""
	bpy.context.view_layer.update()
	dg = bpy.context.evaluated_depsgraph_get()
	pts = []
	for ob in bpy.context.scene.objects:
		if ob.parent is not root or ob.type not in ("MESH", "META"):
			continue
		ev = ob.evaluated_get(dg)
		try:
			me = ev.to_mesh()
		except RuntimeError:
			continue
		if me is None:
			continue
		M = ob.matrix_world
		co = np.empty(len(me.vertices) * 3, np.float32)
		me.vertices.foreach_get("co", co)
		co = co.reshape(-1, 3)
		if len(co):
			co = co[:: max(1, len(co) // 4000)]
			hom = np.c_[co, np.ones(len(co))] @ np.array(M).T
			pts.append(hom[:, :3])
		ev.to_mesh_clear()
	return np.vstack(pts) if pts else np.zeros((0, 3))


# ================================================================================================
# ship
# ================================================================================================
def build_ship(key: str = "interceptor"):
	"""Returns (kit, objects, plumes, muzzle) with the ship centred on its bbox (x, y) like ships.py."""
	kit = SM.Kit(key)
	objs, plumes = SM.BUILDERS[key](kit)
	mn, mx = SL.world_bbox(objs)
	dx, dy = -0.5 * (mn.x + mx.x), -0.5 * (mn.y + mx.y)
	SL.shift_objects(objs, dx, dy)
	plumes = [(px + dx, py + dy, pz, pr) for px, py, pz, pr in plumes]
	muzzle = (0.0, 4.95 + dy, 0.58)   # build_interceptor: muzzle tube y 4.78..4.95, z 0.58
	return kit, objs, plumes, muzzle


def parent_all(objs, name="ship_root"):
	root = bpy.data.objects.new(name, None)
	bpy.context.scene.collection.objects.link(root)
	for ob in objs:
		ob.parent = root
	return root


def add_plumes(kit, plumes, root, length: float = 3.2):
	out = []
	for i, (px, py, pz, pr) in enumerate(plumes):
		for ob in SM.plume("plume%d" % i, px, py, pz, pr, kit.exhaust, length=length):
			ob.parent = root
			out.append(ob)
	return out


# ================================================================================================
# earth
# ================================================================================================
def add_cloud_detail(mat, scale: float, amount: float, contrast: float = 1.2) -> None:
	"""Procedural sub-texel detail for the game's cloud shell when a disk thousands of px wide magnifies
	the equirect texture: fbm noise modulates the coverage where clouds are thin (their edges), cores
	and clear sky stay as painted; a mild contrast curve crisps the edges. scale: noise frequency in
	sphere units (features ~1/scale), amount: modulation strength."""
	nt = mat.node_tree
	n, L = nt.nodes, nt.links
	mix = next(nd for nd in n if nd.type == "MIX_SHADER")
	link = mix.inputs["Fac"].links[0]
	cov_out = link.from_socket
	nt.links.remove(link)
	tc = n.new("ShaderNodeTexCoord")
	nz = n.new("ShaderNodeTexNoise")
	nz.inputs["Scale"].default_value = scale
	nz.inputs["Detail"].default_value = 9.0
	nz.inputs["Roughness"].default_value = 0.62
	nz.inputs["Distortion"].default_value = 0.35
	L.new(tc.outputs["Object"], nz.inputs["Vector"])

	def math_node(op, a=None, b=None):
		m = n.new("ShaderNodeMath")
		m.operation = op
		for i, v in enumerate((a, b)):
			if v is None:
				continue
			if isinstance(v, (int, float)):
				m.inputs[i].default_value = float(v)
			else:
				L.new(v, m.inputs[i])
		return m.outputs[0]

	cov = math_node("ADD", cov_out, 0.0)                       # colour -> float
	edge = math_node("MULTIPLY", math_node("MULTIPLY", cov, math_node("SUBTRACT", 1.0, cov)), 4.0)
	d = math_node("MULTIPLY", math_node("SUBTRACT", nz.outputs["Fac"], 0.5), amount * 2.0)
	c2 = math_node("ADD", cov, math_node("MULTIPLY", d, edge))
	c3 = math_node("ADD", math_node("MULTIPLY", math_node("SUBTRACT", c2, 0.5), contrast), 0.5)
	cl = n.new("ShaderNodeClamp")
	L.new(c3, cl.inputs["Value"])
	L.new(cl.outputs[0], mix.inputs["Fac"])


def render_earth(out_npy: str, tex_dir: str, r_px: float, window, view_lon: float, view_lat: float, roll: float,
		to_sun, samples: int = 64, sun_strength: float = 1.15, sun_color=(1.0, 0.97, 0.92),
		cloud_h: float | None = None, detail: float = 0.0, detail_px: float = 28.0, detail_contrast: float = 1.06):
	"""window = (x0, x1, y0, y1) in disk units (y up). Image px per unit = r_px.
	to_sun is in camera space: x right, y up, z towards the viewer."""
	x0, x1, y0, y1 = window
	w = int(round((x1 - x0) * r_px))
	h = int(round((y1 - y0) * r_px))
	sc = K.reset(w, h, samples=samples, adaptive=0.004, filter_width=1.2, bounces=4)
	cfg = dict(PLANETS["earth"])
	cfg.update({"view_lon": view_lon, "view_lat": view_lat, "roll": roll})
	m = PL.planet_matrix(cfg)
	PL.add_sphere(sc, "earth", 1.0, PL.make_planet_material("earth", cfg, tex_dir), m)
	# the game uses a 0.006 R cloud shell (fine for a 640 px planet); seen at the limb of a disk several
	# thousand px wide that shell floats visibly above the horizon, so big Earths use less
	shell = cfg["clouds"] if cloud_h is None else cloud_h
	cmat = PL.make_cloud_material("earth", cfg, tex_dir)
	if detail > 0:
		add_cloud_detail(cmat, r_px / detail_px, detail, detail_contrast)
	PL.add_sphere(sc, "earth_clouds", 1.0 + shell, cmat, m)
	# camera: Blender world x right, z up, camera at -Y looking +Y (as planets.py)
	cam = bpy.data.cameras.new("cam")
	cam.type = "ORTHO"
	cam.sensor_fit = "HORIZONTAL" if w >= h else "VERTICAL"
	cam.ortho_scale = max(x1 - x0, y1 - y0)
	cam_ob = bpy.data.objects.new("cam", cam)
	sc.collection.objects.link(cam_ob)
	cam_ob.location = (0.5 * (x0 + x1), -20.0, 0.5 * (y0 + y1))
	cam_ob.rotation_euler = (math.pi / 2, 0.0, 0.0)
	cam.clip_start = 1.0
	cam.clip_end = 60.0
	sc.camera = cam_ob
	world = bpy.data.worlds.new("w")
	sc.world = world
	world.use_nodes = True
	bg = world.node_tree.nodes["Background"]
	bg.inputs[0].default_value = (0.012, 0.014, 0.02, 1.0)
	bg.inputs[1].default_value = 1.0
	sx, sy, sz = to_sun
	# camera space (x right, y up, z to viewer) -> Blender (x right, y away, z up)
	PL.add_sun(sc, "key", (sx, -sz, sy), sun_strength * math.pi, sun_color, 1.5)
	K.render_npy(out_npy)
	return {"r_px": r_px, "window": list(window), "size": [w, h], "center_px": [(-x0) * r_px, (y1) * r_px]}
