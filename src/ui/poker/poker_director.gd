class_name PokerDirector
extends Node
# 德州演出导演:把规格 §4.5 的每种事件翻译成镜头、酒客动作(§5.6)、筹码与牌的动画(PokerChips / PokerCards)、
# 音效、宣告与日志。每段演出的实际时长不超过 PokerPacing 的预算(房主据此延长回合计时),
# 由 test_poker_director_pacing 读取这里与资产类的节奏常量来保证。
# 缺少前置状态的事件(规格 §7:没有下注堆的收注、手里没牌的弃牌、没酒客的人的动作)由资产类按视图补齐或跳过,
# 这里只在碰酒客之前确认他还在桌上。机位只有两种常驻:自己座位的越肩与观战俯视(§5.5),按本地状态决定,
# 切换运镜不单独占预算(算在 HAND_STARTED 里,或者不等它走完)。


signal event_started(ev: Dictionary)   # 每段演出开始时发出(调试截图与 bot 的日志标记按它取景)

const INTRO_MOVE := PokerPacing.INTRO - 0.15  # 开场运镜(须在房主给的开场预算之内)
const CAMERA_MOVE := 0.9                      # 常驻机位之间的运镜:入座(算在 HAND_STARTED 里)、观战
const HAND_START_SETTLE := 1.0                # 新一手:收牌、换座、移按钮、运镜同时进行,等这么久(≥ 各自的时长)
const CHECK_PAUSE := 0.35                     # 过牌:敲一下桌子的停顿
const ALLIN_SHAKE := 0.35                     # 全下的轻微震屏
const ALLIN_HOLD := 0.4                       # 全下:筹码推出去之后再停一下(宣告有时间被看到)
const POT_HOLD := 0.8                         # 分池:筹码滑到赢家后再停一下
const HAND_OVER_PAUSE := 0.45
const LEFT_PAUSE := 0.25                      # 离桌:酒客消失后的停顿
const SESSION_OVER_HOLD := 2.4                # 散局:环绕镜头与宣告,之后弹结算面板
const FACES_WAIT_MAX := 10.0                  # 第一次发牌前最多等德州牌面生成这么久
const TABLE_FOCUS := Vector3(0, SeatLayout.TABLE_TOP + 0.1, 0)   # 酒客平时看向的桌心(公共牌架一带)
const MODE_SEAT := "seat"
const MODE_OVERVIEW := "overview"
const MODE_ORBIT := "orbit"
const STREET_NAMES := {PokerRules.FLOP: "翻牌", PokerRules.TURN: "转牌", PokerRules.RIVER: "河牌"}
const BLIND_NAMES := {"sb": "小盲", "bb": "大盲"}

var screen: Node        # PokerScreen
var app: Node
var world: TableWorld
var chips: PokerChips
var cards: PokerCards
var rig: CameraRig
var hud: PokerHud
var _mode := ""          # 当前机位:MODE_SEAT / MODE_OVERVIEW / MODE_ORBIT;空 = 还没运镜
var _settled := false    # 镜头已停在常驻机位
var _camera_serial := 0  # 每次运镜加一:后发的运镜让先前的不再宣布「已停稳」
var seat_camera: SeatCamera   # 座位上的镜头:越肩 / 第一人称(V 切换,和骗子酒馆共用)


func _init(p_screen: Node, p_app: Node, p_hud: PokerHud) -> void:
	screen = p_screen
	app = p_app
	hud = p_hud
	world = p_screen.world
	chips = p_screen.chips
	cards = p_screen.cards
	rig = app.tavern.camera_rig
	var path = app.get("settings_path")
	seat_camera = SeatCamera.new(rig, world, screen.my_pid, path if path is String else Settings.PATH)
	add_child(seat_camera)


# —— 纯逻辑 ——

static func action_text(ev: Dictionary) -> String:
	# 日志里的一次行动:「弃牌」「过牌」「跟注 20」「下注 40」「加注到 80」「全下 960」,超时代打加「(超时)」
	var amount: int = ev["amount"] if ev.get("amount") is int else 0
	var bet: int = ev["bet"] if ev.get("bet") is int else 0
	var text: String
	if ev.get("all_in") is bool and ev["all_in"]:
		text = "全下 %s" % ChipText.format(bet)
	else:
		match ev.get("action", ""):
			PokerRules.FOLD:
				text = "弃牌"
			PokerRules.CHECK:
				text = "过牌"
			PokerRules.CALL:
				text = "跟注 %s" % ChipText.format(amount)
			PokerRules.BET:
				text = "下注 %s" % ChipText.format(bet)
			PokerRules.RAISE:
				text = "加注到 %s" % ChipText.format(bet)
			_:
				text = str(ev.get("action", "?"))
	if ev.get("timeout") is bool and ev["timeout"]:
		text += "(超时)"
	return text


