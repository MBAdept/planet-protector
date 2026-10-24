extends Node2D
## Game HUD (docs/SPEC.md §1, §10, §15): slim top bar (≤ 44 px, never covers the enemy lanes) with SCORE,
## LIVES, LEVEL + name, DIFFICULTY and TIME (MM:SS.t); bonus counters in the ground strip; level intro
## banner, level-clear banner, respawn hint and the pause overlay (with the MUSIC / EFFECTS VOLUME rows, SPEC
## §12/§14; GameScreen handles their input). Attract mode (demo, SPEC §11.1): the values
## come from the demo world (a demo never writes Run), plus the DEMO / PRESS ANY BUTTON overlay.

const FxTex := preload("res://scripts/game/fx_tex.gd")

const BAR_H := 40.0
const C_LABEL := Color(0.58, 0.66, 0.82, 0.9)
const C_VALUE := Color(0.93, 0.96, 1.0)
const C_ACCENT := Color(1.0, 0.68, 0.25)
const ATTRACT_DEMO_Y := 80.0       ## demo label: between the top bar and the top lane (enemies reach up to y ≈ 125)
const ATTRACT_BLINK_HZ := 0.8
# Pause overlay: volume rows (GameScreen.PAUSE_ITEMS order) with a caption under each.
const PAUSE_ROW_Y := 282.0         ## centre of the first row
const PAUSE_ROW_STEP := 66.0
const PAUSE_ROW_W := 520.0
const PAUSE_CAPTION_DY := 35.0     ## caption baseline below its row centre
## Rows: item, label, caption while the sound is on (the game music is silent during a pause by rule),
## caption while its ON/OFF option is OFF (then the bar is dimmed).
const PAUSE_ROWS := [
	["music_volume", "MUSIC VOLUME", "Music is paused – it plays again when you resume",
		"Music is switched off (title menu)"],
	["sfx_volume", "EFFECTS VOLUME", "Every change plays a short preview", "Sound effects are switched off (title menu)"],
]

var world: GameWorld
var level := 1
var paused := false
var pause_sel := 0          ## selected volume row of the pause overlay (GameScreen.PAUSE_ITEMS)
var anim := 0.0             ## real seconds (banner animation)
var clear_time := -1.0      ## real seconds since the level goal was reached (−1 = not yet)
var respawn_time := -1.0
var attract := false

var _f_label: Font
var _f_value: Font
var _f_big: Font
var _f_body: Font
var _bar_tex: GradientTexture2D
var _icon: Texture2D
var _accent := Color(0.4, 0.7, 1.0)
var _planet := "neptune"


func _ready() -> void:
	_f_label = _spaced(Assets.font_body_bold, 2)
	_f_value = Assets.font_title
	_f_big = _spaced(Assets.font_title_heavy, 3)
	_f_body = _spaced(Assets.font_body_bold, 1)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	g.colors = PackedColorArray([Color(0.01, 0.015, 0.04, 0.82), Color(0.01, 0.015, 0.04, 0.6), Color(0.01, 0.015, 0.04, 0.0)])
	_bar_tex = GradientTexture2D.new()
	_bar_tex.gradient = g
	_bar_tex.fill_to = Vector2(0, 1)
	_bar_tex.width = 4
	_bar_tex.height = 64
	_planet = LevelData.planet_of(level)


