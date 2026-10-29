"""Planet Protector Steam library artwork - shared Blender helpers (bpy 5.2, Cycles CPU).

Imported by steam_keyart_models.py / steam_keyart_render.py inside the Blender python. The game's own
art pipeline in tools/blender (ships_lib / ships_models / enemies_* / planets*) is imported as modules,
so ships, demons and the Earth are exactly the game's models and textures; only camera, pose,
lighting and (for the demons) the materials are new.

Every element is rendered on its own with a transparent film into a scene-linear, premultiplied
float RGBA .npy (rows top -> bottom); steam_keyart_compose.py (system python3) composes them.
"""
from __future__ import annotations

import math
import os
import sys

sys.dont_write_bytecode = True  # keep tools/blender free of __pycache__ from these runs

HERE = os.path.dirname(os.path.abspath(__file__))
# the game repo (default: this file lives in <repo>/tools/blender); PP_REPO overrides it
ROOT = os.environ.get("PP_REPO") or os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools", "blender")
for _p in (TOOLS, HERE):
	if _p not in sys.path:
		sys.path.insert(0, _p)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402

THREADS = int(os.environ.get("ART_THREADS", "2"))


def log(*a):
	print("[steam_keyart]", *a, flush=True)


# ------------------------------------------------------------------------------------------------
# scene / render
# ------------------------------------------------------------------------------------------------
def reset(res_x: int, res_y: int, samples: int = 96, denoise: bool = True, bounces: int = 6,
		adaptive: float = 0.01, filter_width: float = 1.5) -> bpy.types.Scene:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	sc = bpy.context.scene
	sc.render.engine = "CYCLES"
	sc.cycles.device = "CPU"
	sc.cycles.samples = samples
	sc.cycles.use_adaptive_sampling = True
	sc.cycles.adaptive_threshold = adaptive
	sc.cycles.use_denoising = denoise
	if denoise:
		try:
			sc.cycles.denoiser = "OPENIMAGEDENOISE"
			sc.cycles.denoising_input_passes = "RGB_ALBEDO_NORMAL"
		except Exception:  # pragma: no cover
			pass
	sc.cycles.max_bounces = bounces
	sc.cycles.diffuse_bounces = 3
	sc.cycles.glossy_bounces = 4
	sc.cycles.transmission_bounces = 4
	sc.cycles.transparent_max_bounces = 16
	sc.cycles.caustics_reflective = False
	sc.cycles.caustics_refractive = False
	sc.cycles.sample_clamp_indirect = 6.0
	sc.cycles.filter_width = filter_width
	sc.render.threads_mode = "FIXED"
	sc.render.threads = THREADS
	sc.render.film_transparent = True
	sc.render.resolution_x = res_x
	sc.render.resolution_y = res_y
	sc.render.resolution_percentage = 100
	sc.view_settings.view_transform = "Standard"
	sc.view_settings.look = "None"
	sc.render.image_settings.file_format = "OPEN_EXR"
	sc.render.image_settings.color_mode = "RGBA"
	sc.render.image_settings.color_depth = "32"
	sc.render.use_persistent_data = False
	return sc


def render_npy(path: str) -> np.ndarray:
	"""Renders the active scene; stores premultiplied linear RGBA float32 (rows top -> bottom)."""
	sc = bpy.context.scene
	path = os.path.abspath(path)
	os.makedirs(os.path.dirname(path), exist_ok=True)
	exr = path[:-4] + ".exr"
	sc.render.filepath = exr
	bpy.ops.render.render(write_still=True)
	img = bpy.data.images.load(exr)
	w, h = img.size
	buf = np.empty(w * h * 4, dtype=np.float32)
	img.pixels.foreach_get(buf)
	bpy.data.images.remove(img)
	arr = buf.reshape(h, w, 4)[::-1].copy()
	np.save(path, arr)
	try:
		os.remove(exr)
	except OSError:
		pass
	log("wrote", path, arr.shape)
	return arr


def look_at(ob, target, up=(0.0, 0.0, 1.0), roll_deg: float = 0.0) -> None:
	"""Points object -Z at target with +Y towards `up` (camera convention), then rolls about the view axis."""
	loc = Vector(ob.location)
	d = (Vector(target) - loc).normalized()
	upv = Vector(up)
	x = d.cross(upv)
	if x.length < 1e-6:
		x = d.cross(Vector((0.0, 1.0, 0.0)))
	x.normalize()
	y = x.cross(d).normalized()
	m = Matrix((x, y, -d)).transposed()
	q = m.to_quaternion()
	if roll_deg:
		q = q @ Euler((0.0, 0.0, math.radians(roll_deg))).to_quaternion()
	ob.rotation_mode = "QUATERNION"
	ob.rotation_quaternion = q


