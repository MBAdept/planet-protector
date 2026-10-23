extends TestBase
## AudioManager: bass rules (SPEC §14), headless robustness, sample-accurate sequencer, asset contract.
## Uses fresh AudioManager instances (not inside the tree, like the autoloads during the test run).

const AudioManagerScript := preload("res://scripts/autoload/audio_manager.gd")
const Q := 13230   # frames per quarter at 200 BPM / 44.1 kHz


func _fresh() -> Node:
	return AudioManagerScript.new()


func test_compute_bass_semitone_rules() -> void:
	# normal levels: one semitone per destruction, capped at +40
	for lvl in [1, 7, 12, 13, 16, 19]:
		check_eq(AudioManagerScript.compute_bass_semitone(lvl, 0), 0, "L%d k0" % lvl)
		check_eq(AudioManagerScript.compute_bass_semitone(lvl, 1), 1, "L%d k1" % lvl)
		check_eq(AudioManagerScript.compute_bass_semitone(lvl, 39), 39, "L%d k39" % lvl)
		check_eq(AudioManagerScript.compute_bass_semitone(lvl, 40), 40, "L%d k40" % lvl)
		check_eq(AudioManagerScript.compute_bass_semitone(lvl, 41), 40, "L%d k41 capped" % lvl)
		check_eq(AudioManagerScript.compute_bass_semitone(lvl, 250), 40, "L%d k250 capped" % lvl)
	# levels 17, 18, 20: back to E1 after every 10 destructions
	for lvl in [17, 18, 20]:
		check_eq(AudioManagerScript.compute_bass_semitone(lvl, 0), 0, "L%d k0" % lvl)
		check_eq(AudioManagerScript.compute_bass_semitone(lvl, 9), 9, "L%d k9" % lvl)
		check_eq(AudioManagerScript.compute_bass_semitone(lvl, 10), 0, "L%d k10 wraps" % lvl)
		check_eq(AudioManagerScript.compute_bass_semitone(lvl, 25), 5, "L%d k25" % lvl)
		check_eq(AudioManagerScript.compute_bass_semitone(lvl, 40), 0, "L%d k40" % lvl)


func test_bass_frequency() -> void:
	check_near(AudioManagerScript.bass_frequency(0), 41.203, 1e-4, "E1")
	check_near(AudioManagerScript.bass_frequency(12), 82.406, 1e-3, "E2")
	check_near(AudioManagerScript.bass_frequency(40), 41.203 * pow(2.0, 40.0 / 12.0), 1e-3, "+40")


func test_reset_and_notify() -> void:
	var am := _fresh()
	am.reset_bass(5)
	check_eq(am.bass_semitone(), 0, "after reset")
	for i in 3:
		am.notify_enemy_destroyed()
	check_eq(am.bass_semitone(), 3)
	for i in 50:
		am.notify_enemy_destroyed()
	check_eq(am.bass_semitone(), 40, "capped")
	am.reset_bass(17)
	check_eq(am.bass_semitone(), 0, "reset at level start")
	for i in 12:
		am.notify_enemy_destroyed()
	check_eq(am.bass_semitone(), 2, "level 17 cycles every 10")
	am.free()


func test_progress_continues_while_music_off() -> void:
	var am := _fresh()
	var was_on: bool = Settings.music_on
	Settings.music_on = false          # no set_music_on(): must not write the user's settings file
	am.apply_settings()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music bus muted")
	am.reset_bass(3)
	am.stop_music()
	am.notify_enemy_destroyed()
	am.notify_enemy_destroyed()
	check_eq(am.bass_semitone(), 2, "counts with music off")
	am.play_game_music()
	am.set_game_music_suspended(true)
	am.notify_enemy_destroyed()
	check_eq(am.bass_semitone(), 3, "counts while suspended")
	Settings.music_on = was_on
	am.apply_settings()
	check_eq(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), not was_on, "restored")
	am.free()


func test_api_callable_headless() -> void:
	var am := _fresh()
	am.apply_settings()
	am.play_title_music()
	check(am.is_title_music_playing(), "title logically on")
	am.play_title_music()
	am.play_game_music()
	check(not am.is_title_music_playing(), "game music replaces the title")
	am.set_game_music_suspended(true)
	am.set_game_music_suspended(true)
	am.set_game_music_suspended(false)
	am.play_game_music()
	for n in AudioManagerScript.SFX_NAMES:
		am.play_sfx(n)
	am.play_sfx("does_not_exist", -3.0, 1.2)
	am.stop_music()
	am.reset_bass(1)
	am.notify_enemy_destroyed()
	check(not am.is_title_music_playing(), "stop_music stops the title")
	check(am.sfx_playing_count("menu_move") == 0, "no player is started outside the tree")
	check(not am.is_game_music_active(), "stopped")
	# buses + limiter
	check(AudioServer.get_bus_index("Music") > 0, "Music bus exists")
	check(AudioServer.get_bus_index("SFX") > 0, "SFX bus exists")
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(0):
		has_limiter = has_limiter or AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter
	check(has_limiter, "limiter on Master")
	# calling setup twice must not create duplicate buses
	var bus_count := AudioServer.bus_count
	am.apply_settings()
	var am2 := _fresh()
	am2.apply_settings()
	check_eq(AudioServer.bus_count, bus_count, "no duplicate buses")
	am.free()
	am2.free()
	# the real autoload is callable as well
	AudioManager.play_sfx("menu_move")
	AudioManager.play_title_music()
	AudioManager.stop_music()


