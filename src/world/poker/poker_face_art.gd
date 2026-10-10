class_name PokerFaceArt
# 德州牌面的矢量图形与排版(纯几何,单测覆盖)。坐标是牌面像素(SIZE),y 向下;烘焙时整体放大到 PokerFaces.SIZE。
# 动森式重画(2026-10-10):
# - 角标:圆头粗笔画的点数(约占牌高 30%)+ 正下方一枚花色,左上一个、右下一个(绕牌心转 180°);
# - 2–10:中间一条竖带里按经典排法摆点数个胖花色(下半的倒过来),两列 + 中列;
# - A:中央一枚大花色(♠A 另画成带圆盘和笑脸的大徽章,见 PokerFacePainter);
# - J/Q/K:中间一块竖长的圆角画框(PANEL),里面是角色插画(狐狸侍从、猫皇后、熊国王,画家画)。
# 点数是粗笔画、花色是多边形与圆拼成的,都不依赖字体:界面字体里没有花色字形,
# 系统字体各平台也不一样,自己画才能保证每台机器上缩到 30×42 像素都认得出。


const SIZE := Vector2i(256, 372)

# 四色牌,两个色系:红色系 ♥ 暖莓红、♦ 珊瑚橘;深色系 ♠ 软藏青墨、♣ 深青墨。
# 跨色系一眼分清(色差 ≥ 0.4),同色系里靠色相再分开(≥ 0.2)与花色形状。下标即 PokerCard 的花色
const SUIT_COLORS := [
	Color(0.2, 0.22, 0.42),    # ♠ 软藏青墨
	Color(0.86, 0.26, 0.4),    # ♥ 暖莓红
	Color(0.96, 0.5, 0.3),     # ♦ 珊瑚橘
	Color(0.12, 0.46, 0.44),   # ♣ 深青墨
]
const RED_SUITS := [PokerCard.HEARTS, PokerCard.DIAMONDS]

# —— 角标 ——
const RANK_HEIGHT := 112.0                # 约占牌高 30%:缩到 30×42 像素时仍有约 13 像素高
const RANK_WIDTH := 60.0
const TEN_WIDTH := 66.0                   # 「10」两个字并排,比单字宽
const STROKE := 18.0                      # 笔画粗细:缩到 30×42 时仍有约两个像素
const TEN_STROKE := 13.0                  # 「10」挤在一格里:笔画稍细,两字之间与「0」的空心才留得出来
const TEN_ONE_X := 0.13                   # 「1」的竖笔位置(单位框):左边留给短旗
const TEN_ZERO_HALF_WIDTH := 0.2          # 「0」的半宽(单位框):窄一点,和「1」之间才留得出缝
const INDEX_ORIGIN := Vector2(13, 14)     # 左上角标点数框的左上角
const INDEX_SUIT_HEIGHT := 36.0
const INDEX_SUIT_GAP := 8.0
# —— 中央 ——
const CENTER := Vector2(128, 186)         # 牌心
const PIP_ROW := 112.0                    # 点数排法的上下半幅:最上 / 最下一排离牌心这么远
const PIP_COLUMN := 24.0                  # 两列离中线这么远
const PIP_COLUMN_TIGHT := 22.0            # 9、10 的花色小一号,两列往里收,给更宽的「10」角标让出纸缝(中列错开半行插在中间)
const PIP_HEIGHTS := {2: 38.0, 3: 38.0, 4: 38.0, 5: 38.0, 6: 38.0, 7: 34.0, 8: 34.0, 9: 28.0, 10: 28.0}
const ACE_HEIGHT := 86.0
const ACE_SPADE_HEIGHT := 108.0           # ♠A 的大徽章
const PANEL := Rect2(84, 40, 88, 292)     # J/Q/K 的角色画框
const PANEL_RADIUS := 30.0
const COURT := [PokerCard.JACK, PokerCard.QUEEN, PokerCard.KING]

# 角标与中央之间至少留这么宽的纸:缩到 30×42 像素(约 1/8.5)时还有一个多像素的缝,不粘成一团
const MIN_CLEARANCE := 10.0

const ARC_STEP := 0.12                    # 弧线每段约 7°:放大到 140 像素也看不出折线
const CIRCLE_SEGMENTS := 40
const BEZIER_SEGMENTS := 16
const DIAMOND_PINCH := 0.16               # 方块四边向中心收的比例:微凹的边更像牌上的方块


# —— 整张牌 ——

static func layout(card: int) -> Dictionary:
	# {"ink": 花色色, "index": 两个角标的多边形, "pips": 中央花色(每枚一组多边形), "panel": J/Q/K 的画框轮廓(其余为空),
	#  "emblem": 是否 ♠A 大徽章}
	var rank := PokerCard.rank(card)
	var suit := PokerCard.suit(card)
	var corner := index_polygons(rank, suit)
	var index: Array[PackedVector2Array] = corner.duplicate()
	for poly in corner:
		index.append(half_turn(poly))
	var art := {"ink": SUIT_COLORS[suit], "index": index, "pips": [], "panel": PackedVector2Array(),
		"emblem": rank == PokerCard.ACE and suit == PokerCard.SPADES}
	if rank in COURT:
		art["panel"] = rounded_rect(PANEL, PANEL_RADIUS)
	else:
		art["pips"] = pip_polygons(rank, suit)
	return art


static func center_polygons(card: int) -> Array[PackedVector2Array]:
	# 中央部分的全部多边形(画框或所有花色摊平),测试量间距与边界用
	var art := layout(card)
	var out: Array[PackedVector2Array] = []
	if not art["panel"].is_empty():
		out.append(art["panel"])
	for pip in art["pips"]:
		out.append_array(pip)
	return out


static func index_polygons(rank: int, suit: int) -> Array[PackedVector2Array]:
	# 左上角标:点数 + 正下方的花色(花色按点数栏居中,「10」变宽也不挪)
	var polys := rank_polygons(rank, rank_box(rank))
	var column_x := INDEX_ORIGIN.x + RANK_WIDTH / 2.0
	var suit_y := INDEX_ORIGIN.y + RANK_HEIGHT + INDEX_SUIT_GAP + INDEX_SUIT_HEIGHT / 2.0
	polys.append_array(suit_polygons(suit, Vector2(column_x, suit_y), INDEX_SUIT_HEIGHT))
	return polys


static func rank_box(rank: int) -> Rect2:
	return Rect2(INDEX_ORIGIN, Vector2(TEN_WIDTH if rank == 10 else RANK_WIDTH, RANK_HEIGHT))


static func pip_slots(rank: int) -> Array[Vector2]:
	# 经典排法,单位坐标:x ∈ {-1, 0, 1}(两列与中列),y ∈ [-1, 1](最上到最下);A 只有牌心一枚
	var third := 1.0 / 3.0
	match rank:
		2:
			return [Vector2(0, -1), Vector2(0, 1)]
		3:
			return [Vector2(0, -1), Vector2(0, 0), Vector2(0, 1)]
		4:
			return [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
		5:
			return [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)]
		6:
			return [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)]
		7:
			return [Vector2(-1, -1), Vector2(1, -1), Vector2(0, -0.5), Vector2(-1, 0), Vector2(1, 0),
				Vector2(-1, 1), Vector2(1, 1)]
		8:
			return [Vector2(-1, -1), Vector2(1, -1), Vector2(0, -0.5), Vector2(-1, 0), Vector2(1, 0),
				Vector2(0, 0.5), Vector2(-1, 1), Vector2(1, 1)]
		9:
			return [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, -third), Vector2(1, -third), Vector2(0, 0),
				Vector2(-1, third), Vector2(1, third), Vector2(-1, 1), Vector2(1, 1)]
		10:
			return [Vector2(-1, -1), Vector2(1, -1), Vector2(0, -2.0 * third), Vector2(-1, -third), Vector2(1, -third),
				Vector2(-1, third), Vector2(1, third), Vector2(0, 2.0 * third), Vector2(-1, 1), Vector2(1, 1)]
	return [Vector2.ZERO]


static func pip_height(rank: int, suit := -1) -> float:
	if rank == PokerCard.ACE:
		return ACE_SPADE_HEIGHT if suit == PokerCard.SPADES else ACE_HEIGHT
	return PIP_HEIGHTS.get(rank, ACE_HEIGHT)


static func pip_polygons(rank: int, suit: int) -> Array:
	# 每枚花色一组多边形;下半的倒过来(绕自己的中心转 180°),和真牌一样
	var height := pip_height(rank, suit)
	var column := PIP_COLUMN_TIGHT if rank >= 9 and rank <= 10 else PIP_COLUMN
	var out := []
	for slot in pip_slots(rank):
		var at := CENTER + Vector2(slot.x * column, slot.y * PIP_ROW)
		var parts := suit_polygons(suit, at, height)
		if slot.y > 0.01:
			for k in parts.size():
				parts[k] = _turn_about(parts[k], at)
		out.append(parts)
	return out


static func half_turn(poly: PackedVector2Array) -> PackedVector2Array:
	# 绕牌心转 180°:右下角标与左上角标中心对称
	var out := PackedVector2Array()
	for p in poly:
		out.append(Vector2(SIZE) - p)
	return out


