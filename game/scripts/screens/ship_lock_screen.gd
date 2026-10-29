extends ScreenBase
## Ship locks before a two-player match (docs/SPEC.md §19.2, client request): PLAYER k locks up to MAX_LOCKS of the
## six ships for the other player, who looks away meanwhile ("PLAYER j – LOOK AWAY!"). A vertical list of the ships
## (icon, name in its accent colour, a compact stat line: shot speed, shots per salvo, guided, piercing, bonus
## factor) and a final row DONE with "n / 3 LOCKED". Up/down selects (wrapping, controlled repeat); confirm (Enter /
## Space / A / X / Y / Start) on a ship toggles its lock – a 4th lock is refused (menu_back, a short message and the
## count flashes); confirm on DONE → finished("done", {"locked": the locked ids, sorted}). Escape / B →
## finished("back") (Main returns to the title: the match setup is aborted). Title music like the ship select.
## setup args: {"player": k (who locks, 0 / 1), "locked": Array[int] (initial locks, default none)}.

const MAX_LOCKS := 3
## Confirm counts only after this many seconds and a quiet moment (ScreenBase.guarded_confirm): a double tap on the
## previous screen never toggles a lock or ends the locking here.
const ENTRY_DELAY := 0.45
const TITLE_Y := 52.0
const SUB_Y := 85.0
const WARN_Y := 129.0           ## centre of the LOOK AWAY banner
const WARN_SIZE := 19
const ROW_W := 760.0
const ROW_H := 56.0
const ROW_STEP := 64.0
const LIST_Y := 168.0           ## top of the first ship row
const ICON_X := 58.0            ## ship icon centre, from the row's left edge
const ICON_W := 66.0
const TEXT_X := 108.0           ## name / stat line start, from the row's left edge
const NAME_Y := 25.0            ## name baseline, from the row's top
const STAT_Y := 46.0            ## stat line baseline, from the row's top
const NAME_SIZE := 19
const STAT_SIZE := 13           ## stat line (lifted in the small display modes, UiKit.label_size)
const STAT_GAP := 18.0          ## between two stat columns
const STATUS_W := 124.0         ## "LOCKED" area at the right end of a row
const DONE_W := 470.0
const DONE_Y := 588.0           ## centre of the DONE row
const DONE_SIZE := 20
const MSG_Y := 638.0            ## refusal message
const MSG_TIME := 2.2
const HINT_Y := 684.0
## Stat columns of the compact line: label + widest value (for the column width).
const STAT_COLS := [["SPEED", "888"], ["SHOTS", "8"], ["GUIDED", "YES"], ["PIERCING", "YES"], ["BONUS", "×888"]]

## Who locks (0 / 1); the ships are locked for the other player.
var player := 0
var locked: Array[int] = []
## Selected row: 0 … 5 = ship id, 6 = DONE.
var _sel := 0
var _refused_at := -10.0
var _anim := {}   # ship id → screen time of its last lock (stamp animation)


func _enter() -> void:
	AudioManager.play_title_music()
	player = clampi(int(args.get("player", 0)), 0, 1)
	for id in args.get("locked", []):
		var i := int(id)
		if i >= 0 and i < ShipData.SHIPS.size() and not locked.has(i) and locked.size() < MAX_LOCKS:
			locked.append(i)


func _star_velocity() -> Vector2:
	return Vector2(-10, 2)


## The other player (the one the locks are for).
func target() -> int:
	return 1 - player


## Index of the DONE row.
static func done_row() -> int:
	return ShipData.SHIPS.size()


func selected() -> int:
	return _sel


## Locks / unlocks a ship. Returns false (nothing changes) for a 4th lock.
func toggle(id: int) -> bool:
	if locked.has(id):
		locked.erase(id)
		return true
	if locked.size() >= MAX_LOCKS:
		return false
	locked.append(id)
	_anim[id] = time
	return true


## Label of the confirm key in the hint bar: what confirm does on the selected row.
func confirm_hint() -> String:
	if _sel == done_row():
		return "Done"
	if locked.has(_sel):
		return "Unlock"
	return "Lock" if locked.size() < MAX_LOCKS else "Max %d locked" % MAX_LOCKS


