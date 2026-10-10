class_name BombCatHandStrip
extends Control
# 炸弹猫底部的 2D 手牌条(规格 §3.2,操作主入口;3D 牌扇只是好看):每张牌一张牌面小图,左上角标快捷键数字(1–9),
# 点一下选中(抬起 + 金边),悬停微抬(牌名与说明由 CardPreview 的悬停大图给出)。牌多时互相压住一部分,整条不超过 MAX_WIDTH。
# 只发信号(card_clicked / card_hovered),选不选得上由牌桌按规则决定;牌面纹理生成完(BombCatFaces.built)重新取。


signal card_clicked(index: int)
signal card_hovered(index: int)

const CARD_SIZE := Vector2(70, 101)
const GAP := 6.0
const MAX_WIDTH := 600.0
const LIFT_SELECTED := 18.0
const LIFT_HOVER := 7.0
const KEY_FONT := 13
const DIM := Color(0.6, 0.6, 0.6, 0.9)

var _ids: Array = []
var _selected := {}
var _hovered := -1
var _enabled := true
var _cards: Array[TextureRect] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(CARD_SIZE.x, CARD_SIZE.y + LIFT_SELECTED)


func _ready() -> void:
	BombCatFaces.built_signal().connect(refresh_textures)


static func layout_step(count: int) -> float:
	# 相邻两张左边缘的距离:放得下就留 GAP,放不下就互相压住
	if count <= 1:
		return CARD_SIZE.x + GAP
	return minf(CARD_SIZE.x + GAP, (MAX_WIDTH - CARD_SIZE.x) / float(count - 1))


static func strip_width(count: int) -> float:
	return 0.0 if count <= 0 else CARD_SIZE.x + layout_step(count) * (count - 1)


func set_hand(ids: Array, selected: Dictionary, enabled: bool) -> void:
	var changed := ids != _ids
	_ids = ids.duplicate()
	_selected = selected.duplicate()
	_enabled = enabled
	if changed:
		_rebuild()
		if _hovered >= _ids.size():
			_hovered = -1
	_layout()


func ids() -> Array:
	return _ids.duplicate()


func card_count() -> int:
	return _cards.size()


func preview_candidates() -> Array:
	# 悬停大图(CardPreview)的候选:每张牌的屏幕矩形 + 牌名与说明(取代原来的文字提示框);后面的牌压在前面的上面。
	# 大图让开整条手牌条(不挡住旁边的牌)
	var out := []
	if not is_visible_in_tree():
		return out
	var strip_rect := get_global_transform_with_canvas() * Rect2(Vector2.ZERO, size)
	for i in _cards.size():
		var card := _cards[i]
		var rect := card.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, card.size)
		var caption := CardPreview.bomb_caption(_ids[i])
		out.append(CardPreview.rect_candidate(rect, card.texture, i, card.get_instance_id(), caption["title"],
			caption["body"], strip_rect))
	return out


func flash(index: int) -> void:
	# 新摸到 / 抢来的那张闪一下金边
	if index < 0 or index >= _cards.size():
		return
	var card := _cards[index]
	var tween := card.create_tween()
	tween.tween_property(card, "self_modulate", Color(1.6, 1.4, 0.9), 0.12)
	tween.tween_property(card, "self_modulate", Color.WHITE, 0.5)


func refresh_textures() -> void:
	for i in _cards.size():
		_cards[i].texture = BombCatFaces.texture(_ids[i])


func _rebuild() -> void:
	for card in _cards:
		remove_child(card)
		card.queue_free()
	_cards.clear()
	for i in _ids.size():
		var card := TextureRect.new()
		card.texture = BombCatFaces.texture(_ids[i])
		card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_SCALE
		card.size = CARD_SIZE
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(_on_card_input.bind(i))
		card.mouse_entered.connect(_on_hover.bind(i, true))
		card.mouse_exited.connect(_on_hover.bind(i, false))
		card.draw.connect(_draw_card_overlay.bind(card, i))
		add_child(card)
		_cards.append(card)
	var width := strip_width(_ids.size())
	custom_minimum_size = Vector2(maxf(width, CARD_SIZE.x), CARD_SIZE.y + LIFT_SELECTED)


func _layout() -> void:
	var step := layout_step(_cards.size())
	var width := strip_width(_cards.size())
	var left := (size.x - width) / 2.0 if size.x > width else 0.0
	for i in _cards.size():
		var card := _cards[i]
		var lift := LIFT_SELECTED if _selected.has(i) else (LIFT_HOVER if i == _hovered and _enabled else 0.0)
		card.position = Vector2(left + i * step, LIFT_SELECTED - lift)
		card.modulate = Color.WHITE if _enabled else DIM
		card.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _draw_card_overlay(card: TextureRect, index: int) -> void:
	# 选中:金边;左上角:快捷键数字
	var rect := Rect2(Vector2.ZERO, CARD_SIZE)
	if _selected.has(index):
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.set_border_width_all(3)
		box.border_color = UiTheme.BRASS_BRIGHT
		box.set_corner_radius_all(7)
		box.expand_margin_left = 2
		box.expand_margin_right = 2
		box.expand_margin_top = 2
		box.expand_margin_bottom = 2
		card.draw_style_box(box, rect)
	if index < 9:
		var font := UiTheme.body_font()
		var center := Vector2(11, 11)
		card.draw_circle(center, 9.0, Color(0.1, 0.07, 0.05, 0.85))
		var text := str(index + 1)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_FONT)
		card.draw_string(font, center + Vector2(-text_size.x / 2.0, KEY_FONT * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_FONT,
			UiTheme.BRASS_BRIGHT)


func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		card_clicked.emit(index)


func _on_hover(index: int, inside: bool) -> void:
	if inside:
		_hovered = index
	elif _hovered == index:
		_hovered = -1
	card_hovered.emit(_hovered)
	_layout()
