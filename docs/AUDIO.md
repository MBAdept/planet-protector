# Audio – Planet Protector

Modern electronic sound (no chiptune), **100 % synthesised by our own Python code** (numpy/scipy):
no samples, no sample packs, no external presets. Implementation: `game/scripts/autoload/audio_manager.gd`
(autoload `AudioManager`). Rules: SPEC §14 and §16.7.

## Files

| Path (under `game/assets/audio/`) | Format | Content |
|---|---|---|
| `music/title.ogg` | OGG Vorbis q6, 44.1 kHz stereo, 30.72 s | Title/menu music, seamless loop (`loop=true` in the `.import` file **and** in code) |
| `music/game/kick.raw`, `hat.raw` | raw float32 LE, mono | one-shots for the in-game sequencer |
| `music/game/snare.raw`, `atmos.raw` | raw float32 LE, stereo interleaved | snare one-shot; 4-bar atmosphere loop |
| `music/game/bass.raw` | raw float32 LE, mono | 41 bass notes × 13230 frames (one quarter each), note *s* = E1·2^(s/12) |
| `music/game/meta.json` | JSON | rate, tempo, frame counts, file list |
| `sfx/<name>.wav` | 16-bit PCM WAV 44.1 kHz | 16 sound effects; imported **uncompressed** (`compress/mode=0`) |

`*.raw` and `*.json` are in the export include filter; Godot never imports them, so they arrive bit-exact
(read with `FileAccess.get_file_as_bytes().to_float32_array()`). This avoids relying on `AudioStreamWAV.data`.

## Title music (`tools/audio/make_title_music.py`)

Dark synthwave / cinematic electronic, **E minor, 125 BPM, 16 bars** (exactly 1 354 752 samples).
Chords two bars each: **Em | C | Am | B** (i–VI–iv–V, the major B gives the menacing pull back to Em), played twice.

- Bars 1–8: four-on-the-floor kick, clap on 2+4 with room, 8th → 16th hats, rolling 16th bass (alias-free saw
  + sine sub, notes only between the kicks), detuned 7-voice supersaw pads with sidechain pumping, a 16th-note
  pluck arpeggio whose filter slowly opens, dotted-8th ping-pong delay. Bar 1 and 9 start with a low distorted
  cinematic "braam", crash and a sub impact; bar 8 ends with a tom fill.
