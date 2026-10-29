extends ScreenBase
## First-start display choice (client request, widescreen round; docs/SPEC.md §11): shown before the title while
## Settings.display_chosen is false (old settings files included, so it appears once), or with --first-start.
## Five options (Steam Deck round: + 1280×800 16:10 and 1280×720 16:9) with the exact Display.MODE_NAMES and a
## one-line explanation each (Display.MODE_INFO), as compact cards that fit every canvas (960 / 1152 / 1280 × 720).
## Up/down (also left/right; keys, D-pad, stick – controlled repeat, wrapping) selects; Enter / Space / A / X / Y /
## Start confirms: Display.choose() applies and stores the mode, display_chosen is set → finished("confirm") and
## Main opens the title on the new canvas. Escape quits the game like on the title (nothing is stored, so the
## choice is offered again next time); controller B is ignored like on the title. The choice can be changed later
## in the title menu (DISPLAY). Release guard: Main calls InputRouter.require_release() when the screen opens.
## Monitor hint (Godot cannot change the monitor's resolution, the 16:9 modes are scaled to it): the line "Your
## screen: W×H" under the cards (plus a note about black bars on a monitor that is not 16:9) and a BEST FIT badge on
## the card that suits it (Display.best_mode: 1280×800 → Steam Deck, 1280×720 → 1280×720, else the 16:9 mode of
## Display.best_wide_mode). The line also says which modes get black bars: on a 16:9 screen the 16:10 mode, on a
## 16:10 screen the 16:9 modes (the 16:10 mode fills it), on any other screen all fullscreen modes.
## Preselection: the current mode (classic on a first start) – except on a 1280×800 / 1280×720 screen (best fit =
## a small mode 3 / 4, e.g. the Steam Deck), where the classic 1280×960 window does not even fit: there the
## best-fit card is preselected on a first start, so A / Enter at once picks it.
## Nothing of the monitor hint is shown when the monitor size is unknown.
## setup args: {"select": <mode>} (optional initial selection; default: the current mode).

const HEADING := "CHOOSE YOUR DISPLAY"
const FOOTNOTE := "You can change this any time in the title menu (DISPLAY)."
const LOGO_W := 360.0
const LOGO_Y := 68.0
const HEADING_Y := 158.0
const HEADING_SIZE := 24
const CARD_W := 700.0
const CARD_H := 66.0
const CARD_GAP := 12.0          ## > BADGE_H / 2: a badge on a card's top border stays clear of the card above
const CARD_Y := 178.0           ## top of the first card
const TEXT_X := 128.0           ## name / explanation start, from the card's left edge
const NAME_Y := 30.0            ## name baseline, from the card's top
const INFO_Y := 54.0            ## explanation baseline, from the card's top
const NAME_SIZE := 20
const INFO_SIZE := 16
const ICON_H := 36.0
const SCREEN_Y := 596.0         ## "Your screen: W×H" (monitor hint)
const FOOTNOTE_Y := 623.0
const HINT_Y := 670.0
const BADGE := "BEST FIT FOR YOUR SCREEN"
const BADGE_SIZE := 11          ## badge and icon captions; lifted in the small modes (badge_size())
const BADGE_H := 20.0

var _sel := 0
var _screen := Vector2i.ZERO   ## monitor size (Display.screen_size(); ZERO = unknown)
var _best := -1                ## Display.best_mode(_screen): the card with the badge (-1 = none)


func _enter() -> void:
	AudioManager.play_title_music()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # logo.png is imported with mipmaps
	_sel = clampi(int(args.get("select", Display.mode())), 0, Display.MODE_COUNT - 1)
	_screen = Display.screen_size()
	_best = Display.best_mode(_screen)
	if not args.has("select") and not Settings.display_chosen and Display.is_small_mode(_best):
		_sel = _best


func _star_velocity() -> Vector2:
	return Vector2(-10, 2)


## Currently highlighted mode (Display.Mode).
func selected() -> int:
	return _sel


## Mode whose card carries the BEST FIT badge (-1: monitor unknown, no badge).
func best_mode() -> int:
	return _best


