class_name WorldLabels
extends Control
# 3D 锚定的 2D 控件:每帧把控件投影到世界坐标点上方(铭牌、对话气泡)。
# 锚点在相机背后或屏幕外时隐藏。
# 登记时 avoid = true 的控件(各种对话气泡)摆好之后再让位:和铭牌、先登记的气泡重叠时左右挪开
# (对面的人铭牌贴着画面上缘时,声称气泡、九宫格气泡都被收进画面、叠在同一处;邻座的气泡也会撞在一起)。
# 牌桌 HUD 的角落面板(左上信息、右上按钮、摊牌面板)加进 KEEP_OUT_GROUP,气泡同样让开它们,不盖住目标牌、底池;
# 铭牌也让开它们(只往下挪):对面座位的铭牌贴着画面上缘时原来被右上的按钮行盖住。
# 条目里的控件可能已自行释放(气泡淡出后 queue_free):取出时先用无类型变量判有效,
# 已释放的实例赋给 Control 类型变量或作为 Control 返回值本身就是脚本错误。


const EDGE_MARGIN := 4.0   # 控件离屏幕边缘的最小距离
const AVOID_GAP := 4.0     # 让位时和别的控件之间留的空隙
const KEEP_OUT_GROUP := "world_label_keep_out"   # 这一组里看得见的控件也是让位的障碍(HUD 的角落面板)

var camera: Camera3D
var _entries := {}   # key -> {"node": Control, "anchor": Callable, "offset": Vector2 或返回 Vector2 的 Callable, "avoid": bool}


func _init(p_camera: Camera3D) -> void:
	camera = p_camera


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func track(key: String, node: Control, anchor: Callable, offset: Variant = Vector2.ZERO, avoid := false) -> void:
	# offset 可以是每帧现算的 Callable(快捷语气泡叠在铭牌、声称气泡之上,高度跟着它们变);
	# avoid:摆好后和别的控件重叠就左右让开(对话气泡用;铭牌不用,它要跟着头)
	untrack(key)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	_entries[key] = {"node": node, "anchor": anchor, "offset": offset, "avoid": avoid}
	_place(node, _entries[key])


func untrack(key: String) -> void:
	if not _entries.has(key):
		return
	var node = _entries[key]["node"]
	_entries.erase(key)
	if is_instance_valid(node):
		node.queue_free()


func anchor_of(key: String) -> Callable:
	# 某个条目的世界锚点(没有时返回空 Callable):快捷语气泡挂在铭牌的同一个锚点上(德州铭牌按座位错开高度)
	if not _entries.has(key) or not is_instance_valid(_entries[key]["node"]):
		return Callable()
	return _entries[key]["anchor"]


func get_node_for(key: String) -> Control:
	if not _entries.has(key):
		return null
	var node = _entries[key]["node"]
	return node if is_instance_valid(node) else null


func clear() -> void:
	for key in _entries.keys():
		untrack(key)


func _process(_delta: float) -> void:
	# 两遍:先摆固定偏移的(铭牌、声称气泡、九宫格快捷对话气泡),再摆偏移现算的(快捷语气泡);
	# 后者读前者这一帧的位置叠上去,镜头在动时也不会差一帧而压到别人身上
	for dependent in [false, true]:
		for key in _entries.keys():
			var entry: Dictionary = _entries[key]
			var node = entry["node"]
			if not is_instance_valid(node):
				_entries.erase(key)
				continue
			if (entry["offset"] is Callable) == dependent:
				_place(node, entry)
	_separate()


