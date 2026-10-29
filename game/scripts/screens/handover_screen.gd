extends ScreenBase
## PLACEHOLDER (replaced by the real screen, docs/SPEC.md §19.2): hand-over between the two players.
## setup {"kind": "locks", "player": k} | {"kind": "turn", "player": k, "level": n} → finished("continue").

const CONFIRM_DELAY := 0.6


func _enter() -> void:
	if String(args.get("kind", "turn")) == "locks":
		AudioManager.play_title_music()
	else:
		AudioManager.stop_music()


func _tick(_delta: float) -> void:
	if time >= CONFIRM_DELAY and InputRouter.confirm_pressed(true):
		sfx("menu_confirm")
		finish("continue")


func _draw() -> void:
	draw_title("PLAYER %d" % (int(args.get("player", 0)) + 1), 300, 48)
