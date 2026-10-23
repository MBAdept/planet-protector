extends ScreenBase
## Victory after level 20 (docs/SPEC.md §11): Earth big in the background, the exact
## LevelData.VICTORY_TEXT, final score and time. Confirm → finished("continue") (Main then opens the
## name entry if the score qualifies, else the highscores).

const CONFIRM_DELAY := 1.5

var _sparks: Array[Vector4] = []   # x, y, speed, phase


func _enter() -> void:
	AudioManager.stop_music()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2020
	for i in 46:
		_sparks.append(Vector4(rng.randf() * W, rng.randf() * H, rng.randf_range(10.0, 32.0), rng.randf() * TAU))


func _star_velocity() -> Vector2:
	return Vector2(-6, 0)


func _tick(_delta: float) -> void:
	if time >= CONFIRM_DELAY and InputRouter.confirm_pressed():
		sfx("menu_confirm")
		finish("continue")


func _draw() -> void:
	# Earth rising from below, big, with a soft atmosphere glow.
	var rise := 1.0 - ramp(0.0, 3.5)
	var c := Vector2(CX, 905.0 + 110.0 * rise)
	var d := 960.0
	UiKit.glow_spot(self, c, Vector2(d, d) * 0.64, Color(0.35, 0.6, 1.0, 0.34))
	Assets.draw_planet(self, "earth", c, d)
	# Thin bright atmosphere rim on top of the sphere.
	draw_arc(c, d * 0.5 + 1.5, PI * 1.08, PI * 1.92, 96, Color(0.55, 0.8, 1.0, 0.35), 3.0, true)
	# Golden sparkles drifting up.
	for s in _sparks:
		var y := fposmod(s.y - s.z * time, H)
		var twinkle := 0.5 + 0.5 * sin(time * 2.0 + s.w)
		UiKit.glow_spot(self, Vector2(s.x + 6.0 * sin(time * 0.7 + s.w), y), Vector2(5, 5) * (0.6 + twinkle),
			Color(1.0, 0.85, 0.45, 0.35 * twinkle * ramp(0.5, 1.0)))
	var a := ramp(0.2, 0.6)
	UiKit.text_spaced(self, Assets.font_title, Vector2(CX, 70), "EARTH IS SAFE", 16, 8.0,
		Color(UiKit.COLOR_HILITE, a), HORIZONTAL_ALIGNMENT_CENTER)
	draw_title("VICTORY!", 128, 54, Color(UiKit.COLOR_GOLD, a), UiKit.COLOR_ACCENT)
	# The victory text, balanced wrap, revealed line by line.
	var font := Assets.font_body
	var size := 25
	var lines := UiKit.wrap_balanced(font, LevelData.VICTORY_TEXT, size, 760.0)
	var lh := 38.0
	var y0 := 205.0
	var tw := 0.0
	for line in lines:
		tw = maxf(tw, UiKit.text_width(font, line, size))
	var pw := tw + 90.0
	var panel := Rect2(CX - pw * 0.5, y0 - 40, pw, lines.size() * lh + 34)
	UiKit.panel(self, panel, 0.5 * a)
	for i in lines.size():
		var la := ramp(0.7 + i * 0.35, 0.5)
		UiKit.text(self, font, Vector2(CX, y0 + lh * i + (1.0 - la) * 6.0), lines[i], size, Color(UiKit.COLOR_TEXT, la),
			HORIZONTAL_ALIGNMENT_CENTER)
	# Final stats
	var sa := ramp(0.9 + lines.size() * 0.35, 0.5)
	var sy := panel.end.y + 70.0
	_stat(CX - 230, sy, "FINAL SCORE", Fmt.score(Run.score), UiKit.COLOR_GOLD, sa)
	_stat(CX, sy, "PLAY TIME", Fmt.time(Run.active_time), UiKit.COLOR_TEXT, sa)
	_stat(CX + 230, sy, "DIFFICULTY", Run.difficulty_name(), UiKit.COLOR_ACCENT, sa)
	draw_continue_hint("Continue", CONFIRM_DELAY)


func _stat(x: float, baseline: float, label: String, value: String, col: Color, a: float) -> void:
	UiKit.text(self, Assets.font_body, Vector2(x, baseline - 34), label, 15, Color(UiKit.COLOR_DIM, a),
		HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.text_outlined(self, Assets.font_title, Vector2(x, baseline), value, 28, Color(col, a), Color(0, 0, 0, 0.6 * a), 6,
		HORIZONTAL_ALIGNMENT_CENTER)
