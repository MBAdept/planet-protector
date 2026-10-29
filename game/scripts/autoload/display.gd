extends Node
## Autoload "Display": display mode, logical canvas size and render resolution (docs/SPEC.md §1, §11, §12).
## Mode 0 is the classic 4:3 game exactly as specified by the client; modes 1 and 2 are 16:9 fullscreen with a
## WIDER playfield (logical 1280×720) rendered at exactly 1920×1080 / 2560×1440. Steam Deck round (SPEC §11.2, §18):
## mode 3 is 16:10 fullscreen for the Steam Deck (logical 1152×720 rendered at exactly 1280×800, canvas scale
## 1280 / 1152 = 1.111…), mode 4 is 16:9 fullscreen at 1280×720 (logical 1280×720, scale 1.0). The logical width
## always comes from the mode (LOGICAL_SIZE): 960 / 1280 / 1280 / 1152 / 1280 – "wide" never implies 1280.
##
## Technique (all modes use the root window only – no extra viewport, no reparenting, plain cross-platform
## Window/Viewport properties, so it behaves the same in the Windows export):
## - Mode 0: root content_scale_mode CANVAS_ITEMS, content_scale_size 960×720, aspect KEEP – unchanged from the
##   original project settings (window 1280×960, resizable, F11 fullscreen = Settings.fullscreen).
## - Modes 1–4: root content_scale_mode VIEWPORT with content_scale_size = the render size (1920×1080 /
##   2560×1440 / 1280×800 / 1280×720), aspect KEEP: the root viewport itself is that big, whatever the monitor or
##   window is, and Godot scales the finished image to the window (letterbox when the monitor's aspect differs).
##   The logical canvas (1280×720, 1152×720 in mode 3) is mapped onto it by the root's global canvas transform
##   (scale 1.5 / 2.0 / 1.111… / 1.0), and fonts are rasterised
##   for that scale (oversampling_override), so text, sprites and lines are drawn at the render resolution.
##   The game has no CanvasLayer and reads no viewport rect: all coordinates come from logical_size().
##   A screenshot of the root viewport is exactly the render size (render_size()).
##   Why not a SubViewport of the render size: every scene (Main, the dev capture / playthrough scenes) would have
##   to live inside it, `_input` handlers (title idle timer, demo exit) would need input forwarding, and screenshots
##   a second path. The root technique needs none of that and switches at runtime by setting five properties.
## - Window changes go through the root Window node (mode / size / position) so its viewport follows at once.
## - F11: mode 0 toggles fullscreen as before (persisted in Settings.fullscreen); modes 1–4 toggle between
##   fullscreen and a window of the mode's aspect (mode_window_size: modes 1/2 the largest of 1920×1080 / 1600×900 /
##   1280×720, mode 3 of 1280×800 / 1152×720, mode 4 of 1280×720 / 1152×648 that fits the screen) for this session –
##   the render resolution stays the chosen one.
## - Mouse pointer: the game has no mouse control, so it is hidden while the window is fullscreen and shown in a
##   window (pointer_mode / update_pointer).
## - Monitor hints for the menus (Godot cannot change the monitor's resolution, the 16:9 picture is scaled to it):
##   screen_size(), best_mode() (a 1280×800 screen → mode 3, a 1280×720 screen → mode 4, else best_wide_mode():
##   1440p from a 2560×1440 monitor up, else 1080p), fit_note(), letterboxed_on().
## - Small screens (modes 3/4, SPEC §11.2): min_text_size() lifts the small captions (HUD labels, key-cap labels of
##   the hint glyphs, badges, stat rows) so that their capital letters are at least MIN_CAP_PX (9) pixels tall on
##   screen – Valve's Deck Verified legibility bar at 1280×800: 12 logical px in mode 3, 14 in mode 4; 0 (no change)
##   in modes 0–2.
## The mode is stored in Settings.display_mode; `--display=<0..4>` forces one for this run without storing it.

signal changed

enum Mode { WINDOW_4_3, FULLSCREEN_1080, FULLSCREEN_1440, FULLSCREEN_DECK, FULLSCREEN_720 }

