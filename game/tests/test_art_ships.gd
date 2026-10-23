extends TestBase
## Asset contract of the art-ships package (docs/SPEC.md §16.1, §16.5, §16.6), produced by
## tools/blender/ships.py: player ships + engine glows, rocket sprites, title logo, app icon.

const SHIPS_DIR := "res://assets/sprites/ships/"
const PROJ_DIR := "res://assets/sprites/projectiles/"


func _image(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	return img


## Bounding rect of pixels with alpha >= thr.
func _bbox(img: Image, thr: float) -> Rect2i:
	var x0 := img.get_width()
	var y0 := img.get_height()
	var x1 := -1
	var y1 := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a >= thr:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func _corners_transparent(img: Image) -> bool:
	var w := img.get_width() - 1
	var h := img.get_height() - 1
	for p in [Vector2i(0, 0), Vector2i(w, 0), Vector2i(0, h), Vector2i(w, h)]:
		if img.get_pixelv(p).a > 0.01:
			return false
	return true


func test_ship_sprites_contract() -> void:
	for s in ShipData.SHIPS:
		var key: String = s["key"]
		var img := _image(SHIPS_DIR + key + ".png")
		check(img != null, key + ".png missing")
		if img == null:
			continue
		check_eq(img.get_width(), 160, key + " width")
		check_eq(img.get_height(), 112, key + " height")
		check(_corners_transparent(img), key + " corners must be transparent")
		var bb := _bbox(img, 0.1)
		# visual size 64-72 x 44-50 game px = 128-144 x 88-100 sprite px
		check(bb.size.x >= 128 and bb.size.x <= 144, "%s visual width %d" % [key, bb.size.x])
		check(bb.size.y >= 88 and bb.size.y <= 100, "%s visual height %d" % [key, bb.size.y])
		var c := Vector2(bb.position) + Vector2(bb.size) * 0.5
		check(absf(c.x - 80.0) <= 1.5, "%s not centred horizontally (%.1f)" % [key, c.x])
		check(absf(c.y - 56.0) <= 2.0, "%s not centred vertically (%.1f)" % [key, c.y])


func test_ship_glow_overlays() -> void:
	for s in ShipData.SHIPS:
		var key: String = s["key"]
		var img := _image(SHIPS_DIR + key + "_glow.png")
		check(img != null, key + "_glow.png missing")
		if img == null:
			continue
		check_eq(img.get_size(), Vector2i(160, 112), key + "_glow size")
		var bb := _bbox(img, 0.05)
		check(bb.size.x > 0, key + "_glow is empty")
		# exhaust glow lives at the rear of the ship (lower part of the canvas)
		check(bb.position.y >= 56, "%s_glow starts too high (row %d)" % [key, bb.position.y])
		check(img.get_pixel(80, 0).a < 0.01, key + "_glow top must be empty")


## Gun muzzles must match the shot offsets: single ships at the centre, double ships at +-24 sprite px.
## The Hunter's single logical shot is drawn as a heavy-rocket pair at +-6 game px (ProjectileArt), so its
## two launchers sit at +-12 sprite px.
func test_muzzles_match_shot_offsets() -> void:
	for s in ShipData.SHIPS:
		var key: String = s["key"]
		var img := _image(SHIPS_DIR + key + ".png")
		if img == null:
			continue
		var offsets: Array[float] = ShipData.shot_offsets(int(s["id"]))
		var win := 8
		if int(s["look"]) == ShipData.Look.ROCKET_HEAVY_PAIR:
			offsets = [-6.0, 6.0]
			win = 5
		for off in offsets:
			var cx := 80 + int(roundf(off * 2.0))
			# topmost solid row within +-win px of the expected muzzle column
			var top_row := -1
			var top_x := 0.0
			for y in 40:
				var xs := 0.0
				var n := 0
				for x in range(cx - win, cx + win + 1):
					if img.get_pixel(x, y).a >= 0.5:
						xs += x
						n += 1
				if n > 0:
					top_row = y
					top_x = xs / n
					break
			check(top_row >= 0, "%s: no muzzle near x=%d" % [key, cx])
			if top_row >= 0:
				check(absf(top_x - cx) <= 2.5, "%s muzzle at x=%.1f, expected %d" % [key, top_x, cx])


func test_rocket_sprites() -> void:
	for spec in [["rocket", Vector2i(24, 64), Vector2i(10, 44), Vector2i(18, 58)],
			["rocket_heavy", Vector2i(40, 72), Vector2i(16, 54), Vector2i(30, 68)]]:
		var name: String = spec[0]
		var img := _image(PROJ_DIR + name + ".png")
		check(img != null, name + ".png missing")
		if img == null:
			continue
		check_eq(img.get_size(), spec[1] as Vector2i, name + " canvas")
		check(_corners_transparent(img), name + " corners must be transparent")
		var bb := _bbox(img, 0.1)
		var lo: Vector2i = spec[2]
		var hi: Vector2i = spec[3]
		check(bb.size.x >= lo.x and bb.size.x <= hi.x, "%s visual width %d" % [name, bb.size.x])
		check(bb.size.y >= lo.y and bb.size.y <= hi.y, "%s visual height %d" % [name, bb.size.y])


func test_logo() -> void:
	var img := _image("res://assets/sprites/ui/logo.png")
	check(img != null, "logo.png missing")
	if img == null:
		return
	check_eq(img.get_size(), Vector2i(1600, 420), "logo size")
	# fully transparent border (no hard glow edge), solid letters inside
	var edge_max := 0.0
	for x in range(0, 1600, 4):
		edge_max = maxf(edge_max, maxf(img.get_pixel(x, 0).a, img.get_pixel(x, 419).a))
	for y in range(0, 420, 4):
		edge_max = maxf(edge_max, maxf(img.get_pixel(0, y).a, img.get_pixel(1599, y).a))
	check(edge_max < 0.02, "logo border alpha %.3f" % edge_max)
	var solid := 0
	for y in range(0, 420, 6):
		for x in range(0, 1600, 6):
			if img.get_pixel(x, y).a > 0.9:
				solid += 1
	check(solid > 2500, "logo has too little solid content (%d samples)" % solid)


func test_icon() -> void:
	var img := _image("res://icon.png")
	check(img != null, "icon.png missing")
	if img == null:
		return
	check_eq(img.get_size(), Vector2i(256, 256), "icon size")
	check(img.get_pixel(128, 128).a > 0.99, "icon centre must be opaque")
	check(img.get_pixel(0, 0).a < 0.01, "icon corners are rounded (transparent)")
