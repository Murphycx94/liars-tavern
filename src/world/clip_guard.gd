class_name ClipGuard
extends RefCounted
# 穿模防护(穿模修复 2026-10-10,规格 2026-10-08-cozy-toon-style-design §穿模修复):牌桌上的东西用解析形状描述,
# 弹簧脖子按它做软碰撞(Patron._update_neck 每个积分小步调一次)。运行时不读网格数组:头的形状是构建时由部件网格的
# 包围盒换算的(Patron.head_metrics,按物种缓存),障碍物是圆、旋转矩形与「别人的头」(按朝向的椭圆半径)。坐标都是牌桌坐标
# (TableWorld 局部:酒客、牌层都挂在它下面),水平面用 Vector2(x, z)。
# 三种处理:
# - 挡(BLOCK):别人的头与身体、骗子酒馆的目标牌立牌、举在头边的牌扇(越肩时自己的牌扇)、玩法登记的高道具。
#   头的水平位置被推到形状外面;每个小步都推,头只会贴着边滑过去,不会穿过去翻到另一边(按头此刻在哪一侧推)
# - 抬(LIFT):立在桌面上空的牌扇(自己的、别人的)、烛台、德州公共牌架等矮东西:头从上面拱过去,
#   要抬的高度按头的椭球下沿离形状顶面的差算(连续、平滑),最多 MAX_LIFT
# - 顶:吊灯罩口。抬头不顶到灯(在灯下按罩口高度封顶)
# 网络:同步的仍是玩家按 WASD 的原始探头偏移(GazeSync 不变),每台机器用自己场景里的形状各自推、各自抬;
# 形状只取决于座位、牌扇与道具的摆法和各人此刻的头位,同样的输入各端结果一致(自己越肩举牌的位置只在本机,差别只在这一处)。
# 给新玩法(吹牛骰子、斗地主……)的接口:world.clip_guard.set_prop(id, shape) 登记桌上的道具(shape 用 circle / rect / box_of 造,
# 会动的用 follow),
# remove_prop(id) 收走;节点不可见或已释放时自动忽略。酒客的牌扇挂在 Patron.fan 下就会自动参与,不用登记。

enum { BLOCK, LIFT }

const MARGIN := 0.03            # 头(按朝向的椭圆半径)与挡路的形状之间至少留这么多(米)
const LIFT_MARGIN := 0.03       # 头从矮东西上面拱过去时,椭球下沿高出它的顶面这么多
const MAX_LIFT := 0.16          # 最多抬这么高
const LIFT_FLAT := 8.0          # 头下沿的超椭球指数(2 = 椭球;越大底面越平)
const NECK_SAMPLES := 16        # 脖子从矮东西上面过:沿脖子取样找第一次进到占地的位置
const NECK_IGNORE := 0.2        # 脖子根附近(前 20%)进到占地的不管:那是自己的牌扇,头往前探时它会矮下去(Patron.fan_tucked)
const LAMP_Y := Tavern.ROOM_HEIGHT + LampProp.MOUTH_Y - LampProp.BEAD   # 吊灯罩口高度(牌桌坐标,≈1.89)
const LAMP_RADIUS := LampProp.MOUTH_RADIUS + LampProp.BEAD
const CEILING_MARGIN := 0.04    # 帽顶离罩口至少这么多
# 别人的身体连椅子:座位坐标里的竖直长方体(躯干横向半宽 ≈0.25 加手臂根、椅背柱在 z 0.34),顶面取椅背顶(ChairBuilder.TOP)
const BODY_CENTER := Vector3(0, 0, 0.04)
const BODY_HALF := Vector2(0.32, 0.37)
const BODY_TOP := ChairBuilder.TOP
const STAND_RADIUS := 0.075     # 目标牌立牌:转着的牌半宽 0.06 + 夹子
const FAN_PAD := 0.01           # 牌扇的占地比牌角外扩这么多
const RAY_SAMPLES := 20         # 探头目标沿直线找第一个碰撞的取样数(头 + 形状的碰撞宽度 ≥ 0.6 米,3 米分 20 段漏不掉)

