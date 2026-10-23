"""art-ships: renders player ships, rockets, title logo and app icon with Blender (bpy, Cycles CPU).

Usage (from anywhere):
    <bpy-python> tools/blender/ships.py [--only=interceptor,fighter,...,rockets,logo,icon]
                                        [--work=<dir>] [--samples=N] [--no-post] [--meta-only]

<bpy-python> is a Python with the `bpy` module (Blender 5.2 as a module). The script renders
scene-linear premultiplied float RGBA dumps (.npy) into the work dir, then runs
tools/blender/ships_post.py with the system python3 (numpy + Pillow + scipy) which tone-maps,
down-samples, writes the final PNG assets into game/assets/sprites/... and game/icon.png and builds
docs/previews/ships_sheet.png.

Per ship the work dir also gets <key>.json with the engine nozzle exits taken straight from the model
builders; the post step publishes them as game/assets/sprites/ships/<key>.json. --meta-only builds the
ships and (re)writes only these JSONs, without rendering (seconds instead of minutes).

Render threads default to 2 (env ART_THREADS) because other renders may run in parallel.
"""
from __future__ import annotations

import json
import math
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402

import ships_lib as L  # noqa: E402
import ships_models as M  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SHIP_KEYS = ["interceptor", "fighter", "double_dart", "double_hunter", "blaster", "hunter"]
SS = 4  # super-sampling factor for ship renders


def _args():
	out = {"only": None, "work": os.path.join(tempfile.gettempdir(), "planet_protector_art_ships"),
		"samples": 128, "post": True, "meta_only": False}
	for a in sys.argv[1:]:
		if a.startswith("--only="):
			out["only"] = [s for s in a[7:].split(",") if s]
		elif a.startswith("--work="):
			out["work"] = os.path.abspath(a[7:])
		elif a.startswith("--samples="):
			out["samples"] = int(a[10:])
		elif a == "--no-post":
			out["post"] = False
		elif a == "--meta-only":
			out["meta_only"] = True
	return out


def ship_lights() -> None:
	L.studio_world(strength=0.6)
	L.sun("key", (-0.62, 0.55, 0.75), 4.4, (1.0, 0.95, 0.88), 8.0)
	L.sun("rim", (0.8, -0.5, 0.28), 4.5, (0.35, 0.6, 1.0), 5.0)


def ship_info(key: str, mn, mx, dx: float, dy: float, plumes) -> dict:
	"""Render metadata. engines = nozzle exit centres in GAME px relative to the ship (= canvas) centre,
	+y down (the canvas centre is the world origin after centring); engine_radius in game px."""
	gpu = L.UNIT_PX * 0.5  # game px per Blender unit (2 sprite px per game px)
	eng = sorted(((px + dx) * gpu, -(py + dy) * gpu, pr * gpu) for px, py, _pz, pr in plumes)
	return {"key": key, "bbox_units": [mn.x + dx, mn.y + dy, mx.x + dx, mx.y + dy],
		"size_sprite_px": [(mx.x - mn.x) * L.UNIT_PX, (mx.y - mn.y) * L.UNIT_PX], "ss": SS,
		"shift_units": [dx, dy],
		"engines": [[round(x, 2), round(y, 2)] for x, y, _r in eng],
		"engine_radius": [round(r, 2) for _x, _y, r in eng]}


def write_info(work: str, info: dict) -> None:
	os.makedirs(os.path.join(work, "ships"), exist_ok=True)
	with open(os.path.join(work, "ships", info["key"] + ".json"), "w") as f:
		json.dump(info, f, indent=1)


def build_ship(key: str):
	kit = M.Kit(key)
	objs, plumes = M.BUILDERS[key](kit)
	mn, mx = L.world_bbox(objs)
	dx, dy = -0.5 * (mn.x + mx.x), -0.5 * (mn.y + mx.y)
	L.shift_objects(objs, dx, dy)
	return kit, objs, plumes, ship_info(key, mn, mx, dx, dy, plumes)


def ship_meta(key: str, work: str) -> None:
	"""Builds the ship without rendering and writes only the metadata JSON."""
	L.reset_scene()
	_kit, _objs, _plumes, info = build_ship(key)
	write_info(work, info)
	print("[ships] %s meta: engines=%s" % (key, info["engines"]))


def render_ship(key: str, work: str, samples: int) -> None:
	t0 = time.time()
	L.reset_scene()
	L.setup_render(160 * SS, 112 * SS, samples)
	L.camera_top(16.0)
	ship_lights()
	kit, objs, plumes, info = build_ship(key)
	dx, dy = info["shift_units"]
	L.render_to_npy(os.path.join(work, "ships", key + ".npy"))
	# --- glow pass: exhaust plumes only, ship as hold-out ---
	for ob in objs:
		ob.is_holdout = True
	for ob in list(bpy.context.scene.objects):
		if ob.type == "LIGHT":
			ob.hide_render = True
	L.flat_world((0, 0, 0), 0.0)
	bpy.context.scene.cycles.samples = max(32, samples // 2)
	for i, (px, py, pz, pr) in enumerate(plumes):
		M.plume("plume%d" % i, px + dx, py + dy, pz, pr, kit.exhaust)
	L.render_to_npy(os.path.join(work, "ships", key + "_glow.npy"))
	write_info(work, info)
	print("[ships] %s done in %.1fs  size(px)=%.0fx%.0f" % (key, time.time() - t0, *info["size_sprite_px"]))


def main() -> None:
	a = _args()
	work = a["work"]
	os.makedirs(work, exist_ok=True)
	jobs = a["only"] or (SHIP_KEYS + ["rockets", "logo", "icon"])
	for j in jobs:
		if a["meta_only"]:
			if j in SHIP_KEYS:
				ship_meta(j, work)
			continue
		if j in SHIP_KEYS:
			render_ship(j, work, a["samples"])
		elif j == "rockets":
			import ships_rockets as R
			R.render_rockets(work, a["samples"])
		elif j == "logo":
			import ships_logo as G
			G.render_logo(work, a["samples"])
		elif j == "icon":
			import ships_logo as G
			G.render_icon(work, a["samples"])
		else:
			print("[ships] unknown job", j)
	if a["post"]:
		cmd = ["python3", os.path.join(HERE, "ships_post.py"), "--work=" + work, "--root=" + ROOT]
		print("[ships] post:", " ".join(cmd))
		subprocess.run(cmd, check=True)


if __name__ == "__main__":
	main()