func test_suspend_flags() -> void:
	var am := _fresh()
	am.set_game_music_suspended(true)
	check(not am.is_game_music_active(), "suspend alone does not start music")
	am.play_game_music()
	check(am.is_game_music_active(), "active")
	check(not am.is_game_music_suspended(), "play clears suspension")
	am.set_game_music_suspended(true)
	check(am.is_game_music_suspended(), "suspended")
	am.play_title_music()
	check(not am.is_game_music_active(), "title stops game music")
	check(not am.is_game_music_suspended(), "title clears suspension")
	am.free()


func test_assets_present() -> void:
	for n in AudioManagerScript.SFX_NAMES:
		var p := "res://assets/audio/sfx/%s.wav" % n
		check(ResourceLoader.exists(p), "missing " + p)
		if ResourceLoader.exists(p):
			var s: AudioStream = load(p)
			check(s != null and s.get_length() > 0.02 and s.get_length() < 5.0, "bad length " + n)
	var t: AudioStream = load("res://assets/audio/music/title.ogg")
	check(t is AudioStreamOggVorbis, "title.ogg loads")
	if t is AudioStreamOggVorbis:
		check((t as AudioStreamOggVorbis).loop, "title loops (import param)")
		check_near(t.get_length(), 30.72, 0.01, "16 bars @125 BPM")
	var am := _fresh()
	check(am.is_sequencer_loaded(), "sequencer samples load from raw PCM")
	am.free()


func test_sequencer_sample_accurate() -> void:
	var am := _fresh()
	if not am.is_sequencer_loaded():
		check(false, "sequencer not loaded")
		am.free()
		return
	am.reset_bass(1)
	am.restart_timeline()
	am.render_frames(5000)
	check_eq(am.current_note_semitone(), 0, "first note E1")
	am.notify_enemy_destroyed()
	am.render_frames(Q - 5000 - 1)
	check_eq(am.current_note_semitone(), 0, "pitch changes only at the next quarter")
	check_eq(am.sequencer_frame(), Q - 1)
	am.render_frames(1)
	check_eq(am.current_note_semitone(), 0, "frame Q-1 still old note")
	am.render_frames(1)
	check_eq(am.current_note_semitone(), 1, "new note starts exactly at frame Q")
	# chunking must not change the output (no jitter): one big render == many odd-sized renders
	am.reset_bass(1)
	am.restart_timeline()
	var big: PackedVector2Array = am.render_frames(3 * 52920 + 777)
	am.restart_timeline()
	var pieces := PackedVector2Array()
	var sizes := [1, 735, 734, 8191, 13229, 2, 4410, 999]
	var k := 0
	while pieces.size() < big.size():
		var want := mini(int(sizes[k % sizes.size()]), big.size() - pieces.size())
		pieces.append_array(am.render_frames(want))
		k += 1
	check_eq(pieces.size(), big.size(), "same length")
	var max_diff := 0.0
	for i in big.size():
		max_diff = maxf(max_diff, (big[i] - pieces[i]).length())
	check(max_diff < 1e-6, "chunked render identical (max diff %f)" % max_diff)
	# the bass note really follows the semitone: difference of two renders == gain * (note b - note a)
	am.reset_bass(1)
	am.restart_timeline()
	var low: PackedVector2Array = am.render_frames(Q)
	am.reset_bass(1)
	for i in 12:
		am.notify_enemy_destroyed()
	am.restart_timeline()
	var high: PackedVector2Array = am.render_frames(Q)
	var bank: PackedFloat32Array = am._bass_bank
	var g: float = AudioManagerScript.SEQ_GAIN["bass"]
	var err := 0.0
	for i in range(0, Q, 7):
		var expect := g * (bank[12 * Q + i] - bank[i])
		err = maxf(err, absf((high[i].x - low[i].x) - expect))
	check(err < 1e-5, "bass note = semitone 12 (err %f)" % err)
	# output stays within range (no runaway mixing)
	var peak := 0.0
	for v in big:
		peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
	check(peak > 0.05 and peak < 1.0, "sane level (peak %f)" % peak)
	am.free()


