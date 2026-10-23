class_name TestBase
extends RefCounted
## Minimal assertion helpers for headless tests. Test files: tests/test_*.gd, extend TestBase,
## methods named test_* are run on a fresh instance each.

var failures: Array[String] = []


func check(cond: bool, msg: String = "") -> void:
	if not cond:
		failures.append(msg if msg != "" else "check failed")


func check_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s expected <%s> got <%s>" % [msg, str(expected), str(actual)])


func check_near(actual: float, expected: float, eps: float = 1e-4, msg: String = "") -> void:
	if absf(actual - expected) > eps:
		failures.append("%s expected ~%f got %f" % [msg, expected, actual])
