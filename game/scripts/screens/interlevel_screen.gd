extends ScreenBase
## Between two levels (docs/SPEC.md §11): "LEVEL n COMPLETE", level name, level bonus, extra life (if
## awarded), score, total play time and the progress line (LevelData.progress_text). Confirm continues;
## confirm is ignored during the first 0.6 s. finished: "continue".
## setup args: {"level": n} (defaults to Run.last_level_result.level / Run.level).

const CONFIRM_DELAY := 0.6
const PLANET_POS := Vector2(890, 700)   ## lower right corner (16:9: + ox, the same distance from the edge)
const PLANET_D := 440.0
const PANEL_TOP := 232.0
const PANEL_W := 460.0
const ROW_H := 44.0
const PROGRESS_SIZE := 22

var _n := 1
var _bonus := 0
var _extra_life := false


func _enter() -> void:
	AudioManager.stop_music()
	var res: Dictionary = Run.last_level_result
	_n = int(args.get("level", res.get("level", Run.level)))
	_bonus = int(res.get("completion_bonus", LevelData.level(_n)["bonus"]))
	_extra_life = bool(res.get("extra_life", false))


func _tick(_delta: float) -> void:
	if time >= CONFIRM_DELAY and InputRouter.confirm_pressed():
		var snd := confirm_sound(_n)
		if snd != "":
			sfx(snd)
		finish("continue")


## Result panel for `rows` rows (4, or 5 with the extra-life row).
static func panel_rect(rows: int) -> Rect2:
	return Rect2(CX - PANEL_W * 0.5, PANEL_TOP, PANEL_W, rows * ROW_H + 36.0)


## Baseline of the progress line below the panel.
static func progress_baseline(rows: int) -> float:
	return panel_rect(rows).end.y + 58.0


## Sound for confirming the interlevel of level n: none when an arrival sequence follows, because the
## arrival is completely silent (SPEC §11/§14) and a confirm sound would ring on into it.
static func confirm_sound(n: int) -> String:
	return "" if RunFlow.next("interlevel", "continue", n)["screen"] == "arrival" else "menu_confirm"


func _draw() -> void:
	var planet := LevelData.planet_of(_n)
	# The planet of the finished battle, big and dim in the lower right corner - far enough out that its
	# limb stays clear of the progress line even with the extra-life row (levels 15-18).
	var pa := 0.55 * ramp(0.0, 0.8)
	Assets.draw_planet(self, planet, PLANET_POS + Vector2(ox, 14.0 * (1.0 - ramp(0.0, 1.2))), PLANET_D,
		Color(1, 1, 1, pa))
	draw_rect(full_rect(), Color(0, 0, 0, 0.18))
	var a := ramp(0.0, 0.35)
	draw_title("LEVEL %d COMPLETE" % _n, 150, 42, Color(UiKit.COLOR_TEXT, a))
	UiKit.text_spaced(self, Assets.font_title, Vector2(CX, 190), String(LevelData.level(_n)["name"]).to_upper(), 17,
		4.0, Color(UiKit.COLOR_HILITE, a), HORIZONTAL_ALIGNMENT_CENTER)
	# Result panel
	var rows: Array = []
	rows.append(["LEVEL BONUS", "+%s" % Fmt.score(int(round(_bonus * ramp(0.25, 0.6)))), UiKit.COLOR_GOLD])
	if _extra_life:
		rows.append(["FLAWLESS", "EXTRA LIFE!", UiKit.COLOR_GOOD])
	rows.append(["SCORE", Fmt.score(Run.score), UiKit.COLOR_TEXT])
	rows.append(["TOTAL TIME", Fmt.time(Run.active_time), UiKit.COLOR_TEXT])
	rows.append(["LIVES", str(Run.lives), UiKit.COLOR_TEXT])
	var row_h := ROW_H
	var pw := PANEL_W
	var top := PANEL_TOP
	var panel := panel_rect(rows.size())
	UiKit.panel(self, panel, 0.62 * a)
	for i in rows.size():
		var ra := ramp(0.12 + i * 0.07, 0.3)
		var by := top + 18.0 + row_h * (i + 0.5) + 8.0
		var row: Array = rows[i]
		var dx := (1.0 - ra) * 18.0
		UiKit.text(self, Assets.font_body, Vector2(panel.position.x + 34 + dx, by), row[0], 20, Color(UiKit.COLOR_DIM, ra))
		var vc: Color = row[2]
		if row[1] == "EXTRA LIFE!":
			UiKit.text_glow(self, Assets.font_title, Vector2(panel.end.x - 34 + dx, by), row[1], 21, Color(vc, ra),
				UiKit.COLOR_GOOD, HORIZONTAL_ALIGNMENT_RIGHT, 0.8 * ra)
		else:
			UiKit.text(self, Assets.font_title, Vector2(panel.end.x - 34 + dx, by), row[1], 21, Color(vc, ra),
				HORIZONTAL_ALIGNMENT_RIGHT)
		if i < rows.size() - 1:
			UiKit.divider(self, Vector2(CX, top + 18.0 + row_h * (i + 1)), pw - 60, Color(UiKit.COLOR_BORDER, 0.16 * ra), 1.0)
	# Progress line ("2 more battles until Uranus" / "Neptune secured!")
	var pa2 := ramp(0.45, 0.4)
	var secured := LevelData.ARRIVAL_AFTER.has(_n) or _n >= LevelData.LAST_LEVEL
	UiKit.text_glow(self, Assets.font_title, Vector2(CX, progress_baseline(rows.size())), LevelData.progress_text(_n),
		PROGRESS_SIZE,
		Color(UiKit.COLOR_GOLD if secured else UiKit.COLOR_ACCENT, pa2), UiKit.COLOR_ACCENT,
		HORIZONTAL_ALIGNMENT_CENTER, 0.7 * pa2)
	draw_continue_hint("Continue", CONFIRM_DELAY)
