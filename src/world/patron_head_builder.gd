class_name PatronHeadBuilder
# 酒客的头、眼、眉、耳(合批配方)。头部坐标都在 Head 枢轴局部,头心固定在 (0, 0.12, 0)(瞄准点与机位目标)。
# 头雕是椭球平滑并集(颅骨、腮、口鼻),长吻另放样一段;斑纹靠形体颜色混合;眼睛由 patron_eye.gdshader 画。
# Q 版:LOOK 里的坐标按原尺寸写,配方开头 push 一个绕头心的放大(PatronParts.head_xform),整颗头连特件一起变大;
# 眉、耳挂在各自枢轴上,网格绕原点放大(pivot_scale),枢轴位置由 Patron 用 PatronParts.head_point 换算。

const HEAD_CENTER := Vector3(0, 0.12, 0)
# 动森式小嘴:LOOK 里写的嘴宽再乘这个(头放大后嘴不跟着咧那么宽),线条加粗一点像画上去的
const MOUTH_WIDTH := 0.62
const MOUTH_THICKNESS := 1.35
# 腮红:眼睛下方外侧贴着颅骨埋一个小椭球,颜色在平滑并集里柔和地晕开(不加三角形)
const BLUSH_OFFSET := Vector3(0.03, -0.06, 0.0)
const BLUSH_RADII := Vector3(0.026, 0.016, 0.016)


static func skull_shapes(look: Dictionary, pal: Dictionary) -> Array:
	return PatronBuilder.shapes_colored(look["head"]["skull"], pal)


static func blush_shape(look: Dictionary, pal: Dictionary, shapes: Array) -> Array:
	# 腮红椭球:从头心朝眼睛下方外侧打射线取颅骨表面点,往里埋一点(只露出 ≈2 mm,平滑并集把颜色晕开)
	var eye: Vector3 = look["eyes"]["pos"]
	var target := eye + BLUSH_OFFSET
	var k: float = look["head"].get("blend", 0.04)
	var p := MeshForge.blob_surface(HEAD_CENTER, target - HEAD_CENTER, shapes, k)
	var inward := (HEAD_CENTER - p).normalized()
	return [p + inward * (BLUSH_RADII.z - 0.002), BLUSH_RADII, PatronBuilder.color(pal, "blush"), "mirror"]


static func head(f: MeshForge, look: Dictionary, pal: Dictionary, hooks: GDScript) -> void:
	PatronBuilder.start(f, 0.6)
	f.push(PatronParts.head_xform(look))
	var h: Dictionary = look["head"]
	var shapes := skull_shapes(look, pal)
	if h.get("blush", false):
		shapes.append(blush_shape(look, pal, shapes))
	PatronBuilder.paint(f, pal, "fur", 0.75, h.get("material", PatronBuilder.FUR))
	f.blob(HEAD_CENTER, shapes, 40, 24, h.get("blend", 0.04))
	var snout: Dictionary = h.get("snout", {})
	if not snout.is_empty():
		# 长吻:从颅骨里埋进 2 cm 起,沿 -Z 渐细,吻尖圆头
		var path := PackedVector3Array(snout["path"])
		var radii := PackedVector2Array(snout["radii"])
		PatronBuilder.paint(f, pal, snout.get("color", "muzzle"), 0.75, h.get("material", PatronBuilder.FUR))
		f.loft(path, radii, 16, Vector2i(0, 1))
		f.sphere(radii[radii.size() - 1].x, 14, PatronBuilder.xf(path[path.size() - 1], Vector3.ZERO,
			Vector3(1.0, radii[radii.size() - 1].y / radii[radii.size() - 1].x, 1.0)))
	var nose: Dictionary = h.get("nose", {})
	if not nose.is_empty():
		PatronBuilder.paint(f, pal, nose.get("color", "nose"), nose.get("rough", 0.2), PatronBuilder.LEATHER)
		f.sphere(1.0, 14, PatronBuilder.xf(nose["pos"], Vector3.ZERO, nose["radii"]))
	_mouth(f, pal, h)
	hooks.extras(f, "head", look, pal)
	f.pop()


