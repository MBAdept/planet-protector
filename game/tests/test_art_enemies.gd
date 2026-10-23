extends TestBase
## Asset contract of the enemy flap strips (docs/SPEC.md §16.2), produced by tools/blender/enemies.py.

const DIR := "res://assets/sprites/enemies/"
const FRAMES := 16
const FW := 256
const FH := 160
const MARGIN := 4
const HALF_W := 128
const HALF_H := 80


func _meta(planet: String) -> Dictionary:
	var path := DIR + planet + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


## Level-0 image of the strip (mipmaps stripped unless keep_mipmaps).
func _image(planet: String, keep_mipmaps := false) -> Image:
	var path := DIR + planet + ".png"
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	if img != null and img.has_mipmaps() and not keep_mipmaps:
		img = img.duplicate() as Image
		img.clear_mipmaps()
	return img


func test_json_contract() -> void:
	for planet in LevelData.PLANETS:
		var m := _meta(planet)
		check(not m.is_empty(), "%s.json missing or invalid" % planet)
		if m.is_empty():
			continue
		check_eq(int(m.get("frames", 0)), FRAMES, planet + " frames")
		check_eq(int(m.get("frame_w", 0)), FW, planet + " frame_w")
		check_eq(int(m.get("frame_h", 0)), FH, planet + " frame_h")
		check_near(float(m.get("px_per_game_px", 0.0)), 2.0, 1e-6, planet + " px_per_game_px")
		check_near(float(m.get("width_factor", 0.0)), float(LevelData.PLANET_WIDTH_FACTOR[planet]), 1e-6,
			planet + " width_factor")
		var top := int(m.get("content_top", -1))
		var bottom := int(m.get("content_bottom", -1))
		check(top >= MARGIN and bottom <= FH - 1 - MARGIN and top < bottom,
			"%s content rows %d..%d" % [planet, top, bottom])


func test_strip_size_margins_and_span() -> void:
	for planet in LevelData.PLANETS:
		var img := _image(planet)
		check(img != null, planet + ".png missing")
		if img == null:
			continue
		check_eq(img.get_width(), FW * FRAMES, planet + " strip width")
		check_eq(img.get_height(), FH, planet + " strip height")
		var m := _meta(planet)
		var union := Rect2i()
		var widest := 0
		for f in FRAMES:
			var r := img.get_region(Rect2i(f * FW, 0, FW, FH)).get_used_rect()
			check(r.size.x > 0, "%s frame %d empty" % [planet, f])
			check(r.position.x >= MARGIN and r.position.y >= MARGIN and r.end.x <= FW - MARGIN
				and r.end.y <= FH - MARGIN, "%s frame %d content %s violates the %d px margin" % [planet, f, r, MARGIN])
			union = r if f == 0 else union.merge(r)
			widest = maxi(widest, r.size.x)
		var target := 180.0 * float(LevelData.PLANET_WIDTH_FACTOR[planet])
		check(absf(widest - target) <= target * 0.06, "%s widest span %d px, expected ~%d" % [planet, widest, int(target)])
		if not m.is_empty():
			check_eq(union.position.y, int(m["content_top"]), planet + " content_top")
			check_eq(union.end.y - 1, int(m["content_bottom"]), planet + " content_bottom")


## Children are drawn at 0.40/0.45 scale (~0.2 of the sprite resolution): the strips need mipmaps (drawn with
## TEXTURE_FILTER_LINEAR_WITH_MIPMAPS) or the wings alias and sparkle. Mip levels up to 3 (8 px texels) must not
## mix neighbouring frames, so the content keeps at least MIP_MARGIN px to the left/right frame borders.
const MIP_MARGIN := 8


func test_mipmaps_for_children() -> void:
	for planet in LevelData.PLANETS:
		var mip := _image(planet, true)
		if mip == null:
			continue
		check(mip.has_mipmaps(), "%s.png is imported without mipmaps (set mipmaps/generate=true)" % planet)
		var base := _image(planet)
		for f in FRAMES:
			var r := base.get_region(Rect2i(f * FW, 0, FW, FH)).get_used_rect()
			check(r.position.x >= MIP_MARGIN and r.end.x <= FW - MIP_MARGIN,
				"%s frame %d content x %d..%d is closer than %d px to the frame border" % [
				planet, f, r.position.x, r.end.x - 1, MIP_MARGIN])


func test_logical_center_and_eyes() -> void:
	for planet in LevelData.PLANETS:
		var img := _image(planet)
		if img == null:
			continue
		var frame := img.get_region(Rect2i(0, 0, FW, FH))
		# symmetric creature: horizontal content centre ~ frame centre
		var r := frame.get_used_rect()
		check(absf((r.position.x + r.end.x) * 0.5 - float(HALF_W)) <= 3.0, "%s not horizontally centred: %s" % [planet, r])
		# the body covers the frame centre (logical centre of the creature)
		check(frame.get_pixel(HALF_W, HALF_H).a > 0.9, planet + " frame centre is not on the body")
		# emissive eyes exist in the blue channel, in the upper half
		var eye_px := 0
		for y in range(0, HALF_H):
			for x in range(HALF_W - 24, HALF_W + 24):
				var c := frame.get_pixel(x, y)
				if c.a > 0.5 and c.b > 0.6:
					eye_px += 1
		check(eye_px >= 6, "%s: no emissive eyes found (B channel)" % planet)
