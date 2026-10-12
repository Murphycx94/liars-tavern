class_name BjChips
extends Node3D
# 21 点的筹码层(挂在 TableWorld.poker_root 下;设计稿 §4):各座位的筹码堆、每手前面的下注。
# 庄家那摞装饰筹码在 BjShoeProp 里;赔付从它那里飞出来、输掉的注飞回去。金额为 0 不建节点。
# 动画方法都是协程,飞行中的筹码是临时的一摞,补间挂在本节点上:中途对账(sync)或清空时协程照常走完、不卡住导演,
# 回来发现已经对过账(_epoch 变了)就不再改金额。静止的筹码堆与下注每帧按 TableWorld.seat_angle_now 摆。


signal sfx(name: String)

const BET_SLIDE := 0.36       # 下注 / 加倍 / 分牌:新放进去的筹码从筹码堆滑到下注位(下注预算 0.45)
const PAY_SLIDE := 0.5        # 结算第一段:赔付从庄家飞到下注位 / 输的注飞回庄家
const RETURN_SLIDE := 0.5     # 结算第二段:连本带利滑回筹码堆(两段 + 停顿在 SETTLED 1.8 之内)
const SETTLE_PAUSE := 0.15
const REBUY_DROP := 0.45
const SLIDE_ARC := 0.05
const DROP_HEIGHT := 0.3
const LABEL_LIFT := 0.03

var world: TableWorld
var bank_spot := BjLayout.bank_position()
var _stacks := {}         # pid -> ChipStack3D
var _bets := {}           # pid -> [ChipStack3D 或 null]:每手的下注
var _flyers: Array = []
var _epoch := 0


func _init(p_world: TableWorld) -> void:
	world = p_world
	name = "BjChips"


func _process(_delta: float) -> void:
	_follow_seats()


# —— 查询 ——

static func settle_duration() -> float:
	return PAY_SLIDE + SETTLE_PAUSE + RETURN_SLIDE


func stack_amount(pid: int) -> int:
	return _stacks[pid].amount if _stacks.has(pid) else 0


func bet_amount(pid: int, hand := 0) -> int:
	var bets: Array = _bets.get(pid, [])
	return bets[hand].amount if hand < bets.size() and bets[hand] != null else 0


func bet_amounts(pid: int) -> Array:
	return _bets.get(pid, []).map(func(node) -> int: return node.amount if node != null else 0)


func stack_anchor(pid: int) -> Vector3:
	var node: ChipStack3D = _stacks.get(pid)
	var spot := node.position if node != null else _stack_spot(pid)
	return to_global(spot + Vector3.UP * ((node.top_height() if node != null else 0.0) + LABEL_LIFT))


# —— 对账 ——

func sync(players: Array) -> void:
	# 按公共视图瞬时摆好:没离开的在座者有筹码堆;下注阶段的注(bet)放在第一手的位置,
	# 发了牌以后按每手没结算的注摆。还没登场的人(没有座位)不摆
	_epoch += 1
	_drop_flyers()
	var stacks := {}
	var bets := {}
	for p in players:
		if not p is Dictionary or not p.get("pid") is int or not world.seat_angles.has(p["pid"]):
			continue
		var pid: int = p["pid"]
		if not Untrusted.flag(p.get("left")):
			stacks[pid] = _int(p, "stack")
		var hands: Array = p["hands"] if p.get("hands") is Array else []
		if hands.is_empty():
			bets[pid] = [_int(p, "bet")]
		else:
			bets[pid] = hands.map(func(hand) -> int:
				return _int(hand, "bet") if hand is Dictionary and Untrusted.same(hand.get("outcome", ""), "") and not Untrusted.flag(hand.get("surrendered")) else 0)
	for pid in _stacks.keys():
		if not stacks.has(pid):
			_set_stack(pid, 0)
	for pid in stacks:
		_set_stack(pid, stacks[pid])
	for pid in _bets.keys():
		if not bets.has(pid):
			_set_bets(pid, [])
	for pid in bets:
		_set_bets(pid, bets[pid])
	_follow_seats()


func remove_seat(pid: int) -> void:
	_set_stack(pid, 0)


func clear() -> void:
	_epoch += 1
	_drop_flyers()
	for pid in _stacks.keys():
		_set_stack(pid, 0)
	for pid in _bets.keys():
		_set_bets(pid, [])


# —— 动画(协程)——

