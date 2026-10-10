class_name PatronDance
extends Node3D
# 结算庆祝时酒客的逐帧动作(规格 2026-10-09-winner-celebration):胜者跳舞、旁人鼓掌、出局的人偶尔抽一下手。
# 挂在 Patron 下(座位坐标,原点 = 座位地面),由 Patron.dance / clap / twitch 建、stop_dance 收;Patron 的待机先跑,
# 本节点在同一帧里随后把身体、头、手臂(帽子、腿、耳朵)按舞步覆盖掉,开头 BLEND_IN 秒从当时的姿势平滑接过来。
# 坐着跳:腿是坐姿的一整块网格,站起来会露出弯着的腿悬在半空,所以只做上半身的大动作 + 屁股离座的小蹦(腿跟着抬),
# 转圈时身体和腿绕髋部前面一点的竖直轴一起转(膝盖、鞋不扫进椅背)。手臂是一节直臂,舞步只给方向(座位里胸前的手不低于桌面、不伸进桌沿)。
# 跳舞的人加 3 个飘起来的音符(一个 MultiMesh,只在跳舞时存在,不投影);鼓掌、抽手不加任何网格。
# 走 _process 的 delta:跟随 Engine.time_scale,场景树暂停(截图 --freeze)时停住。

enum { WAVE, DISCO, SPIN, CHICKEN, HAT, CLAP, TWITCH }
const ROUTINES := [WAVE, DISCO, SPIN, CHICKEN, HAT]   # 胜者的舞(CLAP / TWITCH 是旁人的)
const NAMES := {WAVE: "扭腰挥手", DISCO: "迪斯科", SPIN: "转圈", CHICKEN: "小鸡舞", HAT: "抛帽接帽", CLAP: "鼓掌", TWITCH: "抽手"}
const BPM := 124.0
const BLEND_IN := 0.4           # 秒:从当时的姿势接到舞步
const NOTE_COUNT := 3
const NOTE_CYCLE := 1.8         # 秒:一个音符从头边冒出、飘高、缩没
const NOTE_COLORS := [Color(1.0, 0.38, 0.58), Color(1.0, 0.76, 0.12), Color(0.22, 0.78, 0.7)]
const TAIL_WAG := 7.0           # 跳舞时尾巴多摆的角速度(弧度/秒,叠在着色器自己的 1.3 上)
const TAIL_SWAY := 2.2          # 摆幅放大倍数
# 鼓掌:一阵拍 CLAP_BURST 下,歇 CLAP_REST 秒(歇的时候有时挥一下拳),每人节奏、相位各不相同
const CLAP_RATE := Vector2(2.4, 3.1)     # 每秒拍几下
const CLAP_BURST := Vector2i(6, 11)
const CLAP_REST := Vector2(1.2, 2.6)
const TWITCH_EVERY := Vector2(1.6, 3.8)  # 出局的人隔这么久抽一下手
const TWITCH_TIME := 0.32
const SPIN_PIVOT := Vector3(0.0, 0.0, 0.0)   # 转圈的竖直轴(座位坐标;髋部在 z = 0.12):膝盖转到背后时离椅背(z 0.34)还远
const CLAP_TOUCH := 0.058       # 两只爪子合拢时手心离中线(≈ 爪子半径):刚好碰上
# 拍手的高度(身体局部):动森式大头的下巴垂到身体局部 ≈0.45–0.48,原来 0.52 的拍手点在下巴里(穿模修复 2026-10-10 实测);
# 压到胸口下沿,爪子在下巴下面拍
const CLAP_Y := 0.44

static var _cache := {}         # 音符网格与材质(main.gd 退出时 clear_cache)

