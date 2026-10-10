class_name CardPreview
extends Control
# 悬停大图(炉石式):光标停在自己的手牌或桌上亮着的牌上时,在旁边弹出一张清晰的 2D 大图;炸弹猫的牌下面另配牌名与说明。
# 三种玩法的牌桌屏幕共用。只负责显示:自己和大图都 MOUSE_FILTER_IGNORE,_input 只读光标位置、从不吞事件,
# 点选、悬停抬牌与快捷键照旧归各牌桌屏幕。屏幕给两个回调:
#   source:光标位置 → 候选牌数组(rect_candidate / card_candidate 造的字典;3D 牌用 world_candidates 一次收齐)
#   gate:此刻的屏幕状态(镜头在不在常驻机位、快捷语 / 九宫格开没开、说明书或确认框、结算),交给 is_blocked 判断
# 窗口失焦、光标出了窗口也藏。选牌(pick)、藏起(is_blocked)、尺寸(preview_size)、摆位(place)都是纯静态函数,便于无头测试。
# 藏着时只在光标动过或每 POLL_INTERVAL 才问一次候选;显示中每帧复查(牌飞走、镜头切走都能马上藏)。


const FADE_TIME := 0.12
const FADE_FROM_SCALE := 0.9
const POLL_INTERVAL := 0.15        # 藏着且光标没动:隔这么久复查一次(演出结束、面板合上后光标没动也能弹出来)
const HEIGHT_RATIO := 0.29         # 大图高 = 视口高 × 比例(1280×720 的界面坐标下约 209,1080p 窗口里约 313 物理像素)
const MIN_HEIGHT := 200.0
const MAX_HEIGHT := 300.0
const CARD_ASPECT := Card3D.WIDTH / Card3D.HEIGHT   # 三种牌面同一比例;牌面还没生成时的占位小图也按它画
const EDGE := 12.0                 # 离画面边缘的最小留白
const GAP := 14.0                  # 离悬停那张牌的留白
const CORNER_RATIO := 38.0 / 360.0 # 牌面圆角 / 牌宽(CardFaces.CORNER_RADIUS);投影跟着圆角走
const SHADOW_SIZE := 16
const SHADOW_COLOR := Color(0, 0, 0, 0.5)
const CAPTION_MIN_WIDTH := 250.0
const CAPTION_GAP := 8.0
const CAPTION_PADDING := Vector2(14, 10)
const CAPTION_TITLE_FONT := 22
const CAPTION_BODY_FONT := 16
const CAPTION_LINE_GAP := 4.0
const TEXT_BREAKS := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
const LAYER_WORLD := 0             # 3D 桌上 / 手里的牌
const LAYER_HUD := 1               # 2D 界面上的牌:画在 3D 之上,同一位置先算它

var source := Callable()           # func(point: Vector2) -> Array[Dictionary]
var gate := Callable()             # func() -> Dictionary(is_blocked 的键)

var _point := Vector2(-1, -1)
var _has_point := false            # 收到过光标位置(进屏幕后光标还没动过时不弹)
var _simulated := false            # 位置来自 hover_at(截图 / 测试),不是真光标
var _mouse_inside := true
var _focused := true
var _dirty := false
var _poll := 0.0
var _key: Variant = null           # 当前显示的那张牌(节点 / 控件的实例 id)
var _texture: Texture2D = null
var _title := ""
var _body := ""
var _avoid := Rect2()
var _box: Control
var _tween: Tween = null


func _init() -> void:
	name = "CardPreview"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = Control.new()
	_box.name = "Box"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_box.draw.connect(_draw_box)
	add_child(_box)
	_box.visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# —— 纯逻辑 ——

static func is_blocked(state: Dictionary) -> bool:
	# 任何一条成立就藏:窗口失焦(focused)、光标出了窗口(mouse_inside)、镜头不在常驻机位(特写 / 开枪 / 庆祝,camera_at_rest)、
	# 快捷语面板或九宫格开着(panel_open)、说明书或确认框开着(modal_open)、结算面板(settlement)
	return not state.get("focused", true) or not state.get("mouse_inside", true) or not state.get("camera_at_rest", true) \
		or state.get("panel_open", false) or state.get("modal_open", false) or state.get("settlement", false)


