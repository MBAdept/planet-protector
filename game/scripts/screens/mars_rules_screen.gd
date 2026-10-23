extends ScreenBase
## Rules screen shown before level 14 (docs/SPEC.md §8, §11): the global colour-stage lock of levels
## 14–16, illustrated with real EnemyArt demons in the violet / yellow / green stages of level 14.
## Enter (or X/Y/Start) confirms → finished("continue").

const CONFIRM_DELAY := 0.8
const ROW_Y: Array[float] = [134.0, 244.0, 354.0, 464.0]
const ROW_H := 100.0
const ENEMY_SCALE := 0.6
const ILLU_X := 92.0            # left edge of the illustration area
const TEXT_X := 492.0           # left edge of the explanation text

const C_V := Color(0.78, 0.5, 1.0)
const C_Y := Color(1.0, 0.9, 0.35)
const C_G := Color(0.5, 1.0, 0.52)
const C_W := Color(0.92, 0.95, 1.0)
const C_D := Color(0.6, 0.66, 0.78)
const C_R := Color(1.0, 0.4, 0.3)

var _demons: Array[EnemyArt] = []
var _overlay: Node2D
var _rules: Array = []


func _enter() -> void:
	AudioManager.stop_music()
	# REFERENCE G: normal shots are used up by a locked hit, piercing shots fly on.
	var locked_line: Array = [["Locked hits are wasted shots: ", C_D], ["no points.", C_R]]
	if bool(ShipData.ship(Run.ship_id)["piercing"]):
		locked_line = [["Locked hits: ", C_D], ["no points.", C_R], [" Your shot flies on.", C_D]]
	_rules = [
		[[["Every demon arrives ", C_W], ["VIOLET", C_V], [".", C_W]],
			[["A hit turns it ", C_W], ["YELLOW", C_Y], [".", C_W]]],
		[[["A ", C_W], ["YELLOW", C_Y], [" demon only turns ", C_W], ["GREEN", C_G]],
			[["when ", C_W], ["no violet demon", C_V], [" is left.", C_W]]],
		[[["GREEN", C_G], [" demons can only be destroyed", C_W]],
			[["when ", C_W], ["ALL", C_W], [" demons are green.", C_W]]],
		[[["New ", C_W], ["VIOLET", C_V], [" arrivals lock the others again.", C_W]],
			locked_line],
	]
	var V := LevelData.Stage.VIOLET
	var Y := LevelData.Stage.YELLOW
	var G := LevelData.Stage.GREEN
	# Row 1: violet → yellow
	_add_demon(V, Vector2(ILLU_X + 60, _cy(0)))
	_add_demon(Y, Vector2(ILLU_X + 300, _cy(0)))
	# Row 2: yellow → green (no violet left)
	_add_demon(Y, Vector2(ILLU_X + 60, _cy(1)))
	_add_demon(G, Vector2(ILLU_X + 300, _cy(1)))
	# Row 3: all green → destroyed
	_add_demon(G, Vector2(ILLU_X + 34, _cy(2)), 0.48)
	_add_demon(G, Vector2(ILLU_X + 104, _cy(2)), 0.48)
	_add_demon(G, Vector2(ILLU_X + 174, _cy(2)), 0.48)
	# Row 4: a new violet arrives → yellow and green are locked again
	_add_demon(Y, Vector2(ILLU_X + 40, _cy(3)), 0.5)
	_add_demon(G, Vector2(ILLU_X + 130, _cy(3)), 0.5)
	_add_demon(V, Vector2(ILLU_X + 300, _cy(3)), 0.6)
	_overlay = Node2D.new()
	_overlay.z_index = 2
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func _cy(row: int) -> float:
	return ROW_Y[row] + ROW_H * 0.5


func _add_demon(stage: int, pos: Vector2, sc: float = ENEMY_SCALE) -> void:
	var e := EnemyArt.new()
	e.configure(LevelData.MARS_RULES_BEFORE_LEVEL, stage)
	e.scale_factor = sc
	e.position = pos
	e.flap_phase = randf()
	e.z_index = 1
	add_child(e)
	_demons.append(e)


func _tick(delta: float) -> void:
	for i in _demons.size():
		var e := _demons[i]
		e.flap_phase = fposmod(e.flap_phase + LevelData.FLAP_HZ * delta, 1.0)
		e.position.y = _base_y(i) + 3.0 * sin(time * 2.2 + i * 1.3)
		if i == _demons.size() - 1:
			e.materialize = 0.8 + 0.2 * (0.5 + 0.5 * sin(time * 3.0))   # the new arrival shimmers in
		e.queue_redraw()
	_overlay.queue_redraw()
	if time >= CONFIRM_DELAY and InputRouter.confirm_pressed():
		sfx("menu_confirm")
		finish("continue")


func _base_y(i: int) -> float:
	var rows := [0, 0, 1, 1, 2, 2, 2, 3, 3, 3]
	return _cy(rows[i])


