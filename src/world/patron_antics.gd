class_name PatronAntics
extends Node
# 酒客的 Q 版搞笑表演(2026-10-08 用户追加「Q 一点、搞笑一点」),挂在 Patron 下,由 Patron 每帧调用 tick:
# - 枪口抵着自己的头:冒冷汗(太阳穴边几滴汗往下滑)、眼睛瞪圆瞳孔缩成小点、浑身发抖(整个身体连头带举枪的手一起抖,
#   头和枪之间不相对漂移)、左耳乱颤、尾巴甩得更急;
# - 空枪松一口气:眯眼笑(^ ^)、吐舌头、头和耳朵耷拉一下;
# - 中弹出局:先转蚊香眼再定格成 ×、头顶一圈小星星一直转、舌头吐在嘴角(卡通、不见血);
# - 赢了:先眯眼笑,再挑眉毛、得意地左右晃脑袋;
# - 被吓一跳(有人喊骗子、旁边有人中枪):原地一蹦、眼睛瞪圆、帽子弹起、耳朵炸开;
# - 被番茄砸中:眯眼嫌弃、皱眉、摇头、吐舌头「呸」;说快捷语:头随每个音节轻点一下;
# - 待机小动作:每 4–9 秒随机一个(东张西望、歪头、抖耳朵、甩尾巴、小蹦一下、挑一下眉;物种 LOOK anim.fidget 可加自己的:熊猫嚼竹枝 chew、企鹅晃脑袋 waddle),每个酒客各自的随机种子。
# 便宜为先:不加灯、特效不投影;汗珠和星星各是一个 MultiMesh(网格、材质全体共用),舌头一个小网格,平时都隐藏;
# 补间优先,逐帧只在发抖、冒汗、转星星时更新几个变换。场景树暂停(截图 --freeze)时 tick 与补间都停,跟随 Engine.time_scale。
# 不碰 Patron 的举枪 / 放枪函数:是否「枪口对着自己」按 Patron 的状态判断(坐直且右手是握枪的拳头)。

const SWEAT_DROPS := 3
const SWEAT_CYCLE := 0.85      # 秒:一滴汗从太阳穴滑到脸颊
const STAR_COUNT := 5
const STAR_RADIUS := 0.25      # 星星绕头转的半径(米;动森式大头半宽 ≈0.32,星圈套在头顶上方)
const STAR_LIFT := 0.38        # 星星圈离头心的高度(颅顶 ≈0.29,帽子被打飞)
const STAR_SPIN := 2.6         # 弧度/秒
const TREMBLE := 0.004         # 发抖幅度(米,身体左右)
const EAR_JITTER := 0.16       # 发抖时耳朵左右颤的幅度(弧度)
const FRIGHT_TAIL := 2.6       # 吓到时尾巴摆幅放大倍数
const STARTLE_HOP := 0.05      # 被吓一跳蹦起的高度(米)
const HAT_POP := 0.05          # 帽子弹起的高度(米)
const FIDGET_EVERY := Vector2(4.0, 9.0)
const DIZZY_TIME := 1.3        # 中弹后先转蚊香眼的时长,之后定格成 ×
const TONGUE_COLOR := Color(0.86, 0.42, 0.48)
const FX_SCALE := 1.4          # 汗珠、星星、舌头跟着动森式大头放大(Q 版 1.3 倍头时的尺寸 × 这个)
const NOD := 0.075             # 说话时每个音节点头的幅度(弧度,往下)
const NOD_DOWN := 0.04         # 点下去 / 抬回来的时长(秒)
const NOD_UP := 0.07
const DISGUST_TIME := 1.1      # 被番茄砸中后嫌弃的表情停多久
const SHAKE := 0.17            # 嫌弃地摇头的幅度(弧度)

static var _cache := {}        # 共享的汗珠 / 星星网格与材质(main.gd 退出时 clear_cache)

var head_add := Vector3.ZERO   # 加到头部目标角度上的偏移(俯仰 x、转头 y、歪头 z),Patron._animate_idle 读取
var nod := 0.0                 # 说话点头(加到俯仰上;和 head_add 分开,吓一跳的补间不会把它冲掉)

