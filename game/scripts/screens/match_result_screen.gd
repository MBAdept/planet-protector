extends ScreenBase
## Result of a two-player match (docs/SPEC.md §19.2), after the last level of the match (both players out, or the
## survivors through level 20), before the name entries. "MATCH RESULT" (difficulty and category below), one panel
## per player – score (counts up), GAME OVER / EARTH SAVED, level reached, play time, ship – and the winner by score:
## "PLAYER k WINS!" in the player colour with a WINNER badge on the panel, equal scores "DRAW!". Silent like the
## one-player end screens (victory, game over); the winner reveal plays the level-complete fanfare, the name entry /
## highscores that follow start the title music. Confirm (Enter / X / Y / Start) after CONFIRM_DELAY →
## finished("continue"); the count-up and the reveal are over by then.
## setup args: {} – both players are read with Run.player_get(k, …).

const CONFIRM_DELAY := 1.0
const COUNT_T0 := 0.25          ## the scores count up from 0 …
const COUNT_T1 := 0.8           ## … to their final value
const REVEAL_T := 0.9           ## the winner banner appears
const TITLE_Y := 62.0
const SUB_Y := 94.0
const BANNER_Y := 156.0         ## baseline of "PLAYER k WINS!" / "DRAW!"
const BANNER_SIZE := 42
const PANEL_W := 400.0
const PANEL_GAP := 40.0
const PANEL_Y := 212.0
const PANEL_H := 356.0
const BADGE_H := 24.0

var _tick_acc := 0.0
var _revealed := false


func _enter() -> void:
	AudioManager.stop_music()


func _star_velocity() -> Vector2:
	return Vector2(-5, 1)


func _tick(delta: float) -> void:
	if time >= COUNT_T0 and time < COUNT_T1:
		_tick_acc += delta
		if _tick_acc >= 0.06:
			_tick_acc = 0.0
			sfx("bonus_tick")
	if not _revealed and time >= REVEAL_T:
		_revealed = true
		sfx("level_complete")
	if time >= CONFIRM_DELAY and InputRouter.confirm_pressed():
		sfx("menu_confirm")
		finish("continue")


## Winner by score: 0 = PLAYER 1, 1 = PLAYER 2, −1 = draw (equal scores).
static func winner(score1: int, score2: int) -> int:
	if score1 == score2:
		return -1
	return 0 if score1 > score2 else 1


## The banner: "PLAYER 2 WINS!" / "DRAW!".
static func banner_text(w: int) -> String:
	return "DRAW!" if w < 0 else "%s WINS!" % Run.player_label(w)


## Winner of the match in Run.
func match_winner() -> int:
	return winner(int(Run.player_get(0, "score")), int(Run.player_get(1, "score")))


## Status tag of a player: "EARTH SAVED" (completed level 20), "GAME OVER" (lost the last life) or "".
static func status_text(out: bool, won: bool) -> String:
	if won:
		return "EARTH SAVED"
	return "GAME OVER" if out else ""


## "14 – MARS 1" / "13 – BONUS ROUND" (level reached).
static func level_text(n: int) -> String:
	if n == LevelData.BONUS_LEVEL:
		return "%d • BONUS ROUND" % n
	# "•": Orbitron has no "·", and "–" would clash with level 20's own dash ("EARTH – FINAL BATTLE").
	return "%d • %s" % [n, String(LevelData.level(n)["name"]).to_upper()]


static func panel_rect(k: int) -> Rect2:
	var x := CX - PANEL_GAP * 0.5 - PANEL_W if k == 0 else CX + PANEL_GAP * 0.5
	return Rect2(x, PANEL_Y, PANEL_W, PANEL_H)


# --- Drawing -------------------------------------------------------------------------------------
func _draw() -> void:
	var a := ramp(0.0, 0.35)
	draw_title("MATCH RESULT", TITLE_Y, 36, Color(UiKit.COLOR_TEXT, a))
	var sub := Run.difficulty_name() + ("  ·  POWER-UPS" if Run.powerups else "  ·  CLASSIC")
	UiKit.text_spaced(self, Assets.font_body_bold, Vector2(CX, SUB_Y), sub, 14, 3.0, Color(UiKit.COLOR_ACCENT, a),
		HORIZONTAL_ALIGNMENT_CENTER)
	var w := match_winner()
	for k in 2:
		_draw_panel(k, w, ramp(0.05 + k * 0.08, 0.3))
	_draw_banner(w)
	draw_continue_hint("Continue", CONFIRM_DELAY)


