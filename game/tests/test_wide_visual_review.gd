extends TestBase
## Visual & UX review of the widescreen round (display modes 0 / 1 / 2, docs/SPEC.md §11.2, §18).
## Every screen was captured in all three modes (xvfb 2560×1440 / 1920×1080, plus X-root grabs of the real window on a
## 1920×1200 screen for letterboxing and F11) and looked at; these tests pin what can be checked headlessly.
## Failing tests are review findings (see the messages); the others guard behaviour that was verified on screen.
## Like test_display.gd: the display mode is forced with Display.forced_mode and restored, no settings are written.

const Victory := preload("res://scripts/screens/victory_screen.gd")
const Arrival := preload("res://scripts/screens/arrival_screen.gd")
const TitleScreen := preload("res://scripts/screens/title_screen.gd")
const DisplaySelect := preload("res://scripts/screens/display_select_screen.gd")

const STEP := 1.0 / 60.0
const SCRATCH_CFG := "user://test_wide_visual_review_settings.cfg"


class SpyTitle extends TitleScreen:
	var results: Array[String] = []

	func sfx(_n: String) -> void:
		pass

	func finish(result: String, data: Dictionary = {}) -> void:
		results.append(result)
		super(result, data)


class SpySelect extends DisplaySelect:
	var results: Array[String] = []

	func sfx(_n: String) -> void:
		pass

	func finish(result: String, data: Dictionary = {}) -> void:
		results.append(result)
		super(result, data)


## No joypad exists headless: InputRouter gets a subclass that reads a fake button table / left stick (as in
## test_display.gd).
class FakePadRouter extends "res://scripts/autoload/input_router.gd":
	var pad := {}
	var stick := Vector2.ZERO

	func _joy(button: JoyButton) -> bool:
		return bool(pad.get(button, false))

	func _left_sticks() -> Dictionary:
		return {0: stick}


func _force(m: int) -> int:
	var before := Display.forced_mode
	Display.forced_mode = m
	Display.apply_canvas()
	return before


func _restore(before: int) -> void:
	Display.forced_mode = before
	Display.apply_canvas()


func _fonts() -> void:
	if Assets.font_title == null:
		Assets._ready()


## FINDING (minor, fixed): the victory Earth was visibly pixelated in the 16:9 modes. SPEC §11.2 grows it with the
## canvas (diameter 960 · W / 960 = 1280 logical px), and the canvas is rendered at ×1.5 / ×2.0, so the 640 px sphere
## of assets/sprites/planets/earth.png was drawn 1920 / 2560 px wide: a 3× / 4× upscale next to crisp UI text
## (screenshot m2_victory, 1:1 crop of the lower half: blocky coastlines and clouds). In the classic default window
## (960 logical px at 1280 / 960) it is 2×. The 16:9 modes promise a "sharp" / "extra sharp" picture.
## Fix: the victory screen draws its own 1280 px render of the Earth (Victory.EARTH_ASSET). The check measures the
## texture the screen really draws against the 2× of the in-game sprite in the classic window (test adjusted: as
## first written it took both from earth.png, i.e. it compared 2560 / 640 with 1280 / 640 and could never pass).
func test_victory_earth_is_not_blown_up_beyond_the_classic_window() -> void:
	var classic_scale := float(Display.CLASSIC_WINDOW.x) / float(Display.LOGICAL_4_3.x)
	var classic_up := 960.0 * classic_scale / float(Assets.planet_info("earth")["sphere_diameter_px"])
	check_near(classic_up, 2.0, 0.01, "classic default window: the in-game Earth sprite at 960 px is a 2× upscale")
	var asset := Victory.earth_asset()
	check_eq(asset, Victory.EARTH_ASSET, "the victory screen draws its high-resolution Earth")
	var tex_d := float(Assets.planet_info(asset)["sphere_diameter_px"])
	for m in [Display.Mode.WINDOW_4_3, Display.Mode.FULLSCREEN_1080, Display.Mode.FULLSCREEN_1440]:
		var w := float(Display.logical_size_of(m).x)
		var d := Victory.earth_diameter(w)
		check_near(d, 960.0 * w / ScreenBase.W, 0.001, "mode %d: SPEC §11.2 diameter 960 · W / 960" % m)
		var k := classic_scale if m == Display.Mode.WINDOW_4_3 else Display.canvas_scale_of(m)
		var render_px := d * k
		var up := render_px / tex_d
		check(up <= classic_up + 1e-6,
			"mode %d (%s): victory Earth drawn %.0f px wide from a %.0f px texture sphere = %.1f× upscale (classic window %.1f×) – visibly pixelated at the render resolution" % [
			m, Display.mode_name(m), render_px, tex_d, up, classic_up])