## Pool state from entries [name, serial] (busy) or [name, serial, false] (finished, stale name);
## "" = never used. Returns the slot choose_sfx_slot() picks for `sfx_name`.
func _choose(sfx_name: String, slots: Array) -> int:
	var busy: Array[bool] = []
	var names: Array[String] = []
	var serials: Array[int] = []
	for s: Array in slots:
		names.append(String(s[0]))
		serials.append(int(s[1]))
		busy.append(String(s[0]) != "" and (s.size() < 3 or bool(s[2])))
	return AudioManagerScript.choose_sfx_slot(sfx_name, AudioManagerScript.sfx_priority(sfx_name), busy, names,
		serials)


func _free_slots(n: int) -> Array:
	var a := []
	for i in n:
		a.append(["", 0])
	return a


func test_sfx_slot_cap() -> void:
	const N := AudioManagerScript.SFX_POOL_SIZE
	check_eq(AudioManagerScript.SFX_MAX_SAME, 3, "per-name cap")
	# the live pool exists; outside the tree nothing plays, so every slot is free
	var am := _fresh()
	am._ensure_setup()
	check_eq(am._sfx_players.size(), N, "pool size")
	check_eq(am._pick_sfx_slot("shot_laser", 1), 0, "first free slot")
	check_eq(am.sfx_playing_count("shot_laser"), 0)
	am.free()

	check_eq(_choose("shot_laser", _free_slots(N)), 0, "empty pool -> slot 0")
	check_eq(AudioManagerScript.choose_sfx_slot("x", 1, [] as Array[bool], [] as Array[String], [] as Array[int]), -1,
		"no pool -> dropped")
	# below the cap: a free slot, finished sounds (stale names) do not count
	var pool := _free_slots(N)
	pool[1] = ["shot_laser", 2]
	pool[2] = ["shot_laser", 3]
	pool[4] = ["shot_laser", 9, false]
	check_eq(_choose("shot_laser", pool), 0, "2 playing + 1 finished -> free slot, nothing restarts")
	pool[0] = ["menu_move", 1, false]
	check_eq(_choose("shot_laser", pool), 0, "a finished slot is free")
	# at the cap: the OLDEST instance of that name restarts, although free slots exist
	pool = _free_slots(N)
	pool[3] = ["shot_laser", 7]
	pool[5] = ["shot_laser", 3]
	pool[8] = ["shot_laser", 9]
	pool[1] = ["enemy_fire", 1]
	check_eq(_choose("shot_laser", pool), 5, "cap 3 -> restart the oldest shot_laser")
	check_eq(_choose("enemy_fire", pool), 0, "other names still get a free slot")
	check_eq(_choose("does_not_exist", pool), 0, "unknown name -> free slot")
	check_eq(AudioManagerScript.sfx_priority("does_not_exist"), 1, "unknown name priority")

	# full pool: steal the oldest slot of the LOWEST priority (not simply the oldest slot)
	var full := []
	var names := ["enemy_fire", "shot_laser", "enemy_hit", "materialize", "locked_hit", "shot_rocket",
		"enemy_explode", "bonus_tick", "materialize", "shot_blaster", "enemy_explode", "menu_move"]
	for i in N:
		full.append([names[i], 100 + i])
	full[0] = ["enemy_fire", 1]        # oldest overall, priority 1
	full[3] = ["materialize", 50]      # priority 0
	full[8] = ["materialize", 40]      # priority 0, older -> victim
	check_eq(_choose("enemy_explode", full), 8, "full pool -> oldest of the lowest priority")
	check_eq(_choose("materialize", full), 8, "equal priority may replace the oldest")
	check_eq(_choose("player_explode", full), 8, "high priority steals too")
	full[3] = ["shot_laser", 60]
	full[8] = ["enemy_hit", 30]
	check_eq(_choose("menu_confirm", full), 0, "no priority 0 left -> oldest priority-1 sound")
	# the per-name cap wins over priority stealing in a full pool
	full[2] = ["shot_laser", 20]
	full[9] = ["shot_laser", 80]
	check_eq(_choose("shot_laser", full), 2, "full pool + cap -> oldest shot_laser, not the oldest sound")

	# pool full of more important sounds: drop the new one
	var vip := []
	var vip_names := ["player_explode", "extra_life", "level_complete", "game_over"]
	for i in N:
		vip.append([vip_names[i % 4], 10 + i])
	check_eq(_choose("shot_laser", vip), -1, "priority 1 vs all priority 3 -> dropped")
	check_eq(_choose("menu_move", vip), -1, "priority 2 vs all priority 3 -> dropped")
	check_eq(_choose("game_over", vip), 3, "same name at the cap -> oldest game_over (serial 13)")
	check_eq(_choose("player_explode", vip), 0, "same name at the cap -> oldest player_explode")
	# equal priority stealing between different names: 11 priority-2 sounds + 1 older priority-3 sound
	var mid := []
	var mid_names := ["enemy_explode", "enemy_explode", "enemy_explode", "menu_move", "menu_move",
		"menu_confirm", "menu_confirm", "menu_confirm", "menu_back", "menu_back", "menu_back", "game_over"]
	for i in N:
		mid.append([mid_names[i], 50 + i])
	mid[11] = ["game_over", 1]
	mid[6] = ["menu_confirm", 20]
	check_eq(_choose("menu_move", mid), 6, "equal priority -> oldest priority-2 slot, the older stinger stays")
	check_eq(_choose("shot_laser", mid), -1, "lower priority -> dropped")


