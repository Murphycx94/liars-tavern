class_name BombCatCards
extends Node3D
# 炸弹猫的牌层(挂在 TableWorld.poker_root 下,拆台时 clear_poker 一并收走):
# 桌心的牌堆(按张数缩放的纸边盒子 + 顶上一张牌背)与弃牌堆(纸边盒子 + 顶上几张稍乱的正面牌)、
# 各家牌扇里的手牌(别人的是牌背,张数多时压缩扇面)、自己的牌扇(越肩 / 第一人称)、摸到的炸弹、偷看时浮在镜头前的三张牌。
# 动画方法都是协程,等的是挂在本节点上的补间:牌半路被对账(sync)或拆台收走时导演也不会卡住;
# 对账先停下牌还在走的飞行补间(记在牌的 meta 上),回来的协程发现已经对过账(_epoch 变了)就不再动它。
# 音效通过 sfx 信号交给上层播放。


signal sfx(name: String)

const DEAL_SPAN := 1.9          # 发牌:所有牌出手的总时长上限(人多时每张间隔更短)
const DEAL_STAGGER_MAX := 0.06
const DEAL_FLIGHT := 0.3
const DEAL_TAIL := 0.05
const DEAL_ARC := 0.2
const PLAY_FLIGHT := 0.45       # 出牌:从手里飞到弃牌堆,路上翻成正面
const PLAY_ARC := 0.18
const PLAY_SPIN := 0.5
const NOPE_RISE := 0.16         # 不行!:先飞到弃牌堆正上方,再「啪」地拍下去
const NOPE_SLAM := 0.08
const NOPE_HEIGHT := 0.22
const DRAW_FLIGHT := 0.35       # 摸牌:从牌堆顶滑到手里
const DRAW_ARC := 0.14
const TRANSFER_FLIGHT := 0.5   # 讨要 / 抽牌:一张牌从一人手里飞到另一人手里
const TRANSFER_ARC := 0.3
const BOMB_FLIGHT := 0.4        # 炸弹从牌堆顶翻起来,立在摸牌人面前
const REINSERT_FLIGHT := 0.5    # 炸弹被偷偷塞回牌堆(插进牌堆中间)
const DROP_FLIGHT := 0.5        # 出局者的手牌散进弃牌堆底
const SHUFFLE_TIME := 1.15      # 洗牌:牌堆炸成一股小龙卷风(一圈牌背绕着转、越转越高),再落回来叠好
const SHUFFLE_BOUNCE := 0.16    # 落回之后牌堆「噗」地一弹
const TORNADO_CARDS := 12
const TORNADO_RADIUS := 0.25
const TORNADO_HEIGHT := 0.42
const PEEK_RISE := 0.32         # 偷看:牌堆顶三张浮起来排成发光的扇面(只有偷看的人看到正面)
const PEEK_SINK := 0.25
const PEEK_FAN_HEIGHT := 0.2
const PEEK_FAN_SPACING := 0.095
const JIGGLE_TIME := 0.18       # 「不行!」盖章时桌上的牌一震
const LAYOUT_TIME := 0.18       # 牌扇重排
const LIFT_HOVER := 0.012
const LIFT_SELECTED := 0.035
const GLOW_SELECTED := 0.75
const GLOW_HOVER := 0.3
const BOX_INSET := 0.96         # 纸边盒子比牌略小(牌是圆角,盒子是方角)
const FLIGHT_META := &"bomb_flight"
const SPARK_LOCAL := Vector3(0.019, 0.004, -0.035)   # 炸弹牌面上导火索火花的位置(牌的局部坐标,未缩放)

var world: TableWorld
var my_pid := 0
var deck_count := 0
var discard_count := 0
var _deck_box: MeshInstance3D
var _deck_mesh: BoxMesh
var _deck_top: BombCard3D
var _discard_box: MeshInstance3D
var _discard_mesh: BoxMesh
var _discard_cards: Array = []   # BombCard3D:弃牌堆顶上摊开的(最早的在前)
var _held := {}                  # pid -> [BombCard3D]:牌扇里的(或正飞向牌扇的)
var _selected := {}
var _hovered := -1
var _peek: Array = []
var _bomb: BombCard3D = null
var _sparks: GPUParticles3D = null
var _rising: Array = []          # 偷看时浮起来的三张(临时的,演完自己释放)
var _tornado: Array = []         # 洗牌龙卷风里的牌(临时的)
var _epoch := 0


