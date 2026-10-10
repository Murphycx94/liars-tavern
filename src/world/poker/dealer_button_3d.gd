class_name DealerButton3D
extends Node3D
# 庄家按钮:胖乎乎的圆角圆片写「D」。字按本机视角正立(同桌上的牌);换座位时绕桌心沿圆弧滑过去,
# 直线会从公共牌架上穿过。二次打磨(2026-10-10):一份缓存的 prop 网格(柔红软胶边圈 + 柔黄铜细线 + 奶油色微鼓顶面),
# 不再每个按钮新建两份 StandardMaterial3D;软胶质感与其他道具一样走卡通光照。


const RADIUS := 0.05
const THICKNESS := 0.014
const SEGMENTS := 40               # 圆片的边数
const FACE_INSET := 0.86           # 奶油色顶面半径占 RADIUS 的比例,露出一圈边
const FACE_THICKNESS := 0.002
const EDGE := 0.004                # 边圈上下的圆角半径
const INK := Color(0.30, 0.17, 0.14)   # 暖可可色的字(不是近黑)
const LETTER_PIXEL := 0.0005       # Label3D 每像素多少米:96 号字约 4.8 厘米高
const LETTER_FONT_SIZE := 96
const LETTER_LIFT := 0.0006        # 字贴在顶面上方一点,免得与顶面 Z 冲突

var _tween: Tween = null


func _init() -> void:
	var disc := MeshKit.add(self, MeshForge.cached("prop:dealer_button", button_recipe, {&"metal": WorldMaterials.prop()}), null)
	disc.name = "Disc"
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var letter := Label3D.new()
	letter.text = "D"
	letter.font_size = LETTER_FONT_SIZE
	letter.pixel_size = LETTER_PIXEL
	letter.modulate = INK
	letter.outline_size = 0
	letter.shaded = true
	letter.double_sided = false
	# 平躺在顶面上:字面朝上,字头朝 −Z(本机视角正立)
	letter.rotation_degrees = Vector3(-90, 0, 0)
	letter.position = Vector3(0, THICKNESS + FACE_THICKNESS + LETTER_LIFT, 0)
	add_child(letter)


static func button_recipe(f: MeshForge) -> void:
	# 车削:柔红边圈(上下圆角 EDGE,底面贴桌)+ 顶面外圈一道柔黄铜细线 + 奶油色顶面(中间微微鼓起 FACE_THICKNESS)
	f.surface(&"metal")
	WorldMaterials.paint_prop(f, "enamel_red")
	var rim := PackedVector2Array([Vector2(0.0, 0.0), Vector2(RADIUS - EDGE, 0.0)])
	for k in range(1, 5):
		var a := -PI / 2.0 + PI / 2.0 * k / 4.0
		rim.append(Vector2(RADIUS - EDGE + cos(a) * EDGE, EDGE + sin(a) * EDGE))
	for k in range(1, 5):
		var a := PI / 2.0 * k / 4.0
		rim.append(Vector2(RADIUS - EDGE + cos(a) * EDGE, THICKNESS - EDGE + sin(a) * EDGE))
	rim.append(Vector2(RADIUS * FACE_INSET, THICKNESS))
	f.lathe(rim, SEGMENTS, PackedInt32Array([1]))
	WorldMaterials.paint_prop(f, "brass_soft")
	var line := RADIUS * FACE_INSET
	f.lathe(PackedVector2Array([Vector2(line + 0.0026, THICKNESS - 0.0004), Vector2(line + 0.0011, THICKNESS + 0.0011),
		Vector2(line - 0.0004, THICKNESS + 0.0004)]), SEGMENTS)
	WorldMaterials.paint_prop(f, "candy_cream")
	var face := PackedVector2Array()
	for k in 6:
		var t := 1.0 - k / 5.0
		face.append(Vector2(RADIUS * FACE_INSET * t, THICKNESS + FACE_THICKNESS * (1.0 - t * t)))
	f.lathe(face, SEGMENTS)


func is_moving() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


func move_to(target: Vector3, duration: float) -> Tween:
	# 绕桌心按角度与半径插值滑到目标;duration ≤ 0 时直接落位(返回 null)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if duration <= 0.0:
		position = target
		return null
	var from := position
	var from_angle := TableWorld.angle_of(from)
	var to_angle := TableWorld.angle_of(target)
	var from_radius := Vector2(from.x, from.z).length()
	var to_radius := Vector2(target.x, target.z).length()
	_tween = create_tween()
	_tween.tween_method(func(t: float):
		var flat := SeatLayout.direction(lerp_angle(from_angle, to_angle, t)) * lerpf(from_radius, to_radius, t)
		position = Vector3(flat.x, lerpf(from.y, target.y, t), flat.z),
		0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return _tween