const MODE_COUNT := 5
const LOGICAL_4_3 := Vector2i(960, 720)
const LOGICAL_16_9 := Vector2i(1280, 720)
const LOGICAL_16_10 := Vector2i(1152, 720)
## Logical canvas per mode (all game / screen coordinates; the height is always 720).
const LOGICAL_SIZE := {
	Mode.WINDOW_4_3: LOGICAL_4_3,
	Mode.FULLSCREEN_1080: LOGICAL_16_9,
	Mode.FULLSCREEN_1440: LOGICAL_16_9,
	Mode.FULLSCREEN_DECK: LOGICAL_16_10,
	Mode.FULLSCREEN_720: LOGICAL_16_9,
}
const RENDER_SIZE := {
	Mode.WINDOW_4_3: Vector2i(1280, 960),        # default window size, resizable
	Mode.FULLSCREEN_1080: Vector2i(1920, 1080),
	Mode.FULLSCREEN_1440: Vector2i(2560, 1440),
	Mode.FULLSCREEN_DECK: Vector2i(1280, 800),
	Mode.FULLSCREEN_720: Vector2i(1280, 720),
}
const MODE_NAMES := {
	Mode.WINDOW_4_3: "WINDOW 4:3 (CLASSIC)",
	Mode.FULLSCREEN_1080: "FULLSCREEN 1920×1080 (16:9)",
	Mode.FULLSCREEN_1440: "FULLSCREEN 2560×1440 (16:9)",
	Mode.FULLSCREEN_DECK: "FULLSCREEN 1280×800 (16:10, STEAM DECK)",
	Mode.FULLSCREEN_720: "FULLSCREEN 1280×720 (16:9)",
}
## Value shown in the title menu's DISPLAY row (menu_name): the mode name, except the Steam Deck mode, whose full
## name is too long for the row – there the line under the menu says "Steam Deck" (MODE_SHORT / MODE_INFO).
const MENU_NAMES := {
	Mode.FULLSCREEN_DECK: "FULLSCREEN 1280×800 (16:10)",
}
## One-line explanation per mode (first-start screen, title).
const MODE_INFO := {
	Mode.WINDOW_4_3: "The original game in a resizable window.  F11 = fullscreen.",
	Mode.FULLSCREEN_1080: "Wider 16:9 playfield, sharp Full HD picture.",
	Mode.FULLSCREEN_1440: "Wider 16:9 playfield, extra sharp 1440p picture.",
	Mode.FULLSCREEN_DECK: "Fills the Steam Deck's 1280×800 screen, 16:10 playfield.",
	Mode.FULLSCREEN_720: "Wider 16:9 playfield, light 720p picture for small screens.",
}
## Windowed 16:9 sizes (F11 in modes 1/2), largest first.
const WIDE_WINDOW_SIZES: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1600, 900), Vector2i(1280, 720)]
## Windowed sizes of the small modes (F11 in modes 3/4), largest first: the render size itself (picture 1:1) or a
## size of the same aspect that fits a smaller usable area (e.g. the Steam Deck desktop with its task bar).
const DECK_WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 800), Vector2i(1152, 720)]
const SMALL_WIDE_WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1152, 648)]
## Smallest height of a capital letter on screen in the small modes 3/4 (screen pixels; Valve's Deck Verified
## guideline: the smallest characters at least 9 px tall at 1280×800). See min_text_size().
const MIN_CAP_PX := 9.0
## Cap height / font size of the UI fonts (OS/2 sCapHeight / unitsPerEm): Exo 2 0.69, Orbitron 0.72 – the smaller.
const FONT_CAP_RATIO := 0.69
## Room left for the title bar when a window size is checked against the usable screen area.
const DECORATION_ALLOWANCE := 40
## Same for the fixed window sizes of the small modes 3/4 (DECK_WINDOW_SIZES / SMALL_WIDE_WINDOW_SIZES): a usual
## title bar is 25–32 px, so 1152×720 still fits the Steam Deck desktop with KDE Plasma's 44 px panel (1280×756).
const SMALL_DECORATION_ALLOWANCE := 32
## Mode 0 window (project settings window_width/height_override).
const CLASSIC_WINDOW := Vector2i(1280, 960)

