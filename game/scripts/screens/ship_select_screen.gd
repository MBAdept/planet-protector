extends ScreenBase
## Ship selection (docs/SPEC.md §4, §11, §12): 3 × 2 grid of six tiles, each with an animated preview
## that uses the real projectile graphics (ProjectileArt) with the ship's real projectile speed, salvo
## size and guided behaviour (guided shots follow the preview ship; one salvo at a time).
## Confirm (Enter/Space/A/X/Y/Start) → finished("confirm", {"ship": id}); B/Escape → finished("back").
## setup args: {"ship": <initially selected id>}.

const COLS := 3
const TILE_W := 286.0
const TILE_H := 268.0
const GAP := 13.0
const GRID_Y := 106.0
const PREVIEW_H := 134.0
const PREVIEW_SCALE := 0.9

const BLURBS: Array[String] = [
	"The fastest laser – and the highest bonus factor.",
	"A guided rocket: steer it while it flies.",
	"Two parallel lasers in every salvo.",
	"Two guided rockets – a wide, steerable salvo.",
	"A heavy piercing laser that cuts through demons.",
	"A slow guided warhead that pierces everything.",
]

var _sel := 0
var _previews: Array[Control] = []


func _enter() -> void:
	AudioManager.play_title_music()
	_sel = clampi(int(args.get("ship", 0)), 0, ShipData.SHIPS.size() - 1)
	for i in ShipData.SHIPS.size():
		var p := ShipPreview.new()
		p.ship_id = i
		var r := tile_rect(i)
		p.position = Vector2(r.position.x + 12.0, r.position.y + 42.0)
		p.size = Vector2(r.size.x - 24.0, PREVIEW_H)
		p.preview_scale = PREVIEW_SCALE
		add_child(p)
		_previews.append(p)
	_update_preview_highlight()


func _star_velocity() -> Vector2:
	return Vector2(-10, 2)


static func tile_rect(i: int) -> Rect2:
	var col := i % COLS
	var row := floori(i / float(COLS))
	var x0 := (W - (TILE_W * COLS + GAP * (COLS - 1))) * 0.5
	return Rect2(x0 + col * (TILE_W + GAP), GRID_Y + row * (TILE_H + GAP), TILE_W, TILE_H)


func _tick(_delta: float) -> void:
	var d := InputRouter.menu_direction()
	var n := ShipData.SHIPS.size()
	if d.x != 0:
		_sel = posmod(_sel + d.x, n)
		sfx("menu_move")
		_update_preview_highlight()
	elif d.y != 0:
		_sel = posmod(_sel + d.y * COLS, n)
		sfx("menu_move")
		_update_preview_highlight()
	if InputRouter.confirm_pressed(true):
		sfx("menu_confirm")
		finish("confirm", {"ship": _sel})
	elif InputRouter.back_pressed():
		sfx("menu_back")
		finish("back")


func _update_preview_highlight() -> void:
	for i in _previews.size():
		(_previews[i] as ShipPreview).selected = i == _sel


