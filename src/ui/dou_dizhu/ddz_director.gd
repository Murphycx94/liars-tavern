class_name DdzDirector
extends Node
# 斗地主演出导演(设计稿 §3、§6.11):把阶段一的公共事件(§6.3)翻译成镜头、酒客动作、牌的动画(DdzCards)、
# 特效(DdzFx)、身份帽(DdzHats)、音效、宣告与日志。每段演出的实际时长不超过 DouDizhuPacing 的预算
# (房主据此延长计时),由 test_ddz_director 读这里与 DdzCards / DdzFx 的节奏常量来保证。
# 常驻机位只有自己的座位(越肩 / 第一人称,V 切换,共用 SeatCamera);散局时环绕第一名。
# 私有视图比演出先到:发牌 / 重发按「第几手 : 第几次发牌」的私有快照亮面;自己当地主时底牌直接并进手牌;
# 别人的牌扇永远是牌背,出牌、底牌、一手结束摊牌才翻成正面(id 都来自公共事件)。


signal event_started(ev: Dictionary)   # 每段演出开始时发出(调试截图与 bot 日志按它取景)

const INTRO_MOVE := DouDizhuPacing.INTRO - 0.15
const CAMERA_MOVE := 0.8
const FACES_WAIT_MAX := 10.0          # 第一次发牌前最多等牌面生成这么久(之后已缓存;等待厅里通常已生成完)
const PRIVATE_WAIT := 0.3             # 发牌前最多再等这一次发牌的私有手牌这么久(通常同一帧就到了)
const REDEAL_PRIVATE_WAIT := 0.1
const BID_HOLD := 0.45                # 叫分:头顶气泡
const LANDLORD_TAIL := 0.3            # 底牌进手之后再停一下(帽子刚戴好)
const PLAY_HOLD := 0.1                # 出牌:牌落到出牌行后再停一下
const PLANE_DELAY := 0.2              # 飞机:牌飞出去一会儿纸飞机再起飞
const PASS_HOLD := 0.3
const HAND_OVER_HOLD := 2.2           # 一手结束:摊牌之后宣告输赢、飘分、酒客表情
const LEFT_PAUSE := 0.6
const SESSION_OVER_HOLD := 2.4        # 散局:环绕镜头与宣告,之后弹结算面板
const TABLE_FOCUS := DdzLayout.TABLE_FOCUS
const BUBBLE_KEY := "bubble:%d"
const BUBBLE_ABOVE_PLATE := -66.0
const MODE_SEAT := "seat"
const MODE_ORBIT := "orbit"
# 导演认得的公共事件(§6.3 全部 13 种;测试核对与 DouDizhuPacing 一一对应)
const HANDLED_EVENTS := ["hand_started", "redeal", "turn", "bid", "landlord", "played", "passed", "trick_cleared", "trustee",
	"hand_over", "ending", "player_left", "session_over"]
const CHAIN_COMBOS := [DdzHand.STRAIGHT, DdzHand.PAIR_STRAIGHT]
const PLANE_COMBOS := [DdzHand.AIRPLANE, DdzHand.AIRPLANE_SINGLE, DdzHand.AIRPLANE_PAIR]

var screen: Node        # DouDizhuScreen
var app: Node
var world: TableWorld
var cards: DdzCards
var fx3d: DdzFx
var rig: CameraRig
var fx: PostFx
var hud: DdzHud
var seat_camera: SeatCamera
var _mode := ""
var _settled := false
var _camera_serial := 0


func _init(p_screen: Node, p_app: Node, p_hud: DdzHud) -> void:
	screen = p_screen
	app = p_app
	hud = p_hud
	world = p_screen.world
	cards = p_screen.cards
	fx3d = p_screen.fx3d
	rig = app.tavern.camera_rig
	fx = app.get("post_fx")
	var path = app.get("settings_path")
	seat_camera = SeatCamera.new(rig, world, screen.my_pid, path if path is String else Settings.PATH)
	seat_camera.stow_fan_in_first_person = true   # 第一人称时 3D 牌扇收起来,不和底部的 2D 手牌条叠在一起(穿模修复 2026-10-10)
	add_child(seat_camera)


# —— 纯逻辑 ——

