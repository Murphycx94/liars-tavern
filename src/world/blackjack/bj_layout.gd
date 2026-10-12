class_name BjLayout
# 21 点牌桌的摆放数学(纯函数,设计稿 §4)。角度约定同 SeatLayout(0 = 本机座位,+Z)。
# 桌心是庄家的牌:搁在德州的公共牌架上(PokerLayout 的倾角与放大),张数多了往中间挤;牌架后面左边牌鞋、右边弃牌盘、
# 中间一摞庄家的筹码(赔付从这里飞出、输掉的注飞回这里)。
# 每个座位前:牌平放、牌面朝上、按本机视角正立(同德州亮牌),每张往右上错开一点露出角标;分牌后几手沿桌沿并排;
# 每手前面(靠桌沿)一摞下注;筹码堆在右手边。座位上的东西按桌沿往里的距离摆,换桌也贴着各自的座位。


const TABLE_FOCUS := Vector3(0, SeatLayout.TABLE_TOP + 0.1, -0.1)   # 酒客平时看向桌心庄家的牌

# —— 庄家的牌(搁在公共牌架上)——
const DEALER_MAX_PITCH := Card3D.WIDTH * PokerLayout.BOARD_SCALE + PokerLayout.BOARD_GAP
const DEALER_MIN_PITCH := Card3D.WIDTH * PokerLayout.BOARD_SCALE * 0.42   # 张数多时挤成扇面,露出左上角标
# —— 牌鞋、弃牌盘、庄家筹码:牌架后面一排(越肩看过去被庄家的牌挡住一半,不抢眼)——
const SHOE_SPOT := Vector2(-0.36, -0.46)
const DISCARD_SPOT := Vector2(0.36, -0.46)
const BANK_SPOT := Vector2(0.0, -0.5)
# —— 座位前的牌 ——
const HAND_SCALE := 1.15
const HAND_INSET := 0.58           # 每手牌(第一张)的中心离桌沿
const HAND_SPACING := 0.24         # 分牌后相邻两手的间距(沿桌沿)
const HAND_SPREAD_MAX := 0.66      # 几手牌摊开的总宽度上限:4 手时挤一点,别压到邻座
const CASCADE := Vector2(0.029, -0.043)   # 每多一张往右上(本机视角)错开:6 张的手也压不到庄家牌架
const CARD_LIFT := 0.004
const CARD_STEP := 0.0008          # 后发的牌叠在上面
# —— 筹码 ——
const BET_INSET := 0.33            # 每手的下注离桌沿(在牌和桌沿之间)
const STACK_INSET := 0.2
const STACK_SIDE := 0.44           # 筹码堆在右手边,让开分牌后最右那一手的下注
# —— 本机自己:越肩镜头在座位右后方,自己的大头(和帽子)正好挡住面前那块桌面,所以本机看自己的牌、下注都往右手边挪,
# 筹码堆再往右、往里一点(仍在桌面上)。只影响本机画面,别人看到的还是摆在你座位正前方 ——
const MY_SIDE := 0.42
const MY_MAX_SIDE := 0.62          # 分成几手时最右那一手(和它的下注)不超过这里,免得掉出桌沿
const MY_STACK_INSET := 0.45
const MY_STACK_SIDE := 0.78


static func dealer_pitch(count: int) -> float:
	# 张数不超过 5 用公共牌的间距;更多时挤到整排宽度不超过公共牌架
	if count <= PokerRules.BOARD_CARDS:
		return DEALER_MAX_PITCH
	var room := PokerLayout.board_width() - Card3D.WIDTH * PokerLayout.BOARD_SCALE
	return maxf(room / (count - 1), DEALER_MIN_PITCH)


static func dealer_slot(index: int, count: int) -> Transform3D:
	# 第 index 张庄家的牌(共 count 张):同公共牌槽位的倾角与高度,横向居中排开;后发的牌稍微往前叠
	var slot := PokerLayout.board_slot(0)
	var x := (index - (count - 1) / 2.0) * dealer_pitch(count)
	slot.origin.x = x
	slot.origin += slot.basis.orthonormalized().y * (CARD_STEP * index)
	return slot


