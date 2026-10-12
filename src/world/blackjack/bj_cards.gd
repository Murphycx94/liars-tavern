class_name BjCards
extends Node3D
# 21 点的牌层(挂在 TableWorld.poker_root 下,拆台时一并收走;设计稿 §4):桌心牌架上庄家的牌(暗牌背面朝本机)、
# 各座位前平摊的几手牌、牌架后面的牌鞋与弃牌盘(BjShoeProp)。桌上的牌一律按本机视角正立。
# 动画方法都是协程,等的是挂在本节点上的计时补间:半路被对账(sync)或拆台时导演也不会卡住;
# 对账先停下牌还在走的飞行补间(记在牌的 meta 上),回来的协程发现 _epoch 变了就不再动它。


signal sfx(name: String)

const DEAL_STAGGER := 0.18      # 发牌:相邻两张出手的间隔(发牌预算每张 0.2)
const DEAL_FLIGHT := 0.28
const DEAL_TAIL := 0.05
const HIT_FLIGHT := 0.32        # 要牌 / 加倍的一张(要牌预算 0.55、加倍 0.85)
const SPLIT_MOVE := 0.3         # 分牌:第二张挪到新的一手
const SPLIT_GAP := 0.12
const SPLIT_FLIGHT := 0.28      # 再给两手各补一张(合计 0.3 + 0.12 + 0.28 + 0.12 + 0.05 < 1.0)
const FLIP := 0.32              # 翻暗牌(翻牌预算 0.8)
const PEEK_LIFT := 0.035        # 看暗牌:一角翘起这么高
const PEEK_TIME := 0.7          # 看牌预算 0.9
const DEALER_FLIGHT := 0.36     # 庄家补牌(预算 0.6)
const SWEEP_FLIGHT := 0.45      # 新一局:收牌进弃牌盘(round_started 预算 1.3 之内)
const SWEEP_JITTER := 0.1
const FLIGHT_ARC := 0.12
const SWEEP_ARC := 0.08
const SWEEP_SPIN := 0.8
const SURRENDER_FLIGHT := 0.4   # 投降:两张牌推进弃牌盘
const WIN_COLOR := Color(1.0, 0.82, 0.4)
const BLACKJACK_COLOR := Color(1.0, 0.95, 0.55)
const LOSE_COLOR := Color(0.95, 0.35, 0.3)
const GLOW_PEAK := 1.6
const GLOW_TIME := 1.2
const FLIGHT_META := &"bj_flight"
const SIDEWAYS_META := &"bj_sideways"

var world: TableWorld
var prop: BjShoeProp
var _dealer: Array = []      # Card3D,按发出的顺序
var _hole_hidden := false    # 第二张(暗牌)还是背面
var _hands := {}             # pid -> [[Card3D…], …]:每手的牌
var _discards := 0           # 收进弃牌盘的张数(决定叠放位置)
var _epoch := 0


func _init(p_world: TableWorld) -> void:
	world = p_world
	name = "BjCards"
	var rack := BoardRack.new()
	add_child(rack)
	world.clip_guard.set_prop(&"poker_board", BoardRack.guard_shape(rack))
	prop = BjShoeProp.new()
	add_child(prop)
	prop.register_guards(world.clip_guard)


# —— 查询 ——

static func deal_duration(cards: int) -> float:
	return maxi(cards - 1, 0) * DEAL_STAGGER + DEAL_FLIGHT + DEAL_TAIL


static func split_duration() -> float:
	return SPLIT_MOVE + SPLIT_GAP + SPLIT_FLIGHT + SPLIT_GAP + DEAL_TAIL


func dealer_cards() -> Array:
	return _dealer.filter(func(card): return is_instance_valid(card))


func hand_cards(pid: int, hand: int) -> Array:
	var hands: Array = _hands.get(pid, [])
	return hands[hand].filter(func(card): return is_instance_valid(card)) if hand < hands.size() else []


func hand_count(pid: int) -> int:
	return _hands.get(pid, []).size()


