extends TestBase
## Display modes (client request, widescreen round; docs/SPEC.md §1, §11, §12): persistence + old settings files,
## the first-start flow and screen, the title DISPLAY item (pending choice, apply, layout in both canvas sizes),
## logical sizes / offsets, the render configuration of the 16:9 modes (what a screenshot is: headless cannot
## render, so the root viewport configuration is checked), F11 window sizes, the size-aware Starfield and the
## full-width screen layout.
## Like the other screen tests these run before the SceneTree is live: screens are driven by hand and the
## InputRouter is stepped manually. Settings go to a scratch file (Settings.settings_path) and every display change
## is undone (mode 0 canvas restored), so neither the player's settings.cfg nor later tests are affected.

const TitleScreen := preload("res://scripts/screens/title_screen.gd")
const DisplaySelect := preload("res://scripts/screens/display_select_screen.gd")
const ShipSelect := preload("res://scripts/screens/ship_select_screen.gd")
const Interlevel := preload("res://scripts/screens/interlevel_screen.gd")
const Arrival := preload("res://scripts/screens/arrival_screen.gd")
const Victory := preload("res://scripts/screens/victory_screen.gd")

const STEP := 1.0 / 60.0
const SCRATCH_CFG := "user://test_display_settings.cfg"


## Screens that record their finished() results and keep silent.
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


## No joypad can be connected in the headless runner: like test_volume.gd the InputRouter autoload gets a subclass
## for the controller tests that only reads a fake button table / fake left stick.
class FakePadRouter extends "res://scripts/autoload/input_router.gd":
	var pad := {}
	var stick := Vector2.ZERO

	func _joy(button: JoyButton) -> bool:
		return bool(pad.get(button, false))

	func _left_sticks() -> Dictionary:
		return {0: stick}


# --- Helpers -------------------------------------------------------------------------------------
var _saved := {}
var _orig_router: Script


func _swap_in() -> void:
	_orig_router = InputRouter.get_script()
	InputRouter.set_script(FakePadRouter)
	InputRouter._ready()
	InputRouter.set_text_mode(false)
	InputRouter._process(STEP)


func _swap_out() -> void:
	InputRouter.set_script(_orig_router)
	InputRouter._ready()
	InputRouter._process(STEP)


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


func _begin() -> void:
	_saved = {"path": Settings.settings_path, "difficulty": Settings.difficulty, "music_on": Settings.music_on,
		"sfx_on": Settings.sfx_on, "fullscreen": Settings.fullscreen, "music_volume": Settings.music_volume,
		"sfx_volume": Settings.sfx_volume, "display_mode": Settings.display_mode,
		"display_chosen": Settings.display_chosen, "forced": Display.forced_mode, "windowed": Display.wide_windowed}
	Settings.settings_path = SCRATCH_CFG
	_remove_scratch()


func _end() -> void:
	_remove_scratch()
	Settings.settings_path = _saved["path"]
	for k in ["difficulty", "music_on", "sfx_on", "fullscreen", "music_volume", "sfx_volume", "display_mode",
			"display_chosen"]:
		Settings.set(k, _saved[k])
	Display.forced_mode = _saved["forced"]
	Display.wide_windowed = _saved["windowed"]
	Display.apply_canvas()
	AudioManager.apply_settings()


func _remove_scratch() -> void:
	if FileAccess.file_exists(SCRATCH_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_CFG))


func _stored(section: String, key: String) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(SCRATCH_CFG) != OK:
		return null
	return cfg.get_value(section, key, null)


## Puts the display into mode m for this test (as if stored) and sets up the canvas.
func _mode(m: int) -> void:
	Display.forced_mode = -1
	Settings.display_mode = m
	Display.apply_canvas()


func _router_init() -> void:
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	InputRouter.set_text_mode(false)
	_router_step()


