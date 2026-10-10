class_name DdzCards
extends Node3D
# 斗地主的牌层(挂在 TableWorld.poker_root 下,拆台时 clear_poker 一并收走):
# 桌心扣着的 3 张底牌、各家牌扇里的手牌(别人的是德州牌背,张数多时压缩扇面;自己的亮面,大的在左)、
# 每人面前的出牌行(正面朝上,按本机视角正立)、一手结束时摊开的剩牌。
# 动画方法都是协程,等的是挂在本节点上的补间:牌半路被对账(sync)或拆台收走时导演也不会卡住;
# 对账先停下牌还在走的飞行补间(记在牌的 meta 上),回来的协程发现已经对过账(_epoch 变了)就不再动它。
# 只认已公开的牌:别人的牌扇永远是牌背,只有出牌、底牌亮出、一手结束摊牌时才翻成正面(id 来自公共事件)。
# 音效通过 sfx 信号交给上层播放。


signal sfx(name: String)

const DEAL_SPAN := 1.7          # 发牌:所有牌出手的总时长上限
const REDEAL_SPAN := 1.35       # 重发:收牌之后发得快一点
const DEAL_STAGGER_MAX := 0.035
const DEAL_FLIGHT := 0.3
const DEAL_TAIL := 0.05
const DEAL_ARC := 0.16
const SWEEP_FLIGHT := 0.4       # 收牌(新的一手 / 重发):桌上与各家手里的牌飞回发牌处
const BOTTOM_FLIP := 0.3        # 底牌翻开
const BOTTOM_HOLD := 0.35       # 翻开后亮一会儿
const BOTTOM_FLIGHT := 0.45     # 再飞进地主手里
const PLAY_FLIGHT := 0.4        # 出牌:从手里飞到面前的出牌行,路上翻成正面
const PLAY_STAGGER := 0.008     # 一手里相邻两张出手的间隔(最多 20 张也只多 0.15 秒,算在 PLAY_FLIGHT_MAX 里)
const PLAY_FLIGHT_MAX := PLAY_FLIGHT + PLAY_STAGGER * 19
const PLAY_ARC := 0.12
const PLAY_SPIN := 0.35
const CLEAR_FLIGHT := 0.25      # 被自己下一手顶掉 / 不出时,面前上一手的牌收走
const TRICK_SWEEP := 0.32       # 清桌:三行牌一起收向桌心、缩小消失
const WAVE_TIME := 0.55         # 顺子 / 连对:一串牌从左到右像波浪一样亮起(跳一下)
const WAVE_LIFT := 0.035
const REVEAL_FLIGHT := 0.5      # 一手结束:别人的剩牌从牌扇里摊到面前,翻成正面
const LAYOUT_TIME := 0.18
const LIFT_HOVER := 0.012
const LIFT_SELECTED := 0.035
const GLOW_SELECTED := 0.75
const GLOW_HOVER := 0.3
const WAVE_COLOR := Color(1.0, 0.85, 0.45)
const FLIGHT_META := &"ddz_flight"

var world: TableWorld
var my_pid := 0
var _held := {}                  # pid -> [DdzCard3D]:牌扇里的(或正飞向牌扇的);自己的按牌 id 升序
var _rows := {}                  # pid -> [DdzCard3D]:面前出牌行(从左到右)
var _bottom: Array = []          # 桌心的 3 张底牌(扣着或翻开)
var _selected := {}
var _hovered := -1
var _epoch := 0


func _init(p_world: TableWorld) -> void:
	world = p_world
	name = "DdzCards"
	world.first_person_changed.connect(_on_first_person_changed)


# —— 查询 ——

static func deal_stagger(cards: int, span := DEAL_SPAN) -> float:
	return minf(DEAL_STAGGER_MAX, span / maxf(cards - 1, 1))


static func deal_duration(cards: int, span := DEAL_SPAN) -> float:
	return maxi(cards - 1, 0) * deal_stagger(cards, span) + DEAL_FLIGHT + DEAL_TAIL


static func play_duration(count: int) -> float:
	return PLAY_FLIGHT + maxi(count - 1, 0) * PLAY_STAGGER


func held_count(pid: int) -> int:
	return held_cards(pid).size()


func held_cards(pid: int) -> Array:
	return _held.get(pid, []).filter(func(c): return is_instance_valid(c))


func held_ids(pid: int) -> Array:
	return held_cards(pid).map(func(c: DdzCard3D) -> int: return c.card_id)


func my_ids() -> Array:
	return held_ids(my_pid)


