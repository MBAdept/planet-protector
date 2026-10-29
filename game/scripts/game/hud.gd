extends Node2D
## Game HUD (docs/SPEC.md §1, §10, §15): slim top bar (≤ 44 px, never covers the enemy lanes) with SCORE,
## LIVES, LEVEL + name, DIFFICULTY and TIME (MM:SS.t); bonus counters in the ground strip; level intro
## banner, level-clear banner, respawn hint and the pause overlay (with the MUSIC / EFFECTS VOLUME rows, SPEC
## §12/§14; GameScreen handles their input). Attract mode (demo, SPEC §11.1): the values
## come from the demo world (a demo never writes Run), plus the DEMO / PRESS ANY BUTTON overlay.
## Playfield width (SPEC §18.1): `width` (960, 1280 or 1152 – from the display mode). The top bar spans it (SCORE / LIVES on the left, LEVEL
## centred, DIFFICULTY / TIME at the same distance from the right edge as at 960); banners, the bonus counters, the
## pause overlay and the demo overlay are centred at width / 2.
## Power-ups (SPEC §19.3): a pill centred in the ground strip – READY (name, READY, key hint, gently pulsing) →
## ACTIVE (name, draining bar, seconds left; blinking in the last 2 s) → USED (dim "<NAME> USED", fades out after
## ≈ 2 s, then nothing). Nothing at all on levels without a power-up (the bonus level, the demo). The intro banner of
## a power-up level has an extra line "POWER-UP: <NAME>".
## Two players (SPEC §19.2): the SCORE caption reads "P1 SCORE" / "P2 SCORE" in the player colour and the intro
## caption starts with "PLAYER k" in the player colour. One-player runs look exactly as before.

const FxTex := preload("res://scripts/game/fx_tex.gd")

const BAR_H := 40.0
## Captions of the top bar / bonus counters (SCORE, LIVES, …); UiKit.label_size lifts them in the small modes 3/4.
const LABEL_SIZE := 10
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
# Power-ups (SPEC §19.3).
## Colour of each power-up (pill, banner line, ship effects): rapid fire hot orange, twin violet, shield cyan.
const POWERUP_COLORS := {
	LevelData.PowerUp.RAPID_FIRE: Color(1.0, 0.58, 0.2),
	LevelData.PowerUp.TWIN: Color(0.74, 0.58, 1.0),
	LevelData.PowerUp.SHIELD: Color(0.4, 0.86, 1.0),
}
const POWERUP_WARN_TIME := 2.0     ## real seconds: the effect blinks in its last seconds
const POWERUP_USED_SHOW := 2.0     ## real seconds the USED pill stays …
const POWERUP_USED_FADE := 0.6     ## … then it fades out over this
const PILL_H := 26.0
const PILL_PAD := 14.0
const PILL_BAR_W := 132.0
const PILL_BAR_H := 6.0
const PILL_HINT_SIZE := 12
## Key hint of the power-up button: Shift (keyboard) / X (controller; also Ctrl, Y, LB, RB).
const POWERUP_HINT: Array[String] = ["SHIFT", "pad:X"]
## Baseline of the intro banner's "POWER-UP: <NAME>" line below the banner centre.
const POWERUP_LINE_DY := 84.0

var world: GameWorld
var level := 1
var width := LevelData.SCREEN_W   ## playfield width (960 / 1280 / 1152)
var paused := false
var pause_sel := 0          ## selected volume row of the pause overlay (GameScreen.PAUSE_ITEMS)
var anim := 0.0             ## real seconds (banner animation)
var clear_time := -1.0      ## real seconds since the level goal was reached (−1 = not yet)
var respawn_time := -1.0
var attract := false
var powerup_end := -1.0     ## real seconds since the power-up ended (−1 = not yet), drives the USED fade

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
	_draw_powerup()
	_draw_banners()
	if paused:
		_draw_pause()
	if attract:
		_draw_attract()


## Horizontal centre of the playfield.
func _cx() -> float:
	return width * 0.5


## Shift of right-anchored items (0 at 960): they keep their distance to the right edge.
func _right() -> float:
	return width - LevelData.SCREEN_W


## Shift of centred blocks laid out for 960 (0 at 960, 160 at 1280, 96 at 1152).
func _centre() -> float:
	return (width - LevelData.SCREEN_W) * 0.5


