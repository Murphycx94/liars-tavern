class_name RoomLayout
# 房间布局(纯数据 + 纯函数):墙段切分、门窗洞口、梁端支撑、壁炉砌块网格、墙饰与家具摆放、月光、镜头净空。
# 构建器(RoomShell / FireplaceSet / BarSet / OpeningsSet / RoomProps)的坐标都从这里取;测试直接核对这里的数据。
# 墙的约定:内表面在 ±INNER;u 是沿墙坐标(前后墙 u = x,左右墙 u = z);墙的局部 +Z 指向屋里。


const INNER := Tavern.ROOM_HALF - Tavern.WALL_THICKNESS / 2.0   # 4.4:墙内表面(灰泥面)
const HEIGHT := Tavern.ROOM_HEIGHT
const WAINSCOT_PROUD := 0.015    # 护墙板凸出灰泥面
const WAINSCOT_TOP := Tavern.WAINSCOT_HEIGHT
const RAIL_TOP := 1.13           # 墙裙压条盖板顶
const BASE_HEIGHT := 0.14        # 踢脚线高
const CROWN_BOTTOM := 3.28       # 顶线下沿
const BEAM_Z := [-3.0, -1.5, 0.0, 1.5, 3.0]
const BEAM_SIZE := Vector2(0.22, 0.24)   # 梁截面(宽 z,高 y)
const BEAM_BOTTOM := HEIGHT - 0.24
const CORNER_POST := 0.16
const CORNER_POST_CENTER := 4.32
const WALL_POST := Vector2(0.12, 0.16)   # 墙柱:沿墙宽、离墙深
const WALL_POSTS := {"left": [1.5, 3.0], "right": [-3.0, 3.0]}   # 落地墙柱(其余梁端用托架)
const POST := 1
const CORBEL := 2

# 门(前墙):门洞 x −0.95..0.25,高 2.30;门套侧板 0.11
const DOOR_X := -0.35
const DOOR_WIDTH := 1.2
const DOOR_HEIGHT := 2.30
const DOOR_X0 := DOOR_X - DOOR_WIDTH / 2.0
const DOOR_X1 := DOOR_X + DOOR_WIDTH / 2.0
const DOOR_CASING := 0.11
# 窗(右墙):洞口 z −1.55..−0.25,y 1.15..2.40;套线 0.1
const WINDOW_Z0 := Tavern.WINDOW_Z - Tavern.WINDOW_SIZE.x / 2.0
const WINDOW_Z1 := Tavern.WINDOW_Z + Tavern.WINDOW_SIZE.x / 2.0
const WINDOW_Y0 := Tavern.WINDOW_BOTTOM
const WINDOW_Y1 := Tavern.WINDOW_BOTTOM + Tavern.WINDOW_SIZE.y
const WINDOW_CASING := 0.1
const WINDOW_CENTER := Vector3(INNER, (WINDOW_Y0 + WINDOW_Y1) / 2.0, Tavern.WINDOW_Z)
const CURTAIN_Z := [Vector2(-1.95, -1.40), Vector2(-0.40, 0.15)]
# 窗外景板与门外夜街板
const BACKDROP_X := 5.4
const BACKDROP_Z := Vector2(-2.40, 0.60)
const BACKDROP_Y := Vector2(0.58, 2.98)
const STREET_Z := 5.8
const STREET_X := Vector2(-2.80, 2.10)
const STREET_Y := Vector2(-0.05, 2.95)
# 月光(数值与改造前 tavern.gd 一致:窗框中心 + (2.2, 1.5, 0.6))
const MOON_POS := Vector3(6.6, 3.275, -0.3)
const MOON_TARGET := Vector3(0.5, 0.2, -0.6)