func _draw_banner(w: int) -> void:
	var u := ramp(REVEAL_T, 0.3)
	if u <= 0.0:
		return
	var col := UiKit.COLOR_GOLD if w < 0 else UiKit.player_color(w)
	var pulse := 0.85 + 0.15 * sin(time * 3.0)
	UiKit.glow_spot(self, Vector2(CX, BANNER_Y - BANNER_SIZE * 0.36), Vector2(360, 70), Color(col, 0.12 * u * pulse))
	var s := 1.0 + 0.25 * (1.0 - u) * (1.0 - u)
	var c := Vector2(CX, BANNER_Y - BANNER_SIZE * 0.36)
	draw_set_transform(c, 0.0, Vector2(s, s))
	UiKit.text_glow(self, Assets.font_title_heavy, Vector2(0, BANNER_SIZE * 0.36), banner_text(w), BANNER_SIZE,
		Color(col.lerp(Color.WHITE, 0.25), u), col, HORIZONTAL_ALIGNMENT_CENTER, 1.3 * pulse)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_panel(k: int, w: int, a: float) -> void:
	var r := panel_rect(k)
	r.position.y += (1.0 - a) * 14.0
	var pc := UiKit.player_color(k)
	var won_match := w == k
	var u := ramp(REVEAL_T, 0.3)
	var glow := Color(pc, (0.1 + 0.25 * u * (0.8 + 0.2 * sin(time * 3.0))) * a) if won_match else Color(pc, 0.08 * a)
	var border := Color(pc, (0.4 + 0.45 * u) * a) if won_match else Color(pc, 0.35 * a)
	UiKit.panel_ex(self, r, Color(UiKit.COLOR_PANEL, 0.68 * a), border, 16, 2 if won_match and u > 0.0 else 1, glow,
		20 if won_match else 14)
	var cx := r.get_center().x
	UiKit.text_glow(self, Assets.font_title_heavy, Vector2(cx, r.position.y + 52.0), Run.player_label(k), 30,
		Color(pc.lerp(Color.WHITE, 0.2), a), pc, HORIZONTAL_ALIGNMENT_CENTER, 0.9)
	if won_match and u > 0.0:
		_draw_badge(r, u * a)
	# Status tag (EARTH SAVED / GAME OVER).
	var st := status_text(bool(Run.player_get(k, "out")), bool(Run.player_get(k, "won")))
	if st != "":
		var sc := UiKit.COLOR_GOOD if st == "EARTH SAVED" else UiKit.COLOR_DANGER
		var fs := UiKit.label_size(13)
		var tw := UiKit.spaced_width(Assets.font_body_bold, st, fs, 2.0)
		var tr := Rect2(cx - tw * 0.5 - 14.0, r.position.y + 70.0, tw + 28.0, 24.0)
		UiKit.panel_ex(self, tr, Color(sc.darkened(0.8), 0.8 * a), Color(sc, 0.6 * a), 12, 1)
		UiKit.text_spaced(self, Assets.font_body_bold, Vector2(cx, UiKit.baseline_for(Assets.font_body_bold, fs,
			tr.get_center().y)), st, fs, 2.0, Color(sc.lerp(Color.WHITE, 0.2), a), HORIZONTAL_ALIGNMENT_CENTER)
	# Score, counting up.
	var score := int(Run.player_get(k, "score"))
	var shown := int(round(score * _count_progress()))
	UiKit.text_spaced(self, Assets.font_body_bold, Vector2(cx, r.position.y + 128.0), "SCORE", UiKit.label_size(12), 3.0,
		Color(UiKit.COLOR_DIM, a), HORIZONTAL_ALIGNMENT_CENTER)
	var score_col := UiKit.COLOR_GOLD if won_match or w < 0 else UiKit.COLOR_TEXT
	UiKit.text_glow(self, Assets.font_title_heavy, Vector2(cx, r.position.y + 178.0), Fmt.score(shown), 44,
		Color(score_col, a), UiKit.COLOR_ACCENT if score_col == UiKit.COLOR_GOLD else UiKit.COLOR_HILITE,
		HORIZONTAL_ALIGNMENT_CENTER, 0.7 if won_match else 0.35)
	UiKit.divider(self, Vector2(cx, r.position.y + 204.0), PANEL_W - 60.0, Color(pc, 0.3 * a), 1.0)
	# Level reached, play time, ship.
	var lx := r.position.x + 30.0
	var rx := r.end.x - 30.0
	var lab := Color(UiKit.COLOR_DIM, a)
	var lvl := level_text(int(Run.player_get(k, "level")))
	var vs := UiKit.fit_size(Assets.font_title, lvl, 16, rx - lx - UiKit.text_width(Assets.font_body, "LEVEL", 16) - 16.0)
	_row(lx, rx, r.position.y + 240.0, "LEVEL", lvl, vs, lab, Color(UiKit.COLOR_TEXT, a))
	_row(lx, rx, r.position.y + 278.0, "PLAY TIME", Fmt.time(float(Run.player_get(k, "active_time"))), 16, lab,
		Color(UiKit.COLOR_TEXT, a))
	var ship_id := int(Run.player_get(k, "ship_id"))
	var ship: Dictionary = ShipData.ship(ship_id)
	var by := r.position.y + 316.0
	UiKit.text(self, Assets.font_body, Vector2(lx, by), "SHIP", 16, lab)
	var ship_name := String(ship["name"])
	UiKit.text(self, Assets.font_title, Vector2(rx, by), ship_name, 16,
		Color(Color(ship["accent"]).lerp(Color.WHITE, 0.35), a), HORIZONTAL_ALIGNMENT_RIGHT)
	UiKit.ship_icon(self, ship_id, Vector2(rx - UiKit.text_width(Assets.font_title, ship_name, 16) - 30.0, by - 6.0),
		40.0, Color(1, 1, 1, a))
	UiKit.divider(self, Vector2(cx, r.position.y + 258.0), PANEL_W - 60.0, Color(UiKit.COLOR_BORDER, 0.14 * a), 1.0)
	UiKit.divider(self, Vector2(cx, r.position.y + 296.0), PANEL_W - 60.0, Color(UiKit.COLOR_BORDER, 0.14 * a), 1.0)


