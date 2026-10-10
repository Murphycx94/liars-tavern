class_name LiarsDiceDirector
extends Node
# 吹牛骰子演出导演(设计稿 §3):把阶段一的公共事件(设计稿 §6.3)翻译成镜头、酒客动作、骰盅与骰子的动画(LiarsDiceCups)、
# 特效(LiarsDiceFx)、音效、宣告与日志。每段演出的实际时长不超过 LiarsDicePacing 的预算(房主据此延长计时),
# 由 test_liars_dice_director 读这里与 LiarsDiceCups / LiarsDiceFx 的节奏常量来保证。
# 常驻机位两种:自己座位(越肩 / 第一人称,V 切换,共用 SeatCamera)与出局后的观战俯视;
# 第一人称偷看时视线压低凑到盅沿(MODE_PEEK,马上回座);胜利时环绕胜者。
# 自己的点数从私有视图来(按轮次缓存,演到 round_started 才换上);开盅一律用 revealed 事件里的点数;别人的点数开盅前不碰。


signal event_started(ev: Dictionary)   # 每段演出开始时发出(调试截图与 bot 日志按它取景)

const INTRO_MOVE := LiarsDicePacing.INTRO - 0.1
const CAMERA_MOVE := 0.8
const PRIVATE_WAIT := 0.1             # 演到 round_started 时最多再等私有骰子这么久(通常同一帧就到了;和摇盅同时等,不额外占时间)
const ROUND_TAIL := 0.05
const PEEK_DIP := 0.16                # 第一人称:视线压下去 / 回来
const BID_HOLD := 0.72                # 喊价:气泡、桌心大骰子弹出来之后停一下
const SLAM_AT := 0.28                 # 「开!」:拍桌的手砸到桌面(Patron.slam_table 0.2 + 0.08)
const CHALLENGE_HOLD := 0.78
const REVEAL_OPEN := LiarsDiceCups.LIFT_TIME * 0.55 + LiarsDiceCups.SPREAD_TIME   # 骰盅掀起、骰子排开
const REVEAL_SETTLE := 0.1
const COUNT_STEP := 0.2               # 计数:每颗算进去的骰子跳一下(≤ LiarsDicePacing.REVEAL_PER_MATCH,含一帧余量)
const VERDICT_HOLD := 0.78            # 真话 / 吹牛判定
const DIE_LOST_HOLD := LiarsDiceCups.POP_TIME + 0.25
const OUT_HOLD := 1.35                # 出局:蚊香眼、星星、骰盅歪倒
const LEFT_PAUSE := 0.7
const MATCH_HOLD := 2.2
const TABLE_FOCUS := LiarsDiceLayout.TABLE_FOCUS
const BUBBLE_KEY := "bubble:%d"
const BUBBLE_ABOVE_PLATE := -82.0
const MODE_SEAT := "seat"
const MODE_OVERVIEW := "overview"
const MODE_PEEK := "peek"
const MODE_ORBIT := "orbit"
# 导演认得的公共事件(设计稿 §6.3 全部 9 种;测试核对与 LiarsDicePacing 一一对应)
const HANDLED_EVENTS := ["round_started", "bid", "turn_passed", "challenged", "revealed", "die_lost", "player_out",
	"player_left", "match_over"]

var screen: Node        # LiarsDiceScreen
var app: Node
var world: TableWorld
var cups: LiarsDiceCups
var fx3d: LiarsDiceFx
var rig: CameraRig
var fx: PostFx
var hud: LiarsDiceHud
var seat_camera: SeatCamera
var spectator := false
var _mode := ""
var _settled := false
var _camera_serial := 0
var _challenge := {}            # 最近一次「开!」(判定后的表情要知道谁开谁)


func _init(p_screen: Node, p_app: Node, p_hud: LiarsDiceHud) -> void:
	screen = p_screen
	app = p_app
	hud = p_hud
	world = p_screen.world
	cups = p_screen.cups
	fx3d = p_screen.fx3d
	rig = app.tavern.camera_rig
	fx = app.get("post_fx")
	var path = app.get("settings_path")
	seat_camera = SeatCamera.new(rig, world, screen.my_pid, path if path is String else Settings.PATH)
	add_child(seat_camera)


# —— 纯逻辑 ——

