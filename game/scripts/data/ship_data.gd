class_name ShipData
extends RefCounted
## Player ships and difficulty levels (docs/SPEC.md §2, §4).

const DOUBLE_OFFSET := 12.0

enum Look { LASER_BLUE, ROCKET, LASER_RED_THICK, ROCKET_HEAVY_PAIR }

const SHIPS := [
	{"id": 0, "key": "interceptor", "name": "INTERCEPTOR", "speed": 500.0, "count": 1, "guided": false,
		"piercing": false, "bonus_factor": 400, "look": Look.LASER_BLUE, "sfx": "shot_laser", "accent": Color(0.25, 0.55, 1.0)},
	{"id": 1, "key": "fighter", "name": "FIGHTER", "speed": 430.0, "count": 1, "guided": true,
		"piercing": false, "bonus_factor": 200, "look": Look.ROCKET, "sfx": "shot_rocket", "accent": Color(0.3, 0.9, 0.35)},
	{"id": 2, "key": "double_dart", "name": "DOUBLE DART", "speed": 430.0, "count": 2, "guided": false,
		"piercing": false, "bonus_factor": 300, "look": Look.LASER_BLUE, "sfx": "shot_laser", "accent": Color(0.2, 0.9, 1.0)},
	{"id": 3, "key": "double_hunter", "name": "DOUBLE HUNTER", "speed": 350.0, "count": 2, "guided": true,
		"piercing": false, "bonus_factor": 200, "look": Look.ROCKET, "sfx": "shot_rocket", "accent": Color(1.0, 0.6, 0.15)},
	{"id": 4, "key": "blaster", "name": "BLASTER", "speed": 350.0, "count": 1, "guided": false,
		"piercing": true, "bonus_factor": 300, "look": Look.LASER_RED_THICK, "sfx": "shot_blaster", "accent": Color(1.0, 0.25, 0.2)},
	{"id": 5, "key": "hunter", "name": "HUNTER", "speed": 270.0, "count": 1, "guided": true,
		"piercing": true, "bonus_factor": 200, "look": Look.ROCKET_HEAVY_PAIR, "sfx": "shot_rocket", "accent": Color(0.7, 0.35, 1.0)},
]

const DIFFICULTIES := [
	{"id": 0, "name": "BEGINNER", "lives": 5, "speed_factor": 1.00},
	{"id": 1, "name": "NORMAL", "lives": 3, "speed_factor": 1.00},
	{"id": 2, "name": "HARD", "lives": 3, "speed_factor": 1.20},
	{"id": 3, "name": "EXPERT", "lives": 1, "speed_factor": 1.44},
]


static func ship(id: int) -> Dictionary:
	return SHIPS[clampi(id, 0, SHIPS.size() - 1)]


static func difficulty(id: int) -> Dictionary:
	return DIFFICULTIES[clampi(id, 0, DIFFICULTIES.size() - 1)]


## Lateral offsets of the projectiles of one salvo (one entry per logical projectile).
static func shot_offsets(id: int) -> Array[float]:
	if int(ship(id)["count"]) == 2:
		return [-DOUBLE_OFFSET, DOUBLE_OFFSET]
	return [0.0]