## Guard (verified on screen): the victory sparkles cover the whole 16:9 canvas, both side bands included.
func test_victory_sparkles_cover_the_wide_canvas() -> void:
	_fonts()
	for m in [0, 1]:
		var before := _force(m)
		var v: Node2D = Victory.new()
		v.setup({"level": LevelData.LAST_LEVEL, "qualifies": false})
		v._ready()
		var sparks: Array = v.get("_sparks")
		var lo := INF
		var hi := -INF
		for s: Vector4 in sparks:
			lo = minf(lo, s.x)
			hi = maxf(hi, s.x)
		check(lo >= v.left_x() and hi <= v.right_x(), "mode %d: sparkles on the canvas (%.0f … %.0f)" % [m, lo, hi])
		if m == 1:
			check(lo < 0.0 and hi > ScreenBase.W, "16:9: sparkles reach both side bands (%.0f … %.0f)" % [lo, hi])
			check_eq(sparks.size(), 61, "16:9: proportionally more sparkles (46 · 1280 / 960)")
		v.free()
		_restore(before)
	AudioManager.stop_music()


## Guard (verified on screen, m2_arr*_t4.5 / t6.5 / t6.9): on the 1280 canvas every arrival message is fully visible
## while it fades in (3–6 s), and it has left the canvas completely before the planet appears (7 s).
func test_arrival_message_timeline_on_the_wide_canvas() -> void:
	_fonts()
	var before := _force(1)
	var ox := Display.center_offset()
	var font := Assets.font_title_heavy
	for n: int in LevelData.ARRIVAL_AFTER:
		var text: String = LevelData.ARRIVAL_AFTER[n]["text"]
		var w := UiKit.text_width(font, text, UiKit.fit_size(font, text, 30, 900.0))
		var left_at_6 := ScreenBase.CX + Arrival.message_offset(Arrival.T_MSG_OUT) - w * 0.5
		var right_at_6 := ScreenBase.CX + Arrival.message_offset(Arrival.T_MSG_OUT) + w * 0.5
		check(left_at_6 >= -ox and right_at_6 <= ScreenBase.W + ox, "after %d: message on the canvas at 6 s" % n)
		check(Arrival.message_alpha(Arrival.T_MSG_OUT - 0.01) > 0.95, "after %d: fully faded in at 6 s" % n)
		var right_at_7 := ScreenBase.CX + Arrival.message_offset(Arrival.T_PLANET - 0.001) + w * 0.5
		check(right_at_7 < -ox, "after %d: off the 1280 canvas before the planet appears (%.0f)" % [n, right_at_7])
		check_eq(Arrival.planet_diameter(Arrival.T_PLANET - 0.01), 0.0, "after %d: no planet before 7 s" % n)
	_restore(before)


