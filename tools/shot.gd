extends SceneTree
# 视觉检查:搭建酒馆并按指定机位截图(需要窗口渲染,不能 --headless)。
# 用法:godot --path . -s tools/shot.gd -- --out=/tmp/shots --views=seat,menu,overhead [--showcase | --poker-showcase] [--stats]
# --showcase 时在桌边摆上 4 名酒客、手牌与左轮,用于检查角色与道具;--scene=menu 时是主菜单状态(空牌桌与空椅子)。
# 骗子酒馆机位表见 tools/camera_views.gd。--showcase 时另有第一人称 fp / fp_peek(按住 WASD 探头)/ fp_lean(往前探),
# --poker-showcase 时有 poker_fp / poker_fp_peek(CameraViews.FIRST_PERSON)。
# --poker-showcase 时摆德州展台(tools/poker_showcase.gd);德州机位 poker_seat / poker_overview / poker_lobby
# 取自 TableWorld 的机位函数(不抄数字),没有展台时另建一个放大的空德州桌。4:3 检查加引擎参数 --resolution 1280x960。
# --hud=bet,showdown,… 给展台的德州机位叠上整套 HUD(状态与 --views 按位置对应,不够的沿用最后一个;见 PokerShowcase.HUD_STATES),
# --neck=x,z 让展台上所有酒客把脖子伸到这个座位偏移(-z 朝桌心,会按 Patron.NECK_REACH 截断),检查探头的样子。
# 文件名带状态,同一机位可以拍几种底部区域。没写 --hud 时展台的德州机位也带 HUD:座位机位 bet,观战机位 spectate。
# 全套:--views=poker_seat,poker_seat,poker_seat,poker_seat,poker_seat,poker_seat,poker_seat,poker_seat,poker_overview
#       --hud=bet,wait,showdown,bust,spectate,waiting,away,settlement,spectate --poker-showcase(4:3 再加 --resolution 1280x960)
# --bomb-cat-showcase 时摆炸弹猫展台(tools/bomb_cat_showcase.gd,6 人大桌):机位 bomb_seat / bomb_overview / bomb_fp(第一人称)/
# bomb_close(摸到炸弹的特写);--hud= 按位置给每个机位一个状态(BombCatShowcase.HUD_STATES:turn / window / bomb / exploded /
# defuse / peek / give / settlement),没写时 bomb_seat、bomb_fp 用 turn,bomb_overview 用 exploded,bomb_close 用 bomb。
# 全套:--views=bomb_seat,bomb_seat,bomb_close,bomb_overview,bomb_seat,bomb_seat,bomb_fp,bomb_seat,bomb_seat
#       --hud=turn,window,bomb,exploded,defuse,peek,turn,give,settlement --bomb-cat-showcase
# --dou-dizhu-showcase 时摆斗地主展台(tools/dou_dizhu_showcase.gd,3 人小桌):机位 ddz_seat / ddz_overview / ddz_fp(第一人称);
# --hud= 按位置给每个机位一个状态(DouDizhuShowcase.HUD_STATES:bidding / landlord / playing / bomb / rocket / plane / spring /
# settlement),没写时用 playing。全套:--views=ddz_seat,ddz_seat,ddz_seat,ddz_seat,ddz_overview,ddz_seat,ddz_seat,ddz_seat,ddz_fp
#       --hud=bidding,landlord,playing,bomb,rocket,plane,spring,settlement,playing --dou-dizhu-showcase
# --liars-dice-showcase 时摆吹牛骰子展台(tools/liars_dice_showcase.gd,6 人大桌):机位 dice_seat / dice_overview / dice_fp(第一人称)/
# dice_close(骰盅与骰子特写)/ dice_peek(第一人称偷看时视线压低);--hud= 按位置给每个机位一个状态
# (LiarsDiceShowcase.HUD_STATES:bidding / peek / counting / lost / out / settlement),没写时 dice_overview 用 out,其余用 bidding。
# 全套:--views=dice_seat,dice_fp,dice_peek,dice_seat,dice_close,dice_seat,dice_close,dice_overview,dice_seat
#       --hud=bidding,peek,peek,counting,counting,lost,lost,out,settlement --liars-dice-showcase
# --lineup 时全部 10 个物种一字排开(机位 lineup_front / lineup_back / lineup_heads …);再加 --ddz-hats=landlord|farmer|mix 给他们戴上斗地主的身份帽。
# --atlas 时另存墙饰图集与墙地噪声贴图(decor_atlas.png、surface_noise.png)。
# --stats 时每个机位打印全帧削顶比例、每张酒客脸与爪子的发白(亮度 ≥ 0.85)/削顶比例、墙面灰泥区域的亮度标准差。
# --celebrate[=秒] 在已摆好的展台(--showcase / --poker-showcase / --bomb-cat-showcase)上开演结算庆祝(tools/celebrate_stage.gd:
# 胜者跳舞、旁人鼓掌、出局的倒着、桌沿礼炮放彩纸),等这么多秒(默认 2.6)再拍;机位 celebrate(胜者特写环绕的起点)、
# celebrate_table(整桌环绕的起点)。例:--showcase --celebrate --views=celebrate,celebrate_table;--celebrate=5 拍第二炮;
# 再加 --celebrate-hud 叠上该玩法的结算面板(文件名带 _settlement);--celebrate-winners=1,2,… 换胜者(德州全员平局:1,2,3,4,5,6,7,8)。
# --preview=<目标>[,<目标>…] 按位置给每个机位一个悬停目标,强制显示悬停大图(CardPreview)并画一个光标小箭头再拍,
# 文件名带 _preview_<目标>;目标写法见 tools/preview_stage.gd:骗子酒馆 hand:N / reveal:N,德州 hand:N / board:N /
# shown:PID:N / boardstrip:N / mystrip:N / showdown:R:N,炸弹猫 strip:N / hand:N / discard,任何机位 at:X:Y(视口比例)/ none。
# 例:--showcase --views=seat,fp,seat --preview=hand:2,hand:0,reveal:0 --freeze;
#     --poker-showcase --views=poker_seat,poker_seat,poker_fp --hud=bet,showdown,bet --preview=hand:1,showdown:0:1,board:2;
#     --bomb-cat-showcase --views=bomb_seat,bomb_seat,bomb_fp --preview=strip:2,discard,strip:4(4:3 再加 --resolution 1280x960)。
# 要做前后像素对比(tools/shot_diff.gd)时加 --freeze 与引擎参数 --fixed-fps 60:搭好展台后暂停场景树(呼吸、眨眼、补间、粒子都停下),
# 每帧时长与随机数种子也固定,两次截图可比。


