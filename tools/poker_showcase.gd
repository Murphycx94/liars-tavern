class_name PokerShowcase
extends Node
# 截图与性能用的德州展台(tools/shot.gd --poker-showcase、tools/perf_probe.gd --showcase=poker):
# 德州桌坐满 8 位酒客,5 张公共牌、2 人亮牌、2 人弃牌、各家筹码与本轮下注、2 个底池、庄家按钮、自己的两张手牌。
# 用假视图数据走与德州牌桌相同的对账接口(PokerChips.sync / PokerCards.sync),机位取自 TableWorld。
# worst_case 为真时每摞筹码、每处下注都摆满(40 枚)、底池 7 个:约 900 枚筹码,性能对比用的最坏情况。
# stage_hud 再用同一份假视图喂 PokerHud / BetControls / 铭牌 / 摊牌面板(规格 §8 截图验收),HUD_STATES 列出底部区域的几种状态,
# settlement 另在 HUD 上盖散局结算面板(10 行,其中 2 人已离开,列表要滚动)。

const ShowcaseSpecies := preload("res://tools/showcase_species.gd")

const ME := 1
const SEATS := 8
const BUTTON := 4
const SMALL_BLIND_PID := 5
const BIG_BLIND_PID := 6
const ACTOR := 8                # 3D 里前倾的行动者;HUD 的 bet 状态下行动者改成自己
const HAND_NUMBER := 12
const SETTLE := 3.0   # 秒:登场动画与登场的烟(Fx.smoke_puff 2.8 秒)都散了再拍
const WORST_AMOUNT := 1000000   # 远超每摞显示上限(40 枚)
const WORST_POTS := 7           # 8 人全下额度各不相同时最多 7 个底池
const BET_STATE := "bet"
const SPECTATE_STATE := "spectate"
const SETTLEMENT_STATE := "settlement"
const HUD_STATES := [BET_STATE, "wait", "showdown", "bust", SPECTATE_STATE, "waiting", "away", SETTLEMENT_STATE, "next", "next_wait"]
const LEFT_ROWS := [["早退的猫", 0, 2, -4000], ["路过的鸭", 3480, 1, 1480]]   # 散局前离开的人:名字、筹码、领取、盈亏
const NAMES := {1: "我", 2: "阿狸", 3: "酒馆常客", 4: "一个名字非常非常长的客人", 5: "小熊", 6: "狼叔", 7: "猪猪侠", 8: "老狐狸"}
const TURN_LEFT := 23.0
const BUST_LEFT := 4.0
const BUST_TOTAL := 6.0
const ANNOUNCE_HOLD := 30.0     # 宣告停住等截图
const LOG_LINES := ["猪猪侠 弃牌", "狼叔 全下 960", "一个名字非常非常长的客人 加注到 200", "小熊 跟注 200",
	"转牌 · 公共牌 4 张", "河牌 · 公共牌 5 张"]

var world: TableWorld
var chips: PokerChips
var cards: PokerCards
var worst_case := false
var hud: PokerHud = null
var labels: WorldLabels = null
var settlement: PokerSettlement = null


func build(tavern: Tavern) -> void:
	await CardFaces.build(self)
	await PokerFaces.build(self)
	Card3D.refresh_materials()
	world = TableWorld.new(tavern)
	tavern.table_root.add_child(world)
	# 同 main.apply_table_mode(德州):桌子放大,收起烛台与目标牌立牌(tools 里不能引用 main)
	world.configure_table(SeatLayout.POKER_TABLE_RADIUS)
	tavern.set_table_decor_visible(false)
	world.cards.set_stand_visible(false)
	world.arrange(ShowcaseSpecies.players(range(1, SEATS + 1)), ME, true, false)
	chips = PokerChips.new(world)
	cards = PokerCards.new(world)
	world.poker_root.add_child(chips)
	world.poker_root.add_child(cards)
	var players := _players()
	chips.sync(players, _pots())
	chips.place_button(BUTTON)
	cards.sync(range(1, SEATS + 1), players, _board(), ME, [PokerCard.make(PokerCard.ACE, PokerCard.SPADES),
		PokerCard.make(PokerCard.KING, PokerCard.HEARTS)])
	await get_tree().create_timer(SETTLE).timeout
	_pose()


