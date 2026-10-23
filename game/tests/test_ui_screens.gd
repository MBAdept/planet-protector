extends TestBase
## Screen behaviour of the ui package: silent arrival hand-over (SPEC §11/§14), title ON/OFF toggles
## vs. the menu auto-repeat (§12), and text staying clear of / backed over planet art (§15).
## Like test_ui_review.gd these run before the SceneTree is live: screens are driven by hand and the
## InputRouter is stepped manually; every key that is pressed is released again.

const InterlevelScreen := preload("res://scripts/screens/interlevel_screen.gd")
const ArrivalScreen := preload("res://scripts/screens/arrival_screen.gd")
const TitleScreen := preload("res://scripts/screens/title_screen.gd")

const STEP := 1.0 / 60.0


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


# --- §12 menu repeat: fresh step vs. auto-repeat --------------------------------------------------
func test_router_flags_autorepeat_steps() -> void:
	_router_init()
	_key(KEY_RIGHT, true)
	_router_step()
	check_eq(InputRouter.menu_direction(), Vector2i(1, 0), "fresh press steps immediately")
	check(not InputRouter.menu_direction_is_repeat(), "the first step of a press is not a repeat")
	var steps := 0
	var repeats := 0
	var t := 0.0
	while t < 1.0:
		_router_step()
		t += STEP
		if InputRouter.menu_direction() != Vector2i.ZERO:
			steps += 1
			if InputRouter.menu_direction_is_repeat():
				repeats += 1
		else:
			check(not InputRouter.menu_direction_is_repeat(), "no repeat flag without a step")
	check(steps >= 5, "holding repeats (0.35 s delay, 0.11 s interval), got %d steps" % steps)
	check_eq(repeats, steps, "every later step of the held direction is flagged as repeat")
	InputRouter.require_release()
	check(not InputRouter.menu_direction_is_repeat(), "require_release clears the repeat flag")
	_key(KEY_RIGHT, false)
	_router_step()
	_router_step()
	_key(KEY_RIGHT, true)
	_router_step()
	check_eq(InputRouter.menu_direction(), Vector2i(1, 0), "new press after release steps again")
	check(not InputRouter.menu_direction_is_repeat(), "and is a fresh step")
	_key(KEY_RIGHT, false)
	_router_step()
	_router_step()


func test_title_toggles_flip_once_difficulty_repeats() -> void:
	for item in ["music", "sfx"]:
		check(TitleScreen.accepts_step(item, false), "%s reacts to a fresh step" % item)
		check(not TitleScreen.accepts_step(item, true), "%s ignores auto-repeat steps" % item)
	check(TitleScreen.accepts_step("difficulty", false), "difficulty reacts to a fresh step")
	check(TitleScreen.accepts_step("difficulty", true), "difficulty keeps cycling with the repeat")


# --- §11/§14 arrival is completely silent ---------------------------------------------------------
func test_interlevel_confirm_is_silent_only_before_an_arrival() -> void:
	for n in range(1, LevelData.LAST_LEVEL + 1):
		if n == LevelData.BONUS_LEVEL:
			continue
		var want := "" if LevelData.ARRIVAL_AFTER.has(n) else "menu_confirm"
		check_eq(InterlevelScreen.confirm_sound(n), want, "confirm sound of interlevel %d" % n)


