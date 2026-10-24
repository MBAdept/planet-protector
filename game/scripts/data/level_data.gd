class_name LevelData
extends RefCounted
## Static rule tables (docs/SPEC.md §1, §5–§10). Pure data + small helpers, no state.

# --- Geometry / timing constants -----------------------------------------------------------------
const SCREEN_W := 960.0
const SCREEN_H := 720.0
const GROUND_Y := 685.0
const PLAYER_Y := 659.0
const SALVO_Y := 639.0
const PLAYER_MIN_X := 30.0
const PLAYER_MAX_X := 930.0
const PLAYER_START_X := 480.0
const PLAYER_SPEED := 350.0

const LANE_Y: Array[float] = [180.0, 300.0, 420.0]
const BOTTOM_LANE := 2
const ENEMY_BASE_SPEED := 62.0
const ENEMY_MIN_X := 50.0          # turning limits of the enemy center (all figures), see SPEC §5
const ENEMY_MAX_X := 910.0
const ENEMY_BASE_WIDTH := 90.0
const ENEMY_OSC_AMPLITUDE := 22.0
const ENEMY_OSC_HZ := 0.55
const FLAP_HZ := 2.5
const MATERIALIZE_TIME := 0.45
const SPAWN_MIN_DISTANCE := 160.0
## Fair spawning (SPEC §5): a new original keeps its column free of the figures on the OTHER lanes
## (|dx| ≥ this, children included); crowded screens relax both spawn distances by the same factor.
const SPAWN_COLUMN_CLEARANCE := 110.0
const SPAWN_RELAX_STEPS := 10      # relaxation factors 1.0, 0.9, … 0.0
## Nearest other-lane figure within this |dx| → a new original starts opposite to that figure's direction.
const SPAWN_DIR_RANGE := 250.0
## Stack breaking (SPEC §5, levels ≥ DIR_CHANGE_FROM_LEVEL): a figure counts as covered while a figure on a
## LOWER lane within |dx| < STACK_OVERLAP_DX moves the same way; covered for STACK_COVER_TIME game seconds
## → it reverses early (never sooner than DIR_CHANGE_MIN after its own last direction change).
const STACK_OVERLAP_DX := 60.0
const STACK_COVER_TIME := 0.5
const CHILD_SPAWN_OFFSET := 24.0

const HIT_DX := 49.0               # own projectile vs enemy (scaled by enemy scale)
const HIT_DY := 21.0
const PLAYER_HIT_DX := 21.0        # enemy bullet vs player
const PLAYER_HIT_DY := 15.0

const ENEMY_BULLET_SPEED := 220.0
const ENEMY_BULLET_DIAG_A := 110.0
const ENEMY_BULLET_DIAG_B := 190.5255888
const ENEMY_BULLET_W := 10.0
const ENEMY_BULLET_SPAWN_DY := 18.0
const LEVEL10_COLUMN_DY := 18.0
const OWN_PROJECTILE_REMOVE_Y := -40.0

const FIRE_INTERVAL_MIN := 1.8
const FIRE_INTERVAL_MAX := 2.8
const FIRE_INITIAL_RANK1 := 2.0
const FIRE_INITIAL_RANK2 := 2.5

const REFILL_DELAY := 2.0
const RESPAWN_DELAY := 1.3
const ENEMY_EXPLOSION_TIME := 0.9
const PLAYER_EXPLOSION_TIME := 1.3
const HIT_FLASH_TIME := 0.18
const ROLLING_WINDOW := 10.0
const ROLLING_HITS := 3
const SIM_STEP := 1.0 / 240.0
const DIR_CHANGE_MIN := 1.2
const DIR_CHANGE_MAX := 3.2
const DIR_CHANGE_FROM_LEVEL := 10
const INTRO_TIME := 1.8            # real seconds, level banner

const FIRST_LEVEL := 1
const LAST_LEVEL := 20
const BONUS_LEVEL := 13
const MARS_RULES_BEFORE_LEVEL := 14
const BONUS_ATTEMPTS := 100
const BONUS_TARGET := 20
const BONUS_EXTRA_LIFE_THRESHOLD := 6000   # extra life only if bonus is STRICTLY greater
const FLAWLESS_EXTRA_LIFE_LEVELS: Array[int] = [10, 15, 16, 17, 18]