func _router_step(dt: float = STEP) -> void:
	Input.flush_buffered_events()
	InputRouter._process(dt)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _run(screen: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		_router_step()
		screen._process(STEP)
		t += STEP


func _tap(screen: Node, code: Key) -> void:
	_key(code, true)
	_run(screen, STEP)
	_key(code, false)
	_run(screen, STEP * 2)


func _fonts() -> void:
	if Assets.font_title == null:
		Assets._ready()


# --- Settings ------------------------------------------------------------------------------------
func test_settings_defaults_persistence_and_old_files() -> void:
	_begin()
	# A fresh start (no file): classic mode, not chosen → the first-start screen appears.
	Settings.display_mode = 2
	Settings.display_chosen = true
	Settings.load_settings()   # no file: nothing is loaded, the values stay
	Settings.display_mode = 0
	Settings.display_chosen = false
	Settings.set_display_mode(2)
	Settings.set_display_chosen(true)
	check_eq(_stored("video", "display_mode"), 2, "display_mode stored")
	check_eq(_stored("video", "display_chosen"), true, "display_chosen stored")
	Settings.display_mode = 0
	Settings.display_chosen = false
	Settings.load_settings()
	check_eq(Settings.display_mode, 2, "display_mode loaded")
	check_eq(Settings.display_chosen, true, "display_chosen loaded")
	# A settings file written before this version (no display keys): mode 0, not chosen; other options unchanged.
	var old := ConfigFile.new()
	old.set_value("game", "difficulty", 2)
	old.set_value("audio", "music_on", false)
	old.set_value("audio", "sfx_on", true)
	old.set_value("audio", "music_volume", 70)
	old.set_value("audio", "sfx_volume", 40)
	old.set_value("video", "fullscreen", true)
	old.save(SCRATCH_CFG)
	Settings.load_settings()
	check_eq(Settings.display_mode, 0, "old file: classic mode")
	check_eq(Settings.display_chosen, false, "old file: not chosen → first-start screen once")
	check_eq([Settings.difficulty, Settings.music_on, Settings.music_volume, Settings.sfx_volume, Settings.fullscreen],
		[2, false, 70, 40, true], "old file: the other options load unchanged")
	# Damaged values fall back to the safe defaults.
	var bad := ConfigFile.new()
	bad.set_value("video", "display_mode", "wide")
	bad.set_value("video", "display_chosen", "yes")
	bad.save(SCRATCH_CFG)
	Settings.load_settings()
	check_eq([Settings.display_mode, Settings.display_chosen], [0, false], "damaged values → 0 / not chosen")
	for v in [7, -1, 5]:
		check_eq(Settings.clean_display_mode(v), 0, "out of range %d → 0" % v)
	check_eq(Settings.clean_display_mode(1.0), 1, "float 1.0 → 1")
	Settings.set_display_mode(9)
	check_eq(Settings.display_mode, 0, "set_display_mode clamps invalid values to the classic mode")
	_end()


# --- Logical sizes, render configuration -----------------------------------------------------------
func test_logical_sizes_offsets_and_names() -> void:
	_begin()
	check_eq(Display.MODE_NAMES[0], "WINDOW 4:3 (CLASSIC)")
	check_eq(Display.MODE_NAMES[1], "FULLSCREEN 1920×1080 (16:9)")
	check_eq(Display.MODE_NAMES[2], "FULLSCREEN 2560×1440 (16:9)")
	var expect := {0: [Vector2i(960, 720), 0.0, false], 1: [Vector2i(1280, 720), 160.0, true],
		2: [Vector2i(1280, 720), 160.0, true]}
	for m in 3:
		_mode(m)
		check_eq(Display.mode(), m, "mode %d" % m)
		check_eq(Display.logical_size(), expect[m][0], "logical size of mode %d" % m)
		check_eq(Display.logical_width(), float(expect[m][0].x), "logical width of mode %d" % m)
		check_eq(Display.center_offset(), expect[m][1], "centre offset of mode %d" % m)
		check_eq(Display.is_wide(), expect[m][2], "is_wide of mode %d" % m)
		check_eq(Display.logical_size_of(m), expect[m][0], "logical_size_of(%d)" % m)
	# --display forces a mode for this run without storing it.
	_mode(0)
	Display.forced_mode = 2
	check_eq(Display.mode(), 2, "forced mode wins")
	check_eq(Settings.display_mode, 0, "nothing stored")
	check(not FileAccess.file_exists(SCRATCH_CFG), "no settings written by forcing")
	Display.forced_mode = -1
	_end()


## What a screenshot is: in 16:9 the root viewport is exactly the render size (content_scale_mode VIEWPORT renders
## the root at content_scale_size whatever the window is) and the logical canvas maps onto it exactly; mode 0 is
## the original canvas_items setup of project.godot (screenshot = the window).
func test_render_configuration() -> void:
	_begin()
	var root := (Engine.get_main_loop() as SceneTree).root
	var renders := {1: Vector2i(1920, 1080), 2: Vector2i(2560, 1440)}
	for m in [1, 2]:
		_mode(m)
		check_eq(Display.render_size(), renders[m], "render size of mode %d" % m)
		check_eq(root.content_scale_mode, Window.CONTENT_SCALE_MODE_VIEWPORT, "mode %d: root renders at a fixed size" % m)
		check_eq(root.content_scale_size, renders[m], "mode %d: root viewport = render size" % m)
		check_eq(root.content_scale_aspect, Window.CONTENT_SCALE_ASPECT_KEEP, "mode %d: aspect keep (letterbox)" % m)
		check_eq(Vector2i(root.get_visible_rect().size), renders[m], "mode %d: viewport (screenshot) size" % m)
		var k := root.global_canvas_transform.get_scale()
		check_eq(Vector2i((Vector2(Display.logical_size()) * k).round()), renders[m],
			"mode %d: logical 1280×720 × canvas scale = render size" % m)
		check_near(k.x, float(renders[m].x) / 1280.0, 1e-6, "mode %d: scale" % m)
		check_near(root.oversampling_override, k.x, 1e-6, "mode %d: fonts rasterised at the render scale" % m)
		check_eq(root.global_canvas_transform.origin, Vector2.ZERO, "mode %d: no offset" % m)
	_mode(0)
	check_eq(root.content_scale_mode, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "mode 0: canvas_items")
	check_eq(root.content_scale_size, Vector2i(960, 720), "mode 0: logical 960×720")
	check_eq(root.content_scale_aspect, Window.CONTENT_SCALE_ASPECT_KEEP, "mode 0: aspect keep")
	check_eq(root.global_canvas_transform, Transform2D.IDENTITY, "mode 0: no canvas transform")
	check_eq(root.oversampling_override, 0.0, "mode 0: automatic oversampling")
	# project.godot still describes exactly mode 0 (the window the game opens with).
	check_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 960, "project width")
	check_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 720, "project height")
	check_eq(int(ProjectSettings.get_setting("display/window/size/window_width_override")), 1280, "window width")
	check_eq(int(ProjectSettings.get_setting("display/window/size/window_height_override")), 960, "window height")
	check_eq(String(ProjectSettings.get_setting("display/window/stretch/mode")), "canvas_items", "stretch mode")
	check_eq(String(ProjectSettings.get_setting("display/window/stretch/aspect")), "keep", "stretch aspect")
	check_eq(Display.render_size(), Vector2i(1280, 960), "mode 0: default window")
	# Switching back and forth leaves no trace of the other mode.
	for m in [2, 0, 1, 0]:
		_mode(m)
	check_eq(Display.canvas_config(0)["global_canvas_transform"], root.global_canvas_transform, "back to mode 0")
	check_eq(root.content_scale_size, Vector2i(960, 720), "back to mode 0 canvas")
	_end()


