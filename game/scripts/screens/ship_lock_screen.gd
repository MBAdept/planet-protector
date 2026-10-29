extends ScreenBase
## PLACEHOLDER (replaced by the real screen, docs/SPEC.md §19.2): ship locks before a two-player match.
## setup {"player": k (who locks), "locked": Array[int]} → finished("done", {"locked": Array[int]}) / finished("back").

var player := 0
var locked: Array[int] = []


func _enter() -> void:
	AudioManager.play_title_music()
	player = int(args.get("player", 0))
	for id in args.get("locked", []):
		locked.append(int(id))


func _tick(_delta: float) -> void:
	if InputRouter.confirm_pressed(true):
		sfx("menu_confirm")
		finish("done", {"locked": locked.duplicate()})
	elif InputRouter.back_pressed():
		sfx("menu_back")
		finish("back")


func _draw() -> void:
	draw_title("PLAYER %d LOCKS" % (player + 1), 120, 36)
