class_name BombCatFx
extends Node3D
# 炸弹猫的道具效果层(规格 2026-10-10「道具效果加强」):挂在 TableWorld.poker_root 下(拆台时 clear_poker 一并收走),
# 每个效果是本节点下的一个根节点,补间与计时都挂在根上,演完自己 queue_free(根节点数回到 0 = 没有泄漏)。
# 导演按事件调用这里的入口,入口立刻返回(不阻塞),导演按这里的节奏常量去等(BombCatPacing 的预算据此核对)。
# 道具与薄片的网格、材质见 BombCatProps;酒客的配合动作(溜走、被敲、狗狗眼、举放大镜)在 Patron 里。
# 只有当事人看得到的东西不经过这里(偷看的牌面、转手的牌面由 BombCatCards 按私有视图决定)。
# 第一人称时自己的头藏着:挂在「头顶」的效果一律用 Patron.speech_anchor(第一人称时在眼前上方),镜头里看得见。
# 音效通过 sfx 信号交给上层播放(同 BombCatCards)。


signal sfx(name: String)
signal spawned(kind: String)   # 每个效果根节点建出来时发出(测试与调试据此核对导演的事件 → 效果)

const MAX_PARTICLES := 300            # 每个效果同时活着的粒子上限
const TEXT_LIFE := 0.95
const TEXT_PIXEL := 0.0022
const INK_OUTLINE := Color(0.27, 0.14, 0.1)
# 溜了
const SKIP_TIME := 0.7                # 导演等这么久:侧身溜走、扬尘、速度线、「嗖~」、桌上一串小脚印
const SKIP_STEP := 0.06               # 脚印一个接一个冒出来的间隔
const SKIP_PRINTS := 6
# 甩锅
const PAN_POP := 0.1
const PAN_FLIGHT := 0.45              # 平底锅转着圈画弧飞过去
const PAN_BONK := PAN_POP + PAN_FLIGHT
const PASS_TIME := 1.0                # 导演等这么久:飞锅、当!、星星、压扁、×N 徽章
# 偷看
const GLASS_POP := 0.18
const GLINT_AT := 0.4
# 讨要
const PLEAD_TIME := 0.7               # 狗狗眼 + 飘爱心
const HEARTS := 5
# 不行!
const STAMP_POP := 0.1
const STAMP_SCALE_STEP := 0.3         # 连环「不行!」:每多一张印章大一圈
const STAMP_SCALE_MAX := 2.2
const STAMP_HOVER := 0.32             # 印章悬在牌堆上方这么高
# 零食
const SNACK_HOP := 0.42               # 零食蹦到桌上再弹两下,然后那张牌才飞
const SNACK_LIFE := 1.25
# 炸弹
const KITTY_POP := 0.32               # 从牌里「啵嘤」一下弹出来
const SNIP_IN := 0.32                 # 大剪刀从旁边飞进来张开
const TIPTOE_HOPS := 4
const TIPTOE_SCALE := 0.8            # 踮脚溜走时缩小一点
const TIPTOE_TIME := 0.85             # 炸弹猫踮着脚溜回牌堆(只看得到它钻进去,看不到塞在哪)
const KABOOM_LIFE := 2.2
const TUFT_LIFE := 5.0                # 炸焦的头发冒烟这么久
# 轮转
const TRAIL_STEP := 0.05
const TRAIL_LIFE := 1.1
const HEAD_TOP := 0.4                 # 头心之上这么高算「头顶」(动森式大头 + 帽子)
const BADGE_FP_SCALE := 0.4           # 第一人称的自己:徽章缩小
const BADGE_SIDE := 0.36              # ×N 徽章挂在头顶偏右(别挡铭牌)

var world: TableWorld
var my_pid := 0
var _follow: Array = []               # [node, anchor: Callable, offset]
var _badge: Node3D = null
var _badge_pid: Variant = null
var _badge_label: Label3D = null
var _badge_inner: Node3D = null   # 徽章的盘子与字:第一人称的自己缩小(挂在眼前上方,别挡视线)
var _stamps: Array = []               # 本窗口里盖下的印子(窗口结束时淡掉)
var _kitty: Node3D = null
var _kitty_eyes: Node3D = null
var _kitty_holder: Node3D = null   # 炸弹猫的各部件挂在这里(按 KITTY_SCALE 放大);根节点的缩放留给弹跳与心跳
var _kitty_fuse: Node3D = null
var _kitty_sparks: GPUParticles3D = null
var _kitty_wobble: Tween = null


func _init(p_world: TableWorld) -> void:
	world = p_world
	name = "BombCatFx"


func _process(_delta: float) -> void:
	var keep := []
	for entry in _follow:
		if not is_instance_valid(entry[0]) or not entry[0].is_inside_tree():
			continue
		var node: Node3D = entry[0]
		node.global_position = entry[1].call() + entry[2]
		keep.append(entry)
	_follow = keep
	if is_instance_valid(_badge_inner):
		var me := _patron(_badge_pid)
		_badge_inner.scale = Vector3.ONE * (BADGE_FP_SCALE if me != null and me.is_head_hidden() else 1.0)


# —— 查询 ——

func active_count() -> int:
	# 还活着的效果根节点数(徽章算一个)
	return get_child_count()


func badge_text() -> String:
	return _badge_label.text if is_instance_valid(_badge_label) and is_instance_valid(_badge) else ""


func badge_pid() -> Variant:
	return _badge_pid if is_instance_valid(_badge) else null


func kitty() -> Node3D:
	return _kitty if is_instance_valid(_kitty) else null


func kitty_center() -> Vector3:
	# 炸弹猫身子的球心(全局);没有炸弹猫时是桌心
	if is_instance_valid(_kitty) and is_instance_valid(_kitty_holder):
		return _kitty_holder.global_transform * Vector3(0, BombCatProps.KITTY_RADIUS, 0)
	return world.to_global(BombCatLayout.TABLE_FOCUS)


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_follow = []
	_stamps = []
	_badge = null
	_badge_pid = null
	_kitty = null


# —— 溜了 ——

func skip(pid: int, next_pid: Variant) -> void:
	# 侧身一缩、踮脚溜走:脚边扬起小烟团、身侧几道速度线、头顶「嗖~」,桌上一串小脚印往下家那边跑
	var root := _spawn("skip", SKIP_TIME + 1.2)
	var patron := _patron(pid)
	sfx.emit("sneak")
	if patron != null:
		patron.sneak(SKIP_TIME * 0.85)
		var side := world.seat_right(pid)
		var base := patron.global_position
		puffs(base + side * 0.42 + Vector3(0, 0.55, 0.0), 12, [Color(0.99, 0.96, 0.9), Color(0.92, 0.88, 0.82)], 0.15, Vector2(0.4, 0.8), 0.65)
		puffs(base - side * 0.4 + Vector3(0, 0.45, 0.0), 8, [Color(0.99, 0.96, 0.9)], 0.12, Vector2(0.3, 0.6), 0.6)
		for k in 4:
			var line := _mesh(root, BombCatProps.streak(), Color(1.0, 0.98, 0.92), 0.9)
			var from := patron.head_position() + Vector3(0, -0.15 - k * 0.14, 0) - side * (0.42 + k * 0.05)
			line.global_position = from
			_orient_streak(line, side, 0.01)
			var tween := line.create_tween()
			tween.tween_interval(k * 0.04)
			tween.tween_method(func(t: float) -> void:
				_orient_streak(line, side, lerpf(0.01, 0.7, t))
				line.global_position = from - side * t * 0.2, 0.0, 1.0, 0.16).set_ease(Tween.EASE_OUT)
			tween.tween_method(func(a: float) -> void: line.set_instance_shader_parameter("alpha", a), 0.9, 0.0, 0.25)
		pop_text("嗖~", patron.speech_anchor() + Vector3(0, 0.05, 0), Color(0.62, 0.92, 0.84), 1.0)
	if next_pid is int and next_pid != pid and world.seat_angles.has(pid) and world.seat_angles.has(next_pid):
		_footprints(root, pid, next_pid, SKIP_PRINTS, Color(0.42, 0.52, 0.78), SKIP_STEP, 0.12, "tiptoe")   # 牌面上的蓝灰脚印