## Monitor line under the cards: "Your screen: W×H" plus which fullscreen modes get black bars there; "" if unknown.
static func screen_line(screen: Vector2i) -> String:
	if Display.best_wide_mode(screen) < 0:
		return ""
	var s := "Your screen: %s" % Display.size_text(screen)
	if not Display.letterboxed_on(screen):
		s += "  ·  16:9, so the 16:10 mode gets black bars at the sides"
	elif Display.is_16_10(screen):
		s += "  ·  16:10, so the 16:9 modes get black bars, the 16:10 mode fills it"
	else:
		s += "  ·  not 16:9 or 16:10, so the fullscreen modes get black bars"
	return s


## Font size of the BEST FIT badge and the icon captions: BADGE_SIZE, lifted in the small modes (UiKit.label_size).
static func badge_size() -> int:
	return UiKit.label_size(BADGE_SIZE)


## Badge of the best-fitting 16:9 card: on the card's top border, right-aligned.
static func badge_rect(card: Rect2) -> Rect2:
	var w := UiKit.text_width(Assets.font_body_bold, BADGE, badge_size()) + 22.0
	return Rect2(card.end.x - 24.0 - w, card.position.y - BADGE_H * 0.5, w, BADGE_H)


func _tick(_delta: float) -> void:
	var d := InputRouter.menu_direction()
	var step := d.y if d.y != 0 else d.x
	if step != 0:
		_sel = posmod(_sel + step, Display.MODE_COUNT)
		sfx("menu_move")
	if InputRouter.confirm_pressed(true):
		_confirm()
	elif InputRouter.just_pressed(InputRouter.B.ESCAPE):
		sfx("menu_back")
		finish("quit")


func _confirm() -> void:
	sfx("menu_confirm")
	Display.choose(_sel)
	Settings.set_display_chosen(true)
	finish("confirm", {"mode": _sel})


## Card of option i (content coordinates, centred on the canvas).
static func card_rect(i: int) -> Rect2:
	return Rect2(CX - CARD_W * 0.5, CARD_Y + i * (CARD_H + CARD_GAP), CARD_W, CARD_H)


