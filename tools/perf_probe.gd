extends SceneTree
# 性能探针:在离屏 SubViewport 里按指定分辨率渲染酒馆 + 展台,逐项关闭渲染特性,打印整帧耗时(毫秒)。
# 需要窗口渲染(不能 --headless);离屏渲染,不会占满屏幕,也不受显示器刷新率限制。
# 用法:godot --path . -s tools/perf_probe.gd -- [--size=3840x2160] [--view=seat,menu] [--frames=120]
#        [--cases=fsr-0.5+post-off,ssil-off] [--shot=<目录>] [--assert-budget]
# 不给 --cases 时逐项单独测一遍全部开关。--view 可用逗号给多个机位(机位表见 tools/camera_views.gd)。
# 每帧都让投影灯的阴影图失效重画(游戏里酒客呼吸、吊灯摆动,阴影图每帧都在重画);
# 每组打印整帧耗时、CPU 渲染线程耗时与可见 / 阴影 draw call、物体、图元。
# --assert-budget:按 tools/perf_budget.gd 核对 budget 那一组(游戏实际渲染配置),超预算时退出码为 1。
# --showcase=poker 用德州展台的最坏情况(8 位酒客、每摞筹码与下注摆满、7 个底池,约 900 枚筹码),
# 机位 seat / overview 取自 TableWorld;--showcase=bomb_cat 用炸弹猫 6 人大桌展台(手牌、牌堆、弃牌堆、自己举着 8 张),
# 机位 bomb_seat / bomb_overview / bomb_fp / bomb_close(预算见 tools/perf_budget.gd:bomb_seat、bomb_fp ≤ 700 draw call);第一人称 fp 两种展台都有(取自 TableWorld.first_person_view);德州的帧耗时要求不超过骗子酒馆 4 人展台的 1.25 倍(德州规格 §8)。
# --showcase=dou_dizhu 用斗地主 3 人小桌展台(出牌中:三家牌扇、两行牌、帽子、报警),机位 ddz_seat / ddz_overview / ddz_fp
# (预算:ddz_seat、ddz_fp ≤ 700 draw call,ddz_overview ≤ 900)。
# --showcase=liars_dice 用吹牛骰子 6 人大桌展台(六只骰盅、自己盅底下 5 颗骰子、桌心出价标记),机位 dice_seat / dice_overview /
# dice_fp / dice_close(预算见 tools/perf_budget.gd:dice_seat、dice_fp ≤ 700 draw call);--dice-state=counting 先摆开盅计数
# (全场 27 颗骰子排开、一半亮着金光圈)再测,默认 bidding。
# --celebrate:展台上开演结算庆祝(tools/celebrate_stage.gd,第一炮的彩纸正飘着时开测),机位 celebrate(胜者特写环绕)/
# celebrate_table(整桌环绕),三种展台都能用;预算同其余机位(≤ 900 draw call)。

const CameraViews := preload("res://tools/camera_views.gd")
const CelebrateStage := preload("res://tools/celebrate_stage.gd")
const PerfBudget := preload("res://tools/perf_budget.gd")
const SceneCensus := preload("res://tools/scene_census.gd")
const WARMUP_FRAMES := 60
const BIAS_NUDGE := 0.00001   # 每帧来回微调投影灯的 shadow_bias,让阴影图失效重画(画面看不出差别)
const SHOWCASES := {"liars": "res://tools/showcase.gd", "poker": "res://tools/poker_showcase.gd",
	"bomb_cat": "res://tools/bomb_cat_showcase.gd", "liars_dice": "res://tools/liars_dice_showcase.gd",
	"dou_dizhu": "res://tools/dou_dizhu_showcase.gd"}
# ④ 建的顶层节点(room-off / decor-off 用;同 tests/test_tavern_build.gd)
const ROOM_NODES := ["Room", "Fireplace", "Bar", "Window", "WindowView", "Door", "DoorView", "Decor_", "WallProps_", "Clock",
	"Pendulum", "Piano", "PianoBench", "CoatRack", "Barrel", "Crate", "Clutter", "Rugs", "Sconce", "Decals", "SmokeLayer", "HearthHaze"]

