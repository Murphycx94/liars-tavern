class_name LiarsDiceLayout
# 吹牛骰子牌桌布局(纯函数):每个座位面前的骰盅、盅底下的五颗骰子、开盅后骰子排开的一行、摇盅时捧在胸前的位置、
# 桌心的出价标记,以及偷看 / 特写机位。坐标是牌桌世界的(TableWorld 下,本机座位在 +Z),角度约定同 SeatLayout。
# 骰盅摆在主人右手边的桌面上(越肩镜头从右肩后面看过去正好看得到);旁边有烛台(CandlesProp.SPECS)时换到左手边。


const TABLE_FOCUS := Vector3(0, SeatLayout.TABLE_TOP + 0.05, 0)   # 酒客平时看向桌心
const DIE_SIZE := 0.05             # 骰子边长(米;牌桌上隔两三米看,做得比真骰子胖)
const CUP_RADIUS := 0.102          # 盅口外半径
const CUP_HEIGHT := 0.18
const CUP_INSET := 0.27            # 骰盅中心离桌沿这么远(往桌心)
const CUP_SIDE := 0.17             # 往主人右手(或左手)挪这么多
const CUP_SIDE_BIG := 0.27         # 大桌(5–6 人)座位更宽:越肩镜头从更高更远处看,盅再往右挪,不被自己的大头挡住
const CANDLE_CLEAR := 0.24         # 骰盅离烛台中心至少这么远,否则换一边
const UNDER_SPREAD := 0.0272       # 盅底下:四颗摆成 2×2(离中心横纵各这么远),第五颗叠在它们中间上面
const ROW_FORWARD := 0.16          # 开盅后骰子排成一行:离盅心往桌心这么远
const ROW_GAP := 0.064             # 一行里相邻两颗的间距
const OPEN_BACK := 0.13            # 开盅时骰盅翻过来(口朝上)放回主人那边这么远
const OPEN_LIFT := 0.012           # 口朝上时顶上的小皮扣垫着,整只再抬这么高
const SHAKE_POINT := Vector3(0.0, 0.91, -0.5)     # 摇盅时盅心的位置(座位坐标):下巴前下方、桌面上空(再高会戳进动森式大头里)
const SHAKE_POINT_FP := Vector3(0.06, 0.86, -0.62)   # 第一人称时自己摇盅的位置:更低更远,盅在画面下方摇,不挡住别人
const PAW_GAP := 0.12              # 两只爪子扶在盅身两侧,离盅心这么远
const PAW_BACK := 0.04             # 爪子比盅心稍靠自己(手臂够得着)
const PEEK_TILT := deg_to_rad(58.0)   # 偷看:靠主人那一边的盅沿掀起来这么多度
const MARKER_HEIGHT := 0.36        # 桌心出价标记(大骰子图标 + 个数)离桌面这么高
const MARKER_SCALE := 3.2          # 出价标记的大骰子是普通骰子的这么多倍
const FELT := SeatLayout.FELT_TOP


static func direction(angle: float) -> Vector3:
	return SeatLayout.direction(angle)


static func right_of(angle: float) -> Vector3:
	# 座位主人的右手方向(同 TableWorld.seat_right:Basis.looking_at(-dir).x)
	return Vector3.UP.cross(direction(angle)).normalized()


static func candle_points() -> Array:
	var out := []
	for spec in CandlesProp.SPECS:
		out.append(SeatLayout.direction(spec[0]) * CandlesProp.RADIUS)
	return out


static func side_sign(angle: float, table_radius: float) -> float:
	# +1 右手边,−1 左手边:右手边离最近的烛台不够远而左手边更远时换到左手边
	var right := _flat_spot(angle, table_radius, 1.0)
	var left := _flat_spot(angle, table_radius, -1.0)
	var near_right := _candle_distance(right)
	if near_right >= CANDLE_CLEAR:
		return 1.0
	return -1.0 if _candle_distance(left) > near_right else 1.0


static func _flat_spot(angle: float, table_radius: float, side: float) -> Vector3:
	var lateral := CUP_SIDE_BIG if table_radius > SeatLayout.TABLE_RADIUS else CUP_SIDE
	return direction(angle) * (table_radius - CUP_INSET) + right_of(angle) * lateral * side


static func _candle_distance(p: Vector3) -> float:
	var best := INF
	for c: Vector3 in candle_points():
		best = minf(best, Vector2(p.x - c.x, p.z - c.z).length())
	return best


static func cup_spot(angle: float, table_radius: float) -> Vector3:
	# 骰盅扣在桌上的位置(盅口中心,毡面高度)
	var p := _flat_spot(angle, table_radius, side_sign(angle, table_radius))
	return Vector3(p.x, FELT, p.z)


static func facing(angle: float) -> Basis:
	# 骰盅的朝向:徽章(+Z)朝桌心,别人看得到
	return Basis.looking_at(direction(angle), Vector3.UP)


static func cup_rest(angle: float, table_radius: float) -> Transform3D:
	# 扣着(口朝下)
	return Transform3D(facing(angle), cup_spot(angle, table_radius))