func test_arrival_fades_out_mutes_and_restores_sfx_bus() -> void:
	AudioManager.stop_music()   # makes sure the buses exist
	AudioManager.apply_settings()
	var bus := AudioServer.get_bus_index(AudioManager.BUS_SFX)
	check(bus >= 0, "SFX bus exists")
	if bus < 0:
		return
	var db0 := AudioServer.get_bus_volume_db(bus)
	var arrival := ArrivalScreen.new()
	arrival.setup({"level": 6})
	arrival._ready()
	arrival._process(STEP)
	check(AudioServer.get_bus_volume_db(bus) < db0 - 0.5, "effects still ringing are faded out")
	var t := STEP
	while t < 0.2:
		arrival._process(STEP)
		t += STEP
	check(AudioServer.is_bus_mute(bus), "SFX bus muted during the arrival")
	check_near(AudioServer.get_bus_volume_db(bus), db0, 1e-3, "volume restored once muted")
	# Settings.changed (e.g. F11) re-applies the settings: the arrival keeps the bus muted.
	AudioManager.apply_settings()
	arrival._process(STEP)
	check(AudioServer.is_bus_mute(bus), "stays muted after apply_settings during the arrival")
	check_near(ArrivalScreen.sfx_gain(0.0), 1.0, 1e-6, "gain starts at 1")
	check_near(ArrivalScreen.sfx_gain(ArrivalScreen.SFX_FADE), 0.0, 1e-6, "gain 0 after the fade")
	arrival._exit_tree()   # Main removes the screen from the tree on the next screen change
	check_eq(AudioServer.is_bus_mute(bus), not Settings.sfx_on, "SOUND EFFECTS setting applied again on exit")
	check_near(AudioServer.get_bus_volume_db(bus), db0, 1e-3, "volume unchanged after the arrival")
	arrival.free()
	AudioManager.apply_settings()


# --- §15 readability over planet art --------------------------------------------------------------
## Assets._ready (font loading only) has not run yet inside the test runner.
func _fonts() -> void:
	if Assets.font_title == null:
		Assets._ready()


## Distance from a point to the nearest point of a rectangle (0 inside).
func _dist(p: Vector2, r: Rect2) -> float:
	return p.distance_to(Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y)))


func test_interlevel_texts_clear_of_the_planet_sphere() -> void:
	_fonts()
	var radius := InterlevelScreen.PLANET_D * 0.5
	for n in range(1, LevelData.LAST_LEVEL + 1):
		if n == LevelData.BONUS_LEVEL:
			continue
		for rows in [4, 5]:   # 5 = with the extra-life row (levels 10, 15-18)
			var y := InterlevelScreen.progress_baseline(rows)
			var r := UiKit.text_backing_rect(Assets.font_title, Vector2(ScreenBase.CX, y), LevelData.progress_text(n),
				InterlevelScreen.PROGRESS_SIZE, HORIZONTAL_ALIGNMENT_CENTER, Vector2(4, 4))
			var gap := _dist(InterlevelScreen.PLANET_POS, r) - radius
			check(gap >= 12.0, "interlevel %d (%d rows): progress line %.0f px from the planet limb" % [n, rows, gap])
	var hint := UiKit.hint_bar_rect(Vector2(ScreenBase.CX, ScreenBase.CONTINUE_HINT_Y),
		ScreenBase.continue_hint_items(), ScreenBase.CONTINUE_HINT_SIZE)
	check(_dist(InterlevelScreen.PLANET_POS, hint) - radius >= 12.0, "continue hint clear of the planet sphere")


func test_backing_rects_enclose_their_content() -> void:
	_fonts()
	var items := ScreenBase.continue_hint_items("Start level 14")
	var c := Vector2(480, 688)
	var r := UiKit.hint_bar_rect(c, items, 15)
	var w := UiKit.hint_bar_width(items, 15)
	check(r.size.x > w + 20.0, "hint backing wider than the hint row")
	check(r.size.y > 15 * 1.55, "hint backing taller than the glyphs")
	check_near(r.get_center().x, c.x, 0.01, "hint backing centred horizontally")
	check_near(r.get_center().y, c.y, 0.01, "hint backing centred vertically")
	var font := Assets.font_title
	var tr := UiKit.text_backing_rect(font, Vector2(480, 640), ArrivalScreen.PROMPT, 20, HORIZONTAL_ALIGNMENT_CENTER,
		Vector2(26, 12))
	var tw := UiKit.text_width(font, ArrivalScreen.PROMPT, 20)
	check_near(tr.size.x, tw + 52.0, 0.01, "prompt backing = text width + padding")
	check_near(tr.get_center().x, 480.0, 0.01, "prompt backing centred on the text")
	check(tr.position.y < 640.0 - 20 * 0.72 and tr.end.y > 640.0, "prompt backing covers cap height and baseline")
