class_name TableWorld
extends Node3D
# 牌桌上的角色层:按座位摆放酒客与左轮,提供座位几何与机位查询。卡牌交给 CardTable;
# 德州的 3D 节点(筹码、公共牌架与牌、亮牌、弃牌堆、庄家按钮)都挂在 poker_root 下,拆台时一起清空。
# 等待厅与对局共用:都显示全部玩家(含自己);对局中镜头在自己角色身后越肩(第三人称),按 V 可换成第一人称(first_person)。


signal first_person_changed(on: bool)   # 本机视角换了:德州牌层据此重摆自己的底牌
signal sfx(sound: String)               # 结算庆祝的音效(礼炮、开场小号、掌声),main 接到 Sfx


# 左轮放在座位右前方、翻牌行之外(翻牌行在本机座位前 CardTable.REVEAL_Z 处)
const REVOLVER_RADIUS := 0.78
const REVOLVER_SIDE := 0.32
# 越肩机位(规格 §5.5):座位外 BEHIND 米、右移 SIDE、高 HEIGHT;骗子酒馆桌(座位半径 1.25)正好是上游拉远后的 2.45 米。
# 动森式 2 头身(2026-10-08):自己的大头在画面左下占得多,机位再右移、抬高一点(原 0.6 / 2.05),越过大头看到桌面和左手边的人。
# 4 人桌的铭牌挂在 Patron.NAMEPLATE_HEIGHT(座位上方 1.92 m),镜头比它高,不会挤在一起
const THIRD_PERSON_BEHIND := 1.2
# 德州桌(半径 1.45):铭牌挂在最高的头顶之上(NAMEPLATE_HEIGHT、错开 NAMEPLATE_STAGGER),镜头要比铭牌高出一点,8 个铭牌
# 投到画面上才散得开(镜头和铭牌一样高时全挤在一条地平线上);再高,镜头到对面帽顶的连线就擦到吊灯罩
# (两条都见 test_poker_view_layout)。Q 版是 (0.55, 1.92, 0.85)、铭牌 1.62
const POKER_THIRD_PERSON := Vector3(0.6, 2.05, 0.8)   # (右移, 高, 座位外)
const THIRD_PERSON_HEIGHT := 2.2
const THIRD_PERSON_SIDE := 0.72
const SEAT_FILL_LIGHT := 0.9   # 越肩机位的补光强度(CameraRig.fill_light)
# 第一人称(规格 2026-10-08-first-person-toggle):眼睛见 Patron.FP_EYE_OFFSET;看向桌心再往对面挪一点、略高于桌面,
# 对面的脸落在画面上半、桌面与出牌区在中间。视角放宽一点;补光跟着镜头贴在脸前,手里的牌离它只有半米,减弱
const FIRST_PERSON_FOV := 72.0
const FIRST_PERSON_TARGET := Vector2(0.15, 0.08)   # (越过桌心往对面, 高出桌面)
const FIRST_PERSON_FILL := 0.4
const LOBBY_SHIFT := 0.95      # 等待厅机位向右平移(米)
# 观战与等待厅机位 [位置, 看向]:骗子酒馆的数值不变;德州桌放大后另用一组(规格 §5.5),
# 都让最远的头与 1.70 米高的头顶(动森式大头;Q 版按 1.60)避开吊灯罩(见 test_poker_view_layout)
const OVERVIEW_LIARS := [Vector3(0, 2.3, 2.7), Vector3(0, SeatLayout.TABLE_TOP, -0.25)]
const OVERVIEW_POKER := [Vector3(0, 2.1, 2.7), Vector3(0, SeatLayout.TABLE_TOP, 0.0)]   # Q 版 (0, 2.0, 2.6):铭牌抬高后跟着抬一点
const LOBBY_LIARS := [Vector3(LOBBY_SHIFT, 2.6, 2.5), Vector3(LOBBY_SHIFT, 0.75, -0.1)]
const LOBBY_POKER := [Vector3(1.65, 2.75, 3.35), Vector3(1.35, 0.75, 0.1)]
# 结算环绕(CameraRig.orbit 的参数):德州的椅背在 2.11 米,环绕要更远更高,镜头高约 2 米
const ORBIT_LIARS := {"center": Vector3(0, 0.95, 0), "radius": 2.4, "height": 0.9, "speed": 0.18}
const ORBIT_POKER := {"center": Vector3(0, 0.95, 0), "radius": 3.1, "height": 1.05, "speed": 0.15}
# 结算庆祝:环绕中心(胜者)在画面里的横向位置(-1 左边缘 … 1 右边缘),结算面板停在右边(UiTheme.SETTLEMENT_DOCK)
const SETTLEMENT_FRAME := -0.42
# 胜者特写环绕的半径:让到左边后要把整个人、两门礼炮都框进来(原来居中时 1.3)
const WINNER_ORBIT_RADIUS := 1.75
const GROUP_ORBIT_SPREAD := 1.0  # 几个胜者离中点都不超过这么远(米)时绕他们转,否则整桌环绕
const SEAT_MOVE := 0.6           # 换座位、桌子放大时酒客沿圆弧滑到新座位的时长(秒)
# 德州铭牌挂点(规格 §6.3):高过最高的头顶(动森式大头:羊驼耳尖 ≈1.70 m、礼帽 ≈1.69 m;Q 版统一挂 1.62,礼帽尖
# 会被铭牌下沿盖住几厘米)。挂高之后相邻座位的铭牌在越肩、观战机位下容易叠在一起(离镜头近的那个投得低),
# 所以按座位绕桌的序号错开高度:偶数号(含本机 0 号)再高 NAMEPLATE_STAGGER,奇数号在 NAMEPLATE_HEIGHT
const NAMEPLATE_HEIGHT := 1.74
const NAMEPLATE_STAGGER := 0.12
# 翻牌机位朝出牌者偏转的权重(0 = 只看翻牌行,1 = 只看出牌者头部)
const REVEAL_LIAR_WEIGHT_FRONT := 0.35
const REVEAL_LIAR_WEIGHT_SIDE := 0.2
const EMPTY_CHAIRS := 4        # 主菜单(没有酒客时)牌桌旁摆的空椅子
const LOCAL_SPECIES := -2      # arrange 的物种计划里表示「不带 species 键」:按本地第一个空着的分配(离线工具与测试)

