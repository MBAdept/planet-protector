extends TestBase
## Visual & UX review of the Steam Deck round (display modes 3 / 4, docs/SPEC.md §11.2, §12, §18).
## Every screen was captured in modes 3 and 4 (xvfb 1280×800 / 1280×720), modes 0 / 1 / 2 were captured with the code
## before the change (git d1bd58e) and after it and pixel-compared, and X-root grabs of the real window were taken on a
## 1280×800 screen (bars / first start). These tests pin what can be checked headlessly.
## Failing tests are review findings (see their messages); the others guard behaviour that was verified on screen.
## Text size is measured as the CAP HEIGHT on screen (the height of a capital letter: font size × canvas scale × the
## font's OS/2 sCapHeight / unitsPerEm), which is what a reader sees as "how tall the letters are"; the screenshot
## measurements agreed with it (HUD caption "SCORE" in mode 3: 7–8 px of ink at 1280×800).
## The display mode is forced with Display.forced_mode and restored; no settings are written.

const DisplaySelect := preload("res://scripts/screens/display_select_screen.gd")
const Hud := preload("res://scripts/game/hud.gd")

const DECK := Vector2i(1280, 800)
const SCREEN_720 := Vector2i(1280, 720)
## Valve's Deck Verified legibility guideline: the smallest on-screen characters at least 9 px tall at 1280×800.
## (The lead's brief said "~11 px tall"; 9 px is the more lenient bar and is still missed.)
const MIN_CAP_PX := 9.0
const EXO2 := "res://assets/fonts/Exo2.ttf"


func _force(m: int) -> int:
	var before := Display.forced_mode
	Display.forced_mode = m
	Display.apply_canvas()
	return before


func _restore(before: int) -> void:
	Display.forced_mode = before
	Display.apply_canvas()


## sCapHeight / unitsPerEm of a TrueType font, read from its OS/2 and head tables.
static func cap_ratio(path: String) -> float:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0.0
	f.big_endian = true
	f.seek(4)
	var n := f.get_16()
	var tables := {}
	for i in n:
		f.seek(12 + 16 * i)
		var tag := f.get_buffer(4).get_string_from_ascii()
		f.get_32()
		tables[tag] = f.get_32()
	f.seek(int(tables["head"]) + 18)
	var upem := f.get_16()
	f.seek(int(tables["OS/2"]) + 88)
	var cap := f.get_16()
	return float(cap) / float(upem)


## Cap height in screen pixels of a text drawn at logical font size `size` in mode m.
static func cap_px(size: int, m: int) -> float:
	return float(size) * Display.canvas_scale_of(m) * cap_ratio(EXO2)


# --- Rendering / bars (verified on screen; guards) -------------------------------------------------
func test_deck_mode_fills_a_1280x800_screen_without_bars() -> void:
	# X-root grab of the real window on a 1280×800 xvfb screen: ink reaches all four edges.
	var cfg := Display.canvas_config(Display.Mode.FULLSCREEN_DECK)
	check_eq(cfg["content_scale_size"], DECK, "mode 3 render size")
	var r: Vector2i = cfg["content_scale_size"]
	check_near(float(DECK.x) / r.x, float(DECK.y) / r.y, 1e-9, "mode 3 on a 1280×800 screen: same scale on both axes")
	check_near(float(DECK.x) / r.x, 1.0, 1e-9, "mode 3 on a 1280×800 screen: shown 1:1")
	var cfg4 := Display.canvas_config(Display.Mode.FULLSCREEN_720)
	check_eq(cfg4["content_scale_size"], SCREEN_720, "mode 4 render size")


