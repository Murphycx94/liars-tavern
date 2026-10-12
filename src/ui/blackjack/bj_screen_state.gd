class_name BjScreenState
extends RefCounted
# 21 点牌桌的本地状态(纯逻辑,不依赖场景树):最新公共视图、演出进行到哪一步的「影子」(各人的筹码、状态、每手的牌,
# 庄家的牌——铭牌与 HUD 在演出期间按它显示,视图领先于演出:暗牌、结算结果不能先露出来)、座位表与当前决策的那一手。
# 事件只改影子;演出结束后 refresh_from_view 用视图整体覆盖。视图与事件来自网络,字段类型不对的一律当作没有。


const UNKNOWN_NAME := "?"
const BOTTOM_NONE := "none"
const BOTTOM_BET := "bet"              # 下注阶段,自己还没决定:下注控件
const BOTTOM_BET_WAIT := "bet_wait"    # 已下注 / 这局不玩,等其他人
const BOTTOM_PLAY := "play"            # 有人在决策(自己的回合展开按钮,别人的只留横幅)
const BOTTOM_BUSTED := "busted"
const BOTTOM_AWAY := "away"
const BOTTOM_JOINING := "joining"      # 中途加入:下一局入座

var pub := {}
var rows := {}            # pid -> {stack, status, left, buyins, net, bet, hands}
var order: Array = []
var seats: Array = []     # 桌上有酒客的 pid
var names := {}
var dealer_cards: Array = []
var dealer_hidden := false
var current: Variant = null   # {"pid", "hand"}:演出进行到的那一手
var phase := ""
var round_number := 0
var ending := false


# —— 视图 ——

func set_seats(entries: Array) -> void:
	seats = []
	for entry in entries:
		if entry is Dictionary and entry.get("pid") is int:
			seats.append(entry["pid"])
			if entry.get("name") is String:
				names[entry["pid"]] = entry["name"]


func apply_public(view: Dictionary) -> void:
	pub = view


func refresh_from_view(adopt_seats := false) -> bool:
	# 用最新视图整体覆盖影子;返回座位表是否变了。同一局里座位只会少(有人离开):离开者的位置留到下一局开始再收,
	# 他桌上的牌还要照常和庄家比;adopt_seats(迟到者第一帧)时整个照视图
	if pub.is_empty():
		return false
	var same_round := Untrusted.same(pub.get("round"), round_number)
	rows = {}
	order = []
	for p in _array(pub.get("players")):
		if p is Dictionary and p.get("pid") is int:
			rows[p["pid"]] = _clean_row(p)
			order.append(p["pid"])
			if p.get("name") is String:
				names[p["pid"]] = p["name"]
	var new_seats: Array = _array(pub.get("seats")).filter(func(pid): return pid is int)
	if same_round and not adopt_seats:
		new_seats = PokerScreenState.keep_departed_seats(seats, new_seats)
	var reseat := new_seats != seats
	seats = new_seats
	var dealer: Dictionary = pub["dealer"] if pub.get("dealer") is Dictionary else {}
	dealer_cards = _cards(dealer.get("cards"))
	dealer_hidden = Untrusted.flag(dealer.get("hidden"))
	round_number = pub["round"] if pub.get("round") is int else round_number
	phase = pub["phase"] if pub.get("phase") is String else phase
	ending = Untrusted.flag(pub.get("ending"))
	current = _turn(pub.get("current"))
	return reseat


func sync_from_view() -> bool:
	return refresh_from_view(true)


# —— 事件(只改影子)——