func _players() -> Array:
	# 两人亮牌(3 号、6 号全下)、两人弃牌(2 号、7 号),其余还在本手中;筹码多寡不一,各种面额都看得到
	var c := func(rank: int, suit: int) -> int: return PokerCard.make(rank, suit)
	var rows := [
		[1, 1840, 200, PokerRules.STATUS_ACTIVE, []],
		[2, 2650, 0, PokerRules.STATUS_FOLDED, []],
		[3, 0, 0, PokerRules.STATUS_ALLIN, [c.call(PokerCard.QUEEN, PokerCard.DIAMONDS), c.call(PokerCard.QUEEN, PokerCard.CLUBS)]],
		[4, 5370, 200, PokerRules.STATUS_ACTIVE, []],
		[5, 960, 200, PokerRules.STATUS_ACTIVE, []],
		[6, 0, 0, PokerRules.STATUS_ALLIN, [c.call(PokerCard.JACK, PokerCard.HEARTS), c.call(10, PokerCard.HEARTS)]],
		[7, 12480, 0, PokerRules.STATUS_FOLDED, []],
		[8, 3110, 80, PokerRules.STATUS_ACTIVE, []],
	]
	return rows.map(func(row: Array) -> Dictionary:
		return {"pid": row[0], "name": NAMES[row[0]], "stack": WORST_AMOUNT if worst_case else row[1],
			"bet": WORST_AMOUNT if worst_case else row[2], "committed": row[2] + 220, "status": row[3], "shown": row[4],
			"left": false, "buyins": 1, "net": row[1] + row[2] + 220 - PokerRules.STARTING_STACK})


func _pots() -> Array:
	if worst_case:
		var all := range(1, SEATS + 1)
		return range(WORST_POTS).map(func(_i): return {"amount": WORST_AMOUNT, "eligible": all})
	return [{"amount": 2400, "eligible": [1, 3, 4, 5, 6, 8]}, {"amount": 860, "eligible": [1, 4, 5, 8]}]


func _board() -> Array:
	return [PokerCard.make(PokerCard.QUEEN, PokerCard.HEARTS), PokerCard.make(9, PokerCard.HEARTS),
		PokerCard.make(4, PokerCard.SPADES), PokerCard.make(PokerCard.KING, PokerCard.CLUBS),
		PokerCard.make(2, PokerCard.DIAMONDS)]


func _pose() -> void:
	# 演出里会出现的几种姿态:行动者前倾、亮牌的人一个得意一个发愁、弃牌的人发愁
	world.look_all_at(Vector3(0, SeatLayout.TABLE_TOP + 0.1, 0))
	world.patrons[8].set_active(true)
	world.patrons[3].set_expression("smug")
	world.patrons[6].set_expression("worried")
	world.patrons[2].set_expression("worried")
	cards.highlight([PokerCard.make(PokerCard.QUEEN, PokerCard.DIAMONDS), PokerCard.make(PokerCard.QUEEN, PokerCard.CLUBS),
		PokerCard.make(PokerCard.QUEEN, PokerCard.HEARTS)])


# —— HUD(规格 §6.1–6.5,用上面同一份假数据)——

