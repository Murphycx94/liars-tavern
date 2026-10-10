class_name DouDizhuShowcase
extends Node
# 截图与性能用的斗地主展台(tools/shot.gd --dou-dizhu-showcase、tools/perf_probe.gd --showcase=dou_dizhu):
# 骗子酒馆的小桌坐 3 人(本机 1 号),牌、帽子、特效与 HUD 用假数据走与牌桌相同的接口(DdzCards / DdzFx / DdzHats / DdzHud /
# DdzNameplate / DdzSettlement)。状态(HUD_STATES),每种先摆好 3D,特效类的停在最好看的那一刻(冻住场景树,拍完再放开):
#   bidding    叫分:每人 17 张、底牌扣在桌心,阿狸叫了 1 分,轮到自己(「不叫 / 1 分 / 2 分 / 3 分」)
#   landlord   定地主:阿狸当地主,聚光灯、地主帽与草帽,底牌翻开摊在桌心
#   playing    出牌中:自己是地主,阿狸出了顺子、小熊不出(只剩 2 张,头顶报警),自己选好一手更大的顺子
#   bomb       阿狸甩出炸弹:烟云、「炸弹!」、倍数 ×4
#   rocket     小熊打出王炸:小火箭到顶炸成烟花
#   plane      阿狸出飞机带单:小纸飞机掠过桌面
#   spring     一手结束:自己(地主)打成春天,别人的剩牌摊开、花瓣飘落、右边这一手的结算
#   settlement 散局结算面板 + 第一名跳舞

const ShowcaseSpecies := preload("res://tools/showcase_species.gd")

const ME := 1
const SEATS := [1, 2, 3]
const SETTLE := 3.0
const NAMES := {1: "我", 2: "阿狸", 3: "小熊"}
const STATE_BIDDING := "bidding"
const STATE_LANDLORD := "landlord"
const STATE_PLAYING := "playing"
const STATE_BOMB := "bomb"
const STATE_ROCKET := "rocket"
const STATE_PLANE := "plane"
const STATE_SPRING := "spring"
const STATE_SETTLEMENT := "settlement"
const HUD_STATES := [STATE_BIDDING, STATE_LANDLORD, STATE_PLAYING, STATE_BOMB, STATE_ROCKET, STATE_PLANE, STATE_SPRING, STATE_SETTLEMENT]
const FX_PEAK := {STATE_BOMB: 0.32, STATE_ROCKET: DdzFx.ROCKET_RISE + 0.36, STATE_PLANE: 0.5, STATE_SPRING: 1.1, STATE_LANDLORD: 0.5}
const MY_DEAL := "3 4 5 6 6 7 8 9 10 J J Q K A 2 2 BJ"
const BOTTOM := "7 K SJ"
const LOG := ["阿狸 叫 1 分", "小熊 不叫", "你 叫 3 分", "你 当地主(底分 3):底牌 7♠ K♥ 小王"]
const TURN_LEFT := 22.0

var world: TableWorld
var cards: DdzCards
var fx3d: DdzFx
var hud: DdzHud = null
var labels: WorldLabels = null
var settlement: DdzSettlement = null
var _camera: Camera3D = null
var _staged := ""
var _frozen := false


func build(tavern: Tavern) -> void:
	await PokerFaces.build(self)
	await DdzJokerFaces.build(self)
	_camera = tavern.camera_rig.camera
	world = TableWorld.new(tavern)
	tavern.table_root.add_child(world)
	# 同 main.apply_table_mode(斗地主):骗子酒馆的桌子,点烛台,不摆目标牌立牌
	world.configure_table(SeatLayout.table_radius_for(GameMode.DOU_DIZHU))
	tavern.set_table_decor_visible(true)
	world.cards.set_stand_visible(false)
	world.third_person_override = DdzLayout.THIRD_PERSON
	world.arrange(ShowcaseSpecies.players([1, 2, 3], {1: 3, 2: 0, 3: 1}), ME, true, false)
	cards = DdzCards.new(world)
	cards.my_pid = ME
	world.poker_root.add_child(cards)
	fx3d = DdzFx.new(world)
	fx3d.my_pid = ME
	world.poker_root.add_child(fx3d)
	await get_tree().create_timer(SETTLE).timeout
	await stage(STATE_PLAYING)   # 性能探针量的就是出牌中的这一桌(三家牌扇、两行牌、帽子、报警)


static func ids(text: String) -> Array:
	return DdzHand.sorted(RulebookDouDizhu.cards(text))


func my_hand(state: String) -> Array:
	var deal := ids(MY_DEAL)
	if state == STATE_BIDDING or state == STATE_LANDLORD:
		return deal
	var full := DdzHand.sorted(deal + ids(BOTTOM))
	var played := ids("6 7 8 9 10") if state != STATE_PLAYING else []
	for c in played:
		full.erase(c)
	if state == STATE_SPRING or state == STATE_SETTLEMENT:
		return []
	return full


func selected_for(state: String) -> Dictionary:
	# 出牌中:自己选好 6 7 8 9 10 的顺子(私有下标)
	if state != STATE_PLAYING:
		return {}
	var hand := my_hand(state)
	var sel := {}
	for c in ids("6 7 8 9 10"):
		var i := hand.find(c)
		if i >= 0:
			sel[i] = true
	return sel


# —— 状态 ——

func stage(state: String, ui_root: Control = null) -> void:
	if not HUD_STATES.has(state):
		push_warning("unknown dou dizhu state %s (known: %s)" % [state, ", ".join(HUD_STATES)])
		return
	unfreeze()
	if state != _staged:
		await _stage_world(state)
		_staged = state
	if ui_root != null:
		stage_hud(ui_root, state)


func _stage_world(state: String) -> void:
	fx3d.clear()
	world.stop_celebration()
	for pid in world.patrons:
		DdzHats.take_off(world.patrons[pid])
		world.patrons[pid].reset_pose()
		world.patrons[pid].set_active(false)
	var counts := {1: 17, 2: 17, 3: 17}
	var rows := {}
	var landlord := ME
	match state:
		STATE_BIDDING:
			landlord = -1
		STATE_LANDLORD:
			landlord = 2
			counts = {1: 17, 2: 17, 3: 17}
		STATE_PLAYING:
			counts = {1: 20, 2: 9, 3: 2}
			rows = {2: ids("4 5 6 7 8")}
		STATE_BOMB:
			counts = {1: 15, 2: 5, 3: 2}
			rows = {1: ids("6 7 8 9 10"), 2: ids("Q Q Q Q")}
		STATE_ROCKET:
			counts = {1: 15, 2: 5, 3: 4}
			rows = {3: ids("SJ BJ")}
		STATE_PLANE:
			counts = {1: 15, 2: 4, 3: 6}
			rows = {2: ids("7 7 7 8 8 8 3 K")}
		STATE_SPRING, STATE_SETTLEMENT:
			counts = {1: 0, 2: 17, 3: 17}
			rows = {2: ids("3 3 4 5 6 8 9 9 10 J Q Q K A A 2 2"), 3: ids("3 4 4 5 5 6 7 8 9 10 10 J Q K A A 2")}
	counts[ME] = my_hand(state).size()
	cards.sync(counts, my_hand(state), rows, state == STATE_BIDDING)
	cards.set_selection(selected_for(state), -1)
	if landlord > 0:
		for pid in world.patrons:
			DdzHats.put_on(world.patrons[pid], DdzState.ROLE_LANDLORD if pid == landlord else DdzState.ROLE_FARMER, false)
	world.look_all_at(DdzLayout.TABLE_FOCUS)
	match state:
		STATE_BIDDING:
			world.patrons[2].set_expression("happy")
			world.patrons[ME].set_active(true)
		STATE_LANDLORD:
			cards.sync(counts, my_hand(state), {}, true)
			await cards.reveal_bottom(ids(BOTTOM), -1, [])   # 翻开摊在桌心(不飞走)
			fx3d.spotlight_on(2, 30.0)
			world.look_all_at(world.head_position(2))
			world.patrons[2].set_expression("smug")
			DdzHats.put_on(world.patrons[2], DdzState.ROLE_LANDLORD, true)
		STATE_PLAYING:
			fx3d.pass_mark(3, cards.to_global(DdzLayout.pass_point(world.seat_angles[3], false)))
			fx3d.set_alarm(3, 2)
			world.patrons[ME].set_active(true)
			world.patrons[3].set_expression("smug")
		STATE_BOMB:
			fx3d.set_alarm(3, 2)
			for pid in world.patrons:
				if pid != 2:
					world.patrons[pid].startle()
			world.patrons[2].slam_table()
			fx3d.bomb(cards.row_center(2) + Vector3(0, 0.05, 0), 4)
			world.look_all_at(cards.row_center(2))
		STATE_ROCKET:
			fx3d.rocket(cards.row_center(3) + Vector3(0, 0.03, 0))
			world.patrons[3].celebrate()
			world.look_all_at(cards.row_center(3) + Vector3(0, 1.0, 0))
		STATE_PLANE:
			fx3d.plane(cards.row_center(2), cards.across_from(2))
			cards.wave(2)
		STATE_SPRING:
			fx3d.spring(cards.to_global(Vector3(0, SeatLayout.TABLE_TOP, 0)))
			world.patrons[ME].set_expression("happy")
			world.patrons[ME].celebrate()
			world.patrons[2].set_expression("worried")
			world.patrons[3].set_expression("worried")
			for pid in SEATS:
				var delta := 24 if pid == ME else -12
				fx3d.pop_text(DdzNameplate.signed(delta), fx3d._above(pid) + Vector3(0, 0.12, 0),
					DdzFx.DELTA_GREEN if delta > 0 else DdzFx.DELTA_RED, 1.1, 30.0, 0.2)
		STATE_SETTLEMENT:
			world.celebrate([ME], hash(["dou_dizhu", ME]))
	var peak: float = FX_PEAK.get(state, 0.0)
	if peak > 0.0:
		await get_tree().create_timer(peak).timeout
		freeze()


func freeze() -> void:
	# 特效停在最好看的那一刻:暂停场景树(补间、计时都停),GPU 粒子也停下
	_frozen = true
	get_tree().paused = true
	for particles: GPUParticles3D in get_tree().root.find_children("*", "GPUParticles3D", true, false):
		particles.speed_scale = 0.0


func unfreeze() -> void:
	if not _frozen:
		return
	_frozen = false
	get_tree().paused = false
	for particles: GPUParticles3D in get_tree().root.find_children("*", "GPUParticles3D", true, false):
		particles.speed_scale = 1.0


func stage_hud(ui_root: Control, state: String) -> void:
	clear_hud()
	labels = WorldLabels.new(_camera)
	ui_root.add_child(labels)
	hud = DdzHud.new()
	ui_root.add_child(hud)
	hud.set_host(true)
	var landlord := 2 if state == STATE_LANDLORD else (ME if state != STATE_BIDDING else -1)
	var roles := {}
	for pid in SEATS:
		roles[pid] = "" if landlord < 0 else (DdzState.ROLE_LANDLORD if pid == landlord else DdzState.ROLE_FARMER)
	var counts: Dictionary = {STATE_PLAYING: {1: 20, 2: 9, 3: 2}, STATE_BOMB: {1: 15, 2: 5, 3: 2}, STATE_ROCKET: {1: 15, 2: 5, 3: 4},
		STATE_PLANE: {1: 15, 2: 4, 3: 6}, STATE_SPRING: {1: 0, 2: 17, 3: 17}, STATE_SETTLEMENT: {1: 0, 2: 17, 3: 17}}.get(state,
		{1: 17, 2: 17, 3: 17})
	var scores := {1: 18, 2: -3, 3: -15} if state != STATE_SPRING else {1: 42, 2: -15, 3: -27}
	var current: int = {STATE_BIDDING: ME, STATE_PLAYING: ME, STATE_BOMB: 3, STATE_ROCKET: ME, STATE_PLANE: 3, STATE_LANDLORD: -1}.get(state, -1)
	for pid in [2, 3]:
		var plate := DdzNameplate.new(NAMES[pid])
		var bid := -1
		if state == STATE_BIDDING:
			bid = 1 if pid == 2 else 0
		plate.set_info({"name": NAMES[pid], "role": roles[pid], "score": scores[pid], "count": counts[pid], "trustee": pid == 3 and state == STATE_PLANE,
			"active": pid == current, "bid": bid, "left": false})
		var patron: Patron = world.patrons[pid]
		labels.track("plate:%d" % pid, plate, patron.nameplate_anchor)
	var mult: int = {STATE_BOMB: 4, STATE_ROCKET: 8, STATE_PLANE: 2, STATE_SPRING: 8, STATE_PLAYING: 2}.get(state, 1)
	var bottom := ids(BOTTOM) if state != STATE_BIDDING else []
	hud.set_info(5, 3 if state != STATE_BIDDING else 0, mult, NAMES[landlord] if landlord > 0 else "", bottom, state == STATE_BIDDING,
		DdzHud.status_text(DdzScreenState.PHASE_BIDDING if state == STATE_BIDDING else DdzScreenState.PHASE_PLAYING, 1, false))
	hud.set_me(NAMES[ME], {"role": roles[ME], "score": scores[ME], "count": my_hand(state).size()}, false, true)
	hud.set_hand(my_hand(state), selected_for(state), true)
	for line in LOG:
		hud.log_event(line)
	match state:
		STATE_BIDDING:
			hud.set_action_mode(DdzHud.ACTION_BID)
			hud.set_bid_actions([0, 2, 3])
			hud.set_turn(DdzHud.turn_text(NAMES[ME], true, DdzState.STAGE_BID), true)
			hud.set_countdown(11.0, DouDizhuSession.BID_TIMEOUT, true)
			hud.set_hint_mode(DdzHud.ACTION_BID)
		STATE_LANDLORD:
			hud.set_action_mode(DdzHud.ACTION_NONE)
			hud.set_turn("", false)
			hud.announce("阿狸 当地主!", UiTheme.BRASS_BRIGHT, "底分 3 分 · 底牌亮给大家看", 30.0)
			hud.set_hint_mode(DdzHud.ACTION_NONE)
		STATE_PLAYING:
			hud.set_action_mode(DdzHud.ACTION_PLAY)
			hud.set_play_actions(true, true, true, true, "顺子 · 5 张", true)
			hud.set_turn(DdzHud.turn_text(NAMES[ME], true, DdzState.STAGE_PLAY), true)
			hud.set_countdown(TURN_LEFT, Protocol.TURN_TIMEOUT, true)
			hud.set_hint_mode(DdzHud.ACTION_PLAY)
		STATE_BOMB:
			hud.set_action_mode(DdzHud.ACTION_NONE)
			hud.set_turn(DdzHud.turn_text(NAMES[3], false, DdzState.STAGE_PLAY), false)
			hud.announce("炸弹!", UiTheme.BLOOD, "倍数翻倍:×4", 30.0, DdzHud.ANNOUNCE_Y_LOW)
			hud.log_event("阿狸 出了 炸弹:Q Q Q Q", UiTheme.LIE)
		STATE_ROCKET:
			hud.set_action_mode(DdzHud.ACTION_NONE)
			hud.announce("王炸!", UiTheme.BLOOD, "倍数翻倍:×8", 30.0, DdzHud.ANNOUNCE_Y_LOW)
			hud.log_event("小熊 出了 王炸", UiTheme.LIE)
		STATE_PLANE:
			hud.set_action_mode(DdzHud.ACTION_NONE)
			hud.set_turn(DdzHud.turn_text(NAMES[3], false, DdzState.STAGE_PLAY), false)
			hud.log_event("阿狸 出了 飞机带单 · 8 张:8 8 8 7 7 7 K 3")
		STATE_SPRING:
			hud.set_action_mode(DdzHud.ACTION_NONE)
			hud.announce("春天!", Color(1.0, 0.62, 0.74), "你赢了!(地主胜)", 30.0, DdzHud.ANNOUNCE_Y_LOW)
			var summary := {"landlord": ME, "landlord_won": true, "base": 3, "multiplier": 8, "bombs": 2, "spring": true}
			hud.show_summary(DdzHud.summary_title(summary, DdzState.ROLE_LANDLORD), DdzHud.formula_text(summary),
				[{"pid": 1, "name": NAMES[1], "role": DdzState.ROLE_LANDLORD, "delta": 48, "score": 42},
				{"pid": 2, "name": NAMES[2], "role": DdzState.ROLE_FARMER, "delta": -24, "score": -15},
				{"pid": 3, "name": NAMES[3], "role": DdzState.ROLE_FARMER, "delta": -24, "score": -27}], ME)
		STATE_SETTLEMENT:
			hud.set_away_from_seat(true)
			settlement = DdzSettlement.new([{"pid": 1, "name": NAMES[1], "score": 42, "place": 1, "left": false},
				{"pid": 2, "name": NAMES[2], "score": -15, "place": 2, "left": false},
				{"pid": 3, "name": NAMES[3], "score": -27, "place": 3, "left": false}], true, DdzState.REASON_HOST, 6, ME)
			ui_root.add_child(settlement)


func clear_hud() -> void:
	for node in [hud, labels, settlement]:
		if node != null and is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.free()
	hud = null
	labels = null
	settlement = null


# —— 机位 ——

func view(name: String, state := "") -> Transform3D:
	# ddz_seat:自己座位的越肩;ddz_overview:俯看整桌;结算状态下是环绕第一名的起点(同导演的散局镜头)
	if state == STATE_SETTLEMENT:
		return TableWorld.orbit_start(world.celebration_orbit([ME]), _camera.get_viewport().get_visible_rect().size.aspect() if _camera != null else 16.0 / 9.0)
	match name:
		"ddz_overview":
			return world.overview_view()
	return world.third_person_view(ME)