func _spaced(base: Font, spacing: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_glyph = spacing
	return fv


func _draw() -> void:
	if world == null:
		return
	_draw_top_bar()
	if world.is_bonus():
		_draw_bonus_counters()
	_draw_banners()
	if paused:
		_draw_pause()
	if attract:
		_draw_attract()


# --- Top bar -------------------------------------------------------------------------------------
func _draw_top_bar() -> void:
	draw_texture_rect(_bar_tex, Rect2(0, 0, LevelData.SCREEN_W, BAR_H + 6.0), false)
	var atm: Color = preload("res://scripts/game/backdrop.gd").atmosphere(_planet)
	draw_texture_rect(FxTex.band(), Rect2(0, BAR_H - 1.0, LevelData.SCREEN_W, 2.0), false, Color(atm.r, atm.g, atm.b, 0.35))
	var ly := 14.0
	var vy := 35.0
	# SCORE
	_label(Vector2(18, ly), "SCORE")
	_value(Vector2(18, vy), "%07d" % maxi(_score(), 0), 19, C_VALUE)
	# LIVES
	_label(Vector2(160, ly), "LIVES")
	_draw_lives(Vector2(160, 21), _lives())
	# LEVEL + name (centre)
	var lvl_name := String(LevelData.level(level)["name"]).to_upper()
	_label(Vector2(480, ly), "LEVEL %d" % level, HORIZONTAL_ALIGNMENT_CENTER, C_ACCENT)
	var size := 17
	while size > 11 and _f_value.get_string_size(lvl_name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > 330.0:
		size -= 1
	_value(Vector2(480, vy), lvl_name, size, C_VALUE, HORIZONTAL_ALIGNMENT_CENTER)
	# DIFFICULTY
	_label(Vector2(700, ly), "DIFFICULTY")
	_value(Vector2(700, vy), _difficulty_name(), 14, _difficulty_color())
	# TIME
	_label(Vector2(942, ly), "TIME", HORIZONTAL_ALIGNMENT_RIGHT)
	_value(Vector2(942, vy), Fmt.time(_play_time()), 19, C_VALUE, HORIZONTAL_ALIGNMENT_RIGHT)


## Shown values: the run's (Run) – or, in a demo, the demo world's own.
func _score() -> int:
	return world.score_delta if attract else Run.score


func _lives() -> int:
	return world.lives if attract else Run.lives


func _play_time() -> float:
	return world.active_time if attract else Run.active_time


func _difficulty() -> int:
	return world.difficulty if attract else Run.difficulty


func _difficulty_name() -> String:
	return String(ShipData.difficulty(_difficulty())["name"])


func _ship_id() -> int:
	return world.ship_id if attract else Run.ship_id


func _difficulty_color() -> Color:
	match _difficulty():
		0:
			return Color(0.55, 0.95, 0.6)
		1:
			return Color(0.6, 0.85, 1.0)
		2:
			return Color(1.0, 0.75, 0.35)
	return Color(1.0, 0.42, 0.38)


func _draw_lives(pos: Vector2, n: int) -> void:
	if _icon == null:
		_icon = Assets.ship_texture(_ship_id())
		_accent = ShipData.ship(_ship_id())["accent"]
	var sz := Vector2(_icon.get_width(), _icon.get_height()) * 0.2
	var shown := mini(n, 5)
	for i in shown:
		var p := pos + Vector2(float(i) * (sz.x + 3.0), 0)
		draw_texture_rect(_icon, Rect2(p, sz), false)
	if n > 5:
		_value(pos + Vector2(float(shown) * (sz.x + 3.0) + 2.0, 14.0), "×%d" % n, 13, C_VALUE)
	elif n <= 0:
		_value(pos + Vector2(0, 14.0), "—", 13, C_LABEL)


func _label(pos: Vector2, s: String, align := HORIZONTAL_ALIGNMENT_LEFT, col := C_LABEL) -> void:
	UiKit.text(self, _f_label, pos, s, 10, col, align)


func _value(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	UiKit.text(self, _f_value, pos, s, size, col, align)


# --- Bonus level counters (ground strip) ---------------------------------------------------------
func _draw_bonus_counters() -> void:
	var y := LevelData.GROUND_Y + (LevelData.SCREEN_H - LevelData.GROUND_Y) * 0.5
	var r := Rect2(300, y - 13.0, 360, 26)
	draw_rect(r, Color(0.01, 0.015, 0.04, 0.72))
	draw_rect(r, Color(1.0, 0.68, 0.25, 0.35), false, 1.0)
	_label(Vector2(318, y + 4.0), "SHOTS LEFT")
	var shots_col := C_VALUE if world.attempts > 10 else Color(1.0, 0.45, 0.35)
	_value(Vector2(410, y + 6.5), "%d" % world.attempts, 16, shots_col)
	_label(Vector2(498, y + 4.0), "HITS")
	_value(Vector2(540, y + 6.5), "%d/%d" % [mini(world.destroyed, LevelData.BONUS_TARGET), LevelData.BONUS_TARGET], 16, C_ACCENT)


# --- Banners -------------------------------------------------------------------------------------
func _draw_banners() -> void:
	if world.state == GameWorld.State.INTRO:
		_draw_intro(world.intro_time)
	elif clear_time >= 0.0:
		_draw_clear(clear_time)
	elif respawn_time >= 0.0 and world.state == GameWorld.State.RESPAWN:
		var a := clampf((respawn_time - 0.35) * 4.0, 0.0, 1.0)
		if a > 0.0:
			UiKit.text(self, _f_big, Vector2(480, 380), "GET READY", 30, Color(1, 1, 1, 0.85 * a), HORIZONTAL_ALIGNMENT_CENTER)
			var lives_txt := "%d %s LEFT" % [world.lives, "SHIP" if world.lives == 1 else "SHIPS"]
			UiKit.text(self, _f_body, Vector2(480, 410), lives_txt, 16, Color(C_LABEL, 0.9 * a), HORIZONTAL_ALIGNMENT_CENTER)


func _banner_alpha(t: float, total: float, fade_in := 0.25, fade_out := 0.3) -> float:
	return clampf(t / fade_in, 0.0, 1.0) * clampf((total - t) / fade_out, 0.0, 1.0)


func _draw_intro(t: float) -> void:
	var total := LevelData.INTRO_TIME
	var a := _banner_alpha(t, total)
	var e := 1.0 - pow(1.0 - clampf(t / 0.45, 0.0, 1.0), 3.0)
	var cy := 330.0
	# Light band sweeping across.
	var band_w := LevelData.SCREEN_W * (0.35 + 0.65 * e)
	draw_texture_rect(FxTex.band(), Rect2(480.0 - band_w * 0.5, cy - 70.0, band_w, 140.0), false, Color(0.02, 0.03, 0.08, 0.75 * a))
	draw_texture_rect(FxTex.band(), Rect2(480.0 - band_w * 0.5, cy - 58.0, band_w, 3.0), false, Color(C_ACCENT, 0.7 * a))
	draw_texture_rect(FxTex.band(), Rect2(480.0 - band_w * 0.5, cy + 55.0, band_w, 3.0), false, Color(C_ACCENT, 0.7 * a))
	if world.is_bonus():
		UiKit.text(self, _f_label, Vector2(480, cy - 30.0), "LEVEL %d  ·  BONUS ROUND" % level, 13, Color(C_ACCENT, a), HORIZONTAL_ALIGNMENT_CENTER)
		_glow_text(Vector2(480, cy + 10.0), LevelData.BONUS_TITLE, 40, a, e)
		UiKit.text(self, _f_body, Vector2(480, cy + 42.0), "100 shots – destroy 20 demons", 20, Color(C_VALUE, a), HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var planet_name: String = LevelData.PLANET_NAMES[_planet]
		UiKit.text(self, _f_label, Vector2(480, cy - 34.0), planet_name.to_upper() + "  ·  " + _difficulty_name(), 12,
			Color(C_ACCENT, a), HORIZONTAL_ALIGNMENT_CENTER)
		_glow_text(Vector2(480, cy + 12.0), "LEVEL %d" % level, 54, a, e)
		UiKit.text(self, _f_body, Vector2(480, cy + 44.0), String(LevelData.level(level)["name"]).to_upper(), 20,
			Color(C_VALUE, a), HORIZONTAL_ALIGNMENT_CENTER)


func _glow_text(pos: Vector2, s: String, size: int, a: float, e: float) -> void:
	var w := _f_big.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos - Vector2(w * 0.5, 0) + Vector2((1.0 - e) * 40.0, 0)
	draw_string_outline(_f_big, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 14, Color(1.0, 0.45, 0.1, 0.16 * a))
	draw_string_outline(_f_big, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(1.0, 0.55, 0.15, 0.35 * a))
	draw_string(_f_big, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1.0, 0.97, 0.9, a))


func _draw_clear(t: float) -> void:
	var a := clampf(t / 0.2, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - clampf(t / 0.35, 0.0, 1.0), 3.0)
	var cy := 330.0
	draw_texture_rect(FxTex.band(), Rect2(0, cy - 50.0, LevelData.SCREEN_W, 100.0), false, Color(0.02, 0.03, 0.08, 0.6 * a))
	var title := "BONUS COMPLETE" if world.is_bonus() else "LEVEL CLEAR"
	_glow_text(Vector2(480, cy + 8.0), title, 40, a, e)
	if world.state == GameWorld.State.COMPLETE:
		var sub := "BONUS  +%d" % world.completion_bonus
		if world.extra_life_awarded:
			sub += "   ·   EXTRA LIFE"
		UiKit.text(self, _f_body, Vector2(480, cy + 38.0), sub, 18, Color(C_ACCENT, a), HORIZONTAL_ALIGNMENT_CENTER)


# --- Pause ---------------------------------------------------------------------------------------
func _draw_pause() -> void:
	draw_rect(Rect2(0, 0, LevelData.SCREEN_W, LevelData.SCREEN_H), Color(0.0, 0.01, 0.03, 0.62))
	draw_texture_rect(FxTex.band(), Rect2(0, 150.0, LevelData.SCREEN_W, 380.0), false, Color(0.03, 0.05, 0.12, 0.84))
	_glow_text(Vector2(480, 222.0), "PAUSED", 56, 1.0, 1.0)
	var top := PAUSE_ROW_Y - 36.0
	var bottom := PAUSE_ROW_Y + (PAUSE_ROWS.size() - 1) * PAUSE_ROW_STEP + PAUSE_CAPTION_DY + 20.0
	UiKit.panel(self, Rect2(480.0 - PAUSE_ROW_W * 0.5 - 40.0, top, PAUSE_ROW_W + 80.0, bottom - top), 0.8)
	for i in PAUSE_ROWS.size():
		var row: Array = PAUSE_ROWS[i]
		var item := String(row[0])
		var on := Settings.volume_switch_on(item)
		var cy := PAUSE_ROW_Y + i * PAUSE_ROW_STEP
		UiKit.menu_item_volume(self, Vector2(480, cy), String(row[1]), Settings.volume(item), i == pause_sel, anim,
			PAUSE_ROW_W, 18, on)
		UiKit.text(self, Assets.font_body, Vector2(480, cy + PAUSE_CAPTION_DY), String(row[2] if on else row[3]), 14,
			Color(C_LABEL, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.hint_bar(self, Vector2(480, 438.0), [[["UD"], "Select"], [["LR"], "Volume"]], 14)
	UiKit.text(self, _f_body, Vector2(480, 480.0), "P / ESC / START   resume", 20, C_VALUE, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.text(self, _f_body, Vector2(480, 508.0), "Q / BACK   quit to title", 20, C_LABEL, HORIZONTAL_ALIGNMENT_CENTER)


# --- Attract mode (demo) -------------------------------------------------------------------------
## Unobtrusive overlay that never covers the play: "DEMO" in the free band under the top bar and a gently
## blinking "PRESS ANY BUTTON" in the ground strip below the ship.
func _draw_attract() -> void:
	var a := clampf(anim / 0.4, 0.0, 1.0)
	var demo := "DEMO"
	var size := 18
	var spacing := 9.0
	var half := UiKit.spaced_width(_f_value, demo, size, spacing) * 0.5
	UiKit.divider(self, Vector2(480.0 - half - 62.0, ATTRACT_DEMO_Y - 7.0), 90.0, Color(C_ACCENT, 0.55 * a))
	UiKit.divider(self, Vector2(480.0 + half + 62.0, ATTRACT_DEMO_Y - 7.0), 90.0, Color(C_ACCENT, 0.55 * a))
	UiKit.text_spaced(self, _f_value, Vector2(480.0, ATTRACT_DEMO_Y), demo, size, spacing, Color(C_ACCENT, 0.85 * a),
		HORIZONTAL_ALIGNMENT_CENTER)
	# Ground strip (685…720): dark pill + blinking prompt.
	var prompt := "PRESS ANY BUTTON"
	var psize := 14
	var cy := LevelData.GROUND_Y + (LevelData.SCREEN_H - LevelData.GROUND_Y) * 0.5
	var w := UiKit.spaced_width(_f_label, prompt, psize, 3.0)
	var r := Rect2(480.0 - w * 0.5 - 22.0, cy - 12.0, w + 44.0, 24.0)
	UiKit.backing(self, r, 0.85 * a)
	var blink := 0.7 + 0.3 * cos(anim * TAU * ATTRACT_BLINK_HZ)
	UiKit.text_spaced(self, _f_label, Vector2(480.0, UiKit.baseline_for(_f_label, psize, cy)), prompt, psize, 3.0,
		Color(C_VALUE, blink * a), HORIZONTAL_ALIGNMENT_CENTER)
