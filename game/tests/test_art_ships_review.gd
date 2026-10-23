extends TestBase
## Reviewer checks for the art-ships package (docs/SPEC.md §16.1, §16.5) that complement
## test_art_ships.gd: straight (not premultiplied) alpha on sprite edges, and rocket nozzles lining up
## with the procedural flame origin used by ProjectileArt._rocket (nozzle_y 12.5 / 15.5 game px,
## textures drawn at half size).


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


func _lum(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b))


## Semi-transparent edge pixels must carry their full colour (straight alpha). If the PNG held
## premultiplied colour, edge pixels with alpha 0.25..0.8 would be ~alpha times darker than their opaque
## neighbour (median ratio ≈ 0.5); straight alpha keeps the ratio close to 1 (rendered rims are a bit darker).
func _edge_ratio(img: Image) -> float:
	var ratios: Array[float] = []
	var w := img.get_width()
	var h := img.get_height()
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var c := img.get_pixel(x, y)
			if c.a < 0.25 or c.a > 0.8:
				continue
			var best := -1.0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := img.get_pixel(x + d.x, y + d.y)
				if n.a > 0.98:
					best = maxf(best, _lum(n))
			if best > 0.2:
				ratios.append((_lum(c) + 0.02) / (best + 0.02))
	if ratios.is_empty():
		return 1.0
	ratios.sort()
	return ratios[ratios.size() / 2]


func test_ship_and_rocket_edges_are_straight_alpha() -> void:
	var paths: Array[String] = []
	for s in ShipData.SHIPS:
		paths.append("res://assets/sprites/ships/%s.png" % s["key"])
	paths.append("res://assets/sprites/projectiles/rocket.png")
	paths.append("res://assets/sprites/projectiles/rocket_heavy.png")
	for p in paths:
		var img := _image(p)
		if img == null:
			continue
		var r := _edge_ratio(img)
		check(r > 0.7, "%s: edge pixels look premultiplied/dark (median ratio %.2f)" % [p.get_file(), r])


## Lowest row with alpha >= 0.1 at the canvas centre column, converted to game px below the rocket centre.
func _nozzle_game_y(img: Image) -> float:
	var cx := img.get_width() / 2
	for y in range(img.get_height() - 1, -1, -1):
		for x in range(cx - 2, cx + 2):
			if img.get_pixel(x, y).a >= 0.1:
				return (float(y) + 1.0 - img.get_height() * 0.5) * 0.5
	return -999.0


func test_rocket_nozzles_match_flame_origin() -> void:
	for spec in [["rocket", 12.5], ["rocket_heavy", 15.5]]:
		var img := _image("res://assets/sprites/projectiles/%s.png" % spec[0])
		if img == null:
			continue
		var ny := _nozzle_game_y(img)
		check(absf(ny - float(spec[1])) <= 1.5, "%s nozzle ends at %.1f game px, flame starts at %.1f"
			% [spec[0], ny, spec[1]])