## One-line explanation without the picture detail (title DISPLAY line next to a screen note, see fit_note).
const MODE_SHORT := {
	Mode.WINDOW_4_3: "The original game in a resizable window",
	Mode.FULLSCREEN_1080: "Wider 16:9 playfield",
	Mode.FULLSCREEN_1440: "Wider 16:9 playfield",
	Mode.FULLSCREEN_DECK: "Steam Deck 16:10 playfield",
	Mode.FULLSCREEN_720: "Wider 16:9 playfield",
}
## A monitor counts as 16:9 within this relative aspect tolerance (1366×768 is 16:9, 1920×1200 is not).
const ASPECT_TOLERANCE := 0.01

## Mode forced by `--display=<n>` for this run (-1 = none; then Settings.display_mode counts).
var forced_mode := -1
## Monitor size used instead of the real one (tests; Vector2i.ZERO = the real monitor, see screen_size()).
var screen_override := Vector2i.ZERO
## F11 in a 16:9 mode: shown in a window instead of fullscreen (this session only; the mode name says fullscreen).
var wide_windowed := false
## Window layout last applied by apply_window(): -1 none yet, 0 classic, 1 wide.
var _window_kind := -1
## The classic window gets its standard size again the next time it is shown windowed after a 16:9 mode.
var _classic_resize_pending := false


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for s in a:
		if s.begins_with("--display="):
			var v := s.substr(10)
			if v.is_valid_int():
				forced_mode = clampi(int(v), 0, MODE_COUNT - 1)
	# Every scene (main, dev captures) gets the canvas of the current mode at once; the window itself is set up
	# by Main (apply_window) – screenshot runs keep their window.
	apply_canvas()
	# The pointer follows the window mode also when the window manager changes it (see update_pointer).
	get_tree().root.size_changed.connect(update_pointer)


## Current display mode: the forced one (--display) or the stored Settings.display_mode.
func mode() -> int:
	if forced_mode >= 0:
		return forced_mode
	return clampi(Settings.display_mode, 0, MODE_COUNT - 1)


func is_wide() -> bool:
	return mode() != Mode.WINDOW_4_3


## Logical canvas size all game/screen coordinates live in: 960×720 (4:3), 1280×720 (16:9) or 1152×720 (16:10).
func logical_size() -> Vector2i:
	return logical_size_of(mode())


func logical_width() -> float:
	return float(logical_size().x)


## Horizontal offset that centres a 960-wide layout on the current canvas (0 in 4:3, 160 at 1280, 96 at 1152).
func center_offset() -> float:
	return (logical_width() - float(LOGICAL_4_3.x)) * 0.5


## Resolution the game is rendered at: the window size in mode 0, the mode's fixed render size in modes 1–4.
func render_size() -> Vector2i:
	return RENDER_SIZE[mode()]


static func is_wide_mode(m: int) -> bool:
	return m != Mode.WINDOW_4_3


static func logical_size_of(m: int) -> Vector2i:
	return LOGICAL_SIZE[clampi(m, 0, MODE_COUNT - 1)]


## Canvas scale of a fixed-size mode (render width / logical width; the same vertically): 1.5 / 2.0 / 1.111… / 1.0.
## Mode 0: 1 (the window stretch does the rest).
static func canvas_scale_of(m: int) -> float:
	if not is_wide_mode(m):
		return 1.0
	return float(RENDER_SIZE[m].x) / float(logical_size_of(m).x)


static func mode_name(m: int) -> String:
	return String(MODE_NAMES.get(clampi(m, 0, MODE_COUNT - 1)))


## Value of the title DISPLAY row (MENU_NAMES, else the mode name).
static func menu_name(m: int) -> String:
	m = clampi(m, 0, MODE_COUNT - 1)
	return String(MENU_NAMES.get(m, MODE_NAMES[m]))


