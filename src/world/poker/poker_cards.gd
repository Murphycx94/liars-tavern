class_name PokerCards
extends Node3D
# 德州的牌层(挂在 TableWorld.poker_root 下):桌心的公共牌架与公共牌、各家牌扇里的手牌、
# 座位前亮出的牌、弃牌堆。桌上的牌一律按本机视角正立;自己的牌扇抬到德州位置,牌面正对越肩镜头。
# 动画方法都是协程,等的是挂在本节点上的计时补间:牌半路被对账(sync)或拆台收走时导演也不会卡住;
# 对账会先停下牌自己还在走的飞行补间(记在牌的 meta 上),回来的协程发现已经对过账(_epoch 变了)就不再动它。


signal sfx(name: String)

const DEAL_STAGGER := 0.06      # 发手牌:相邻两张出手的间隔
const DEAL_FLIGHT := 0.3
const DEAL_TAIL := 0.05         # 最后一张落定后再等的余量
const BOARD_STAGGER := 0.3      # 发公共牌:相邻两张出手的间隔;每张先背面朝上飞到牌架再翻开
const BOARD_FLIGHT := 0.26
const BOARD_FLIP := 0.22
const FOLD_FLIGHT := 0.4        # 弃牌:两张牌推进弃牌堆(行动预算 0.7 之内)
const REVEAL_FLIGHT := 0.4      # 亮牌:从牌扇翻到座位前的桌面上(每人 0.5 之内)
const SWEEP_FLIGHT := 0.45      # 新一手:桌上与各家手里的牌收回发牌处
const SWEEP_JITTER := 0.1
const HIGHLIGHT_TIME := 1.2     # 赢家的牌亮起:升到峰值再回落到常亮
const HIGHLIGHT_PEAK := 1.6
const HIGHLIGHT_HOLD := 0.7
const HIGHLIGHT_COLOR := Color(1.0, 0.82, 0.4)
const DECK_SCALE := 0.5         # 牌在发牌处(飞出前、收回后)缩小
const FLIGHT_ARC := 0.12        # 公共牌与亮牌的弧高
const DEAL_ARC := FLIGHT_ARC * 1.5   # 发手牌飞得高些:越过别人的筹码堆
const FOLD_ARC := FLIGHT_ARC * 0.5   # 弃牌贴着桌面推
const SWEEP_ARC := FLIGHT_ARC * 0.6
const FOLD_SPIN := 0.8          # 弧度:弃牌与收牌时牌随手一转
const SWEEP_SPIN := 1.2
const HIGHLIGHT_RISE := 0.3     # HIGHLIGHT_TIME 里升到峰值占的比例,其余回落
const FLIGHT_META := &"poker_flight"

var world: TableWorld
var my_pid := 0
var _board: Array = []      # Card3D,下标 = 公共牌序号(没发到的为 null)
var _held := {}             # pid -> [Card3D]:牌扇里的(或正飞向牌扇的)手牌
var _shown := {}            # pid -> [Card3D]:亮在座位前的牌
var _muck: Array = []       # Card3D
var _epoch := 0
var _glow_tween: Tween = null


func _init(p_world: TableWorld) -> void:
	world = p_world
	name = "PokerCards"
	_board.resize(PokerRules.BOARD_CARDS)
	var rack := BoardRack.new()
	add_child(rack)
	# 穿模防护:探头的头从公共牌架上面拱过去(牌架随本节点释放后自动忽略)
	world.clip_guard.set_prop(&"poker_board", BoardRack.guard_shape(rack))
	world.first_person_changed.connect(_on_first_person_changed)


# —— 查询 ——

static func deal_duration(cards: int) -> float:
	return maxi(cards - 1, 0) * DEAL_STAGGER + DEAL_FLIGHT + DEAL_TAIL


static func board_duration(cards: int) -> float:
	return maxi(cards - 1, 0) * BOARD_STAGGER + BOARD_FLIGHT + BOARD_FLIP


func board_cards() -> Array:
	return _board.filter(func(card): return card != null)


