extends Node
## Autoload "Settings": persistent options and the four highscore lists (docs/SPEC.md §11, §13).

signal changed

const SETTINGS_PATH := "user://settings.cfg"
const HIGHSCORE_PATH := "user://highscores.json"
const LIST_SIZE := 10
const NAME_MAX := 5
const NAME_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
const DEFAULT_NAME := "PILOT"

var difficulty := 1
var music_on := true
var sfx_on := true
var fullscreen := false

## difficulty id (0..3) → Array of entries {name, score, time, level, ship}
var _highscores := {0: [], 1: [], 2: [], 3: []}


func _ready() -> void:
	load_settings()
	load_highscores()


# --- Options -------------------------------------------------------------------------------------
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	difficulty = clampi(int(cfg.get_value("game", "difficulty", difficulty)), 0, 3)
	music_on = bool(cfg.get_value("audio", "music_on", music_on))
	sfx_on = bool(cfg.get_value("audio", "sfx_on", sfx_on))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("audio", "music_on", music_on)
	cfg.set_value("audio", "sfx_on", sfx_on)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.save(SETTINGS_PATH)


func set_difficulty(value: int) -> void:
	difficulty = posmod(value, 4)
	save_settings()
	changed.emit()


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


# --- Highscores ----------------------------------------------------------------------------------
func load_highscores() -> void:
	if not FileAccess.file_exists(HIGHSCORE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(HIGHSCORE_PATH))
	if not (data is Dictionary):
		return
	for d in 4:
		var list: Array = []
		for e in data.get(str(d), []):
			if e is Dictionary:
				list.append(_clean_entry(e))
		sort_entries(list)
		_highscores[d] = list.slice(0, LIST_SIZE)


func save_highscores() -> void:
	var out := {}
	for d in 4:
		out[str(d)] = _highscores[d]
	var f := FileAccess.open(HIGHSCORE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  ", false, true))


func get_highscores(diff: int) -> Array:
	return (_highscores[clampi(diff, 0, 3)] as Array).duplicate(true)


## True if an entry with this score/time would enter the top 10 of that difficulty.
func qualifies(diff: int, score: int, time: float) -> bool:
	var list: Array = _highscores[clampi(diff, 0, 3)]
	if list.size() < LIST_SIZE:
		return true
	return _better({"score": score, "time": time}, list[list.size() - 1])


## Inserts an entry, persists and returns its rank index (0-based) or -1 if it did not qualify.
func insert_highscore(diff: int, entry: Dictionary) -> int:
	diff = clampi(diff, 0, 3)
	var e := _clean_entry(entry)
	var list: Array = _highscores[diff]
	list.append(e)
	sort_entries(list)
	var rank := list.find(e)
	_highscores[diff] = list.slice(0, LIST_SIZE)
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
