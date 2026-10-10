class_name LiarsDiceCups
extends Node3D
# 吹牛骰子的骰盅与骰子(设计稿 §3):挂在 TableWorld.poker_root 下(拆台时 clear_poker 一并收走),坐标 = 牌桌世界坐标。
# 每个座位一只骰盅(物种色的皮革盅,LiarsDiceProps.cup),状态:
#   down   扣在桌上(口朝下),盅底下是这一轮的骰子;
#   open   开盅后翻过来口朝上,放回主人那边,骰子在面前排成一行;
#   tipped 出局 / 断线:歪倒在桌上;
#   held   正捧在手里摇(过渡中)。
# 隐藏信息:**别人的骰子在开盅之前根本不建**(reveal 时才按 revealed 事件的点数建出来);自己的骰子按私有视图建在自己的盅底下,
# 只有偷看(掀开盅沿)或开盅时露出来。所有骰子共用一份网格(LiarsDiceProps.die),计数高亮时换成发光网格。
# 动画入口都不阻塞:导演按这里的节奏常量去等(LiarsDicePacing 的预算据此核对)。音效经 sfx 信号交给上层。


signal sfx(name: String)

const STATE_DOWN := "down"
const STATE_OPEN := "open"
const STATE_TIPPED := "tipped"
const STATE_HELD := "held"
# —— 节奏(秒;导演按这些去等)——
const GATHER_TIME := 0.25          # 新一轮:桌上的骰子蹦回各自口朝上的盅里
const GRAB_TIME := 0.15            # 双手捧起骰盅到胸前
const SHAKE_TIME := 0.8            # 哗啦哗啦摇
const SHAKE_HZ := 6.5
const SHAKE_SWING := 0.034         # 左右甩的幅度(米)
const SHAKE_BOB := 0.028           # 上下颠的幅度
const SHAKE_ROLL := 0.3            # 摇的时候盅身左右歪(弧度)
const SLAM_TIME := 0.15            # 翻过来「啪」地扣在桌上
const SHAKE_TOTAL := GRAB_TIME + SHAKE_TIME + SLAM_TIME
const PEEK_UP := 0.12              # 掀开盅沿
const PEEK_HOLD := 0.24
const PEEK_DOWN := 0.12
const PEEK_TOTAL := PEEK_UP + PEEK_HOLD + PEEK_DOWN
const HOVER_TIME := 0.16           # 鼠标停在自己的盅上:盅沿掀起 / 放下
const LIFT_TIME := 0.3             # 开盅:所有骰盅一起掀起、翻过来放到主人那边
const SPREAD_TIME := 0.24          # 骰子从盅底滑出来排成一行
const HOP_TIME := 0.2              # 计数时一颗骰子跳一下(≤ LiarsDicePacing.REVEAL_PER_MATCH)
const HOP_HEIGHT := 0.07
const POP_TIME := 0.6              # 丢骰子:那一颗「啵」地弹飞、转着缩没
const TIP_TIME := 0.35             # 出局:骰盅歪倒
const HALO_COLOR := Color(1.0, 0.8, 0.36)   # 算进去的骰子底下一圈金光(BombCatProps 的淡出薄片环,实例 tint)
const HALO_RADIUS := 0.05

var world: TableWorld
var my_pid := 0
var cups := {}          # pid -> Node3D(盅的枢轴,原点在盅口中心)
var cup_state := {}     # pid -> STATE_*
var dice := {}          # pid -> Array[MeshInstance3D](自己的随时有;别人的只在开盅之后)
var values := {}        # pid -> Array[int](与 dice 一一对应)
var _tweens := {}       # pid -> Tween(盅的动作)
var _hover := false     # 自己的盅正被鼠标掀开
var _halos: Array = []  # 计数时算进去的骰子底下的金色小光圈(unglow_all 时收走)


func _init(p_world: TableWorld) -> void:
	world = p_world
	name = "LiarsDiceCups"


# —— 查询 ——

func angle_of(pid: int) -> float:
	return world.seat_angle_now(pid)


func rest_of(pid: int) -> Transform3D:
	return LiarsDiceLayout.cup_rest(angle_of(pid), world.table_radius)


func state_of(pid: int) -> String:
	return cup_state.get(pid, "")


func dice_count(pid: int) -> int:
	return dice.get(pid, []).size()


func values_of(pid: int) -> Array:
	return values.get(pid, []).duplicate()