static func _mouth(f: MeshForge, pal: Dictionary, h: Dictionary) -> void:
	var m: Dictionary = h.get("mouth", {})
	if m.is_empty():
		return
	var at: Vector3 = m["pos"]
	var w: float = m.get("width", 0.06) * MOUTH_WIDTH
	var path := PackedVector3Array()
	match m.get("kind", "smile"):
		"smirk":   # 坏笑:一边嘴角翘
			path = PackedVector3Array([at + Vector3(-w * 0.5, 0.004, 0.01), at + Vector3(0, -0.004, 0), at + Vector3(w * 0.5, 0.012, 0.012)])
		"w":       # 猫的 w 嘴
			path = PackedVector3Array([at + Vector3(-w * 0.5, 0.004, 0.012), at + Vector3(-w * 0.22, -0.006, 0.0), at + Vector3(0, 0.004, -0.004),
				at + Vector3(w * 0.22, -0.006, 0.0), at + Vector3(w * 0.5, 0.004, 0.012)])
		"wide":    # 咧嘴笑
			path = PackedVector3Array([at + Vector3(-w * 0.5, 0.012, 0.016), at + Vector3(-w * 0.25, -0.006, 0.004), at + Vector3(0, -0.01, 0),
				at + Vector3(w * 0.25, -0.006, 0.004), at + Vector3(w * 0.5, 0.012, 0.016)])
		_:         # 微笑
			path = PackedVector3Array([at + Vector3(-w * 0.5, 0.006, 0.01), at + Vector3(0, -0.005, 0), at + Vector3(w * 0.5, 0.006, 0.01)])
	PatronBuilder.paint(f, pal, m.get("color", "dark"), 0.5, PatronBuilder.SMOOTH)
	f.tube(path, m.get("thickness", 0.0032) * MOUTH_THICKNESS, 6)


# —— 眼睛 ——

static func eyes(f: MeshForge, look: Dictionary) -> void:
	# 两只眼一个网格,CUSTOM0 写眼面坐标 (u, v, 左右, 0) 给 patron_eye.gdshader。
	# 动森式「画在脸上」的大眼:眼面在放大后的颅骨上按眼睛朝向投影,贴着脸的曲面,只往外鼓 EYE_DEPTH 那么一点
	# (像一层薄薄的贴片);横竖在头放大之上再大 EYE_SCALE 倍。法线是颅骨法线略带一点眼球的鼓
	var e: Dictionary = look["eyes"]
	var scale := PatronParts.head_scale(look)
	var pos: Vector3 = PatronParts.head_point(look, e["pos"])
	var raw: Vector3 = e.get("size", Vector3(0.04, 0.045, 0.02))
	var size := Vector3(raw.x * scale.x * PatronParts.EYE_SCALE, raw.y * scale.y * PatronParts.EYE_SCALE,
		raw.z * PatronParts.HEAD_SCALE * PatronParts.EYE_DEPTH)
	var shapes := scaled_skull(look)
	var k: float = look["head"].get("blend", 0.04) * PatronParts.HEAD_SCALE
	var list := MeshForge._expand_shapes(shapes)
	# 眼面离颅骨的最小高度:脸上贴了花纹贴片(熊猫眼斑、企鹅白脸,离颅骨 ≈2–3 mm)的物种在 LOOK eyes.lift 里抬高,眼圈不被贴片盖住
	var lift: float = e.get("lift", 0.0015)
	f.paint(Color(0.66, 0.65, 0.62), 0.15)
	for side: float in [-1.0, 1.0]:
		var center := Vector3(pos.x * side, pos.y, pos.z)
		# 眼睛朝外偏一点(跟着颅骨曲面),正面投影出眼面坐标
		var yaw := deg_to_rad(e.get("yaw", 12.0)) * side
		var basis := Basis(Vector3.UP, -yaw)
		var fwd := basis * Vector3(0, 0, -1)
		var points := PackedVector3Array()
		var normals := PackedVector3Array()
		var customs := PackedFloat32Array()
		var indices := PackedInt32Array()
		var seg := 18
		var rings := 9
		for j in rings + 1:
			var theta := (PI * 0.5) * j / rings   # 0 = 正前方中心 → π/2 = 边缘
			for i in seg + 1:
				var phi := TAU * i / seg
				var plane := center + basis * Vector3(sin(theta) * cos(phi) * size.x, sin(theta) * sin(phi) * size.y, 0.0)
				var surf := MeshForge.blob_surface(plane - fwd * 0.2, fwd, shapes, k)
				var n := _sdf_normal(surf, list, k)
				var dome := cos(theta)
				points.append(surf + n * (size.z * dome + lift))
				var bulge := basis * Vector3(sin(theta) * cos(phi) / size.x, sin(theta) * sin(phi) / size.y, 0.0) * 0.02
				normals.append((n + bulge * dome).normalized())
				customs.append_array([sin(theta) * cos(phi), sin(theta) * sin(phi), side, 0.0])
				if i > 0 and j > 0:
					var prevrow := (j - 1) * (seg + 1)
					var thisrow := j * (seg + 1)
					indices.append_array([prevrow + i - 1, thisrow + i - 1, prevrow + i, prevrow + i, thisrow + i - 1, thisrow + i])
		f._append(points, normals, indices, Transform3D.IDENTITY, PackedColorArray(), customs)


