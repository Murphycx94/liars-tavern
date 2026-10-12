class_name BlackjackDirector
extends Node
# 21 点演出导演:把每种事件(设计稿 §3)翻译成镜头、酒客动作、牌与筹码的动画(BjCards / BjChips)、音效、宣告与日志。
# 每段演出的实际时长不超过 BlackjackPacing 的预算(房主据此延长计时),由 test_blackjack_director 读取这里与资产类的
# 节奏常量来保证。机位同德州:自己座位的越肩 / 第一人称(V 切换),没登场的人(中途加入)用观战俯视。


signal event_started(ev: Dictionary)

const INTRO_MOVE := BlackjackPacing.INTRO - 0.15
const CAMERA_MOVE := 0.9
const ROUND_SETTLE := 1.0        # 新一局:收牌、换座、运镜同时进行(≤ ROUND_STARTED 1.3)
const SHUFFLE_HOLD := 1.0        # 洗牌宣告(≤ SHUFFLE 1.2)
const STAND_PAUSE := 0.25
const REVEAL_HOLD := 0.35        # 翻开暗牌后停一下让人看清点数(翻牌 0.32 + 0.35 ≤ 0.8)
const SETTLE_HOLD := 0.35        # 结算筹码飞完再停一下(1.15 + 0.35 ≤ 1.8)
const ROUND_OVER_PAUSE := 0.3
const LEFT_PAUSE := 0.25
const SESSION_OVER_HOLD := 2.4
const FACES_WAIT_MAX := 10.0
const TABLE_FOCUS := BjLayout.TABLE_FOCUS
const MODE_SEAT := "seat"
const MODE_OVERVIEW := "overview"
const MODE_ORBIT := "orbit"

var screen: Node        # BlackjackScreen
var app: Node
var world: TableWorld
var cards: BjCards
var chips: BjChips
var rig: CameraRig
var hud: BjHud
var seat_camera: SeatCamera
var _mode := ""
var _settled := false
var _camera_serial := 0


func _init(p_screen: Node, p_app: Node, p_hud: BjHud) -> void:
	screen = p_screen
	app = p_app
	hud = p_hud
	world = p_screen.world
	cards = p_screen.cards
	chips = p_screen.chips
	rig = app.tavern.camera_rig
	var path = app.get("settings_path")
	seat_camera = SeatCamera.new(rig, world, screen.my_pid, path if path is String else Settings.PATH)
	add_child(seat_camera)


# —— 纯逻辑 ——

static func action_text(ev: Dictionary) -> String:
	# 日志里的一步:「要牌 → 18」「停牌(超时)」「加倍 → 21」「分牌」「投降」
	var total: Variant = ev.get("total")
	var tail := ""
	if total is int:
		tail = " → 爆牌 %d" % total if Untrusted.flag(ev.get("bust")) else " → %d" % total
	match ev.get("type", ""):
		"hit":
			return "要牌" + tail
		"double":
			return "加倍" + tail
		"stand":
			return "停牌" + ("(超时)" if Untrusted.flag(ev.get("timeout")) else "")
		"split":
			return "分牌(A 各补一张)" if Untrusted.flag(ev.get("aces")) else "分牌"
		"surrender":
			return "投降,收回一半"
	return str(ev.get("type", "?"))


static func my_result(rows: Array, my_pid: int) -> Dictionary:
	# 自己这一局的总结 {"net", "outcomes"}:没有自己的手时 outcomes 为空
	var net := 0
	var outcomes := []
	for row in rows:
		if row is Dictionary and Untrusted.same(row.get("pid"), my_pid) and row.get("bet") is int and row.get("payout") is int:
			net += row["payout"] - row["bet"]
			outcomes.append(row.get("outcome", ""))
	return {"net": net, "outcomes": outcomes}


