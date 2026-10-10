extends SceneTree
# 穿模测量报告(规格 2026-10-08-cozy-toon-style-design §穿模修复):牌 / 头 / 手臂与酒客网格的相交次数,改动前后各跑一遍对比。
# 用法:godot --headless --path . --fixed-fps 60 -s tools/clip_report.gd [-- --only=fan,neck,arms,fp,table,dead] [--verbose]
# 判定方法见 tests/clip_probe.gd(按真实三角形,TriangleMesh 线段求交)。各类别:
# - fan   他人的牌扇 vs 持牌者自己(头 / 躯干 / 手臂):8 个物种 × 牌扇(骗子酒馆 5 张、德州 2 张、炸弹猫 8 / 14 张)×
#         转头包络(俯仰到物种下限再减待机噪声与说话点头、左右转、歪头)× 坐着 / 轮到他前倾,外加被平底锅拍扁的头
# - neck  探头网格(座位坐标,正前 ±90°、0.15–3 米):头 vs 自己的牌扇、别人的身体与头、别人的牌扇、桌心立牌 / 公共牌 / 吊灯
# - arms  手势逐帧(出牌伸手、拍桌、捂嘴、讨要、放大镜、拆弹、抹脸、丢番茄、举枪、欢呼、跳舞、鼓掌):手臂 vs 牌扇、爪子 vs 自己的头
# - fp    第一人称探头时手里的牌扇 vs 别人(身体、头、牌扇)、立牌、吊灯
# - table 桌上的牌(翻牌行、出牌区、德州公共牌与亮牌、炸弹猫牌堆)vs 酒客(坐着、前倾、出牌伸手)
# - dead  出局倒下(骗子酒馆中枪、炸弹猫炸飞)时扣在大腿上的牌扇 vs 自己

const Probe := preload("res://tests/clip_probe.gd")
const CATEGORIES := ["fan", "neck", "arms", "fp", "table", "dead"]
const LAMP_MOUTH_Y := 1.885     # 吊灯罩口(世界高度,LampProp.MOUTH_Y − BEAD + 枢轴)
const LAMP_RADIUS := 0.38       # 罩口半径 + 珠边
const NECK_ANGLES := 13         # 探头网格:正前 ±90° 每 15°
const NECK_RADII := [0.15, 0.3, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0]

var opts := {}
var results := []   # [类别, 项目, 命中, 样本]


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _wanted(cat: String) -> bool:
	return not opts.has("only") or cat in opts["only"].split(",")


func _run() -> void:
	var started := Time.get_ticks_msec()
	if _wanted("fan"):
		await _fan()
	if _wanted("neck"):
		await _neck()
	if _wanted("arms"):
		await _arms()
	if _wanted("fp"):
		await _fp()
	if _wanted("table"):
		await _table()
	if _wanted("dead"):
		await _dead()
	print("\n==== 穿模报告(命中 / 样本)====")
	var sums := {}
	for r in results:
		print("%-6s %-44s %6d / %d" % r)
		if not sums.has(r[0]):
			sums[r[0]] = [0, 0]
		sums[r[0]][0] += r[2]
		sums[r[0]][1] += r[3]
	print("---- 合计 ----")
	for cat in sums:
		print("%-6s %6d / %d" % [cat, sums[cat][0], sums[cat][1]])
	print("用时 %.1f 秒" % ((Time.get_ticks_msec() - started) / 1000.0))
	quit()


func _record(cat: String, item: String, hits: int, samples: int) -> void:
	results.append([cat, item, hits, samples])
	if opts.has("verbose"):
		print("%-6s %-44s %6d / %d" % [cat, item, hits, samples])


# —— 搭台 ——

func _make_world(species: Array, radius := SeatLayout.TABLE_RADIUS, revolvers := false) -> TableWorld:
	var world := TableWorld.new(null)
	root.add_child(world)
	if radius != SeatLayout.TABLE_RADIUS:
		world.configure_table(radius)
	var players := []
	for i in species.size():
		players.append({"pid": i + 1, "species": species[i]})
	world.arrange(players, 1, true, revolvers)
	await create_timer(0.8).timeout   # 登场缩放走完
	if opts.has("no-guard"):   # 对比:关掉探头的软碰撞(改动之前的探头)
		for pid in world.patrons:
			world.patrons[pid].guard = null
	return world