var routine := WAVE
var _p: Patron
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _hat_rest := Transform3D.IDENTITY
var _hat: Node3D = null
var _tail_rest = null           # 尾巴实例参数(Vector4);没有尾巴为 null
var _fan_was_visible := true
var _notes: MultiMeshInstance3D = null
var _flip := 1.0                # 转圈方向、迪斯科换手:每轮交替
# 鼓掌
var _clap_rate := 2.7
var _clap_left := 0             # 这一阵还剩几下
var _clap_phase := 0.0          # 当前一下的进度(0..1)
var _rest_left := 0.0           # 歇着的剩余秒数
var _pump := 0.0                # 歇的时候挥拳的进度(0 = 不挥)
var _pump_side := 1.0
# 抽手
var _dead_quats := {}           # 手臂 -> 倒下时的姿势
var _twitch_in := 0.0
var _twitch_arm: Node3D = null
var _twitch_t := -1.0


static func pick(species_index: int, seed_value: int) -> int:
	# 胜者跳哪支舞:按物种与种子确定(各端同一个种子就同一支舞),同一物种换一局通常换一支
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([species_index, seed_value, "dance"])
	return ROUTINES[rng.randi() % ROUTINES.size()]


func setup(patron: Patron, p_routine: int, seed_value := 0) -> void:
	# 加进 Patron 之前调用:记下要恢复的东西,建音符
	_p = patron
	routine = p_routine
	name = "Dance"
	_rng.seed = hash([patron.species_index, seed_value, p_routine])
	_hat = patron._hat
	if _hat != null:
		_hat_rest = _hat.transform
	if not patron._look_data.get("tail", {}).is_empty():
		_tail_rest = patron._legs.get_instance_shader_parameter("tail")
	_fan_was_visible = patron.fan.visible
	match routine:
		CLAP:
			_clap_rate = _rng.randf_range(CLAP_RATE.x, CLAP_RATE.y)
			_clap_left = _rng.randi_range(CLAP_BURST.x, CLAP_BURST.y)
			_clap_phase = _rng.randf()
			patron.fan.visible = false   # 牌扇挡在胸前,拍手会穿过牌
		TWITCH:
			for arm: Node3D in [patron._arm_l, patron._arm_r]:
				_dead_quats[arm] = arm.quaternion
			_twitch_in = _rng.randf_range(0.6, TWITCH_EVERY.y)
		_:
			patron.fan.visible = false
			_build_notes()


func is_dance() -> bool:
	return ROUTINES.has(routine)


func restore() -> void:
	# 收起舞步:帽子、腿、身体的横移与扭转、耳朵、尾巴、牌扇、脖子、表情偏移复原(手臂与前倾交给 Patron)
	var p := _p
	if p == null:
		return
	if _hat != null and is_instance_valid(_hat) and p._hat == _hat:
		_hat.transform = _hat_rest
	p._legs.transform = Transform3D.IDENTITY
	p.body.position = Patron.HIP
	p.body.rotation.y = 0.0
	p.body.rotation.z = 0.0
	for i in p._ears.size():
		p._ears[i].rotation.z = p._antics._ear_rest[i]
	if _tail_rest != null and p.alive:
		p._legs.set_instance_shader_parameter("tail", _tail_rest)
	p.fan.visible = _fan_was_visible
	p._antics.head_add = Vector3.ZERO
	if routine == TWITCH:
		for arm in _dead_quats:
			arm.quaternion = _dead_quats[arm]
	elif p.alive:
		p.set_neck_target(Vector3.ZERO)
	if _notes != null:
		_notes.queue_free()
		_notes = null


func _process(delta: float) -> void:
	if _p == null or not is_instance_valid(_p):
		return
	_t += delta
	match routine:
		CLAP:
			_clap(delta)
		TWITCH:
			_twitch(delta)
		_:
			_dance()
			_spin_notes()


# —— 舞步:每支舞给出这一刻的姿势,统一按混入权重套到骨架上 ——

func _dance() -> void:
	var b := _t * BPM / 60.0
	var pose: Dictionary
	match routine:
		WAVE:
			pose = _wave(b)
		DISCO:
			pose = _disco(b)
		SPIN:
			pose = _spin(b)
		CHICKEN:
			pose = _chicken(b)
		HAT:
			pose = _hat_toss(b)
	_apply(pose, _weight())
	# 耳朵随拍子一扇一扇,尾巴摇得飞快
	for i in _p._ears.size():
		var side := -1.0 if i == 0 else 1.0
		_p._ears[i].rotation.z = _p._antics._ear_rest[i] - side * 0.18 * _hop(b) * _weight()
	if _tail_rest != null:
		var tail: Vector4 = _tail_rest
		_p._legs.set_instance_shader_parameter("tail", Vector4(tail.x + _t * TAIL_WAG, tail.y * TAIL_SWAY, 0.0, 0.0))


