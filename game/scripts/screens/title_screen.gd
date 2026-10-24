extends ScreenBase
## Title screen (docs/SPEC.md §11, §12): logo, menu START GAME / DIFFICULTY / MUSIC / MUSIC VOLUME /
## SOUND EFFECTS / EFFECTS VOLUME / HIGHSCORES / QUIT. Up/down selects, left/right changes values, confirm
## activates. Keyboard: Enter/Space confirm, Escape quits. Controller: A/X/Y/Start confirm, Select/Back →
## highscores, B is ignored. Options persist via Settings and act immediately.
## Volumes (SPEC §14): left/right ±10 % with the controlled menu repeat; MUSIC VOLUME is heard live in the
## title music, EFFECTS VOLUME plays a short preview effect at the new gain. Confirm on them only previews.
## Attract mode (SPEC §11.1): after AttractDirector.IDLE_TIME (90) real seconds without any player input (key,
## mouse button, joypad button, D-pad, stick beyond 0.5) the title hands over to the demo; any input restarts
## the idle timer.
## finished: "start" | "highscores" | "quit" | "attract".
## setup args: {"select": <item id>} (optional initial selection), {"attract_after": <s>} (idle time, dev/tests),
##             {"preview_best": {name, score}} (dev screenshots only: BEST line while the stored list is empty).

const GAME_TITLE := "PLANET PROTECTOR"
const TAGLINE := "DEFEND THE SOLAR SYSTEM"
const ITEMS: Array[String] = ["start", "difficulty", "music", "music_volume", "sfx", "sfx_volume", "highscores",
	"quit"]
const LABELS := {"start": "START GAME", "difficulty": "DIFFICULTY", "music": "MUSIC", "music_volume": "MUSIC VOLUME",
	"sfx": "SOUND EFFECTS", "sfx_volume": "EFFECTS VOLUME", "highscores": "HIGHSCORES", "quit": "QUIT"}
## Binary ON/OFF items (left/right flips them).
const TOGGLES: Array[String] = ["music", "sfx"]
# Layout (960 × 720): logo + tagline on top, the 8-row menu panel, the two hint rows at the bottom.
const LOGO_W := 620.0
const LOGO_Y := 132.0           ## the letters start below the BEST line in the top-right corner
const MENU_Y := 292.0
const MENU_STEP := 41.0
const MENU_W := 500.0
const MENU_FONT := 19
const MENU_PAD := 34.0          ## panel margin above the first / below the last row centre
const HINT_Y := 664.0
const BEST_X := W - 26.0        ## right edge of the BEST line (name up to Settings.NAME_MAX = 8 characters)
const BEST_SIZE := 18

var _sel := 0
var _demons: Array[Dictionary] = []
var _best: Dictionary = {}
## Real seconds without player input (attract mode).
var idle := 0.0
var _attract_after := AttractDirector.IDLE_TIME


func _enter() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # logo.png is imported with mipmaps
	AudioManager.play_title_music()
	_sel = maxi(ITEMS.find(String(args.get("select", "start"))), 0)
	_attract_after = float(args.get("attract_after", AttractDirector.IDLE_TIME))
	_spawn_demons()
	_refresh_best()


func _refresh_best() -> void:
	var list := Settings.get_highscores(Settings.difficulty)
	_best = list[0] if not list.is_empty() else args.get("preview_best", {})


func _star_velocity() -> Vector2:
	return Vector2(-10, 2)


func _spawn_demons() -> void:
	# A few demons of different planets patrol the free space beside the menu panel (like the game's lanes):
	# two on the left, one on the right.
	var defs := [
		{"level": 2, "y": 335.0, "x": 70.0, "dir": 1.0, "speed": 30.0, "scale": 0.56, "min": 48.0, "max": 140.0},
		{"level": 11, "y": 530.0, "x": 120.0, "dir": -1.0, "speed": 26.0, "scale": 0.56, "min": 48.0, "max": 140.0},
		{"level": 17, "y": 430.0, "x": 880.0, "dir": -1.0, "speed": 28.0, "scale": 0.58, "min": 820.0, "max": 912.0},
	]
	for d: Dictionary in defs:
		var e := EnemyArt.new()
		e.configure(int(d["level"]))
		e.scale_factor = float(d["scale"])
		e.z_index = -1
		e.modulate = Color(1, 1, 1, 0.72)
		add_child(e)
		var st := d.duplicate()
		st["node"] = e
		st["phase"] = randf() * TAU
		st["flap"] = randf()
		_demons.append(st)
	_update_demons(0.0)


