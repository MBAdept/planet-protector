extends TestBase
## Audit (dimension "data"): level table, colours, planets, zoom stages – checked against the client's
## reference docs/REFERENCE_DE.md, section E (level data) and the colour statements of section I.
## The reference table is transcribed here VERBATIM (numbers + German colour words) so that any drift of
## scripts/data/level_data.gd from the binding reference is caught.

# Lvl; Name; Gesamt; Bahnen (oben/mittig/unten); Tempo; Feuer; Punkte; Abschlussbonus (-1 = Sonderregel)
const REF := [
	[1, "Neptune 1", 10, [1, 1, 1], 1.0, 1.0, 10, 100],
	[2, "Neptune 2", 10, [1, 1, 1], 1.0, 1.2, 10, 100],
	[3, "Neptune 3", 12, [1, 1, 2], 1.0, 1.2, 10, 100],
	[4, "Uranus 1", 12, [1, 1, 2], 1.2, 1.25, 25, 250],
	[5, "Uranus 2", 16, [2, 1, 2], 1.2, 1.3, 25, 250],
	[6, "Uranus 3", 16, [2, 1, 2], 1.2, 1.35, 25, 250],
	[7, "Saturn 1", 10, [1, 1, 1], 1.2, 1.25, 25, 500],
	[8, "Saturn 2", 12, [1, 1, 1], 1.38, 1.3, 25, 500],
	[9, "Saturn 3", 12, [1, 1, 1], 1.518, 1.35, 25, 500],
	[10, "Jupiter 1", 16, [1, 1, 1], 1.6698, 1.4, 40, 750],
	[11, "Jupiter 2", 16, [1, 1, 2], 2.00376, 1.75, 40, 750],
	[12, "Jupiter 3", 16, [1, 1, 2], 2.404512, 1.9, 50, 900],
	[13, "Mars / Bonus", 20, [1, 1, 0], 3.606768, 0.0, 0, -1],
	[14, "Mars 1", 12, [1, 1, 1], 1.5, 1.9, 75, 1000],
	[15, "Mars 2", 20, [1, 2, 1], 1.8, 2.2, 100, 1500],
	[16, "Mars 3", 25, [2, 2, 1], 2.0, 2.5, 110, 2000],
	[17, "Earth 1", 40, [2, 2, 2], 2.2, 2.6, 120, 2000],
	[18, "Earth 2", 40, [2, 2, 2], 2.4, 2.2, 120, 2000],
	[19, "Earth 3", 12, [1, 1, 1], 2.6, 2.4, 150, 3000],
	[20, "Earth – Final Battle", 30, [2, 2, 2], 2.9, 2.5, 150, 500],
]

# Section I: "Zoomstufen: Neptun 1/2/3, Uranus 1/2/3, Saturn 1/2/3, Jupiter 1/2/3, Bonus 13 Stufe 1,
# Mars 14/15/16 Stufe 1/2/3, Erde 17/18/19/20 Stufe 1/1/2/3."
const REF_ZOOM := [0, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 1, 2, 3, 1, 1, 2, 3]
const REF_PLANET := ["", "neptune", "neptune", "neptune", "uranus", "uranus", "uranus", "saturn", "saturn",
	"saturn", "jupiter", "jupiter", "jupiter", "mars", "mars", "mars", "mars", "earth", "earth", "earth", "earth"]


# --- helpers -------------------------------------------------------------------------------------
static func _hue_deg(c: Color) -> float:
	return c.h * 360.0


static func _lum(c: Color) -> float:
	return c.get_luminance()


## Drives a whole level with an invincible player and no enemy fire: every alive enemy is hit until
## destroyed, refills happen through the real slot logic. Returns the finished world.
func _play_level(level: int, rng_seed := 11) -> GameWorld:
	var w := GameWorld.new(level, 1, 0, 3, rng_seed)
	w.invincible = true
	w.allow_enemy_fire = false
	w.start_combat()
	var guard := 0
	while not w.is_finished() and guard < 200000:
		guard += 1
		if not w.enemies.is_empty() and w.state == GameWorld.State.PLAYING:
			# colour-lock levels: hit the lowest stage first so no hit is ever locked
			var arr: Array = w.enemies.duplicate()
			arr.sort_custom(func(a, b) -> bool: return a.stage < b.stage)
			w.apply_hit(arr[0])
		else:
			w.run_steps(1)
	return w