static func bid_log(ev: Dictionary, names: Callable) -> String:
	# 日志:「阿狸 喊 3 个 5」「阿狸 喊 3 个 5(超时代喊)」
	var text := "%s 喊 %s" % [names.call(ev.get("pid")), LiarsDiceScreenState.bid_text(ev.get("count", "?"), ev.get("face", "?"))]
	if ev.get("auto") is bool and ev["auto"]:
		text += "(超时代喊)"
	return text


static func challenge_log(ev: Dictionary, names: Callable) -> String:
	var text := "%s 开 %s 的「%s」" % [names.call(ev.get("pid")), names.call(ev.get("target")),
		LiarsDiceScreenState.bid_text(ev.get("count", "?"), ev.get("face", "?"))]
	if ev.get("auto") is bool and ev["auto"]:
		text += "(超时代开)"
	return text


static func loser_of(challenge: Dictionary, truthful: bool) -> Variant:
	# 真话:开的人输;吹牛:喊的人输
	return challenge.get("pid") if truthful else challenge.get("target")


static func reveal_duration(actual: int) -> float:
	# 开盅这一段的实际时长(测试核对预算用)
	return REVEAL_OPEN + REVEAL_SETTLE + COUNT_STEP * clampi(actual, 0, LiarsDicePacing.REVEAL_MATCH_CAP) + VERDICT_HOLD


# —— 入口 ——

func intro() -> void:
	Sfx.play("whoosh")
	await settle_camera(INTRO_MOVE)


func play(ev: Dictionary) -> void:
	event_started.emit(ev)
	match ev.get("type", ""):
		"round_started":
			await _round_started(ev)
		"bid":
			await _bid(ev)
		"turn_passed":
			_turn_passed(ev)
		"challenged":
			await _challenged(ev)
		"revealed":
			await _revealed(ev)
		"die_lost":
			await _die_lost(ev)
		"player_out":
			await _player_out(ev)
		"player_left":
			await _player_left(ev)
		"match_over":
			await _match_over(ev)


# —— 新一轮:收骰子、摇盅、扣下、偷看 ——

func _round_started(ev: Dictionary) -> void:
	screen.set_current(null)
	screen.note_event(ev)
	fx3d.clear_bid_marker()
	cups.unglow_all()
	hud.hide_reveal()
	var round_no := _int(ev, "round")
	var shakers: Array = []
	for row in (ev["counts"] if ev.get("counts") is Array else []):
		if row is Dictionary and row.get("pid") is int and _int(row, "count") > 0:
			shakers.append(row["pid"])
	if round_no <= 1:
		hud.announce("吹牛骰子", UiTheme.BRASS_BRIGHT, "每人 %d 颗骰子 · 1 点万能 · 喊大一点,或者「开!」" % LiarsDiceState.DICE_PER_PLAYER, 1.0)
	hud.log_event("—— 第 %d 轮 · 场上 %d 颗骰子 ——" % [round_no, _int(ev, "total")], UiTheme.BRASS)
	world.look_all_at(TABLE_FOCUS)
	# 上一轮开盅排开的骰子蹦回各自的盅
	if _dice_on_table():
		cups.gather(cups.cups.keys())
		await _wait(LiarsDiceCups.GATHER_TIME)
	# 全员捧起骰盅哗啦哗啦摇、扣下;摇的同时等自己这一轮的私有骰子
	for pid in shakers:
		if world.patrons.has(pid) and world.patrons[pid].alive:
			world.patrons[pid].look_at_point(world.to_global(LiarsDiceLayout.shake_global(world.seat_transform(world.seat_angle_now(pid)))))
	cups.shake(shakers)
	var started := Time.get_ticks_msec()
	var mine: Array = await screen.wait_round_dice(round_no, PRIVATE_WAIT)
	var waited := (Time.get_ticks_msec() - started) / 1000.0 * Engine.time_scale
	await _wait(maxf(LiarsDiceCups.SHAKE_TOTAL - waited, 0.0))
	if shakers.has(screen.my_pid):
		rig.shake(0.12)
	cups.set_my_dice(mine)
	screen.refresh_my_dice(true)
	# 偷看:每人掀开自己的盅沿瞄一眼、捂嘴偷乐(别人只看到他偷瞄);第一人称时自己的视线压低凑过去
	for pid in shakers:
		cups.peek(pid)
		if world.patrons.has(pid) and world.patrons[pid].alive:
			var patron: Patron = world.patrons[pid]
			patron.look_at_point(world.to_global(cups.rest_of(pid).origin))
			if pid != screen.my_pid or not seat_camera.first_person:
				patron.cover_mouth(LiarsDiceCups.PEEK_HOLD + 0.1)
	var dipped := false
	if shakers.has(screen.my_pid) and seat_camera.first_person and _mode == MODE_SEAT and _settled:
		dipped = true
		_leave_rest(MODE_PEEK, false)
		rig.move_to(LiarsDiceLayout.peek_view(world, screen.my_pid), PEEK_DIP)
	await _wait(LiarsDiceCups.PEEK_TOTAL)
	if dipped:
		settle_camera(PEEK_DIP)
	world.look_all_at(TABLE_FOCUS)
	await _wait(ROUND_TAIL)
	screen.set_current(ev.get("starter"))