def camera(name: str, loc, target, lens: float = 50.0, sensor: float = 36.0, up=(0.0, 0.0, 1.0),
		roll_deg: float = 0.0, clip=(0.1, 5000.0), ortho_scale: float | None = None):
	cam = bpy.data.cameras.new(name)
	cam.sensor_fit = "HORIZONTAL"
	cam.sensor_width = sensor
	if ortho_scale is not None:
		cam.type = "ORTHO"
		cam.ortho_scale = ortho_scale
	else:
		cam.lens = lens
	cam.clip_start, cam.clip_end = clip
	ob = bpy.data.objects.new(name, cam)
	bpy.context.scene.collection.objects.link(ob)
	ob.location = loc
	look_at(ob, target, up, roll_deg)
	bpy.context.scene.camera = ob
	return ob


def sun(name: str, to_light, strength: float, color=(1, 1, 1), angle_deg: float = 4.0, diffuse: bool = True,
		glossy: bool = True, shadow: bool = True, camera: bool = False) -> bpy.types.Object:
	"""Sun lamp; `to_light` points from the scene towards the light."""
	lt = bpy.data.lights.new(name, type="SUN")
	lt.energy = strength
	lt.color = color
	lt.angle = math.radians(angle_deg)
	lt.use_shadow = shadow
	ob = bpy.data.objects.new(name, lt)
	bpy.context.scene.collection.objects.link(ob)
	ob.rotation_euler = Vector(to_light).normalized().to_track_quat("Z", "Y").to_euler()
	ob.visible_diffuse = diffuse
	ob.visible_glossy = glossy
	ob.visible_camera = camera
	return ob


def _tree(idblock):
	if getattr(idblock, "node_tree", None) is None:
		idblock.use_nodes = True
	return idblock.node_tree


def gradient_world(stops, axis_dir=(0.0, 0.0, 1.0), strength: float = 1.0, camera_visible: bool = False):
	"""World = colour ramp over dot(view direction, axis_dir) mapped from [-1, 1] to [0, 1].
	stops: [(pos, (r, g, b)), ...]. Used for reflections / ambient only (camera-invisible)."""
	w = bpy.data.worlds.new("env")
	bpy.context.scene.world = w
	nt = _tree(w)
	n, L = nt.nodes, nt.links
	n.clear()
	tc = n.new("ShaderNodeTexCoord")
	dot = n.new("ShaderNodeVectorMath")
	dot.operation = "DOT_PRODUCT"
	dot.inputs[1].default_value = Vector(axis_dir).normalized()
	L.new(tc.outputs["Generated"], dot.inputs[0])
	mr = n.new("ShaderNodeMapRange")
	mr.inputs["From Min"].default_value = -1.0
	mr.inputs["From Max"].default_value = 1.0
	L.new(dot.outputs["Value"], mr.inputs["Value"])
	ramp = n.new("ShaderNodeValToRGB")
	cr = ramp.color_ramp
	cr.interpolation = "B_SPLINE"
	cr.elements[0].position = stops[0][0]
	cr.elements[0].color = (*stops[0][1], 1)
	cr.elements[1].position = stops[-1][0]
	cr.elements[1].color = (*stops[-1][1], 1)
	for p, c in stops[1:-1]:
		e = cr.elements.new(p)
		e.color = (*c, 1)
	L.new(mr.outputs["Result"], ramp.inputs["Fac"])
	bg = n.new("ShaderNodeBackground")
	bg.inputs["Strength"].default_value = strength
	L.new(ramp.outputs["Color"], bg.inputs["Color"])
	out = n.new("ShaderNodeOutputWorld")
	L.new(bg.outputs["Background"], out.inputs["Surface"])
	w.cycles_visibility.camera = camera_visible
	return w


def principled(name: str, base, metallic: float = 0.0, rough: float = 0.4, spec: float = 0.5, coat: float = 0.0,
		coat_rough: float = 0.1, emission=None, emit: float = 0.0, sheen: float = 0.0,
		sheen_tint=(1.0, 1.0, 1.0)) -> bpy.types.Material:
	m = bpy.data.materials.new(name)
	nt = _tree(m)
	bs = nt.nodes.get("Principled BSDF")
	bs.inputs["Base Color"].default_value = (*base, 1)
	bs.inputs["Metallic"].default_value = metallic
	bs.inputs["Roughness"].default_value = rough
	bs.inputs["Specular IOR Level"].default_value = spec
	bs.inputs["Coat Weight"].default_value = coat
	bs.inputs["Coat Roughness"].default_value = coat_rough
	if sheen > 0:
		bs.inputs["Sheen Weight"].default_value = sheen
		bs.inputs["Sheen Tint"].default_value = (*sheen_tint, 1)
	if emission is not None:
		bs.inputs["Emission Color"].default_value = (*emission, 1)
		bs.inputs["Emission Strength"].default_value = emit
	return m


def emission(name: str, color, strength: float) -> bpy.types.Material:
	m = bpy.data.materials.new(name)
	nt = _tree(m)
	nt.nodes.clear()
	em = nt.nodes.new("ShaderNodeEmission")
	em.inputs["Color"].default_value = (*color, 1)
	em.inputs["Strength"].default_value = strength
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	nt.links.new(em.outputs[0], out.inputs[0])
	return m


def add_noise_bump(mat, scale: float, strength: float, distance: float = 0.3, detail: float = 3.0,
		coords: str = "Object") -> None:
	nt = _tree(mat)
	n, L = nt.nodes, nt.links
	bs = n.get("Principled BSDF")
	tc = n.new("ShaderNodeTexCoord")
	nz = n.new("ShaderNodeTexNoise")
	nz.inputs["Scale"].default_value = scale
	nz.inputs["Detail"].default_value = detail
	nz.inputs["Roughness"].default_value = 0.55
	L.new(tc.outputs[coords], nz.inputs["Vector"])
	bp = n.new("ShaderNodeBump")
	bp.inputs["Strength"].default_value = strength
	bp.inputs["Distance"].default_value = distance
	L.new(nz.outputs["Fac"], bp.inputs["Height"])
	L.new(bp.outputs["Normal"], bs.inputs["Normal"])


def project(cam_ob, co) -> tuple[float, float, float]:
	"""World point -> (x, y) in normalised frame coords (0..1, y DOWN) and depth."""
	from bpy_extras.object_utils import world_to_camera_view
	v = world_to_camera_view(bpy.context.scene, cam_ob, Vector(co))
	return float(v.x), float(1.0 - v.y), float(v.z)


# ------------------------------------------------------------------------------------------------
# camera-space lighting + exact framing
# ------------------------------------------------------------------------------------------------
def cam_dir(cam_ob, v_cam) -> Vector:
	"""Camera space (x right, y up, z towards the viewer) -> world direction."""
	R = cam_ob.matrix_world.to_3x3().normalized()
	return (R @ Vector(v_cam)).normalized()


def cam_sun(cam_ob, name: str, to_light_cam, strength: float, color=(1, 1, 1), angle_deg: float = 4.0, **kw):
	return sun(name, tuple(cam_dir(cam_ob, to_light_cam)), strength, color, angle_deg, **kw)


def point_light(name: str, loc, power: float, color=(1, 1, 1), radius: float = 0.5, glossy: bool = True):
	lt = bpy.data.lights.new(name, type="POINT")
	lt.energy = power
	lt.color = color
	lt.shadow_soft_size = radius
	ob = bpy.data.objects.new(name, lt)
	bpy.context.scene.collection.objects.link(ob)
	ob.location = loc
	ob.visible_glossy = glossy
	return ob


def cam_world(cam_ob, stops, strength: float = 1.0, down_cam=(0.0, -1.0, 0.0)):
	"""Reflection/ambient environment whose ramp runs along a CAMERA-space direction (default: image down,
	i.e. the Earth below the scene). stops are over dot(dir, down) in [-1, 1] -> [0, 1]."""
	return gradient_world(stops, axis_dir=tuple(cam_dir(cam_ob, down_cam)), strength=strength)


def fit_frame(cam_ob, pts, width_px: int, margin: float = 0.04, max_h: int | None = None):
	"""Perspective camera already aimed roughly at the subject: sets lens, shift and resolution so the
	projected points fill the frame (plus a relative margin). Returns (res_x, res_y)."""
	sc = bpy.context.scene
	cam = cam_ob.data
	cam.sensor_fit = "HORIZONTAL"
	cam.shift_x = cam.shift_y = 0.0
	sc.render.resolution_x = sc.render.resolution_y = 1000
	bpy.context.view_layer.update()
	from bpy_extras.object_utils import world_to_camera_view
	uv = np.array([tuple(world_to_camera_view(sc, cam_ob, Vector(p)))[:2] for p in pts])
	u0, u1 = uv[:, 0].min(), uv[:, 0].max()
	v0, v1 = uv[:, 1].min(), uv[:, 1].max()   # v up
	fw, fh = (u1 - u0) * (1 + 2 * margin), (v1 - v0) * (1 + 2 * margin * (u1 - u0) / max(v1 - v0, 1e-6))
	uc, vc = 0.5 * (u0 + u1), 0.5 * (v0 + v1)
	cam.lens = cam.lens / fw
	rx = int(width_px)
	ry = int(round(width_px * fh / fw))
	if max_h and ry > max_h:
		k = max_h / ry
		rx, ry = int(rx * k), int(max_h)
	sc.render.resolution_x, sc.render.resolution_y = rx, ry
	big = max(rx, ry)
	cam.shift_x = (uc - 0.5) / fw * rx / big
	cam.shift_y = (vc - 0.5) / fw * rx / big
	bpy.context.view_layer.update()
	return rx, ry


def project_px(cam_ob, co):
	"""World point -> pixel (x right, y down) of the current render resolution."""
	sc = bpy.context.scene
	from bpy_extras.object_utils import world_to_camera_view
	v = world_to_camera_view(sc, cam_ob, Vector(co))
	return [float(v.x * sc.render.resolution_x), float((1.0 - v.y) * sc.render.resolution_y)]


def obj_center(ob) -> Vector:
	"""World-space centre of an object's evaluated bounding box."""
	bpy.context.view_layer.update()
	cs = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
	return sum(cs, Vector()) / 8.0
