extends Node
## Autoload "Run": state of the current run, shared between screens (docs/SPEC.md §17).

var difficulty := 1
var ship_id := 0
var speed_factor := 1.0
var score := 0
var lives := 3
var level := 1
## Real (unscaled) seconds of active level play, see SPEC §9.
var active_time := 0.0
var active := false

## Filled by GameScreen before it emits "completed".
var last_level_result := {}
var last_bonus_result := {}

## Dev/test flags parsed by Main from the command line (SPEC §17.3).
var dev_flags := {}


func start_new(p_difficulty: int, p_ship_id: int, start_level: int = 1) -> void:
	var d := ShipData.difficulty(p_difficulty)
	difficulty = int(d["id"])
	speed_factor = float(d["speed_factor"])
	lives = int(d["lives"])
	ship_id = clampi(p_ship_id, 0, ShipData.SHIPS.size() - 1)
	score = 0
	level = clampi(start_level, LevelData.FIRST_LEVEL, LevelData.LAST_LEVEL)
	active_time = 0.0
	last_level_result = {}
	last_bonus_result = {}
	active = true


func difficulty_name() -> String:
	return String(ShipData.difficulty(difficulty)["name"])


func dev(flag: String) -> bool:
	return bool(dev_flags.get(flag, false))
