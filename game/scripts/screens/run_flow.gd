class_name RunFlow
extends RefCounted
## Pure run-flow decisions (docs/SPEC.md §11) and command-line parsing (§17.3). No nodes, no state –
## `Main` asks "where do we go after <screen> finished with <result>?" and gets a step back:
##   {"screen": <name>, "level": <int>}
## Screen names: display_select, title, ship_select, level, interlevel, arrival, bonus_result, mars_rules,
## victory, game_over, name_entry, highscores, attract, quit.
##
##   (first start) DISPLAY SELECT ──confirm──▶ TITLE   (Escape quits, like on the title)
##   TITLE ──DISPLAY applied──▶ TITLE (re-created on the new canvas)
##   TITLE ──Start──▶ SHIP SELECT ──confirm──▶ LEVEL 1
##   LEVEL n completed:
##      n ≠ 13 → INTERLEVEL(n) → n ∈ {3,6,9,12,16}: ARRIVAL(n) → LEVEL n+1
##                             → n = 20: VICTORY → NAME ENTRY (if qualifies) → HIGHSCORES → TITLE
##                             → else LEVEL n+1
##      n = 13 → BONUS RESULT → MARS RULES → LEVEL 14
##   LEVEL game over → GAME OVER → NAME ENTRY (if qualifies) → HIGHSCORES → TITLE
##   PAUSE quit → TITLE
##   TITLE idle 90 s ──▶ ATTRACT (demo) ──end / any input──▶ TITLE
##
## Two-player hotseat match (SPEC §19.2, client request, forum round): setup_next() for the setup screens,
## match_next() for the match itself – the one-player flow above (next()) is untouched. Match steps also carry
## "player": the player the screen is for (−1 = a shared screen). Extra screen names: ship_lock, handover,
## lock_reveal, turn (the hand-over screen of kind "turn" before a level), match_result.
##   TITLE ─start─▶ SHIP LOCK(P1) ─done─▶ HANDOVER(P2) ─continue─▶ SHIP LOCK(P2) ─done─▶ LOCK REVEAL ─continue─▶
##      SHIP SELECT(P1) ─confirm─▶ SHIP SELECT(P2) ─confirm─▶ TURN(P1, 1) ─▶ LEVEL 1 (P1)      back → TITLE
##   Round n: every player who is not out plays level n, PLAYER 1 first:
##      TURN(k, n) (only when the player changes) ─▶ LEVEL n (k) ─completed─▶ INTERLEVEL / BONUS RESULT (k)
##                                                               ─game over─▶ GAME OVER (k)
##      ─▶ the next player of the round (TURN(j, n) ─▶ LEVEL n (j)) or, the round is over:
##         nobody left ─▶ MATCH RESULT · n = 20 ─▶ VICTORY ─▶ MATCH RESULT · n = 13 ─▶ MARS RULES ─▶ round 14
##         n ∈ {3,6,9,12,16} ─▶ ARRIVAL(n) ─▶ round n+1 · else round n+1
##   MATCH RESULT ─▶ NAME ENTRY (each qualifying player, best score first) ─▶ HIGHSCORES ─▶ TITLE

const SCREENS: Array[String] = ["title", "ship_select", "interlevel", "arrival", "mars_rules", "bonus_result",
	"victory", "game_over", "name_entry", "highscores", "display_select", "ship_lock", "handover", "lock_reveal",
	"match_result", "turn"]


static func step(screen: String, level: int = 0) -> Dictionary:
	return {"screen": screen, "level": level}


## A step of a two-player match: step() plus the player the screen is for (−1 = shared screen).
static func match_step(screen: String, level: int, player: int) -> Dictionary:
	return {"screen": screen, "level": level, "player": player}


## Next step after `from` emitted `finished(result)`. `level` = the level the run is at (for "level":
## the level that just ended), `qualifies` = the run's score enters the highscore list.
static func next(from: String, result: String, level: int, qualifies: bool = false) -> Dictionary:
	match from:
		"display_select":
			return step("quit" if result == "quit" else "title")
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
			return step("title")   # also "display": a new display mode was applied → title on the new canvas
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


# --- Two-player hotseat match (SPEC §19.2) ---------------------------------------------------------
## Next step of the match setup after `from` (shown for `player`) finished with `result`. Escape / B on a lock or
## ship select screen ("back") aborts the setup. The ship select of PLAYER 2 starts the match (Main calls
## Run.start_match) with the TURN screen of PLAYER 1 in level 1.
static func setup_next(from: String, result: String, player: int) -> Dictionary:
	if result == "back":
		return match_step("title", 0, -1)
	match from:
		"title":
			return match_step("ship_lock", 0, 0)
		"ship_lock":
			if player == 0:
				return match_step("handover", 0, 1)   # PLAYER 1 locked: hand the controller to PLAYER 2
			return match_step("lock_reveal", 0, -1)
		"handover":
			return match_step("ship_lock", 0, 1)
		"lock_reveal":
			return match_step("ship_select", 0, 0)
		"ship_select":
			if player == 0:
				return match_step("ship_select", 0, 1)
			return match_step("turn", LevelData.FIRST_LEVEL, 0)
	return match_step("title", 0, -1)


