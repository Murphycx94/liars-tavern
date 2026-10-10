class_name BoardRack
extends Node3D
# 公共牌架(PokerCards 的一部分):桌上一块垫高的底座、与公共牌同角度的斜面托板(垫在牌下面)、
# 前沿一道黄铜托条挡住牌的下边。几何全部取自 PokerLayout 的公共牌槽位;越肩看过去大半被牌挡住,只露出木框与托条。


const MARGIN := 0.025       # 托板比整排公共牌宽出的边
const THICKNESS := 0.006
const LIP_HEIGHT := 0.012   # 托条高出牌的下边
const LIP_DEPTH := 0.012
const LIP_OFFSET := 0.008   # 托条在牌下边之前多远


static func guard_shape(rack: Node3D) -> Dictionary:
	# 穿模防护的形状(牌桌坐标):整排公共牌与托板的水平占地,顶面是斜立的牌的上边(放大回弹时再高一点)
	var tilt := deg_to_rad(PokerLayout.BOARD_TILT_DEG)
	var card_len := Card3D.HEIGHT * PokerLayout.BOARD_SCALE
	var depth := card_len * cos(tilt)
	var front := PokerLayout.board_front_z()
	var top := SeatLayout.TABLE_TOP + PokerLayout.RACK_HEIGHT + card_len * sin(tilt) + 0.01
	return ClipGuard.rect(Vector3(0, 0, front - depth / 2.0), Vector3.RIGHT,
		Vector2(PokerLayout.board_width() / 2.0 + MARGIN, depth / 2.0 + MARGIN), top, ClipGuard.LIFT, rack)


func _init() -> void:
	name = "BoardRack"
	var tilt := deg_to_rad(PokerLayout.BOARD_TILT_DEG)
	var width := PokerLayout.board_width() + MARGIN * 2.0
	var card_len := Card3D.HEIGHT * PokerLayout.BOARD_SCALE
	var depth := card_len * cos(tilt)
	var rise := card_len * sin(tilt)
	var front := PokerLayout.board_front_z()
	var base_y := SeatLayout.TABLE_TOP + PokerLayout.RACK_HEIGHT
	# 斜面托板:从牌的下边沿牌面往后,往牌背一侧让开半个厚度
	var plate_mid := Vector3(0, base_y, front) + Basis(Vector3.RIGHT, tilt) * Vector3(0, -THICKNESS / 2.0, -card_len / 2.0)
	MeshKit.add(self, MeshKit.box(Vector3(width, THICKNESS, card_len + MARGIN)), WorldMaterials.wood("dark"),
		plate_mid, Vector3(rad_to_deg(tilt), 0, 0))
	# 托板下的楔形木块(直角在后),坐在底座上
	var wedge := MeshKit.prism(Vector3(depth, rise, width))
	wedge.left_to_right = 1.0
	MeshKit.add(self, wedge, WorldMaterials.wood("table"), Vector3(0, base_y + rise / 2.0 - THICKNESS, front - depth / 2.0),
		Vector3(0, 90, 0))
	MeshKit.add(self, MeshKit.box(Vector3(width, PokerLayout.RACK_HEIGHT, depth + MARGIN)), WorldMaterials.wood("dark"),
		Vector3(0, SeatLayout.TABLE_TOP + PokerLayout.RACK_HEIGHT / 2.0, front - depth / 2.0))
	var lip_height := PokerLayout.RACK_HEIGHT + LIP_HEIGHT
	MeshKit.add(self, MeshKit.box(Vector3(width, lip_height, LIP_DEPTH)), WorldMaterials.brass(),
		Vector3(0, SeatLayout.TABLE_TOP + lip_height / 2.0, front + LIP_OFFSET))
