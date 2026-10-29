extends ScreenBase
## Hand-over between the two players of a hotseat match (docs/SPEC.md §19.2). Two kinds:
## - "locks" (match setup, between the two SHIP LOCK screens; k = who takes the controller now, the other one just
##   locked): "PLAYER j READY" with a check mark, "Pass the controller to PLAYER k" and "PLAYER j – LOOK AWAY!". It
##   shows NO lock information (hidden until LOCK REVEAL). Title music like the other setup screens; confirm also
##   with Space / A (Enter / Space / A / X / Y / Start), like the ship lock / ship select.
## - "turn" (before a level whenever the player changes): big "PLAYER k" in the player colour, "GET READY", the level
##   ("LEVEL n • <name>", the bonus level "BONUS ROUND") under its planet, the player's score / lives (ship icons) /
##   ship, the other player's score or GAME OVER, and with POWER-UPS on a level that has one "POWER-UP THIS LEVEL:
##   <NAME>" with its keys (Shift / pad X). Silent: it sits between two levels like the interlevel (whose confirm
##   sound may still ring) – the title music would only start for a few seconds and be cut by the level start, and
##   after an arrival the silence carries on into the next battle. Confirm with Enter / X / Y / Start like every
##   in-match screen (A / B are fire buttons in the game).
## Confirm is ignored for CONFIRM_DELAY s → finished("continue"). Escape / B do nothing (no way back from here).
## setup args: {"kind": "locks", "player": k} | {"kind": "turn", "player": k, "level": n}. The turn kind reads both
## players' state through Run.player_get.

const CONFIRM_DELAY := 0.6
# "locks" layout
const CHECK_Y := 150.0          ## centre of the check badge
const READY_Y := 258.0
const NOTE_Y := 296.0
const PASS_Y := 380.0
const PASS_NAME_Y := 444.0
const WARN_Y := 532.0           ## centre of the LOOK AWAY banner
const LOCKS_NOTE := "Ship locks set – they stay secret until both players are done"
# "turn" layout
const PLANET_Y := 144.0
const PLANET_D := 130.0         ## sphere diameter …
const PLANET_BOX_H := 232.0     ## … unless the whole image (rings) would be taller than this (Uranus' tilted ring)
const LEVEL_Y := 286.0
const NAME_Y := 368.0
const NAME_SIZE := 64
const BAND_H := 40.0            ## the band lines above / below the name's centre
const READY_SPACED_Y := 413.0
const PANEL := Rect2(CX - 290.0, 440.0, 580.0, 92.0)
const PANEL_CAPTIONS: Array[String] = ["SCORE", "LIVES", "SHIP"]
const OTHER_Y := 565.0
const POWERUP_Y := 613.0        ## centre of the power-up pill
## Power-up line: caption, name and the keys that trigger it (Shift / pad X, SPEC §19.3).
const POWERUP_CAPTION := "POWER-UP THIS LEVEL:"
const POWERUP_KEYS: Array[String] = ["SHIFT", "pad:X"]
const POWERUP_KEY_SIZE := 14

var kind := "turn"
## Player who takes the controller / plays now.
var player := 0
var level := 1


func _enter() -> void:
	kind = "locks" if String(args.get("kind", "turn")) == "locks" else "turn"
	player = clampi(int(args.get("player", 0)), 0, 1)
	level = clampi(int(args.get("level", Run.level)), LevelData.FIRST_LEVEL, LevelData.LAST_LEVEL)
	if kind == "locks":
		AudioManager.play_title_music()
	else:
		AudioManager.stop_music()


func _star_velocity() -> Vector2:
	return Vector2(-10, 2) if kind == "locks" else Vector2(-16, 0)


func _tick(_delta: float) -> void:
	if guarded_confirm(kind == "locks", CONFIRM_DELAY):
		sfx("menu_confirm")
		finish("continue")


## The player who just finished (locks) / waits (turn).
func other() -> int:
	return 1 - player


## Power-up of the level shown on the turn screen (NONE without POWER-UPS or on a level without one).
func powerup() -> int:
	return LevelData.powerup_of(level) if Run.powerups else LevelData.PowerUp.NONE


## Sphere diameter of the turn screen's planet: PLANET_D, smaller if its image (with rings) is taller than
## PLANET_BOX_H (the images are centred on the sphere).
static func planet_size(planet: String) -> float:
	var info := Assets.planet_info(planet)
	var tex: Texture2D = info["texture"]
	return minf(PLANET_D, PLANET_BOX_H * float(info["sphere_diameter_px"]) / float(tex.get_height()))