func dealer_kinds() -> Array:
	# 庄家牌的牌型(暗牌是 CardFaces.BACK):测试与调试截图对账用
	return _kinds_of(_dealer)


func hand_kinds(pid: int) -> Array:
	# 这个人每手牌的牌型 [[…], …]
	return _hands.get(pid, []).map(func(hand: Array) -> Array: return _kinds_of(hand))


func hoverable_cards() -> Array:
	# 悬停放大(CardPreview):桌上所有亮着的牌(暗牌是背面,CardPreview 自己会跳过)
	var out := dealer_cards()
	for pid in _hands:
		for hand in _hands[pid]:
			out.append_array(hand.filter(func(card): return is_instance_valid(card)))
	return out


# —— 动画(协程)——

func sweep() -> void:
	# 新一局:桌上的牌全部飞进弃牌盘
	_epoch += 1
	var all := _all_cards()
	_forget_all()
	if all.is_empty():
		return
	sfx.emit("sweep")
	for card in all:
		_lift_out(card)
		card.set_glow(0.0)
		card.show_poker_back()
		_fly(card, global_transform * BjLayout.discard_slot(_discards), SWEEP_FLIGHT + randf() * SWEEP_JITTER, SWEEP_ARC, SWEEP_SPIN)
		_discards += 1
	await _wait(SWEEP_FLIGHT + SWEEP_JITTER)
	_free_cards(all)


func deal(order: Array, hands: Dictionary, dealer_up: int) -> void:
	# 发牌:每人一张 → 庄家明牌 → 每人第二张 → 庄家暗牌(背面朝本机)。没有座位的人跳过
	var epoch := _epoch
	_free_cards(_all_cards())
	_forget_all()
	var count := 0
	for round in 2:
		for pid in order:
			var cards: Array = hands.get(pid, []) if hands.get(pid) is Array else []
			if round >= cards.size() or not PokerCard.is_card(cards[round]) or not world.seat_angles.has(pid):
				continue
			if not _hands.has(pid):
				_hands[pid] = [[]]
			var card := _new_card(cards[round], _shoe_transform())
			_hands[pid][0].append(card)
			_launch(card, func() -> Transform3D: return _hand_slot(pid, 0, round), count * DEAL_STAGGER, DEAL_FLIGHT)
			count += 1
		var dealer_card := _new_card(dealer_up if round == 0 else CardFaces.BACK, _shoe_transform())
		_dealer.append(dealer_card)
		var hidden := round == 1
		_hole_hidden = hidden or _hole_hidden
		_launch(dealer_card, func() -> Transform3D: return _dealer_slot(_dealer.find(dealer_card), _dealer.size()),
			count * DEAL_STAGGER, DEAL_FLIGHT)
		count += 1
	await _wait(deal_duration(count))
	if epoch == _epoch:
		_settle_all()


func add_card(pid: int, hand: int, card_value: int, sideways := false) -> void:
	# 要牌 / 加倍:从牌鞋飞到这一手的下一个位置;加倍那张横放
	var epoch := _epoch
	if not PokerCard.is_card(card_value) or not world.seat_angles.has(pid):
		return
	_ensure_hand(pid, hand)
	var card := _new_card(card_value, _shoe_transform())
	card.set_meta(SIDEWAYS_META, sideways)
	var index: int = _hands[pid][hand].size()
	_hands[pid][hand].append(card)
	sfx.emit("deal")
	_fly(card, global_transform * _hand_slot(pid, hand, index, sideways), HIT_FLIGHT, FLIGHT_ARC)
	await _wait(HIT_FLIGHT)
	if epoch == _epoch:
		_settle_all()