# 壁炉:半块网格(宽 0.16、行高 0.2),原点在外框左下前角
const FIRE_HALF := 0.16
const FIRE_COURSE := 0.2
const FIRE_GRID_ORIGIN := Vector3(-2.62, 0.0, -3.92)
const FIRE_PIVOT := Vector3(Tavern.FIREPLACE_X, 0.0, -INNER)
const FIRE_BACK_Z := -4.24
# 壁炉各砌体盒子(世界坐标 AABB 的 min / max);测试核对它们都落在网格上
const FIRE_BOXES := {
	"pier_l": [Vector3(-2.62, 0.0, -4.40), Vector3(-2.14, 1.0, -3.92)],
	"pier_r": [Vector3(-0.86, 0.0, -4.40), Vector3(-0.38, 1.0, -3.92)],
	"lintel": [Vector3(-2.62, 1.0, -4.40), Vector3(-0.38, 1.4, -3.92)],
	"breast": [Vector3(-2.30, 1.6, -4.40), Vector3(-0.70, HEIGHT, -4.08)],
	"back": [Vector3(-2.14, 0.0, -4.40), Vector3(-0.86, 1.0, FIRE_BACK_Z)],
}
const HEARTH := [Vector3(-2.78, 0.0, -4.24), Vector3(-0.22, 0.06, -3.12)]
const MANTEL := [Vector3(-2.78, 1.4, -4.40), Vector3(-0.22, 1.6, -3.86)]

# 吧台
const BAR_X := Vector2(-3.66, -3.04)
const BAR_Z := Vector2(-2.30, 1.10)
const BAR_TOP_Y := 1.05
const BACKBAR_Z := Vector2(-2.26, 1.06)
const BACKBAR_FRONT := -3.95
const STOOL_X := -2.62
const STOOL_Z := [-1.9, -1.1, -0.3, 0.5]
const STOOL_SEAT := 0.76
const MIRROR_SIZE := Vector2(3.08, 1.67)   # z −2.14..0.94,y 0.95..2.62

# 地毯(2026-10-10 重做,动森式毛绒毯)[中心 xz, 横宽 x, 纵长 z, 款式];款式与 decor 着色器 rug_sizes[i].w 对应:
# main = 圆形主毯(凸起的毛绒包边、星星圈),runner = 圆角条纹长毯(两端流苏),mat = 门口小椭圆毯(毛绒包边、小花)
# 主毯圆心必须在原点:它随牌桌放大,着色器绕原点缩放顶点(见 main_rug_scale)
const RUG_MARGIN := 0.5          # 主毯半径 = 座位半径 + 0.5(椅子连椅背都落在毯上)
const RUG_MAIN_RADIUS := SeatLayout.SEAT_RADIUS + RUG_MARGIN   # 1.75(小桌);德州 / 炸弹猫大桌 2.25
const RUGS := [
	[Vector2(0.0, 0.0), RUG_MAIN_RADIUS * 2.0, RUG_MAIN_RADIUS * 2.0, "main"],
	[Vector2(STOOL_X, -0.6), 0.62, 3.1, "runner"],     # x −2.93..−2.31、z −2.15..0.95,吧凳正中
	[Vector2(DOOR_X, 3.72), 1.1, 0.7, "mat"],          # 门里 x −0.9..0.2、z 3.37..4.07
]
const RUG_KINDS := ["main", "runner", "mat"]
const FRINGE := 0.08             # 长条毯两端流苏宽
const RUG_RIM := 0.09            # 圆毯毛绒包边宽(主毯;小毯 0.06)
const RUG_CORNER := 0.05         # 长条毯圆角

