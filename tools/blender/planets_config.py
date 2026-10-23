"""Per-planet view / lighting / atmosphere settings shared by planets.py (Blender) and planets_post.py.

Plain python (no numpy, no bpy). Blender world axes: +X right, +Y away from the camera, +Z up.
"""

SPHERE_RADIUS_PX = 320          # rendered sphere diameter = 640 px (SPEC §16.3: >= 600)

# Direction TO the rim (back) light: from behind / lower right, only grazes the night-side limb.
RIM_DIR = (0.50, 1.0, -0.30)

# Direction TO the key light: upper left, somewhat towards the viewer -> lit disk with the
# terminator crescent at the lower right.
LIGHT_DIR = (-0.66, -0.40, 0.64)

# Canvas sizes are derived from the geometry (planets.py: canvas_size); the post step crops.
# view_lon: longitude facing the camera; view_lat: sub-observer latitude (tilts the north pole
# towards the viewer); roll: clockwise rotation of the pole in the image (degrees).
PLANETS = {
	"neptune": {
		"view_lon": 10.0, "view_lat": -4.0, "roll": -10.0,
		"roughness": 0.62, "specular": 0.30, "key_strength": 1.12,
		"rim_strength": 0.05, "rim_color": (0.35, 0.55, 1.0),
		"atmo": {"color": (0.42, 0.66, 1.0), "width": 0.022, "outer": 0.55, "inner": 0.45, "inner_width": 0.16},
	},
	"uranus": {
		"view_lon": 0.0, "view_lat": 30.0, "roll": -60.0,
		"rings": (1.58, 2.06), "ring_translucency": 0.35, "ring_emission": 0.05,
		"roughness": 0.70, "specular": 0.25, "key_strength": 1.05,
		"rim_strength": 0.04, "rim_color": (0.5, 0.85, 0.9),
		"atmo": {"color": (0.70, 0.95, 1.0), "width": 0.020, "outer": 0.45, "inner": 0.40, "inner_width": 0.16},
	},
	"saturn": {
		"view_lon": 0.0, "view_lat": 24.0, "roll": -14.0,
		"rings": (1.22, 2.36), "ring_translucency": 0.25,
		"roughness": 0.70, "specular": 0.22, "key_strength": 1.05,
		"rim_strength": 0.04, "rim_color": (1.0, 0.85, 0.6),
		"atmo": {"color": (1.0, 0.90, 0.70), "width": 0.012, "outer": 0.18, "inner": 0.18, "inner_width": 0.12},
	},
	"jupiter": {
		"view_lon": -4.0, "view_lat": 9.0, "roll": -8.0,
		"roughness": 0.70, "specular": 0.22, "key_strength": 1.0,
		"rim_strength": 0.04, "rim_color": (1.0, 0.8, 0.6),
		"atmo": {"color": (1.0, 0.86, 0.68), "width": 0.012, "outer": 0.18, "inner": 0.18, "inner_width": 0.12},
	},
	"mars": {
		"view_lon": -66.0, "view_lat": 10.0, "roll": -10.0,
		"roughness": 0.85, "specular": 0.18, "key_strength": 1.0, "bump": 0.03,
		"rim_strength": 0.04, "rim_color": (1.0, 0.6, 0.45),
		"atmo": {"color": (1.0, 0.68, 0.48), "width": 0.016, "outer": 0.45, "inner": 0.30, "inner_width": 0.16},
	},
	"earth": {
		"view_lon": 14.0, "view_lat": 16.0, "roll": -14.0,
		"roughness": 0.85, "specular": 0.2, "specular_water": 0.45, "key_strength": 1.05, "bump": 0.006,
		"clouds": 0.006,
		"rim_strength": 0.035, "rim_color": (0.4, 0.6, 1.0),
		"atmo": {"color": (0.40, 0.66, 1.0), "width": 0.035, "outer": 1.0, "inner": 0.70, "inner_width": 0.22},
	},
}