const CameraViews := preload("res://tools/camera_views.gd")
const CelebrateStage := preload("res://tools/celebrate_stage.gd")
const ImageStats := preload("res://tools/image_stats.gd")
const PreviewStage := preload("res://tools/preview_stage.gd")
const WARMUP_FRAMES := 45
const SETTLE_DRAWS := 8   # 截图前连续强制绘制的帧数(体积雾的时域累积要几帧才收敛;同 DebugFlags)
const POKER_ME := 1
const LINEUP_SPACING := 0.7    # --lineup 时酒客之间的间距(米):10 个物种(原来 8 个时 0.78),大头 ≈0.64 米宽
const LINEUP_Z := 1.5          # 排在牌桌前面,不和桌子重叠
const FACE_RADIUS := 0.17   # 酒客头的半径(米),--stats 按它在画面上框出脸
const PAW_RADIUS := 0.06    # 爪子的半径(米)
# --stats 的灰泥取样区域(按画面比例):只有能看到大片墙面的机位才有
const PLASTER_RECTS := {
	"seat": Rect2(0.55, 0.02, 0.2, 0.12),
	"menu": Rect2(0.62, 0.2, 0.2, 0.15),
	"opponent": Rect2(0.08, 0.08, 0.15, 0.25),
	"gun": Rect2(0.25, 0.1, 0.15, 0.25),
}
const NECK_SETTLE := 1.5   # 秒:--neck 之后等弹簧脖子停稳