enum Hit { SINGLE, SPLIT, COLOR_LOCK, ROLLING }
enum Dir { DOWN, D57, D48 }
enum Perm { NONE, RANK1, RANK2, LANE_BOTTOM, LANES_MID_BOTTOM, ALL }
enum ChildRule { NONE, ONE_ARMED, BOTTOM_LANE }
enum Stage { VIOLET, YELLOW, GREEN }

const PLANETS: Array[String] = ["neptune", "uranus", "saturn", "jupiter", "mars", "earth"]
const PLANET_NAMES := {
	"neptune": "Neptune", "uranus": "Uranus", "saturn": "Saturn",
	"jupiter": "Jupiter", "mars": "Mars", "earth": "Earth",
}
const PLANET_WIDTH_FACTOR := {
	"neptune": 1.00, "uranus": 1.02, "saturn": 1.04, "jupiter": 1.06, "mars": 1.08, "earth": 1.10,
}
const GROUND_COLORS := {
	"neptune": Color(0.10, 0.20, 0.46), "uranus": Color(0.32, 0.58, 0.62), "saturn": Color(0.58, 0.47, 0.31),
	"jupiter": Color(0.46, 0.29, 0.16), "mars": Color(0.58, 0.23, 0.11), "earth": Color(0.20, 0.42, 0.17),
}
## Sphere diameter of the background planet for zoom stage 1/2/3 (SPEC §15).
const PLANET_DIAMETERS: Array[float] = [174.0, 174.0 * 220.0 / 192.0, 174.0 * 275.0 / 192.0]

# Arrival sequences after these levels (SPEC §11), texts must stay EXACT.
const ARRIVAL_AFTER := {
	3: {"text": "Neptun has been secured - approaching Uranus", "target": "uranus"},
	6: {"text": "Uranus has been secured - approaching Saturn", "target": "saturn"},
	9: {"text": "Saturn has been secured - approaching Jupiter", "target": "jupiter"},
	12: {"text": "Jupiter has been secured - approaching Mars", "target": "mars"},
	16: {"text": "Mars has been secured - protect EARTH!", "target": "earth"},
}
const VICTORY_TEXT := "You are a real champion on the trigger. You moved smoothly through enemy lines, you destroyed them all! Everlasting love to You, oh great PLANET PROTECTOR!"
const BONUS_TITLE := "Prove Your Accuracy!"

# --- Colours (top → bottom gradient stops) -------------------------------------------------------
const C_VIOLET_STOPS: Array[Color] = [Color(0.66, 0.28, 1.0), Color(0.06, 0.02, 0.09)]
const C_YELLOW_STOPS: Array[Color] = [Color(1.0, 0.98, 0.60), Color(0.62, 0.50, 0.0)]
const C_GREEN_STOPS: Array[Color] = [Color(0.62, 1.0, 0.55), Color(0.0, 0.33, 0.06)]
const C_RAINBOW: Array[Color] = [
	Color(0.56, 0.18, 0.95), Color(0.22, 0.30, 1.0), Color(0.10, 0.72, 0.95),
	Color(0.15, 0.85, 0.28), Color(1.0, 0.92, 0.10),
]
const C_BLACK: Array[Color] = [Color(0.035, 0.035, 0.045), Color(0.02, 0.02, 0.03)]
const EYE_COLOR_DEFAULT := Color(1.0, 0.95, 0.70)
const EYE_COLOR_BLACK := Color(1.0, 0.28, 0.08)
const HIT_FLASH_COLOR := Color(1.0, 0.55, 0.1)

