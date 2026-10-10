class_name DdzHandStrip
extends Control
# 斗地主底部的 2D 手牌条(操作主入口;3D 牌扇只是好看):17–20 张牌面小图,大的在左(私有视图按 id 升序存放,
# 第 i 张摆在第 count-1-i 个位置),同点数挨在一起、不同点数之间多留一道小缝;牌多时互相压住,整条不超过 MAX_WIDTH。
# 点一下选中 / 取消(抬起 + 金边);按住拖过一串牌:按第一张的新状态把扫过的牌一起选上或取消(拖回来会恢复);右键清空。
# 只发信号(selection_changed / card_hovered / reset_requested),选得上与否由牌桌决定;牌面纹理生成完重新取。


signal selection_changed(selected: Dictionary)   # 私有下标 -> true
signal card_hovered(index: int)                  # 私有下标;离开为 -1
signal reset_requested

const CARD_SIZE := Vector2(66, 96)
const GROUP_GAP := 7.0             # 不同点数之间多留的缝
const MAX_WIDTH := 780.0
const MAX_STEP := 46.0
const LIFT_SELECTED := 22.0
const LIFT_HOVER := 7.0
const DIM := Color(0.78, 0.78, 0.78, 0.95)

var _ids: Array = []
var _selected := {}
var _hovered := -1
var _enabled := true
var _cards: Array[TextureRect] = []   # 按显示位置(左 → 右)
var _xs: Array = []                   # 每个显示位置的左边缘
var _drag_from := -1                  # 拖选起点(显示位置);-1 = 没在拖
var _drag_to := -1
var _drag_on := true
var _drag_base := {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(CARD_SIZE.x, CARD_SIZE.y + LIFT_SELECTED)


func _ready() -> void:
	PokerFaces.built_signal().connect(refresh_textures)
	DdzJokerFaces.built_signal().connect(refresh_textures)


# —— 纯逻辑 ——

static func display_index(i: int, count: int) -> int:
	return count - 1 - i


static func layout_xs(ids: Array) -> Array:
	# 每个显示位置的左边缘:相邻同点数按 step,不同点数再加 GROUP_GAP;总宽超过 MAX_WIDTH 就整体压缩
	var n := ids.size()
	var xs := []
	if n == 0:
		return xs
	var gaps := 0
	for d in range(1, n):
		if DdzHand.rank(ids[display_index(d, n)]) != DdzHand.rank(ids[display_index(d - 1, n)]):
			gaps += 1
	var step := MAX_STEP
	var gap := GROUP_GAP
	var width := CARD_SIZE.x + step * (n - 1) + gap * gaps
	if width > MAX_WIDTH:
		var k := (MAX_WIDTH - CARD_SIZE.x) / maxf(step * (n - 1) + gap * gaps, 1.0)
		step *= k
		gap *= k
	var x := 0.0
	for d in n:
		if d > 0:
			x += step + (gap if DdzHand.rank(ids[display_index(d, n)]) != DdzHand.rank(ids[display_index(d - 1, n)]) else 0.0)
		xs.append(x)
	return xs


static func strip_width(ids: Array) -> float:
	var xs := layout_xs(ids)
	return 0.0 if xs.is_empty() else xs[-1] + CARD_SIZE.x


static func drag_selection(base: Dictionary, from_d: int, to_d: int, on: bool, count: int) -> Dictionary:
	# 拖选:从显示位置 from_d 拖到 to_d,扫过的牌按 on 选上或取消,其余保持拖动开始时(base)的样子
	var out := base.duplicate()
	for d in range(mini(from_d, to_d), maxi(from_d, to_d) + 1):
		if d < 0 or d >= count:
			continue
		var i := display_index(d, count)
		if on:
			out[i] = true
		else:
			out.erase(i)
	return out


# —— 状态 ——

func set_hand(ids: Array, selected: Dictionary, enabled: bool) -> void:
	var changed := ids != _ids
	_ids = ids.duplicate()
	_selected = selected.duplicate()
	_enabled = enabled
	if changed:
		_drag_from = -1
		_rebuild()
		if _hovered >= _ids.size():
			_hovered = -1
	_layout()


func ids() -> Array:
	return _ids.duplicate()


func card_count() -> int:
	return _cards.size()


func card_rect(i: int) -> Rect2:
	# 私有下标 i 那张牌在本控件里的矩形(测试与机器人模拟点击用)
	var d := display_index(i, _ids.size())
	if d < 0 or d >= _cards.size():
		return Rect2()
	return Rect2(_cards[d].position, CARD_SIZE)


func preview_candidates() -> Array:
	# 悬停大图(CardPreview)的候选:每张牌露出来的屏幕矩形;后面(右边)的牌压在前面的上面。大图让开整条手牌条
	var out := []
	if not is_visible_in_tree():
		return out
	var strip_rect := get_global_transform_with_canvas() * Rect2(Vector2.ZERO, size)
	for d in _cards.size():
		var card := _cards[d]
		var rect := card.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, card.size)
		out.append(CardPreview.rect_candidate(rect, card.texture, d, card.get_instance_id(), "", "", strip_rect))
	return out