static func best_cards(ev: Dictionary) -> Array:
	# pot_won 里所有赢家成牌的并集(高亮用);没摊牌就赢时为空
	var out := []
	var best: Dictionary = ev["best"] if ev.get("best") is Dictionary else {}
	for pid in best:
		for card in (best[pid] if best[pid] is Array else []):
			if PokerCard.is_card(card) and not out.has(card):
				out.append(card)
	return out


static func pot_won_text(ev: Dictionary, names: Callable) -> Dictionary:
	# 宣告 {"title", "sub"}:「X 赢得 1,240」+ 牌型;平分写「X、Y 平分 1,240」;没摊牌就赢写「无人跟注」
	var winners: Array = ev["winners"] if ev.get("winners") is Array else []
	var amount: int = ev["amount"] if ev.get("amount") is int else 0
	var who := "、".join(winners.map(func(pid) -> String: return names.call(pid)))
	var title := "%s %s %s" % [who, "平分" if winners.size() > 1 else "赢得", ChipText.format(amount)]
	var uncontested: bool = ev.get("uncontested") is bool and ev["uncontested"]
	var hand_name: String = ev["hand_name"] if ev.get("hand_name") is String else ""
	return {"title": title, "sub": "无人跟注" if uncontested else hand_name}


# —— 入口 ——

func intro() -> void:
	Sfx.play("whoosh")
	await settle_camera(INTRO_MOVE)


func play(ev: Dictionary) -> void:
	event_started.emit(ev)
	match ev.get("type", ""):
		"hand_started":
			await _hand_started(ev)
		"blind":
			await _blind(ev)
		"hole_cards":
			await _hole_cards(ev)
		"turn":
			screen.set_current(ev.get("pid"))
		"action":
			await _action(ev)
		"bets_collected":
			await _bets_collected(ev)
		"street":
			await _street(ev)
		"reveal":
			await _reveal(ev)
		"pot_won":
			await _pot_won(ev)
		"hand_over":
			await _hand_over(ev)
		"rebuy":
			await _rebuy(ev)
		"spectate":
			_spectate(ev)
		"away", "sit_in":
			_seat_change(ev)
		"next_ready":
			screen.note_event(ev)
			screen.refresh_actions()   # 铭牌「已准备」、底部「等待其他人(2/5)」
		"hand_record":
			screen.note_event(ev)
			screen.add_record()
		"player_joined":
			_player_joined(ev)
		"player_left":
			await _player_left(ev)
		"ending":
			_ending(ev)
		"session_over":
			await _session_over(ev)


# —— 新一手 ——

func _hand_started(ev: Dictionary) -> void:
	# 收上一手的牌、按新座位表换座、庄家按钮滑到新位置、新入座者的镜头回座位:同时进行,等 HAND_START_SETTLE
	screen.begin_hand(ev)
	var hand: int = ev["hand"] if ev.get("hand") is int else screen.state.hand
	hud.announce("第 %d 手" % hand, UiTheme.BRASS_BRIGHT, "", 0.9)
	hud.log_event("—— 第 %d 手 ——" % hand, UiTheme.BRASS)
	cards.highlight([])
	hud.board_strip.highlight([])
	cards.sweep()
	var button: Variant = ev.get("button")
	if button is int:
		chips.move_button(button)
	else:
		chips.place_button(null)
	settle_camera(CAMERA_MOVE)
	await _wait(HAND_START_SETTLE)


func _blind(ev: Dictionary) -> void:
	screen.note_event(ev)
	var pid: Variant = ev.get("pid")
	hud.log_event("%s 下%s %s" % [screen.name_of(pid), BLIND_NAMES.get(ev.get("kind"), "盲注"), ChipText.format(_int(ev, "amount"))],
		UiTheme.PARCHMENT_DIM)
	_reach(pid)
	await chips.bet(pid if pid is int else -1, _int(ev, "bet"), _int(ev, "stack"))