static func _turn_about(poly: PackedVector2Array, at: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(at * 2.0 - p)
	return out


static func rounded_rect(rect: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [Vector2(rect.end.x - radius, rect.position.y + radius), Vector2(rect.end.x - radius, rect.end.y - radius),
		Vector2(rect.position.x + radius, rect.end.y - radius), Vector2(rect.position.x + radius, rect.position.y + radius)]
	for c in 4:
		for k in 9:
			var a := -PI / 2 + c * PI / 2 + PI / 2 * k / 8.0
			pts.append(corners[c] + Vector2(cos(a), sin(a)) * radius)
	return pts


# —— 点数 ——

static func rank_polygons(rank: int, box: Rect2) -> Array[PackedVector2Array]:
	# 笔画中心线映射到点数框内缩半个笔画的范围,再加粗成圆头圆角的多边形:笔画外缘正好贴着框
	var half := rank_stroke(rank) / 2.0
	var inner := box.grow(-half)
	var polys: Array[PackedVector2Array] = []
	for line in rank_strokes(rank):
		var pts := PackedVector2Array()
		for p in line:
			pts.append(inner.position + p * inner.size)
		polys.append_array(Geometry2D.offset_polyline(pts, half, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND))
	return polys


static func rank_stroke(rank: int) -> float:
	return TEN_STROKE if rank == 10 else STROKE


static func rank_strokes(rank: int) -> Array[PackedVector2Array]:
	# 每个点数的笔画中心线,单位框 [0,1]²(y 向下)。
	# 围成圈的笔画要拆成几段分别加粗:一整条加粗时圈里会多出一个「洞」多边形,画家填色就把空心填实了
	match rank:
		2:
			return [_chain([_arc(Vector2(0.5, 0.27), Vector2(0.5, 0.27), PI + 0.5, TAU + 0.6),
				_pts([0.0, 1.0, 1.0, 1.0])])]
		3:
			return [_arc(Vector2(0.5, 0.25), Vector2(0.46, 0.25), PI + 0.5, TAU + PI / 2.0 + 0.3),
				_arc(Vector2(0.5, 0.72), Vector2(0.5, 0.28), PI * 1.5 - 0.3, TAU + PI / 2.0 + 0.9)]
		4:
			# 竖笔单独一段:斜笔、横笔与竖笔围出的三角形空心才留得住
			return [_pts([0.74, 1.0, 0.74, 0.0]), _pts([0.74, 0.0, 0.0, 0.68, 1.0, 0.68])]
		5:
			return [_chain([_pts([0.92, 0.0, 0.14, 0.0, 0.08, 0.45]),
				_arc(Vector2(0.5, 0.69), Vector2(0.5, 0.31), PI * 1.5 - 0.95, TAU + PI / 2.0 + 0.9)])]
		6:
			var six := _ring(Vector2(0.5, 0.67), Vector2(0.5, 0.33))
			six.append(_bezier(Vector2(0.0, 0.67), Vector2(0.02, 0.02), Vector2(0.82, 0.0)))
			return six
		7:
			return [_pts([0.0, 0.0, 1.0, 0.0, 0.32, 1.0])]
		8:
			var eight := _ring(Vector2(0.5, 0.24), Vector2(0.42, 0.24))
			eight.append_array(_ring(Vector2(0.5, 0.72), Vector2(0.5, 0.28)))
			return eight
		9:
			var nine := _ring(Vector2(0.5, 0.33), Vector2(0.5, 0.33))
			nine.append(_pts([1.0, 0.36, 0.4, 1.0]))
			return nine
		10:
			# 「1」只留一个短旗,「0」是窄椭圆:两字之间与「0」的空心都要在缩小后还看得出来
			var ten := _ring(Vector2(1.0 - TEN_ZERO_HALF_WIDTH, 0.5), Vector2(TEN_ZERO_HALF_WIDTH, 0.5))
			ten.append(_pts([0.0, 0.17, TEN_ONE_X, 0.0, TEN_ONE_X, 1.0]))
			return ten
		PokerCard.JACK:
			return [_chain([_pts([0.36, 0.0, 0.92, 0.0, 0.92, 0.66]),
				_arc(Vector2(0.47, 0.66), Vector2(0.45, 0.34), 0.0, PI - 0.1)])]
		PokerCard.QUEEN:
			var queen := _ring(Vector2(0.5, 0.47), Vector2(0.5, 0.47))
			queen.append(_pts([0.56, 0.7, 1.0, 1.0]))
			return queen
		PokerCard.KING:
			return [_pts([0.0, 0.0, 0.0, 1.0]), _pts([1.0, 0.0, 0.0, 0.66]), _pts([0.36, 0.42, 1.0, 1.0])]
		PokerCard.ACE:
			return [_pts([0.0, 1.0, 0.5, 0.0, 1.0, 1.0]), _pts([0.2, 0.68, 0.8, 0.68])]
	return []


# —— 花色 ——

static func suit_polygons(suit: int, center: Vector2, height: float) -> Array[PackedVector2Array]:
	# 花色由几块互相重叠的多边形拼成(同色填充,重叠处看不出接缝)
	var polys: Array[PackedVector2Array] = []
	for part in suit_parts(suit):
		var poly := PackedVector2Array()
		for p in part:
			poly.append(center + p * height)
		polys.append(poly)
	return polys


static func suit_parts(suit: int) -> Array[PackedVector2Array]:
	# 单位高度、以原点为中心(y ∈ [-0.5, 0.5])的花色部件
	match suit:
		PokerCard.SPADES:
			return _spade()
		PokerCard.HEARTS:
			return _heart()
		PokerCard.DIAMONDS:
			return _diamond()
	return _club()


static func _heart() -> Array[PackedVector2Array]:
	# 上方两个圆瓣,两条切线收到底部尖角
	var r := 0.265
	var left := Vector2(-0.255, -0.235)
	var right := Vector2(0.255, -0.235)
	var tip := Vector2(0.0, 0.5)
	var body := PackedVector2Array([_tangent(left, r, tip, 1.0), tip, _tangent(right, r, tip, -1.0), right, left])
	return [_circle(left, r), _circle(right, r), body]


static func _spade() -> Array[PackedVector2Array]:
	# 倒过来的红心(圆瓣在下、尖角朝上)加一个上窄下宽的柄
	var r := 0.235
	var left := Vector2(-0.225, 0.07)
	var right := Vector2(0.225, 0.07)
	var tip := Vector2(0.0, -0.5)
	var body := PackedVector2Array([_tangent(left, r, tip, -1.0), tip, _tangent(right, r, tip, 1.0), right, left])
	return [_circle(left, r), _circle(right, r), body, _stem(0.1, 0.2)]


static func _club() -> Array[PackedVector2Array]:
	# 品字形三个圆,中间补一块三角,下面一个柄
	var r := 0.235
	var top := Vector2(0.0, -0.265)
	var left := Vector2(-0.265, 0.075)
	var right := Vector2(0.265, 0.075)
	return [_circle(top, r), _circle(left, r), _circle(right, r), PackedVector2Array([top, right, left]),
		_stem(0.05, 0.2)]


static func _diamond() -> Array[PackedVector2Array]:
	var corners := [Vector2(0.0, -0.5), Vector2(0.39, 0.0), Vector2(0.0, 0.5), Vector2(-0.39, 0.0)]
	var poly := PackedVector2Array()
	for i in corners.size():
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % corners.size()]
		var edge := _bezier(a, (a + b) / 2.0 * (1.0 - DIAMOND_PINCH), b)
		edge.remove_at(edge.size() - 1)   # 终点是下一条边的起点
		poly.append_array(edge)
	return [poly]


static func _stem(top: float, half_base: float) -> PackedVector2Array:
	# 柄:从花色中部往下,两侧内凹地张开到底边
	var neck := 0.035
	var poly := _bezier(Vector2(neck, top), Vector2(neck, 0.42), Vector2(half_base, 0.5))
	poly.append_array(_bezier(Vector2(-half_base, 0.5), Vector2(-neck, 0.42), Vector2(-neck, top)))
	return poly


static func _tangent(center: Vector2, radius: float, from: Vector2, turn: float) -> Vector2:
	# 从圆外一点 from 引到圆上的切点;turn = ±1 选两条切线中的一条
	var d := from - center
	var angle := d.angle() + turn * acos(radius / d.length())
	return center + Vector2.from_angle(angle) * radius


# —— 曲线工具 ——

static func _pts(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		out.append(Vector2(flat[i], flat[i + 1]))
	return out


static func _chain(parts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for part in parts:
		out.append_array(part)
	return out


static func _arc(center: Vector2, radius: Vector2, from: float, to: float) -> PackedVector2Array:
	# 椭圆弧;角度增大在屏幕上是顺时针(y 向下)
	var steps := maxi(2, ceili(absf(to - from) / ARC_STEP))
	var out := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(from, to, float(i) / steps)
		out.append(center + Vector2(cos(a), sin(a)) * radius)
	return out


static func _ring(center: Vector2, radius: Vector2) -> Array[PackedVector2Array]:
	# 闭合的圈拆成左右两半:单独加粗再叠起来,中间的洞才留得住
	return [_arc(center, radius, -PI / 2.0, PI / 2.0), _arc(center, radius, PI / 2.0, PI * 1.5)]


static func _bezier(a: Vector2, control: Vector2, b: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in BEZIER_SEGMENTS + 1:
		var t := float(i) / BEZIER_SEGMENTS
		out.append(a.lerp(control, t).lerp(control.lerp(b, t), t))
	return out


static func _circle(center: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in CIRCLE_SEGMENTS:
		out.append(center + Vector2.from_angle(TAU * i / CIRCLE_SEGMENTS) * radius)
	return out
