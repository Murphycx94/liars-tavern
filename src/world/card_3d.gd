class_name Card3D
extends Node3D
# 3D 卡牌:一片带厚度的圆角薄片(本地 +Y 为正面法线,宽沿 X、高沿 Z,牌顶朝 -Z,以 y=0 为中面)。
# 所有牌共用一份网格;骗子酒馆的牌还共用一份材质(牌型、两面、光晕都是实例参数),德州牌每张一份材质。
# 支持翻面、弧线飞行、悬停抬起、选中高亮,以及射线拾取(纯数学,无需物理体)。


const WIDTH := 0.12
const HEIGHT := 0.1733
const THICKNESS := 0.0008
const CORNER := 0.0146667       # = 44/360 × WIDTH,与贴图圆角一致(CardFaces.CORNER_RADIUS)
const CORNER_STEPS := 8         # 圆角加大后每角多两段:轮廓 36 点,正反面 + 侧边共 144 个三角形(≤ 160)
const CARD_SHADER := preload("res://src/world/shaders/card.gdshader")

static var _shared: ShaderMaterial = null   # 骗子酒馆的 5 种牌共用
static var _poker := {}                     # 德州牌(与斗地主的两张王):牌值 -> 材质(正面是单张贴图)
static var _poker_back: ShaderMaterial = null   # 德州的背面朝上的牌:两面都是德州牌背

var kind := CardFaces.BACK     # 正面牌型;BACK 表示未知(他人的牌)
var _mesh: MeshInstance3D
var _glow_tween: Tween = null


static func material_for(face_kind: int) -> ShaderMaterial:
	# 德州牌(含斗地主的大王 / 小王)每张一份材质(正面贴图不同);骗子酒馆的牌都用共享材质,牌型走实例参数 face
	if PokerCard.is_card(face_kind) or DdzJokerFaces.is_kind(face_kind):
		if not _poker.has(face_kind):
			var mat := _new_material()
			mat.set_shader_parameter("single_face", true)
			mat.set_shader_parameter("card_texture", CardFaces.texture(face_kind))
			mat.set_shader_parameter("back_texture", PokerFaces.back_texture())
			_poker[face_kind] = mat
		return _poker[face_kind]
	if _shared == null:
		_shared = _new_material()
	return _shared


static func _new_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CARD_SHADER
	mat.set_shader_parameter("faces", CardFaces.face_array())
	mat.set_shader_parameter("foil", CardFaces.foil_array())
	return mat


static func poker_back_material() -> ShaderMaterial:
	if _poker_back == null:
		_poker_back = _new_material()
		_poker_back.set_shader_parameter("single_face", true)
		_poker_back.set_shader_parameter("card_texture", PokerFaces.back_texture())
		_poker_back.set_shader_parameter("back_texture", PokerFaces.back_texture())
	return _poker_back


static func clear_materials() -> void:
	_shared = null
	_poker = {}
	_poker_back = null


static func refresh_materials() -> void:
	# 牌面纹理异步生成完毕后重绑数组纹理(与德州的单张牌面)
	if _poker_back != null:
		_poker_back.set_shader_parameter("card_texture", PokerFaces.back_texture())
		_poker_back.set_shader_parameter("back_texture", PokerFaces.back_texture())
	for mat: ShaderMaterial in ([_shared] if _shared != null else []) + ([_poker_back] if _poker_back != null else []) \
			+ _poker.values():
		mat.set_shader_parameter("faces", CardFaces.face_array())
		mat.set_shader_parameter("foil", CardFaces.foil_array())
	for face_kind in _poker:
		_poker[face_kind].set_shader_parameter("card_texture", CardFaces.texture(face_kind))
		_poker[face_kind].set_shader_parameter("back_texture", PokerFaces.back_texture())


static func slab_mesh() -> ArrayMesh:
	return MeshForge.cached("prop:card", slab_recipe)


static func outline() -> PackedVector2Array:
	# 圆角矩形轮廓 (x, z):+z → +x → −z → −x(从 +Y 往下看是逆时针)
	var pts := PackedVector2Array()
	var hx := WIDTH / 2.0 - CORNER
	var hz := HEIGHT / 2.0 - CORNER
	var centers := [Vector2(hx, hz), Vector2(hx, -hz), Vector2(-hx, -hz), Vector2(-hx, hz)]
	for c in 4:
		for k in CORNER_STEPS + 1:
			var a := PI / 2.0 - c * PI / 2.0 - PI / 2.0 * k / CORNER_STEPS
			pts.append(centers[c] + Vector2(cos(a), sin(a)) * CORNER)
	return pts


