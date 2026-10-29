extends Node
## Autoload "AudioManager" (docs/SPEC.md §14, §16.7): title music, the in-game music sequencer, sound
## effects, the bass-progress logic and the bus setup. See docs/AUDIO.md.
##
## - Buses "Music" and "SFX" are created at runtime if missing; a hard limiter sits on Master.
## - Player volumes (Settings.music_volume / sfx_volume, 0–100 %) set the Music / SFX bus gain with the curve of
##   volume_db() (amplitude = v², 100 % = 0 dB = the original mix, 0 % = mute); MUSIC / SOUND EFFECTS OFF mute
##   the bus regardless of the volume. Never above 0 dB, so the limiter guarantee is unchanged.
## - Title music: looping OGG (assets/audio/music/title.ogg).
## - Game music: sample-accurate runtime sequencer at 200 BPM (1 bar = 1.2 s = 52920 frames @ 44.1 kHz).
##   Kick on every quarter, snare on beat 3, hats on 8ths with a velocity groove (4-bar cycle) and a quiet
##   atmosphere loop are assembled ONCE at load time from pre-rendered one-shots into a 4-bar "bed"; every
##   quarter a bass hit is mixed on top whose pitch is E1 * 2^(bass_semitone()/12), taken from a bank of 41
##   pre-rendered notes (raw float32 PCM, read with FileAccess). An AudioStreamGenerator is topped up every
##   frame to exactly LOOKAHEAD_FRAMES (90 ms) queued frames; the timeline counts rendered frames, so
##   stalls never shift the beat, and a kill is heard on the first quarter starting >= 90 ms later.
## - Everything is harmless without audio hardware and before the node enters the tree (the headless test
##   runner calls into autoloads from _initialize()). Under the Dummy driver nothing is audible anyway, so no
##   player is started there (playbacks started under Dummy are never released before exit and Godot would
##   report leaks) - except in Movie Maker mode, which mixes the Dummy output into the recording. The
##   logical state (title on, game music active/suspended, bass progress) is kept in every case.

const MAX_BASS_STEPS := 40

const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const TITLE_MUSIC_PATH := "res://assets/audio/music/title.ogg"
const GAME_MUSIC_DIR := "res://assets/audio/music/game/"
const SFX_DIR := "res://assets/audio/sfx/"
const SFX_NAMES: Array[String] = ["shot_laser", "shot_rocket", "shot_blaster", "enemy_fire", "enemy_hit",
	"enemy_explode", "locked_hit", "player_explode", "extra_life", "level_complete", "materialize", "menu_move",
	"menu_confirm", "menu_back", "bonus_tick", "game_over", "powerup_on", "powerup_off", "shield_hit"]

# --- Sequencer timing: all integers at 44.1 kHz -> sample accurate --------------------------------
const MIX_RATE := 44100
const BPM := 200.0
const FRAMES_PER_QUARTER := 13230        # 0.3 s
const FRAMES_PER_EIGHTH := 6615
const FRAMES_PER_BAR := 52920            # 1.2 s
const BED_BARS := 4
const BASS_BASE_HZ := 41.203             # E1
## Look-ahead of the game music: the fill keeps exactly this many frames queued in the generator
## (90 ms = 5.4 frames at 60 fps). It is the stall tolerance before an underrun AND it bounds how fast a
## kill is heard: the semitone is read when a note starts RENDERING, so a kill reaches the speakers on the
## first quarter that starts at least LOOKAHEAD_FRAMES later, i.e. 90...390 ms after the kill (+ driver
## latency). Kept explicit instead of relying on the ring size, which Godot rounds up to a power of two.
const LOOKAHEAD_FRAMES := 3969
## Generator ring buffer. 0.09 s -> 3969 frames, rounded up by Godot to a 4096-frame ring (4095 usable).
## (0.15 s would already become 8192 frames = 186 ms.) Must be >= the look-ahead.
const GENERATOR_BUFFER_SEC := 0.09
const FIRST_BAR_FADE_IN := 1323          # 30 ms fade-in of the atmosphere after a (re)start

