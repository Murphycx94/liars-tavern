class_name SeatCamera
extends Node
# 自己座位上的镜头(骗子酒馆与德州的牌桌共用):越肩(第三人称)或第一人称,V 切换,选择存进设置。
# 回座 enter():越肩 = 移到 TableWorld.third_person_view;第一人称 = CameraRig.follow 跟着自己的眼睛(探头时镜头跟着走)。
# 离座 leave():拍特写、观战前调用,视角与补光还原。
# 第一人称时自己的头只投影不渲染(Patron.set_head_hidden,只在本机):每帧看镜头是不是正在第一人称跟随、且已经到了眼睛附近,
# 拍特写、观战、换屏时头一律露出来;酒客重建(复活、换形象)也按每帧的判断重新处理。
# 不论视角,镜头钻进自己的头里(翻牌机位就在自己座位上方、开局运镜从后脑穿过去、探出去的头挡在特写前)时也藏头,
# 免得满屏是自己的胡须、耳朵和帽子里面。
# 离座时自己举着的牌扇收到桌面上空(Patron.set_fan_stowed),回座举回来;stow_fan_in_first_person 让第一人称时也收着。


signal mode_changed(first_person: bool)

const HEAD_CLEAR := 0.45   # 镜头离眼睛这么近才藏头:回座过渡刚开始时镜头还在远处,头照常看得见
const HEAD_INSIDE := 0.42  # 镜头离自己的头心这么近就算钻进头里(大头半径约 0.3,加上耳朵、帽檐与胡须),不论视角都藏头
const FP_COMFORT := 0.4    # 第一人称坐在座位上时自己的头在探头软碰撞里多算这么大一圈(Patron.guard_extra,只在本机)
const TOAST_FIRST := "第一人称视角"
const TOAST_THIRD := "越肩视角"
const TOGGLE_MOVE := 0.35  # 在座位上切换视角的过渡时长(秒)

var rig: CameraRig
var world: TableWorld
var my_pid := 0
var settings_path := Settings.PATH
var default_fov := CameraRig.DEFAULT_FOV
var first_person := false
var _seated := false        # enter() 之后、leave() 之前:镜头归座位
var _hidden: Patron = null  # 正藏着头的酒客
var _entering: Tween = null # 回座运镜;导演会 await 它,切换视角不能把它打断
# 第一人称时把自己的 3D 牌扇收起来(底部有 2D 手牌条当主要入口的玩法:斗地主),免得牌扇和手牌条叠在一起
var stow_fan_in_first_person := false


func _init(p_rig: CameraRig, p_world: TableWorld, p_my_pid: int, p_settings_path := Settings.PATH) -> void:
	rig = p_rig
	world = p_world
	my_pid = p_my_pid
	settings_path = p_settings_path
	first_person = Settings.first_person(settings_path)
	world.set_first_person(first_person)   # 手牌按存下的视角举好


func _process(_delta: float) -> void:
	update_head()


func _exit_tree() -> void:
	# 换屏:头露出来(等待厅里看得见自己),镜头停止跟随(跟随的回调属于本节点)
	_show_head()
	if is_instance_valid(rig):
		rig.stop_follow(_eye_target)


# —— 机位 ——

func enter(duration: float) -> Tween:
	# 回到自己的座位:按当前视角运镜、调补光与视角;返回运镜补间(可 await .finished)
	_seated = true
	if first_person:
		rig.set_fill(TableWorld.FIRST_PERSON_FILL, duration)
		rig.set_fov(TableWorld.FIRST_PERSON_FOV, duration)
		_entering = rig.follow(_eye_target, duration)
	else:
		rig.set_fill(TableWorld.SEAT_FILL_LIGHT, duration)
		rig.set_fov(default_fov, duration)
		_entering = rig.move_to(world.third_person_view(my_pid), duration)
	return _entering


func leave(fill_duration := 0.5) -> void:
	# 镜头要去拍特写或观战:视角、补光还原(特写按默认视角取景);跟随由接下来的 move_to / orbit 停掉
	_seated = false
	rig.set_fill(0.0, fill_duration)
	rig.set_fov(default_fov, fill_duration)


func is_seated() -> bool:
	return _seated


func toggle() -> bool:
	# V:换视角并存进设置;镜头在座位上就马上切过去(手牌跟着重摆),否则等下次回座生效。返回新视角是不是第一人称
	set_first_person(not first_person)
	return first_person


func set_first_person(on: bool, persist := true) -> void:
	# persist = false:只换本次(调试开关 --camera),不写设置
	first_person = on
	if persist:
		Settings.set_first_person(on, settings_path)
	world.set_first_person(on)
	mode_changed.emit(on)
	if _seated:
		_reenter()


func _reenter() -> void:
	# 回座运镜还在走(导演在等它结束):等它走完再切,免得补间被打断、导演的 await 永远等不到
	if _entering != null and _entering.is_valid() and _entering.is_running():
		await _entering.finished
	if _seated:
		enter(TOGGLE_MOVE)


static func toast_text(on: bool, seated: bool) -> String:
	return (TOAST_FIRST if on else TOAST_THIRD) + ("" if seated else "(回到座位后生效)")


func _eye_target() -> Transform3D:
	return world.first_person_view(my_pid)


# —— 藏头 ——

func update_head() -> void:
	# 「第一人称跟随中、镜头已到眼睛附近」或「镜头在自己头里」时藏头;其余一律露出
	var me: Patron = world.patrons.get(my_pid)
	var want := false
	if me != null and is_instance_valid(me) and me.alive:
		var fp_seated: bool = _seated and first_person and rig.is_following(_eye_target) \
			and rig.global_position.distance_to(me.eye_position()) < HEAD_CLEAR
		want = fp_seated or rig.global_position.distance_to(me.head_position()) < HEAD_INSIDE
	if _hidden != null and (not is_instance_valid(_hidden) or _hidden != me or not want):
		_show_head()
	if want and not me.is_head_hidden():
		me.set_head_hidden(true)
		_hidden = me
	# 镜头离开座位(特写、翻牌、观战)时自己举着的牌扇收到桌面上空,不挡镜头;回座再举起来。
	# 第一人称时自己的头在软碰撞里多算一圈,别人的头不贴到镜头上(穿模修复 2026-10-10)
	if me != null and is_instance_valid(me):
		me.set_fan_stowed(not _seated or (first_person and stow_fan_in_first_person))
		me.guard_extra = FP_COMFORT if _seated and first_person else 0.0


func _show_head() -> void:
	if _hidden != null and is_instance_valid(_hidden):
		_hidden.set_head_hidden(false)
	_hidden = null
