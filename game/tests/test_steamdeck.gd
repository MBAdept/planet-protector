extends TestBase
## Steam Deck round (client request; docs/SPEC.md §11.2, §12, §18): two more display modes –
## 3 "FULLSCREEN 1280×800 (16:10, STEAM DECK)": logical 1152 × 720 rendered at exactly 1280 × 800 (scale 1.111…),
## 4 "FULLSCREEN 1280×720 (16:9)": logical 1280 × 720 rendered at exactly 1280 × 720 (scale 1.0).
## Covered here: the mode table and render configuration, settings back-compat (0–4 valid, anything else → 0), the
## BEST FIT decisions, F11 window sizes, the playfield rules at W = 1152 (generic W rules of §18.1), bots and demos
## at 1152, GameScreen width, the layout of the first-start screen and the title in every canvas
## (960 / 1152 / 1280 × 720), the small-text minimum of the small modes, and that modes 0 / 1 / 2 are bit-for-bit
## unchanged (W = 960 digests of tests/test_wide_playfield.gd plus W = 1280 digests recorded with the code before
## this change, git d1bd58e).
## Settings go to a scratch file and every display change is undone (mode 0 canvas restored).

const WP := preload("res://tests/test_wide_playfield.gd")
const TitleScreen := preload("res://scripts/screens/title_screen.gd")
const DisplaySelect := preload("res://scripts/screens/display_select_screen.gd")
const ShipSelect := preload("res://scripts/screens/ship_select_screen.gd")
const Victory := preload("res://scripts/screens/victory_screen.gd")
const Backdrop := preload("res://scripts/game/backdrop.gd")
const Autopilot := preload("res://scripts/game/autopilot.gd")
const GameScreenScript := preload("res://scripts/game/game_screen.gd")

const W_DECK := 1152.0
const STEP := 1.0 / 60.0
const SCRATCH_CFG := "user://test_steamdeck_settings.cfg"


## GameScreen without its view update (the view nodes never enter the tree here).
class LogicOnlyScreen extends GameScreenScript:
	func _update_views(_dt: float, _game_dt: float) -> void:
		pass


class QuietTitle extends TitleScreen:
	func sfx(_n: String) -> void:
		pass


class QuietSelect extends DisplaySelect:
	func sfx(_n: String) -> void:
		pass


# --- Helpers -------------------------------------------------------------------------------------
var _saved := {}


func _begin() -> void:
	_saved = {"path": Settings.settings_path, "display_mode": Settings.display_mode,
		"display_chosen": Settings.display_chosen, "fullscreen": Settings.fullscreen, "forced": Display.forced_mode,
		"windowed": Display.wide_windowed, "override": Display.screen_override}
	Settings.settings_path = SCRATCH_CFG
	_remove_scratch()


func _end() -> void:
	_remove_scratch()
	Settings.settings_path = _saved["path"]
	Settings.display_mode = _saved["display_mode"]
	Settings.display_chosen = _saved["display_chosen"]
	Settings.fullscreen = _saved["fullscreen"]
	Display.forced_mode = _saved["forced"]
	Display.wide_windowed = _saved["windowed"]
	Display.screen_override = _saved["override"]
	Display.apply_canvas()


func _remove_scratch() -> void:
	if FileAccess.file_exists(SCRATCH_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_CFG))


func _mode(m: int) -> void:
	Display.forced_mode = -1
	Settings.display_mode = m
	Display.apply_canvas()


func _fonts() -> void:
	if Assets.font_title == null:
		Assets._ready()


func _router() -> void:
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	InputRouter.set_text_mode(false)


## A world in combat with no automatic spawns, no enemy fire and no oscillation.
func _world(level: int, width: float, rng_seed := 7) -> GameWorld:
	var w := GameWorld.new(level, 1, 0, 3, rng_seed, width)
	w.auto_slots = false
	w.osc_amplitude = 0.0
	w.allow_enemy_fire = false
	w.start_combat()
	w.events.clear()
	return w


# --- Mode table, render configuration --------------------------------------------------------------
func test_mode_table() -> void:
	check_eq(Display.MODE_COUNT, 5, "five modes")
	check_eq(Display.Mode.size(), 5, "enum")
	var names := ["WINDOW 4:3 (CLASSIC)", "FULLSCREEN 1920×1080 (16:9)", "FULLSCREEN 2560×1440 (16:9)",
		"FULLSCREEN 1280×800 (16:10, STEAM DECK)", "FULLSCREEN 1280×720 (16:9)"]
	var logical := [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1280, 720), Vector2i(1152, 720),
		Vector2i(1280, 720)]
	var render := [Vector2i(1280, 960), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1280, 800),
		Vector2i(1280, 720)]
	var scale := [1.0, 1.5, 2.0, 1280.0 / 1152.0, 1.0]
	var offset := [0.0, 160.0, 160.0, 96.0, 160.0]
	for m in 5:
		check_eq(Display.mode_name(m), names[m], "name of mode %d" % m)
		check_eq(Display.logical_size_of(m), logical[m], "logical size of mode %d" % m)
		check_eq(Display.RENDER_SIZE[m], render[m], "render size of mode %d" % m)
		check_near(Display.canvas_scale_of(m), scale[m], 1e-9, "canvas scale of mode %d" % m)
		check_eq(Display.is_wide_mode(m), m != 0, "fixed-size (fullscreen) mode %d" % m)
		if m > 0:
			# The logical canvas maps exactly onto the render size, in both directions (no distortion).
			check_eq(Vector2i((Vector2(logical[m]) * scale[m]).round()), render[m], "mode %d: logical × scale = render" % m)
	check_near(800.0 / 720.0, Display.canvas_scale_of(3), 1e-9, "mode 3: vertical scale = horizontal scale")
	# The title row value: the Steam Deck name is shortened (the line under the menu says Steam Deck).
	check_eq(Display.menu_name(3), "FULLSCREEN 1280×800 (16:10)")
	for m in [0, 1, 2, 4]:
		check_eq(Display.menu_name(m), Display.mode_name(m), "menu name of mode %d = its name" % m)
	check(String(Display.MODE_INFO[3]).contains("Steam Deck"), "mode 3 explanation names the Steam Deck")
	check(String(Display.MODE_SHORT[3]).contains("Steam Deck"), "mode 3 short explanation names the Steam Deck")
	# --display=<n>: the Display autoload clamps it to the valid range (0–4).
	check_eq(clampi(4, 0, Display.MODE_COUNT - 1), 4)