# —— 甩锅 ——

func pass_turns(from: int, to: int, turns: int) -> void:
	# 一口圆滚滚的平底锅转着圈画弧飞向下家,「当!」地敲在他头上:星星、头被拍扁再弹回;头顶冒出「×N」徽章(欠几回合)
	var root := _spawn("pass_turns", PASS_TIME + 0.8)
	var pan := MeshKit.add(root, BombCatProps.pan(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF)
	var start := _hand_point(from)
	var target_patron := _patron(to)
	var hit := _head_top(to) if target_patron != null else world.to_global(BombCatLayout.TABLE_FOCUS)
	# 敲中时锅口斜朝镜头上方(看得到圆圆的锅面),锅底扣在头顶;飞行中绕侧轴翻滚两圈多,最后正好转到这个姿势
	var to_cam := _camera_pos() - hit
	to_cam.y = 0.0
	to_cam = to_cam.normalized() if to_cam.length() > 0.01 else Vector3.BACK
	var axis := (to_cam * 0.85 + Vector3.UP * 0.53).normalized()
	var handle := Vector3.UP.cross(to_cam).normalized()
	handle = (handle - axis * handle.dot(axis)).normalized()
	var land := Basis(handle, axis, handle.cross(axis))
	var face := hit - start
	face.y = 0.0
	var roll := Vector3.UP.cross(face.normalized() if face.length() > 0.01 else Vector3.FORWARD).normalized()
	var rest := hit + to_cam * 0.14 + Vector3.UP * 0.04   # 往镜头这边挪一点:不被宽檐帽挡住
	pan.global_position = start
	pan.scale = Vector3.ONE * 0.05
	sfx.emit("whoosh")
	var mid := (start + rest) / 2.0 + Vector3.UP * 0.55
	var tween := pan.create_tween()
	tween.tween_property(pan, "scale", Vector3.ONE, PAN_POP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(t: float) -> void:
		var p := start.lerp(mid, t).lerp(mid.lerp(rest, t), t)
		pan.global_transform = Transform3D(Basis(roll, (1.0 - t) * TAU * 2.25) * land, p),
		0.0, 1.0, PAN_FLIGHT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		sfx.emit("bonk")
		pop_text("当!", hit + Vector3(0, 0.32, 0) + handle * 0.12, Color(1.0, 0.86, 0.36), 1.3)
		shock_ring(hit + to_cam * 0.05, Color(1.0, 0.95, 0.8), 0.55, 0.3, to_cam)
		if target_patron != null:
			target_patron.bonk()
			star_ring(func() -> Vector3: return _head_top(to), 5, 0.32, 0.9, Vector3(0, 0.06, 0))
		set_owed(to, turns))
	# 弹开:锅往上蹦一下、翻个面、缩没在一小团烟里
	var bounce := hit + Vector3(0, 0.28, 0) + world.seat_right(to) * 0.18 if world.seat_angles.has(to) else hit + Vector3(0, 0.28, 0)
	tween.tween_property(pan, "global_position", bounce, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(pan, "rotation:z", pan.rotation.z + 2.4, 0.3)
	tween.tween_callback(func() -> void: puffs(pan.global_position, 8, [Color(0.95, 0.93, 0.9)], 0.15, Vector2(0.3, 0.5), 0.5))
	tween.tween_property(pan, "scale", Vector3.ONE * 0.01, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


func set_owed(pid: Variant, turns: int) -> void:
	# 「×N」徽章:挂在要连走好几回合的人头顶偏右,N = 还欠的回合数;N ≤ 1 或换人时收起(同时只有一个)
	if not pid is int or turns <= 1 or _patron(pid) == null:
		_hide_badge()
		return
	if _badge_pid != pid or not is_instance_valid(_badge):
		_hide_badge()
		_badge = _spawn("badge", -1.0)
		_badge_pid = pid
		_badge_inner = Node3D.new()
		_badge.add_child(_badge_inner)
		var disc := _mesh(_badge_inner, BombCatProps.badge(), Color.WHITE, 1.0)
		disc.name = "Disc"
		_badge_label = _label("", 0.34, Color(1.0, 0.98, 0.92))
		_badge_label.outline_size = 22
		_badge_label.position = Vector3(0, 0.002, 0)
		_badge_inner.add_child(_badge_label)
		var side := world.seat_right(pid) * BADGE_SIDE
		var anchor := func() -> Vector3: return _head_top(pid)
		_follow.append([_badge, anchor, side + Vector3(0, 0.06, 0)])
		_badge.global_position = _head_top(pid) + side
	var text := "×%d" % turns
	if _badge_label.text != text:
		_badge_label.text = text
		_badge.scale = Vector3.ONE * 0.3
		var tween := _badge.create_tween()
		tween.tween_property(_badge, "scale", Vector3.ONE * 1.25, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(_badge, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_SINE)
		sfx.emit("pop")


func _hide_badge() -> void:
	if is_instance_valid(_badge):
		var badge := _badge
		var tween := badge.create_tween()
		tween.tween_property(badge, "scale", Vector3.ONE * 0.01, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_callback(badge.queue_free)
	_badge = null
	_badge_pid = null
	_badge_label = null


# —— 偷看 ——

func peek_glass(pid: int, hold: float) -> void:
	# 举起一把大大的放大镜凑到眼前(另一只爪捂嘴偷乐),镜片一闪;第一人称的自己:放大镜举在镜头左下方
	var root := _spawn("peek", hold + 0.6)
	var patron := _patron(pid)
	var glass := MeshKit.add(root, BombCatProps.magnifier(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF)
	glass.scale = Vector3.ONE * 0.05
	var fp_me := pid == my_pid and world.first_person
	if patron != null:
		patron.peek_with_glass(hold)
	var place := func() -> void:
		if not is_instance_valid(glass):
			return
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if fp_me and cam != null:
			glass.global_transform = Transform3D(cam.global_basis * Basis(Vector3.BACK, 0.35), cam.global_transform * Vector3(-0.17, -0.1, -0.42)) \
				.scaled_local(glass.scale)
		elif patron != null:
			var hand := patron.right_hand.global_position
			var deck := world.to_global(BombCatLayout.deck_position())
			var look := (deck - hand)
			look.y = 0.0
			var basis := Basis.looking_at(-look.normalized() if look.length() > 0.01 else Vector3.BACK, Vector3.UP)
			glass.global_transform = Transform3D(basis * Basis(Vector3.BACK, -0.3), hand + Vector3(0, 0.27, 0)).scaled_local(glass.scale)
	place.call()
	var keep := glass.create_tween()
	keep.tween_method(func(_t: float) -> void: place.call(), 0.0, 1.0, hold + 0.45)
	var pop := glass.create_tween()
	pop.tween_property(glass, "scale", Vector3.ONE * (0.36 if fp_me else 1.0), GLASS_POP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_interval(GLINT_AT - GLASS_POP)
	pop.tween_callback(func() -> void:
		sfx.emit("sparkle")
		var at := glass.global_transform * Vector3(-0.035, 0.04, 0.03)
		glint(at, 0.22 if not fp_me else 0.07)
		Fx.sparkles(root, at, Vector3.UP, 10))
	pop.tween_interval(maxf(hold - GLINT_AT, 0.0))
	pop.tween_property(glass, "scale", Vector3.ONE * 0.01, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


func shuffle_stars(center: Vector3, duration: float) -> void:
	# 洗牌龙卷风:三圈半透明的风环叠成漏斗(越高越大、各自晃着转),四周绕圈的小星星一闪一闪、越转越高
	var root := _spawn("shuffle", duration + 0.3)
	root.global_position = center
	for k in 3:
		var ring := _mesh(root, BombCatProps.ring(), Color(1.0, 0.98, 0.94), 0.0)
		var height := 0.07 + k * 0.12
		var radius := 0.13 + k * 0.08
		var wind := ring.create_tween()
		wind.tween_method(func(t: float) -> void:
			var grow := smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.75, 1.0, t))
			ring.position = Vector3(sin(t * TAU * 2.0 + k) * 0.02, height * grow, cos(t * TAU * 2.0 + k) * 0.02)
			ring.rotation = Vector3(0.12 * sin(t * TAU * 3.0 + k), t * TAU * (3.0 + k), 0.1 * cos(t * TAU * 2.5 + k))
			ring.scale = Vector3.ONE * radius * (0.4 + 0.6 * grow)
			ring.set_instance_shader_parameter("alpha", 0.6 * grow), 0.0, 1.0, duration)
	for k in 5:
		var s := _star(root, 0.7)
		var phase := TAU * k / 5.0
		var tween := s.create_tween()
		tween.tween_method(func(t: float) -> void:
			var a := phase + t * TAU * 1.6
			var r := 0.3 + 0.08 * sin(t * PI)
			s.position = Vector3(cos(a) * r, 0.1 + t * 0.3 + 0.04 * sin(t * TAU * 3.0 + phase), sin(a) * r)
			s.rotation = Vector3(0, -a, 0)
			s.scale = Vector3.ONE * (0.8 + 0.4 * absf(sin(t * TAU * 2.0 + phase))) * minf(t * 6.0, 1.0) * (1.0 - smoothstep(0.8, 1.0, t)),
			0.0, 1.0, duration)


# —— 讨要 ——

func plead(pid: int) -> void:
	# 狗狗眼:水汪汪的大眼睛 + 双爪合十 + 头边飘出一串粉色爱心
	var root := _spawn("beg", PLEAD_TIME + 1.0)
	var patron := _patron(pid)
	if patron == null:
		return
	patron.plead(PLEAD_TIME + 0.35)
	sfx.emit("sparkle")
	var anchor := func() -> Vector3: return _head_top(pid)
	for k in HEARTS:
		var heart := MeshKit.add(root, BombCatProps.heart(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF)
		var side := -1.0 if k % 2 == 0 else 1.0
		var start: Vector3 = anchor.call() + Vector3(0, -0.12, 0)
		var right := world.seat_right(pid) if world.seat_angles.has(pid) else Vector3.RIGHT
		var drift := right * side * (0.3 + 0.07 * k)
		heart.global_position = start
		heart.scale = Vector3.ONE * 0.01
		var tween := heart.create_tween()
		tween.tween_interval(k * 0.08)
		tween.tween_method(func(t: float) -> void:
			heart.global_position = start + drift * minf(t * 1.6, 1.0) + Vector3(0, t * 0.4, 0) + right * 0.04 * sin(t * TAU * 2.0)
			heart.scale = Vector3.ONE * (1.4 + 0.25 * sin(t * TAU * 3.0)) * minf(t * 8.0, 1.0) * (1.0 - smoothstep(0.8, 1.0, t))
			_face_camera(heart), 0.0, 1.0, 0.9)
	Fx.sparkles(root, anchor.call(), Vector3.UP, 12)


func heart_pop(pos: Vector3) -> void:
	# 讨要的牌落到手里:一颗大爱心「啵」地鼓起来,再炸成一圈小爱心
	var root := _spawn("heart_pop", 1.0)
	root.global_position = pos
	var big := MeshKit.add(root, BombCatProps.heart(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 0.01, MeshKit.SHADOW_OFF)
	_face_camera(big)
	sfx.emit("pop")
	var tween := big.create_tween()
	tween.tween_property(big, "scale", Vector3.ONE * 1.5, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(big, "scale", Vector3.ONE * 0.01, 0.1)
	tween.tween_callback(func() -> void:
		for k in 6:
			var small := MeshKit.add(root, BombCatProps.heart(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 0.5, MeshKit.SHADOW_OFF)
			var a := TAU * k / 6.0
			var dir := (_camera_right() * cos(a) + Vector3.UP * sin(a)) * 0.3
			var t2 := small.create_tween()
			t2.tween_method(func(t: float) -> void:
				small.position = dir * t + Vector3(0, -0.05 * t * t, 0)
				small.scale = Vector3.ONE * 0.5 * (1.0 - t)
				_face_camera(small), 0.0, 1.0, 0.45))


# —— 转手的牌:拖尾 ——

func trail(card: Node3D, kind: String, duration: float) -> void:
	# 跟着飞行中的牌:讨要 = 粉色蝴蝶结 + 一串小爱心;抽牌 / 点名 = 金色闪光拖尾
	if not is_instance_valid(card):
		return
	var root := _spawn("trail", duration + 1.2)
	var particles := _trail_particles(root, kind == "beg")
	if kind == "beg":
		var bow := MeshKit.add(root, BombCatProps.bow(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 1.4, MeshKit.SHADOW_OFF)
		_follow.append([bow, _node_anchor(card, bow), Vector3(0, 0.03, 0)])
		var spin := bow.create_tween()
		spin.tween_method(func(t: float) -> void: _face_camera(bow), 0.0, 1.0, duration)
		spin.tween_property(bow, "scale", Vector3.ONE * 0.01, 0.15)
	_follow.append([particles, _node_anchor(card, particles), Vector3.ZERO])
	var stop := root.create_tween()
	stop.tween_interval(duration)
	stop.tween_callback(func() -> void: particles.emitting = false)


func _trail_particles(root: Node3D, hearts: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.55
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 4, 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.02
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.12
	pm.gravity = Vector3(0, 0.1 if hearts else -0.3, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var gradient := Gradient.new()
	var c := Color(1.0, 0.55, 0.72) if hearts else Color(1.0, 0.86, 0.4)
	gradient.colors = PackedColorArray([c, Color(c, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	pm.color_ramp = ramp
	p.process_material = pm
	if hearts:
		var mesh := BombCatProps.heart()
		p.draw_pass_1 = mesh
		pm.scale_min = 0.25
		pm.scale_max = 0.45
		pm.color_ramp = null
		pm.particle_flag_rotate_y = true
		pm.angular_velocity_min = -120.0
		pm.angular_velocity_max = 120.0
	else:
		p.draw_pass_1 = Fx._additive_quad(0.02, 4.0)
	root.add_child(p)
	return p


# —— 不行! ——

func nope_stamp(pos: Vector3, depth: int, slam_at: float) -> void:
	# 一枚巨大的圆形红色爪印章悬在弃牌堆上方,slam_at 秒时「砰」地盖下:冲击波圈、桌子一震、留下「不行!」印子;
	# 连环「不行!」一张比一张大,偶数张(不行掉不行)换成薄荷绿的「不行不行!」
	var root := _spawn("nope", slam_at + 1.0)
	var s := minf(1.0 + STAMP_SCALE_STEP * maxi(depth - 1, 0), STAMP_SCALE_MAX)
	var odd := depth % 2 == 1
	var color := Color(0.9, 0.36, 0.38) if odd else Color(0.3, 0.7, 0.58)   # 牌面的柔红 / 薄荷
	var text := "不行!" if odd else "不行不行!"
	var stamp := MeshKit.add(root, BombCatProps.stamp(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF)
	var yaw := randf_range(-0.5, 0.5)
	var high := pos + Vector3(0, STAMP_HOVER * s, 0)
	stamp.global_position = high
	stamp.rotation.y = yaw
	stamp.scale = Vector3.ONE * 0.05
	var tween := stamp.create_tween()
	tween.tween_property(stamp, "scale", Vector3.ONE * s, STAMP_POP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(stamp, "global_position", high + Vector3(0, 0.06 * s, 0), maxf(slam_at - STAMP_POP - 0.07, 0.01)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(stamp, "global_position", pos + Vector3(0, 0.004, 0), 0.07).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		sfx.emit("stamp")
		stamp.scale = Vector3(s * 1.12, s * 0.7, s * 1.12)
		_mark(pos, s, yaw, color, text)
		shock_ring(pos + Vector3(0, 0.01, 0), Color(1.0, 0.95, 0.9), 0.5 * s, 0.35)
		puffs(pos + Vector3(0, 0.02, 0), 12, [Color(0.96, 0.94, 0.9), Color(1.0, 0.9, 0.86)], 0.1 * s, Vector2(0.5, 1.0), 0.45, 0.0, 80.0)
		pop_text("砰!", pos + Vector3(0, 0.32 + 0.08 * s, 0), Color(1.0, 0.6, 0.22), 1.15 + 0.15 * mini(depth, 4)))
	tween.tween_property(stamp, "scale", Vector3.ONE * s, 0.08)
	tween.tween_property(stamp, "global_position", high + Vector3(0, 0.12, 0), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(stamp, "scale", Vector3.ONE * 0.01, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


func _mark(pos: Vector3, s: float, yaw: float, color: Color, text: String) -> void:
	# 盖下去的印子:圆框 + 爪印 + 字,一直留到窗口结束(clear_stamps)
	var root := _spawn("stamp_mark", -1.0)
	root.global_position = pos + Vector3(0, 0.003 + 0.0015 * _stamps.size(), 0)
	root.rotation.y = yaw
	var disc := _mesh(root, BombCatProps.stamp_mark(), color, 0.92)
	disc.scale = Vector3.ONE * BombCatProps.STAMP_RADIUS * 1.05 * s
	var label := _label(text, 0.24 * s, color)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = false
	label.outline_size = 0
	label.rotation = Vector3(-PI * 0.5, 0, 0)
	label.position = Vector3(0, 0.002, 0.05 * s)
	root.add_child(label)
	_stamps.append(root)


func clear_stamps() -> void:
	# 窗口结算:印子淡掉
	for root in _stamps:
		if not is_instance_valid(root):
			continue
		var tween: Tween = root.create_tween()
		tween.tween_method(func(a: float) -> void:
			for child in root.get_children():
				if child is MeshInstance3D:
					child.set_instance_shader_parameter("alpha", a * 0.92)
				elif child is Label3D:
					child.modulate.a = a, 1.0, 0.0, 0.35)
		tween.tween_callback(root.queue_free)
	_stamps = []


# —— 零食 ——

func snack_hop(snack_id: String, count: int, from: Vector3, toward: Vector3) -> void:
	# 打出的零食(2 或 3 份)从弃牌堆里蹦到桌上,落地压扁、再弹两下,小脸笑眯眯;牌飞走之后「噗」地缩没
	var root := _spawn("snack", SNACK_LIFE + 0.3)
	var mesh := BombCatProps.snack(snack_id)
	var dir := toward - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	var side := Vector3.UP.cross(dir).normalized()
	sfx.emit("boing")
	for k in count:
		var item := MeshKit.add(root, mesh, null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 0.01, MeshKit.SHADOW_OFF)
		var land := from + dir * (0.26 + 0.04 * k) + side * (float(k) - (count - 1) / 2.0) * 0.2
		land.y = from.y
		item.global_position = from
		var look := _camera_pos() - land
		look.y = 0.0
		var face := Basis.looking_at(-look.normalized() if look.length() > 0.01 else Vector3.BACK, Vector3.UP)
		item.global_basis = face
		var big := BombCatProps.SNACK_SCALE
		var tween := item.create_tween()
		tween.tween_interval(k * 0.06)
		tween.tween_method(func(t: float) -> void:
			item.global_position = from.lerp(land, t) + Vector3.UP * sin(t * PI) * 0.24
			item.global_basis = face.scaled(Vector3.ONE * big * minf(0.2 + t * 1.6, 1.0)), 0.0, 1.0, 0.24)
		for b in 2:
			var h := 0.07 / (b + 1)
			tween.tween_method(func(v: float) -> void: item.global_basis = face.scaled(Vector3(big * (1.0 + 0.25 * v), big * (1.0 - 0.3 * v), big * (1.0 + 0.25 * v))),
				1.0, 0.0, 0.08)
			tween.tween_method(func(t: float) -> void: item.global_position = land + Vector3.UP * sin(t * PI) * h, 0.0, 1.0, 0.12 / (b + 1))
		tween.tween_interval(maxf(SNACK_LIFE - 0.24 - 0.36 - k * 0.06, 0.05))
		tween.tween_callback(func() -> void: puffs(item.global_position + Vector3(0, 0.08, 0), 6, [Color(0.96, 0.93, 0.88)], 0.1, Vector2(0.2, 0.4), 0.4))
		tween.tween_method(func(v: float) -> void: item.global_basis = face.scaled(Vector3.ONE * big * v), 1.0, 0.01, 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


func spotlight(pid: int, named: String, life: float) -> Node3D:
	# 三张零食点名:一束暖黄聚光照在目标头上,头顶一个大「?」气泡,写着点名的牌;导演在结算时 dismiss,最多留 life 秒
	var root := _spawn("spotlight", life)
	var patron := _patron(pid)
	if patron == null:
		return root
	var cone := _mesh(root, BombCatProps.cone(), Color(1.0, 0.92, 0.6), 0.0)
	var floor_y := world.to_global(Vector3(0, 0, 0)).y
	var base := patron.global_position
	base.y = floor_y
	cone.global_position = base
	cone.scale = Vector3(1.0, 2.7, 1.0)
	var bubble_root := Node3D.new()
	root.add_child(bubble_root)
	_mesh(bubble_root, BombCatProps.bubble(), Color.WHITE, 1.0)
	var q := _label("?", 1.0, Color(0.95, 0.42, 0.4))
	q.position = Vector3(0, 0.05, 0)
	bubble_root.add_child(q)
	var name_label := _label("「%s」" % BombCatCard.display_name(named), 0.32, Color(0.32, 0.2, 0.14))
	name_label.outline_modulate = Color(1.0, 0.97, 0.9)
	name_label.outline_size = 18
	name_label.position = Vector3(0, -0.11, 0)
	bubble_root.add_child(name_label)
	_follow.append([bubble_root, _above_anchor(pid), Vector3(0, 0.34, 0)])
	bubble_root.global_position = _above(pid) + Vector3(0, 0.34, 0)
	bubble_root.scale = Vector3.ONE * 0.05
	sfx.emit("pop")
	var tween := root.create_tween().set_parallel()
	tween.tween_method(func(a: float) -> void: cone.set_instance_shader_parameter("alpha", a), 0.0, 0.2, 0.25)
	tween.tween_property(bubble_root, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var bob := bubble_root.create_tween().set_loops(int(ceil(life / 0.8)))
	bob.tween_property(bubble_root, "rotation:z", 0.08, 0.4).set_trans(Tween.TRANS_SINE)
	bob.tween_property(bubble_root, "rotation:z", -0.08, 0.4).set_trans(Tween.TRANS_SINE)
	return root


func dismiss(root: Node3D) -> void:
	# 提前收起一个效果(聚光灯):缩没再释放
	if not is_instance_valid(root):
		return
	var tween := root.create_tween()
	tween.tween_property(root, "scale", Vector3(1.0, 0.01, 1.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(root.queue_free)


# —— 炸弹猫 ——

func bomb_pop(at: Vector3, delay: float) -> void:
	# 炸弹牌立起来时(at = 炸弹牌立定的位置),一只圆滚滚的黑炸弹猫「啵嘤」一下从牌里弹出来:亮晶晶的大眼睛、导火索嘶嘶冒火花
	clear_kitty()
	var root := _spawn("bomb", -1.0)
	_kitty = root
	root.visible = false
	_kitty_holder = MeshKit.pivot(root, Vector3.ZERO, "Holder")
	_kitty_holder.scale = Vector3.ONE * BombCatProps.KITTY_SCALE
	MeshKit.add(_kitty_holder, BombCatProps.kitty_body(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF).name = "Body"
	_kitty_eyes = MeshKit.add(_kitty_holder, BombCatProps.kitty_eyes(), null, Vector3(0, BombCatProps.KITTY_RADIUS * 1.12,
		BombCatProps.KITTY_RADIUS * 0.84), Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF)
	_kitty_fuse = MeshKit.pivot(_kitty_holder, BombCatProps.FUSE_BASE, "Fuse")
	MeshKit.add(_kitty_fuse, BombCatProps.kitty_fuse(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF)
	var tween := root.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func() -> void:
		var center := world.to_global(BombCatLayout.TABLE_FOCUS)
		var out := center - at
		out.y = 0.0
		out = out.normalized() if out.length() > 0.01 else Vector3.BACK
		root.global_position = at + out * 0.1 + Vector3(0, -0.13, 0)
		root.global_basis = Basis.looking_at(-out, Vector3.UP)
		root.scale = Vector3(0.3, 0.05, 0.3)
		root.visible = true
		_kitty_sparks = Fx.fuse_sparks(_kitty_fuse, BombCatProps.FUSE_TIP)
		sfx.emit("boing")
		puffs(root.global_position + Vector3(0, 0.08, 0), 10, [Color(0.98, 0.95, 0.88), Color(1.0, 0.86, 0.5)], 0.12, Vector2(0.4, 0.8), 0.45)
		star_burst(root.global_position + Vector3(0, 0.18, 0), 5, 0.35, 0.55))
	tween.tween_property(root, "scale", Vector3(0.75, 1.35, 0.75), KITTY_POP * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(root, "scale", Vector3(1.22, 0.8, 1.22), KITTY_POP * 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(root, "scale", Vector3.ONE, KITTY_POP * 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func kitty_panic(duration: float, beats: Array) -> void:
	# 倒计时:炸弹猫越晃越厉害(歪来歪去、原地小跳),眼睛瞪圆;beats 是心跳的时刻(秒),每一下整个身子鼓一下
	if not is_instance_valid(_kitty):
		return
	var root := _kitty
	if _kitty_wobble != null and _kitty_wobble.is_valid():
		_kitty_wobble.kill()
	_kitty_wobble = root.create_tween()
	var base := root.position
	_kitty_wobble.tween_method(func(t: float) -> void:
		var amp := 0.08 + 0.22 * t
		var freq := 5.0 + 9.0 * t
		root.rotation.z = sin(t * duration * freq) * amp
		var beat := 0.0
		for b in beats:
			beat = maxf(beat, exp(-pow((t * duration - float(b)) * 9.0, 2.0)))
		root.scale = Vector3(1.0 + 0.16 * beat, 1.0 + 0.1 * beat, 1.0 + 0.16 * beat)
		root.position = base + Vector3(0, absf(sin(t * duration * freq * 0.5)) * 0.012 * (0.5 + t), 0)
		if is_instance_valid(_kitty_eyes):
			_kitty_eyes.scale = Vector3.ONE * (1.0 + 0.18 * t), 0.0, 1.0, duration)


func kitty_snip(snip_at: float) -> void:
	# 拆弹:一把粉紫大剪刀从旁边飞来张开,snip_at 秒时「咔嚓」剪断导火索——火花熄灭、剩下半截耷拉下来、
	# 炸弹猫眯眼长出一口气(呼~一小团白烟),撒一小把彩纸
	if not is_instance_valid(_kitty):
		return
	if _kitty_wobble != null and _kitty_wobble.is_valid():
		_kitty_wobble.kill()
	var kitty := _kitty
	var calm := kitty.create_tween()
	calm.tween_property(kitty, "rotation:z", 0.0, 0.25)
	calm.parallel().tween_property(kitty, "scale", Vector3.ONE, 0.25)
	var root := _spawn("defuse", snip_at + 1.2)
	var tip := _kitty_fuse.global_transform * (BombCatProps.FUSE_TIP * 0.55)
	var k := BombCatProps.SNIP_SCALE
	var side := kitty.global_basis.x
	var snips := Node3D.new()
	root.add_child(snips)
	var a := MeshKit.add(snips, BombCatProps.snip_half(1.0), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF)
	var b := MeshKit.add(snips, BombCatProps.snip_half(-1.0), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF)
	# 剪刀横着伸过来:刀尖朝炸弹猫(局部 +Y = -side),刀面正对镜头那一侧(局部 +Z = 炸弹猫的正脸方向),刀口卡在导火索上
	side = side.normalized()
	var face := kitty.global_basis.z.normalized()
	var basis := Basis((-side).cross(face).normalized(), -side, face)
	var rest := tip - basis.y * 0.1 * k
	var start := rest + side * 0.6 + Vector3(0, 0.3, 0)
	snips.global_transform = Transform3D(basis, start).scaled_local(Vector3.ONE * 0.2 * k)
	var open := func(angle: float) -> void:
		a.rotation.z = angle
		b.rotation.z = -angle
	open.call(0.5)
	sfx.emit("whoosh")
	var tween := snips.create_tween()
	tween.tween_method(func(t: float) -> void:
		snips.global_transform = Transform3D(basis * Basis(Vector3.BACK, (1.0 - t) * 1.2), start.lerp(rest, t)).scaled_local(Vector3.ONE * lerpf(0.2, 1.0, t) * k),
		0.0, 1.0, SNIP_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 等的时候剪刀「咔、咔」空剪两下
	var wait := maxf(snip_at - SNIP_IN - 0.06, 0.0)
	tween.tween_method(func(t: float) -> void: open.call(0.5 - 0.22 * absf(sin(t * PI * 2.0))), 0.0, 1.0, wait)
	tween.tween_method(func(v: float) -> void: open.call(v), 0.5, 0.0, 0.06).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		_snip_fuse()
		pop_text("咔嚓!", tip + Vector3(0, 0.24, 0), Color(0.6, 0.92, 0.78), 0.8)
		sfx.emit("sigh"))
	tween.tween_interval(0.25)
	tween.tween_property(snips, "global_position", rest - side * 0.5 + Vector3(0, 0.45, 0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(snips, "scale", Vector3.ONE * 0.05, 0.25)


func _snip_fuse() -> void:
	if not is_instance_valid(_kitty):
		return
	if is_instance_valid(_kitty_sparks):
		_kitty_sparks.emitting = false
	_kitty_sparks = null
	var kitty := _kitty
	# 剪下来的那截打着转掉下去
	var root := _spawn("fuse_bit", 1.0)
	var piece := MeshKit.add(root, BombCatProps.kitty_fuse(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 0.5, MeshKit.SHADOW_OFF)
	var from := _kitty_fuse.global_transform * (BombCatProps.FUSE_TIP * 0.6)
	piece.global_position = from
	var fall := piece.create_tween()
	fall.tween_method(func(t: float) -> void:
		piece.global_position = from + kitty.global_basis.x.normalized() * t * 0.15 + Vector3(0, 0.1 * t - 0.6 * t * t, 0)
		piece.rotation = Vector3(t * 6.0, 0, t * 4.0)
		piece.scale = Vector3.ONE * 0.5 * (1.0 - smoothstep(0.7, 1.0, t)), 0.0, 1.0, 0.7)
	# 剩下半截耷拉下来;眯眼、长出一口气、撒彩纸
	var droop := _kitty_fuse.create_tween().set_parallel()
	droop.tween_property(_kitty_fuse, "scale", Vector3(1.0, 0.55, 1.0), 0.2)
	droop.tween_property(_kitty_fuse, "rotation", Vector3(0.0, 0.0, -1.9), 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	if is_instance_valid(_kitty_eyes):
		var eyes := _kitty_eyes.create_tween()
		eyes.tween_property(_kitty_eyes, "scale", Vector3(1.05, 0.18, 1.0), 0.1)
	var sigh := kitty.create_tween()
	sigh.tween_property(kitty, "scale", Vector3(1.12, 0.86, 1.12), 0.18).set_trans(Tween.TRANS_SINE)
	sigh.tween_property(kitty, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var mouth := _kitty_holder.global_transform * Vector3(BombCatProps.KITTY_RADIUS * 0.7, BombCatProps.KITTY_RADIUS * 0.7, BombCatProps.KITTY_RADIUS)
	puffs(mouth, 7, [Color(0.98, 0.98, 0.98)], 0.09, Vector2(0.2, 0.45), 0.6, 0.15, 30.0)
	pop_text("呼~", mouth + Vector3(0, 0.16, 0) + kitty.global_basis.x.normalized() * 0.12, Color(0.85, 0.95, 1.0), 0.5)
	var table := {"center": world.to_global(Vector3(0, 0, 0)), "radius": world.table_radius,
		"top": world.to_global(Vector3(0, SeatLayout.FELT_TOP, 0)).y, "floor": world.to_global(Vector3.ZERO).y}
	ConfettiFx.burst(self, Transform3D(Basis(), kitty.global_position + Vector3(0, 0.2, 0)), table, 36, 4, Vector2(1.2, 2.2))   # 彩纸落完自行释放


func kitty_tiptoe(entry: Vector3, side_dir: Vector3) -> void:
	# 塞回:炸弹猫(导火索耷拉着)缩小一点,跳到桌上,踮着脚一蹦一蹦溜到牌堆侧面,从侧边一钻钻进牌堆里(位置永远是牌堆中间,看不出塞在哪)
	if not is_instance_valid(_kitty):
		return
	var kitty := _kitty
	_kitty = null
	if _kitty_wobble != null and _kitty_wobble.is_valid():
		_kitty_wobble.kill()
	if is_instance_valid(_kitty_eyes):
		_kitty_eyes.scale = Vector3(1.0, 0.8, 1.0)
	var side := side_dir
	side.y = 0.0
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	var door := entry + side * 0.2
	door.y = entry.y - 0.012
	var start := kitty.global_position
	var floor_y := door.y
	var hops: Array = []
	var land0 := start
	land0.y = floor_y
	for k in TIPTOE_HOPS:
		hops.append(land0.lerp(door, float(k + 1) / TIPTOE_HOPS))
	var tween := kitty.create_tween()
	var hop_time := (TIPTOE_TIME - 0.22) / (TIPTOE_HOPS + 1)
	var prev := start
	# 先蹦下桌面,再踮脚小跳
	for k in TIPTOE_HOPS + 1:
		var a: Vector3 = prev
		var b: Vector3 = land0 if k == 0 else hops[k - 1]
		var height := 0.08 if k == 0 else 0.035
		tween.tween_method(func(t: float) -> void:
			kitty.global_position = a.lerp(b, t) + Vector3.UP * sin(t * PI) * height
			var look := b - a
			look.y = 0.0
			if look.length() > 0.001:
				kitty.global_basis = Basis.looking_at(-look.normalized().lerp(-side, 0.3).normalized(), Vector3.UP).scaled(Vector3.ONE * TIPTOE_SCALE)
			kitty.rotation.z = sin(t * PI) * 0.15 * (1.0 if k % 2 == 0 else -1.0), 0.0, 1.0, hop_time)
		tween.tween_callback(func() -> void: sfx.emit("tiptoe"))
		prev = b
	# 一钻:横着压扁、挤进牌堆侧面
	tween.tween_method(func(t: float) -> void:
		kitty.global_position = door.lerp(entry, t)
		kitty.global_basis = Basis.looking_at(side, Vector3.UP).scaled(Vector3(1.0 - t * 0.9, 1.0 - t * 0.5, 1.0 - t * 0.6) * TIPTOE_SCALE),
		0.0, 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		puffs(entry, 6, [Color(0.96, 0.93, 0.86)], 0.08, Vector2(0.15, 0.3), 0.35)
		kitty.queue_free())


func kaboom(pos: Vector3, pid: Variant) -> void:
	# 轰!一大团卡通烟云(一层层圆滚滚的奶黄、橘、薰衣草灰烟团,不是写实的火)、乱飞的星星、贴桌的冲击波圈、大字「轰!」;
	# 炸弹猫自己先鼓成一个球再消失在烟里;被炸的人头上一撮炸焦冒烟的头发
	var root := _spawn("kaboom", KABOOM_LIFE)
	root.global_position = pos
	if is_instance_valid(_kitty):
		var kitty := _kitty
		_kitty = null
		if is_instance_valid(_kitty_sparks):
			_kitty_sparks.emitting = false
		var swell := kitty.create_tween()
		swell.tween_property(kitty, "scale", Vector3.ONE * 1.7, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		swell.tween_callback(kitty.queue_free)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.55)
	light.light_energy = 4.0
	light.omni_range = 5.0
	light.shadow_enabled = false
	root.add_child(light)
	var fade := light.create_tween()
	fade.tween_property(light, "light_energy", 0.0, 0.45).set_ease(Tween.EASE_OUT)
	puffs(pos, 28, [Color(1.0, 0.8, 0.3), Color(1.0, 0.56, 0.3), Color(1.0, 0.93, 0.62), Color(1.0, 0.68, 0.45)], 0.21, Vector2(0.8, 1.6), 0.85, 0.4)
	puffs(pos + Vector3(0, 0.05, 0), 20, [Color(0.7, 0.6, 0.86), Color(0.56, 0.5, 0.68), Color(0.86, 0.76, 0.92)], 0.25,
		Vector2(0.4, 1.0), 1.5, 0.3)
	puffs(pos + Vector3(0, 0.1, 0), 12, [Color(1.0, 0.46, 0.42), Color(1.0, 0.78, 0.36)], 0.13, Vector2(1.6, 2.6), 0.6, 0.0)
	star_burst(pos + Vector3(0, 0.1, 0), 8, 0.7, 0.9)
	Fx.sparkles(root, pos, Vector3.UP, 30)
	var ground := pos
	ground.y = world.to_global(Vector3(0, SeatLayout.FELT_TOP, 0)).y + 0.01
	shock_ring(ground, Color(1.0, 0.86, 0.6), 1.3, 0.5)
	pop_text("轰!", pos + Vector3(0, 0.5, 0), Color(1.0, 0.45, 0.32), 1.6, 1.3, 0.25)
	if pid is int and _patron(pid) != null:
		frazzle(pid)


func frazzle(pid: int) -> void:
	# 炸焦的头发:头顶一撮炭灰色的卷卷乱毛(几个小烟团),一缕缕往上冒烟;TUFT_LIFE 秒后缩没
	var root := _spawn("tuft", TUFT_LIFE + 0.4)
	var tuft := Node3D.new()
	root.add_child(tuft)
	var anchor := func() -> Vector3:
		var p := _patron(pid)
		return p.head_position() + Vector3(0, 0.2, 0) if p != null else tuft.global_position
	_follow.append([tuft, anchor, Vector3.ZERO])
	tuft.global_position = anchor.call()
	var mesh := BombCatProps.puff_mesh()
	var mat_colors := [Color(0.24, 0.22, 0.26), Color(0.34, 0.31, 0.34), Color(0.2, 0.19, 0.22)]
	for k in 6:
		var a := TAU * k / 6.0
		var bit := MeshInstance3D.new()
		bit.mesh = mesh
		bit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bit.material_override = BombCatProps.tuft_material(mat_colors[k % 3])
		bit.position = Vector3(cos(a) * 0.09, 0.02 + 0.04 * (k % 2), sin(a) * 0.09)
		bit.scale = Vector3.ONE * 0.01
		tuft.add_child(bit)
		var tween := bit.create_tween()
		tween.tween_interval(0.05 * k)
		tween.tween_property(bit, "scale", Vector3.ONE * (0.1 + 0.03 * (k % 2)), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_interval(TUFT_LIFE - 0.4)
		tween.tween_property(bit, "scale", Vector3.ONE * 0.005, 0.25)
	var smoke := root.create_tween().set_loops(4)
	smoke.tween_callback(func() -> void:
		if is_instance_valid(tuft):
			Fx.head_smoke(self, tuft.global_position + Vector3(0, 0.05, 0)))
	smoke.tween_interval(1.1)



func clear_kitty() -> void:
	if is_instance_valid(_kitty):
		_kitty.queue_free()
	_kitty = null
	_kitty_sparks = null


# —— 轮转 ——

func paw_trail(from: int, to: int) -> void:
	# 轮到下一位:一串小爪印从上一位面前沿着桌面一路跑到下一位面前
	if from == to or not world.seat_angles.has(from) or not world.seat_angles.has(to):
		return
	var root := _spawn("paw_trail", TRAIL_LIFE + 1.0)
	_footprints(root, from, to, 0, Color(1.0, 0.74, 0.86), TRAIL_STEP, 0.0, "")


func _footprints(root: Node3D, from: int, to: int, count: int, color: Color, step: float, delay: float, sound: String) -> void:
	# 桌面上沿较短的圆弧从 from 的面前走到 to 的面前,左右交替;count = 0 时按弧长定数量
	var a0 := world.seat_angle_now(from)
	var a1 := world.seat_angle_now(to)
	var diff := wrapf(a1 - a0, -PI, PI)
	var radius := world.table_radius * 0.6
	var n := count if count > 0 else clampi(int(absf(diff) * radius / 0.13), 4, 12)
	for k in n:
		var u := (k + 0.5) / n
		var a := a0 + diff * u
		var dir := SeatLayout.direction(a)
		var tangent := Vector3.UP.cross(dir).normalized() * signf(diff)
		var foot := 1.0 if k % 2 == 0 else -1.0
		var local := dir * (radius + 0.04 * foot) + Vector3(0, SeatLayout.FELT_TOP + 0.003 + 0.0004 * k, 0)
		var print := _mesh(root, BombCatProps.paw_print(), color, 0.0)
		print.global_position = world.to_global(local)
		print.global_basis = world.global_basis * Basis.looking_at(tangent, Vector3.UP)
		print.scale = Vector3.ONE
		var tween := print.create_tween()
		tween.tween_interval(delay + k * step)
		tween.tween_callback(func() -> void:
			if sound != "" and k % 2 == 0:
				sfx.emit(sound))
		tween.tween_method(func(v: float) -> void:
			print.set_instance_shader_parameter("alpha", 0.9 * minf(v * 2.0, 1.0))
			print.scale = Vector3.ONE * (1.0 + 0.5 * sin(v * PI)), 0.0, 1.0, 0.12)
		tween.tween_interval(0.5)
		tween.tween_method(func(a2: float) -> void: print.set_instance_shader_parameter("alpha", a2), 0.9, 0.0, 0.35)


# —— 通用小件 ——

func pop_text(text: String, pos: Vector3, color: Color, size := 1.0, life := TEXT_LIFE, rise := 0.16) -> Label3D:
	# 漫画字:弹出来(放大过头再回弹)、往上飘、最后淡掉;始终画在最上层(第一人称也看得见)
	var root := _spawn("text", life + 0.1)
	var label := _label(text, size, color)
	root.add_child(label)
	root.global_position = pos
	label.scale = Vector3.ONE * 0.05
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector3.ONE * 1.3, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector3.ONE, 0.1).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(label, "position:y", rise, life - 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var fade := label.create_tween()
	fade.tween_interval(life * 0.65)
	fade.tween_property(label, "modulate:a", 0.0, life * 0.35)
	fade.parallel().tween_property(label, "outline_modulate:a", 0.0, life * 0.35)
	return label


func puffs(pos: Vector3, amount: int, colors: Array, size: float, speed: Vector2, life: float, rise := 0.3,
		spread := 180.0) -> GPUParticles3D:
	# 卡通烟团:一次喷出的一群圆滚滚的小球,鼓起来再缩没(不透明的软 toon 球,不是写实烟)
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = clampi(amount, 1, MAX_PARTICLES)
	p.lifetime = life
	p.explosiveness = 0.9
	p.randomness = 0.3
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = size * 0.4
	pm.direction = Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = speed.x
	pm.initial_velocity_max = speed.y
	pm.gravity = Vector3(0, rise, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.scale_min = size * 0.7
	pm.scale_max = size * 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(0.18, 1.0))
	curve.add_point(Vector2(0.65, 0.85))
	curve.add_point(Vector2(1.0, 0.0))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var packed := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / maxf(colors.size() - 1, 1))
		packed.append(colors[i])
	if colors.size() == 1:
		offsets = PackedFloat32Array([0.0, 1.0])
		packed = PackedColorArray([colors[0], colors[0]])
	gradient.offsets = offsets
	gradient.colors = packed
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	pm.color_initial_ramp = ramp
	p.process_material = pm
	p.draw_pass_1 = BombCatProps.puff_mesh()
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	spawned.emit("puffs")
	return p


func star_burst(pos: Vector3, count: int, reach: float, life: float) -> void:
	# 几颗胖星星往四面八方蹦出去、打着转落下、缩没
	var root := _spawn("stars", life + 0.1)
	root.global_position = pos
	for k in count:
		var s := _star(root, 0.01)
		var a := TAU * k / count + randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), 0.0, sin(a)) * reach * randf_range(0.6, 1.0)
		var up := randf_range(0.15, 0.35)
		var tween := s.create_tween()
		tween.tween_method(func(t: float) -> void:
			s.position = dir * t + Vector3(0, up * sin(t * PI * 0.8) - 0.15 * t * t, 0)
			s.rotation = Vector3(0, a + t * 8.0, t * 3.0)
			s.scale = Vector3.ONE * (0.9 * minf(t * 8.0, 1.0)) * (1.0 - smoothstep(0.7, 1.0, t)), 0.0, 1.0, life)


func star_ring(anchor: Callable, count: int, radius: float, life: float, offset := Vector3.ZERO) -> void:
	# 被敲晕:一圈星星绕着头顶转
	var root := _spawn("stars", life + 0.1)
	_follow.append([root, anchor, offset])
	root.global_position = anchor.call() + offset
	for k in count:
		var s := _star(root, 0.01)
		var phase := TAU * k / count
		var tween := s.create_tween()
		tween.tween_method(func(t: float) -> void:
			var a := phase + t * TAU * 1.5
			s.position = Vector3(cos(a) * radius, 0.03 * sin(a * 2.0), sin(a) * radius)
			s.rotation = Vector3(0, -a, 0)
			s.scale = Vector3.ONE * 0.8 * minf(t * 6.0, 1.0) * (1.0 - smoothstep(0.75, 1.0, t)), 0.0, 1.0, life)


func shock_ring(pos: Vector3, color: Color, radius: float, life: float, normal := Vector3.UP) -> void:
	# 冲击波:一圈薄环从小涨大、越来越淡
	var root := _spawn("ring", life + 0.05)
	var ring := _mesh(root, BombCatProps.ring(), color, 0.9)
	root.global_position = pos
	if absf(normal.normalized().dot(Vector3.UP)) < 0.98:
		root.global_basis = Basis(Quaternion(Vector3.UP, normal.normalized()))
	ring.scale = Vector3.ONE * radius * 0.15
	var tween := ring.create_tween()
	tween.tween_method(func(t: float) -> void:
		ring.scale = Vector3.ONE * radius * lerpf(0.15, 1.0, 1.0 - pow(1.0 - t, 2.5))
		ring.set_instance_shader_parameter("alpha", 0.9 * (1.0 - t)), 0.0, 1.0, life)


func glint(pos: Vector3, size: float) -> void:
	# 一下「叮」的闪光十字:转着放大再缩没
	var root := _spawn("glint", 0.45)
	var g := _mesh(root, BombCatProps.glint(), Color(1.0, 0.98, 0.9), 1.0)
	root.global_position = pos
	g.scale = Vector3.ONE * 0.01
	var tween := g.create_tween()
	tween.tween_method(func(t: float) -> void:
		g.scale = Vector3.ONE * size * sin(t * PI)
		g.rotation.z = t * 1.2, 0.0, 1.0, 0.4)


# —— 工具 ——

func _spawn(kind: String, life: float) -> Node3D:
	# 一个效果的根节点;life > 0 时到点自己释放(life < 0 由调用方收)
	var root := Node3D.new()
	root.name = kind.capitalize().replace(" ", "")
	root.set_meta(&"fx_kind", kind)
	add_child(root)
	if life > 0.0:
		var tween := root.create_tween()
		tween.tween_interval(life)
		tween.tween_callback(root.queue_free)
	spawned.emit(kind)
	return root


func _mesh(parent: Node3D, mesh: Mesh, color: Color, alpha: float) -> MeshInstance3D:
	var inst := MeshKit.add(parent, mesh, null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF)
	inst.set_instance_shader_parameter("tint", color)
	inst.set_instance_shader_parameter("alpha", alpha)
	return inst


func _star(parent: Node3D, scale: float) -> MeshInstance3D:
	return MeshKit.add(parent, BombCatProps.star(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * scale, MeshKit.SHADOW_OFF)


func _label(text: String, size: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = UiTheme.display_font()
	label.font_size = 112
	label.pixel_size = TEXT_PIXEL * size
	label.outline_size = 30
	label.modulate = color
	label.outline_modulate = INK_OUTLINE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.double_sided = true
	label.render_priority = 4
	label.outline_render_priority = 3
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return label


func _orient_streak(line: MeshInstance3D, side: Vector3, length: float) -> void:
	# 速度线:细条沿 side 方向拉长,条宽朝上(竖着的一道),面朝桌心 / 椅背方向
	var x := side.normalized()
	var n := x.cross(Vector3.UP).normalized()
	line.global_basis = Basis(x * length, n, Vector3.UP * 0.9)


func _face_camera(node: Node3D) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var look := cam.global_position - node.global_position
	if look.length() < 0.001:
		return
	var s := node.scale
	node.global_basis = Basis.looking_at(-look.normalized(), Vector3.UP)
	node.scale = s


func _camera_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam != null else world.to_global(Vector3(0, 1.6, 2.0))


func _camera_right() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_basis.x if cam != null else Vector3.RIGHT


func _node_anchor(node: Node3D, fallback: Node3D) -> Callable:
	# 跟着 node 走(只记弱引用:node 半路被释放时改跟 fallback 不动,不让 lambda 捕获已释放的对象)
	var ref: WeakRef = weakref(node)
	var back: WeakRef = weakref(fallback)
	return func() -> Vector3:
		var live: Variant = ref.get_ref()
		if live != null and live.is_inside_tree():
			return live.global_position
		var still: Variant = back.get_ref()
		return still.global_position if still != null else Vector3.ZERO


func _patron(pid: Variant) -> Patron:
	if pid is int and world.patrons.has(pid) and is_instance_valid(world.patrons[pid]):
		return world.patrons[pid]
	return null


func _above(pid: Variant) -> Vector3:
	var p := _patron(pid)
	if p != null:
		return p.speech_anchor()
	return world.head_position(pid) + Vector3(0, 0.34, 0) if pid is int else world.to_global(BombCatLayout.TABLE_FOCUS)


func _head_top(pid: Variant) -> Vector3:
	# 头顶上方(帽子之上):第一人称的自己头藏着,改用眼前上方的气泡挂点
	var p := _patron(pid)
	if p == null:
		return _above(pid)
	if p.is_head_hidden():
		return p.speech_anchor()
	return p.head_position() + Vector3.UP * HEAD_TOP


func _above_anchor(pid: Variant) -> Callable:
	return func() -> Vector3: return _above(pid)


func _hand_point(pid: Variant) -> Vector3:
	var p := _patron(pid)
	if p != null:
		return p.right_hand.global_position + Vector3(0, 0.08, 0)
	return world.to_global(BombCatLayout.TABLE_FOCUS)