static func scaled_skull(look: Dictionary) -> Array:
	# 放大后的颅骨形体(Head 局部):椭球中心按头心换算、半径按轴缩放(轴对齐椭球缩放后仍是椭球);颜色不用
	var out := []
	var scale := PatronParts.head_scale(look)
	for s: Array in look["head"]["skull"]:
		var item := [PatronParts.head_point(look, s[0]), (s[1] as Vector3) * scale, Color.WHITE]
		if s.size() > 3:
			item.append(s[3])
		out.append(item)
	return out


static func _sdf_normal(p: Vector3, list: Array, k: float) -> Vector3:
	var eps := 0.002
	var grad := Vector3(
		MeshForge._blob_sdf(p + Vector3(eps, 0, 0), list, k) - MeshForge._blob_sdf(p - Vector3(eps, 0, 0), list, k),
		MeshForge._blob_sdf(p + Vector3(0, eps, 0), list, k) - MeshForge._blob_sdf(p - Vector3(0, eps, 0), list, k),
		MeshForge._blob_sdf(p + Vector3(0, 0, eps), list, k) - MeshForge._blob_sdf(p - Vector3(0, 0, eps), list, k))
	return grad.normalized() if grad.length_squared() > 1e-12 else Vector3(0, 0, -1)


# —— 眉毛 ——

static func brow(f: MeshForge, look: Dictionary, pal: Dictionary) -> void:
	# 一条圆头圆尾、沿额头微弯的短粗眉(动森式的「豆子眉」);枢轴在眉心位置(表情动画转它)
	PatronBuilder.start(f, 0.7)
	f.push(PatronParts.pivot_scale(PatronParts.BROW_SCALE))
	var br: Dictionary = look["brows"]
	var w: float = br.get("width", 0.062)
	var t: float = br.get("thickness", 0.011)
	PatronBuilder.paint(f, pal, br.get("color", "dark"), 0.7, PatronBuilder.FUR)
	f.loft(PackedVector3Array([Vector3(-w * 0.5, -0.003, 0.004), Vector3(0, 0.004, -0.002), Vector3(w * 0.5, 0.0, 0.006)]),
		PackedVector2Array([Vector2(t * 0.9, t * 0.75), Vector2(t, t * 0.8), Vector2(t * 0.75, t * 0.65)]), 8, Vector2i(1, 1),
		Transform3D.IDENTITY, PackedColorArray(), Vector2(-1, -1), Vector3(0, 0, -1))
	f.pop()


# —— 耳朵(枢轴在耳根,左右共用一份;薄片透光)——

