"""Renders the six enemy designs as channel-packed 16-frame wing-flap strips (docs/SPEC.md §15, §16.2).

Run with the Blender Python module:
    <bpyenv>/bin/python tools/blender/enemies.py [planet ...] [--samples N] [--frames 16] [--out DIR]

Output per planet (default DIR = game/assets/sprites/enemies):
    <planet>.png   4096 x 160 RGBA strip, 16 frames of 256 x 160
                   R = diffuse lighting of a white material (key light upper left + soft fill)
                   G = specular / rim highlight intensity
                   B = emissive mask (eyes, glowing details)
                   A = coverage alpha (straight, not premultiplied)
    <planet>.json  {"frames", "frame_w", "frame_h", "px_per_game_px", "content_top", "content_bottom", "width_factor"}
                   (+ "eye_rect" [x0, y0, x1, y1] frame px for designs listed in EYE_RECT)

Each frame is rendered once with Cycles (CPU) into a multilayer EXR; the channels are taken from the light passes:
R = (DiffDir + DiffInd) * DiffCol, G = tonemapped (GlossDir + GlossInd) * GlossCol, B = Emission, A = Combined alpha.
"""
import argparse
import json
import math
import os
import struct
import sys
import time
import zlib

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import enemies_designs  # noqa: E402
import enemies_geom as G  # noqa: E402
from enemies_exr import read_exr  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PLANETS = ["neptune", "uranus", "saturn", "jupiter", "mars", "earth"]
WIDTH_FACTOR = {"neptune": 1.00, "uranus": 1.02, "saturn": 1.04, "jupiter": 1.06, "mars": 1.08, "earth": 1.10}
# Eye area (frame px, inclusive) of designs that are also shown BLACK (levels 19/20): there the shader lets only
# this part of the emissive B channel glow (both eyes in every frame of the bob; no veins, sigil or crown jewels).
EYE_RECT = {"earth": [112, 44, 144, 57]}
FRAME_W = 256
FRAME_H = 160
PX_PER_GAME_PX = 2.0
GLOSS_GAIN = 5.0
BOB_GAME_PX = 1.1  # <= 1.5 game px (3 sprite px)
AMBIENT = 0.1      # world light strength (diffuse only)


# --------------------------------------------------------------------------------------------------
def write_png(path, rgba8):
	"""Minimal PNG writer (8-bit RGBA, straight alpha)."""
	h, w, _ = rgba8.shape
	raw = b"".join(b"\x00" + rgba8[y].tobytes() for y in range(h))

	def chunk(tag, data):
		c = struct.pack(">I", len(data)) + tag + data
		return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

	png = b"\x89PNG\r\n\x1a\n"
	png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
	png += chunk(b"IDAT", zlib.compress(raw, 9))
	png += chunk(b"IEND", b"")
	with open(path, "wb") as f:
		f.write(png)


def sun(name, direction_to_light, strength, angle_deg=6.0, diffuse=True, glossy=True, shadow=True):
	ld = bpy.data.lights.new(name, "SUN")
	ld.energy = strength
	ld.angle = math.radians(angle_deg)
	ld.use_shadow = shadow
	ob = bpy.data.objects.new(name, ld)
	bpy.context.scene.collection.objects.link(ob)
	d = -Vector(direction_to_light).normalized()  # direction the light travels
	ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
	ob.visible_diffuse = diffuse
	ob.visible_glossy = glossy
	ob.visible_camera = False
	return ob


