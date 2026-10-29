"""Planet Protector Steam library artwork - shared scene description (plain python: no bpy, no numpy).

Used by steam_keyart_render.py (Blender) and steam_keyart_compose.py (2-D), so the 3-D lighting and the
painted atmosphere / flashes agree.

Camera space convention: x right, y up, z towards the viewer.
"""

# The sun: upper right and a little behind the scene -> lit Earth on the right, warm rims on the demons.
SUN_CAM = (0.55, 0.45, -0.70)
SUN_COLOR = (1.0, 0.9, 0.78)
# Light bounced off the Earth below (blue) and a weak cool front fill.
EARTH_CAM = (-0.15, -0.6, -0.8)
EARTH_COLOR = (0.3, 0.56, 1.0)
EARTH_FRONT_CAM = (0.05, -0.75, 0.42)
FILL_CAM = (0.15, 0.25, 1.0)
FILL_COLOR = (0.5, 0.62, 1.0)
# Cool kicker from the upper left behind: the key-art version of the game's outline for black enemies
# (enemy.gdshader outline_color (0.42, 0.47, 0.62)) - a thin cool rim on wing bones, horns, torso, legs.
KICK_CAM = (-0.62, 0.48, -0.62)
KICK_COLOR = (0.56, 0.68, 1.0)

# The Earth is lit a little more from the side than the characters' rim light (artistic licence:
# the day side with oceans and clouds stays visible); image space (x right, y DOWN, z to viewer) for
# the analytic atmosphere.
EARTH_SUN_CAM = (0.88, 0.25, -0.40)
SUN_IMG = (EARTH_SUN_CAM[0], -EARTH_SUN_CAM[1], EARTH_SUN_CAM[2])

ASSETS = {
	"capsule": {"size": (600, 900)},
	"wide": {"size": (920, 430)},
	"header": {"size": (460, 215)},
	"hero": {"size": (3840, 1240)},
	"icon": {"size": (512, 512)},
}

# Earth per asset: centre (cx, cy) and radius R in canvas px; view = globe orientation (lon, lat, roll)
# of planets.planet_matrix (roll 180 = south up: the cloudy southern storm belt fills the cap);
# ss = render super-sampling; cloud_h = cloud shell height; detail = procedural cloud detail amount.
EARTH = {
	# South Pacific, pure ocean under the storm belt
	"hero": {"cx": 2050.0, "cy": 5060.0, "R": 4200.0, "view": (-120.0, 28.0, 180.0), "ss": 1.25, "cloud_h": 0.0018,
		"detail": 0.65},
	# Indian Ocean, rolled so a bright cyclone sits in the lower right next to the ship
	"capsule": {"cx": 330.0, "cy": 1560.0, "R": 900.0, "view": (72.0, 18.0, 196.0), "ss": 1.5, "cloud_h": 0.003,
		"detail": 0.35},
	"wide": {"cx": 470.0, "cy": 1520.0, "R": 1180.0, "view": (-120.0, 28.0, 180.0), "ss": 1.5, "cloud_h": 0.003,
		"detail": 0.45},
	"icon": {"cx": 256.0, "cy": 1010.0, "R": 600.0, "view": (100.0, 26.0, 180.0), "ss": 2.0, "cloud_h": 0.004,
		"detail": 0.0},
}


def earth_window(asset: str, margin_px: float = 24.0):
	"""Render window (x0, x1, y0, y1) in disk units (y up) covering the canvas part of the disk."""
	e = EARTH[asset]
	W, H = ASSETS[asset]["size"]
	R = e["R"]
	x0 = max(-1.02, (0 - margin_px - e["cx"]) / R)
	x1 = min(1.02, (W + margin_px - e["cx"]) / R)
	y_top = min(1.02, (e["cy"] - (0 - margin_px)) / R)
	y_bot = max(-1.02, (e["cy"] - (H + margin_px)) / R)
	return (x0, x1, y_bot, y_top)