var opts := {}
var _poker_world: TableWorld = null
var _poker: Node = null
var _bomb: Node = null
var _ddz: Node = null
var _dice: Node = null
var _showcase: Node = null
var _ui: Control = null
var _celebrate_world: TableWorld = null   # --celebrate:开演庆祝的那张牌桌
var _celebrate_kind := ""
var _preview: CardPreview = null   # --preview:悬停大图(单独一层,压在 HUD 之上)
var _cursor: Control = null        # --preview:光标小箭头


func _initialize() -> void:
	seed(2026)
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	process_frame.connect(_run, CONNECT_ONE_SHOT)
	process_frame.connect(_draw_when_covered)


func _draw_when_covered() -> void:
	# 窗口被别的窗口挡住时 macOS 不再调度正常绘制:牌面生成与截图里等 frame_post_draw 会永远卡住。
	# 每帧强制绘制一次(不交换缓冲),frame_post_draw 照常发出,不依赖窗口可见
	if not DisplayServer.window_can_draw():
		RenderingServer.force_draw(false)


func _run() -> void:
	var out_dir: String = opts.get("out", OS.get_user_data_dir() + "/shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	RenderBudget.apply(root)
	var tavern := Tavern.new()
	root.add_child(tavern)
	await RoomTextures.build(root)   # 墙地噪声与墙饰图集:不等的话截图里是回退色
	if opts.has("atlas"):
		# 顺手存一份墙饰图集与噪声贴图,检查通缉令、招牌与外景
		DecorAtlas.texture().get_image().save_png(out_dir + "/decor_atlas.png")
		SurfaceNoise.texture().get_image().save_png(out_dir + "/surface_noise.png")
	if opts.has("lineup"):
		# 全部物种一字排开(面朝镜头),配 lineup_front / lineup_back / lineup_heads 机位
		for i in Species.count():
			var patron := Patron.new(i)
			patron.position = Vector3((i - (Species.count() - 1) * 0.5) * LINEUP_SPACING, 0, LINEUP_Z)
			patron.rotation.y = PI
			tavern.table_root.add_child(patron)
			patron.look_at_point(Vector3(0, 1.2, 3.0))
			if opts.has("ddz-hats"):   # 斗地主的身份帽:--ddz-hats=landlord 全戴瓜皮帽,=farmer 全戴草帽,=mix 交替
				var kind: String = opts["ddz-hats"]
				var landlord := kind == "landlord" or (kind == "mix" and i % 2 == 0)
				DdzHats.put_on(patron, DdzState.ROLE_LANDLORD if landlord else DdzState.ROLE_FARMER, false)
	if opts.get("scene", "") == "menu":
		var world := TableWorld.new(tavern)
		tavern.table_root.add_child(world)
		world.clear()
	elif opts.has("showcase"):
		var script: GDScript = load("res://tools/showcase.gd")
		var showcase: Node = script.new()
		root.add_child(showcase)
		await showcase.build(tavern)
		_showcase = showcase
	if opts.has("poker-showcase"):
		var poker: Node = load("res://tools/poker_showcase.gd").new()
		root.add_child(poker)
		await poker.build(tavern)
		_poker_world = poker.world
		_poker = poker
	if opts.has("bomb-cat-showcase"):
		var bomb: Node = load("res://tools/bomb_cat_showcase.gd").new()
		root.add_child(bomb)
		await bomb.build(tavern)
		_bomb = bomb
	if opts.has("dou-dizhu-showcase"):
		var ddz: Node = load("res://tools/dou_dizhu_showcase.gd").new()
		root.add_child(ddz)
		await ddz.build(tavern)
		_ddz = ddz
	if opts.has("liars-dice-showcase"):
		var dice: Node = load("res://tools/liars_dice_showcase.gd").new()
		root.add_child(dice)
		await dice.build(tavern)
		_dice = dice
	if opts.has("celebrate"):
		await _stage_celebration()
	if opts.has("neck"):
		await _stretch_necks(opts["neck"])
	if opts.has("freeze"):
		paused = true   # 暂停场景树:_process、补间、计时器停下,渲染照常
		# 火焰着色器按渲染时间 TIME 跳动、粒子在 GPU 上推进,暂停树管不到:一并停下
		WorldMaterials.flame().set_shader_parameter("speed", 0.0)
		for particles: GPUParticles3D in root.find_children("*", "GPUParticles3D", true, false):
			particles.speed_scale = 0.0
	var views: PackedStringArray = opts.get("views", "seat").split(",")
	var hud_states: PackedStringArray = opts.get("hud", "").split(",")
	for index in views.size():
		var view: String = views[index]
		var hud_state: String = hud_states[mini(index, hud_states.size() - 1)]
		if CelebrateStage.VIEWS.has(view):
			hud_state = "settlement" if opts.has("celebrate-hud") else ""
		elif hud_state == "" and _poker != null:
			hud_state = PokerShowcase.SPECTATE_STATE if view == "poker_overview" else PokerShowcase.BET_STATE
		if CelebrateStage.VIEWS.has(view) and _celebrate_world != null:
			var xform := CelebrateStage.view(_celebrate_world, _celebrate_kind, view, tavern.camera_rig.aspect())
			tavern.camera_rig.stop_follow()
			tavern.camera_rig.camera.fov = CameraRig.DEFAULT_FOV
			tavern.camera_rig.fill_light.light_energy = CelebrateStage.fill(_celebrate_world, _celebrate_kind, view)
			tavern.camera_rig.snap(xform.origin, xform.origin - xform.basis.z)
			if hud_state != "":
				_stage_settlement(tavern)
		elif view.begins_with("ddz_") and _ddz != null:
			if hud_state == "" or not DouDizhuShowcase.HUD_STATES.has(hud_state):
				hud_state = DouDizhuShowcase.STATE_PLAYING
			await _place_ddz_camera(tavern, view, hud_state)
		elif view.begins_with("bomb_") and _bomb != null:
			if hud_state == "" or not BombCatShowcase.HUD_STATES.has(hud_state):
				hud_state = {"bomb_overview": BombCatShowcase.STATE_EXPLODED, "bomb_close": BombCatShowcase.STATE_BOMB}.get(view,
					BombCatShowcase.STATE_TURN)
			await _place_bomb_camera(tavern, view, hud_state)
		elif view.begins_with("dice_") and _dice != null:
			if hud_state == "" or not LiarsDiceShowcase.HUD_STATES.has(hud_state):
				hud_state = LiarsDiceShowcase.STATE_OUT if view == "dice_overview" else LiarsDiceShowcase.STATE_BIDDING
			await _place_dice_camera(tavern, view, hud_state)
		elif CameraViews.FIRST_PERSON.has(view):
			var fp_world: TableWorld = _poker_table(tavern) if view.begins_with("poker_") else _showcase.world
			if view.begins_with("poker_"):
				_place_poker_camera(tavern, "poker_seat")
			CameraViews.place_first_person(tavern.camera_rig, fp_world, POKER_ME, view)
			_stage_hud(tavern, view, hud_state)
		elif view.begins_with("poker_"):
			if _poker_world != null:
				CameraViews.leave_first_person(_poker_world, POKER_ME)
			_place_poker_camera(tavern, view)
			_stage_hud(tavern, view, hud_state)
		else:
			if _showcase != null:
				CameraViews.leave_first_person(_showcase.world, 1)
			_place_camera(tavern.camera_rig, view)
		for i in WARMUP_FRAMES:
			await process_frame
		for i in SETTLE_DRAWS:
			RenderingServer.force_draw(false)
		if view.begins_with("flash") and _showcase != null:
			# 开一枪:2 帧后拍枪口焰,再过 0.6 秒拍硝烟(flashclose 是同一枪的特写机位)
			_showcase.fire()
			for i in 2:
				await process_frame
			_save(out_dir, view)
			await create_timer(0.6).timeout
			_save(out_dir, view.replace("flash", "smoke"))
			continue
		var suffix := ""
		if opts.has("preview"):
			suffix = await _stage_preview(tavern, view, index)
		var image := _save(out_dir, (view if hud_state == "" else view + "_" + hud_state) + suffix)
		if opts.has("stats"):
			_print_stats(view, image)
	quit()


func _stage_preview(tavern: Tavern, view: String, index: int) -> String:
	# --preview:按位置取这个机位的悬停目标,光标停到那张牌露出来的地方,立刻显示大图(不淡入,冻结的场景树里也看得到)
	var targets: PackedStringArray = opts["preview"].split(",")
	var target: String = targets[mini(index, targets.size() - 1)]
	if _preview == null:
		var layer := CanvasLayer.new()
		layer.layer = 30
		root.add_child(layer)
		var host := Control.new()
		host.theme = UiTheme.theme()
		host.set_anchors_preset(Control.PRESET_FULL_RECT)
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(host)
		_preview = CardPreview.new()
		host.add_child(_preview)
		_cursor = Control.new()
		_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cursor.draw.connect(_draw_cursor)
		host.add_child(_cursor)
	var kind := PreviewStage.kind_of(view)
	var stage: Node = {"liars": _showcase, "poker": _poker, "bomb_cat": _bomb}[kind]
	_cursor.visible = false
	if target == "none" or target == "" or stage == null:
		_preview.hide_preview()
		return ""
	var camera := tavern.camera_rig.camera
	_preview.source = func(point: Vector2) -> Array: return PreviewStage.candidates(kind, stage, camera, point)
	var point := PreviewStage.point_for(kind, stage, camera, target, _preview.size)
	_preview.hover_at(point)
	_cursor.position = point
	_cursor.visible = point.x >= 0.0
	if not _preview.is_showing():
		push_warning("--preview: %s 上的 %s 没有弹出大图" % [view, target])
	for i in 3:
		await process_frame
	return "_preview_" + target.replace(":", "-")


func _draw_cursor() -> void:
	# 截图里看不到系统光标:画一个白底黑边的小箭头标出悬停的位置
	var arrow := PackedVector2Array([Vector2(0, 0), Vector2(0, 19), Vector2(5, 14), Vector2(9, 22), Vector2(12, 21),
		Vector2(8, 13), Vector2(14, 13)])
	_cursor.draw_colored_polygon(arrow, Color.WHITE)
	arrow.append(arrow[0])
	_cursor.draw_polyline(arrow, Color.BLACK, 1.5, true)


func _stretch_necks(spec: String) -> void:
	var xz := spec.split_floats(",")
	var offset := Vector3(xz[0], 0.0, xz[1] if xz.size() > 1 else 0.0)
	for patron in root.find_children("*", "Patron", true, false):
		(patron as Patron).set_neck_target(offset)
	await create_timer(NECK_SETTLE).timeout


func _stage_celebration() -> void:
	# 在最后摆的那个展台上开演结算庆祝,等 --celebrate 给的秒数(默认 CelebrateStage.SETTLE)
	if _bomb != null:
		_celebrate_world = _bomb.world
		_celebrate_kind = "bomb_cat"
	elif _poker_world != null:
		_celebrate_world = _poker_world
		_celebrate_kind = "poker"
	elif _showcase != null:
		_celebrate_world = _showcase.world
		_celebrate_kind = "liars"
	else:
		push_warning("--celebrate 需要 --showcase / --poker-showcase / --bomb-cat-showcase")
		return
	if opts.has("celebrate-winners"):
		CelebrateStage.winners_override = Array(opts["celebrate-winners"].split(",")).map(func(pid: String) -> int: return int(pid))
	CelebrateStage.stage(_celebrate_world, _celebrate_kind)
	var wait: String = opts["celebrate"]
	await create_timer(float(wait) if wait.is_valid_float() else CelebrateStage.SETTLE).timeout


func _stage_settlement(tavern: Tavern) -> void:
	# --celebrate-hud:庆祝机位上叠该玩法的结算面板(德州 / 炸弹猫用展台自己的结算状态,骗子酒馆现摆一个)
	if _ui == null:
		var layer := CanvasLayer.new()
		root.add_child(layer)
		_ui = Control.new()
		_ui.theme = UiTheme.theme()
		_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_ui)
	match _celebrate_kind:
		"poker":
			_poker.stage_hud(_ui, tavern.camera_rig.camera, PokerShowcase.SETTLEMENT_STATE)
		"bomb_cat":
			_bomb.stage_hud(_ui, BombCatShowcase.STATE_SETTLEMENT)
		_:
			for child in _ui.get_children():
				child.free()
			var stats := {1: {"name": "我", "shots": 2, "rounds": 3}, 2: {"name": "阿狸", "shots": 3, "rounds": 4},
				3: {"name": "小熊", "shots": 1, "rounds": 4}, 4: {"name": "老狐狸", "shots": 4, "rounds": 2}}
			# 骗子酒馆的结算面板读 Net(autoload):运行时再加载,免得本脚本编译时就要认得 Net
			var panel_script: GDScript = load("res://src/ui/table/settlement.gd")
			_ui.add_child(panel_script.new("阿狸", panel_script.build_ranking(2, [4, 1, 3], stats), false))