func test_render_configuration_of_the_new_modes() -> void:
	_begin()
	var root := (Engine.get_main_loop() as SceneTree).root
	for m in [3, 4]:
		_mode(m)
		var r: Vector2i = Display.RENDER_SIZE[m]
		check_eq(Display.mode(), m)
		check_eq(Display.render_size(), r, "mode %d: render size" % m)
		check_eq(Display.logical_width(), float(Display.logical_size_of(m).x), "mode %d: logical width" % m)
		check_eq(Display.center_offset(), (Display.logical_width() - 960.0) * 0.5, "mode %d: centre offset" % m)
		check_eq(root.content_scale_mode, Window.CONTENT_SCALE_MODE_VIEWPORT, "mode %d: fixed render size" % m)
		check_eq(root.content_scale_size, r, "mode %d: root viewport = render size" % m)
		check_eq(root.content_scale_aspect, Window.CONTENT_SCALE_ASPECT_KEEP, "mode %d: aspect keep" % m)
		check_eq(Vector2i(root.get_visible_rect().size), r, "mode %d: screenshot size" % m)
		var k := root.global_canvas_transform.get_scale()
		check_near(k.x, Display.canvas_scale_of(m), 1e-6, "mode %d: canvas scale x" % m)
		check_near(k.y, Display.canvas_scale_of(m), 1e-6, "mode %d: canvas scale y" % m)
		check_eq(root.global_canvas_transform.origin, Vector2.ZERO, "mode %d: no offset" % m)
		check_near(root.oversampling_override, k.x, 1e-6, "mode %d: fonts rasterised at the render scale" % m)
	check_eq(Display.center_offset(), 160.0, "mode 4: 1280 canvas")
	_mode(3)
	check_eq(Display.center_offset(), 96.0, "mode 3: 1152 canvas")
	# Modes 0–2: exactly the configuration they had before (values as in tests/test_display.gd).
	var cfg0 := Display.canvas_config(0)
	check_eq(cfg0["content_scale_mode"], Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "mode 0 unchanged")
	check_eq(cfg0["content_scale_size"], Vector2i(960, 720), "mode 0 canvas unchanged")
	check_eq(cfg0["global_canvas_transform"], Transform2D.IDENTITY, "mode 0 transform unchanged")
	check_eq(cfg0["oversampling_override"], 0.0, "mode 0 oversampling unchanged")
	for m in [1, 2]:
		var cfg := Display.canvas_config(m)
		var k := 1.5 if m == 1 else 2.0
		check_eq(cfg["content_scale_size"], Vector2i(1920, 1080) if m == 1 else Vector2i(2560, 1440), "mode %d size" % m)
		check_eq(cfg["global_canvas_transform"], Transform2D.IDENTITY.scaled(Vector2(k, k)), "mode %d transform" % m)
		check_eq(cfg["oversampling_override"], k, "mode %d oversampling" % m)
	_end()


# --- Settings ------------------------------------------------------------------------------------
func test_settings_back_compat() -> void:
	for m in 5:
		check_eq(Settings.clean_display_mode(m), m, "int %d valid" % m)
		check_eq(Settings.clean_display_mode(float(m)), m, "whole float %d.0 valid" % m)
	for v: Variant in [5, 6, 99, -1, 5.0, 3.5, 4.0001, NAN, INF, "3", "4", true, null, [3], Vector2i(3, 0)]:
		check_eq(Settings.clean_display_mode(v), 0, "display_mode=%s → classic" % str(v))
	_begin()
	for m in [3, 4]:
		Settings.set_display_mode(m)
		Settings.display_mode = 0
		Settings.load_settings()
		check_eq(Settings.display_mode, m, "mode %d stored and loaded" % m)
	Settings.set_display_mode(5)
	check_eq(Settings.display_mode, 0, "set_display_mode(5) → classic")
	# A file of the previous version (modes 0–2) keeps its meaning.
	for m in 3:
		var cfg := ConfigFile.new()
		cfg.set_value("video", "display_mode", m)
		cfg.set_value("video", "display_chosen", true)
		cfg.save(SCRATCH_CFG)
		Settings.load_settings()
		check_eq([Settings.display_mode, Settings.display_chosen], [m, true], "old file with mode %d" % m)
	var bad := ConfigFile.new()
	bad.set_value("video", "display_mode", 7)
	bad.save(SCRATCH_CFG)
	Settings.load_settings()
	check_eq(Settings.display_mode, 0, "out of range on disk → classic")
	# Display.choose stores the new modes and switches the canvas.
	_mode(0)
	check(Display.choose(3), "choose(3) changes the mode")
	check_eq([Display.mode(), Settings.display_mode, Display.logical_width()], [3, 3, W_DECK], "Steam Deck mode applied")
	check(Display.choose(4), "choose(4)")
	check_eq([Display.mode(), Display.logical_width()], [4, 1280.0], "1280×720 applied")
	Display.choose(9)
	check_eq(Display.mode(), 4, "choose(9) is clamped to the last mode")
	_end()