func _weight() -> float:
	return smoothstep(0.0, BLEND_IN, _t)


static func _hop(b: float) -> float:
	# 每拍一蹦:拍点上落地,拍中间最高(0..1)
	return pow(sin(PI * fposmod(b, 1.0)), 1.6)


static func _snap(x: float) -> float:
	# 0..1 的进度变成「快到位、停住」的节奏感(迪斯科的点指)
	return smoothstep(0.0, 0.35, x)


func _wave(b: float) -> Dictionary:
	# 扭腰挥手:屁股左右扭(两拍一来回),双手举成 V 字跟着腰一起左右挥,头往反方向歪
	var sway := sin(PI * b)
	return {
		"lift": 0.045 * _hop(b), "roll": 0.15 * sway, "yaw": 0.12 * sway, "pitch": -0.04,
		"head": Vector3(0.06 * _hop(b) + 0.08, 0.12 * sway, -0.16 * sway),
		"r": Vector3(0.62 + 0.4 * sway, 1.0, -0.12), "l": Vector3(-(0.62 - 0.4 * sway), 1.0, -0.12),
	}


func _disco(b: float) -> Dictionary:
	# 迪斯科:一只手在「指向右上」和「甩到身侧下方」之间每拍换一下(快到位、停住),另一只手叉在身侧;
	# 每 8 拍换手。头每拍往前点一下,身体扭向指着的那边
	var bar := floori(b / 8.0)
	var side := 1.0 if bar % 2 == 0 else -1.0
	var beat := floori(b)
	var k := _snap(fposmod(b, 1.0))
	var up := beat % 2 == 0
	var from := Vector3(0.95, -0.25, -0.3) if up else Vector3(0.72, 1.0, -0.3)
	var to := Vector3(0.72, 1.0, -0.3) if up else Vector3(0.95, -0.25, -0.3)
	var point := from.lerp(to, k)
	var up_amount := (k if up else 1.0 - k)
	var hip := Vector3(0.75, -0.65, 0.15)
	var nod := pow(maxf(sin(TAU * fposmod(b, 1.0)), 0.0), 2.0)
	var pose := {
		"lift": 0.04 * _hop(b), "roll": -0.06 * side * up_amount, "yaw": 0.18 * side * (up_amount - 0.3), "pitch": -0.03,
		"head": Vector3(0.12 * up_amount - 0.14 * nod, 0.22 * side * up_amount, 0.1 * side * up_amount),
	}
	pose["r" if side > 0.0 else "l"] = Vector3(point.x * side, point.y, point.z)
	pose["l" if side > 0.0 else "r"] = Vector3(-hip.x * side, hip.y, hip.z)
	return pose