func row_cards(pid: int) -> Array:
	return _rows.get(pid, []).filter(func(c): return is_instance_valid(c))


func row_ids(pid: int) -> Array:
	return row_cards(pid).map(func(c: DdzCard3D) -> int: return c.card_id)


func bottom_cards() -> Array:
	return _bottom.filter(func(c): return is_instance_valid(c))


func bottom_ids() -> Array:
	return bottom_cards().map(func(c: DdzCard3D) -> int: return c.card_id)


func all_cards() -> Array:
	var out := bottom_cards()
	for pid in _held:
		out.append_array(held_cards(pid))
	for pid in _rows:
		out.append_array(row_cards(pid))
	return out


func face_up_ids_of_others() -> Array:
	# 别人牌扇里亮着正面的牌 id(隐藏信息检查用:一手结束之前必须为空)
	var out := []
	for pid in _held:
		if pid == my_pid:
			continue
		for card in held_cards(pid):
			if not card.is_back():
				out.append(card.card_id)
	return out


func hoverable_cards() -> Array:
	# 本机能悬停放大(CardPreview)的牌:自己牌扇里的、桌上各行亮着的、翻开的底牌(牌背由 CardPreview 自己排除)
	var out := held_cards(my_pid) + bottom_cards()
	for pid in _rows:
		out.append_array(row_cards(pid))
	return out


func row_center(pid: int) -> Vector3:
	return global_transform * DdzLayout.row_center(world.seat_angles.get(pid, 0.0), pid == my_pid)


func across_from(pid: int) -> Vector3:
	# 纸飞机的终点(贴着桌面):左右翻过来、再往桌子里侧挪,飞机从桌子远端掠过去,越肩机位里不被自己的头挡住
	var c := DdzLayout.row_center(world.seat_angles.get(pid, 0.0), pid == my_pid)
	return global_transform * Vector3(-c.x, c.y, minf(c.z, -0.1) - 0.15)


# —— 对账 ——

func sync(counts: Dictionary, my_hand: Array, rows: Dictionary, bottom_hidden: bool) -> void:
	# 按视图瞬时摆好:counts = pid → 手牌张数(自己的按 my_hand);rows = pid → 面前的牌 id;bottom_hidden = 桌心扣着 3 张底牌。
	# 对得上的牌留着,对不上的换掉;先停下所有还在走的动画
	_epoch += 1
	for pid in _held.keys():
		if not counts.has(pid) or not world.patrons.has(pid):
			_free_cards(_held[pid])
			_held.erase(pid)
	for pid in counts:
		if not world.patrons.has(pid):
			continue
		var want: Array = my_hand.filter(DdzHand.is_card) if pid == my_pid else []
		if pid != my_pid:
			for i in maxi(int(counts[pid]), 0):
				want.append(DdzCard3D.BACK)
		var have := held_cards(pid)
		var ids: Array = have.map(func(c: DdzCard3D) -> int: return c.card_id)
		if ids != want:
			_free_cards(have)
			have = want.map(func(id: int) -> DdzCard3D: return _new_card(id, DdzLayout.deck_transform()))
		_held[pid] = have
	for pid in _rows.keys():
		if not rows.has(pid):
			_free_cards(_rows[pid])
			_rows.erase(pid)
	for pid in rows:
		var want_row: Array = DdzLayout.row_order(rows[pid])
		var have_row := row_cards(pid)
		if have_row.map(func(c: DdzCard3D) -> int: return c.card_id) != want_row:
			_free_cards(have_row)
			have_row = want_row.map(func(id: int) -> DdzCard3D: return _new_card(id, Transform3D()))
		_rows[pid] = have_row
	var bottom := bottom_cards()
	if bottom_hidden and (bottom.size() != DdzState.BOTTOM_SIZE or bottom.any(func(c: DdzCard3D) -> bool: return not c.is_back())):
		_free_cards(bottom)
		bottom = []
		for i in DdzState.BOTTOM_SIZE:
			bottom.append(_new_card(DdzCard3D.BACK, DdzLayout.bottom_slot(i)))
	elif not bottom_hidden:
		_free_cards(bottom)
		bottom = []
	_bottom = bottom
	_present_my_fan()
	_settle_all()


func set_selection(selected: Dictionary, hovered: int) -> void:
	_selected = selected.duplicate()
	_hovered = hovered
	_layout(my_pid, LAYOUT_TIME * 0.6)