func _init(p_world: TableWorld) -> void:
	world = p_world
	name = "BombCatCards"
	_deck_mesh = BoxMesh.new()
	_deck_box = MeshKit.add(self, _deck_mesh, BombCatFaces.edge_material(), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF)
	_deck_box.name = "DeckStack"
	_deck_top = BombCard3D.new()
	_deck_top.name = "DeckTop"
	add_child(_deck_top)
	_discard_mesh = BoxMesh.new()
	_discard_box = MeshKit.add(self, _discard_mesh, BombCatFaces.edge_material(), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF)
	_discard_box.name = "DiscardStack"
	world.first_person_changed.connect(_on_first_person_changed)
	_set_deck(0)
	_set_discard_base()


# —— 查询 ——

static func deal_stagger(cards: int) -> float:
	return minf(DEAL_STAGGER_MAX, DEAL_SPAN / maxf(cards - 1, 1))


static func deal_duration(cards: int) -> float:
	return maxi(cards - 1, 0) * deal_stagger(cards) + DEAL_FLIGHT + DEAL_TAIL


func held_count(pid: int) -> int:
	return _held.get(pid, []).filter(func(c): return is_instance_valid(c)).size()


func held_cards(pid: int) -> Array:
	return _held.get(pid, []).filter(func(c): return is_instance_valid(c))


func my_ids() -> Array:
	return held_cards(my_pid).map(func(c: BombCard3D) -> String: return c.card_id)


func discard_ids() -> Array:
	return _discard_cards.filter(func(c): return is_instance_valid(c)).map(func(c: BombCard3D) -> String: return c.card_id)


func deck_top_node() -> BombCard3D:
	return _deck_top


func bomb_node() -> BombCard3D:
	return _bomb if is_instance_valid(_bomb) else null


func hoverable_cards() -> Array:
	# 本机能悬停放大(CardPreview)的牌:自己牌扇里的手牌、弃牌堆顶上摊开的几张(牌背由 CardPreview 自己排除)
	return held_cards(my_pid) + _discard_cards.filter(func(c): return is_instance_valid(c))


func peek_nodes() -> Array:
	return _peek.filter(func(c): return is_instance_valid(c))


func rising_nodes() -> Array:
	return _rising.filter(func(c): return is_instance_valid(c))


func tornado_nodes() -> Array:
	return _tornado.filter(func(c): return is_instance_valid(c))


# —— 对账 ——

func sync(counts: Dictionary, my_hand: Array, p_deck_count: int, p_discard_count: int, top_ids: Array, keep_bomb := false) -> void:
	# 按视图瞬时摆好:counts = pid → 手牌张数(出局者 0;自己的按 my_hand),牌堆 / 弃牌堆张数,弃牌堆顶上的几张(最上面在最后)。
	# 牌型对得上的牌留着,对不上的换掉;先停下所有还在走的动画。keep_bomb:正在等人塞回炸弹,立着的炸弹牌留着
	_epoch += 1
	if not keep_bomb:
		_free_bomb()
	_set_deck(p_deck_count)
	discard_count = maxi(p_discard_count, 0)
	_sync_discard(top_ids)
	for pid in _held.keys():
		if not counts.has(pid) or not world.patrons.has(pid):
			_free_cards(_held[pid])
			_held.erase(pid)
	for pid in counts:
		if not world.patrons.has(pid):
			continue
		var want: Array = my_hand.filter(BombCatCard.is_valid) if pid == my_pid else []
		if pid != my_pid:
			for i in maxi(int(counts[pid]), 0):
				want.append(BombCatFaces.BACK)
		var have: Array = held_cards(pid)
		var ids: Array = have.map(func(c: BombCard3D) -> String: return c.card_id)
		if ids != want:
			_free_cards(have)
			have = want.map(func(id: String) -> BombCard3D: return _new_card(id, _deck_transform()))
		_held[pid] = have
	_present_my_fan()
	_settle_all()


func set_selection(selected: Dictionary, hovered: int) -> void:
	_selected = selected.duplicate()
	_hovered = hovered
	_layout(my_pid, LAYOUT_TIME * 0.6)