var opts := {}
var _viewport: SubViewport
var _tavern: Tavern
var _post_fx: PostFx
var _world: TableWorld = null   # 德州展台的牌桌:机位从它取
var _liars_world: TableWorld = null   # 骗子酒馆展台的牌桌:第一人称机位 fp 从它取
var _bomb: Node = null                 # 炸弹猫展台:bomb_* 机位从它取
var _ddz: Node = null                  # 斗地主展台:ddz_* 机位从它取
var _dice: Node = null                 # 吹牛骰子展台:dice_* 机位从它取
var _celebrate_world: TableWorld = null   # --celebrate:开演庆祝的牌桌
var _kind := "liars"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(320, 180)
	var dims: PackedStringArray = opts.get("size", "3840x2160").split("x")
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(int(dims[0]), int(dims[1]))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d")
	root.add_child(_viewport)
	_tavern = Tavern.new()
	_viewport.add_child(_tavern)
	await RoomTextures.build(_viewport)   # 墙地噪声与墙饰图集:不等的话测的是回退贴图
	_post_fx = PostFx.new()
	_viewport.add_child(_post_fx)
	var kind: String = opts.get("showcase", "liars")
	if not SHOWCASES.has(kind):
		push_error("unknown showcase %s (known: %s)" % [kind, ", ".join(SHOWCASES.keys())])
		quit(1)
		return
	var showcase: Node = load(SHOWCASES[kind]).new()
	if kind == "poker":
		showcase.set("worst_case", true)
	_viewport.add_child(showcase)
	await showcase.build(_tavern)
	_world = showcase.get("world") if kind == "poker" else null
	_bomb = showcase if kind == "bomb_cat" else null
	_ddz = showcase if kind == "dou_dizhu" else null
	_dice = showcase if kind == "liars_dice" else null
	if _dice != null:
		await _dice.stage(opts.get("dice-state", "bidding"))
	_liars_world = showcase.get("world") if kind == "liars" else null
	_kind = kind
	if opts.has("celebrate"):
		_celebrate_world = showcase.get("world")
		CelebrateStage.stage(_celebrate_world, kind)
		await create_timer(1.6).timeout   # 第一炮(0.55 秒)的彩纸飞到半空
	var rid := _viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	print("%s / %s  size=%s msaa=%d" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_driver_name(),
		_viewport.size, _viewport.msaa_3d])
	print("census ", SceneCensus.count(_viewport))
	print("texture memory %.1f MB" % (RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0))
	var toggles := _toggles()
	var cases: PackedStringArray = opts["cases"].split(",") if opts.has("cases") else PackedStringArray(toggles.keys())
	if opts.has("assert-budget") and not cases.has("budget"):
		cases.append("budget")
	var failures := PackedStringArray()
	for view in opts.get("view", "seat").split(","):
		if not _place_camera(view):
			push_error("unknown view %s (known: %s)" % [view, ", ".join(CameraViews.NAMES)])
			quit(1)
			return
		print("== view %s" % view)
		var base := await _measure()
		_report("baseline (all on)", base, base)
		_shot("%s-baseline" % view)
		for case in cases:
			var undos := []
			for name in case.split("+"):
				if not toggles.has(name):
					push_error("unknown toggle %s (known: %s)" % [name, ", ".join(toggles.keys())])
					quit(1)
					return
				undos.append(toggles[name].call())
			var m := await _measure()
			_report(case, m, base)
			_shot("%s-%s" % [view, case])
			if case == "budget" and opts.has("assert-budget"):
				failures.append_array(PerfBudget.violations(view, _budget_stats(m)))
			undos.reverse()
			for undo in undos:
				undo.call()
		_report("baseline again (drift check)", await _measure(), base)
	if opts.has("assert-budget"):
		for message in failures:
			print("OVER BUDGET: ", message)
		print("BUDGET %s" % ("FAIL" if failures.size() > 0 else "OK"))
		quit(1 if failures.size() > 0 else 0)
		return
	quit()