static func result_title(result: Dictionary) -> Dictionary:
	# 自己的大字宣告 {"text", "color"}:黑杰克 / 赢 / 平手 / 输 / 爆牌;多手看总盈亏
	var outcomes: Array = result["outcomes"]
	var net: int = result["net"]
	if outcomes.is_empty():
		return {}
	if outcomes.size() == 1:
		match outcomes[0]:
			BjRules.OUTCOME_BLACKJACK:
				return {"text": "黑杰克!", "color": UiTheme.BRASS_BRIGHT}
			BjRules.OUTCOME_WIN:
				return {"text": "赢了!", "color": UiTheme.TRUTH}
			BjRules.OUTCOME_PUSH:
				return {"text": "平手", "color": UiTheme.PARCHMENT}
			BjRules.OUTCOME_BUST:
				return {"text": "爆牌", "color": UiTheme.LIE}
			BjRules.OUTCOME_SURRENDER:
				return {"text": "投降", "color": UiTheme.MUTED}
		return {"text": "输了", "color": UiTheme.LIE}
	if net > 0:
		return {"text": "赢了!", "color": UiTheme.TRUTH}
	return {"text": "平手", "color": UiTheme.PARCHMENT} if net == 0 else {"text": "输了", "color": UiTheme.LIE}


# —— 入口 ——

func intro() -> void:
	Sfx.play("whoosh")
	await settle_camera(INTRO_MOVE)


func play(ev: Dictionary) -> void:
	event_started.emit(ev)
	match ev.get("type", ""):
		"round_started":
			await _round_started(ev)
		"bet_placed":
			await _bet_placed(ev)
		"bet_skipped":
			screen.note_event(ev)
			hud.log_event("%s 这局不玩%s" % [screen.name_of(ev.get("pid")), "(超时)" if Untrusted.flag(ev.get("timeout")) else ""],
				UiTheme.MUTED)
		"dealt":
			await _dealt(ev)
		"peek":
			await _peek(ev)
		"turn":
			screen.set_current(ev)
		"hit", "double":
			await _card(ev)
		"stand":
			screen.note_event(ev)
			hud.log_event("%s %s" % [screen.name_of(ev.get("pid")), action_text(ev)], UiTheme.PARCHMENT_DIM)
			await _wait(STAND_PAUSE)
		"split":
			await _split(ev)
		"surrender":
			screen.note_event(ev)
			hud.log_event("%s %s" % [screen.name_of(ev.get("pid")), action_text(ev)], UiTheme.MUTED)
			_express(ev.get("pid"), "worried")
			await cards.surrender(_pid(ev), _int(ev, "hand"))
		"dealer_reveal":
			await _dealer_reveal(ev)
		"dealer_hit":
			await _dealer_hit(ev)
		"settled":
			await _settle_round(ev)
		"round_over":
			screen.note_event(ev)
			for pid in (ev["busted"] if ev.get("busted") is Array else []):
				hud.log_event("%s 筹码不够下注了" % screen.name_of(pid), UiTheme.LIE)
			screen.refresh_hud()
			await _wait(ROUND_OVER_PAUSE)
		"rebuy":
			await _rebuy(ev)
		"away", "sit_in":
			screen.note_event(ev)
			hud.log_event(("%s 离座(连续超时)" if Untrusted.same(ev["type"], "away") else "%s 回到牌桌") % screen.name_of(ev.get("pid")),
				UiTheme.MUTED)
			screen.refresh_hud()
		"player_joined":
			screen.note_event(ev)
			Sfx.play("join")
			hud.log_event("%s 走进了酒馆,下一局入座" % screen.name_of(ev.get("pid")), UiTheme.BRASS_BRIGHT)
			screen.refresh_hud()
		"player_left":
			await _player_left(ev)
		"ending":
			screen.note_event(ev)
			hud.set_ending(true)
			hud.announce(BjHud.ENDING_TEXT, UiTheme.BRASS_BRIGHT, "房主宣布散局", 1.0)
			hud.log_event("房主宣布散局:本局结束后结算", UiTheme.BRASS)
		"session_over":
			await _session_over(ev)


# —— 一局 ——