# 墙饰摆放:wall = back / front / left / right;u 沿墙、y 中心高;size 宽 × 高;tilt 度(画面内旋转)
const DECOR := [
	{"id": "poster_fox", "kind": "poster", "wall": "back", "u": 0.22, "y": 1.62, "size": Vector2(0.30, 0.40), "tilt": -2.0, "species": 0, "curl": 0.02},
	{"id": "poster_bear", "kind": "poster", "wall": "back", "u": 0.62, "y": 1.55, "size": Vector2(0.30, 0.40), "tilt": 3.0, "species": 1, "curl": 0.0},
	{"id": "clock", "kind": "clock", "wall": "back", "u": 2.30, "y": 1.80, "size": Vector2(0.34, 0.85), "tilt": 0.0},
	{"id": "painting_bison", "kind": "painting", "wall": "back", "u": 3.82, "y": 1.62, "size": Vector2(0.56, 0.40), "tilt": 0.0, "art": "bison"},
	{"id": "poster_pig", "kind": "poster", "wall": "left", "u": 2.60, "y": 1.62, "size": Vector2(0.30, 0.40), "tilt": 1.5, "species": 2, "curl": 0.015},
	{"id": "poster_cat", "kind": "poster", "wall": "left", "u": 3.40, "y": 1.58, "size": Vector2(0.30, 0.40), "tilt": -2.5, "species": 3, "curl": 0.0},
	{"id": "poster_turtle", "kind": "poster", "wall": "left", "u": 3.78, "y": 1.66, "size": Vector2(0.30, 0.40), "tilt": 2.0, "species": 4, "curl": 0.022},
	{"id": "sign_cheat", "kind": "sign", "wall": "left", "u": 3.60, "y": 2.08, "size": Vector2(0.60, 0.15), "tilt": 0.0, "art": "no_cheating"},
	{"id": "poster_alpaca", "kind": "poster", "wall": "front", "u": 0.82, "y": 1.62, "size": Vector2(0.30, 0.40), "tilt": -1.5, "species": 5, "curl": 0.018},
	{"id": "poster_monkey", "kind": "poster", "wall": "front", "u": 1.20, "y": 1.55, "size": Vector2(0.30, 0.40), "tilt": 2.5, "species": 6, "curl": 0.0},
	{"id": "painting_coach", "kind": "painting", "wall": "front", "u": -2.72, "y": 1.85, "size": Vector2(0.60, 0.45), "tilt": 0.0, "art": "coach"},
	{"id": "horseshoe", "kind": "horseshoe", "wall": "front", "u": -0.35, "y": 2.66, "size": Vector2(0.14, 0.15), "tilt": 0.0},
	{"id": "poster_crocodile", "kind": "poster", "wall": "right", "u": 0.55, "y": 1.60, "size": Vector2(0.30, 0.40), "tilt": -2.0, "species": 7, "curl": 0.02},
	{"id": "painting_mesa", "kind": "painting", "wall": "right", "u": -2.45, "y": 1.62, "size": Vector2(0.60, 0.42), "tilt": 0.0, "art": "mesa"},
	{"id": "wagon_wheel", "kind": "wheel", "wall": "right", "u": 2.40, "y": 1.72, "size": Vector2(0.72, 0.72), "tilt": 0.0},
	{"id": "chalkboard", "kind": "chalkboard", "wall": "left", "u": -3.9, "y": 1.58, "size": Vector2(0.5, 0.38), "tilt": 1.0},
	{"id": "lasso", "kind": "lasso", "wall": "right", "u": -3.35, "y": 1.75, "size": Vector2(0.34, 0.46), "tilt": 0.0},
]
const FLAT_OFFSET := 0.005       # 平面件离墙
# 墙上的大件(特写背景测试与墙饰避让用):wall、u 中心、宽、y 下沿、y 上沿
const WALL_FEATURES := {
	"mirror": {"wall": "left", "u": -0.6, "width": 3.08, "y0": 0.95, "y1": 2.62},
	"bar_sign": {"wall": "left", "u": -0.6, "width": 2.48, "y0": 2.64, "y1": 2.93},
	"door": {"wall": "front", "u": DOOR_X, "width": DOOR_WIDTH + DOOR_CASING * 2.0, "y0": 0.0, "y1": 2.5},
	"window": {"wall": "right", "u": Tavern.WINDOW_Z, "width": 1.3 + WINDOW_CASING * 2.0, "y0": 1.05, "y1": 2.56},
	"curtain_a": {"wall": "right", "u": -1.675, "width": 0.55, "y0": 1.05, "y1": 2.62},
	"curtain_b": {"wall": "right", "u": -0.125, "width": 0.55, "y0": 1.05, "y1": 2.62},
	"piano": {"wall": "front", "u": -2.75, "width": 1.4, "y0": 0.0, "y1": 1.25},
	"coat_rack": {"wall": "front", "u": 2.55, "width": 0.5, "y0": 0.0, "y1": 1.85},
	"fireplace": {"wall": "back", "u": -1.5, "width": 2.56, "y0": 0.0, "y1": HEIGHT},
}
const FRAME_DEPTH := 0.03        # 画框厚