static func played_text(ev: Dictionary, names: Callable) -> String:
	# 日志:「阿狸 出了 顺子 · 7 张:7 6 5 4 3」「小熊 出了 炸弹」
	var cards_played := DdzScreenState._cards(ev.get("cards"))
	var combo := str(ev.get("combo", ""))
	var text := "%s 出了 %s" % [names.call(ev.get("pid")), DdzScreenState.combo_text({"type": combo, "count": cards_played.size()})]
	if combo != DdzHand.ROCKET:
		text += ":" + " ".join(DdzLayout.row_order(cards_played).map(func(c: int) -> String: return DdzHand.RANK_LABELS[DdzHand.rank(c)]))
	if ev.get("auto") is bool and ev["auto"]:
		text += "(托管)"
	elif ev.get("timed_out") is bool and ev["timed_out"]:
		text += "(超时)"
	return text


static func effect_for(combo: String) -> String:
	# 牌型 → 特效:bomb / rocket / plane / chain / ""
	if combo == DdzHand.BOMB:
		return "bomb"
	if combo == DdzHand.ROCKET:
		return "rocket"
	if PLANE_COMBOS.has(combo):
		return "plane"
	if CHAIN_COMBOS.has(combo):
		return "chain"
	return ""


static func winners_of(ev: Dictionary, seats: Array) -> Array:
	# 一手的赢家:地主赢 → [地主];否则两个农民
	var landlord: Variant = ev.get("landlord")
	var landlord_won: bool = ev.get("landlord_won") is bool and ev["landlord_won"]
	if landlord_won:
		return [landlord] if landlord is int else []
	return seats.filter(func(pid) -> bool: return pid != landlord)


static func played_time(combo: String, count: int) -> float:
	# 这段出牌演出要等多久(测试对照 DouDizhuPacing.played_time)
	var flight := DdzCards.play_duration(count)
	match effect_for(combo):
		"bomb":
			return flight + DdzFx.BOMB_TIME
		"rocket":
			return flight + DdzFx.ROCKET_TIME
		"plane":
			return maxf(flight, PLANE_DELAY + DdzFx.PLANE_TIME) + PLAY_HOLD
		"chain":
			return flight + DdzCards.WAVE_TIME
	return flight + PLAY_HOLD


# —— 入口 ——

func intro() -> void:
	Sfx.play("whoosh")
	await settle_camera(INTRO_MOVE)


func play(ev: Dictionary) -> void:
	event_started.emit(ev)
	match ev.get("type", ""):
		"hand_started":
			await _hand_started(ev)
		"redeal":
			await _redeal(ev)
		"turn":
			_turn(ev)
		"bid":
			await _bid(ev)
		"landlord":
			await _landlord(ev)
		"played":
			await _played(ev)
		"passed":
			await _passed(ev)
		"trick_cleared":
			await _trick_cleared(ev)
		"trustee":
			_trustee(ev)
		"hand_over":
			await _hand_over(ev)
		"ending":
			_ending(ev)
		"player_left":
			await _player_left(ev)
		"session_over":
			await _session_over(ev)


# —— 发牌与叫分 ——

func _hand_started(ev: Dictionary) -> void:
	# 收上一手的牌(和等私有手牌同时进行)、摘帽、复位表情,洗牌发牌:3 张底牌扣到桌心,每人 17 张
	var had_cards := not cards.all_cards().is_empty()
	screen.begin_hand(ev)
	var hand := _int(ev, "hand")
	hud.announce("第 %d 手" % hand, UiTheme.BRASS_BRIGHT, "", 0.8)
	hud.log_event("—— 第 %d 手 ——" % hand, UiTheme.BRASS)
	if had_cards:
		cards.sweep_all()
	await _ensure_faces()
	var mine: Array = await screen.cards_for_deal(hand, maxi(_int(ev, "deal"), 1), PRIVATE_WAIT)
	if had_cards:
		await _wait(maxf(DdzCards.SWEEP_FLIGHT - PRIVATE_WAIT, 0.0))
	screen.show_dealt(mine)
	world.look_all_at(TABLE_FOCUS)
	Sfx.play("riffle")
	await cards.deal(screen.state.seats, _counts(ev), mine)
	screen.sync_table()