## The locks as reported by finished("done"): ascending ids.
func result_locks() -> Array[int]:
	var out := locked.duplicate()
	out.sort()
	return out


func _tick(_delta: float) -> void:
	var d := InputRouter.menu_direction()
	if d.y != 0:
		_sel = posmod(_sel + d.y, done_row() + 1)
		sfx("menu_move")
	if guarded_confirm(true, ENTRY_DELAY):
		if _sel == done_row():
			sfx("menu_confirm")
			finish("done", {"locked": result_locks()})
		elif toggle(_sel):
			# Locking and unlocking sound exactly like a cursor step: the player looking away must not hear the locks.
			sfx("menu_move")
		else:
			sfx("menu_back")   # refused: already MAX_LOCKS ships locked
			_refused_at = time
	elif InputRouter.back_pressed():
		sfx("menu_back")
		finish("back")


# --- Layout --------------------------------------------------------------------------------------
static func row_rect(i: int) -> Rect2:
	return Rect2(CX - ROW_W * 0.5, LIST_Y + i * ROW_STEP, ROW_W, ROW_H)


static func done_rect() -> Rect2:
	var h := DONE_SIZE * 1.9
	return Rect2(CX - DONE_W * 0.5, DONE_Y - h * 0.5, DONE_W, h)


static func stat_size() -> int:
	return UiKit.label_size(STAT_SIZE)


## Left x of every stat column (label start, value start) relative to the row's left edge; values of a column share
## one x, so the rows read like a table.
static func stat_columns() -> Array:
	var fs := stat_size()
	var out: Array = []
	var x := TEXT_X
	for col: Array in STAT_COLS:
		var lw := UiKit.text_width(Assets.font_body, String(col[0]), fs)
		var vw := UiKit.text_width(Assets.font_title, String(col[1]), fs)
		out.append([x, x + lw + 6.0])
		x += lw + 6.0 + vw + STAT_GAP
	return out


## Right end of the stat line (relative to the row's left edge) – it must end before the LOCKED area.
static func stat_line_end() -> float:
	var cols := stat_columns()
	var fs := stat_size()
	var last: Array = cols[cols.size() - 1]
	return float(last[1]) + UiKit.text_width(Assets.font_title, String(STAT_COLS[STAT_COLS.size() - 1][1]), fs)


## Headline / subline / warning texts.
func title_text() -> String:
	return "%s LOCKS" % Run.player_label(player)


func warning_text() -> String:
	return "%s – LOOK AWAY!" % Run.player_label(target())


# --- Drawing -------------------------------------------------------------------------------------
func _draw() -> void:
	var pc := UiKit.player_color(player)
	var tc := UiKit.player_color(target())
	var a := ramp(0.0, 0.3)
	draw_title(title_text(), TITLE_Y, 34, Color(pc.lerp(Color.WHITE, 0.2), a), pc)
	_draw_subline(a)
	UiKit.look_away_banner(self, Vector2(CX, WARN_Y), warning_text(), tc, time, WARN_SIZE, a)
	for i in ShipData.SHIPS.size():
		_draw_row(i, ramp(0.06 + i * 0.04, 0.25))
	_draw_done(ramp(0.3, 0.25))
	_draw_message()
	var confirm_label := confirm_hint()
	UiKit.hint_bar(self, Vector2(CX, HINT_Y), [
		[["UD"], "Select"], [["ENTER", "pad:A"], confirm_label], [["ESC", "pad:B"], "Back"],
	], 14)


## "Lock up to 3 ships PLAYER 2 may not fly" – the target player in his colour.
func _draw_subline(a: float) -> void:
	var parts := [["Lock up to %d ships " % MAX_LOCKS, UiKit.COLOR_DIM, Assets.font_body],
		[Run.player_label(target()), UiKit.player_color(target()), Assets.font_body_bold],
		[" may not fly", UiKit.COLOR_DIM, Assets.font_body]]
	var total := 0.0
	for p: Array in parts:
		total += UiKit.text_width(p[2], String(p[0]), 18)
	var x := CX - total * 0.5
	for p: Array in parts:
		UiKit.text(self, p[2], Vector2(x, SUB_Y), String(p[0]), 18, Color(p[1], a))
		x += UiKit.text_width(p[2], String(p[0]), 18)