var world: Node3D
var _props := {}                # id -> shape
var _frame := -1
var _shapes: Array = []         # 这一帧的全部形状(带 owner;各酒客查询时跳过自己的)


func _init(p_world: Node3D) -> void:
	world = p_world


# —— 道具登记(新玩法用) ——

func set_prop(id: StringName, shape: Dictionary) -> void:
	shape = shape.duplicate()
	shape["tied"] = shape.get("node") != null   # 登记时就记下是不是跟节点绑着(节点释放后取出来的值不可靠)
	_props[id] = shape
	_frame = -1


func remove_prop(id: StringName) -> void:
	_props.erase(id)
	_frame = -1


func has_prop(id: StringName) -> bool:
	return _props.has(id)


static func follow(node: Node3D, radius: float, points: PackedVector3Array, mode := LIFT) -> Dictionary:
	# 跟着节点走的竖直圆柱:每帧按节点此刻的位置取水平中心,顶面取 points(节点局部)变换后的最高点。
	# 会动的道具用它(吹牛骰子的骰盅:扣着、捧起来摇、翻开都跟着走);节点释放或隐藏后自动忽略
	return {"kind": "circle", "c": Vector2.ZERO, "r": radius, "top": 0.0, "mode": mode, "node": node, "owner": -1,
		"follow": points}


static func circle(center: Vector3, radius: float, top: float, mode := BLOCK, node: Node3D = null) -> Dictionary:
	# 竖直圆柱(牌桌坐标):center 取水平位置,top 是顶面高度;node 不可见或已释放时忽略
	return {"kind": "circle", "c": Vector2(center.x, center.z), "r": radius, "top": top, "mode": mode, "node": node, "owner": -1}


static func rect(center: Vector3, axis: Vector3, half: Vector2, top: float, mode := BLOCK, node: Node3D = null) -> Dictionary:
	# 竖直的长方体(牌桌坐标):axis 是 half.x 那条边的水平方向,half.y 是与它垂直的半宽
	var a := Vector2(axis.x, axis.z)
	a = a.normalized() if a.length_squared() > 0.000001 else Vector2.RIGHT
	return {"kind": "rect", "c": Vector2(center.x, center.z), "axis": a, "half": half, "top": top, "mode": mode, "node": node, "owner": -1}


static func box_of(points: PackedVector3Array, axis: Vector3, mode := BLOCK, node: Node3D = null, pad := 0.0) -> Dictionary:
	# 一组点(牌桌坐标)沿 axis 方向的水平包围矩形,顶面取最高点:牌、道具的角点都可以丢进来
	var a := Vector2(axis.x, axis.z)
	a = a.normalized() if a.length_squared() > 0.000001 else Vector2.RIGHT
	var perp := Vector2(-a.y, a.x)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var top := -INF
	for p in points:
		var q := Vector2(p.x, p.z)
		var u := Vector2(q.dot(a), q.dot(perp))
		lo = lo.min(u)
		hi = hi.max(u)
		top = maxf(top, p.y)
	var mid := (lo + hi) * 0.5
	var shape := rect(Vector3.ZERO, axis, (hi - lo) * 0.5 + Vector2(pad, pad), top, mode, node)
	shape["c"] = a * mid.x + perp * mid.y
	return shape


static func fan_shape(fan: Node3D, space: Node3D, mode: int, owner := -1) -> Dictionary:
	# 牌扇的占地(牌桌坐标 = space 的局部):按牌扇里每张牌的四个角;没有可见的牌时返回空字典。
	# 只用牌的变换与固定尺寸(Card3D.WIDTH / HEIGHT),不读网格
	if fan == null or not fan.is_visible_in_tree():
		return {}
	var to_space := space.global_transform.affine_inverse() * fan.global_transform
	var points := PackedVector3Array()
	var hw := Card3D.WIDTH * 0.5
	var hh := Card3D.HEIGHT * 0.5
	for card in fan.get_children():
		if not card is Card3D or not card.visible:
			continue
		var xf: Transform3D = to_space * card.transform
		for corner in [Vector3(-hw, 0, -hh), Vector3(hw, 0, -hh), Vector3(hw, 0, hh), Vector3(-hw, 0, hh)]:
			points.append(xf * corner)
	if points.is_empty():
		return {}
	var shape := box_of(points, to_space.basis.x, mode, fan, FAN_PAD)
	shape["owner"] = owner
	return shape