func _row(lx: float, rx: float, by: float, label: String, value: String, size: int, lc: Color, vc: Color) -> void:
	UiKit.text(self, Assets.font_body, Vector2(lx, by), label, 16, lc)
	UiKit.text(self, Assets.font_title, Vector2(rx, by), value, size, vc, HORIZONTAL_ALIGNMENT_RIGHT)


## The WINNER badge on the top border of panel rect r.
static func badge_rect(r: Rect2) -> Rect2:
	var tw := UiKit.spaced_width(Assets.font_body_bold, "WINNER", UiKit.label_size(13), 3.0)
	return Rect2(r.get_center().x - tw * 0.5 - 16.0, r.position.y - BADGE_H * 0.5, tw + 32.0, BADGE_H)


## Gold "WINNER" badge on the winner panel's top border.
func _draw_badge(r: Rect2, a: float) -> void:
	var fs := UiKit.label_size(13)
	var font := Assets.font_body_bold
	var br := badge_rect(r)
	UiKit.panel_ex(self, br, Color(0.09, 0.06, 0.015, 0.96 * a), Color(UiKit.COLOR_GOLD, 0.85 * a), 12, 1,
		Color(UiKit.COLOR_GOLD, 0.25 * a), 10)
	UiKit.text_spaced(self, font, Vector2(br.get_center().x, UiKit.baseline_for(font, fs, br.get_center().y)), "WINNER",
		fs, 3.0, Color(UiKit.COLOR_GOLD, a), HORIZONTAL_ALIGNMENT_CENTER)


## 0 → 1 while the scores count up (eased).
func _count_progress() -> float:
	var u := clampf((time - COUNT_T0) / (COUNT_T1 - COUNT_T0), 0.0, 1.0)
	return 1.0 - pow(1.0 - u, 2.0)