func test_old_modes_render_configuration_unchanged() -> void:
	# Values of git d1bd58e (screenshots of modes 0 / 1 / 2 before and after differ only in animation timing).
	var c0 := Display.canvas_config(0)
	check_eq(c0["content_scale_mode"], Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "mode 0 stretch")
	check_eq(c0["content_scale_size"], Vector2i(960, 720), "mode 0 canvas")
	check_eq(c0["oversampling_override"], 0.0, "mode 0 oversampling")
	for m in [1, 2]:
		var c := Display.canvas_config(m)
		var k := 1.5 if m == 1 else 2.0
		check_eq(c["content_scale_size"], Vector2i(1920, 1080) if m == 1 else Vector2i(2560, 1440), "mode %d size" % m)
		check_eq(c["global_canvas_transform"], Transform2D.IDENTITY.scaled(Vector2(k, k)), "mode %d transform" % m)
		check_eq(c["oversampling_override"], k, "mode %d oversampling" % m)
	for m in [0, 1, 2]:
		check_eq(Display.min_text_size_of(m), 0, "mode %d: no text minimum (exact old look)" % m)


func test_best_fit_badge_on_deck_and_720_screens() -> void:
	check_eq(Display.best_mode(DECK), Display.Mode.FULLSCREEN_DECK, "1280×800 → Steam Deck card")
	check_eq(Display.best_mode(SCREEN_720), Display.Mode.FULLSCREEN_720, "1280×720 → 1280×720 card")
	check_eq(Display.best_mode(Vector2i(1920, 1080)), Display.Mode.FULLSCREEN_1080, "1080p unchanged")
	check_eq(Display.best_mode(Vector2i(2560, 1440)), Display.Mode.FULLSCREEN_1440, "1440p unchanged")
	check_eq(Display.fit_note(Display.Mode.FULLSCREEN_DECK, DECK), "best fit for your 1280×800 screen", "title note")


# --- Readability on the 7" 1280×800 screen (findings) ---------------------------------------------
func test_hud_captions_are_legible_on_the_deck() -> void:
	# SCORE / LIVES / LEVEL / DIFFICULTY / TIME / SHOTS LEFT / HITS. Mode 3: label_size(10) stays 10 (10 × 1.111 =
	# 11.1 px font, i.e. NOT changed at all in mode 3), cap height 7.7 px; mode 4: 11 px font, cap 7.6 px.
	for m in [Display.Mode.FULLSCREEN_DECK, Display.Mode.FULLSCREEN_720]:
		var before := _force(m)
		var size := UiKit.label_size(Hud.LABEL_SIZE)
		_restore(before)
		var px := cap_px(size, m)
		check(px >= MIN_CAP_PX, "mode %d: HUD captions are only %.1f px tall on screen (cap height; font %d logical px)"
			% [m, px, size] + " – below %.0f px (lead: ~11 px)" % MIN_CAP_PX)


func test_keycap_labels_are_legible_on_the_deck() -> void:
	# Key labels (ENTER, ESC, F11, …) of the standard 14 px hint rows and pad labels (START, SELECT): in mode 3 the
	# lift changes nothing at size 14 (int(14×0.8)=11, int(14×0.72)=10 ≥ min 10).
	for m in [Display.Mode.FULLSCREEN_DECK, Display.Mode.FULLSCREEN_720]:
		var before := _force(m)
		var key := UiKit.label_size(int(14 * 0.8))
		var pad := UiKit.label_size(int(14 * 0.72))
		_restore(before)
		check(cap_px(key, m) >= MIN_CAP_PX, "mode %d: key-cap labels (ENTER/ESC) %.1f px tall on screen" % [m, cap_px(key, m)])
		check(cap_px(pad, m) >= MIN_CAP_PX, "mode %d: pad labels (START/SELECT) %.1f px tall on screen" % [m, cap_px(pad, m)])