static func cup_open(angle: float, table_radius: float) -> Transform3D:
	# 开盅后翻过来口朝上,放回主人那边(给骰子让出一行)。口朝上 = 绕主人的左右轴翻半圈,原点(盅口)抬到盅高
	var spot := cup_spot(angle, table_radius) + direction(angle) * OPEN_BACK
	var flipped := facing(angle) * Basis(Vector3.RIGHT, PI)
	return Transform3D(flipped, spot + Vector3(0, CUP_HEIGHT + OPEN_LIFT, 0))


static func cup_tipped(angle: float, table_radius: float) -> Transform3D:
	# 出局:骰盅歪倒在桌上(侧躺,口朝主人的左手边)
	var spot := cup_spot(angle, table_radius)
	var lay := Basis(Vector3.UP, 0.5) * facing(angle) * Basis(Vector3.BACK, PI * 0.5)
	var axis := lay * Vector3.UP
	return Transform3D(lay, spot - axis * CUP_HEIGHT * 0.5 + Vector3(0, CUP_RADIUS * 1.08, 0))


static func cup_peek(angle: float, table_radius: float, tilt := PEEK_TILT) -> Transform3D:
	# 偷看:靠主人那一边的盅沿掀起来,铰在靠桌心那一边的盅沿上
	var rest := cup_rest(angle, table_radius)
	var hinge := rest.origin - direction(angle) * CUP_RADIUS
	var axis := right_of(angle)
	var rot := Basis(axis, -tilt)
	return Transform3D(rot * rest.basis, hinge + rot * (rest.origin - hinge))


static func under_slot(i: int) -> Vector3:
	# 盅底下第 i 颗(0..4)的位置(盅的局部坐标,y 是骰子底面离桌面的高度):前四颗 2×2 平铺,
	# 第五颗叠在四颗中间的上面(五颗平铺塞不进圆胖的盅口)
	var slots := [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]
	if i >= 4:
		return Vector3(0, DIE_SIZE, 0)
	return slots[maxi(i, 0)] * UNDER_SPREAD


static func under_position(angle: float, table_radius: float, i: int) -> Vector3:
	var rest := cup_rest(angle, table_radius)
	var s := under_slot(i)
	return rest.origin + rest.basis * Vector3(s.x, 0, s.z) + Vector3(0, s.y + DIE_SIZE * 0.5 + 0.0005, 0)


static func under_yaw(angle: float, i: int) -> float:
	# 盅底下的骰子只微微歪一点(2×2 挨得很近,歪多了会互相穿);叠在上面的那颗转 45°
	return -angle + (PI * 0.25 if i >= 4 else (0.05 if i % 2 == 0 else -0.05))


static func row_position(angle: float, table_radius: float, i: int, count: int) -> Vector3:
	# 开盅后一行排开(离盅心往桌心 ROW_FORWARD,沿主人的左右排;从主人看是从左到右)
	var spot := cup_spot(angle, table_radius)
	var mid := (count - 1) / 2.0
	var p := spot - direction(angle) * ROW_FORWARD + right_of(angle) * (float(i) - mid) * ROW_GAP
	return Vector3(p.x, FELT + DIE_SIZE * 0.5 + 0.0005, p.z)


static func die_yaw(angle: float, i: int, salt := 0) -> float:
	# 骰子绕竖轴的小偏转(确定性:各端一样、同一颗不会每帧乱跳)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["die", snappedf(angle, 0.001), i, salt])
	return -angle + rng.randf_range(-0.28, 0.28)


static func shake_global(seat: Transform3D) -> Vector3:
	return seat * SHAKE_POINT


static func paw_points(seat: Transform3D, cup_center: Vector3) -> Array:
	# 两只爪子扶盅的位置(座位坐标):盅身两侧(盅心在座位坐标里左右各 PAW_GAP)
	var local := seat.affine_inverse() * cup_center
	return [local + Vector3(-PAW_GAP, 0.0, PAW_BACK), local + Vector3(PAW_GAP, 0.0, PAW_BACK)]


static func marker_position() -> Vector3:
	return Vector3(0, SeatLayout.TABLE_TOP + MARKER_HEIGHT, 0)


static func peek_view(world: TableWorld, pid: int) -> Transform3D:
	# 第一人称偷看:视线压低、凑到掀开的盅沿上往里看
	var angle := world.seat_angle_now(pid)
	var spot := cup_spot(angle, world.table_radius)
	# 从主人这边、偏身体中线(右爪搭在盅旁边会挡住)低低地看进掀开的盅沿
	var pos := spot + direction(angle) * 0.23 - right_of(angle) * 0.08 + Vector3(0, 0.28, 0)
	var target := spot + Vector3(0, 0.025, 0)
	return Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)


static func close_view(world: TableWorld, pid: int) -> Transform3D:
	# 骰盅与骰子的特写(展台用):从桌心那边斜上方看这位的骰盅和排开的一行骰子
	var angle := world.seat_angle_now(pid)
	var spot := cup_spot(angle, world.table_radius)
	var target := spot - direction(angle) * ROW_FORWARD * 0.6 + Vector3(0, 0.03, 0)
	var pos := target - direction(angle) * 0.42 + right_of(angle) * 0.12 + Vector3(0, 0.28, 0)
	return Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)