## The small modes (3 / 4: rendered at 1280 px wide, e.g. on the Steam Deck's 7" screen).
static func is_small_mode(m: int) -> bool:
	return m == Mode.FULLSCREEN_DECK or m == Mode.FULLSCREEN_720


## Smallest font size (logical px) for small captions in mode m: capitals of at least MIN_CAP_PX on screen at its
## canvas scale (12 in mode 3 = 13.3 px font, cap 9.2 px; 14 in mode 4, cap 9.7 px); 0 = no minimum (modes 0–2 keep
## their look exactly).
static func min_text_size_of(m: int) -> int:
	if not is_small_mode(m):
		return 0
	return ceili(MIN_CAP_PX / (FONT_CAP_RATIO * canvas_scale_of(m)) - 1e-6)


## Cap height in screen pixels of text drawn at logical font size `size` in mode m (the smaller UI font's ratio).
static func cap_height_px(size: int, m: int) -> float:
	return float(size) * canvas_scale_of(m) * FONT_CAP_RATIO


## min_text_size_of() for the current mode (UiKit.label_size, HUD labels).
func min_text_size() -> int:
	return min_text_size_of(mode())


## Root window configuration of a mode (pure; apply_canvas() sets exactly these values).
static func canvas_config(m: int) -> Dictionary:
	if is_wide_mode(m):
		var k := canvas_scale_of(m)
		return {"content_scale_mode": Window.CONTENT_SCALE_MODE_VIEWPORT, "content_scale_size": RENDER_SIZE[m],
			"content_scale_aspect": Window.CONTENT_SCALE_ASPECT_KEEP,
			"global_canvas_transform": Transform2D.IDENTITY.scaled(Vector2(k, k)), "oversampling_override": k}
	return {"content_scale_mode": Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "content_scale_size": LOGICAL_4_3,
		"content_scale_aspect": Window.CONTENT_SCALE_ASPECT_KEEP,
		"global_canvas_transform": Transform2D.IDENTITY, "oversampling_override": 0.0}


## Window size for F11 in a 16:9 mode: the largest of WIDE_WINDOW_SIZES that fits the usable screen area (with
## room for the title bar); on a smaller screen the biggest 16:9 size that fits.
static func wide_window_size(usable: Vector2i) -> Vector2i:
	return _window_from(WIDE_WINDOW_SIZES, usable, Vector2i(16, 9))


## Window size for F11 in mode m (1–4): modes 1/2 wide_window_size(); mode 3 the largest of DECK_WINDOW_SIZES
## (16:10), mode 4 of SMALL_WIDE_WINDOW_SIZES (16:9) that fits (title bar room SMALL_DECORATION_ALLOWANCE), else the
## biggest size of that aspect that fits.
static func mode_window_size(m: int, usable: Vector2i) -> Vector2i:
	match m:
		Mode.FULLSCREEN_DECK:
			return _window_from(DECK_WINDOW_SIZES, usable, Vector2i(16, 10), SMALL_DECORATION_ALLOWANCE)
		Mode.FULLSCREEN_720:
			return _window_from(SMALL_WIDE_WINDOW_SIZES, usable, Vector2i(16, 9), SMALL_DECORATION_ALLOWANCE)
	return wide_window_size(usable)


static func _window_from(sizes: Array[Vector2i], usable: Vector2i, aspect: Vector2i,
		allowance: int = DECORATION_ALLOWANCE) -> Vector2i:
	for s in sizes:
		if s.x <= usable.x and s.y + allowance <= usable.y:
			return s
	return fit_aspect(usable, aspect)


## Window size when the classic mode is entered from a 16:9 mode: 1280×960, or the biggest 4:3 size that fits.
static func classic_window_size(usable: Vector2i) -> Vector2i:
	if CLASSIC_WINDOW.x <= usable.x and CLASSIC_WINDOW.y + DECORATION_ALLOWANCE <= usable.y:
		return CLASSIC_WINDOW
	return fit_aspect(usable, Vector2i(4, 3))