func clear() -> void:
	_epoch += 1
	clear_peek()
	_free_cards(_rising)
	_rising = []
	_free_cards(_tornado)
	_tornado = []
	_free_bomb()
	for pid in _held:
		_free_cards(_held[pid])
	_held = {}
	_free_cards(_discard_cards)
	_discard_cards = []
	discard_count = 0
	_set_deck(0)
	_set_discard_base()


# —— 动画(协程)——

func deal(order: Array, counts: Dictionary, my_hand: Array) -> void:
	# 开局:每人 counts[pid] 张从牌堆飞到手里(一轮一张、轮流发);自己的按 my_hand 亮面
	var epoch := _epoch
	_present_my_fan()
	for pid in order:
		_free_cards(_held.get(pid, []))
		_held[pid] = []
	var rounds := 0
	var total := 0
	for pid in order:
		rounds = maxi(rounds, int(counts.get(pid, 0)))
		total += int(counts.get(pid, 0))
	var stagger := deal_stagger(total)
	var dealt := 0
	for r in rounds:
		for pid in order:
			if r >= int(counts.get(pid, 0)) or not world.patrons.has(pid):
				continue
			var id: String = my_hand[r] if pid == my_pid and r < my_hand.size() else BombCatFaces.BACK
			var card := _new_card(id, _deck_transform())
			card.visible = false
			_held[pid].append(card)
			_deal_one(card, pid, r, int(counts[pid]), dealt * stagger)
			dealt += 1
	await _wait(deal_duration(total))
	if epoch == _epoch:
		_settle_all()


func _deal_one(card: BombCard3D, pid: int, index: int, count: int, delay: float) -> void:
	var epoch := _epoch
	await _wait(delay)
	if epoch != _epoch or not is_instance_valid(card) or not world.patrons.has(pid):
		return
	card.visible = true
	_set_deck(deck_count - 1)
	sfx.emit("deal")
	var fan: Node3D = world.patrons[pid].fan
	_fly(card, fan.global_transform * BombCatLayout.fan_slot(index, count), DEAL_FLIGHT, DEAL_ARC)
	await _wait(DEAL_FLIGHT)
	if epoch == _epoch and is_instance_valid(card) and is_instance_valid(fan):
		card.reparent(fan, true)


func play(pid: int, ids: Array, my_indices := []) -> void:
	# 出牌:从手里拿出这几张(自己的按提交时的下标),飞到弃牌堆、路上翻成正面
	var nodes := _take(pid, ids, my_indices)
	var landing := _discard_landing(nodes.size())
	for i in nodes.size():
		var card: BombCard3D = nodes[i]
		card.set_card(ids[i] if i < ids.size() else BombCatFaces.BACK)
		card.set_glow(0.0)
		_fly(card, global_transform * landing[i], PLAY_FLIGHT + i * 0.04, PLAY_ARC, PLAY_SPIN)
	sfx.emit("slide")
	_layout(pid, LAYOUT_TIME)
	await _wait(PLAY_FLIGHT + maxi(nodes.size() - 1, 0) * 0.04)
	_push_discard(nodes)
	sfx.emit("slap")


func nope_slam(pid: int) -> void:
	# 不行!:一张从手里飞到弃牌堆正上方,再狠狠拍下去
	var nodes := _take(pid, [BombCatCard.NOPE], [])
	var card: BombCard3D = nodes[0]
	card.set_card(BombCatCard.NOPE)
	var landing: Transform3D = _discard_landing(1)[0]
	var above := landing.translated(Vector3.UP * NOPE_HEIGHT)
	_fly(card, global_transform * above, NOPE_RISE, 0.08, 0.3)
	_layout(pid, LAYOUT_TIME)
	await _wait(NOPE_RISE)
	if is_instance_valid(card):
		_fly(card, global_transform * landing, NOPE_SLAM, 0.0)
	await _wait(NOPE_SLAM)
	_push_discard(nodes)
	sfx.emit("nope_slap")