func _spin(b: float) -> Dictionary:
	# 转圈:8 拍一轮——前 4 拍原地蹦、左右手轮流往上挥拳;第 4 拍蹲一下,第 4.5–6 拍蹦起来原地转一整圈
	# (双手平举像小陀螺);落地压一下,双手举成 V 字「锵锵」。每轮换个方向转
	var cycle := floori(b / 8.0)
	var turn := 1.0 if cycle % 2 == 0 else -1.0
	var c := fposmod(b, 8.0)
	var pose := {"lift": 0.0, "roll": 0.0, "yaw": 0.0, "pitch": -0.04, "spin": 0.0, "head": Vector3(0.1, 0.0, 0.0)}
	if c < 4.0:
		var pump := sin(PI * fposmod(c, 1.0))
		var right := floori(c) % 2 == 0
		var high := Vector3(0.5, 1.0, -0.15)
		var low := Vector3(0.75, 0.25, -0.35)
		pose["lift"] = 0.05 * _hop(c)
		pose["r"] = low.lerp(high, pump if right else 0.0)
		var left := low.lerp(high, 0.0 if right else pump)
		pose["l"] = Vector3(-left.x, left.y, left.z)
		pose["roll"] = 0.08 * (1.0 if right else -1.0) * pump
		pose["head"] = Vector3(0.1 + 0.08 * pump, 0.15 * (1.0 if right else -1.0) * pump, 0.0)
	elif c < 6.0:
		var air := clampf((c - 4.5) / 1.5, 0.0, 1.0)
		var crouch := clampf((c - 4.0) / 0.5, 0.0, 1.0)
		pose["lift"] = -0.025 * sin(PI * crouch) * (1.0 - air) + 0.26 * sin(PI * air)
		pose["spin"] = TAU * turn * smoothstep(0.0, 1.0, air)
		var arms := Vector3(1.0, 0.25 + 0.15 * sin(PI * air), -0.05)
		pose["r"] = arms
		pose["l"] = Vector3(-arms.x, arms.y, arms.z)
		pose["head"] = Vector3(0.22 * sin(PI * air), 0.0, 0.1 * turn * sin(PI * air))
	else:
		var land := c - 6.0
		var squash := exp(-land * 5.0) * sin(land * 9.0)
		pose["lift"] = maxf(-0.03 * squash, -0.03) + 0.03 * maxf(squash, 0.0)
		var v := Vector3(0.7, 1.0, -0.1)
		pose["r"] = v
		pose["l"] = Vector3(-v.x, v.y, v.z)
		pose["head"] = Vector3(0.18, 0.0, 0.0)
	return pose


func _chicken(b: float) -> Dictionary:
	# 小鸡舞:16 拍一轮——4 拍「鸡嘴」(双手在脸前一开一合,头往前啄)、4 拍扇翅膀、4 拍扭屁股、4 拍拍手
	var c := fposmod(b, 16.0)
	var phase := floori(c / 4.0)
	var pose := {"lift": 0.0, "roll": 0.0, "yaw": 0.0, "pitch": -0.04, "head": Vector3(0.05, 0.0, 0.0), "neck": Vector3.ZERO}
	match phase:
		0:
			var snap := 0.5 + 0.5 * sin(TAU * 2.0 * c)
			pose["r"] = palm(1.0, 0.1 + 0.12 * snap, 0.56)
			pose["l"] = palm(-1.0, 0.1 + 0.12 * snap, 0.56)
			var peck := pow(maxf(sin(TAU * c), 0.0), 3.0)
			pose["neck"] = Vector3(0, 0, -0.14 * peck)
			pose["head"] = Vector3(0.05 - 0.22 * peck, 0.0, 0.0)
			pose["lift"] = 0.02 * _hop(c)
		1:
			var flap := 0.5 + 0.5 * sin(TAU * 2.0 * c)
			var wing := Vector3(1.0, -0.45 + 0.85 * flap, 0.2)
			pose["r"] = wing
			pose["l"] = Vector3(-wing.x, wing.y, wing.z)
			pose["lift"] = 0.05 * _hop(c * 2.0)
			pose["head"] = Vector3(0.12 * flap, 0.0, 0.0)
		2:
			var wiggle := sin(TAU * 2.0 * c)
			pose["roll"] = 0.17 * wiggle
			pose["yaw"] = -0.1 * wiggle
			pose["lift"] = -0.015 + 0.015 * absf(wiggle)
			var wing := Vector3(0.9, -0.2, 0.25)
			pose["r"] = wing
			pose["l"] = Vector3(-wing.x, wing.y, wing.z)
			pose["head"] = Vector3(0.0, 0.0, -0.18 * wiggle)
		_:
			var clap := _clap_curve(fposmod(c * 2.0, 1.0))
			pose["r"] = palm(1.0, lerpf(0.2, CLAP_TOUCH, clap), CLAP_Y)
			pose["l"] = palm(-1.0, lerpf(0.2, CLAP_TOUCH, clap), CLAP_Y)
			pose["lift"] = 0.04 * _hop(c)
			pose["head"] = Vector3(0.1 + 0.06 * clap, 0.0, 0.0)
	return pose


