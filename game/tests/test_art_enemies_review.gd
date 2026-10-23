extends TestBase
## Review checks for the enemy flap strips (docs/SPEC.md §16.2) that go beyond the format contract:
## every frame must be ONE connected creature. Thin anti-aliased features (antenna stalks, crown spike
## tips) may break up at alpha 0.5, so only detached pieces of at least MIN_PART px count as defects
## (e.g. a lower leg cut off at the knee by a transparent seam).

const DIR := "res://assets/sprites/enemies/"
const FRAMES := 16
const FW := 256
const FH := 160
const ALPHA_MIN := 128      # alpha > 0.5
const MIN_PART := 40        # px; a detached piece this large is a body part, not an AA speck


func _alpha_strip(planet: String) -> PackedByteArray:
	var path := DIR + planet + ".png"
	if not ResourceLoader.exists(path):
		return PackedByteArray()
	var tex := load(path) as Texture2D
	if tex == null:
		return PackedByteArray()
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var a := PackedByteArray()
	a.resize(img.get_width() * img.get_height())
	for i in a.size():
		a[i] = data[i * 4 + 3]
	return a


## Sizes of the 8-connected components of alpha > ALPHA_MIN in one frame, largest first.
func _component_sizes(alpha: PackedByteArray, strip_w: int, frame: int) -> Array[int]:
	var seen := PackedByteArray()
	seen.resize(FW * FH)
	var sizes: Array[int] = []
	var stack := PackedInt32Array()
	for y in FH:
		for x in FW:
			var k := y * FW + x
			if seen[k] != 0 or alpha[y * strip_w + frame * FW + x] <= ALPHA_MIN:
				continue
			seen[k] = 1
			stack.append(k)
			var n := 0
			while not stack.is_empty():
				var c := stack[stack.size() - 1]
				stack.remove_at(stack.size() - 1)
				n += 1
				var cx := c % FW
				@warning_ignore("integer_division")
				var cy := c / FW
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx := cx + dx
						var ny := cy + dy
						if nx < 0 or ny < 0 or nx >= FW or ny >= FH:
							continue
						var nk := ny * FW + nx
						if seen[nk] == 0 and alpha[ny * strip_w + frame * FW + nx] > ALPHA_MIN:
							seen[nk] = 1
							stack.append(nk)
			sizes.append(n)
	sizes.sort()
	sizes.reverse()
	return sizes


func test_no_detached_body_parts() -> void:
	for planet in LevelData.PLANETS:
		var alpha := _alpha_strip(planet)
		if alpha.is_empty():
			continue
		var bad: Array[String] = []
		for f in FRAMES:
			var sizes := _component_sizes(alpha, FW * FRAMES, f)
			for i in range(1, sizes.size()):
				if sizes[i] >= MIN_PART:
					bad.append("f%d:%dpx" % [f, sizes[i]])
		check(bad.is_empty(), "%s: body parts detached from the creature (alpha>0.5) in %d piece(s): %s" % [
			planet, bad.size(), ", ".join(bad.slice(0, 6))])