# --- E: level table -------------------------------------------------------------------------------
func test_level_table_matches_reference_numbers() -> void:
	for r in REF:
		var n: int = r[0]
		var ld := LevelData.level(n)
		check_eq(String(ld["name"]), String(r[1]), "L%d name" % n)
		check_eq(int(ld["total"]), int(r[2]), "L%d Gesamt" % n)
		check_eq(Array(ld["lanes"]), Array(r[3]), "L%d Bahnen" % n)
		check_near(float(ld["tempo"]), float(r[4]), 1e-9, "L%d Tempo" % n)
		check_near(float(ld["fire"]), float(r[5]), 1e-9, "L%d Feuer" % n)
		check_eq(int(ld["points"]), int(r[6]), "L%d Punkte" % n)
		if int(r[7]) >= 0:
			check_eq(int(ld["bonus"]), int(r[7]), "L%d Abschlussbonus" % n)
		var lanes: Array = r[3]
		check_eq(LevelData.slot_lanes(n).size(), int(lanes[0]) + int(lanes[1]) + int(lanes[2]), "L%d slots" % n)


## "Tempo = Faktor auf Grundtempo 62 px/s vor Schwierigkeitsfaktor."
func test_enemy_speed_is_62_times_tempo_per_game_second() -> void:
	for r in REF:
		var n: int = r[0]
		var w := GameWorld.new(n, 1, 0, 3, 5)
		w.auto_slots = false
		w.allow_enemy_fire = false
		w.osc_amplitude = 0.0
		w.start_combat()
		var e := w.add_enemy(0, 480.0, 1.0)
		e.dir_timer = INF
		w.run_game_seconds(1.0)
		check_near(e.x - 480.0, 62.0 * float(r[4]), 1e-3, "L%d enemy px per game second" % n)


## "Feuer = Frequenzfaktor, kein Intervallmultiplikator. Basisintervall zufällig 1,8–2,8 Spielsekunden;
## durch Feuerfaktor teilen."
func test_fire_interval_is_base_interval_divided_by_fire_factor() -> void:
	for r in REF:
		var n: int = r[0]
		var f := float(r[5])
		if f <= 0.0:
			continue
		var w := GameWorld.new(n, 1, 0, 3, 9)
		var lo := INF
		var hi := -INF
		for i in 4000:
			var v: float = w._next_fire_interval()
			lo = minf(lo, v)
			hi = maxf(hi, v)
		check(lo >= 1.8 / f - 1e-6 and hi <= 2.8 / f + 1e-6, "L%d interval range [%f, %f] not within [1.8, 2.8]/%f" % [n, lo, hi, f])
		check(lo < 1.85 / f and hi > 2.75 / f, "L%d interval range [%f, %f] does not span [1.8, 2.8]/%f" % [n, lo, hi, f])


## "Bahnen = Anzahl originaler Gegnerplätze oben/mittig/unten" – at combat start every slot is filled.
func test_combat_start_fills_the_lane_slots_of_the_table() -> void:
	for r in REF:
		var n: int = r[0]
		var w := GameWorld.new(n, 1, 0, 3, 3)
		w.allow_enemy_fire = false
		w.start_combat()
		var per_lane := [0, 0, 0]
		for e in w.enemies:
			per_lane[e.lane] += 1
		check_eq(per_lane, Array(r[3]), "L%d enemies per lane at combat start" % n)


## Gesamt (originals), Punkte per final destruction (per child for split enemies), Abschlussbonus once.
func test_full_level_totals_points_and_completion_bonus() -> void:
	for r in REF:
		var n: int = r[0]
		if n == LevelData.BONUS_LEVEL:
			continue
		var w := _play_level(n)
		check(w.state == GameWorld.State.COMPLETE, "L%d did not complete" % n)
		check_eq(w.spawned, int(r[2]), "L%d originals spawned" % n)
		var finals := int(r[2]) * (2 if (n >= 7 and n <= 12) else 1)
		check_eq(w.destroyed, finals, "L%d final destructions" % n)
		check_eq(w.completion_bonus, int(r[7]), "L%d completion bonus" % n)
		check_eq(w.score_delta, finals * int(r[6]) + int(r[7]), "L%d level score" % n)
		# "Extra-Leben für Abschluss OHNE Lebensverlust nur in 10,15,16,17,18."
		check_eq(w.extra_life_awarded, n in [10, 15, 16, 17, 18], "L%d flawless extra life" % n)
		check_eq(w.lives, 3 + (1 if n in [10, 15, 16, 17, 18] else 0), "L%d lives after flawless completion" % n)


