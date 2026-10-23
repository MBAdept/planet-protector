extends SceneTree
## Headless test runner:  godot --headless --path game -s res://tests/run_tests.gd [-- --filter=<substr>]
## Runs every method test_* of every tests/test_*.gd (fresh instance per method). Exit code 1 on failure.


func _initialize() -> void:
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_base.gd":
			files.append(f)
	files.sort()
	var total := 0
	var failed := 0
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null:
			print("LOAD ERROR ", f)
			failed += 1
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (f + ":" + name).contains(filter):
				continue
			total += 1
			var inst: Object = script.new()
			inst.call(name)
			var fails: Array = inst.get("failures")
			if fails.is_empty():
				print("  ok   %s:%s" % [f, name])
			else:
				failed += 1
				print("  FAIL %s:%s" % [f, name])
				for msg in fails:
					print("         - ", msg)
	print("%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)