def setup_scene(samples):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	s = bpy.context.scene
	s.render.engine = "CYCLES"
	s.cycles.device = "CPU"
	s.render.threads_mode = "FIXED"
	s.render.threads = 2
	s.render.resolution_x = FRAME_W
	s.render.resolution_y = FRAME_H
	s.render.resolution_percentage = 100
	s.render.film_transparent = True
	s.cycles.samples = samples
	s.cycles.use_adaptive_sampling = True
	s.cycles.adaptive_threshold = 0.005
	s.cycles.use_denoising = False
	s.cycles.pixel_filter_type = "BLACKMAN_HARRIS"
	s.cycles.filter_width = 1.3
	s.cycles.max_bounces = 3
	s.cycles.diffuse_bounces = 1
	s.cycles.glossy_bounces = 1
	s.cycles.transmission_bounces = 0
	s.cycles.volume_bounces = 0
	s.cycles.transparent_max_bounces = 2
	s.cycles.sample_clamp_indirect = 2.0
	s.cycles.sample_clamp_direct = 4.0
	s.render.use_persistent_data = True
	w = bpy.data.worlds.new("world")
	s.world = w
	w.color = (0.0, 0.0, 0.0)
	if hasattr(w, "use_nodes") and not w.use_nodes:
		w.use_nodes = True
	bg = w.node_tree.nodes.get("Background")
	bg.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
	bg.inputs["Strength"].default_value = AMBIENT
	w.cycles_visibility.glossy = False
	w.cycles_visibility.camera = False
	vl = s.view_layers[0]
	vl.use_pass_diffuse_direct = True
	vl.use_pass_diffuse_indirect = True
	vl.use_pass_diffuse_color = True
	vl.use_pass_glossy_direct = True
	vl.use_pass_glossy_indirect = True
	vl.use_pass_glossy_color = True
	vl.use_pass_emit = True
	im = s.render.image_settings
	im.media_type = "MULTI_LAYER_IMAGE"
	im.exr_codec = "ZIP"
	im.color_depth = "32"
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
	s.collection.objects.link(cam)
	cam.data.type = "ORTHO"
	cam.data.ortho_scale = FRAME_W / PX_PER_GAME_PX
	cam.data.clip_start = 1.0
	cam.data.clip_end = 1000.0
	cam.location = (0.0, -300.0, 0.0)
	cam.rotation_euler = (math.pi / 2, 0.0, 0.0)
	s.camera = cam
	pi = math.pi
	# key: upper left, in front
	sun("key", (-0.8, -0.62, 0.8), pi * 1.07, angle_deg=8.0)
	# soft fill from the right / slightly below, no shadows, diffuse only
	sun("fill", (0.8, -0.6, -0.1), pi * 0.1, angle_deg=40.0, glossy=False, shadow=False)
	sun("bounce", (0.0, -0.3, -1.0), pi * 0.04, angle_deg=60.0, glossy=False, shadow=False)
	# rim lights: glossy only, from behind
	sun("rim_r", (0.75, 0.9, 0.55), pi * 1.4, angle_deg=12.0, diffuse=False)
	sun("rim_l", (-0.85, 0.8, -0.1), pi * 0.8, angle_deg=12.0, diffuse=False)
	return s


def materials():
	m = {}
	m["skin"] = G.mat_surface("skin", albedo=0.92, rough=0.45, spec=0.5, bump=0.1, bump_scale=0.3, bump_detail=1.0)
	m["membrane"] = G.mat_surface("membrane", albedo=0.82, rough=0.55, spec=0.4, bump=0.1, bump_scale=6.0,
		bump_detail=1.0, coords="UV")
	m["bone"] = G.mat_surface("bone", albedo=0.95, rough=0.36, spec=0.6, bump=0.05, bump_scale=1.2)
	m["horn"] = G.mat_surface("horn", albedo=0.92, rough=0.26, spec=0.75, bump=0.08, bump_scale=1.5)
	m["claw"] = G.mat_surface("claw", albedo=0.97, rough=0.2, spec=0.8)
	m["armor"] = G.mat_surface("armor", albedo=1.0, rough=0.24, spec=0.8, bump=0.06, bump_scale=2.0)
	m["gold"] = G.mat_surface("gold", albedo=1.0, rough=0.16, spec=1.0, bump=0.04, bump_scale=3.0)
	m["dark"] = G.mat_surface("dark", albedo=0.06, rough=0.5, spec=0.3)
	m["eye"] = G.mat_eye("eye", 1.0)
	m["glow"] = G.mat_emission("glow", 0.95)
	m["glow_soft"] = G.mat_emission("glow_soft", 0.85)
	m["vein"] = G.mat_emission("vein", 0.72)
	return m


