"""Planet Protector Steam library artwork - renders every 3-D element in Blender (bpy 5.2, Cycles CPU).

    <bpy-python> tools/blender/steam_keyart_render.py --work=DIR --tex=DIR [--only=name,...] [--draft]
                                                      [--scale=F] [--spp=F]

Normally started by tools/blender/steam_keyart.py. Each element is rendered on its own (transparent
film) into <work>/renders/<name>.npy (scene-linear premultiplied float RGBA, rows top -> bottom) and
<name>.json (projected anchor points: eyes, chest, mouth, muzzle, nozzles ... in render pixels).

Elements (all lit by the same camera-space rig from steam_keyart_layout.py):
  earth_<asset>          the game's Earth for that asset's framing (8K textures of planets_textures.py)
  demon_lead, demon_b..e the game's crowned Earth demon, posed (lead diving at the viewer, formation)
  ship (+ ship_glow)     the Interceptor from behind (chase view) + its additive exhaust pass
  icon_demon, icon_ship  layers of the square icon
--draft renders at 1/3 size with few samples (layout work); --scale / --spp multiply size / samples.
Render threads: 2 (env ART_THREADS) because other renders may run in parallel.
"""
from __future__ import annotations

import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import steam_keyart_bpy as K  # noqa: E402  (sets sys.path for the game's tools/blender modules)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import steam_keyart_layout as LY  # noqa: E402
import steam_keyart_models as MD  # noqa: E402

ELEMENTS_EARTH = ["earth_hero", "earth_capsule", "earth_wide", "earth_icon"]


def _args():
	o = {"work": None, "only": None, "draft": False, "tex": None, "scale": 1.0, "spp": 1.0}
	for a in sys.argv[1:]:
		if a.startswith("--tex="):
			o["tex"] = os.path.abspath(a[6:])
		elif a.startswith("--work="):
			o["work"] = os.path.abspath(a[7:])
		elif a.startswith("--only="):
			o["only"] = [s for s in a[7:].split(",") if s]
		elif a.startswith("--scale="):
			o["scale"] = float(a[8:])
		elif a.startswith("--spp="):
			o["spp"] = float(a[6:])
		elif a == "--draft":
			o["draft"] = True
	if not o["work"]:
		sys.exit("steam_keyart_render.py: --work=DIR is required")
	o["tex"] = o["tex"] or os.path.join(o["work"], "earth", "tex")
	if o["draft"]:
		o["scale"] *= 1.0 / 3.0
		o["spp"] *= 0.2
	return o


def _save_meta(path, meta):
	with open(path, "w") as f:
		json.dump(meta, f, indent=1)


# ------------------------------------------------------------------------------------------------
# lighting rigs (camera space)
# ------------------------------------------------------------------------------------------------
def rig_demon(cam, sun=10.0, earth=9.0, earth_front=2.2, fill=0.5, kick=15.0, world=0.25):
	"""Glossy black demon: almost no diffuse, the shape comes from highlights. Warm sun rim (upper right
	behind), cool kicker (upper left behind) = the silhouette's thin cool contour, blue Earth bounce from
	below (behind and a soft one from the front for the torso and legs), faint cool front fill, and a
	reflection environment that is brighter towards the Earth below."""
	K.cam_world(cam, [(0.0, (0.002, 0.003, 0.007)), (0.5, (0.006, 0.009, 0.02)), (0.8, (0.03, 0.06, 0.14)),
		(1.0, (0.07, 0.13, 0.3))], strength=world)
	K.cam_sun(cam, "sun", LY.SUN_CAM, sun, LY.SUN_COLOR, 3.0)
	K.cam_sun(cam, "kick", LY.KICK_CAM, kick, LY.KICK_COLOR, 2.5)
	K.cam_sun(cam, "earth", LY.EARTH_CAM, earth, LY.EARTH_COLOR, 4.0)
	K.cam_sun(cam, "earth_front", LY.EARTH_FRONT_CAM, earth_front, LY.EARTH_COLOR, 35.0, shadow=False)
	K.cam_sun(cam, "fill", LY.FILL_CAM, fill, LY.FILL_COLOR, 30.0, shadow=False)


def rig_ship(cam, sun=4.2, earth=3.0, fire=1.1, world=0.9):
	# metal needs something to reflect: soft cool sky above, bright blue Earth below, dark horizon band
	K.cam_world(cam, [(0.0, (0.16, 0.17, 0.22)), (0.42, (0.03, 0.035, 0.05)), (0.55, (0.012, 0.016, 0.03)),
		(0.75, (0.08, 0.14, 0.28)), (1.0, (0.3, 0.48, 0.85))], strength=world)
	K.cam_sun(cam, "sun", LY.SUN_CAM, sun, LY.SUN_COLOR, 5.0)
	K.cam_sun(cam, "earth", LY.EARTH_CAM, earth, LY.EARTH_COLOR, 12.0)
	# orange light from the fight ahead (fireballs / impact): from up-screen, behind the ship
	K.cam_sun(cam, "fire", (0.25, 0.85, -0.45), fire, (1.0, 0.36, 0.1), 8.0)


