extends ScreenBase
## Both players' ship locks revealed after the two hidden SHIP LOCK screens (docs/SPEC.md §19.2): "SHIP LOCKS
## REVEALED" and one panel per player, "PLAYER k MAY NOT FLY", with the locked ships (icon, name, padlock) – or
## "NO LOCKS – every ship is free" – and a strip of all six ships with the free ones lit. The locks land one after
## the other with a stamp and the lock "clink" (both players' i-th lock together). Title music like the other setup
## screens. Confirm (Enter / Space / A / X / Y / Start) after CONFIRM_DELAY → finished("continue").
## setup args: {"locked": [ids PLAYER 1 may not fly, ids PLAYER 2 may not fly]}.

const CONFIRM_DELAY := 0.8
const TITLE_Y := 74.0
const SUB_Y := 110.0
const PANEL_W := 400.0
const PANEL_GAP := 40.0
const PANEL_Y := 142.0
const PANEL_H := 436.0
const ROW_Y := 138.0            ## centre of the first lock row, from the panel's top
const ROW_STEP := 76.0
const STRIP_Y := 372.0          ## centre of the six-ship strip, from the panel's top
const STRIP_STEP := 58.0
const STAMP_T0 := 0.25          ## the first locks land at this screen time …
const STAMP_STEP := 0.15        ## … the next ones this much later (all landed before CONFIRM_DELAY)
const STAMP_TIME := 0.22        ## duration of one stamp

## Ship ids each player may not fly (sorted).
var locks: Array = [[], []]
var _stamped := 0


func _enter() -> void:
	AudioManager.play_title_music()
	var raw: Array = args.get("locked", [[], []])
	for k in 2:
		var ids: Array[int] = []
		if k < raw.size():
			for id in raw[k]:
				ids.append(int(id))
		ids.sort()
		locks[k] = ids


func _star_velocity() -> Vector2:
	return Vector2(-10, 2)


func _tick(_delta: float) -> void:
	# One clink per stamp moment (both players' i-th locks land together).
	if _stamped < stamp_count() and time >= stamp_time(_stamped):
		sfx("locked_hit")
		_stamped += 1
	if time >= CONFIRM_DELAY and InputRouter.confirm_pressed(true):
		sfx("menu_confirm")
		finish("continue")


## Number of stamp moments (the longer of the two lock lists).
func stamp_count() -> int:
	return maxi((locks[0] as Array).size(), (locks[1] as Array).size())


static func stamp_time(i: int) -> float:
	return STAMP_T0 + i * STAMP_STEP


## Panel of player k (0 left, 1 right).
static func panel_rect(k: int) -> Rect2:
	var x := CX - PANEL_GAP * 0.5 - PANEL_W if k == 0 else CX + PANEL_GAP * 0.5
	return Rect2(x, PANEL_Y, PANEL_W, PANEL_H)


## Backing of the i-th lock row inside panel rect r.
static func lock_row_rect(r: Rect2, i: int) -> Rect2:
	var cy := r.position.y + ROW_Y + i * ROW_STEP
	return Rect2(r.position.x + 18.0, cy - 31.0, r.size.x - 36.0, 62.0)


## "PLAYER 1 MAY NOT FLY" – the panel's headline as one string (tests, captions).
static func panel_title(k: int) -> String:
	return "%s MAY NOT FLY" % Run.player_label(k)


# --- Drawing -------------------------------------------------------------------------------------
func _draw() -> void:
	var a := ramp(0.0, 0.35)
	draw_title("SHIP LOCKS REVEALED", TITLE_Y, 36, Color(UiKit.COLOR_TEXT, a), UiKit.COLOR_DANGER)
	UiKit.text(self, Assets.font_body, Vector2(CX, SUB_Y), "Now each player chooses a ship from the ones still free", 18,
		Color(UiKit.COLOR_DIM, a), HORIZONTAL_ALIGNMENT_CENTER)
	for k in 2:
		_draw_panel(k, ramp(0.08 + k * 0.08, 0.3))
	var ha := ramp(CONFIRM_DELAY, 0.35)
	if ha > 0.0:
		var col := UiKit.COLOR_DIM.lerp(UiKit.COLOR_TEXT, 0.25)
		col.a = ha * (0.78 + 0.22 * sin(time * 3.0))
		UiKit.hint_bar(self, Vector2(CX, CONTINUE_HINT_Y), [[["ENTER", "pad:A"], "Continue"]], CONTINUE_HINT_SIZE, col, ha)


