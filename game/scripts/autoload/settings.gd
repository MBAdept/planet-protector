extends Node
## Autoload "Settings": persistent options and the four highscore lists (docs/SPEC.md §11, §13).
## Highscore names: max NAME_MAX (8) characters – client decision, originally 5. Files written with 5-character names
## load unchanged; longer names in a hand-edited file are cut to NAME_MAX on load (sanitize_name).
## Volumes (SPEC §14): MUSIC VOLUME / EFFECTS VOLUME in percent, 0–100 in VOLUME_STEP steps, default 100 (the
## original mix). They scale the Music / SFX bus (AudioManager.volume_db); the ON/OFF options still mute on top.
## Display (client request, widescreen round; Steam Deck round): display_mode 0–4 = Display.Mode (0 = the
## classic 4:3 window, default; 3 / 4 = the Steam Deck 1280×800 and the 1280×720 modes) and display_chosen (false until the player confirmed a mode on the first-start screen). Files written
## before these keys existed read as mode 0, not chosen – so that screen appears once.
## Two players / power-ups (SPEC §19, client request, forum round): the title's PLAYERS (1 / 2) and POWER-UPS (OFF / ON)
## are stored as [game] players / powerups (missing keys: 1 player, power-ups off). Power-up runs have their OWN four
## highscore lists (JSON keys "p0" … "p3" next to the classic "0" … "3"; older files simply have none). A two-player
## match enters both players' scores into the normal lists of its difficulty and power-up setting (the rules per
## player are exactly those of a one-player run).

signal changed

const SETTINGS_PATH := "user://settings.cfg"
const HIGHSCORE_PATH := "user://highscores.json"
const LIST_SIZE := 10
const NAME_MAX := 8
const NAME_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
const DEFAULT_NAME := "PILOT"
const VOLUME_STEP := 10
const VOLUME_MAX := 100
const DEFAULT_VOLUME := 100
## Menu item ids of the two volume options (title menu and pause overlay).
const VOLUME_ITEMS: Array[String] = ["music_volume", "sfx_volume"]
## Number of display modes: Display.MODE_COUNT itself (one source; valid stored values 0 … DISPLAY_MODES − 1).
const DISPLAY_MODES: int = preload("res://scripts/autoload/display.gd").MODE_COUNT

var difficulty := 1
var music_on := true
var sfx_on := true
var fullscreen := false
var music_volume := DEFAULT_VOLUME   ## percent, multiple of VOLUME_STEP
var sfx_volume := DEFAULT_VOLUME     ## percent, multiple of VOLUME_STEP
var display_mode := 0               ## Display.Mode: 0 classic 4:3 window, 1 / 2 fullscreen 16:9 (1080 / 1440),
                                    ## 3 fullscreen 16:10 1280×800 (Steam Deck), 4 fullscreen 16:9 1280×720
var display_chosen := false         ## the player confirmed a mode on the first-start screen
var players := 1                    ## title PLAYERS: 1 (classic) or 2 (hotseat match, SPEC §19.2)
var powerups := false               ## title POWER-UPS (SPEC §19.3)
## File of the options (tests point it to a scratch file so the player's settings stay untouched).
var settings_path := SETTINGS_PATH
## File of the highscore lists (same: tests use a scratch file).
var highscore_path := HIGHSCORE_PATH

## difficulty id (0..3) → Array of entries {name, score, time, level, ship}: classic runs …
var _highscores := {0: [], 1: [], 2: [], 3: []}
## … and runs with POWER-UPS on (SPEC §19.3).
var _highscores_pu := {0: [], 1: [], 2: [], 3: []}


func _ready() -> void:
	load_settings()
	load_highscores()


