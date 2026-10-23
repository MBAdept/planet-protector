extends TestBase
## Asset contract checks for the background planets and ground strips (docs/SPEC.md §16.3, §16.4).
## Package art-planets. Images are read straight from the PNG files so the test also works headless.

const PLANET_DIR := "res://assets/sprites/planets/"
const GROUND_DIR := "res://assets/sprites/ground/"


func _load_png(path: String) -> Image:
	# absolute path: reading the source PNG directly (tests run on the project, not on an export)
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func test_planet_files_and_metadata() -> void:
	for planet in LevelData.PLANETS:
		var png := PLANET_DIR + planet + ".png"
		check(FileAccess.file_exists(png), "missing " + png)
		check(ResourceLoader.exists(png), "not imported " + png)
		var meta := _load_json(PLANET_DIR + planet + ".json")
		check(meta.has("sphere_diameter_px") and meta.has("center"), "bad json for " + planet)
		if not meta.has("center"):
			continue
		var img := _load_png(png)
		check(img != null, "cannot read " + png)
		if img == null:
			continue
		var d := float(meta["sphere_diameter_px"])
		var c := Vector2(float(meta["center"][0]), float(meta["center"][1]))
		check(d >= 600.0, "%s sphere diameter %f < 600" % [planet, d])
		# SPEC §16.3: square or wide canvas (no portrait images, even with strongly tilted rings)
		check(img.get_width() >= img.get_height(), "%s canvas is portrait (%dx%d)" % [planet, img.get_width(), img.get_height()])
		# the whole sphere lies inside the image
		check(c.x - d * 0.5 >= 0.0 and c.y - d * 0.5 >= 0.0, "%s sphere cut off (top/left)" % planet)
		check(c.x + d * 0.5 <= img.get_width() and c.y + d * 0.5 <= img.get_height(), "%s sphere cut off (bottom/right)" % planet)


func test_planet_alpha_layout() -> void:
	for planet in LevelData.PLANETS:
		var img := _load_png(PLANET_DIR + planet + ".png")
		var meta := _load_json(PLANET_DIR + planet + ".json")
		if img == null or not meta.has("center"):
			failures.append("missing planet " + planet)
			continue
		var c := Vector2(float(meta["center"][0]), float(meta["center"][1]))
		var r := float(meta["sphere_diameter_px"]) * 0.5
		# opaque sphere (sample the lit upper-left quarter and the centre), transparent corners
		check(img.get_pixelv(Vector2i(c)).a > 0.99, planet + " centre not opaque")
		check(img.get_pixelv(Vector2i(c + Vector2(-0.5, -0.5) * r)).a > 0.99, planet + " lit side not opaque")
		check(img.get_pixel(0, 0).a < 0.01, planet + " corner not transparent")
		check(img.get_pixel(img.get_width() - 1, img.get_height() - 1).a < 0.01, planet + " corner not transparent")
		# light from the upper left: the upper-left part is brighter than the lower-right part
		# (ringed planets skipped: the rings may cover the lower-right sample point)
		if planet == "saturn" or planet == "uranus":
			continue
		var ul := img.get_pixelv(Vector2i(c + Vector2(-0.45, -0.45) * r)).get_luminance()
		var lr := img.get_pixelv(Vector2i(c + Vector2(0.6, 0.6) * r)).get_luminance()
		check(ul > lr, "%s not lit from the upper left (%f vs %f)" % [planet, ul, lr])


func test_ground_strips() -> void:
	for planet in LevelData.PLANETS:
		var png := GROUND_DIR + planet + ".png"
		check(ResourceLoader.exists(png), "not imported " + png)
		var img := _load_png(png)
		check(img != null, "cannot read " + png)
		if img == null:
			continue
		check_eq(img.get_width(), 1920, planet + " ground width")
		check_eq(img.get_height(), 70, planet + " ground height")
		# row 0 is the surface line: fully opaque everywhere
		var opaque := true
		for x in range(0, img.get_width(), 7):
			if img.get_pixel(x, 0).a < 0.999:
				opaque = false
		check(opaque, planet + " ground row 0 not opaque")
		# horizontally tileable: the step across the seam is like a step between neighbouring columns
		var seam := 0.0
		var inner := 0.0
		for y in img.get_height():
			var a := img.get_pixel(0, y)
			var b := img.get_pixel(img.get_width() - 1, y)
			seam += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			var p := img.get_pixel(960, y)
			var q := img.get_pixel(961, y)
			inner += absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)
		check(seam <= inner * 3.0 + 0.5, "%s ground seam visible (%f vs %f)" % [planet, seam, inner])
