class_name SeatLayout
# 牌桌布局数学(纯函数):座位环形分布、手牌扇形、出牌区散落、翻牌排列。
# 角度约定:0 = 本机座位(+Z,靠近相机),角度增大按俯视顺时针转到本机左手边(-X)。


const TABLE_RADIUS := 0.95
const TABLE_TOP := 0.78
const FELT_TOP := TABLE_TOP + 0.004   # 桌布顶面(桌布 4 mm 厚,铺在桌面上):平放在桌上的牌和枪都要高于它
const FELT_RADIUS := 0.82
const SEAT_RADIUS := 1.25
const PILE_INNER := 0.13
const PILE_OUTER := 0.31
# 德州最多 8 人,桌子放大;座位到桌沿的距离不变,酒客按座位局部坐标摆的爪子与伸手位置照常可用
const POKER_TABLE_RADIUS := 1.45
const SEAT_GAP := SEAT_RADIUS - TABLE_RADIUS
# 炸弹猫最多 6 人:到这个人数换德州那张大桌(4 人以内用骗子酒馆的桌子)
const BOMB_CAT_BIG_TABLE_FROM := 5
# 吹牛骰子同样最多 6 人、同样的换桌规则
const LIARS_DICE_BIG_TABLE_FROM := 5


static func table_radius_for(mode: String, players := 0) -> float:
	# players:本局人数(炸弹猫与吹牛骰子按它选桌;不知道时传 0,用小桌,如等待厅与主菜单)
	if GameMode.is_poker(mode):
		return POKER_TABLE_RADIUS
	if GameMode.is_bomb_cat(mode) and players >= BOMB_CAT_BIG_TABLE_FROM:
		return POKER_TABLE_RADIUS
	if GameMode.is_liars_dice(mode) and players >= LIARS_DICE_BIG_TABLE_FROM:
		return POKER_TABLE_RADIUS
	return TABLE_RADIUS


static func seat_radius_for(table_radius: float) -> float:
	return table_radius + SEAT_GAP


static func seat_angle(seat_index: int, my_index: int, count: int) -> float:
	return wrapf(float(seat_index - my_index) * TAU / count, 0.0, TAU)


static func direction(angle: float) -> Vector3:
	return Vector3(-sin(angle), 0.0, cos(angle))


static func seat_position(angle: float, radius := SEAT_RADIUS) -> Vector3:
	return direction(angle) * radius


static func fan_slots(count: int, spread_deg := 7.0, spacing := 0.068, drop := 0.008) -> Array:
	# 返回 [{"x", "y", "rot"}]:x 横向偏移,y 纵向下沉(外侧更低),rot 为绕视线轴旋转(弧度,左正)
	var slots := []
	var mid := (count - 1) / 2.0
	for i in count:
		var k := float(i) - mid
		slots.append({
			"x": k * spacing,
			"y": -absf(k) * absf(k) * drop,
			"rot": -k * deg_to_rad(spread_deg),
		})
	return slots


static func pile_offset(index: int, seed: int) -> Dictionary:
	# 出牌区散落位置:确定性伪随机,保证所有客户端同一张牌落点一致
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([index, seed])
	var angle := rng.randf() * TAU
	var radius := rng.randf_range(PILE_INNER, PILE_OUTER)
	return {
		"pos": Vector2(cos(angle), sin(angle)) * radius,
		"rot": rng.randf_range(-PI, PI),
	}


static func reveal_slots(count: int, spacing := 0.14) -> Array:
	var xs := []
	var mid := (count - 1) / 2.0
	for i in count:
		xs.append((float(i) - mid) * spacing)
	return xs
