extends ScreenBase
## Victory after level 20 (docs/SPEC.md §11): Earth big in the background, the exact
## LevelData.VICTORY_TEXT, final score and time. Confirm → finished("continue") (Main then opens the
## name entry if the score qualifies, else the highscores).
## Two players (SPEC §19.2): setup {"match": true} – shown once when round 20 is over and someone saved Earth; the
## stats row shows both players' scores (labels in the player colours; under each "EARTH SAVED" or the level the
## player was out in) around the difficulty. Main then opens the match result.

const CONFIRM_DELAY := 1.5
## The Earth drawn here: the in-game planet rendered again with a 1280 px sphere (tools/blender/planets_hd.py,
## same textures, view and lighting). The victory Earth is up to 1280 logical px wide and the 16:9 modes render
## at ×1.5 / ×2.0, so the 640 px in-game sprite would be blown up 3× / 4×; this one is at most 2× (2560×1440),
## 1.5× at 1080p and 1:1 in the classic 1280 × 960 window. Falls back to the in-game sprite if it is missing.
const EARTH_ASSET := "earth_hd"
const EARTH_FALLBACK := "earth"

var _sparks: Array[Vector4] = []   # x, y, speed, phase
var _earth := EARTH_ASSET
var _match := false


func _enter() -> void:
	AudioManager.stop_music()
	# Smooth (linear + mipmaps, like the title) instead of the project's nearest filter: the big Earth is scaled
	# up to the window / render resolution and nearest sampling would show its texels as blocks.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_earth = earth_asset()
	_match = bool(args.get("match", false))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2020
	# Spread over the whole canvas (1280 wide in 16:9: proportionally more of them).
	for i in roundi(46.0 * sw / W):
		_sparks.append(Vector4(left_x() + rng.randf() * sw, rng.randf() * H, rng.randf_range(10.0, 32.0),
			rng.randf() * TAU))


func _star_velocity() -> Vector2:
	return Vector2(-6, 0)


## Planet asset of the victory Earth: EARTH_ASSET, or the in-game EARTH_FALLBACK if that file is missing.
static func earth_asset() -> String:
	return EARTH_ASSET if ResourceLoader.exists(Assets.SPRITES + "planets/%s.png" % EARTH_ASSET) else EARTH_FALLBACK


## Diameter (logical px) of the risen victory Earth on a canvas canvas_w wide: it fills the canvas width
## (960 in 4:3, 1280 in 16:9, 1152 in the 16:10 Steam Deck mode).
static func earth_diameter(canvas_w: float) -> float:
	return 960.0 * canvas_w / W


func _tick(_delta: float) -> void:
	if time >= CONFIRM_DELAY and InputRouter.confirm_pressed():
		sfx("menu_confirm")
		finish("continue")


func _draw() -> void:
	# Earth rising from below, big, with a soft atmosphere glow. It fills the canvas width (960, 1280 or 1152) and always
	# shows the same cap height (its top at y = 425 once risen).
	var rise := 1.0 - ramp(0.0, 3.5)
	var d := earth_diameter(sw)
	var c := Vector2(CX, 425.0 + d * 0.5 + 110.0 * rise)
	UiKit.glow_spot(self, c, Vector2(d, d) * 0.64, Color(0.35, 0.6, 1.0, 0.34))
	Assets.draw_planet(self, _earth, c, d)
	# Thin bright atmosphere rim on top of the sphere.
	draw_arc(c, d * 0.5 + 1.5, PI * 1.08, PI * 1.92, 96, Color(0.55, 0.8, 1.0, 0.35), 3.0, true)
	# Golden sparkles drifting up.
	for s in _sparks:
		var y := fposmod(s.y - s.z * time, H)
		var twinkle := 0.5 + 0.5 * sin(time * 2.0 + s.w)
		UiKit.glow_spot(self, Vector2(s.x + 6.0 * sin(time * 0.7 + s.w), y), Vector2(5, 5) * (0.6 + twinkle),
			Color(1.0, 0.85, 0.45, 0.35 * twinkle * ramp(0.5, 1.0)))
	var a := ramp(0.2, 0.6)
	UiKit.text_spaced(self, Assets.font_title, Vector2(CX, 70), "EARTH IS SAFE", 16, 8.0,
		Color(UiKit.COLOR_HILITE, a), HORIZONTAL_ALIGNMENT_CENTER)
	draw_title("VICTORY!", 128, 54, Color(UiKit.COLOR_GOLD, a), UiKit.COLOR_ACCENT)
	# The victory text, balanced wrap, revealed line by line.
	var font := Assets.font_body
	var size := 25
	var lines := UiKit.wrap_balanced(font, LevelData.VICTORY_TEXT, size, 760.0)
	var lh := 38.0
	var y0 := 205.0
	var tw := 0.0
	for line in lines:
		tw = maxf(tw, UiKit.text_width(font, line, size))
	var pw := tw + 90.0
	var panel := Rect2(CX - pw * 0.5, y0 - 40, pw, lines.size() * lh + 34)
	UiKit.panel(self, panel, 0.5 * a)
	for i in lines.size():
		var la := ramp(0.7 + i * 0.35, 0.5)
		UiKit.text(self, font, Vector2(CX, y0 + lh * i + (1.0 - la) * 6.0), lines[i], size, Color(UiKit.COLOR_TEXT, la),
			HORIZONTAL_ALIGNMENT_CENTER)
	# Final stats
	var sa := ramp(0.9 + lines.size() * 0.35, 0.5)
	var sy := panel.end.y + 70.0
	if _match:
		for k in 2:
			_stat(CX + (k * 2 - 1) * 230, sy, Run.player_label(k), Fmt.score(int(Run.player_get(k, "score"))),
				UiKit.COLOR_GOLD, sa, UiKit.player_color(k))
			_player_note(CX + (k * 2 - 1) * 230, sy + 30, k, sa)
		_stat(CX, sy, "DIFFICULTY", Run.difficulty_name(), UiKit.COLOR_ACCENT, sa)
	else:
		_stat(CX - 230, sy, "FINAL SCORE", Fmt.score(Run.score), UiKit.COLOR_GOLD, sa)
		_stat(CX, sy, "PLAY TIME", Fmt.time(Run.active_time), UiKit.COLOR_TEXT, sa)
		_stat(CX + 230, sy, "DIFFICULTY", Run.difficulty_name(), UiKit.COLOR_ACCENT, sa)
	draw_continue_hint("Continue", CONFIRM_DELAY)


## Small line under a player's score (two players): "EARTH SAVED" or "GAME OVER · LEVEL n".
func _player_note(x: float, baseline: float, k: int, a: float) -> void:
	var won := bool(Run.player_get(k, "won"))
	var s := "EARTH SAVED" if won else "GAME OVER · LEVEL %d" % int(Run.player_get(k, "level"))
	UiKit.text_outlined(self, Assets.font_body_bold, Vector2(x, baseline), s, UiKit.label_size(13),
		Color(UiKit.COLOR_GOOD if won else UiKit.COLOR_DIM, a), Color(0, 0, 0, 0.6 * a), 4, HORIZONTAL_ALIGNMENT_CENTER)


func _stat(x: float, baseline: float, label: String, value: String, col: Color, a: float,
		label_col: Color = UiKit.COLOR_DIM) -> void:
	UiKit.text(self, Assets.font_body, Vector2(x, baseline - 34), label, 15, Color(label_col, a),
		HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.text_outlined(self, Assets.font_title, Vector2(x, baseline), value, 28, Color(col, a), Color(0, 0, 0, 0.6 * a), 6,
		HORIZONTAL_ALIGNMENT_CENTER)
