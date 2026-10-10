class_name BombCatShowcase
extends Node
# 截图与性能用的炸弹猫展台(tools/shot.gd --bomb-cat-showcase、tools/perf_probe.gd --showcase=bomb_cat):
# 6 人大桌坐满,桌心牌堆与弃牌堆,各家牌扇(有人 11 张、压缩扇面),自己举着 8 张;机位取自 TableWorld。
# 状态(HUD_STATES)用假数据走与牌桌相同的接口(BombCatCards / BombCatHud / BombCatNameplate),每种状态再摆好对应的 3D:
#   turn      自己的回合,选中两张鱼干,横幅「轮到你了」
#   window    3 号对自己打出「甩锅」,反应窗口条 + 亮着的「不行!」按钮
#   bomb      4 号摸到炸弹:炸弹牌立在他面前冒火花、所有人吓一跳(配 bomb_close 机位)
#   exploded  4 号被炸飞:黑脸、×眼星星、帽子飞走、头顶黑烟
#   defuse    自己拆了弹:塞回滑块
#   peek      自己偷看:三张牌浮在镜头前 + 2D 浮层
#   give      2 号向自己讨要一张牌
#   settlement 结算面板

const ShowcaseSpecies := preload("res://tools/showcase_species.gd")

const ME := 1
const SEATS := 6
const SETTLE := 3.0
const NAMES := {1: "我", 2: "阿狸", 3: "小熊", 4: "老狐狸", 5: "猪猪侠", 6: "一个名字很长的客人"}
const HANDS := {1: [BombCatCard.DEFUSE, BombCatCard.SNACK_FISH, BombCatCard.SNACK_FISH, BombCatCard.NOPE, BombCatCard.SKIP,
	BombCatCard.PEEK, BombCatCard.SNACK_CACTUS, BombCatCard.BEG]}
const COUNTS := {1: 8, 2: 6, 3: 7, 4: 5, 5: 11, 6: 3}
const DECK := 18
const DISCARD := [BombCatCard.SKIP, BombCatCard.SNACK_YARN, BombCatCard.SNACK_YARN, BombCatCard.NOPE, BombCatCard.PASS_TURNS]
const DISCARD_COUNT := 14
const BOMBS := 5
const TURN_LEFT := 21.0
const ANNOUNCE_HOLD := 30.0
const BOMB_PID := 4
const STATE_TURN := "turn"
const STATE_WINDOW := "window"
const STATE_BOMB := "bomb"
const STATE_EXPLODED := "exploded"
const STATE_DEFUSE := "defuse"
const STATE_PEEK := "peek"
const STATE_GIVE := "give"
const STATE_SETTLEMENT := "settlement"
const HUD_STATES := [STATE_TURN, STATE_WINDOW, STATE_BOMB, STATE_EXPLODED, STATE_DEFUSE, STATE_PEEK, STATE_GIVE, STATE_SETTLEMENT]
const PEEK := [BombCatCard.SNACK_BANANA, BombCatCard.BOMB, BombCatCard.SHUFFLE]
const LOG := ["阿狸 摸了一张", "小熊 打出两张毛线球 → 猪猪侠", "小熊 从 猪猪侠 手里抽走一张", "猪猪侠 打出「不行!」(第 1 张)"]

var world: TableWorld
var cards: BombCatCards
var hud: BombCatHud = null
var labels: WorldLabels = null
var settlement: BombCatSettlement = null
var _camera: Camera3D = null
var _staged := ""


func build(tavern: Tavern) -> void:
	await BombCatFaces.build(self)
	_camera = tavern.camera_rig.camera
	world = TableWorld.new(tavern)
	tavern.table_root.add_child(world)
	# 同 main.apply_table_mode + 炸弹猫牌桌:6 人换大桌,烛台照常,不摆目标牌立牌
	world.configure_table(SeatLayout.table_radius_for(GameMode.BOMB_CAT, SEATS))
	tavern.set_table_decor_visible(true)
	world.cards.set_stand_visible(false)
	world.arrange(ShowcaseSpecies.players(range(1, SEATS + 1)), ME, true, false)
	cards = BombCatCards.new(world)
	cards.my_pid = ME
	world.poker_root.add_child(cards)
	await get_tree().create_timer(SETTLE).timeout
	_sync()
	world.look_all_at(BombCatLayout.TABLE_FOCUS)
	world.patrons[3].set_active(true)