## Sequencer mix (keep in sync with tools/audio/make_game_music.py GAIN / HAT_VEL).
const SEQ_GAIN := {"kick": 0.42, "snare": 0.36, "hat": 0.3, "bass": 0.33, "atmos": 0.2}
const HAT_VEL := [
	[0.55, 1.0, 0.62, 0.92, 0.55, 1.0, 0.66, 0.9],
	[0.55, 0.96, 0.6, 0.92, 0.58, 1.0, 0.62, 0.95],
	[0.55, 1.0, 0.62, 0.92, 0.55, 1.0, 0.66, 0.9],
	[0.58, 0.96, 0.6, 0.94, 0.55, 1.0, 0.7, 1.0],
]
const HAT_PAN_ON := -0.1
const HAT_PAN_OFF := 0.15

# --- Levels ---------------------------------------------------------------------------------------
const TITLE_VOLUME_DB := -4.0
const GAME_VOLUME_DB := -2.0
const MASTER_CEILING_DB := -1.0
## Player volume curve: amplitude = (percent / 100) ^ VOLUME_CURVE_EXP, i.e. 40·log10(v) dB:
## 100 % = 0 dB, 90 % = −1.8, 70 % = −6.2, 50 % = −12, 30 % = −20.9, 10 % = −40 dB, 0 % = mute.
## (Loudness grows roughly with amplitude^0.6, so v² gives evenly sized perceived steps; a linear gain
## would leave the upper half of the scale nearly inaudible as a change.)
const VOLUME_CURVE_EXP := 2.0
## Bus gain written for 0 % (the bus is muted as well).
const VOLUME_MUTE_DB := -80.0
## Sound played when the player changes EFFECTS VOLUME (title menu, pause): a short, typical game effect.
const VOLUME_PREVIEW_SFX := "shot_laser"

# --- SFX pool -------------------------------------------------------------------------------------
const SFX_POOL_SIZE := 12
const SFX_MAX_SAME := 3
## name -> [extra gain dB, random pitch spread (± fraction), steal priority (higher = kept longer)]
const SFX_TUNING := {
	"shot_laser": [0.0, 0.025, 1],
	"shot_rocket": [0.0, 0.03, 1],
	"shot_blaster": [0.0, 0.02, 1],
	"enemy_fire": [0.0, 0.04, 1],
	"enemy_hit": [0.0, 0.05, 1],
	"enemy_explode": [0.0, 0.06, 2],
	"locked_hit": [0.0, 0.03, 1],
	"player_explode": [0.0, 0.0, 3],
	"extra_life": [0.0, 0.0, 3],
	"level_complete": [0.0, 0.0, 3],
	"materialize": [0.0, 0.04, 0],
	"menu_move": [0.0, 0.0, 2],
	"menu_confirm": [0.0, 0.0, 2],
	"menu_back": [0.0, 0.0, 2],
	"bonus_tick": [0.0, 0.0, 1],
	"game_over": [0.0, 0.0, 3],
	# Power-ups (SPEC §19.3): trigger / end stingers, and the frequent fireball-on-shield zap.
	"powerup_on": [0.0, 0.0, 3],
	"powerup_off": [0.0, 0.0, 2],
	"shield_hit": [0.0, 0.05, 1],
}

# --- Bass logic -----------------------------------------------------------------------------------
var _kills := 0
var _level := 1

# --- Nodes / resources ----------------------------------------------------------------------------
var _setup_done := false
var _output := true                     # false under the Dummy driver (unless Movie Maker records)
var _title_on := false                  # logical title-music state
var _title_player: AudioStreamPlayer
var _game_player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _gen_capacity := 0                  # usable frames of the generator ring (measured at start)
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_slot_name: Array[String] = []
var _sfx_slot_serial: Array[int] = []
var _sfx_serial := 0
var _sfx_streams := {}                  # name -> AudioStream (or null if missing)
var _rng := RandomNumberGenerator.new()