# —— 每帧的形状 ——

func shapes() -> Array:
	# 这一帧所有的形状(按帧缓存):登记的道具 + 每位酒客的头、身体、牌扇
	var frame := Engine.get_process_frames()
	if frame == _frame:
		return _shapes
	_frame = frame
	_shapes = []
	var gone := []
	for id in _props:
		var shape: Dictionary = _props[id]
		if shape.get("tied", false):
			# 跟节点绑着的:节点已释放就收走登记(已释放的对象和 null 比较也是相等的,得用 is_instance_valid 判断),隐藏时这一帧不算
			var node = shape["node"]
			if not is_instance_valid(node):
				gone.append(id)
				continue
			if not (node as Node3D).is_visible_in_tree():
				continue
		if shape.has("follow"):
			shape = _followed(shape)
		_shapes.append(shape)
	for id in gone:
		_props.erase(id)
	var patrons: Dictionary = world.get("patrons") if world.get("patrons") != null else {}
	for pid in patrons:
		var p: Patron = patrons[pid]
		if not is_instance_valid(p) or not p.is_inside_tree() or not p.visible:
			continue
		var seat := p.transform.orthonormalized()
		var forward := -seat.basis.z
		var head := world.to_local(p.head_position())
		var m := p.guard_metrics()
		_shapes.append({"kind": "head", "c": Vector2(head.x, head.z), "fwd": Vector2(forward.x, forward.z).normalized(),
			"rx": m["rx"], "front": m["front"], "back": m["back"], "top": head.y + m["above"], "bottom": head.y - m["below"],
			"mode": BLOCK, "owner": pid})
		var body := rect(seat * BODY_CENTER, seat.basis.x, BODY_HALF, (seat * Vector3(0, BODY_TOP, 0)).y)
		body["owner"] = pid
		_shapes.append(body)
		var mode := -1
		match p.fan_mode():
			Patron.FAN_TABLE:
				mode = LIFT
			Patron.FAN_HAND:
				mode = BLOCK
		if mode >= 0:
			var fan := fan_shape(p.fan, world, mode, pid)
			if not fan.is_empty():
				fan["fan"] = true
				_shapes.append(fan)
	return _shapes


func _followed(shape: Dictionary) -> Dictionary:
	var node: Node3D = shape["node"]
	var xf := world.global_transform.affine_inverse() * node.global_transform
	var top := -INF
	for p in shape["follow"]:
		top = maxf(top, (xf * p).y)
	var out := shape.duplicate()
	out["c"] = Vector2(xf.origin.x, xf.origin.z)
	out["top"] = top
	return out


# —— 解析几何(纯函数) ——

static func ellipse_radius(dir: Vector2, fwd: Vector2, rx: float, front: float, back: float) -> float:
	# 头的水平轮廓按朝向的半径:dir 是单位方向,fwd 是头朝的方向;前半用 front、后半用 back、两侧 rx,椭圆插值(连续)
	var along := dir.dot(fwd)
	var side := dir.dot(Vector2(-fwd.y, fwd.x))
	var rz := front if along > 0.0 else back
	return 1.0 / sqrt(side * side / (rx * rx) + along * along / (rz * rz))