## Largest size with the given aspect that fits `usable` (minus the title bar allowance), at least 640 wide.
static func fit_aspect(usable: Vector2i, aspect: Vector2i) -> Vector2i:
	var h := maxi(usable.y - DECORATION_ALLOWANCE, 1)
	var w := mini(usable.x, h * aspect.x / aspect.y)
	w = maxi(w, 640)
	return Vector2i(w, w * aspect.y / aspect.x)


## Applies window mode, canvas size and render resolution for the current mode, then emits `changed`.
func apply() -> void:
	apply_canvas()
	apply_window()
	changed.emit()


## Root window canvas of the current mode (see canvas_config). Safe headless and in tests.
func apply_canvas() -> void:
	var root := get_tree().root if is_inside_tree() else (Engine.get_main_loop() as SceneTree).root
	var cfg := canvas_config(mode())
	root.content_scale_mode = cfg["content_scale_mode"]
	root.content_scale_aspect = cfg["content_scale_aspect"]
	root.content_scale_size = cfg["content_scale_size"]
	root.global_canvas_transform = cfg["global_canvas_transform"]
	root.oversampling_override = cfg["oversampling_override"]


## Window mode / size of the current mode (not headless). Mode 0: fullscreen = Settings.fullscreen, otherwise a
## window (1280×960 when coming from a 16:9 mode, else the size the player left it at). The very first classic
## window of a run is fitted to the screen too when the project's 1280×960 does not fit (classic_window_size, e.g. a
## 1280×800 Steam Deck screen at the first start); on a big enough screen it is left exactly as Godot opened it. Modes 1–4: fullscreen,
## or a window of the mode's aspect after F11 (mode_window_size, centred). Uses the root Window node (mode / size /
## position), never DisplayServer directly: the node resizes its viewport itself (DisplayServer.window_set_size
## alone leaves the root viewport at the old size on X11).
func apply_window() -> void:
	var kind := 1 if is_wide() else 0
	var first_classic := _window_kind == -1 and kind == 0 and not Settings.fullscreen
	if (_window_kind == 1 and kind == 0) or first_classic:
		_classic_resize_pending = true
	_window_kind = kind
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var win := get_tree().root
	var want_full := (not wide_windowed) if kind == 1 else Settings.fullscreen
	var target := Window.MODE_FULLSCREEN if want_full else Window.MODE_WINDOWED
	if win.mode != target:
		win.mode = target
	_set_pointer(want_full)
	if want_full or (kind == 0 and not _classic_resize_pending):
		return
	_classic_resize_pending = false
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	if first_classic and win.size.x <= usable.size.x and win.size.y + DECORATION_ALLOWANCE <= usable.size.y:
		return   # the first window fits: keep Godot's own size and placement (unchanged behaviour)
	var sz := mode_window_size(mode(), usable.size) if kind == 1 else classic_window_size(usable.size)
	_set_window_rect(Rect2i(usable.position + (usable.size - sz) / 2, sz))


## Sets the window rectangle now and once more two frames later: some window managers restore the old size
## asynchronously when a window leaves fullscreen.
func _set_window_rect(r: Rect2i) -> void:
	var win := get_tree().root
	win.size = r.size
	win.position = r.position
	await get_tree().process_frame
	await get_tree().process_frame
	if win.mode == Window.MODE_WINDOWED and win.size != r.size:
		win.size = r.size
		win.position = r.position


## Mouse pointer for a window state: the game is played without the mouse, so the pointer is hidden while the
## window is fullscreen (the normal presentation of the 16:9 modes, and classic F11 fullscreen) and visible in a
## window (to move or resize it). Mouse buttons still count as input (attract mode).
static func pointer_mode(fullscreen: bool) -> Input.MouseMode:
	return Input.MOUSE_MODE_HIDDEN if fullscreen else Input.MOUSE_MODE_VISIBLE


## Pointer for the window's actual mode (connected to the root's size_changed, so a window manager that changes the
## window mode itself is followed too). Nothing headless.
func update_pointer() -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var m := get_tree().root.mode
	_set_pointer(m == Window.MODE_FULLSCREEN or m == Window.MODE_EXCLUSIVE_FULLSCREEN)