var tavern: Tavern
var cards: CardTable
var banter: BanterFx   # 丢番茄与说话的表现(等待厅与两种牌桌共用)
var patrons := {}      # pid -> Patron
var revolvers := {}    # pid -> Revolver3D
var seat_angles := {}  # pid -> float
var my_pid := 0
var table_radius := SeatLayout.TABLE_RADIUS   # 当前桌面半径:德州时放大
var seat_radius := SeatLayout.SEAT_RADIUS     # 座位到桌心的距离 = 桌面半径 + SEAT_GAP
var poker_root: Node3D   # 德州的 3D 节点都挂在这里(规格 §5.1),clear_poker 一次清空
var _show_self := true
var _empty_chairs: Array[MeshInstance3D] = []
var _slides := {}        # pid -> Tween:正在沿圆弧滑向新座位的酒客
var _spawned_frame := {} # pid -> 建出这个酒客的帧号:同一帧里物种又变了,直接收走刚建的、不再冒一次烟
var _menu_preview: Patron = null   # 主菜单上自己选的形象,坐在 0 号椅
var first_person := false          # 本机牌桌视角(只影响本机):seat_view / rest_view 据此给机位
var third_person_override: Variant = null   # 越肩机位的 (右移, 高, 座位外):牌桌屏幕按玩法换(斗地主),为空时按桌子大小用默认值
var celebration: Celebration = null   # 结算庆祝(胜者跳舞、旁人鼓掌、礼炮彩纸),见 celebration.gd
var clip_guard: ClipGuard          # 穿模防护:探头的软碰撞形状(酒客、牌扇自动参与;玩法道具用 clip_guard.set_prop 登记)


func _init(p_tavern: Tavern) -> void:
	tavern = p_tavern
	clip_guard = ClipGuard.new(self)
	# 在 _init 里建:德州牌桌可能在本节点进树之前就要往里挂东西
	poker_root = Node3D.new()
	poker_root.name = "PokerRoot"
	add_child(poker_root)


func _ready() -> void:
	cards = CardTable.new(self)
	add_child(cards)
	_guard_candles()
	banter = BanterFx.new(self)
	add_child(banter)
	# 主菜单第一眼不再是一张光秃秃的桌子:没有酒客时摆上空椅子(共用酒客椅子的网格)
	for i in EMPTY_CHAIRS:
		var chair := MeshKit.add(self, PatronParts.chair_mesh(), null)
		chair.name = "EmptyChair%d" % i
		chair.transform = seat_transform(TAU * i / EMPTY_CHAIRS)
		_empty_chairs.append(chair)


# —— 座位 ——

func configure_table(radius: float) -> void:
	# 桌子按玩法放大或复原(德州 POKER_TABLE_RADIUS,骗子酒馆 TABLE_RADIUS);
	# 座位跟着桌沿走,已落座的酒客滑到新位置
	table_radius = radius
	seat_radius = SeatLayout.seat_radius_for(radius)
	if tavern != null:   # 单元测试里只有角色层,没有酒馆
		tavern.set_table_radius(radius)
	for pid in patrons:
		_place_patron(pid, seat_angles.get(pid, 0.0))


func is_poker_table() -> bool:
	return table_radius > SeatLayout.TABLE_RADIUS


func arrange(players: Array, p_my_pid: int, show_self: bool, with_revolvers: bool, wait_for_species := false) -> void:
	# players: [{"pid", "species"?, ...}] 按座位顺序;新玩家弹出登场,离开的玩家消失。
	# 物种用房主分配的 species(子项目② §3.5),各端一致;没有形象(-1 或非法值)时:
	# wait_for_species(等待厅)→ 先不建,等房主分配;否则(对局)→ 按座位顺序本地补第一个空着的并告警。
	# 不带 species 键(离线工具与测试)→ 本地第一个空着的
	clear_menu_preview()
	my_pid = p_my_pid
	_show_self = show_self
	_show_empty_chairs(false)
	var order := players.map(func(p): return p["pid"])
	var plan := species_plan(players, wait_for_species)
	var my_index := maxi(order.find(my_pid), 0)
	for pid in patrons.keys():
		if not order.has(pid):
			patrons[pid].vanish()
			patrons.erase(pid)
			_slides.erase(pid)
	for pid in revolvers.keys():
		if not order.has(pid) or not with_revolvers:
			revolvers[pid].queue_free()
			revolvers.erase(pid)
	seat_angles = {}
	for i in order.size():
		var pid = order[i]
		var angle := SeatLayout.seat_angle(i, my_index, order.size())
		seat_angles[pid] = angle
		var visible_patron: bool = show_self or pid != my_pid
		if visible_patron:
			_place_patron(pid, angle, plan[pid])
		elif patrons.has(pid):
			patrons[pid].queue_free()
			patrons.erase(pid)
		if with_revolvers:
			_place_revolver(pid, angle)


static func species_plan(players: Array, wait_for_species: bool) -> Dictionary:
	# pid -> 物种下标:房主分配的合法值照用;没有形象的在等待厅里是 UNASSIGNED(先不建),
	# 在对局里按座位顺序补第一个空着的(只看这份名单,不看本地已有的角色:各端结果一致);不带键的是 LOCAL_SPECIES
	var plan := {}
	var taken := []
	for p in players:
		var assigned := Species.sanitize(p.get("species"))
		if assigned != Species.UNASSIGNED:
			taken.append(assigned)
	for p in players:
		if not p.has("species"):
			plan[p["pid"]] = LOCAL_SPECIES
			continue
		var index := Species.sanitize(p["species"])
		if index == Species.UNASSIGNED and not wait_for_species:
			index = Species.first_free(taken)
			taken.append(index)
			push_warning("座位 %s 没有房主分配的形象(%s),本地补成 %s" % [p["pid"], str(p["species"]), Species.IDS[index]])
		plan[p["pid"]] = index
	return plan


func _place_patron(pid: int, angle: float, species := LOCAL_SPECIES) -> void:
	# species:LOCAL_SPECIES = 已有就沿用、新来的取本地第一个没人用的(之后一直沿用,换座、复活都不变);
	# UNASSIGNED = 还没分到形象,已有就留着、没有先不建;合法值 = 用它,和现有角色不同就原地换人
	var xform := seat_transform(angle)
	if patrons.has(pid):
		if species < 0 or patrons[pid].species_index == species:
			_slide_patron(pid, angle)
		else:
			_swap_patron(pid, species, xform)
		return
	if species == Species.UNASSIGNED:
		return
	if species == LOCAL_SPECIES:
		var used := patrons.values().map(func(p: Patron) -> int: return p.species_index)
		species = Species.first_free(used)
	var patron := Patron.new(species)
	patron.transform = xform
	patron.guard = clip_guard
	patron.guard_id = pid
	add_child(patron)
	patron.appear()
	patrons[pid] = patron
	_spawned_frame[pid] = Engine.get_process_frames()


func _swap_patron(pid: int, species: int, xform: Transform3D) -> void:
	# 等待厅换形象:在座位上建新的并登场,旧的冒烟缩小离场,烟雾盖住交接。
	# 同一帧里又变了(连着几份名单)只换最后一次:刚建的直接收走
	var old: Patron = patrons[pid]
	if _slides.has(pid) and _slides[pid].is_valid():
		_slides[pid].kill()
	_slides.erase(pid)
	var fresh := Patron.new(species)
	fresh.transform = xform
	fresh.guard = clip_guard
	fresh.guard_id = pid
	fresh.visible = old.visible
	add_child(fresh)
	if _spawned_frame.get(pid, -1) == Engine.get_process_frames():
		old.queue_free()
	else:
		old.vanish()
	fresh.appear()
	patrons[pid] = fresh
	_spawned_frame[pid] = Engine.get_process_frames()


func _slide_patron(pid: int, angle: float) -> void:
	# 沿圆弧滑到新座位:按角度(走短的一侧)与半径插值,走弦线会穿过桌沿。
	# 补间挂在酒客身上:酒客离场释放时一起停下;上一段没走完就从当前位置接着走
	var patron: Patron = patrons[pid]
	if _slides.has(pid) and _slides[pid].is_valid():
		_slides[pid].kill()
	var from_angle := angle_of(patron.position)
	var from_radius := Vector2(patron.position.x, patron.position.z).length()
	var to_radius := seat_radius
	var tween := patron.create_tween()
	tween.tween_method(func(t: float) -> void:
		_put_on_circle(patron, lerp_angle(from_angle, angle, t), lerpf(from_radius, to_radius, t)),
		0.0, 1.0, SEAT_MOVE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_slides[pid] = tween


static func _put_on_circle(patron: Node3D, angle: float, radius: float) -> void:
	# 与 seat_transform 同一朝向(面向桌心);只改位置与转角,不动缩放(登场动画还在放大时也照常)
	patron.position = SeatLayout.seat_position(angle, radius)
	patron.rotation = Vector3(0.0, -angle, 0.0)


func remove_patron(pid: int) -> void:
	# 离桌(德州 player_left):酒客播离场动画后释放;座位角度留到下一次 arrange,
	# 筹码、铭牌在这之前仍按这个座位摆
	if not patrons.has(pid):
		return
	_slides.erase(pid)
	patrons[pid].vanish()
	patrons.erase(pid)


func set_patron_visible(pid: int, shown: bool) -> void:
	# 本机观战:观战机位在本机座位后上方,自己的酒客会挡镜头,只在本机藏起来(别人照样看得到)。
	# 不用 arrange 的 show_self:它会释放并重建酒客,可能换成别的动物
	if patrons.has(pid):
		patrons[pid].visible = shown


func species_index_of(pid: int) -> int:
	# 该玩家角色的物种下标;还没有角色时返回 UNASSIGNED
	if not patrons.has(pid):
		return Species.UNASSIGNED
	return patrons[pid].species_index


# —— 主菜单形象预览 ——

func show_menu_preview(species: int) -> void:
	# 自己选的形象坐在 0 号椅上(0 号空椅子藏起来),换形象时原地冒烟换人;桌上有真人酒客(等待厅、牌桌)时不摆
	species = Species.sanitize(species)
	if species == Species.UNASSIGNED or not patrons.is_empty():
		clear_menu_preview()
		return
	if is_instance_valid(_menu_preview) and _menu_preview.species_index == species:
		return
	var fresh := Patron.new(species)
	fresh.transform = seat_transform(0.0)
	add_child(fresh)
	if is_instance_valid(_menu_preview):
		_menu_preview.vanish()
	fresh.appear()
	fresh.set_expression("smug")
	_menu_preview = fresh
	if not _empty_chairs.is_empty():
		_empty_chairs[0].visible = false


func clear_menu_preview() -> void:
	# arrange 与 clear 会自动收走;0 号空椅子在空桌上回来
	if is_instance_valid(_menu_preview):
		_menu_preview.queue_free()
	_menu_preview = null
	if not _empty_chairs.is_empty() and patrons.is_empty():
		_empty_chairs[0].visible = _empty_chairs[1].visible if _empty_chairs.size() > 1 else true


func _place_revolver(pid: int, angle: float) -> void:
	if not revolvers.has(pid):
		var gun := Revolver3D.new()
		add_child(gun)
		revolvers[pid] = gun
	revolvers[pid].global_transform = revolver_rest(pid)


func revive_all() -> void:
	# 新一局开始前:收起结算庆祝,倒下的酒客换成新的(带登场动画),活着的复位姿势(如胜者的庆祝),帽子等散落物一并清理
	stop_celebration()
	for pid in patrons.keys():
		var old: Patron = patrons[pid]
		if old.alive:
			old.reset_pose()
			continue
		var fresh := Patron.new(old.species_index)
		fresh.transform = old.transform
		old.queue_free()
		add_child(fresh)
		fresh.appear()
		patrons[pid] = fresh
	_clear_debris()


func clear() -> void:
	stop_celebration()
	clear_menu_preview()
	for pid in patrons:
		patrons[pid].queue_free()
	for pid in revolvers:
		revolvers[pid].queue_free()
	patrons = {}
	revolvers = {}
	seat_angles = {}
	_slides = {}
	_spawned_frame = {}
	cards.clear_all()
	if banter != null:
		banter.clear()
	_clear_debris()
	_show_empty_chairs(true)


# —— 结算庆祝(规格 2026-10-09-winner-celebration)——

func celebrate(winners: Array, seed_value := 0) -> Celebration:
	# 结算开始:胜者(可以几个人并列)跳舞、活着的其他人鼓掌、出局的人抽手,胜者两侧的桌沿放礼炮。
	# 纯本地表现;再调用一次就从头再来。seed_value 决定挑哪支舞(各端用同样的对局信息算,就跳同一支)
	stop_celebration()
	celebration = Celebration.new()
	celebration.setup(self, winners, seed_value)
	celebration.sfx.connect(sfx.emit)
	add_child(celebration)
	return celebration


func stop_celebration() -> void:
	# 收起庆祝(回等待厅、离开、新一局、拆台):舞步停下、活着的人坐回去,礼炮与彩纸立刻收走。可以重复调用
	if celebration != null and is_instance_valid(celebration):
		celebration.stop()
		remove_child(celebration)
	celebration = null


func is_celebrating() -> bool:
	return celebration != null and is_instance_valid(celebration)


func winner_orbit(pid: int) -> Dictionary:
	# 胜者特写环绕(CameraRig.orbit 的参数):从胜者面朝牌桌的一侧开始,绕着胜者的头转;胜者在画面左边(frame)
	var toward_table := -SeatLayout.direction(seat_angles.get(pid, 0.0))
	return {"center": head_position(pid) + Vector3(0, -0.25, 0), "radius": WINNER_ORBIT_RADIUS, "height": 0.45, "speed": 0.22,
		"start": atan2(toward_table.x, toward_table.z), "frame": SETTLEMENT_FRAME, "fill": SEAT_FILL_LIGHT * 0.6}


func celebration_orbit(winners: Array) -> Dictionary:
	# 结算庆祝的环绕(规格 2026-10-09-winner-celebration):结算面板停在右边,跳舞的人一直待在画面左边。
	# 一个胜者:绕他的头转(winner_orbit);几个胜者挨得近:绕他们的中点转、按散开的距离拉远;
	# 散得开(德州全员平局等)或胜者都不在桌上:整桌环绕,桌心也让到画面左边
	var heads: Array[Vector3] = []
	var first := -1
	for pid in winners:
		if patrons.has(pid):
			heads.append(head_position(pid))
			if first < 0:
				first = pid
	if heads.size() == 1:
		return winner_orbit(first)
	if heads.size() > 1:
		var mid := Vector3.ZERO
		for h in heads:
			mid += h / heads.size()
		var spread := 0.0
		for h in heads:
			spread = maxf(spread, Vector2(h.x - mid.x, h.z - mid.z).length())
		if spread <= GROUP_ORBIT_SPREAD:
			var toward := Vector3(-mid.x, 0.0, -mid.z) + to_global(Vector3.ZERO) * Vector3(1, 0, 1)
			if toward.length_squared() < 0.0001:
				toward = Vector3.BACK
			return {"center": mid + Vector3(0, -0.2, 0), "radius": WINNER_ORBIT_RADIUS + spread * 1.2, "height": 0.45 + spread * 0.3,
				"speed": 0.2, "start": atan2(toward.x, toward.z), "frame": SETTLEMENT_FRAME, "fill": SEAT_FILL_LIGHT * 0.6}
	var orbit := table_orbit()
	orbit["frame"] = SETTLEMENT_FRAME
	orbit["fill"] = 0.0
	return orbit


static func orbit_start(orbit: Dictionary, view_aspect := 16.0 / 9.0) -> Transform3D:
	# 环绕的起始机位(截图与性能探针用;同 CameraRig.orbit 的起点,含横向取景)
	var a: float = orbit.get("start", 0.0)
	var pos: Vector3 = orbit["center"] + Vector3(sin(a) * orbit["radius"], orbit["height"], cos(a) * orbit["radius"])
	return CameraRig.framed(_look(pos, orbit["center"]), orbit.get("frame", 0.0), CameraRig.DEFAULT_FOV, view_aspect)


func _show_empty_chairs(shown: bool) -> void:
	for chair in _empty_chairs:
		chair.visible = shown


func clear_poker() -> void:
	# 拆台(规格 §5.1):德州的 3D 节点全部释放,酒客牌扇里不归 CardTable 管的牌(德州手牌)也收走。
	# 先摘下再释放:同一帧里就看不到了,挂在它们身上的补间与协程随之停下;可以重复调用
	for child in poker_root.get_children():
		poker_root.remove_child(child)
		child.queue_free()
	var liars_cards := cards.my_cards.duplicate()
	for pid in cards.held:
		liars_cards.append_array(cards.held[pid])
	for pid in patrons:
		var fan: Node3D = patrons[pid].fan
		for child in fan.get_children():
			if child is Card3D and not liars_cards.has(child):
				fan.remove_child(child)
				child.queue_free()
	third_person_override = null   # 斗地主换过的越肩机位也回到默认


func _clear_debris() -> void:
	# 出局时打飞的帽子等:Patron 把它们挂到本节点下并打上 DEBRIS_GROUP 标记
	for child in get_children():
		if child.is_in_group(Patron.DEBRIS_GROUP):
			child.queue_free()


func _guard_candles() -> void:
	# 桌上的烛台(酒馆的摆设,德州时收起):头从上面拱过去。没有酒馆(单元测试)时不登记
	if tavern == null:
		return
	var holders := tavern.table_decor()
	for i in holders.size():
		var holder: Node3D = holders[i]
		var at := to_local(holder.global_position)
		clip_guard.set_prop(StringName("candles_%d" % i), ClipGuard.circle(at, CandlesProp.DISH_RADIUS, CandlesProp.top_height(),
			ClipGuard.LIFT, holder))


# —— 几何查询 ——

static func angle_of(pos: Vector3) -> float:
	# 桌面上一点绕桌心的角度(SeatLayout 的约定:0 = +Z,俯视顺时针增大),取值 [0, TAU)
	return wrapf(atan2(-pos.x, pos.z), 0.0, TAU)


func seat_angle_now(pid: int) -> float:
	# 此刻的座位角度:酒客还在沿圆弧滑动时取他当前所在的角度(筹码堆、按钮、铭牌跟着他走);
	# 没有酒客(已离场、本机观战者与迟到者不建)时取座位角度
	if patrons.has(pid):
		return angle_of(patrons[pid].position)
	return seat_angles.get(pid, 0.0)


func nameplate_anchor(pid: int) -> Vector3:
	# 德州铭牌挂点(全局坐标):座位原点上方 nameplate_height(pid);跟着滑动中的酒客走,
	# 不随登场 / 离场的缩放动画升降;离场或没建酒客时按座位算
	var base: Vector3 = patrons[pid].position if patrons.has(pid) else seat_transform(seat_angles.get(pid, 0.0)).origin
	return to_global(base + Vector3.UP * nameplate_height(pid))


func nameplate_height(pid: int) -> float:
	# 按座位绕桌的序号(本机 0 号,往左手边数)错开:偶数号高一档。用座位角度(不是滑动中的位置)定序号,
	# 换座位滑动时铭牌高低不跟着跳
	var count := maxi(seat_angles.size(), 1)
	var ring := int(round(seat_angles.get(pid, 0.0) / (TAU / count))) % count
	return NAMEPLATE_HEIGHT + (NAMEPLATE_STAGGER if ring % 2 == 0 else 0.0)


func seat_transform(angle: float) -> Transform3D:
	var pos := SeatLayout.seat_position(angle, seat_radius)
	return Transform3D(Basis.looking_at(-SeatLayout.direction(angle), Vector3.UP), pos)


func seat_right(pid: int) -> Vector3:
	return seat_transform(seat_angles.get(pid, 0.0)).basis.x


func revolver_rest(pid: int) -> Transform3D:
	# 平放在座位右前方桌面上,枪管斜指桌心
	var angle: float = seat_angles.get(pid, 0.0)
	var dir := SeatLayout.direction(angle)
	# 侧放:转轮压在毡面上、握把底帽落在毡面外的木桌面上(低 4 mm),所以用桌上那组侧倾与抬高
	var pos := dir * REVOLVER_RADIUS + seat_right(pid) * REVOLVER_SIDE + Vector3(0, SeatLayout.FELT_TOP + Revolver3D.TABLE_REST_LIFT, 0)
	var aim := (-dir + seat_right(pid) * -0.35).normalized()
	var basis := Basis.looking_at(aim, Vector3.UP) * Basis(Vector3.BACK, PI / 2.0 + Revolver3D.TABLE_REST_ROLL)
	return Transform3D(basis, pos)


func third_person_view(pid: int) -> Transform3D:
	# 越过右肩看向桌心:自己的角色在画面左下,牌扇在其右侧,对手与桌面在画面中央
	var angle: float = seat_angles.get(pid, 0.0)
	var dir := SeatLayout.direction(angle)
	var offset := Vector3(THIRD_PERSON_SIDE, THIRD_PERSON_HEIGHT, THIRD_PERSON_BEHIND) \
		if table_radius <= SeatLayout.TABLE_RADIUS else POKER_THIRD_PERSON
	if third_person_override is Vector3:
		offset = third_person_override
	var pos := dir * (seat_radius + offset.z) + seat_right(pid) * offset.x + Vector3(0, offset.y, 0)
	var target := -dir * 0.12 + Vector3(0, SeatLayout.TABLE_TOP, 0)
	return Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)


func first_person_rest_view(pid: int) -> Transform3D:
	# 第一人称的静止机位:眼睛在坐好、没探头时的位置(Patron.rest_eye),看向桌心对面。镜头朝向与手里牌扇都按它定
	var seat := seat_transform(seat_angles.get(pid, 0.0))
	var eye := seat * Patron.rest_eye()
	var target := seat * Vector3(0, SeatLayout.TABLE_TOP + FIRST_PERSON_TARGET.y, -(seat_radius + FIRST_PERSON_TARGET.x))
	return Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)


func first_person_view(pid: int) -> Transform3D:
	# 第一人称的实时机位:位置跟着自己的眼睛(前倾、WASD 探头都会挪),朝向跟着转头(像 CS:头转到哪镜头跟到哪,
	# 2026-10-09 用户要求)。转头角度取 Patron.view_angles(不含待机晃动),加在静止机位的水平 / 俯仰角上,不横滚
	var rest := first_person_rest_view(pid)
	if not patrons.has(pid):
		return rest
	var me: Patron = patrons[pid]
	rest.origin = me.eye_position()
	var turn: Vector2 = me.view_angles()
	var forward := -rest.basis.z
	var rest_yaw := atan2(-forward.x, -forward.z)
	var rest_pitch := asin(clampf(forward.y, -1.0, 1.0))
	rest.basis = Basis.from_euler(Vector3(rest_pitch + turn.y, rest_yaw + turn.x, 0.0))
	return rest


