class_name Revolver3D
extends Node3D
# 左轮手枪模型:原点在握把(手持点),枪管沿本地 -Z。转轮可旋转、击锤可扳动、开火有后坐。
# 网格配方在 RevolverModel(玩具式单动左轮:糖果色犁柄握把与枪口帽、五槽转轮、圆珠准星、黄铜护圈)。


const BARREL_Y := RevolverModel.BARREL_Y
const DRUM_POS := RevolverModel.DRUM_POS
const HAMMER_PIVOT := RevolverModel.HAMMER_PIVOT
const MUZZLE_POS := RevolverModel.MUZZLE_POS
const CHAMBER_STEP := TAU / Revolver.CHAMBERS
# 握持:爪心 = 枪原点,枪管沿手的 −Z;往前挪 4 mm,机匣与转轮露在拳头外面,握把大半包在拳里
const HOLD_OFFSET := Transform3D(Basis(), Vector3(0, 0, -0.004))
# 侧放(左侧着地,绕枪管轴转 PI/2 + ROLL)。四个常量都由测试按网格顶点校验:
# 地上:转轮与底帽同时着地,最低点离原点 REST_HALF_WIDTH;
# 桌上:转轮压在毡面(FELT_TOP)、底帽落在木桌面(低 4 mm),转轮最低点离原点 TABLE_REST_LIFT
const REST_ROLL := -0.1030
const REST_HALF_WIDTH := 0.0253
const TABLE_REST_ROLL := -0.1335
const TABLE_REST_LIFT := 0.0236

var drum: Node3D
var hammer: Node3D
var muzzle: Marker3D


static func forge_jobs() -> Array:
	# 启动时后台预建(材质在主线程先建好)
	return [
		["revolver:body", RevolverModel.body, _materials()],
		["revolver:drum", RevolverModel.drum, _materials()],
		["revolver:hammer", RevolverModel.hammer, _materials()],
	]


static func _materials() -> Dictionary:
	# 三件都只有一个 prop surface(糖果色握把也是顶点色,不再用木纹材质)
	return {&"metal": WorldMaterials.prop()}


static func aligned_angle(a: float) -> float:
	# 弹膛角从 12 点起排:转角是整格时恰好一个弹膛在 12 点,与枪管同轴
	return roundf(a / CHAMBER_STEP) * CHAMBER_STEP


func _init() -> void:
	var body := MeshKit.pivot(self, Vector3.ZERO, "Body")
	MeshKit.add(body, MeshForge.cached("revolver:body", RevolverModel.body, _materials()), null).name = "BodyMesh"
	# 转轮:5 个一模一样的弹膛(标记只表示位置,外观不区分),绕枪管轴旋转
	drum = MeshKit.pivot(body, DRUM_POS, "Drum")
	MeshKit.add(drum, MeshForge.cached("revolver:drum", RevolverModel.drum, _materials()), null).name = "DrumMesh"
	for i in Revolver.CHAMBERS:
		var marker := Marker3D.new()
		marker.name = "Chamber%d" % (i + 1)
		marker.position = RevolverModel.chamber_offset(i) + Vector3(0, 0, -RevolverModel.DRUM_LENGTH / 2.0)
		drum.add_child(marker)
	# 击锤:绕铰点扳动
	hammer = MeshKit.pivot(body, HAMMER_PIVOT, "Hammer")
	MeshKit.add(hammer, MeshForge.cached("revolver:hammer", RevolverModel.hammer, _materials()), null).name = "HammerMesh"
	muzzle = Marker3D.new()
	muzzle.position = MUZZLE_POS
	add_child(muzzle)


func spin_drum(duration: float, turns := 2.5) -> Tween:
	# 转整数格停下,总有一个弹膛对准枪管(转几格与子弹位置无关,所有弹膛外观一样)
	var target := aligned_angle(drum.rotation.z + TAU * turns)
	var tween := create_tween()
	tween.tween_property(drum, "rotation:z", target, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	return tween


func cock_hammer(duration := 0.18) -> Tween:
	var tween := create_tween()
	tween.tween_property(hammer, "rotation:x", deg_to_rad(38.0), duration).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(drum, "rotation:z", aligned_angle(drum.rotation.z + CHAMBER_STEP), duration)
	return tween


func release_hammer() -> Tween:
	var tween := create_tween()
	tween.tween_property(hammer, "rotation:x", 0.0, 0.04)
	return tween


func recoil() -> Tween:
	# 枪口上跳后回位
	var base := rotation
	var tween := create_tween()
	tween.tween_property(self, "rotation:x", base.x + 0.5, 0.05).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation:x", base.x, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return tween


func muzzle_transform() -> Transform3D:
	return muzzle.global_transform