# --- E: colours -----------------------------------------------------------------------------------
## "17 ... Regenbogen violett oben bis gelb unten", "18 ... Regenbogen gelb oben bis violett unten".
func test_rainbow_directions_17_18() -> void:
	var c17 := LevelData.gradient_colors(17)
	var c18 := LevelData.gradient_colors(18)
	check(c17.size() >= 4, "L17 is not a multi-stop rainbow")
	check(_hue_deg(c17[0]) > 250.0 and _hue_deg(c17[0]) < 300.0, "L17 top not violet (hue %f)" % _hue_deg(c17[0]))
	check(_hue_deg(c17[-1]) > 45.0 and _hue_deg(c17[-1]) < 65.0, "L17 bottom not yellow (hue %f)" % _hue_deg(c17[-1]))
	check(_hue_deg(c18[0]) > 45.0 and _hue_deg(c18[0]) < 65.0, "L18 top not yellow (hue %f)" % _hue_deg(c18[0]))
	check(_hue_deg(c18[-1]) > 250.0 and _hue_deg(c18[-1]) < 300.0, "L18 bottom not violet (hue %f)" % _hue_deg(c18[-1]))
	# the hue runs monotonically through the spectrum (violet → blue → cyan → green → yellow)
	for i in range(1, c17.size()):
		check(_hue_deg(c17[i]) < _hue_deg(c17[i - 1]), "L17 rainbow hue not monotonic at stop %d" % i)
	# 18 is exactly 17 reversed
	for i in c17.size():
		check(c17[i].is_equal_approx(c18[c18.size() - 1 - i]), "L18 is not the reverse of L17 at stop %d" % i)


## "19 ... schwarz", "20 ... schwarz" (black enemies keep readable via outline + eyes).
func test_black_levels_19_20() -> void:
	for n in [19, 20]:
		check(LevelData.is_black(n), "L%d not flagged black" % n)
		for c in LevelData.gradient_colors(n):
			check(c.get_luminance() < 0.06, "L%d colour %s is not black" % [n, str(c)])
	for n in range(1, 19):
		check(not LevelData.is_black(n), "L%d wrongly black" % n)


## "Gelb-Verlauf hellgelb bis dunkelgelb; Grün-Verlauf hellgrün bis dunkelgrün" (top → bottom).
func test_colour_stage_gradients_light_to_dark() -> void:
	for n in [14, 15, 16]:
		var y := LevelData.gradient_colors(n, LevelData.Stage.YELLOW)
		var g := LevelData.gradient_colors(n, LevelData.Stage.GREEN)
		var v := LevelData.gradient_colors(n, LevelData.Stage.VIOLET)
		check(_lum(y[0]) > _lum(y[-1]) + 0.3, "L%d yellow not light → dark" % n)
		check(_lum(g[0]) > _lum(g[-1]) + 0.3, "L%d green not light → dark" % n)
		check(_hue_deg(y[0]) > 45.0 and _hue_deg(y[0]) < 65.0 and _hue_deg(y[-1]) > 40.0 and _hue_deg(y[-1]) < 65.0, "L%d yellow hues" % n)
		check(_hue_deg(g[0]) > 90.0 and _hue_deg(g[0]) < 150.0 and _hue_deg(g[-1]) > 90.0 and _hue_deg(g[-1]) < 150.0, "L%d green hues" % n)
		check(_hue_deg(v[0]) > 250.0 and _hue_deg(v[0]) < 300.0, "L%d start colour not violet" % n)
		check(_lum(v[-1]) < 0.06, "L%d violet stage does not end almost black" % n)


## Every level gradient: exactly the described direction (spot checks of the German colour words).
func test_table_colour_words() -> void:
	# "fast schwarz" bottoms
	for n in [5, 6, 11, 12, 13, 14, 15, 16]:
		var c := LevelData.gradient_colors(n)
		check(_lum(c[-1]) < 0.07, "L%d bottom not almost black (%s)" % [n, str(c[-1])])
		check(_lum(c[0]) > _lum(c[-1]) + 0.1, "L%d not top-light → bottom-dark" % n)
	# "... bis weiß" / "hellblau/weiß" / "hellrot/weiß" bottoms are very light
	for n in [7, 8, 9, 10]:
		var c := LevelData.gradient_colors(n)
		check(_lum(c[-1]) > 0.8, "L%d bottom not white-ish (%s)" % [n, str(c[-1])])
		check(_lum(c[0]) < _lum(c[-1]) - 0.3, "L%d top not darker than bottom (%s)" % [n, str(c[0])])
		check(c[0].v < 0.7, "L%d top not dark (%s)" % [n, str(c[0])])


# --- I: planets and zoom stages ---------------------------------------------------------------------
func test_planets_and_zoom_stages_per_level() -> void:
	for n in range(1, 21):
		check_eq(LevelData.planet_of(n), String(REF_PLANET[n]), "L%d planet" % n)
		check_eq(LevelData.zoom_stage(n), int(REF_ZOOM[n]), "L%d zoom stage" % n)
	check_near(LevelData.planet_diameter(1), 174.0, 1e-4, "stage 1 diameter")
	check_near(LevelData.planet_diameter(2), 174.0 * 220.0 / 192.0, 1e-4, "stage 2 diameter")
	check_near(LevelData.planet_diameter(3), 174.0 * 275.0 / 192.0, 1e-4, "stage 3 diameter")