# --- Level table (SPEC §6). Index 0 is unused. ---------------------------------------------------
const LEVELS := [
	{},
	{"name": "Neptune 1", "total": 10, "lanes": [1, 1, 1], "tempo": 1.0, "fire": 1.0, "points": 10, "bonus": 100,
		"colors": [Color(0.08, 0.22, 0.95), Color(0.55, 1.0, 1.0)]},
	{"name": "Neptune 2", "total": 10, "lanes": [1, 1, 1], "tempo": 1.0, "fire": 1.2, "points": 10, "bonus": 100,
		"colors": [Color(0.45, 0.02, 0.02), Color(1.0, 0.92, 0.12)]},
	{"name": "Neptune 3", "total": 12, "lanes": [1, 1, 2], "tempo": 1.0, "fire": 1.2, "points": 10, "bonus": 100,
		"colors": [Color(0.28, 0.04, 0.42), Color(1.0, 0.55, 0.82)]},
	{"name": "Uranus 1", "total": 12, "lanes": [1, 1, 2], "tempo": 1.2, "fire": 1.25, "points": 25, "bonus": 250,
		"colors": [Color(0.03, 0.32, 0.07), Color(1.0, 0.95, 0.20)]},
	{"name": "Uranus 2", "total": 16, "lanes": [2, 1, 2], "tempo": 1.2, "fire": 1.3, "points": 25, "bonus": 250,
		"colors": [Color(0.86, 0.87, 0.90), Color(0.06, 0.06, 0.07)]},
	{"name": "Uranus 3", "total": 16, "lanes": [2, 1, 2], "tempo": 1.2, "fire": 1.35, "points": 25, "bonus": 250,
		"colors": [Color(0.06, 0.42, 0.12), Color(0.02, 0.05, 0.02)]},
	{"name": "Saturn 1", "total": 10, "lanes": [1, 1, 1], "tempo": 1.2, "fire": 1.25, "points": 25, "bonus": 500,
		"colors": [Color(0.62, 0.52, 0.04), Color(1.0, 1.0, 1.0)]},
	{"name": "Saturn 2", "total": 12, "lanes": [1, 1, 1], "tempo": 1.38, "fire": 1.3, "points": 25, "bonus": 500,
		"colors": [Color(0.03, 0.07, 0.45), Color(0.82, 0.93, 1.0)]},
	{"name": "Saturn 3", "total": 12, "lanes": [1, 1, 1], "tempo": 1.518, "fire": 1.35, "points": 25, "bonus": 500,
		"colors": [Color(0.48, 0.02, 0.03), Color(1.0, 0.84, 0.82)]},
	{"name": "Jupiter 1", "total": 16, "lanes": [1, 1, 1], "tempo": 1.6698, "fire": 1.4, "points": 40, "bonus": 750,
		"colors": [Color(0.48, 0.02, 0.03), Color(1.0, 0.84, 0.82)]},
	{"name": "Jupiter 2", "total": 16, "lanes": [1, 1, 2], "tempo": 2.00376, "fire": 1.75, "points": 40, "bonus": 750,
		"colors": [Color(0.10, 0.88, 0.82), Color(0.02, 0.06, 0.06)]},
	{"name": "Jupiter 3", "total": 16, "lanes": [1, 1, 2], "tempo": 2.404512, "fire": 1.9, "points": 50, "bonus": 900,
		"colors": [Color(1.0, 0.55, 0.05), Color(0.06, 0.03, 0.01)]},
	{"name": "Mars / Bonus", "total": 20, "lanes": [1, 1, 0], "tempo": 3.606768, "fire": 0.0, "points": 0, "bonus": 0,
		"colors": [Color(0.58, 0.35, 0.16), Color(0.05, 0.03, 0.02)]},
	{"name": "Mars 1", "total": 12, "lanes": [1, 1, 1], "tempo": 1.5, "fire": 1.9, "points": 75, "bonus": 1000,
		"colors": C_VIOLET_STOPS},
	{"name": "Mars 2", "total": 20, "lanes": [1, 2, 1], "tempo": 1.8, "fire": 2.2, "points": 100, "bonus": 1500,
		"colors": C_VIOLET_STOPS},
	{"name": "Mars 3", "total": 25, "lanes": [2, 2, 1], "tempo": 2.0, "fire": 2.5, "points": 110, "bonus": 2000,
		"colors": C_VIOLET_STOPS},
	{"name": "Earth 1", "total": 40, "lanes": [2, 2, 2], "tempo": 2.2, "fire": 2.6, "points": 120, "bonus": 2000,
		"colors": C_RAINBOW},
	{"name": "Earth 2", "total": 40, "lanes": [2, 2, 2], "tempo": 2.4, "fire": 2.2, "points": 120, "bonus": 2000,
		"colors": [Color(1.0, 0.92, 0.10), Color(0.15, 0.85, 0.28), Color(0.10, 0.72, 0.95), Color(0.22, 0.30, 1.0), Color(0.56, 0.18, 0.95)]},
	{"name": "Earth 3", "total": 12, "lanes": [1, 1, 1], "tempo": 2.6, "fire": 2.4, "points": 150, "bonus": 3000,
		"colors": C_BLACK, "black": true},
	{"name": "Earth – Final Battle", "total": 30, "lanes": [2, 2, 2], "tempo": 2.9, "fire": 2.5, "points": 150, "bonus": 500,
		"colors": C_BLACK, "black": true},
]