func clear() -> void:
	_epoch += 1
	for pid in _held:
		_free_cards(_held[pid])
	for pid in _rows:
		_free_cards(_rows[pid])
	_free_cards(_bottom)
	_held = {}
	_rows = {}
	_bottom = []


# —— 动画(协程)——

func sweep_all() -> void:
	# 新的一手 / 重发:桌上的牌与各家手里的牌一起飞回发牌处、缩小消失
	var cards := all_cards()
	_epoch += 1
	_held = {}
	_rows = {}
	_bottom = []
	var target := global_transform * DdzLayout.deck_transform().scaled_local(Vector3.ONE * 0.5)
	for card in cards:
		_lift_out(card)
		_fly(card, target, SWEEP_FLIGHT * randf_range(0.8, 1.0), 0.1, randf_range(-1.0, 1.0))
	if not cards.is_empty():
		sfx.emit("sweep")
	await _wait(SWEEP_FLIGHT)
	_free_cards(cards)


func deal(order: Array, counts: Dictionary, my_hand: Array, span := DEAL_SPAN) -> void:
	# 发牌:3 张底牌先扣到桌心,再每人一轮一张、轮流发到牌扇里;自己的按 my_hand(升序)亮面,牌扇里大的在左
	var epoch := _epoch
	_present_my_fan()
	for pid in order:
		_free_cards(_held.get(pid, []))
		_held[pid] = []
	_free_cards(_bottom)
	_bottom = []
	var rounds := 0
	var total := DdzState.BOTTOM_SIZE
	for pid in order:
		rounds = maxi(rounds, int(counts.get(pid, 0)))
		total += int(counts.get(pid, 0))
	var stagger := deal_stagger(total, span)
	var dealt := 0
	for i in DdzState.BOTTOM_SIZE:
		var card := _new_card(DdzCard3D.BACK, DdzLayout.deck_transform())
		card.visible = false
		_bottom.append(card)
		_deal_bottom(card, i, dealt * stagger)
		dealt += 1
	var mine := my_hand.filter(DdzHand.is_card)
	for r in rounds:
		for pid in order:
			var n := int(counts.get(pid, 0))
			if r >= n or not world.patrons.has(pid):
				continue
			var id: int = mine[r] if pid == my_pid and r < mine.size() else DdzCard3D.BACK
			var card := _new_card(id, DdzLayout.deck_transform())
			card.visible = false
			_held[pid].append(card)
			_deal_one(card, pid, r, n, dealt * stagger)
			dealt += 1
	await _wait(deal_duration(total, span))
	if epoch == _epoch:
		_settle_all()


func _deal_bottom(card: DdzCard3D, i: int, delay: float) -> void:
	var epoch := _epoch
	await _wait(delay)
	if epoch != _epoch or not is_instance_valid(card):
		return
	card.visible = true
	_fly(card, global_transform * DdzLayout.bottom_slot(i), DEAL_FLIGHT, 0.06)


func _deal_one(card: DdzCard3D, pid: int, index: int, count: int, delay: float) -> void:
	var epoch := _epoch
	await _wait(delay)
	if epoch != _epoch or not is_instance_valid(card) or not world.patrons.has(pid):
		return
	card.visible = true
	if index % 3 == 0:
		sfx.emit("deal")
	var fan: Node3D = world.patrons[pid].fan
	# 自己的牌按 id 升序发出,牌扇里大的在左:第 index 张先按「发到第几张」排在右边,发完由 _settle_all 重排
	var slot := BombCatLayout.fan_slot(index, count) if pid != my_pid else DdzLayout.fan_slot(index, count)
	_fly(card, fan.global_transform * slot, DEAL_FLIGHT, DEAL_ARC)
	await _wait(DEAL_FLIGHT)
	if epoch == _epoch and is_instance_valid(card) and is_instance_valid(fan):
		card.reparent(fan, true)