func _set_pointer(fullscreen: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := pointer_mode(fullscreen)
	if Input.mouse_mode != want:
		Input.mouse_mode = want


# --- Monitor hints (first-start screen, title DISPLAY line) ----------------------------------------
## Size of the monitor the game window is on; Vector2i.ZERO when unknown (headless). screen_override wins.
func screen_size() -> Vector2i:
	if screen_override != Vector2i.ZERO:
		return screen_override
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return Vector2i.ZERO
	return DisplayServer.screen_get_size(get_tree().root.current_screen)


## The 16:9 mode that suits a monitor: 2560×1440 when the monitor has at least that many pixels (shown 1:1 or
## scaled up the least), else 1920×1080 (on a smaller monitor 1440p would only be scaled down: more GPU work, no
## gain). -1 for an unknown monitor. Godot cannot change the monitor's video mode, so this is only a hint.
static func best_wide_mode(screen: Vector2i) -> int:
	if screen.x <= 0 or screen.y <= 0:
		return -1
	var big: Vector2i = RENDER_SIZE[Mode.FULLSCREEN_1440]
	return Mode.FULLSCREEN_1440 if screen.x >= big.x and screen.y >= big.y else Mode.FULLSCREEN_1080


## The mode that suits a monitor best (BEST FIT badge, title note): a 1280×800 screen (Steam Deck) → mode 3, a
## 1280×720 screen → mode 4, otherwise best_wide_mode(). -1 for an unknown monitor.
static func best_mode(screen: Vector2i) -> int:
	if screen == RENDER_SIZE[Mode.FULLSCREEN_DECK]:
		return Mode.FULLSCREEN_DECK
	if screen == RENDER_SIZE[Mode.FULLSCREEN_720]:
		return Mode.FULLSCREEN_720
	return best_wide_mode(screen)


## True for a monitor that is not 16:9 (the 16:9 modes show black bars there, aspect keep). False if unknown.
static func letterboxed_on(screen: Vector2i) -> bool:
	if screen.x <= 0 or screen.y <= 0:
		return false
	return absf(float(screen.x) / float(screen.y) / (16.0 / 9.0) - 1.0) > ASPECT_TOLERANCE


## True for a 16:10 monitor (1280×800, 1920×1200, 2560×1600, 1440×900 …): the 16:10 mode fills it without bars.
static func is_16_10(screen: Vector2i) -> bool:
	if screen.x <= 0 or screen.y <= 0:
		return false
	return absf(float(screen.x) / float(screen.y) / 1.6 - 1.0) <= ASPECT_TOLERANCE


## "1920×1080" (the × as in the mode names).
static func size_text(s: Vector2i) -> String:
	return "%d×%d" % [s.x, s.y]


## How a fullscreen mode's picture fits the monitor: "best fit for your W×H screen" (best_mode), else "scaled down
## to / scaled up to your W×H screen". "" for the classic window or an unknown monitor.
static func fit_note(m: int, screen: Vector2i) -> String:
	var best := best_mode(screen)
	if not is_wide_mode(m) or best < 0:
		return ""
	if m == best:
		return "best fit for your %s screen" % size_text(screen)
	var r: Vector2i = RENDER_SIZE[m]
	var k := minf(float(screen.x) / float(r.x), float(screen.y) / float(r.y))   # scale of the fullscreen picture
	return ("scaled down to your %s screen" if k < 1.0 else "scaled up to your %s screen") % size_text(screen)


## F11: mode 0 toggles Settings.fullscreen (persisted, as before); modes 1–4 toggle fullscreen ↔ a window of the
## mode's aspect.
func toggle_fullscreen() -> void:
	if is_wide():
		wide_windowed = not wide_windowed
	else:
		Settings.set_fullscreen(not Settings.fullscreen)
	apply_window()


## Stores a new mode (title menu / first-start screen) and applies it at once. A forced --display mode ends here
## (the player's choice counts from now on). Returns true if the mode changed.
func choose(m: int) -> bool:
	m = clampi(m, 0, MODE_COUNT - 1)
	var before := mode()
	forced_mode = -1
	Settings.set_display_mode(m)
	if m == before:
		return false
	wide_windowed = false
	apply()
	return true
