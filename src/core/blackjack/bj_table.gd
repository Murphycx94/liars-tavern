class_name BjTable
extends RefCounted
# 21 点状态机(设计稿 2026-10-12-blackjack-design §2、§3):只在房主端运行,不依赖节点 / 网络 / UI。
# 动作方法返回 {"ok": bool, "error"?: String, "events"?: Array};座位变化直接返回事件数组。
# 一局:下注阶段(同时下注,没决定的人超时算「这局不玩」)→ 发牌(庄家明牌是 A / 10 点先看暗牌)→
# 按座位轮流打每一手 → 庄家翻暗牌、要到 17 → 逐手结算 → 两局之间。散局在两局之间或下注阶段立即结算,打牌中打完这一局。
# 筹码只在三处变:下注 / 加倍 / 分牌时押出去,结算时按 BjRules.payout 退回,再领时加 2000(庄家是无底的银行,不守恒)。


enum Phase { IDLE, BETTING, PLAYING, OVER }

var _rng: RandomNumberGenerator
var _shoe: BjShoe
var _players := {}          # pid -> 玩家记录:在座的人,含要到这一局结束才移出的离开者
var _seat_order := []       # 座位顺序 = 行动顺序;新人排在末尾
var _opening_seats := []    # 开局入座的人:第一局之前他们就有酒客
var _round_seats := []      # 本局(两局之间为上一局)开始时在座的人:桌上有他们的酒客;中途加入的要等下一局
var _order := []            # 本局下了注、发到牌的人(按座位)
var _departed := []         # 已移出座位的离开者 [{"pid", "stack", "buyins"}]
var _phase := Phase.IDLE
var _round := 0
var _ending := false
var _dealer := []           # 庄家的牌:[明牌, 暗牌, 补的牌…]
var _hole_shown := false
var _turn: Variant = null   # {"pid", "hand"}:正在决策的那一手;没有时为 null


func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng
	_shoe = BjShoe.new(rng)


# —— 测试钩子 ——

func rig(cards: Array) -> void:
	# 接下来按顺序发这些牌(发牌顺序:每人一张 → 庄家明牌 → 每人第二张 → 庄家暗牌,之后按要牌顺序)
	_shoe.rigged = cards.duplicate()


func set_stack(pid: int, stack: int) -> void:
	_players[pid]["stack"] = stack


# —— 座位 ——

func seat(pid: int) -> void:
	if _players.has(pid):
		return
	_players[pid] = _new_player()
	_seat_order.append(pid)
	_opening_seats.append(pid)


func add_player(pid: int) -> Array:
	# 中途加入:领 2000,排在末尾,下一局开始才登场;座位上限只数没离开的人
	# 同一个 pid 离开后又回来(连接 id 随机,极少见)不收:结算表里会有两行
	if _phase == Phase.OVER or _players.has(pid) or _seated_count() >= BjRules.MAX_SEATS \
			or _departed.any(func(gone: Dictionary) -> bool: return gone["pid"] == pid):
		return []
	_players[pid] = _new_player()
	_seat_order.append(pid)
	return [{"type": "player_joined", "pid": pid}]


func remove_player(pid: int) -> Array:
	# 离开或断线:不在本局里(两局之间、还没登场)→ 立即移出;下注阶段 → 押的注退回,这局不玩;
	# 打牌中 → 他没打完的手都停牌、照常和庄家比,本局结束后带着筹码移出
	if _phase == Phase.OVER or not _is_seated(pid):
		return []
	var p: Dictionary = _players[pid]
	p["left"] = true
	var events := [{"type": "player_left", "pid": pid}]
	if _phase == Phase.IDLE or not _round_seats.has(pid):
		_depart(pid)
		return events
	if _phase == Phase.BETTING:
		if p["status"] == BjRules.STATUS_BET:
			p["stack"] += p["bet"]
			p["bet"] = 0
		p["status"] = BjRules.STATUS_SKIP
		_deal_if_decided(events)
		return events
	var was_turn: bool = _turn != null and _turn["pid"] == pid
	for hand in p["hands"]:
		hand["done"] = true
	if was_turn:
		_advance(events)
	return events