func _sync(counts := COUNTS) -> void:
	cards.sync(counts, HANDS[ME], DECK, DISCARD_COUNT, DISCARD)


# —— 状态 ——

func stage(state: String, ui_root: Control = null) -> void:
	# 摆好 state 的 3D(每种状态只摆一次:爆炸不可逆),ui_root 不为空时再叠上整套 HUD
	if not HUD_STATES.has(state):
		push_warning("unknown bomb cat state %s (known: %s)" % [state, ", ".join(HUD_STATES)])
		return
	if state != _staged:
		await _stage_world(state)
		_staged = state
	if ui_root != null:
		stage_hud(ui_root, state)


func _stage_world(state: String) -> void:
	cards.clear_peek()
	if not [STATE_BOMB, STATE_EXPLODED, STATE_DEFUSE].has(state):
		cards.blow_bomb()   # 上一个状态留下的炸弹牌收走
	match state:
		STATE_TURN:
			cards.set_selection({1: true, 2: true}, -1)
			world.patrons[ME].set_active(true)
		STATE_WINDOW:
			world.patrons[3].reach_toward_center()
			world.look_all_at(world.head_position(ME))
			world.patrons[ME].set_expression("worried")
		STATE_BOMB:
			for pid in world.patrons:
				world.patrons[pid].startle()
			world.patrons[BOMB_PID].set_expression("worried")
			world.look_all_at(world.head_position(BOMB_PID))
			await cards.reveal_bomb(BOMB_PID, DECK)
		STATE_EXPLODED:
			var patron: Patron = world.patrons[BOMB_PID]
			if patron.alive:
				if cards.bomb_node() == null:
					await cards.reveal_bomb(BOMB_PID, DECK)
				Fx.explosion(world, cards.bomb_position())
				cards.blow_bomb()
				patron.die()
				patron.set_soot(1.0)
				await cards.discard_hand(BOMB_PID)
				Fx.head_smoke(world, patron.head_position() + Vector3(0, 0.25, 0))
				world.look_all_at(world.head_position(BOMB_PID))
		STATE_DEFUSE:
			if cards.bomb_node() == null and world.patrons[ME].alive:
				await cards.reveal_bomb(ME, DECK)
				cards.stop_sparks()
		STATE_PEEK:
			if _camera != null:
				cards.show_peek(PEEK, _camera)
			world.patrons[ME].cover_mouth(5.0)
		STATE_GIVE:
			world.look_all_at(world.head_position(ME))