static func pick(point: Vector2, candidates: Array) -> int:
	# 光标下的哪张牌:只看正面朝上的(face_up)、光标落在它屏幕轮廓(quad)里的;2D 界面层先于 3D,
	# 同一层取 depth 最小的(3D:离镜头最近;2D:后画的在上面,depth 给负的序号)。没有返回 -1
	var best := -1
	var best_layer := -1
	var best_depth := INF
	for i in candidates.size():
		var c: Variant = candidates[i]
		if not c is Dictionary or not c.get("face_up", false) or not contains(c.get("quad", PackedVector2Array()), point):
			continue
		var layer: int = c.get("layer", LAYER_WORLD)
		var depth: float = c.get("depth", 0.0)
		if layer > best_layer or (layer == best_layer and depth < best_depth):
			best = i
			best_layer = layer
			best_depth = depth
	return best


static func contains(quad: PackedVector2Array, point: Vector2) -> bool:
	return quad.size() >= 3 and Geometry2D.is_point_in_polygon(point, quad)


static func quad_of(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


static func bounds_of(quad: PackedVector2Array) -> Rect2:
	if quad.is_empty():
		return Rect2()
	var rect := Rect2(quad[0], Vector2.ZERO)
	for p in quad:
		rect = rect.expand(p)
	return rect


static func preview_size(viewport: Vector2) -> Vector2:
	# 牌面大图的尺寸(界面坐标):高随视口高缩放,夹在 [MIN_HEIGHT, MAX_HEIGHT]
	var height := clampf(viewport.y * HEIGHT_RATIO, MIN_HEIGHT, MAX_HEIGHT)
	return Vector2(round(height * CARD_ASPECT), round(height))


static func caption_height(title: String, body: String, width: float) -> float:
	# 牌名 + 说明的面板高(没有文字为 0);说明按面板内宽折行
	if title == "" and body == "":
		return 0.0
	var inner := width - CAPTION_PADDING.x * 2.0
	var height := CAPTION_PADDING.y * 2.0
	if title != "":
		height += UiTheme.display_font().get_height(CAPTION_TITLE_FONT)
	if body != "":
		if title != "":
			height += CAPTION_LINE_GAP
		height += UiTheme.body_font().get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, inner, CAPTION_BODY_FONT,
			-1, TEXT_BREAKS).y
	return ceilf(height)


static func box_size(card: Vector2, caption: float) -> Vector2:
	# 整块(牌 + 下面的说明面板)的尺寸;有说明时面板至少 CAPTION_MIN_WIDTH 宽,牌居中
	if caption <= 0.0:
		return card
	return Vector2(maxf(card.x, CAPTION_MIN_WIDTH), card.y + CAPTION_GAP + caption)


static func clamp_into(top_left: Vector2, box: Vector2, viewport: Vector2, edge := EDGE) -> Vector2:
	# 整块留在画面里(离边 edge);比画面还大时贴左上
	var x := clampf(top_left.x, edge, maxf(edge, viewport.x - box.x - edge))
	var y := clampf(top_left.y, edge, maxf(edge, viewport.y - box.y - edge))
	return Vector2(x, y)