func stage_hud(ui_root: Control, camera: Camera3D, state: String) -> void:
	# 在 ui_root 下摆出整套 HUD:铭牌挂在酒客头顶(WorldLabels)、四角面板、底部区域按 state 切换
	clear_hud()
	if not HUD_STATES.has(state):
		push_warning("unknown hud state %s (known: %s)" % [state, ", ".join(HUD_STATES)])
		return
	labels = WorldLabels.new(camera)
	ui_root.add_child(labels)
	hud = PokerHud.new()
	ui_root.add_child(hud)
	var pub := public_view(state)
	_stage_nameplates(pub)
	hud.set_header(pub["mode"], pub["blinds"], pub["hand"])
	hud.set_pots(pub["pots"])
	hud.set_board(pub["board"])
	hud.set_host(true)
	hud.set_my_status(NAMES[ME], _me(state))
	hud.set_my_hole(_my_hole())
	hud.set_my_best(HandEvaluator.evaluate(_my_hole() + _board(), false)["detail"])
	for line in LOG_LINES:
		hud.log_event(line)
	_stage_bottom(pub, state)
	if state == SETTLEMENT_STATE:
		settlement = PokerSettlement.new(_results(), true)
		ui_root.add_child(settlement)


func clear_hud() -> void:
	for node in [hud, labels, settlement]:
		if node != null:
			node.get_parent().remove_child(node)
			node.free()
	hud = null
	labels = null
	settlement = null


func public_view(state: String) -> Dictionary:
	# 规格 §4.6 的公共视图(假数据):bet 状态下轮到自己(要跟 120),wait 状态下轮到 8 号
	var actor := ME if state == "bet" else ACTOR
	var players := _players()
	var pub := {"mode": GameMode.SHORT_DECK, "hand": HAND_NUMBER, "phase": "betting", "street": PokerRules.RIVER,
		"board": _board(), "pots": _pots(), "button": BUTTON, "sb": SMALL_BLIND_PID, "bb": BIG_BLIND_PID,
		"current_pid": actor, "current_bet": 200, "blinds": [PokerRules.SMALL_BLIND, PokerRules.BIG_BLIND],
		"seats": range(1, SEATS + 1), "players": players, "turn_time_left": TURN_LEFT, "ending": false, "results": []}
	var me: Dictionary = players[0]
	if state == "bet":
		me["bet"] = 80
	var to_call: int = pub["current_bet"] - me["bet"]
	pub["actions"] = {"pid": actor, "to_call": to_call, "call_amount": to_call, "can_check": to_call == 0, "can_raise": true,
		"can_allin": true, "min_raise_to": pub["current_bet"] * 2, "max_raise_to": me["bet"] + me["stack"]}
	return pub


func _me(state: String) -> Dictionary:
	var me: Dictionary = _players()[0]
	match state:
		"bust":
			me.merge({"status": PokerRules.STATUS_BUSTED, "stack": 0, "net": -2000}, true)
		"spectate":
			me.merge({"status": PokerRules.STATUS_SPECTATING, "stack": 0, "net": -4000, "buyins": 2}, true)
		"waiting":
			me.merge({"status": PokerRules.STATUS_WAITING, "stack": 2000, "net": -2000, "buyins": 2}, true)
		"away":
			me["status"] = PokerRules.STATUS_AWAY
	return me


func _my_hole() -> Array:
	return [PokerCard.make(PokerCard.ACE, PokerCard.SPADES), PokerCard.make(PokerCard.KING, PokerCard.HEARTS)]


func _stage_nameplates(pub: Dictionary) -> void:
	for p in pub["players"]:
		var pid: int = p["pid"]
		if pid == ME:
			continue
		var plate := PokerNameplate.new(p["name"])
		plate.set_info(p, PokerNameplate.badge_for(pid, pub), pid == pub["current_pid"])
		labels.track("plate:%d" % pid, plate, world.nameplate_anchor.bind(pid))