func rebuy(pid: int) -> Dictionary:
	# 再领:只有筹码不够最小下注的人(busted)可以;下注阶段领了就能马上下注
	var error := _seat_error(pid)
	if error == "" and _players[pid]["status"] != BjRules.STATUS_BUSTED:
		error = "cannot_rebuy"
	if error != "":
		return _fail(error)
	var p: Dictionary = _players[pid]
	p["stack"] += BjRules.STARTING_STACK
	p["buyins"] += 1
	p["timeouts"] = 0
	p["status"] = BjRules.STATUS_WAITING
	return _ok([{"type": "rebuy", "pid": pid, "amount": BjRules.STARTING_STACK, "buyins": p["buyins"], "stack": p["stack"]}])


func sit_in(pid: int) -> Dictionary:
	# 挂机离座的人回到牌桌:下注阶段回来就能下注,否则等下一局
	var error := _seat_error(pid)
	if error == "" and _players[pid]["status"] != BjRules.STATUS_AWAY:
		error = "invalid_action"
	if error != "":
		return _fail(error)
	var p: Dictionary = _players[pid]
	p["timeouts"] = 0
	p["status"] = BjRules.STATUS_WAITING if p["stack"] >= BjRules.MIN_BET else BjRules.STATUS_BUSTED
	return _ok([{"type": "sit_in", "pid": pid}])


func request_end() -> Array:
	# 散局:两局之间或下注阶段(还没发牌)立即结算,押着的注退回;打牌中打完这一局再结算
	if _phase == Phase.OVER or _ending:
		return []
	_ending = true
	if _phase == Phase.PLAYING:
		return [{"type": "ending"}]
	for pid in _seat_order:
		var p: Dictionary = _players[pid]
		p["stack"] += p["bet"]
		p["bet"] = 0
	_turn = null
	_phase = Phase.OVER
	return [{"type": "session_over", "results": results()}]


# —— 一局 ——

func can_start_round() -> bool:
	# 两局之间,而且至少有一个人能下注(没离开、没离座、筹码够最小下注)
	if _phase != Phase.IDLE:
		return false
	for pid in _seat_order:
		var p: Dictionary = _players[pid]
		if _is_seated(pid) and p["status"] != BjRules.STATUS_AWAY and p["stack"] >= BjRules.MIN_BET:
			return true
	return false


func start_round() -> Array:
	# 开下注阶段:这时在座的人都登场(中途加入的也是);牌鞋剩得少就整鞋重洗
	if not can_start_round():
		return []
	_round += 1
	_phase = Phase.BETTING
	_turn = null
	_order = []
	_dealer = []
	_hole_shown = false
	var shuffled := _shoe.needs_shuffle()
	if shuffled:
		_shoe.shuffle()
	_round_seats = _seat_order.filter(_is_seated)
	for pid in _round_seats:
		var p: Dictionary = _players[pid]
		p["hands"] = []
		p["bet"] = 0
		if p["status"] != BjRules.STATUS_AWAY:
			p["status"] = BjRules.STATUS_WAITING if p["stack"] >= BjRules.MIN_BET else BjRules.STATUS_BUSTED
	return [{
		"type": "round_started", "round": _round, "seats": _round_seats.duplicate(), "shuffled": shuffled,
		"shoe_left": _shoe.remaining(),
	}]


func bet(pid: int, amount: Variant) -> Dictionary:
	var error := _decide_error(pid)
	if error == "" and not BjRules.is_valid_bet(amount, _players[pid]["stack"]):
		error = "invalid_amount"
	if error != "":
		return _fail(error)
	var p: Dictionary = _players[pid]
	p["stack"] -= amount
	p["bet"] = amount
	p["status"] = BjRules.STATUS_BET
	p["timeouts"] = 0
	var events := [{"type": "bet_placed", "pid": pid, "amount": amount, "stack": p["stack"]}]
	_deal_if_decided(events)
	return _ok(events)


func skip(pid: int) -> Dictionary:
	var error := _decide_error(pid)
	if error != "":
		return _fail(error)
	_players[pid]["status"] = BjRules.STATUS_SKIP
	_players[pid]["timeouts"] = 0
	var events := [{"type": "bet_skipped", "pid": pid, "timeout": false}]
	_deal_if_decided(events)
	return _ok(events)