func _redeal(ev: Dictionary) -> void:
	screen.note_event(ev)
	screen.set_current(null)
	hud.log_event("没人叫地主,重新发牌(第 %d 次)" % _int(ev, "deal"), UiTheme.PARCHMENT_DIM)
	hud.announce("重新发牌", UiTheme.PARCHMENT, "三家都不叫", 0.7)
	for pid in world.patrons:
		_express(pid, "worried")
	cards.sweep_all()
	var mine: Array = await screen.cards_for_deal(screen.state.hand, _int(ev, "deal"), REDEAL_PRIVATE_WAIT)
	await _wait(maxf(DdzCards.SWEEP_FLIGHT - REDEAL_PRIVATE_WAIT, 0.0))
	for pid in world.patrons:
		_express(pid, "neutral")
	screen.show_dealt(mine)
	Sfx.play("riffle")
	await cards.deal(screen.state.seats, _counts(ev), mine, DdzCards.REDEAL_SPAN)
	screen.sync_table()


func _turn(ev: Dictionary) -> void:
	screen.note_event(ev)
	screen.set_current(ev.get("pid"))
	screen.pulse_nameplate(ev.get("pid"))


func _bid(ev: Dictionary) -> void:
	var pid: Variant = ev.get("pid")
	var score := _int(ev, "score")
	screen.note_event(ev)
	var text := DdzScreenState.bid_text(score)
	_bubble(pid, text, UiTheme.INK if score > 0 else Color(0.4, 0.34, 0.3))
	hud.log_event("%s %s%s" % [screen.name_of(pid), "叫 " + text if score > 0 else "不叫", _auto_tag(ev)],
		UiTheme.BRASS if score > 0 else UiTheme.PARCHMENT_DIM)
	Sfx.play("bid" if score > 0 else "knock")
	if score > 0:
		_reach(pid)
		_express(pid, "smug" if score == DdzState.MAX_BID else "happy")
		_look_all(world.head_position(pid) if pid is int else TABLE_FOCUS)
	screen.refresh_hud()
	await _wait(BID_HOLD)


func _landlord(ev: Dictionary) -> void:
	# 定地主:聚光灯照着他、所有人看向他,地主帽 / 草帽「啵」地戴上;底牌翻开亮一下,再飞进他手里
	var pid: Variant = ev.get("pid")
	var bottom := DdzScreenState._cards(ev.get("bottom"))
	var mine_after: Array = screen.state.shown_hand.duplicate()
	if pid == screen.my_pid:
		mine_after.append_array(bottom)
		mine_after.sort()
	screen.note_event(ev)
	screen.set_current(null)
	var forced: bool = ev.get("forced") is bool and ev["forced"]
	var who: String = "你" if pid == screen.my_pid else screen.name_of(pid)
	hud.announce("%s 当地主!" % who, UiTheme.BRASS_BRIGHT,
		"三家都不叫,只好由%s当 1 分地主" % who if forced else "底分 %d 分 · 底牌亮给大家看" % _int(ev, "base"), 1.0)
	hud.log_event("%s 当地主(底分 %d):底牌 %s" % [screen.name_of(pid), _int(ev, "base"), DdzHand.labels(bottom)], UiTheme.BRASS_BRIGHT)
	Sfx.play("win")
	if pid is int:
		fx3d.spotlight_on(pid)
		_look_all(world.head_position(pid))
	screen.put_on_hats(true)
	if pid is int and world.patrons.has(pid):
		_express(pid, "smug")
		world.patrons[pid].relief()
	screen.refresh_hud()
	await cards.reveal_bottom(bottom, pid if pid is int else -1, mine_after)
	if pid == screen.my_pid:
		screen.take_bottom(bottom)
	await _wait(LANDLORD_TAIL)
	_look_all(TABLE_FOCUS)


# —— 出牌 ——