## The player who plays level n after player `after` in round n (−1: the round starts): the next one in seat order
## (PLAYER 1 first) who is not out, or −1 when everyone still in the match has played it – the round is over.
## out[k]: player k has lost the last life.
static func next_in_round(after: int, out: Array) -> int:
	for k in range(maxi(after + 1, 0), out.size()):
		if not bool(out[k]):
			return k
	return -1


## True while at least one player is still in the match.
static func anyone_left(out: Array) -> bool:
	return next_in_round(-1, out) >= 0


## The TURN screen comes before a level when its player differs from the player of the previous level
## (`last_player`, −1 at the start of the match): before every level while both play, only after a switch once
## one of them is out (consecutive levels of the same player follow each other like in a one-player run).
static func needs_turn_screen(player: int, last_player: int) -> bool:
	return player != last_player


## Level n of `player`, behind its TURN screen when the player changes (see needs_turn_screen).
static func turn_or_level(player: int, n: int, last_player: int) -> Dictionary:
	return match_step("turn" if needs_turn_screen(player, last_player) else "level", n, player)


## What follows round n once it is over (everyone still in the match has played level n). `last_player` = the
## player of level n's last turn.
static func after_round(n: int, out: Array, last_player: int) -> Dictionary:
	if not anyone_left(out):
		return match_step("match_result", n, -1)
	if n >= LevelData.LAST_LEVEL:
		return match_step("victory", n, -1)
	if n == LevelData.BONUS_LEVEL:
		return match_step("mars_rules", n, -1)
	if LevelData.ARRIVAL_AFTER.has(n):
		return match_step("arrival", n, -1)
	return turn_or_level(next_in_round(-1, out), n + 1, last_player)


## Next step of a match after `from` finished with `result`. level = the round's level n; player = the player of
## `from` (turn, level, interlevel, bonus result, game over) – for the shared screens (arrival, mars rules) the
## player of the last level played; out = [PLAYER 1 out, PLAYER 2 out], already updated for this level's game over;
## entry = the next player whose score enters the highscore list now (match result / name entry; −1 = nobody,
## Main checks Settings.qualifies at that moment).
static func match_next(from: String, result: String, level: int, player: int, out: Array,
		entry: int = -1) -> Dictionary:
	match from:
		"turn":
			return match_step("level", level, player)
		"level":
			match result:
				"completed":
					return match_step("bonus_result" if level == LevelData.BONUS_LEVEL else "interlevel", level, player)
				"game_over":
					return match_step("game_over", level, player)
			return match_step("title", 0, -1)   # "quit" from the pause menu: the match is aborted (no entries)
		"interlevel", "bonus_result", "game_over":
			var k := next_in_round(player, out)
			if k >= 0:
				return turn_or_level(k, level, player)
			return after_round(level, out, player)
		"arrival", "mars_rules":
			if not anyone_left(out):
				return match_step("match_result", level, -1)
			return turn_or_level(next_in_round(-1, out), level + 1, player)
		"victory":
			return match_step("match_result", level, -1)
		"match_result", "name_entry":
			if entry >= 0:
				return match_step("name_entry", level, entry)
			return match_step("highscores", level, -1)
	return match_step("title", 0, -1)


## Order of the name entries at the end of a match: by score (descending), equal scores by play time (shorter
## first), then PLAYER 1 before PLAYER 2. scores[k] / times[k]: player k's.
static func entry_order(scores: Array, times: Array) -> Array[int]:
	var order: Array[int] = []
	for k in scores.size():
		order.append(k)
	order.sort_custom(func(a: int, b: int) -> bool:
		if int(scores[a]) != int(scores[b]):
			return int(scores[a]) > int(scores[b])
		if float(times[a]) != float(times[b]):
			return float(times[a]) < float(times[b])
		return a < b)
	return order


## Rows (0-based, ascending) of a highscore `list` that hold `entries` (the entries made in this match, all fields
## equal; each row counts once) – recomputed after the last insert, so a later better entry that pushed an earlier
## one down (or out of the top 10) is reflected.
static func entry_ranks(list: Array, entries: Array) -> Array[int]:
	var ranks: Array[int] = []
	for e: Dictionary in entries:
		for i in list.size():
			if not ranks.has(i) and _same_entry(list[i], e):
				ranks.append(i)
				break
	ranks.sort()
	return ranks


## Two highscore entries are the same: every stored field ({name, score, time, level, ship}) is equal.
static func _same_entry(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("name", "")) == String(b.get("name", "")) \
		and int(a.get("score", 0)) == int(b.get("score", 0)) \
		and float(a.get("time", 0.0)) == float(b.get("time", 0.0)) \
		and int(a.get("level", 0)) == int(b.get("level", 0)) \
		and int(a.get("ship", 0)) == int(b.get("ship", 0))


## First screen of a normal start (no --screen / --level): the first-start display choice while the player has
## not confirmed one (or --first-start forces it), else the title. A mode forced with --display skips it.
static func first_screen(display_chosen: bool, display_forced: bool, force_first_start: bool) -> String:
	if force_first_start or (not display_chosen and not display_forced):
		return "display_select"
	return "title"


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