static func place(box: Vector2, avoid: Rect2, cursor: Vector2, viewport: Vector2, gap := GAP, edge := EDGE) -> Vector2:
	# 大图的左上角:依次试 上方(以光标为中线)→ 右侧 → 左侧 → 下方,挪进画面后第一个不压住 avoid(悬停的牌 + 光标)的就用;
	# 都压住时取压住面积最小的
	avoid = avoid.expand(cursor)
	var options := [
		Vector2(cursor.x - box.x / 2.0, avoid.position.y - gap - box.y),
		Vector2(avoid.end.x + gap, cursor.y - box.y / 2.0),
		Vector2(avoid.position.x - gap - box.x, cursor.y - box.y / 2.0),
		Vector2(cursor.x - box.x / 2.0, avoid.end.y + gap),
	]
	var best := Vector2.ZERO
	var best_overlap := INF
	for option: Vector2 in options:
		var at := clamp_into(option, box, viewport, edge)
		var overlap := Rect2(at, box).intersection(avoid).get_area()
		if overlap <= 0.0:
			return at
		if overlap < best_overlap:
			best_overlap = overlap
			best = at
	return best


# —— 候选牌 ——

static func rect_candidate(rect: Rect2, texture: Texture2D, order: int, key: Variant, title := "", body := "",
		avoid := Rect2()) -> Dictionary:
	# 2D 界面上的一张牌(全局矩形);order 越大画得越靠上。avoid:摆大图时要让开的整块(如牌所在的面板),默认只让开这张牌
	var c := {"quad": quad_of(rect), "depth": -float(order), "layer": LAYER_HUD, "face_up": texture != null,
		"texture": texture, "title": title, "body": body, "key": key}
	if avoid.has_area():
		c["avoid"] = avoid.merge(rect)
	return c


static func avoid_rect(candidate: Dictionary) -> Rect2:
	# 摆大图时要让开的矩形:候选给了 avoid(牌所在的面板)就用它,否则用牌的屏幕外接矩形
	var avoid: Variant = candidate.get("avoid")
	return avoid if avoid is Rect2 and avoid.has_area() else bounds_of(candidate.get("quad", PackedVector2Array()))


static func card_candidate(camera: Camera3D, card: Card3D, origin: Vector3, direction: Vector3) -> Dictionary:
	# 一张 3D 牌:屏幕轮廓(四角投影)、离镜头的距离(射线打中时取命中点,否则取牌心)、正面朝不朝镜头、牌面纹理。
	# 牌背(他人的牌、未翻开的牌)face_up 为 false;不可见或有角在镜头背后的给空字典
	if not is_instance_valid(card) or not card.is_visible_in_tree():
		return {}
	var xform := card.global_transform
	var quad := PackedVector2Array()
	for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
		var p: Vector3 = xform * (corner * Vector3(Card3D.WIDTH / 2.0, 0.0, Card3D.HEIGHT / 2.0))
		if camera.is_position_behind(p):
			return {}
		quad.append(camera.unproject_position(p))
	var hit := card.ray_hit_distance(origin, direction)
	var cam_pos := camera.global_position
	var face := face_of(card)
	var toward: bool = xform.basis.y.dot(cam_pos - xform.origin) > 0.0
	return {"quad": quad, "depth": hit if hit >= 0.0 else cam_pos.distance_to(xform.origin), "layer": LAYER_WORLD,
		"face_up": toward and face["texture"] != null, "texture": face["texture"], "title": face["title"], "body": face["body"],
		"key": card.get_instance_id()}


static func world_candidates(camera: Camera3D, point: Vector2, cards: Array) -> Array:
	# 一组 3D 牌按光标位置的射线逐张造候选(跳过已释放的、不可见的)
	if camera == null or not camera.is_inside_tree():
		return []
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var out := []
	for card in cards:
		if card is Card3D and is_instance_valid(card):
			var c := card_candidate(camera, card, origin, direction)
			if not c.is_empty():
				out.append(c)
	return out


static func face_of(card: Card3D) -> Dictionary:
	# 牌面纹理与说明:炸弹猫的牌按 card_id(带牌名与说明),骗子酒馆 / 德州按 kind;牌背 texture 为 null
	if card is BombCard3D:
		var id: String = card.card_id
		if not BombCatCard.is_valid(id):
			return {"texture": null, "title": "", "body": ""}
		return {"texture": BombCatFaces.texture(id), "title": BombCatCard.display_name(id), "body": BombCatCard.description(id)}
	if card.kind == CardFaces.BACK:
		return {"texture": null, "title": "", "body": ""}
	return {"texture": CardFaces.texture(card.kind), "title": "", "body": ""}


