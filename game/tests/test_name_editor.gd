extends TestBase
## NameEditor rules (docs/SPEC.md §13): names of up to 8 characters (client decision, originally 5).


func _ed(text: String = "", cursor: int = -1) -> NameEditor:
	var e := NameEditor.new()
	e.text = text
	e.cursor = e.max_cursor() if cursor < 0 else cursor
	return e


func test_starts_empty_on_end_field() -> void:
	var e := NameEditor.new()
	check_eq(e.text, "")
	check_eq(e.cursor, 0)
	check(e.is_on_end_field())


func test_vertical_on_empty_end_field_inserts_a_without_advancing() -> void:
	var e := NameEditor.new()
	e.char_up()
	check_eq(e.text, "A", "up on empty field")
	check_eq(e.cursor, 0, "cursor must not advance")
	var d := NameEditor.new()
	d.char_down()
	check_eq(d.text, "A", "down on empty field also inserts A")
	check_eq(d.cursor, 0)
	# Same on a later empty end field.
	var f := _ed("XY", 2)
	f.char_down()
	check_eq(f.text, "XYA")
	check_eq(f.cursor, 2)


func test_vertical_cycles_character_set_with_wrap() -> void:
	var e := _ed("A", 0)
	e.char_up()
	check_eq(e.text, "B", "up = next")
	e.char_down()
	e.char_down()
	check_eq(e.text, "-", "down from A wraps to the last character")
	e.char_up()
	check_eq(e.text, "A", "up from - wraps to A")
	var z := _ed("Z", 0)
	z.char_up()
	check_eq(z.text, "0", "Z → 0")
	var n := _ed("9", 0)
	n.char_up()
	check_eq(n.text, "_", "9 → _")
	n.char_up()
	check_eq(n.text, "-", "_ → -")
	# Full cycle returns to the start.
	var c := _ed("K", 0)
	for i in Settings.NAME_CHARS.length():
		c.char_up()
	check_eq(c.text, "K", "full cycle")


func test_vertical_changes_only_the_char_under_the_cursor() -> void:
	var e := _ed("ABC", 1)
	e.char_up()
	check_eq(e.text, "ACC")
	check_eq(e.cursor, 1)


func test_horizontal_only_moves_cursor() -> void:
	var e := _ed("AB", 0)
	e.move_right()
	check_eq(e.cursor, 1)
	check_eq(e.text, "AB", "text unchanged")
	e.move_right()
	check_eq(e.cursor, 2, "may stand on the next free position")
	e.move_right()
	check_eq(e.cursor, 2, "never beyond the next free position")
	check_eq(e.text, "AB", "moving onto the end field does not insert")
	e.move_left()
	e.move_left()
	e.move_left()
	check_eq(e.cursor, 0, "clamped at 0")


func test_max_length_is_8() -> void:
	check_eq(Settings.NAME_MAX, 8, "client decision: 8 characters (originally 5)")
	check_eq(NameEditor.max_len(), 8)
	check_eq(_ed("ABCDEFG").max_cursor(), 7, "7 characters: cursor may reach the 8th box")
	check_eq(_ed("ABCDEFGH").max_cursor(), 7, "full name: the cursor stays on the 8th character")
	check_eq(_ed("ABCDE").max_cursor(), 5, "5 characters are no longer full: the 6th box is the end field")


func test_cursor_never_beyond_index_7() -> void:
	var e := _ed("ABCDEFGH", 7)
	e.move_right()
	check_eq(e.cursor, 7)
	e.char_up()
	check_eq(e.text, "ABCDEFGI", "vertical on index 7 changes the 8th char, no 9th char")
	check_eq(e.text.length(), 8)
	e.char_down()
	e.char_down()
	check_eq(e.text, "ABCDEFGG")
	check_eq(e.cursor, 7)
	# Walking right through a full name stops on the last character.
	var g := _ed("ABCDEFGH", 0)
	for i in 12:
		g.move_right()
		check(g.cursor <= 7, "cursor %d never beyond index 7" % g.cursor)
	check_eq(g.cursor, 7)
	check_eq(g.text, "ABCDEFGH", "moving never changes the name")


func test_insert_at_position_7() -> void:
	var f := _ed("ABCDEFG", 7)
	check(f.is_on_end_field(), "index 7 is the empty end field of a 7-character name")
	f.char_up()
	check_eq(f.text, "ABCDEFGA", "end field at index 7 inserts the 8th char")
	check_eq(f.cursor, 7, "the cursor does not advance")
	check(not f.is_on_end_field(), "now on the 8th character")
	f.move_right()
	check_eq(f.cursor, 7, "no end field after 8 characters")
	f.char_up()
	check_eq(f.text, "ABCDEFGB", "the next vertical input changes the 8th char, no 9th char")
	check_eq(f.text.length(), 8)
	var d := _ed("ABCDEFG", 7)
	d.char_down()
	check_eq(d.text, "ABCDEFGA", "down on the end field also inserts A")
	check_eq(d.cursor, 7)