func shown_cards(pid: int) -> Array:
	return _shown.get(pid, []).duplicate()


func muck_cards() -> Array:
	return _muck.duplicate()


func hoverable_cards(pid: int) -> Array:
	# 本机能悬停放大(CardPreview)的牌:桌上的公共牌与亮牌、pid(本机)牌扇里的手牌;弃牌堆不算。
	# 牌面朝不朝镜头、是不是牌背由 CardPreview 自己判断
	return _table_cards() + _held.get(pid, []).filter(func(card): return is_instance_valid(card))


# —— 动画(协程)——

func deal_hole(order: Array, p_my_pid: int, my_cards: Array) -> void:
	# 发手牌:按发牌顺序每人一张、发两轮;自己的按私有视图亮面(不是牌的值当牌背),别人的是牌背。没有酒客的人跳过
	var epoch := _epoch
	my_pid = p_my_pid
	_present_my_fan()
	my_cards = my_cards.filter(PokerCard.is_card)
	for pid in order:
		_free_cards(_held.get(pid, []))   # 上一手没收走的(视图与演出不同步时):换成新发的
		_held.erase(pid)
	var dealt := 0
	for round in PokerRules.HOLE_CARDS:
		for pid in order:
			if not world.patrons.has(pid):
				continue
			var kind: int = CardFaces.BACK
			if pid == my_pid and round < my_cards.size():
				kind = my_cards[round]
			var card := _new_card(kind, _deck_transform())
			card.visible = false
			if not _held.has(pid):
				_held[pid] = []
			_held[pid].append(card)
			_deal_one(card, pid, round, dealt * DEAL_STAGGER)
			dealt += 1
	await _wait(deal_duration(dealt))
	if epoch == _epoch:
		_settle_held()


func _deal_one(card: Card3D, pid: int, index: int, delay: float) -> void:
	# 每一步都先确认这张牌还归这手牌管:半路弃牌、亮牌、对账、收牌拿走了就不再动它
	var epoch := _epoch
	await _wait(delay)
	if not _still_held(card, pid, epoch) or not world.patrons.has(pid):
		return
	var fan: Node3D = world.patrons[pid].fan
	card.visible = true
	sfx.emit("deal")
	_fly(card, fan.global_transform * CardTable.fan_slot(index, PokerRules.HOLE_CARDS, 0.0), DEAL_FLIGHT, DEAL_ARC)
	await _wait(DEAL_FLIGHT)
	if _still_held(card, pid, epoch) and is_instance_valid(fan):
		card.reparent(fan, true)


func _still_held(card: Variant, pid: int, epoch: int) -> bool:
	# card 不标类型:已释放的牌传给 Card3D 类型的参数本身就是脚本错误
	return epoch == _epoch and is_instance_valid(card) and _held.get(pid, []).has(card)


func deal_board(cards: Array, first_index: int) -> void:
	# 发公共牌:背面朝上飞到牌架上的槽位,再逐张翻开
	var epoch := _epoch
	var count := 0
	for i in cards.size():
		var slot := first_index + i
		if slot < 0 or slot >= PokerRules.BOARD_CARDS or not PokerCard.is_card(cards[i]):
			continue
		_free_card(_board[slot])
		var card := _new_card(cards[i], _deck_transform())
		card.visible = false
		_board[slot] = card
		_deal_board_card(card, slot, count * BOARD_STAGGER)
		count += 1
	await _wait(board_duration(count))
	if epoch == _epoch:
		_settle_board()


func _deal_board_card(card: Card3D, slot: int, delay: float) -> void:
	var epoch := _epoch
	await _wait(delay)
	if epoch != _epoch or not is_instance_valid(card) or _board[slot] != card:
		return
	card.visible = true
	sfx.emit("deal")
	var face_down := PokerLayout.board_slot(slot)
	face_down.basis = face_down.basis * Basis(Vector3.BACK, PI)
	_fly(card, global_transform * face_down, BOARD_FLIGHT, FLIGHT_ARC)
	await _wait(BOARD_FLIGHT)
	if epoch != _epoch or not is_instance_valid(card) or _board[slot] != card:
		return
	sfx.emit("flip")
	card.set_meta(FLIGHT_META, card.flip_to_face(BOARD_FLIP, 0.04))