# --- Top bar -------------------------------------------------------------------------------------
func _draw_top_bar() -> void:
	draw_texture_rect(_bar_tex, Rect2(0, 0, width, BAR_H + 6.0), false)
	var atm: Color = preload("res://scripts/game/backdrop.gd").atmosphere(_planet)
	draw_texture_rect(FxTex.band(), Rect2(0, BAR_H - 1.0, width, 2.0), false, Color(atm.r, atm.g, atm.b, 0.35))
	var ly := 14.0
	var vy := 35.0
	# SCORE ("P1 SCORE" / "P2 SCORE" in the player colour in a two-player match)
	var sc := score_caption()
	_label(Vector2(18, ly), String(sc[0]), HORIZONTAL_ALIGNMENT_LEFT, sc[1])
	_value(Vector2(18, vy), "%07d" % maxi(_score(), 0), 19, C_VALUE)
	# LIVES
	_label(Vector2(160, ly), "LIVES")
	_draw_lives(Vector2(160, 21), _lives())
	# LEVEL + name (centre)
	var lvl_name := String(LevelData.level(level)["name"]).to_upper()
	_label(Vector2(_cx(), ly), "LEVEL %d" % level, HORIZONTAL_ALIGNMENT_CENTER, C_ACCENT)
	var size := 17
	while size > 11 and _f_value.get_string_size(lvl_name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > 330.0:
		size -= 1
	_value(Vector2(_cx(), vy), lvl_name, size, C_VALUE, HORIZONTAL_ALIGNMENT_CENTER)
	# DIFFICULTY
	_label(Vector2(700 + _right(), ly), "DIFFICULTY")
	_value(Vector2(700 + _right(), vy), _difficulty_name(), 14, _difficulty_color())
	# TIME
	_label(Vector2(942 + _right(), ly), "TIME", HORIZONTAL_ALIGNMENT_RIGHT)
	_value(Vector2(942 + _right(), vy), Fmt.time(_play_time()), 19, C_VALUE, HORIZONTAL_ALIGNMENT_RIGHT)


## Caption of the score and its colour: "SCORE"; in a two-player match "P1 SCORE" / "P2 SCORE" in the colour of the
## player whose turn it is (SPEC §19.2). A demo is never a match.
func score_caption() -> Array:
	if attract or not Run.is_two_player():
		return ["SCORE", C_LABEL]
	return ["P%d SCORE" % (Run.current + 1), UiKit.player_color(Run.current)]


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
	UiKit.text(self, _f_label, pos, s, UiKit.label_size(LABEL_SIZE), col, align)


func _value(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	UiKit.text(self, _f_value, pos, s, size, col, align)


# --- Bonus level counters (ground strip) ---------------------------------------------------------
func _draw_bonus_counters() -> void:
	var y := LevelData.GROUND_Y + (LevelData.SCREEN_H - LevelData.GROUND_Y) * 0.5
	var c := _centre()
	var r := Rect2(300 + c, y - 13.0, 360, 26)
	draw_rect(r, Color(0.01, 0.015, 0.04, 0.72))
	draw_rect(r, Color(1.0, 0.68, 0.25, 0.35), false, 1.0)
	_label(Vector2(318 + c, y + 4.0), "SHOTS LEFT")
	var shots_col := C_VALUE if world.attempts > 10 else Color(1.0, 0.45, 0.35)
	_value(Vector2(counter_value_x("SHOTS LEFT", 318.0, 410.0) + c, y + 6.5), "%d" % world.attempts, 16, shots_col)
	_label(Vector2(498 + c, y + 4.0), "HITS")
	_value(Vector2(counter_value_x("HITS", 498.0, 540.0) + c, y + 6.5), "%d/%d" % [mini(world.destroyed, LevelData.BONUS_TARGET), LevelData.BONUS_TARGET], 16, C_ACCENT)


## Left edge (960 layout) of a bonus counter value whose caption starts at label_x: value_x as designed, or right
## after the caption when the small modes 3/4 lift the caption size (modes 0–2: always value_x).
func counter_value_x(caption: String, label_x: float, value_x: float) -> float:
	var lw := _f_label.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.label_size(LABEL_SIZE)).x
	return maxf(value_x, label_x + lw + 8.0)


# --- Power-up pill (ground strip, SPEC §19.3) ----------------------------------------------------
## "RAPID FIRE" / "TWIN" / "SHIELD" ("" for NONE).
static func powerup_name(kind: int) -> String:
	return String(LevelData.POWERUP_NAMES.get(kind, ""))


static func powerup_color(kind: int) -> Color:
	return POWERUP_COLORS.get(kind, POWERUP_COLORS[LevelData.PowerUp.SHIELD])


## 0…1 visibility of an expiring power-up's effects with `left` real seconds left: 1 until the last
## POWERUP_WARN_TIME seconds, then short dips that come faster towards the end (4 → 9 per second). Driven by the
## world's timer, so it freezes with it (respawn, level end, pause).
static func powerup_blink(left: float) -> float:
	if left <= 0.0 or left >= POWERUP_WARN_TIME:
		return 1.0
	var t := POWERUP_WARN_TIME - left
	var phase := 4.0 * t + 1.25 * t * t
	return 0.25 + 0.75 * smoothstep(0.08, 0.22, absf(fposmod(phase, 1.0) - 0.5))


## What the ground-strip pill shows now: {"mode": "" (nothing) | "ready" | "active" | "used", "alpha": 0…1,
## "fill": bar fill 0…1, "seconds": the seconds left as shown (rounded up to tenths, "6.3"), "blink": 0…1}.
## READY dims once the level goal is met (it can no longer be used); USED stays POWERUP_USED_SHOW seconds, then
## fades out.
func powerup_pill() -> Dictionary:
	var out := {"mode": "", "alpha": 0.0, "fill": 0.0, "seconds": "", "blink": 1.0}
	if world == null or world.powerup == LevelData.PowerUp.NONE:
		return out
	match world.powerup_state:
		GameWorld.PowerState.READY:
			out["mode"] = "ready"
			# Full strength only while the button really works (not in the intro banner, a respawn, after the goal).
			out["alpha"] = 1.0 if world.can_activate_powerup() else 0.45
		GameWorld.PowerState.ACTIVE:
			out["mode"] = "active"
			var over := world.state == GameWorld.State.GAME_OVER_WAIT or world.state == GameWorld.State.GAME_OVER
			out["alpha"] = 0.45 if over else 1.0
			out["fill"] = clampf(world.powerup_left / maxf(world.powerup_time(), 1e-6), 0.0, 1.0)
			out["seconds"] = "%.1f" % (ceilf(world.powerup_left * 10.0 - 1e-6) / 10.0)
			out["blink"] = powerup_blink(world.powerup_left)
		_:
			var fade := clampf(1.0 - (maxf(powerup_end, 0.0) - POWERUP_USED_SHOW) / POWERUP_USED_FADE, 0.0, 1.0)
			if fade > 0.0:
				out["mode"] = "used"
				out["alpha"] = fade
	return out


## Width of the pill's content (without padding) for a mode at caption size `ls`.
func powerup_pill_width(mode: String, ls: int) -> float:
	var name_w := _f_label.get_string_size(powerup_name(world.powerup), HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
	match mode:
		"ready":
			return name_w + 10.0 + _f_label.get_string_size("READY", HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x + 16.0 \
				+ _hint_width()
		"active":
			return name_w + 12.0 + PILL_BAR_W + 12.0 + _seconds_width()
		"used":
			return name_w + _f_label.get_string_size("  USED", HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
	return 0.0


## The pill's rectangle (centred in the ground strip).
func powerup_pill_rect(mode: String) -> Rect2:
	var w := powerup_pill_width(mode, UiKit.label_size(12)) + PILL_PAD * 2.0
	var cy := LevelData.GROUND_Y + (LevelData.SCREEN_H - LevelData.GROUND_Y) * 0.5
	return Rect2(_cx() - w * 0.5, cy - PILL_H * 0.5, w, PILL_H)


## Width of the key hint "[SHIFT] / [X]" (its key caps are 1.55 × PILL_HINT_SIZE tall, inside the pill).
func _hint_width() -> float:
	return UiKit.glyph_width(POWERUP_HINT[0], PILL_HINT_SIZE) + PILL_HINT_SIZE * 0.9 \
		+ UiKit.glyph_width(POWERUP_HINT[1], PILL_HINT_SIZE)


func _seconds_width() -> float:
	return _f_value.get_string_size("00.0", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x


func _draw_powerup() -> void:
	var p := powerup_pill()
	var mode := String(p["mode"])
	if mode == "":
		return
	var a := float(p["alpha"])
	var col := powerup_color(world.powerup)
	var pname := powerup_name(world.powerup)
	var ls := UiKit.label_size(12)
	var r := powerup_pill_rect(mode)
	var cy := r.get_center().y
	var base := UiKit.baseline_for(_f_label, ls, cy)
	var x := r.position.x + PILL_PAD
	var name_w := _f_label.get_string_size(pname, HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
	match mode:
		"ready":
			# Gently pulsing: the border light and READY breathe.
			var pulse := 0.5 + 0.5 * cos(anim * TAU * 0.9) if world.can_activate_powerup() else 0.0
			_pill(r, col, a, snappedf(0.4 + 0.4 * pulse, 1.0 / 32.0))
			UiKit.text(self, _f_label, Vector2(x, base), pname, ls, Color(col, a))
			x += name_w + 10.0
			UiKit.text(self, _f_label, Vector2(x, base), "READY", ls, Color(C_VALUE, a * (0.72 + 0.28 * pulse)))
			x += _f_label.get_string_size("READY", HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x + 16.0
			var gs := PILL_HINT_SIZE
			var hc := Color(C_VALUE, 0.8 * a)
			x += UiKit.glyph(self, POWERUP_HINT[0], x, cy, gs, hc, a)
			UiKit.text(self, Assets.font_body, Vector2(x + gs * 0.45, UiKit.baseline_for(Assets.font_body, gs, cy)), "/", gs,
				Color(hc, hc.a * 0.6), HORIZONTAL_ALIGNMENT_CENTER)
			x += gs * 0.9
			UiKit.glyph(self, POWERUP_HINT[1], x, cy, gs, hc, a)
		"active":
			var blink := float(p["blink"])
			_pill(r, col, a, 0.6 * blink)
			UiKit.text(self, _f_label, Vector2(x, base), pname, ls, Color(col, a))
			x += name_w + 12.0
			# Draining bar: dim track, the remaining part in the power-up colour with a light edge and a glow at its end.
			var bar := Rect2(x, cy - PILL_BAR_H * 0.5, PILL_BAR_W, PILL_BAR_H)
			draw_rect(bar, Color(1, 1, 1, 0.1 * a))
			var fw := PILL_BAR_W * float(p["fill"])
			if fw > 0.5:
				var ba := a * blink
				draw_rect(Rect2(bar.position, Vector2(fw, PILL_BAR_H)), Color(col, 0.9 * ba))
				draw_rect(Rect2(bar.position, Vector2(fw, 2.0)), Color(col.lerp(Color.WHITE, 0.6), 0.9 * ba))
				FxTex.draw_centered(self, FxTex.glow(), Vector2(bar.position.x + fw, cy), Vector2(18, 18), Color(col.lerp(Color.WHITE, 0.4), 0.8 * ba))
			x += PILL_BAR_W + 12.0
			var warn := world.powerup_left < POWERUP_WARN_TIME
			var sc := Color(1.0, 0.45, 0.35) if warn else C_VALUE
			_value(Vector2(x + _seconds_width(), UiKit.baseline_for(_f_value, 14, cy)), String(p["seconds"]), 14,
				Color(sc, a * (blink if warn else 1.0)), HORIZONTAL_ALIGNMENT_RIGHT)
		"used":
			_pill(r, C_LABEL, a * 0.7, 0.0)
			UiKit.text(self, _f_label, Vector2(x, base), pname + "  USED", ls, Color(C_LABEL, 0.75 * a))


## Dark rounded pill with a border in `col`; glow 0…1 adds a soft outer light in that colour.
func _pill(r: Rect2, col: Color, a: float, glow: float) -> void:
	UiKit.backing(self, r, 0.85 * a)
	UiKit.panel_ex(self, r, Color(0, 0, 0, 0), Color(col, (0.35 + 0.4 * glow) * a), int(r.size.y * 0.5), 1,
		Color(col, 0.22 * glow * a), 10)


# --- Banners -------------------------------------------------------------------------------------
func _draw_banners() -> void:
	if world.state == GameWorld.State.INTRO:
		_draw_intro(world.intro_time)
	elif clear_time >= 0.0:
		_draw_clear(clear_time)
	elif respawn_time >= 0.0 and world.state == GameWorld.State.RESPAWN:
		var a := clampf((respawn_time - 0.35) * 4.0, 0.0, 1.0)
		if a > 0.0:
			UiKit.text(self, _f_big, Vector2(_cx(), 380), "GET READY", 30, Color(1, 1, 1, 0.85 * a), HORIZONTAL_ALIGNMENT_CENTER)
			var lives_txt := "%d %s LEFT" % [world.lives, "SHIP" if world.lives == 1 else "SHIPS"]
			UiKit.text(self, _f_body, Vector2(_cx(), 410), lives_txt, 16, Color(C_LABEL, 0.9 * a), HORIZONTAL_ALIGNMENT_CENTER)


func _banner_alpha(t: float, total: float, fade_in := 0.25, fade_out := 0.3) -> float:
	return clampf(t / fade_in, 0.0, 1.0) * clampf((total - t) / fade_out, 0.0, 1.0)


func _draw_intro(t: float) -> void:
	var total := LevelData.INTRO_TIME
	var a := _banner_alpha(t, total)
	var e := 1.0 - pow(1.0 - clampf(t / 0.45, 0.0, 1.0), 3.0)
	var cy := 330.0
	var cx := _cx()
	# Light band sweeping across.
	var band_w := width * (0.35 + 0.65 * e)
	draw_texture_rect(FxTex.band(), Rect2(cx - band_w * 0.5, cy - 70.0, band_w, 140.0), false, Color(0.02, 0.03, 0.08, 0.75 * a))
	draw_texture_rect(FxTex.band(), Rect2(cx - band_w * 0.5, cy - 58.0, band_w, 3.0), false, Color(C_ACCENT, 0.7 * a))
	draw_texture_rect(FxTex.band(), Rect2(cx - band_w * 0.5, cy + 55.0, band_w, 3.0), false, Color(C_ACCENT, 0.7 * a))
	if world.is_bonus():
		_text_parts(Vector2(cx, cy - 30.0), intro_caption(), UiKit.label_size(13), a)
		_glow_text(Vector2(cx, cy + 10.0), LevelData.BONUS_TITLE, 40, a, e)
		UiKit.text(self, _f_body, Vector2(cx, cy + 42.0), "100 shots – destroy 20 demons", 20, Color(C_VALUE, a), HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_text_parts(Vector2(cx, cy - 34.0), intro_caption(), UiKit.label_size(12), a)
		_glow_text(Vector2(cx, cy + 12.0), "LEVEL %d" % level, 54, a, e)
		UiKit.text(self, _f_body, Vector2(cx, cy + 44.0), String(LevelData.level(level)["name"]).to_upper(), 20,
			Color(C_VALUE, a), HORIZONTAL_ALIGNMENT_CENTER)
	if world.powerup != LevelData.PowerUp.NONE:
		_text_parts(Vector2(cx, cy + POWERUP_LINE_DY), [["POWER-UP:  ", C_LABEL], [powerup_name(world.powerup), powerup_color(world.powerup)]],
			UiKit.label_size(13), a)


## Caption line of the intro banner as [text, colour] parts: "SATURN  ·  NORMAL" (bonus level: "LEVEL 13  ·  BONUS
## ROUND"); in a two-player match it starts with "PLAYER k" in the player colour (SPEC §19.2).
func intro_caption() -> Array:
	var rest := "LEVEL %d  ·  BONUS ROUND" % level if world.is_bonus() \
		else String(LevelData.PLANET_NAMES[_planet]).to_upper() + "  ·  " + _difficulty_name()
	if attract or not Run.is_two_player():
		return [[rest, C_ACCENT]]
	return [[Run.player_label(Run.current), UiKit.player_color(Run.current)], ["  ·  " + rest, C_ACCENT]]


## One centred line made of differently coloured parts ([text, colour] each) in the caption font, faded by `a`.
func _text_parts(center: Vector2, parts: Array, size: int, a: float) -> void:
	var total := 0.0
	for p: Array in parts:
		total += _f_label.get_string_size(String(p[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := center.x - total * 0.5
	for p: Array in parts:
		var c: Color = p[1]
		UiKit.text(self, _f_label, Vector2(x, center.y), String(p[0]), size, Color(c, c.a * a))
		x += _f_label.get_string_size(String(p[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


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
	draw_texture_rect(FxTex.band(), Rect2(0, cy - 50.0, width, 100.0), false, Color(0.02, 0.03, 0.08, 0.6 * a))
	var title := "BONUS COMPLETE" if world.is_bonus() else "LEVEL CLEAR"
	_glow_text(Vector2(_cx(), cy + 8.0), title, 40, a, e)
	if world.state == GameWorld.State.COMPLETE:
		var sub := "BONUS  +%d" % world.completion_bonus
		if world.extra_life_awarded:
			sub += "   ·   EXTRA LIFE"
		UiKit.text(self, _f_body, Vector2(_cx(), cy + 38.0), sub, 18, Color(C_ACCENT, a), HORIZONTAL_ALIGNMENT_CENTER)


# --- Pause ---------------------------------------------------------------------------------------
func _draw_pause() -> void:
	var cx := _cx()
	draw_rect(Rect2(0, 0, width, LevelData.SCREEN_H), Color(0.0, 0.01, 0.03, 0.62))
	draw_texture_rect(FxTex.band(), Rect2(0, 150.0, width, 380.0), false, Color(0.03, 0.05, 0.12, 0.84))
	_glow_text(Vector2(cx, 222.0), "PAUSED", 56, 1.0, 1.0)
	var top := PAUSE_ROW_Y - 36.0
	var bottom := PAUSE_ROW_Y + (PAUSE_ROWS.size() - 1) * PAUSE_ROW_STEP + PAUSE_CAPTION_DY + 20.0
	UiKit.panel(self, Rect2(cx - PAUSE_ROW_W * 0.5 - 40.0, top, PAUSE_ROW_W + 80.0, bottom - top), 0.8)
	for i in PAUSE_ROWS.size():
		var row: Array = PAUSE_ROWS[i]
		var item := String(row[0])
		var on := Settings.volume_switch_on(item)
		var cy := PAUSE_ROW_Y + i * PAUSE_ROW_STEP
		UiKit.menu_item_volume(self, Vector2(cx, cy), String(row[1]), Settings.volume(item), i == pause_sel, anim,
			PAUSE_ROW_W, 18, on)
		UiKit.text(self, Assets.font_body, Vector2(cx, cy + PAUSE_CAPTION_DY), String(row[2] if on else row[3]), 14,
			Color(C_LABEL, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.hint_bar(self, Vector2(cx, 438.0), [[["UD"], "Select"], [["LR"], "Volume"]], 14)
	UiKit.text(self, _f_body, Vector2(cx, 480.0), "P / ESC / START   resume", 20, C_VALUE, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.text(self, _f_body, Vector2(cx, 508.0), "Q / BACK   quit to title", 20, C_LABEL, HORIZONTAL_ALIGNMENT_CENTER)


# --- Attract mode (demo) -------------------------------------------------------------------------
## Unobtrusive overlay that never covers the play: "DEMO" in the free band under the top bar and a gently
## blinking "PRESS ANY BUTTON" in the ground strip below the ship.
func _draw_attract() -> void:
	var a := clampf(anim / 0.4, 0.0, 1.0)
	var cx := _cx()
	var demo := "DEMO"
	var size := 18
	var spacing := 9.0
	var half := UiKit.spaced_width(_f_value, demo, size, spacing) * 0.5
	UiKit.divider(self, Vector2(cx - half - 62.0, ATTRACT_DEMO_Y - 7.0), 90.0, Color(C_ACCENT, 0.55 * a))
	UiKit.divider(self, Vector2(cx + half + 62.0, ATTRACT_DEMO_Y - 7.0), 90.0, Color(C_ACCENT, 0.55 * a))
	UiKit.text_spaced(self, _f_value, Vector2(cx, ATTRACT_DEMO_Y), demo, size, spacing, Color(C_ACCENT, 0.85 * a),
		HORIZONTAL_ALIGNMENT_CENTER)
	# Ground strip (685…720): dark pill + blinking prompt.
	var prompt := "PRESS ANY BUTTON"
	var psize := 14
	var cy := LevelData.GROUND_Y + (LevelData.SCREEN_H - LevelData.GROUND_Y) * 0.5
	var w := UiKit.spaced_width(_f_label, prompt, psize, 3.0)
	var r := Rect2(cx - w * 0.5 - 22.0, cy - 12.0, w + 44.0, 24.0)
	UiKit.backing(self, r, 0.85 * a)
	var blink := 0.7 + 0.3 * cos(anim * TAU * ATTRACT_BLINK_HZ)
	UiKit.text_spaced(self, _f_label, Vector2(cx, UiKit.baseline_for(_f_label, psize, cy)), prompt, psize, 3.0,
		Color(C_VALUE, blink * a), HORIZONTAL_ALIGNMENT_CENTER)
