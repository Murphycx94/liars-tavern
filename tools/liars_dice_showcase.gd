class_name LiarsDiceShowcase
extends Node
# 截图与性能用的吹牛骰子展台(tools/shot.gd --liars-dice-showcase、tools/perf_probe.gd --showcase=liars_dice):
# 6 人大桌坐满,每人面前一只物种色的骰盅,自己盅底下 5 颗骰子;机位取自 TableWorld 与 LiarsDiceLayout。
# 状态(HUD_STATES)用假数据走与牌桌相同的接口(LiarsDiceCups / LiarsDiceFx / LiarsDiceHud / LiarsDiceNameplate),
# 每种状态先用真实的动画入口摆好 3D(等动画播完再拍):
#   bidding   自己的回合:桌心浮着「3 个 5」的大骰子,出价器停在 4 个 5,横幅「轮到你了」
#   shaking   新一轮:全员双手捧着骰盅哗啦哗啦摇(摇个不停,方便取景)
#   peek      新一轮刚摇完:自己掀开盅沿偷看(配 dice_fp 机位就是第一人称视线压低凑过去)
#   counting  开盅计数:所有骰盅翻开、骰子排成一行,5 点与 1 点一颗颗亮起来,计数器数到一半
#   lost      数完判定「吹牛!」:喊的人的一颗骰子「啵」地弹飞冒星星
#   out       5 号骰子输光出局:蚊香眼、星星、骰盅歪倒(配 dice_overview)
#   settlement 结算面板

const ShowcaseSpecies := preload("res://tools/showcase_species.gd")

const ME := 1
const SEATS := 6
const SETTLE := 3.0
const NAMES := {1: "我", 2: "阿狸", 3: "小熊", 4: "老狐狸", 5: "猪猪侠", 6: "一个名字很长的客人"}
const DICE := {1: [1, 2, 5, 5, 6], 2: [1, 3, 3, 4, 6], 3: [2, 2, 5, 6, 6], 4: [1, 1, 4, 5, 6], 5: [3, 4], 6: [2, 3, 4, 5, 5]}
const BID := {"pid": 4, "count": 3, "face": 5}
const CHALLENGE := {"pid": 2, "target": 4, "count": 11, "face": 5}   # 实际 10 个(含 1 点):吹牛,老狐狸丢骰子
const OUT_PID := 5
const LOSER := 4
const TURN_LEFT := 21.0
const ANNOUNCE_HOLD := 30.0
const STATE_BIDDING := "bidding"
const STATE_SHAKING := "shaking"
const STATE_PEEK := "peek"
const STATE_COUNTING := "counting"
const STATE_LOST := "lost"
const STATE_OUT := "out"
const STATE_SETTLEMENT := "settlement"
const HUD_STATES := [STATE_BIDDING, STATE_SHAKING, STATE_PEEK, STATE_COUNTING, STATE_LOST, STATE_OUT, STATE_SETTLEMENT]
const COUNTED := 5          # counting 状态数到第几颗
const LOG := ["—— 第 3 轮 · 场上 27 颗骰子 ——", "小熊 喊 2 个 5", "老狐狸 喊 3 个 5"]

var world: TableWorld
var cups: LiarsDiceCups
var fx3d: LiarsDiceFx
var hud: LiarsDiceHud = null
var labels: WorldLabels = null
var settlement: LiarsDiceSettlement = null
var _camera: Camera3D = null
var _staged := ""


func build(tavern: Tavern) -> void:
	_camera = tavern.camera_rig.camera
	world = TableWorld.new(tavern)
	tavern.table_root.add_child(world)
	# 同 main.apply_table_mode + 吹牛骰子牌桌:6 人换大桌,烛台照常,不摆目标牌立牌
	world.configure_table(SeatLayout.table_radius_for(GameMode.LIARS_DICE, SEATS))
	tavern.set_table_decor_visible(true)
	world.cards.set_stand_visible(false)
	world.arrange(ShowcaseSpecies.players(range(1, SEATS + 1)), ME, true, false)
	cups = LiarsDiceCups.new(world)
	cups.my_pid = ME
	world.poker_root.add_child(cups)
	fx3d = LiarsDiceFx.new(world)
	fx3d.my_pid = ME
	world.poker_root.add_child(fx3d)
	await get_tree().create_timer(SETTLE).timeout
	cups.setup(range(1, SEATS + 1), {})
	cups.set_my_dice(DICE[ME])
	world.look_all_at(world.to_global(LiarsDiceLayout.TABLE_FOCUS))


# —— 状态 ——

func stage(state: String, ui_root: Control = null) -> void:
	# 摆好 state 的 3D(每种状态只摆一次:开盅、出局不可逆),ui_root 不为空时再叠上整套 HUD
	if not HUD_STATES.has(state):
		push_warning("unknown liars dice state %s (known: %s)" % [state, ", ".join(HUD_STATES)])
		return
	if state != _staged:
		await _stage_world(state)
		_staged = state
	if ui_root != null:
		stage_hud(ui_root, state)