static func separation(shape: Dictionary, h: Vector2) -> Array:
	# [离形状边界的距离(在里面为负), 往外的单位法向]:h 是头心的水平位置
	match shape["kind"]:
		"circle", "head":
			var v: Vector2 = h - shape["c"]
			var d := v.length()
			var n := v / d if d > 0.000001 else Vector2.RIGHT
			var r: float = shape["r"] if shape["kind"] == "circle" else \
				ellipse_radius(n, shape["fwd"], shape["rx"], shape["front"], shape["back"])
			return [d - r, n]
		_:
			var a: Vector2 = shape["axis"]
			var perp := Vector2(-a.y, a.x)
			var rel: Vector2 = h - shape["c"]
			var u := rel.dot(a)
			var w := rel.dot(perp)
			var half: Vector2 = shape["half"]
			var q := Vector2(clampf(u, -half.x, half.x), clampf(w, -half.y, half.y))
			var out := Vector2(u, w) - q
			if out.length_squared() > 0.0000001:
				var d := out.length()
				var n_local := out / d
				return [d, a * n_local.x + perp * n_local.y]
			var px := half.x - absf(u)
			var py := half.y - absf(w)
			if px < py:
				return [-px, a * signf(u if u != 0.0 else 1.0)]
			return [-py, perp * signf(w if w != 0.0 else 1.0)]


func blockers_for(owner: int, home: Vector2, fwd: Vector2, metrics: Dictionary) -> Array:
	# 某位酒客要躲的「挡」形状:去掉他自己的头和身体。头在原位(没探头)时就已经挨着的形状(摆法本来就贴得近,
	# 如越肩时举在大头旁边的牌扇)记下原位时差的那一截(slack):只是不让头比原位更靠近它,原位不推、也不会卡住动不了
	var out := []
	for shape in shapes():
		if shape["mode"] != BLOCK:
			continue
		if shape["owner"] == owner and owner != -1 and not shape.get("fan", false):
			continue
		var gap := clearance(shape, home, fwd, metrics)
		if gap < 0.0:
			shape = shape.duplicate()
			shape["slack"] = -gap
		out.append(shape)
	return out


static func clearance(shape: Dictionary, h: Vector2, fwd: Vector2, metrics: Dictionary) -> float:
	# 头(椭圆半径 + MARGIN)离形状还有多远,负数表示已经挨上(扣掉形状自带的 slack)
	var sep := separation(shape, h)
	return sep[0] - ellipse_radius(-sep[1], fwd, metrics["rx"], metrics["front"], metrics["back"]) - MARGIN \
		+ float(shape.get("slack", 0.0))


static func overlaps(shape: Dictionary, h: Vector2, fwd: Vector2, metrics: Dictionary) -> bool:
	return clearance(shape, h, fwd, metrics) < 0.0


static func push_out(blockers: Array, h: Vector2, fwd: Vector2, metrics: Dictionary, head_bottom: float) -> Array:
	# 把头心 h 推到「挡」形状外面(头的椭圆半径 + MARGIN − slack);返回 [新位置, 最后一次推的法向(没推时为零)]
	var normal := Vector2.ZERO
	for pass_i in 2:
		for shape in blockers:
			if shape["top"] < head_bottom:
				continue   # 头从它上面过(比如抬过了矮东西)
			var gap := clearance(shape, h, fwd, metrics)
			if gap < 0.0:
				var n: Vector2 = separation(shape, h)[1]
				h -= n * gap
				normal = n
	return [h, normal]


static func ray_clamp(blockers: Array, from: Vector2, to: Vector2, fwd: Vector2, metrics: Dictionary) -> float:
	# 头心从原位 from 沿直线去 to,碰到第一个「挡」形状之前能走多远(0..1)。探头目标按它截短:头只去得了从原位直接看得见的地方,
	# 不会绕到别人身后卡在缝里,收回来时一路畅通;每个小步再推一次(push_out)兜住目标之间的过渡
	var d := to - from
	if d.length_squared() < 0.000001:
		return 1.0
	var reach := maxf(metrics["rx"], maxf(metrics["front"], metrics["back"])) + MARGIN
	var best := 1.0
	for shape in blockers:
		if _segment_distance(from, to, shape["c"]) > _bound(shape) + reach:
			continue
		var clear := 0.0
		for i in range(1, RAY_SAMPLES + 1):
			var t := float(i) / RAY_SAMPLES
			if t > best:
				break
			if overlaps(shape, from + d * t, fwd, metrics):
				var hit := t
				for k in 6:
					var mid := (clear + hit) * 0.5
					if overlaps(shape, from + d * mid, fwd, metrics):
						hit = mid
					else:
						clear = mid
				best = minf(best, clear)
				break
			clear = t
	return best