# --- Monitor hints -------------------------------------------------------------------------------
func test_best_fit_decisions() -> void:
	var cases := [
		[Vector2i(1280, 800), 3], [Vector2i(1280, 720), 4], [Vector2i.ZERO, -1],
		[Vector2i(1920, 1080), 1], [Vector2i(1920, 1200), 1], [Vector2i(1366, 768), 1], [Vector2i(2560, 1440), 2],
		[Vector2i(2560, 1600), 2], [Vector2i(3840, 2160), 2], [Vector2i(1280, 1024), 1], [Vector2i(1440, 900), 1],
		[Vector2i(800, 1280), 1],
	]
	for c: Array in cases:
		check_eq(Display.best_mode(c[0]), c[1], "best mode for %s" % str(c[0]))
	# best_wide_mode keeps its meaning (the 16:9 choice).
	check_eq(Display.best_wide_mode(Vector2i(1280, 800)), 1, "16:9 choice for 1280×800 unchanged")
	check_eq(Display.fit_note(3, Vector2i(1280, 800)), "best fit for your 1280×800 screen")
	check_eq(Display.fit_note(4, Vector2i(1280, 720)), "best fit for your 1280×720 screen")
	check_eq(Display.fit_note(1, Vector2i(1280, 800)), "scaled down to your 1280×800 screen")
	check_eq(Display.fit_note(4, Vector2i(1280, 800)), "scaled up to your 1280×800 screen")
	check_eq(Display.fit_note(3, Vector2i(1920, 1080)), "scaled up to your 1920×1080 screen")
	check_eq(Display.fit_note(1, Vector2i(1920, 1080)), "best fit for your 1920×1080 screen", "1080p unchanged")
	check_eq(Display.fit_note(0, Vector2i(1280, 800)), "", "classic: no note")
	_fonts()
	_begin()
	_mode(0)
	# Review round: on a 1280×800 / 1280×720 screen (best fit = a small mode) the best-fit card is preselected on a
	# first start (the classic 1280×960 window does not fit there); elsewhere, or once a mode was chosen (or with an
	# explicit "select"), the current mode stays preselected.
	for chosen in [false, true]:
		Settings.display_chosen = chosen
		for c: Array in [[Vector2i(1280, 800), 3], [Vector2i(1280, 720), 4], [Vector2i(1920, 1080), 1]]:
			Display.screen_override = c[0]
			var s := QuietSelect.new()
			s.setup({})
			s._ready()
			check_eq(s.best_mode(), c[1], "first start: badge for %s" % str(c[0]))
			var want: int = c[1] if not chosen and c[1] >= 3 else 0
			check_eq(s.selected(), want, "preselected on %s (chosen before: %s)" % [str(c[0]), chosen])
			s.free()
		var s2 := QuietSelect.new()
		s2.setup({"select": 0})
		Display.screen_override = Vector2i(1280, 800)
		s2._ready()
		check_eq(s2.selected(), 0, "an explicit selection wins")
		s2.free()
	Settings.display_chosen = false
	check_eq(DisplaySelect.screen_line(Vector2i(1280, 800)),
		"Your screen: 1280×800  ·  16:10, so the 16:9 modes get black bars, the 16:10 mode fills it")
	check_eq(DisplaySelect.screen_line(Vector2i(1280, 720)),
		"Your screen: 1280×720  ·  16:9, so the 16:10 mode gets black bars at the sides")
	check_eq(DisplaySelect.screen_line(Vector2i(1280, 1024)),
		"Your screen: 1280×1024  ·  not 16:9 or 16:10, so the fullscreen modes get black bars")
	# Title DISPLAY line on the Steam Deck.
	Display.screen_override = Vector2i(1280, 800)
	_mode(3)
	var t := QuietTitle.new()
	t.setup({"select": "display"})
	t._ready()
	check_eq(t.display_line_text(false), "Steam Deck 16:10 playfield  ·  best fit for your 1280×800 screen")
	t.display_pending = 4
	check_eq(t.display_line_text(true), "Press ENTER to apply  ·  Wider 16:9 playfield  ·  scaled up to your 1280×800 screen")
	t.free()
	_end()


# --- F11 -----------------------------------------------------------------------------------------
func test_f11_window_sizes() -> void:
	var cases := [
		# mode, usable screen area, window
		[3, Vector2i(2560, 1400), Vector2i(1280, 800)],
		[3, Vector2i(1920, 1040), Vector2i(1280, 800)],
		[3, Vector2i(1280, 840), Vector2i(1280, 800)],
		[3, Vector2i(1280, 800), Vector2i(1152, 720)],   # Steam Deck desktop without a task bar
		[3, Vector2i(1280, 756), Vector2i(1152, 720)],   # Steam Deck desktop with KDE's 44 px panel (review round)
		[3, Vector2i(1280, 740), Vector2i(1120, 700)],   # even less room: biggest 16:10 that fits
		[4, Vector2i(2560, 1400), Vector2i(1280, 720)],
		[4, Vector2i(1280, 760), Vector2i(1280, 720)],
		[4, Vector2i(1280, 740), Vector2i(1152, 648)],
		[4, Vector2i(1100, 700), Vector2i(1100, 618)],
		[1, Vector2i(2560, 1400), Vector2i(1920, 1080)],
		[2, Vector2i(1920, 1040), Vector2i(1600, 900)],
		[1, Vector2i(1366, 728), Vector2i(1223, 687)],
	]
	for c: Array in cases:
		var s := Display.mode_window_size(c[0], c[1])
		check_eq(s, c[2], "mode %d window on %s" % [c[0], str(c[1])])
		var u: Vector2i = c[1]
		var allow := Display.SMALL_DECORATION_ALLOWANCE if Display.is_small_mode(c[0]) else Display.DECORATION_ALLOWANCE
		check(s.x <= u.x and s.y + allow <= u.y, "fits %s" % str(u))
		var aspect := 1.6 if c[0] == 3 else 16.0 / 9.0
		check(absf(float(s.x) / s.y - aspect) < 0.01, "mode %d window keeps the aspect (%s)" % [c[0], str(s)])
	for u in [Vector2i(2560, 1400), Vector2i(1600, 860), Vector2i(1366, 728)]:
		check_eq(Display.mode_window_size(1, u), Display.wide_window_size(u), "modes 1/2 unchanged on %s" % str(u))
	# F11 in the new modes: fullscreen ↔ window for this session; the classic option is untouched.
	_begin()
	for m in [3, 4]:
		_mode(m)
		Settings.fullscreen = false
		Display.wide_windowed = false
		Display.toggle_fullscreen()
		check(Display.wide_windowed, "mode %d: F11 → window" % m)
		check(not Settings.fullscreen, "mode %d: classic fullscreen option untouched" % m)
		check_eq(Display.render_size(), Display.RENDER_SIZE[m], "mode %d: render size unchanged" % m)
		Display.toggle_fullscreen()
		check(not Display.wide_windowed, "mode %d: F11 again → fullscreen" % m)
	_end()


