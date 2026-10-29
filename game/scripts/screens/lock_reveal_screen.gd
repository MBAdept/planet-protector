extends ScreenBase
## PLACEHOLDER (replaced by the real screen, docs/SPEC.md §19.2): both players' ship locks revealed.
## setup {"locked": [ids on PLAYER 1, ids on PLAYER 2]} → finished("continue").

const CONFIRM_DELAY := 0.8


func _enter() -> void:
	AudioManager.play_title_music()


func _tick(_delta: float) -> void:
	if time >= CONFIRM_DELAY and InputRouter.confirm_pressed(true):
		sfx("menu_confirm")
		finish("continue")


func _draw() -> void:
	draw_title("SHIP LOCKS REVEALED", 120, 36)