class Ctx:
	def __init__(self, planet, mats, root):
		self.planet = planet
		self.mats = mats
		self.root = root
		self.metas = []
		self.objects = []
		self.n = 0

	def meta(self, name="body", mat="skin", res=0.32):
		m = G.Meta("%s_%s" % (self.planet, name), self.mats[mat], self.root, res=res)
		self.metas.append(m)
		return m

	def add(self, part, mat, name=None):
		self.n += 1
		ob = G.mesh_object(name or "%s_part%d" % (self.planet, self.n), part, self.mats[mat], self.root)
		self.objects.append(ob)
		return ob

	def add_mirrored(self, part, mat, name=None):
		"""Adds part (built for the right side, x > 0) and a mirrored copy."""
		ob = self.add(part, mat, name)
		obl = bpy.data.objects.new(ob.name + "_L", ob.data)
		bpy.context.scene.collection.objects.link(obl)
		obl.parent = self.root
		obl.scale = (-1.0, 1.0, 1.0)
		self.objects.append(obl)
		return ob

	def surface(self, objects=None):
		bpy.context.view_layer.update()
		return G.Surface(objects if objects is not None else [m.ob for m in self.metas])


# --------------------------------------------------------------------------------------------------
def render_planet(planet, out_dir, samples, frames, scratch, only_frames=None):
	t0 = time.time()
	s = setup_scene(samples)
	mats = materials()
	root = bpy.data.objects.new("root", None)
	s.collection.objects.link(root)
	ctx = Ctx(planet, mats, root)
	design = enemies_designs.DESIGNS[planet]
	wing_specs = design(ctx)
	wf = WIDTH_FACTOR[planet]
	rigs = []
	for spec in wing_specs:
		rig = G.WingRig(spec, mats, root)
		rigs.append(rig)
	# fit the widest pose of the main wing to the span; secondary wings keep their relative size
	main = rigs[0]
	k_target = 45.0 * wf
	before = main.max_extent(frames)[0]
	ext = main.fit_span(k_target, frames)
	scale = k_target / before
	for rig in rigs[1:]:
		P = rig.spec.pivot
		for _key, part in rig.groups:
			part.verts = P + (part.verts - P) * scale
			part.anchors = P + (part.anchors - P) * scale
		rig.spec.arm = [P + (p - P) * scale for p in rig.spec.arm]
	for rig in rigs:
		rig.build()
		print("  wing %s extent x=%.2f z=[%.2f, %.2f]" % ((rig.spec.name,) + rig.max_extent(frames)))
	print("  main wing span fit: %.2f -> %.2f (scale %.3f)" % (before * 2, ext[0] * 2, scale))

	strip = np.zeros((FRAME_H, FRAME_W * frames, 4), dtype=np.float32)
	frame_list = range(frames) if only_frames is None else only_frames
	for f in frame_list:
		t = f / frames
		for rig in rigs:
			rig.update(t)
		root.location = (0.0, 0.0, BOB_GAME_PX * math.sin(2 * math.pi * (t - 0.18)))
		if hasattr(design, "animate"):
			design.animate(ctx, t)
		path = os.path.join(scratch, "%s_%02d.exr" % (planet, f))
		s.render.filepath = path
		bpy.ops.render.render(write_still=True)
		strip[:, f * FRAME_W:(f + 1) * FRAME_W] = process_exr(path)
	rgba8 = (np.clip(strip, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
	rgba8[rgba8[:, :, 3] == 0, :3] = 0
	alpha = rgba8[:, :, 3]
	rows = np.nonzero(alpha.max(axis=1) > 0)[0]
	cols_all = []
	for f in frame_list:
		fa = alpha[:, f * FRAME_W:(f + 1) * FRAME_W]
		c = np.nonzero(fa.max(axis=0) > 0)[0]
		r = np.nonzero(fa.max(axis=1) > 0)[0]
		cols_all.append((f, int(c.min()), int(c.max()), int(r.min()), int(r.max())))
	top, bottom = int(rows.min()), int(rows.max())
	os.makedirs(out_dir, exist_ok=True)
	png = os.path.join(out_dir, "%s.png" % planet)
	write_png(png, rgba8)
	meta = {"frames": frames, "frame_w": FRAME_W, "frame_h": FRAME_H, "px_per_game_px": PX_PER_GAME_PX,
		"content_top": top, "content_bottom": bottom, "width_factor": wf}
	if planet in EYE_RECT:
		meta["eye_rect"] = EYE_RECT[planet]
	with open(os.path.join(out_dir, "%s.json" % planet), "w") as fh:
		json.dump(meta, fh)
		fh.write("\n")
	# report
	spans = [c[2] - c[1] + 1 for c in cols_all]
	minmargin = min(min(c[1], FRAME_W - 1 - c[2], c[3], FRAME_H - 1 - c[4]) for c in cols_all)
	print("  %s: content rows %d..%d, widest span %d px (target %.0f), min margin %d px, %.1fs" % (
		planet, top, bottom, max(spans), 180 * wf, minmargin, time.time() - t0))
	for c in cols_all:
		print("    frame %2d: x %3d..%3d (span %3d)  y %3d..%3d" % (c[0], c[1], c[2], c[2] - c[1] + 1, c[3], c[4]))
	return meta


def process_exr(path):
	d = read_exr(path)

	def rgb(name):
		return np.stack([d["ViewLayer.%s.%s" % (name, c)] for c in "RGB"], axis=-1)

	def lum(x):
		return x[..., 0] * 0.2126 + x[..., 1] * 0.7152 + x[..., 2] * 0.0722

	a = d["ViewLayer.Combined.A"]
	diff = lum((rgb("Diffuse Direct") + rgb("Diffuse Indirect")) * rgb("Diffuse Color"))
	gloss = lum((rgb("Glossy Direct") + rgb("Glossy Indirect")) * rgb("Glossy Color"))
	emit = lum(rgb("Emission"))
	inv = np.where(a > 1e-4, 1.0 / np.maximum(a, 1e-4), 0.0)
	R = np.clip(diff * inv, 0.0, 1.0)
	Gc = 1.0 - np.exp(-np.maximum(gloss * inv, 0.0) * GLOSS_GAIN)
	B = np.clip(emit * inv, 0.0, 1.0)
	out = np.stack([R, Gc, B, np.clip(a, 0.0, 1.0)], axis=-1)
	return out


def main():
	argv = sys.argv[1:]
	if "--" in argv:
		argv = argv[argv.index("--") + 1:]
	ap = argparse.ArgumentParser()
	ap.add_argument("planets", nargs="*", default=PLANETS)
	ap.add_argument("--samples", type=int, default=192)
	ap.add_argument("--frames", type=int, default=16)
	ap.add_argument("--only-frames", type=str, default="")
	ap.add_argument("--out", default=os.path.join(ROOT, "game", "assets", "sprites", "enemies"))
	ap.add_argument("--scratch", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "enemy_renders"))
	args = ap.parse_args(argv)
	os.makedirs(args.scratch, exist_ok=True)
	only = [int(x) for x in args.only_frames.split(",")] if args.only_frames else None
	for p in args.planets:
		print("rendering %s ..." % p)
		render_planet(p, args.out, args.samples, args.frames, args.scratch, only)


if __name__ == "__main__":
	main()