# --- Drawing -------------------------------------------------------------------------------------
func _draw() -> void:
	draw_title("MARS: THE COLOUR LOCK", 62, 32, UiKit.COLOR_TEXT, Color(0.75, 0.4, 1.0))
	UiKit.text(self, Assets.font_body, Vector2(CX, 98), "New rules for levels 14 – 16. Read carefully, pilot!", 18,
		UiKit.COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	for row in 4:
		var r := Rect2(40, ROW_Y[row], 880, ROW_H - 8)
		var a := ramp(0.1 + row * 0.12, 0.35)
		UiKit.panel(self, r, 0.55 * a)
		# Number badge
		var bc := Vector2(70, r.get_center().y)
		draw_circle(bc, 15, Color(0.6, 0.35, 1.0, 0.25 * a), true, -1.0, true)
		draw_circle(bc, 15, Color(0.75, 0.5, 1.0, 0.7 * a), false, 1.5, true)
		UiKit.text(self, Assets.font_title, Vector2(bc.x, UiKit.baseline_for(Assets.font_title, 16, bc.y)),
			str(row + 1), 16, Color(UiKit.COLOR_TEXT, a), HORIZONTAL_ALIGNMENT_CENTER)
		# Text
		var lines: Array = _rules[row]
		var y0 := r.get_center().y - 6.0
		for li in lines.size():
			_rich(TEXT_X, y0 + li * 28.0, lines[li], 19, a)
	# Arrows (under the demons)
	var hit_col := Color(UiKit.COLOR_ACCENT, 0.95)
	_hit_arrow(Vector2(ILLU_X + 112, _cy(0)), Vector2(ILLU_X + 248, _cy(0)), "HIT", hit_col)
	_hit_arrow(Vector2(ILLU_X + 112, _cy(1)), Vector2(ILLU_X + 248, _cy(1)), "HIT", hit_col)
	_hit_arrow(Vector2(ILLU_X + 218, _cy(2)), Vector2(ILLU_X + 268, _cy(2)), "HIT", hit_col)
	# Row 4 "arrives" marker
	var p := Vector2(ILLU_X + 300, _cy(3))
	UiKit.glow_spot(self, p, Vector2(80, 46), Color(0.7, 0.35, 1.0, 0.30 + 0.10 * sin(time * 3.0)))
	UiKit.text(self, Assets.font_body, Vector2(CX, 604), "Colours already reached are kept while the lock is active.", 17,
		UiKit.COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	draw_continue_hint("Start level 14", CONFIRM_DELAY)


func _draw_overlay() -> void:
	var a := ramp(0.3, 0.4)
	# Row 2: "no violet left" condition badge between the two demons
	var c2 := Vector2(ILLU_X + 180, _cy(1) + 32)
	UiKit.text(_overlay, Assets.font_body_bold, Vector2(c2.x, c2.y), "only if no violet is left", 13,
		Color(C_V, 0.95 * a), HORIZONTAL_ALIGNMENT_CENTER)
	# Row 3: destroyed burst
	var b := Vector2(ILLU_X + 330, _cy(2) - 6)
	var pulse := 0.5 + 0.5 * sin(time * 4.0)
	UiKit.glow_spot(_overlay, b, Vector2(40, 40) * (0.9 + 0.15 * pulse), Color(1.0, 0.7, 0.25, 0.55 * a))
	UiKit.glow_spot(_overlay, b, Vector2(16, 16), Color(1.0, 0.95, 0.8, 0.9 * a))
	for k in 10:
		var ang := TAU * k / 10.0 + 0.2
		var r0 := 12.0 + 3.0 * pulse
		var r1 := 25.0 + 5.0 * pulse
		_overlay.draw_line(b + Vector2.from_angle(ang) * r0, b + Vector2.from_angle(ang) * r1,
			Color(1.0, 0.8, 0.4, 0.75 * a), 2.0, true)
	UiKit.text(_overlay, Assets.font_body_bold, Vector2(b.x, _cy(2) + 37), "DESTROYED", 12, Color(UiKit.COLOR_GOLD, a),
		HORIZONTAL_ALIGNMENT_CENTER)
	# Row 4: locks on the older demons + "NEW" tag on the violet arrival
	for x in [ILLU_X + 40, ILLU_X + 130]:
		var lc := Vector2(x + 26, _cy(3) - 20)
		_overlay.draw_circle(lc, 13, Color(0, 0, 0, 0.6 * a), true, -1.0, true)
		UiKit.lock_icon(_overlay, lc + Vector2(0, -1), 15, Color(C_R, a))
	UiKit.text(_overlay, Assets.font_body_bold, Vector2(ILLU_X + 300, _cy(3) + 37), "NEW ARRIVAL", 12,
		Color(C_V, a), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.text(_overlay, Assets.font_body_bold, Vector2(ILLU_X + 85, _cy(3) + 37), "LOCKED", 12, Color(C_R, a),
		HORIZONTAL_ALIGNMENT_CENTER)


func _hit_arrow(from: Vector2, to: Vector2, label: String, col: Color) -> void:
	var a := ramp(0.3, 0.4)
	var c := Color(col, col.a * a)
	UiKit.arrow(self, from, to, c, 3.0, 13.0)
	UiKit.text(self, Assets.font_title, Vector2((from.x + to.x) * 0.5, from.y - 10), label, 13, c,
		HORIZONTAL_ALIGNMENT_CENTER)


## Draws one line of coloured segments starting at x.
func _rich(x: float, baseline: float, segments: Array, size: int, alpha: float) -> void:
	var font := Assets.font_body
	for seg in segments:
		var s: String = seg[0]
		var c: Color = seg[1]
		var f := font if c == C_W or c == C_D else Assets.font_body_bold
		UiKit.text(self, f, Vector2(x, baseline), s, size, Color(c, alpha))
		x += UiKit.text_width(f, s, size)