static func bomb_caption(id: String) -> Dictionary:
	return {"title": BombCatCard.display_name(id), "body": BombCatCard.description(id)}


# —— 运行时 ——

func _input(event: InputEvent) -> void:
	# 只记光标位置,不吞事件(牌桌的悬停抬牌、点选照旧收得到)
	if event is InputEventMouseMotion:
		_point = event.position
		_has_point = true
		_simulated = false
		_mouse_inside = true
		_dirty = true


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_focused = false
			hide_preview()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_focused = true
		NOTIFICATION_WM_MOUSE_EXIT:
			_mouse_inside = false
			hide_preview()
		NOTIFICATION_WM_MOUSE_ENTER:
			_mouse_inside = true
		NOTIFICATION_RESIZED:
			if is_showing():
				_layout_box()


func _process(delta: float) -> void:
	if not _has_point:
		return
	if not is_showing() and not _dirty:
		_poll -= delta
		if _poll > 0.0:
			return
	_poll = POLL_INTERVAL
	_dirty = false
	refresh(true)


func hover_at(point: Vector2, animate := false) -> void:
	# 截图工具 / 测试:当作光标停在 point,立刻按当前状态显示或藏起(animate=false 时不淡入,暂停的场景树里也看得到)。
	# 真光标不在这里,所以之后不再问「光标下是不是界面控件」;真光标一动就恢复
	_point = point
	_has_point = true
	_simulated = true
	_mouse_inside = true
	_focused = true
	refresh(animate)


func refresh(animate := true) -> void:
	# 按光标位置与屏幕状态重新挑牌:被挡住或光标下没有亮面的牌就藏起
	if is_blocked(_state()) or not source.is_valid():
		hide_preview()
		return
	var candidates: Array = source.call(_point)
	if _gui_under_cursor():
		# 光标在按钮、面板这类接鼠标的界面上:它后面的 3D 牌不算(同牌桌的悬停抬牌,鼠标事件被界面吃掉了)
		candidates = candidates.filter(func(c): return c is Dictionary and c.get("layer", LAYER_WORLD) == LAYER_HUD)
	var index := pick(_point, candidates)
	if index < 0:
		hide_preview()
		return
	var c: Dictionary = candidates[index]
	var avoid := avoid_rect(c)
	var new_card: bool = c.get("key") != _key or not is_showing()
	# 同一张牌:牌面后台生成完(占位小图 → 正式牌面,尺寸变了)或翻成了别的牌才重画;占位图每次取都是新对象,不按对象比
	var texture: Texture2D = c["texture"]
	var restyled: bool = _texture == null or texture.get_size() != _texture.get_size() \
		or c.get("title", "") != _title or c.get("body", "") != _body
	_key = c.get("key")
	if new_card or restyled:
		_texture = texture
		_title = c.get("title", "")
		_body = c.get("body", "")
	if new_card:
		_avoid = avoid
		_show(animate)
	elif restyled or _overlaps_box(avoid):
		# 换了图,或悬停的牌在动(抬起、重排)压到了大图:重新摆
		_avoid = avoid
		_layout_box()


func hide_preview() -> void:
	_key = null
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_box.visible = false


func is_showing() -> bool:
	return _box.visible


func shown_rect() -> Rect2:
	# 大图整块(牌 + 说明)在本控件里的矩形;藏着时为空
	return Rect2(_box.position, _box.size) if is_showing() else Rect2()


func shown_texture() -> Texture2D:
	return _texture if is_showing() else null


func shown_caption() -> Dictionary:
	return {"title": _title, "body": _body} if is_showing() else {}


func _state() -> Dictionary:
	var state: Dictionary = gate.call() if gate.is_valid() else {}
	state = state.duplicate()
	state["focused"] = _focused and state.get("focused", true)
	state["mouse_inside"] = _mouse_inside and state.get("mouse_inside", true)
	return state