func _dice_on_table() -> bool:
	for pid in cups.dice:
		if not cups.dice[pid].is_empty() and cups.state_of(pid) == LiarsDiceCups.STATE_OPEN:
			return true
	return false


# —— 喊价 ——

func _bid(ev: Dictionary) -> void:
	var pid: Variant = ev.get("pid")
	screen.set_current(null)
	screen.note_event(ev)
	var text := LiarsDiceScreenState.bid_text(ev.get("count", "?"), ev.get("face", "?"))
	_bubble(pid, text)
	hud.log_event(bid_log(ev, screen.name_of), UiTheme.PARCHMENT)
	if pid is int and world.patrons.has(pid):
		world.patrons[pid].reach_toward_center()
		if world.patrons[pid].alive:
			world.patrons[pid].set_expression("smug" if _int(ev, "count") * 3 > screen.state.total * 2 else "neutral")
	if ev.get("count") is int and ev.get("face") is int:
		fx3d.bid_marker(ev["count"], ev["face"])
	Sfx.play("pop")
	_look_all(world.to_global(LiarsDiceLayout.marker_position()))
	await _wait(BID_HOLD)


# —— 轮转 ——

func _turn_passed(ev: Dictionary) -> void:
	var pid: Variant = ev.get("pid")
	screen.note_event(ev)
	screen.set_current(pid)
	screen.pulse_nameplate(pid)


# —— 开! ——

func _challenged(ev: Dictionary) -> void:
	var pid: Variant = ev.get("pid")
	var target: Variant = ev.get("target")
	_challenge = ev.duplicate()
	screen.note_event(ev)
	screen.set_current(null)
	_bubble(pid, "开!", UiTheme.BLOOD)
	hud.log_event(challenge_log(ev, screen.name_of), UiTheme.LIE)
	var who: String = "你" if pid == screen.my_pid else screen.name_of(pid)
	hud.announce("开!", UiTheme.LIE, "%s 不信 %s 的「%s」" % [who, "你" if target == screen.my_pid else screen.name_of(target),
		LiarsDiceScreenState.bid_text(ev.get("count", "?"), ev.get("face", "?"))], 0.7)
	if pid is int and world.patrons.has(pid):
		world.patrons[pid].slam_table()
	if target is int and world.patrons.has(target):
		_look_all(world.head_position(target))
	await _wait(SLAM_AT)
	fx3d.open_burst()
	rig.shake(0.4)
	app.tavern.kick_lamp(0.06)
	_startle_all(pid)
	if target is int and world.patrons.has(target) and world.patrons[target].alive:
		world.patrons[target].set_expression("worried")
	await _wait(CHALLENGE_HOLD)


