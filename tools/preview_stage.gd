extends RefCounted
# 截图工具(tools/shot.gd --preview=…)的悬停大图:在展台上找到要悬停的那张牌、算出光标该停在哪,
# 候选牌与牌桌屏幕同一套(CardPreview.world_candidates + HUD 的 preview_candidates),光标停的点要真的选中那张牌
# (牌扇里互相压住时取它露出来、离牌心最近的那一点)。
# 目标写法(同一次截图的几个机位按位置对应,用逗号分隔):
#   骗子酒馆(seat / fp 等):hand:N 自己的第 N 张手牌(从 0 数)、reveal:N 翻牌行第 N 张
#   德州(poker_*):hand:N 自己牌扇里的底牌、board:N 桌上第 N 张公共牌、shown:PID:N 某人亮在座位前的牌、
#                   boardstrip:N / mystrip:N 左上公共牌条 / 左下自己的小图、showdown:R:N 摊牌面板第 R 行的牌
#   炸弹猫(bomb_*):strip:N 底部 2D 手牌条、hand:N 3D 牌扇、discard 弃牌堆最上面那张
#   任何机位:at:X:Y 光标停在视口比例 (X, Y)(0–1);none 不悬停
# tools/ 不进导出包,所以不声明 class_name,用 preload 取用。

const SAMPLES := Vector2i(7, 9)   # 在目标牌的外接矩形里撒点找它露出来的位置
const POKER_ME := 1
const BOMB_ME := 1


static func kind_of(view: String) -> String:
	if view.begins_with("bomb_"):
		return "bomb_cat"
	if view.begins_with("poker_"):
		return "poker"
	return "liars"


static func candidates(kind: String, stage: Node, camera: Camera3D, point: Vector2) -> Array:
	# 同各牌桌屏幕的 _make_preview().source
	var out := []
	match kind:
		"liars":
			var table: CardTable = stage.world.cards
			out = CardPreview.world_candidates(camera, point, table.my_cards + table.revealed)
		"poker":
			if stage.hud != null:
				out.append_array(stage.hud.preview_candidates())
			out.append_array(CardPreview.world_candidates(camera, point, stage.cards.hoverable_cards(POKER_ME)))
		"bomb_cat":
			if stage.hud != null:
				out.append_array(stage.hud.strip.preview_candidates())
			out.append_array(CardPreview.world_candidates(camera, point, stage.cards.hoverable_cards()))
	return out


static func target_key(kind: String, stage: Node, target: String) -> Variant:
	# 目标牌的实例 id(与候选里的 key 对得上);认不出来返回 null
	var parts := target.split(":")
	var n := int(parts[1]) if parts.size() > 1 else 0
	var node: Object = null
	match [kind, parts[0]]:
		["liars", "hand"]:
			node = _at(stage.world.cards.my_cards, n)
		["liars", "reveal"]:
			node = _at(stage.world.cards.revealed, n)
		["poker", "hand"]:
			var fan: Node3D = stage.world.patrons[POKER_ME].fan
			node = _at(stage.cards.hoverable_cards(POKER_ME).filter(func(c): return c.get_parent() == fan), n)
		["poker", "board"]:
			node = _at(stage.cards.board_cards(), n)
		["poker", "shown"]:
			node = _at(stage.cards.shown_cards(n), int(parts[2]) if parts.size() > 2 else 0)
		["poker", "boardstrip"]:
			return _key_at(stage.hud.board_strip.preview_candidates(), n)
		["poker", "mystrip"]:
			return _key_at(stage.hud.my_strip.preview_candidates(), n)
		["poker", "showdown"]:
			var strip: CardStrip = _at(stage.hud.showdown.strips(), n)
			return _key_at(strip.preview_candidates(), int(parts[2]) if parts.size() > 2 else 0) if strip != null else null
		["bomb_cat", "strip"]:
			return _key_at(stage.hud.strip.preview_candidates(), n)
		["bomb_cat", "hand"]:
			node = _at(stage.cards.held_cards(BOMB_ME), n)
		["bomb_cat", "discard"]:
			var held: Array = stage.cards.held_cards(BOMB_ME)
			var pile: Array = stage.cards.hoverable_cards().filter(func(c): return not held.has(c))
			node = pile[-1] if not pile.is_empty() else null
	return node.get_instance_id() if node != null else null


static func point_for(kind: String, stage: Node, camera: Camera3D, target: String, viewport: Vector2) -> Vector2:
	# 光标该停的位置(视口坐标);找不到目标时给 (-1, -1)
	if target.begins_with("at:"):
		var xy := target.split(":")
		return Vector2(float(xy[1]), float(xy[2]) if xy.size() > 2 else 0.5) * viewport
	var key: Variant = target_key(kind, stage, target)
	if key == null:
		push_warning("--preview: 找不到 %s 的目标 %s" % [kind, target])
		return Vector2(-1, -1)
	var quad := PackedVector2Array()
	for c in candidates(kind, stage, camera, Vector2.ZERO):
		if c.get("key") == key:
			quad = c["quad"]
	if quad.is_empty():
		return Vector2(-1, -1)
	var bounds := CardPreview.bounds_of(quad)
	var center := bounds.get_center()
	var points := []
	for i in SAMPLES.x:
		for j in SAMPLES.y:
			points.append(bounds.position + bounds.size * Vector2((i + 0.5) / SAMPLES.x, (j + 0.5) / SAMPLES.y))
	points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(center) < b.distance_squared_to(center))
	for p: Vector2 in points:
		var list := candidates(kind, stage, camera, p)
		var index := CardPreview.pick(p, list)
		if index >= 0 and list[index].get("key") == key:
			return p
	return center


static func _at(list: Array, index: int) -> Variant:
	return list[index] if index >= 0 and index < list.size() else null


static func _key_at(list: Array, index: int) -> Variant:
	var c: Variant = _at(list, index)
	return c.get("key") if c is Dictionary else null