static func ear(f: MeshForge, look: Dictionary, pal: Dictionary) -> void:
	PatronBuilder.start(f, 0.8)
	f.push(PatronParts.pivot_scale(PatronParts.EAR_SCALE))
	var e: Dictionary = look.get("ears", {})
	var kind: String = e.get("kind", "none")
	var size: Vector3 = e.get("size", Vector3(0.05, 0.15, 0.02))
	var outer: String = e.get("color", "fur")
	var inner: String = e.get("inner", "cream")
	f.custom.w = 1.0
	match kind:
		"pointy", "cat":
			# 尖叶耳:扁圆锥放样,内侧再贴一层浅色;猫耳更短更三角
			var sides := 4 if kind == "cat" else 10
			var h := size.y
			PatronBuilder.paint(f, pal, outer, 0.75, PatronBuilder.FUR)
			f.custom.w = 1.0
			f.loft(PackedVector3Array([Vector3(0, -0.02, 0), Vector3(0, h * 0.45, 0), Vector3(0, h, 0)]),
				PackedVector2Array([Vector2(size.z, size.x), Vector2(size.z * 0.75, size.x * 0.7), Vector2(0.003, 0.004)]), sides,
				Vector2i(1, 1), Transform3D.IDENTITY, _tip_colors(pal, outer, e.get("tip", outer), 3), Vector2(-1, -1), Vector3(0, 0, -1))
			PatronBuilder.paint(f, pal, inner, 0.8, PatronBuilder.FUR)
			f.custom.w = 1.0
			f.loft(PackedVector3Array([Vector3(0, 0.0, -size.z * 0.6), Vector3(0, h * 0.42, -size.z * 0.55), Vector3(0, h * 0.85, -size.z * 0.3)]),
				PackedVector2Array([Vector2(size.z * 0.35, size.x * 0.6), Vector2(size.z * 0.3, size.x * 0.42), Vector2(0.002, 0.003)]), sides,
				Vector2i(1, 1), Transform3D.IDENTITY, PackedColorArray(), Vector2(-1, -1), Vector3(0, 0, -1))
		"round", "side_round":
			# 圆杯耳:扁球外壳 + 内侧凹面的浅色
			PatronBuilder.paint(f, pal, outer, 0.75, PatronBuilder.FUR)
			f.custom.w = 1.0
			f.sphere(1.0, 16, PatronBuilder.xf(Vector3.ZERO, Vector3.ZERO, size))
			PatronBuilder.paint(f, pal, inner, 0.8, PatronBuilder.FUR)
			f.custom.w = 1.0
			f.sphere(1.0, 14, PatronBuilder.xf(Vector3(0, -size.y * 0.06, -size.z * 0.55), Vector3.ZERO, size * Vector3(0.66, 0.66, 0.6)))
		"floppy":
			# 软耳:往前下方折的扁片
			PatronBuilder.paint(f, pal, outer, 0.75, PatronBuilder.FUR)
			f.custom.w = 1.0
			f.loft(PackedVector3Array([Vector3(0, 0, 0), Vector3(0, size.y * 0.45, -0.02), Vector3(0, size.y * 0.75, -0.06), Vector3(0, size.y * 0.85, -0.1)]),
				PackedVector2Array([Vector2(size.z, size.x), Vector2(size.z, size.x * 1.05), Vector2(size.z * 0.8, size.x * 0.75), Vector2(0.004, 0.012)]), 10,
				Vector2i(1, 1), Transform3D.IDENTITY, PackedColorArray(), Vector2(-1, -1), Vector3(0, 0, -1))
		"banana":
			# 羊驼的香蕉耳:细长,尖端向内弯
			PatronBuilder.paint(f, pal, outer, 0.75, PatronBuilder.FUR)
			f.custom.w = 1.0
			f.loft(PackedVector3Array([Vector3(0, -0.01, 0), Vector3(0, size.y * 0.4, 0), Vector3(-0.008, size.y * 0.8, 0), Vector3(-0.025, size.y, 0.004)]),
				PackedVector2Array([Vector2(size.z, size.x), Vector2(size.z, size.x), Vector2(size.z * 0.8, size.x * 0.7), Vector2(0.003, 0.005)]), 10,
				Vector2i(1, 1), Transform3D.IDENTITY, PackedColorArray(), Vector2(-1, -1), Vector3(0, 0, -1))
			PatronBuilder.paint(f, pal, inner, 0.8, PatronBuilder.FUR)
			f.custom.w = 1.0
			f.loft(PackedVector3Array([Vector3(0, 0.0, -size.z * 0.6), Vector3(0, size.y * 0.5, -size.z * 0.55), Vector3(-0.01, size.y * 0.82, -size.z * 0.3)]),
				PackedVector2Array([Vector2(size.z * 0.3, size.x * 0.55), Vector2(size.z * 0.3, size.x * 0.5), Vector2(0.002, 0.003)]), 8,
				Vector2i(1, 1), Transform3D.IDENTITY, PackedColorArray(), Vector2(-1, -1), Vector3(0, 0, -1))
	f.custom.w = 0.0
	f.pop()


static func _tip_colors(pal: Dictionary, base: String, tip: String, count: int) -> PackedColorArray:
	var out := PackedColorArray()
	for i in count:
		var c := PatronBuilder.color(pal, tip if i == count - 1 else base)
		out.append(Color(c.r, c.g, c.b, 1.0))
	return out