func _ddz_stage(world: TableWorld) -> void:
	# 斗地主:越肩机位换成斗地主的,2 号当地主戴瓜皮帽、其余戴草帽(同 DouDizhuScreen / DdzDirector)
	world.third_person_override = DdzLayout.THIRD_PERSON
	for pid in world.patrons:
		DdzHats.put_on(world.patrons[pid], DdzState.ROLE_LANDLORD if pid == 2 else DdzState.ROLE_FARMER, false)


func _drop_world(world: TableWorld) -> void:
	world.queue_free()
	await process_frame


static func fill_fan(p: Patron, kind: String, count: int) -> void:
	for c in p.fan.get_children():
		if c is Card3D:
			p.fan.remove_child(c)
			c.free()
	for i in count:
		var card := Card3D.new()
		p.fan.add_child(card)
		card.transform = BombCatLayout.fan_slot(i, count) if kind in ["bomb", "ddz"] else CardTable.fan_slot(i, count, 0.0)


static func pitch_floor(p: Patron) -> float:
	# 转头包络的最低俯仰:物种看向下限 − 待机噪声(0.05)− 说话点头(PatronAntics.NOD)
	return float(p._look_data.get("anim", {}).get("look_pitch_min", -0.45)) - 0.05 - PatronAntics.NOD


static func head_envelope(p: Patron) -> Array:
	var lo := pitch_floor(p)
	var out := []
	for pitch in [lo, lo * 0.5, 0.0, 0.3, 0.55]:
		for yaw in [-0.95, -0.5, 0.0, 0.5, 0.95]:
			for roll in [-0.3, 0.0, 0.3]:
				out.append(Vector3(pitch, yaw, roll))
	return out


func _present_self(world: TableWorld, mode: String) -> void:
	# 越肩机位下自己的牌扇,同各玩法的摆法
	var me: Patron = world.patrons[1]
	var seat := world.seat_transform(world.seat_angles[1])
	var view := world.third_person_view(1).origin
	match mode:
		"dice":
			return   # 吹牛骰子没有牌
		"ddz":
			me.present_hand_to(view)   # 同 DdzCards:越肩举牌再缩小、往右下挪
			me.hold_fan(me.fan.transform.translated(DdzLayout.FAN_SHIFT_ME))
			me.hold_fan(me.fan.transform.scaled_local(Vector3.ONE * DdzLayout.FAN_SCALE_ME))
		"poker":
			me.hold_fan(PokerLayout.fan_transform(seat, view))
		"bomb":
			me.hold_fan(PokerLayout.fan_transform(seat, view).translated(Vector3.UP * BombCatLayout.BIG_TABLE_FAN_RAISE))
			me.hold_fan(me.fan.transform.scaled_local(Vector3.ONE * BombCatLayout.MY_FAN_SCALE))
		_:
			me.present_hand_to(view)


func _present_fp(world: TableWorld, mode: String) -> void:
	world.first_person = true
	var me: Patron = world.patrons[1]
	var seat := world.seat_transform(world.seat_angles[1])
	var view := world.first_person_rest_view(1)
	match mode:
		"poker":
			me.present_hand_first_person(seat, view, PokerLayout.FP_FAN_CAM, PokerLayout.FP_FAN_SCALE)
		"bomb":
			me.present_hand_first_person(seat, view, BombCatLayout.FP_FAN_CAM, BombCatLayout.FP_FAN_SCALE)
		"ddz":
			me.present_hand_first_person(seat, view, DdzLayout.FP_FAN_CAM, DdzLayout.FP_FAN_SCALE)
		_:
			me.present_hand_first_person(seat, view)