static func dealer_hidden_slot(count: int) -> Transform3D:
	# 暗牌:同一个槽位,背面朝本机(绕牌的纵轴翻过去)
	var slot := dealer_slot(1, count)
	slot.basis = slot.basis * Basis(Vector3.BACK, PI)
	return slot


static func shoe_position() -> Vector3:
	return Vector3(SHOE_SPOT.x, SeatLayout.TABLE_TOP, SHOE_SPOT.y)


static func shoe_mouth() -> Transform3D:
	# 牌从牌鞋口滑出时的变换:背面朝上、缩小
	return Transform3D(Basis(Vector3.BACK, PI).scaled(Vector3.ONE * 0.6),
		shoe_position() + Vector3(0.07, BjShoeProp.MOUTH_HEIGHT, 0.04))


static func discard_position() -> Vector3:
	return Vector3(DISCARD_SPOT.x, SeatLayout.TABLE_TOP, DISCARD_SPOT.y)


static func discard_slot(index: int) -> Transform3D:
	# 收走的牌:背面朝上、一张叠一张,随序号转一点(所有客户端一致)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([index, "bj_discard"])
	var pos := discard_position() + Vector3(0, BjShoeProp.TRAY_FLOOR + CARD_LIFT + (index % 40) * CARD_STEP, 0)
	return Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)) * Basis(Vector3.BACK, PI), pos)


static func bank_position() -> Vector3:
	return Vector3(BANK_SPOT.x, SeatLayout.TABLE_TOP, BANK_SPOT.y)


static func hand_offset(hand: int, count: int) -> float:
	# 第 hand 手(共 count 手)沿桌沿的横向偏移(座位的右手为正)
	if count <= 1:
		return 0.0
	var spacing := minf(HAND_SPACING, HAND_SPREAD_MAX / (count - 1))
	return (hand - (count - 1) / 2.0) * spacing


static func my_shift(count: int) -> float:
	# 本机自己的几手往右挪多少:一般 MY_SIDE,手多了收一点,最右一手不过 MY_MAX_SIDE
	return minf(MY_SIDE, MY_MAX_SIDE - hand_offset(count - 1, count))


static func hand_center(angle: float, table_radius: float, hand: int, count: int, mine := false) -> Vector3:
	return _on_table(angle, table_radius - HAND_INSET, hand_offset(hand, count) + (my_shift(count) if mine else 0.0))


static func card_slot(angle: float, table_radius: float, hand: int, count: int, index: int, sideways := false,
		mine := false) -> Transform3D:
	# 第 hand 手的第 index 张牌:牌面朝上、按本机视角正立,往右上错开;加倍的那张横放。mine:本机自己的牌(往右手边挪)
	var base := hand_center(angle, table_radius, hand, count, mine)
	var pos := base + Vector3(CASCADE.x * index, CARD_LIFT + CARD_STEP * index, CASCADE.y * index) * HAND_SCALE
	var basis := Basis.from_scale(Vector3.ONE * HAND_SCALE)
	if sideways:
		basis = Basis(Vector3.UP, PI / 2.0) * basis
	return Transform3D(basis, pos)


static func bet_position(angle: float, table_radius: float, hand: int, count: int, mine := false) -> Vector3:
	return _on_table(angle, table_radius - BET_INSET, hand_offset(hand, count) + (my_shift(count) if mine else 0.0))


static func stack_position(angle: float, table_radius: float, mine := false) -> Vector3:
	if mine:
		return _on_table(angle, table_radius - MY_STACK_INSET, MY_STACK_SIDE)
	return _on_table(angle, table_radius - STACK_INSET, STACK_SIDE)


static func _on_table(angle: float, radial: float, side: float) -> Vector3:
	var flat := SeatLayout.direction(angle) * radial + PokerLayout.facing(angle).x * side
	return Vector3(flat.x, SeatLayout.TABLE_TOP, flat.z)