# --- Playfield at W = 1152 -----------------------------------------------------------------------
func test_limits_at_1152() -> void:
	check_eq(LevelData.player_max_x(W_DECK), 1122.0, "player max x")
	check_eq(LevelData.player_start_x(W_DECK), 576.0, "player start")
	check_eq(LevelData.enemy_max_x(W_DECK), 1102.0, "enemy max x")
	for s in [1.0, 0.45, 0.40]:
		check_eq(GameWorld.min_x(s, W_DECK), 50.0, "enemy min x (scale %.2f)" % s)
		check_eq(GameWorld.max_x(s, W_DECK), 1102.0, "enemy max x (scale %.2f)" % s)
	var w := GameWorld.new(1, 1, 0, 3, 1, W_DECK)
	check_eq(w.width, W_DECK, "world width")
	check_eq(w.player_x, 576.0, "ship starts at W / 2")
	# Planet: same distance to the right edge as at 960.
	for lvl in [1, 10, 20]:
		check_eq(Backdrop.planet_center(lvl, W_DECK).x - Backdrop.planet_center(lvl).x, 192.0, "level %d planet" % lvl)


func test_player_clamp_and_respawn_at_1152() -> void:
	var w := _world(1, W_DECK)
	w.run_game_seconds(6.0, 1.0)
	check_eq(w.player_x, 1122.0, "right clamp")
	w.run_game_seconds(6.0, -1.0)
	check_eq(w.player_x, 30.0, "left clamp")
	w.run_game_seconds(6.0, 1.0)
	w.add_bullet(w.player_x, LevelData.PLAYER_Y, 0.0, 0.0)
	w.run_steps(1)
	check_eq(w.state, GameWorld.State.RESPAWN, "hit")
	var guard := 0
	while w.state == GameWorld.State.RESPAWN and guard < 2000:
		w.run_steps(1)
		guard += 1
	check_eq(w.state, GameWorld.State.PLAYING, "respawned")
	check_eq(w.player_x, 576.0, "respawn at W / 2")


func test_enemies_turn_and_children_clamp_at_1152() -> void:
	for lvl in [1, 10, 17]:
		var w := _world(lvl, W_DECK)
		var e := w.add_enemy(1, 576.0, 1.0)
		e.dir_timer = INF
		var lo := INF
		var hi := -INF
		for i in int(40.0 / LevelData.SIM_STEP):
			w.run_steps(1)
			lo = minf(lo, e.x)
			hi = maxf(hi, e.x)
		check_eq(hi, 1102.0, "level %d: turns at 1102" % lvl)
		check_eq(lo, 50.0, "level %d: turns at 50" % lvl)
	for lvl in [7, 12]:
		var w := _world(lvl, W_DECK)
		var e := w.add_enemy(2, 1102.0)
		w.apply_hit(e)
		check_eq(w.enemies.size(), 2, "level %d: split" % lvl)
		check_eq([w.enemies[0].x, w.enemies[1].x], [1078.0, 1102.0], "level %d: right child clamped to 1102" % lvl)


func test_spawn_range_at_1152() -> void:
	# Blockers everywhere left of 1022 on the other lanes: the new original appears in the free right column.
	for s in [1, 2, 3, 4, 5, 6]:
		var w := GameWorld.new(1, 1, 0, 3, s, W_DECK)
		for x in [160.0, 380.0, 600.0, 820.0]:
			w.add_enemy(1 if int(x) % 2 == 0 else 2, x)
		w.slots.resize(1)
		w.start_combat()
		var spawned: Array = w.events.filter(func(e: Dictionary) -> bool: return e["type"] == "enemy_spawned")
		check_eq(spawned.size(), 1, "seed %d: one original" % s)
		var x := float(spawned[0]["x"])
		check(x >= 930.0 and x <= 1102.0, "seed %d: spawn x %.1f in the free column [930, 1102]" % [s, x])
	var beyond := 0
	for s in 60:
		var w := GameWorld.new(17, 1, 0, 3, 2000 + s, W_DECK)
		w.start_combat()
		for e in w.enemies:
			check(e.x >= 50.0 and e.x <= 1102.0, "seed %d: spawn %.1f within [50, 1102]" % [s, e.x])
			if e.x > 910.0:
				beyond += 1
	check(beyond > 10, "spawns on the widened part of the field (%d)" % beyond)


func test_bullets_removed_beyond_1152() -> void:
	var w := _world(17, W_DECK)
	w.invincible = true
	var r := w.add_bullet(W_DECK - 60.0, 300.0, LevelData.ENEMY_BULLET_DIAG_B, LevelData.ENEMY_BULLET_DIAG_A)
	var last := r.x
	while w.bullets.has(r):
		last = r.x
		w.run_steps(1)
	check(last > W_DECK and last - GameWorld.BULLET_HALF <= W_DECK, "removed once off the 1152 field (last x %.2f)" % last)
	var b := w.add_bullet(1100.0, 300.0, 0.0, LevelData.ENEMY_BULLET_SPEED)
	w.run_steps(1)
	check(w.bullets.has(b), "x = 1100 is on the 1152 field")
	check_eq(preload("res://scripts/game/projectiles_view.gd").side_fade(1143.0, 190.0, W_DECK), 1.0, "fade band from W − 9")