func _played(ev: Dictionary) -> void:
	var pid: Variant = ev.get("pid")
	var played := DdzScreenState._cards(ev.get("cards"))
	var combo := str(ev.get("combo", ""))
	var before: int = screen.state.multiplier
	if pid == screen.my_pid:
		screen.take_played(played)
	screen.note_event(ev)
	fx3d.clear_pass(pid if pid is int else -1)
	_reach(pid)
	_bubble(pid, DdzScreenState.shout_for(combo, played), UiTheme.BLOOD if DdzHand.is_bomb_like({"type": combo}) else UiTheme.INK)
	hud.log_event(played_text(ev, screen.name_of), UiTheme.LIE if DdzHand.is_bomb_like({"type": combo}) else UiTheme.PARCHMENT)
	_look_all(cards.row_center(pid) if pid is int else TABLE_FOCUS)
	var effect := effect_for(combo)
	if effect == "plane" and pid is int:
		_plane_later(pid)
	if pid is int:
		await cards.play(pid, played)
	var mult := _int(ev, "multiplier")
	match effect:
		"bomb":
			var at: Vector3 = cards.row_center(pid) + Vector3(0, 0.05, 0)
			fx3d.bomb(at, mult)
			rig.shake(0.6)
			app.tavern.kick_lamp(0.12)
			if fx != null:
				fx.flash(Color(1.0, 0.82, 0.55, 0.6), 0.4)
			_startle_all(pid)
			if pid is int and world.patrons.has(pid):
				world.patrons[pid].slam_table()
			hud.announce("炸弹!", UiTheme.BLOOD, "倍数翻倍:×%d" % mult, 0.9, DdzHud.ANNOUNCE_Y_LOW)
			await _wait(DdzFx.BOMB_TIME)
		"rocket":
			fx3d.rocket(cards.row_center(pid) + Vector3(0, 0.03, 0))
			_look_all(cards.row_center(pid) + Vector3(0, DdzFx.ROCKET_HEIGHT, 0))
			_startle_all(pid)
			if pid is int and world.patrons.has(pid):
				world.patrons[pid].celebrate()
			hud.announce("王炸!", UiTheme.BLOOD, "倍数翻倍:×%d" % mult, 1.2, DdzHud.ANNOUNCE_Y_LOW)
			await _wait(DdzFx.ROCKET_TIME * 0.45)
			rig.shake(0.4)
			if fx != null:
				fx.flash(Color(1.0, 0.9, 0.7, 0.5), 0.35)
			await _wait(DdzFx.ROCKET_TIME * 0.55)
		"plane":
			await _wait(maxf(PLANE_DELAY + DdzFx.PLANE_TIME - DdzCards.play_duration(played.size()), 0.0) + PLAY_HOLD)
		"chain":
			cards.wave(pid)
			fx3d.pop_text(DdzHand.type_name(combo) + "!", cards.row_center(pid) + Vector3(0, 0.3, 0), Color(1.0, 0.86, 0.42), 1.1, 0.9)
			await _wait(DdzCards.WAVE_TIME)
		_:
			await _wait(PLAY_HOLD)
	if mult != before:
		hud.set_multiplier(mult, false)
		hud.pop_multiplier()
		Sfx.play("pop")
		if effect != "bomb":
			fx3d.multiplier_pop(cards.row_center(pid) + Vector3(0.25, 0.32, 0) if pid is int else TABLE_FOCUS, mult)
	var left := _int(ev, "remaining")
	if pid is int:
		if left >= 1 and left <= 2:
			fx3d.set_alarm(pid, left)
			hud.log_event("%s 只剩 %d 张了!" % [screen.name_of(pid), left], UiTheme.LIE)
		else:
			fx3d.clear_alarm(pid)
		if left >= 1 and left <= 2 and pid != screen.my_pid:
			_express(pid, "smug")


func _plane_later(pid: int) -> void:
	# 纸飞机:从出牌的人那边起飞,掠过桌心飞到对面
	await _wait(PLANE_DELAY)
	if not is_inside_tree():
		return
	fx3d.plane(cards.row_center(pid), cards.across_from(pid))


func _passed(ev: Dictionary) -> void:
	var pid: Variant = ev.get("pid")
	screen.note_event(ev)
	_bubble(pid, "不出", Color(0.4, 0.34, 0.3))
	hud.log_event("%s 不出%s" % [screen.name_of(pid), _auto_tag(ev)], UiTheme.PARCHMENT_DIM)
	Sfx.play("knock")
	if pid is int:
		cards.pass_turn(pid)
		var mine: bool = pid == screen.my_pid
		fx3d.pass_mark(pid, cards.to_global(DdzLayout.pass_point(world.seat_angles.get(pid, 0.0), mine)))
		_express(pid, "neutral")
	await _wait(PASS_HOLD)


