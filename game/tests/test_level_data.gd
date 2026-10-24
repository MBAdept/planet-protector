extends TestBase


func test_salvo_offsets_full_width() -> void:
	var o := LevelData.salvo_offsets(4, 0.70, 1.0)
	check_eq(o.size(), 4)
	check_near(o[0], -(63.0 - 10.0) / 2.0)
	check_near(o[3], (63.0 - 10.0) / 2.0)
	check_eq(LevelData.salvo_offsets(1, 0.0, 1.0), [0.0] as Array[float])


func test_bullet_velocities() -> void:
	check_eq(LevelData.bullet_velocity(LevelData.Dir.DOWN, 0, 100), Vector2(0, 220))
	check_near(LevelData.bullet_velocity(LevelData.Dir.D57, 500, 100).x, 110.0)
	check_near(LevelData.bullet_velocity(LevelData.Dir.D57, 50, 100).x, -110.0)
	check_near(LevelData.bullet_velocity(LevelData.Dir.D48, 50, 100).length(), 220.0, 1e-3)


func test_slots_and_stages() -> void:
	check_eq(LevelData.slot_lanes(5), [0, 0, 1, 2, 2] as Array[int])
	check_eq(LevelData.slot_lanes(13), [0, 1] as Array[int])
	check_eq(LevelData.zoom_stage(18), 1)
	check_eq(LevelData.zoom_stage(20), 3)
	check_eq(LevelData.planet_of(13), "mars")


func test_bonus_rules() -> void:
	check_eq(LevelData.bonus_value(15, 0), 6000)
	check(not LevelData.bonus_gives_extra_life(6000), "exactly 6000 gives no life")
	check(LevelData.bonus_gives_extra_life(6001))


func test_progress_text() -> void:
	check_eq(LevelData.progress_text(1), "2 more battles until Uranus")
	check_eq(LevelData.progress_text(2), "1 more battle until Uranus")
	check_eq(LevelData.progress_text(14), "2 more battles until Earth")
	check_eq(LevelData.progress_text(19), "1 more battle to defend Earth")
	check_eq(LevelData.progress_text(12), "Jupiter secured!")


func test_fmt_time() -> void:
	check_eq(Fmt.time(0.0), "00:00.0")
	check_eq(Fmt.time(61.99), "01:01.9")
	check_eq(Fmt.time(600.05), "10:00.0")


func test_highscore_sort() -> void:
	var l := [{"score": 10, "time": 5.0}, {"score": 20, "time": 9.0}, {"score": 20, "time": 3.0}]
	Settings.sort_entries(l)
	check_eq(l[0]["time"], 3.0)
	check_eq(l[2]["score"], 10)
	check_eq(Settings.sanitize_name(""), "PILOT")
	check_eq(Settings.sanitize_name("ab#c-d_e"), "ABC-D_E")
	check_eq(Settings.sanitize_name("ab#c-d_e-f9"), "ABC-D_E-", "cut to 8 characters")