func place_bet(pid: int, hand: int, total: int, stack: int, hand_count := 1) -> void:
	# 下注 / 加倍 / 分牌:这一手的注变成 total,筹码堆剩 stack;新放进去的部分从筹码堆滑过去
	var epoch := _epoch
	var added := total - bet_amount(pid, hand)
	_set_stack(pid, stack)
	_resize_bets(pid, hand_count)
	if added <= 0 or not world.seat_angles.has(pid):
		_set_bet(pid, hand, total)
		return
	sfx.emit("chips")
	var flyer := _launch(added, _stack_spot(pid), pid)
	await _fly([[flyer, _bet_spot(pid, hand)]], BET_SLIDE)
	if epoch == _epoch:
		_set_bet(pid, hand, total)


func split_bet(pid: int, hand: int, bet: int, stack: int) -> void:
	# 分牌:在这一手后面插进新的一手,它的注(和原来一样多)从筹码堆滑过去;后面几手的注跟着往右让
	var bets: Array = _bets.get(pid, [])
	while bets.size() <= hand:
		bets.append(null)
	bets.insert(hand + 1, null)
	_bets[pid] = bets
	_follow_seats()
	await place_bet(pid, hand + 1, bet, stack, bets.size())


func settle(rows: Array, stacks: Dictionary) -> void:
	# 结算(settled):rows 每手 {pid, hand, outcome, bet, payout}。第一段:赢的部分从庄家飞到这一手的下注位,
	# 输掉的部分(输、爆牌全部,投降一半)飞回庄家,留下的本金原地不动;停一下,第二段:每手拿回的(payout)滑回筹码堆。
	# 最后按 stacks 定格
	var epoch := _epoch
	var first := []
	var kept := []      # 第一段里留在下注位上的本金(第二段开始时换成整笔 payout 一起飞)
	var returns := []   # [pid, payout, 下注位]
	for row in rows:
		if not row is Dictionary or not row.get("pid") is int or not world.seat_angles.has(row["pid"]):
			continue
		var pid: int = row["pid"]
		var bet := _int(row, "bet")
		var payout := _int(row, "payout")
		var spot := _bet_spot(pid, _int(row, "hand"))
		_set_bet(pid, _int(row, "hand"), 0)
		if mini(payout, bet) > 0:
			kept.append(_launch(mini(payout, bet), spot, pid))
		if payout > bet:
			first.append([_launch(payout - bet, bank_spot, pid), spot])
		elif payout < bet:
			first.append([_launch(bet - payout, spot, pid), bank_spot])
		if payout > 0:
			returns.append([pid, payout, spot])
	if not first.is_empty():
		sfx.emit("chips")
		await _fly(first, PAY_SLIDE)
	else:
		await _wait(PAY_SLIDE)
	if epoch != _epoch:
		return
	await _wait(SETTLE_PAUSE)
	if epoch != _epoch:
		return
	_land(kept)
	var second := returns.map(func(entry: Array) -> Array: return [_launch(entry[1], entry[2], entry[0]), _stack_spot(entry[0])])
	if not second.is_empty():
		sfx.emit("chips")
		await _fly(second, RETURN_SLIDE)
	else:
		await _wait(RETURN_SLIDE)
	if epoch != _epoch:
		return
	for pid in stacks:
		if stacks[pid] is int and world.seat_angles.has(pid):
			_set_stack(pid, stacks[pid])
	for pid in _bets.keys():
		_set_bets(pid, [])


func rebuy(pid: int, stack: int) -> void:
	# 再领:一摞新筹码从座位前上方落下
	var epoch := _epoch
	var added := stack - stack_amount(pid)
	if added <= 0 or not world.seat_angles.has(pid):
		_set_stack(pid, stack)
		return
	sfx.emit("chips")
	var spot := _stack_spot(pid)
	var flyer := _launch(added, spot + Vector3.UP * DROP_HEIGHT, pid)
	var ref: WeakRef = weakref(flyer)
	var tween := create_tween()
	tween.tween_method(func(y: float) -> void:
		var node: Node3D = ref.get_ref()
		if node != null:
			node.position.y = y,
		spot.y + DROP_HEIGHT, spot.y, REBUY_DROP).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await tween.finished
	_land([flyer])
	if epoch == _epoch:
		_set_stack(pid, stack)