func reveal_bottom(ids: Array, landlord: int, my_hand_after: Array) -> void:
	# 定地主:桌心 3 张底牌翻开、亮一会儿,再飞进地主手里(自己是地主时按 my_hand_after 插进牌扇里该在的位置)
	var epoch := _epoch
	var cards := bottom_cards()
	while cards.size() < ids.size():
		var extra := _new_card(DdzCard3D.BACK, DdzLayout.bottom_slot(cards.size()))
		_bottom.append(extra)
		cards.append(extra)
	for i in cards.size():
		var card: DdzCard3D = cards[i]
		_stop_flight(card)
		var id: int = ids[i] if i < ids.size() else DdzCard3D.BACK
		_flip_to(card, id, global_transform * DdzLayout.bottom_slot(i, true), BOTTOM_FLIP)
	sfx.emit("flip")
	await _wait(BOTTOM_FLIP)
	if epoch != _epoch:
		return
	for card in cards:
		if is_instance_valid(card):
			card.pulse_glow(WAVE_COLOR, 1.4, BOTTOM_HOLD + 0.2)
	await _wait(BOTTOM_HOLD)
	if epoch != _epoch or not world.patrons.has(landlord):
		return
	_bottom = []
	var fan: Node3D = world.patrons[landlord].fan
	var held := held_cards(landlord)
	if landlord == my_pid:
		# 自己:三张牌飞到排好序之后各自的位置,剩下的牌同时让开
		var by_id := {}
		for c in held:
			by_id[c.card_id] = c
		for c in cards:
			by_id[c.card_id] = c
		var ordered := []
		for id in my_hand_after:
			if by_id.has(id):
				ordered.append(by_id[id])
		_held[landlord] = ordered
		for c in cards:
			var at := ordered.find(c)
			_fly(c, fan.global_transform * DdzLayout.fan_slot(at, ordered.size()), BOTTOM_FLIGHT, 0.16, 0.6)
		for c in held:
			_layout_one(landlord, c, BOTTOM_FLIGHT)
	else:
		for c in cards:
			held.append(c)
		_held[landlord] = held
		for i in cards.size():
			var c: DdzCard3D = cards[i]
			_fly(c, fan.global_transform * BombCatLayout.fan_slot(held.size() - cards.size() + i, held.size()), BOTTOM_FLIGHT, 0.16, 0.6)
		_layout(landlord, BOTTOM_FLIGHT)
	sfx.emit("slide")
	await _wait(BOTTOM_FLIGHT)
	if epoch != _epoch:
		return
	for c in cards:
		if is_instance_valid(c) and is_instance_valid(fan):
			_stop_flight(c)
			if landlord != my_pid:
				c.set_card(DdzCard3D.BACK)   # 进了别人手里:又是牌背(大家都记得是哪三张,但牌扇里不亮面)
			c.reparent(fan, true)
	_layout(landlord, 0.0)


func play(pid: int, ids: Array) -> void:
	# 出牌:从手里拿出这几张(自己的按 id 找,别人的从牌扇末尾拿),飞到面前的出牌行、路上翻成正面;他面前上一手的牌先收走
	var epoch := _epoch
	_clear_row(pid)
	var order := DdzLayout.row_order(ids)
	var nodes := _take(pid, order)
	var angle: float = world.seat_angles.get(pid, 0.0)
	for i in nodes.size():
		var card: DdzCard3D = nodes[i]
		card.set_card(order[i] if i < order.size() else DdzCard3D.BACK)
		card.set_glow(0.0)
		_fly_later(card, global_transform * DdzLayout.play_slot(angle, pid == my_pid, i, nodes.size()), i * PLAY_STAGGER)
	_rows[pid] = nodes
	sfx.emit("slide")
	_layout(pid, LAYOUT_TIME)
	await _wait(play_duration(nodes.size()))
	if epoch == _epoch:
		_settle_row(pid)
		sfx.emit("card_slap")


func _fly_later(card: DdzCard3D, target: Transform3D, delay: float) -> void:
	if delay > 0.0:
		await _wait(delay)
	if is_instance_valid(card):
		_fly(card, target, PLAY_FLIGHT, PLAY_ARC, PLAY_SPIN)


func wave(pid: int) -> void:
	# 顺子 / 连对:一串牌从左到右依次跳一下、亮一下(不阻塞,总长 WAVE_TIME)
	var cards := row_cards(pid)
	if cards.is_empty():
		return
	var step := (WAVE_TIME - 0.24) / maxf(cards.size() - 1, 1)
	for i in cards.size():
		var card: DdzCard3D = cards[i]
		var rest := card.transform
		var tween: Tween = card.create_tween()
		tween.tween_interval(i * step)
		tween.tween_callback(func() -> void: card.pulse_glow(WAVE_COLOR, 1.8, 0.5))
		tween.tween_method(func(t: float) -> void:
			card.transform = rest.translated(Vector3.UP * WAVE_LIFT * sin(t * PI)), 0.0, 1.0, 0.24)
	sfx.emit("sparkle")


func pass_turn(pid: int) -> void:
	# 不出:他面前上一手的牌收走(「不出」牌子由特效层立起来)
	_clear_row(pid)