func _hole_cards(ev: Dictionary) -> void:
	# 第一次发牌前等德州牌面生成完(规格 §5.2),之后牌面已缓存
	await _ensure_faces()
	var pids: Array = ev["pids"] if ev.get("pids") is Array else []
	var my_hole: Array = []
	if pids.has(screen.my_pid):
		my_hole = await screen.hole_for_hand(_int(ev, "hand"))
	hud.log_event("发牌 · %d 人" % pids.size(), UiTheme.PARCHMENT_DIM)
	world.look_all_at(TABLE_FOCUS)
	await cards.deal_hole(pids, screen.my_pid, my_hole)
	hud.set_my_hole(my_hole)


# —— 行动 ——

func _action(ev: Dictionary) -> void:
	screen.note_event(ev)
	var pid: Variant = ev.get("pid")
	hud.log_event("%s %s" % [screen.name_of(pid), action_text(ev)],
		UiTheme.BRASS_BRIGHT if ev.get("all_in") == true else UiTheme.PARCHMENT)
	match ev.get("action", ""):
		PokerRules.FOLD:
			_express(pid, "worried")
			await cards.fold(pid if pid is int else -1)
		PokerRules.CHECK:
			_look(pid, TABLE_FOCUS)
			await _wait(CHECK_PAUSE)
		_:
			await _put_chips(ev)


func _put_chips(ev: Dictionary) -> void:
	# 跟注 / 下注 / 加注:新筹码从筹码堆滑到下注位;全下另有宣告与轻微震屏(规格 §5.6)
	var pid: Variant = ev.get("pid")
	_reach(pid)
	var all_in: bool = ev.get("all_in") is bool and ev["all_in"]
	if all_in:
		hud.announce("全下!", UiTheme.LIE, "%s 推出了全部筹码" % screen.name_of(pid), 0.8)
		rig.shake(ALLIN_SHAKE)
	await chips.bet(pid if pid is int else -1, _int(ev, "bet"), _int(ev, "stack"))
	if all_in:
		await _wait(ALLIN_HOLD)


func _bets_collected(ev: Dictionary) -> void:
	# 一轮下注结束:到下一个 turn 事件之前没人在行动,回合横幅不能还写「等待 X 行动…」(收注、发公共牌、全下亮牌、摊牌分池都是)
	screen.note_event(ev)
	screen.set_current(null)
	var refund: Dictionary = ev["refund"] if ev.get("refund") is Dictionary else {}
	if refund.get("amount") is int and refund["amount"] > 0:
		hud.log_event("%s 退回未跟注的 %s" % [screen.name_of(refund.get("pid")), ChipText.format(refund["amount"])], UiTheme.PARCHMENT_DIM)
	var pots: Array = ev["pots"] if ev.get("pots") is Array else []
	await chips.collect(pots, refund)
	hud.set_pots(pots)


func _street(ev: Dictionary) -> void:
	screen.note_event(ev)
	screen.set_current(null)
	var board: Array = screen.state.board
	var new_cards: Array = (ev["cards"] if ev.get("cards") is Array else []).filter(PokerCard.is_card)
	var street: String = ev["street"] if ev.get("street") is String else ""
	var title: String = STREET_NAMES.get(street, "公共牌")
	hud.announce(title, UiTheme.BRASS_BRIGHT, "", 0.7)
	hud.log_event("%s · 公共牌 %d 张" % [title, board.size()], UiTheme.BRASS)
	world.look_all_at(TABLE_FOCUS)
	await cards.deal_board(new_cards, board.size() - new_cards.size())
	hud.set_board(board)
	hud.set_my_best(screen.state.best_detail())
	if screen.state.in_showdown:
		hud.set_showdown(screen.state.showdown_entries(screen.state.is_short_deck()))


# —— 摊牌 ——

func _reveal(ev: Dictionary) -> void:
	screen.note_event(ev)
	screen.set_current(null)
	if ev.get("reason") == "allin":
		hud.announce("亮牌", UiTheme.BRASS_BRIGHT, "全下后先亮牌,再发完公共牌", 0.8)
	for entry in (ev["hands"] if ev.get("hands") is Array else []):
		if not entry is Dictionary or not entry.get("pid") is int:
			continue
		var pid: int = entry["pid"]
		hud.log_event("%s 亮牌" % screen.name_of(pid), UiTheme.PARCHMENT_DIM)
		_look(pid, TABLE_FOCUS)
		await cards.reveal(pid, entry["cards"] if entry.get("cards") is Array else [])
		hud.set_showdown(screen.state.showdown_entries(screen.state.is_short_deck()))


func _pot_won(ev: Dictionary) -> void:
	screen.note_event(ev)
	screen.set_current(null)
	var winners: Array = ev["winners"] if ev.get("winners") is Array else []
	var lit := best_cards(ev)
	cards.highlight(lit)
	hud.board_strip.highlight(lit)
	var text := pot_won_text(ev, screen.name_of)
	hud.announce(text["title"], UiTheme.BRASS_BRIGHT, text["sub"], 1.2)
	hud.log_event(text["title"] + (" · " + text["sub"] if text["sub"] != "" else ""), UiTheme.BRASS_BRIGHT)
	if winners.has(screen.my_pid):
		Sfx.play("win")
	for pid in winners:
		if world.patrons.has(pid):
			world.patrons[pid].celebrate()
	var shares: Dictionary = ev["shares"] if ev.get("shares") is Dictionary else {}
	if screen.state.in_showdown:
		hud.set_showdown(screen.state.showdown_entries(screen.state.is_short_deck()))   # 结果列:谁赢了多少
	await chips.award(_int(ev, "index"), shares, {})
	await _wait(POT_HOLD)


func _hand_over(ev: Dictionary) -> void:
	screen.note_event(ev)
	screen.end_hand(ev)
	for pid in (ev["busted"] if ev.get("busted") is Array else []):
		hud.log_event("%s 输光了" % screen.name_of(pid), UiTheme.LIE)
		_express(pid, "worried")
	await _wait(HAND_OVER_PAUSE)


# —— 座位 ——

func _rebuy(ev: Dictionary) -> void:
	screen.note_event(ev)
	var pid: Variant = ev.get("pid")
	hud.log_event("%s 再领 %s" % [screen.name_of(pid), ChipText.format(_int(ev, "amount"))], UiTheme.TRUTH)
	_express(pid, "neutral")
	if pid == screen.my_pid:
		# 从观战回来:酒客重新露面,镜头回到自己座位(运镜不等,不占再领的预算)
		world.set_patron_visible(pid, true)
		settle_camera(CAMERA_MOVE)
	await chips.rebuy(pid if pid is int else -1, _int(ev, "stack"))
	screen.refresh_hud()


func _spectate(ev: Dictionary) -> void:
	screen.note_event(ev)
	var pid: Variant = ev.get("pid")
	hud.log_event("%s 观战" % screen.name_of(pid), UiTheme.MUTED)
	if pid == screen.my_pid:
		# 观战机位在自己座位后上方,自己的酒客会挡镜头:只在本机藏起来(规格 §5.5)
		world.set_patron_visible(pid, false)
		settle_camera(CAMERA_MOVE)
	screen.refresh_hud()


func _seat_change(ev: Dictionary) -> void:
	screen.note_event(ev)
	var pid: Variant = ev.get("pid")
	if ev.get("type") == "away":
		hud.log_event("%s 离座(连续超时)" % screen.name_of(pid), UiTheme.MUTED)
	else:
		hud.log_event("%s 回到牌桌" % screen.name_of(pid), UiTheme.PARCHMENT_DIM)
	screen.refresh_hud()


func _player_joined(ev: Dictionary) -> void:
	screen.note_event(ev)
	Sfx.play("join")
	hud.log_event("%s 走进了酒馆,下一手入座" % screen.name_of(ev.get("pid")), UiTheme.BRASS_BRIGHT)
	screen.refresh_hud()


func _player_left(ev: Dictionary) -> void:
	screen.note_event(ev)
	var pid: Variant = ev.get("pid")
	hud.log_event("%s 离开了牌桌" % screen.name_of(pid), UiTheme.LIE)
	screen.drop_player(pid)
	if not pid is int or not world.patrons.has(pid):
		return   # 没有酒客的人(还没登场的新人、已离场者)什么也不用演
	if ev.get("folded") is bool and ev["folded"]:
		await cards.fold(pid)
	Sfx.play("thud")
	world.remove_patron(pid)
	chips.remove_seat(pid)
	await _wait(LEFT_PAUSE)


# —— 散局 ——

func _ending(ev: Dictionary) -> void:
	screen.note_event(ev)
	hud.set_ending(true)
	hud.announce(PokerHud.ENDING_TEXT, UiTheme.BRASS_BRIGHT, "房主宣布散局", 1.0)
	hud.log_event("房主宣布散局:本手结束后结算", UiTheme.BRASS)


func _session_over(ev: Dictionary) -> void:
	screen.set_current(null)
	_leave_rest(MODE_ORBIT)
	hud.announce("散局", UiTheme.BRASS_BRIGHT, "牌局结束,结算中", 1.8)
	hud.log_event("散局结算", UiTheme.BRASS_BRIGHT)
	# 结算庆祝(规格 2026-10-09):盈亏第一的人跳舞(并列第一都跳)、其他人鼓掌、礼炮彩纸;开场小号与掌声由庆祝发出。
	# 镜头绕着跳舞的人转(让到画面左边,右边放结算面板);并列的人散得开时整桌环绕
	var results: Array = ev["results"] if ev.get("results") is Array else []
	var winners := top_ranked(results)
	world.celebrate(winners, hash(["poker", winners, results.size()]))
	var orbit := world.celebration_orbit(winners)
	rig.set_fill(orbit.get("fill", 0.0), 1.0)
	rig.orbit(orbit["center"], orbit["radius"], orbit["height"], orbit["speed"], 1.4, orbit.get("start", NAN), orbit.get("frame", 0.0))
	await _wait(SESSION_OVER_HOLD)
	screen.show_settlement(results)


static func top_ranked(results: Array) -> Array:
	# 散局的胜者:盈亏最高的人(并列时都算),按结算行的顺序;坏行跳过
	var best = null
	var out := []
	for row in results:
		if not row is Dictionary or not row.get("pid") is int or not row.get("net") is int:
			continue
		if best == null or row["net"] > best:
			best = row["net"]
			out = [row["pid"]]
		elif row["net"] == best:
			out.append(row["pid"])
	return out


# —— 机位 ——

func is_at_seat() -> bool:
	# 镜头停在自己座位的越肩机位:只有这时自己的头才跟光标、读 WASD
	return _settled and _mode == MODE_SEAT


func is_camera_at_rest() -> bool:
	# 镜头停在常驻机位(越肩或观战俯视):视线归各玩家自己
	return _settled


func camera_mode() -> String:
	return _mode


func wanted_mode() -> String:
	return MODE_OVERVIEW if screen.state.uses_overview(screen.my_pid) else MODE_SEAT


func settle_camera(duration := CAMERA_MOVE) -> void:
	# 按本地状态选常驻机位(规格 §5.5),已在那里就不动;协程,调用方可以等也可以不等
	var wanted := wanted_mode()
	if wanted == _mode and _settled:
		return
	_leave_rest(wanted)
	var serial := _camera_serial
	if wanted == MODE_SEAT:
		seat_camera.enter(duration)   # 越肩或第一人称(按 V 选的),补光、视角一并调好
	else:
		rig.set_fill(0.0, duration)
		rig.move_to(world.overview_view(), duration)
	await _wait(duration)
	if serial == _camera_serial:
		_settled = true
		rig.parallax_enabled = wanted == MODE_SEAT


func _leave_rest(mode: String) -> void:
	_mode = mode
	_settled = false
	_camera_serial += 1
	rig.parallax_enabled = false
	seat_camera.leave()


func toggle_camera_mode() -> void:
	# V:越肩 ⇄ 第一人称(存进设置)。镜头在座位上就马上切过去,观战或结算时等回座再生效
	var on := seat_camera.toggle()
	app.toast(SeatCamera.toast_text(on, seat_camera.is_seated()), UiTheme.PARCHMENT)


# —— 酒客与工具 ——

func _reach(pid: Variant) -> void:
	if pid is int and world.patrons.has(pid):
		world.patrons[pid].reach_toward_center()


func _express(pid: Variant, kind: String) -> void:
	if pid is int and world.patrons.has(pid):
		world.patrons[pid].set_expression(kind)


func _look(pid: Variant, point: Vector3) -> void:
	if pid is int and world.patrons.has(pid):
		world.patrons[pid].look_at_point(point)


func _ensure_faces() -> void:
	var waited := 0.0
	while not PokerFaces.is_built() and waited < FACES_WAIT_MAX and is_inside_tree():
		await get_tree().process_frame
		waited += get_process_delta_time()


static func _int(ev: Dictionary, key: String) -> int:
	return ev[key] if ev.get(key) is int else 0


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
