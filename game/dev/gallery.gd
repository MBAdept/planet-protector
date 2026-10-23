extends Node2D
## DEV ONLY: renders a contact sheet of all gameplay art (enemies, shots, fireballs, explosions, impulses,
## ships) into one frame and saves it:  ... res://dev/gallery.tscn -- --out=/abs/file.png [--page=fx|enemies]
const Backdrop := preload("res://scripts/game/backdrop.gd")
const FxLayer := preload("res://scripts/game/fx_layer.gd")
const PlayerView := preload("res://scripts/game/player_view.gd")

var _out := "/tmp/gallery.png"
var _page := "fx"
var _frames := 0
var _labels: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		if a.begins_with("--page="):
			_page = a.substr(7)
	var sky := Backdrop.new()
	sky.setup(Backdrop.Mode.SKY, 1)
	add_child(sky)
	if _page == "enemies":
		_build_enemies()
	elif _page == "clip":
		_build_clip()
	else:
		_build_fx()
	var lab := Node2D.new()
	lab.draw.connect(func() -> void:
		for l in _labels:
			lab.draw_string(Assets.font_body, l[0], l[1], HORIZONTAL_ALIGNMENT_CENTER if l.size() > 2 else HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.75, 0.85)))
	add_child(lab)


func _label(p: Vector2, s: String) -> void:
	_labels.append([p, s])


func _build_clip() -> void:
	const ProjectilesView := preload("res://scripts/game/projectiles_view.gd")
	var ground := Backdrop.new()
	ground.setup(Backdrop.Mode.GROUND, 1)
	add_child(ground)
	var w := GameWorld.new(1, 1, 0, 3, 1)
	var ys := [640.0, 660.0, 672.0, 678.0, 682.0, 684.0, 686.0, 688.0, 689.9]
	for i in ys.size():
		var b := w.add_bullet(60.0 + i * 100.0, ys[i], 0.0, 220.0)
		b.age = 0.2 + 0.1 * i
		_label(Vector2(40.0 + i * 100.0, 560.0), "y=%.1f" % ys[i])
	var clip := Control.new()
	clip.clip_contents = true
	clip.size = Vector2(960, LevelData.GROUND_Y)
	add_child(clip)
	var bv := ProjectilesView.new()
	bv.mode = ProjectilesView.Mode.BULLETS
	bv.world = w
	clip.add_child(bv)
	bv.splash(910.0)


func _build_enemies() -> void:
	var specs := [[1, 0, 0.0, 1.0], [2, 0, 0.0, 1.0], [3, 0, 0.0, 1.0], [4, 0, 0.0, 1.0], [5, 0, 0.0, 1.0], [6, 0, 0.0, 1.0],
		[7, 0, 0.0, 1.0], [8, 0, 0.0, 1.0], [9, 0, 0.0, 1.0], [10, 0, 0.0, 1.0], [11, 0, 0.0, 1.0], [12, 0, 0.0, 1.0],
		[13, 0, 0.0, 1.0], [14, 0, 0.0, 1.0], [14, 1, 0.0, 1.0], [14, 2, 0.0, 1.0], [17, 0, 0.0, 1.0], [18, 0, 0.0, 1.0],
		[19, 0, 0.0, 1.0], [20, 0, 1.0, 1.0], [1, 0, 0.0, 0.25], [1, 0, 0.0, 0.55], [19, 0, 0.0, 0.8], [8, 0, 0.0, 1.0]]
	for i in specs.size():
		var s: Array = specs[i]
		var e := EnemyArt.new()
		e.configure(int(s[0]), int(s[1]))
		e.flash = float(s[2])
		e.materialize = float(s[3])
		e.flap_phase = fposmod(float(i) * 0.13, 1.0)
		if i == specs.size() - 1:
			e.scale_factor = 0.45
		if i == specs.size() - 2:
			e.modulate = Color(1, 1, 1, 0.35)
		e.position = Vector2(80 + (i % 6) * 160, 90 + (i / 6) * 170)
		add_child(e)
		var tag := "L%d" % s[0]
		if int(s[1]) > 0:
			tag += " st%d" % s[1]
		if float(s[2]) > 0.0:
			tag += " flash"
		if float(s[3]) < 1.0:
			tag += " mat %.2f" % s[3]
		if i == specs.size() - 2:
			tag += " modulate 0.35"
		_label(e.position + Vector2(-60, 62), tag)


func _build_fx() -> void:
	var w := GameWorld.new(1, 1, 0, 3, 1)
	var fx := FxLayer.new()
	fx.world = w
	fx.level = 8
	add_child(fx)
	# explosions at several ages
	var ages := [0.03, 0.1, 0.2, 0.35, 0.55, 0.75]
	for i in ages.size():
		var ex := GameWorld.Explosion.new()
		ex.id = 100 + i
		ex.x = 80 + i * 160
		ex.y = 90
		ex.age = ages[i]
		w.explosions.append(ex)
		_label(Vector2(ex.x - 30, 170), "enemy %.2f" % ages[i])
	var pages := [0.05, 0.25, 0.6, 1.0]
	for i in pages.size():
		var ex := GameWorld.Explosion.new()
		ex.id = 200 + i
		ex.kind = "player"
		ex.duration = LevelData.PLAYER_EXPLOSION_TIME
		ex.x = 120 + i * 240
		ex.y = 270
		ex.age = pages[i]
		w.explosions.append(ex)
		_label(Vector2(ex.x - 30, 370), "player %.2f" % pages[i])
	# impulses
	var kinds := ["split", "stage", "locked", "rolling", "materialize", "respawn"]
	for i in kinds.size():
		fx.impulse(kinds[i], Vector2(80 + i * 160, 450), 1.0, Color(1.0, 0.9, 0.3) if kinds[i] == "stage" else Color(0.4, 0.7, 1.0))
		fx._impulses[i]["age"] = fx._impulses[i]["dur"] * 0.3
		_label(Vector2(50 + i * 160, 510), kinds[i])
	# shots + bullets + ships
	var art := Node2D.new()
	art.draw.connect(func() -> void:
		for sid in 6:
			ProjectileArt.draw_player_shot(art, sid, Vector2(60 + sid * 60, 580), 0.1 + sid * 0.07)
		var vels := [Vector2(0, 220), Vector2(110, 190.5), Vector2(-110, 190.5), Vector2(190.5, 110), Vector2(-190.5, 110)]
		for i in vels.size():
			ProjectileArt.draw_enemy_bullet(art, Vector2(440 + i * 50, 580), vels[i], 0.2 + i * 0.1)
		for i in 3:
			ProjectileArt.draw_enemy_bullet(art, Vector2(720 + i * 18, 575 + (i % 2) * 18), Vector2(0, 220), 0.3 + i * 0.2))
	add_child(art)
	for sid in 6:
		var pv := PlayerView.new()
		pv.ship_id = sid
		pv.position = Vector2(80 + sid * 160, 670)
		add_child(pv)
		pv.refresh()


func _process(_d: float) -> void:
	_frames += 1
	if _frames == 3:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		get_tree().quit()