func _toggles() -> Dictionary:
	# 名字 -> 应用这项改动并返回撤销函数;--cases 用 + 组合多项,用 , 分隔多组
	var env := _tavern.environment
	return {
		"msaa-off": func(): return _swap(_viewport, "msaa_3d", Viewport.MSAA_DISABLED),
		"ssao-off": func(): return _swap(env, "ssao_enabled", false),
		"ssil-off": func(): return _swap(env, "ssil_enabled", false),
		"fog-off": func(): return _swap(env, "volumetric_fog_enabled", false),
		"glow-off": func(): return _swap(env, "glow_enabled", false),
		"shadows-off": _shadows_off,
		"post-off": func(): return _swap(_post_fx, "visible", false),
		"post-screen": _post_screen,
		"plain-shaders": _plain_materials,
		"fsr-0.75": func(): return _scale(0.75, Viewport.SCALING_3D_MODE_FSR),
		"fsr-0.67": func(): return _scale(0.667, Viewport.SCALING_3D_MODE_FSR),
		"fsr-0.5": func(): return _scale(0.5, Viewport.SCALING_3D_MODE_FSR),
		"bilinear-0.67": func(): return _scale(0.667, Viewport.SCALING_3D_MODE_BILINEAR),
		"bilinear-0.5": func(): return _scale(0.5, Viewport.SCALING_3D_MODE_BILINEAR),
		"budget": func(): return _budget(),
		"fsr2-0.5": func(): return _scale(0.5, Viewport.SCALING_3D_MODE_FSR2),
		"fsr2-0.67": func(): return _scale(0.667, Viewport.SCALING_3D_MODE_FSR2),
		"fxaa": func(): return _swap(_viewport, "screen_space_aa", Viewport.SCREEN_SPACE_AA_FXAA),
		"smaa": func(): return _swap(_viewport, "screen_space_aa", Viewport.SCREEN_SPACE_AA_SMAA),
		"sconce-lights-off": func(): return _lights_off("Sconce"),
		"candle-lights-off": func(): return _lights_off("Candles"),
		"lamp-lights-off": func(): return _lights_off("LampPivot"),
		"fireplace-light-off": func(): return _lights_off("Fireplace"),
		"fireplace-shadow-off": func(): return _shadow_off("Fireplace"),
		"ssil-low": func(): return _ssil_quality(RenderingServer.ENV_SSIL_QUALITY_LOW),
		"ssao-low": func(): return _ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW),
		"fog-small": _fog_small,
		"soft-shadow-hard": func(): return _soft_shadows(RenderingServer.SHADOW_QUALITY_HARD),
		"patrons-off": func(): return _hide(_viewport.find_children("*", "Patron", true, false)),
		"revolvers-off": func(): return _hide(_viewport.find_children("*", "Revolver3D", true, false)),
		"bottles-off": func(): return _hide(_bottles()),
		# ④ 房间子预算:只隐藏 ④ 建的网格、MultiMesh、贴花与雾,灯一律不动
		"room-off": func(): return _hide(_room_visuals(false)),
		"decor-off": func(): return _hide(_room_visuals(true)),
	}


func _room_visuals(decor_only: bool) -> Array:
	# ④ 建的可视节点:decor_only 时只取墙饰、地毯与外景(decor 材质的网格)
	var out := []
	for node in _tavern.find_children("*", "", true, false):
		var visual: bool = node is GeometryInstance3D or node is Decal or node is FogVolume
		if not visual or node is Light3D or node is GPUParticles3D:
			continue
		if node is GeometryInstance3D and node.material_override is ShaderMaterial \
				and node.material_override.shader == WorldMaterials.FLAME_SHADER:
			continue   # 火焰片不是 ④ 新建的
		if decor_only:
			var mesh: Mesh = node.mesh if node is MeshInstance3D else null
			if mesh != null and mesh.get_surface_count() > 0 and mesh.surface_get_material(0) == WorldMaterials.decor():
				out.append(node)
			continue
		var top: Node = node
		while top.get_parent() != _tavern:
			top = top.get_parent()
		for prefix in ROOM_NODES:
			if String(top.name).begins_with(prefix) and not (top.name == &"Bar" and node is MultiMeshInstance3D and String(node.name).begins_with("Bottles")):
				out.append(node)
				break
	return out


func _budget() -> Callable:
	# 游戏实际使用的配置(RenderBudget):限制 3D 像素数 + FSR 放大 + SMAA
	var undos := [_swap(_viewport, "msaa_3d", _viewport.msaa_3d), _swap(_viewport, "screen_space_aa", _viewport.screen_space_aa),
		_swap(_viewport, "scaling_3d_mode", _viewport.scaling_3d_mode), _swap(_viewport, "scaling_3d_scale", _viewport.scaling_3d_scale)]
	RenderBudget.apply(_viewport)
	return func():
		for undo in undos:
			undo.call()