var _patron: Patron
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _fidget_in := 0.0
var _aiming := false           # 枪口正抵着自己的头(冒汗、发抖)
var _relieved := false         # 空枪之后到放下枪之前:不再冒汗发抖
var _dead := false
var _sweat: MultiMeshInstance3D
var _stars: MultiMeshInstance3D
var _tongue: MeshInstance3D
var _ear_rest: Array[float] = []   # 耳朵静止时的 rotation.z(抖耳朵只动 z,眨眼时的抽动动的是 x)
var _sweat_side := -1.0        # 汗冒在不拿枪的那一侧(左)
var _sweat_from := Vector3.ZERO
var _sweat_to := Vector3.ZERO
var _tweens: Array[Tween] = []
var _talk_tween: Tween = null
var _disgust_serial := 0
var _sweat_left := 0.0         # 炸弹猫拆弹:不举枪也冒汗的剩余秒数


func setup(patron: Patron) -> void:
	# Patron 建好头和耳朵之后调用:建隐藏的特效节点,记下耳朵的静止角度
	_patron = patron
	name = "Antics"
	_rng.seed = hash([patron.species_index, "antics"])
	_fidget_in = _rng.randf_range(FIDGET_EVERY.x, FIDGET_EVERY.y)
	for ear: Node3D in patron._ears:
		_ear_rest.append(ear.rotation.z)
	var look: Dictionary = patron._look_data
	var skull: Vector3 = look["head"]["skull"][0][1] * PatronParts.head_scale(look)
	var eye := PatronParts.head_point(look, look["eyes"]["pos"])
	# 汗珠从额角滑到腮边:贴着颅骨外侧一点,高度从眼睛上方到眼睛下方
	_sweat_from = Vector3(_sweat_side * (skull.x * 0.86), eye.y + skull.y * 0.32, eye.z * 0.55)
	_sweat_to = Vector3(_sweat_side * (skull.x * 0.98), eye.y - skull.y * 0.38, eye.z * 0.4)
	_sweat = _multimesh(patron.head, "Sweat", sweat_mesh(), SWEAT_DROPS)
	_stars = _multimesh(patron, "Stars", star_mesh(), STAR_COUNT)
	_tongue = MeshKit.add(patron.head, tongue_mesh(), null)
	_tongue.name = "Tongue"
	_tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tongue.transform = _tongue_rest(look)
	_tongue.visible = false


func _multimesh(parent: Node3D, node_name: String, mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var inst := MultiMeshInstance3D.new()
	inst.name = node_name
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.extra_cull_margin = 0.4   # 实例在包围盒外转,别被视锥剔掉
	inst.visible = false
	parent.add_child(inst)
	return inst


func _tongue_rest(look: Dictionary) -> Transform3D:
	# 舌头挂在嘴角(没写嘴的鳄鱼挂在上下颌之间的嘴缝),往下、略往外歪
	var mouth: Dictionary = look["head"].get("mouth", {})
	var at: Vector3 = mouth.get("pos", Vector3(0, 0.058, -0.2))
	var width: float = mouth.get("width", 0.11) * PatronHeadBuilder.MOUTH_WIDTH
	var p := PatronParts.head_point(look, at + Vector3(width * 0.3, -0.002, -0.004))
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(-18.0), 0.0, deg_to_rad(14.0))), p)


# —— 每帧 ——

func tick(delta: float) -> void:
	_time += delta
	var p := _patron
	var aiming := p.alive and p._sitting_up and p._fist != null and p._fist.visible and not _relieved
	if not p._sitting_up:
		_relieved = false
	if aiming != _aiming:
		_set_aiming(aiming)
	if _aiming:
		_tremble()
	elif _sweat_left > 0.0:
		_sweat_left -= delta
		_drip()
		if _sweat_left <= 0.0:
			_sweat.visible = false
	if _dead:
		_spin_stars()
	elif p.alive and not p._arms_locked and not p._sitting_up:
		_fidget_in -= delta
		if _fidget_in <= 0.0:
			_fidget_in = _rng.randf_range(FIDGET_EVERY.x, FIDGET_EVERY.y)
			_fidget()