func fold(pid: int) -> void:
	# 弃牌:两张牌背面朝下推进弃牌堆;手里没牌(视图与演出不同步)就直接在弃牌堆补两张
	var held: Array = _held.get(pid, [])
	_held.erase(pid)
	sfx.emit("fold")
	for i in PokerRules.HOLE_CARDS:
		var slot := PokerLayout.muck_slot(_muck.size())
		var card: Card3D = held[i] if i < held.size() and is_instance_valid(held[i]) else null
		if card == null:
			card = _new_card(CardFaces.BACK, slot)
		else:
			_lift_out(card)
			_fly(card, global_transform * slot, FOLD_FLIGHT, FOLD_ARC, FOLD_SPIN)
		_muck.append(card)
	for i in range(PokerRules.HOLE_CARDS, held.size()):
		_free_card(held[i])
	await _wait(FOLD_FLIGHT)


func reveal(pid: int, cards: Array) -> void:
	# 亮牌:从牌扇里拿出来,正面朝上摊到座位前(本机视角正立);手里没牌(如已离桌)就在座位前现出来。
	# cards 里不是牌的值跳过
	cards = cards.filter(PokerCard.is_card)
	var held: Array = _held.get(pid, [])
	_held.erase(pid)
	_free_cards(_shown.get(pid, []))
	var shown := []
	var angle := world.seat_angle_now(pid)
	for i in mini(cards.size(), PokerRules.HOLE_CARDS):
		var target := PokerLayout.shown_card(angle, world.table_radius, i)
		var card: Card3D = held[i] if i < held.size() and is_instance_valid(held[i]) else null
		if card == null:
			card = _new_card(cards[i], target.translated(Vector3.UP * FLIGHT_ARC))
		else:
			_lift_out(card)
		card.set_kind(cards[i])
		_fly(card, global_transform * target, REVEAL_FLIGHT, FLIGHT_ARC)
		shown.append(card)
	for i in range(shown.size(), held.size()):
		_free_card(held[i])
	_shown[pid] = shown
	sfx.emit("flip")
	await _wait(REVEAL_FLIGHT)


func highlight(kinds: Array) -> void:
	# 赢家组成牌型的那几张(公共牌与亮牌里)亮起;先熄掉上一个底池的高亮。传 [] 只熄灭
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	var lit := []
	for card in _table_cards():
		card.set_glow(0.0)
		if kinds.has(card.kind):
			lit.append(weakref(card))
	if lit.is_empty():
		return
	var glow := func(value: float) -> void:
		for ref in lit:
			var card: Card3D = ref.get_ref()
			if card != null:
				card.set_glow(value, HIGHLIGHT_COLOR)
	_glow_tween = create_tween()
	_glow_tween.tween_method(glow, 0.0, HIGHLIGHT_PEAK, HIGHLIGHT_TIME * HIGHLIGHT_RISE)
	_glow_tween.tween_method(glow, HIGHLIGHT_PEAK, HIGHLIGHT_HOLD, HIGHLIGHT_TIME * (1.0 - HIGHLIGHT_RISE))


func sweep() -> void:
	# 新一手开始:桌上与各家手里的牌全部飞回发牌处,然后释放
	_epoch += 1
	var all := _all_cards()
	_forget_all()
	if all.is_empty():
		return
	sfx.emit("sweep")
	for card in all:
		_lift_out(card)
		card.set_glow(0.0)
		_fly(card, global_transform * _deck_transform(), SWEEP_FLIGHT + randf() * SWEEP_JITTER, SWEEP_ARC, SWEEP_SPIN)
	await _wait(SWEEP_FLIGHT + SWEEP_JITTER)
	_free_cards(all)


# —— 对账 ——

