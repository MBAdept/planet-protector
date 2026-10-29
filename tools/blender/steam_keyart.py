"""Planet Protector - Steam library artwork ("Steam grid" assets), rendered from the game's own models.

Usage (system python3 with numpy + scipy + Pillow; Blender runs as a python module, see BPY_PYTHON):

    python3 tools/blender/steam_keyart.py                     # everything -> steam-grid/ (~25 min on 2 threads,
                                                              # +8 min once for the Earth textures)
    python3 tools/blender/steam_keyart.py --compose-only      # only the 2-D step from the kept renders (~1.5 min)
    python3 tools/blender/steam_keyart.py --only=demon_lead,ship    # re-render these, then compose
    python3 tools/blender/steam_keyart.py --draft             # quick low-res check (~3 min) -> <work>/draft/out

Options:
  --out=DIR       where the six images go (default: <repo>/steam-grid; with --draft: <work>/draft/out, so a
                  draft never replaces the finished images unless --out names steam-grid/ explicitly)
  --work=DIR      renders, Earth textures and the review sheets contact_sheet.png / thumbnail_sheet.png
                  (default: <tmp>/planet_protector_steam_keyart; the renders are kept for --compose-only)
  --draft         1/3-size renders with few samples and 2048 px Earth textures (layout checks, soft output)
  --compose-only  skip Blender and compose from <work>/renders
  --only=a,b,...  render only these elements, then compose: earth_hero, earth_capsule, earth_wide, earth_icon,
                  demon_lead, demon_b, demon_c, demon_d, demon_e, icon_demon, ship, icon_ship
Environment:
  BPY_PYTHON   a python with Blender's bpy module (bpy 5.x; default: the bpyenv python used by planets.py)
  ART_THREADS  Cycles render threads (default 2, other renders may run in parallel)

Pipeline:
  1. planets_textures.py paints the game's Earth textures at 8192 x 4096 (once, cached in <work>/earth/tex).
  2. steam_keyart_render.py (Blender, Cycles CPU) renders every 3-D element on its own: the game's Earth
     (planets.py materials), the crowned Earth demon (enemies_designs.earth + WingRig) in six poses, the
     Interceptor (ships_models) with its exhaust - see steam_keyart_models.py / steam_keyart_layout.py.
  3. steam_keyart_compose.py paints space, atmosphere, lasers, fireballs and glows around them, grades the
     images with the game's tone curve and sets the game's logo (game/assets/sprites/ui/logo.png).

Outputs (Steam names):
  capsule_600x900.png        Library Capsule (portrait grid tile)
  capsule_wide_920x430.png   Wide Capsule / Grid ("recent games" tile)
  header_460x215.png         Header
  hero_3840x1240.png         Library Hero (no text: Steam lays the logo over it)
  logo.png                   Library Logo (1280 px wide, transparent)
  icon_512.png               Icon (the game icon's rounded frame, transparent corners)
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True  # keep tools/blender free of __pycache__ from these runs

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("PP_REPO") or os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools", "blender")
for _p in (TOOLS, HERE):
	if _p not in sys.path:
		sys.path.insert(0, _p)

DEFAULT_BPY = "/tmp/claude-0/-home-user/0a1ab13c-d1d4-5f9b-bc34-b18cd450004b/scratchpad/tools/bpyenv/bin/python"
EARTH_TEX_RES = 8192
DRAFT_TEX_RES = 2048


def log(*a):
	print("[steam_keyart]", *a, flush=True)


def _args():
	o = {"out": None, "work": os.path.join(tempfile.gettempdir(), "planet_protector_steam_keyart"),
		"draft": False, "compose_only": False, "only": None}
	for a in sys.argv[1:]:
		if a.startswith("--out="):
			o["out"] = os.path.abspath(a[6:])
		elif a.startswith("--work="):
			o["work"] = os.path.abspath(a[7:])
		elif a == "--draft":
			o["draft"] = True
		elif a == "--compose-only":
			o["compose_only"] = True
		elif a.startswith("--only="):
			o["only"] = a[7:]
		elif a in ("-h", "--help"):
			print(__doc__)
			sys.exit(0)
		else:
			sys.exit("steam_keyart.py: unknown option %s (see --help)" % a)
	if o["out"] is None:
		# soft draft images must not overwrite the finished assets in steam-grid/ by accident
		o["out"] = os.path.join(o["work"], "draft", "out") if o["draft"] else os.path.join(ROOT, "steam-grid")
	return o


def earth_textures(work: str, res: int) -> str:
	"""The game's procedural Earth textures (planets_textures.py) at res x res/2, cached."""
	d = os.path.join(work, "earth" if res == EARTH_TEX_RES else "earth_%d" % res)
	tex = os.path.join(d, "tex")
	if not os.path.exists(os.path.join(tex, "earth_clouds.png")):
		import planets_textures  # noqa: E402  (game: tools/blender, system python3)
		log("painting the Earth textures at %d x %d (once) ..." % (res, res // 2))
		planets_textures.generate(d, ["earth"], res, res // 2)
	return tex


def render(work: str, tex: str, draft: bool, only: str | None) -> None:
	bpy_python = os.environ.get("BPY_PYTHON", DEFAULT_BPY)
	cmd = [bpy_python, os.path.join(HERE, "steam_keyart_render.py"), "--work=" + work, "--tex=" + tex]
	if draft:
		cmd.append("--draft")
	if only:
		cmd.append("--only=" + only)
	env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
	if "PP_REPO" not in env:
		env["PP_REPO"] = ROOT
	log("Blender:", " ".join(cmd[1:]))
	subprocess.run(cmd, check=True, env=env)


def main() -> None:
	o = _args()
	t0 = time.time()
	work = os.path.join(o["work"], "draft") if o["draft"] else o["work"]
	os.makedirs(work, exist_ok=True)
	if not o["compose_only"]:
		tex = earth_textures(o["work"], DRAFT_TEX_RES if o["draft"] else EARTH_TEX_RES)
		render(work, tex, o["draft"], o["only"])
	import steam_keyart_compose as C  # noqa: E402
	ok = C.run(os.path.join(work, "renders"), o["out"], os.path.join(work, "sheets"))
	log("done in %.1f min -> %s (review sheets in %s)" % ((time.time() - t0) / 60.0, o["out"], os.path.join(work, "sheets")))
	sys.exit(0 if ok else 1)


if __name__ == "__main__":
	main()
