class_name DdzLayout
# 斗地主牌桌布局(纯函数):桌心扣着的 3 张底牌与发牌处、每人面前的出牌行、「不出」牌子的位置、牌扇的显示顺序。
# 坐标是牌桌世界的(TableWorld 下,本机座位在 +Z;SeatLayout.direction 的角度约定)。3 人坐骗子酒馆的小桌:
# 本机的出牌行在桌心靠近自己这一侧,两位对手的在各自面前;桌上的牌一律按本机视角正立(牌顶朝 -Z),
# 一行里大的在左(同手牌条),重叠排开,太长就挤紧(最宽 MAX_ROW),离烛台(半径 0.7)和别人的行都有空隙。


const TABLE_FOCUS := Vector3(0, SeatLayout.TABLE_TOP + 0.05, 0)   # 酒客平时看向桌心
const CARD_STEP := 0.0011
const LAYER_STEP := 0.0009                 # 一行里后面的牌叠高一点(重叠处不闪烁)
const DECK_SPOT := Vector2(0.07, 0.02)     # 发牌处 / 底牌中心 (x, z):往右挪一点,越肩时自己的头挡住的是桌心偏左那块
const DECK_SCALE := 1.1
const BOTTOM_GAP := 0.16                   # 三张底牌之间的距离
const BOTTOM_SCALE := 1.15
const BOTTOM_TILT := [0.06, -0.03, 0.05]   # 底牌稍稍歪一点(弧度),不像摆得太整齐
const PLAY_SCALE := 1.25
const PLAY_STEP := 0.064                   # 出牌行相邻两张的距离(重叠排开)
const MAX_ROW := 0.46                      # 一行最宽这么宽(两端牌心之间)
# 越肩机位(TableWorld.third_person_view)里自己的头和帽子挡住桌面偏左、靠近自己的那一块(约 x < −0.13、z > −0.15):
# 对手的出牌行在各自面前再往桌子里侧(−Z)挪一点,本机的出牌行往右挪,都露在头的右上方
const MY_ROW_SPOT := Vector2(0.11, 0.29)   # 本机出牌行中心 (x, z)
const ROW_RADIUS := 0.3                    # 对手出牌行离桌心
const ROW_BACK := 0.05                     # 对手出牌行再往里侧挪这么多
# 穿模修复(2026-10-10):他人的牌扇改立在两爪前方的桌面上空(离桌心 ≈0.6 米,Patron.FAN_SEAT_POS),出牌行沿世界 X 排开,
# 侧边两位对手的行朝自己那头伸得太远会插进自己的牌扇。对手的行收近桌心(原 0.36 / 0.1)、最宽 OPP_MAX_ROW(原同 MAX_ROW 0.46),
# 两行之间、与底牌之间仍有空隙(test_ddz_world、tools/clip_report.gd 量过)
const OPP_MAX_ROW := 0.36
const ROW_TILT_DEG := 24.0                 # 出牌行与翻开的底牌牌顶微微翘起、朝向本机(平躺在远处的牌看不清点数)
const PASS_LIFT := 0.11                    # 「不出」牌子悬在出牌行上方
const ALARM_SIDE := 0.32                   # 报警徽章挂在头顶偏右
const SWEEP_SCALE := 0.4                   # 清桌:牌收向桌心时缩小到这么大
# 越肩机位(TableWorld.third_person_override):比骗子酒馆的更靠右、更高一点,自己的头和帽子落在画面左下,
# 不挡左边那位对手面前的出牌行
const THIRD_PERSON := Vector3(0.95, 2.45, 1.05)
const FAN_SCALE_ME := 0.55                 # 越肩时自己的牌扇缩小、往右下挪(20 张的扇子别挡住桌面;2D 手牌条才是主入口)
const FAN_SHIFT_ME := Vector3(0.13, 0.03, 0.0)
const FP_FAN_CAM := Vector3(0.36, -0.035, -0.62)   # 第一人称:牌扇拿在镜头右侧偏下(在底部 HUD 之上)
const FP_FAN_SCALE := 0.5


# —— 发牌处与底牌 ——

static func deck_transform(count := 54) -> Transform3D:
	# 牌背朝上的一摞的顶上那张(发牌时牌从这里飞出去)
	var y := SeatLayout.FELT_TOP + minf(count, 54) * CARD_STEP * 0.5 + 0.0004
	return Transform3D(Basis(Vector3.BACK, PI).scaled(Vector3.ONE * DECK_SCALE), Vector3(DECK_SPOT.x, y, DECK_SPOT.y))