func split(pid: int, hand: int, first: Array, second: Array) -> void:
	# 分牌:这一手的第二张挪到右边新的一手,其余几手跟着让开;再给两手各补一张(first / second 是分完补好的两手)
	var epoch := _epoch
	if not world.seat_angles.has(pid) or first.size() < 2 or second.size() < 2:
		return
	_ensure_hand(pid, hand)
	var cards: Array = _hands[pid][hand]
	var moved: Card3D = cards[1] if cards.size() > 1 and is_instance_valid(cards[1]) else _new_card(second[0], _shoe_transform())
	_free_cards(cards.slice(2))
	_hands[pid][hand] = [cards[0]] if not cards.is_empty() else [_new_card(first[0], _shoe_transform())]
	_hands[pid].insert(hand + 1, [moved])
	sfx.emit("deal")
	_relayout(pid, SPLIT_MOVE)
	await _wait(SPLIT_MOVE + SPLIT_GAP)
	if epoch != _epoch:
		return
	for pair in [[hand, first[1]], [hand + 1, second[1]]]:
		if not PokerCard.is_card(pair[1]):
			continue
		var card := _new_card(pair[1], _shoe_transform())
		_hands[pid][pair[0]].append(card)
		_fly(card, global_transform * _hand_slot(pid, pair[0], 1), SPLIT_FLIGHT, FLIGHT_ARC)
		sfx.emit("deal")
		await _wait(SPLIT_GAP)
		if epoch != _epoch:
			return
	await _wait(SPLIT_FLIGHT - SPLIT_GAP + DEAL_TAIL)
	if epoch == _epoch:
		_settle_all()


func peek() -> void:
	# 庄家明牌是 A / 10 点:暗牌的一角翘起来看一眼再放下
	var epoch := _epoch
	if _dealer.size() < 2 or not is_instance_valid(_dealer[1]):
		await _wait(PEEK_TIME)
		return
	var card: Card3D = _dealer[1]
	_stop_flight(card)
	var start := card.transform
	sfx.emit("flip")
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		if is_instance_valid(card):
			var lift := sin(t * PI) * PEEK_LIFT
			card.transform = Transform3D(start.basis * Basis(Vector3.RIGHT, -sin(t * PI) * 0.35), start.origin + Vector3.UP * lift),
		0.0, 1.0, PEEK_TIME * 0.85)
	card.set_meta(FLIGHT_META, tween)
	await _wait(PEEK_TIME)
	if epoch == _epoch:
		_settle_all()


func reveal_hole(hole: int) -> void:
	# 翻暗牌:背面那张换成真牌再翻过来
	var epoch := _epoch
	if _dealer.size() < 2 or not is_instance_valid(_dealer[1]):
		_settle_all()
		return
	var card: Card3D = _dealer[1]
	_stop_flight(card)
	card.set_kind(hole)
	card.transform = _dealer_slot(1, _dealer.size())
	card.transform.basis = card.transform.basis * Basis(Vector3.BACK, PI)
	_hole_hidden = false
	sfx.emit("flip")
	card.set_meta(FLIGHT_META, card.flip_to_face(FLIP, 0.05))
	await _wait(FLIP)
	if epoch == _epoch:
		_settle_all()


func dealer_hit(card_value: int) -> void:
	var epoch := _epoch
	if not PokerCard.is_card(card_value):
		return
	var card := _new_card(card_value, _shoe_transform())
	_dealer.append(card)
	sfx.emit("deal")
	var count := _dealer.size()
	for i in count - 1:
		if is_instance_valid(_dealer[i]):
			_fly(_dealer[i], global_transform * _dealer_slot(i, count), DEALER_FLIGHT * 0.6, 0.0)
	_fly(card, global_transform * _dealer_slot(count - 1, count), DEALER_FLIGHT, FLIGHT_ARC)
	await _wait(DEALER_FLIGHT)
	if epoch == _epoch:
		_settle_all()


func surrender(pid: int, hand: int) -> void:
	# 投降:这一手的牌背面朝上推进弃牌盘
	var cards := hand_cards(pid, hand)
	if cards.is_empty():
		return
	_hands[pid][hand] = []
	sfx.emit("fold")
	for card in cards:
		_lift_out(card)
		card.show_poker_back()
		_fly(card, global_transform * BjLayout.discard_slot(_discards), SURRENDER_FLIGHT, FLIGHT_ARC * 0.5, SWEEP_SPIN)
		_discards += 1
	await _wait(SURRENDER_FLIGHT)
	_free_cards(cards)