func _table_cards(world: TableWorld, mode: String) -> Array:
	# 桌上的牌(挂在 world.cards 下,测完随牌桌一起释放)
	var out := []
	var xforms := []
	match mode:
		"poker":
			world.clip_guard.set_prop(&"poker_board", BoardRack.guard_shape(world.poker_root))   # 同 PokerCards
			for i in PokerRules.BOARD_CARDS:
				xforms.append(PokerLayout.board_slot(i))
			for pid in world.seat_angles:
				for i in PokerRules.HOLE_CARDS:
					xforms.append(PokerLayout.shown_card(world.seat_angles[pid], world.table_radius, i))
			for i in 4:
				xforms.append(PokerLayout.muck_slot(i))
		"ddz":
			xforms.append(DdzLayout.deck_transform(10))
			for i in 3:
				xforms.append(DdzLayout.bottom_slot(i, true))
			for pid in world.seat_angles:
				for i in 12:   # 最长的一行(顺子 / 飞机):MAX_ROW 封顶
					xforms.append(DdzLayout.play_slot(world.seat_angles[pid], pid == 1, i, 12))
		"bomb":
			xforms.append(BombCatLayout.deck_top(30))
			for i in BombCatLayout.DISCARD_SHOWN:
				xforms.append(BombCatLayout.discard_slot(i))
		_:
			for i in 3:
				xforms.append(CardTable.reveal_transform(i, 3))
			for i in 8:
				xforms.append(CardTable.pile_transform(i, 1))
	for xf in xforms:
		var card := Card3D.new()
		world.cards.add_child(card)
		card.transform = xf
		out.append(card)
	return out


func _static_meshes(world: TableWorld, mode: String) -> Array:
	# 桌上的道具:骗子酒馆的目标牌立牌(底座、夹子、牌);吹牛骰子的骰盅与桌心出价标记(同 tools/liars_dice_showcase.gd 搭)
	var out := []
	if mode == "dice":
		var cups := LiarsDiceCups.new(world)
		world.poker_root.add_child(cups)
		var fx := LiarsDiceFx.new(world)
		world.poker_root.add_child(fx)
		cups.setup(world.seat_angles.keys(), {})
		fx.bid_marker(3, 4)
		for node in world.poker_root.find_children("*", "MeshInstance3D", true, false):
			if (node as MeshInstance3D).is_visible_in_tree():
				out.append(node)
		return out
	if mode == "liars":
		for node in world.cards.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var stand: Node3D = world.cards.get_node("TargetStand")
			if stand.is_ancestor_of(mi) and mi.is_visible_in_tree():
				out.append(mi)
	return out


static func lamp_hits(p: Patron) -> bool:
	# 吊灯罩(解析形状):头部外壳点伸进罩口以上、半径以内就算碰到
	for s in Probe.head_spokes(p):
		var e: Vector3 = s[1]
		if e.y > LAMP_MOUTH_Y and Vector2(e.x, e.z).length() < LAMP_RADIUS:
			return true
	return false


static func head_in_table(p: Patron, world: TableWorld) -> bool:
	# 头(外壳)伸进桌面以下:外壳点低于桌面木板顶、又在桌面范围内
	for sp in Probe.head_spokes(p):
		var e: Vector3 = world.to_local(sp[1])
		if e.y < SeatLayout.TABLE_TOP and Vector2(e.x, e.z).length() < world.table_radius:
			return true
	return false


static func neck_targets() -> Array:
	var out := []
	for i in NECK_ANGLES:
		var a := deg_to_rad(-90.0 + 180.0 * i / (NECK_ANGLES - 1))
		for r in NECK_RADII:
			out.append(Vector3(sin(a), 0.0, -cos(a)) * r)
	return out


# —— fan:他人的牌扇 vs 持牌者自己 ——