func apply_event(ev: Dictionary) -> void:
	var pid: Variant = ev.get("pid")
	match ev.get("type", ""):
		"round_started":
			_round_started(ev)
		"bet_placed":
			_put(pid, {"bet": _int(ev, "amount"), "stack": _int(ev, "stack"), "status": BjRules.STATUS_BET})
		"bet_skipped":
			_put(pid, {"status": BjRules.STATUS_SKIP})
		"dealt":
			_dealt(ev)
		"turn":
			current = _turn(ev)
		"hit", "double":
			_add_card(pid, ev)
		"stand":
			_hand_field(pid, ev, "done", true)
		"split":
			_split(pid, ev)
		"surrender":
			_hand_field(pid, ev, "surrendered", true)
			_hand_field(pid, ev, "done", true)
		"dealer_reveal":
			current = null
			dealer_cards = _cards(ev.get("cards"))
			dealer_hidden = false
		"dealer_hit":
			if PokerCard.is_card(ev.get("card")):
				dealer_cards.append(ev["card"])
		"settled":
			_settled(ev)
		"round_over":
			phase = "idle"
			current = null
			for busted in _array(ev.get("busted")):
				_put(busted, {"status": BjRules.STATUS_BUSTED})
		"rebuy":
			_put(pid, {"stack": _int(ev, "stack"), "buyins": _int(ev, "buyins"), "status": BjRules.STATUS_WAITING})
		"away":
			_put(pid, {"status": BjRules.STATUS_AWAY})
		"sit_in":
			_put(pid, {"status": BjRules.STATUS_WAITING})
		"player_joined":
			if pid is int:
				if ev.get("name") is String:
					names[pid] = ev["name"]
				if not rows.has(pid):
					rows[pid] = _clean_row({"stack": BjRules.STARTING_STACK, "buyins": 1})
					order.append(pid)
		"player_left":
			_put(pid, {"left": true})
		"ending":
			ending = true


func _round_started(ev: Dictionary) -> void:
	round_number = _int(ev, "round")
	phase = "betting"
	current = null
	dealer_cards = []
	dealer_hidden = false
	var new_seats: Array = _array(ev.get("seats")).filter(func(pid): return pid is int)
	if not new_seats.is_empty():
		seats = new_seats
	for pid in rows:
		var r: Dictionary = rows[pid]
		r["hands"] = []
		r["bet"] = 0
		if not [BjRules.STATUS_AWAY, BjRules.STATUS_BUSTED].has(r["status"]):
			r["status"] = BjRules.STATUS_WAITING if r["stack"] >= BjRules.MIN_BET else BjRules.STATUS_BUSTED


func _dealt(ev: Dictionary) -> void:
	phase = "playing"
	var hands: Dictionary = ev["hands"] if ev.get("hands") is Dictionary else {}
	for pid in _array(ev.get("order")):
		if not rows.has(pid):
			continue
		var r: Dictionary = rows[pid]
		var cards := _cards(hands.get(pid))
		r["status"] = BjRules.STATUS_PLAYING
		r["hands"] = [_new_hand(cards, r["bet"])]
		r["hands"][0]["natural"] = BjScore.is_natural(cards) if cards.size() == 2 else false
	dealer_cards = _cards([ev.get("dealer_up")])
	dealer_hidden = true


func _add_card(pid: Variant, ev: Dictionary) -> void:
	var hand := _hand(pid, ev)
	if hand.is_empty() or not PokerCard.is_card(ev.get("card")):
		return
	hand["cards"].append(ev["card"])
	if Untrusted.same(ev.get("type"), "double"):
		hand["bet"] = _int(ev, "bet")
		hand["doubled"] = true
		hand["done"] = true
		_put(pid, {"stack": _int(ev, "stack")})
	elif BjScore.total(hand["cards"]) >= BjRules.BLACKJACK:
		hand["done"] = true


func _split(pid: Variant, ev: Dictionary) -> void:
	var index := _int(ev, "hand")
	var pair: Array = _array(ev.get("cards"))
	if not rows.has(pid) or pair.size() != 2 or index >= rows[pid]["hands"].size():
		return
	var bet := _int(ev, "bet")
	var hands: Array = rows[pid]["hands"]
	var first := _new_hand(_cards(pair[0]), bet)
	var second := _new_hand(_cards(pair[1]), bet)
	for hand in [first, second]:
		hand["split"] = true
		hand["done"] = Untrusted.flag(ev.get("aces")) or BjScore.total(hand["cards"]) >= BjRules.BLACKJACK
	hands[index] = first
	hands.insert(index + 1, second)
	_put(pid, {"stack": _int(ev, "stack")})