func _round_started(ev: Dictionary) -> void:
	screen.begin_round(ev)
	var number := _int(ev, "round")
	hud.announce("第 %d 局" % number, UiTheme.BRASS_BRIGHT, "请下注", 0.8)
	hud.log_event("—— 第 %d 局 ——" % number, UiTheme.BRASS)
	cards.sweep()
	settle_camera(CAMERA_MOVE)
	await _wait(ROUND_SETTLE)
	if Untrusted.flag(ev.get("shuffled")):
		hud.announce("洗牌", UiTheme.BRASS_BRIGHT, "牌鞋快发完了,重新洗 %d 副牌" % BjRules.DECKS, 0.6)
		hud.log_event("重新洗牌", UiTheme.PARCHMENT_DIM)
		Sfx.play("sweep")
		await _wait(SHUFFLE_HOLD)


func _bet_placed(ev: Dictionary) -> void:
	screen.note_event(ev)
	var pid := _pid(ev)
	hud.log_event("%s 下注 %s" % [screen.name_of(pid), ChipText.format(_int(ev, "amount"))], UiTheme.PARCHMENT)
	_reach(pid)
	await chips.place_bet(pid, 0, _int(ev, "amount"), _int(ev, "stack"))


func _dealt(ev: Dictionary) -> void:
	await _ensure_faces()
	screen.note_event(ev)
	var order: Array = ev["order"] if ev.get("order") is Array else []
	var hands: Dictionary = ev["hands"] if ev.get("hands") is Dictionary else {}
	hud.log_event("发牌 · %d 人" % order.size(), UiTheme.PARCHMENT_DIM)
	world.look_all_at(TABLE_FOCUS)
	await cards.deal(order, hands, ev["dealer_up"] if PokerCard.is_card(ev.get("dealer_up")) else CardFaces.BACK)
	screen.refresh_hud()
	for pid in order:
		var cards_of: Array = hands.get(pid, []) if hands.get(pid) is Array else []
		if cards_of.size() == 2 and cards_of.all(PokerCard.is_card) and BjScore.is_natural(cards_of):
			hud.log_event("%s 黑杰克!" % screen.name_of(pid), UiTheme.BRASS_BRIGHT)
			cards.glow_hand(pid, 0, BjRules.OUTCOME_BLACKJACK)
			if Untrusted.same(pid, screen.my_pid):
				hud.announce("黑杰克!", UiTheme.BRASS_BRIGHT, "", 0.5)
				Sfx.play("win")


func _peek(ev: Dictionary) -> void:
	screen.note_event(ev)
	hud.log_event("庄家看了一眼暗牌", UiTheme.PARCHMENT_DIM)
	await cards.peek()
	if Untrusted.flag(ev.get("blackjack")):
		hud.announce("庄家黑杰克!", UiTheme.LIE, "", 0.6)
		rig.shake(0.3)


func _card(ev: Dictionary) -> void:
	screen.note_event(ev)
	var pid := _pid(ev)
	var double: bool = Untrusted.same(ev.get("type"), "double")
	hud.log_event("%s %s" % [screen.name_of(pid), action_text(ev)], UiTheme.BRASS_BRIGHT if double else UiTheme.PARCHMENT)
	_reach(pid)
	if double:
		await chips.place_bet(pid, _int(ev, "hand"), _int(ev, "bet"), _int(ev, "stack"), cards.hand_count(pid))
	await cards.add_card(pid, _int(ev, "hand"), _int(ev, "card"), double)
	screen.refresh_hud()
	if Untrusted.flag(ev.get("bust")):
		_express(pid, "worried")
		cards.glow_hand(pid, _int(ev, "hand"), BjRules.OUTCOME_BUST)
		if pid == screen.my_pid:
			hud.announce("爆牌!", UiTheme.LIE, "", 0.4)
			Sfx.play("thud")
	elif Untrusted.same(ev.get("total"), BjRules.BLACKJACK) and pid == screen.my_pid:
		hud.announce("21 点!", UiTheme.BRASS_BRIGHT, "", 0.4)


func _split(ev: Dictionary) -> void:
	screen.note_event(ev)
	var pid := _pid(ev)
	var hand := _int(ev, "hand")
	hud.log_event("%s %s" % [screen.name_of(pid), action_text(ev)], UiTheme.BRASS_BRIGHT)
	_reach(pid)
	var pair: Array = ev["cards"] if ev.get("cards") is Array else []
	chips.split_bet(pid, hand, _int(ev, "bet"), _int(ev, "stack"))
	if pair.size() == 2 and pair[0] is Array and pair[1] is Array:
		await cards.split(pid, hand, pair[0], pair[1])
	screen.refresh_hud()