func _save(out_dir: String, file: String) -> Image:
	RenderingServer.force_draw(false)
	var path := "%s/%s.png" % [out_dir, file]
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("saved ", path)
	return image


func _place_camera(rig: CameraRig, view: String) -> void:
	if not CameraViews.place(rig, view):
		push_warning("unknown view " + view)


func _print_stats(view: String, image: Image) -> void:
	var size := image.get_size()
	print("STATS %s frame_clip=%.3f" % [view, ImageStats.clipped_ratio(image, Rect2i(Vector2i.ZERO, size))])
	var camera := root.get_camera_3d()
	for patron in root.find_children("*", "Patron", true, false):
		var id: String = PatronParts.species(patron.species_index)["id"]
		_print_region(view, "face " + id, image, camera, patron.head_position(), FACE_RADIUS)
		for hand: Node3D in [patron.find_child("ArmL", true, false).get_node("Hand"), patron.right_hand]:
			_print_region(view, "paw " + id, image, camera, hand.global_position, PAW_RADIUS)
	if PLASTER_RECTS.has(view):
		var rel: Rect2 = PLASTER_RECTS[view]
		var rect := Rect2i(Rect2(rel.position * Vector2(size), rel.size * Vector2(size)))
		print("STATS %s plaster_stddev=%.1f" % [view, ImageStats.luma_stddev(image, rect)])


