class_name ChipStack3D
extends Node3D
# 一摞筹码:金额按面额贪心拆分,每种面额立成列(每列最多 COLUMN_MAX 枚),每堆最多显示 DISPLAY_MAX 枚。
# 整摞只用一个 MultiMeshInstance3D(逐实例颜色)且不投影:8 人满桌最坏约 900 枚,逐枚建网格、投影会多出上千次绘制。
# 准确金额由界面的 2D 标签显示,这里只求「看起来有那么多钱」。本地 −Z 朝桌心:大面额那一排在里侧。


const DENOMINATIONS := [5000, 1000, 500, 100, 50, 10]
# 面额颜色(规格 §5.4,按 sRGB 填写):10 象牙白、50 红、100 绿、500 黑、1000 金、5000 紫。
# 二次打磨(2026-10-10)换成同色相的粉彩:柔红、薄荷绿、深靛(「黑」也带色相)、奶黄金、淡紫,远看仍一眼分得清
const COLORS := {
	10: Color(0.90, 0.87, 0.78),
	50: Color(0.82, 0.33, 0.32),
	100: Color(0.30, 0.66, 0.46),
	500: Color(0.22, 0.22, 0.33),
	1000: Color(0.90, 0.72, 0.30),
	5000: Color(0.60, 0.42, 0.78),
}
# 比真筹码(直径 3.9 厘米)大一圈:德州桌直径近 3 米、越肩镜头离桌心 2.6 米,真尺寸的筹码在 1280×720 下只剩几个像素
const CHIP_RADIUS := 0.03
const CHIP_HEIGHT := 0.0094
const CHIP_SEGMENTS := 20
const CHIP_BEVEL := 0.0016     # 上下边一圈圆角(软胶筹码,不再是锋利的圆柱边)
const COLUMN_MAX := 10
const DISPLAY_MAX := 40
# 显示上限 40 枚时贪心拆分最多 8 列:5000 最多占 4 列,其余面额各至多 1 列,且两者此消彼长(见测试穷举)
const MAX_COLUMNS := 8
const ROW_LENGTH := 3          # 每排最多几列,多出来的往桌心方向另起一排
const COLUMN_GAP := 0.004
const JITTER := 0.0012         # 每枚筹码的随机错位:码得太齐像一根圆柱
const CHIP_SHADER := preload("res://src/world/poker/chip.gdshader")

static var _mesh: ArrayMesh = null
static var _material: ShaderMaterial = null

var amount := 0
var _instance: MultiMeshInstance3D
var _count := 0
var _top := 0.0


func _init() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = chip_mesh()
	mm.instance_count = DISPLAY_MAX
	mm.visible_instance_count = 0
	_instance = MultiMeshInstance3D.new()
	_instance.multimesh = mm
	_instance.material_override = chip_material()
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_instance)


# —— 拆分与排布(纯函数)——

static func breakdown(value: int) -> Array:
	# [[面额, 枚数]],从大到小;金额都是 10 的倍数,不足 10 的零头不画
	var result := []
	var rest := maxi(value, 0)
	for denom in DENOMINATIONS:
		var count: int = rest / denom
		if count > 0:
			result.append([denom, count])
			rest -= count * denom
	return result


static func columns(value: int) -> Array:
	# [[面额, 枚数]] 每项是一列(≤ COLUMN_MAX 枚);超过 DISPLAY_MAX 的部分省略小面额
	var result := []
	var budget := DISPLAY_MAX
	for pair in breakdown(value):
		var left: int = mini(pair[1], budget)
		budget -= left
		while left > 0:
			var count := mini(left, COLUMN_MAX)
			result.append([pair[0], count])
			left -= count
	return result


static func column_offset(index: int, count: int) -> Vector2:
	# 第 index 列在堆内的位置 (x, z):每排 ROW_LENGTH 列居中,第 0 排在里侧(−Z,朝桌心)
	var rows := ceili(float(count) / ROW_LENGTH)
	var row := index / ROW_LENGTH
	var in_row := mini(count - row * ROW_LENGTH, ROW_LENGTH)
	var col := index % ROW_LENGTH
	var pitch := column_pitch()
	return Vector2((col - (in_row - 1) / 2.0) * pitch, (row - (rows - 1) / 2.0) * pitch)


static func chips(value: int) -> Array:
	# [{"transform", "color"}]:每枚筹码在堆内的摆放(堆的本地坐标),set_amount 照它写进 MultiMesh。
	# 错位与转角按序号确定:同一金额每次摆出来都一样,不会每次对账都抖一下
	var result := []
	var cols := columns(value)
	for c in cols.size():
		var base := column_offset(c, cols.size())
		for level in cols[c][1]:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(result.size() * 7919 + 17)
			var jitter := Vector2(rng.randf_range(-JITTER, JITTER), rng.randf_range(-JITTER, JITTER))
			var pos := Vector3(base.x + jitter.x, CHIP_HEIGHT * (level + 0.5), base.y + jitter.y)
			result.append({"transform": Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pos), "color": COLORS[cols[c][0]]})
	return result


static func column_pitch() -> float:
	return CHIP_RADIUS * 2.0 + COLUMN_GAP


static func footprint_radius() -> float:
	# 任意金额下所有筹码离堆中心的最远距离(含错位):布局据此保证相邻物件不重叠
	var reach := 0.0
	for count in range(1, MAX_COLUMNS + 1):
		for i in count:
			reach = maxf(reach, column_offset(i, count).length())
	return reach + CHIP_RADIUS + JITTER * sqrt(2.0)


static func chip_mesh() -> ArrayMesh:
	# 车削的圆角筹码:顶面平(镶边与细环画在上面),上下边各一段斜面、法线与侧面平滑过渡(看起来是圆边,每枚 200 面;
	# 满桌最坏约 900 枚),侧面竖直;
	# 顶点色是白色(MultiMesh 的逐实例颜色乘上去不变)。高度、半径与原来的圆柱一样
	if _mesh == null:
		var h := CHIP_HEIGHT / 2.0
		var r := CHIP_RADIUS
		var e := CHIP_BEVEL
		_mesh = MeshForge.commit(MeshForge.run(func(f: MeshForge):
			f.lathe(PackedVector2Array([Vector2(0.0, -h), Vector2(r - e, -h), Vector2(r, -h + e), Vector2(r, h - e),
				Vector2(r - e, h), Vector2(0.0, h)]), CHIP_SEGMENTS, PackedInt32Array([1, 4]))))
	return _mesh


static func chip_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = CHIP_SHADER
		_material.set_shader_parameter("radius", CHIP_RADIUS)
	return _material


static func clear_cache() -> void:
	# 静态缓存持有网格与材质:退出时释放(同 WorldMaterials.clear_cache),免得 ObjectDB 报泄漏
	_mesh = null
	_material = null


# —— 显示 ——

func set_amount(value: int) -> void:
	amount = maxi(value, 0)
	var mm := _instance.multimesh
	var laid := chips(amount)
	for i in laid.size():
		mm.set_instance_transform(i, laid[i]["transform"])
		mm.set_instance_color(i, laid[i]["color"])
	mm.visible_instance_count = laid.size()
	_count = laid.size()
	_top = 0.0
	for column in columns(amount):
		_top = maxf(_top, column[1] * CHIP_HEIGHT)


func chip_count() -> int:
	return _count


func top_height() -> float:
	# 最高一列的顶面高度(堆的本地坐标):2D 金额标签挂在它上方
	return _top


func multimesh() -> MultiMesh:
	return _instance.multimesh