func _dealer_reveal(ev: Dictionary) -> void:
	screen.note_event(ev)
	screen.set_current(null)
	world.look_all_at(TABLE_FOCUS)
	await cards.reveal_hole(_int(ev, "card"))
	screen.refresh_hud()
	var all: Array = ev["cards"] if ev.get("cards") is Array else []
	var natural := all.size() == 2 and all.all(PokerCard.is_card) and BjScore.is_natural(all)
	hud.log_event("庄家翻开暗牌 · %s" % ("黑杰克" if natural else str(_int(ev, "total"))), UiTheme.BRASS)
	await _wait(REVEAL_HOLD)


func _dealer_hit(ev: Dictionary) -> void:
	screen.note_event(ev)
	await cards.dealer_hit(_int(ev, "card"))
	screen.refresh_hud()
	if Untrusted.flag(ev.get("bust")):
		hud.announce("庄家爆牌!", UiTheme.TRUTH, "", 0.4)
		hud.log_event("庄家要牌 → 爆牌 %d" % _int(ev, "total"), UiTheme.TRUTH)
		for pid in world.patrons:
			if _has_live_hand(pid):   # 只有还在这一局里、没爆没投降的人高兴
				world.patrons[pid].set_expression("happy")
	else:
		hud.log_event("庄家要牌 → %d" % _int(ev, "total"), UiTheme.PARCHMENT_DIM)


func _settle_round(ev: Dictionary) -> void:
	screen.note_event(ev)
	screen.set_current(null)
	var rows: Array = ev["hands"] if ev.get("hands") is Array else []
	var winners := {}
	for row in rows:
		if not row is Dictionary or not row.get("pid") is int:
			continue
		cards.glow_hand(row["pid"], _int(row, "hand"), str(row.get("outcome", "")))
		if [BjRules.OUTCOME_WIN, BjRules.OUTCOME_BLACKJACK].has(row.get("outcome")):
			winners[row["pid"]] = true
	for pid in winners:
		if world.patrons.has(pid):
			world.patrons[pid].celebrate()
	var mine := my_result(rows, screen.my_pid)
	var title := result_title(mine)
	if not title.is_empty():
		var net: int = mine["net"]
		hud.announce(title["text"], title["color"], ("盈亏 " + ChipText.signed(net)) if net != 0 else "", 0.9)
		if net > 0:
			Sfx.play("win")
	_log_results(rows)
	screen.refresh_hud()
	# 已离开的人(本局里走了)筹码不再摆回他的空座位
	var stacks: Dictionary = ev["stacks"] if ev.get("stacks") is Dictionary else {}
	stacks = stacks.duplicate()
	for pid in stacks.keys():
		if screen.state.has_left(pid):
			stacks.erase(pid)
	await chips.settle(rows.filter(func(row) -> bool: return row is Dictionary and not screen.state.has_left(row.get("pid"))), stacks)
	await _wait(SETTLE_HOLD)


func _log_results(rows: Array) -> void:
	# 每人一行:「甲 赢 +200」「乙 爆牌 −100」;分牌的人合计
	var nets := {}
	var order := []
	for row in rows:
		if not row is Dictionary or not row.get("pid") is int:
			continue
		if not nets.has(row["pid"]):
			order.append(row["pid"])
			nets[row["pid"]] = 0
		nets[row["pid"]] += _int(row, "payout") - _int(row, "bet")
	for pid in order:
		var net: int = nets[pid]
		var color := UiTheme.TRUTH if net > 0 else (UiTheme.LIE if net < 0 else UiTheme.PARCHMENT_DIM)
		hud.log_event("%s %s" % [screen.name_of(pid), "平手" if net == 0 else ChipText.signed(net)], color)


func _has_live_hand(pid: int) -> bool:
	for hand in screen.state.hands_of(pid):
		if not hand["surrendered"] and not BjScore.is_bust(hand["cards"]):
			return true
	return false


# —— 座位 ——

func _rebuy(ev: Dictionary) -> void:
	screen.note_event(ev)
	var pid := _pid(ev)
	hud.log_event("%s 再领 %s" % [screen.name_of(pid), ChipText.format(_int(ev, "amount"))], UiTheme.TRUTH)
	_express(pid, "neutral")
	await chips.rebuy(pid, _int(ev, "stack"))
	screen.refresh_hud()


func _player_left(ev: Dictionary) -> void:
	screen.note_event(ev)
	var pid: Variant = ev.get("pid")
	if pid is int and screen.state.phase == "betting":
		chips.refund(pid, 0)   # 下注阶段押的注已退回(他也带着筹码走了),桌上的注一并收走;发了牌的手照常比
	hud.log_event("%s 离开了牌桌" % screen.name_of(pid), UiTheme.LIE)
	screen.drop_player(pid)
	if not pid is int or not world.patrons.has(pid):
		return
	Sfx.play("thud")
	world.remove_patron(pid)
	chips.remove_seat(pid)
	await _wait(LEFT_PAUSE)


func _session_over(ev: Dictionary) -> void:
	screen.set_current(null)
	_leave_rest(MODE_ORBIT)
	hud.announce("散局", UiTheme.BRASS_BRIGHT, "牌局结束,结算中", 1.8)
	hud.log_event("散局结算", UiTheme.BRASS_BRIGHT)
	var results: Array = ev["results"] if ev.get("results") is Array else []
	var winners := PokerDirector.top_ranked(results)
	world.celebrate(winners, hash(["blackjack", winners, results.size()]))
	var orbit := world.celebration_orbit(winners)
	rig.set_fill(orbit.get("fill", 0.0), 1.0)
	rig.orbit(orbit["center"], orbit["radius"], orbit["height"], orbit["speed"], 1.4, orbit.get("start", NAN), orbit.get("frame", 0.0))
	await _wait(SESSION_OVER_HOLD)
	screen.show_settlement(results)


# —— 机位(同德州)——

func is_at_seat() -> bool:
	return _settled and _mode == MODE_SEAT


func is_camera_at_rest() -> bool:
	return _settled


func camera_mode() -> String:
	return _mode


func wanted_mode() -> String:
	return MODE_OVERVIEW if screen.state.uses_overview(screen.my_pid) else MODE_SEAT


func settle_camera(duration := CAMERA_MOVE) -> void:
	var wanted := wanted_mode()
	if wanted == _mode and _settled:
		return
	_leave_rest(wanted)
	var serial := _camera_serial
	if wanted == MODE_SEAT:
		seat_camera.enter(duration)
	else:
		rig.set_fill(0.0, duration)
		rig.move_to(world.overview_view(), duration)
	await _wait(duration)
	if serial == _camera_serial:
		_settled = true
		rig.parallax_enabled = wanted == MODE_SEAT


func _leave_rest(mode: String) -> void:
	_mode = mode
	_settled = false
	_camera_serial += 1
	rig.parallax_enabled = false
	seat_camera.leave()


func toggle_camera_mode() -> void:
	var on := seat_camera.toggle()
	app.toast(SeatCamera.toast_text(on, seat_camera.is_seated()), UiTheme.PARCHMENT)


# —— 工具 ——

func _reach(pid: Variant) -> void:
	if pid is int and world.patrons.has(pid):
		world.patrons[pid].reach_toward_center()


func _express(pid: Variant, kind: String) -> void:
	if pid is int and world.patrons.has(pid):
		world.patrons[pid].set_expression(kind)


func _ensure_faces() -> void:
	var waited := 0.0
	while not PokerFaces.is_built() and waited < FACES_WAIT_MAX and is_inside_tree():
		await get_tree().process_frame
		waited += get_process_delta_time()


static func _pid(ev: Dictionary) -> int:
	return ev["pid"] if ev.get("pid") is int else -1


static func _int(ev: Dictionary, key: String) -> int:
	return ev[key] if ev.get(key) is int else 0


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