func act(pid: int, action: String) -> Dictionary:
	var error := _seat_error(pid)
	if error == "" and not BjRules.PLAY_ACTIONS.has(action):
		error = "invalid_action"
	if error == "" and (_phase != Phase.PLAYING or _turn == null):
		error = "no_round"
	if error == "" and _turn["pid"] != pid:
		error = "not_your_turn"
	if error == "" and not legal_actions(pid).get(action, false):
		error = "invalid_action"
	if error != "":
		return _fail(error)
	_players[pid]["timeouts"] = 0
	return _ok(_play(pid, action, false))


func timeout_action() -> Dictionary:
	# 回合超时:下注阶段没决定的人都算这局不玩;打牌中当前这一手停牌。都记一次连续超时
	if _phase == Phase.OVER:
		return _fail("session_over")
	if _phase == Phase.BETTING:
		var events := []
		for pid in _deciders():
			var p: Dictionary = _players[pid]
			p["status"] = BjRules.STATUS_SKIP
			p["timeouts"] += 1
			events.append({"type": "bet_skipped", "pid": pid, "timeout": true})
		_deal(events)
		return _ok(events)
	if _phase != Phase.PLAYING or _turn == null:
		return _fail("no_round")
	var pid: int = _turn["pid"]
	_players[pid]["timeouts"] += 1
	return _ok(_play(pid, BjRules.STAND, true))


func legal_actions(pid: int) -> Dictionary:
	# 轮到他时 {"hand", "hit", "stand", "double", "split", "surrender"};不轮到他为 {}
	if _phase != Phase.PLAYING or _turn == null or _turn["pid"] != pid:
		return {}
	var p: Dictionary = _players[pid]
	var index: int = _turn["hand"]
	var hand: Dictionary = p["hands"][index]
	var cards: Array = hand["cards"]
	var two := cards.size() == 2
	var afford: bool = p["stack"] >= hand["bet"]
	return {
		"hand": index,
		BjRules.HIT: true,
		BjRules.STAND: true,
		BjRules.DOUBLE: two and afford,
		BjRules.SPLIT: two and afford and BjScore.same_value(cards[0], cards[1]) and p["hands"].size() < BjRules.MAX_HANDS,
		BjRules.SURRENDER: two and p["hands"].size() == 1 and not hand["split"],
	}


func results() -> Array:
	# 结算行(含已离开的):盈亏 = 筹码 − 领取次数 × 2000,按盈亏从高到低(同分按座位、离开的先后)。
	# 一局进行中也能调用(预览):押在桌上还没结算的注按原额算进筹码
	var rows := []
	for pid in _seat_order:
		var p: Dictionary = _players[pid]
		rows.append(_result_row(pid, p["stack"] + _committed(p), p["buyins"], p["left"]))
	for gone in _departed:
		rows.append(_result_row(gone["pid"], gone["stack"], gone["buyins"], true))
	var order := range(rows.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return rows[a]["net"] > rows[b]["net"] or (rows[a]["net"] == rows[b]["net"] and a < b))
	return order.map(func(i: int) -> Dictionary: return rows[i])


# —— 只读访问(视图层只用这些)——

func phase() -> Phase:
	return _phase


func round_number() -> int:
	return _round


func is_ending() -> bool:
	return _ending


func current() -> Variant:
	return _turn.duplicate() if _turn != null else null


func current_pid() -> Variant:
	return _turn["pid"] if _turn != null else null


func seat_order() -> Array:
	return _seat_order.duplicate()


func seats_with_patrons() -> Array:
	# 桌上有酒客的人:本局(两局之间为上一局)开始时在座、还没离开的;第一局之前是开局入座的人
	return (_round_seats if _round > 0 else _opening_seats).filter(_is_seated)


func round_seats() -> Array:
	return _round_seats.duplicate()


func player(pid: int) -> Dictionary:
	# 玩家公开信息的拷贝;已移出座位或不认识的 pid 返回 {}
	if not _players.has(pid):
		return {}
	var p: Dictionary = _players[pid]
	return {
		"stack": p["stack"], "status": p["status"], "left": p["left"], "buyins": p["buyins"], "bet": p["bet"],
		"net": p["stack"] + _committed(p) - p["buyins"] * BjRules.STARTING_STACK,
		"hands": p["hands"].map(_hand_view),
	}


func dealer_cards() -> Array:
	# 公开的庄家牌:暗牌翻开之前只有明牌
	if _dealer.is_empty():
		return []
	return _dealer.duplicate() if _hole_shown else [_dealer[0]]


func dealer_hidden() -> bool:
	# 桌上有一张还没翻开的暗牌
	return _dealer.size() >= 2 and not _hole_shown


func shoe_left() -> int:
	return _shoe.remaining()


func awaiting_bets() -> Array:
	return _deciders()


# —— 发牌、轮转、庄家、结算 ——

func _deal_if_decided(events: Array) -> void:
	if _phase == Phase.BETTING and _deciders().is_empty():
		_deal(events)


func _deal(events: Array) -> void:
	# 没人下注:这一局直接结束。否则每人一张 → 庄家明牌 → 每人第二张 → 庄家暗牌
	_order = _round_seats.filter(func(pid: int) -> bool:
		return _is_seated(pid) and _players[pid]["status"] == BjRules.STATUS_BET)
	if _order.is_empty():
		_end_round(events)
		return
	_phase = Phase.PLAYING
	var dealt := {}
	for pid in _order:
		var p: Dictionary = _players[pid]
		p["status"] = BjRules.STATUS_PLAYING
		p["hands"] = [_new_hand([], p["bet"])]
	for round in 2:
		for pid in _order:
			_players[pid]["hands"][0]["cards"].append(_shoe.draw())
		_dealer.append(_shoe.draw())
	for pid in _order:
		var hand: Dictionary = _players[pid]["hands"][0]
		hand["natural"] = BjScore.is_natural(hand["cards"])
		hand["done"] = hand["natural"]   # 黑杰克不用再决策
		dealt[pid] = hand["cards"].duplicate()
	events.append({"type": "dealt", "order": _order.duplicate(), "hands": dealt, "dealer_up": _dealer[0]})
	if BjScore.dealer_peeks(_dealer[0]):
		var blackjack := BjScore.is_natural(_dealer)
		events.append({"type": "peek", "blackjack": blackjack})
		if blackjack:
			for pid in _order:
				_players[pid]["hands"][0]["done"] = true
	_advance(events)


func _play(pid: int, action: String, timed_out: bool) -> Array:
	var p: Dictionary = _players[pid]
	var index: int = _turn["hand"]
	var hand: Dictionary = p["hands"][index]
	var events := []
	match action:
		BjRules.HIT:
			hand["cards"].append(_shoe.draw())
			_finish_if_21_or_bust(hand)
			events.append(_card_event("hit", pid, index, hand))
		BjRules.STAND:
			hand["done"] = true
			events.append({"type": "stand", "pid": pid, "hand": index, "timeout": timed_out})
		BjRules.DOUBLE:
			p["stack"] -= hand["bet"]
			hand["bet"] *= 2
			hand["doubled"] = true
			hand["cards"].append(_shoe.draw())
			hand["done"] = true
			events.append(_card_event("double", pid, index, hand).merged({"bet": hand["bet"], "stack": p["stack"]}))
		BjRules.SPLIT:
			events.append(_split(p, pid, index))
		BjRules.SURRENDER:
			hand["surrendered"] = true
			hand["done"] = true
			events.append({"type": "surrender", "pid": pid, "hand": index, "refund": hand["bet"] / 2})
	# 每次决策之后都重新找该谁(没打完的这一手还是他:再发一个 turn,房主据此重给满回合时间)
	_advance(events)
	return events


func _split(p: Dictionary, pid: int, index: int) -> Dictionary:
	# 两张拆成两手,各补一张;分 A 各只补一张就停(不能再分、不能加倍)。新的一手插在这一手后面
	var hand: Dictionary = p["hands"][index]
	var aces: bool = PokerCard.rank(hand["cards"][0]) == PokerCard.ACE
	var other := _new_hand([hand["cards"].pop_back()], hand["bet"])
	p["stack"] -= hand["bet"]
	hand["split"] = true
	other["split"] = true
	hand["cards"].append(_shoe.draw())
	other["cards"].append(_shoe.draw())
	for h in [hand, other]:
		if aces:
			h["done"] = true
			h["split_aces"] = true
		_finish_if_21_or_bust(h)
	p["hands"].insert(index + 1, other)
	return {
		"type": "split", "pid": pid, "hand": index, "cards": [hand["cards"].duplicate(), other["cards"].duplicate()],
		"bet": hand["bet"], "stack": p["stack"], "aces": aces,
	}


func _advance(events: Array) -> void:
	# 找下一手要决策的(按座位、每人从第一手起);都打完就轮到庄家,再结算
	for pid in _order:
		var hands: Array = _players[pid]["hands"]
		for i in hands.size():
			if not hands[i]["done"]:
				_turn = {"pid": pid, "hand": i}
				events.append({"type": "turn", "pid": pid, "hand": i})
				return
	_turn = null
	_dealer_play(events)
	_settle(events)
	_end_round(events)


func _dealer_play(events: Array) -> void:
	# 翻暗牌;还有要比的手(没爆、没投降、不是黑杰克)就要牌到 17
	_hole_shown = true
	var score := BjScore.evaluate(_dealer)
	events.append({"type": "dealer_reveal", "card": _dealer[1], "cards": _dealer.duplicate(), "total": score["total"],
		"soft": score["soft"]})
	if BjScore.is_natural(_dealer) or not _has_live_hand():
		return
	while BjScore.dealer_draws(_dealer):
		var card := _shoe.draw()
		_dealer.append(card)
		score = BjScore.evaluate(_dealer)
		events.append({"type": "dealer_hit", "card": card, "total": score["total"], "soft": score["soft"],
			"bust": score["total"] > BjRules.BLACKJACK})


func _has_live_hand() -> bool:
	for pid in _order:
		for hand in _players[pid]["hands"]:
			if not hand["surrendered"] and not hand["natural"] and not BjScore.is_bust(hand["cards"]):
				return true
	return false


func _settle(events: Array) -> void:
	var dealer_total := BjScore.total(_dealer)
	var dealer_bj := BjScore.is_natural(_dealer)
	var rows := []
	var stacks := {}
	for pid in _order:
		var p: Dictionary = _players[pid]
		for i in p["hands"].size():
			var hand: Dictionary = p["hands"][i]
			var outcome := _outcome(hand, dealer_total, dealer_bj)
			var paid := BjRules.payout(outcome, hand["bet"])
			p["stack"] += paid
			hand["outcome"] = outcome
			hand["payout"] = paid
			rows.append({"pid": pid, "hand": i, "outcome": outcome, "bet": hand["bet"], "payout": paid})
		p["bet"] = 0
		stacks[pid] = p["stack"]
	events.append({"type": "settled", "hands": rows, "stacks": stacks, "dealer_total": dealer_total,
		"dealer_bust": dealer_total > BjRules.BLACKJACK, "dealer_blackjack": dealer_bj})


static func _outcome(hand: Dictionary, dealer_total: int, dealer_bj: bool) -> String:
	if hand["surrendered"]:
		return BjRules.OUTCOME_SURRENDER
	var total := BjScore.total(hand["cards"])
	if total > BjRules.BLACKJACK:
		return BjRules.OUTCOME_BUST
	if hand["natural"]:
		return BjRules.OUTCOME_PUSH if dealer_bj else BjRules.OUTCOME_BLACKJACK
	if dealer_bj:
		return BjRules.OUTCOME_LOSE
	if dealer_total > BjRules.BLACKJACK or total > dealer_total:
		return BjRules.OUTCOME_WIN
	return BjRules.OUTCOME_PUSH if total == dealer_total else BjRules.OUTCOME_LOSE


func _end_round(events: Array) -> void:
	# 一局结束:不够最小下注的人输光(等他再领);连续超时的人离座;离开者筹码定格并移出座位;散局中就结算
	_phase = Phase.IDLE
	_turn = null
	var busted := []
	var stacks := {}
	for pid in _round_seats:
		if not _players.has(pid):
			continue
		var p: Dictionary = _players[pid]
		p["bet"] = 0
		stacks[pid] = p["stack"]
		if p["left"]:
			continue
		if p["stack"] < BjRules.MIN_BET:
			p["status"] = BjRules.STATUS_BUSTED
			if _order.has(pid):
				busted.append(pid)
	events.append({"type": "round_over", "round": _round, "busted": busted, "stacks": stacks})
	if not _ending:
		for pid in _round_seats:
			if not _players.has(pid):
				continue
			var p: Dictionary = _players[pid]
			if not p["left"] and p["timeouts"] >= BjRules.AWAY_AFTER_TIMEOUTS and p["status"] != BjRules.STATUS_BUSTED:
				p["status"] = BjRules.STATUS_AWAY
				p["timeouts"] = 0
				events.append({"type": "away", "pid": pid})
	for pid in _seat_order.filter(func(q): return _players[q]["left"]):
		_depart(pid)
	if _ending:
		_phase = Phase.OVER
		events.append({"type": "session_over", "results": results()})


# —— 小工具 ——

func _deciders() -> Array:
	# 下注阶段还没决定的人:本局登场、没离开、状态 waiting(输光还没再领的、离座的不等)
	return _round_seats.filter(func(pid: int) -> bool:
		return _is_seated(pid) and _players[pid]["status"] == BjRules.STATUS_WAITING)


func _decide_error(pid: int) -> String:
	var error := _seat_error(pid)
	if error == "" and _phase != Phase.BETTING:
		error = "not_betting"
	if error == "" and (not _round_seats.has(pid) or _players[pid]["status"] != BjRules.STATUS_WAITING):
		error = "invalid_action"
	return error


func _finish_if_21_or_bust(hand: Dictionary) -> void:
	if BjScore.total(hand["cards"]) >= BjRules.BLACKJACK:
		hand["done"] = true


func _card_event(kind: String, pid: int, index: int, hand: Dictionary) -> Dictionary:
	var score := BjScore.evaluate(hand["cards"])
	return {"type": kind, "pid": pid, "hand": index, "card": hand["cards"].back(), "total": score["total"],
		"soft": score["soft"], "bust": score["total"] > BjRules.BLACKJACK}


func _new_player() -> Dictionary:
	return {"stack": BjRules.STARTING_STACK, "buyins": 1, "status": BjRules.STATUS_WAITING, "left": false, "bet": 0,
		"hands": [], "timeouts": 0}


static func _new_hand(cards: Array, bet_amount: int) -> Dictionary:
	return {"cards": cards, "bet": bet_amount, "done": false, "doubled": false, "split": false, "split_aces": false,
		"surrendered": false, "natural": false, "outcome": "", "payout": 0}


static func _hand_view(hand: Dictionary) -> Dictionary:
	var score := BjScore.evaluate(hand["cards"])
	return {
		"cards": hand["cards"].duplicate(), "bet": hand["bet"], "total": score["total"], "soft": score["soft"],
		"done": hand["done"], "doubled": hand["doubled"], "split": hand["split"], "surrendered": hand["surrendered"],
		"natural": hand["natural"], "outcome": hand["outcome"], "payout": hand["payout"],
	}


static func _committed(p: Dictionary) -> int:
	# 押在桌上还没结算的注:下注阶段是 bet,打牌中是各手的注(已结算的手 outcome 非空,不再算)
	if p["hands"].is_empty():
		return p["bet"]
	var total := 0
	for hand in p["hands"]:
		if hand["outcome"] == "":
			total += hand["bet"]
	return total


func _seat_error(pid: int) -> String:
	if _phase == Phase.OVER:
		return "session_over"
	if not _is_seated(pid):
		return "not_seated"
	return ""


func _is_seated(pid: Variant) -> bool:
	return _players.has(pid) and not _players[pid]["left"]


func _seated_count() -> int:
	return _seat_order.filter(_is_seated).size()


func _depart(pid: int) -> void:
	var p: Dictionary = _players[pid]
	_departed.append({"pid": pid, "stack": p["stack"] + _committed(p), "buyins": p["buyins"]})
	_players.erase(pid)
	_seat_order.erase(pid)
	_round_seats.erase(pid)
	_opening_seats.erase(pid)


func _result_row(pid: int, stack: int, buyins: int, left: bool) -> Dictionary:
	return {"pid": pid, "stack": stack, "buyins": buyins, "net": stack - buyins * BjRules.STARTING_STACK, "left": left}


static func _ok(events: Array) -> Dictionary:
	return {"ok": true, "events": events}


static func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}