# --- Drawing -------------------------------------------------------------------------------------
func _draw() -> void:
	_draw_logo()
	draw_title(HEADING, HEADING_Y, HEADING_SIZE)
	for i in Display.MODE_COUNT:
		_draw_card(i)
	var line := screen_line(_screen)
	if line != "":
		UiKit.text(self, Assets.font_body, Vector2(CX, SCREEN_Y), line, 15, Color(UiKit.COLOR_TEXT, 0.82 * ramp(0.3, 0.4)),
			HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.text(self, Assets.font_body, Vector2(CX, FOOTNOTE_Y), FOOTNOTE, 15, UiKit.COLOR_DIM,
		HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.hint_bar(self, Vector2(CX, HINT_Y), [
		[["UD"], "Select"], [["ENTER", "pad:A"], "Confirm"], [["ESC"], "Quit"],
	], 14)


func _draw_logo() -> void:
	var logo := Assets.logo_texture()
	var c := Vector2(CX, LOGO_Y + sin(time * 0.9) * 2.0)
	UiKit.glow_spot(self, c + Vector2(0, 6), Vector2(240, 72), Color(1.0, 0.35, 0.08, 0.11))
	if logo:
		var h := LOGO_W * float(logo.get_height()) / float(logo.get_width())
		draw_texture_rect(logo, Rect2(c - Vector2(LOGO_W, h) * 0.5, Vector2(LOGO_W, h)), false)
	else:
		UiKit.text_glow(self, Assets.font_title_heavy, Vector2(CX, c.y + 16), "PLANET PROTECTOR", 44,
			Color(1.0, 0.78, 0.38), Color(1.0, 0.3, 0.05), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_card(i: int) -> void:
	var r := card_rect(i)
	var selected := i == _sel
	var a := ramp(0.08 + i * 0.05, 0.3)
	if selected:
		var pulse := 0.5 + 0.5 * sin(time * 4.0)
		UiKit.panel_ex(self, r, Color(UiKit.COLOR_HILITE, (0.10 + 0.05 * pulse) * a),
			Color(UiKit.COLOR_HILITE, (0.6 + 0.3 * pulse) * a), 14, 2, Color(UiKit.COLOR_HILITE, 0.22 * a), 14)
		UiKit.triangle(self, Vector2(r.position.x - 18, r.get_center().y), Vector2.RIGHT, 13, Color(UiKit.COLOR_HILITE, a))
		UiKit.triangle(self, Vector2(r.end.x + 18, r.get_center().y), Vector2.LEFT, 13, Color(UiKit.COLOR_HILITE, a))
	else:
		UiKit.panel_ex(self, r, Color(UiKit.COLOR_PANEL, 0.62 * a), Color(UiKit.COLOR_BORDER, 0.22 * a), 14, 1)
	var col := UiKit.COLOR_TEXT if selected else UiKit.COLOR_DIM
	# Icon (plus its render-height caption in the fullscreen modes) vertically centred in the card.
	var icon_c := Vector2(r.position.x + TEXT_X * 0.5 + 4.0, r.get_center().y - (7.0 if Display.is_wide_mode(i) else 0.0))
	_draw_mode_icon(icon_c, i, Color(UiKit.COLOR_ACCENT if selected else UiKit.COLOR_DIM, a))
	UiKit.text(self, Assets.font_title, Vector2(r.position.x + TEXT_X, r.position.y + NAME_Y), Display.mode_name(i),
		NAME_SIZE, Color(col, a))
	UiKit.text(self, Assets.font_body, Vector2(r.position.x + TEXT_X, r.position.y + INFO_Y), String(Display.MODE_INFO[i]),
		INFO_SIZE, Color(UiKit.COLOR_DIM.lerp(UiKit.COLOR_TEXT, 0.3 if selected else 0.0), a))
	if i == _best:
		_draw_badge(r, a)


func _draw_badge(card: Rect2, a: float) -> void:
	var br := badge_rect(card)
	UiKit.panel_ex(self, br, Color(0.09, 0.06, 0.015, 0.96 * a), Color(UiKit.COLOR_GOLD, 0.8 * a), 10, 1)
	var font := Assets.font_body_bold
	var fs := badge_size()
	UiKit.text(self, font, Vector2(br.get_center().x, UiKit.baseline_for(font, fs, br.get_center().y)), BADGE,
		fs, Color(UiKit.COLOR_GOLD, a), HORIZONTAL_ALIGNMENT_CENTER)


## Small screen icon in the proportions of the mode's playfield (4:3, 16:10 or 16:9) with ground, ship and
## three enemy dots; the fullscreen icons carry their render height (1080p / 1440p / 800p / 720p).
func _draw_mode_icon(c: Vector2, m: int, col: Color) -> void:
	var lsz := Vector2(Display.logical_size_of(m))
	var h := ICON_H
	var w := h * lsz.x / lsz.y
	var r := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
	UiKit.panel_ex(self, r, Color(0.0, 0.02, 0.06, 0.8 * col.a), col, 5, 2)
	var gy := r.position.y + h * 0.82
	draw_line(Vector2(r.position.x + 3, gy), Vector2(r.end.x - 3, gy), Color(col, col.a * 0.6), 1.5)
	UiKit.triangle(self, Vector2(c.x, gy - 4.0), Vector2.UP, 7.0, col)
	for k in 3:
		var ex := r.position.x + w * (0.25 + 0.25 * k)
		var ey := r.position.y + h * (0.25 + 0.15 * k)
		draw_circle(Vector2(ex, ey), 2.2, Color(col, col.a * 0.85), true, -1.0, true)
	if Display.is_wide_mode(m):
		var label := "%dp" % int(Display.RENDER_SIZE[m].y)
		UiKit.text(self, Assets.font_body_bold, Vector2(c.x, r.end.y + 14.0), label, badge_size(), Color(col, col.a * 0.9),
			HORIZONTAL_ALIGNMENT_CENTER)
