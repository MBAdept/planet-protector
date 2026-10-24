class_name NameEditor
extends RefCounted
## Pure highscore-name editing logic (docs/SPEC.md §13). No nodes; the name-entry screen feeds it.
##
## - Max Settings.NAME_MAX = 8 characters (client decision, originally 5) from Settings.NAME_CHARS ("A–Z 0–9 _ -").
## - The cursor stands on an existing character or on the next free position ("empty end field"),
##   never beyond index 7 (NAME_MAX - 1): 0 <= cursor <= min(len, 7).
## - Horizontal input only moves the cursor.
## - Vertical input changes the character under the cursor (up = next in NAME_CHARS, down = previous,
##   wrapping). On the empty end field it first inserts "A" WITHOUT advancing the cursor.
## - Diagonal input: only the stronger axis counts, a tie counts as horizontal.
## - B / Backspace deletes the last character. Keyboard typing appends. Confirm: empty → "PILOT".

var text := ""
var cursor := 0


func _init(initial: String = "") -> void:
	for ch in initial.to_upper():
		type_char(ch)
	cursor = 0 if text.is_empty() else max_cursor()


static func chars() -> String:
	return Settings.NAME_CHARS


static func max_len() -> int:
	return Settings.NAME_MAX


func max_cursor() -> int:
	return mini(text.length(), max_len() - 1)


func is_on_end_field() -> bool:
	return cursor >= text.length()


## Only the stronger axis counts; a tie counts as horizontal (SPEC §13). Returns a unit step or ZERO.
static func dominant_direction(v: Vector2) -> Vector2i:
	if v.x == 0.0 and v.y == 0.0:
		return Vector2i.ZERO
	if absf(v.x) >= absf(v.y):
		return Vector2i(int(signf(v.x)), 0)
	return Vector2i(0, int(signf(v.y)))


## Applies one navigation step (screen coordinates: y < 0 = up). Diagonals are resolved first.
func apply_direction(dir: Vector2i) -> void:
	var d := dominant_direction(Vector2(dir))
	if d.x < 0:
		move_left()
	elif d.x > 0:
		move_right()
	elif d.y < 0:
		char_up()
	elif d.y > 0:
		char_down()


func move_left() -> void:
	cursor = maxi(cursor - 1, 0)


func move_right() -> void:
	cursor = mini(cursor + 1, max_cursor())


## Up = next character in the cycle.
func char_up() -> void:
	_cycle(1)


## Down = previous character in the cycle.
func char_down() -> void:
	_cycle(-1)


func _cycle(step: int) -> void:
	if cursor >= text.length():
		if text.length() < max_len():
			text += "A"   # empty end field: insert 'A', cursor stays on it
		return
	var cs := chars()
	var i := cs.find(text[cursor])
	var ni := posmod((i if i >= 0 else 0) + step, cs.length())
	text = text.substr(0, cursor) + cs[ni] + text.substr(cursor + 1)


## Deletes the last character (B / Backspace); the cursor is pulled back if it would stand beyond.
func delete_last() -> void:
	if text.is_empty():
		return
	text = text.substr(0, text.length() - 1)
	cursor = mini(cursor, max_cursor())


## Keyboard typing appends a character; the cursor follows to the next free position.
## Returns false if the character is not allowed or the name is full.
func type_char(ch: String) -> bool:
	if ch.length() != 1:
		return false
	var c := ch.to_upper()
	if not chars().contains(c) or text.length() >= max_len():
		return false
	text += c
	cursor = max_cursor()
	return true


## Name to store; empty → "PILOT". (`text` only ever holds valid characters, max 8 – see type_char/_cycle;
## Settings.insert_highscore sanitises again.)
func final_name() -> String:
	return text if not text.is_empty() else Settings.DEFAULT_NAME