# ------------------------------------------------------------------------------------------------
# demons
# ------------------------------------------------------------------------------------------------
RIG_DEMON = {}                         # overrides of rig_demon's defaults
MEMBRANE = {"spec": 0.25, "rough": 0.7}    # matte enough to stay deep red, not reflect the blue rig

DEMONS = {
	# t = wing phase (0 wings up, 0.5 down), pitch = dive towards the camera, roll, yaw (deg), lens (mm),
	# el = camera elevation (deg, + = camera above), width = render width px, tr = membrane translucency,
	# impact = the laser hits this one (orange-white light in front of its chest)
	"demon_lead": dict(t=0.0, pitch=44.0, roll=-9.0, yaw=0.0, lens=30.0, el=-2.0, width=1700, tr=0.07, impact=True),
	# formation: four clearly different attitudes
	"demon_b": dict(t=0.52, pitch=22.0, roll=30.0, yaw=-40.0, lens=35.0, el=6.0, width=900, tr=0.07),   # banking turn
	"demon_c": dict(t=0.1, pitch=30.0, roll=-15.0, yaw=24.0, lens=35.0, el=-6.0, width=900, tr=0.07),   # wings up
	"demon_d": dict(t=0.62, pitch=30.0, roll=8.0, yaw=-14.0, lens=35.0, el=-8.0, width=700, tr=0.07),   # downstroke
	"demon_e": dict(t=0.78, pitch=12.0, roll=18.0, yaw=-62.0, lens=40.0, el=4.0, width=700, tr=0.07),   # side view
	"icon_demon": dict(t=0.0, pitch=20.0, roll=0.0, yaw=0.0, lens=40.0, el=4.0, width=1100, tr=0.045),
}


def render_demon(name, work, o):
	cfg = DEMONS[name]
	t0 = time.time()
	spp = max(8, int(128 * o["spp"]))
	K.reset(64, 64, samples=spp, adaptive=0.006)
	bpy.context.scene.cycles.sample_clamp_direct = 12.0   # no pin-point fireflies from the impact light
	bpy.context.scene.cycles.sample_clamp_indirect = 4.0
	mats = MD.demon_materials(eye=16.0, throat=4.0, translucent=cfg["tr"], membrane_tint=(0.45, 0.06, 0.02),
		membrane_spec=MEMBRANE["spec"], membrane_rough=MEMBRANE["rough"])
	root, ctx, rigs = MD.build_demon(t=cfg["t"], mats=mats, meta_res=0.16 if o["scale"] > 0.5 else 0.3)
	MD.pose(root, pitch_deg=cfg["pitch"], roll_deg=cfg["roll"], yaw_deg=cfg["yaw"])
	el = math.radians(cfg["el"])
	dist = 115.0 * cfg["lens"] / 30.0
	cam = K.camera("cam", (0.0, -dist * math.cos(el), dist * math.sin(el)), (0.0, 0.0, 0.0), lens=cfg["lens"])
	pts = MD.bbox_points(root)
	w = max(64, int(cfg["width"] * o["scale"]))
	rx, ry = K.fit_frame(cam, pts, w, margin=0.03)
	rig_demon(cam, **RIG_DEMON)
	chest_w = None
	if ctx.sigil_objects:
		cs = [K.obj_center(ob) for ob in ctx.sigil_objects]
		chest_w = sum(cs, Vector()) / len(cs)
	meta = {"name": name, "size": [rx, ry], "eyes": [K.project_px(cam, K.obj_center(ob)) for ob in ctx.eye_objects],
		"chest": K.project_px(cam, chest_w) if chest_w is not None else None,
		"mouth": K.project_px(cam, K.obj_center(ctx.throat_objects[0])) if ctx.throat_objects else None,
		"cfg": cfg}
	if cfg.get("impact") and chest_w is not None:
		# the laser hits the chest: hot orange-white light just in front of it lights the demon up
		cpos = Vector(chest_w) + (Vector(cam.location) - Vector(chest_w)).normalized() * 9.0
		K.point_light("impact", tuple(cpos), 12000.0, (1.0, 0.55, 0.22), radius=7.0)
		blue = Vector(chest_w) + (Vector(cam.location) - Vector(chest_w)).normalized() * 30.0 + K.cam_dir(cam, (0, -1, 0)) * 25.0
		K.point_light("laser", tuple(blue), 14000.0, (0.3, 0.6, 1.0), radius=10.0)
	K.render_npy(os.path.join(work, "renders", name + ".npy"))
	_save_meta(os.path.join(work, "renders", name + ".json"), meta)
	K.log(name, "%dx%d %d spp in %.0fs" % (rx, ry, spp, time.time() - t0))


# ------------------------------------------------------------------------------------------------
# ship
# ------------------------------------------------------------------------------------------------
SHIPS = {
	# el = camera elevation above the wing plane (deg), az = camera azimuth (deg, + = camera to the right
	# of the tail), roll = bank of the ship (deg, + = right wing down), width px
	"ship": dict(el=36.0, az=8.0, roll=16.0, pitch=0.0, lens=40.0, width=1500),
	"icon_ship": dict(el=58.0, az=0.0, roll=0.0, pitch=0.0, lens=50.0, width=1000),
}


def render_ship(name, work, o):
	cfg = SHIPS[name]
	t0 = time.time()
	spp = max(8, int(160 * o["spp"]))
	K.reset(64, 64, samples=spp, adaptive=0.006)
	kit, objs, plumes, muzzle = MD.build_ship()
	root = MD.parent_all(objs)
	root.rotation_mode = "XYZ"
	root.rotation_euler = (math.radians(cfg["pitch"]), math.radians(cfg["roll"]), 0.0)
	el, az = math.radians(cfg["el"]), math.radians(cfg["az"])
	dist = 32.0 * cfg["lens"] / 40.0
	loc = (dist * math.cos(el) * math.sin(az), -dist * math.cos(el) * math.cos(az), dist * math.sin(el))
	cam = K.camera("cam", loc, (0.0, 0.3, 0.3), lens=cfg["lens"])
	bpy.context.view_layer.update()
	pts = []
	dg = bpy.context.evaluated_depsgraph_get()
	for ob in objs:
		if ob.type != "MESH":
			continue
		me = ob.evaluated_get(dg).to_mesh()
		M = ob.matrix_world
		vs = [M @ v.co for v in me.vertices]
		pts.extend(vs[:: max(1, len(vs) // 600)])
		ob.evaluated_get(dg).to_mesh_clear()
	# keep room for the exhaust plume behind the nozzle
	for px, py, pz, pr in plumes:
		pts.append(root.matrix_world @ Vector((px, py - 3.4, pz)))
	w = max(64, int(cfg["width"] * o["scale"]))
	rx, ry = K.fit_frame(cam, pts, w, margin=0.03)
	rig_ship(cam)
	mz = root.matrix_world @ Vector(muzzle)
	mz_dir = (root.matrix_world.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()
	ahead = mz + mz_dir * 40.0
	meta = {"name": name, "size": [rx, ry], "muzzle": K.project_px(cam, mz), "ahead40": K.project_px(cam, ahead),
		"nozzles": [K.project_px(cam, root.matrix_world @ Vector((px, py, pz))) for px, py, pz, pr in plumes],
		"cfg": cfg}
	K.render_npy(os.path.join(work, "renders", name + ".npy"))
	# glow pass: plumes only, ship as hold-out (additive layer, like the game's *_glow sprites)
	for ob in objs:
		ob.is_holdout = True
	for ob in list(bpy.context.scene.objects):
		if ob.type == "LIGHT":
			ob.hide_render = True
	bpy.context.scene.world = None
	K.gradient_world([(0.0, (0, 0, 0)), (1.0, (0, 0, 0))], strength=0.0)
	bpy.context.scene.cycles.samples = max(16, spp // 2)
	MD.add_plumes(kit, plumes, root, length=3.2)
	K.render_npy(os.path.join(work, "renders", name + "_glow.npy"))
	_save_meta(os.path.join(work, "renders", name + ".json"), meta)
	K.log(name, "%dx%d %d spp in %.0fs" % (rx, ry, spp, time.time() - t0))


# ------------------------------------------------------------------------------------------------
# earth
# ------------------------------------------------------------------------------------------------
def render_earth(asset, work, o):
	e = LY.EARTH[asset]
	win = LY.earth_window(asset)
	r_px = e["R"] * e["ss"] * min(1.0, o["scale"] * 1.05)
	lon, lat, roll = e["view"]
	t0 = time.time()
	spp = max(8, int(64 * o["spp"]))
	meta = MD.render_earth(os.path.join(work, "renders", "earth_%s.npy" % asset), o["tex"], r_px, win, lon, lat, roll,
		LY.EARTH_SUN_CAM, samples=spp, sun_strength=1.5, cloud_h=e.get("cloud_h"), detail=e.get("detail", 0.0),
		detail_px=28.0 * r_px / (e["R"] * e["ss"]))
	meta["asset"] = asset
	_save_meta(os.path.join(work, "renders", "earth_%s.json" % asset), meta)
	K.log("earth_%s" % asset, meta["size"], "%d spp in %.0fs" % (spp, time.time() - t0))


def all_elements():
	return ELEMENTS_EARTH + list(DEMONS) + list(SHIPS)


def main():
	o = _args()
	work = o["work"]
	os.makedirs(os.path.join(work, "renders"), exist_ok=True)
	jobs = o["only"] or all_elements()
	for j in jobs:
		if j.startswith("earth_") and j in ELEMENTS_EARTH:
			render_earth(j[6:], work, o)
		elif j in DEMONS:
			render_demon(j, work, o)
		elif j in SHIPS:
			render_ship(j, work, o)
		else:
			sys.exit("steam_keyart_render.py: unknown element %r (known: %s)" % (j, ", ".join(all_elements())))


if __name__ == "__main__":
	main()