# --- Enemy fire table (SPEC §7) ------------------------------------------------------------------
# count/width are for a full figure; child_count is used for armed children (child rule).
const FIRE := [
	{},
	{"count": 1, "width": 0.0, "dir": Dir.DOWN, "perm": Perm.RANK1},
	{"count": 4, "width": 0.70, "dir": Dir.DOWN, "perm": Perm.RANK1},
	{"count": 4, "width": 0.70, "dir": Dir.DOWN, "perm": Perm.RANK2},
	{"count": 6, "width": 0.55, "dir": Dir.D57, "perm": Perm.RANK2},
	{"count": 6, "width": 0.65, "dir": Dir.D57, "perm": Perm.RANK2},
	{"count": 8, "width": 0.75, "dir": Dir.D57, "perm": Perm.RANK2},
	{"count": 6, "width": 0.55, "dir": Dir.D57, "perm": Perm.RANK2, "child_rule": ChildRule.ONE_ARMED, "child_count": 2},
	{"count": 6, "width": 0.60, "dir": Dir.D57, "perm": Perm.RANK2, "child_rule": ChildRule.ONE_ARMED, "child_count": 2},
	{"count": 6, "width": 0.60, "dir": Dir.D57, "perm": Perm.RANK2, "child_rule": ChildRule.BOTTOM_LANE, "child_count": 2},
	{"count": 8, "width": 0.80, "dir": Dir.D57, "perm": Perm.RANK1, "child_rule": ChildRule.BOTTOM_LANE, "child_count": 4, "columns": true},
	{"count": 8, "width": 0.80, "dir": Dir.D57, "perm": Perm.LANE_BOTTOM, "child_rule": ChildRule.BOTTOM_LANE, "child_count": 4},
	{"count": 8, "width": 0.80, "dir": Dir.D57, "perm": Perm.LANE_BOTTOM, "child_rule": ChildRule.BOTTOM_LANE, "child_count": 4},
	{"count": 0, "width": 0.0, "dir": Dir.DOWN, "perm": Perm.NONE},
	{"count": 8, "width": 0.80, "dir": Dir.D57, "perm": Perm.LANE_BOTTOM},
	{"count": 10, "width": 0.90, "dir": Dir.D57, "perm": Perm.LANE_BOTTOM},
	{"count": 10, "width": 0.90, "dir": Dir.D57, "perm": Perm.LANE_BOTTOM},
	{"count": 12, "width": 1.00, "dir": Dir.D48, "perm": Perm.LANE_BOTTOM},
	{"count": 12, "width": 1.00, "dir": Dir.D48, "perm": Perm.LANES_MID_BOTTOM},
	{"count": 12, "width": 1.00, "dir": Dir.D48, "perm": Perm.LANES_MID_BOTTOM},
	{"count": 12, "width": 1.00, "dir": Dir.D48, "perm": Perm.ALL},
]


# --- Helpers -------------------------------------------------------------------------------------
static func level(n: int) -> Dictionary:
	return LEVELS[clampi(n, FIRST_LEVEL, LAST_LEVEL)]


static func fire(n: int) -> Dictionary:
	var f: Dictionary = FIRE[clampi(n, FIRST_LEVEL, LAST_LEVEL)]
	var out := {"count": 0, "width": 0.0, "dir": Dir.DOWN, "perm": Perm.NONE,
		"child_rule": ChildRule.NONE, "child_count": 0, "columns": false}
	out.merge(f, true)
	return out


static func hit_rule(n: int) -> Hit:
	if n >= 7 and n <= 12:
		return Hit.SPLIT
	if n >= 14 and n <= 16:
		return Hit.COLOR_LOCK
	if n >= 19:
		return Hit.ROLLING
	return Hit.SINGLE


## Linear size of a child relative to the original (SPEC §8).
static func child_scale(n: int) -> float:
	return 0.40 if n == 7 else 0.45