func _stage_bottom(pub: Dictionary, state: String) -> void:
	match state:
		"bet", "wait":
			hud.set_bottom_mode(PokerHud.BOTTOM_BET)
			hud.controls.update(pub, ME)
			hud.set_turn("轮到你了" if state == "bet" else "等待 %s 行动…" % NAMES[ACTOR], state == "bet")
			hud.set_countdown(TURN_LEFT, Protocol.TURN_TIMEOUT, true)
			if state == "bet":
				hud.announce("河牌", UiTheme.BRASS_BRIGHT, "", ANNOUNCE_HOLD)
		"showdown":
			hud.set_bottom_mode(PokerHud.BOTTOM_NONE)
			hud.set_showdown(_showdown_entries())
			hud.board_strip.highlight([PokerCard.make(PokerCard.QUEEN, PokerCard.HEARTS), PokerCard.make(9, PokerCard.HEARTS),
				PokerCard.make(PokerCard.KING, PokerCard.CLUBS)])
			hud.announce("%s 赢得 2,400" % NAMES[3], UiTheme.BRASS_BRIGHT, "三条 · Q", ANNOUNCE_HOLD)
		"bust":
			hud.set_bottom_mode(PokerHud.BOTTOM_BUST)
			hud.set_bust_countdown(BUST_LEFT, BUST_TOTAL)
		"spectate":
			hud.set_bottom_mode(PokerHud.BOTTOM_SPECTATE)
		"waiting":
			hud.set_bottom_mode(PokerHud.BOTTOM_WAITING)
		"away":
			hud.set_bottom_mode(PokerHud.BOTTOM_AWAY)
		"next", "next_wait":
			hud.set_bottom_mode(PokerHud.BOTTOM_NEXT if state == "next" else PokerHud.BOTTOM_NEXT_WAIT)
			hud.set_next_progress(3, 8)
			hud.set_bust_countdown(BUST_LEFT, PokerPacing.NEXT_HAND_TIMEOUT)
			hud.set_showdown(_showdown_entries())
		SETTLEMENT_STATE:
			hud.set_bottom_mode(PokerHud.BOTTOM_NONE)


func _results() -> Array:
	# 散局结算行(规格 §4.6 results):8 位在座的 + 2 位已离开的,超过 8 行让列表滚动
	var rows: Array = _players().map(func(p: Dictionary) -> Dictionary:
		return {"pid": p["pid"], "name": p["name"], "stack": p["stack"], "buyins": p["buyins"], "net": p["net"], "left": false})
	for row in LEFT_ROWS:
		rows.append({"pid": 0, "name": row[0], "stack": row[1], "buyins": row[2], "net": row[3], "left": true})
	return rows


func _showdown_entries() -> Array:
	# 摊牌面板最坏情况:8 个人都亮牌,牌型名用 HandEvaluator 算;3 号赢主池、6 号赢边池(赢家排在最前)
	var c := func(rank: int, suit: int) -> int: return PokerCard.make(rank, suit)
	var holes := {
		1: _my_hole(), 2: [c.call(7, PokerCard.CLUBS), c.call(7, PokerCard.DIAMONDS)],
		3: [c.call(PokerCard.QUEEN, PokerCard.DIAMONDS), c.call(PokerCard.QUEEN, PokerCard.CLUBS)],
		4: [c.call(PokerCard.ACE, PokerCard.HEARTS), c.call(3, PokerCard.HEARTS)],
		5: [c.call(10, PokerCard.SPADES), c.call(PokerCard.JACK, PokerCard.SPADES)],
		6: [c.call(PokerCard.JACK, PokerCard.HEARTS), c.call(10, PokerCard.HEARTS)],
		7: [c.call(4, PokerCard.CLUBS), c.call(4, PokerCard.DIAMONDS)], 8: [c.call(2, PokerCard.SPADES), c.call(2, PokerCard.CLUBS)],
	}
	var won := {3: 2400, 6: 860}
	var entries := []
	for pid in [3, 6, 1, 2, 4, 5, 7, 8]:
		entries.append({"name": NAMES[pid], "cards": holes[pid], "hand_name": HandEvaluator.evaluate(holes[pid] + _board(), false)["detail"],
			"won": won.get(pid, 0)})
	return entries