func _settled(ev: Dictionary) -> void:
	current = null
	for row in _array(ev.get("hands")):
		if not row is Dictionary:
			continue
		var hand := _hand(row.get("pid"), row)
		if not hand.is_empty():
			hand["outcome"] = row["outcome"] if row.get("outcome") is String else ""
			hand["payout"] = _int(row, "payout")
	var stacks: Dictionary = ev["stacks"] if ev.get("stacks") is Dictionary else {}
	for pid in stacks:
		if stacks[pid] is int and rows.has(pid):
			_put(pid, {"stack": stacks[pid], "bet": 0,
				"net": stacks[pid] - maxi(rows[pid]["buyins"], 1) * BjRules.STARTING_STACK})


# —— 查询 ——

func row(pid: Variant) -> Dictionary:
	return rows.get(pid, {})


func status_of(pid: Variant) -> String:
	return row(pid).get("status", "")


func has_left(pid: Variant) -> bool:
	return Untrusted.flag(row(pid).get("left"))


func name_of(pid: Variant) -> String:
	return names.get(pid, UNKNOWN_NAME)


func hands_of(pid: Variant) -> Array:
	return row(pid).get("hands", [])


func current_pid() -> Variant:
	return current["pid"] if current != null else null


func legal(my_pid: int) -> Dictionary:
	# 视图里给自己的可选动作:视图说轮到自己、演出也演到自己的这一手
	var actions: Dictionary = pub["actions"] if pub.get("actions") is Dictionary else {}
	if not Untrusted.same(actions.get("pid"), my_pid) or current == null or current["pid"] != my_pid \
			or not Untrusted.same(actions.get("hand"), current["hand"]):
		return {}
	var out := {}
	for kind in BjRules.PLAY_ACTIONS:
		out[kind] = Untrusted.flag(actions.get(kind))
	return out


func uses_overview(my_pid: int) -> bool:
	return not seats.has(my_pid)


func is_excluded(pid: Variant) -> bool:
	return not rows.has(pid) or has_left(pid)


func bottom_mode(my_pid: int) -> String:
	# 底部中间放什么:没登场 → 下一局入座;输光 / 离座的提示;下注阶段自己没决定 → 下注控件,决定了 → 等别人;
	# 打牌中有人在决策 → 决策栏(别人的回合只留横幅)
	if not seats.has(my_pid):
		return BOTTOM_JOINING if rows.has(my_pid) else BOTTOM_NONE
	var status := status_of(my_pid)
	if status == BjRules.STATUS_BUSTED:
		return BOTTOM_BUSTED
	if status == BjRules.STATUS_AWAY:
		return BOTTOM_AWAY
	if phase == "betting":
		return BOTTOM_BET if status == BjRules.STATUS_WAITING else BOTTOM_BET_WAIT
	if current != null:
		return BOTTOM_PLAY
	return BOTTOM_NONE


func betting_progress() -> Array:
	# [已决定的人数, 要决定的人数]:「已下注 · 等待其他人(2/5)」
	var deciding := seats.filter(func(pid): return rows.has(pid) and not has_left(pid) and [BjRules.STATUS_WAITING,
		BjRules.STATUS_BET, BjRules.STATUS_SKIP].has(status_of(pid)))
	return [deciding.filter(func(pid): return status_of(pid) != BjRules.STATUS_WAITING).size(), deciding.size()]


func seat_entries(my_pid: int) -> Array:
	var pids := seats.duplicate()
	if not pids.has(my_pid):
		pids.append(my_pid)
	return pids.map(func(pid: int) -> Dictionary: return {"pid": pid, "name": name_of(pid)})


func dealer_label() -> String:
	# 「庄家 10 + ?」(暗牌没翻)/「庄家 17」/「庄家 爆牌 24」/「庄家 黑杰克」
	if dealer_cards.is_empty():
		return "庄家"
	if dealer_hidden:
		return "庄家 %d + ?" % BjScore.total(dealer_cards)
	if BjScore.is_natural(dealer_cards):
		return "庄家 黑杰克"
	return "庄家 " + BjScore.label(dealer_cards)


