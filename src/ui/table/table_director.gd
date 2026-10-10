class_name TableDirector
extends Node
# 演出导演:把网络事件翻译成镜头、角色动作、卡牌动画、音效与 HUD 宣告。
# 每段演出时长须不超过 Pacing 中的预算(房主据此延长回合计时)。


signal event_started(ev: Dictionary)   # 每段演出开始时发出(调试截图按演出节点取景)

const BUBBLE_KEY := "bubble:%d"   # WorldLabels 里他人对话气泡的键
const BUBBLE_ABOVE_PLATE := -66.0  # 他人气泡挂在铭牌正上方(屏幕像素),不压住名字
const SEAT_RETURN := 0.45          # 新一局前镜头回座的时长(强制验证为真话时没有开枪段)
const SPECTATOR_SEAT_FACTOR := 1.6 # 观战者回俯视机位要走更远,时长按此倍数
const INTRO_MOVE := Pacing.INTRO - 0.1   # 开局运镜到座位机位(越肩或第一人称)的时长(须在房主给的开场预算之内)

var screen: Node        # TableScreen
var app: Node
var world: TableWorld
var cards: CardTable
var rig: CameraRig
var fx: PostFx
var hud: TableHud
var spectator := false
var seat_camera: SeatCamera   # 座位上的镜头:越肩 / 第一人称(V 切换)
var _at_seat := false


func _init(p_screen: Node, p_app: Node, p_hud: TableHud) -> void:
	screen = p_screen
	app = p_app
	hud = p_hud
	world = app.world
	cards = world.cards
	rig = app.tavern.camera_rig
	fx = app.post_fx
	var path = app.get("settings_path")
	seat_camera = SeatCamera.new(rig, world, screen.my_pid, path if path is String else Settings.PATH)
	add_child(seat_camera)


func intro() -> void:
	rig.parallax_enabled = false
	Sfx.play("whoosh")
	await seat_camera.enter(INTRO_MOVE).finished
	rig.parallax_enabled = true
	_at_seat = true


func play(ev: Dictionary) -> void:
	event_started.emit(ev)
	match ev["type"]:
		"round_started":
			await _round_started(ev)
		"played":
			await _played(ev)
		"turn":
			screen.set_current(ev["pid"])
		"reveal":
			await _reveal(ev)
		"gunshot":
			await _gunshot(ev)
		"eliminated":
			await _eliminated(ev)
		"match_over":
			await _match_over(ev)


# —— 新一局 ——

func _round_started(ev: Dictionary) -> void:
	screen.set_current(null)
	screen.begin_round(ev["round"])
	if not _at_seat:
		# 强制验证为真话时没有开枪段,镜头还停在翻牌机位
		await back_to_seat(SEAT_RETURN)
	hud.set_target(ev["target"], ev["round"])
	await cards.sweep()
	hud.announce("第 %d 局" % ev["round"], UiTheme.BRASS_BRIGHT, "目标牌 ·「%s」" % Card.NAMES[ev["target"]], 0.9)
	hud.log_event("—— 第 %d 局 · 目标「%s」——" % [ev["round"], Card.NAMES[ev["target"]]], UiTheme.BRASS)
	await cards.set_target(ev["target"])
	var order: Array = screen.alive_order()
	var counts := {}
	for pid in order:
		counts[pid] = Deck.HAND_SIZE
	var my_hand: Array = []
	if order.has(screen.my_pid):
		my_hand = await screen.initial_hand(ev["round"])
	world.look_all_at(cards.stand_position())
	await cards.deal(order, counts, my_hand)
	screen.set_current(ev["starter"])


# —— 出牌 ——

func _played(ev: Dictionary) -> void:
	var pid: int = ev["pid"]
	var claim := "%d 张「%s」" % [ev["count"], Card.NAMES.get(cards.target_kind, "?")]
	if world.patrons.has(pid):
		world.patrons[pid].reach_toward_center()
	_bubble(pid, claim)
	hud.log_event("%s 打出 %s" % [screen.name_of(pid), claim])
	world.look_all_at(cards.stand_position())
	await cards.play(pid, ev["count"], screen.take_submitted() if pid == screen.my_pid else [])


# —— 质疑翻牌 ——

func _reveal(ev: Dictionary) -> void:
	screen.set_current(null)
	var liar: int = ev["pid"]
	var challenger = ev["challenger"]
	var kinds: Array = ev["cards"]
	if challenger == null:
		Sfx.play("bell")
		hud.announce("强制验证", UiTheme.BRASS_BRIGHT, "只剩 %s 有手牌,系统直接翻牌" % screen.name_of(liar), 0.8)
		hud.log_event("只剩 %s 有手牌,强制翻牌" % screen.name_of(liar), UiTheme.BRASS)
		await _wait(0.5)
	else:
		hud.log_event("%s 质疑 %s!" % [screen.name_of(challenger), screen.name_of(liar)], UiTheme.LIE)
		_bubble(challenger, "骗子!", UiTheme.BLOOD)
		world.look_all_at(world.head_position(challenger))
		if world.patrons.has(challenger):
			await world.patrons[challenger].slam_table()
		Sfx.play("slam")
		_startle_all(challenger)   # 拍桌一声,其他人吓一跳
		rig.shake(0.45)
		app.tavern.kick_lamp(0.07)
	_leave_seat()
	rig.move_to(world.reveal_view(liar), 0.55)
	await cards.gather_for_reveal(kinds.size())
	world.look_all_at(Vector3(0, SeatLayout.TABLE_TOP, CardTable.REVEAL_Z))
	for i in kinds.size():
		var matches := Card.matches(kinds[i], ev["target"])
		await cards.flip_revealed(i, kinds[i], matches)
		await _wait(0.4)
	if ev["honest"]:
		Sfx.play("sting_truth")
		hud.announce("没说谎!", UiTheme.TRUTH, "%s 句句属实" % screen.name_of(liar), 0.7)
	else:
		Sfx.play("sting_lie")
		hud.announce("骗子!", UiTheme.LIE, "%s 在撒谎" % screen.name_of(liar), 0.7)
		if world.patrons.has(liar):
			world.patrons[liar].startle()   # 被抓包:一蹦、眼睛瞪圆
			world.patrons[liar].set_expression("worried")
	await _wait(0.6)


# —— 开枪 ——

func _gunshot(ev: Dictionary) -> void:
	var shooter: int = ev["pid"]
	hud.log_event("%s 对自己扣下扳机(第 %d 枪)" % [screen.name_of(shooter), ev["shots_fired"]], UiTheme.PARCHMENT_DIM)
	hud.hide_announce()
	fx.set_tension(0.55, 0.8)
	await _third_person_shot(shooter, ev["hit"])
	if shooter == screen.my_pid and ev["hit"]:
		# 自己中弹:画面短暂染红,之后以俯视镜头观战
		spectator = true
		await fx.fade_to(Color(0.25, 0.0, 0.0, 0.6), 0.45)
		fx.flash(Color(0.25, 0.0, 0.0, 0.6), 1.0)
	fx.set_tension(0.0, 0.7)
	screen.on_gunshot_resolved(shooter, ev["shots_fired"], ev["hit"])
	await back_to_seat(0.55)


func _third_person_shot(shooter: int, hit: bool) -> void:
	# 所有人(包括自己)都用同一套演出:镜头转到开枪者正面,角色拿枪抵住太阳穴
	_leave_seat()
	rig.move_to(world.focus_view(shooter), 0.7)
	world.look_all_at(world.head_position(shooter))
	var patron: Patron = world.patrons.get(shooter)
	var gun: Revolver3D = world.revolvers.get(shooter)
	if patron == null or gun == null:
		await _wait(1.5)
		_announce_shot(shooter, hit)
		return
	await patron.pick_up(gun, 0.28)
	Sfx.play("cock")
	gun.cock_hammer()
	await patron.raise_gun_to_head(gun, 0.42)
	await _suspense(gun)
	gun.release_hammer()
	if hit:
		_bang(gun.muzzle_transform())
		gun.recoil()
		patron.die(gun, world)
		_startle_all(shooter)   # 枪响,其他人吓一跳
		_announce_shot(shooter, true)
		await _wait(1.0)
	else:
		Sfx.play("click")
		rig.shake(0.12)
		_announce_shot(shooter, false)
		patron.relief()
		await _wait(0.35)
		await patron.lower_gun(gun, world.revolver_rest(shooter), world, 0.3)


func _suspense(gun: Revolver3D) -> void:
	# 转轮 + 心跳 + 暗角收紧:整段约 1.4 秒
	Sfx.play("spin")
	gun.spin_drum(0.85, 2.0 + randf())
	fx.set_tension(1.0, 1.0)
	Sfx.play("heartbeat", 0.0)
	await _wait(0.72)
	Sfx.play("heartbeat", 0.0)
	fx.pulse_aberration(1.6, 0.4)
	await _wait(0.68)


func _bang(muzzle: Transform3D) -> void:
	Sfx.play("bang", 0.02)
	Fx.muzzle_flash(world, muzzle)
	Fx.smoke_puff(world, muzzle.origin, 22)
	fx.flash(Color(1.0, 0.85, 0.7, 0.75), 0.3)
	rig.shake(0.95)
	app.tavern.kick_lamp(0.14)


func _announce_shot(pid: int, hit: bool) -> void:
	var mine: bool = pid == screen.my_pid
	if hit:
		hud.announce("砰!", UiTheme.BLOOD, "你中弹了……" if mine else "%s 倒下了" % screen.name_of(pid), 1.0,
			TableHud.ANNOUNCE_Y_LOW)
		hud.log_event("砰!%s 出局" % screen.name_of(pid), UiTheme.BLOOD)
	else:
		hud.announce("咔哒……", UiTheme.PARCHMENT, "空枪!你活下来了" if mine else "空枪!%s 逃过一劫" % screen.name_of(pid), 0.8,
			TableHud.ANNOUNCE_Y_LOW)
		hud.log_event("咔哒,%s 是空枪" % screen.name_of(pid), UiTheme.PARCHMENT_DIM)


# —— 出局 / 结束 ——

func _eliminated(ev: Dictionary) -> void:
	var pid: int = ev["pid"]
	if screen.is_marked_dead(pid):
		return
	screen.mark_eliminated(pid)
	hud.log_event("%s 离开了牌桌(断线出局)" % screen.name_of(pid), UiTheme.LIE)
	_bubble(pid, "……")
	cards.drop_held(pid)
	if world.patrons.has(pid):
		world.patrons[pid].die()
	Sfx.play("thud")
	await _wait(0.8)


func _match_over(ev: Dictionary) -> void:
	screen.set_current(null)
	var winner = ev["winner"]
	fx.set_tension(0.0, 0.6)
	_leave_seat()
	var title := "你赢了!" if winner == screen.my_pid else "%s 赢了" % screen.name_of(winner)
	hud.announce(title, UiTheme.BRASS_BRIGHT, "活到了最后", 1.8, TableHud.ANNOUNCE_Y_LOW)
	# 结算庆祝(规格 2026-10-09):胜者跳舞、其他人鼓掌、礼炮彩纸,开场小号与掌声由庆祝发出(代替原来的 win 铃声)
	world.celebrate([winner], hash(["liars", winner, screen.get("_round_now")]))
	# 从胜者面朝牌桌的一侧开始环绕(自己赢时镜头原本在背后),给一点补光看清表情;胜者让到画面左边,右边放结算面板。
	# 胜者不在桌上时整桌环绕
	_orbit(world.celebration_orbit([winner]))
	hud.log_event("胜者:%s" % screen.name_of(winner), UiTheme.BRASS_BRIGHT)
	await _wait(2.2)
	screen.show_settlement(winner)


# —— 工具 ——

func _orbit(focus: Dictionary) -> void:
	rig.set_fill(focus.get("fill", 0.0), 1.0)
	rig.orbit(focus["center"], focus["radius"], focus["height"], focus["speed"], 1.4, focus.get("start", NAN), focus.get("frame", 0.0))


func _startle_all(except_pid) -> void:
	# 桌上其他人吓一跳(Q 版搞笑表演);死了的不动
	for pid in world.patrons:
		if pid != except_pid and is_instance_valid(world.patrons[pid]):
			world.patrons[pid].startle()


func toggle_camera_mode() -> void:
	# V:越肩 ⇄ 第一人称(存进设置)。镜头在座位上就马上切过去,拍特写或观战时等回座再生效
	var on := seat_camera.toggle()
	app.toast(SeatCamera.toast_text(on, seat_camera.is_seated()), UiTheme.PARCHMENT)


func is_at_seat() -> bool:
	# 镜头在自己座位的常驻机位(越肩或第一人称;不是特写、不是观战)
	return _at_seat and not spectator


func is_camera_at_rest() -> bool:
	# 镜头停在常驻机位(越肩或观战俯视),没在拍特写
	return _at_seat


func back_to_seat(duration: float) -> void:
	_at_seat = true
	if spectator:
		await rig.move_to(world.overview_view(), duration * SPECTATOR_SEAT_FACTOR).finished
		hud.set_away_from_seat(false)
		return
	await seat_camera.enter(duration).finished
	# 镜头回到座位后再露出按钮行,免得特写还没切走就挡住角色
	hud.set_away_from_seat(false)
	rig.parallax_enabled = true


func _leave_seat() -> void:
	_at_seat = false
	# 收起自己的气泡:按钮行一藏,气泡会掉到翻牌行正上方,盖住刚翻开的牌
	hud.clear_my_bubble()
	hud.set_away_from_seat(true)
	rig.parallax_enabled = false
	seat_camera.leave(0.5)


func _bubble(pid: int, text: String, color := UiTheme.INK) -> void:
	if pid == screen.my_pid:
		# 越肩镜头在自己头顶正上方,挂在自己头顶的气泡永远出画:改由 HUD 在出牌按钮上方显示
		hud.my_bubble(text, color)
		return
	if not world.patrons.has(pid):
		return
	var patron: Patron = world.patrons[pid]
	app.labels.track(BUBBLE_KEY % pid, SpeechBubble.new(text, color),
		func(): return patron.nameplate_anchor() if is_instance_valid(patron) else Vector3.ZERO,
		Vector2(0, BUBBLE_ABOVE_PLATE), true)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