func _draw_row(i: int, a: float) -> void:
	var r := row_rect(i)
	var ship: Dictionary = ShipData.ship(i)
	var accent: Color = ship["accent"]
	var selected := i == _sel
	var lk := locked.has(i)
	var pulse := 0.5 + 0.5 * sin(time * 4.0)
	var dx := (1.0 - a) * 16.0
	r.position.x += dx
	if lk:
		UiKit.panel_ex(self, r, Color(0.17, 0.02, 0.04, 0.78 * a), Color(UiKit.COLOR_DANGER,
			(0.6 + 0.3 * pulse if selected else 0.45) * a), 12, 2 if selected else 1,
			Color(UiKit.COLOR_DANGER, (0.22 if selected else 0.1) * a), 14)
	elif selected:
		UiKit.panel_ex(self, r, Color(UiKit.COLOR_HILITE, (0.10 + 0.05 * pulse) * a),
			Color(UiKit.COLOR_HILITE, (0.55 + 0.25 * pulse) * a), 12, 2, Color(UiKit.COLOR_HILITE, 0.18 * a), 12)
	else:
		UiKit.panel_ex(self, r, Color(UiKit.COLOR_PANEL, 0.62 * a), Color(UiKit.COLOR_BORDER, 0.2 * a), 12, 1)
	if selected:
		var col := UiKit.COLOR_DANGER if lk else UiKit.COLOR_HILITE
		UiKit.triangle(self, Vector2(r.position.x - 16, r.get_center().y), Vector2.RIGHT, 12, Color(col, a))
		UiKit.triangle(self, Vector2(r.end.x + 16, r.get_center().y), Vector2.LEFT, 12, Color(col, a))
	var cy := r.get_center().y
	UiKit.ship_icon(self, i, Vector2(r.position.x + ICON_X, cy), ICON_W,
		Color(0.55, 0.45, 0.5, 0.8 * a) if lk else Color(1, 1, 1, a))
	var name_col := accent.lerp(Color.WHITE, 0.35 if selected else 0.2)
	if lk:
		name_col = accent.lerp(UiKit.COLOR_DIM, 0.55)
	UiKit.text(self, Assets.font_title, Vector2(r.position.x + TEXT_X, r.position.y + NAME_Y), String(ship["name"]),
		NAME_SIZE, Color(name_col, a))
	_draw_stats(r, ship, a * (0.6 if lk else (1.0 if selected else 0.85)))
	if lk:
		_draw_locked_tag(r, i, a)


func _draw_stats(r: Rect2, ship: Dictionary, a: float) -> void:
	var fs := stat_size()
	var by := r.position.y + STAT_Y
	var values := [["%d" % int(ship["speed"]), UiKit.COLOR_TEXT], ["%d" % int(ship["count"]), UiKit.COLOR_TEXT],
		["YES" if ship["guided"] else "NO", UiKit.COLOR_GOOD if ship["guided"] else UiKit.COLOR_FAINT],
		["YES" if ship["piercing"] else "NO", UiKit.COLOR_GOOD if ship["piercing"] else UiKit.COLOR_FAINT],
		["×%d" % int(ship["bonus_factor"]), UiKit.COLOR_GOLD]]
	var cols := stat_columns()
	for c in cols.size():
		UiKit.text(self, Assets.font_body, Vector2(r.position.x + float(cols[c][0]), by), String(STAT_COLS[c][0]), fs,
			Color(UiKit.COLOR_DIM, a))
		UiKit.text(self, Assets.font_title, Vector2(r.position.x + float(cols[c][1]), by), String(values[c][0]), fs,
			Color(values[c][1], a))


