class_name UiKit
extends RefCounted
## Text/panel drawing helpers for screens and HUD (docs/SPEC.md §15, fonts from `Assets`).
## All functions are static and draw onto the given CanvasItem inside its _draw (or draw signal).
## Positions are in game pixels; for text `pos.y` is the BASELINE and `pos.x` the anchor given by `align`.

const COLOR_TEXT := Color(0.92, 0.95, 1.0)
const COLOR_DIM := Color(0.6, 0.66, 0.78)
const COLOR_ACCENT := Color(1.0, 0.62, 0.18)
const COLOR_HILITE := Color(0.45, 0.85, 1.0)
const COLOR_FAINT := Color(0.40, 0.45, 0.57)
const COLOR_GOOD := Color(0.45, 1.0, 0.58)
const COLOR_GOLD := Color(1.0, 0.84, 0.36)
const COLOR_DANGER := Color(1.0, 0.33, 0.25)
const COLOR_PANEL := Color(0.025, 0.035, 0.085)
const COLOR_BORDER := Color(0.4, 0.6, 1.0)
## Segments of a volume bar (one per 10 %).
const VOLUME_SEGMENTS := 10
## Player colours of a two-player match (SPEC §19.2): PLAYER 1 cyan, PLAYER 2 pink.
const COLOR_P1 := Color(0.35, 0.85, 1.0)
const COLOR_P2 := Color(1.0, 0.47, 0.74)


## Colour of player k (0 = PLAYER 1, 1 = PLAYER 2).
static func player_color(k: int) -> Color:
	return COLOR_P2 if k == 1 else COLOR_P1

static var _styles := {}


# --- Text ----------------------------------------------------------------------------------------
## Draws text; align: HORIZONTAL_ALIGNMENT_LEFT/CENTER/RIGHT relative to pos.x; pos.y is the baseline.
static func text(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, color: Color = COLOR_TEXT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var p := pos
	if width < 0.0:
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if align == HORIZONTAL_ALIGNMENT_CENTER:
			p.x -= w * 0.5
		elif align == HORIZONTAL_ALIGNMENT_RIGHT:
			p.x -= w
		ci.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	else:
		ci.draw_string(font, p, s, align, width, size, color)


static func text_width(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Left x of a string drawn with the given anchor/alignment.
static func aligned_x(font: Font, s: String, size: int, x: float, align: HorizontalAlignment) -> float:
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		return x - text_width(font, s, size) * 0.5
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		return x - text_width(font, s, size)
	return x


## Baseline that vertically centres capital letters on `center_y`.
static func baseline_for(font: Font, size: int, center_y: float) -> float:
	return center_y + (font.get_ascent(size) - font.get_descent(size)) * 0.36


## Largest font size <= size so that the string fits into max_width.
static func fit_size(font: Font, s: String, size: int, max_width: float, min_size: int = 8) -> int:
	var sz := size
	while sz > min_size and text_width(font, s, sz) > max_width:
		sz -= 1
	return sz


## Text with an outline (good readability over bright backgrounds).
static func text_outlined(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, color: Color,
		outline: Color = Color(0, 0, 0, 0.8), outline_size: int = 4,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var p := Vector2(aligned_x(font, s, size, pos.x, align), pos.y)
	ci.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_size, outline)
	ci.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Text with a soft glow: a wide blurred light spot behind it plus a thin luminous outline.
static func text_glow(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, color: Color = COLOR_TEXT,
		glow: Color = COLOR_HILITE, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
		strength: float = 1.0) -> void:
	var w := text_width(font, s, size)
	var x := aligned_x(font, s, size, pos.x, align)
	var cy := pos.y - size * 0.36
	var g := glow
	g.a = 0.16 * strength
	glow_spot(ci, Vector2(x + w * 0.5, cy), Vector2(w * 0.62 + size * 1.2, size * 1.5), g)
	var p := Vector2(x, pos.y)
	var o := glow
	o.a = 0.10 * strength
	ci.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(4, int(size / 5.0)), o)
	o.a = 0.22 * strength
	ci.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(2, int(size / 12.0)), o)
	ci.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Letter-spaced text (e.g. small captions in capitals).