# --- Bots ----------------------------------------------------------------------------------------
func test_autoplay_bot_at_1152() -> void:
	for lvl in [1, 7, 14]:
		var w := GameWorld.new(lvl, 1, lvl % 6, 3, 31 + lvl, W_DECK)
		w.invincible = true
		var right := -INF
		var guard := 0
		while not w.is_finished() and guard < 60 * 300:
			var d: Vector2 = Autopilot.decide(w)
			w.update(STEP, d.x, d.y > 0.5)
			right = maxf(right, w.player_x)
			if w.player_x < 30.0 or w.player_x > 1122.0:
				check(false, "level %d: ship x %.1f out of range" % [lvl, w.player_x])
				return
			guard += 1
		check_eq(w.state, GameWorld.State.COMPLETE, "level %d completed by the bot at 1152" % lvl)
		check(right > 930.0, "level %d: the bot uses the widened field (max x %.1f)" % [lvl, right])
	var e := _world(17, W_DECK)
	check_eq(Autopilot._escape_set(e), PackedFloat64Array([30.0, 1122.0]), "escape set spans [30, 1122]")


func _simulate_demo(d: AttractDirector, tag: String) -> void:
	var w := d.make_world(W_DECK)
	check_eq(w.width, W_DECK, "%s: demo world width" % tag)
	var guard := 0
	var hits := 0
	var hits_at_hit := -1
	var fired_after := 0
	var through := {}
	while not d.is_over() and guard < int(AttractDirector.DURATION_MAX * 60.0) + 120:
		guard += 1
		w.events.clear()
		d.play(w, STEP)
		check(w.state != GameWorld.State.CLEARING and w.state != GameWorld.State.COMPLETE and not w.goal_met,
			"%s: never completes the level" % tag)
		for ev in w.events:
			var ty := String(ev["type"])
			if AttractDirector.HIT_EVENTS.has(ty):
				hits += 1
			elif ty == "shot_fired" and hits >= d.hits_wanted:
				fired_after += 1
			elif ty == "player_hit":
				check(hits_at_hit < 0, "%s: hit only once" % tag)
				hits_at_hit = hits
		if w.player_alive and w.invincible:
			for b in w.bullets:
				if absf(b.x - w.player_x) < LevelData.PLAYER_HIT_DX and absf(b.y - LevelData.PLAYER_Y) < LevelData.PLAYER_HIT_DY:
					through[b.id] = true
		check(w.player_x >= 30.0 and w.player_x <= 1122.0, "%s: ship in range" % tag)
		if not failures.is_empty():
			return
	check(d.is_over(), "%s: the demo ends" % tag)
	check_eq(fired_after, 0, "%s: no salvo after the wanted hits" % tag)
	check(hits_at_hit >= AttractDirector.HITS_MIN, "%s: %d hits before the ship was hit" % [tag, hits_at_hit])
	check_eq(through.size(), 0, "%s: no fireball through the invincible ship" % tag)
	check(d.time >= AttractDirector.DURATION_MIN - 1e-6 and d.time <= d.duration + 1e-6, "%s: length %.2f" % [tag, d.time])
	check_eq(w.state, GameWorld.State.GAME_OVER, "%s: ends with the player explosion" % tag)


func test_attract_demos_at_1152() -> void:
	for s in range(1, 9):
		_simulate_demo(AttractDirector.new(s * 6007), "W=1152 seed %d" % (s * 6007))
		if not failures.is_empty():
			return
	for lvl in [1, 20]:
		var d := AttractDirector.new(4321 + lvl, lvl)
		d.set_duration(AttractDirector.DURATION_MIN)
		_simulate_demo(d, "W=1152 level %d" % lvl)


func test_game_screen_takes_1152() -> void:
	_router()
	_begin()
	Display.forced_mode = 3
	check_eq(Display.logical_width(), W_DECK)
	Run.start_new(1, 0, 3)
	Run.dev_flags = {"invincible": true, "autoplay": true}
	var gs: Node2D = LogicOnlyScreen.new()
	gs.setup({"level": 2})
	gs._ready()
	var w: GameWorld = gs.get("world")
	check_eq(w.width, W_DECK, "world width")
	check_eq(w.player_x, 576.0, "ship at W / 2")
	check_eq((gs.get("_hud") as Node2D).get("width"), W_DECK, "HUD width")
	var clip: Control = (gs.get("_bullets") as Node).get_parent()
	check_eq(clip.size, Vector2(W_DECK, LevelData.GROUND_Y), "fireball clip spans the field")
	var guard := 0
	while not w.is_finished() and guard < 1200:
		gs._process(0.25)
		guard += 1
	check_eq(w.state, GameWorld.State.COMPLETE, "autoplay completes level 2 at 1152")
	gs.free()
	var ds: Node2D = LogicOnlyScreen.new()
	ds.setup({"attract": {"seed": 777, "level": 4}})
	ds._ready()
	check_eq((ds.get("world") as GameWorld).width, W_DECK, "demo world width")
	ds.free()
	Run.dev_flags = {}
	AudioManager.stop_music()
	_end()