func _print_region(view: String, label: String, image: Image, camera: Camera3D, center_3d: Vector3, radius: float) -> void:
	# 按球心与半径在画面上框出一块(脸、爪),打印发白与削顶比例
	if camera.is_position_behind(center_3d):
		return
	var center := camera.unproject_position(center_3d)
	var r := center.distance_to(camera.unproject_position(center_3d + camera.global_basis.x * radius))
	var rect := Rect2i(Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0))
	if rect.intersection(Rect2i(Vector2i.ZERO, image.get_size())).get_area() < 16:
		return
	print("STATS %s %s washed=%.3f clip=%.3f" % [view, label, ImageStats.washed_ratio(image, rect), ImageStats.clipped_ratio(image, rect)])


func _place_poker_camera(tavern: Tavern, view: String) -> void:
	# 德州机位:取自 TableWorld(本机座位 = 1 号)。观战机位下本机的酒客藏起来(规格 §5.5),
	# 等待厅里桌上还没有筹码与牌
	var world := _poker_table(tavern)
	var rig := tavern.camera_rig
	world.set_patron_visible(POKER_ME, view != "poker_overview")
	world.poker_root.visible = view != "poker_lobby"
	for pid in world.patrons:
		world.patrons[pid].fan.visible = view != "poker_lobby"
	rig.fill_light.light_energy = 0.0
	var xform: Transform3D
	match view:
		"poker_seat":
			xform = world.third_person_view(POKER_ME)
			rig.fill_light.light_energy = TableWorld.SEAT_FILL_LIGHT
		"poker_overview":
			xform = world.overview_view()
		"poker_lobby":
			xform = world.lobby_view()
		_:
			push_warning("unknown view " + view)
			return
	rig.snap(xform.origin, xform.origin - xform.basis.z)


