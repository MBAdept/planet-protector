extends Node
## Autoload "Run": state of the current run, shared between screens (docs/SPEC.md §17).
## Two players (hotseat, SPEC §19, client request, forum round): both players share the difficulty, the power-up
## switch and the level sequence, everything else is per player. The per-player fields below (ship_id, score, lives,
## level, active_time, last_level_result, last_bonus_result, out, won, locked) always hold the state of the CURRENT
## player (`current`); switch_to() parks them in the player's slot and loads the other one. So every screen that reads
## Run.score / Run.lives / … shows the player whose turn it is, and a one-player run is exactly as before.

const PLAYER_FIELDS: Array[String] = ["ship_id", "score", "lives", "level", "active_time", "last_level_result",
	"last_bonus_result", "out", "won", "locked"]

var difficulty := 1
var speed_factor := 1.0
## 1 = classic one-player run, 2 = hotseat match (SPEC §19.2).
var players := 1
## POWER-UPS for this run (SPEC §19.3): one power-up per level on Saturn, Jupiter and Mars.
var powerups := false
## Index of the player whose state is in the per-player fields: 0 = PLAYER 1, 1 = PLAYER 2 (always 0 with 1 player).
var current := 0

# --- Per-player fields (the current player's) ------------------------------------------------------
var ship_id := 0
var score := 0
var lives := 3
var level := 1
## Real (unscaled) seconds of active level play, see SPEC §9.
var active_time := 0.0
## Filled by GameScreen before it emits "completed".
var last_level_result := {}
var last_bonus_result := {}
## The player lost the last life (game over; in a match the other one plays on).
var out := false
## The player completed level 20.
var won := false
## Ship ids this player may not fly (locked by the other player before the match, SPEC §19.2).
var locked: Array[int] = []

var active := false

## Dev/test flags parsed by Main from the command line (SPEC §17.3).
var dev_flags := {}

## Parked state of both players (only the entry of the player who is NOT current is up to date).
var _slots: Array[Dictionary] = [{}, {}]


## Starts a one-player run (the classic game; p_powerups: POWER-UPS on).
func start_new(p_difficulty: int, p_ship_id: int, start_level: int = 1, p_powerups: bool = false) -> void:
	_start_common(p_difficulty, 1, p_powerups)
	_reset_player(p_ship_id, start_level, [])
	_slots = [_pack(), {}]
	active = true


## Starts a two-player hotseat match: ships[k] / p_locked[k] (ship ids player k may not fly) of PLAYER 1 / 2.
## PLAYER 1 is current afterwards. Both players start at start_level with the difficulty's lives.
func start_match(p_difficulty: int, ships: Array, p_locked: Array, start_level: int = 1,
		p_powerups: bool = false) -> void:
	_start_common(p_difficulty, 2, p_powerups)
	var slots: Array[Dictionary] = [{}, {}]
	for k in 2:
		var lk: Array = p_locked[k] if k < p_locked.size() else []
		_reset_player(int(ships[k]) if k < ships.size() else 0, start_level, lk)
		slots[k] = _pack()
	_slots = slots
	current = 0
	_unpack(_slots[0])
	active = true


func _start_common(p_difficulty: int, p_players: int, p_powerups: bool) -> void:
	var d := ShipData.difficulty(p_difficulty)
	difficulty = int(d["id"])
	speed_factor = float(d["speed_factor"])
	players = p_players
	powerups = p_powerups
	current = 0


func _reset_player(p_ship_id: int, start_level: int, p_locked: Array) -> void:
	lives = int(ShipData.difficulty(difficulty)["lives"])
	ship_id = clampi(p_ship_id, 0, ShipData.SHIPS.size() - 1)
	score = 0
	level = clampi(start_level, LevelData.FIRST_LEVEL, LevelData.LAST_LEVEL)
	active_time = 0.0
	last_level_result = {}
	last_bonus_result = {}
	out = false
	won = false
	var lk: Array[int] = []
	for id in p_locked:
		lk.append(int(id))
	locked = lk


func is_two_player() -> bool:
	return players == 2


## Makes player k (0 / 1) current: the current player's fields are parked in its slot, player k's are loaded.
## No-op for k == current or in a one-player run.
func switch_to(k: int) -> void:
	if players < 2 or k == current or k < 0 or k > 1:
		return
	_slots[current] = _pack()
	current = k
	_unpack(_slots[k])


## A per-player value (PLAYER_FIELDS) of player k – the live field for the current player, else the parked one.
func player_get(k: int, key: String) -> Variant:
	if k == current:
		return get(key)
	return (_slots[clampi(k, 0, 1)] as Dictionary).get(key)


## "PLAYER 1" / "PLAYER 2".
static func player_label(k: int) -> String:
	return "PLAYER %d" % (k + 1)


func _pack() -> Dictionary:
	var d := {}
	for f in PLAYER_FIELDS:
		var v: Variant = get(f)
		d[f] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	return d


func _unpack(d: Dictionary) -> void:
	for f in PLAYER_FIELDS:
		if d.has(f):
			var v: Variant = d[f]
			if f == "locked":
				var lk: Array[int] = []
				for id in v:
					lk.append(int(id))
				locked = lk
			else:
				set(f, v.duplicate(true) if (v is Dictionary or v is Array) else v)


func difficulty_name() -> String:
	return String(ShipData.difficulty(difficulty)["name"])


func dev(flag: String) -> bool:
	return bool(dev_flags.get(flag, false))