# --- Layout in every canvas ----------------------------------------------------------------------
func test_first_start_layout_fits_every_canvas() -> void:
	_fonts()
	for m in 5:
		_begin()
		_mode(m)
		var s := QuietSelect.new()
		s.setup({})
		s._ready()
		var ox := Display.center_offset()
		check_eq(s.position.x, ox, "mode %d: content centred" % m)
		check_eq(s.starfield.size, Vector2(Display.logical_size()), "mode %d: sky spans the canvas" % m)
		for i in Display.MODE_COUNT:
			var r := DisplaySelect.card_rect(i)
			check(r.position.x - 30.0 >= -ox and r.end.x + 30.0 <= ScreenBase.W + ox, "mode %d: card %d on the canvas" % [m, i])
			var name_w := UiKit.text_width(Assets.font_title, Display.mode_name(i), DisplaySelect.NAME_SIZE)
			check(DisplaySelect.TEXT_X + name_w + 16.0 < r.size.x, "card %d: name fits (%.0f)" % [i, name_w])
			var info_w := UiKit.text_width(Assets.font_body, String(Display.MODE_INFO[i]), DisplaySelect.INFO_SIZE)
			check(DisplaySelect.TEXT_X + info_w + 16.0 < r.size.x, "card %d: explanation fits (%.0f)" % [i, info_w])
			check(DisplaySelect.INFO_Y + 6.0 <= DisplaySelect.CARD_H, "explanation inside the card")
			# Icon + caption inside the card, left of the text.
			var iw := DisplaySelect.ICON_H * float(Display.logical_size_of(i).x) / 720.0
			check(DisplaySelect.TEXT_X * 0.5 + 4.0 + iw * 0.5 < DisplaySelect.TEXT_X - 6.0, "card %d: icon left of the text" % i)
			check(DisplaySelect.CARD_H * 0.5 - 7.0 + DisplaySelect.ICON_H * 0.5 + 14.0 + 3.0 <= DisplaySelect.CARD_H,
				"card %d: icon caption inside the card" % i)
			if i > 0:
				var b := DisplaySelect.badge_rect(r)
				check(b.position.y > DisplaySelect.card_rect(i - 1).end.y, "badge %d clear of the card above" % i)
				check(b.end.y < r.position.y + DisplaySelect.NAME_Y - 18.0, "badge %d clear of the mode name" % i)
				check(b.end.x < r.end.x - 10.0, "badge %d inside the card" % i)
		var last := DisplaySelect.card_rect(Display.MODE_COUNT - 1)
		check(last.end.y + 22.0 < DisplaySelect.SCREEN_Y - 12.0, "cards above the screen line")
		check(DisplaySelect.SCREEN_Y + 12.0 < DisplaySelect.FOOTNOTE_Y - 12.0, "screen line above the footnote")
		check(DisplaySelect.FOOTNOTE_Y + 8.0 < DisplaySelect.HINT_Y - 14 * 2.45 * 0.5, "footnote above the hints")
		check(DisplaySelect.HEADING_Y + 8.0 < DisplaySelect.CARD_Y - 6.0, "heading above the cards")
		var logo := Assets.logo_texture()
		if logo:
			var lh := DisplaySelect.LOGO_W * float(logo.get_height()) / float(logo.get_width())
			check(DisplaySelect.LOGO_Y - lh * 0.5 - 3.0 > 0.0, "logo on the canvas")
			check(DisplaySelect.LOGO_Y + lh * 0.5 + 3.0 < DisplaySelect.HEADING_Y - DisplaySelect.HEADING_SIZE,
				"logo above the heading")
		var lw := UiKit.text_width(Assets.font_body, DisplaySelect.screen_line(Vector2i(2560, 1600)), 15)
		check(lw < ScreenBase.W - 60.0, "screen line fits")
		s.free()
		_end()