func draw(pid: int, id: String, p_deck_count: int) -> void:
	# 摸牌:牌堆顶一张滑到手里(自己的翻成正面),牌堆矮一截
	var epoch := _epoch
	var card := _new_card(BombCatFaces.BACK, _deck_top.transform)
	_set_deck(p_deck_count)
	if pid == my_pid:
		card.set_card(id)
	if not world.patrons.has(pid):
		card.queue_free()
		return
	if not _held.has(pid):
		_held[pid] = []
	_held[pid].append(card)
	var count: int = _held[pid].size()
	var fan: Node3D = world.patrons[pid].fan
	sfx.emit("deal")
	_fly(card, fan.global_transform * BombCatLayout.fan_slot(count - 1, count), DRAW_FLIGHT, DRAW_ARC)
	_layout(pid, DRAW_FLIGHT, card)
	await _wait(DRAW_FLIGHT)
	if epoch == _epoch and is_instance_valid(card) and is_instance_valid(fan):
		card.reparent(fan, true)
		_layout(pid, 0.0)


func reveal_bomb(pid: int, p_deck_count: int, sparks := true) -> void:
	# 摸到炸弹:牌堆顶那张翻起来立在摸牌人面前(牌面朝桌心),导火索冒火花(sparks 为假时火花交给炸弹猫道具)
	_free_bomb()
	_set_deck(p_deck_count)
	_bomb = _new_card(BombCatCard.BOMB, _deck_top.transform.translated(Vector3.UP * 0.002))
	_bomb.name = "Bomb"
	var target := BombCatLayout.bomb_show(world.seat_angle_now(pid), world.seat_radius)
	sfx.emit("flip")
	_fly(_bomb, global_transform * target, BOMB_FLIGHT, 0.25, 0.0)
	if sparks:
		_sparks = Fx.fuse_sparks(_bomb, SPARK_LOCAL)
	await _wait(BOMB_FLIGHT)
	if is_instance_valid(_bomb):
		_bomb.pulse_glow(Color(1.0, 0.45, 0.2), 1.6, 0.8)


func reinsert(p_deck_count: int) -> void:
	# 炸弹被偷偷塞回牌堆:翻成背面、插进牌堆中间,牌堆高一截
	if not is_instance_valid(_bomb):
		_set_deck(p_deck_count)
		await _wait(REINSERT_FLIGHT)
		return
	var bomb := _bomb
	_bomb = null
	_stop_sparks()
	bomb.set_card(BombCatFaces.BACK)
	var middle := BombCatLayout.deck_top(maxi(p_deck_count - 1, 0) / 2)
	_fly(bomb, global_transform * middle, REINSERT_FLIGHT, 0.12, 0.6)
	sfx.emit("slide")
	await _wait(REINSERT_FLIGHT)
	_free_card(bomb)
	_set_deck(p_deck_count)


func blow_bomb() -> void:
	# 爆炸:炸弹牌炸没了(闪光与烟由导演放)
	_stop_sparks()
	_free_bomb()


func bomb_position() -> Vector3:
	return _bomb.global_position if is_instance_valid(_bomb) else global_transform * BombCatLayout.deck_position()


func discard_hand(pid: int) -> void:
	# 出局:手里的牌散进弃牌堆底(看不到是哪些),弃牌堆的纸边盒子高一截
	var cards := held_cards(pid)
	_held.erase(pid)
	var target := global_transform * Transform3D(Basis(Vector3.BACK, PI).scaled(Vector3.ONE * BombCatLayout.PILE_SCALE),
		BombCatLayout.discard_position() + Vector3(0, 0.01, 0))
	for card in cards:
		_lift_out(card)
		card.set_card(BombCatFaces.BACK)
		_fly(card, target, DROP_FLIGHT + randf() * 0.08, 0.2, randf_range(-1.0, 1.0))
	if not cards.is_empty():
		sfx.emit("sweep")
	await _wait(DROP_FLIGHT + 0.08)
	_free_cards(cards)
	discard_count += cards.size()
	_set_discard_base()