func test_generator_lookahead() -> void:
	const L := AudioManagerScript.LOOKAHEAD_FRAMES
	var rate := float(AudioManagerScript.MIX_RATE)
	check(L >= 5 * 735, "look-ahead covers >= 5 frames at 60 fps")
	check(float(L) / rate <= 0.1, "look-ahead <= 100 ms (%.1f ms)" % (L * 1000.0 / rate))
	# the real ring buffer (Godot rounds it up to a power of two) must hold the look-ahead.
	# Keep `gen` referenced while `pb` is used: the playback only holds a RAW pointer to its generator
	# (a temporary generator is freed at once and mix_audio() then reads a garbage rate and never returns).
	var gen := AudioManagerScript.make_generator()
	var pb := gen.instantiate_playback() as AudioStreamGeneratorPlayback
	var cap := pb.get_frames_available()
	check(cap >= L, "ring (%d) holds the look-ahead (%d)" % [cap, L])
	# pure top-up rule
	check_eq(AudioManagerScript.frames_to_push(cap, cap, L), L, "empty ring -> fill to the look-ahead")
	check_eq(AudioManagerScript.frames_to_push(cap - L, cap, L), 0, "look-ahead queued -> nothing")
	check_eq(AudioManagerScript.frames_to_push(cap - L + 735, cap, L), 735, "refill what was consumed")
	check_eq(AudioManagerScript.frames_to_push(cap - L - 100, cap, L), 0, "over-full -> nothing")
	check_eq(AudioManagerScript.frames_to_push(100, 100, L), 100, "small ring -> keep it full")
	check_eq(AudioManagerScript.frames_to_push(0, cap, L), 0, "ring full -> nothing")

	# the real fill against the real ring, consumed by the real mixer with uneven frame times
	var am := _fresh()
	if not am.is_sequencer_loaded():
		check(false, "sequencer not loaded")
		am.free()
		return
	am.reset_bass(1)
	am.restart_timeline()
	am._attach_playback(pb)
	pb.start(0.0)
	am._fill_generator()
	check_eq(am.sequencer_frame(), L, "start renders exactly the look-ahead")
	check_eq(cap - pb.get_frames_available(), L, "start queues exactly the look-ahead")
	var steps := [735, 735, 512, 1470, 735, 2940, 128, 735, 3500, 735, 1100, 735, 640]  # frames + stalls < L
	var consumed := 0
	var max_ahead := 0
	var max_latency := 0
	var pending_at := -1          # frame where the note carrying the latest kill starts
	var pending_semi := 0
	var verified := 0
	for k in 160:
		var before := pb.get_frames_available()
		pb.mix_audio(1.0, int(steps[k % steps.size()]))
		consumed += pb.get_frames_available() - before     # what the mixer really took from the ring
		if k % 17 == 5:
			# a kill in game logic: it is heard on the first quarter that is not rendered yet
			am.notify_enemy_destroyed()
			@warning_ignore("integer_division")
			pending_at = (am.sequencer_frame() + Q - 1) / Q * Q
			pending_semi = am.bass_semitone()
			max_latency = maxi(max_latency, pending_at - consumed)
		am._fill_generator()
		check_eq(cap - pb.get_frames_available(), L, "queued == look-ahead after fill %d" % k)
		max_ahead = maxi(max_ahead, am.sequencer_frame() - consumed)
		if pending_at >= 0 and am.sequencer_frame() > pending_at:
			check_eq(am.current_note_semitone(), pending_semi, "kill heard on the predicted quarter (fill %d)" % k)
			pending_at = -1
			verified += 1
	check_eq(max_ahead, L, "rendered never more than the look-ahead ahead of the mixer")
	check(verified >= 8, "kills verified (%d)" % verified)
	check(max_latency <= L + Q, "kill -> new note <= look-ahead + 1 quarter (%d frames)" % max_latency)
	check(float(max_latency) / rate < 0.4, "kill audible within 0.4 s (%.3f s)" % (max_latency / rate))
	check_eq(pb.get_skips(), 0, "no underrun for stalls shorter than the look-ahead")
	am.free()