func test_first_start_badge_is_legible_on_small_screens() -> void:
	# BEST FIT FOR YOUR SCREEN (11 px) and the 800p / 720p icon captions (11 px) were not lifted.
	# Fix round: measured at the size actually drawn in mode m (DisplaySelect.badge_size()); the constant BADGE_SIZE
	# itself must stay 11 so that modes 0–2 keep their exact look.
	for m in [Display.Mode.FULLSCREEN_DECK, Display.Mode.FULLSCREEN_720]:
		var before := _force(m)
		var size := DisplaySelect.badge_size()
		_restore(before)
		var px := cap_px(size, m)
		check(px >= MIN_CAP_PX, "mode %d: BEST FIT badge / icon captions %.1f px tall on screen" % [m, px])


# --- Window handling (findings) --------------------------------------------------------------------
func test_first_start_window_fits_a_1280x800_screen() -> void:
	# A real first start (mode 0, not fullscreen) on a 1280×800 screen opens the project's 1280×960 window: X-root grab
	# showed the footnote and the hint row (Select / Confirm / Quit) below the bottom of the screen. Only a window
	# coming back from a 16:9 mode is fitted (classic_window_size); the very first one is not. This is the screen on
	# which a Steam Deck user (desktop mode) must pick 1280×800.
	var h := int(ProjectSettings.get_setting("display/window/size/window_height_override", 960))
	var saved_kind: int = Display.get("_window_kind")
	var saved_pending: bool = Display.get("_classic_resize_pending")
	var before := _force(Display.Mode.WINDOW_4_3)
	Display.set("_window_kind", -1)
	Display.set("_classic_resize_pending", false)
	Display.apply_window()
	var fitted: bool = Display.get("_classic_resize_pending")
	Display.set("_window_kind", saved_kind)
	Display.set("_classic_resize_pending", saved_pending)
	_restore(before)
	check(fitted or h + Display.DECORATION_ALLOWANCE <= DECK.y,
		"first start on a 1280×800 screen: the classic window is %d px tall and is not fitted to the screen" % h)


func test_f11_deck_desktop_window_with_task_bar() -> void:
	# display.gd says 1152×720 is there for "a smaller usable area (e.g. the Steam Deck desktop with its task bar)".
	# With KDE Plasma's default 44 px panel the usable area is 1280×756; 720 + 40 > 756, so the list is skipped and
	# fit_aspect gives 1145×715 (not exactly 16:10, a non-integer downscale of the 1280×800 picture).
	var s := Display.mode_window_size(Display.Mode.FULLSCREEN_DECK, Vector2i(1280, 756))
	check_eq(s, Vector2i(1152, 720), "F11 in mode 3 on the Deck desktop (44 px panel)")
	check_near(float(s.x) / float(s.y), 1.6, 1e-3, "F11 window of mode 3 is 16:10")


func test_f11_sizes_on_common_screens() -> void:
	check_eq(Display.mode_window_size(3, Vector2i(1920, 1040)), Vector2i(1280, 800), "mode 3 on 1080p desktop")
	check_eq(Display.mode_window_size(4, Vector2i(1920, 1040)), Vector2i(1280, 720), "mode 4 on 1080p desktop")
	check_eq(Display.mode_window_size(4, Vector2i(1280, 690)), Vector2i(1152, 648), "mode 4 on a 1280×720 desktop")
	check_eq(Display.mode_window_size(1, Vector2i(1920, 1040)), Vector2i(1600, 900), "mode 1 unchanged")


# --- Monitor hint (finding) ------------------------------------------------------------------------
func test_screen_note_warns_about_bars_of_the_16_10_mode() -> void:
	# On a 16:9 monitor the Steam Deck mode is pillarboxed (1280×800 shown at 1728×1080 with 96 px bars), but the
	# first-start line only ever warns about the 16:9 modes – and on a 16:10 monitor it says the 16:9 modes get bars
	# while not pointing at the bar-free 16:10 mode.
	var line := DisplaySelect.screen_line(Vector2i(1920, 1080))
	check(line.contains("16:10") or line.contains("Steam Deck"),
		"first-start line on a 1920×1080 screen does not mention that the 16:10 mode gets black bars: '%s'" % line)
