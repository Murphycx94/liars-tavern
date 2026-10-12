class_name BlackjackShowcase
extends Node
# 截图用的 21 点展台(tools/shot.gd --blackjack-showcase):德州大桌坐满 7 位酒客,庄家一张明牌一张暗牌(或翻开要过牌),
# 自己分成两手、有人加倍(横放的第三张)、有人这局不玩、有人爆牌,各家筹码堆与每手的下注。
# 用假视图数据走与 21 点牌桌相同的对账接口(BjChips.sync / BjCards.sync),机位取自 TableWorld。
# stage_hud 再用同一份假视图喂 BjHud / BjControls / 铭牌(HUD_STATES 列出几种状态),settlement 另盖散局结算面板。

const ShowcaseSpecies := preload("res://tools/showcase_species.gd")

const ME := 1
const SEATS := 7
const ACTOR := 4
const ROUND := 9
const SETTLE := 3.0
const STATE_BET := "bet"
const STATE_PLAY := "play"
const STATE_WAIT := "wait"
const STATE_SETTLED := "settled"
const STATE_BUSTED := "busted"
const STATE_JOINING := "joining"
const STATE_SETTLEMENT := "settlement"
const HUD_STATES := [STATE_BET, STATE_PLAY, STATE_WAIT, STATE_SETTLED, STATE_BUSTED, STATE_JOINING, STATE_SETTLEMENT]
const NAMES := {1: "我", 2: "阿狸", 3: "酒馆常客", 4: "一个名字非常非常长的客人", 5: "小熊", 6: "狼叔", 7: "猪猪侠"}
const LOG_LINES := ["—— 第 9 局 ——", "小熊 下注 200", "发牌 · 6 人", "阿狸 要牌 → 爆牌 25", "酒馆常客 加倍 → 20",
	"我 分牌"]

var world: TableWorld
var chips: BjChips
var cards: BjCards
var hud: BjHud = null
var labels: WorldLabels = null
var settlement: PokerSettlement = null
var revealed := false   # 庄家暗牌翻开了(settled 状态)


static func c(rank: int, suit: int) -> int:
	return PokerCard.make(rank, suit)


func build(tavern: Tavern) -> void:
	await CardFaces.build(self)
	await PokerFaces.build(self)
	Card3D.refresh_materials()
	world = TableWorld.new(tavern)
	tavern.table_root.add_child(world)
	world.configure_table(SeatLayout.POKER_TABLE_RADIUS)
	tavern.set_table_decor_visible(false)
	world.cards.set_stand_visible(false)
	world.arrange(ShowcaseSpecies.players(range(1, SEATS + 1)), ME, true, false)
	chips = BjChips.new(world)
	cards = BjCards.new(world)
	world.poker_root.add_child(chips)
	world.poker_root.add_child(cards)
	sync_table()
	await get_tree().create_timer(SETTLE).timeout
	world.look_all_at(BjLayout.TABLE_FOCUS)
	world.patrons[ACTOR].set_active(true)
	world.patrons[2].set_expression("worried")
	world.patrons[5].set_expression("happy")


func sync_table() -> void:
	var view := public_view(STATE_SETTLED if revealed else STATE_PLAY)
	chips.sync(view["players"])
	cards.sync(view["players"], view["dealer"])


func _hand(cards_of: Array, bet: int, extra := {}) -> Dictionary:
	var score := BjScore.evaluate(cards_of)
	return {"cards": cards_of, "bet": bet, "total": score["total"], "soft": score["soft"], "done": false, "doubled": false,
		"split": false, "surrendered": false, "natural": false, "outcome": "", "payout": 0}.merged(extra, true)


func _players(state: String) -> Array:
	var settled := state == STATE_SETTLED
	var win := func(bet: int) -> Dictionary: return {"outcome": BjRules.OUTCOME_WIN, "payout": bet * 2} if settled else {}
	var lose := {"outcome": BjRules.OUTCOME_LOSE, "payout": 0} if settled else {}
	var rows := [
		[1, 1500, BjRules.STATUS_PLAYING, [
			_hand([c(8, 0), c(3, 1), c(PokerCard.KING, 2)], 200, {"split": true, "done": true}.merged(win.call(200), true)),
			_hand([c(8, 3), c(9, 1)], 200, {"split": true}.merged(lose, true))]],
		[2, 2650, BjRules.STATUS_PLAYING, [_hand([c(PokerCard.KING, 0), c(5, 1), c(PokerCard.QUEEN, 3)], 100,
			{"done": true, "outcome": BjRules.OUTCOME_BUST if settled else ""})]],
		[3, 1760, BjRules.STATUS_PLAYING, [_hand([c(6, 2), c(4, 0), c(PokerCard.JACK, 1)], 240,
			{"doubled": true, "done": true}.merged(win.call(240), true))]],
		[4, 5370, BjRules.STATUS_PLAYING, [_hand([c(PokerCard.ACE, 2), c(6, 3)], 500, lose)]],
		[5, 960, BjRules.STATUS_PLAYING, [_hand([c(PokerCard.ACE, 1), c(PokerCard.KING, 3)], 200,
			{"natural": true, "done": true, "outcome": BjRules.OUTCOME_BLACKJACK if settled else "", "payout": 500 if settled else 0})]],
		[6, 3110, BjRules.STATUS_SKIP, []],
		[7, 12480, BjRules.STATUS_PLAYING, [_hand([c(9, 0), c(9, 2)], 1000, lose)]],
	]
	return rows.map(func(row: Array) -> Dictionary:
		var hands: Array = row[3]
		var stake := 0
		for hand in hands:
			stake += hand["bet"]
		return {"pid": row[0], "name": NAMES[row[0]], "stack": row[1], "status": row[2], "left": false, "buyins": 1,
			"bet": 0, "net": row[1] + stake - BjRules.STARTING_STACK, "hands": hands})