func _post_screen() -> Callable:
	# 强制走读屏幕的完整后处理(去饱和给一个看不出来的量),对比只叠加的平时状态
	_post_fx._set_param("desaturate", 0.002)
	return func(): _post_fx._set_param("desaturate", 0.0)


func _lights_under(prefix: String) -> Array:
	return _viewport.find_children("*", "Light3D", true, false).filter(
		func(l: Light3D): return String(l.get_parent().name).begins_with(prefix))


func _lights_off(prefix: String) -> Callable:
	var lights := _lights_under(prefix)
	for light in lights:
		light.visible = false
	return func():
		for light in lights:
			light.visible = true


func _shadow_off(prefix: String) -> Callable:
	var lights := _lights_under(prefix).filter(func(l): return l.shadow_enabled)
	for light in lights:
		light.shadow_enabled = false
	return func():
		for light in lights:
			light.shadow_enabled = true


func _ssil_quality(quality: RenderingServer.EnvironmentSSILQuality) -> Callable:
	RenderingServer.environment_set_ssil_quality(quality, true, 0.5, 4, 50.0, 300.0)
	return func(): RenderingServer.environment_set_ssil_quality(_setting("ssil/quality"), _setting("ssil/half_size"),
		_setting("ssil/adaptive_target"), _setting("ssil/blur_passes"), _setting("ssil/fadeout_from"), _setting("ssil/fadeout_to"))


func _ssao_quality(quality: RenderingServer.EnvironmentSSAOQuality) -> Callable:
	RenderingServer.environment_set_ssao_quality(quality, true, 0.5, 2, 50.0, 300.0)
	return func(): RenderingServer.environment_set_ssao_quality(_setting("ssao/quality"), _setting("ssao/half_size"),
		_setting("ssao/adaptive_target"), _setting("ssao/blur_passes"), _setting("ssao/fadeout_from"), _setting("ssao/fadeout_to"))


func _fog_small() -> Callable:
	RenderingServer.environment_set_volumetric_fog_volume_size(48, 48)
	return func(): RenderingServer.environment_set_volumetric_fog_volume_size(_setting("volumetric_fog/volume_size"),
		_setting("volumetric_fog/volume_depth"))