static func text_spaced(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, spacing: float,
		color: Color = COLOR_TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var total := spaced_width(font, s, size, spacing)
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= total * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= total
	for ch in s:
		ci.draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		x += text_width(font, ch, size) + spacing


static func spaced_width(font: Font, s: String, size: int, spacing: float) -> float:
	var total := 0.0
	for ch in s:
		total += text_width(font, ch, size) + spacing
	return maxf(total - spacing, 0.0)


## Greedy word wrap. Explicit "\n" starts a new paragraph line.
static func wrap_lines(font: Font, s: String, size: int, max_width: float) -> PackedStringArray:
	var out := PackedStringArray()
	for para in s.split("\n"):
		var line := ""
		for word in para.split(" ", false):
			var cand := word if line == "" else line + " " + word
			if line != "" and text_width(font, cand, size) > max_width:
				out.append(line)
				line = word
			else:
				line = cand
		out.append(line)
	return out


## Word wrap with balanced line lengths (same number of lines as greedy wrap, but as even as possible).
static func wrap_balanced(font: Font, s: String, size: int, max_width: float) -> PackedStringArray:
	var base := wrap_lines(font, s, size, max_width)
	if base.size() <= 1:
		return base
	var lo := max_width * 0.3
	var hi := max_width
	for i in 14:
		var mid := (lo + hi) * 0.5
		if wrap_lines(font, s, size, mid).size() <= base.size():
			hi = mid
		else:
			lo = mid
	return wrap_lines(font, s, size, hi)


## Draws wrapped text; pos.x is the anchor for `align`, pos.y the first baseline. Returns the block height.
static func text_wrapped(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, max_width: float,
		line_height: float = -1.0, color: Color = COLOR_TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
		balanced: bool = false) -> float:
	var lh := line_height if line_height > 0.0 else size * 1.35
	var lines := wrap_balanced(font, s, size, max_width) if balanced else wrap_lines(font, s, size, max_width)
	for i in lines.size():
		text(ci, font, pos + Vector2(0, lh * i), lines[i], size, color, align)
	return lh * lines.size()


# --- Panels & shapes -----------------------------------------------------------------------------
## Standard translucent panel with rounded corners, thin border and a soft outer glow.
static func panel(ci: CanvasItem, rect: Rect2, alpha: float = 0.6) -> void:
	var fill := COLOR_PANEL
	fill.a = alpha
	var border := COLOR_BORDER
	border.a = 0.35 * alpha / 0.6
	var shadow := Color(0.15, 0.3, 0.7, 0.10 * alpha / 0.6)
	ci.draw_style_box(_style(fill, border, 12, 1, shadow, 14), rect)


## Panel with explicit colours. glow: colour of a soft outer glow (alpha 0 = none).
static func panel_ex(ci: CanvasItem, rect: Rect2, fill: Color, border: Color, radius: int = 12,
		border_width: int = 1, glow: Color = Color(0, 0, 0, 0), glow_size: int = 14) -> void:
	ci.draw_style_box(_style(fill, border, radius, border_width, glow, glow_size if glow.a > 0.0 else 0), rect)


static func _style(fill: Color, border: Color, radius: int, border_w: int, shadow: Color, shadow_size: int) -> StyleBoxFlat:
	var key := "%x|%x|%d|%d|%x|%d" % [fill.to_rgba32(), border.to_rgba32(), radius, border_w,
		shadow.to_rgba32(), shadow_size]
	var sb: StyleBoxFlat = _styles.get(key)
	if sb == null:
		if _styles.size() > 600:
			_styles.clear()
		sb = StyleBoxFlat.new()
		sb.bg_color = fill
		sb.border_color = border
		sb.set_border_width_all(border_w if border.a > 0.0 else 0)
		sb.set_corner_radius_all(radius)
		sb.corner_detail = 10
		sb.anti_aliasing = true
		sb.shadow_color = shadow
		sb.shadow_size = shadow_size
		_styles[key] = sb
	return sb


## Dark rounded backing ("pill") that keeps small text readable over busy art (planet clouds, rings).
## alpha 0…1 scales the whole backing (use it to fade it in together with its text).
static func backing(ci: CanvasItem, rect: Rect2, alpha: float = 1.0) -> void:
	if alpha <= 0.0:
		return
	var a := clampf(alpha, 0.0, 1.0)
	var fill := COLOR_PANEL
	fill.a = 0.84 * a
	var border := COLOR_BORDER
	border.a = 0.24 * a
	ci.draw_style_box(_style(fill, border, int(rect.size.y * 0.5), 1, Color(0, 0, 0, 0.5 * a), 12), rect)


## Rectangle of a backing around a single text line (pos/align as in `text`), with padding.
static func text_backing_rect(font: Font, pos: Vector2, s: String, size: int,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, pad: Vector2 = Vector2(-1, -1)) -> Rect2:
	var p := pad if pad.x >= 0.0 else Vector2(size * 1.2, size * 0.6)
	var w := text_width(font, s, size)
	var x := aligned_x(font, s, size, pos.x, align)
	var cy := pos.y - size * 0.36
	var h := size * 1.0
	return Rect2(x - p.x, cy - h * 0.5 - p.y, w + p.x * 2.0, h + p.y * 2.0)


## Soft radial light spot (uses Assets.soft_circle()); radius per axis.
static func glow_spot(ci: CanvasItem, center: Vector2, radius: Vector2, color: Color) -> void:
	ci.draw_texture_rect(Assets.soft_circle(), Rect2(center - radius, radius * 2.0), false, color)


## Horizontal line that fades out towards both ends.
static func divider(ci: CanvasItem, center: Vector2, width: float, color: Color = COLOR_HILITE,
		thickness: float = 1.5) -> void:
	var c0 := color
	c0.a = 0.0
	var h := thickness * 0.5
	var l := center.x - width * 0.5
	var r := center.x + width * 0.5
	var m := center.x
	ci.draw_polygon(PackedVector2Array([Vector2(l, center.y - h), Vector2(m, center.y - h), Vector2(m, center.y + h),
		Vector2(l, center.y + h)]), PackedColorArray([c0, color, color, c0]))
	ci.draw_polygon(PackedVector2Array([Vector2(m, center.y - h), Vector2(r, center.y - h), Vector2(r, center.y + h),
		Vector2(m, center.y + h)]), PackedColorArray([color, c0, c0, color]))


## Arrow from → to with a filled triangular head.
static func arrow(ci: CanvasItem, from: Vector2, to: Vector2, color: Color, width: float = 3.0,
		head: float = 12.0) -> void:
	var d := (to - from)
	if d.length() < 0.001:
		return
	var n := d.normalized()
	var base := to - n * head
	ci.draw_line(from, base + n * 1.0, color, width, true)
	var side := Vector2(-n.y, n.x) * head * 0.6
	ci.draw_colored_polygon(PackedVector2Array([to, base + side, base - side]), color)


## Small filled triangle pointing in `dir` (Vector2.LEFT/RIGHT/UP/DOWN), centred at `center`.
static func triangle(ci: CanvasItem, center: Vector2, dir: Vector2, size: float, color: Color) -> void:
	var n := dir.normalized()
	var side := Vector2(-n.y, n.x)
	var tip := center + n * size * 0.55
	var b := center - n * size * 0.45
	ci.draw_colored_polygon(PackedVector2Array([tip, b + side * size * 0.55, b - side * size * 0.55]), color)


## Simple padlock icon (used for "locked" states).
static func lock_icon(ci: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	var body := Rect2(center + Vector2(-size * 0.5, -size * 0.1), Vector2(size, size * 0.7))
	ci.draw_arc(center + Vector2(0, -size * 0.12), size * 0.3, PI, TAU, 16, color, maxf(2.0, size * 0.13), true)
	panel_ex(ci, body, color, Color(0, 0, 0, 0), int(size * 0.14), 0)
	ci.draw_circle(center + Vector2(0, size * 0.2), size * 0.09, Color(0, 0, 0, 0.75))


# --- Menu items ----------------------------------------------------------------------------------
## One menu row centred at `center` (y = vertical centre). value != "" renders "LABEL   < VALUE >".
## `t` is a running time for the subtle pulse of the selection bar. value_color (alpha > 0) replaces the accent
## colour of the value (e.g. a pending, not yet applied choice).
static func menu_item(ci: CanvasItem, center: Vector2, label: String, value: String, selected: bool,
		t: float = 0.0, width: float = 440.0, size: int = 22, value_color: Color = Color(0, 0, 0, 0)) -> void:
	var rect := menu_row_rect(center, width, size)
	var font := Assets.font_title
	if selected:
		_menu_row_highlight(ci, rect, t)
	var col := COLOR_TEXT if selected else COLOR_DIM
	var by := baseline_for(font, size, center.y)
	if value == "":
		text(ci, font, Vector2(center.x, by), label, size, col, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var pad := 30.0
	text(ci, font, Vector2(rect.position.x + pad, by), label, size, col)
	var vcol := COLOR_ACCENT if selected else Color(COLOR_ACCENT, 0.75)
	if value_color.a > 0.0:
		vcol = value_color
	var vx := rect.end.x - pad
	if selected:
		triangle(ci, Vector2(vx - 4, center.y), Vector2.RIGHT, 10, vcol)
		vx -= 18.0
	text(ci, font, Vector2(vx, by), value, size, vcol, HORIZONTAL_ALIGNMENT_RIGHT)
	if selected:
		var vw := text_width(font, value, size)
		triangle(ci, Vector2(vx - vw - 14, center.y), Vector2.LEFT, 10, vcol)


## Rectangle of a menu row (menu_item / menu_item_volume) centred at `center`.
static func menu_row_rect(center: Vector2, width: float, size: int) -> Rect2:
	var h := size * 1.9
	return Rect2(center.x - width * 0.5, center.y - h * 0.5, width, h)


## Pulsing selection pill of a menu row plus the two pointers outside it.
static func _menu_row_highlight(ci: CanvasItem, rect: Rect2, t: float) -> void:
	var h := rect.size.y
	var cy := rect.get_center().y
	var pulse := 0.5 + 0.5 * sin(t * 4.0)
	var fill := COLOR_HILITE
	fill.a = 0.10 + 0.05 * pulse
	var border := COLOR_HILITE
	border.a = 0.55 + 0.25 * pulse
	var glow := COLOR_HILITE
	glow.a = 0.18
	panel_ex(ci, rect, fill, border, int(h * 0.5), 1, glow, 12)
	triangle(ci, Vector2(rect.position.x - 16, cy), Vector2.RIGHT, 12, COLOR_HILITE)
	triangle(ci, Vector2(rect.end.x + 16, cy), Vector2.LEFT, 12, COLOR_HILITE)


## Volume row "LABEL   ◀ ▁▂▃▄▅▆▇ 70% ▶" in the look of menu_item: a VOLUME_SEGMENTS bar (volume_bar) and the
## percentage in a fixed column, so nothing moves when the row is selected or the value changes.
## enabled = false (the matching ON/OFF option is OFF) draws bar and value dimmed.
static func menu_item_volume(ci: CanvasItem, center: Vector2, label: String, percent: int, selected: bool,
		t: float = 0.0, width: float = 440.0, size: int = 22, enabled: bool = true) -> void:
	var rect := menu_row_rect(center, width, size)
	var font := Assets.font_title
	if selected:
		_menu_row_highlight(ci, rect, t)
	var col := COLOR_TEXT if selected else COLOR_DIM
	var by := baseline_for(font, size, center.y)
	text(ci, font, Vector2(rect.position.x + 30.0, by), label, size, col)
	var vcol := COLOR_ACCENT if selected else Color(COLOR_ACCENT, 0.75)
	if not enabled:
		vcol = COLOR_FAINT
	# Value column exactly as in menu_item (right-aligned, moved left by the pointer when selected).
	var vx := rect.end.x - 30.0
	if selected:
		triangle(ci, Vector2(vx - 4, center.y), Vector2.RIGHT, 10, vcol)
		vx -= 18.0
	text(ci, font, Vector2(vx, by), "%d%%" % percent, size, vcol, HORIZONTAL_ALIGNMENT_RIGHT)
	var bar := volume_bar_rect(Vector2(vx - text_width(font, "100%", size) - size * 0.6, center.y), size)
	volume_bar(ci, bar, percent, vcol, enabled)
	if selected:
		triangle(ci, Vector2(bar.position.x - 14, center.y), Vector2.LEFT, 10, vcol)


## Rectangle of a volume bar whose right edge is at right_mid.x, vertically centred on right_mid.y; scaled
## with the font size of its row.
static func volume_bar_rect(right_mid: Vector2, size: int = 20) -> Rect2:
	var seg := maxf(roundf(size * 0.42), 4.0)
	var gap := maxf(roundf(size * 0.16), 2.0)
	var w := seg * VOLUME_SEGMENTS + gap * (VOLUME_SEGMENTS - 1)
	var h := roundf(size * 0.95)
	return Rect2(right_mid.x - w, right_mid.y - h * 0.5, w, h)


## 10-segment volume bar (one segment per 10 %) in `rect`: segments rise in height from left to right like a
## volume ramp, lit ones in `color` (brighter towards the top), unlit ones as dim outlines.
## enabled = false: everything faint (the sound is switched off).
static func volume_bar(ci: CanvasItem, rect: Rect2, percent: int, color: Color = COLOR_ACCENT,
		enabled: bool = true) -> void:
	var n := VOLUME_SEGMENTS
	var gap := maxf(roundf(rect.size.y * 0.17), 2.0)
	var seg := (rect.size.x - gap * (n - 1)) / n
	var lit := clampi(roundi(percent / (100.0 / n)), 0, n)
	for i in n:
		var hf := lerpf(0.42, 1.0, float(i) / (n - 1))
		var h := roundf(rect.size.y * hf)
		var r := Rect2(rect.position.x + i * (seg + gap), rect.end.y - h, seg, h)
		if i < lit:
			var c := color.lerp(Color(1.0, 0.93, 0.75, color.a), 0.35 * float(i) / (n - 1)) if enabled else color
			ci.draw_rect(r, c)
		else:
			var c := Color(COLOR_DIM, 0.16 if enabled else 0.1)
			ci.draw_rect(r, c)
			ci.draw_rect(r, Color(COLOR_DIM, 0.38 if enabled else 0.22), false, 1.0)


## Label/value row: label left-aligned at left_x, value right-aligned at right_x (same baseline).
static func stat_row(ci: CanvasItem, left_x: float, right_x: float, baseline: float, label: String, value: String,
		size: int = 20, label_color: Color = COLOR_DIM, value_color: Color = COLOR_TEXT) -> void:
	text(ci, Assets.font_body, Vector2(left_x, baseline), label, size, label_color)
	text(ci, Assets.font_title, Vector2(right_x, baseline), value, size, value_color, HORIZONTAL_ALIGNMENT_RIGHT)


# --- Key / button hint glyphs --------------------------------------------------------------------
## Glyph tokens: "ENTER", "ESC", "SPACE", "BKSP", any short key label, arrows "LEFT"/"RIGHT"/"UP"/"DOWN",
## "LR" (◀▶), "UD" (▲▼), controller "pad:A"/"pad:B"/"pad:X"/"pad:Y" (positional face buttons:
## A bottom, B right, X left, Y top), "pad:START", "pad:BACK", "pad:DPAD".
static func glyph_width(token: String, size: int = 14) -> float:
	var h := size * 1.55
	if token.begins_with("pad:"):
		var k := token.substr(4)
		if k == "START" or k == "BACK":
			return text_width(Assets.font_body_bold, _pad_label(k), label_size(int(size * 0.72))) + size * 1.1
		return h * 1.2
	match token:
		"LEFT", "RIGHT", "UP", "DOWN":
			return h
		"LR", "UD":
			return h * 1.45
	return maxf(text_width(Assets.font_body_bold, _key_label(token), label_size(int(size * 0.8))) + size * 0.9, h)


## Draws a glyph with its left edge at x, vertically centred on cy. Returns its width.
static func glyph(ci: CanvasItem, token: String, x: float, cy: float, size: int = 14,
		color: Color = COLOR_TEXT) -> float:
	var w := glyph_width(token, size)
	var h := size * 1.55
	var rect := Rect2(x, cy - h * 0.5, w, h)
	var fill := Color(color, 0.10)
	var border := Color(color, 0.55)
	if token.begins_with("pad:"):
		var k := token.substr(4)
		match k:
			"A", "B", "X", "Y":
				# Positional face-button diamond (A bottom, B right, X left, Y top): platform neutral.
				var pc := Vector2(x + w * 0.5, cy)
				var r := h * 0.32
				var offs := {"A": Vector2(0, 1), "B": Vector2(1, 0), "X": Vector2(-1, 0), "Y": Vector2(0, -1)}
				for key: String in offs:
					var p: Vector2 = pc + (offs[key] as Vector2) * r
					if key == k:
						ci.draw_circle(p, h * 0.2, color, true, -1.0, true)
					else:
						ci.draw_circle(p, h * 0.12, Color(color, 0.4), true, -1.0, true)
			"DPAD":
				var dc := Vector2(x + w * 0.5, cy)
				var a := h * 0.42
				var t := h * 0.16
				panel_ex(ci, Rect2(dc.x - a, dc.y - t, a * 2, t * 2), Color(color, 0.85), Color(0, 0, 0, 0), 2, 0)
				panel_ex(ci, Rect2(dc.x - t, dc.y - a, t * 2, a * 2), Color(color, 0.85), Color(0, 0, 0, 0), 2, 0)
			_:
				panel_ex(ci, rect, fill, border, int(h * 0.5), 1)
				var fs := label_size(int(size * 0.72))
				text(ci, Assets.font_body_bold, Vector2(x + w * 0.5, baseline_for(Assets.font_body_bold, fs, cy)),
					_pad_label(k), fs, color, HORIZONTAL_ALIGNMENT_CENTER)
		return w
	panel_ex(ci, rect, fill, border, int(size * 0.3), 1)
	var c := rect.get_center()
	var ts := size * 0.62
	match token:
		"LEFT":
			triangle(ci, c, Vector2.LEFT, ts, color)
		"RIGHT":
			triangle(ci, c, Vector2.RIGHT, ts, color)
		"UP":
			triangle(ci, c, Vector2.UP, ts, color)
		"DOWN":
			triangle(ci, c, Vector2.DOWN, ts, color)
		"LR":
			triangle(ci, c - Vector2(ts * 0.62, 0), Vector2.LEFT, ts, color)
			triangle(ci, c + Vector2(ts * 0.62, 0), Vector2.RIGHT, ts, color)
		"UD":
			triangle(ci, c - Vector2(ts * 0.62, 0), Vector2.UP, ts, color)
			triangle(ci, c + Vector2(ts * 0.62, 0), Vector2.DOWN, ts, color)
		_:
			var fs := label_size(int(size * 0.8))
			text(ci, Assets.font_body_bold, Vector2(c.x, baseline_for(Assets.font_body_bold, fs, cy)),
				_key_label(token), fs, color, HORIZONTAL_ALIGNMENT_CENTER)
	return w


## Font size of a tiny caption (key-cap labels, HUD labels): `size`, lifted to Display.min_text_size() in the small
## display modes 3/4 (≥ 11 px on screen, e.g. the Steam Deck's 7" 1280×800 screen); unchanged in modes 0–2.
static func label_size(size: int) -> int:
	return maxi(size, Display.min_text_size())


static func _key_label(token: String) -> String:
	match token:
		"BKSP":
			return "BACKSPACE"
	return token


static func _pad_label(k: String) -> String:
	match k:
		"BACK":
			return "SELECT"
	return k


## Width of one hint item: glyphs separated by "/" followed by its label.
static func hint_width(glyphs: Array, label: String, size: int = 14) -> float:
	var w := 0.0
	for i in glyphs.size():
		w += glyph_width(String(glyphs[i]), size)
		if i < glyphs.size() - 1:
			w += size * 0.9
	return w + size * 0.6 + text_width(Assets.font_body, label, size)


## Total width of a hint bar (see hint_bar).
static func hint_bar_width(items: Array, size: int = 14) -> float:
	var total := 0.0
	for it in items:
		total += hint_width(it[0], it[1], size)
	return total + size * 2.2 * maxf(items.size() - 1, 0)


## Rectangle of the dark backing behind a hint bar (see hint_bar).
static func hint_bar_rect(center: Vector2, items: Array, size: int = 14) -> Rect2:
	var total := hint_bar_width(items, size)
	var h := size * 1.55 + size * 0.9
	return Rect2(center.x - total * 0.5 - size * 1.1, center.y - h * 0.5, total + size * 2.2, h)


## A centred row of hints. items: Array of [glyph_tokens: Array, label: String].
## backing_alpha > 0 draws a dark pill behind the row (for hints over planets or other bright art).
static func hint_bar(ci: CanvasItem, center: Vector2, items: Array, size: int = 14,
		color: Color = COLOR_DIM, backing_alpha: float = 0.0) -> void:
	var gap := size * 2.2
	var total := hint_bar_width(items, size)
	if backing_alpha > 0.0:
		backing(ci, hint_bar_rect(center, items, size), backing_alpha)
	var x := center.x - total * 0.5
	for it in items:
		var glyphs: Array = it[0]
		for i in glyphs.size():
			x += glyph(ci, String(glyphs[i]), x, center.y, size, color)
			if i < glyphs.size() - 1:
				text(ci, Assets.font_body, Vector2(x + size * 0.45, baseline_for(Assets.font_body, size, center.y)), "/",
					size, Color(color, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
				x += size * 0.9
		x += size * 0.6
		text(ci, Assets.font_body, Vector2(x, baseline_for(Assets.font_body, size, center.y)), String(it[1]), size, color)
		x += text_width(Assets.font_body, String(it[1]), size) + gap


# --- Two-player screens (SPEC §19.2) --------------------------------------------------------------
## A player ship sprite (Assets.ship_texture, 80 × 56 game px canvas) drawn `width` px wide, centred at `center`.
static func ship_icon(ci: CanvasItem, ship_id: int, center: Vector2, width: float,
		modulate: Color = Color.WHITE) -> void:
	var sz := Vector2(width, width * 56.0 / 80.0)
	ci.draw_texture_rect(Assets.ship_texture(ship_id), Rect2(center - sz * 0.5, sz), false, modulate)


## Check mark (two strokes), `size` px wide, centred at `center`.
static func check_icon(ci: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	var pts := PackedVector2Array([center + Vector2(-0.42, 0.02) * size, center + Vector2(-0.13, 0.3) * size,
		center + Vector2(0.44, -0.32) * size])
	ci.draw_polyline(pts, color, maxf(2.0, size * 0.15), true)


## "Look away" pictogram: an eye (almond of two lid arcs, iris) crossed out by a slash, `size` px wide.
static func eye_slash_icon(ci: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	var w := maxf(1.5, size * 0.085)
	# Lid arcs through the corners (±size/2, 0) with an opening of 0.36·size: centre offset d, radius r.
	var h := 0.36
	var d := (0.25 - h * h * 0.25) / h
	var r := d + h * 0.5
	var a0 := atan2(-d, 0.5)
	var a1 := atan2(-d, -0.5)
	ci.draw_arc(center + Vector2(0, d) * size, r * size, a1, a0, 20, color, w, true)
	ci.draw_arc(center - Vector2(0, d) * size, r * size, -a0, -a1, 20, color, w, true)
	ci.draw_circle(center, size * 0.12, color, true, -1.0, true)
	var s0 := center + Vector2(-0.4, -0.4) * size
	var s1 := center + Vector2(0.4, 0.4) * size
	ci.draw_line(s0, s1, Color(0, 0, 0, 0.7 * color.a), w * 3.0, true)
	ci.draw_line(s0, s1, color, w * 1.3, true)


## Rectangle of a look_away_banner (pill around icon + text), centred at `center`.
static func look_away_rect(center: Vector2, s: String, size: int = 24) -> Rect2:
	var w := text_width(Assets.font_title_heavy, s, size) + size * (1.35 + 0.5 + 1.8)
	var h := size * 2.0
	return Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)


## Pulsing warning pill in a player colour, e.g. "PLAYER 2 – LOOK AWAY!" (eye_slash_icon + heavy text). `t` drives
## the pulse; alpha fades the whole banner.
static func look_away_banner(ci: CanvasItem, center: Vector2, s: String, color: Color, t: float, size: int = 24,
		alpha: float = 1.0) -> void:
	if alpha <= 0.0:
		return
	var font := Assets.font_title_heavy
	var r := look_away_rect(center, s, size)
	var pulse := 0.5 + 0.5 * sin(t * 5.0)
	panel_ex(ci, r, Color(color.darkened(0.84), 0.9 * alpha), Color(color, (0.55 + 0.4 * pulse) * alpha),
		int(r.size.y * 0.5), 2, Color(color, (0.16 + 0.2 * pulse) * alpha), 18)
	var icon := size * 1.35
	var x := r.position.x + size * 0.9
	eye_slash_icon(ci, Vector2(x + icon * 0.5, center.y), icon, Color(color.lerp(Color.WHITE, 0.25), alpha))
	text(ci, font, Vector2(x + icon + size * 0.5, baseline_for(font, size, center.y)), s, size,
		Color(color.lerp(Color.WHITE, 0.2 + 0.25 * pulse), alpha))