func test_f11_window_sizes() -> void:
	# The largest of 1920×1080 / 1600×900 / 1280×720 that fits the usable screen (with room for a title bar).
	var cases := [
		[Vector2i(2560, 1400), Vector2i(1920, 1080)],
		[Vector2i(3840, 2100), Vector2i(1920, 1080)],
		[Vector2i(1920, 1040), Vector2i(1600, 900)],
		[Vector2i(1920, 1080), Vector2i(1600, 900)],
		[Vector2i(1680, 1010), Vector2i(1600, 900)],
		[Vector2i(1600, 860), Vector2i(1280, 720)],
		[Vector2i(1366, 728), Vector2i(1223, 687)],
	]
	for c in cases:
		var s: Vector2i = Display.wide_window_size(c[0])
		check_eq(s, c[1], "16:9 window on %s" % c[0])
		check(s.x <= c[0].x and s.y + Display.DECORATION_ALLOWANCE <= c[0].y, "fits %s" % c[0])
		check(absf(float(s.x) / s.y - 16.0 / 9.0) < 0.01, "16:9 (%s)" % s)
	check_eq(Display.classic_window_size(Vector2i(1920, 1040)), Vector2i(1280, 960), "classic window")
	check_eq(Display.classic_window_size(Vector2i(1366, 728)), Vector2i(917, 687), "classic window on a small screen")


## F11: mode 0 toggles the persisted fullscreen option as before; 16:9 modes toggle fullscreen ↔ 16:9 window for
## the session only (the option of mode 0 is untouched).
func test_f11_toggle_per_mode() -> void:
	_begin()
	_mode(0)
	Settings.fullscreen = false
	Display.toggle_fullscreen()
	check(Settings.fullscreen, "mode 0: F11 → fullscreen")
	check_eq(_stored("video", "fullscreen"), true, "mode 0: persisted")
	Display.toggle_fullscreen()
	check(not Settings.fullscreen, "mode 0: F11 again → window")
	_mode(1)
	Display.wide_windowed = false
	Display.toggle_fullscreen()
	check(Display.wide_windowed, "16:9: F11 → 16:9 window")
	check(not Settings.fullscreen, "16:9: the mode 0 option is untouched")
	Display.toggle_fullscreen()
	check(not Display.wide_windowed, "16:9: F11 again → fullscreen")
	# The InputRouter routes F11 there.
	_router_init()
	_key(KEY_F11, true)
	_router_step()
	_key(KEY_F11, false)
	_router_step()
	check(Display.wide_windowed, "F11 key → Display.toggle_fullscreen")
	_end()


# --- First start ---------------------------------------------------------------------------------
func test_first_start_flow_decisions() -> void:
	check_eq(RunFlow.first_screen(false, false, false), "display_select", "not chosen → first-start screen")
	check_eq(RunFlow.first_screen(true, false, false), "title", "chosen → title")
	check_eq(RunFlow.first_screen(false, true, false), "title", "--display forces a mode: no first-start screen")
	check_eq(RunFlow.first_screen(true, false, true), "display_select", "--first-start forces it")
	check_eq(RunFlow.first_screen(true, true, true), "display_select", "--first-start wins over --display")
	check_eq(RunFlow.next("display_select", "confirm", 0)["screen"], "title", "confirm → title")
	check_eq(RunFlow.next("display_select", "quit", 0)["screen"], "quit", "Escape → quit")
	check_eq(RunFlow.next("title", "display", 0)["screen"], "title", "DISPLAY applied → title again")
	check(RunFlow.SCREENS.has("display_select"), "dev --screen=display_select")