# --- Sequencer state ------------------------------------------------------------------------------
var _seq_loaded := false
var _game_active := false               # play_game_music() called, not stopped
var _game_suspended := false
var _seq_frame := 0                     # frames rendered since the last (re)start at a bar start
var _bed_first := PackedVector2Array()  # bar 1 after a (re)start: no wrapped tails, atmosphere fades in
var _bed_loop := PackedVector2Array()   # BED_BARS bars, tails wrapped around (seamless)
var _bass_bank := PackedFloat32Array()  # 41 notes x FRAMES_PER_QUARTER frames, mono
var _bass_note_count := 0
var _bass_offset := 0                   # start of the current note inside _bass_bank
var _current_note_semitone := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_setup()
	if not Settings.changed.is_connected(apply_settings):
		Settings.changed.connect(apply_settings)
	apply_settings()


func _exit_tree() -> void:
	# Release every playback before the engine shuts down (otherwise the looping title stream is still
	# referenced by the AudioServer at exit and Godot reports leaked instances).
	_playback = null
	for p: AudioStreamPlayer in [_title_player, _game_player]:
		if p != null:
			p.stop()
	for p in _sfx_players:
		p.stop()


func _process(_delta: float) -> void:
	if _game_active and not _game_suspended:
		_fill_generator()


# ==================================================================================================
# Public API (binding, see SPEC §17)
# ==================================================================================================

## Title/menu music (loop). No-op if already playing.
func play_title_music() -> void:
	_ensure_setup()
	_game_active = false
	_game_suspended = false
	_stop_sequencer()
	_title_on = _title_player.stream != null
	if _title_on and _can_play() and not _title_player.playing:
		_title_player.play()


## Starts the in-game sequencer at a bar start (200 BPM, bass from current semitone).
## If the sequencer is already running it keeps its groove (no restart).
func play_game_music() -> void:
	_ensure_setup()
	_title_on = false
	if _title_player.playing:
		_title_player.stop()
	_game_suspended = false
	if _game_active and _is_sequencer_running():
		return
	_game_active = true
	_start_sequencer()


func stop_music() -> void:
	_ensure_setup()
	_game_active = false
	_game_suspended = false
	_title_on = false
	_stop_sequencer()
	if _title_player.playing:
		_title_player.stop()


## Pause / respawn: true silences the game music; false restarts the beat at a bar start.
func set_game_music_suspended(suspended: bool) -> void:
	_ensure_setup()
	if suspended == _game_suspended:
		return
	_game_suspended = suspended
	if not _game_active:
		return
	if suspended:
		_stop_sequencer()
	else:
		_start_sequencer()


## Level start: bass back to E1 and remember the level for the cycle rule.
func reset_bass(level: int) -> void:
	_level = level
	_kills = 0


## Call on every FINAL destruction of a figure (not on split hits / colour changes / non-lethal hits).
## Counts even while the music is off or suspended.
func notify_enemy_destroyed() -> void:
	_kills += 1


## Current bass offset in semitones above E1.
func bass_semitone() -> int:
	return compute_bass_semitone(_level, _kills)


## Levels 17, 18, 20: back to E1 after every 10 destructions; elsewhere capped at +40.
static func compute_bass_semitone(level: int, kills: int) -> int:
	if level == 17 or level == 18 or level == 20:
		return kills % 10
	return mini(kills, MAX_BASS_STEPS)


## Bass frequency in Hz for a semitone offset (E1 = 41.203 Hz).
static func bass_frequency(semitone: int) -> float:
	return BASS_BASE_HZ * pow(2.0, float(semitone) / 12.0)