func _set_aiming(on: bool) -> void:
	_aiming = on
	_sweat.visible = on
	_eye_to("shock", 1.0 if on else 0.0, 0.18 if on else 0.3)
	_tail_fright(on)
	if not on:
		_patron.body.position.x = Patron.HIP.x
		_patron.body.position.z = Patron.HIP.z
		head_add.z = 0.0
		_reset_ears()


func _tremble() -> void:
	# 抖:两个不成倍数的频率叠起来,不像机械振动;身体带着头和举枪的手一起抖
	var t := _time
	var body := _patron.body
	body.position.x = Patron.HIP.x + (sin(t * 47.0) + 0.6 * sin(t * 29.0)) * TREMBLE
	body.position.z = Patron.HIP.z + sin(t * 37.0) * TREMBLE * 0.5
	if not _patron._ears.is_empty():   # 只颤不拿枪那一侧(左)的耳朵:右耳紧挨着枪管
		_patron._ears[0].rotation.z = _ear_rest[0] + sin(t * 41.0) * EAR_JITTER
	_drip()


func _drip() -> void:
	# 冷汗:几滴错开相位往下滑,滑到底变小消失再从额角冒出来
	var t := _time
	var mm := _sweat.multimesh
	for i in SWEAT_DROPS:
		var k := fposmod(t / SWEAT_CYCLE + float(i) / SWEAT_DROPS, 1.0)
		var pos := _sweat_from.lerp(_sweat_to, k * k) + Vector3(0, 0, -0.035 * i)
		var size := sin(k * PI) * (1.0 - 0.18 * i)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(0.85, 1.0, 0.85) * maxf(size, 0.01)), pos))


func _spin_stars() -> void:
	var p := _patron
	var center := p.to_local(p.head_position()) + Vector3(0, STAR_LIFT, 0)
	var mm := _stars.multimesh
	for i in STAR_COUNT:
		var a := _time * STAR_SPIN + TAU * i / STAR_COUNT
		var pos := center + Vector3(cos(a) * STAR_RADIUS, sin(a * 2.0 + i) * 0.015, sin(a) * STAR_RADIUS)
		var basis := Basis(Vector3.UP, -a + _time * 3.0).scaled(Vector3.ONE * _stars.get_meta("pop", 1.0))
		mm.set_instance_transform(i, Transform3D(basis, pos))


# —— 表演(Patron 在对应时刻调用)——