func test_first_start_screen_confirm_applies_and_stores() -> void:
	_begin()
	_mode(0)
	Settings.display_chosen = false
	_router_init()
	var s := SpySelect.new()
	s.setup({})
	s._ready()
	_run(s, 0.1)
	check_eq(s.selected(), 0, "starts on the current (classic) mode")
	_tap(s, KEY_DOWN)
	check_eq(s.selected(), 1, "down → 1080")
	for k in Display.MODE_COUNT - 1:
		_tap(s, KEY_DOWN)
	check_eq(s.selected(), 0, "wraps")
	_tap(s, KEY_UP)
	check_eq(s.selected(), 4, "up wraps to the last mode (1280×720)")
	_tap(s, KEY_LEFT)
	_tap(s, KEY_LEFT)
	_tap(s, KEY_LEFT)
	check_eq(s.selected(), 1, "left/right select too")
	check(s.results.is_empty(), "moving never confirms")
	check_eq(Display.mode(), 0, "nothing applied while choosing (no live preview)")
	_tap(s, KEY_ENTER)
	check_eq(s.results, ["confirm"] as Array[String], "Enter confirms")
	check_eq(Display.mode(), 1, "mode applied")
	check_eq([Settings.display_mode, Settings.display_chosen], [1, true], "stored + chosen")
	check_eq([_stored("video", "display_mode"), _stored("video", "display_chosen")], [1, true], "on disk")
	var root := (Engine.get_main_loop() as SceneTree).root
	check_eq(root.content_scale_size, Vector2i(1920, 1080), "render size switched at once")
	s.free()
	_end()


func test_first_start_screen_escape_quits_and_guards() -> void:
	_begin()
	_mode(0)
	Settings.display_chosen = false
	_router_init()
	# Release guard: Enter still held from before the screen opened (Main calls require_release) does nothing.
	_key(KEY_ENTER, true)
	_router_step()
	InputRouter.require_release()
	var s := SpySelect.new()
	s.setup({"select": 2})
	s._ready()
	_run(s, 0.3)
	check(s.results.is_empty(), "held Enter does not confirm")
	_key(KEY_ENTER, false)
	_run(s, STEP * 2)
	check(s.results.is_empty(), "releasing does not confirm either")
	# Space confirms like on the title, but only on a fresh press; here Escape quits instead.
	_tap(s, KEY_ESCAPE)
	check_eq(s.results, ["quit"] as Array[String], "Escape quits the game (like on the title)")
	check_eq([Settings.display_mode, Settings.display_chosen], [0, false], "nothing stored: offered again next time")
	check(not FileAccess.file_exists(SCRATCH_CFG), "no settings written")
	s.free()
	# Space / controller-style confirm keys work as on the title.
	var s2 := SpySelect.new()
	s2.setup({"select": 0})
	s2._ready()
	_run(s2, 0.1)
	_tap(s2, KEY_SPACE)
	check_eq(s2.results, ["confirm"] as Array[String], "Space confirms")
	check_eq([Settings.display_mode, Settings.display_chosen], [0, true], "classic chosen and stored")
	s2.free()
	_end()


func test_first_start_screen_layout_fits_both_canvases() -> void:
	_fonts()
	for m in [0, 1]:
		_begin()
		_mode(m)
		var s := SpySelect.new()
		s.setup({})
		s._ready()
		var ox := Display.center_offset()
		check_eq(s.position.x, ox, "mode %d: content centred" % m)
		for i in 3:
			var r := DisplaySelect.card_rect(i)
			check(r.position.x - 30.0 >= -ox and r.end.x + 30.0 <= ScreenBase.W + ox, "card %d inside the canvas" % i)
			var name_w := UiKit.text_width(Assets.font_title, Display.mode_name(i), DisplaySelect.NAME_SIZE)
			check(DisplaySelect.TEXT_X + name_w + 16.0 < r.size.x, "mode %d name fits its card" % i)
			var info_w := UiKit.text_width(Assets.font_body, String(Display.MODE_INFO[i]), DisplaySelect.INFO_SIZE)
			check(DisplaySelect.TEXT_X + info_w + 16.0 < r.size.x, "mode %d explanation fits its card" % i)
		check(DisplaySelect.card_rect(2).end.y + 20.0 < DisplaySelect.FOOTNOTE_Y - 15.0, "cards above the footnote")
		s.free()
		_end()


# --- Title DISPLAY item ----------------------------------------------------------------------------
func _title(select: String) -> SpyTitle:
	var t := SpyTitle.new()
	t.setup({"select": select})
	t._ready()
	_run(t, 0.1)
	return t


