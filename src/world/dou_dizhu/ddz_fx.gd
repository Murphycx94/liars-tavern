class_name DdzFx
extends BombCatFx
# 斗地主的特效层:沿用炸弹猫效果层的全部小件(卡通烟团 puffs、星星 star_burst、冲击波 shock_ring、漫画字 pop_text、闪光 glint、
# 跟随挂点 _follow、到点自释放的根节点 _spawn),挂在 TableWorld.poker_root 下,拆台时一并收走。入口都不阻塞,
# 导演按这里的节奏常量去等(DouDizhuPacing 的预算据此核对,见 test_ddz_director)。
# - 炸弹:一大团圆滚滚的卡通烟云 +「炸弹!」+ 倍数「×2」弹出来(复用炸弹猫「轰!」那团烟的画法,不带炸弹猫);
# - 王炸:一枚小火箭从出牌行冲天而起,拖着一串小烟团,到顶「砰」地炸成几簇彩色烟花 +「王炸!」;
# - 飞机:一架小纸飞机从出牌的人那边掠过桌面、绕个弯飞走 +「飞机!」;
# - 春天:桌子上空飘下一阵粉色花瓣 +「春天!」;
# - 定地主:一束暖黄的聚光照在地主身上;
# - 报警:只剩 1–2 张的人头顶一枚一闪一闪的红色「!」徽章(写着剩几张);
# - 「不出」:出牌行上方立一块小牌子,清桌或他再出牌时收起。
# 音效同 BombCatFx:sfx 信号交给上层。


const BOMB_TIME := 1.2              # 炸弹:烟云鼓起来、字弹出来、冲击波扩散完
const BOMB_TEXT_LIFE := 1.25
const ROCKET_RISE := 0.55           # 小火箭冲到顶
const ROCKET_HEIGHT := 0.78           # 到顶的高度(在吊灯罩下面炸开)
const FIREWORK_BURSTS := 3          # 到顶炸成几簇
const FIREWORK_STAGGER := 0.16
const FIREWORK_LIFE := 0.95
const ROCKET_TIME := ROCKET_RISE + FIREWORK_STAGGER * (FIREWORK_BURSTS - 1) + 0.55   # 导演等这么久(最后一簇炸开之后再看一下)
const PLANE_TIME := 1.05            # 纸飞机从这头掠到那头
const PLANE_LIFT := 0.22
const PLANE_SCALE := 2.2
const SPRING_TIME := 1.4            # 花瓣飘这么久(导演只等这么久,花瓣自己再飘一会儿淡掉)
const SPRING_PETALS := 120
const SPOT_LIFE := 2.4
const SPOT_POP := 0.25
const ALARM_SIDE := 0.3
const ALARM_BLINK := 0.5
const PASS_POP := 0.16
const MULTIPLIER_COLOR := Color(1.0, 0.86, 0.36)
const DELTA_GREEN := Color(0.5, 0.95, 0.55)   # 一手结束头顶飘的得分(赢绿输红)
const DELTA_RED := Color(1.0, 0.5, 0.42)

var _alarms := {}                   # pid -> 徽章根节点
var _passes := {}                   # pid -> 「不出」牌子


func _init(p_world: TableWorld) -> void:
	super(p_world)
	name = "DdzFx"


func clear() -> void:
	super()
	_alarms = {}
	_passes = {}


# —— 炸弹 ——

