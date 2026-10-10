extends SceneTree
# 穿模修复的前后对比截图(规格 2026-10-08-cozy-toon-style-design §穿模修复):需要窗口渲染,不能 --headless。
# 只用改动前后都有的公开接口,所以同一个脚本放进改动前的代码树里也能跑(前后两张图机位、姿势一样)。
# 用法:godot --path . --fixed-fps 60 -s tools/clip_shots.gd -- --out=/tmp/clip [--only=lean,center,neighbour,clap,fp]
# - lean       鳄鱼 / 羊驼 / 猫轮到自己前倾、低头看桌面,手里拿着牌(特写,另有一张炸弹猫 14 张的鳄鱼)
# - center     对手们把头探到桌心(越肩、俯视)
# - neighbour  对手们把头往右手边的邻座探(越肩、俯视)
# - clap       结算:2 号跳舞、其他人鼓掌(特写一位鼓掌的)
# - fp         第一人称把头探到桌心、探向右前方

const SPECIES := [0, 7, 5, 3]   # 1 号(自己)狐狸,2 号鳄鱼,3 号羊驼,4 号猫
const SETTLE := 1.6

var opts := {}
var tavern: Tavern
var world: TableWorld
var out_dir := ""


func _initialize() -> void:
	seed(2026)
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	out_dir = opts.get("out", OS.get_user_data_dir() + "/clip_shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	process_frame.connect(_run, CONNECT_ONE_SHOT)
	process_frame.connect(func(): if not DisplayServer.window_can_draw(): RenderingServer.force_draw(false))


func _wanted(name: String) -> bool:
	return not opts.has("only") or name in opts["only"].split(",")


func _run() -> void:
	RenderBudget.apply(root)
	tavern = Tavern.new()
	root.add_child(tavern)
	await RoomTextures.build(root)
	await CardFaces.build(root)
	Card3D.refresh_materials()
	if _wanted("lean"):
		await _lean()
	if _wanted("center"):
		await _peek("center", Vector3(0, 0, -1.25))
	if _wanted("neighbour"):
		await _peek("neighbour", Vector3(1.5, 0, -0.35))
	if _wanted("clap"):
		await _clap()
	if _wanted("fp"):
		await _fp()
	quit()


func _table() -> void:
	if world != null:
		world.queue_free()
		await process_frame
	paused = false
	world = TableWorld.new(tavern)
	tavern.table_root.add_child(world)
	var players := []
	for i in SPECIES.size():
		players.append({"pid": i + 1, "species": SPECIES[i]})
	world.arrange(players, 1, true, true)
	var me: Patron = world.patrons[1]
	me.present_hand_to(world.third_person_view(1).origin)
	world.cards.attach_hand(me.fan)
	world.cards.sync({1: 5, 2: 5, 3: 5, 4: 5}, [Card.QUEEN, Card.KING, Card.JOKER, Card.ACE, Card.KING])
	await create_timer(0.8).timeout


func _lean() -> void:
	await _table()
	for pid in [2, 3, 4]:
		var p: Patron = world.patrons[pid]
		p.set_active(true)
		# 低头看自己面前的桌面(俯仰到下限)
		p.look_at_point(p.global_transform * Vector3(0, SeatLayout.TABLE_TOP, -0.45))
	await create_timer(SETTLE).timeout
	for pid in [2, 3, 4]:
		await _shot("lean_%s" % Species.IDS[SPECIES[pid - 1]], world.focus_view(pid))
	# 炸弹猫的 14 张牌扇(鳄鱼)
	var croc: Patron = world.patrons[2]
	for c in croc.fan.get_children():
		c.free()
	for i in 14:
		var card := Card3D.new()
		croc.fan.add_child(card)
		card.transform = BombCatLayout.fan_slot(i, 14)
	await _shot("lean_crocodile_bomb14", world.focus_view(2))


func _peek(name: String, neck: Vector3) -> void:
	await _table()
	for pid in [2, 3, 4]:
		world.patrons[pid].set_neck_target(neck)
		world.patrons[pid].look_at_point(Vector3(0, SeatLayout.TABLE_TOP, 0))
	await create_timer(SETTLE).timeout
	await _shot(name + "_seat", world.third_person_view(1), TableWorld.SEAT_FILL_LIGHT)
	# 斜上方(吊灯罩下面)看桌心
	var eye := Vector3(1.55, 1.75, 1.55)
	await _shot(name + "_table", Transform3D(Basis.looking_at(Vector3(0, 1.05, -0.1) - eye, Vector3.UP), eye))


func _clap() -> void:
	await _table()
	world.celebrate([3], 1)
	await create_timer(2.0).timeout
	await _shot("clap_croc", world.focus_view(2))
	await _shot("clap_cat", world.focus_view(4))


func _fp() -> void:
	await _table()
	world.set_first_person(true)
	var me: Patron = world.patrons[1]
	me.set_head_hidden(true)
	for item in [["fp_center", Vector3(0, 0, -1.25)], ["fp_right", Vector3(0.9, 0, -0.9)]]:
		me.set_neck_target(item[1])
		paused = false
		await create_timer(SETTLE).timeout
		tavern.camera_rig.camera.fov = TableWorld.FIRST_PERSON_FOV
		await _shot(item[0], world.first_person_view(1), TableWorld.FIRST_PERSON_FILL, TableWorld.FIRST_PERSON_FOV)


func _shot(name: String, xform: Transform3D, fill := 0.0, fov := CameraRig.DEFAULT_FOV) -> void:
	var rig := tavern.camera_rig
	rig.stop_follow()
	rig.camera.fov = fov
	rig.fill_light.light_energy = fill
	rig.snap(xform.origin, xform.origin - xform.basis.z)
	paused = true
	for i in 30:
		await process_frame
	for i in 8:
		RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [out_dir, name])
	print("saved ", name)
	paused = false