func transfer(from: int, to: int, id: String, on_card := Callable()) -> void:
	# 讨要 / 抽牌 / 点名:一张牌从 from 手里飞到 to 手里;只有当事人(id 非空)看得到正面,别人看到的是牌背。
	# on_card(card) 在牌出手时调用(导演拿去挂蝴蝶结 / 闪光拖尾)
	var epoch := _epoch
	var nodes := _take(from, [id] if from == my_pid and id != "" else [], [])
	var card: BombCard3D = nodes[0]
	card.set_card(id if to == my_pid else BombCatFaces.BACK)
	if not world.patrons.has(to):
		card.queue_free()
		return
	if on_card.is_valid():
		on_card.call(card)
	if not _held.has(to):
		_held[to] = []
	_held[to].append(card)
	var count: int = _held[to].size()
	var fan: Node3D = world.patrons[to].fan
	sfx.emit("slide")
	_fly(card, fan.global_transform * BombCatLayout.fan_slot(count - 1, count), TRANSFER_FLIGHT, TRANSFER_ARC, 1.2)
	_layout(from, LAYOUT_TIME)
	_layout(to, TRANSFER_FLIGHT, card)
	await _wait(TRANSFER_FLIGHT)
	if epoch == _epoch and is_instance_valid(card) and is_instance_valid(fan):
		card.reparent(fan, true)
		_layout(to, 0.0)


func shuffle() -> void:
	# 洗牌:牌堆顶上炸出一股小龙卷风——一圈牌背从牌堆里旋出来、绕着转、越转越高,再一张张旋回去,
	# 牌堆被压扁后「噗」地弹回原样。龙卷风里的牌是临时的,不改牌堆张数
	sfx.emit("tornado")
	var epoch := _epoch
	_free_cards(_tornado)
	_tornado = []
	var top := BombCatLayout.deck_top(maxi(deck_count - 1, 0))
	var base := top.origin
	var count := mini(TORNADO_CARDS, maxi(deck_count, 3))
	for i in count:
		var card := _new_card(BombCatFaces.BACK, top)
		card.name = "Tornado%d" % i
		_tornado.append(card)
	var box_scale := Vector3.ONE
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		for i in _tornado.size():
			var card: BombCard3D = _tornado[i]
			if not is_instance_valid(card):
				continue
			var k := float(i) / maxf(_tornado.size(), 1)
			# 每张错开一点出场 / 回场:0..0.3 旋出、0.3..0.72 绕圈升高、0.72..1 旋回牌堆
			var u := clampf((t - k * 0.12) / 0.88, 0.0, 1.0)
			var out := smoothstep(0.0, 0.3, u) * (1.0 - smoothstep(0.72, 1.0, u))
			var angle := k * TAU + u * TAU * 2.6
			var radius := TORNADO_RADIUS * out * (0.75 + 0.35 * k)
			var height := TORNADO_HEIGHT * out * (0.12 + 0.88 * k)
			var pos := base + Vector3(cos(angle) * radius, height, sin(angle) * radius)
			var tilt := Basis(Vector3.UP, -angle) * Basis(Vector3.RIGHT, out * 0.75) * Basis(Vector3.BACK, out * 0.45)
			card.transform = Transform3D(tilt.scaled(Vector3.ONE * BombCatLayout.PILE_SCALE * (1.0 - 0.3 * out)), pos)
		var squash := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.78, 1.0, t))
		_deck_box.scale = Vector3(box_scale.x * (1.0 + 0.12 * squash), box_scale.y * (1.0 - 0.55 * squash), box_scale.z * (1.0 + 0.12 * squash))
		_deck_top.visible = deck_count > 0 and squash < 0.2,
		0.0, 1.0, SHUFFLE_TIME)
	await tween.finished
	_free_cards(_tornado)
	_tornado = []
	if epoch != _epoch:
		return
	_set_deck(deck_count)
	# 叠好之后弹一下
	var bounce := create_tween()
	bounce.tween_method(func(v: float) -> void:
		var k := sin(v * PI) * (1.0 - v)
		_deck_box.scale = Vector3(1.0 - 0.1 * k, 1.0 + 0.45 * k, 1.0 - 0.1 * k)
		_deck_top.position.y = BombCatLayout.deck_top(maxi(deck_count - 1, 0)).origin.y + BombCatLayout.stack_height(deck_count - 1) * 0.225 * k,
		0.0, 1.0, SHUFFLE_BOUNCE)
	await bounce.finished
	if epoch == _epoch:
		_set_deck(deck_count)