func bomb(pos: Vector3, multiplier: int) -> void:
	# 一团卡通烟云(奶黄、橘、薰衣草灰的圆烟团)、乱飞的星星、贴桌的冲击波圈;「炸弹!」+「×N」
	var root := _spawn("bomb", BOMB_TIME + 0.8)
	root.global_position = pos
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.55)
	light.light_energy = 3.0
	light.omni_range = 4.0
	light.shadow_enabled = false
	root.add_child(light)
	light.create_tween().tween_property(light, "light_energy", 0.0, 0.45).set_ease(Tween.EASE_OUT)
	puffs(pos, 30, [Color(1.0, 0.72, 0.25), Color(1.0, 0.5, 0.28), Color(1.0, 0.86, 0.45), Color(1.0, 0.62, 0.4)], 0.21, Vector2(0.7, 1.3), 0.85, 0.4)
	puffs(pos + Vector3(0, 0.05, 0), 20, [Color(0.66, 0.56, 0.84), Color(0.52, 0.46, 0.66), Color(0.82, 0.7, 0.9)], 0.24,
		Vector2(0.35, 0.8), 1.2, 0.3)
	star_burst(pos + Vector3(0, 0.08, 0), 7, 0.55, 0.85)
	Fx.sparkles(root, pos, Vector3.UP, 24)
	var ground := pos
	ground.y = world.to_global(Vector3(0, SeatLayout.FELT_TOP, 0)).y + 0.01
	shock_ring(ground, Color(1.0, 0.86, 0.6), 1.0, 0.5)
	pop_text("炸弹!", pos + Vector3(0, 0.42, 0), Color(1.0, 0.45, 0.32), 1.5, BOMB_TEXT_LIFE, 0.22)
	multiplier_pop(pos + Vector3(0.28, 0.3, 0), multiplier)
	sfx.emit("boom")


func multiplier_pop(pos: Vector3, multiplier: int) -> void:
	# 倍数翻倍:金色的「×N」弹出来
	if multiplier <= 1:
		return
	var label := pop_text("×%d" % multiplier, pos, MULTIPLIER_COLOR, 0.9, 1.1, 0.18)
	label.outline_modulate = Color(0.42, 0.2, 0.08)


# —— 王炸 ——