func _hat_toss(b: float) -> Dictionary:
	# 抛帽接帽:8 拍一轮——第 0–1 拍右手抬到帽边;第 1–3 拍帽子飞起来(转两圈、翻一个跟头),
	# 双手举高、抬头盯着;第 3 拍帽子落回头上(压扁一下,人跟着一蹲);第 3–5 拍压帽檐致意(帽子往前歪,点头);
	# 第 5–8 拍扭腰挥手,帽子回正
	var c := fposmod(b, 8.0)
	var sway := sin(PI * b)
	var pose := {"lift": 0.0, "roll": 0.0, "yaw": 0.0, "pitch": -0.04, "head": Vector3(0.08, 0.0, 0.0),
		"hat_lift": 0.0, "hat_rot": Vector3.ZERO, "hat_scale": Vector3.ONE}
	var reach := Vector3(0.4, 1.0, -0.12)
	var v := Vector3(0.7, 1.0, -0.1)
	if c < 1.0:
		pose["r"] = Vector3(0.8, 0.2, -0.35).lerp(reach, smoothstep(0.0, 0.8, c))
		pose["l"] = Vector3(-0.8, 0.2, -0.35)
		pose["hat_lift"] = 0.02 * smoothstep(0.6, 1.0, c)
		pose["lift"] = 0.03 * _hop(c)
	elif c < 3.0:
		var air := (c - 1.0) / 2.0
		pose["hat_lift"] = 0.62 * 4.0 * air * (1.0 - air)
		pose["hat_rot"] = Vector3(TAU * smoothstep(0.0, 1.0, air), TAU * 2.0 * air, 0.0)
		pose["head"] = Vector3(0.08 + 0.3 * sin(PI * air), 0.0, 0.0)
		var arms := reach.lerp(v, smoothstep(0.0, 0.3, air))
		pose["r"] = arms
		pose["l"] = Vector3(-v.x, v.y, v.z).lerp(Vector3(-0.8, 0.2, -0.35), 1.0 - smoothstep(0.0, 0.3, air))
		pose["lift"] = 0.02 * sin(PI * air)
	elif c < 5.0:
		var land := c - 3.0
		var squash := exp(-land * 6.0)
		pose["hat_scale"] = Vector3(1.0 + 0.2 * squash, 1.0 - 0.3 * squash, 1.0 + 0.2 * squash)
		pose["lift"] = -0.03 * squash
		var tip := sin(PI * clampf((land - 0.2) / 1.6, 0.0, 1.0))
		pose["hat_rot"] = Vector3(-0.45 * tip, 0.0, 0.1 * tip)
		pose["hat_lift"] = 0.015 * tip
		pose["head"] = Vector3(0.08 - 0.2 * tip, 0.0, 0.08 * tip)
		pose["r"] = reach.lerp(Vector3(0.3, 1.0, -0.45), tip)
		var wave := Vector3(-0.6 - 0.25 * sin(TAU * 2.0 * land), 0.9, -0.15)
		pose["l"] = wave
	else:
		pose["lift"] = 0.045 * _hop(c)
		pose["roll"] = 0.13 * sway
		pose["yaw"] = 0.1 * sway
		pose["head"] = Vector3(0.12, 0.1 * sway, -0.14 * sway)
		pose["r"] = Vector3(0.62 + 0.4 * sway, 1.0, -0.12)
		pose["l"] = Vector3(-(0.62 - 0.4 * sway), 1.0, -0.12)
	return pose


static func palm(side: float, x: float, y: float) -> Vector3:
	# 手停在胸前 (x·side, y)(身体局部)时手臂的方向:手在以肩为心、一臂长的球面上,取前方那一点。
	# 只给方向的话手会停在臂长末端,横向位置对不上——拍手要两只爪子真的碰到
	var shoulder := Vector3(Patron.SHOULDER.x * side, Patron.SHOULDER.y, Patron.SHOULDER.z)
	var dx := x * side - shoulder.x
	var dy := y - shoulder.y
	var dz := -sqrt(maxf(Patron.ARM_LENGTH * Patron.ARM_LENGTH - dx * dx - dy * dy, 0.0))
	return Vector3(dx, dy, dz)