func _draw_panel(k: int, a: float) -> void:
	var r := panel_rect(k)
	var pc := UiKit.player_color(k)
	r.position.y += (1.0 - a) * 14.0
	UiKit.panel_ex(self, r, Color(UiKit.COLOR_PANEL, 0.66 * a), Color(pc, 0.4 * a), 16, 1, Color(pc, 0.1 * a), 16)
	var cx := r.get_center().x
	UiKit.text_glow(self, Assets.font_title_heavy, Vector2(cx, r.position.y + 50.0), Run.player_label(k), 30,
		Color(pc.lerp(Color.WHITE, 0.2), a), pc, HORIZONTAL_ALIGNMENT_CENTER, 0.9)
	UiKit.text_spaced(self, Assets.font_title, Vector2(cx, r.position.y + 78.0), "MAY NOT FLY", 14, 5.0,
		Color(UiKit.COLOR_DANGER.lerp(Color.WHITE, 0.2), a), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.divider(self, Vector2(cx, r.position.y + 96.0), PANEL_W - 60.0, Color(pc, 0.35 * a), 1.0)
	var ids: Array = locks[k]
	if ids.is_empty():
		var na := a * ramp(STAMP_T0, 0.3)
		UiKit.text_glow(self, Assets.font_title_heavy, Vector2(cx, r.position.y + 196.0), "NO LOCKS", 30,
			Color(UiKit.COLOR_GOOD, na), UiKit.COLOR_GOOD, HORIZONTAL_ALIGNMENT_CENTER, 0.8)
		UiKit.text(self, Assets.font_body, Vector2(cx, r.position.y + 230.0), "every ship is free", 18,
			Color(UiKit.COLOR_DIM, na), HORIZONTAL_ALIGNMENT_CENTER)
	for i in ids.size():
		_draw_lock_row(r, k, int(ids[i]), i, a)
	_draw_strip(r, k, a)


## One locked ship: icon, name in its accent colour, "LOCKED BY PLAYER j" and a padlock that lands with a stamp.
func _draw_lock_row(r: Rect2, k: int, id: int, i: int, a: float) -> void:
	var u := clampf((time - stamp_time(i)) / STAMP_TIME, 0.0, 1.0)
	if u <= 0.0:
		return
	var ra := a * u
	var cy := r.position.y + ROW_Y + i * ROW_STEP
	var ship: Dictionary = ShipData.ship(id)
	var row := lock_row_rect(r, i)
	UiKit.panel_ex(self, row, Color(0.17, 0.02, 0.04, 0.7 * ra), Color(UiKit.COLOR_DANGER, 0.4 * ra), 10, 1)
	UiKit.ship_icon(self, id, Vector2(row.position.x + 50.0, cy), 74.0, Color(0.75, 0.68, 0.72, ra))
	UiKit.text(self, Assets.font_title, Vector2(row.position.x + 100.0, cy - 2.0), String(ship["name"]), 18,
		Color(Color(ship["accent"]).lerp(Color.WHITE, 0.3), ra))
	UiKit.text(self, Assets.font_body_bold, Vector2(row.position.x + 100.0, cy + 19.0),
		"LOCKED BY %s" % Run.player_label(1 - k), UiKit.label_size(12), Color(UiKit.player_color(1 - k), 0.85 * ra))
	# The padlock lands: big and bright → its place.
	var s := 1.0 + 0.9 * (1.0 - u) * (1.0 - u)
	var lc := Vector2(row.end.x - 30.0, cy)
	if u < 1.0:
		UiKit.glow_spot(self, lc, Vector2(46, 46) * s, Color(UiKit.COLOR_DANGER, 0.45 * (1.0 - u) * a))
	UiKit.lock_icon(self, lc, 24.0 * s, Color(UiKit.COLOR_DANGER.lerp(Color.WHITE, 0.5 * (1.0 - u)), ra))


## All six ships in a row: the free ones lit, the locked ones dark with a small padlock; "n OF 6 SHIPS FREE".
func _draw_strip(r: Rect2, k: int, a: float) -> void:
	var ids: Array = locks[k]
	var n := ShipData.SHIPS.size()
	var cy := r.position.y + STRIP_Y
	var x0 := r.get_center().x - STRIP_STEP * (n - 1) * 0.5
	for id in n:
		var c := Vector2(x0 + id * STRIP_STEP, cy)
		var lk := ids.has(id) and time >= stamp_time(ids.find(id))
		UiKit.ship_icon(self, id, c, 46.0, Color(0.3, 0.27, 0.32, 0.6 * a) if lk else Color(1, 1, 1, 0.9 * a))
		if lk:
			UiKit.lock_icon(self, c + Vector2(13, 9), 13.0, Color(UiKit.COLOR_DANGER, a))
	var free := n - ids.size()
	UiKit.text(self, Assets.font_body_bold, Vector2(r.get_center().x, cy + 44.0),
		"%d OF %d SHIPS FREE" % [free, n], UiKit.label_size(13), Color(UiKit.COLOR_DIM, a), HORIZONTAL_ALIGNMENT_CENTER)