# 家具与道具簇的 AABB(世界坐标 min / max):镜头净空测试与构建器共用
const PROPS := {
	"fireplace": [Vector3(-2.62, 0.0, -4.40), Vector3(-0.38, HEIGHT, -3.92)],
	"mantel": [Vector3(-2.78, 1.4, -4.40), Vector3(-0.22, 1.6, -3.86)],
	"mantel_items": [Vector3(-2.55, 1.6, -4.25), Vector3(-0.45, 1.95, -3.95)],
	"skull": [Vector3(-2.02, 2.33, -4.40), Vector3(-0.98, 2.90, -3.86)],
	"hearth": [Vector3(-2.78, 0.0, -4.24), Vector3(-0.22, 0.06, -3.12)],
	"log_pile": [Vector3(-3.35, 0.0, -4.35), Vector3(-2.9, 0.62, -3.85)],
	"fire_tools": [Vector3(-0.22, 0.0, -4.32), Vector3(-0.02, 0.85, -4.08)],
	"bar": [Vector3(-3.70, 0.0, -2.36), Vector3(-2.96, 1.11, 1.16)],
	"bar_rail": [Vector3(-2.92, 0.12, -2.24), Vector3(-2.84, 0.24, 1.04)],
	"bar_top_items": [Vector3(-3.62, 1.11, -2.0), Vector3(-3.10, 1.50, 0.75)],
	"stools": [Vector3(-2.80, 0.0, -2.08), Vector3(-2.44, 0.80, 0.68)],
	"backbar": [Vector3(-4.40, 0.0, -2.30), Vector3(-3.86, 2.93, 1.10)],
	"spittoons": [Vector3(-2.91, 0.0, -1.61), Vector3(-2.69, 0.15, 0.21)],
	"piano": [Vector3(-3.45, 0.0, 3.55), Vector3(-2.05, 1.38, 4.33)],
	"piano_bench": [Vector3(-2.93, 0.0, 3.0), Vector3(-2.57, 0.55, 3.3)],
	"coat_rack": [Vector3(2.30, 0.0, 3.88), Vector3(2.80, 1.85, 4.36)],
	"crates_front": [Vector3(2.90, 0.0, 3.55), Vector3(4.15, 1.05, 4.20)],
	"sacks_front": [Vector3(3.15, 0.0, 3.0), Vector3(4.22, 0.45, 3.65)],
	"barrels_back": [Vector3(2.60, 0.0, -4.25), Vector3(4.20, 0.86, -2.55)],
	"sacks_back": [Vector3(3.40, 0.0, -2.55), Vector3(4.22, 0.45, -2.05)],
	"kegs": [Vector3(-4.22, 0.0, -4.22), Vector3(-3.62, 0.95, -3.70)],
	"window": [Vector3(4.24, 1.05, -1.95), Vector3(4.62, 2.62, 0.15)],
	"door": [Vector3(-1.06, 0.0, 4.20), Vector3(0.36, 2.50, 4.64)],
}


# —— 墙 ——

static func wall_normal(wall: String) -> Vector3:
	match wall:
		"back":
			return Vector3(0, 0, 1)
		"front":
			return Vector3(0, 0, -1)
		"left":
			return Vector3(1, 0, 0)
		_:
			return Vector3(-1, 0, 0)


static func wall_basis(wall: String) -> Basis:
	# 局部 Z = 朝屋里的法线,Y = 上,X = Y × Z(站在屋里看墙时朝右)
	var z := wall_normal(wall)
	return Basis(Vector3.UP.cross(z), Vector3.UP, z)


static func wall_point(wall: String, u: float, y: float, offset := 0.0) -> Vector3:
	# 墙面上 (u, y) 处、离灰泥面 offset 米的点
	match wall:
		"back":
			return Vector3(u, y, -INNER + offset)
		"front":
			return Vector3(u, y, INNER - offset)
		"left":
			return Vector3(-INNER + offset, y, u)
		_:
			return Vector3(INNER - offset, y, u)