static func _clap_curve(x: float) -> float:
	# 一下拍手的进度 0..1 → 两手合拢程度:快速合上(拍点在 0.35)、慢慢分开
	return smoothstep(0.0, 0.35, x) if x < 0.35 else 1.0 - smoothstep(0.35, 1.0, x)


func _apply(pose: Dictionary, w: float) -> void:
	var p := _p
	var body := p.body
	var spin: float = pose.get("spin", 0.0)
	# 转圈:身体和腿一起绕 SPIN_PIVOT(髋部往前一点、座位坐标的竖直轴)转——绕髋部转的话膝盖、鞋会扫进椅背
	var turn := Basis(Vector3.UP, spin * w)
	var lift := Vector3(0.0, pose.get("lift", 0.0) * w, 0.0)
	body.position = SPIN_PIVOT + turn * (Patron.HIP - SPIN_PIVOT) + lift
	var rot := Vector3(-Patron.SITTING_UP_LEAN + pose.get("pitch", 0.0), pose.get("yaw", 0.0) + spin, pose.get("roll", 0.0))
	body.rotation = body.rotation.lerp(rot, w)
	# 腿跟着屁股抬起(不往下沉进座面),转圈时跟身体绕同一根轴
	p._legs.transform = Transform3D(turn, SPIN_PIVOT - turn * SPIN_PIVOT + Vector3(0.0, maxf(lift.y, 0.0), 0.0))
	if pose.has("head"):
		p.head.rotation = p.head.rotation.lerp(pose["head"], w)
	if pose.has("neck"):
		p.set_neck_target(pose["neck"])
	if pose.has("r"):
		_aim(p._arm_r, pose["r"], w)
	if pose.has("l"):
		_aim(p._arm_l, pose["l"], w)
	if _hat != null and is_instance_valid(_hat) and p._hat == _hat and pose.has("hat_lift"):
		var r: Vector3 = pose["hat_rot"]
		var spin_basis := Basis.from_euler(Vector3(r.x * w, r.y * w, r.z * w)) * Basis.from_scale(Vector3.ONE.lerp(pose["hat_scale"], w))
		_hat.transform = Transform3D(_hat_rest.basis * spin_basis, _hat_rest.origin + Vector3(0.0, pose["hat_lift"] * w, 0.0))


func _aim(arm: Node3D, dir: Vector3, w: float) -> void:
	# 手臂指向 dir(身体局部方向);w < 1 时从当前姿势插过去
	_p._resting[arm] = false
	var q: Quaternion = _p._arm_quat(arm, arm.position + dir, true)   # 手掌不落进大头里(Patron.clear_of_head)
	arm.quaternion = arm.quaternion.slerp(q, w) if w < 1.0 else q


# —— 鼓掌 ——

func _clap(delta: float) -> void:
	var p := _p
	var w := _weight()
	var together := 0.0
	var lift := 0.0
	if _clap_left > 0:
		_clap_phase += delta * _clap_rate
		if _clap_phase >= 1.0:
			_clap_phase -= 1.0
			_clap_left -= 1
			if _clap_left == 0:
				_rest_left = _rng.randf_range(CLAP_REST.x, CLAP_REST.y)
				_pump = 0.0 if _rng.randf() < 0.45 else 0.001
				_pump_side = 1.0 if _rng.randf() < 0.5 else -1.0
		together = _clap_curve(_clap_phase)
		lift = 0.012 * together
	else:
		_rest_left -= delta
		if _rest_left <= 0.0:
			_clap_left = _rng.randi_range(CLAP_BURST.x, CLAP_BURST.y)
			_clap_phase = 0.0
	var right := palm(1.0, lerpf(0.2, CLAP_TOUCH, together), CLAP_Y)
	var left := palm(-1.0, lerpf(0.2, CLAP_TOUCH, together), CLAP_Y)
	if _clap_left == 0:
		# 歇着:手松开放低一点;有时举拳欢呼一下
		right = palm(1.0, 0.26, CLAP_Y - 0.06)
		left = palm(-1.0, 0.26, CLAP_Y - 0.06)
		if _pump > 0.0:
			_pump = minf(_pump + delta / 0.9, 1.0)
			var up := sin(PI * _pump)
			var fist := Vector3(0.35, 1.0, -0.2)
			if _pump_side > 0.0:
				right = right.lerp(fist, up)
			else:
				left = left.lerp(Vector3(-fist.x, fist.y, fist.z), up)
			lift = 0.03 * up
	p.body.position = Patron.HIP + Vector3(0.0, lift * w, 0.0)
	p._legs.position = Vector3(0.0, lift * w, 0.0)
	_aim(p._arm_r, right, w)
	_aim(p._arm_l, left, w)
	p._antics.head_add.x = 0.06 * together