func _fan() -> void:
	var fans := [["liars", 5], ["poker", 2], ["bomb", 8], ["bomb", 14], ["ddz", 20]]
	var totals := {}
	for s in Species.count():
		var world := await _make_world([(s + 1) % Species.count(), s], SeatLayout.TABLE_RADIUS, true)
		var p: Patron = world.patrons[2]
		Probe.freeze(p)
		var head := Probe.patron_meshes(p, "head")
		var torso := Probe.patron_meshes(p, "torso")
		var arms := Probe.patron_meshes(p, "arms")
		var gun: Array = world.revolvers[2].find_children("*", "MeshInstance3D", true, false)
		for f in fans:
			fill_fan(p, f[0], f[1])
			if f[0] == "ddz":   # 斗地主戴着身份帽(草帽帽檐最宽)
				DdzHats.put_on(p, DdzState.ROLE_FARMER, false)
				head = Probe.patron_meshes(p, "head")
			var cards := Probe.fan_cards(p)
			var key := "%s%d" % f
			var hit := {"head": 0, "torso": 0, "arms": 0, "gun": 0, "table(head)": 0}
			var n := 0
			for active in [false, true]:
				p.set_active(active)
				var poses := head_envelope(p)
				for rot in poses:
					Probe.pose(p, rot)
					n += 1
					if Probe.cards_hitting(cards, head) > 0 or Probe.cards_in_head(p, cards) > 0:
						hit["head"] += 1
						if opts.has("poses"):
							print("  hit %s %s active=%s rot=%s" % [Species.IDS[s], key, active, rot])
					if Probe.cards_hitting(cards, torso) > 0:
						hit["torso"] += 1
					if Probe.cards_hitting(cards, arms) > 0:
						hit["arms"] += 1
					if f[0] == "liars" and Probe.cards_hitting(cards, gun) > 0:   # 只有骗子酒馆桌上有枪
						hit["gun"] += 1
					if head_in_table(p, world):
						hit["table(head)"] += 1
						if opts.has("poses"):
							print("  table %s active=%s rot=%s" % [Species.IDS[s], active, rot])
			# 被平底锅拍扁的头(炸弹猫「甩锅」):横向放大 1.2 倍
			Probe.pose(p, Vector3.ZERO, Vector3.ZERO, 0.0, Patron.BONK_SQUASH)
			n += 1
			if Probe.cards_hitting(cards, head) > 0:
				hit["head"] += 1
				if opts.has("poses"):
					print("  hit %s %s bonk" % [Species.IDS[s], key])
			p.head.scale = Vector3.ONE
			for part in hit:
				_record("fan", "%s %s vs %s" % [Species.IDS[s], key, part], hit[part], n)
				var t := "%s vs %s" % [key, part]
				if not totals.has(t):
					totals[t] = [0, 0]
				totals[t][0] += hit[part]
				totals[t][1] += n
		await _drop_world(world)
	for t in totals:
		_record("fan", "全部物种 " + t, totals[t][0], totals[t][1])


# —— neck:探头 ——

func _neck_worlds() -> Array:
	return [["liars", [0, 1, 2, 3], SeatLayout.TABLE_RADIUS, 5], ["liars", [4, 5, 6, 7], SeatLayout.TABLE_RADIUS, 5],
		["poker", [0, 1, 2, 3, 4, 5, 6, 7], SeatLayout.POKER_TABLE_RADIUS, 2],
		["bomb", [3, 7, 5, 0, 1, 2], SeatLayout.POKER_TABLE_RADIUS, 5],
		["dice", [7, 5, 3, 0], SeatLayout.TABLE_RADIUS, 0], ["dice", [1, 2, 4, 6, 7, 5], SeatLayout.POKER_TABLE_RADIUS, 0],
		["ddz", [0, 3, 7], SeatLayout.TABLE_RADIUS, 17], ["ddz", [5, 7, 3], SeatLayout.TABLE_RADIUS, 20]]