func test_title_layout_fits_every_canvas() -> void:
	_fonts()
	var font := Assets.font_title
	var row := UiKit.menu_row_rect(Vector2(TitleScreen.CX, 300.0), TitleScreen.MENU_W, TitleScreen.MENU_FONT)
	var label_end := row.position.x + 30.0 + UiKit.text_width(font, TitleScreen.LABELS["display"], TitleScreen.MENU_FONT)
	for m in 5:
		var vw := UiKit.text_width(font, Display.menu_name(m), TitleScreen.MENU_FONT)
		var pointer_left := row.end.x - 30.0 - 18.0 - vw - 14.0 - 6.0
		check(label_end + 12.0 < pointer_left, "%s fits the DISPLAY row" % Display.menu_name(m))
	var panel := TitleScreen.menu_panel_rect()
	for m in 5:
		_begin()
		_mode(m)
		var t := QuietTitle.new()
		t.setup({"select": "display"})
		t._ready()
		var ox := Display.center_offset()
		check_eq(t.position.x, ox, "mode %d: title centred" % m)
		check_eq(t.starfield.size, Vector2(Display.logical_size()), "mode %d: sky spans the canvas" % m)
		check(panel.position.x - 30.0 > -ox and panel.end.x + 30.0 < ScreenBase.W + ox, "mode %d: panel on the canvas" % m)
		check_eq(TitleScreen.BEST_X + t.ox, t.right_x() - 26.0, "mode %d: BEST at the canvas edge" % m)
		for d: Dictionary in t.get("_demons"):
			check(float(d["min"]) >= t.left_x() + 40.0 and float(d["max"]) <= t.right_x() - 40.0,
				"mode %d: demon band on the canvas" % m)
			check(float(d["max"]) < panel.position.x - 25.0 or float(d["min"]) > panel.end.x + 25.0,
				"mode %d: demon band clear of the panel" % m)
		# Every DISPLAY line (pending or not, with a monitor note for the Steam Deck / a 1080p screen) fits.
		for screen in [Vector2i.ZERO, Vector2i(1280, 800), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			t.set("_screen", screen)
			for p in 5:
				t.display_pending = p
				var w := UiKit.text_width(Assets.font_body_bold, t.display_line_text(true), 16)
				check(w < ScreenBase.W - 80.0, "mode %d pending %d on %s: DISPLAY line fits (%.0f)" % [m, p, str(screen), w])
		t.free()
		_end()


func test_screens_on_the_1152_canvas() -> void:
	_fonts()
	_begin()
	_mode(3)
	Run.start_new(1, 0, 5)
	var ss := ShipSelect.new()
	ss.setup({"ship": 0})
	ss._ready()
	check_eq([ss.left_x(), ss.right_x()], [-96.0, 1056.0], "canvas edges in content coordinates")
	var t0 := ShipSelect.tile_rect(0)
	var t2 := ShipSelect.tile_rect(2)
	check_near(t0.position.x + ss.ox, W_DECK - (t2.end.x + ss.ox), 0.01, "tiles centred on 1152")
	check_eq(ss.full_rect(), Rect2(-96, 0, 1152, 720), "full rect")
	ss.free()
	check_eq(Victory.earth_diameter(W_DECK), W_DECK, "victory Earth fills the 1152 canvas")
	var sf := Starfield.new()
	check_eq(sf.tex_size(), Vector2i(1152, 720), "starfield texture size")
	sf.free()
	_end()


# --- Readability on the small screens --------------------------------------------------------------
func test_small_text_minimum() -> void:
	check_eq([Display.min_text_size_of(0), Display.min_text_size_of(1), Display.min_text_size_of(2)], [0, 0, 0],
		"modes 0–2: no minimum (unchanged look)")
	# Review round: measured as cap height (capital letters ≥ 9 px on screen, Deck Verified), not font size.
	check_eq(Display.min_text_size_of(3), 12, "mode 3: 12 logical px = 13.3 px font, capitals 9.2 px at 1280×800")
	check_eq(Display.min_text_size_of(4), 14, "mode 4: 14 px font, capitals 9.7 px")
	for m in [3, 4]:
		check(Display.cap_height_px(Display.min_text_size_of(m), m) >= Display.MIN_CAP_PX - 1e-6,
			"mode %d: capitals ≥ 9 px" % m)
		check(Display.cap_height_px(Display.min_text_size_of(m) - 1, m) < Display.MIN_CAP_PX,
			"mode %d: the smallest size that reaches 9 px (modest lift)" % m)
	_fonts()
	_begin()
	var widths := {}
	for m in [0, 1, 2, 3, 4]:
		_mode(m)
		check_eq(UiKit.label_size(14), 14, "mode %d: larger sizes untouched" % m)
		var expect := 9 if m < 3 else Display.min_text_size_of(m)
		check_eq(UiKit.label_size(9), expect, "mode %d: key-cap label size" % m)
		widths[m] = UiKit.glyph_width("pad:START", 13)
	check_eq(widths[1], widths[0], "glyph width unchanged in mode 1")
	check_eq(widths[2], widths[0], "glyph width unchanged in mode 2")
	check(widths[4] >= widths[0], "mode 4: the larger label widens its key cap")
	_end()


## Review round: the lifted captions still fit their layouts in modes 3/4, and modes 0–2 keep every position.
func test_lifted_captions_fit() -> void:
	_fonts()
	_begin()
	var hud: Node2D = load("res://scripts/game/hud.gd").new()
	var f_label: Font = hud.call("_spaced", Assets.font_body_bold, 2)
	hud.set("_f_label", f_label)
	var f_value: Font = Assets.font_title
	for m in [0, 1, 2, 3, 4]:
		_mode(m)
		var ls := UiKit.label_size(10)
		var sx: float = hud.call("counter_value_x", "SHOTS LEFT", 318.0, 410.0)
		var hx: float = hud.call("counter_value_x", "HITS", 498.0, 540.0)
		if m < 3:
			check_eq([ls, sx, hx], [10, 410.0, 540.0], "mode %d: HUD captions and bonus counters unchanged" % m)
		var cap_w := func(t: String) -> float: return f_label.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
		var val_w := func(t: String) -> float: return f_value.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		check(318.0 + cap_w.call("SHOTS LEFT") + 4.0 <= sx, "mode %d: SHOTS LEFT caption clear of its value" % m)
		check(sx + val_w.call("100") + 8.0 <= 498.0, "mode %d: shots value clear of HITS" % m)
		check(498.0 + cap_w.call("HITS") + 4.0 <= hx, "mode %d: HITS caption clear of its value" % m)
		check(hx + val_w.call("20/20") <= 660.0 - 4.0, "mode %d: HITS value inside the counter box" % m)
		# Top bar: captions (baseline 14) inside the 40 px bar, above the values (baseline 35), DIFFICULTY ≠ TIME.
		check(14.0 - ls * 0.72 >= 1.0, "mode %d: caption top inside the bar" % m)
		check(14.0 + f_label.get_descent(ls) < 35.0 - 19 * 0.72, "mode %d: caption above the values" % m)
		check(700.0 + cap_w.call("DIFFICULTY") + 10.0 < 942.0 - cap_w.call("TIME"), "mode %d: DIFFICULTY / TIME apart" % m)
		# First-start badge on the card's top border, inside the card, clear of the icon caption below.
		var card := DisplaySelect.card_rect(0)
		var br := DisplaySelect.badge_rect(card)
		check(br.position.x > card.position.x + DisplaySelect.TEXT_X, "mode %d: badge right of the icon column" % m)
		check(DisplaySelect.badge_size() * 0.72 <= DisplaySelect.BADGE_H - 4.0, "mode %d: badge text fits its pill" % m)
		check(card.position.y + DisplaySelect.CARD_H * 0.5 + 11.0 + 14.0 + Assets.font_body_bold.get_descent(
			DisplaySelect.badge_size()) <= card.end.y, "mode %d: icon caption inside the card" % m)
		# Ship select stat rows: one size, 13 in modes 0–2, lifted only as far as label and value stay apart.
		var fs := ShipSelect.stat_size()
		if m < 3:
			check_eq(fs, 13, "mode %d: stat rows unchanged" % m)
		var col_w := ShipSelect.TILE_W * 0.5 - 28.0
		for row: Array in ShipSelect.STAT_WORST:
			var gap: float = col_w - UiKit.text_width(Assets.font_body, row[0], fs) - UiKit.text_width(Assets.font_title, row[1], fs)
			check(gap >= (ShipSelect.STAT_GAP if fs > 13 else 0.0), "mode %d: stat row %s / %s apart (%.1f px)" % [m, row[0], row[1], gap])
	hud.free()
	_end()


# --- Determinism of modes 0 / 1 / 2 ------------------------------------------------------------------
## W = 1280 digests recorded with the code BEFORE the Steam Deck change (git d1bd58e, tests/test_wide_playfield.gd
## digest functions), for the same scenarios as WP.EXPECTED.
const EXPECTED_1280 := [
	[[3, 1, 2, 4242, 3, true, "bot", 40.0], {"destroyed": 12,"enemies_md5": "d751713988987e9331980363e24189ce","events": 182,"lives": 3,"md5": "7b09f5b3cc46a447ff47e64b2c467766","player_x": 643.7543655776172,"score": 220,"state": 4,"steps": 6921}],
	[[11, 2, 4, 777, 3, true, "sweep", 30.0], {"destroyed": 1,"enemies_md5": "89da0e5fa822dbe8ed2b236ba0a5ef3d","events": 451,"lives": 3,"md5": "c7fb0981edcb062b0dee22a7baf293f4","player_x": 870.0000000000066,"score": 40,"state": 1,"steps": 8121}],
	[[17, 3, 1, 99, 3, false, "bot", 40.0], {"destroyed": 7,"enemies_md5": "3cdd94b1dd205d2e40621ddfad8db0f5","events": 338,"lives": 0,"md5": "5cdee90c814bf146b0912a2924c90640","player_x": 520.5351008050912,"score": 840,"state": 6,"steps": 5386}],
	[[8, 0, 3, 1234, 5, true, "sweep", 30.0], {"destroyed": 4,"enemies_md5": "0fab3c60ef4b359cb14a40f619d57b8b","events": 172,"lives": 5,"md5": "e4e52fa4b65d81eb66e3aa4c3686e17d","player_x": 730.000000000003,"score": 100,"state": 1,"steps": 6768}],
	[[20, 1, 5, 31337, 3, false, "sweep", 30.0], {"destroyed": 0,"enemies_md5": "863704d312682ec262eb7275705e06af","events": 154,"lives": 0,"md5": "a631da1142e9c2f22a43beb81fce374d","player_x": 462.0833333333307,"score": 0,"state": 6,"steps": 3512}],
	[[13, 1, 0, 55, 3, true, "bot", 40.0], {"destroyed": 17,"enemies_md5": "db90115a80c67d3f68a03f88caca7040","events": 58,"lives": 3,"md5": "21e525401b08fc31172ec037c8f67b2d","player_x": 525.7638702130128,"score": 0,"state": 1,"steps": 9168}],
	[[15, 1, 2, 2024, 3, true, "bot", 40.0], {"destroyed": 1,"enemies_md5": "4d926508eb0a73cd2f71cc5b463988e9","events": 446,"lives": 3,"md5": "e211ceb77f81ad95f6b6f6cc1e8d39e9","player_x": 798.2874752520122,"score": 100,"state": 1,"steps": 9168}],
]
const EXPECTED_DEMOS_1280 := [
	[7919, {"events": 129,"hit_time": 16.56666666666701,"hits": 5,"md5": "a297fc98649fc36246a119342d2aaaba","player_x": 384.3375117106659,"time": 18.466666666666903,"withdrawn": 0}],
	[39595, {"events": 201,"hit_time": 26.666666666666433,"hits": 3,"md5": "d8fab4637bc7d481a35c30b661f479a0","player_x": 1247.4665756202712,"time": 28.566666666666325,"withdrawn": 0}],
	[451383, {"events": 700,"hit_time": 22.89999999999998,"hits": 4,"md5": "ce6e82704aa8210c4d0ca6477fcd6256","player_x": 765.3159317436395,"time": 24.799999999999873,"withdrawn": 0}],
]


func _check_digest(got: Dictionary, want: Dictionary, tag: String) -> void:
	check_eq(got.keys().size(), want.keys().size(), "%s: digest keys" % tag)
	for k: String in want:
		if want[k] is float:
			check_near(float(got.get(k, NAN)), want[k], 1e-9, "%s: %s" % [tag, k])
		else:
			check_eq(got.get(k), want[k], "%s: %s" % [tag, k])


static func _demo_digest(rng_seed: int, width: float) -> Dictionary:
	var d := AttractDirector.new(rng_seed)
	var w := d.make_world(width)
	var lines := PackedStringArray()
	var i := 0
	while not d.is_over() and i < 60 * 45:
		w.events.clear()
		d.play(w, 1.0 / 60.0)
		for ev in w.events:
			lines.append("%d %s" % [i, JSON.stringify(ev, "", true, true)])
		i += 1
	return {"events": lines.size(), "md5": "\n".join(lines).md5_text(), "hits": d.hits, "hit_time": d.hit_time,
		"withdrawn": d.salvos_withdrawn, "time": d.time, "player_x": w.player_x}


## Modes 0 / 1 / 2 play exactly as before: their worlds are built with the mode's width (960 / 1280 / 1280), and
## the simulation at both widths reproduces the digests recorded before this change.
func test_modes_0_1_2_are_bit_for_bit_unchanged() -> void:
	check_eq([Display.logical_size_of(0).x, Display.logical_size_of(1).x, Display.logical_size_of(2).x], [960, 1280, 1280],
		"widths of modes 0–2")
	for row: Array in WP.EXPECTED:
		var a: Array = row[0]
		_check_digest(WP.digest(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], float(Display.logical_size_of(0).x)),
			row[1], "mode 0 %s" % str(a))
		if not failures.is_empty():
			return
	for row: Array in EXPECTED_1280:
		var a: Array = row[0]
		_check_digest(WP.digest(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], float(Display.logical_size_of(1).x)),
			row[1], "modes 1/2 %s" % str(a))
		if not failures.is_empty():
			return
	for row: Array in WP.EXPECTED_DEMOS:
		_check_digest(_demo_digest(row[0], 960.0), row[1], "mode 0 demo %d" % row[0])
	for row: Array in EXPECTED_DEMOS_1280:
		_check_digest(_demo_digest(row[0], 1280.0), row[1], "modes 1/2 demo %d" % row[0])
	# The Steam Deck width is a different field (the limits matter).
	var a := WP.digest(17, 1, 2, 4242, 3, true, "sweep", 20.0, 1280.0)
	var b := WP.digest(17, 1, 2, 4242, 3, true, "sweep", 20.0, W_DECK)
	check(a["md5"] != b["md5"], "1152 differs from 1280")