func clear_trick() -> void:
	# 两家不出:三行牌一起收向桌心、缩小消失
	var cards := []
	for pid in _rows:
		cards.append_array(row_cards(pid))
	_rows = {}
	var target := global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * DdzLayout.SWEEP_SCALE), DdzLayout.sweep_point())
	for card in cards:
		_lift_out(card)
		_fly(card, target, TRICK_SWEEP, 0.06, randf_range(-0.8, 0.8))
	if not cards.is_empty():
		sfx.emit("sweep")
	await _wait(TRICK_SWEEP)
	_free_cards(cards)


func reveal_remaining(remaining: Dictionary) -> void:
	# 一手结束摊牌:别人牌扇里剩的牌飞到面前、翻成正面(remaining = pid → 牌 id,来自 hand_over);自己的留在牌扇里
	var epoch := _epoch
	var any := false
	for pid in remaining:
		if pid == my_pid or not world.patrons.has(pid):
			continue
		var ids: Array = DdzLayout.row_order(remaining[pid])
		if ids.is_empty():
			continue
		_clear_row(pid)
		var nodes := _take(pid, ids)
		var angle: float = world.seat_angles.get(pid, 0.0)
		for i in nodes.size():
			var card: DdzCard3D = nodes[i]
			card.set_card(ids[i] if i < ids.size() else DdzCard3D.BACK)
			_fly(card, global_transform * DdzLayout.play_slot(angle, false, i, nodes.size()), REVEAL_FLIGHT, 0.14, 0.4)
		_rows[pid] = nodes
		any = true
	if any:
		sfx.emit("flip")
	await _wait(REVEAL_FLIGHT)
	if epoch == _epoch:
		for pid in _rows:
			_settle_row(pid)


func pick(origin: Vector3, direction: Vector3) -> int:
	# 自己牌扇里被射线点中的那张(返回私有手牌下标);没点中 -1
	var best := -1
	var best_dist := INF
	var cards := held_cards(my_pid)
	for i in cards.size():
		var dist: float = cards[i].ray_hit_distance(origin, direction)
		if dist >= 0.0 and dist < best_dist:
			best_dist = dist
			best = i
	return best


# —— 摆放 ——

func _on_first_person_changed(_on: bool) -> void:
	_present_my_fan()


func present_my_fan() -> void:
	_present_my_fan()


func _present_my_fan() -> void:
	# 越肩:按 Patron 的举牌位置缩小、往右下挪(20 张的扇子别挡住桌面);第一人称:拿在镜头右侧
	if not world.patrons.has(my_pid) or not world.seat_angles.has(my_pid):
		return
	var me: Patron = world.patrons[my_pid]
	var seat := world.seat_transform(world.seat_angles[my_pid])
	if world.first_person:
		me.present_hand_first_person(seat, world.first_person_rest_view(my_pid), DdzLayout.FP_FAN_CAM, DdzLayout.FP_FAN_SCALE)
		return
	me.present_hand_to(world.third_person_view(my_pid).origin)
	me.hold_fan(me.fan.transform.translated(DdzLayout.FAN_SHIFT_ME))
	me.hold_fan(me.fan.transform.scaled_local(Vector3.ONE * DdzLayout.FAN_SCALE_ME))


func _settle_all() -> void:
	for pid in _held:
		_layout(pid, 0.0)
	for pid in _rows:
		_settle_row(pid)
	for i in _bottom.size():
		var card: DdzCard3D = _bottom[i]
		if is_instance_valid(card):
			_stop_flight(card)
			if card.get_parent() != self:
				card.reparent(self, false)
			card.transform = DdzLayout.bottom_slot(i, not card.is_back())
			card.visible = true


func _settle_row(pid: int) -> void:
	var cards := row_cards(pid)
	var angle: float = world.seat_angles.get(pid, 0.0)
	for i in cards.size():
		var card: DdzCard3D = cards[i]
		_stop_flight(card)
		if card.get_parent() != self:
			card.reparent(self, false)
		card.transform = DdzLayout.play_slot(angle, pid == my_pid, i, cards.size())
		card.visible = true


func _layout(pid: int, duration: float, skip: Node3D = null) -> void:
	if not world.patrons.has(pid):
		return
	for card in held_cards(pid):
		if card != skip:
			_layout_one(pid, card, duration)