func _revealed(ev: Dictionary) -> void:
	screen.note_event(ev)
	var rows: Array = ev["dice"] if ev.get("dice") is Array else []
	var face := _int(ev, "face")
	var target := _int(ev, "count")
	var truthful: bool = ev.get("truthful") is bool and ev["truthful"]
	cups.reveal(rows)
	world.look_all_at(TABLE_FOCUS)
	await _wait(REVEAL_OPEN + REVEAL_SETTLE)
	# 点数等于 X 的骰子和 1 点逐个高亮跳一下,桌心计数器一路数上去(自己的 2D 骰子同时标出算进去的)
	screen.show_reveal_dice(face)
	fx3d.set_counter(0, target)
	var order: Array = rows.filter(func(r): return r is Dictionary and r.get("pid") is int).map(func(r): return r["pid"])
	hud.show_reveal(rows.filter(func(r): return r is Dictionary and r.get("pid") is int).map(func(r: Dictionary) -> Dictionary:
		return {"name": "你" if r["pid"] == screen.my_pid else screen.name_of(r["pid"]),
			"dice": LiarsDiceScreenState.sanitize_dice(r.get("dice"))}), face, target)
	var n := 0
	for item in LiarsDiceScreenState.count_order(rows, face).slice(0, LiarsDicePacing.REVEAL_MATCH_CAP):
		n += 1
		var pos := cups.hop(item[0], item[1])
		fx3d.counted(pos)
		fx3d.set_counter(n, target)
		hud.reveal_mark(order.find(item[0]), item[1])
		hud.set_reveal_count(n, target)
		await _wait(COUNT_STEP)
	hud.reveal_finish(truthful)
	# 判定:真话(喊的人得意、开的人傻眼)或吹牛(反过来)
	fx3d.verdict(truthful)
	hud.announce("真话!" if truthful else "吹牛!", UiTheme.TRUTH if truthful else UiTheme.LIE, LiarsDiceScreenState.verdict_text(ev), 0.7,
		LiarsDiceHud.ANNOUNCE_Y_LOW)
	hud.log_event(("真话!" if truthful else "吹牛!") + LiarsDiceScreenState.verdict_text(ev), UiTheme.TRUTH if truthful else UiTheme.LIE)
	var bidder: Variant = _challenge.get("target")
	var challenger: Variant = _challenge.get("pid")
	_react(bidder if truthful else challenger, true)
	_react(challenger if truthful else bidder, false)
	await _wait(VERDICT_HOLD)


func _react(pid: Variant, won: bool) -> void:
	if not pid is int or not world.patrons.has(pid) or not world.patrons[pid].alive:
		return
	var patron: Patron = world.patrons[pid]
	if won:
		patron.set_expression("smug")
		patron.cover_mouth(0.5)
	else:
		patron.startle()
		patron.set_expression("worried")


# —— 丢骰子、出局、断线 ——

func _die_lost(ev: Dictionary) -> void:
	var pid: Variant = ev.get("pid")
	screen.note_event(ev)
	var left := _int(ev, "left")
	hud.log_event("%s 丢了一颗骰子(还剩 %d 颗)" % [screen.name_of(pid), left], UiTheme.LIE)
	if pid is int:
		var pos := cups.pop_die(pid)
		fx3d.die_popped(pos)
		if world.patrons.has(pid) and world.patrons[pid].alive:
			world.patrons[pid].bonk()
			world.patrons[pid].set_expression("worried")
	if pid == screen.my_pid:
		screen.drop_my_die()
		if left > 0:
			hud.announce("啵!", UiTheme.LIE, "你丢了一颗骰子 · 还剩 %d 颗" % left, 0.5, LiarsDiceHud.ANNOUNCE_Y_LOW)
	await _wait(DIE_LOST_HOLD)


func _player_out(ev: Dictionary) -> void:
	var pid: Variant = ev.get("pid")
	var mine: bool = pid == screen.my_pid
	screen.note_event(ev)
	hud.log_event("%s 的骰子输光了,出局" % screen.name_of(pid), UiTheme.BLOOD)
	hud.announce("出局!", UiTheme.BLOOD, "你的骰子输光了……" if mine else "%s 的骰子输光了" % screen.name_of(pid), 0.9,
		LiarsDiceHud.ANNOUNCE_Y_LOW)
	Sfx.play("thud")
	if pid is int:
		screen.mark_out(pid)
		cups.tip(pid)
		cups.clear_dice(pid)
		if world.patrons.has(pid):
			world.patrons[pid].die()   # 蚊香眼转几圈定格成 ×、头顶一圈小星星(PatronAntics)
			_look_all(world.head_position(pid))
	_startle_all(pid)
	await _wait(OUT_HOLD)
	if mine:
		spectator = true
		settle_camera(CAMERA_MOVE)


func _player_left(ev: Dictionary) -> void:
	var pid: Variant = ev.get("pid")
	screen.note_event(ev)
	hud.log_event("%s 离开了牌桌(断线出局),这一轮作废、重摇" % screen.name_of(pid), UiTheme.LIE)
	_bubble(pid, "……")
	if pid is int:
		screen.mark_out(pid)
		cups.tip(pid)
		cups.clear_dice(pid)
		if world.patrons.has(pid):
			world.patrons[pid].die()
	fx3d.clear_bid_marker()
	if pid == screen.my_pid:
		spectator = true
		settle_camera(CAMERA_MOVE)
	Sfx.play("thud")
	await _wait(LEFT_PAUSE)


