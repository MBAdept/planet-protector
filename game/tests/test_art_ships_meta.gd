extends TestBase
## art-ships: engine metadata (assets/sprites/ships/<key>.json) and clean sprite edges.
## The PNG files are read raw (Image.load_from_file), not through the importer, because Godot's
## fix_alpha_border would hide colour problems of faint edge pixels.

const SHIPS_DIR := "res://assets/sprites/ships/"
## Nozzles per ship as built in tools/blender/ships_models.py.
const ENGINE_COUNT := {"interceptor": 1, "fighter": 2, "double_dart": 4, "double_hunter": 4, "blaster": 3, "hunter": 2}


func _raw(path: String) -> Image:
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return null
	var img := Image.load_from_file(abs_path)
	if img != null and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _meta(key: String) -> Dictionary:
	var path := SHIPS_DIR + key + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func test_engine_meta_contract() -> void:
	for s in ShipData.SHIPS:
		var key: String = s["key"]
		var m := _meta(key)
		check(not m.is_empty(), key + ".json missing or invalid")
		if m.is_empty():
			continue
		check(m.get("canvas") == [160, 112] or m.get("canvas") == [160.0, 112.0], key + ".json canvas")
		var eng: Array = m.get("engines", [])
		var rad: Array = m.get("engine_radius", [])
		check_eq(eng.size(), int(ENGINE_COUNT[key]), key + " engine count")
		check_eq(rad.size(), eng.size(), key + " engine_radius count")
		var prev_x := -1e9
		var sum_x := 0.0
		for i in eng.size():
			var x := float(eng[i][0])
			var y := float(eng[i][1])
			check(x >= prev_x, "%s engines not sorted by x" % key)
			prev_x = x
			sum_x += x
			# rear half of the 80 x 56 game px canvas, inside it
			check(y > 10.0 and y < 28.0, "%s engine %d y=%.2f outside the rear" % [key, i, y])
			check(absf(x) < 30.0, "%s engine %d x=%.2f" % [key, i, x])
			check(float(rad[i]) > 0.5 and float(rad[i]) < 4.0, "%s engine %d radius %s" % [key, i, str(rad[i])])
		check(absf(sum_x) < 0.05, "%s engines not symmetric (sum x %.2f)" % [key, sum_x])


## Every engine sits on solid nozzle geometry with its exhaust glow right behind (below) the exit.
func test_engines_match_sprite_and_glow() -> void:
	for s in ShipData.SHIPS:
		var key: String = s["key"]
		var m := _meta(key)
		var ship := _raw(SHIPS_DIR + key + ".png")
		var glow := _raw(SHIPS_DIR + key + "_glow.png")
		if m.is_empty() or ship == null or glow == null:
			continue
		for e in m.get("engines", []):
			var sx := int(roundf(80.0 + 2.0 * float(e[0])))
			var sy := int(roundf(56.0 + 2.0 * float(e[1])))
			var body := 0.0
			for dy in range(1, 4):
				body = maxf(body, ship.get_pixel(sx, sy - dy).a)
			check(body > 0.6, "%s: no nozzle geometry above engine at (%d, %d)" % [key, sx, sy])
			var hot := 0.0
			for dy in range(0, 6):
				for dx in range(-1, 2):
					var c := glow.get_pixel(sx + dx, sy + dy)
					hot = maxf(hot, maxf(c.r, maxf(c.g, c.b)) * c.a)
			check(hot > 0.5, "%s: no exhaust glow behind engine at (%d, %d) (%.2f)" % [key, sx, sy, hot])


## No resampling halo: every visible pixel must be connected (4-neighbourhood through alpha > 0) to the
## solid body, i.e. there is no faint detached 'ghost' outline around the silhouette, and faint edge
## pixels carry a real colour instead of clipped black.
func test_sprite_edges_have_no_ghost_ring() -> void:
	var paths: Array[String] = []
	for s in ShipData.SHIPS:
		paths.append(SHIPS_DIR + "%s.png" % s["key"])
	paths.append("res://assets/sprites/projectiles/rocket.png")
	paths.append("res://assets/sprites/projectiles/rocket_heavy.png")
	for p in paths:
		var img := _raw(p)
		if img == null:
			continue
		var w := img.get_width()
		var h := img.get_height()
		var seen := PackedByteArray()
		seen.resize(w * h)
		var stack: Array[int] = []
		for y in h:
			for x in w:
				if img.get_pixel(x, y).a >= 0.5:
					seen[y * w + x] = 1
					stack.append(y * w + x)
		while not stack.is_empty():
			var i: int = stack.pop_back()
			var cx := i % w
			var cy := i / w
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := cx + d.x
				var ny := cy + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j := ny * w + nx
				if seen[j] == 0 and img.get_pixel(nx, ny).a8 > 0:
					seen[j] = 1
					stack.append(j)
		var detached := 0
		var black_faint := 0
		for y in h:
			for x in w:
				var c := img.get_pixel(x, y)
				if c.a8 > 0 and seen[y * w + x] == 0:
					detached += 1
				if c.a8 > 0 and c.a8 <= 16 and c.r8 == 0 and c.g8 == 0 and c.b8 == 0:
					black_faint += 1
		check_eq(detached, 0, "%s: faint pixels detached from the silhouette (ghost ring)" % p.get_file())
		check_eq(black_faint, 0, "%s: faint edge pixels with clipped black colour" % p.get_file())