func _place_bomb_camera(tavern: Tavern, view: String, state: String) -> void:
	# 炸弹猫机位:取自展台的牌桌(本机座位 = 1 号);先摆状态的 3D,再上机位与 HUD
	var world: TableWorld = _bomb.world
	var rig := tavern.camera_rig
	await _bomb.stage(state)
	if view == "bomb_fp":
		CameraViews.place_first_person(rig, world, BombCatShowcase.ME, view)
	else:
		CameraViews.leave_first_person(world, BombCatShowcase.ME)
		_bomb.cards.present_my_fan()
		rig.stop_follow()
		rig.camera.fov = CameraRig.DEFAULT_FOV
		rig.fill_light.light_energy = TableWorld.SEAT_FILL_LIGHT if view == "bomb_seat" else 0.0
		var xform: Transform3D = _bomb.view(view)
		rig.snap(xform.origin, xform.origin - xform.basis.z)
	if _ui == null:
		var layer := CanvasLayer.new()
		root.add_child(layer)
		_ui = Control.new()
		_ui.theme = UiTheme.theme()
		_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_ui)
	_bomb.stage_hud(_ui, state)


func _place_ddz_camera(tavern: Tavern, view: String, state: String) -> void:
	# 斗地主机位:取自展台的牌桌(本机座位 = 1 号);先摆状态的 3D(特效类的停在最好看的那一刻),再上机位与 HUD
	var world: TableWorld = _ddz.world
	var rig := tavern.camera_rig
	await _ddz.stage(state)
	if view == "ddz_fp":
		CameraViews.place_first_person(rig, world, DouDizhuShowcase.ME, view)
	else:
		CameraViews.leave_first_person(world, DouDizhuShowcase.ME)
		_ddz.cards.present_my_fan()
		rig.stop_follow()
		rig.camera.fov = CameraRig.DEFAULT_FOV
		rig.fill_light.light_energy = TableWorld.SEAT_FILL_LIGHT if view == "ddz_seat" else 0.0
		var xform: Transform3D = _ddz.view(view, state)
		rig.snap(xform.origin, xform.origin - xform.basis.z)
	if _ui == null:
		var layer := CanvasLayer.new()
		root.add_child(layer)
		_ui = Control.new()
		_ui.theme = UiTheme.theme()
		_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_ui)
	_ddz.stage_hud(_ui, state)