func seat_view(pid: int) -> Transform3D:
	# 自己座位上的常驻机位:按本机视角给越肩或第一人称
	return first_person_view(pid) if first_person else third_person_view(pid)


func set_first_person(on: bool) -> void:
	# 换本机视角:骗子酒馆的手牌由自己的角色重新举好(德州由牌层收到信号后重摆)
	first_person = on
	present_my_hand()
	first_person_changed.emit(on)


func present_my_hand() -> void:
	# 骗子酒馆:自己的牌扇按视角举到越肩镜头前或第一人称的右下方;德州桌由 PokerCards 摆。
	# 出局了不动(牌扇扣在大腿上)
	if is_poker_table() or not patrons.has(my_pid) or not seat_angles.has(my_pid) or not patrons[my_pid].alive:
		return
	var me: Patron = patrons[my_pid]
	if first_person:
		me.present_hand_first_person(seat_transform(seat_angles[my_pid]), first_person_rest_view(my_pid))
	else:
		me.present_hand_to(third_person_view(my_pid).origin)


func focus_view(pid: int) -> Transform3D:
	# 聚焦某位酒客的特写机位:从桌心斜上方看向其头部
	var angle: float = seat_angles.get(pid, 0.0)
	var dir := SeatLayout.direction(angle)
	var head := head_position(pid)
	var pos := dir * 0.15 + Vector3(0, 1.42, 0) + seat_right(pid) * -0.35
	return Transform3D(Basis.looking_at(head + Vector3(0, -0.08, 0) - pos, Vector3.UP), pos)