func test_title_display_item_pending_and_apply() -> void:
	_begin()
	_mode(0)
	_router_init()
	check_eq(TitleScreen.ITEMS.find("display"), TitleScreen.ITEMS.find("highscores") - 1, "DISPLAY above HIGHSCORES")
	check_eq(TitleScreen.LABELS["display"], "DISPLAY")
	var t := _title("display")
	check_eq(t._value("display"), Display.MODE_NAMES[0], "shows the current mode")
	check(not t.display_is_pending(), "nothing pending")
	_tap(t, KEY_RIGHT)
	check_eq(t._value("display"), Display.MODE_NAMES[1], "right → 1920×1080")
	check(t.display_is_pending(), "pending")
	check(t.display_line_text(true).begins_with("Press ENTER to apply"), "apply prompt")
	check_eq([Display.mode(), Settings.display_mode], [0, 0], "not applied yet")
	check(not FileAccess.file_exists(SCRATCH_CFG), "not stored yet")
	_tap(t, KEY_RIGHT)
	check_eq(t._value("display"), Display.MODE_NAMES[2], "right → 2560×1440")
	_tap(t, KEY_RIGHT)
	check_eq(t._value("display"), "FULLSCREEN 1280×800 (16:10)", "right → 1280×800 (Steam Deck)")
	_tap(t, KEY_RIGHT)
	check_eq(t._value("display"), Display.MODE_NAMES[4], "right → 1280×720")
	_tap(t, KEY_RIGHT)
	check_eq(t._value("display"), Display.MODE_NAMES[0], "wraps")
	_tap(t, KEY_LEFT)
	check_eq(t.display_pending, 4, "left steps back")
	# Leaving the row drops the unapplied choice.
	_tap(t, KEY_DOWN)
	_tap(t, KEY_UP)
	check(not t.display_is_pending(), "leaving the row resets the pending choice")
	check(t.results.is_empty(), "no finish yet")
	# Confirm without a pending choice steps it (like the other value rows), a second confirm applies.
	_tap(t, KEY_ENTER)
	check(t.display_is_pending() and t.results.is_empty(), "first Enter only picks the next mode")
	check_eq(t.display_pending, 1, "next mode")
	_tap(t, KEY_ENTER)
	check_eq(t.results, ["display"] as Array[String], "second Enter applies → finished(display)")
	check_eq([Display.mode(), Settings.display_mode, Settings.display_chosen], [1, 1, true], "applied + stored")
	check_eq(_stored("video", "display_mode"), 1, "on disk")
	check_eq(Display.logical_width(), 1280.0, "16:9 canvas")
	t.free()
	# Escape still quits on the DISPLAY row, even with a pending choice (nothing applied).
	var t2 := _title("display")
	_tap(t2, KEY_RIGHT)
	_tap(t2, KEY_ESCAPE)
	check_eq(t2.results, ["quit"] as Array[String], "Escape quits")
	check_eq(Display.mode(), 1, "the pending choice was not applied")
	t2.free()
	# A forced --display mode ends when the player applies a choice on the title.
	Display.forced_mode = 2
	var t3 := _title("display")
	check_eq(t3.display_pending, 2, "starts on the forced mode")
	_tap(t3, KEY_LEFT)
	_tap(t3, KEY_ENTER)
	check_eq([Display.forced_mode, Display.mode(), Settings.display_mode], [-1, 1, 1], "choice replaces --display")
	t3.free()
	_end()


func test_title_layout_fits_both_canvases() -> void:
	_fonts()
	var font := Assets.font_title
	var panel := TitleScreen.menu_panel_rect()
	check(panel.end.y + 10.0 < TitleScreen.INFO_LINE_Y - 16.0, "DISPLAY line below the menu panel")
	check(TitleScreen.INFO_LINE_Y + 6.0 < TitleScreen.HINT_Y - 14 * 1.55 * 0.5, "DISPLAY line above the hints")
	# The longest DISPLAY value fits its row next to the label, with the value pointers (selected row).
	var c := Vector2(TitleScreen.CX, 300.0)
	var row := UiKit.menu_row_rect(c, TitleScreen.MENU_W, TitleScreen.MENU_FONT)
	var label_end := row.position.x + 30.0 + UiKit.text_width(font, TitleScreen.LABELS["display"], TitleScreen.MENU_FONT)
	for m in 3:
		var vw := UiKit.text_width(font, Display.mode_name(m), TitleScreen.MENU_FONT)
		var pointer_left := row.end.x - 30.0 - 18.0 - vw - 14.0 - 6.0
		check(label_end + 12.0 < pointer_left, "%s fits the DISPLAY row (label to %.0f, pointer %.0f)" % [
			Display.mode_name(m), label_end, pointer_left])
	for m in [0, 1, 2]:
		_begin()
		_mode(m)
		var t := _title("display")
		var ox := Display.center_offset()
		check_eq(t.position.x, ox, "mode %d: title centred" % m)
		check_eq(t.starfield.size, Vector2(Display.logical_size()), "mode %d: sky spans the canvas" % m)
		check_eq(t.starfield.position.x, -ox, "mode %d: sky from the canvas edge" % m)
		check(panel.position.x - 30.0 > -ox and panel.end.x + 30.0 < ScreenBase.W + ox, "panel inside the canvas")
		var pw := UiKit.text_width(Assets.font_body_bold, t.display_line_text(false), 16)
		check(pw < ScreenBase.W - 40.0, "DISPLAY line fits")
		# The BEST line ends at the right edge of the canvas; the demons stay on the canvas, clear of the panel.
		check_eq(TitleScreen.BEST_X + t.ox, t.right_x() - 26.0, "mode %d: BEST at the canvas edge" % m)
		for d: Dictionary in t.get("_demons"):
			check(float(d["min"]) >= t.left_x() + 40.0 and float(d["max"]) <= t.right_x() - 40.0,
				"mode %d: demon band on the canvas" % m)
			check(float(d["max"]) < panel.position.x - 25.0 or float(d["min"]) > panel.end.x + 25.0,
				"mode %d: demon band clear of the panel" % m)
		t.free()
		_end()