func _neck() -> void:
	var sums := {"own_fan": [0, 0], "others": [0, 0], "other_fans": [0, 0], "props": [0, 0], "lamp": [0, 0], "fan_table": [0, 0]}
	for spec in _neck_worlds():
		var mode: String = spec[0]
		var world := await _make_world(spec[1], spec[2])
		if mode == "ddz":
			_ddz_stage(world)
		if mode != "liars":
			world.cards.set_stand_visible(false)
		for pid in world.patrons:
			if pid != 1:
				fill_fan(world.patrons[pid], mode, spec[3])
		fill_fan(world.patrons[1], mode, spec[3])
		_present_self(world, mode)
		var props := _static_meshes(world, mode)
		var table := _table_cards(world, mode) if mode != "liars" else []
		for pid in world.patrons:
			Probe.freeze(world.patrons[pid])
			Probe.pose(world.patrons[pid])
		for pid in world.patrons:
			var p: Patron = world.patrons[pid]
			var own := Probe.fan_cards(p)
			var head := Probe.patron_meshes(p, "head")
			var others := []
			var other_cards := []
			for q in world.patrons:
				if q != pid:
					others.append_array(Probe.patron_meshes(world.patrons[q]))
					other_cards.append_array(Probe.fan_cards(world.patrons[q]))
			var hit := {"own_fan": 0, "others": 0, "other_fans": 0, "props": 0, "lamp": 0, "fan_table": 0}
			var targets := neck_targets()
			for target in targets:
				Probe.pose(p, Vector3.ZERO, target)
				if Probe.cards_hitting(own, head) > 0:
					hit["own_fan"] += 1
					if opts.has("poses"):
						print("  own %s %s pid%d %s -> %s" % [mode, Species.IDS[p.species_index], pid, target, p.neck_offset()])
				if Probe.head_hits(p, others) > 0:
					hit["others"] += 1
					if opts.has("poses"):
						print("  others %s %s pid%d %s -> %s" % [mode, Species.IDS[p.species_index], pid, target, p.neck_offset()])
						for mi in others:
							if Probe.head_hits(p, [mi]) > 0:
								print("     hits %s of %s" % [mi.name, mi.get_parent().name])
				if Probe.cards_hitting(other_cards, head) > 0:
					hit["other_fans"] += 1
					if opts.has("poses"):
						print("  ofans %s %s pid%d %s -> %s" % [mode, Species.IDS[p.species_index], pid, target, p.neck_offset()])
				if Probe.head_hits(p, props) > 0 or Probe.cards_hitting(table, head) > 0:
					hit["props"] += 1
					if opts.has("poses"):
						print("  props %s %s pid%d %s -> %s" % [mode, Species.IDS[p.species_index], pid, target, p.neck_offset()])
						for card in table:
							for mi in head:
								if Probe.segments_hit(Probe.card_segments(card), mi) > 0:
									print("     card %s scale %s hits %s" % [world.to_local(card.global_position), card.scale, mi.name])
				if lamp_hits(p):
					hit["lamp"] += 1
				var crossed := false
				for a in own:
					for b in table:
						if not crossed and _cards_cross(a, b):
							crossed = true
				if crossed:
					hit["fan_table"] += 1
					if opts.has("poses"):
						print("  fan_table %s %s pid%d %s" % [mode, Species.IDS[p.species_index], pid, target])
			Probe.pose(p)
			for k in hit:
				sums[k][0] += hit[k]
				sums[k][1] += targets.size()
				if opts.has("verbose"):
					_record("neck", "%s %s %s" % [mode, Species.IDS[p.species_index], k], hit[k], targets.size())
		await _drop_world(world)
	for k in sums:
		_record("neck", "头 vs " + {"own_fan": "自己的牌扇(含脖子)", "others": "别人的身体与头", "other_fans": "别人的牌扇",
			"props": "桌心立牌 / 公共牌 / 牌堆", "lamp": "吊灯", "fan_table": "(倒下的)自己的牌扇 vs 桌上的牌"}[k], sums[k][0], sums[k][1])


# —— arms:手势逐帧 ——

const GESTURES := ["rest_active", "reach", "slam", "cover", "plead", "peek", "snip", "wipe", "throw", "gun", "cheer",
	"clap", "dance"]