static func planet_of(n: int) -> String:
	if n <= 3:
		return "neptune"
	if n <= 6:
		return "uranus"
	if n <= 9:
		return "saturn"
	if n <= 12:
		return "jupiter"
	if n <= 16:
		return "mars"
	return "earth"


## Zoom stage 1..3 of the background planet (SPEC §15).
static func zoom_stage(n: int) -> int:
	const STAGES := [0, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 1, 2, 3, 1, 1, 2, 3]
	return STAGES[clampi(n, FIRST_LEVEL, LAST_LEVEL)]


static func planet_diameter(n: int) -> float:
	return PLANET_DIAMETERS[zoom_stage(n) - 1]


static func width_factor(n: int) -> float:
	return PLANET_WIDTH_FACTOR[planet_of(n)]


## Enemy speed in px per GAME second (difficulty is applied through game time).
static func enemy_speed(n: int) -> float:
	return ENEMY_BASE_SPEED * float(level(n)["tempo"])


## Lane index for every ORIGINAL slot of the level, e.g. [0, 1, 2, 2].
static func slot_lanes(n: int) -> Array[int]:
	var lanes: Array = level(n)["lanes"]
	var out: Array[int] = []
	for lane in 3:
		for i in int(lanes[lane]):
			out.append(lane)
	return out


static func gradient_colors(n: int, stage: int = Stage.VIOLET) -> Array[Color]:
	if hit_rule(n) == Hit.COLOR_LOCK:
		match stage:
			Stage.YELLOW:
				return C_YELLOW_STOPS
			Stage.GREEN:
				return C_GREEN_STOPS
	var out: Array[Color] = []
	for c in level(n)["colors"]:
		out.append(c)
	return out


static func is_black(n: int) -> bool:
	return bool(level(n).get("black", false))


static func eye_color(n: int) -> Color:
	return EYE_COLOR_BLACK if is_black(n) else EYE_COLOR_DEFAULT


## Velocity of enemy bullets in px per GAME second (SPEC §7).
static func bullet_velocity(dir: Dir, player_x: float, figure_x: float) -> Vector2:
	var sx := 1.0 if player_x >= figure_x else -1.0
	match dir:
		Dir.D57:
			return Vector2(sx * ENEMY_BULLET_DIAG_A, ENEMY_BULLET_DIAG_B)
		Dir.D48:
			return Vector2(sx * ENEMY_BULLET_DIAG_B, ENEMY_BULLET_DIAG_A)
	return Vector2(0.0, ENEMY_BULLET_SPEED)


## Horizontal offsets of n bullets in one row; width_pct is the FULL salvo width incl. bullet width
## relative to the 90 px base width, scaled by the figure scale (SPEC §7).
static func salvo_offsets(n_bullets: int, width_pct: float, scale: float) -> Array[float]:
	var out: Array[float] = []
	if n_bullets <= 0:
		return out
	if n_bullets == 1:
		out.append(0.0)
		return out
	var w := width_pct * ENEMY_BASE_WIDTH * scale
	var span := maxf(w - ENEMY_BULLET_W, 0.0)
	for i in n_bullets:
		out.append(-span * 0.5 + span * float(i) / float(n_bullets - 1))
	return out


## Bonus-level result (SPEC §10).
static func bonus_value(remaining_attempts: int, ship_id: int) -> int:
	return remaining_attempts * int(ShipData.ship(ship_id)["bonus_factor"])


static func bonus_gives_extra_life(bonus: int) -> bool:
	return bonus > BONUS_EXTRA_LIFE_THRESHOLD


static func flawless_extra_life(n: int) -> bool:
	return FLAWLESS_EXTRA_LIFE_LEVELS.has(n)


## Text for the interlevel screen (SPEC §11).
static func progress_text(n: int) -> String:
	if ARRIVAL_AFTER.has(n):
		return "%s secured!" % PLANET_NAMES[planet_of(n)]
	if n >= LAST_LEVEL:
		return "Earth is safe!"
	if n >= 17:
		var k := LAST_LEVEL - n
		return "%d more battle%s to defend Earth" % [k, "" if k == 1 else "s"]
	var last := 3
	for a in [3, 6, 9, 12, 16]:
		if n < a:
			last = a
			break
	var nxt: String = ARRIVAL_AFTER[last]["target"]
	var left := last - n
	return "%d more battle%s until %s" % [left, "" if left == 1 else "s", PLANET_NAMES[nxt]]
