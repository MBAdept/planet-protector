extends ScreenBase
## Arrival sequence after levels 3, 6, 9, 12, 16 (docs/SPEC.md §11). COMPLETELY SILENT.
## Exact timeline (real seconds):
##   0–3 s   small stars stream from right to left (fast)
##   3–6 s   the message fades in (stars keep streaming)
##   6–7 s   the message slides out to the left (stars slow down)
##   7–12 s  the target planet appears small in the centre and zooms in for 5 s
##   ≥ 12 s  "Press ENTER to continue" – confirm → finished("continue")
## setup args: {"level": n} with n ∈ LevelData.ARRIVAL_AFTER.

const T_MSG_IN := 3.0
const T_MSG_OUT := 6.0
const T_PLANET := 7.0
const T_END := 12.0
const STREAM_SPEED := 1100.0
const DRIFT_SPEED := 30.0
const PLANET_D0 := 10.0
const PLANET_D1 := 400.0
## Sounds still ringing from the previous screen (the tail of the level_complete jingle) are faded out
## over this time, then the SFX bus stays muted until the arrival leaves the tree.
const SFX_FADE := 0.08
const PROMPT := "Press ENTER to continue"
const PROMPT_Y := 640.0

var _n := 3
var _text := ""
var _target := "uranus"
var _sfx_bus := -1
var _sfx_bus_db := 0.0


func _enter() -> void:
	# Completely silent (SPEC §11/§14): no music, and no sound effect - neither one of ours nor one that
	# was started before the hand-over.
	AudioManager.stop_music()
	_sfx_bus = AudioServer.get_bus_index(AudioManager.BUS_SFX)
	if _sfx_bus >= 0:
		_sfx_bus_db = AudioServer.get_bus_volume_db(_sfx_bus)
	_update_silence()
	_n = int(args.get("level", 3))
	if not LevelData.ARRIVAL_AFTER.has(_n):
		_n = 3
	_text = LevelData.ARRIVAL_AFTER[_n]["text"]
	_target = LevelData.ARRIVAL_AFTER[_n]["target"]
	starfield.velocity = Vector2(-STREAM_SPEED, 0)


func _use_fade() -> bool:
	return false


func _star_velocity() -> Vector2:
	return Vector2(-STREAM_SPEED, 0)


## Stream speed: fast from the start (short ramp-up), braking 6.0 → 7.6 s to a slow drift.
static func stream_speed(t: float) -> float:
	var up := smoothstep(0.0, 0.35, t)
	var brake := smoothstep(T_MSG_OUT, T_PLANET + 0.6, t)
	return lerpf(STREAM_SPEED * (0.35 + 0.65 * up), DRIFT_SPEED, brake)


## Message alpha (0 before 3 s, fades in until 6 s, stays while sliding out).
static func message_alpha(t: float) -> float:
	if t < T_MSG_IN:
		return 0.0
	if t >= T_PLANET:
		return 0.0
	return smoothstep(T_MSG_IN, T_MSG_OUT, t)


## Horizontal offset of the message (0 until 6 s, then accelerating to the left, off-screen at 7 s).
static func message_offset(t: float) -> float:
	if t <= T_MSG_OUT:
		return 0.0
	var u := clampf((t - T_MSG_OUT) / (T_PLANET - T_MSG_OUT), 0.0, 1.0)
	return -u * u * 1300.0


## Sphere diameter of the target planet: appears at 7 s, zooms in for 5 s (ease-out at the end).
static func planet_diameter(t: float) -> float:
	if t < T_PLANET:
		return 0.0
	var u := clampf((t - T_PLANET) / (T_END - T_PLANET), 0.0, 1.0)
	var e := 1.0 - pow(1.0 - u, 2.2)
	return PLANET_D0 * pow(PLANET_D1 / PLANET_D0, e)


func _exit_tree() -> void:
	# Give the effects back (volume + the player's SOUND EFFECTS setting) before the next screen starts.
	if _sfx_bus >= 0:
		AudioServer.set_bus_volume_db(_sfx_bus, _sfx_bus_db)
	AudioManager.apply_settings()


## SFX bus gain while the arrival runs: 1 → 0 over SFX_FADE seconds (a short de-click fade), then 0.
static func sfx_gain(t: float) -> float:
	return clampf(1.0 - t / SFX_FADE, 0.0, 1.0)


func _update_silence() -> void:
	if _sfx_bus < 0:
		return
	var g := sfx_gain(time)
	if g > 0.0:
		AudioServer.set_bus_volume_db(_sfx_bus, _sfx_bus_db + linear_to_db(g))
	else:
		# Muted for the rest of the sequence. Re-asserted every frame because AudioManager.apply_settings()
		# (e.g. on Settings.changed after F11) would unmute the bus again.
		AudioServer.set_bus_volume_db(_sfx_bus, _sfx_bus_db)
		AudioServer.set_bus_mute(_sfx_bus, true)


func _tick(_delta: float) -> void:
	_update_silence()
	starfield.velocity = Vector2(-stream_speed(time), 0)
	if time >= T_END and InputRouter.confirm_pressed():
		finish("continue")   # no sound: the arrival sequence is completely silent


func _draw() -> void:
	# Message
	var ma := message_alpha(time)
	if ma > 0.0:
		var font := Assets.font_title_heavy
		var size := UiKit.fit_size(font, _text, 30, 900.0)
		var x := CX + message_offset(time)
		UiKit.text_glow(self, font, Vector2(x, 372), _text, size, Color(UiKit.COLOR_TEXT, ma), UiKit.COLOR_HILITE,
			HORIZONTAL_ALIGNMENT_CENTER, ma)
	# Target planet
	var d := planet_diameter(time)
	if d > 0.0:
		var pa := clampf((time - T_PLANET) / 0.6, 0.0, 1.0)
		var c := Vector2(CX, 350)
		UiKit.glow_spot(self, c, Vector2(d, d) * 0.85, Color(_atmosphere(_target), 0.20 * pa))
		Assets.draw_planet(self, _target, c, d, Color(1, 1, 1, pa))
	if time >= T_END:
		# On a dark backing: the zoomed planet (Uranus/Saturn rings) reaches down behind the prompt.
		var fa := clampf((time - T_END) / 0.5, 0.0, 1.0)
		var a := fa * (0.72 + 0.28 * sin((time - T_END) * 3.2))
		var font := Assets.font_title
		var pos := Vector2(CX, PROMPT_Y)
		UiKit.backing(self, UiKit.text_backing_rect(font, pos, PROMPT, 20, HORIZONTAL_ALIGNMENT_CENTER,
			Vector2(26, 12)), fa)
		UiKit.text(self, font, pos, PROMPT, 20, Color(UiKit.COLOR_TEXT, a), HORIZONTAL_ALIGNMENT_CENTER)


static func _atmosphere(planet: String) -> Color:
	return {"uranus": Color(0.5, 0.9, 0.95), "saturn": Color(1.0, 0.85, 0.6), "jupiter": Color(1.0, 0.75, 0.5),
		"mars": Color(1.0, 0.5, 0.3), "earth": Color(0.4, 0.7, 1.0)}.get(planet, Color(0.5, 0.7, 1.0))