func _arms() -> void:
	var sums := {}
	for s in Species.count():
		var world := await _make_world([(s + 1) % Species.count(), s], SeatLayout.TABLE_RADIUS, true)
		var me: Patron = world.patrons[1]
		var p: Patron = world.patrons[2]
		fill_fan(p, "liars", 5)
		fill_fan(me, "liars", 5)
		_present_self(world, "liars")
		for who in [["opp", p], ["self", me]]:
			var q: Patron = who[1]
			var arms := Probe.patron_meshes(q, "arms")
			var paws := arms.filter(func(m): return m.name in ["PawMesh", "FistMesh"])
			var head := Probe.patron_meshes(q, "head")
			for g in GESTURES:
				q.reset_pose()
				await create_timer(0.4).timeout
				var frames := await _gesture(world, q, g)
				var fan_hits := 0
				var face_hits := 0
				for i in frames:
					await process_frame
					var cards := Probe.fan_cards(q)
					if Probe.cards_hitting(cards, arms) > 0:
						fan_hits += 1
					# 爪子碰脸:捂嘴、抹脸、放大镜、讨要本来就贴着脸,不算
					if not g in ["cover", "wipe", "peek", "plead"] and _paws_in_head(q, paws, head):
						face_hits += 1
				q.stop_dance()
				var key := "%s %s" % [who[0], g]
				for part in [["vs fan", fan_hits], ["paw vs face", face_hits]]:
					var k: String = key + " " + part[0]
					if not sums.has(k):
						sums[k] = [0, 0]
					sums[k][0] += part[1]
					sums[k][1] += frames
		await _drop_world(world)
	for k in sums:
		if sums[k][0] > 0 or opts.has("verbose") or k.ends_with("vs fan"):
			_record("arms", k, sums[k][0], sums[k][1])


func _paws_in_head(q: Patron, paws: Array, head: Array) -> bool:
	return Probe.head_hits(q, paws) > 0


func _gesture(world: TableWorld, q: Patron, g: String) -> int:
	# 开始一个手势(不等它结束),返回要逐帧取样的帧数
	match g:
		"rest_active":
			q.set_active(true)
			return 40
		"reach":
			q.reach_toward_center()
			return 40
		"slam":
			q.slam_table()
			return 45
		"cover":
			q.cover_mouth()
			return 60
		"plead":
			q.plead()
			return 70
		"peek":
			q.peek_with_glass()
			return 60
		"snip":
			q.snip_wires()
			return 70
		"wipe":
			q.hit_by_tomato(Vector3.ZERO)
			return 60
		"throw":
			var other: Patron = world.patrons[1] if q != world.patrons[1] else world.patrons[2]
			q.throw_at(other.head_position())
			return 45
		"gun":
			var pid := 1 if q == world.patrons[1] else 2
			_gun(q, world.revolvers[pid])
			return 80
		"cheer":
			q.celebrate()
			return 60
		"clap":
			q.clap(7)
			return 120
		"dance":
			q.dance(-1, 3)
			return 150
	return 1


func _gun(q: Patron, gun: Node3D) -> void:
	await q.pick_up(gun, 0.3)
	await q.raise_gun_to_head(gun, 0.35)


# —— fp:第一人称手里的牌扇 ——

func _fp() -> void:
	var sums := {"others": [0, 0], "props": [0, 0], "lamp": [0, 0]}
	for spec in _neck_worlds():
		var mode: String = spec[0]
		var world := await _make_world(spec[1], spec[2])
		if mode == "ddz":
			_ddz_stage(world)
		if mode != "liars":
			world.cards.set_stand_visible(false)
		for pid in world.patrons:
			fill_fan(world.patrons[pid], mode, spec[3])
		_present_fp(world, mode)
		var props := _static_meshes(world, mode)
		var table := _table_cards(world, mode) if mode != "liars" else []
		for pid in world.patrons:
			Probe.freeze(world.patrons[pid])
			Probe.pose(world.patrons[pid])
		var me: Patron = world.patrons[1]
		var others := []
		for q in world.patrons:
			if q != 1:
				others.append_array(Probe.patron_meshes(world.patrons[q]))
		var hit := {"others": 0, "props": 0, "lamp": 0}
		var targets := neck_targets()
		for target in targets:
			Probe.pose(me, Vector3.ZERO, target)
			var cards := Probe.fan_cards(me)
			if Probe.cards_hitting(cards, others) > 0:
				hit["others"] += 1
			var on_props := Probe.cards_hitting(cards, props) > 0
			for card in cards:
				for t in table:
					if _cards_cross(card, t):
						on_props = true
			if on_props:
				hit["props"] += 1
			for card in cards:
				var c: Vector3 = card.global_position
				if c.y > LAMP_MOUTH_Y - 0.1 and Vector2(c.x, c.z).length() < LAMP_RADIUS:
					hit["lamp"] += 1
					break
		for k in hit:
			sums[k][0] += hit[k]
			sums[k][1] += targets.size()
		await _drop_world(world)
	for k in sums:
		_record("fp", "第一人称牌扇 vs " + {"others": "别人(身体、头)", "props": "立牌 / 桌上的牌", "lamp": "吊灯"}[k],
			sums[k][0], sums[k][1])