static func _bound(shape: Dictionary) -> float:
	match shape["kind"]:
		"circle":
			return shape["r"]
		"head":
			return maxf(shape["rx"], maxf(shape["front"], shape["back"]))
		_:
			return (shape["half"] as Vector2).length()


static func _segment_distance(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func lift_needed(shapes_list: Array, h: Vector2, base_y: float, fwd: Vector2, metrics: Dictionary, skip_owner: int,
		neck_base := Vector3(INF, 0, 0), neck_radius := 0.0) -> float:
	# 头从「抬」形状上面拱过去要抬多高:头 = 超椭球(水平半径按朝向,前 front、后 back、两侧 mx;下沿半径 below),
	# 球心在 (h, base_y);取形状占地里离球心最近的点,算那里的下沿要高出顶面 LIFT_MARGIN 还差多少。
	# 给了 neck_base(脖子根,牌桌坐标)时也让伸长的脖子从形状上面过去:脖子是从脖子根连到头枢轴(头心下 HEAD_CENTER.y)的直线
	var lift := 0.0
	var pivot_y := base_y - PatronParts.HEAD_CENTER.y
	for shape in shapes_list:
		if shape["mode"] != LIFT:
			continue
		if shape["owner"] == skip_owner and skip_owner != -1 and not shape.get("fan", false):
			continue
		var q := _closest(shape, h)
		var v := q - h
		var d := v.length()
		var t := 0.0
		if d > 0.000001:
			t = d / ellipse_radius(v / d, fwd, metrics["mx"], metrics["front"], metrics["back"])
		if t < 1.0:
			# 下沿按超椭球(比椭球平得多):鳄鱼的下颌、羊驼的吻最低点都在头心前面很远,不在正下方
			var bottom: float = base_y - metrics["below"] * pow(1.0 - pow(t, LIFT_FLAT), 1.0 / LIFT_FLAT)
			lift = maxf(lift, shape["top"] + LIFT_MARGIN - bottom)
		if neck_base.x != INF:
			var s := _first_inside(shape, Vector2(neck_base.x, neck_base.z), h, neck_radius)
			if s > NECK_IGNORE:
				var need: float = (shape["top"] + LIFT_MARGIN + neck_radius - neck_base.y) / s - (pivot_y - neck_base.y)
				lift = maxf(lift, need)
	return minf(lift, MAX_LIFT)


static func _first_inside(shape: Dictionary, a: Vector2, b: Vector2, pad: float) -> float:
	# 线段 a→b 第一次进到形状占地(外扩 pad)的位置(0..1);不进去时 −1
	for i in range(1, NECK_SAMPLES + 1):
		var s := float(i) / NECK_SAMPLES
		var p := a.lerp(b, s)
		if (_closest(shape, p) - p).length() <= pad:
			return s
	return -1.0


static func ceiling_cap(h: Vector2, base_y: float, metrics: Dictionary) -> float:
	# 吊灯下最多还能抬多高(头的水平轮廓碰到罩口范围时):离灯越近封顶越低,灯外不封
	var reach: float = LAMP_RADIUS + metrics["rx"]
	var d := h.length()
	if d >= reach + 0.1:
		return INF
	var room: float = LAMP_Y - CEILING_MARGIN - (base_y + metrics["above"])
	return maxf(room, 0.0) + MAX_LIFT * smoothstep(reach - 0.1, reach + 0.1, d)


static func _closest(shape: Dictionary, h: Vector2) -> Vector2:
	match shape["kind"]:
		"circle":
			var v: Vector2 = h - shape["c"]
			return shape["c"] + v.limit_length(shape["r"])
		"head":
			return shape["c"]
		_:
			var a: Vector2 = shape["axis"]
			var perp := Vector2(-a.y, a.x)
			var rel: Vector2 = h - shape["c"]
			var half: Vector2 = shape["half"]
			return shape["c"] + a * clampf(rel.dot(a), -half.x, half.x) + perp * clampf(rel.dot(perp), -half.y, half.y)