# --- Options -------------------------------------------------------------------------------------
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	difficulty = clampi(int(cfg.get_value("game", "difficulty", difficulty)), 0, 3)
	music_on = bool(cfg.get_value("audio", "music_on", music_on))
	sfx_on = bool(cfg.get_value("audio", "sfx_on", sfx_on))
	# Files written before the volume options existed have no keys: the default (100 %) is the old mix.
	music_volume = clean_volume(cfg.get_value("audio", "music_volume", DEFAULT_VOLUME))
	sfx_volume = clean_volume(cfg.get_value("audio", "sfx_volume", DEFAULT_VOLUME))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	display_mode = clean_display_mode(cfg.get_value("video", "display_mode", 0))
	var chosen: Variant = cfg.get_value("video", "display_chosen", false)
	display_chosen = chosen is bool and chosen
	players = clean_players(cfg.get_value("game", "players", 1))
	var pu: Variant = cfg.get_value("game", "powerups", false)
	powerups = pu is bool and pu


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "players", players)
	cfg.set_value("game", "powerups", powerups)
	cfg.set_value("audio", "music_on", music_on)
	cfg.set_value("audio", "sfx_on", sfx_on)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "display_mode", display_mode)
	cfg.set_value("video", "display_chosen", display_chosen)
	cfg.save(settings_path)


func set_difficulty(value: int) -> void:
	difficulty = posmod(value, 4)
	save_settings()
	changed.emit()


## PLAYERS of the title (1 / 2; anything else → 1).
func set_players(value: int) -> void:
	players = clean_players(value)
	save_settings()
	changed.emit()


## POWER-UPS of the title.
func set_powerups(value: bool) -> void:
	powerups = value
	save_settings()
	changed.emit()


## A stored PLAYERS value: 2 (also the float 2.0) or else 1.
static func clean_players(value: Variant) -> int:
	return 2 if (value is int or value is float) and float(value) == 2.0 else 1


func set_music_on(value: bool) -> void:
	music_on = value
	save_settings()
	changed.emit()


func set_sfx_on(value: bool) -> void:
	sfx_on = value
	save_settings()
	changed.emit()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	save_settings()
	changed.emit()


## Stores the display mode (Display.Mode; invalid values → 0, see clean_display_mode). Display.choose() applies it.
func set_display_mode(value: int) -> void:
	display_mode = clean_display_mode(value)
	save_settings()
	changed.emit()


## Marks the first-start display choice as done (the first-start screen does not appear again).
func set_display_chosen(value: bool) -> void:
	display_chosen = value
	save_settings()
	changed.emit()


## A display mode as stored: an integer 0–4 (a whole-number float like 1.0 counts as that integer); anything else
## – another type, a fraction like 1.5, NaN, out of range – is a damaged file and falls back to 0 (classic), so a
## broken settings.cfg never starts the game fullscreen.
static func clean_display_mode(value: Variant) -> int:
	if value is float:
		if is_nan(value) or value != floorf(value):
			return 0
		value = int(value)
	if not (value is int):
		return 0
	return value if value >= 0 and value < DISPLAY_MODES else 0


## Sets MUSIC VOLUME (clamped to 0–100, snapped to VOLUME_STEP). Saves and emits `changed` only if the value
## changed; returns whether it did (a step beyond 0 % / 100 % does nothing).
func set_music_volume(percent: int) -> bool:
	var v := clean_volume(percent)
	if v == music_volume:
		return false
	music_volume = v
	save_settings()
	changed.emit()
	return true


## Sets EFFECTS VOLUME, see set_music_volume.
func set_sfx_volume(percent: int) -> bool:
	var v := clean_volume(percent)
	if v == sfx_volume:
		return false
	sfx_volume = v
	save_settings()
	changed.emit()
	return true


## Current value of a volume item ("music_volume" / "sfx_volume").
func volume(item: String) -> int:
	return music_volume if item == "music_volume" else sfx_volume


## The ON/OFF option that belongs to a volume item (MUSIC / SOUND EFFECTS); OFF silences it whatever the volume.
func volume_switch_on(item: String) -> bool:
	return music_on if item == "music_volume" else sfx_on


