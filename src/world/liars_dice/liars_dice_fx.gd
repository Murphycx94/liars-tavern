class_name LiarsDiceFx
extends BombCatFx
# 吹牛骰子的演出效果层:挂在 TableWorld.poker_root 下(拆台时一并收走)。通用小件(漫画字、星星、冲击波、闪光、烟团)
# 直接用 BombCatFx 那一套(同样的动森式卡通效果、同样的「每个效果一个根节点、演完自己释放」);这里加吹牛骰子自己的:
# - 桌心的出价标记:一颗放大的骰子(那个点数朝着镜头)+「×N」,喊价时弹出来,之后一直浮在桌心慢慢晃,下一口顶掉它;
# - 开盅计数器:标记下面的「数到 N / 喊了 M」,一颗一颗往上跳,够数变绿;
# - 「开!」大字与拍桌冲击波、真话 / 吹牛判定字、丢骰子的「啵」和小星星。
# 入口都不阻塞;导演按 LiarsDiceCups 与这里的节奏常量去等。


const MARKER_POP := 0.28            # 出价标记弹出来
const MARKER_BOB := 0.012
const MARKER_GUARD_RADIUS := 0.12   # 穿模防护:出价标记(放大的骰子 + 字)在桌心占的半径,探头的头绕开它
const LABEL_GAP := 0.15             # 「×N」在大骰子右边(镜头右方向)这么远
const COUNTER_DROP := 0.16          # 计数器在标记下面这么低
const OPEN_TEXT_SIZE := 1.4
const VERDICT_SIZE := 1.1
const TRUTH_COLOR := Color(0.55, 0.92, 0.55)
const LIE_COLOR := Color(1.0, 0.45, 0.35)
const COUNT_COLOR := Color(1.0, 0.86, 0.5)
const MARKER_TEXT := 0.62           # 「×N」的字号(BombCatFx._label 的倍数:1 ≈ 字高 0.25 米)
const COUNTER_TEXT := 0.46

var _marker: Node3D = null
var _marker_die: MeshInstance3D = null
var _marker_label: Label3D = null
var _marker_face := 0
var _counter: Label3D = null
var _time := 0.0


func _init(p_world: TableWorld) -> void:
	super(p_world)
	name = "LiarsDiceFx"


func _process(delta: float) -> void:
	super(delta)
	_time += delta
	if is_instance_valid(_marker) and is_instance_valid(_marker_die):
		var cam := _camera_pos()
		var base := world.to_global(LiarsDiceLayout.marker_position())
		_marker.global_position = base + Vector3.UP * sin(_time * 2.2) * MARKER_BOB
		var to_cam := cam - _marker.global_position
		to_cam.y *= 0.6
		if Vector2(to_cam.x, to_cam.z).length() > 0.05:
			var face_to_cam := Basis.looking_at(-to_cam.normalized(), Vector3.UP)
			var face_n: Vector3 = LiarsDiceProps.FACE_NORMALS.get(_marker_face, Vector3.UP)
			var face_basis := Basis(Quaternion(face_n, Vector3.BACK)) if face_n.dot(Vector3.BACK) > -0.999 else Basis(Vector3.UP, PI)
			var s := _marker_die.scale
			_marker_die.global_basis = face_to_cam * Basis(Vector3.BACK, sin(_time * 1.3) * 0.12) * face_basis
			_marker_die.scale = s
		if is_instance_valid(_marker_label):
			_marker_label.global_position = _marker.global_position + _camera_right() * LABEL_GAP
		if is_instance_valid(_counter):
			_counter.global_position = _marker.global_position + Vector3.DOWN * COUNTER_DROP


# —— 出价标记 ——