func _update_demons(delta: float) -> void:
	for d in _demons:
		var e: EnemyArt = d["node"]
		var x := float(d["x"]) + float(d["dir"]) * float(d["speed"]) * delta
		if x < float(d["min"]) or x > float(d["max"]):
			d["dir"] = -float(d["dir"])
			x = clampf(x, float(d["min"]), float(d["max"]))
		d["x"] = x
		d["flap"] = fposmod(float(d["flap"]) + LevelData.FLAP_HZ * delta, 1.0)
		e.position = Vector2(x, float(d["y"]) + 12.0 * sin(float(d["phase"]) + TAU * 0.55 * time))
		e.flap_phase = float(d["flap"])
		e.queue_redraw()


func _input(event: InputEvent) -> void:
	if AttractDirector.is_player_input(event):
		idle = 0.0


func _tick(delta: float) -> void:
	_update_demons(delta)
	if _update_idle(delta):
		finish("attract")
		return
	var dir := InputRouter.menu_direction()
	if dir.y != 0:
		_sel = posmod(_sel + dir.y, ITEMS.size())
		sfx("menu_move")
	elif dir.x != 0 and accepts_step(ITEMS[_sel], InputRouter.menu_direction_is_repeat()):
		_change(ITEMS[_sel], dir.x)
	if InputRouter.confirm_pressed(true):
		_activate(ITEMS[_sel])
	elif InputRouter.just_pressed(InputRouter.B.ESCAPE):
		sfx("menu_back")
		finish("quit")
	elif InputRouter.highscores_pressed():
		sfx("menu_confirm")
		finish("highscores")


## Idle timer of the attract mode: input events reset it (_input), so does anything held. True once the demo is due.
func _update_idle(delta: float) -> bool:
	idle = 0.0 if AttractDirector.input_held() else idle + delta
	return idle >= _attract_after


## ON/OFF options flip once per press: auto-repeat steps of a held direction are ignored for them
## (otherwise holding Left/Right would flicker the setting and rewrite settings.cfg ~9x per second).
## DIFFICULTY keeps cycling and the volumes keep stepping (clamped at 0 % / 100 %) with the controlled repeat.
static func accepts_step(item: String, is_repeat: bool) -> bool:
	return not (is_repeat and TOGGLES.has(item))


func _change(item: String, step: int) -> void:
	match item:
		"difficulty":
			Settings.set_difficulty(Settings.difficulty + step)
			_refresh_best()
			sfx("menu_move")
		"music":
			Settings.set_music_on(not Settings.music_on)
			AudioManager.apply_settings()
			if Settings.music_on:
				AudioManager.play_title_music()
			sfx("menu_move")
		"sfx":
			Settings.set_sfx_on(not Settings.sfx_on)
			AudioManager.apply_settings()
			sfx("menu_move")
		"music_volume", "sfx_volume":
			if not Settings.step_volume(item, step):
				return   # already at 0 % / 100 %
			AudioManager.apply_settings()   # at once (Settings.changed does it too once the autoloads run)
			_volume_feedback(item)


## Sound after a volume change: the effects preview (at the new gain) for EFFECTS VOLUME; for MUSIC VOLUME
## the title music itself is the feedback, plus the usual soft menu blip.
func _volume_feedback(item: String) -> void:
	sfx(AudioManager.VOLUME_PREVIEW_SFX if item == "sfx_volume" else "menu_move")


func _activate(item: String) -> void:
	match item:
		"start":
			sfx("menu_confirm")
			finish("start")
		"highscores":
			sfx("menu_confirm")
			finish("highscores")
		"quit":
			sfx("menu_back")
			finish("quit")
		"music_volume", "sfx_volume":
			_volume_feedback(item)   # confirm does not change a volume (no accidental wrap to 0 %)
		_:
			_change(item, 1)


func _value(item: String) -> String:
	match item:
		"difficulty":
			return String(ShipData.difficulty(Settings.difficulty)["name"])
		"music":
			return "ON" if Settings.music_on else "OFF"
		"sfx":
			return "ON" if Settings.sfx_on else "OFF"
	return ""