func rocket(from: Vector3) -> void:
	# 小火箭从 from(出牌行)冲天而起:先蹲一下,再一边打转一边往上窜,拖一串奶白小烟团;到顶炸成几簇烟花
	var root := _spawn("rocket", ROCKET_TIME + FIREWORK_LIFE + 0.3)
	var ship := MeshKit.add(root, DdzProps.rocket(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 1.3, MeshKit.SHADOW_OFF)
	ship.name = "Rocket"
	root.global_position = from
	var top := from + Vector3(0, ROCKET_HEIGHT, 0)
	sfx.emit("rocket")
	var tween := ship.create_tween()
	tween.tween_property(ship, "scale", Vector3(1.5, 1.0, 1.5), 0.06)
	tween.tween_method(func(t: float) -> void:
		var k := t * t
		ship.global_position = from.lerp(top, k) + Vector3(sin(t * 9.0) * 0.03 * (1.0 - t), 0, cos(t * 9.0) * 0.03 * (1.0 - t))
		ship.rotation = Vector3(0, t * 10.0, sin(t * 14.0) * 0.12)
		ship.scale = Vector3.ONE * 1.3 * (1.0 + 0.12 * sin(t * PI)),
		0.0, 1.0, ROCKET_RISE - 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		ship.visible = false
		_firework(top, 0))
	var trail := root.create_tween().set_loops(6)
	trail.tween_callback(func() -> void:
		if is_instance_valid(ship) and ship.visible:
			puffs(ship.global_position, 4, DdzProps.trail_puff_colors(), 0.06, Vector2(0.05, 0.2), 0.45, -0.1, 40.0))
	trail.tween_interval((ROCKET_RISE - 0.06) / 6.0)
	var toward := (_camera_pos() - top) * Vector3(1, 0, 1)
	toward = toward.normalized() if toward.length() > 0.01 else Vector3.BACK
	var side := Vector3.UP.cross(toward).normalized()
	for k in range(1, FIREWORK_BURSTS):
		var at := top + side * (0.4 if k % 2 == 1 else -0.4) + toward * 0.15 + Vector3(0, -0.08 * k, 0)
		var delay := ROCKET_RISE + FIREWORK_STAGGER * k
		var later := root.create_tween()
		later.tween_interval(delay)
		later.tween_callback(func() -> void: _firework(at, k))
	pop_text("王炸!", top + Vector3(0, 0.42, 0), Color(1.0, 0.52, 0.42), 1.6, 1.4, 0.15)


func _firework(at: Vector3, index: int) -> void:
	# 一簇烟花:亮色小圆点往四面八方喷、慢慢往下坠,中间一下闪光 + 几颗胖星星
	var palettes := [[Color(1.0, 0.45, 0.5), Color(1.0, 0.82, 0.4), Color(1.0, 0.95, 0.75)],
		[Color(0.5, 0.85, 1.0), Color(0.75, 0.6, 1.0), Color(1.0, 1.0, 1.0)],
		[Color(0.55, 1.0, 0.65), Color(1.0, 0.9, 0.45), Color(1.0, 0.6, 0.85)]]
	var colors: Array = palettes[index % palettes.size()]
	sparks(at, 120, colors, Vector2(0.9, 1.4), FIREWORK_LIFE)
	puffs(at, 10, [colors[0], colors[1]], 0.06, Vector2(0.3, 0.5), FIREWORK_LIFE * 0.6, -0.3, 180.0)
	star_burst(at, 6, 0.5, 0.85)
	glint(at, 0.36)
	var root := _spawn("firework", FIREWORK_LIFE)
	root.global_position = at
	Fx.sparkles(root, at, Vector3.UP, 26)
	var light := OmniLight3D.new()
	light.light_color = colors[0]
	light.light_energy = 2.5
	light.omni_range = 3.0
	light.shadow_enabled = false
	root.add_child(light)
	light.create_tween().tween_property(light, "light_energy", 0.0, 0.5)
	sfx.emit("firework")


func sparks(at: Vector3, amount: int, colors: Array, speed: Vector2, life: float) -> GPUParticles3D:
	# 烟花的火星:一群发光的小圆点往四面八方炸开,边飞边往下坠、慢慢变暗缩小
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = clampi(amount, 1, MAX_PARTICLES)
	p.lifetime = life
	p.explosiveness = 0.95
	p.randomness = 0.4
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.03
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = speed.x
	pm.initial_velocity_max = speed.y
	pm.gravity = Vector3(0, -1.1, 0)
	pm.damping_min = 1.4
	pm.damping_max = 2.2
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.6, 0.8))
	curve.add_point(Vector2(1.0, 0.0))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var packed := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / maxf(colors.size() - 1, 1))
		packed.append(colors[i])
	gradient.offsets = offsets
	gradient.colors = packed
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	pm.color_initial_ramp = ramp
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	pm.color_ramp = fade_tex
	p.process_material = pm
	p.draw_pass_1 = Fx._additive_quad(0.06, 5.0)   # 同礼炮火星的加色软圆点(泛光会把它晕开)
	add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	spawned.emit("sparks")
	return p


# —— 飞机 ——