# --- Starfield, screens on the 16:9 canvas ---------------------------------------------------------
func test_starfield_size_follows_the_mode() -> void:
	_begin()
	for m in [0, 1]:
		_mode(m)
		var sf := Starfield.new()
		check_eq(sf.size, Vector2(Display.logical_size()), "mode %d: default size = logical canvas" % m)
		check_eq(sf.tex_size(), Display.logical_size(), "mode %d: texture size" % m)
		sf._ready()
		var layers: Array = sf.get("_data")["layers"]
		check_eq(Vector2i((layers[0] as Texture2D).get_size()), Display.logical_size(), "mode %d: layer textures" % m)
		var key: String = sf.get("_key")
		check(key.ends_with("%dx%d" % [Display.logical_size().x, Display.logical_size().y]), "cache per size: %s" % key)
		sf.free()
	_end()


func test_screens_use_the_full_wide_canvas() -> void:
	_fonts()
	_begin()
	_mode(1)
	Run.start_new(1, 0, 5)
	Run.last_level_result = {"level": 5, "completion_bonus": 250, "extra_life": false, "flawless": true}
	# Ship select: the difficulty caption sits in the canvas corner, the tiles are centred.
	var ss := ShipSelect.new()
	ss.setup({"ship": 0})
	ss._ready()
	check_eq(ss.right_x(), 1120.0, "right edge in content coordinates")
	check_eq(ss.left_x(), -160.0, "left edge in content coordinates")
	var t0 := ShipSelect.tile_rect(0)
	var t2 := ShipSelect.tile_rect(2)
	check_near(t0.position.x + ss.ox, 1280.0 - (t2.end.x + ss.ox), 0.01, "tiles centred on 1280")
	ss.free()
	# Interlevel: the planet stays in the lower right corner (same distance from the edge as in 4:3).
	var il := Interlevel.new()
	il.setup({"level": 5})
	il._ready()
	check_eq(il.full_rect(), Rect2(-160, 0, 1280, 720), "darkening overlay spans the canvas")
	il.free()
	# Arrival: the message leaves the 1280 canvas completely to the left by 7 s; the planet zooms at the centre.
	var font := Assets.font_title_heavy
	for n: int in LevelData.ARRIVAL_AFTER:
		var text: String = LevelData.ARRIVAL_AFTER[n]["text"]
		var w := UiKit.text_width(font, text, UiKit.fit_size(font, text, 30, 900.0))
		var right_end := ScreenBase.CX + Arrival.message_offset(Arrival.T_PLANET - 0.001) + w * 0.5
		check(right_end < -Display.center_offset(), "after %d: message off the 16:9 canvas (%.0f)" % [n, right_end])
	_end()


## Controller: the stick selects, B is ignored (like on the title), A confirms; on the title stick right picks a
## pending mode and A applies it.
func test_controller_on_first_start_and_title() -> void:
	_begin()
	_mode(0)
	Settings.display_chosen = false
	_swap_in()
	var s := SpySelect.new()
	s.setup({})
	s._ready()
	_run(s, 0.1)
	# (The D-pad shares the arrow keys' path in InputRouter._raw_dir; it cannot be faked headless.)
	_stick_tap(s, Vector2(0.0, 0.9))
	check_eq(s.selected(), 1, "stick down")
	_stick_tap(s, Vector2(0.0, 0.9))
	check_eq(s.selected(), 2, "stick down again")
	_stick_tap(s, Vector2(0.0, -0.9))
	check_eq(s.selected(), 1, "stick up")
	_pad_tap(s, JOY_BUTTON_B)
	check(s.results.is_empty(), "B is ignored")
	_pad_tap(s, JOY_BUTTON_A)
	check_eq(s.results, ["confirm"] as Array[String], "A confirms")
	check_eq([Display.mode(), Settings.display_chosen], [1, true], "1080 chosen")
	s.free()
	for button in [JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START]:
		var s2 := SpySelect.new()
		s2.setup({"select": 0})
		s2._ready()
		_run(s2, 0.1)
		_pad_tap(s2, button)
		check_eq(s2.results, ["confirm"] as Array[String], "button %d confirms" % button)
		s2.free()
	check_eq(Display.mode(), 0, "classic chosen by the last one")
	var t := SpyTitle.new()
	t.setup({"select": "display"})
	t._ready()
	_run(t, 0.1)
	_stick_tap(t, Vector2(0.9, 0.0))
	_stick_tap(t, Vector2(0.9, 0.0))
	check_eq(t.display_pending, 2, "stick right twice → 1440 pending")
	check(t.results.is_empty(), "not applied by moving")
	_pad_tap(t, JOY_BUTTON_A)
	check_eq(t.results, ["display"] as Array[String], "A applies")
	check_eq([Display.mode(), Settings.display_mode], [2, 2], "1440 applied and stored")
	t.free()
	_swap_out()
	_end()