## Plays a one-shot from assets/audio/sfx/<name>.wav on the SFX bus (pooled, max SFX_MAX_SAME at once
## per name - the oldest instance of that name is restarted when the cap is reached).
func play_sfx(sfx_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	_ensure_setup()
	if not _can_play():
		return
	var stream := _sfx_stream(sfx_name)
	if stream == null:
		return
	var tune: Array = SFX_TUNING.get(sfx_name, [0.0, 0.0, 1])
	var slot := _pick_sfx_slot(sfx_name, int(tune[2]))
	if slot < 0:
		return  # pool full of more important sounds
	var p := _sfx_players[slot]
	p.stop()
	p.stream = stream
	p.volume_db = volume_db + float(tune[0])
	# a little random detune against machine-gun repeats - only if the caller did not choose a pitch
	var spread := float(tune[1]) if is_equal_approx(pitch, 1.0) else 0.0
	var rnd := _rng.randf_range(-spread, spread) if spread > 0.0 else 0.0
	p.pitch_scale = clampf(pitch * (1.0 + rnd), 0.05, 4.0)
	p.play()
	_sfx_serial += 1
	_sfx_slot_name[slot] = sfx_name
	_sfx_slot_serial[slot] = _sfx_serial


## Re-reads Settings.music_on / sfx_on and music_volume / sfx_volume and applies them immediately: bus gain
## from the volume (volume_db), bus mute when the option is OFF or the volume is 0 %.
## (The arrival sequence fades/mutes the SFX bus on its own and calls this again when it ends.)
func apply_settings() -> void:
	_ensure_buses()
	_apply_bus(AudioServer.get_bus_index(BUS_MUSIC), Settings.music_on, Settings.music_volume)
	_apply_bus(AudioServer.get_bus_index(BUS_SFX), Settings.sfx_on, Settings.sfx_volume)


func _apply_bus(bus: int, on: bool, percent: int) -> void:
	if bus < 0:
		return
	AudioServer.set_bus_volume_db(bus, volume_db(percent))
	AudioServer.set_bus_mute(bus, bus_muted(on, percent))


## Bus gain in dB for a player volume in percent (curve: VOLUME_CURVE_EXP). 0 % → VOLUME_MUTE_DB.
static func volume_db(percent: int) -> float:
	if percent <= 0:
		return VOLUME_MUTE_DB
	var v := clampf(percent / 100.0, 0.0, 1.0)
	return maxf(linear_to_db(pow(v, VOLUME_CURVE_EXP)), VOLUME_MUTE_DB)


## True if a bus is silent: its ON/OFF option is OFF (whatever the volume) or its volume is 0 %.
static func bus_muted(on: bool, percent: int) -> bool:
	return not on or percent <= 0


# --- Read-only helpers (UI / tests) ---------------------------------------------------------------
## Logical state: true between play_title_music() and stop_music()/play_game_music().
func is_title_music_playing() -> bool:
	return _title_on


## True while the game music is logically on (between play_game_music() and stop/title), even if suspended.
func is_game_music_active() -> bool:
	return _game_active


func is_game_music_suspended() -> bool:
	return _game_suspended


## Number of SFX currently playing with this name.
func sfx_playing_count(sfx_name: String) -> int:
	var c := 0
	for i in _sfx_players.size():
		if _sfx_slot_name[i] == sfx_name and _sfx_players[i].playing:
			c += 1
	return c


# ==================================================================================================
# Setup
# ==================================================================================================
func _ensure_setup() -> void:
	if _setup_done:
		return
	_setup_done = true
	_rng.randomize()
	_output = AudioServer.get_driver_name() != "Dummy" or Engine.get_write_movie_path() != ""
	_ensure_buses()

	_title_player = AudioStreamPlayer.new()
	_title_player.name = "TitleMusic"
	_title_player.bus = BUS_MUSIC
	_title_player.volume_db = TITLE_VOLUME_DB
	var title: AudioStream = load(TITLE_MUSIC_PATH) if ResourceLoader.exists(TITLE_MUSIC_PATH) else null
	if title is AudioStreamOggVorbis:
		(title as AudioStreamOggVorbis).loop = true
		(title as AudioStreamOggVorbis).loop_offset = 0.0
	_title_player.stream = title
	add_child(_title_player)

	_game_player = AudioStreamPlayer.new()
	_game_player.name = "GameMusic"
	_game_player.bus = BUS_MUSIC
	_game_player.volume_db = GAME_VOLUME_DB
	_game_player.stream = make_generator()
	add_child(_game_player)

	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		p.bus = BUS_SFX
		add_child(p)
		_sfx_players.append(p)
		_sfx_slot_name.append("")
		_sfx_slot_serial.append(0)
	for n in SFX_NAMES:
		_sfx_stream(n)

	_load_sequencer()


## Creates the Music and SFX buses if missing and puts a hard limiter on Master. Idempotent.
func _ensure_buses() -> void:
	for bus_name: String in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			return
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = MASTER_CEILING_DB
	lim.release = 0.1
	AudioServer.add_bus_effect(0, lim)


## True if starting a player makes sense (inside the tree and the output is really mixed).
func _can_play() -> bool:
	return _output and is_inside_tree()


func _sfx_stream(sfx_name: String) -> AudioStream:
	if _sfx_streams.has(sfx_name):
		return _sfx_streams[sfx_name]
	var path := SFX_DIR + sfx_name + ".wav"
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_sfx_streams[sfx_name] = s
	return s


## Pool slot for a new sound, from the live state of the players (see choose_sfx_slot).
func _pick_sfx_slot(sfx_name: String, priority: int) -> int:
	var busy: Array[bool] = []
	for p in _sfx_players:
		busy.append(p.playing)
	return choose_sfx_slot(sfx_name, priority, busy, _sfx_slot_name, _sfx_slot_serial)


## Steal priority of a sound (higher = kept longer); unknown names count as 1.
static func sfx_priority(sfx_name: String) -> int:
	return int((SFX_TUNING.get(sfx_name, [0.0, 0.0, 1]) as Array)[2])


## Pure slot choice (unit-tested). Per slot: busy = still playing, names = last sound started there,
## serials = start order (higher = newer). Returns:
## 1. the OLDEST busy instance of the same name once SFX_MAX_SAME of them play (that one restarts),
## 2. else the first free slot,
## 3. else (pool full) the oldest slot of the lowest priority, if that priority is <= the new sound's,
## 4. else -1: every playing sound is more important, the new one is dropped.
static func choose_sfx_slot(sfx_name: String, priority: int, busy: Array[bool], names: Array[String],
		serials: Array[int]) -> int:
	var same := 0
	var oldest_same := -1
	var free := -1
	for i in busy.size():
		if busy[i] and names[i] == sfx_name:
			same += 1
			if oldest_same < 0 or serials[i] < serials[oldest_same]:
				oldest_same = i
		elif not busy[i] and free < 0:
			free = i
	if same >= SFX_MAX_SAME:
		return oldest_same
	if free >= 0:
		return free
	var best := -1
	var best_pr := 0
	for i in busy.size():
		var pr := sfx_priority(names[i])
		if best < 0 or pr < best_pr or (pr == best_pr and serials[i] < serials[best]):
			best = i
			best_pr = pr
	return best if best >= 0 and best_pr <= priority else -1


# ==================================================================================================
# Sequencer
# ==================================================================================================
func _load_sequencer() -> void:
	var meta_path := GAME_MUSIC_DIR + "meta.json"
	if not FileAccess.file_exists(meta_path):
		return
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if not (meta is Dictionary) or not (meta as Dictionary).has("samples"):
		return
	var samples: Dictionary = meta["samples"]
	var kick := _load_raw(samples, "kick")
	var snare := _load_raw(samples, "snare")
	var hat := _load_raw(samples, "hat")
	var atmos := _load_raw(samples, "atmos")
	_bass_bank = _load_raw(samples, "bass")
	@warning_ignore("integer_division")
	_bass_note_count = _bass_bank.size() / FRAMES_PER_QUARTER
	if _bass_note_count <= 0 or kick.is_empty():
		return
	_bed_loop = _build_bed(BED_BARS, true, kick, snare, hat, atmos)
	_bed_first = _build_bed(1, false, kick, snare, hat, atmos)
	_seq_loaded = true


func _load_raw(samples: Dictionary, key: String) -> PackedFloat32Array:
	if not samples.has(key):
		return PackedFloat32Array()
	var path: String = GAME_MUSIC_DIR + String((samples[key] as Dictionary).get("file", ""))
	if not FileAccess.file_exists(path):
		return PackedFloat32Array()
	return FileAccess.get_file_as_bytes(path).to_float32_array()


## Assembles kick/snare/hats/atmosphere for `bars` bars. wrap_tails = tails past the end continue at the start
## (seamless loop); otherwise they are dropped (first bar after a restart).
func _build_bed(bars: int, wrap_tails: bool, kick: PackedFloat32Array, snare: PackedFloat32Array,
		hat: PackedFloat32Array, atmos: PackedFloat32Array) -> PackedVector2Array:
	var n := bars * FRAMES_PER_BAR
	var bed := PackedVector2Array()
	bed.resize(n)
	bed.fill(Vector2.ZERO)
	var ga: float = SEQ_GAIN["atmos"]
	@warning_ignore("integer_division")
	var atmos_frames := atmos.size() / 2
	if atmos_frames > 0:
		for i in n:
			var k := (i % atmos_frames) * 2
			var g := ga
			if not wrap_tails and i < FIRST_BAR_FADE_IN:
				g *= float(i) / FIRST_BAR_FADE_IN
			bed[i] = Vector2(atmos[k] * g, atmos[k + 1] * g)
	var gk: float = SEQ_GAIN["kick"]
	var gs: float = SEQ_GAIN["snare"]
	var gh: float = SEQ_GAIN["hat"]
	for bar in bars:
		var b0 := bar * FRAMES_PER_BAR
		for q in 4:
			_mix_mono(bed, kick, b0 + q * FRAMES_PER_QUARTER, gk, gk, wrap_tails)
		_mix_stereo(bed, snare, b0 + 2 * FRAMES_PER_QUARTER, gs, wrap_tails)
		var vel: Array = HAT_VEL[bar % HAT_VEL.size()]
		for e in 8:
			var v: float = float(vel[e]) * gh
			var p := HAT_PAN_OFF if e % 2 == 1 else HAT_PAN_ON
			_mix_mono(bed, hat, b0 + e * FRAMES_PER_EIGHTH, v * _pan_l(p), v * _pan_r(p), wrap_tails)
	return bed


static func _pan_l(p: float) -> float:
	return cos((p + 1.0) * PI * 0.25) * sqrt(2.0)


static func _pan_r(p: float) -> float:
	return sin((p + 1.0) * PI * 0.25) * sqrt(2.0)


static func _mix_mono(dst: PackedVector2Array, src: PackedFloat32Array, start: int, gl: float, gr: float,
		wrap_tails: bool) -> void:
	var n := dst.size()
	for i in src.size():
		var j := start + i
		if j >= n:
			if not wrap_tails:
				return
			j %= n
		var v := src[i]
		dst[j] = dst[j] + Vector2(v * gl, v * gr)


static func _mix_stereo(dst: PackedVector2Array, src: PackedFloat32Array, start: int, g: float, wrap_tails: bool) -> void:
	var n := dst.size()
	@warning_ignore("integer_division")
	var frames := src.size() / 2
	for i in frames:
		var j := start + i
		if j >= n:
			if not wrap_tails:
				return
			j %= n
		dst[j] = dst[j] + Vector2(src[i * 2] * g, src[i * 2 + 1] * g)


func _is_sequencer_running() -> bool:
	return _playback != null and _game_player != null and _game_player.playing


func _start_sequencer() -> void:
	_seq_frame = 0
	if not _seq_loaded or not _can_play():
		return
	if _game_player.playing:
		_game_player.stop()
	_game_player.play()
	_attach_playback(_game_player.get_stream_playback() as AudioStreamGeneratorPlayback)
	_fill_generator()


## Uses `pb` as the output of the sequencer. Must be called while its ring is still empty: the free space
## then equals the ring capacity (needed to know how much is queued later on). The generator that created
## `pb` must stay referenced while it is used (the playback keeps only a raw pointer to it) - here the
## player's `stream` holds it.
func _attach_playback(pb: AudioStreamGeneratorPlayback) -> void:
	_playback = pb
	_gen_capacity = pb.get_frames_available() if pb != null else 0


func _stop_sequencer() -> void:
	_playback = null
	if _game_player != null and _game_player.playing:
		_game_player.stop()


## The generator stream of the game music (44.1 kHz, ring >= LOOKAHEAD_FRAMES).
static func make_generator() -> AudioStreamGenerator:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate_mode = AudioStreamGenerator.MIX_RATE_CUSTOM
	gen.mix_rate = MIX_RATE
	gen.buffer_length = GENERATOR_BUFFER_SEC
	return gen


## Frames to push so that `lookahead` frames are queued: queued = capacity - available. Never more than the
## ring can take (a ring smaller than the look-ahead is simply kept full).
static func frames_to_push(available: int, capacity: int, lookahead: int) -> int:
	return clampi(lookahead - (capacity - available), 0, maxi(available, 0))


## Tops the generator up to LOOKAHEAD_FRAMES queued frames. Called every frame, so a stall shorter than
## the look-ahead is bridged without a gap; the timeline is counted in rendered frames, never in
## wall-clock time, so neither stalls nor uneven frame times can shift the beat.
func _fill_generator() -> void:
	if _playback == null:
		return
	var n := frames_to_push(_playback.get_frames_available(), _gen_capacity, LOOKAHEAD_FRAMES)
	if n <= 0:
		return
	_playback.push_buffer(render_frames(n))


## Renders the next `frames` frames of the game music and advances the sequencer (public for tests and
## offline rendering; normally only called by the generator fill).
func render_frames(frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	if not _seq_loaded:
		out.fill(Vector2.ZERO)
		_seq_frame += frames
		return out
	var bass := _bass_bank
	var bass_gain: float = SEQ_GAIN["bass"]
	var i := 0
	while i < frames:
		var q_pos := _seq_frame % FRAMES_PER_QUARTER
		if q_pos == 0:
			_start_bass_note()
		var chunk := mini(frames - i, FRAMES_PER_QUARTER - q_pos)
		var bed := _bed_first
		var bed_pos := _seq_frame
		if _seq_frame >= FRAMES_PER_BAR:
			bed = _bed_loop
			bed_pos = _seq_frame % _bed_loop.size()
		var b_off := _bass_offset + q_pos
		for k in chunk:
			var b := bass[b_off + k] * bass_gain
			var d := bed[bed_pos + k]
			out[i + k] = Vector2(d.x + b, d.y + b)
		i += chunk
		_seq_frame += chunk
	return out


## Restarts the sequencer timeline at a bar start without touching the audio player (tests / offline).
func restart_timeline() -> void:
	_seq_frame = 0


## Semitone of the bass note that is currently being rendered (tests / debug).
func current_note_semitone() -> int:
	return _current_note_semitone


func sequencer_frame() -> int:
	return _seq_frame


func is_sequencer_loaded() -> bool:
	_ensure_setup()
	return _seq_loaded


func _start_bass_note() -> void:
	var s := clampi(bass_semitone(), 0, maxi(_bass_note_count - 1, 0))
	_current_note_semitone = s
	_bass_offset = s * FRAMES_PER_QUARTER