func others_dice_count() -> int:
	# 别人桌上有几颗骰子节点(开盅之前必须是 0)
	var n := 0
	for pid in dice:
		if pid != my_pid:
			n += dice[pid].size()
	return n


func die_node(pid: int, index: int) -> MeshInstance3D:
	var list: Array = dice.get(pid, [])
	return list[index] if index >= 0 and index < list.size() else null


func is_busy(pid: int) -> bool:
	return _tweens.has(pid) and _tweens[pid] is Tween and _tweens[pid].is_valid() and _tweens[pid].is_running()


# —— 搭建与对账 ——

func setup(order: Array, species: Dictionary) -> void:
	# order:座位顺序的 pid;species:pid -> 物种下标(没有时按 TableWorld 上那位酒客的物种)
	clear()
	for pid in order:
		if not pid is int:
			continue
		var index: int = species.get(pid, world.species_index_of(pid))
		var holder := Node3D.new()
		holder.name = "Cup%d" % pid
		add_child(holder)
		var mesh := MeshKit.add(holder, LiarsDiceProps.cup(index), null)
		mesh.name = "Mesh"
		holder.transform = rest_of(pid)
		cups[pid] = holder
		# 穿模防护:探头的头从骰盅上面拱过去(扣着、捧着摇、翻开都跟着盅走;盅收走后自动忽略)
		world.clip_guard.set_prop(StringName("liars_dice_cup_%d" % pid), ClipGuard.follow(holder, LiarsDiceLayout.CUP_RADIUS,
			PackedVector3Array([Vector3.ZERO, Vector3(0, LiarsDiceLayout.CUP_HEIGHT, 0)])))
		cup_state[pid] = STATE_DOWN
		dice[pid] = []
		values[pid] = []


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	cups = {}
	cup_state = {}
	dice = {}
	values = {}
	_tweens = {}
	_hover = false
	_halos = []


func sync(alive: Dictionary, my_dice: Array) -> void:
	# 演出结束后兜底:出局的盅歪倒;扣着的盅底下不留别人的骰子;自己扣着的盅底下是 my_dice
	for pid in cups:
		if not alive.get(pid, false) and cup_state[pid] != STATE_TIPPED:
			tip(pid, false)
		elif alive.get(pid, false) and cup_state[pid] == STATE_TIPPED:
			_kill(pid)
			cups[pid].transform = rest_of(pid)
			cup_state[pid] = STATE_DOWN
	for pid in cups:
		if pid != my_pid and cup_state[pid] == STATE_DOWN and not is_busy(pid):
			clear_dice(pid)
	if cups.has(my_pid) and cup_state[my_pid] == STATE_DOWN and not is_busy(my_pid):
		if values.get(my_pid, []) != my_dice:
			set_my_dice(my_dice)


func set_my_dice(dice_values: Array) -> void:
	# 自己这一轮的骰子:摆在自己的盅底下(梅花位,点数朝上)
	if not cups.has(my_pid):
		return
	clear_dice(my_pid)
	var angle := angle_of(my_pid)
	var list: Array = []
	for i in dice_values.size():
		var die := _new_die()
		die.position = LiarsDiceLayout.under_position(angle, world.table_radius, i)
		die.basis = LiarsDiceProps.up_basis(dice_values[i], LiarsDiceLayout.under_yaw(angle, i))
		list.append(die)
	dice[my_pid] = list
	values[my_pid] = dice_values.duplicate()


func clear_dice(pid: int) -> void:
	for die in dice.get(pid, []):
		if is_instance_valid(die):
			remove_child(die)
			die.queue_free()
	dice[pid] = []
	values[pid] = []


func _new_die() -> MeshInstance3D:
	var die := MeshKit.add(self, LiarsDiceProps.die(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF)
	die.name = "Die"
	return die


# —— 新一轮:收骰子、摇盅、扣下、偷看 ——

func gather(pids: Array) -> void:
	# 桌上排开的骰子蹦回各自的盅(口朝上的就落进盅口,扣着的直接收走),之后释放(自己的新点数扣下时再建)
	var any := false
	for pid in pids:
		if not cups.has(pid):
			continue
		var into: Vector3 = cups[pid].position
		for die in dice.get(pid, []):
			if not is_instance_valid(die):
				continue
			any = true
			var from: Vector3 = die.position
			var spin: Basis = die.basis
			var tween: Tween = die.create_tween()
			tween.tween_method(func(t: float) -> void:
				die.position = from.lerp(into, t) + Vector3.UP * sin(t * PI) * 0.12
				die.basis = spin.rotated(Vector3.UP, t * 4.0).scaled(Vector3.ONE * lerpf(1.0, 0.6, t)), 0.0, 1.0, GATHER_TIME)
		var list: Array = dice.get(pid, [])
		dice[pid] = []
		values[pid] = []
		_free_later(list, GATHER_TIME)
	if any:
		sfx.emit("dice_clack")


func shake(pids: Array, shake_time := SHAKE_TIME) -> void:
	# 双手捧起骰盅(口朝上)到胸前、哗啦哗啦摇、翻过来「啪」地扣在桌上;手跟着盅(Patron.hold_paws)。
	# 自己的骰子在摇的时候藏起来(扣下后由 set_my_dice 按新点数重建)
	var any := false
	for pid in pids:
		if not cups.has(pid) or cup_state[pid] == STATE_TIPPED:
			continue
		any = true
		_shake_one(pid, shake_time)
	if not any:
		return
	sfx.emit("dice_shake")
	var tween := create_tween()
	tween.tween_interval(GRAB_TIME + shake_time + SLAM_TIME * 0.8)
	tween.tween_callback(func() -> void: sfx.emit("cup_slam"))


func _shake_one(pid: int, shake_time: float) -> void:
	_kill(pid)
	_hover = false if pid == my_pid else _hover
	cup_state[pid] = STATE_HELD
	if pid == my_pid:
		for die in dice.get(my_pid, []):
			if is_instance_valid(die):
				die.visible = false
	var cup: Node3D = cups[pid]
	var angle := angle_of(pid)
	var seat := world.seat_transform(angle)
	var start := cup.transform
	var rest := rest_of(pid)
	var up_basis := LiarsDiceLayout.facing(angle) * Basis(Vector3.RIGHT, PI)
	var center := LiarsDiceLayout.shake_global(seat)
	if pid == my_pid and world.first_person:
		# 第一人称:自己的盅捧得低一点、远一点,摇得看得见又不占半个画面(穿模修复 2026-10-10)
		center = seat * LiarsDiceLayout.SHAKE_POINT_FP
	var held := Transform3D(up_basis, center + Vector3(0, LiarsDiceLayout.CUP_HEIGHT * 0.5, 0))
	var right := LiarsDiceLayout.right_of(angle)
	var fwd := -LiarsDiceLayout.direction(angle)
	var phase := float(pid % 7) * 0.9
	var patron: Patron = world.patrons.get(pid)
	var total := GRAB_TIME + shake_time + SLAM_TIME
	var tween := create_tween()
	_tweens[pid] = tween
	tween.tween_method(func(t: float) -> void:
		var time := t * total
		var xform: Transform3D
		if time < GRAB_TIME:
			var k := smoothstep(0.0, 1.0, time / GRAB_TIME)
			xform = _blend(start, held, k)
		elif time < GRAB_TIME + shake_time:
			var s := (time - GRAB_TIME) * TAU * SHAKE_HZ + phase
			var off := right * sin(s) * SHAKE_SWING + Vector3.UP * absf(sin(s * 0.5 + 0.4)) * SHAKE_BOB
			xform = Transform3D(Basis(fwd, sin(s) * SHAKE_ROLL) * held.basis, held.origin + off)
		else:
			var k := (time - GRAB_TIME - shake_time) / SLAM_TIME
			xform = _blend(held, rest, k * k)
		cup.transform = xform
		if patron != null and is_instance_valid(patron) and patron.alive:
			var body_center := xform.origin + xform.basis.y.normalized() * LiarsDiceLayout.CUP_HEIGHT * 0.5
			var paws := LiarsDiceLayout.paw_points(seat, body_center)
			patron.hold_paws(paws[0], paws[1]), 0.0, 1.0, total)
	tween.tween_callback(func() -> void:
		cup.transform = rest
		cup_state[pid] = STATE_DOWN
		if patron != null and is_instance_valid(patron):
			patron.release_paws())


func peek(pid: int, hold := PEEK_HOLD) -> void:
	# 掀开靠自己这边的盅沿看一眼再扣回去(别人只看到他偷瞄;自己的盅底下才有骰子)
	if not cups.has(pid) or cup_state[pid] != STATE_DOWN:
		return
	_kill(pid)
	var cup: Node3D = cups[pid]
	var angle := angle_of(pid)
	var rest := rest_of(pid)
	var open := LiarsDiceLayout.cup_peek(angle, world.table_radius)
	var tween := create_tween()
	_tweens[pid] = tween
	tween.tween_method(func(k: float) -> void: cup.transform = _blend(rest, open, k), 0.0, 1.0, PEEK_UP) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold)
	tween.tween_method(func(k: float) -> void: cup.transform = _blend(open, rest, k), 0.0, 1.0, PEEK_DOWN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if pid == my_pid:
		sfx.emit("dice_peek")


func set_hover_peek(on: bool) -> void:
	# 鼠标停在自己扣着的盅上:盅沿掀起来看一眼,移开就放下(只在本机)
	if on == _hover or not cups.has(my_pid) or cup_state[my_pid] != STATE_DOWN or is_busy(my_pid):
		return
	_hover = on
	var cup: Node3D = cups[my_pid]
	var from := cup.transform
	var to := LiarsDiceLayout.cup_peek(angle_of(my_pid), world.table_radius) if on else rest_of(my_pid)
	var tween := create_tween()
	tween.tween_method(func(k: float) -> void: cup.transform = _blend(from, to, k), 0.0, 1.0, HOVER_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if on:
		sfx.emit("dice_peek")


func is_hover_peeking() -> bool:
	return _hover


func pick_my_cup(origin: Vector3, dir: Vector3) -> bool:
	# 鼠标射线(全局)是否碰到自己的盅(按一个包住盅身的球算)
	if not cups.has(my_pid) or not is_inside_tree():
		return false
	var center: Vector3 = to_global(rest_of(my_pid).origin + Vector3(0, LiarsDiceLayout.CUP_HEIGHT * 0.5, 0))
	var radius := LiarsDiceLayout.CUP_HEIGHT * 0.62
	var to_center := center - origin
	var along := to_center.dot(dir.normalized())
	if along < 0.0:
		return false
	return (to_center - dir.normalized() * along).length() <= radius


# —— 开盅 ——

func reveal(rows: Array) -> void:
	# rows:revealed 事件的 [{pid, dice}](全场存活者)。别人的骰子此刻才按点数建在他的盅底下;
	# 所有骰盅一起掀起、翻过来口朝上放回主人那边,骰子再从盅底滑出来排成一行
	var r := world.table_radius
	for row in rows:
		if not row is Dictionary or not row.get("pid") is int or not cups.has(row["pid"]):
			continue
		var pid: int = row["pid"]
		var dice_values := LiarsDiceScreenState.sanitize_dice(row.get("dice"))
		var angle := angle_of(pid)
		if values.get(pid, []) != dice_values or dice.get(pid, []).size() != dice_values.size():
			clear_dice(pid)
			var list: Array = []
			for i in dice_values.size():
				var die := _new_die()
				die.position = LiarsDiceLayout.under_position(angle, r, i)
				die.basis = LiarsDiceProps.up_basis(dice_values[i], LiarsDiceLayout.under_yaw(angle, i))
				list.append(die)
			dice[pid] = list
			values[pid] = dice_values
		for die in dice[pid]:
			die.visible = true
		_lift_open(pid)
		var count: int = dice[pid].size()
		for i in count:
			var die: MeshInstance3D = dice[pid][i]
			var from := die.position
			var to := LiarsDiceLayout.row_position(angle, r, i, count)
			var tween := die.create_tween()
			tween.tween_interval(LIFT_TIME * 0.55)
			tween.tween_method(func(t: float) -> void:
				die.position = from.lerp(to, t) + Vector3.UP * sin(t * PI) * 0.03, 0.0, 1.0, SPREAD_TIME) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	sfx.emit("dice_clack")


func _lift_open(pid: int) -> void:
	_kill(pid)
	if pid == my_pid:
		_hover = false
	var cup: Node3D = cups[pid]
	var from := cup.transform
	var to := LiarsDiceLayout.cup_open(angle_of(pid), world.table_radius)
	var tween := create_tween()
	_tweens[pid] = tween
	tween.tween_method(func(t: float) -> void:
		var x := _blend(from, to, t)
		x.origin += Vector3.UP * sin(t * PI) * 0.16
		cup.transform = x, 0.0, 1.0, LIFT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void: cup_state[pid] = STATE_OPEN)
	cup_state[pid] = STATE_HELD


func hop(pid: int, index: int, glow := true) -> Vector3:
	# 计数:这一颗跳一下(换成发光网格);返回它的位置(牌桌世界坐标,特效挂在这里)
	var die := die_node(pid, index)
	if die == null:
		return LiarsDiceLayout.TABLE_FOCUS
	if glow:
		die.mesh = LiarsDiceProps.die(true)
		var halo := MeshKit.add(self, BombCatProps.ring(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * HALO_RADIUS,
			MeshKit.SHADOW_OFF)
		halo.name = "Halo"
		halo.position = Vector3(die.position.x, LiarsDiceLayout.FELT + 0.002, die.position.z)
		halo.set_instance_shader_parameter("tint", HALO_COLOR)
		halo.set_instance_shader_parameter("alpha", 0.9)
		_halos.append(halo)
		die.set_meta(&"halo", halo)
	var base := die.position
	var basis := die.basis
	var tween := die.create_tween()
	tween.tween_method(func(t: float) -> void:
		die.position = base + Vector3.UP * sin(t * PI) * HOP_HEIGHT
		die.basis = basis.rotated(Vector3.UP, sin(t * PI) * 0.6).scaled(Vector3.ONE * (1.0 + 0.25 * sin(t * PI))), 0.0, 1.0, HOP_TIME)
	tween.tween_callback(func() -> void:
		die.position = base
		die.basis = basis)
	return base


func unglow_all() -> void:
	for halo in _halos:
		if is_instance_valid(halo):
			halo.queue_free()
	_halos = []
	for pid in dice:
		for die in dice[pid]:
			if is_instance_valid(die):
				die.mesh = LiarsDiceProps.die()


func pop_die(pid: int) -> Vector3:
	# 丢骰子:输家那一行最右边的一颗「啵」地弹飞(往他身后的桌外、打着转缩没);返回弹起的位置
	var list: Array = dice.get(pid, [])
	if list.is_empty():
		return world.head_position(pid) if world.patrons.has(pid) else LiarsDiceLayout.TABLE_FOCUS
	var die: MeshInstance3D = list.pop_back()
	if die.has_meta(&"halo") and is_instance_valid(die.get_meta(&"halo")):
		die.get_meta(&"halo").queue_free()
	var vals: Array = values.get(pid, [])
	if not vals.is_empty():
		vals.pop_back()
	var from := die.position
	var out := LiarsDiceLayout.direction(angle_of(pid)) * 0.55 + LiarsDiceLayout.right_of(angle_of(pid)) * 0.25
	var to := from + out + Vector3(0, -0.05, 0)
	var basis := die.basis
	var tween := die.create_tween()
	tween.tween_method(func(t: float) -> void:
		die.position = from.lerp(to, t) + Vector3.UP * (sin(t * PI) * 0.42)
		die.basis = basis.rotated(Vector3(1, 0.3, 0.2).normalized(), t * 14.0).scaled(Vector3.ONE * maxf(1.0 - t * t, 0.05)),
		0.0, 1.0, POP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		if is_instance_valid(die):
			die.queue_free())
	sfx.emit("die_pop")
	return from


func tip(pid: int, animate := true) -> void:
	# 出局 / 断线:骰盅歪倒在桌上,他桌上的骰子收走
	if not cups.has(pid):
		return
	_kill(pid)
	if pid == my_pid:
		_hover = false
	var cup: Node3D = cups[pid]
	var to := LiarsDiceLayout.cup_tipped(angle_of(pid), world.table_radius)
	cup_state[pid] = STATE_TIPPED
	if not animate:
		cup.transform = to
		return
	var from := cup.transform
	var tween := create_tween()
	_tweens[pid] = tween
	tween.tween_method(func(t: float) -> void:
		var x := _blend(from, to, t)
		x.origin += Vector3.UP * sin(t * PI) * 0.06
		cup.transform = x, 0.0, 1.0, TIP_TIME).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func lower_all() -> void:
	# 兜底(断线作废本轮时):口朝上的盅不动(新一轮的摇盅会捧起来);扣着的保持
	pass


# —— 工具 ——

func _blend(a: Transform3D, b: Transform3D, k: float) -> Transform3D:
	var qa := a.basis.get_rotation_quaternion()
	var qb := b.basis.get_rotation_quaternion()
	return Transform3D(Basis(qa.slerp(qb, clampf(k, 0.0, 1.0))), a.origin.lerp(b.origin, k))


func _kill(pid: int) -> void:
	if _tweens.has(pid) and _tweens[pid] is Tween and _tweens[pid].is_valid():
		_tweens[pid].kill()
	_tweens.erase(pid)


func _free_later(nodes: Array, seconds: float) -> void:
	if nodes.is_empty():
		return
	var tween := create_tween()
	tween.tween_interval(seconds)
	tween.tween_callback(func() -> void:
		for node in nodes:
			if is_instance_valid(node):
				node.queue_free())