## Padlock + "LOCKED" at the right end of a locked row; it lands with a short stamp when the lock is set.
func _draw_locked_tag(r: Rect2, id: int, a: float) -> void:
	var k := clampf((time - float(_anim.get(id, -10.0))) / 0.22, 0.0, 1.0)
	var s := 1.0 + 0.7 * (1.0 - k) * (1.0 - k)
	var x := r.end.x - STATUS_W + 4.0
	var cy := r.get_center().y
	if k < 1.0:
		UiKit.glow_spot(self, Vector2(x + 10.0, cy), Vector2(40, 40) * s, Color(UiKit.COLOR_DANGER, 0.35 * (1.0 - k) * a))
	UiKit.lock_icon(self, Vector2(x + 10.0, cy + 1.0), 20.0 * s, Color(UiKit.COLOR_DANGER.lerp(Color.WHITE, 0.15), a))
	var font := Assets.font_title
	UiKit.text(self, font, Vector2(x + 28.0, UiKit.baseline_for(font, 16, cy)), "LOCKED", 16,
		Color(UiKit.COLOR_DANGER.lerp(Color.WHITE, 0.2), a * (0.4 + 0.6 * k)))


## DONE row: "DONE" and, on the right, three padlock pips (set ones red) + "n / 3 LOCKED".
func _draw_done(a: float) -> void:
	var r := done_rect()
	var selected := _sel == done_row()
	var pulse := 0.5 + 0.5 * sin(time * 4.0)
	var flash := clampf(1.0 - (time - _refused_at) / 0.8, 0.0, 1.0)
	if selected:
		UiKit.panel_ex(self, r, Color(UiKit.COLOR_HILITE, (0.10 + 0.05 * pulse) * a),
			Color(UiKit.COLOR_HILITE, (0.55 + 0.25 * pulse) * a), int(r.size.y * 0.5), 1,
			Color(UiKit.COLOR_HILITE, 0.18 * a), 12)
		UiKit.triangle(self, Vector2(r.position.x - 16, DONE_Y), Vector2.RIGHT, 12, Color(UiKit.COLOR_HILITE, a))
		UiKit.triangle(self, Vector2(r.end.x + 16, DONE_Y), Vector2.LEFT, 12, Color(UiKit.COLOR_HILITE, a))
	else:
		UiKit.panel_ex(self, r, Color(UiKit.COLOR_PANEL, 0.62 * a), Color(UiKit.COLOR_BORDER, 0.22 * a),
			int(r.size.y * 0.5), 1)
	var font := Assets.font_title
	var by := UiKit.baseline_for(font, DONE_SIZE, DONE_Y)
	UiKit.text(self, font, Vector2(r.position.x + 34.0, by), "DONE", DONE_SIZE,
		Color(UiKit.COLOR_TEXT if selected else UiKit.COLOR_DIM, a))
	var count := "%d / %d LOCKED" % [locked.size(), MAX_LOCKS]
	var vcol := UiKit.COLOR_ACCENT.lerp(UiKit.COLOR_DANGER, flash)
	var vx := r.end.x - 34.0
	UiKit.text(self, font, Vector2(vx, by), count, 17, Color(vcol, a), HORIZONTAL_ALIGNMENT_RIGHT)
	var px := vx - UiKit.text_width(font, count, 17) - 20.0
	for k in MAX_LOCKS:
		var c := Vector2(px - (MAX_LOCKS - 1 - k) * 22.0, DONE_Y + 1.0)
		if k < locked.size():
			UiKit.lock_icon(self, c, 15.0, Color(UiKit.COLOR_DANGER.lerp(Color.WHITE, 0.4 * flash), a))
		else:
			UiKit.lock_icon(self, c, 15.0, Color(UiKit.COLOR_FAINT, 0.35 * a))


## After a refused 4th lock: a short line under the DONE row (fades out after MSG_TIME).
func _draw_message() -> void:
	var t := time - _refused_at
	if t < 0.0 or t > MSG_TIME:
		return
	var a := clampf(t / 0.12, 0.0, 1.0) * clampf((MSG_TIME - t) / 0.4, 0.0, 1.0)
	var shake := sin(t * 48.0) * 6.0 * maxf(0.0, 1.0 - t / 0.5)
	UiKit.text(self, Assets.font_body_bold, Vector2(CX + shake, MSG_Y), refusal_text(), 17,
		Color(UiKit.COLOR_DANGER.lerp(Color.WHITE, 0.15), a), HORIZONTAL_ALIGNMENT_CENTER)


static func refusal_text() -> String:
	return "Only %d ships can be locked – unlock one first" % MAX_LOCKS