func _trick_cleared(ev: Dictionary) -> void:
	screen.note_event(ev)
	fx3d.clear_passes()
	var pid: Variant = ev.get("pid")
	hud.log_event("两家都不出:%s 接着出" % screen.name_of(pid), UiTheme.PARCHMENT_DIM)
	await cards.clear_trick()


func _trustee(ev: Dictionary) -> void:
	var pid: Variant = ev.get("pid")
	var on: bool = ev.get("on") is bool and ev["on"]
	screen.note_event(ev)
	var auto: bool = ev.get("auto") is bool and ev["auto"]
	hud.log_event("%s %s" % [screen.name_of(pid), ("连续超时,进入托管" if auto else "开启托管") if on else "取消托管"], UiTheme.PARCHMENT_DIM)
	if pid == screen.my_pid:
		app.toast("连续超时,已替你托管(点「取消托管」接回来)" if auto and on else ("已托管" if on else "已取消托管"),
			UiTheme.BRASS_BRIGHT)
	screen.refresh_hud()


# —— 一手结束与散局 ——

func _hand_over(ev: Dictionary) -> void:
	# 摊牌:别人剩的牌翻到面前;宣告输赢(底分 × 倍数)、头顶飘分、赢家欢呼、输家垂头;春天另有花瓣
	screen.note_event(ev)
	screen.set_current(null)
	fx3d.clear_passes()
	fx3d.clear_alarms()
	var remaining := {}
	for row in (ev["remaining"] if ev.get("remaining") is Array else []):
		if row is Dictionary and row.get("pid") is int:
			remaining[row["pid"]] = DdzScreenState._cards(row.get("cards"))
	await cards.reveal_remaining(remaining)
	var landlord: Variant = ev.get("landlord")
	var landlord_won: bool = ev.get("landlord_won") is bool and ev["landlord_won"]
	var winners := winners_of(ev, screen.state.seats)
	var my_role := str(screen.state.roles.get(screen.my_pid, ""))
	var title := DdzHud.summary_title(ev, my_role)
	var mine_won := winners.has(screen.my_pid)
	hud.announce(title, UiTheme.BRASS_BRIGHT if mine_won else UiTheme.LIE, DdzHud.formula_text(ev), 1.6)
	hud.log_event("%s:%s" % ["地主胜" if landlord_won else "农民胜", DdzHud.formula_text(ev)], UiTheme.BRASS_BRIGHT)
	Sfx.play("win" if mine_won else "sting_lie")
	for row in (ev["deltas"] if ev.get("deltas") is Array else []):
		if row is Dictionary and row.get("pid") is int:
			var delta := _int(row, "delta")
			fx3d.pop_text(DdzNameplate.signed(delta), fx3d._above(row["pid"]) + Vector3(0, 0.12, 0),
				DdzFx.DELTA_GREEN if delta > 0 else DdzFx.DELTA_RED, 1.1, HAND_OVER_HOLD, 0.2)
	for pid in world.patrons:
		var patron: Patron = world.patrons[pid]
		if winners.has(pid):
			patron.set_expression("happy")
			patron.celebrate()
		else:
			patron.set_expression("angry" if pid == landlord else "worried")
			patron.startle()
	screen.refresh_hud()
	screen.show_hand_summary()
	if ev.get("spring") is bool and ev["spring"]:
		fx3d.spring(cards.to_global(Vector3(0, SeatLayout.TABLE_TOP, 0)))
		hud.set_multiplier(_int(ev, "multiplier"), false)
		hud.pop_multiplier()   # 春天 ×2
		hud.announce("春天!", Color(1.0, 0.62, 0.74), title, 1.2, DdzHud.ANNOUNCE_Y_LOW)
		await _wait(DdzFx.SPRING_TIME)
	await _wait(HAND_OVER_HOLD)


func _ending(ev: Dictionary) -> void:
	screen.note_event(ev)
	hud.log_event("房主散局:打完这一手就结算", UiTheme.LIE)
	hud.set_ending(true)


func _player_left(ev: Dictionary) -> void:
	var pid: Variant = ev.get("pid")
	screen.note_event(ev)
	hud.log_event("%s 离开了牌桌%s" % [screen.name_of(pid), ",这一手作废" if ev.get("hand_voided") is bool and ev["hand_voided"] else ""],
		UiTheme.LIE)
	_bubble(pid, "……")
	screen.drop_player(pid)
	Sfx.play("thud")
	await _wait(LEFT_PAUSE)


func _session_over(ev: Dictionary) -> void:
	screen.note_event(ev)
	screen.set_current(null)
	fx3d.clear_alarms()
	fx3d.clear_passes()
	_leave_rest(MODE_ORBIT)
	hud.set_away_from_seat(true)
	hud.hide_summary()
	var left_reason: bool = str(ev.get("reason", "")) == DdzState.REASON_PLAYER_LEFT
	hud.announce("散局" if not left_reason else "牌局结束", UiTheme.BRASS_BRIGHT, "按累计分排名", 1.8)
	hud.log_event("散局结算", UiTheme.BRASS_BRIGHT)
	# 结算庆祝:第一名(同分并列都算)跳舞、其他人鼓掌、礼炮彩纸;镜头绕着跳舞的人转,右边放结算面板
	var results: Array = ev["results"] if ev.get("results") is Array else []
	var winners := DdzScreenState.top_ranked(results).filter(func(pid: int) -> bool: return world.patrons.has(pid))
	world.celebrate(winners, hash(["dou_dizhu", winners, results.size()]))
	var orbit := world.celebration_orbit(winners)
	rig.set_fill(orbit.get("fill", 0.0), 1.0)
	rig.orbit(orbit["center"], orbit["radius"], orbit["height"], orbit["speed"], 1.4, orbit.get("start", NAN), orbit.get("frame", 0.0))
	if not winners.is_empty():
		_look_all(world.head_position(winners[0]))
	await _wait(SESSION_OVER_HOLD)
	screen.show_settlement(results, str(ev.get("reason", "")))


# —— 机位 ——

func is_at_seat() -> bool:
	return _settled and _mode == MODE_SEAT


func is_camera_at_rest() -> bool:
	return _settled and _mode == MODE_SEAT


func camera_mode() -> String:
	return _mode


func settle_camera(duration := CAMERA_MOVE) -> void:
	if _mode == MODE_SEAT and _settled:
		return
	if _mode == MODE_ORBIT:
		return   # 散局环绕之后不再回座
	_leave_rest(MODE_SEAT)
	var serial := _camera_serial
	seat_camera.enter(duration)
	await _wait(duration)
	if serial == _camera_serial:
		_settled = true
		rig.parallax_enabled = true


func _leave_rest(mode: String) -> void:
	_mode = mode
	_settled = false
	_camera_serial += 1
	rig.parallax_enabled = false
	seat_camera.leave()
	if mode == MODE_ORBIT:
		hud.clear_my_bubble()


func toggle_camera_mode() -> void:
	var on := seat_camera.toggle()
	cards.present_my_fan()
	app.toast(SeatCamera.toast_text(on, seat_camera.is_seated()), UiTheme.PARCHMENT)


# —— 酒客与工具 ——

func _counts(ev: Dictionary) -> Dictionary:
	var out := {}
	for row in (ev["hands"] if ev.get("hands") is Array else []):
		if row is Dictionary and row.get("pid") is int:
			out[row["pid"]] = _int(row, "count")
	return out


func _reach(pid: Variant) -> void:
	if pid is int and world.patrons.has(pid):
		world.patrons[pid].reach_toward_center()


func _express(pid: Variant, kind: String) -> void:
	if pid is int and world.patrons.has(pid):
		world.patrons[pid].set_expression(kind)


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


static func _auto_tag(ev: Dictionary) -> String:
	if ev.get("auto") is bool and ev["auto"]:
		return "(托管)"
	if ev.get("timed_out") is bool and ev["timed_out"]:
		return "(超时)"
	return ""


func _ensure_faces() -> void:
	if DdzJokerFaces.faces_ready():
		return
	PokerFaces.build(screen)
	DdzJokerFaces.build(screen)
	var waited := 0.0
	while not DdzJokerFaces.faces_ready() and waited < FACES_WAIT_MAX and is_inside_tree():
		await get_tree().process_frame
		waited += get_process_delta_time()


static func _int(ev: Dictionary, key: String) -> int:
	return ev[key] if ev.get(key) is int else 0


func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout
