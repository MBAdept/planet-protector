"""Background planets for Planet Protector (package art-planets, docs/SPEC.md §15, §16.3).

Pipeline (fully procedural, deterministic):
  1. planets_textures.py  (system python3: numpy/scipy/PIL) paints equirectangular textures.
  2. this script          (Blender as Python module, Cycles CPU) renders lit spheres (+ rings, clouds)
                          to linear float buffers.
  3. planets_post.py      (system python3) adds the atmosphere rim, tone-maps, crops and writes
                          game/assets/sprites/planets/<planet>.png + <planet>.json and the contact sheet.

Usage:
  <bpy-python> tools/blender/planets.py [planet ...] [--work=DIR] [--samples=N] [--force-tex] [--preview]
If started with a python that has no bpy, the script re-executes itself with $BPY_PYTHON
(default: the bpyenv python of this machine).
"""
from __future__ import annotations

import math
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DEFAULT_BPY = "/tmp/claude-0/-home-user/0a1ab13c-d1d4-5f9b-bc34-b18cd450004b/scratchpad/tools/bpyenv/bin/python"

try:
	import bpy  # noqa: F401
except ImportError:  # re-exec inside the Blender python
	bpy_python = os.environ.get("BPY_PYTHON", DEFAULT_BPY)
	os.execv(bpy_python, [bpy_python, os.path.abspath(__file__)] + sys.argv[1:])

import bpy  # noqa: E402,F811
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

sys.path.insert(0, HERE)
from planets_config import LIGHT_DIR, PLANETS, RIM_DIR, SPHERE_RADIUS_PX  # noqa: E402

ORDER = ["neptune", "uranus", "saturn", "jupiter", "mars", "earth"]


def log(*a):
	print("[planets]", *a, flush=True)


def system_python() -> str:
	return os.environ.get("PYTHON3", shutil.which("python3") or "python3")


# ------------------------------------------------------------------------------------------------
# scene helpers
# ------------------------------------------------------------------------------------------------
def reset_scene(w: int, h: int, samples: int):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	sc = bpy.context.scene
	sc.render.engine = "CYCLES"
	sc.cycles.device = "CPU"
	sc.render.threads_mode = "FIXED"
	sc.render.threads = 2
	sc.cycles.samples = samples
	sc.cycles.use_adaptive_sampling = True
	sc.cycles.adaptive_threshold = 0.004
	sc.cycles.use_denoising = True
	sc.cycles.denoiser = "OPENIMAGEDENOISE"
	sc.cycles.max_bounces = 4
	sc.cycles.transparent_max_bounces = 16
	sc.cycles.filter_width = 1.2
	sc.render.film_transparent = True
	sc.render.resolution_x = w
	sc.render.resolution_y = h
	sc.render.resolution_percentage = 100
	sc.view_settings.view_transform = "Standard"
	sc.render.image_settings.file_format = "OPEN_EXR"
	sc.render.image_settings.color_depth = "32"
	sc.render.image_settings.exr_codec = "ZIP"
	world = bpy.data.worlds.new("World")
	sc.world = world
	world.use_nodes = True
	bg = world.node_tree.nodes["Background"]
	bg.inputs[0].default_value = (0.012, 0.014, 0.02, 1.0)
	bg.inputs[1].default_value = 1.0
	cam = bpy.data.cameras.new("cam")
	cam.type = "ORTHO"
	cam.ortho_scale = max(w, h) / SPHERE_RADIUS_PX
	cam_ob = bpy.data.objects.new("cam", cam)
	sc.collection.objects.link(cam_ob)
	cam_ob.location = (0.0, -20.0, 0.0)
	cam_ob.rotation_euler = (math.pi / 2, 0.0, 0.0)
	cam.clip_start = 1.0
	cam.clip_end = 60.0
	sc.camera = cam_ob
	return sc


def add_sun(sc, name, to_light, strength, color=(1, 1, 1), angle_deg=1.0, specular=1.0):
	light = bpy.data.lights.new(name, "SUN")
	light.energy = strength
	if hasattr(light, "specular_factor"):   # EEVEE
		light.specular_factor = specular
	light.color = color
	light.angle = math.radians(angle_deg)
	ob = bpy.data.objects.new(name, light)
	sc.collection.objects.link(ob)
	ob.rotation_euler = Vector(to_light).normalized().to_track_quat("Z", "Y").to_euler()
	if specular <= 0.0:   # Cycles: no glossy highlights from this lamp (rim light only shapes the limb)
		ob.visible_glossy = False
	return ob


def planet_matrix(cfg) -> Matrix:
	"""Planet-local frame: +Z north pole, +X lon 0, +Y lon 90E. Camera looks along +Y (from -Y)."""
	phi = math.radians(-90.0 - cfg["view_lon"])
	return (Matrix.Rotation(math.radians(cfg["roll"]), 4, "Y")
		@ Matrix.Rotation(math.radians(cfg["view_lat"]), 4, "X")
		@ Matrix.Rotation(phi, 4, "Z"))


def load_image(path: str, non_color: bool = False):
	img = bpy.data.images.load(path, check_existing=True)
	if non_color:
		img.colorspace_settings.name = "Non-Color"
	return img


def equirect_uv(nt):
	"""Object coordinates -> (u, v) for an equirect texture (u = lon/2pi + .5, v = lat/pi + .5)."""
	n = nt.nodes
	l = nt.links
	tc = n.new("ShaderNodeTexCoord")
	norm = n.new("ShaderNodeVectorMath")
	norm.operation = "NORMALIZE"
	l.new(tc.outputs["Object"], norm.inputs[0])
	sep = n.new("ShaderNodeSeparateXYZ")
	l.new(norm.outputs["Vector"], sep.inputs[0])
	at = n.new("ShaderNodeMath")
	at.operation = "ARCTAN2"
	l.new(sep.outputs["Y"], at.inputs[0])
	l.new(sep.outputs["X"], at.inputs[1])
	u = n.new("ShaderNodeMath")
	u.operation = "MULTIPLY_ADD"
	l.new(at.outputs[0], u.inputs[0])
	u.inputs[1].default_value = 1.0 / (2.0 * math.pi)
	u.inputs[2].default_value = 0.5
	asn = n.new("ShaderNodeMath")
	asn.operation = "ARCSINE"
	l.new(sep.outputs["Z"], asn.inputs[0])
	v = n.new("ShaderNodeMath")
	v.operation = "MULTIPLY_ADD"
	l.new(asn.outputs[0], v.inputs[0])
	v.inputs[1].default_value = 1.0 / math.pi
	v.inputs[2].default_value = 0.5
	comb = n.new("ShaderNodeCombineXYZ")
	l.new(u.outputs[0], comb.inputs[0])
	l.new(v.outputs[0], comb.inputs[1])
	return comb.outputs[0]


def tex_node(nt, uv, img, interpolation="Cubic", extension="REPEAT"):
	t = nt.nodes.new("ShaderNodeTexImage")
	t.image = img
	t.interpolation = interpolation
	t.extension = extension
	nt.links.new(uv, t.inputs["Vector"])
	return t


def make_planet_material(name, cfg, tex_dir):
	mat = bpy.data.materials.new(name)
	if hasattr(mat, "use_nodes") and not mat.use_nodes:
		mat.use_nodes = True
	nt = mat.node_tree
	n = nt.nodes
	l = nt.links
	bsdf = n["Principled BSDF"]
	uv = equirect_uv(nt)
	alb = tex_node(nt, uv, load_image(os.path.join(tex_dir, f"{name}_albedo.png")))
	l.new(alb.outputs["Color"], bsdf.inputs["Base Color"])
	bsdf.inputs["Roughness"].default_value = cfg.get("roughness", 0.75)
	bsdf.inputs["Specular IOR Level"].default_value = cfg.get("specular", 0.25)
	rough_path = os.path.join(tex_dir, f"{name}_rough.png")
	if os.path.exists(rough_path):
		r = tex_node(nt, uv, load_image(rough_path, True), "Linear")
		l.new(r.outputs["Color"], bsdf.inputs["Roughness"])
		# glossy oceans also reflect a bit more
		spec = n.new("ShaderNodeMapRange")
		l.new(r.outputs["Color"], spec.inputs["Value"])
		spec.inputs["From Min"].default_value = 0.35
		spec.inputs["From Max"].default_value = 0.9
		spec.inputs["To Min"].default_value = cfg.get("specular_water", 0.55)
		spec.inputs["To Max"].default_value = cfg.get("specular", 0.2)
		l.new(spec.outputs["Result"], bsdf.inputs["Specular IOR Level"])
	h_path = os.path.join(tex_dir, f"{name}_height.png")
	if os.path.exists(h_path) and cfg.get("bump", 0.0) > 0:
		ht = tex_node(nt, uv, load_image(h_path, True), "Cubic")
		bump = n.new("ShaderNodeBump")
		bump.inputs["Strength"].default_value = 1.0
		bump.inputs["Distance"].default_value = cfg["bump"]
		l.new(ht.outputs["Color"], bump.inputs["Height"])
		l.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
	return mat


def make_cloud_material(name, cfg, tex_dir):
	mat = bpy.data.materials.new(name + "_clouds")
	if hasattr(mat, "use_nodes") and not mat.use_nodes:
		mat.use_nodes = True
	nt = mat.node_tree
	n = nt.nodes
	l = nt.links
	out = n["Material Output"]
	bsdf = n["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = (0.97, 0.98, 1.0, 1.0)
	bsdf.inputs["Roughness"].default_value = 0.95
	bsdf.inputs["Specular IOR Level"].default_value = 0.1
	uv = equirect_uv(nt)
	ct = tex_node(nt, uv, load_image(os.path.join(tex_dir, f"{name}_clouds.png"), True), "Cubic")
	tr = n.new("ShaderNodeBsdfTransparent")
	mix = n.new("ShaderNodeMixShader")
	l.new(ct.outputs["Color"], mix.inputs["Fac"])
	l.new(tr.outputs[0], mix.inputs[1])
	l.new(bsdf.outputs[0], mix.inputs[2])
	l.new(mix.outputs[0], out.inputs["Surface"])
	return mat


def make_ring_material(name, cfg, tex_dir, r_in, r_out):
	mat = bpy.data.materials.new(name + "_ring")
	if hasattr(mat, "use_nodes") and not mat.use_nodes:
		mat.use_nodes = True
	nt = mat.node_tree
	n = nt.nodes
	l = nt.links
	for node in list(n):
		if node.type != "OUTPUT_MATERIAL":
			n.remove(node)
	out = n["Material Output"]
	tc = n.new("ShaderNodeTexCoord")
	ln = n.new("ShaderNodeVectorMath")
	ln.operation = "LENGTH"
	l.new(tc.outputs["Object"], ln.inputs[0])
	u = n.new("ShaderNodeMapRange")
	u.clamp = True
	l.new(ln.outputs["Value"], u.inputs["Value"])
	u.inputs["From Min"].default_value = r_in
	u.inputs["From Max"].default_value = r_out
	comb = n.new("ShaderNodeCombineXYZ")
	l.new(u.outputs["Result"], comb.inputs[0])
	comb.inputs[1].default_value = 0.5
	img = load_image(os.path.join(tex_dir, f"{name}_ring.png"))
	img.alpha_mode = "STRAIGHT"
	t = tex_node(nt, comb.outputs[0], img, "Linear", "EXTEND")
	diff = n.new("ShaderNodeBsdfDiffuse")
	diff.inputs["Roughness"].default_value = 0.6
	l.new(t.outputs["Color"], diff.inputs["Color"])
	trl = n.new("ShaderNodeBsdfTranslucent")
	l.new(t.outputs["Color"], trl.inputs["Color"])
	add = n.new("ShaderNodeMixShader")
	add.inputs["Fac"].default_value = cfg.get("ring_translucency", 0.25)
	l.new(diff.outputs[0], add.inputs[1])
	l.new(trl.outputs[0], add.inputs[2])
	surf = add
	if cfg.get("ring_emission", 0.0) > 0:
		em = n.new("ShaderNodeEmission")
		l.new(t.outputs["Color"], em.inputs["Color"])
		em.inputs["Strength"].default_value = cfg["ring_emission"]
		both = n.new("ShaderNodeAddShader")
		l.new(add.outputs[0], both.inputs[0])
		l.new(em.outputs[0], both.inputs[1])
		surf = both
	tr = n.new("ShaderNodeBsdfTransparent")
	mix = n.new("ShaderNodeMixShader")
	l.new(t.outputs["Alpha"], mix.inputs["Fac"])
	l.new(tr.outputs[0], mix.inputs[1])
	l.new(surf.outputs[0], mix.inputs[2])
	l.new(mix.outputs[0], out.inputs["Surface"])
	return mat


def ring_mesh(name, r_in, r_out, segments=512):
	verts = []
	faces = []
	for i in range(segments):
		a = 2 * math.pi * i / segments
		verts.append((r_in * math.cos(a), r_in * math.sin(a), 0.0))
		verts.append((r_out * math.cos(a), r_out * math.sin(a), 0.0))
	for i in range(segments):
		j = (i + 1) % segments
		faces.append((2 * i, 2 * i + 1, 2 * j + 1, 2 * j))
	me = bpy.data.meshes.new(name)
	me.from_pydata(verts, [], faces)
	me.update()
	return me


def add_sphere(sc, name, radius, mat, matrix):
	bpy.ops.mesh.primitive_uv_sphere_add(segments=256, ring_count=128, radius=radius)
	ob = bpy.context.active_object
	ob.name = name
	for p in ob.data.polygons:
		p.use_smooth = True
	ob.data.materials.append(mat)
	ob.matrix_world = matrix
	return ob


def canvas_size(cfg, m: Matrix):
	"""Canvas (even w, h) that holds the sphere, its glow and the ring ellipse, sphere centred."""
	R = SPHERE_RADIUS_PX
	margin = max(24.0, 7.0 * cfg["atmo"]["width"] * R) + 8.0
	ex = ez = 1.0
	if cfg.get("rings"):
		r = cfg["rings"][1]
		ex = max(ex, r * math.hypot(m[0][0], m[0][1]))
		ez = max(ez, r * math.hypot(m[2][0], m[2][1]))
	w = 2 * int(math.ceil(ex * R + margin))
	h = 2 * int(math.ceil(ez * R + margin))
	return w, h


# ------------------------------------------------------------------------------------------------
def render_planet(name: str, work: str, samples: int, preview: bool = False) -> str:
	cfg = PLANETS[name]
	tex_dir = os.path.join(work, "tex")
	m = planet_matrix(cfg)
	w, h = canvas_size(cfg, m)
	if preview:
		samples = min(samples, 24)
	sc = reset_scene(w, h, samples)
	add_sphere(sc, name, 1.0, make_planet_material(name, cfg, tex_dir), m)
	if cfg.get("clouds"):
		add_sphere(sc, name + "_clouds", 1.0 + cfg["clouds"], make_cloud_material(name, cfg, tex_dir), m)
	if cfg.get("rings"):
		r_in, r_out = cfg["rings"]
		ob = bpy.data.objects.new(name + "_ring", ring_mesh(name + "_ring", r_in, r_out))
		sc.collection.objects.link(ob)
		ob.data.materials.append(make_ring_material(name, cfg, tex_dir, r_in, r_out))
		ob.matrix_world = m
	key = cfg.get("key_strength", 1.0) * math.pi
	add_sun(sc, "key", LIGHT_DIR, key, cfg.get("key_color", (1.0, 0.98, 0.95)), cfg.get("sun_angle", 2.0))
	if cfg.get("rim_strength", 0) > 0:
		add_sun(sc, "rim", cfg.get("rim_dir", RIM_DIR), cfg["rim_strength"] * math.pi,
			cfg.get("rim_color", (0.6, 0.7, 1.0)), 4.0, specular=0.0)
	out_dir = os.path.join(work, "render")
	os.makedirs(out_dir, exist_ok=True)
	exr = os.path.join(out_dir, f"{name}.exr")
	sc.render.filepath = exr
	t0 = time.time()
	bpy.ops.render.render(write_still=True)
	log(name, f"rendered {w}x{h} in {time.time() - t0:.1f}s")
	img = bpy.data.images.load(exr)
	a = np.empty(img.size[0] * img.size[1] * 4, np.float32)
	img.pixels.foreach_get(a)
	a = a.reshape(img.size[1], img.size[0], 4)[::-1]  # Blender rows are bottom-up
	npy = os.path.join(out_dir, f"{name}.npy")
	np.save(npy, a)
	return npy


def main() -> None:
	argv = sys.argv[1:]
	opts = {a.split("=")[0]: (a.split("=", 1)[1] if "=" in a else True) for a in argv if a.startswith("--")}
	planets = [a for a in argv if not a.startswith("--")] or ORDER
	work = opts.get("--work", os.path.join(tempfile.gettempdir(), "planet_protector_planets"))
	samples = int(opts.get("--samples", 128))
	os.makedirs(work, exist_ok=True)
	py3 = system_python()
	cmd = [py3, os.path.join(HERE, "planets_textures.py"), work] + planets
	if opts.get("--force-tex"):
		cmd.append("--force")
	if opts.get("--tex-res"):
		cmd.append("--res=" + str(opts["--tex-res"]))
	subprocess.run(cmd, check=True)
	if not opts.get("--post-only"):
		for p in planets:
			render_planet(p, work, samples, bool(opts.get("--preview")))
	post = [py3, os.path.join(HERE, "planets_post.py"), work] + planets
	if opts.get("--out"):
		post.append("--out=" + str(opts["--out"]))
	subprocess.run(post, check=True)


if __name__ == "__main__":
	main()
