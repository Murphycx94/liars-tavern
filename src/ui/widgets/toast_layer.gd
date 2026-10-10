class_name ToastLayer
extends VBoxContainer
# 顶部居中的提示条:滑入、停留、淡出。用于加入/离开/错误等非阻塞提示。


const LIFETIME := 3.2
const MAX_TOASTS := 4
# 顶边留白:让开牌桌 HUD 顶部居中的回合横幅与倒计时环(y 18–78),提示不会盖住「轮到你了」
const TOP_OFFSET := 96.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	position.y = TOP_OFFSET
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_toast(text: String, color := UiTheme.PARCHMENT) -> void:
	while get_child_count() >= MAX_TOASTS:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.PANEL, Color(color, 0.8), 1, 18))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := UiTheme.label(text, 18, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	add_child(panel)
	panel.modulate.a = 0.0
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.25)
	tween.tween_interval(LIFETIME)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)


func clear() -> void:
	# 进牌桌时收掉等待厅留下的提示(「某某走进了酒馆」……):开局运镜时还挂着,会压住右上的九宫格
	for child in get_children():
		remove_child(child)
		child.queue_free()