func flash(ids_to_flash: Array) -> void:
	# 新进手的牌(底牌)闪一下金光
	for d in _cards.size():
		var i := display_index(d, _ids.size())
		if ids_to_flash.has(_ids[i]):
			var card := _cards[d]
			var tween := card.create_tween()
			tween.tween_property(card, "self_modulate", Color(1.6, 1.4, 0.9), 0.15)
			tween.tween_property(card, "self_modulate", Color.WHITE, 0.6)


func refresh_textures() -> void:
	for d in _cards.size():
		_cards[d].texture = DdzJokerFaces.texture_for(_ids[display_index(d, _ids.size())])


func _rebuild() -> void:
	for card in _cards:
		remove_child(card)
		card.queue_free()
	_cards.clear()
	var n := _ids.size()
	for d in n:
		var card := TextureRect.new()
		card.texture = DdzJokerFaces.texture_for(_ids[display_index(d, n)])
		card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_SCALE
		card.size = CARD_SIZE
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(_on_card_input.bind(d))
		card.mouse_entered.connect(_on_hover.bind(d, true))
		card.mouse_exited.connect(_on_hover.bind(d, false))
		card.draw.connect(_draw_card_overlay.bind(card, d))
		add_child(card)
		_cards.append(card)
	_xs = layout_xs(_ids)
	custom_minimum_size = Vector2(maxf(strip_width(_ids), CARD_SIZE.x), CARD_SIZE.y + LIFT_SELECTED)


func _layout() -> void:
	var n := _cards.size()
	var width := strip_width(_ids)
	var left := (size.x - width) / 2.0 if size.x > width else 0.0
	for d in n:
		var i := display_index(d, n)
		var card := _cards[d]
		var lift := LIFT_SELECTED if _selected.has(i) else (LIFT_HOVER if i == _hovered and _enabled else 0.0)
		card.position = Vector2(left + float(_xs[d]), LIFT_SELECTED - lift)
		card.modulate = Color.WHITE if _enabled else DIM
		card.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _draw_card_overlay(card: TextureRect, d: int) -> void:
	# 选中:金边 + 顶上一道暖光
	var i := display_index(d, _ids.size())
	if not _selected.has(i):
		return
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(3)
	box.border_color = UiTheme.BRASS_BRIGHT
	box.set_corner_radius_all(7)
	box.expand_margin_left = 2
	box.expand_margin_right = 2
	box.expand_margin_top = 2
	box.expand_margin_bottom = 2
	card.draw_style_box(box, Rect2(Vector2.ZERO, CARD_SIZE))
	card.draw_rect(Rect2(4, 3, CARD_SIZE.x - 8, 4), Color(1.0, 0.86, 0.5, 0.75))


func display_at(local_x: float) -> int:
	# 本控件里这个横坐标落在哪个显示位置上(压住的部分算后面那张);在最左边那张左边时为 -1
	var best := -1
	for d in _cards.size():
		if local_x >= _cards[d].position.x:
			best = d
	return best


func _on_card_input(event: InputEvent, d: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		accept_event()
		reset_requested.emit()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if event.pressed:
			begin_drag(d)
		else:
			end_drag()
		return
	if event is InputEventMouseMotion and _drag_from >= 0 and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		# 事件坐标是按下的那张牌的局部坐标(拖动时一直是它在收),换成本控件里的横坐标
		var over := display_at(_cards[d].position.x + event.position.x)
		if over >= 0:
			drag_to(over)


func begin_drag(d: int) -> void:
	# 按下:这张牌换成相反的状态,之后拖过的牌都跟它一样
	if d < 0 or d >= _cards.size():
		return
	var i := display_index(d, _ids.size())
	_drag_base = _selected.duplicate()
	_drag_on = not _selected.has(i)
	_drag_from = d
	_drag_to = d
	_emit_drag()


func drag_to(d: int) -> void:
	if _drag_from < 0 or d == _drag_to:
		return
	_drag_to = d
	_emit_drag()


func end_drag() -> void:
	_drag_from = -1


func _emit_drag() -> void:
	selection_changed.emit(drag_selection(_drag_base, _drag_from, _drag_to, _drag_on, _ids.size()))


func _on_hover(d: int, inside: bool) -> void:
	var i := display_index(d, _ids.size())
	if inside:
		_hovered = i
	elif _hovered == i:
		_hovered = -1
	card_hovered.emit(_hovered)
	_layout()