## Height of the turn screen's planet image (rings included).
static func planet_image_h(planet: String) -> float:
	var info := Assets.planet_info(planet)
	var tex: Texture2D = info["texture"]
	return planet_size(planet) * float(tex.get_height()) / float(info["sphere_diameter_px"])


## "LEVEL 7 – SATURN 1" / "LEVEL 13 – BONUS ROUND".
static func level_line(n: int) -> String:
	if n == LevelData.BONUS_LEVEL:
		return "LEVEL %d  •  BONUS ROUND" % n
	# "•": Orbitron has no "·", and "–" would clash with level 20's own dash ("EARTH – FINAL BATTLE").
	return "LEVEL %d  •  %s" % [n, String(LevelData.level(n)["name"]).to_upper()]


## Status of the waiting player on the turn screen: "EARTH SAVED" (completed level 20), "GAME OVER" (out) or "".
static func status_text(out: bool, won: bool) -> String:
	if won:
		return "EARTH SAVED"
	return "GAME OVER" if out else ""


# --- Drawing -------------------------------------------------------------------------------------
func _draw() -> void:
	if kind == "locks":
		_draw_locks()
	else:
		_draw_turn()


func _draw_locks() -> void:
	var done_c := UiKit.player_color(other())
	var next_c := UiKit.player_color(player)
	var a := ramp(0.0, 0.35)
	# Check badge: the other player's locks are set.
	var k := ramp(0.05, 0.3)
	var s := 0.7 + 0.3 * k
	var c := Vector2(CX, CHECK_Y)
	UiKit.glow_spot(self, c, Vector2(110, 110) * s, Color(done_c, 0.16 * k))
	draw_circle(c, 46.0 * s, Color(done_c.darkened(0.8), 0.9 * k), true, -1.0, true)
	draw_circle(c, 46.0 * s, Color(done_c, 0.85 * k), false, 3.0, true)
	UiKit.check_icon(self, c + Vector2(0, 2) * s, 48.0 * s, Color(done_c.lerp(Color.WHITE, 0.3), k))
	draw_title("%s READY" % Run.player_label(other()), READY_Y, 40, Color(done_c.lerp(Color.WHITE, 0.25), a), done_c)
	UiKit.text(self, Assets.font_body, Vector2(CX, NOTE_Y), LOCKS_NOTE, 17, Color(UiKit.COLOR_DIM, a),
		HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.divider(self, Vector2(CX, (NOTE_Y + PASS_Y) * 0.5 - 6.0), 520, Color(UiKit.COLOR_BORDER, 0.3 * a), 1.0)
	var b := ramp(0.25, 0.4)
	UiKit.text(self, Assets.font_body, Vector2(CX, PASS_Y), "Pass the controller to", 22,
		Color(UiKit.COLOR_TEXT, 0.85 * b), HORIZONTAL_ALIGNMENT_CENTER)
	var pulse := 0.85 + 0.15 * sin(time * 3.0)
	draw_title(Run.player_label(player), PASS_NAME_Y + (1.0 - b) * 10.0, 54, Color(next_c.lerp(Color.WHITE, 0.2), b),
		Color(next_c, pulse))
	UiKit.look_away_banner(self, Vector2(CX, WARN_Y), "%s – LOOK AWAY!" % Run.player_label(other()), done_c, time, 22,
		ramp(0.45, 0.35))
	_draw_hint([[["ENTER", "pad:A"], "%s: Continue" % Run.player_label(player)]])


func _draw_turn() -> void:
	var pc := UiKit.player_color(player)
	var a := ramp(0.0, 0.35)
	# The level's planet, sinking a little into place.
	var planet := LevelData.planet_of(level)
	var pa := ramp(0.0, 0.7)
	UiKit.glow_spot(self, Vector2(CX, PLANET_Y), Vector2(170, 170), Color(pc, 0.08 * pa))
	Assets.draw_planet(self, planet, Vector2(CX, PLANET_Y - 12.0 * (1.0 - ramp(0.0, 1.0))), planet_size(planet),
		Color(1, 1, 1, pa))
	UiKit.text_spaced(self, Assets.font_title, Vector2(CX, LEVEL_Y), level_line(level), 18, 3.0,
		Color(UiKit.COLOR_HILITE.lerp(Color.WHITE, 0.2), a), HORIZONTAL_ALIGNMENT_CENTER)
	# Light band behind the name (like the level intro banner): a dark glow with two thin lines in the player colour
	# that sweep open.
	var e := 1.0 - pow(1.0 - ramp(0.0, 0.45), 3.0)
	var band_w := 420.0 + 380.0 * e
	var mid := NAME_Y - NAME_SIZE * 0.36
	UiKit.glow_spot(self, Vector2(CX, mid), Vector2(band_w * 0.62, 64.0), Color(pc.darkened(0.85), 0.6 * a))
	UiKit.divider(self, Vector2(CX, mid - BAND_H), band_w, Color(pc, 0.6 * a), 2.0)
	UiKit.divider(self, Vector2(CX, mid + BAND_H), band_w, Color(pc, 0.6 * a), 2.0)
	var s := 1.0 + 0.1 * (1.0 - ramp(0.0, 0.4))
	draw_set_transform(Vector2(CX, NAME_Y - NAME_SIZE * 0.36), 0.0, Vector2(s, s))
	UiKit.text_glow(self, Assets.font_title_heavy, Vector2(0, NAME_SIZE * 0.36), Run.player_label(player), NAME_SIZE,
		Color(pc.lerp(Color.WHITE, 0.25), a), pc, HORIZONTAL_ALIGNMENT_CENTER, 1.3)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	UiKit.text_spaced(self, Assets.font_title, Vector2(CX, READY_SPACED_Y), "GET READY", 17, 9.0,
		Color(UiKit.COLOR_TEXT, a * (0.75 + 0.25 * sin(time * 4.0))), HORIZONTAL_ALIGNMENT_CENTER)
	_draw_turn_panel(ramp(0.2, 0.35))
	_draw_other(ramp(0.3, 0.35))
	if powerup() != LevelData.PowerUp.NONE:
		_draw_powerup(ramp(0.4, 0.35))
	draw_continue_hint("Start", CONFIRM_DELAY)


## SCORE | LIVES | SHIP of the player whose turn it is.
func _draw_turn_panel(a: float) -> void:
	var r := PANEL
	UiKit.panel(self, r, 0.62 * a)
	var cols := [r.position.x + r.size.x / 6.0, r.get_center().x, r.end.x - r.size.x / 6.0]
	var cap_y := r.position.y + 30.0
	var val_y := r.position.y + 66.0
	var cap_size := UiKit.label_size(12)
	var cap_col := Color(UiKit.COLOR_DIM, a)
	for i in PANEL_CAPTIONS.size():
		UiKit.text_spaced(self, Assets.font_body_bold, Vector2(cols[i], cap_y), PANEL_CAPTIONS[i], cap_size, 2.0, cap_col,
			HORIZONTAL_ALIGNMENT_CENTER)
	for x: float in [r.position.x + r.size.x / 3.0, r.end.x - r.size.x / 3.0]:
		draw_line(Vector2(x, r.position.y + 16.0), Vector2(x, r.end.y - 16.0), Color(UiKit.COLOR_BORDER, 0.2 * a), 1.0)
	UiKit.text(self, Assets.font_title, Vector2(cols[0], val_y), Fmt.score(int(Run.player_get(player, "score"))), 24,
		Color(UiKit.COLOR_GOLD, a), HORIZONTAL_ALIGNMENT_CENTER)
	var ship_id := int(Run.player_get(player, "ship_id"))
	_draw_lives(Vector2(cols[1], val_y - 8.0), int(Run.player_get(player, "lives")), ship_id, a)
	var ship: Dictionary = ShipData.ship(ship_id)
	var ship_name := String(ship["name"])
	var fs := UiKit.fit_size(Assets.font_title, ship_name, 17, r.size.x / 3.0 - 24.0)
	UiKit.text(self, Assets.font_title, Vector2(cols[2], val_y - 1.0), ship_name, fs,
		Color(Color(ship["accent"]).lerp(Color.WHITE, 0.35), a), HORIZONTAL_ALIGNMENT_CENTER)


## Lives as ship icons (like the HUD): up to 5 icons; more as one icon + "×n" (fits the panel column).
func _draw_lives(c: Vector2, n: int, ship_id: int, a: float) -> void:
	var w := 30.0
	var gap := 4.0
	var shown := n if n <= 5 else 1
	var extra := "×%d" % n if n > 5 else ""
	var total := shown * w + maxf(shown - 1, 0) * gap
	if extra != "":
		total += 8.0 + UiKit.text_width(Assets.font_title, extra, 15)
	var x := c.x - total * 0.5
	for i in shown:
		UiKit.ship_icon(self, ship_id, Vector2(x + w * 0.5, c.y), w, Color(1, 1, 1, a))
		x += w + gap
	if extra != "":
		UiKit.text(self, Assets.font_title, Vector2(x + 4.0, c.y + 6.0), extra, 15, Color(UiKit.COLOR_TEXT, a))
	elif n <= 0:
		UiKit.text(self, Assets.font_title, Vector2(c.x, c.y + 6.0), "—", 15, Color(UiKit.COLOR_FAINT, a),
			HORIZONTAL_ALIGNMENT_CENTER)


## The waiting player, small: "PLAYER 1   12345" or "PLAYER 1   GAME OVER   12345".
func _draw_other(a: float) -> void:
	var j := other()
	var parts: Array = [[Run.player_label(j), Assets.font_body_bold, UiKit.player_color(j)]]
	var st := status_text(bool(Run.player_get(j, "out")), bool(Run.player_get(j, "won")))
	if st != "":
		parts.append([st, Assets.font_body_bold, UiKit.COLOR_DANGER if st == "GAME OVER" else UiKit.COLOR_GOOD])
	parts.append([Fmt.score(int(Run.player_get(j, "score"))), Assets.font_title, UiKit.COLOR_TEXT])
	var gap := 18.0
	var total := -gap
	for p: Array in parts:
		total += UiKit.text_width(p[1], String(p[0]), 16) + gap
	var x := CX - total * 0.5
	for p: Array in parts:
		UiKit.text(self, p[1], Vector2(x, OTHER_Y), String(p[0]), 16, Color(p[2], 0.8 * a))
		x += UiKit.text_width(p[1], String(p[0]), 16) + gap


## Widths of the power-up line's parts: [caption, name, keys] (caption and name 16 / 17 px, keys as hint glyphs).
static func powerup_widths(pname: String) -> Array[float]:
	var gw := POWERUP_KEY_SIZE * 0.9 * (POWERUP_KEYS.size() - 1)
	for g in POWERUP_KEYS:
		gw += UiKit.glyph_width(g, POWERUP_KEY_SIZE)
	return [UiKit.text_width(Assets.font_body_bold, POWERUP_CAPTION, 16), UiKit.text_width(Assets.font_title, pname, 17), gw]


## The gold pill around the power-up line.
static func powerup_rect(pname: String) -> Rect2:
	var w := powerup_widths(pname)
	var total := w[0] + 10.0 + w[1] + 22.0 + w[2]
	return Rect2(CX - total * 0.5 - 22.0, POWERUP_Y - 19.0, total + 44.0, 38.0)


## "POWER-UP THIS LEVEL: RAPID FIRE   [SHIFT] / (X)" on a dark pill with a gold rim.
func _draw_powerup(a: float) -> void:
	var pname := String(LevelData.POWERUP_NAMES[powerup()])
	var w := powerup_widths(pname)
	var r := powerup_rect(pname)
	var pulse := 0.5 + 0.5 * sin(time * 3.0)
	UiKit.panel_ex(self, r, Color(0.08, 0.06, 0.01, 0.85 * a), Color(UiKit.COLOR_GOLD, (0.45 + 0.3 * pulse) * a),
		19, 1, Color(UiKit.COLOR_GOLD, 0.15 * a), 12)
	var x := r.position.x + 22.0
	UiKit.text(self, Assets.font_body_bold, Vector2(x, UiKit.baseline_for(Assets.font_body_bold, 16, POWERUP_Y)),
		POWERUP_CAPTION, 16, Color(UiKit.COLOR_DIM.lerp(UiKit.COLOR_TEXT, 0.3), a))
	x += w[0] + 10.0
	UiKit.text(self, Assets.font_title, Vector2(x, UiKit.baseline_for(Assets.font_title, 17, POWERUP_Y)), pname, 17,
		Color(UiKit.COLOR_GOLD, a))
	x += w[1] + 22.0
	var ks := POWERUP_KEY_SIZE
	for i in POWERUP_KEYS.size():
		x += UiKit.glyph(self, POWERUP_KEYS[i], x, POWERUP_Y, ks, Color(UiKit.COLOR_TEXT, 0.85 * a))
		if i < POWERUP_KEYS.size() - 1:
			UiKit.text(self, Assets.font_body, Vector2(x + ks * 0.45, UiKit.baseline_for(Assets.font_body, ks, POWERUP_Y)),
				"/", ks, Color(UiKit.COLOR_DIM, 0.6 * a), HORIZONTAL_ALIGNMENT_CENTER)
			x += ks * 0.9


## Hint bar of the setup kind (fades in after CONFIRM_DELAY like the standard continue hint).
func _draw_hint(items: Array) -> void:
	var a := ramp(CONFIRM_DELAY, 0.35)
	if a <= 0.0:
		return
	var col := UiKit.COLOR_DIM.lerp(UiKit.COLOR_TEXT, 0.25)
	col.a = a * (0.78 + 0.22 * sin(time * 3.0))
	UiKit.hint_bar(self, Vector2(CX, CONTINUE_HINT_Y), items, CONTINUE_HINT_SIZE, col, a)