func relief() -> void:
	# 空枪:不抖了,眯眼笑 + 吐舌头,头和耳朵往下一耷拉,再慢慢抬回来
	_relieved = true
	if _aiming:
		_set_aiming(false)
	_eye_to("joy", 1.0, 0.12)
	_after(1.1, func(): _eye_to("joy", 0.0, 0.25))
	_tongue_out(0.12)
	_after(0.95, func(): _tongue_in(0.15))
	var head := _track(create_tween())
	head.tween_property(self, "head_add:x", -0.32, 0.22).set_trans(Tween.TRANS_SINE)
	head.tween_property(self, "head_add:x", 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_delay(0.35)
	_ears_to(0.35, 0.2, 0.6)


func sweat(duration: float) -> void:
	# 炸弹猫拆弹:不举枪也满头冷汗、眼睛瞪圆,duration 秒后收起
	if not _patron.alive:
		return
	_sweat_left = maxf(_sweat_left, duration)
	_sweat.visible = true
	_eye_to("shock", 1.0, 0.1)
	_after(duration, func():
		if not _aiming:
			_eye_to("shock", 0.0, 0.3))
	_tail_fright(true)
	_after(duration, func():
		if not _aiming:
			_tail_fright(false))


func giggle(hold: float) -> void:
	# 炸弹猫偷看:眯眼偷乐、耳朵一抖
	if not _patron.alive:
		return
	_eye_to("joy", 1.0, 0.12)
	_after(hold + 0.15, func(): _eye_to("joy", 0.0, 0.2))
	_ears_to(0.3, 0.1, 0.4)


func bonked(hold: float) -> void:
	# 炸弹猫「甩锅」:被平底锅敲中——蚊香眼晕 hold 秒、耳朵炸开、头往后一仰
	if not _patron.alive:
		return
	_eye("dizzy", 1.0)
	_after(hold, func():
		if not _dead:
			_eye("dizzy", 0.0))
	var jolt := _track(create_tween())
	jolt.tween_property(self, "head_add:x", -0.18, 0.06)
	jolt.tween_property(self, "head_add:x", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	_ears_to(-0.5, 0.05, 0.5)


func plead(hold: float) -> void:
	# 炸弹猫「讨要」:水汪汪的狗狗眼(眼睛着色器 plead)、歪头左右轻晃、耳朵往下耷拉
	if not _patron.alive:
		return
	_eye_to("plead", 1.0, 0.15)
	_after(hold, func(): _eye_to("plead", 0.0, 0.25))
	var tilt := _track(create_tween())
	tilt.tween_property(self, "head_add:z", 0.2, 0.18).set_trans(Tween.TRANS_SINE)
	tilt.tween_property(self, "head_add:z", 0.12, maxf(hold - 0.4, 0.05)).set_trans(Tween.TRANS_SINE)
	tilt.tween_property(self, "head_add:z", 0.0, 0.25).set_trans(Tween.TRANS_SINE)
	_ears_to(0.3, 0.15, 0.5)


func die() -> void:
	# 出局:先转蚊香眼再定格 ×,星星在头顶一圈圈转,舌头吐在嘴角
	_dead = true
	_sweat_left = 0.0
	_sweat.visible = false
	if _aiming:
		_set_aiming(false)
	_kill_tweens()
	head_add = Vector3.ZERO
	nod = 0.0
	_eye("joy", 0.0)
	_eye("shock", 0.0)
	_eye("dizzy", 1.0)
	_after(DIZZY_TIME, func(): _eye("dizzy", 0.0))
	_stars.set_meta("pop", 0.01)
	_after(0.45, func():
		_stars.visible = true
		var pop := _track(create_tween())
		pop.tween_method(func(v: float): _stars.set_meta("pop", v), 0.01, 1.0, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	_spin_stars()
	if not _patron._fade_targets.has(_tongue):
		_patron._fade_targets.append(_tongue)   # 舌头跟着一起褪灰
	_after(0.55, func(): _tongue_out(0.2))
	_ears_to(0.55, 0.4, -1.0)


func celebrate() -> void:
	# 赢了:先眯眼笑,再挑三下眉毛、左右得意地晃脑袋
	_eye_to("joy", 1.0, 0.12)
	_after(0.7, func(): _eye_to("joy", 0.0, 0.2))
	var brows := _track(create_tween())
	brows.tween_interval(0.75)
	for i in 3:
		_brows_by(brows, 0.016, 0.09)
		_brows_by(brows, -0.016, 0.11)
	var bob := _track(create_tween())
	bob.tween_interval(0.6)
	for i in 5:
		bob.tween_property(self, "head_add:z", 0.2 * (1.0 if i % 2 == 0 else -1.0), 0.22).set_trans(Tween.TRANS_SINE)
	bob.tween_property(self, "head_add:z", 0.0, 0.25).set_trans(Tween.TRANS_SINE)


func startle() -> void:
	# 吓一跳:原地一蹦(动作中、坐直时不蹦,免得和举枪 / 庆祝的补间抢身体)、眼睛瞪圆、帽子弹起、耳朵炸开
	if not _patron.alive:
		return
	_eye_to("shock", 1.0, 0.06)
	_after(0.55, func():
		if not _aiming:
			_eye_to("shock", 0.0, 0.35))
	var p := _patron
	if not p._arms_locked and not p._sitting_up:
		var hop := _track(create_tween())
		hop.tween_property(p.body, "position:y", Patron.HIP.y + STARTLE_HOP, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		hop.tween_property(p.body, "position:y", Patron.HIP.y, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	if p._hat != null:
		var hat := p._hat
		var rest := hat.position.y
		var pop := _track(create_tween())
		pop.tween_property(hat, "position:y", rest + HAT_POP, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pop.tween_property(hat, "position:y", rest, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	var jolt := _track(create_tween())
	jolt.tween_property(self, "head_add:x", 0.14, 0.07)
	jolt.tween_property(self, "head_add:x", 0.0, 0.4).set_trans(Tween.TRANS_SINE)
	_ears_to(-0.45, 0.06, 0.4)
	_tail_fright(true)
	_after(0.9, func():
		if not _aiming:
			_tail_fright(false))


func talk(syllable_times: PackedFloat32Array) -> void:
	# 每个音节开始时点一下头(时刻相对现在);新的一句顶掉还没点完的上一句
	if _talk_tween != null and _talk_tween.is_valid():
		_talk_tween.kill()
	nod = 0.0
	if syllable_times.is_empty():
		return
	var tween := _track(create_tween())
	_talk_tween = tween
	var at := 0.0
	for t in syllable_times:
		tween.tween_interval(maxf(t - at, 0.0))
		tween.tween_property(self, "nod", NOD, NOD_DOWN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "nod", 0.0, NOD_UP).set_trans(Tween.TRANS_SINE)
		at = maxf(t, at) + NOD_DOWN + NOD_UP


func disgust() -> void:
	# 被番茄砸中:眼睛挤成 ^ ^、眉毛皱起来、左右摇两下头、吐舌头「呸」,然后复原
	var p := _patron
	if not p.alive:
		return
	_disgust_serial += 1
	var serial := _disgust_serial
	p.set_expression("angry")
	_eye_to("joy", 0.85, 0.08)
	_after(DISGUST_TIME, func():
		if serial == _disgust_serial and p.alive:
			_eye_to("joy", 0.0, 0.25)
			p.set_expression("neutral"))
	var shake := _track(create_tween())
	shake.tween_interval(0.12)
	for i in 4:
		shake.tween_property(self, "head_add:y", SHAKE * (1.0 if i % 2 == 0 else -1.0), 0.09).set_trans(Tween.TRANS_SINE)
	shake.tween_property(self, "head_add:y", 0.0, 0.15).set_trans(Tween.TRANS_SINE)
	_after(0.25, func(): _tongue_out(0.12))
	_after(0.95, func():
		if _tongue.visible and p.alive:
			_tongue_in(0.15))


func reset() -> void:
	# 回到等待厅 / 新一局:收起所有特效,眼睛、耳朵、头复原
	_kill_tweens()
	nod = 0.0
	_sweat_left = 0.0
	_dead = false
	_relieved = false
	if _aiming:
		_set_aiming(false)
	head_add = Vector3.ZERO
	for key in ["shock", "joy", "dizzy", "plead"]:
		_eye(key, 0.0)
	_sweat.visible = false
	_stars.visible = false
	_tongue.visible = false
	_reset_ears()
	_fidget_in = _rng.randf_range(FIDGET_EVERY.x, FIDGET_EVERY.y)


# —— 待机小动作 ——

func fidget_kinds() -> Array:
	var p := _patron
	var kinds := ["look", "tilt", "bounce", "brow"]
	if not p._ears.is_empty():
		kinds.append("ears")
	if not p._look_data.get("tail", {}).is_empty():
		kinds.append("tail")
	var own: String = p._look_data.get("anim", {}).get("fidget", "")
	if own != "":
		kinds.append_array([own, own])   # 物种自己的小动作(熊猫嚼竹枝、企鹅左右晃),抽中的机会多一倍
	return kinds


func _fidget() -> void:
	var kinds := fidget_kinds()
	play_fidget(kinds[_rng.randi() % kinds.size()])


func play_fidget(kind: String) -> void:
	var p := _patron
	var tween := _track(create_tween())
	match kind:
		"look":   # 东张西望(幅度小:自己的头转来转去不该挡住手牌)
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			tween.tween_property(self, "head_add:y", 0.28 * side, 0.35).set_trans(Tween.TRANS_SINE)
			tween.tween_property(self, "head_add:y", -0.22 * side, 0.45).set_trans(Tween.TRANS_SINE).set_delay(0.45)
			tween.tween_property(self, "head_add:y", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_delay(0.3)
		"tilt":   # 歪头
			tween.tween_property(self, "head_add:z", 0.24 * (1.0 if _rng.randf() < 0.5 else -1.0), 0.3).set_trans(Tween.TRANS_SINE)
			tween.tween_property(self, "head_add:z", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_delay(0.7)
		"bounce":   # 屁股一颠,小蹦两下
			for i in 2:
				tween.tween_property(p.body, "position:y", Patron.HIP.y + 0.022, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tween.tween_property(p.body, "position:y", Patron.HIP.y, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		"brow":   # 挑一下眉
			_brows_by(tween, 0.014, 0.12)
			tween.tween_interval(0.35)
			_brows_by(tween, -0.014, 0.18)
		"ears":   # 两只耳朵一起抖两下
			tween.kill()
			_ears_to(-0.3, 0.07, 0.18)
			_after(0.3, func(): _ears_to(-0.3, 0.07, 0.18))
		"chew":   # 熊猫嚼嘴角的竹枝:头微微往上一抬一落四下,同时往竹枝那边歪一点(竹枝在头部网格里,跟着动)
			tween.tween_property(self, "head_add:z", -0.08, 0.2).set_trans(Tween.TRANS_SINE)
			for i in 4:
				tween.tween_property(self, "head_add:x", -0.06, 0.09).set_trans(Tween.TRANS_SINE)
				tween.tween_property(self, "head_add:x", 0.0, 0.11).set_trans(Tween.TRANS_SINE)
			tween.tween_property(self, "head_add:z", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
		"waddle":   # 企鹅左右晃三下脑袋,像在冰上踱步
			for i in 3:
				var side := 1.0 if i % 2 == 0 else -1.0
				tween.tween_property(self, "head_add:z", 0.15 * side, 0.18).set_trans(Tween.TRANS_SINE)
			tween.tween_property(self, "head_add:z", 0.0, 0.22).set_trans(Tween.TRANS_SINE)
		"tail":   # 甩一下尾巴
			tween.kill()
			_tail_fright(true)
			_after(1.2, func():
				if not _aiming:
					_tail_fright(false))


# —— 小工具 ——

func _eye(key: String, value: float) -> void:
	_patron._eye.set_instance_shader_parameter(key, value)


func _eye_to(key: String, value: float, duration: float) -> void:
	var current = _patron._eye.get_instance_shader_parameter(key)   # 没写过的实例参数读出来是 null
	var from: float = current if current != null else 0.0
	var tween := _track(create_tween())
	tween.tween_method(func(v: float): _eye(key, v), from, value, duration)


func _ears_to(flare: float, out_time: float, back_time: float) -> void:
	# 耳朵往外炸开(flare 负值)或往下耷拉(正值),back_time < 0 时不回来(出局)
	var p := _patron
	if p._ears.is_empty():
		return
	var tween := _track(create_tween().set_parallel())
	for i in p._ears.size():
		var side := -1.0 if i == 0 else 1.0
		tween.tween_property(p._ears[i], "rotation:z", _ear_rest[i] - flare * side, out_time).set_trans(Tween.TRANS_QUAD)
	if back_time > 0.0:
		for i in p._ears.size():   # 第一只接在炸开之后,其余与它并行
			(tween.chain() if i == 0 else tween).tween_property(p._ears[i], "rotation:z", _ear_rest[i], back_time) \
				.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _brows_by(tween: Tween, dy: float, duration: float) -> void:
	# 两条眉毛一起挪 dy(相对位移,和表情补间叠加不打架):第一条接在前一步之后,第二条与它并行
	for i in _patron._brows.size():
		var step := tween.tween_property(_patron._brows[i], "position:y", dy, duration).as_relative() if i == 0 \
			else tween.parallel().tween_property(_patron._brows[i], "position:y", dy, duration).as_relative()
		step.set_trans(Tween.TRANS_SINE)


func _reset_ears() -> void:
	for i in _patron._ears.size():
		_patron._ears[i].rotation.z = _ear_rest[i]


func _tail_fright(on: bool) -> void:
	# 尾巴摆幅放大(摆动在 patron.gdshader 的顶点阶段算);出局时 Patron.die 自己接管尾巴参数
	var p := _patron
	var tail: Dictionary = p._look_data.get("tail", {})
	if tail.is_empty() or not p.alive:
		return
	var sway: float = tail.get("sway", 0.12) * (FRIGHT_TAIL if on else 1.0)
	p._legs.set_instance_shader_parameter("tail", Vector4(p._phase, sway, 0.0, 0.0))


func _tongue_out(duration: float) -> void:
	_tongue.visible = true
	_tongue.scale = Vector3(1.0, 0.05, 1.0)
	var tween := _track(create_tween())
	tween.tween_property(_tongue, "scale", Vector3.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _tongue_in(duration: float) -> void:
	var tween := _track(create_tween())
	tween.tween_property(_tongue, "scale", Vector3(1.0, 0.05, 1.0), duration)
	tween.tween_callback(func(): _tongue.visible = false)


func _after(seconds: float, fn: Callable) -> void:
	var tween := _track(create_tween())
	tween.tween_interval(seconds)
	tween.tween_callback(fn)


func _track(tween: Tween) -> Tween:
	# 记下进行中的补间,复位时一起停;顺手清掉已经结束的
	_tweens = _tweens.filter(func(t: Tween) -> bool: return t.is_valid() and t.is_running())
	_tweens.append(tween)
	return tween


func _kill_tweens() -> void:
	for tween in _tweens:
		if tween.is_valid():
			tween.kill()
	_tweens.clear()


# —— 共享网格与材质(纯数组运算建网格,材质在主线程建一次)——

static func sweat_mesh() -> Mesh:
	if not _cache.has("sweat"):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.62, 0.8, 0.95)
		mat.roughness = 0.06
		mat.metallic_specular = 1.0
		mat.rim_enabled = true
		mat.rim = 0.6
		mat.emission_enabled = true
		mat.emission = Color(0.12, 0.2, 0.3)   # 暗处也认得出是一滴汗(很弱,不触发泛光)
		_cache["sweat"] = MeshForge.cached("antics:sweat", func(f: MeshForge):
			# 水滴:下半个圆球 + 上面一个尖顶
			f.sphere(0.016 * FX_SCALE, 10, MeshForge.xf())
			f.cylinder(0.0, 0.0157 * FX_SCALE, 0.032 * FX_SCALE, 10, MeshForge.CAPS_NONE, MeshForge.xf(Vector3(0, 0.018 * FX_SCALE, 0))),
			{&"main": mat})
	return _cache["sweat"]


static func star_mesh() -> Mesh:
	if not _cache.has("star"):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.84, 0.2)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache["star"] = MeshForge.cached("antics:star", func(f: MeshForge):
			# 五角星:外 5 个尖、内 5 个凹点,前后两面扇形 + 一圈侧壁,薄片立着
			var outer := 0.04 * FX_SCALE
			var inner := 0.018 * FX_SCALE
			var half := 0.006 * FX_SCALE
			var points := PackedVector3Array()
			var normals := PackedVector3Array()
			var indices := PackedInt32Array()
			for z: float in [half, -half]:
				points.append(Vector3(0, 0, z))
				normals.append(Vector3(0, 0, signf(z)))
				for k in 10:
					var a := PI * 0.5 + TAU * k / 10.0
					var r := outer if k % 2 == 0 else inner
					points.append(Vector3(cos(a) * r, sin(a) * r, z))
					normals.append(Vector3(0, 0, signf(z)))
			for face in 2:
				var c := face * 11
				for k in 10:
					indices.append_array([c, c + 1 + k, c + 1 + (k + 1) % 10])
			for k in 10:
				var a := 1 + k
				var b := 1 + (k + 1) % 10
				indices.append_array([a, b, a + 11, b, b + 11, a + 11])
			f._append(points, normals, indices, Transform3D.IDENTITY), {&"main": mat})
	return _cache["star"]


static func tongue_mesh() -> Mesh:
	# 舌头用酒客材质(出局时跟着褪灰);原点在舌根,往 -Y 垂下
	return MeshForge.cached("patron:tongue", func(f: MeshForge):
		PatronBuilder.start(f, 0.65)
		var pink := PatronParts.capped(TONGUE_COLOR)
		f.paint(pink, 0.35)
		f.custom = Vector4(PatronBuilder.SMOOTH, 0.0, f.custom.z, 0.0)
		f.push(MeshForge.xf(Vector3.ZERO, Vector3.ZERO, Vector3.ONE * FX_SCALE))
		f.blob(Vector3(0, -0.02, 0), [[Vector3(0, -0.016, 0), Vector3(0.019, 0.024, 0.007), pink],
			[Vector3(0, -0.034, 0.001), Vector3(0.016, 0.013, 0.0075), pink]], 14, 8, 0.008)
		f.pop(), {&"main": WorldMaterials.patron()})


static func clear_cache() -> void:
	_cache.clear()