func _rows() -> Array:
	var rows := []
	for pid in range(1, SEATS + 1):
		rows.append({"pid": pid, "dice": DICE[pid]})
	return rows


func _stage_world(state: String) -> void:
	match state:
		STATE_BIDDING:
			fx3d.bid_marker(BID["count"], BID["face"])
			world.patrons[ME].set_active(true)
			world.patrons[4].set_expression("smug")
			await get_tree().create_timer(0.5).timeout
		STATE_SHAKING:
			cups.shake(range(1, SEATS + 1), 60.0)
			await get_tree().create_timer(0.4).timeout
		STATE_PEEK:
			cups.peek(ME, 30.0)
			for pid in [3, 5]:
				cups.peek(pid, 30.0)
				world.patrons[pid].cover_mouth(30.0)
			await get_tree().create_timer(0.4).timeout
		STATE_COUNTING, STATE_LOST:
			if cups.state_of(ME) != LiarsDiceCups.STATE_OPEN:
				fx3d.bid_marker(CHALLENGE["count"], CHALLENGE["face"])
				cups.reveal(_rows())
				await get_tree().create_timer(LiarsDiceCups.LIFT_TIME + LiarsDiceCups.SPREAD_TIME + 0.2).timeout
				var order := LiarsDiceScreenState.count_order(_rows(), CHALLENGE["face"])
				var upto := COUNTED if state == STATE_COUNTING else order.size()
				for i in upto:
					cups.hop(order[i][0], order[i][1])
				fx3d.set_counter(upto, CHALLENGE["count"])
				await get_tree().create_timer(LiarsDiceCups.HOP_TIME + 0.1).timeout
			if state == STATE_LOST:
				var order := LiarsDiceScreenState.count_order(_rows(), CHALLENGE["face"])
				for i in range(COUNTED, order.size()):
					cups.hop(order[i][0], order[i][1])
				fx3d.set_counter(order.size(), CHALLENGE["count"])
				world.patrons[2].set_expression("smug")
				world.patrons[2].cover_mouth(30.0)
				world.patrons[LOSER].startle()
				world.patrons[LOSER].set_expression("worried")
				fx3d.verdict(false)
				var pos := cups.pop_die(LOSER)
				fx3d.die_popped(pos)
				await get_tree().create_timer(LiarsDiceCups.POP_TIME * 0.35).timeout
		STATE_OUT:
			if world.patrons[OUT_PID].alive:
				cups.tip(OUT_PID)
				cups.clear_dice(OUT_PID)
				world.patrons[OUT_PID].die()
				world.look_all_at(world.head_position(OUT_PID))
				await get_tree().create_timer(1.6).timeout
		STATE_SETTLEMENT:
			pass