# --- Controller paths of the first-start screen and the title DISPLAY row ----------------------------
func _run(screen: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		Input.flush_buffered_events()
		InputRouter._process(STEP)
		screen._process(STEP)
		t += STEP


func _pad_tap(screen: Node, button: JoyButton) -> void:
	InputRouter.pad[button] = true
	_run(screen, STEP)
	InputRouter.pad[button] = false
	_run(screen, STEP * 2)


func _stick_tap(screen: Node, v: Vector2) -> void:
	InputRouter.stick = v
	_run(screen, STEP)
	InputRouter.stick = Vector2.ZERO
	_run(screen, STEP * 2)


## Guard (verified with the runtime driver for the keyboard; the controller can only be faked headless): on the
## first-start screen Back does nothing (no quit, nothing stored), stick left/right select like up/down, Start
## confirms. On the title DISPLAY row B keeps a pending choice (B is ignored on the title), Start applies it, and
## Back (highscores) leaves without applying.
func test_controller_back_and_start_on_first_start_and_title_display() -> void:
	var saved := {"path": Settings.settings_path, "mode": Settings.display_mode, "chosen": Settings.display_chosen,
		"forced": Display.forced_mode, "windowed": Display.wide_windowed}
	Settings.settings_path = SCRATCH_CFG
	Display.forced_mode = -1
	Settings.display_mode = 0
	Settings.display_chosen = false
	Display.apply_canvas()
	var orig_router: Script = InputRouter.get_script()
	InputRouter.set_script(FakePadRouter)
	InputRouter._ready()
	InputRouter.set_text_mode(false)
	InputRouter._process(STEP)
	var s := SpySelect.new()
	s.setup({})
	s._ready()
	_run(s, 0.1)
	_pad_tap(s, JOY_BUTTON_BACK)
	check(s.results.is_empty(), "first start: Back does nothing")
	check(not FileAccess.file_exists(SCRATCH_CFG), "first start: Back stores nothing")
	_stick_tap(s, Vector2(0.9, 0.0))
	check_eq(s.selected(), 1, "first start: stick right selects the next mode")
	_stick_tap(s, Vector2(-0.9, 0.0))
	_stick_tap(s, Vector2(-0.9, 0.0))
	check_eq(s.selected(), 2, "first start: stick left wraps")
	_pad_tap(s, JOY_BUTTON_START)
	check_eq(s.results, ["confirm"] as Array[String], "first start: Start confirms")
	check_eq([Display.mode(), Settings.display_mode, Settings.display_chosen], [2, 2, true], "1440 chosen + stored")
	s.free()
	var t := SpyTitle.new()
	t.setup({"select": "display"})
	t._ready()
	_run(t, 0.1)
	_stick_tap(t, Vector2(0.9, 0.0))
	check_eq(t.display_pending, 0, "title: stick right on DISPLAY → classic pending (wraps)")
	_pad_tap(t, JOY_BUTTON_B)
	check(t.results.is_empty() and t.display_is_pending(), "title: B is ignored and keeps the pending choice")
	_pad_tap(t, JOY_BUTTON_START)
	check_eq(t.results, ["display"] as Array[String], "title: Start applies the pending mode")
	check_eq([Display.mode(), Settings.display_mode], [0, 0], "classic applied + stored")
	t.free()
	var t2 := SpyTitle.new()
	t2.setup({"select": "display"})
	t2._ready()
	_run(t2, 0.1)
	_stick_tap(t2, Vector2(0.9, 0.0))
	_pad_tap(t2, JOY_BUTTON_BACK)
	check_eq(t2.results, ["highscores"] as Array[String], "title: Back opens the highscores")
	check_eq(Display.mode(), 0, "the pending 1080 choice was not applied")
	t2.free()
	InputRouter.set_script(orig_router)
	InputRouter._ready()
	InputRouter._process(STEP)
	if FileAccess.file_exists(SCRATCH_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_CFG))
	Settings.settings_path = saved["path"]
	Settings.display_mode = saved["mode"]
	Settings.display_chosen = saved["chosen"]
	Display.forced_mode = saved["forced"]
	Display.wide_windowed = saved["windowed"]
	Display.apply_canvas()
	AudioManager.stop_music()