func _soft_shadows(quality: RenderingServer.ShadowQuality) -> Callable:
	RenderingServer.positional_soft_shadow_filter_set_quality(quality)
	RenderingServer.directional_soft_shadow_filter_set_quality(quality)
	return func():
		RenderingServer.positional_soft_shadow_filter_set_quality(
			ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality"))
		RenderingServer.directional_soft_shadow_filter_set_quality(
			ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"))


func _setting(key: String) -> Variant:
	return ProjectSettings.get_setting("rendering/environment/" + key)


func _swap(target: Object, property: String, value: Variant) -> Callable:
	var old: Variant = target.get(property)
	target.set(property, value)
	return func(): target.set(property, old)


func _scale(scale: float, mode: Viewport.Scaling3DMode) -> Callable:
	var undo_scale := _swap(_viewport, "scaling_3d_scale", scale)
	var undo_mode := _swap(_viewport, "scaling_3d_mode", mode)
	return func():
		undo_scale.call()
		undo_mode.call()


func _shadows_off() -> Callable:
	var lights := _viewport.find_children("*", "Light3D", true, false).filter(func(l): return l.shadow_enabled)
	for light in lights:
		light.shadow_enabled = false
	return func():
		for light in lights:
			light.shadow_enabled = true


func _plain_materials() -> Callable:
	# 把程序化 ShaderMaterial 换成同色的 StandardMaterial3D,估算这些着色器的片元开销
	var swapped := []
	for node in _viewport.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for i in mesh_node.mesh.get_surface_count():
			var mat := mesh_node.get_active_material(i)
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader.get_mode() == Shader.MODE_SPATIAL:
				var plain := StandardMaterial3D.new()
				var tint: Variant = (mat as ShaderMaterial).get_shader_parameter("color_light")
				plain.albedo_color = tint if tint is Color else Color(0.4, 0.3, 0.2)
				swapped.append([mesh_node, i, mesh_node.get_surface_override_material(i)])
				mesh_node.set_surface_override_material(i, plain)
	print("  (swapped %d procedural surfaces)" % swapped.size())
	return func():
		for entry in swapped:
			entry[0].set_surface_override_material(entry[1], entry[2])


func _measure() -> Dictionary:
	# Metal 上 viewport_get_measured_render_time_gpu 恒为 0,窗口呈现又会被系统按刷新率节流:
	# 先走几帧让改动生效,再连续 force_draw(不交换缓冲、不等垂直同步),GPU 排满后吞吐就是每帧 GPU 耗时。
	# force_draw 期间场景不动,阴影图会一直沿用缓存:每帧微调投影灯的参数让它重画,和游戏里一致
	for i in WARMUP_FRAMES:
		await process_frame
	var frames := int(opts.get("frames", "120"))
	var times := PackedFloat64Array()
	var cpu := 0.0
	var rid := _viewport.get_viewport_rid()
	var lights := _viewport.find_children("*", "Light3D", true, false).filter(func(l): return l.shadow_enabled and l.visible)
	_nudge(lights, 0)
	RenderingServer.force_draw(false)
	var last := Time.get_ticks_usec()
	for i in frames:
		_nudge(lights, i + 1)
		RenderingServer.force_draw(false)
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	times.sort()
	var total := 0.0
	for t in times:
		total += t
	var info := func(type: RenderingServer.ViewportRenderInfoType, what: RenderingServer.ViewportRenderInfo) -> int:
		return RenderingServer.viewport_get_render_info(rid, type, what)
	var visible_dc: int = info.call(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var shadow_dc: int = info.call(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	_nudge(lights, 0)
	return {
		"avg": total / frames, "p95": times[int(frames * 0.95)], "cpu": cpu / frames,
		"visible_dc": visible_dc, "shadow_dc": shadow_dc,
		"objects": info.call(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
			+ info.call(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		"primitives": info.call(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
			+ info.call(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
	}


func _place_camera(view: String) -> bool:
	if CelebrateStage.VIEWS.has(view) and _celebrate_world != null:
		var xform := CelebrateStage.view(_celebrate_world, _kind, view, float(_viewport.size.x) / _viewport.size.y)
		_tavern.camera_rig.stop_follow()
		_tavern.camera_rig.camera.fov = CameraRig.DEFAULT_FOV
		_tavern.camera_rig.snap(xform.origin, xform.origin - xform.basis.z)
		_tavern.camera_rig.fill_light.light_energy = CelebrateStage.fill(_celebrate_world, _kind, view)
		return true
	if _bomb != null and view.begins_with("bomb_"):
		var bomb_world: TableWorld = _bomb.world
		if view == "bomb_fp":
			CameraViews.place_first_person(_tavern.camera_rig, bomb_world, 1, view)
			return true
		CameraViews.leave_first_person(bomb_world, 1)
		_bomb.cards.present_my_fan()
		_tavern.camera_rig.stop_follow()
		_tavern.camera_rig.camera.fov = CameraRig.DEFAULT_FOV
		var bomb_xform: Transform3D = _bomb.view(view)
		_tavern.camera_rig.snap(bomb_xform.origin, bomb_xform.origin - bomb_xform.basis.z)
		_tavern.camera_rig.fill_light.light_energy = TableWorld.SEAT_FILL_LIGHT if view == "bomb_seat" else 0.0
		return true
	if _ddz != null and view.begins_with("ddz_"):
		# 斗地主展台(出牌中的那一桌):座位越肩 / 第一人称 / 俯视
		var ddz_world: TableWorld = _ddz.world
		if view == "ddz_fp":
			CameraViews.place_first_person(_tavern.camera_rig, ddz_world, 1, view)
			return true
		CameraViews.leave_first_person(ddz_world, 1)
		_ddz.cards.present_my_fan()
		_tavern.camera_rig.stop_follow()
		_tavern.camera_rig.camera.fov = CameraRig.DEFAULT_FOV
		var ddz_xform: Transform3D = _ddz.view(view)
		_tavern.camera_rig.snap(ddz_xform.origin, ddz_xform.origin - ddz_xform.basis.z)
		_tavern.camera_rig.fill_light.light_energy = TableWorld.SEAT_FILL_LIGHT if view == "ddz_seat" else 0.0
		return true
	if _dice != null and view.begins_with("dice_"):
		var dice_world: TableWorld = _dice.world
		if view == "dice_fp":
			CameraViews.place_first_person(_tavern.camera_rig, dice_world, 1, view)
			return true
		CameraViews.leave_first_person(dice_world, 1)
		_tavern.camera_rig.stop_follow()
		_tavern.camera_rig.camera.fov = CameraRig.DEFAULT_FOV
		var dice_xform: Transform3D = _dice.view(view)
		_tavern.camera_rig.snap(dice_xform.origin, dice_xform.origin - dice_xform.basis.z)
		_tavern.camera_rig.fill_light.light_energy = TableWorld.SEAT_FILL_LIGHT if view == "dice_seat" else 0.0
		return true
	if view == "fp" or view == "poker_fp":
		# 第一人称(V 切换):自己的头只投影不渲染,手牌拿在镜头右下方
		var fp_world := _world if _world != null else _liars_world
		CameraViews.place_first_person(_tavern.camera_rig, fp_world, 1, view)
		return true
	for w in [_world, _liars_world]:
		if w != null:
			CameraViews.leave_first_person(w, 1)
	if _world != null:
		# 德州展台:本机座位 = 1 号的越肩或观战机位
		var xform := _world.overview_view() if view == "overview" else _world.third_person_view(1)
		_tavern.camera_rig.snap(xform.origin, xform.origin - xform.basis.z)
		_tavern.camera_rig.fill_light.light_energy = 0.0 if view == "overview" else TableWorld.SEAT_FILL_LIGHT
		return true
	return CameraViews.place(_tavern.camera_rig, view)


func _nudge(lights: Array, frame: int) -> void:
	# 偶数帧还原、奇数帧加一点:灯参数一变,这盏灯的阴影图就整张重画
	for light in lights:
		light.shadow_bias = snappedf(light.shadow_bias, BIAS_NUDGE * 2.0) + (BIAS_NUDGE if frame % 2 == 1 else 0.0)


func _budget_stats(m: Dictionary) -> Dictionary:
	# 探针的测量结果换成 PerfBudget 用的统计键;灯数等清点项来自 SceneCensus
	var stats := SceneCensus.count(_viewport)
	stats.merge({
		"draw_calls": m["visible_dc"] + m["shadow_dc"], "visible_draw_calls": m["visible_dc"],
		"shadow_draw_calls": m["shadow_dc"], "objects": m["objects"], "primitives": m["primitives"],
		"frame_ms": m["avg"], "cpu_ms": m["cpu"],
	}, true)
	return stats


func _hide(nodes: Array) -> Callable:
	var shown := nodes.filter(func(n: Node3D): return n.visible)
	for node in shown:
		node.visible = false
	return func():
		for node in shown:
			node.visible = true


func _bottles() -> Array:
	# 吧台搁板上的酒瓶:合批前是一件件圆柱,合批后是 MultiMesh
	var out := []
	for bar in _viewport.find_children("Bar", "Node3D", true, false):
		for child in bar.get_children():
			if child is MultiMeshInstance3D or (child is MeshInstance3D and child.mesh is CylinderMesh and child.position.y > 1.5):
				out.append(child)
	return out


func _shot(label: String) -> void:
	# --shot=<目录> 时把每组配置的画面存成 PNG,对比画质损失
	if not opts.has("shot"):
		return
	DirAccess.make_dir_recursive_absolute(opts["shot"])
	var path := "%s/%s.png" % [opts["shot"], label]
	_viewport.get_texture().get_image().save_png(path)


func _report(label: String, m: Dictionary, base: Dictionary) -> void:
	print("%-30s frame %6.2f ms  p95 %6.2f ms  (%+6.2f ms vs base, %5.1f fps)  cpu %5.2f ms  dc %4d (vis %4d + shadow %4d)  obj %5d  prims %7d" % [
		label, m["avg"], m["p95"], m["avg"] - base["avg"], 1000.0 / m["avg"], m["cpu"],
		m["visible_dc"] + m["shadow_dc"], m["visible_dc"], m["shadow_dc"], m["objects"], m["primitives"]])