func _match_over(ev: Dictionary) -> void:
	screen.note_event(ev)
	hud.hide_reveal()
	screen.set_current(null)
	fx3d.clear_bid_marker()
	var winner: Variant = ev.get("winner")
	if fx != null:
		fx.set_tension(0.0, 0.6)
	_leave_rest(MODE_ORBIT)
	var title := "你赢了!" if winner == screen.my_pid else "%s 赢了" % screen.name_of(winner)
	hud.announce(title, UiTheme.BRASS_BRIGHT, "骰子留到了最后", 1.8, LiarsDiceHud.ANNOUNCE_Y_LOW)
	# 结算庆祝:胜者跳舞、活着的人鼓掌、出局的倒着抽手、礼炮彩纸;开场小号与掌声由庆祝发出
	world.celebrate([winner] if winner is int else [], hash(["liars_dice", winner, ev.get("ranking")]))
	var focus := world.celebration_orbit([winner] if winner is int else [])
	rig.set_fill(focus.get("fill", 0.0), 1.0)
	rig.orbit(focus["center"], focus["radius"], focus["height"], focus["speed"], 1.4, focus.get("start", NAN), focus.get("frame", 0.0))
	if winner is int and world.patrons.has(winner):
		_look_all(world.head_position(winner))
	hud.log_event("胜者:%s" % screen.name_of(winner), UiTheme.BRASS_BRIGHT)
	await _wait(MATCH_HOLD)
	screen.show_settlement()


# —— 机位 ——

func is_at_seat() -> bool:
	return _settled and _mode == MODE_SEAT


func is_camera_at_rest() -> bool:
	return _settled and (_mode == MODE_SEAT or _mode == MODE_OVERVIEW)


func camera_mode() -> String:
	return _mode


func wanted_mode() -> String:
	return MODE_OVERVIEW if spectator else MODE_SEAT


func settle_camera(duration := CAMERA_MOVE) -> void:
	# 回到常驻机位(座位或观战),已在那里就不动;协程,调用方可以等也可以不等
	var wanted := wanted_mode()
	if wanted == _mode and _settled:
		return
	_leave_rest(wanted)
	var serial := _camera_serial
	if wanted == MODE_SEAT:
		seat_camera.enter(duration)
	else:
		rig.set_fill(0.0, duration)
		rig.move_to(world.overview_view(), duration)
	await _wait(duration)
	if serial == _camera_serial:
		_settled = true
		rig.parallax_enabled = wanted == MODE_SEAT
		hud.set_away_from_seat(false)


func _leave_rest(mode: String, away := true) -> void:
	_mode = mode
	_settled = false
	_camera_serial += 1
	rig.parallax_enabled = false
	if mode != MODE_PEEK:
		seat_camera.leave()
	if mode == MODE_ORBIT and away:
		hud.clear_my_bubble()
		hud.set_away_from_seat(true)


func toggle_camera_mode() -> void:
	var on := seat_camera.toggle()
	app.toast(SeatCamera.toast_text(on, seat_camera.is_seated()), UiTheme.PARCHMENT)


# —— 酒客与工具 ——

func _startle_all(except_pid: Variant) -> void:
	for pid in world.patrons:
		if pid != except_pid and is_instance_valid(world.patrons[pid]):
			world.patrons[pid].startle()


func _look_all(point: Vector3) -> void:
	world.look_all_at(point)


func _bubble(pid: Variant, text: String, color := UiTheme.INK) -> void:
	if not pid is int:
		return
	if pid == screen.my_pid:
		hud.my_bubble(text, color)
		return
	if not world.patrons.has(pid):
		return
	var patron: Patron = world.patrons[pid]
	app.labels.track(BUBBLE_KEY % pid, SpeechBubble.new(text, color),
		func(): return patron.nameplate_anchor() if is_instance_valid(patron) else Vector3.ZERO,
		Vector2(0, BUBBLE_ABOVE_PLATE), true)


static func _int(ev: Dictionary, key: String) -> int:
	var v: Variant = ev.get(key, 0)
	return v if v is int else 0


func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout
