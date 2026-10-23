extends TestBase
## Reviewer checks for package art-planets (docs/SPEC.md §15, §16.3, §16.4).
## Measures the real alpha edge of each sphere against the JSON contract, checks that the ringed
## planets really have rings outside the sphere, and that the ground strips have a flat, uniform
## surface row and no visible horizontal seam.

const PLANET_DIR := "res://assets/sprites/planets/"
const GROUND_DIR := "res://assets/sprites/ground/"
const RINGED := ["uranus", "saturn"]


func _load_png(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _meta(planet: String) -> Dictionary:
	var path := PLANET_DIR + planet + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## Bilinear alpha sample in continuous image coordinates (pixel i covers [i, i+1)).
func _alpha_at(img: Image, p: Vector2) -> float:
	var x := p.x - 0.5
	var y := p.y - 0.5
	var x0 := int(floor(x))
	var y0 := int(floor(y))
	var fx := x - x0
	var fy := y - y0
	var s := 0.0
	for j in 2:
		for i in 2:
			var xi := x0 + i
			var yj := y0 + j
			var a := 0.0
			if xi >= 0 and yj >= 0 and xi < img.get_width() and yj < img.get_height():
				a = img.get_pixel(xi, yj).a
			s += a * (fx if i == 1 else 1.0 - fx) * (fy if j == 1 else 1.0 - fy)
	return s


## Distance from c along dir to the first alpha < 0.5 crossing (0.1 px steps).
func _edge_distance(img: Image, c: Vector2, dir: Vector2, max_r: float) -> float:
	var t := 0.0
	while t < max_r:
		if _alpha_at(img, c + dir * t) < 0.5:
			return t
		t += 0.1
	return max_r


func test_json_matches_measured_sphere_edge() -> void:
	for planet in LevelData.PLANETS:
		var img := _load_png(PLANET_DIR + planet + ".png")
		var meta := _meta(planet)
		if img == null or not meta.has("center"):
			failures.append("missing planet " + planet)
			continue
		var r := float(meta["sphere_diameter_px"]) * 0.5
		var c := Vector2(float(meta["center"][0]), float(meta["center"][1]))
		var dists: Array[float] = []
		for k in 8:
			var ang := TAU * k / 8.0
			dists.append(_edge_distance(img, c, Vector2(cos(ang), -sin(ang)), r * 1.4))
		# the closest edge is the bare sphere limb (atmosphere / rings only push it outwards)
		var dmin: float = dists.min()
		check(absf(dmin - r) <= 2.0, "%s: measured sphere radius %.1f vs JSON %.1f (%s)" % [planet, dmin, r, str(dists)])
		# right (0 deg) and down (270 deg) lie on the dark side: no atmosphere, no ring for these
		# views -> both must hit the bare limb at R, which pins the JSON centre in x and y
		check(absf(dists[0] - r) <= 1.5, "%s: JSON centre off in x (right edge at %.1f, R %.1f)" % [planet, dists[0], r])
		check(absf(dists[6] - r) <= 1.5, "%s: JSON centre off in y (bottom edge at %.1f, R %.1f)" % [planet, dists[6], r])
		# the lit side may carry a few px of opaque atmosphere, never more than that
		if not planet in RINGED:
			var dmax: float = dists.max()
			check(dmax - r <= 10.0, "%s: opaque halo %.1f px beyond the sphere" % [planet, dmax - r])


func test_ringed_planets_have_rings_outside_sphere() -> void:
	for planet in RINGED:
		var img := _load_png(PLANET_DIR + planet + ".png")
		var meta := _meta(planet)
		if img == null or not meta.has("center"):
			failures.append("missing planet " + planet)
			continue
		var r := float(meta["sphere_diameter_px"]) * 0.5
		var c := Vector2(float(meta["center"][0]), float(meta["center"][1]))
		var ring_hits := 0
		var far := 0.0
		for k in 72:
			var ang := TAU * k / 72.0
			var dir := Vector2(cos(ang), -sin(ang))
			var t := r * 1.3
			var hit := false
			while t < r * 2.6:
				if _alpha_at(img, c + dir * t) > 0.4:
					hit = true
					far = maxf(far, t)
				t += 1.0
			if hit:
				ring_hits += 1
		# a tilted ring ellipse leaves the sphere along its major axis (along the minor axis it
		# passes in front of / behind the planet), so at least a third of all directions hit it
		check(ring_hits >= 24, "%s: ring found outside 1.3 R in only %d of 72 directions" % [planet, ring_hits])
		print("    [review] %s ring: %d of 72 directions, reaches %.2f R" % [planet, ring_hits, far / r])
		check(far >= r * 1.9, "%s: ring reaches only %.2f R" % [planet, far / r])


func test_ground_surface_row_flat_and_strip_opaque() -> void:
	for planet in LevelData.PLANETS:
		var img := _load_png(GROUND_DIR + planet + ".png")
		if img == null:
			failures.append("missing ground " + planet)
			continue
		var w := img.get_width()
		var h := img.get_height()
		var opaque := true
		for y in range(0, h, 3):
			for x in range(0, w, 5):
				if img.get_pixel(x, y).a < 0.999:
					opaque = false
		check(opaque, planet + " ground strip not fully opaque")
		# row 0 = flat surface line: one uniform colour along the whole width
		var mean := Vector3.ZERO
		var n := 0
		for x in range(0, w, 2):
			var p := img.get_pixel(x, 0)
			mean += Vector3(p.r, p.g, p.b)
			n += 1
		mean /= n
		var max_dev := 0.0
		for x in range(0, w, 2):
			var p := img.get_pixel(x, 0)
			max_dev = maxf(max_dev, (Vector3(p.r, p.g, p.b) - mean).length())
		check(max_dev < 0.12, "%s ground row 0 not a uniform surface line (max deviation %.3f)" % [planet, max_dev])