func peek_rise(ids: Array, count: int, viewer: Vector3) -> void:
	# 偷看:牌堆顶 count 张浮起来排成一把发金光的扇面,正面朝 viewer(偷看的人);ids 是这几张的牌面——
	# 只有偷看的人自己传私有视图里的牌,别人传空(一律牌背)。浮在空中一会儿再落回牌堆(落回不阻塞)
	_free_cards(_rising)
	_rising = []
	var shown := mini(maxi(count, 0), 3)
	if shown == 0:
		return
	var top := BombCatLayout.deck_top(maxi(deck_count - 1, 0))
	var to_viewer := to_local(viewer) - top.origin
	to_viewer.y = 0.0
	var facing := BombCatLayout.facing(to_viewer if to_viewer.length() > 0.01 else Vector3.BACK)
	var right := facing.x.normalized()
	for i in shown:
		var id: String = ids[i] if i < ids.size() and BombCatCard.is_valid(str(ids[i])) else BombCatFaces.BACK
		var card := _new_card(id, top.translated(Vector3.UP * 0.002 * (shown - i)))
		card.name = "PeekRise%d" % i
		_rising.append(card)
		var k := float(i) - (shown - 1) / 2.0
		var slot := Transform3D((Basis(to_viewer.normalized() if to_viewer.length() > 0.01 else Vector3.BACK, -k * 0.22) * facing) \
			.scaled(Vector3.ONE * BombCatLayout.PILE_SCALE * 0.82), top.origin + right * k * PEEK_FAN_SPACING + Vector3(0, PEEK_FAN_HEIGHT - absf(k) * 0.02, 0))
		var tween := card.create_tween()
		tween.tween_interval(i * 0.05)
		tween.tween_property(card, "transform", slot, PEEK_RISE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func() -> void: card.pulse_glow(Color(1.0, 0.86, 0.45), 1.6, 0.9))
	sfx.emit("flip")
	await _wait(PEEK_RISE + 0.05 * (shown - 1))


func peek_sink() -> void:
	# 浮起来的三张落回牌堆顶、消失(偷看的那段演完后调用,不阻塞)
	var cards := rising_nodes()
	_rising = []
	var top := BombCatLayout.deck_top(maxi(deck_count - 1, 0))
	for card in cards:
		var tween: Tween = card.create_tween()
		tween.tween_property(card, "transform", top, PEEK_SINK).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(card.queue_free)


func jiggle(strength := 1.0) -> void:
	# 桌上的牌(牌堆、弃牌堆、飞行中的牌)一震:「不行!」盖章、爆炸
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		var k := (1.0 - t) * strength
		position = Vector3(sin(t * 55.0) * 0.006 * k, absf(sin(t * 38.0)) * 0.008 * k, cos(t * 47.0) * 0.005 * k), 0.0, 1.0, JIGGLE_TIME)
	tween.tween_callback(func() -> void: position = Vector3.ZERO)


func pulse_top(color: Color, peak := 1.8, duration := 0.5) -> void:
	# 窗口结算:作废的牌闪红、生效的牌闪金
	if not _discard_cards.is_empty() and is_instance_valid(_discard_cards[-1]):
		_discard_cards[-1].pulse_glow(color, peak, duration)