## "Sichtbarer Kugeldurchmesser ungefähr 174 px ... Ringe kommen außen hinzu": the sphere (not the image)
## is drawn at the stage diameter – checks the sprite metadata against the opaque disc of each PNG.
func test_planet_sprite_sphere_metadata_matches_opaque_disc() -> void:
	for p in LevelData.PLANETS:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/sprites/planets/%s.png" % p))
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/planets/%s.json" % p))
		var cx := int(round(float(meta["center"][0])))
		var cy := int(round(float(meta["center"][1])))
		var d := float(meta["sphere_diameter_px"])
		# vertical extent of the opaque disc through the centre column (rings are thin/tilted, the
		# opaque run that contains the centre is the sphere)
		var top := cy
		while top > 0 and img.get_pixel(cx, top - 1).a > 0.5:
			top -= 1
		var bot := cy
		while bot < img.get_height() - 1 and img.get_pixel(cx, bot + 1).a > 0.5:
			bot += 1
		var measured := float(bot - top + 1)
		check(absf(measured - d) <= d * 0.03, "%s opaque sphere %f px vs metadata %f px" % [p, measured, d])


## I: "Farben aus Leveltabelle haben Vorrang vor Materialdetails. Schwarze Erdgegner durch dezente Kontur
## und Augen erkennbar halten." – levels 19/20 are "schwarz". The Earth sheet's emissive B channel also holds
## wing veins, a chest sigil and crown jewels (they glow on the rainbow levels 17/18). On the black levels
## enemy.gdshader multiplies B and every halo sample by the sheet's eye_rect, so only the eyes glow
## (audit finding data-1, regression test: checks what the shader lets through, not the raw PNG).
func test_black_earth_enemies_emit_only_at_the_eyes() -> void:
	check(LevelData.is_black(19) and LevelData.is_black(20), "levels 19/20 must be black")
	var sh := Assets.enemy_sheet("earth")
	check(sh.has("eye_rect"), "earth.json defines eye_rect")
	var er: Array = sh.get("eye_rect", [0, 0, 255, 159])
	var x0 := int(er[0])
	var y0 := int(er[1])
	var x1 := int(er[2])
	var y1 := int(er[3])
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/sprites/enemies/earth.png"))
	img.convert(Image.FORMAT_RGBA8)
	var fw := 256
	var wing := 0
	var chest := 0
	var between := 0
	var masked_out := 0
	for f in 16:
		var eye_l := 0
		var eye_r := 0
		for y in 160:
			for x in fw:
				var c := img.get_pixel(f * fw + x, y)
				if c.a < 0.5 or c.b < 0.1:
					continue
				if x < x0 or x > x1 or y < y0 or y > y1:
					masked_out += 1    # does not glow on black enemies
					continue
				if absf(float(x) - 128.0) > 36.0:
					wing += 1          # wing membrane / veins
				elif y >= 62:
					chest += 1         # torso emblem, well below the eyes
				elif absf(float(x) - 127.5) < 2.5:
					between += 1       # centre column between the eyes (crown jewel)
				elif c.b > 0.6:
					if x < 128:
						eye_l += 1
					else:
						eye_r += 1
		check(eye_l >= 6 and eye_r >= 6, "frame %d: both eyes glow inside eye_rect (%d / %d texels)" % [f, eye_l, eye_r])
	check_eq(wing, 0, "black Earth enemy: emissive (orange-glowing) wing texels over 16 frames")
	check_eq(chest, 0, "black Earth enemy: emissive (orange-glowing) torso texels over 16 frames")
	check_eq(between, 0, "black Earth enemy: emissive texels between the eyes (crown jewel) over 16 frames")
	check(masked_out > 1000, "veins / sigil / jewels exist in B and are masked out (%d texels)" % masked_out)
	# EnemyArt passes the rect (frame UV) to the shader for black enemies only.
	var uv := EnemyArt.eye_rect_uv(sh)
	check_near(uv.x, x0 / 256.0, 1e-6, "eye_rect_uv x0")
	check_near(uv.w, (y1 + 1) / 160.0, 1e-6, "eye_rect_uv y1")
	check(uv.z - uv.x < 0.25 and uv.w - uv.y < 0.15, "eye_rect_uv is not the full frame")
	var art_src := (load("res://scripts/common/enemy_art.gd") as GDScript).source_code
	check(art_src.contains('"eye_rect", eye_rect_uv(sh) if black else'), "EnemyArt sets eye_rect only for black enemies")
	var shader_src := (load("res://shaders/enemy.gdshader") as Shader).code
	check(shader_src.contains("s.b * eye_mask(UV)"), "shader masks the emissive term")
	check(shader_src.contains(".b * eye_mask(u1)") and shader_src.contains(".b * eye_mask(u2)"),
		"shader masks every halo sample")