# --- Drawing -------------------------------------------------------------------------------------
func _draw() -> void:
	_draw_logo()
	# Menu
	UiKit.panel(self, menu_panel_rect(), 0.55)
	for i in ITEMS.size():
		var item := ITEMS[i]
		var selected := i == _sel
		var c := Vector2(CX, MENU_Y + i * MENU_STEP)
		if Settings.VOLUME_ITEMS.has(item):
			# The bar is dimmed while the matching ON/OFF option is OFF.
			UiKit.menu_item_volume(self, c, LABELS[item], Settings.volume(item), selected, time, MENU_W, MENU_FONT,
				Settings.volume_switch_on(item))
		else:
			UiKit.menu_item(self, c, LABELS[item], _value(item), selected, time, MENU_W, MENU_FONT)
	_draw_best()
	_draw_hints()


## Backing panel of the menu (all rows plus MENU_PAD above and below).
static func menu_panel_rect() -> Rect2:
	var top := MENU_Y - MENU_PAD
	return Rect2(CX - MENU_W * 0.5 - 40.0, top, MENU_W + 80.0, MENU_STEP * (ITEMS.size() - 1) + MENU_PAD * 2.0)


func _draw_logo() -> void:
	var float_y := sin(time * 0.9) * 3.0
	var logo := Assets.logo_texture()
	var center := Vector2(CX, LOGO_Y + float_y)
	UiKit.glow_spot(self, center + Vector2(0, 8), Vector2(400, 128), Color(1.0, 0.35, 0.08, 0.13))
	var bottom := 0.0
	if logo:
		var w := LOGO_W
		var h := w * float(logo.get_height()) / float(logo.get_width())
		draw_texture_rect(logo, Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h)), false)
		bottom = center.y + h * 0.5
	else:
		# Fallback while the rendered logo is missing: big fiery Orbitron lettering.
		var font := Assets.font_title_heavy
		var size := UiKit.fit_size(font, GAME_TITLE, 72, LOGO_W)
		var base := center.y + size * 0.36
		UiKit.text_glow(self, font, Vector2(CX, base + 3.0), GAME_TITLE, size, Color(0.55, 0.08, 0.02),
			Color(1.0, 0.3, 0.05), HORIZONTAL_ALIGNMENT_CENTER, 1.6)
		UiKit.text(self, font, Vector2(CX, base), GAME_TITLE, size, Color(1.0, 0.78, 0.38),
			HORIZONTAL_ALIGNMENT_CENTER)
		bottom = center.y + size * 0.6
	var tag_y := bottom + 22.0
	var half := UiKit.spaced_width(Assets.font_title, TAGLINE, 14, 6.0) * 0.5
	UiKit.divider(self, Vector2(CX - half - 80, tag_y - 6), 130, Color(1.0, 0.6, 0.2, 0.7))
	UiKit.divider(self, Vector2(CX + half + 80, tag_y - 6), 130, Color(1.0, 0.6, 0.2, 0.7))
	UiKit.text_spaced(self, Assets.font_title, Vector2(CX, tag_y), TAGLINE, 14, 6.0, UiKit.COLOR_ACCENT,
		HORIZONTAL_ALIGNMENT_CENTER)


## "NAME  SCORE" of the best entry (drawn right-aligned at BEST_X in font_title, BEST_SIZE).
static func best_text(entry: Dictionary) -> String:
	return "%s  %s" % [entry["name"], Fmt.score(int(entry["score"]))]


func _draw_best() -> void:
	if _best.is_empty():
		return
	var diff_name := String(ShipData.difficulty(Settings.difficulty)["name"])
	UiKit.text(self, Assets.font_body, Vector2(BEST_X, 32), "BEST · %s" % diff_name, 13, UiKit.COLOR_FAINT,
		HORIZONTAL_ALIGNMENT_RIGHT)
	UiKit.text(self, Assets.font_title, Vector2(BEST_X, 56), best_text(_best), BEST_SIZE, UiKit.COLOR_GOLD,
		HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_hints() -> void:
	UiKit.hint_bar(self, Vector2(CX, HINT_Y), [
		[["UD"], "Select"], [["LR"], "Change"], [["ENTER", "pad:A"], "Confirm"],
	], 14)
	UiKit.hint_bar(self, Vector2(CX, HINT_Y + 29.0), [
		[["pad:BACK"], "Highscores"], [["ESC"], "Quit"], [["F11"], "Fullscreen"],
	], 13, UiKit.COLOR_FAINT)