func glow_hand(pid: int, hand: int, outcome: String) -> void:
	# 结算:赢的一手亮金光(黑杰克更亮),输的、爆牌的闪一下红;平手不亮。不等
	var color: Color
	match outcome:
		BjRules.OUTCOME_BLACKJACK:
			color = BLACKJACK_COLOR
		BjRules.OUTCOME_WIN:
			color = WIN_COLOR
		BjRules.OUTCOME_LOSE, BjRules.OUTCOME_BUST:
			color = LOSE_COLOR
		_:
			return
	for card in hand_cards(pid, hand):
		card.pulse_glow(color, GLOW_PEAK, GLOW_TIME)


func glow_dealer(color: Color) -> void:
	for card in dealer_cards():
		card.pulse_glow(color, GLOW_PEAK, GLOW_TIME)


# —— 对账 ——

func sync(players: Array, dealer: Dictionary) -> void:
	# 按公共视图瞬时摆好:players 同视图的 players(每人 hands[].cards),dealer 同视图的 dealer({cards, hidden})。
	# 有座位的人才摆;投降的那一手不在桌上。视图来自网络,类型不对的行当空。先停下所有还在走的动画
	_epoch += 1
	var wanted := {}
	for p in players:
		if not p is Dictionary or not p.get("pid") is int or not world.seat_angles.has(p["pid"]):
			continue
		var hands: Array = p["hands"] if p.get("hands") is Array else []
		var rows := []
		for hand in hands:
			if not hand is Dictionary:
				continue
			var cards: Array = hand["cards"].filter(PokerCard.is_card) if hand.get("cards") is Array else []
			rows.append({"cards": [] if Untrusted.flag(hand.get("surrendered")) else cards, "doubled": Untrusted.flag(hand.get("doubled"))})
		if not rows.is_empty():
			wanted[p["pid"]] = rows
	for pid in _hands.keys():
		if not wanted.has(pid):
			for hand in _hands[pid]:
				_free_cards(hand)
			_hands.erase(pid)
	for pid in wanted:
		_sync_hands(pid, wanted[pid])
	var shown: Array = dealer["cards"].filter(PokerCard.is_card) if dealer.get("cards") is Array else []
	var hidden: bool = Untrusted.flag(dealer.get("hidden")) and shown.size() == 1
	var kinds := shown.duplicate()
	if hidden:
		kinds.append(CardFaces.BACK)
	if _kinds_of(_dealer) != kinds or _hole_hidden != hidden:
		_free_cards(_dealer)
		_dealer = kinds.map(func(kind: int) -> Card3D: return _new_card(kind, _shoe_transform()))
	_hole_hidden = hidden
	_settle_all()


func clear() -> void:
	_epoch += 1
	_free_cards(_all_cards())
	_forget_all()


func _sync_hands(pid: int, rows: Array) -> void:
	var have: Array = _hands.get(pid, [])
	var out := []
	for i in rows.size():
		var kinds: Array = rows[i]["cards"]
		var cards: Array = have[i].filter(func(card): return is_instance_valid(card)) if i < have.size() else []
		if _kinds_of(cards) != kinds:
			_free_cards(cards)
			cards = kinds.map(func(kind: int) -> Card3D: return _new_card(kind, _shoe_transform()))
		for j in cards.size():
			cards[j].set_meta(SIDEWAYS_META, rows[i]["doubled"] and j == 2)
		out.append(cards)
	for i in range(rows.size(), have.size()):
		_free_cards(have[i])
	_hands[pid] = out


# —— 摆放 ——

