class_name PokerLayout
# 德州牌桌的摆放数学(纯函数):桌心牌架上的公共牌、底池、各座位的筹码堆 / 下注 / 庄家按钮 / 亮牌、
# 发牌处与弃牌堆、本机牌扇。角度约定同 SeatLayout(0 = 本机座位,+Z);座位上的东西按桌沿往里的距离摆,
# 桌子放大或复原都贴着各自的座位。桌上的牌一律按本机视角正立(牌顶朝 −Z),每个客户端都把自己放在 +Z。
# 越肩机位下(按截图调过):公共牌在画面正中,底池紧贴牌架靠本机一侧,自己的牌扇在底池与下注控件之间。


# —— 公共牌架(规格 §5.3)——
const BOARD_SCALE := 1.8
const BOARD_TILT_DEG := 35.0       # 牌面从平放朝本机镜头立起的角度
const BOARD_GAP := 0.02            # 相邻公共牌的间隙
const RACK_HEIGHT := 0.012         # 牌架托条高出桌面
const CARD_LIFT := 0.004           # 牌浮在台面 / 牌架上方一点,免得与表面 Z 冲突
# —— 亮牌:摊在座位前,比手里的牌大 ——
const SHOWN_SCALE := 1.4
const SHOWN_GAP := 0.012
const SHOWN_INSET := 0.55          # 两张亮牌的中心离桌沿的距离
# —— 各座位的筹码(规格 §5.4):筹码堆在桌沿内侧偏右手,下注更靠桌心,按钮在左手 ——
const STACK_INSET := 0.24
const STACK_SIDE := 0.30
const BET_INSET := 0.53
const BET_SIDE := 0.10
const BUTTON_INSET := 0.33
const BUTTON_SIDE := -0.30
# —— 底池:公共牌靠本机一侧,主池与边池从左到右并排;多于 POTS_PER_ROW 个时往本机方向另起一排 ——
const POT_Z := 0.30
const POT_SPACING := 0.25
const POTS_PER_ROW := 4
# —— 发牌处与弃牌堆:牌架后面(越肩看过去被公共牌挡住一半,不抢眼)——
const DECK_SPOT := Vector2(-0.15, -0.5)
const MUCK_SPOT := Vector2(0.15, -0.5)
const MUCK_SCATTER := 0.06         # 弃牌在弃牌堆里的散开半径
const MUCK_STEP := 0.0012          # 每张弃牌叠高
# —— 自己的牌扇(规格 §5.3):座位坐标,相对髋部;落在公共牌与下注控件之间。
# 动森式大头(2026-10-08)会整个挡住原来的 (0.30, 0.74, -0.30),往右前方挪到大头旁边 ——
const FAN_OFFSET := Vector3(0.48, 0.72, -0.36)
# —— 第一人称(V 切换)时自己的底牌:按镜头坐标拿在画面右下(右、下、前),比骗子酒馆的牌扇更靠右:让开下注面板、右下角的记录与公共牌 ——
const FP_FAN_CAM := Vector3(0.4, -0.1, -0.6)
const FP_FAN_SCALE := 0.95


static func board_slot(index: int) -> Transform3D:
	# 第 index 张公共牌:下边搁在牌架托条上,牌面向本机倾斜 BOARD_TILT_DEG,放大 BOARD_SCALE;
	# 整排牌的俯视占地前后居中在桌心,最外侧的牌角也在桌心 0.6 米以内
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(BOARD_TILT_DEG))
	var pitch := Card3D.WIDTH * BOARD_SCALE + BOARD_GAP
	var x := (index - (PokerRules.BOARD_CARDS - 1) / 2.0) * pitch
	var bottom := Vector3(x, SeatLayout.TABLE_TOP + RACK_HEIGHT, board_front_z())
	var center := bottom + tilt * Vector3(0, CARD_LIFT, -Card3D.HEIGHT * BOARD_SCALE / 2.0)
	return Transform3D(tilt.scaled(Vector3.ONE * BOARD_SCALE), center)


static func board_front_z() -> float:
	# 牌架前沿(牌的下边,靠本机一侧):斜立的牌在桌面上的投影深度的一半
	return Card3D.HEIGHT * BOARD_SCALE * cos(deg_to_rad(BOARD_TILT_DEG)) / 2.0


static func board_width() -> float:
	return PokerRules.BOARD_CARDS * Card3D.WIDTH * BOARD_SCALE + (PokerRules.BOARD_CARDS - 1) * BOARD_GAP


static func pot_position(index: int, count: int) -> Vector3:
	var row := index / POTS_PER_ROW
	var in_row := mini(count - row * POTS_PER_ROW, POTS_PER_ROW)
	var col := index % POTS_PER_ROW
	return Vector3((col - (in_row - 1) / 2.0) * POT_SPACING, SeatLayout.TABLE_TOP, POT_Z + row * POT_SPACING)


static func facing(angle: float) -> Basis:
	# 座位朝向:本地 −Z 朝桌心,+X 是座位的右手(与 TableWorld.seat_transform 一致)
	return Basis.looking_at(-SeatLayout.direction(angle), Vector3.UP)


static func stack_position(angle: float, table_radius: float) -> Vector3:
	return _on_table(angle, table_radius - STACK_INSET, STACK_SIDE)


static func bet_position(angle: float, table_radius: float) -> Vector3:
	return _on_table(angle, table_radius - BET_INSET, BET_SIDE)


static func button_position(angle: float, table_radius: float) -> Vector3:
	return _on_table(angle, table_radius - BUTTON_INSET, BUTTON_SIDE)


static func shown_card(angle: float, table_radius: float, i: int) -> Transform3D:
	# 摊牌时第 i 张亮牌:座位前方桌面上,牌面朝上、按本机视角正立,两张从左到右并排
	var center := SeatLayout.direction(angle) * (table_radius - SHOWN_INSET)
	var pitch := Card3D.WIDTH * SHOWN_SCALE + SHOWN_GAP
	var x := (i - (PokerRules.HOLE_CARDS - 1) / 2.0) * pitch
	return Transform3D(Basis.from_scale(Vector3.ONE * SHOWN_SCALE),
		center + Vector3(x, SeatLayout.TABLE_TOP + CARD_LIFT, 0))


static func deck_position() -> Vector3:
	return Vector3(DECK_SPOT.x, SeatLayout.TABLE_TOP + CARD_LIFT, DECK_SPOT.y)


static func muck_position() -> Vector3:
	return Vector3(MUCK_SPOT.x, SeatLayout.TABLE_TOP, MUCK_SPOT.y)


static func muck_radius() -> float:
	# 弃牌堆在桌面上的占地:散开半径 + 一张牌的半对角线(牌可能转到任意角度)
	return MUCK_SCATTER + Vector2(Card3D.WIDTH, Card3D.HEIGHT).length() / 2.0


static func muck_slot(index: int) -> Transform3D:
	# 第 index 张弃牌:牌面朝下、随机转角,一张叠一张;按序号确定,所有客户端落点一致
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([index, "muck"])
	var spread := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * MUCK_SCATTER
	var pos := muck_position() + Vector3(spread.x, CARD_LIFT + index * MUCK_STEP, spread.y)
	return Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.BACK, PI), pos)


static func poker_fan_offset() -> Vector3:
	return FAN_OFFSET


static func fan_transform(seat: Transform3D, viewer: Vector3) -> Transform3D:
	# 自己的牌扇在身体局部坐标里的变换:同 Patron.present_hand_to 的算法(牌面法线指向越肩镜头、
	# 牌顶朝上、放大 SELF_FAN_SCALE,并抵消坐姿前倾),只是位置换成德州的。seat 是座位的静止变换
	# (TableWorld.seat_transform),不受登场缩放影响;由德州牌桌设置 fan.transform,不改 Patron
	var seat_basis := seat.basis.orthonormalized()
	var fan_seat := Patron.HIP + FAN_OFFSET
	var fan_world := seat.origin + seat_basis * fan_seat
	var normal := (viewer - fan_world).normalized()
	var bottom := -(Vector3.UP - normal * Vector3.UP.dot(normal)).normalized()
	var world_basis := Basis(normal.cross(bottom), normal, bottom)
	return Patron.in_seat(Transform3D((seat_basis.inverse() * world_basis).scaled(Vector3.ONE * Patron.SELF_FAN_SCALE), fan_seat))


static func first_person_fan_transform(seat: Transform3D, view: Transform3D) -> Transform3D:
	# 第一人称时自己的牌扇(座位坐标,Patron 每帧按眼睛平移后换到身体局部):同 Patron.first_person_fan,
	# view 是脖子没探出时的第一人称机位
	return Patron.first_person_fan(seat, view, FP_FAN_CAM, FP_FAN_SCALE)


static func _on_table(angle: float, radial: float, side: float) -> Vector3:
	var flat := SeatLayout.direction(angle) * radial + facing(angle).x * side
	return Vector3(flat.x, SeatLayout.TABLE_TOP, flat.z)