func show_peek(ids: Array, camera: Node3D) -> void:
	# 偷看:三张牌浮在镜头前(只在本机),弹出来
	clear_peek()
	if camera == null:
		return
	var shown: Array = ids.filter(BombCatCard.is_valid)
	for i in shown.size():
		var card := BombCard3D.new(shown[i])
		card.name = "Peek%d" % i
		camera.add_child(card)
		var slot := BombCatLayout.peek_slot(i, shown.size())
		card.transform = slot.scaled_local(Vector3.ONE * 0.05)
		var tween := card.create_tween()
		tween.tween_interval(i * 0.08)
		tween.tween_property(card, "transform", slot, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_peek.append(card)
	if not shown.is_empty():
		sfx.emit("flip")


func clear_peek() -> void:
	for card in _peek:
		if is_instance_valid(card):
			card.queue_free()
	_peek = []


func pick(origin: Vector3, direction: Vector3) -> int:
	# 自己牌扇里被射线点中的那张(下标 = 私有手牌下标);没点中 -1
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
	# 越肩:小桌按 Patron 的举牌位置(稍缩小),大桌按德州的牌扇位置;第一人称:拿在镜头右下方
	if not world.patrons.has(my_pid) or not world.seat_angles.has(my_pid):
		return
	var me: Patron = world.patrons[my_pid]
	if not me.alive:
		return
	var seat := world.seat_transform(world.seat_angles[my_pid])
	if world.first_person:
		me.present_hand_first_person(seat, world.first_person_rest_view(my_pid), BombCatLayout.FP_FAN_CAM, BombCatLayout.FP_FAN_SCALE)
		return
	if world.is_poker_table():
		me.hold_fan(PokerLayout.fan_transform(seat, world.third_person_view(my_pid).origin).translated(
			Vector3.UP * BombCatLayout.BIG_TABLE_FAN_RAISE))
	else:
		me.present_hand_to(world.third_person_view(my_pid).origin)
		me.hold_fan(me.fan.transform.translated(Vector3.UP * BombCatLayout.SMALL_TABLE_FAN_RAISE))
	me.hold_fan(me.fan.transform.scaled_local(Vector3.ONE * BombCatLayout.MY_FAN_SCALE))


func _settle_all() -> void:
	for pid in _held:
		_layout(pid, 0.0)
	_settle_discard()


func _layout(pid: int, duration: float, skip: Node3D = null) -> void:
	# 牌扇重排;skip 是正飞进来的那张(它自己的飞行补间会落到位)
	if not world.patrons.has(pid):
		return
	var fan: Node3D = world.patrons[pid].fan
	var cards := held_cards(pid)
	for i in cards.size():
		var card: BombCard3D = cards[i]
		if card == skip:
			continue
		var mine := pid == my_pid
		var lift := 0.0
		if mine:
			lift = LIFT_SELECTED if _selected.has(i) else (LIFT_HOVER if i == _hovered else 0.0)
			card.set_glow(GLOW_SELECTED if _selected.has(i) else (GLOW_HOVER if i == _hovered else 0.0))
		var slot := BombCatLayout.fan_slot(i, cards.size(), lift)
		if card.get_parent() != fan:
			if duration <= 0.0:
				_stop_flight(card)
				card.reparent(fan, false)
				card.transform = slot
				card.visible = true
			continue
		if card.has_meta(FLIGHT_META):
			continue
		if duration <= 0.0:
			card.transform = slot
		else:
			var tween := card.create_tween()
			tween.tween_property(card, "transform", slot, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_deck(count: int) -> void:
	deck_count = maxi(count, 0)
	var h := BombCatLayout.stack_height(deck_count - 1)
	var size := Vector2(Card3D.WIDTH, Card3D.HEIGHT) * BombCatLayout.PILE_SCALE * BOX_INSET
	_deck_mesh.size = Vector3(size.x, maxf(h, 0.0005), size.y)
	_deck_box.position = BombCatLayout.deck_position() + Vector3(0, h / 2.0, 0)
	_deck_box.rotation = Vector3.ZERO
	_deck_box.scale = Vector3.ONE
	_deck_box.visible = deck_count > 1
	_deck_top.transform = BombCatLayout.deck_top(deck_count - 1 if deck_count > 0 else 0)
	_deck_top.visible = deck_count > 0


func _set_discard_base() -> void:
	var base := maxi(discard_count - _discard_cards.size(), 0)
	var h := BombCatLayout.stack_height(base)
	var size := Vector2(Card3D.WIDTH, Card3D.HEIGHT) * BombCatLayout.PILE_SCALE * BOX_INSET
	_discard_mesh.size = Vector3(size.x, maxf(h, 0.0005), size.y)
	_discard_box.position = BombCatLayout.discard_position() + Vector3(0, h / 2.0, 0)
	_discard_box.visible = base > 0


func _discard_landing(count: int) -> Array:
	# 接下来 count 张落到弃牌堆的位置(按落定后的全局序号,已在堆上的牌不挪)
	var out := []
	for i in count:
		out.append(BombCatLayout.discard_slot(discard_count + i))
	return out


func _push_discard(nodes: Array) -> void:
	for card in nodes:
		if not is_instance_valid(card):
			continue
		_stop_flight(card)
		if card.get_parent() != self:
			card.reparent(self, true)
		_discard_cards.append(card)
		discard_count += 1
	while _discard_cards.size() > BombCatLayout.DISCARD_SHOWN:
		_free_card(_discard_cards.pop_front())
	_settle_discard()


func _settle_discard() -> void:
	_discard_cards = _discard_cards.filter(func(c): return is_instance_valid(c))
	var first := discard_count - _discard_cards.size()
	for i in _discard_cards.size():
		var card: BombCard3D = _discard_cards[i]
		_stop_flight(card)
		card.transform = BombCatLayout.discard_slot(first + i)
		card.visible = true
	_set_discard_base()


func _sync_discard(top_ids: Array) -> void:
	var ids: Array = top_ids.filter(BombCatCard.is_valid)
	ids = ids.slice(maxi(ids.size() - BombCatLayout.DISCARD_SHOWN, 0))
	ids = ids.slice(maxi(ids.size() - discard_count, 0))
	if discard_ids() != ids:
		_free_cards(_discard_cards)
		_discard_cards = ids.map(func(id: String) -> BombCard3D: return _new_card(id, Transform3D()))
	_settle_discard()


func _take(pid: int, ids: Array, my_indices: Array) -> Array:
	# 从 pid 手里拿出 ids 那几张(自己的优先按下标,对不上再按牌型找;别人的从末尾拿),拿到本节点下(保持世界位置)。
	# 手里不够(视图与演出不同步)就在他头前补一张
	var cards := held_cards(pid)
	var taken := []
	if pid == my_pid:
		var picked := []
		var by_index := my_indices.size() == ids.size() and my_indices.all(func(i): return i is int and i >= 0 and i < cards.size())
		if by_index:
			for k in my_indices.size():
				if cards[my_indices[k]].card_id != ids[k]:
					by_index = false
		if by_index:
			picked = my_indices.map(func(i: int) -> BombCard3D: return cards[i])
		else:
			var pool := cards.duplicate()
			for id in ids:
				for card in pool:
					if card.card_id == id:
						picked.append(card)
						pool.erase(card)
						break
		if picked.is_empty() and ids.is_empty() and not cards.is_empty():
			picked = [cards[-1]]
		taken = picked
	else:
		for i in mini(maxi(ids.size(), 1), cards.size()):
			taken.append(cards[cards.size() - 1 - i])
	var want := maxi(ids.size(), 1)
	for card in taken:
		if _held.has(pid):
			_held[pid].erase(card)
		_lift_out(card)
	while taken.size() < want:
		var origin := world.head_position(pid) + Vector3(0, -0.4, 0) if world.seat_angles.has(pid) else global_transform * BombCatLayout.deck_position()
		var card := _new_card(BombCatFaces.BACK, Transform3D())
		card.global_transform = Transform3D(Basis(), origin)
		taken.append(card)
	return taken


# —— 工具 ——

func _new_card(id: String, xform: Transform3D) -> BombCard3D:
	var card := BombCard3D.new(id)
	add_child(card)
	card.transform = xform
	return card


func _deck_transform() -> Transform3D:
	return _deck_top.transform


func _fly(card: BombCard3D, target: Transform3D, duration: float, arc: float, spin := 0.0) -> void:
	_stop_flight(card)
	var tween := card.fly_to(target, duration, arc, spin)
	card.set_meta(FLIGHT_META, tween)
	# 落定后摘掉标记(牌扇重排据此知道它已经停下);只记补间的 id,不让回调反过来引用补间(否则成环泄漏)
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


func _lift_out(card: BombCard3D) -> void:
	_stop_flight(card)
	card.visible = true
	if card.get_parent() != self:
		card.reparent(self, true)


func _wait(seconds: float) -> void:
	var tween := create_tween()
	tween.tween_interval(maxf(seconds, 0.0))
	await tween.finished


func stop_sparks() -> void:
	# 拆弹剪断导火索:火花停下(炸弹牌还立着,等塞回)
	_stop_sparks()


func set_deck_count(count: int) -> void:
	_set_deck(count)


func _stop_sparks() -> void:
	if is_instance_valid(_sparks):
		_sparks.emitting = false
	_sparks = null


func _free_bomb() -> void:
	_stop_sparks()
	if is_instance_valid(_bomb):
		_bomb.queue_free()
	_bomb = null


func _free_cards(cards: Array) -> void:
	for card in cards:
		_free_card(card)


func _free_card(card: Variant) -> void:
	if card != null and is_instance_valid(card):
		card.queue_free()