# --- Review round: damaged values, mouse pointer, monitor hints, victory Earth ------------------------
## SPEC §11.2: display_mode is 0–4 (Steam Deck round; was 0–2), anything else reads as 0 – also fractions (1.5 must not start a 16:9 mode),
## NaN / infinities, strings and booleans.
func test_damaged_display_mode_values_read_as_classic() -> void:
	for v: Variant in [1.5, 2.9, 1.0001, 0.5, -0.5, NAN, INF, -INF, 5.0, -1.0, "1", true, null, [1], Vector2i(1, 1)]:
		check_eq(Settings.clean_display_mode(v), 0, "display_mode=%s → classic" % str(v))
	for m in 3:
		check_eq(Settings.clean_display_mode(m), m, "int %d" % m)
		check_eq(Settings.clean_display_mode(float(m)), m, "whole float %d.0" % m)
	check_eq(Settings.clean_display_mode(-0.0), 0, "-0.0 → 0")


## The game has no mouse control: the pointer is hidden in fullscreen (the 16:9 modes start fullscreen) and visible
## in a window. Headless nothing is touched.
func test_pointer_hidden_while_fullscreen() -> void:
	check_eq(Display.pointer_mode(true), Input.MOUSE_MODE_HIDDEN, "fullscreen → hidden")
	check_eq(Display.pointer_mode(false), Input.MOUSE_MODE_VISIBLE, "window → visible")
	var before := Input.mouse_mode
	Display.update_pointer()
	Display.apply_window()
	check_eq(Input.mouse_mode, before, "headless: pointer untouched")


## Which 16:9 option suits a monitor (Godot cannot change the monitor's resolution; the 16:9 picture is scaled).
func test_monitor_hint_decisions() -> void:
	var cases := [
		[Vector2i.ZERO, -1, false],
		[Vector2i(1920, 1080), 1, false], [Vector2i(1920, 1200), 1, true], [Vector2i(1366, 768), 1, false],
		[Vector2i(1280, 800), 1, true], [Vector2i(2560, 1080), 1, true], [Vector2i(2560, 1440), 2, false],
		[Vector2i(2560, 1600), 2, true], [Vector2i(3440, 1440), 2, true], [Vector2i(3840, 2160), 2, false],
		[Vector2i(1600, 1200), 1, true],
	]
	for c: Array in cases:
		check_eq(Display.best_wide_mode(c[0]), c[1], "best 16:9 mode for %s" % str(c[0]))
		check_eq(Display.letterboxed_on(c[0]), c[2], "black bars on %s" % str(c[0]))
	check_eq(Display.fit_note(0, Vector2i(1920, 1080)), "", "classic: no note")
	check_eq(Display.fit_note(1, Vector2i.ZERO), "", "unknown monitor: no note")
	check_eq(Display.fit_note(1, Vector2i(1920, 1200)), "best fit for your 1920×1200 screen")
	check_eq(Display.fit_note(2, Vector2i(1920, 1080)), "scaled down to your 1920×1080 screen")
	check_eq(Display.fit_note(1, Vector2i(2560, 1440)), "scaled up to your 2560×1440 screen")
	check_eq(Display.fit_note(2, Vector2i(2560, 1440)), "best fit for your 2560×1440 screen")
	check_eq(Display.fit_note(1, Vector2i(3840, 2160)), "scaled up to your 3840×2160 screen")
	check_eq(Display.fit_note(1, Vector2i(1366, 768)), "best fit for your 1366×768 screen")
	check_eq(Display.screen_size(), Vector2i.ZERO, "headless: monitor unknown")