func _gui_under_cursor() -> bool:
	if _simulated or not is_inside_tree():
		return false
	return get_viewport().gui_get_hovered_control() != null


func _to_local() -> Transform2D:
	# 本控件铺满屏幕层:光标与牌的屏幕坐标换到本控件里
	return get_global_transform_with_canvas().affine_inverse() if is_inside_tree() else Transform2D.IDENTITY


func _overlaps_box(screen_rect: Rect2) -> bool:
	return Rect2(_box.position, _box.size).intersects(_to_local() * screen_rect)


func _show(animate: bool) -> void:
	_layout_box()
	_box.visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not animate or not is_inside_tree():
		_box.modulate.a = 1.0
		_box.scale = Vector2.ONE
		return
	_box.modulate.a = 0.0
	_box.scale = Vector2.ONE * FADE_FROM_SCALE
	_tween = create_tween().set_parallel()
	_tween.tween_property(_box, "modulate:a", 1.0, FADE_TIME)
	_tween.tween_property(_box, "scale", Vector2.ONE, FADE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _viewport_size() -> Vector2:
	if size.x > 0.0 and size.y > 0.0:
		return size
	return get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)


func _layout_box() -> void:
	var viewport := _viewport_size()
	var card := preview_size(viewport)
	var caption := caption_height(_title, _body, maxf(card.x, CAPTION_MIN_WIDTH))
	var box := box_size(card, caption)
	var to_local := _to_local()
	var avoid := to_local * _avoid
	_box.size = box
	_box.position = place(box, avoid, to_local * _point, viewport)
	_box.pivot_offset = box / 2.0   # 淡入时从中心放大
	_box.queue_redraw()


func _draw_box() -> void:
	var viewport := _viewport_size()
	var card := preview_size(viewport)
	var box := _box.size
	var card_rect := Rect2(Vector2((box.x - card.x) / 2.0, 0.0), card)
	var radius := int(round(card.x * CORNER_RATIO))
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.25)
	shadow.set_corner_radius_all(radius)
	shadow.shadow_color = SHADOW_COLOR
	shadow.shadow_size = SHADOW_SIZE
	shadow.shadow_offset = Vector2(0, 5)
	shadow.anti_aliasing = true
	_box.draw_style_box(shadow, card_rect.grow(-2.0))
	if _texture != null:
		_box.draw_texture_rect(_texture, card_rect, false)
	if _title == "" and _body == "":
		return
	var panel_rect := Rect2(0.0, card.y + CAPTION_GAP, box.x, box.y - card.y - CAPTION_GAP)
	var panel := UiTheme.panel_box(Color(UiTheme.INK, 0.92), Color(UiTheme.BRASS, 0.75), 2, 10)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 10
	_box.draw_style_box(panel, panel_rect)
	var inner := panel_rect.size.x - CAPTION_PADDING.x * 2.0
	var y := panel_rect.position.y + CAPTION_PADDING.y
	if _title != "":
		var title_font := UiTheme.display_font()
		_box.draw_string(title_font, Vector2(panel_rect.position.x + CAPTION_PADDING.x, y + title_font.get_ascent(CAPTION_TITLE_FONT)),
			_title, HORIZONTAL_ALIGNMENT_CENTER, inner, CAPTION_TITLE_FONT, UiTheme.BRASS_BRIGHT)
		y += title_font.get_height(CAPTION_TITLE_FONT) + CAPTION_LINE_GAP
	if _body != "":
		var body_font := UiTheme.body_font()
		_box.draw_multiline_string(body_font, Vector2(panel_rect.position.x + CAPTION_PADDING.x, y + body_font.get_ascent(CAPTION_BODY_FONT)),
			_body, HORIZONTAL_ALIGNMENT_LEFT, inner, CAPTION_BODY_FONT, -1, UiTheme.PARCHMENT, TEXT_BREAKS)