func test_build_8_character_name_with_controller() -> void:
	var e := NameEditor.new()
	for i in 10:   # more rounds than boxes: the 9th and 10th must not add anything
		e.apply_direction(Vector2i(0, -1))   # up: insert A (or A → B on a filled box)
		e.apply_direction(Vector2i(1, 0))    # right: next box
		check(e.cursor <= 7, "cursor never beyond index 7")
	check_eq(e.text, "AAAAAAAC", "8 characters; the 9th and 10th round only change the 8th (A → B → C)")
	check_eq(e.cursor, 7)


func test_build_name_with_controller() -> void:
	var e := NameEditor.new()
	e.apply_direction(Vector2i(0, -1))   # up: insert A
	e.apply_direction(Vector2i(0, -1))   # up: B
	e.apply_direction(Vector2i(1, 0))    # right: end field
	e.apply_direction(Vector2i(0, 1))    # down: insert A
	e.apply_direction(Vector2i(0, 1))    # down: '-'
	check_eq(e.text, "B-")
	check_eq(e.cursor, 1)


func test_diagonal_uses_stronger_axis_tie_horizontal() -> void:
	check_eq(NameEditor.dominant_direction(Vector2(0.7, 0.7)), Vector2i(1, 0), "tie → horizontal")
	check_eq(NameEditor.dominant_direction(Vector2(-0.6, -0.6)), Vector2i(-1, 0), "tie → horizontal (left)")
	check_eq(NameEditor.dominant_direction(Vector2(0.4, -0.9)), Vector2i(0, -1), "vertical stronger")
	check_eq(NameEditor.dominant_direction(Vector2(-0.9, 0.3)), Vector2i(-1, 0), "horizontal stronger")
	check_eq(NameEditor.dominant_direction(Vector2.ZERO), Vector2i.ZERO)
	# D-pad diagonal (both pressed) counts as horizontal: only the cursor moves.
	var e := _ed("AB", 0)
	e.apply_direction(Vector2i(1, -1))
	check_eq(e.text, "AB", "diagonal must not change a character")
	check_eq(e.cursor, 1)


func test_delete_removes_last_char_and_clamps_cursor() -> void:
	var e := _ed("ABC", 0)
	e.delete_last()
	check_eq(e.text, "AB", "deletes the LAST character, not the one under the cursor")
	check_eq(e.cursor, 0)
	var f := _ed("ABC", 3)
	f.delete_last()
	check_eq(f.text, "AB")
	check_eq(f.cursor, 2, "cursor pulled back onto the new end field")
	var g := _ed("ABCDEFGH", 7)
	g.delete_last()
	check_eq(g.text, "ABCDEFG")
	check_eq(g.cursor, 7, "index 7 is now the empty end field")
	var k := _ed("ABCDEFGH", 2)
	k.delete_last()
	check_eq(k.text, "ABCDEFG", "B deletes the last character of a full name")
	check_eq(k.cursor, 2)
	var h := NameEditor.new()
	h.delete_last()
	check_eq(h.text, "", "delete on empty name is a no-op")
	check_eq(h.cursor, 0)


func test_keyboard_typing_appends() -> void:
	var e := _ed("AB", 0)
	check(e.type_char("x"), "lowercase accepted")
	check_eq(e.text, "ABX", "typing appends (uppercased) at the end")
	check_eq(e.cursor, 3, "cursor follows to the next free position")
	check(e.type_char("_"))
	check(e.type_char("7"))
	check_eq(e.text, "ABX_7")
	check_eq(e.cursor, 5, "5 characters are not full: the cursor is on the 6th box")
	check(e.type_char("-"))
	check(e.type_char("z"))
	check(e.type_char("0"))
	check_eq(e.text, "ABX_7-Z0")
	check_eq(e.cursor, 7, "cursor never beyond index 7")
	check(not e.type_char("Q"), "full name rejects more characters")
	check_eq(e.text, "ABX_7-Z0")


func test_typing_stops_at_8() -> void:
	var e := NameEditor.new()
	var accepted := 0
	for ch in "STARDUST99":
		if e.type_char(ch):
			accepted += 1
	check_eq(accepted, 8, "the 9th and 10th character are rejected")
	check_eq(e.text, "STARDUST")
	check_eq(e.cursor, 7)
	check_eq(e.final_name(), "STARDUST")
	e.delete_last()
	check(e.type_char("Y"), "after a delete the 8th character can be typed again")
	check_eq(e.text, "STARDUSY")


func test_keyboard_rejects_invalid_chars() -> void:
	var e := NameEditor.new()
	for ch in ["!", " ", "ä", ".", "AB", ""]:
		check(not e.type_char(ch), "rejects '%s'" % ch)
	check_eq(e.text, "")
	check(e.type_char("-"))
	check_eq(e.text, "-")


func test_final_name_empty_is_pilot() -> void:
	check_eq(NameEditor.new().final_name(), "PILOT")
	check_eq(_ed("AB_-9").final_name(), "AB_-9")
	check_eq(_ed("AB_-9XYZ").final_name(), "AB_-9XYZ")
	check_eq(_ed("Z").final_name(), "Z")


func test_initial_text_constructor() -> void:
	var e := NameEditor.new("ace!x")
	check_eq(e.text, "ACEX")
	check_eq(e.cursor, 4)
	var f := NameEditor.new("commander-1")
	check_eq(f.text, "COMMANDE", "an over-long initial name is cut to 8")
	check_eq(f.cursor, 7)