func sync(seats: Array, players: Array, board: Array, p_my_pid: int, my_hole: Array) -> void:
	# 按公共 / 私有视图瞬时摆好(seats、players、board 同公共视图字段,my_hole 是私有视图的 hole):
	# 在 seats 里(桌上有酒客的人:还没登场的新人与已离场者不算)、在本手中(active / allin)且没亮牌、
	# 有酒客的人手里两张(自己的按 my_hole);亮了牌的摊在座位前;弃了牌的人(含已离场者)的牌在弃牌堆。
	# 视图来自网络,字段类型不对的行跳过或当空。先停下所有还在走的动画
	_epoch += 1
	my_pid = p_my_pid
	_present_my_fan()
	var held := {}
	var shown := {}
	var folded := 0
	var my_cards: Array = my_hole.filter(PokerCard.is_card)
	for p in players:
		if p is not Dictionary:
			continue
		var pid := int(p.get("pid", 0))
		var cards := _cards_of(p.get("shown"))
		var status := str(p.get("status", ""))
		if status == PokerRules.STATUS_FOLDED:
			folded += 1
		elif status not in [PokerRules.STATUS_ACTIVE, PokerRules.STATUS_ALLIN] or not seats.has(pid):
			continue
		elif cards.size() == PokerRules.HOLE_CARDS and world.seat_angles.has(pid):
			shown[pid] = cards
		elif world.patrons.has(pid):
			var mine := pid == my_pid and my_cards.size() == PokerRules.HOLE_CARDS
			held[pid] = my_cards if mine else [CardFaces.BACK, CardFaces.BACK]
	_sync_board(board)
	_sync_hands(_held, held)
	_sync_hands(_shown, shown)
	_sync_muck(folded * PokerRules.HOLE_CARDS)
	_settle_held()
	_settle_shown()


func clear() -> void:
	# 收走所有牌(牌架留着)
	_epoch += 1
	highlight([])
	_free_cards(_all_cards())
	_forget_all()


func _sync_board(board: Array) -> void:
	for i in PokerRules.BOARD_CARDS:
		var want: Variant = board[i] if i < board.size() and PokerCard.is_card(board[i]) else null
		var card: Card3D = _board[i]
		if card != null and (want == null or card.kind != want):
			_free_card(card)
			card = null
		if card == null and want != null:
			card = _new_card(want, PokerLayout.board_slot(i))
		_board[i] = card
	_settle_board()


func _sync_hands(current: Dictionary, wanted: Dictionary) -> void:
	# current:_held 或 _shown;wanted:pid -> [两张牌的牌型]。牌型对得上的牌留着,对不上的换掉
	for pid in current.keys():
		if not wanted.has(pid):
			_free_cards(current[pid])
			current.erase(pid)
	for pid in wanted:
		var have: Array = current.get(pid, []).filter(func(card): return is_instance_valid(card))
		var kinds: Array = wanted[pid]
		if have.size() != kinds.size() or _kinds_of(have) != kinds:
			_free_cards(have)
			have = kinds.map(func(kind: int) -> Card3D: return _new_card(kind, _deck_transform()))
		current[pid] = have


func _sync_muck(count: int) -> void:
	while _muck.size() > count:
		_free_card(_muck.pop_back())
	while _muck.size() < count:
		_muck.append(_new_card(CardFaces.BACK, PokerLayout.muck_slot(_muck.size())))
	for i in _muck.size():
		_settle(_muck[i], self, PokerLayout.muck_slot(i))


# —— 摆放 ——

func _settle_board() -> void:
	for i in PokerRules.BOARD_CARDS:
		if _board[i] != null:
			_settle(_board[i], self, PokerLayout.board_slot(i))


func _settle_held() -> void:
	for pid in _held:
		if not world.patrons.has(pid):
			continue
		var cards: Array = _held[pid]
		for i in cards.size():
			_settle(cards[i], world.patrons[pid].fan, CardTable.fan_slot(i, cards.size(), 0.0))


