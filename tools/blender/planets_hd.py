"""High-resolution Earth for the victory screen (widescreen round, docs/SPEC.md §11.2, §16.3).

The victory screen draws the Earth up to 1280 logical px wide; the 16:9 modes render the canvas at x1.5 / x2.0
(1920 / 2560 px). The in-game sprite planets/earth.png (sphere 640 px) would be upscaled 3x / 4x there and look
blocky next to the crisp text, so the victory screen draws its own render of the SAME planet - same procedural
textures, view, lighting and post step as planets.py / planets_post.py - with a sphere of HD_DIAMETER px:
game/assets/sprites/planets/earth_hd.png + earth_hd.json (at most a 2x upscale in every mode, like the in-game
sprite in the classic 1280 x 960 window).

Usage:
  python3 tools/blender/planets_hd.py [--work=DIR] [--samples=N] [--threads=N] [--out=DIR]

Steps: planets_textures.py (system python3, cached in <work>/tex), the Cycles render in the Blender python
($BPY_PYTHON, see planets.py) and planets_post.py (system python3), both with planets_config.SPHERE_RADIUS_PX
patched to HD_DIAMETER / 2. Nothing else in the pipeline changes, so the in-game sprites stay as they are.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

PLANET = "earth"
SUFFIX = "_hd"
HD_DIAMETER = 1280
OUT_DEFAULT = os.path.join(ROOT, "game", "assets", "sprites", "planets")


def _opts() -> dict:
	return {a.split("=")[0]: (a.split("=", 1)[1] if "=" in a else True) for a in sys.argv[1:] if a.startswith("--")}


def _patch_radius() -> None:
	import planets_config
	planets_config.SPHERE_RADIUS_PX = HD_DIAMETER // 2


def render_stage(work: str, samples: int, threads: int) -> None:
	"""Inside the Blender python: planets.render_planet with the bigger sphere (and more render threads)."""
	_patch_radius()
	import planets  # noqa: E402  (binds the patched SPHERE_RADIUS_PX)
	reset = planets.reset_scene

	def reset_scene(w: int, h: int, s: int):
		sc = reset(w, h, s)
		sc.render.threads = threads
		return sc

	planets.reset_scene = reset_scene
	planets.render_planet(PLANET, work, samples)


def post_stage(work: str, out_dir: str) -> None:
	"""System python3: planets_post.process into a scratch folder, then stored as earth_hd.png / .json."""
	_patch_radius()
	import planets_post  # noqa: E402
	tmp = os.path.join(work, "hd_out")
	planets_post.process(PLANET, work, tmp)
	os.makedirs(out_dir, exist_ok=True)
	for ext in ("png", "json"):
		shutil.copyfile(os.path.join(tmp, f"{PLANET}.{ext}"), os.path.join(out_dir, f"{PLANET}{SUFFIX}.{ext}"))
	print(f"[planets_hd] wrote {os.path.join(out_dir, PLANET + SUFFIX)}.png / .json", flush=True)


def main() -> None:
	o = _opts()
	work = str(o.get("--work", os.path.join(tempfile.gettempdir(), "planet_protector_planets_hd")))
	samples = int(o.get("--samples", 128))
	threads = int(o.get("--threads", os.cpu_count() or 2))
	if o.get("--stage") == "render":
		render_stage(work, samples, threads)
		return
	os.makedirs(work, exist_ok=True)
	py3 = os.environ.get("PYTHON3", shutil.which("python3") or "python3")
	subprocess.run([py3, os.path.join(HERE, "planets_textures.py"), work, PLANET], check=True)
	subprocess.run([_bpy_python(), os.path.abspath(__file__), "--stage=render", f"--work={work}",
		f"--samples={samples}", f"--threads={threads}"], check=True)
	post_stage(work, os.path.realpath(str(o.get("--out", OUT_DEFAULT))))


def _bpy_python() -> str:
	"""The Blender python of planets.py ($BPY_PYTHON or its DEFAULT_BPY), read without importing planets.py
	(importing it outside Blender would re-execute it)."""
	if os.environ.get("BPY_PYTHON"):
		return os.environ["BPY_PYTHON"]
	with open(os.path.join(HERE, "planets.py")) as f:
		for line in f:
			if line.startswith("DEFAULT_BPY"):
				return line.split("=", 1)[1].strip().strip('"')
	return "python3"


if __name__ == "__main__":
	main()
