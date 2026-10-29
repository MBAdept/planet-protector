extends ScreenBase
## Ship selection (docs/SPEC.md §4, §11, §12): 3 × 2 grid of six tiles, each with an animated preview
## that uses the real projectile graphics (ProjectileArt) with the ship's real projectile speed, salvo
## size and guided behaviour (guided shots follow the preview ship; one salvo at a time).
## Confirm (Enter/Space/A/X/Y/Start) → finished("confirm", {"ship": id}); B/Escape → finished("back").
## Two players (SPEC §19.2): the screen is shown once per player with a header "PLAYER k – CHOOSE YOUR SHIP" (the
## player in the player colour). The ships the other player locked are darkened, their preview stands still and
## carries a padlock with "LOCKED BY PLAYER j"; the cursor may rest on them, but confirm is refused (menu_back and
## the line under the header says so, with a short shake). If the requested ship is locked, the selection starts on
## the first free one. One player (player −1, nothing locked): exactly the classic screen.
## setup args: {"ship": <initially selected id>, "player": k (−1 = one player, default), "locked": Array[int]
##             (ships player k may not fly, default none)}.

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

## Two players: the header's maximum width (clear of the DIFFICULTY caption in the top-right corner of the 4:3 canvas).
const TITLE_MAX_W := 660.0
## Seconds the refusal of a locked ship stays highlighted (shake + bright line).
const REFUSE_TIME := 0.9
## Two players: confirm counts only after this many seconds and a quiet moment (ScreenBase.guarded_confirm).
const ENTRY_DELAY := 0.45

var _sel := 0
var _previews: Array[Control] = []
## Player who chooses (0 / 1), −1 in a one-player run.
var player := -1
## Ships this player may not fly (locked by the other player).
var locked: Array[int] = []
var _refused_at := -10.0


func _enter() -> void:
	AudioManager.play_title_music()
	player = clampi(int(args.get("player", -1)), -1, 1)
	for id in args.get("locked", []):
		locked.append(int(id))
	_sel = initial_selection(int(args.get("ship", 0)), locked)
	for i in ShipData.SHIPS.size():
		var p := ShipPreview.new()
		p.ship_id = i
		p.locked = locked.has(i)
		p.lock_text = lock_caption(player)
		var r := tile_rect(i)
		p.position = Vector2(r.position.x + 12.0, r.position.y + 42.0)
		p.size = Vector2(r.size.x - 24.0, PREVIEW_H)
		p.preview_scale = PREVIEW_SCALE
		add_child(p)
		_previews.append(p)
	_update_preview_highlight()


## Ship the cursor starts on: the requested one (clamped), or the first free ship if that one is locked.
static func initial_selection(requested: int, p_locked: Array) -> int:
	var id := clampi(requested, 0, ShipData.SHIPS.size() - 1)
	if not p_locked.has(id):
		return id
	for i in ShipData.SHIPS.size():
		if not p_locked.has(i):
			return i
	return id


## Currently highlighted ship id.
func selected() -> int:
	return _sel


func is_locked(id: int) -> bool:
	return locked.has(id)


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
	# Two players: the hand-over guard (ScreenBase.guarded_confirm), so a double tap on the previous screen never picks
	# a ship here; one player: exactly as before.
	var confirmed := InputRouter.confirm_pressed(true) if player < 0 else guarded_confirm(true, ENTRY_DELAY)
	if confirmed:
		if is_locked(_sel):
			sfx("menu_back")   # refused: the other player locked this ship
			_refused_at = time
		else:
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
	var ship: Dictionary = ShipData.ship(_sel)
	if player < 0:
		draw_title("CHOOSE YOUR SHIP", 54, 32)
	else:
		_draw_player_title()
	if is_locked(_sel):
		_draw_locked_line()
	else:
		UiKit.text(self, Assets.font_body, Vector2(CX, 85), BLURBS[_sel], 17,
			Color(ship["accent"]).lerp(Color.WHITE, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	var rx := right_x() - 24.0   # top-right corner of the canvas (16:9 too)
	UiKit.text(self, Assets.font_body, Vector2(rx, 30), "DIFFICULTY", UiKit.label_size(12), UiKit.COLOR_FAINT,
		HORIZONTAL_ALIGNMENT_RIGHT)
	UiKit.text(self, Assets.font_title, Vector2(rx, 50), String(ShipData.difficulty(Settings.difficulty)["name"]),
		15, UiKit.COLOR_ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in ShipData.SHIPS.size():
		_draw_tile(i)
	# PLAYER 1's choice does not start the match yet (PLAYER 2 chooses next).
	UiKit.hint_bar(self, Vector2(CX, 690), [
		[["LR", "UD"], "Choose"], [["ENTER", "pad:A"], "Confirm" if player == 0 else "Start"], [["ESC", "pad:B"], "Back"],
	], 14)


## Two players: "PLAYER k" in the player colour, " – CHOOSE YOUR SHIP" in the text colour, one glowing line (sized
## to TITLE_MAX_W, so it stays clear of the DIFFICULTY caption in the corner).
func _draw_player_title() -> void:
	var font := Assets.font_title_heavy
	var pc := UiKit.player_color(player)
	var parts := [[Run.player_label(player), pc.lerp(Color.WHITE, 0.2)], ["  –  CHOOSE YOUR SHIP", UiKit.COLOR_TEXT]]
	var size := title_size(player)
	var x := CX - UiKit.text_width(font, player_title(player), size) * 0.5
	for part: Array in parts:
		UiKit.text_glow(self, font, Vector2(x, 54), String(part[0]), size, part[1], pc)
		x += UiKit.text_width(font, String(part[0]), size)


## Header of the two-player screen and its font size (32 like the one-player title, smaller only if it would not fit).
static func player_title(k: int) -> String:
	return "%s  –  CHOOSE YOUR SHIP" % Run.player_label(k)


static func title_size(k: int) -> int:
	return UiKit.fit_size(Assets.font_title_heavy, player_title(k), 32, TITLE_MAX_W)


## Line under the header while a locked ship is selected: padlock + "Locked by PLAYER j – choose a free ship"; after
## a refused confirm it shakes briefly and lights up.
func _draw_locked_line() -> void:
	var font := Assets.font_body_bold
	var s := locked_line_text(player)
	var k := clampf(1.0 - (time - _refused_at) / REFUSE_TIME, 0.0, 1.0)
	var shake := sin((time - _refused_at) * 48.0) * 7.0 * k * k
	var w := UiKit.text_width(font, s, 17)
	var x := CX - (w + 24.0) * 0.5 + shake
	var col := UiKit.COLOR_DANGER.lerp(Color.WHITE, 0.35 * k)
	UiKit.lock_icon(self, Vector2(x + 8.0, 79.0), 15.0, col)
	UiKit.text(self, font, Vector2(x + 24.0, 85), s, 17, col)


## "Locked by PLAYER j – choose a free ship" (j = the other player; one player: no names).
static func locked_line_text(k: int) -> String:
	if k < 0:
		return "This ship is locked – choose a free ship"
	return "Locked by %s – choose a free ship" % Run.player_label(1 - k)


## Caption under the padlock of a locked preview: "LOCKED BY PLAYER j".
static func lock_caption(k: int) -> String:
	return "LOCKED" if k < 0 else "LOCKED BY %s" % Run.player_label(1 - k)


func _draw_tile(i: int) -> void:
	var r := tile_rect(i)
	var ship: Dictionary = ShipData.ship(i)
	var accent: Color = ship["accent"]
	var selected := i == _sel
	var lk := is_locked(i)
	if lk:
		# Locked by the other player: dark, with a red border (pulsing while the cursor rests on it).
		var pulse := 0.5 + 0.5 * sin(time * 4.0)
		var flash := clampf(1.0 - (time - _refused_at) / REFUSE_TIME, 0.0, 1.0) if selected else 0.0
		UiKit.panel_ex(self, r, Color(0.06, 0.01, 0.02, 0.8), Color(UiKit.COLOR_DANGER,
			(0.55 + 0.3 * pulse if selected else 0.28) + 0.3 * flash), 14, 2 if selected else 1,
			Color(UiKit.COLOR_DANGER, 0.2 + 0.25 * flash) if selected else Color(0, 0, 0, 0), 16)
	elif selected:
		var pulse := 0.5 + 0.5 * sin(time * 4.0)
		UiKit.panel_ex(self, r, Color(accent.darkened(0.82), 0.78), Color(accent.lightened(0.2), 0.75 + 0.25 * pulse),
			14, 2, Color(accent, 0.30 + 0.12 * pulse), 18)
	else:
		UiKit.panel_ex(self, r, Color(UiKit.COLOR_PANEL, 0.62), Color(UiKit.COLOR_BORDER, 0.22), 14, 1)
	# Name
	var name_col := accent.lerp(Color.WHITE, 0.35) if selected else UiKit.COLOR_TEXT.darkened(0.12)
	if lk:
		name_col = UiKit.COLOR_FAINT.lerp(UiKit.COLOR_TEXT, 0.3 if selected else 0.0)
	UiKit.text(self, Assets.font_title, Vector2(r.get_center().x, r.position.y + 30), String(ship["name"]), 18,
		name_col, HORIZONTAL_ALIGNMENT_CENTER)
	# Preview frame
	var pr := Rect2(r.position + Vector2(12, 42), Vector2(r.size.x - 24, PREVIEW_H))
	var frame_col := Color(accent if selected else UiKit.COLOR_BORDER, 0.45 if selected else 0.16)
	if lk:
		frame_col = Color(UiKit.COLOR_DANGER, 0.3)
	UiKit.panel_ex(self, pr.grow(1), Color(0, 0, 0, 0), frame_col, 8, 1)
	# Stats
	var lx := r.position.x + 18.0
	var rx := r.end.x - 18.0
	var mx := r.get_center().x
	var y := r.position.y + 202.0
	var dim := 1.0 if selected else 0.8
	if lk:
		dim = 0.45
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
	var fs := stat_size()
	UiKit.text(self, Assets.font_body, Vector2(x0, baseline), label, fs, label_col)
	UiKit.text(self, Assets.font_title, Vector2(x1, baseline), value, fs, val_col, HORIZONTAL_ALIGNMENT_RIGHT)


## Font size of the stat rows (one size for all rows and cards): 13, lifted in the small modes 3/4
## (UiKit.label_size) only as far as the widest row – SHOT SPEED 500 / SHOTS / SALVO 2 in a half-card column – keeps
## STAT_GAP between label and value (never below 13, so modes 0–2 are unchanged).
const STAT_SIZE := 13
const STAT_GAP := 8.0
## Widest label / value pairs of the half-card columns.
const STAT_WORST := [["SHOT SPEED", "888"], ["SHOTS / SALVO", "8"], ["PIERCING", "YES"]]
static func stat_size() -> int:
	var col_w := TILE_W * 0.5 - 18.0 - 10.0   # lx = left + 18 … mx − 10 (and mx + 10 … right − 18)
	var fs := UiKit.label_size(STAT_SIZE)
	while fs > STAT_SIZE:
		var fits := true
		for row: Array in STAT_WORST:
			if UiKit.text_width(Assets.font_body, row[0], fs) + UiKit.text_width(Assets.font_title, row[1], fs) \
					+ STAT_GAP > col_w:
				fits = false
		if fits:
			break
		fs -= 1
	return fs


# --- Animated preview ----------------------------------------------------------------------------
## Clipped preview area: the ship patrols left/right and keeps firing like a player holding fire.
## A locked ship (two players) stands still in the middle, dark, under a padlock with lock_text.
class ShipPreview extends Control:
	var ship_id := 0
	var preview_scale := 0.8
	var selected := false
	var locked := false
	var lock_text := "LOCKED"
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
		# Optional engine glow (Assets.ship_glow_texture), drawn additively on top of the ship (not on a locked one).
		if Assets.ship_glow_texture(ship_id) != null and not locked:
			_glow = Node2D.new()
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			_glow.material = mat
			_glow.draw.connect(_draw_glow)
			add_child(_glow)
		_rng.seed = 4242 + ship_id * 97
		_x = size.x * (0.3 + 0.4 * _rng.randf())
		if locked:
			_x = size.x * 0.5
		_target = _x
		_wait = _rng.randf_range(0.0, 0.4)

	func _ship_y() -> float:
		return size.y - 32.0

	func _process(delta: float) -> void:
		_t += delta
		if locked:
			queue_redraw()   # stopped: no patrol, no shots (only the padlock pulses while selected)
			return
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
		if locked:
			_draw_locked()
			return
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

	## Locked: the ship as a dark silhouette in the middle, a red padlock and "LOCKED BY PLAYER j" above it.
	func _draw_locked() -> void:
		var k := preview_scale
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.0, 0.01, 0.7))
		var tex := Assets.ship_texture(ship_id)
		var sz := Vector2(80, 56) * k
		draw_texture_rect(tex, Rect2(Vector2(_x, _ship_y()) - sz * 0.5, sz), false, Color(0.32, 0.3, 0.36, 0.55))
		var pulse := 0.5 + 0.5 * sin(_t * 4.0) if selected else 0.0
		var col := UiKit.COLOR_DANGER.lerp(Color.WHITE, 0.15 * pulse)
		var c := Vector2(size.x * 0.5, 36.0)
		UiKit.glow_spot(self, c, Vector2(46, 30), Color(UiKit.COLOR_DANGER, 0.14 + 0.08 * pulse))
		UiKit.lock_icon(self, c, 26.0, Color(col, 0.95 if selected else 0.75))
		var fs := UiKit.label_size(12)
		UiKit.text(self, Assets.font_body_bold, Vector2(size.x * 0.5, 72.0), lock_text, fs,
			Color(col, 0.95 if selected else 0.7), HORIZONTAL_ALIGNMENT_CENTER)