func plane(from: Vector3, to: Vector3) -> void:
	# 纸飞机从 from 那边起飞,贴着桌面上方划一道弧掠过桌心,往 to 那边拉高飞走、缩没;尾巴后面一串小星星
	var root := _spawn("plane", PLANE_TIME + 0.2)
	var craft := MeshKit.add(root, DdzProps.paper_plane(), null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * PLANE_SCALE, MeshKit.SHADOW_OFF)
	craft.name = "Plane"
	var mid := (from + to) * 0.5
	var side := (to - from).cross(Vector3.UP).normalized() * 0.18
	var a := from + Vector3(0, 0.12, 0)
	var b := mid + side + Vector3(0, PLANE_LIFT, 0)
	var c := to + Vector3(0, 0.55, 0)
	root.global_position = a
	sfx.emit("plane")
	var last := [a]
	var tween := craft.create_tween()
	tween.tween_method(func(t: float) -> void:
		var p := a.lerp(b, t).lerp(b.lerp(c, t), t)
		var heading: Vector3 = p - last[0]
		last[0] = p
		craft.global_position = p
		if heading.length() > 0.0005:
			var bank := sin(t * PI) * 0.6
			craft.global_basis = Basis.looking_at(heading.normalized(), Vector3.UP) * Basis(Vector3.BACK, bank)
		craft.scale = Vector3.ONE * PLANE_SCALE * (1.0 - smoothstep(0.85, 1.0, t)),
		0.0, 1.0, PLANE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var sparkle := root.create_tween().set_loops(7)
	sparkle.tween_callback(func() -> void:
		if is_instance_valid(craft):
			glint(craft.global_position, 0.06))
	sparkle.tween_interval(PLANE_TIME / 7.0)
	pop_text("飞机!", from + Vector3(0, 0.55, 0), Color(0.55, 0.82, 1.0), 1.3, 1.1, 0.16)


# —— 春天 ——

func spring(center: Vector3) -> void:
	# 桌子上空飘下一阵粉色花瓣(打着转、左右飘),「春天!」
	var root := _spawn("spring", SPRING_TIME + 2.4)
	var p := GPUParticles3D.new()
	p.amount = SPRING_PETALS
	p.lifetime = 2.6
	p.one_shot = true
	p.explosiveness = 0.55
	p.randomness = 0.5
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2.5, -2, -2.5), Vector3(5, 4, 5))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.1, 0.2, 1.1)
	pm.direction = Vector3.DOWN
	pm.spread = 25.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0, -0.35, 0)
	pm.angular_velocity_min = -180.0
	pm.angular_velocity_max = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 1.6
	pm.scale_min = 2.6
	pm.scale_max = 4.2
	pm.particle_flag_rotate_y = true
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	gradient.colors = PackedColorArray(DdzProps.PETAL_COLORS)
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	pm.color_initial_ramp = ramp
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.3))
	fade.add_point(Vector2(0.1, 1.0))
	fade.add_point(Vector2(0.85, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	var fade_tex := CurveTexture.new()
	fade_tex.curve = fade
	pm.scale_curve = fade_tex
	p.process_material = pm
	p.draw_pass_1 = DdzProps.petal_mesh()
	root.add_child(p)
	p.global_position = center + Vector3(0, 0.95, 0)
	p.emitting = true
	pop_text("春天!", center + Vector3(0, 0.62, 0), Color(1.0, 0.62, 0.74), 1.7, SPRING_TIME + 0.4, 0.18)
	sfx.emit("chime")


# —— 定地主 ——

func spotlight_on(pid: int, life := SPOT_LIFE) -> Node3D:
	# 一束暖黄聚光照在地主身上(半透明光柱 + 真的聚光灯,渐亮再渐暗)
	var root := _spawn("spot", life)
	var patron := _patron(pid)
	if patron == null:
		return root
	var cone := _mesh(root, BombCatProps.cone(), Color(1.0, 0.92, 0.62), 0.0)
	cone.visible = pid != my_pid   # 自己当地主:光柱会从镜头前穿过,只留真的聚光灯
	var base := patron.global_position
	base.y = world.to_global(Vector3.ZERO).y
	cone.global_position = base
	cone.scale = Vector3(1.0, 2.1, 1.0)
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.58)
	lamp.light_energy = 0.0
	lamp.spot_range = 4.0
	lamp.spot_angle = 18.0
	lamp.shadow_enabled = false
	root.add_child(lamp)
	lamp.global_position = patron.head_position() + Vector3(0, 1.6, 0)
	lamp.global_basis = Basis.looking_at(Vector3.DOWN, Vector3.FORWARD)
	var tween := root.create_tween().set_parallel()
	tween.tween_method(func(a: float) -> void: cone.set_instance_shader_parameter("alpha", a), 0.0, 0.16, SPOT_POP)
	tween.tween_property(lamp, "light_energy", 6.0, SPOT_POP)
	var out := root.create_tween().set_parallel()
	out.tween_interval(maxf(life - 0.5, 0.1))
	out.chain().tween_method(func(a: float) -> void: cone.set_instance_shader_parameter("alpha", a), 0.16, 0.0, 0.45)
	out.tween_property(lamp, "light_energy", 0.0, 0.45)
	sfx.emit("sparkle")
	return root


# —— 报警 ——

func set_alarm(pid: int, count: int) -> void:
	# 只剩 1–2 张:头顶偏右一枚一闪一闪的红色「!」徽章,下面写剩几张;其余张数收起
	if count < 1 or count > 2 or _patron(pid) == null:
		clear_alarm(pid)
		return
	var root: Node3D = _alarms.get(pid)
	if root == null or not is_instance_valid(root):
		root = _spawn("alarm", -1.0)
		_alarms[pid] = root
		var inner := Node3D.new()
		inner.name = "Inner"
		root.add_child(inner)
		_mesh(inner, DdzProps.alarm_badge(), Color.WHITE, 1.0).name = "Disc"
		var mark := _label("!", 0.5, Color(1.0, 0.98, 0.92))
		mark.name = "Mark"
		mark.outline_size = 20
		mark.position = Vector3(0, 0.004, 0.002)
		inner.add_child(mark)
		var tag := _label("", 0.42, Color(1.0, 0.9, 0.84))
		tag.name = "Count"
		tag.outline_size = 22
		tag.position = Vector3(0, -0.12, 0.002)
		inner.add_child(tag)
		var side := world.seat_right(pid) * ALARM_SIDE
		_follow.append([root, func() -> Vector3: return _head_top(pid), side + Vector3(0, 0.04, 0)])
		root.global_position = _head_top(pid) + side
		root.scale = Vector3.ONE * 0.05
		var pop := root.create_tween()
		pop.tween_property(root, "scale", Vector3.ONE * 1.25, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(root, "scale", Vector3.ONE, 0.12)
		var blink := inner.create_tween().set_loops()
		blink.tween_property(inner, "scale", Vector3.ONE * 1.15, ALARM_BLINK * 0.5).set_trans(Tween.TRANS_SINE)
		blink.tween_property(inner, "scale", Vector3.ONE * 0.9, ALARM_BLINK * 0.5).set_trans(Tween.TRANS_SINE)
		sfx.emit("alarm")
	var count_label: Label3D = root.get_node("Inner/Count")
	count_label.text = "剩 %d 张" % count


func alarm_count(pid: int) -> int:
	var root: Variant = _alarms.get(pid)
	if root == null or not is_instance_valid(root):
		return 0
	var text: String = (root as Node3D).get_node("Inner/Count").text
	return int(text.replace("剩", "").replace("张", "").strip_edges())


func clear_alarm(pid: int) -> void:
	var root: Variant = _alarms.get(pid)
	_alarms.erase(pid)
	if root != null and is_instance_valid(root):
		dismiss(root)


func clear_alarms() -> void:
	for pid in _alarms.keys():
		clear_alarm(pid)


# —— 「不出」——

func pass_mark(pid: int, pos: Vector3) -> void:
	clear_pass(pid)
	var root := _spawn("pass", -1.0)
	_passes[pid] = root
	root.global_position = pos
	var label := _label("不出", 0.55, Color(0.97, 0.93, 0.84))
	label.outline_modulate = Color(0.36, 0.26, 0.2)
	label.outline_size = 26
	root.add_child(label)
	root.scale = Vector3.ONE * 0.05
	var tween := root.create_tween()
	tween.tween_property(root, "scale", Vector3.ONE * 1.2, PASS_POP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(root, "scale", Vector3.ONE, 0.1)
	var bob := label.create_tween().set_loops()
	bob.tween_property(label, "position:y", 0.015, 0.6).set_trans(Tween.TRANS_SINE)
	bob.tween_property(label, "position:y", 0.0, 0.6).set_trans(Tween.TRANS_SINE)


func has_pass(pid: int) -> bool:
	return _passes.has(pid) and is_instance_valid(_passes[pid])


func clear_pass(pid: int) -> void:
	var root: Variant = _passes.get(pid)
	_passes.erase(pid)
	if root != null and is_instance_valid(root):
		dismiss(root)


func clear_passes() -> void:
	for pid in _passes.keys():
		clear_pass(pid)