func _layout_one(pid: int, card: DdzCard3D, duration: float) -> void:
	if not world.patrons.has(pid):
		return
	var fan: Node3D = world.patrons[pid].fan
	var cards := held_cards(pid)
	var i := cards.find(card)
	if i < 0:
		return
	var mine := pid == my_pid
	var lift := 0.0
	if mine:
		lift = LIFT_SELECTED if _selected.has(i) else (LIFT_HOVER if i == _hovered else 0.0)
		card.set_glow(GLOW_SELECTED if _selected.has(i) else (GLOW_HOVER if i == _hovered else 0.0))
	var slot := DdzLayout.fan_slot(i, cards.size(), lift) if mine else BombCatLayout.fan_slot(i, cards.size(), 0.0)
	if card.get_parent() != fan:
		if duration <= 0.0:
			_stop_flight(card)
			card.reparent(fan, false)
			card.transform = slot
			card.visible = true
		elif not card.has_meta(FLIGHT_META):
			_fly(card, fan.global_transform * slot, duration, 0.02)
		return
	if card.has_meta(FLIGHT_META):
		return
	if duration <= 0.0:
		card.transform = slot
	else:
		var tween: Tween = card.create_tween()
		tween.tween_property(card, "transform", slot, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _clear_row(pid: int) -> void:
	var cards := row_cards(pid)
	_rows.erase(pid)
	if cards.is_empty():
		return
	var target := global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * DdzLayout.SWEEP_SCALE), DdzLayout.sweep_point())
	for card in cards:
		_lift_out(card)
		_fly(card, target, CLEAR_FLIGHT, 0.04, 0.0)
		var tween: Tween = card.create_tween()
		tween.tween_interval(CLEAR_FLIGHT)
		tween.tween_callback(card.queue_free)


func _take(pid: int, ids: Array) -> Array:
	# 从 pid 手里拿出 ids 那几张(自己的按 id 找;别人的从牌扇末尾拿,手里不够就在他胸前补),拿到本节点下(保持世界位置)
	var cards := held_cards(pid)
	var taken := []
	if pid == my_pid:
		for id in ids:
			for card in cards:
				if card.card_id == id and not taken.has(card):
					taken.append(card)
					break
	else:
		for i in mini(ids.size(), cards.size()):
			taken.append(cards[cards.size() - 1 - i])
	for card in taken:
		if _held.has(pid):
			_held[pid].erase(card)
		_lift_out(card)
	while taken.size() < ids.size():
		var origin := world.head_position(pid) + Vector3(0, -0.4, 0) if world.seat_angles.has(pid) else global_transform * DdzLayout.deck_transform().origin
		var card := _new_card(DdzCard3D.BACK, Transform3D())
		card.global_transform = Transform3D(Basis(), origin)
		taken.append(card)
	return taken


# —— 工具 ——

func _new_card(id: int, xform: Transform3D) -> DdzCard3D:
	var card := DdzCard3D.new(id)
	add_child(card)
	card.transform = xform
	return card


func _flip_to(card: DdzCard3D, id: int, target: Transform3D, duration: float) -> void:
	# 原地翻开:飞到正面朝上的位置(路上转半圈),中途换牌面
	_fly(card, target, duration, 0.08)
	var tween: Tween = card.create_tween()
	tween.tween_interval(duration * 0.5)
	tween.tween_callback(func() -> void: card.set_card(id))


func _fly(card: DdzCard3D, target: Transform3D, duration: float, arc: float, spin := 0.0) -> void:
	_stop_flight(card)
	var tween := card.fly_to(target, duration, arc, spin)
	card.set_meta(FLIGHT_META, tween)
	var tween_id := tween.get_instance_id()
	tween.finished.connect(func() -> void:
		if is_instance_valid(card) and card.has_meta(FLIGHT_META):
			var current: Variant = card.get_meta(FLIGHT_META)
			if current is Tween and current.get_instance_id() == tween_id:
				card.remove_meta(FLIGHT_META), CONNECT_ONE_SHOT)


func _stop_flight(card: Node) -> void:
	if card.has_meta(FLIGHT_META):
		var tween: Tween = card.get_meta(FLIGHT_META)
		if tween != null and tween.is_valid():
			tween.kill()
		card.remove_meta(FLIGHT_META)


func _lift_out(card: DdzCard3D) -> void:
	_stop_flight(card)
	card.visible = true
	if card.get_parent() != self:
		card.reparent(self, true)


func _wait(seconds: float) -> void:
	var tween := create_tween()
	tween.tween_interval(maxf(seconds, 0.0))
	await tween.finished


func _free_cards(cards: Array) -> void:
	for card in cards:
		if card != null and is_instance_valid(card):
			card.queue_free()