func _place_dice_camera(tavern: Tavern, view: String, state: String) -> void:
	# 吹牛骰子机位:取自展台的牌桌(本机座位 = 1 号);先摆状态的 3D,再上机位与 HUD(偷看与特写机位不叠 HUD)
	var world: TableWorld = _dice.world
	var rig := tavern.camera_rig
	await _dice.stage(state)
	if view == "dice_fp":
		CameraViews.place_first_person(rig, world, LiarsDiceShowcase.ME, view)
	else:
		CameraViews.leave_first_person(world, LiarsDiceShowcase.ME)
		rig.stop_follow()
		rig.camera.fov = TableWorld.FIRST_PERSON_FOV if view == "dice_peek" else CameraRig.DEFAULT_FOV
		rig.fill_light.light_energy = TableWorld.SEAT_FILL_LIGHT if view == "dice_seat" else 0.0
		var xform: Transform3D = _dice.view(view)
		rig.snap(xform.origin, xform.origin - xform.basis.z)
		world.patrons[LiarsDiceShowcase.ME].set_head_hidden(view == "dice_peek")
	if _ui == null:
		var layer := CanvasLayer.new()
		root.add_child(layer)
		_ui = Control.new()
		_ui.theme = UiTheme.theme()
		_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_ui)
	if view == "dice_close" or view == "dice_peek":
		_dice.clear_hud()
	else:
		_dice.stage_hud(_ui, state)


func _poker_table(tavern: Tavern) -> TableWorld:
	if _poker_world == null:
		_poker_world = TableWorld.new(tavern)
		tavern.table_root.add_child(_poker_world)
		_poker_world.configure_table(SeatLayout.POKER_TABLE_RADIUS)
		tavern.set_table_decor_visible(false)
		_poker_world.cards.set_stand_visible(false)
	return _poker_world


func _stage_hud(tavern: Tavern, view: String, state: String) -> void:
	# 德州 HUD 叠在展台上(等待厅机位没有 HUD);同 main._ui_layer:CanvasLayer + 全屏根控件 + 主题
	if _poker == null or state == "" or view == "poker_lobby":
		return
	if _ui == null:
		var layer := CanvasLayer.new()
		root.add_child(layer)
		_ui = Control.new()
		_ui.theme = UiTheme.theme()
		_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_ui)
	_poker.stage_hud(_ui, tavern.camera_rig.camera, state)