## One menu step (dir = -1 / +1) of a volume item: ±VOLUME_STEP, clamped. True if the value changed.
func step_volume(item: String, dir: int) -> bool:
	var v := volume(item) + signi(dir) * VOLUME_STEP
	return set_music_volume(v) if item == "music_volume" else set_sfx_volume(v)


## A volume as stored: numbers are rounded to a multiple of VOLUME_STEP and clamped to 0–100; anything else
## (a damaged file) falls back to DEFAULT_VOLUME.
static func clean_volume(value: Variant) -> int:
	if not (value is int or value is float):
		return DEFAULT_VOLUME
	return clampi(snappedi(roundi(float(value)), VOLUME_STEP), 0, VOLUME_MAX)


# --- Highscores ----------------------------------------------------------------------------------
func load_highscores() -> void:
	if not FileAccess.file_exists(highscore_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(highscore_path))
	if not (data is Dictionary):
		return
	for pu in [false, true]:
		for d in 4:
			var list: Array = []
			var raw: Variant = data.get(list_key(d, pu), [])
			if raw is Array:
				for e in raw:
					if e is Dictionary:
						list.append(_clean_entry(e))
			sort_entries(list)
			_lists(pu)[d] = list.slice(0, LIST_SIZE)


func save_highscores() -> void:
	var out := {}
	for pu in [false, true]:
		for d in 4:
			out[list_key(d, pu)] = _lists(pu)[d]
	var f := FileAccess.open(highscore_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  ", false, true))


## JSON key of a list: "0" … "3" (classic), "p0" … "p3" (power-ups).
static func list_key(diff: int, p_powerups: bool) -> String:
	return ("p%d" if p_powerups else "%d") % clampi(diff, 0, 3)


func _lists(p_powerups: bool) -> Dictionary:
	return _highscores_pu if p_powerups else _highscores


## The top 10 of a difficulty – classic, or with p_powerups the power-up list.
func get_highscores(diff: int, p_powerups: bool = false) -> Array:
	return (_lists(p_powerups)[clampi(diff, 0, 3)] as Array).duplicate(true)


## True if an entry with this score/time would enter the top 10 of that difficulty (and power-up setting).
func qualifies(diff: int, score: int, time: float, p_powerups: bool = false) -> bool:
	var list: Array = _lists(p_powerups)[clampi(diff, 0, 3)]
	if list.size() < LIST_SIZE:
		return true
	return _better({"score": score, "time": time}, list[list.size() - 1])


## Inserts an entry, persists and returns its rank index (0-based) or -1 if it did not qualify.
func insert_highscore(diff: int, entry: Dictionary, p_powerups: bool = false) -> int:
	diff = clampi(diff, 0, 3)
	var e := _clean_entry(entry)
	var lists := _lists(p_powerups)
	var list: Array = lists[diff]
	list.append(e)
	sort_entries(list)
	var rank := list.find(e)
	lists[diff] = list.slice(0, LIST_SIZE)
	if rank >= LIST_SIZE:
		return -1
	save_highscores()
	return rank


## Primary: score descending; secondary: time ascending (SPEC §13). Stable for equal entries.
static func sort_entries(list: Array) -> void:
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _better(a, b))


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if int(a["score"]) != int(b["score"]):
		return int(a["score"]) > int(b["score"])
	return float(a["time"]) < float(b["time"])


## Upper-case, only NAME_CHARS, at most NAME_MAX characters (longer names are cut); empty → DEFAULT_NAME.
static func sanitize_name(raw: String) -> String:
	var out := ""
	for ch in raw.to_upper():
		if NAME_CHARS.contains(ch) and out.length() < NAME_MAX:
			out += ch
	return out if out != "" else DEFAULT_NAME


func _clean_entry(e: Dictionary) -> Dictionary:
	return {
		"name": sanitize_name(str(e.get("name", ""))),
		"score": int(e.get("score", 0)),
		"time": float(e.get("time", 0.0)),
		"level": int(e.get("level", 1)),
		"ship": int(e.get("ship", 0)),
	}
