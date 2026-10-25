extends Node
## Autoload "Display": display mode, logical canvas size and render resolution (docs/SPEC.md §1, §18).
## Binding API for gameplay and screens. Mode 0 is the classic 4:3 game exactly as specified by the client;
## modes 1 and 2 are 16:9 fullscreen with a WIDER playfield (logical 1280×720) rendered at 1920×1080 / 2560×1440.
## STUB by the lead – the display engineer implements apply() (window mode, render resolution) and the rest.

signal changed

enum Mode { WINDOW_4_3, FULLSCREEN_1080, FULLSCREEN_1440 }

const LOGICAL_4_3 := Vector2i(960, 720)
const LOGICAL_16_9 := Vector2i(1280, 720)
const RENDER_SIZE := {
	Mode.WINDOW_4_3: Vector2i(1280, 960),        # default window size, resizable
	Mode.FULLSCREEN_1080: Vector2i(1920, 1080),
	Mode.FULLSCREEN_1440: Vector2i(2560, 1440),
}
const MODE_NAMES := {
	Mode.WINDOW_4_3: "WINDOW 4:3 (CLASSIC)",
	Mode.FULLSCREEN_1080: "FULLSCREEN 1920×1080 (16:9)",
	Mode.FULLSCREEN_1440: "FULLSCREEN 2560×1440 (16:9)",
}


## Current display mode (persisted in Settings by the display engineer).
func mode() -> int:
	return clampi(int(Settings.get("display_mode") if Settings.get("display_mode") != null else 0), 0, 2)


func is_wide() -> bool:
	return mode() != Mode.WINDOW_4_3


## Logical canvas size all game/screen coordinates live in: 960×720 (4:3) or 1280×720 (16:9).
func logical_size() -> Vector2i:
	return LOGICAL_16_9 if is_wide() else LOGICAL_4_3


func logical_width() -> float:
	return float(logical_size().x)


## Horizontal offset that centres a 960-wide layout on the current canvas (0 in 4:3, 160 in 16:9).
func center_offset() -> float:
	return (logical_width() - float(LOGICAL_4_3.x)) * 0.5


## Applies window mode, canvas size and render resolution for the current mode. Stub: canvas size only.
func apply() -> void:
	var root := get_tree().root
	root.content_scale_size = logical_size()
	changed.emit()