# --- Drawing -------------------------------------------------------------------------------------
func _draw() -> void:
	draw_title("CHOOSE YOUR SHIP", 54, 32)
	var ship: Dictionary = ShipData.ship(_sel)
	UiKit.text(self, Assets.font_body, Vector2(CX, 85), BLURBS[_sel], 17, Color(ship["accent"]).lerp(Color.WHITE, 0.45),
		HORIZONTAL_ALIGNMENT_CENTER)
	var rx := right_x() - 24.0   # top-right corner of the canvas (16:9 too)
	UiKit.text(self, Assets.font_body, Vector2(rx, 30), "DIFFICULTY", 12, UiKit.COLOR_FAINT,
		HORIZONTAL_ALIGNMENT_RIGHT)
	UiKit.text(self, Assets.font_title, Vector2(rx, 50), String(ShipData.difficulty(Settings.difficulty)["name"]),
		15, UiKit.COLOR_ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in ShipData.SHIPS.size():
		_draw_tile(i)
	UiKit.hint_bar(self, Vector2(CX, 690), [
		[["LR", "UD"], "Choose"], [["ENTER", "pad:A"], "Start"], [["ESC", "pad:B"], "Back"],
	], 14)


func _draw_tile(i: int) -> void:
	var r := tile_rect(i)
	var ship: Dictionary = ShipData.ship(i)
	var accent: Color = ship["accent"]
	var selected := i == _sel
	if selected:
		var pulse := 0.5 + 0.5 * sin(time * 4.0)
		UiKit.panel_ex(self, r, Color(accent.darkened(0.82), 0.78), Color(accent.lightened(0.2), 0.75 + 0.25 * pulse),
			14, 2, Color(accent, 0.30 + 0.12 * pulse), 18)
	else:
		UiKit.panel_ex(self, r, Color(UiKit.COLOR_PANEL, 0.62), Color(UiKit.COLOR_BORDER, 0.22), 14, 1)
	# Name
	var name_col := accent.lerp(Color.WHITE, 0.35) if selected else UiKit.COLOR_TEXT.darkened(0.12)
	UiKit.text(self, Assets.font_title, Vector2(r.get_center().x, r.position.y + 30), String(ship["name"]), 18,
		name_col, HORIZONTAL_ALIGNMENT_CENTER)
	# Preview frame
	var pr := Rect2(r.position + Vector2(12, 42), Vector2(r.size.x - 24, PREVIEW_H))
	UiKit.panel_ex(self, pr.grow(1), Color(0, 0, 0, 0), Color(accent if selected else UiKit.COLOR_BORDER,
		0.45 if selected else 0.16), 8, 1)
	# Stats
	var lx := r.position.x + 18.0
	var rx := r.end.x - 18.0
	var mx := r.get_center().x
	var y := r.position.y + 202.0
	var dim := 1.0 if selected else 0.8
	var label_col := Color(UiKit.COLOR_DIM, dim)
	var val_col := Color(UiKit.COLOR_TEXT, dim)
	_stat(lx, mx - 10.0, y, "SHOT SPEED", "%d" % int(ship["speed"]), label_col, val_col)
	_stat(mx + 10.0, rx, y, "SHOTS / SALVO", "%d" % int(ship["count"]), label_col, val_col)
	y += 22.0
	_stat(lx, mx - 10.0, y, "GUIDED", "YES" if ship["guided"] else "NO", label_col,
		Color(UiKit.COLOR_GOOD, dim) if ship["guided"] else Color(UiKit.COLOR_FAINT, dim))
	_stat(mx + 10.0, rx, y, "PIERCING", "YES" if ship["piercing"] else "NO", label_col,
		Color(UiKit.COLOR_GOOD, dim) if ship["piercing"] else Color(UiKit.COLOR_FAINT, dim))
	y += 22.0
	_stat(lx, rx, y, "BONUS FACTOR", "×%d" % int(ship["bonus_factor"]), label_col, Color(UiKit.COLOR_GOLD, dim))
	# Speed meter under the first stat (relative to the fastest ship)
	var bar_y := r.position.y + 207.0
	var bw := (mx - 10.0) - lx
	UiKit.panel_ex(self, Rect2(lx, bar_y, bw, 3), Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 1, 0)
	UiKit.panel_ex(self, Rect2(lx, bar_y, bw * float(ship["speed"]) / 500.0, 3), Color(accent.lightened(0.15), 0.85 * dim),
		Color(0, 0, 0, 0), 1, 0)


func _stat(x0: float, x1: float, baseline: float, label: String, value: String, label_col: Color, val_col: Color) -> void:
	UiKit.text(self, Assets.font_body, Vector2(x0, baseline), label, 13, label_col)
	UiKit.text(self, Assets.font_title, Vector2(x1, baseline), value, 13, val_col, HORIZONTAL_ALIGNMENT_RIGHT)


# --- Animated preview ----------------------------------------------------------------------------
## Clipped preview area: the ship patrols left/right and keeps firing like a player holding fire.
class ShipPreview extends Control:
	var ship_id := 0
	var preview_scale := 0.8
	var selected := false
	var _x := 0.0
	var _target := 0.0
	var _wait := 0.0
	var _shots: Array[Dictionary] = []   # {off, x, y, age}
	var _rng := RandomNumberGenerator.new()
	var _t := 0.0

	var _glow: Node2D

	func _ready() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Optional engine glow (Assets.ship_glow_texture), drawn additively on top of the ship.
		if Assets.ship_glow_texture(ship_id) != null:
			_glow = Node2D.new()
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			_glow.material = mat
			_glow.draw.connect(_draw_glow)
			add_child(_glow)
		_rng.seed = 4242 + ship_id * 97
		_x = size.x * (0.3 + 0.4 * _rng.randf())
		_target = _x
		_wait = _rng.randf_range(0.0, 0.4)

	func _ship_y() -> float:
		return size.y - 32.0

	func _process(delta: float) -> void:
		_t += delta
		var k := preview_scale
		# Patrol: run to a random target at full ship speed, pause briefly, repeat.
		var margin := 34.0
		if absf(_target - _x) < 0.5:
			_wait -= delta
			if _wait <= 0.0:
				_target = _rng.randf_range(margin, size.x - margin)
				_wait = _rng.randf_range(0.05, 0.45)
		else:
			_x = move_toward(_x, _target, LevelData.PLAYER_SPEED * k * delta)
		var ship: Dictionary = ShipData.ship(ship_id)
		var speed := float(ship["speed"]) * k
		var guided: bool = ship["guided"]
		for s in _shots:
			s["y"] = float(s["y"]) - speed * delta
			s["age"] = float(s["age"]) + delta
			if guided:
				s["x"] = _x + float(s["off"]) * k   # guided: x = CURRENT ship x + original offset
		_shots = _shots.filter(func(s: Dictionary) -> bool: return float(s["y"]) > -30.0)
		if _shots.is_empty():   # one salvo at a time, auto-refire like a held fire button
			for off in ShipData.shot_offsets(ship_id):
				_shots.append({"off": off, "x": _x + off * k,
					"y": _ship_y() - (LevelData.PLAYER_Y - LevelData.SALVO_Y) * k, "age": 0.0})
		queue_redraw()
		if _glow:
			_glow.queue_redraw()

	func _draw_glow() -> void:
		var k := preview_scale
		var sz := Vector2(80, 56) * k
		var flicker := 0.85 + 0.15 * sin(_t * 31.0) * sin(_t * 17.0)
		_glow.draw_texture_rect(Assets.ship_glow_texture(ship_id), Rect2(Vector2(_x, _ship_y()) - sz * 0.5, sz), false,
			Color(1, 1, 1, flicker * (1.0 if selected else 0.6)))

	func _draw() -> void:
		var k := preview_scale
		var accent: Color = ShipData.ship(ship_id)["accent"]
		var a := 1.0 if selected else 0.62
		# Backdrop: dark gradient with a faint floor line.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.01, 0.04, 0.55))
		UiKit.glow_spot(self, Vector2(_x, _ship_y() + 6.0), Vector2(70, 34), Color(accent, 0.10 * a))
		draw_rect(Rect2(0, _ship_y() + 22.0 * k, size.x, 1.0), Color(accent, 0.18 * a))
		for s in _shots:
			ProjectileArt.draw_player_shot(self, ship_id, Vector2(float(s["x"]), float(s["y"])), float(s["age"]), k)
		var tex := Assets.ship_texture(ship_id)
		var sz := Vector2(80, 56) * k
		draw_texture_rect(tex, Rect2(Vector2(_x, _ship_y()) - sz * 0.5, sz), false, Color(1, 1, 1, 0.75 + 0.25 * a))
		if not selected:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.25))