static func hand_label(hand: Dictionary) -> String:
	# 一手牌的点数与结果:「软 17」「20 · 赢 +200」「爆牌 24」「黑杰克 · +150」「投降」
	var cards: Array = hand.get("cards", [])
	var text := "黑杰克" if Untrusted.flag(hand.get("natural")) and cards.size() == 2 else BjScore.label(cards)
	if Untrusted.flag(hand.get("surrendered")):
		text = "投降"
	var outcome: String = hand.get("outcome", "")
	if outcome == "":
		return text
	var net: int = hand.get("payout", 0) - hand.get("bet", 0)
	match outcome:
		BjRules.OUTCOME_PUSH:
			return text + " · 平手"
		BjRules.OUTCOME_BUST, BjRules.OUTCOME_SURRENDER:
			return text + " · " + ChipText.signed(net)
	return "%s · %s %s" % [text, BjRules.OUTCOME_NAMES.get(outcome, outcome), ChipText.signed(net)]


func plate_status(pid: Variant) -> String:
	# 铭牌第二行筹码后面的状态:下注阶段「下注 100」「这局不玩」;打牌中每手的点数(分牌时用 / 隔开);输光、离座、已离开
	var r := row(pid)
	if r.is_empty():
		return ""
	if Untrusted.flag(r.get("left")):
		return "已离开"
	match r.get("status"):
		BjRules.STATUS_BUSTED:
			return "输光"
		BjRules.STATUS_AWAY:
			return "离座"
		BjRules.STATUS_SKIP:
			return "这局不玩"
		BjRules.STATUS_BET:
			return "下注 %s" % ChipText.format(r.get("bet", 0))
		BjRules.STATUS_WAITING:
			return "下注中" if phase == "betting" and seats.has(pid) else ""
	var hands: Array = r.get("hands", [])
	return " / ".join(hands.map(func(hand: Dictionary) -> String:
		return "黑杰克" if Untrusted.flag(hand.get("natural")) else ("投降" if Untrusted.flag(hand.get("surrendered")) else BjScore.label(hand["cards"]))))


# —— 小工具 ——

func _put(pid: Variant, fields: Dictionary) -> void:
	if not pid is int:
		return
	if not rows.has(pid):
		rows[pid] = _clean_row({})
		order.append(pid)
	rows[pid].merge(fields, true)


func _hand(pid: Variant, ev: Dictionary) -> Dictionary:
	var index := _int(ev, "hand")
	var hands: Array = hands_of(pid)
	return hands[index] if index >= 0 and index < hands.size() else {}


func _hand_field(pid: Variant, ev: Dictionary, key: String, value: Variant) -> void:
	var hand := _hand(pid, ev)
	if not hand.is_empty():
		hand[key] = value


static func _new_hand(cards: Array, bet: int) -> Dictionary:
	return {"cards": cards, "bet": bet, "done": false, "doubled": false, "split": false, "surrendered": false,
		"natural": false, "outcome": "", "payout": 0}


static func _clean_row(p: Dictionary) -> Dictionary:
	var hands := []
	for hand in _array(p.get("hands")):
		if hand is Dictionary:
			var clean := _new_hand(_cards(hand.get("cards")), _int(hand, "bet"))
			for key in ["done", "doubled", "split", "surrendered", "natural"]:
				clean[key] = Untrusted.flag(hand.get(key))
			clean["outcome"] = hand["outcome"] if hand.get("outcome") is String else ""
			clean["payout"] = _int(hand, "payout")
			hands.append(clean)
	return {
		"stack": _int(p, "stack"), "bet": _int(p, "bet"), "buyins": _int(p, "buyins"), "net": _int(p, "net"),
		"status": p["status"] if p.get("status") is String else BjRules.STATUS_WAITING, "left": Untrusted.flag(p.get("left")),
		"hands": hands,
	}


static func _turn(value: Variant) -> Variant:
	if value is Dictionary and value.get("pid") is int and value.get("hand") is int:
		return {"pid": value["pid"], "hand": value["hand"]}
	return null


static func _int(d: Dictionary, key: String) -> int:
	return d[key] if d.get(key) is int else 0


static func _array(value: Variant) -> Array:
	return value if value is Array else []


static func _cards(value: Variant) -> Array:
	return _array(value).filter(PokerCard.is_card)
