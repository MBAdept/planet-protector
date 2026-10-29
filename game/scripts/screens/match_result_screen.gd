extends ScreenBase
## PLACEHOLDER (replaced by the real screen, docs/SPEC.md §19.2): result of a two-player match (reads Run).
## setup {} → finished("continue").

const CONFIRM_DELAY := 1.0


func _enter() -> void:
	AudioManager.play_title_music()


func _tick(_delta: float) -> void:
	if time >= CONFIRM_DELAY and InputRouter.confirm_pressed():
		sfx("menu_confirm")
		finish("continue")


func _draw() -> void:
	draw_title("MATCH RESULT", 120, 36)