func head_position(pid: int) -> Vector3:
	if patrons.has(pid):
		return patrons[pid].head_position()
	var angle: float = seat_angles.get(pid, 0.0)
	return SeatLayout.seat_position(angle, seat_radius) + Vector3(0, 1.32, 0)


func overview_view() -> Transform3D:
	# 观战机位:从自己座位后上方俯看整桌,越过自己(倒下的)角色的头顶;
	# 高度压在吊灯罩之下,否则对面玩家的脸会被灯罩挡住。德州桌更大:更低、更靠后,看向桌心
	var view: Array = OVERVIEW_POKER if is_poker_table() else OVERVIEW_LIARS
	return _look(view[0], view[1])


func lobby_view() -> Transform3D:
	# 等待厅机位:整体右移,牌桌落在画面左侧,右侧留给等待厅面板;抬高以免自己的角色挡住桌面
	var view: Array = LOBBY_POKER if is_poker_table() else LOBBY_LIARS
	return _look(view[0], view[1])


func table_orbit() -> Dictionary:
	# 结算时的环绕机位 {"center", "radius", "height", "speed"}(CameraRig.orbit 的参数)
	return (ORBIT_POKER if is_poker_table() else ORBIT_LIARS).duplicate()


static func uses_overview(in_seats: bool, status: String) -> bool:
	# 德州用哪个常驻机位(规格 §5.5):不在当前座位表里(迟到者)或在观战 → 观战机位;
	# 其余(输光还没选、刚再领等下一手、离座)都留在自己座位的越肩
	return not in_seats or status == PokerRules.STATUS_SPECTATING


func rest_view(pid: int, in_seats: bool, status: String) -> Transform3D:
	# 观战机位,或按本机视角的座位机位
	return overview_view() if uses_overview(in_seats, status) else seat_view(pid)


static func _look(pos: Vector3, target: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)


func reveal_view(liar_pid: int) -> Transform3D:
	# 俯看本机座位前的翻牌行,同时尽量把出牌者(被翻牌的人)的脸收进画面。
	# 翻牌行必须完整在画面里:侧座时镜头只能少转一点,否则牌会掉出画面下缘
	var pos := Vector3(0, 1.42, 1.05)
	var target := Vector3(0, 0.86, 0.0)
	if liar_pid != my_pid and seat_angles.has(liar_pid):
		var sideways := absf(sin(float(seat_angles[liar_pid])))
		var row := Vector3(0, SeatLayout.TABLE_TOP, CardTable.REVEAL_Z)
		target = row.lerp(head_position(liar_pid), lerpf(REVEAL_LIAR_WEIGHT_FRONT, REVEAL_LIAR_WEIGHT_SIDE, sideways))
	return Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)


func look_all_at(point: Vector3) -> void:
	for pid in patrons:
		patrons[pid].look_at_point(point)
