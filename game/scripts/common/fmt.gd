class_name Fmt
extends RefCounted
## Small formatting helpers shared by HUD and menus.


## Seconds → "MM:SS.t" (tenths, truncated, never rounds up to the next second).
static func time(seconds: float) -> String:
	var tenths := int(floor(maxf(seconds, 0.0) * 10.0 + 1e-6))
	@warning_ignore("integer_division")
	var m := tenths / 600
	@warning_ignore("integer_division")
	var s := (tenths / 10) % 60
	var t := tenths % 10
	return "%02d:%02d.%d" % [m, s, t]


static func score(value: int) -> String:
	return str(value)