func stage_hud(ui_root: Control, state: String) -> void:
	clear_hud()
	labels = WorldLabels.new(_camera)
	ui_root.add_child(labels)
	hud = BombCatHud.new()
	ui_root.add_child(hud)
	var current := ME
	match state:
		STATE_WINDOW:
			current = 3
		STATE_BOMB, STATE_EXPLODED:
			current = BOMB_PID
	var alive := func(pid: int) -> bool: return not (pid == BOMB_PID and state == STATE_EXPLODED)
	for pid in range(2, SEATS + 1):
		var plate := BombCatNameplate.new(NAMES[pid])
		plate.set_info(0 if not alive.call(pid) else COUNTS[pid], alive.call(pid), true, pid == current, 1)
		var anchor: Callable = world.nameplate_anchor.bind(pid) if world.is_poker_table() else world.patrons[pid].nameplate_anchor
		labels.track("plate:%d" % pid, plate, anchor)
	var bombs_left := BOMBS - (1 if state == STATE_EXPLODED else 0)
	var turn_text := BombCatHud.turn_info_text(NAMES[current], current == ME, 2 if state == STATE_TURN else 1,
		BombCatScreenState.STEP_WINDOW if state == STATE_WINDOW else BombCatScreenState.STEP_TURN)
	hud.set_info(DECK, bombs_left, BOMBS, turn_text, "你:手牌 8 张 · 拆弹 ×1 · 不行! ×1")
	var selected := {1: true, 2: true} if state == STATE_TURN else {}
	hud.set_hand(HANDS[ME], selected, true)
	for line in LOG:
		hud.log_event(line)
	match state:
		STATE_TURN:
			hud.set_turn("轮到你了 · 要走 2 回合", true)
			hud.set_countdown(TURN_LEFT, Protocol.TURN_TIMEOUT, true)
			hud.set_actions(true, true, 2, true, "两张一样的零食:出牌后选一个人,随机抽他一张")
		STATE_WINDOW:
			hud.set_turn("等待 %s 行动…" % NAMES[3], false)
			hud.set_window(BombCatHud.window_text({"pid": 3, "kind": BombCatCard.PASS_TURNS, "target": null, "nopes": 0},
				func(pid): return NAMES.get(pid, "?")), 0.62, true, true)
			hud.set_actions(false, false, 0, false)
			hud.announce("甩锅!", UiTheme.LIE, "小熊 把锅甩给了你", ANNOUNCE_HOLD)
		STATE_BOMB:
			hud.set_away_from_seat(true)
			hud.announce("炸弹!", UiTheme.BLOOD, "%s 摸到了炸弹" % NAMES[BOMB_PID], ANNOUNCE_HOLD, BombCatHud.ANNOUNCE_Y_LOW)
			hud.log_event("%s 摸到了炸弹!" % NAMES[BOMB_PID], UiTheme.BLOOD)
		STATE_EXPLODED:
			hud.set_turn("等待 %s 行动…" % NAMES[5], false)
			hud.set_actions(false, false, 0, false)
			hud.announce("轰!", UiTheme.BLOOD, "%s 被炸飞了" % NAMES[BOMB_PID], ANNOUNCE_HOLD)
			hud.log_event("轰!%s 被炸飞了" % NAMES[BOMB_PID], UiTheme.BLOOD)
		STATE_DEFUSE:
			hud.set_hand(HANDS[ME].slice(1), {}, true)
			hud.show_reinsert(DECK)
			hud.reinsert_slider.value = 6
			hud.set_countdown(11.0, BombCatState.REINSERT_TIMEOUT, true)
			hud.set_actions(false, false, 0, false)
		STATE_PEEK:
			hud.show_peek(PEEK)
			hud.set_turn("轮到你了", true)
			hud.set_countdown(TURN_LEFT, Protocol.TURN_TIMEOUT, true)
			hud.set_actions(false, true, 0, true)
		STATE_GIVE:
			hud.show_give(NAMES[2])
			hud.set_countdown(12.0, BombCatState.GIVE_TIMEOUT, true)
			hud.set_actions(false, false, 0, false, "被讨要:点一张手牌给出去")
		STATE_SETTLEMENT:
			hud.set_away_from_seat(true)
			var rows := [{"pid": 2, "name": NAMES[2], "place": 1, "fate": "winner"}, {"pid": 1, "name": NAMES[1], "place": 2, "fate": "exploded"},
				{"pid": 5, "name": NAMES[5], "place": 3, "fate": "exploded"}, {"pid": 6, "name": NAMES[6], "place": 4, "fate": "left"},
				{"pid": 3, "name": NAMES[3], "place": 5, "fate": "exploded"}, {"pid": 4, "name": NAMES[4], "place": 6, "fate": "exploded"}]
			settlement = BombCatSettlement.new(NAMES[2], rows, false)
			ui_root.add_child(settlement)


func clear_hud() -> void:
	for node in [hud, labels, settlement]:
		if node != null and is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.free()
	hud = null
	labels = null
	settlement = null


# —— 机位 ——

func view(name: String) -> Transform3D:
	# bomb_seat:自己座位的越肩;bomb_overview:观战俯视;bomb_close:摸到炸弹的特写(同导演的推近机位)
	match name:
		"bomb_overview":
			return world.overview_view()
		"bomb_close":
			return BombCatLayout.bomb_view(world, BOMB_PID)
	return world.third_person_view(ME)