static func _cards_cross(a: Node3D, b: Node3D) -> bool:
	# 两张牌相交:a 的检测线穿过 b 的牌面(两个三角形)
	var xf := b.global_transform
	var h := Vector2(Card3D.WIDTH, Card3D.HEIGHT) * 0.5
	var p0 := xf * Vector3(-h.x, 0, -h.y)
	var p1 := xf * Vector3(h.x, 0, -h.y)
	var p2 := xf * Vector3(h.x, 0, h.y)
	var p3 := xf * Vector3(-h.x, 0, h.y)
	for s in Probe.card_segments(a):
		if Geometry3D.segment_intersects_triangle(s[0], s[1], p0, p1, p2) != null \
				or Geometry3D.segment_intersects_triangle(s[0], s[1], p0, p2, p3) != null:
			return true
	return false


# —— table:桌上的牌 vs 酒客 ——

func _table() -> void:
	for spec in _neck_worlds():
		var mode: String = spec[0]
		var world := await _make_world(spec[1], spec[2])
		if mode == "ddz":
			_ddz_stage(world)
		if mode != "liars":
			world.cards.set_stand_visible(false)
		var table := _table_cards(world, mode)
		var meshes := []
		for pid in world.patrons:
			meshes.append_array(Probe.patron_meshes(world.patrons[pid]))
		var hits := 0
		var n := 0
		for phase in ["seated", "active", "reach"]:
			for pid in world.patrons:
				var q: Patron = world.patrons[pid]
				q.set_active(phase != "seated")
				if phase == "reach":
					q.reach_toward_center()
			for i in 30:
				await process_frame
				n += 1
				if Probe.cards_hitting(table, meshes) > 0:
					hits += 1
		_record("table", "%s %s 桌上的牌 vs 酒客" % [mode, spec[1]], hits, n)
		await _drop_world(world)


# —— dead:出局倒下 ——

func _dead() -> void:
	var hits := 0
	var gun_hits := 0
	var n := 0
	for s in Species.count():
		for who in [2, 1]:
			var world := await _make_world([(s + 1) % Species.count(), s] if who == 2 else [s, (s + 1) % Species.count()],
				SeatLayout.TABLE_RADIUS, true)
			var p: Patron = world.patrons[who]
			fill_fan(p, "liars", 5)
			if who == 1:
				_present_self(world, "liars")
			var meshes := Probe.patron_meshes(p)
			var gun: Node3D = world.revolvers[who]
			var gun_meshes: Array = gun.find_children("*", "MeshInstance3D", true, false)
			p.die(gun, world)
			var mine := 0
			for i in 90:
				await process_frame
				var cards := Probe.fan_cards(p)
				if Probe.cards_hitting(cards, meshes) > 0:
					mine += 1
				if Probe.cards_hitting(cards, gun_meshes) > 0:
					gun_hits += 1
					if opts.has("poses"):
						print("  gun %s %s frame %d gun %s" % [Species.IDS[s], who, i, p.to_local(gun.global_position)])
			hits += mine
			n += 90
			if opts.has("verbose"):
				_record("dead", "%s %s" % [Species.IDS[s], "opp" if who == 2 else "self"], mine, 90)
			await _drop_world(world)
	_record("dead", "出局倒下时的牌扇 vs 自己", hits, n)
	_record("dead", "出局倒下时的牌扇 vs 掉在桌上的枪", gun_hits, n)