func _settle_all() -> void:
	for i in _dealer.size():
		var card: Card3D = _dealer[i]
		if not is_instance_valid(card):
			continue
		var xform := _dealer_slot(i, _dealer.size())
		if i == 1 and _hole_hidden:
			xform = BjLayout.dealer_hidden_slot(_dealer.size())
			card.show_poker_back()
		_settle(card, xform)
	for pid in _hands:
		if not world.seat_angles.has(pid):
			continue
		for h in _hands[pid].size():
			var cards: Array = _hands[pid][h]
			for i in cards.size():
				if is_instance_valid(cards[i]):
					_settle(cards[i], _hand_slot(pid, h, i, cards[i].get_meta(SIDEWAYS_META, false)))


func _relayout(pid: int, duration: float) -> void:
	for h in _hands[pid].size():
		var cards: Array = _hands[pid][h]
		for i in cards.size():
			if is_instance_valid(cards[i]):
				_lift_out(cards[i])
				_fly(cards[i], global_transform * _hand_slot(pid, h, i, cards[i].get_meta(SIDEWAYS_META, false)), duration, 0.03)


func _hand_slot(pid: int, hand: int, index: int, sideways := false) -> Transform3D:
	return BjLayout.card_slot(world.seat_angle_now(pid), world.table_radius, hand, maxi(hand_count(pid), 1), index, sideways,
		pid == world.my_pid)


func _dealer_slot(index: int, count: int) -> Transform3D:
	return BjLayout.dealer_slot(maxi(index, 0), count)


func _shoe_transform() -> Transform3D:
	return BjLayout.shoe_mouth()


func _ensure_hand(pid: int, hand: int) -> void:
	if not _hands.has(pid):
		_hands[pid] = []
	while _hands[pid].size() <= hand:
		_hands[pid].append([])


func _settle(card: Card3D, xform: Transform3D) -> void:
	_stop_flight(card)
	if card.get_parent() != self:
		card.reparent(self, false)
	card.transform = xform
	card.visible = true


# —— 工具 ——

func _new_card(kind: int, xform: Transform3D) -> Card3D:
	var card := Card3D.new()
	card.set_kind(kind)
	if kind == CardFaces.BACK:
		card.show_poker_back()
	add_child(card)
	card.transform = xform
	return card


func _launch(card: Card3D, target: Callable, delay: float, duration: float) -> void:
	# 等 delay 再从牌鞋飞出(目标在出手时才算:前面的牌可能挤开了庄家的位置)
	var epoch := _epoch
	card.visible = false
	await _wait(delay)
	if epoch != _epoch or not is_instance_valid(card):
		return
	card.visible = true
	sfx.emit("deal")
	_fly(card, global_transform * target.call(), duration, FLIGHT_ARC)


func _fly(card: Card3D, target: Transform3D, duration: float, arc: float, spin := 0.0) -> void:
	card.set_meta(FLIGHT_META, card.fly_to(target, duration, arc, spin))


func _stop_flight(card: Card3D) -> void:
	if card.has_meta(FLIGHT_META):
		var tween: Tween = card.get_meta(FLIGHT_META)
		if tween != null and tween.is_valid():
			tween.kill()
		card.remove_meta(FLIGHT_META)


func _lift_out(card: Card3D) -> void:
	_stop_flight(card)
	card.visible = true
	if card.get_parent() != self:
		card.reparent(self, true)


func _wait(seconds: float) -> void:
	var tween := create_tween()
	tween.tween_interval(maxf(seconds, 0.0))
	await tween.finished


func _all_cards() -> Array:
	var out := _dealer.duplicate()
	for pid in _hands:
		for hand in _hands[pid]:
			out.append_array(hand)
	return out.filter(func(card): return is_instance_valid(card))


func _forget_all() -> void:
	_dealer = []
	_hole_hidden = false
	_hands = {}


static func _kinds_of(cards: Array) -> Array:
	return cards.filter(func(card): return is_instance_valid(card)).map(func(card: Card3D) -> int: return card.kind)


func _free_cards(cards: Array) -> void:
	for card in cards:
		if card != null and is_instance_valid(card):
			card.queue_free()