# —— 出局的人抽一下手 ——

func _twitch(delta: float) -> void:
	if _twitch_t < 0.0:
		_twitch_in -= delta
		if _twitch_in <= 0.0:
			_twitch_t = 0.0
			_twitch_arm = _p._arm_l if _rng.randf() < 0.5 else _p._arm_r
		return
	_twitch_t += delta
	var k := _twitch_t / TWITCH_TIME
	var arm := _twitch_arm
	if k >= 1.0:
		arm.quaternion = _dead_quats[arm]
		_twitch_t = -1.0
		_twitch_in = _rng.randf_range(TWITCH_EVERY.x, TWITCH_EVERY.y)
		return
	# 两下快速的小抽动:往上抬一点再落回去
	var jerk := sin(PI * minf(k * 2.0, 1.0)) * 0.3 + sin(PI * clampf(k * 2.0 - 1.0, 0.0, 1.0)) * 0.15
	arm.quaternion = _dead_quats[arm] * Quaternion(Vector3.RIGHT, jerk)


# —— 音符 ——

func _build_notes() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = note_mesh()
	mm.instance_count = NOTE_COUNT
	for i in NOTE_COUNT:
		mm.set_instance_color(i, NOTE_COLORS[i % NOTE_COLORS.size()])
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3.ZERO))
	_notes = MultiMeshInstance3D.new()
	_notes.name = "Notes"
	_notes.multimesh = mm
	_notes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_notes.extra_cull_margin = 0.8
	add_child(_notes)


func _spin_notes() -> void:
	# 音符从头两侧轮流冒出来,边飘高边左右晃,冒出时弹大、飘到头再缩没
	if _notes == null:
		return
	var head := _p.to_local(_p.head_position())
	var mm := _notes.multimesh
	for i in NOTE_COUNT:
		var k := fposmod(_t / NOTE_CYCLE + float(i) / NOTE_COUNT, 1.0)
		var side := 1.0 if i % 2 == 0 else -1.0
		var pos := head + Vector3(side * (0.36 + 0.08 * k) + 0.05 * sin(k * TAU * 1.5), 0.12 + 0.5 * k, -0.05)
		var size := smoothstep(0.0, 0.15, k) * (1.0 - smoothstep(0.75, 1.0, k)) * _weight()
		var basis := Basis(Vector3.FORWARD, 0.35 * sin(k * TAU + i)).scaled(Vector3.ONE * maxf(size, 0.001))
		mm.set_instance_transform(i, Transform3D(basis, pos))


static func note_mesh() -> Mesh:
	# 八分音符 ♪:扁圆的符头(往左下歪)、竖着的符干、往右下飘的符尾;不打光的纯色,颜色来自 MultiMesh 实例
	if not _cache.has("note"):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache["note"] = MeshForge.cached("dance:note", func(f: MeshForge):
			f.paint(Color.WHITE, 1.0)
			f.sphere(0.03, 12, MeshForge.xf(Vector3(0, 0, 0), Vector3(0, 0, 25), Vector3(1.25, 0.85, 0.45)))
			f.box(Vector3(0.011, 0.11, 0.011), MeshForge.xf(Vector3(0.031, 0.055, 0)))
			f.box(Vector3(0.011, 0.055, 0.011), MeshForge.xf(Vector3(0.05, 0.088, 0), Vector3(0, 0, 55))),
			{&"main": mat})
	return _cache["note"]


static func clear_cache() -> void:
	_cache.clear()