static func wall_xform(wall: String, u: float, y: float, offset := 0.0, tilt_deg := 0.0) -> Transform3D:
	var basis := wall_basis(wall) * Basis(Vector3(0, 0, 1), deg_to_rad(tilt_deg))
	return Transform3D(basis, wall_point(wall, u, y, offset))


static func panel_fit(length: float, target: float) -> float:
	# 墙段里放整数块面板:取节距最接近 target 的块数(至少 1),返回实际节距
	var n := maxi(floori(length / target), 1)
	if absf(length / (n + 1) - target) < absf(length / n - target):
		n += 1
	return length / n


static func wainscot_segments(wall: String) -> Array:
	# 护墙板墙段 [u0, u1](被角柱、墙柱、门套、壁炉、后吧、窗套隔开)
	var c := CORNER_POST_CENTER - CORNER_POST / 2.0   # 4.24
	var hp := WALL_POST.x / 2.0
	match wall:
		"back":
			return [[-c, FIRE_GRID_ORIGIN.x], [-0.38, c]]
		"front":
			return [[-c, DOOR_X0 - DOOR_CASING], [DOOR_X1 + DOOR_CASING, c]]
		"left":
			return [[-c, BACKBAR_Z.x], [BACKBAR_Z.y, 1.5 - hp], [1.5 + hp, 3.0 - hp], [3.0 + hp, c]]
		_:
			return [[-c, -3.0 - hp], [-3.0 + hp, WINDOW_Z0 - WINDOW_CASING], [WINDOW_Z0 - WINDOW_CASING, WINDOW_Z1 + WINDOW_CASING],
				[WINDOW_Z1 + WINDOW_CASING, 3.0 - hp], [3.0 + hp, c]]


static func beam_support(wall: String, z: float) -> int:
	# 梁端落地墙柱(POST)还是托架(CORBEL):禁区(壁灯 ±0.3 m、窗洞加窗帘、后吧、墙饰)里只能用托架
	var posts: Array = WALL_POSTS.get(wall, [])
	for p in posts:
		if absf(p - z) < 0.01:
			return POST
	return CORBEL


static func beam_ends() -> Array:
	# 10 个梁端 [wall, z]
	var out := []
	for wall in ["left", "right"]:
		for z in BEAM_Z:
			out.append([wall, z])
	return out


# —— 地毯与月亮 ——

static func rug_sizes() -> Array:
	# decor 着色器的 rug_sizes[3]:(半宽 x, 半长 z, 包边 / 流苏宽, 款式编号)
	var out := []
	for rug in RUGS:
		out.append(Vector4(rug[1] / 2.0, rug[2] / 2.0, rug_edge(rug), float(RUG_KINDS.find(rug[3]))))
	return out


static func rug_edge(rug: Array) -> float:
	# 圆毯是包边宽(小毯按短半轴收窄),长条毯是流苏宽
	match rug[3]:
		"runner":
			return FRINGE
		"mat":
			return 0.06
		_:
			return RUG_RIM


static func main_rug_scale(table_radius: float) -> float:
	# 主毯随牌桌放大:半径跟座位半径走(座位半径 + RUG_MARGIN),小桌 1.0,德州大桌 2.25 / 1.75
	return (SeatLayout.seat_radius_for(table_radius) + RUG_MARGIN) / RUG_MAIN_RADIUS


static func moon_uv() -> Vector2:
	# 从窗心逆着月光方向(MOON_TARGET → MOON_POS)与外景板(x = BACKDROP_X)的交点,换算成外景板 UV(u 沿 +Z,v 自上而下)
	var dir := (MOON_POS - MOON_TARGET).normalized()
	var t := (BACKDROP_X - WINDOW_CENTER.x) / dir.x
	var hit := WINDOW_CENTER + dir * t
	return Vector2((hit.z - BACKDROP_Z.x) / (BACKDROP_Z.y - BACKDROP_Z.x), (BACKDROP_Y.y - hit.y) / (BACKDROP_Y.y - BACKDROP_Y.x))