func _separate() -> void:
	# 让位:HUD 的角落面板先当障碍;铭牌只让开 HUD(贴着画面上缘、被收到右上按钮行底下时往下挪到按钮下面,
	# 不横着挪,免得离开自己的头太远),再当障碍;让位的气泡按「固定偏移的先、现算偏移的后,同一遍里先登记的先」
	# 逐个摆:和已经摆好的重叠就左右或往下挪到最近的空处(挪动量取各障碍边缘处,挑最小又不出画面的);
	# 都没有空处就留在原处。每帧从 _place 的原位重新算,不累积
	var hud_rects: Array[Rect2] = []
	var to_local := get_global_transform_with_canvas().affine_inverse()
	for hud in get_tree().get_nodes_in_group(KEEP_OUT_GROUP):
		if hud is Control and hud.is_visible_in_tree():
			hud_rects.append(to_local * hud.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, hud.size))
	var placed: Array[Rect2] = hud_rects.duplicate()
	var movers: Array = []
	for dependent in [false, true]:
		for key in _entries:
			var entry: Dictionary = _entries[key]
			var node = entry["node"]
			if not is_instance_valid(node) or not node.visible or (entry["offset"] is Callable) != dependent:
				continue
			if entry.get("avoid", false):
				movers.append(node)
				continue
			var plate := clear_spot(Rect2(node.position, node.size), hud_rects, size, false)
			node.position = plate.position
			placed.append(plate)
	for node in movers:
		var rect := clear_spot(Rect2(node.position, node.size), placed, size)
		node.position = rect.position
		placed.append(rect)


static func clear_spot(rect: Rect2, obstacles: Array[Rect2], area: Vector2, sideways := true) -> Rect2:
	# rect 和 obstacles 都不重叠时原样返回;否则挪到最近的空处:先试横着挪(sideways,气泡往下挪会压到头上),
	# 横着没地方(或不许横挪)再往下挪;不出 [EDGE_MARGIN, area − EDGE_MARGIN];没有空处原样返回
	if not _hits(rect, obstacles):
		return rect
	var across: Array[Vector2] = []
	var down: Array[Vector2] = []
	for other in obstacles:
		if sideways:
			across.append(Vector2(other.end.x + AVOID_GAP - rect.position.x, 0.0))
			across.append(Vector2(other.position.x - AVOID_GAP - rect.end.x, 0.0))
		if other.end.y + AVOID_GAP > rect.position.y:
			down.append(Vector2(0.0, other.end.y + AVOID_GAP - rect.position.y))
	across.sort_custom(func(a: Vector2, b: Vector2) -> bool: return absf(a.x) < absf(b.x))
	down.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
	for d in across + down:
		var moved := Rect2(rect.position + d, rect.size)
		if moved.position.x < EDGE_MARGIN - 0.5 or moved.end.x > area.x - EDGE_MARGIN + 0.5 \
				or moved.end.y > area.y - EDGE_MARGIN + 0.5:
			continue
		if not _hits(moved, obstacles):
			return moved
	return rect


static func _hits(rect: Rect2, obstacles: Array[Rect2]) -> bool:
	for other in obstacles:
		if rect.intersects(other):
			return true
	return false


func _place(node: Control, entry: Dictionary) -> void:
	var anchor: Callable = entry["anchor"]
	if not anchor.is_valid() or camera == null or not camera.is_inside_tree():
		node.visible = false
		return
	var world_pos: Vector3 = anchor.call()
	if camera.is_position_behind(world_pos):
		node.visible = false
		return
	var screen := camera.unproject_position(world_pos)
	# unproject 返回视口坐标;换算到本控件所在画布层的本地坐标
	var pos := get_global_transform_with_canvas().affine_inverse() * screen
	node.visible = get_rect().grow(80).has_point(pos)
	var offset: Variant = entry["offset"]
	if offset is Callable:
		offset = offset.call() if offset.is_valid() else Vector2.ZERO
	var top_left: Vector2 = pos - Vector2(node.size.x / 2.0, node.size.y) + offset
	# 贴边时收进屏幕内(画面上缘的对手气泡不被裁掉)
	var limit := (size - node.size - Vector2(EDGE_MARGIN, EDGE_MARGIN)).max(Vector2(EDGE_MARGIN, EDGE_MARGIN))
	node.position = top_left.clamp(Vector2(EDGE_MARGIN, EDGE_MARGIN), limit).round()