func public_view(state: String) -> Dictionary:
	var settled := state == STATE_SETTLED
	var dealer: Array = [c(10, 1), c(7, 0), c(PokerCard.KING, 2)] if settled else [c(10, 1)]
	var players := _players(state)
	var phase := "betting" if state in [STATE_BET, STATE_BUSTED, STATE_JOINING] else ("idle" if settled else "playing")
	if phase == "betting":
		for p in players:
			p["hands"] = []
			p["status"] = BjRules.STATUS_BET if p["pid"] in [3, 5, 7] else BjRules.STATUS_WAITING
			p["bet"] = 200 if p["status"] == BjRules.STATUS_BET else 0
	var actor := ME if state == STATE_PLAY else ACTOR
	var current: Variant = {"pid": actor, "hand": 1 if actor == ME else 0} if phase == "playing" else null
	return {"mode": GameMode.BLACKJACK, "round": ROUND, "phase": phase, "shoe_left": 214, "shoe_size": BjShoe.size(),
		"dealer": {"cards": dealer, "hidden": not settled and phase == "playing", "total": BjScore.total(dealer), "soft": false},
		"current": current, "seats": range(1, SEATS + 1), "players": players, "ending": false, "results": [],
		"actions": {"pid": actor, "hand": current["hand"], "hit": true, "stand": true, "double": true, "split": false,
			"surrender": false} if current != null else {}}


# —— HUD ——

func stage_hud(ui_root: Control, camera: Camera3D, state: String) -> void:
	clear_hud()
	if not HUD_STATES.has(state):
		push_warning("unknown hud state %s (known: %s)" % [state, ", ".join(HUD_STATES)])
		return
	revealed = state == STATE_SETTLED
	sync_table()
	labels = WorldLabels.new(camera)
	ui_root.add_child(labels)
	hud = BjHud.new()
	ui_root.add_child(hud)
	var pub := public_view(state)
	var model := BjScreenState.new()
	model.apply_public(pub)
	model.refresh_from_view(true)
	if state == STATE_BUSTED:
		model.rows[ME].merge({"status": BjRules.STATUS_BUSTED, "stack": 0, "net": -2000}, true)
	if state == STATE_JOINING:
		model.seats.erase(ME)
	for pid in model.seats:
		if pid == ME:
			continue
		var plate := BjNameplate.new(NAMES[pid])
		plate.set_plate(model.row(pid)["stack"], model.plate_status(pid), model.current_pid() == pid)
		labels.track("plate:%d" % pid, plate, world.nameplate_anchor.bind(pid))
	hud.set_header(ROUND, pub["shoe_left"], pub["shoe_size"])
	hud.set_dealer(model.dealer_label(), model.dealer_cards)
	hud.set_host(true)
	hud.set_my_status(NAMES[ME], model.row(ME))
	hud.set_my_hands(model.hands_of(ME), 1 if state == STATE_PLAY else -1)
	for line in LOG_LINES:
		hud.log_event(line)
	var bottom := model.bottom_mode(ME)
	hud.set_bottom(bottom)
	match state:
		STATE_BET:
			hud.controls.show_betting(1500, 200)
			hud.controls.set_turn("请下注", true)
			hud.controls.set_countdown(11.0, BlackjackPacing.BET_TIMEOUT)
		STATE_PLAY:
			hud.controls.show_play(model.legal(ME))
			hud.controls.set_turn("轮到你了 · 第 2 手", true)
			hud.controls.set_countdown(17.0, BlackjackPacing.PLAY_TIMEOUT)
		STATE_WAIT:
			hud.controls.set_mode(BjControls.MODE_HIDDEN)
			hud.controls.set_turn("等待 %s 决策…" % NAMES[ACTOR], false)
			hud.controls.set_countdown(12.0, BlackjackPacing.PLAY_TIMEOUT)
		STATE_SETTLED:
			hud.announce("赢了!", UiTheme.TRUTH, "盈亏 +0", 30.0)
	if state == STATE_SETTLEMENT:
		var results := []
		for p in public_view(STATE_SETTLED)["players"]:
			results.append({"pid": p["pid"], "name": p["name"], "stack": p["stack"], "buyins": 1, "net": p["net"], "left": false})
		settlement = PokerSettlement.new(results, true)
		ui_root.add_child(settlement)


func clear_hud() -> void:
	for node in [hud, labels, settlement]:
		if node != null:
			node.get_parent().remove_child(node)
			node.free()
	hud = null
	labels = null
	settlement = null
