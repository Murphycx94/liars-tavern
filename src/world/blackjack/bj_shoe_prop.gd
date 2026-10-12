class_name BjShoeProp
extends Node3D
# 21 点桌心牌架后面的一排道具(设计稿 §4):左边发牌用的牌鞋(深色木盒,斜口露出一截德州牌背)、
# 右边收牌的弃牌盘(矮木框)、中间一摞庄家的筹码(纯装饰,赔付与收注都从这里进出)。坐标 = 牌桌世界坐标。
# 都很矮,越肩看过去被庄家的牌挡住一半;零件不多(各一两个网格),不进性能预算的大头。


const SHOE_SIZE := Vector3(0.14, 0.075, 0.2)
const SHOE_TILT_DEG := 12.0          # 牌鞋朝本机一侧低下去一点,牌从斜口滑出
const MOUTH_HEIGHT := 0.05           # 牌鞋口(发牌起点)离桌面
const TRAY_SIZE := Vector3(0.16, 0.022, 0.21)
const TRAY_WALL := 0.008
const TRAY_FLOOR := 0.006            # 弃牌盘底板厚度:收进来的牌搁在它上面
const BANK_AMOUNT := 12_000          # 庄家那摞装饰筹码的面额(只决定码几列、什么颜色)

var bank: ChipStack3D


func _init() -> void:
	name = "BjShoeProp"
	_build_shoe()
	_build_tray()
	bank = ChipStack3D.new()
	bank.name = "Bank"
	bank.set_amount(BANK_AMOUNT)
	bank.position = BjLayout.bank_position()
	add_child(bank)


func register_guards(guard: ClipGuard) -> void:
	# 穿模防护:牌鞋与弃牌盘的占地(探头的头从上面拱过去);跟本节点绑着,拆台后自动忽略
	var spots := {&"bj_shoe": BjLayout.shoe_position(), &"bj_discard": BjLayout.discard_position()}
	for id in spots:
		guard.set_prop(id, ClipGuard.rect(spots[id], Vector3.RIGHT, Vector2(SHOE_SIZE.x, SHOE_SIZE.z) / 2.0 + Vector2(0.03, 0.03),
			SeatLayout.TABLE_TOP + SHOE_SIZE.y + 0.03, ClipGuard.LIFT, self))


func _build_shoe() -> void:
	var shoe := MeshKit.pivot(self, BjLayout.shoe_position(), "Shoe")
	shoe.rotation_degrees = Vector3(-SHOE_TILT_DEG, 25.0, 0)
	MeshKit.add(shoe, MeshKit.box(SHOE_SIZE), WorldMaterials.wood("dark"), Vector3(0, SHOE_SIZE.y / 2.0, 0))
	# 斜口上的黄铜压条与露出的一截牌背
	MeshKit.add(shoe, MeshKit.box(Vector3(SHOE_SIZE.x + 0.006, 0.008, 0.012)), WorldMaterials.brass(),
		Vector3(0, SHOE_SIZE.y, SHOE_SIZE.z / 2.0 - 0.006))
	var card := Card3D.new()
	card.show_poker_back()
	card.name = "ShoeCard"
	shoe.add_child(card)
	card.transform = Transform3D(Basis(Vector3.BACK, PI).scaled(Vector3.ONE * 0.95), Vector3(0, SHOE_SIZE.y + 0.002, 0.02))


func _build_tray() -> void:
	var tray := MeshKit.pivot(self, BjLayout.discard_position(), "DiscardTray")
	tray.rotation_degrees = Vector3(0, -20.0, 0)
	var dark := WorldMaterials.wood("dark")
	MeshKit.add(tray, MeshKit.box(Vector3(TRAY_SIZE.x, TRAY_FLOOR, TRAY_SIZE.z)), dark, Vector3(0, TRAY_FLOOR / 2.0, 0))
	for side in [-1.0, 1.0]:
		MeshKit.add(tray, MeshKit.box(Vector3(TRAY_WALL, TRAY_SIZE.y, TRAY_SIZE.z)), dark,
			Vector3(side * (TRAY_SIZE.x - TRAY_WALL) / 2.0, TRAY_SIZE.y / 2.0, 0))
		MeshKit.add(tray, MeshKit.box(Vector3(TRAY_SIZE.x, TRAY_SIZE.y, TRAY_WALL)), dark,
			Vector3(0, TRAY_SIZE.y / 2.0, side * (TRAY_SIZE.z - TRAY_WALL) / 2.0))