func stage_hud(ui_root: Control, state: String) -> void:
	clear_hud()
	labels = WorldLabels.new(_camera)
	ui_root.add_child(labels)
	hud = LiarsDiceHud.new()
	ui_root.add_child(hud)
	var current := ME
	match state:
		STATE_COUNTING, STATE_LOST, STATE_OUT:
			current = -1
		STATE_PEEK, STATE_SHAKING:
			current = 3
	for pid in range(2, SEATS + 1):
		var plate := LiarsDiceNameplate.new(NAMES[pid])
		var out := state == STATE_OUT and pid == OUT_PID
		var count: int = 0 if out else DICE[pid].size()
		if pid == LOSER and state in [STATE_LOST, STATE_OUT]:
			count -= 1
		var last := {"count": 3, "face": 5} if pid == 4 else ({"count": 2, "face": 5} if pid == 3 else {})
		plate.set_info(count, not out, false, pid == current, last)
		var anchor: Callable = world.nameplate_anchor.bind(pid) if world.is_poker_table() else world.patrons[pid].nameplate_anchor
		labels.track("plate:%d" % pid, plate, anchor)
	var challenged := {"pid": CHALLENGE["target"], "count": CHALLENGE["count"], "face": CHALLENGE["face"]}
	var bid := BID if state in [STATE_BIDDING, STATE_PEEK, STATE_SHAKING] else challenged
	var bids := [{"pid": 3, "count": 2, "face": 5}, BID] if state == STATE_BIDDING else [{"pid": 3, "count": 2, "face": 5}, BID,
		{"pid": 5, "count": 6, "face": 5}, {"pid": 6, "count": 10, "face": 4}, challenged]
	if state == STATE_PEEK or state == STATE_SHAKING:
		bid = {}
		bids = []
	var total := 27
	hud.set_info(total, bid, LiarsDiceHud.bid_line(bid, NAMES.get(bid.get("pid"), "?"), false), LiarsDiceHud.bids_line(bids),
		LiarsDiceHud.turn_info_text(NAMES.get(current, ""), current == ME, not bid.is_empty()), "你:5 颗骰子")
	if state in [STATE_COUNTING, STATE_LOST]:
		var rows := _rows().map(func(r: Dictionary) -> Dictionary: return {"name": "你" if r["pid"] == ME else NAMES[r["pid"]], "dice": r["dice"]})
		hud.show_reveal(rows, CHALLENGE["face"], CHALLENGE["count"])
		var order := LiarsDiceScreenState.count_order(_rows(), CHALLENGE["face"])
		var upto := COUNTED if state == STATE_COUNTING else order.size()
		for i in upto:
			hud.reveal_mark(order[i][0] - 1, order[i][1])
		hud.set_reveal_count(upto, CHALLENGE["count"])
		if state == STATE_LOST:
			hud.reveal_finish(false)
	for line in LOG:
		hud.log_event(line)
	var face_ok := {}
	for f in range(2, 7):
		face_ok[f] = LiarsDiceState.bid_error(4 if state == STATE_BIDDING else 1, f, bid, total) == ""
	var face := 5 if state == STATE_BIDDING else 2
	var count := 4 if state == STATE_BIDDING else 1
	hud.set_my_dice(DICE[ME], true, CHALLENGE["face"] if state in [STATE_COUNTING, STATE_LOST] else 0)
	match state:
		STATE_BIDDING:
			hud.set_turn("轮到你了 · 加注还是开?", true)
			hud.set_countdown(TURN_LEFT, Protocol.TURN_TIMEOUT, true)
			hud.set_picker(count, face, face_ok, true, true, true, true, true)
		STATE_SHAKING:
			hud.set_picker(count, face, face_ok, false, true, false, false, false)
			hud.log_event("—— 第 4 轮 · 场上 26 颗骰子 ——", UiTheme.BRASS)
		STATE_PEEK:
			hud.set_turn("等待 小熊 喊…", false)
			hud.set_picker(count, face, face_ok, false, true, false, false, false)
			hud.log_event("—— 第 4 轮 · 场上 26 颗骰子 ——", UiTheme.BRASS)
		STATE_COUNTING:
			hud.set_picker(count, face, face_ok, false, true, false, false, false)
			hud.announce("开!", UiTheme.LIE, "阿狸 不信 老狐狸 的「11 个 5」", ANNOUNCE_HOLD)
			hud.log_event("阿狸 开 老狐狸 的「11 个 5」", UiTheme.LIE)
		STATE_LOST:
			hud.set_picker(count, face, face_ok, false, true, false, false, false)
			hud.announce("吹牛!", UiTheme.LIE, LiarsDiceScreenState.verdict_text({"actual": 10, "face": 5, "count": 11}), ANNOUNCE_HOLD,
				LiarsDiceHud.ANNOUNCE_Y_LOW)
			hud.log_event("老狐狸 丢了一颗骰子(还剩 4 颗)", UiTheme.LIE)
		STATE_OUT:
			hud.set_picker(count, face, face_ok, false, true, false, false, false)
			hud.announce("出局!", UiTheme.BLOOD, "%s 的骰子输光了" % NAMES[OUT_PID], ANNOUNCE_HOLD, LiarsDiceHud.ANNOUNCE_Y_LOW)
			hud.log_event("%s 的骰子输光了,出局" % NAMES[OUT_PID], UiTheme.BLOOD)
		STATE_SETTLEMENT:
			hud.set_away_from_seat(true)
			var rows := [{"pid": 2, "name": NAMES[2], "place": 1, "fate": "winner", "dice": 3},
				{"pid": 1, "name": NAMES[1], "place": 2, "fate": "out", "dice": 0},
				{"pid": 4, "name": NAMES[4], "place": 3, "fate": "out", "dice": 0},
				{"pid": 6, "name": NAMES[6], "place": 4, "fate": "left", "dice": 0},
				{"pid": 3, "name": NAMES[3], "place": 5, "fate": "out", "dice": 0},
				{"pid": 5, "name": NAMES[5], "place": 6, "fate": "out", "dice": 0}]
			settlement = LiarsDiceSettlement.new(NAMES[2], rows, false)
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

func view(name: String) -> Transform3D:
	# dice_seat:自己座位的越肩;dice_overview:观战俯视;dice_close:骰盅与骰子的特写;dice_peek:第一人称偷看时视线压低
	match name:
		"dice_overview":
			return world.overview_view()
		"dice_close":
			return LiarsDiceLayout.close_view(world, LOSER)
		"dice_peek":
			return LiarsDiceLayout.peek_view(world, ME)
	return world.third_person_view(ME)