## First-start screen: "Your screen: W×H" under the cards and the BEST FIT badge on the matching 16:9 card; the
## classic window stays preselected. Nothing of it with an unknown monitor. Fits both canvases.
func test_first_start_screen_monitor_hint() -> void:
	_fonts()
	var saved_override := Display.screen_override
	for m in [0, 1]:
		_begin()
		_mode(m)
		var ox := Display.center_offset()
		Display.screen_override = Vector2i.ZERO
		var s0 := SpySelect.new()
		s0.setup({})
		s0._ready()
		check_eq(s0.best_mode(), -1, "unknown monitor: no badge")
		s0.free()
		for c: Array in [[Vector2i(1920, 1080), 1], [Vector2i(1920, 1200), 1], [Vector2i(2560, 1440), 2]]:
			Display.screen_override = c[0]
			var s := SpySelect.new()
			s.setup({})
			s._ready()
			check_eq(s.best_mode(), c[1], "mode %d: badge on the card that suits %s" % [m, str(c[0])])
			check_eq(s.selected(), m, "the current mode stays preselected")
			s.free()
		var long_line := DisplaySelect.screen_line(Vector2i(2560, 1600))
		# Steam Deck review round: the line also names the 16:10 mode (bars on 16:9, fills a 16:10 screen).
		check_eq(long_line, "Your screen: 2560×1600  ·  16:10, so the 16:9 modes get black bars, the 16:10 mode fills it")
		check_eq(DisplaySelect.screen_line(Vector2i(1920, 1080)),
			"Your screen: 1920×1080  ·  16:9, so the 16:10 mode gets black bars at the sides")
		check_eq(DisplaySelect.screen_line(Vector2i.ZERO), "")
		var lw := UiKit.text_width(Assets.font_body, long_line, 15)
		check(ScreenBase.CX - lw * 0.5 > -ox + 20.0 and lw < ScreenBase.W - 60.0, "mode %d: screen line fits" % m)
		check(DisplaySelect.card_rect(2).end.y + 22.0 < DisplaySelect.SCREEN_Y - 12.0, "screen line below the cards")
		check(DisplaySelect.SCREEN_Y + 12.0 < DisplaySelect.FOOTNOTE_Y - 12.0, "screen line above the footnote")
		check(DisplaySelect.FOOTNOTE_Y + 8.0 < DisplaySelect.HINT_Y - 14 * 2.45 * 0.5, "footnote above the hints")
		for i in [1, 2]:
			var card := DisplaySelect.card_rect(i)
			var b := DisplaySelect.badge_rect(card)
			var name_end := card.position.x + DisplaySelect.TEXT_X + UiKit.text_width(Assets.font_title,
				Display.mode_name(i), DisplaySelect.NAME_SIZE)
			check(b.end.x < card.end.x - 10.0 and b.position.x > name_end - 200.0, "badge %d at the right of the card" % i)
			check(b.end.y < card.position.y + 42.0 - 18.0, "badge %d clear of the mode name" % i)
			check(b.position.y > DisplaySelect.card_rect(i - 1).end.y, "badge %d clear of the card above" % i)
		_end()
	Display.screen_override = saved_override


## Title DISPLAY line: for the 16:9 modes it says how the picture fits the monitor, also while a choice is pending.
func test_title_display_line_monitor_note() -> void:
	_fonts()
	var saved_override := Display.screen_override
	_begin()
	_mode(0)
	_router_init()
	Display.screen_override = Vector2i(1920, 1080)
	var t := _title("display")
	check_eq(t.display_line_text(false), String(Display.MODE_INFO[0]), "classic: plain explanation")
	_tap(t, KEY_RIGHT)
	check_eq(t.display_line_text(true), "Press ENTER to apply  ·  Wider 16:9 playfield  ·  best fit for your 1920×1080 screen")
	_tap(t, KEY_RIGHT)
	check_eq(t.display_line_text(true),
		"Press ENTER to apply  ·  Wider 16:9 playfield  ·  scaled down to your 1920×1080 screen")
	var w := UiKit.text_width(Assets.font_body_bold, t.display_line_text(true), 16)
	check(w < ScreenBase.W - 80.0, "pending line with the note fits the 960 canvas (%.0f px)" % w)
	t.free()
	Display.screen_override = Vector2i.ZERO
	var t2 := _title("display")
	_tap(t2, KEY_RIGHT)
	check_eq(t2.display_line_text(true), "Press ENTER to apply  ·  %s" % String(Display.MODE_INFO[1]),
		"unknown monitor: the full explanation")
	t2.free()
	Display.screen_override = Vector2i(2560, 1440)
	_mode(2)
	var t3 := _title("display")
	check_eq(t3.display_line_text(false), "Wider 16:9 playfield  ·  best fit for your 2560×1440 screen")
	t3.free()
	Display.screen_override = saved_override
	_end()


## Victory: the Earth comes from its 1280 px render and is drawn with linear filtering + mipmaps (the project's
## nearest default showed its texels as blocks when scaled up).
func test_victory_earth_is_smooth_and_high_resolution() -> void:
	_fonts()
	check_eq(Victory.earth_asset(), "earth_hd", "the high-resolution Earth ships")
	var hd: Dictionary = Assets.planet_info("earth_hd")
	check_eq(float(hd["sphere_diameter_px"]), 1280.0, "sphere 1280 px")
	var lo: Dictionary = Assets.planet_info("earth")
	check((hd["center"] as Vector2).distance_to((lo["center"] as Vector2) * 2.0) < 12.0,
		"same framing as the in-game sprite at twice the size")
	for m in [0, 2]:
		_begin()
		_mode(m)
		var v: Node2D = Victory.new()
		v.setup({"level": LevelData.LAST_LEVEL, "qualifies": false})
		v._ready()
		check_eq(v.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "mode %d: smooth filtering" % m)
		check_eq(v.get("_earth"), "earth_hd", "mode %d: draws the HD Earth" % m)
		v.free()
		_end()
	AudioManager.stop_music()