- Bars 9–16: the **lead hook** (3-3-2 rhythm: B–E–G–F#–E …, glide, delayed vibrato, chorus, delay, hall),
  full 16th hats, open hats, brighter pads. Bar 16 drops kick and bass for two beats: snare roll, noise riser and
  reverse cymbal lead back into the loop start.
- **Seamless loop by construction**: every note, reverb tail (circular FFT convolution with a synthetic IR) and
  delay repeat that runs past the end is wrapped to the beginning; stateful processing (filters, compressor,
  limiter) runs on three copies of the loop and keeps the middle one. Godot loops it sample-exactly (verified).
- Master: gentle glue compression (2.2:1), look-ahead brick-wall limiter at −2 dBFS (≈3 dB max. gain
  reduction) → **decoded OGG peak −1.4 dBFS, ≈ −11.4 LUFS**. Played at −4 dB in game.

## In-game music: runtime sequencer (`tools/audio/make_game_music.py` + `AudioManager`)

200 BPM, 1 bar = 1.2 s = **52 920 frames**, quarter = 13 230, 8th = 6 615 (all integers at 44.1 kHz → sample accurate).

- **Pattern**: kick on every quarter, snare/clap on beat 3, hats on every 8th with a velocity groove (4-bar cycle,
  off-beats accented, slight L/R alternation), quiet non-tonal atmosphere (dark "air", pumping on the quarters –
  deliberately without pitch so it never clashes with the rising bass).
- **Bass**: a hit on every quarter, pitch = **E1 (41.203 Hz) · 2^(semitone/12)** where semitone = `bass_semitone()`
  read at the frame where the note starts. Sound: two detuned alias-free saws + square + sine sub (fades in over
  25 ms so the kick keeps its punch), resonant low-pass with envelope, saturation and a presence boost around
  650 Hz so the rising pitch is clearly audible on laptop speakers. All 41 notes are pre-rendered (no resampling
  artefacts) and loudness-matched with a slight upward tilt (+1.5 dB over 40 semitones) for rising tension.
- **Runtime**: on startup the one-shots are assembled once into a 4-bar "bed" (tails wrapped) plus a separate
  "first bar" (no wrapped tails, 30 ms atmosphere fade-in). An `AudioStreamGenerator` (44.1 kHz) is topped up
  every frame in `_process` with bed + current bass note so that exactly **`LOOKAHEAD_FRAMES` = 3969 frames
  (90 ms ≈ 5.4 frames at 60 fps)** are queued. The look-ahead is explicit because Godot rounds the generator's
  ring up to a power of two (`buffer_length` 0.09 s → 4096 frames; the former 0.15 s silently became 8192
  frames = 186 ms). The timeline is counted in rendered frames, never in wall-clock time, so frame stalls
  cannot shift the beat; stalls shorter than 90 ms do not even cause a gap.
  Cost ≈ 0.15 ms per frame (735 frames), assembly ≈ 0.1 s once at boot.
- **Bass response**: the semitone is read when a note starts *rendering*, so a kill is heard on the first
  quarter that starts at least 90 ms later: **90–390 ms after the kill** (+ driver latency); a kill in the last
  ~90 ms before a beat moves to the following beat. Measured in a Movie Maker recording (16 kills at all
  phases of the beat, bass note identified per quarter from the audio): 100–367 ms, mean 229 ms
  (with the former 186 ms buffer: 183–467 ms, mean 323 ms, 9 of 16 kills a beat late instead of 4).
- `set_game_music_suspended(true)` stops the player immediately (silence within ~15 ms);
  `false` restarts the timeline at a bar start. `play_game_music()` keeps a running groove (no restart) and clears
  a suspension. `stop_music()` stops title + game music.

## Bass rules (SPEC §14)

`reset_bass(level)` at every level start → E1. `notify_enemy_destroyed()` once per destroyed ORIGINAL enemy
(GameScreen calls it only when `enemy_destroyed.group_cleared` is true, i.e. for a split pair when its last child dies).
`compute_bass_semitone(level, kills)`: levels 17, 18, 20 → `kills % 10`; otherwise `min(kills, 40)`.
The counter runs regardless of music on/off/suspended.

## Sound effects (`tools/audio/make_sfx.py`)

Loudness targets (≈LUFS, BS.1770 K-weighting) balance the mix: frequent sounds sit low, events high.

| name | description | target | peak cap |
|---|---|---|---|
| `shot_laser` | blue laser: FM zap falling 1.9 kHz → 380 Hz, click, sub punch | −21 | −6 |
| `shot_rocket` | ignition pop, rising hiss whoosh, low thump, sparks, faint whistle | −21 | −6 |
| `shot_blaster` | thick red laser: detuned saws diving 950 → 140 Hz through a closing filter | −19.5 | −5 |
| `enemy_fire` | fireball "fwoom": noise falling through a band-pass + low thoom + crackle | −22 | −7 |
| `enemy_hit` | small hit: metallic tick + noise burst + knock | −20 | −6 |
| `enemy_explode` | crack, roar with closing low-pass, falling boom, debris crackle, hall | −15.5 | −3 |
| `locked_hit` | "clink": inharmonic bell partials + dull blocked knock | −19 | −5 |
| `player_explode` | double blast, deeper boom, brighter roar + metallic sizzle, wider, 2.2 s – the loudest sound, limited to −1.5 dBFS (never clips) | −11.8 | −1.5 |
| `extra_life` | E-major glass-bell arpeggio over a soft supersaw swell, ping-pong delay | −16 | −3 |
| `level_complete` | rising bell arpeggio into a bright E-major supersaw chord + sub hit + shimmer | −14.5 | −2 |
| `materialize` | 0.45 s rising tremolo glissando + rising filtered noise (stereo) | −24 | −10 |
| `menu_move` / `menu_confirm` / `menu_back` | soft blip / rising two-tone / falling two-tone | −21 / −18 / −19.5 | |
| `bonus_tick` | very short bright tick for counting | −21 | −8 |
| `game_over` | sinking distorted low drone, falling minor bells, long hall | −14 | −2 |

## AudioManager (runtime mixing)

- Buses **Music** and **SFX** are created at runtime if missing (sending to Master); an
  `AudioEffectHardLimiter` (ceiling −1 dB) sits on Master as a safety net (verified: output never exceeds −1 dBFS).
- `apply_settings()` mutes the buses from `Settings.music_on` / `Settings.sfx_on` immediately; connected to
  `Settings.changed` and applied at start. `process_mode = ALWAYS` (works while the tree is paused).
- SFX pool: 12 `AudioStreamPlayer`s, max **3 simultaneous per name** (the oldest of that name restarts), streams
  cached at startup. When the pool is full the oldest sound of the lowest priority is replaced (equal priority
  may replace, lower may not: then the new sound is dropped); long stingers and the player explosion have high
  priority. The choice is the pure static `choose_sfx_slot()` (unit-tested). Repeated sounds get a small random
  detune (±2–6 %) unless the caller passes its own pitch.
- `game_over` is a 4 s stinger meant to be played once when the game-over screen opens
  (`AudioManager.play_sfx("game_over")`, after `stop_music()`).
- Volumes: title −4 dB, game music −2 dB, SFX 0 dB (levels are baked into the files).
- Headless / Dummy driver: all API calls are harmless; the logical state is kept, but no player is started
  (nothing would be audible, and Godot would report playbacks still in use at exit). Movie Maker
  (`--write-movie`) is detected and does play, so audio can be recorded for checks.

## Regenerate

```bash
tools/audio/build_audio.sh            # everything (~1 min): title + sequencer samples + SFX, import, analysis
tools/audio/build_audio.sh sfx        # only SFX   (also: title | game)
python3 tools/audio/analyze_audio.py --png docs/previews/audio   # analysis + spectrograms
```

`build_audio.sh` renders, encodes the OGG (`ffmpeg -c:a libvorbis -q:a 6`), runs `godot --import`, pins the import
parameters (`tools/audio/set_import_params.py`: WAV uncompressed, OGG loop) and analyses the result (peaks,
loudness, octave balance, loop seam, codec error at the loop edges, bass pitch per semitone).
Sequencer gains/hat velocities live in both `make_game_music.py` (preview) and `audio_manager.gd`
(`SEQ_GAIN`, `HAT_VEL`) – keep them in sync.

## Verification done

- `godot --headless --path game -s res://tests/run_tests.gd` → `tests/test_audio.gd` (bass rules, notify while
  music off/suspended, headless API, bus/limiter setup, assets, **sample-accurate sequencer**: pitch changes
  exactly at quarter boundaries, chunked rendering identical to one-shot rendering, correct note per semitone;
  **SFX slot choice**: per-name cap restarts the oldest instance, free slots, priority stealing and dropping;
  **look-ahead**: the real fill against Godot's real generator ring, consumed by the real resampler with uneven
  frame times and stalls → always exactly 3969 frames queued, no underrun, every kill on the predicted quarter,
  kill → note ≤ 0.39 s). The SFX and look-ahead tests were mutation-checked (old fill, cap/priority variants).
- Movie Maker recordings (real mixing through buses, generator and limiter): beat grid exactly 0.300 s, bass
  pitch per bar = E1·2^(s/12), suspend → digital silence within 15 ms, restart at a bar start, music-off mutes
  immediately, per-name cap holds at 3, output peak −1.0 dBFS, title loop seam sample-exact in Godot
  (error at the loop point −42 dB, lower than mid-loop), in-game mix ≈ −14.5 LUFS.
- Exported release build: raw PCM files are inside the PCK and the sequencer plays (300 ms quarter period).