# —— 摆放查询 ——

static func decor_aabb(item: Dictionary) -> AABB:
	# 墙饰的世界 AABB(按未倾斜的外框,深度取离墙 FRAME_DEPTH + 卷边)
	var size: Vector2 = item["size"]
	var depth := 0.12 if item["kind"] == "clock" else FRAME_DEPTH + float(item.get("curl", 0.0))
	var b := wall_basis(item["wall"])
	var center := wall_point(item["wall"], item["u"], item["y"], depth / 2.0)
	var half: Vector3 = (b.x * size.x / 2.0).abs() + (b.y * size.y / 2.0).abs() + (b.z * depth / 2.0).abs()
	return AABB(center - half, half * 2.0)


static func prop_aabb(id: String) -> AABB:
	var box: Array = PROPS[id]
	return AABB(box[0], box[1] - box[0])


static func all_aabbs() -> Dictionary:
	var out := {}
	for id in PROPS:
		out[id] = prop_aabb(id)
	for item in DECOR:
		out[item["id"]] = decor_aabb(item)
	return out


static func focus_backdrop(angle: float) -> Dictionary:
	# 特写机位(TableWorld.focus_view:镜头在桌心斜上方、偏向座位左侧 0.35 m,看向头心)背后的墙:
	# 从镜头穿过头心的射线打到哪面墙。头心取座位外移 0.10 m、高 1.27 m。返回 {"wall", "u", "y", "point"}
	var dir := SeatLayout.direction(angle)
	var right := Vector3.UP.cross(dir)
	var camera := dir * 0.15 + Vector3(0, 1.42, 0) - right * 0.35
	var head := dir * (SeatLayout.SEAT_RADIUS + 0.10) + Vector3(0, 1.27, 0)
	return wall_hit(camera, head - camera)


static func wall_hit(origin: Vector3, d: Vector3) -> Dictionary:
	# 射线 origin + d·t 先打到的墙(墙面在 ±INNER)
	d = d.normalized()
	var best := INF
	var out := {}
	for wall in ["back", "front", "left", "right"]:
		var n := wall_normal(wall)   # 朝屋里
		var denom := d.dot(-n)
		if denom <= 1e-6:
			continue
		var t := (INNER + origin.dot(n)) / denom
		if t > 0.0 and t < best:
			best = t
			var p := origin + d * t
			out = {"wall": wall, "u": p.x if wall in ["back", "front"] else p.z, "y": p.y, "point": p, "t": t}
	return out


static func camera_paths() -> Array:
	# 镜头路径的采样点 [名字, 点]:菜单环绕(每 2°)、结算环绕(骗子 / 德州)、观战、等待厅、翻牌机位
	var out := []
	for k in 180:
		var a := TAU * k / 180.0
		out.append(["menu", Vector3(0, 0.9, -0.2) + Vector3(sin(a) * 3.3, 1.15, cos(a) * 3.3)])
		out.append(["settle", Vector3(0, 0.95, 0) + Vector3(sin(a) * 2.4, 0.9, cos(a) * 2.4)])
		out.append(["settle_poker", Vector3(0, 0.95, 0) + Vector3(sin(a) * 3.1, 1.05, cos(a) * 3.1)])
	for p in [Vector3(0, 2.3, 2.7), Vector3(0.95, 2.6, 2.5), Vector3(0, 1.42, 1.05)]:
		out.append(["fixed", p])
	return out


static func clearance_violations(min_dist: float) -> Array:
	# 每个摆放的 AABB 离所有镜头路径采样点都要 ≥ min_dist;返回违规描述
	var out := []
	var boxes := all_aabbs()
	for sample in camera_paths():
		var p: Vector3 = sample[1]
		for id in boxes:
			var box: AABB = boxes[id]
			var d := _aabb_distance(box, p)
			if d < min_dist:
				out.append("%s 离 %s 机位 %s 只有 %.2f m" % [id, sample[0], p, d])
	return out


static func _aabb_distance(box: AABB, p: Vector3) -> float:
	var q := p.clamp(box.position, box.end)
	return q.distance_to(p)
