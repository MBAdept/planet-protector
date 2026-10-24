class_name RunFlow
extends RefCounted
## Pure run-flow decisions (docs/SPEC.md §11) and command-line parsing (§17.3). No nodes, no state –
## `Main` asks "where do we go after <screen> finished with <result>?" and gets a step back:
##   {"screen": <name>, "level": <int>}
## Screen names: title, ship_select, level, interlevel, arrival, bonus_result, mars_rules, victory,
## game_over, name_entry, highscores, attract, quit.
##
##   TITLE ──Start──▶ SHIP SELECT ──confirm──▶ LEVEL 1
##   LEVEL n completed:
##      n ≠ 13 → INTERLEVEL(n) → n ∈ {3,6,9,12,16}: ARRIVAL(n) → LEVEL n+1
##                             → n = 20: VICTORY → NAME ENTRY (if qualifies) → HIGHSCORES → TITLE
##                             → else LEVEL n+1
##      n = 13 → BONUS RESULT → MARS RULES → LEVEL 14
##   LEVEL game over → GAME OVER → NAME ENTRY (if qualifies) → HIGHSCORES → TITLE
##   PAUSE quit → TITLE
##   TITLE idle 90 s ──▶ ATTRACT (demo) ──end / any input──▶ TITLE

const SCREENS: Array[String] = ["title", "ship_select", "interlevel", "arrival", "mars_rules", "bonus_result",
	"victory", "game_over", "name_entry", "highscores"]


static func step(screen: String, level: int = 0) -> Dictionary:
	return {"screen": screen, "level": level}


## Next step after `from` emitted `finished(result)`. `level` = the level the run is at (for "level":
## the level that just ended), `qualifies` = the run's score enters the highscore list.
static func next(from: String, result: String, level: int, qualifies: bool = false) -> Dictionary:
	match from:
		"title":
			match result:
				"start":
					return step("ship_select")
				"highscores":
					return step("highscores")
				"quit":
					return step("quit")
				"attract":
					return step("attract")
			return step("title")
		"attract":
			return step("title")   # the demo is over or the player pressed something
		"ship_select":
			if result == "confirm":
				return step("level", LevelData.FIRST_LEVEL)
			return step("title")
		"level":
			match result:
				"completed":
					if level == LevelData.BONUS_LEVEL:
						return step("bonus_result", level)
					return step("interlevel", level)
				"game_over":
					return step("game_over", level)
			return step("title")   # "quit" from the pause menu (no highscore entry)
		"interlevel":
			if LevelData.ARRIVAL_AFTER.has(level):
				return step("arrival", level)
			if level >= LevelData.LAST_LEVEL:
				return step("victory", level)
			return step("level", level + 1)
		"arrival":
			return step("level", level + 1)
		"bonus_result":
			return step("mars_rules", level)
		"mars_rules":
			return step("level", LevelData.MARS_RULES_BEFORE_LEVEL)
		"victory", "game_over":
			return step("name_entry" if qualifies else "highscores", level)
		"name_entry":
			return step("highscores", level)
		"highscores":
			return step("title")
	return step("title")


## A finished run enters the list only with a positive score that makes the top 10 (SPEC §13).
static func entry_qualifies(score: int, list_qualifies: bool) -> bool:
	return score > 0 and list_qualifies


## "--level=3 --dev foo" → {"level": "3", "dev": true, "foo": true}
static func parse_args(user_args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in user_args:
		var s := a.trim_prefix("--")
		if s == "":
			continue
		var eq := s.find("=")
		if eq >= 0:
			out[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			out[s] = true
	return out


## Integer argument with default and clamping.
static func arg_int(args: Dictionary, key: String, default_value: int, lo: int, hi: int) -> int:
	if not args.has(key) or not String(str(args[key])).is_valid_int():
		return default_value
	return clampi(int(str(args[key])), lo, hi)


static func arg_float(args: Dictionary, key: String, default_value: float) -> float:
	if not args.has(key) or not String(str(args[key])).is_valid_float():
		return default_value
	return float(str(args[key]))
