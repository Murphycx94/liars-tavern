extends RefCounted
# 截图工具与性能探针共用的机位表:seat 与游戏里的越肩机位(TableWorld.third_person_view,本机座位)一致。
# tools/ 不进导出包,所以不声明 class_name,用 preload 取用。

const NAMES := ["seat", "selfshot", "gun", "menu", "overhead", "fireplace", "bar", "window", "closeup", "opponent",
	"lineup_front", "lineup_back", "lineup_heads", "lineup_left", "lineup_right",
	"focus0", "focus90", "focus180", "focus270", "focus120", "focus240", "door", "corner", "corner_front"]
# 第一人称机位(要展台的牌桌,shot.gd / perf_probe.gd 另行处理,不进 NAMES):名字 -> 脖子偏移(座位坐标,模拟按住 WASD 探头)
const FIRST_PERSON := {"fp": Vector3.ZERO, "fp_peek": Vector3(0.45, 0, -0.35), "fp_lean": Vector3(0, 0, -0.6),
	"poker_fp": Vector3.ZERO, "poker_fp_peek": Vector3(-0.4, 0, -0.3), "bomb_fp": Vector3.ZERO,
	"dice_fp": Vector3.ZERO, "ddz_fp": Vector3.ZERO}
# 特写机位(复刻 TableWorld.focus_view:镜头在桌心斜上方、偏向座位左侧,看向座位上的头):名字 -> 座位角(度)
const FOCUS := {"focus0": 0.0, "focus90": 90.0, "focus180": 180.0, "focus270": 270.0, "focus120": 120.0, "focus240": 240.0}


static func place_first_person(rig: CameraRig, world: TableWorld, pid: int, view: String) -> void:
	# 第一人称(同 SeatCamera.enter):本机视角换成第一人称(手牌重摆)、头只投影不渲染、镜头跟着眼睛走,
	# 脖子按 FIRST_PERSON[view] 探出去;镜头先直接摆到眼睛上(性能探针不跑 _process)
	world.set_first_person(true)
	var me: Patron = world.patrons[pid]
	me.set_neck_target(FIRST_PERSON[view])
	me.set_head_hidden(true)
	rig.camera.fov = TableWorld.FIRST_PERSON_FOV
	rig.fill_light.light_energy = TableWorld.FIRST_PERSON_FILL
	rig.global_transform = world.first_person_view(pid)
	rig.follow(func() -> Transform3D: return world.first_person_view(pid), 0.0)


static func leave_first_person(world: TableWorld, pid: int) -> void:
	# 拍完第一人称换回越肩(手牌、头、脖子复原);机位由接下来的 place / snap 摆
	if world == null or not world.first_person:
		return
	world.set_first_person(false)
	world.patrons[pid].set_head_hidden(false)
	world.patrons[pid].set_neck_target(Vector3.ZERO)


static func place(rig: CameraRig, view: String) -> bool:
	# 摆好机位返回 true;不认识的机位返回 false
	var top := SeatLayout.TABLE_TOP
	rig.fill_light.light_energy = 0.0
	rig.camera.fov = CameraRig.DEFAULT_FOV
	match view:
		"seat":
			rig.snap(Vector3(TableWorld.THIRD_PERSON_SIDE, TableWorld.THIRD_PERSON_HEIGHT,
				SeatLayout.SEAT_RADIUS + TableWorld.THIRD_PERSON_BEHIND),
				Vector3(0, top, -0.12))
			rig.fill_light.light_energy = TableWorld.SEAT_FILL_LIGHT
		"selfshot":
			rig.snap(Vector3(-0.35, 1.42, 0.15), Vector3(0, 1.19, 1.37))
		"gun":
			rig.snap(Vector3(0.1, 1.42, 0.3), Vector3(1.25, 1.25, 0.0))
		"menu":
			rig.snap(Vector3(2.6, 2.1, 2.9), Vector3(-0.4, 0.9, -0.8))
		"overhead":
			rig.snap(Vector3(0, 2.6, 1.6), Vector3(0, top, 0))
		"fireplace":
			rig.snap(Vector3(0.5, 1.4, -1.5), Vector3(-1.5, 0.8, -4.4))
		"bar":
			rig.snap(Vector3(0.5, 1.5, 0.8), Vector3(-4.0, 1.4, -0.6))
		"window":
			rig.snap(Vector3(-1.5, 1.5, 1.5), Vector3(4.4, 1.5, -0.9))
		"closeup":
			rig.snap(Vector3(0.0, 1.05, 0.55), Vector3(0, top, -0.2))
		"opponent":
			rig.snap(Vector3(0, 1.3, 0.2), Vector3(0, 1.1, -1.25))
		# 开发机位(道具特写,不进 NAMES,探针不跑)
		"gunrest":
			rig.snap(Vector3(0.62, 1.0, 1.02), Vector3(0.3, top, 0.74))
		"fan":
			rig.snap(Vector3(0.66, 1.56, 2.08), Vector3(0.45, 1.33, 1.5))
		"candles":
			rig.snap(Vector3(-0.16, 1.06, -0.08), Vector3(-0.48, top + 0.06, -0.51))
		"stand":
			rig.snap(Vector3(0.05, 0.98, 0.36), Vector3(0, top + 0.1, 0))
		"lamp":
			rig.snap(Vector3(0.9, 1.55, 1.25), Vector3(0, 1.95, 0))
		"reveal":
			rig.snap(Vector3(0, 1.42, 1.05), Vector3(0, 0.86, 0.0))
		"table":
			rig.snap(Vector3(1.9, 1.15, 1.9), Vector3(0, 0.55, 0))
		"gunclose", "flashclose":
			rig.snap(Vector3(0.78, 1.42, -0.62), Vector3(1.22, 1.33, -0.3))
		"flash":
			rig.snap(Vector3(0.1, 1.42, 0.3), Vector3(1.25, 1.25, 0.0))
		# --lineup:8 个物种一字排开在 x ∈ [-2.73, 2.73]、z = 1.5,面朝 +Z;
		# 正面机位要留在前墙(z = 4.5)里面,66° 竖直视角在 16:9 下 2.8 m 外横向能看到 6.4 m
		"lineup_front":
			rig.snap(Vector3(0, 1.3, 4.3), Vector3(0, 0.85, 1.5))
		"lineup_back":
			rig.snap(Vector3(0, 1.4, -2.0), Vector3(0, 0.8, 1.5))
		"lineup_heads":
			rig.camera.fov = 62.0
			rig.snap(Vector3(0, 1.42, 4.3), Vector3(0, 1.38, 1.5))
		"lineup_left":
			rig.snap(Vector3(-1.56, 1.35, 3.1), Vector3(-1.56, 1.0, 1.5))
		"lineup_right":
			rig.snap(Vector3(1.56, 1.35, 3.1), Vector3(1.56, 1.0, 1.5))
		"door":
			rig.snap(Vector3(0.9, 1.55, 1.0), Vector3(-0.35, 1.25, 4.4))
		"corner":
			rig.snap(Vector3(1.0, 1.6, -0.6), Vector3(3.7, 0.55, -3.5))
		"corner_front":
			rig.snap(Vector3(0.8, 1.7, 1.2), Vector3(3.5, 0.7, 3.9))
		_:
			if not FOCUS.has(view):
				return false
			var angle := deg_to_rad(FOCUS[view])
			var dir := SeatLayout.direction(angle)
			var head := dir * (SeatLayout.SEAT_RADIUS + 0.10) + Vector3(0, 1.27, 0)
			var pos := dir * 0.15 + Vector3(0, 1.42, 0) - Vector3.UP.cross(dir) * 0.35
			rig.snap(pos, head + Vector3(0, -0.08, 0))
	return true