func refund(pid: int, stack: int) -> void:
	# 离开时下注阶段的注退回:不演,直接定格
	_set_bets(pid, [])
	_set_stack(pid, stack)


# —— 内部 ——

func _stack_spot(pid: int) -> Vector3:
	return BjLayout.stack_position(world.seat_angle_now(pid), world.table_radius, pid == world.my_pid)


func _bet_spot(pid: int, hand: int) -> Vector3:
	var count := maxi(_bets.get(pid, []).size(), hand + 1)
	return BjLayout.bet_position(world.seat_angle_now(pid), world.table_radius, hand, count, pid == world.my_pid)


func _follow_seats() -> void:
	for pid in _stacks:
		_pin(_stacks[pid], pid, _stack_spot(pid))
	for pid in _bets:
		var bets: Array = _bets[pid]
		for hand in bets.size():
			if bets[hand] != null:
				_pin(bets[hand], pid, _bet_spot(pid, hand))


func _pin(node: Node3D, pid: int, spot: Vector3) -> void:
	if world.seat_angles.has(pid):
		node.position = spot
		node.rotation = Vector3(0.0, -world.seat_angle_now(pid), 0.0)


func _set_stack(pid: int, amount: int) -> void:
	if amount <= 0:
		if _stacks.has(pid):
			_stacks[pid].queue_free()
			_stacks.erase(pid)
		return
	if not _stacks.has(pid):
		if not world.seat_angles.has(pid):
			return
		_stacks[pid] = _new_stack()
		_pin(_stacks[pid], pid, _stack_spot(pid))
	_stacks[pid].set_amount(amount)


func _resize_bets(pid: int, count: int) -> void:
	var bets: Array = _bets.get(pid, [])
	while bets.size() < count:
		bets.append(null)
	_bets[pid] = bets


func _set_bets(pid: int, amounts: Array) -> void:
	var bets: Array = _bets.get(pid, [])
	for i in range(amounts.size(), bets.size()):
		if bets[i] != null:
			bets[i].queue_free()
	bets.resize(amounts.size())
	_bets[pid] = bets
	for i in amounts.size():
		_set_bet(pid, i, amounts[i])
	if amounts.is_empty():
		_bets.erase(pid)


func _set_bet(pid: int, hand: int, amount: int) -> void:
	_resize_bets(pid, hand + 1)
	var bets: Array = _bets[pid]
	if amount <= 0:
		if bets[hand] != null:
			bets[hand].queue_free()
			bets[hand] = null
		return
	if bets[hand] == null:
		if not world.seat_angles.has(pid):
			return
		bets[hand] = _new_stack()
		_pin(bets[hand], pid, _bet_spot(pid, hand))
	bets[hand].set_amount(amount)


func _new_stack() -> ChipStack3D:
	var stack := ChipStack3D.new()
	add_child(stack)
	return stack


func _launch(amount: int, from: Vector3, pid: int) -> ChipStack3D:
	var flyer := _new_stack()
	flyer.set_amount(amount)
	flyer.position = from
	flyer.rotation = Vector3(0.0, -world.seat_angle_now(pid), 0.0)
	_flyers.append(flyer)
	return flyer


func _fly(flights: Array, duration: float) -> void:
	# flights: [[节点, 目标位置]]:沿抬起的弧线同时滑过去,到了就收走;节点半路可能被对账收走,只捕获弱引用
	var tween := create_tween().set_parallel()
	for flight in flights:
		var ref: WeakRef = weakref(flight[0])
		var from: Vector3 = flight[0].position
		var to: Vector3 = flight[1]
		var mid := (from + to) / 2.0 + Vector3.UP * SLIDE_ARC
		tween.tween_method(func(t: float) -> void:
			var node: Node3D = ref.get_ref()
			if node != null:
				node.position = from.lerp(mid, t).lerp(mid.lerp(to, t), t),
			0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	_land(flights.map(func(flight): return flight[0]))


func _land(nodes: Array) -> void:
	for node in nodes:
		_flyers.erase(node)
		if is_instance_valid(node):
			node.queue_free()


func _drop_flyers() -> void:
	_land(_flyers.duplicate())
	_flyers = []


func _wait(seconds: float) -> void:
	var tween := create_tween()
	tween.tween_interval(maxf(seconds, 0.0))
	await tween.finished


static func _int(d: Dictionary, key: String) -> int:
	return d[key] if d.get(key) is int else 0
