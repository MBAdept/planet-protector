extends ScreenBase
## Result of the bonus level 13 (docs/SPEC.md §10, §11): remaining attempts, ship factor, bonus and
## "EXTRA LIFE!" if awarded (Run.last_bonus_result). No planet counter. Stays until confirm.
## finished: "continue".

const CONFIRM_DELAY := 0.6
const COUNT_TIME := 1.3

var _remaining := 0
var _factor := 0
var _bonus := 0
var _extra := false
var _shown := 0          # currently displayed (counting) bonus
var _tick_acc := 0.0
var _skip := false


func _enter() -> void:
	AudioManager.stop_music()
	var r: Dictionary = Run.last_bonus_result
	_factor = int(r.get("factor", ShipData.ship(Run.ship_id)["bonus_factor"]))
	_remaining = int(r.get("remaining", 0))
	_bonus = int(r.get("bonus", _remaining * _factor))
	_extra = bool(r.get("extra_life", LevelData.bonus_gives_extra_life(_bonus)))


func _count_t() -> float:
	if _skip:
		return 1.0
	return clampf((time - 0.7) / COUNT_TIME, 0.0, 1.0)


func _tick(delta: float) -> void:
	var u := _count_t()
	var target := int(round(_bonus * u))
	if target != _shown:
		_tick_acc += delta
		if _tick_acc >= 0.06:
			_tick_acc = 0.0
			sfx("bonus_tick")
		_shown = target
		if u >= 1.0 and _extra:
			sfx("extra_life")
	if time >= CONFIRM_DELAY and InputRouter.confirm_pressed():
		if u < 1.0:
			_skip = true   # first press completes the count-up
			return
		sfx("menu_confirm")
		finish("continue")


func _draw() -> void:
	var a := ramp(0.0, 0.35)
	# Mars in the lower left corner (16:9: the same distance from the canvas edge).
	Assets.draw_planet(self, "mars", Vector2(150.0 - ox, 610), 380.0, Color(1, 1, 1, 0.42 * ramp(0.0, 0.8)))
	draw_title("BONUS ROUND COMPLETE", 112, 36, Color(UiKit.COLOR_TEXT, a), UiKit.COLOR_ACCENT)
	UiKit.text(self, Assets.font_body, Vector2(CX, 152), LevelData.BONUS_TITLE, 21, Color(UiKit.COLOR_ACCENT, a),
		HORIZONTAL_ALIGNMENT_CENTER)
	var panel := Rect2(CX - 250, 192, 500, 300)
	UiKit.panel(self, panel, 0.62 * a)
	var lx := panel.position.x + 36
	var rx := panel.end.x - 36
	var ship_name := String(ShipData.ship(Run.ship_id)["name"])
	UiKit.stat_row(self, lx, rx, 240, "REMAINING ATTEMPTS", "%d / %d" % [_remaining, LevelData.BONUS_ATTEMPTS], 20,
		Color(UiKit.COLOR_DIM, a), Color(UiKit.COLOR_TEXT, a))
	UiKit.stat_row(self, lx, rx, 284, "SHIP FACTOR  (%s)" % ship_name, "×%d" % _factor, 20,
		Color(UiKit.COLOR_DIM, a), Color(UiKit.COLOR_TEXT, a))
	UiKit.divider(self, Vector2(CX, 312), 430, Color(UiKit.COLOR_ACCENT, 0.45 * a), 1.5)
	# Equation + counting bonus
	UiKit.text(self, Assets.font_body, Vector2(CX, 346), "%d  ×  %d  =" % [_remaining, _factor], 19,
		Color(UiKit.COLOR_DIM, a), HORIZONTAL_ALIGNMENT_CENTER)
	var done := _count_t() >= 1.0
	UiKit.text_glow(self, Assets.font_title_heavy, Vector2(CX, 408), Fmt.score(_shown), 50,
		Color(UiKit.COLOR_GOLD, a), UiKit.COLOR_ACCENT, HORIZONTAL_ALIGNMENT_CENTER, 1.0 if done else 0.6)
	UiKit.text(self, Assets.font_body, Vector2(CX, 440), "BONUS POINTS", 15, Color(UiKit.COLOR_FAINT, a),
		HORIZONTAL_ALIGNMENT_CENTER)
	if done:
		var ea := clampf((time - 0.7 - COUNT_TIME) / 0.3, 0.0, 1.0) if not _skip else 1.0
		if _extra:
			var pulse := 0.8 + 0.2 * sin(time * 5.0)
			UiKit.text_glow(self, Assets.font_title_heavy, Vector2(CX, 474), "EXTRA LIFE!", 24,
				Color(UiKit.COLOR_GOOD, ea * pulse), UiKit.COLOR_GOOD, HORIZONTAL_ALIGNMENT_CENTER, ea)
		else:
			UiKit.text(self, Assets.font_body, Vector2(CX, 474), "Extra life for a bonus above %d" %
				LevelData.BONUS_EXTRA_LIFE_THRESHOLD, 15, Color(UiKit.COLOR_FAINT, ea), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.stat_row(self, CX - 200, CX + 200, 548, "SCORE", Fmt.score(Run.score), 20,
		Color(UiKit.COLOR_DIM, a), Color(UiKit.COLOR_TEXT, a))
	UiKit.stat_row(self, CX - 200, CX + 200, 584, "TOTAL TIME", Fmt.time(Run.active_time), 20,
		Color(UiKit.COLOR_DIM, a), Color(UiKit.COLOR_TEXT, a))
	draw_continue_hint("Continue", CONFIRM_DELAY)