static func bottom_slot(i: int, face_up := false) -> Transform3D:
	# 第 i 张底牌(0–2):扣着(牌背朝上)或翻开(正面朝上,牌顶朝 -Z)
	var x := DECK_SPOT.x + (i - 1) * BOTTOM_GAP
	var tilt: float = BOTTOM_TILT[clampi(i, 0, BOTTOM_TILT.size() - 1)]
	var basis := Basis(Vector3.UP, tilt)
	var y := SeatLayout.FELT_TOP + Card3D.THICKNESS * BOTTOM_SCALE / 2.0 + 0.0004 + i * LAYER_STEP
	if not face_up:
		basis = basis * Basis(Vector3.BACK, PI)
	else:
		basis = basis * Basis(Vector3.RIGHT, deg_to_rad(ROW_TILT_DEG))
		y += lift_for_tilt(BOTTOM_SCALE)
	return Transform3D(basis.scaled(Vector3.ONE * BOTTOM_SCALE), Vector3(x, y, DECK_SPOT.y))


# —— 出牌行 ——

static func row_center(angle: float, mine: bool) -> Vector3:
	if mine:
		return Vector3(MY_ROW_SPOT.x, SeatLayout.FELT_TOP, MY_ROW_SPOT.y)
	var d := SeatLayout.direction(angle) * ROW_RADIUS
	return Vector3(d.x, SeatLayout.FELT_TOP, d.z - ROW_BACK)


static func row_step(count: int, mine := true) -> float:
	if count <= 1:
		return PLAY_STEP
	return minf(PLAY_STEP, max_row(mine) / float(count - 1))


static func max_row(mine: bool) -> float:
	# 一行最宽(两端牌心之间):本机 MAX_ROW,对手 OPP_MAX_ROW
	return MAX_ROW if mine else OPP_MAX_ROW


static func play_slot(angle: float, mine: bool, i: int, count: int) -> Transform3D:
	# 出牌行里第 i 张(从左往右)
	var c := row_center(angle, mine)
	var step := row_step(count, mine)
	var x := c.x + (i - (count - 1) / 2.0) * step
	var y := SeatLayout.FELT_TOP + Card3D.THICKNESS * PLAY_SCALE / 2.0 + 0.0005 + i * LAYER_STEP + lift_for_tilt(PLAY_SCALE)
	return Transform3D(Basis(Vector3.RIGHT, deg_to_rad(ROW_TILT_DEG)).scaled(Vector3.ONE * PLAY_SCALE), Vector3(x, y, c.z))


static func lift_for_tilt(scale: float) -> float:
	# 牌绕自己的横轴翘起 ROW_TILT_DEG:牌心抬高半张牌高 × sin,牌底边正好贴着桌面
	return Card3D.HEIGHT * scale * 0.5 * sin(deg_to_rad(ROW_TILT_DEG))


static func pass_point(angle: float, mine: bool) -> Vector3:
	return row_center(angle, mine) + Vector3(0, PASS_LIFT, 0)


static func sweep_point() -> Vector3:
	return Vector3(DECK_SPOT.x, SeatLayout.FELT_TOP + 0.03, DECK_SPOT.y - 0.08)


static func row_order(cards: Array) -> Array:
	# 摆在桌上的顺序:同点数张数多的在前(三带一的三张、飞机的机身先摆),同张数点数大的在前
	var counts := {}
	for c in cards:
		if DdzHand.is_card(c):
			var r := DdzHand.rank(c)
			counts[r] = counts.get(r, 0) + 1
	var out := cards.filter(DdzHand.is_card)
	out.sort_custom(func(a: int, b: int) -> bool:
		var ca: int = counts[DdzHand.rank(a)]
		var cb: int = counts[DdzHand.rank(b)]
		if ca != cb:
			return ca > cb
		return a > b)
	return out


# —— 牌扇 ——

static func fan_index(i: int, count: int) -> int:
	# 手牌按牌 id 升序存放(私有视图的下标);牌扇与手牌条里大的在左:第 i 张摆在第 count-1-i 个位置
	return count - 1 - i


static func fan_slot(i: int, count: int, lift := 0.0) -> Transform3D:
	return BombCatLayout.fan_slot(fan_index(i, count), count, lift)