func bid_marker(count: int, face: int) -> void:
	# 桌心浮出「这个点数的大骰子 + ×N」,弹一下;已有标记时顶掉旧的
	clear_bid_marker()
	_marker = _spawn("bid_marker", -1.0)
	_guard_marker()
	_marker.global_position = world.to_global(LiarsDiceLayout.marker_position())
	_marker_face = face
	_marker_die = MeshKit.add(_marker, LiarsDiceProps.die(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 0.05,
		MeshKit.SHADOW_OFF)
	_marker_label = _label("×%d" % count, MARKER_TEXT, COUNT_COLOR)
	_marker.add_child(_marker_label)
	_marker_label.scale = Vector3.ONE * 0.05
	var die := _marker_die
	var label := _marker_label
	var tween := _marker.create_tween().set_parallel()
	tween.tween_property(die, "scale", Vector3.ONE * LiarsDiceLayout.MARKER_SCALE, MARKER_POP).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector3.ONE, MARKER_POP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	shock_ring(_marker.global_position + Vector3.DOWN * 0.12, Color(1.0, 0.9, 0.62), 0.18, 0.35)


func clear_bid_marker() -> void:
	if is_instance_valid(_marker):
		remove_child(_marker)
		_marker.queue_free()
	_marker = null
	_marker_die = null
	_marker_label = null
	_counter = null


func marker_text() -> String:
	return _marker_label.text if is_instance_valid(_marker_label) else ""


func marker_face() -> int:
	return _marker_face if is_instance_valid(_marker) else 0


# —— 开盅计数 ——

func set_counter(n: int, target: int) -> void:
	# 标记下面的计数「数到 n / 喊了 target」:每次变化弹一下,够数变绿
	if not is_instance_valid(_marker):
		_marker = _spawn("bid_marker", -1.0)
		_guard_marker()
		_marker.global_position = world.to_global(LiarsDiceLayout.marker_position())
	if not is_instance_valid(_counter):
		_counter = _label("", COUNTER_TEXT, COUNT_COLOR)
		_marker.add_child(_counter)
	_counter.text = "数到 %d / 喊了 %d" % [n, target]
	_counter.modulate = TRUTH_COLOR if n >= target else COUNT_COLOR
	_counter.scale = Vector3.ONE * 1.35
	var tween := _counter.create_tween()
	tween.tween_property(_counter, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func counter_text() -> String:
	return _counter.text if is_instance_valid(_counter) else ""


# —— 「开!」、判定、丢骰子 ——

func open_burst() -> void:
	# 拍桌大字「开!」:桌心冒出来,冲击波一圈、几颗星星
	var center := world.to_global(LiarsDiceLayout.TABLE_FOCUS + Vector3(0, 0.22, 0))
	pop_text("开!", center, Color(1.0, 0.82, 0.4), OPEN_TEXT_SIZE, 1.0, 0.1)
	shock_ring(world.to_global(LiarsDiceLayout.TABLE_FOCUS), Color(1.0, 0.85, 0.55), 0.9, 0.45)
	star_burst(center, 6, 0.35, 0.7)
	sfx.emit("nope_slap")


func verdict(truthful: bool) -> void:
	var center := world.to_global(LiarsDiceLayout.marker_position() + Vector3(0, 0.16, 0))
	pop_text("真话!" if truthful else "吹牛!", center, TRUTH_COLOR if truthful else LIE_COLOR, VERDICT_SIZE, 1.1, 0.08)
	sfx.emit("sting_truth" if truthful else "sting_lie")


func counted(pos_local: Vector3) -> void:
	# 数到一颗:骰子上方「叮」一闪
	var pos := world.to_global(pos_local + Vector3(0, LiarsDiceLayout.DIE_SIZE * 1.6, 0))
	glint(pos, 0.07)
	sfx.emit("count_tick")


func die_popped(pos_local: Vector3) -> void:
	# 丢骰子:「啵」+ 一小圈星星
	var pos := world.to_global(pos_local + Vector3(0, 0.04, 0))
	star_burst(pos, 6, 0.2, 0.65)
	pop_text("啵!", pos + Vector3(0, 0.1, 0), Color(1.0, 0.9, 0.6), 0.55, 0.7, 0.12)


func _guard_marker() -> void:
	# 穿模防护:探头的头绕开桌心的出价标记(标记收走后自动忽略)
	world.clip_guard.set_prop(&"liars_dice_marker", ClipGuard.follow(_marker, MARKER_GUARD_RADIUS,
		PackedVector3Array([Vector3(0, MARKER_GUARD_RADIUS, 0)]), ClipGuard.BLOCK))