func _settle_shown() -> void:
	for pid in _shown:
		var cards: Array = _shown[pid]
		for i in cards.size():
			_settle(cards[i], self, PokerLayout.shown_card(world.seat_angle_now(pid), world.table_radius, i))


func _settle(card: Card3D, parent: Node3D, xform: Transform3D) -> void:
	# 瞬时摆好:先停下这张牌还在走的飞行 / 翻面补间
	if not is_instance_valid(card):
		return
	_stop_flight(card)
	if card.get_parent() != parent:
		card.reparent(parent, false)
	card.transform = xform
	card.visible = true


func _on_first_person_changed(_on: bool) -> void:
	_present_my_fan()   # 本机换视角(V):自己的底牌重摆


func _present_my_fan() -> void:
	# 规格 §5.3:德州时自己的牌扇抬到座位坐标 HIP + FAN_OFFSET,牌面正对越肩镜头;第一人称时拿在镜头右下方
	if not world.patrons.has(my_pid) or not world.seat_angles.has(my_pid):
		return
	var seat := world.seat_transform(world.seat_angles[my_pid])
	var me: Patron = world.patrons[my_pid]
	if world.first_person:
		# 第一人称:拿在镜头右下方,跟着探头走
		me.present_hand_first_person(seat, world.first_person_rest_view(my_pid), PokerLayout.FP_FAN_CAM, PokerLayout.FP_FAN_SCALE)
	else:
		me.hold_fan(PokerLayout.fan_transform(seat, world.third_person_view(my_pid).origin))


# —— 工具 ——

func _new_card(kind: int, xform: Transform3D) -> Card3D:
	var card := Card3D.new()
	card.set_kind(kind)
	if kind == CardFaces.BACK:
		card.show_poker_back()   # 德州有自己的牌背
	add_child(card)
	card.transform = xform
	return card


func _deck_transform() -> Transform3D:
	# 发牌处:背面朝上、缩小
	return Transform3D(Basis(Vector3.BACK, PI).scaled(Vector3.ONE * DECK_SCALE), PokerLayout.deck_position())


func _fly(card: Card3D, target: Transform3D, duration: float, arc: float, spin := 0.0) -> void:
	# 弧线飞到全局变换 target;补间记在牌上,对账时停得下来
	card.set_meta(FLIGHT_META, card.fly_to(target, duration, arc, spin))


func _stop_flight(card: Card3D) -> void:
	if card.has_meta(FLIGHT_META):
		var tween: Tween = card.get_meta(FLIGHT_META)
		if tween != null and tween.is_valid():
			tween.kill()
		card.remove_meta(FLIGHT_META)


func _lift_out(card: Card3D) -> void:
	# 从牌扇里拿出来挂到本节点下(保持世界位置),再往桌上飞
	_stop_flight(card)
	card.visible = true
	if card.get_parent() != self:
		card.reparent(self, true)


func _wait(seconds: float) -> void:
	var tween := create_tween()
	tween.tween_interval(maxf(seconds, 0.0))
	await tween.finished


func _table_cards() -> Array:
	var cards := board_cards()
	for pid in _shown:
		cards.append_array(_shown[pid])
	return cards.filter(func(card): return is_instance_valid(card))


func _all_cards() -> Array:
	var cards := _table_cards() + _muck
	for pid in _held:
		cards.append_array(_held[pid])
	return cards.filter(func(card): return is_instance_valid(card))


func _forget_all() -> void:
	_board = []
	_board.resize(PokerRules.BOARD_CARDS)
	_held = {}
	_shown = {}
	_muck = []


static func _kinds_of(cards: Array) -> Array:
	return cards.map(func(card: Card3D) -> int: return card.kind)


static func _cards_of(value: Variant) -> Array:
	# 视图里的一组牌:不是数组当空,数组里不是牌的值丢掉
	return value.filter(PokerCard.is_card) if value is Array else []


func _free_cards(cards: Array) -> void:
	for card in cards:
		_free_card(card)


func _free_card(card: Variant) -> void:
	if card != null and is_instance_valid(card):
		card.queue_free()