static func slab_recipe(f: MeshForge) -> void:
	# 正反面各一个扇面 + 一圈侧边;正面 u = x/W + 0.5、v = z/H + 0.5,背面 u 镜像(同原来背面绕 Z 转 π)
	var ring := outline()
	var n := ring.size()
	var half := THICKNESS / 2.0
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for face in 2:
		var y := half if face == 0 else -half
		var base := points.size()
		points.append(Vector3(0, y, 0))
		normals.append(Vector3(0, 1 if face == 0 else -1, 0))
		uvs.append(Vector2(0.5, 0.5))
		for p in ring:
			points.append(Vector3(p.x, y, p.y))
			normals.append(Vector3(0, 1 if face == 0 else -1, 0))
			uvs.append(Vector2(p.x / WIDTH + 0.5 if face == 0 else 0.5 - p.x / WIDTH, p.y / HEIGHT + 0.5))
		for k in n:
			var a := base + 1 + k
			var b := base + 1 + (k + 1) % n
			# 轮廓从 +Y 看是逆时针;Godot 正面是顺时针:正面按 中心→b→a,背面反过来(同 MeshForge.cylinder 的顶盖)
			if face == 0:
				indices.append_array([base, b, a])
			else:
				indices.append_array([base, a, b])
	var side := points.size()
	for k in n + 1:
		var p := ring[k % n]
		var prev := ring[(k - 1 + n) % n]
		var next := ring[(k + 1) % n]
		var t := (next - prev).normalized()
		var out := Vector3(-t.y, 0, t.x)
		for y in [half, -half]:
			points.append(Vector3(p.x, y, p.y))
			normals.append(out)
			uvs.append(Vector2(p.x / WIDTH + 0.5, p.y / HEIGHT + 0.5))
	for k in n:
		var a := side + k * 2
		indices.append_array([a, a + 2, a + 1, a + 2, a + 3, a + 1])
	f.raw(points, normals, uvs, indices)


func _init() -> void:
	_mesh = MeshKit.add(self, slab_mesh(), material_for(CardFaces.BACK))
	_mesh.name = "Slab"
	set_glow(0.0)


func set_kind(face_kind: int) -> void:
	kind = face_kind
	_mesh.material_override = material_for(face_kind)
	_mesh.set_instance_shader_parameter("face", CardFaces.layer(face_kind))


func show_poker_back() -> void:
	# 德州里背面朝上的牌(别人的底牌、弃牌堆):牌型仍记作 BACK,外观换成德州牌背
	kind = CardFaces.BACK
	_mesh.material_override = poker_back_material()


func set_both_faces(face_kind: int) -> void:
	# 桌心立牌:两面都显示目标牌,旋转时任何角度都看得到
	set_kind(face_kind)
	_mesh.set_instance_shader_parameter("both_faces", 1.0)


func set_glow(amount: float, color := Color(1.0, 0.82, 0.4)) -> void:
	_mesh.set_instance_shader_parameter("glow", amount)
	_mesh.set_instance_shader_parameter("glow_color", color)


func pulse_glow(color: Color, peak: float, duration: float) -> void:
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.tween_method(func(v: float): set_glow(v, color), 0.0, peak, duration * 0.25)
	_glow_tween.tween_method(func(v: float): set_glow(v, color), peak, peak * 0.45, duration * 0.75)


func fly_to(target: Transform3D, duration: float, arc_height := 0.12, spin := 0.0) -> Tween:
	# 二次贝塞尔弧线飞行;旋转用四元数插值,可附加绕法线的旋转
	var from := global_transform
	var mid := (from.origin + target.origin) / 2.0 + Vector3.UP * arc_height
	var from_q := from.basis.get_rotation_quaternion()
	var to_q := target.basis.get_rotation_quaternion()
	var to_scale := target.basis.get_scale()
	var from_scale := from.basis.get_scale()
	var tween := create_tween()
	tween.tween_method(func(t: float):
		var p := from.origin.lerp(mid, t).lerp(mid.lerp(target.origin, t), t)
		var q := from_q.slerp(to_q, t)
		if spin != 0.0:
			q = q * Quaternion(Vector3.UP, spin * sin(t * PI))
		global_transform = Transform3D(Basis(q).scaled(from_scale.lerp(to_scale, t)), p),
		0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween


func flip_to_face(duration: float, lift := 0.05) -> Tween:
	# 抬起 → 绕牌的纵轴翻转 180° → 落下
	var start := transform
	var tween := create_tween()
	tween.tween_method(func(t: float):
		var angle := PI * t
		var offset := Vector3.UP * sin(t * PI) * lift
		transform = Transform3D(start.basis * Basis(Vector3.BACK, angle), start.origin + offset),
		0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	return tween


func ray_hit_distance(origin: Vector3, direction: Vector3) -> float:
	# 射线与牌面矩形求交:返回沿射线距离,未命中返回 -1
	var inv := global_transform.affine_inverse()
	var local_origin := inv * origin
	var local_dir := inv.basis * direction
	if absf(local_dir.y) < 0.00001:
		return -1.0
	var t := -local_origin.y / local_dir.y
	if t <= 0.0:
		return -1.0
	var hit := local_origin + local_dir * t
	if absf(hit.x) > WIDTH / 2.0 or absf(hit.z) > HEIGHT / 2.0:
		return -1.0
	return (global_transform * hit).distance_to(origin)
