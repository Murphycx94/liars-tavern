class_name StandModel
# 桌心目标牌立架的网格配方(纯数组运算):固定不转的车削底座(蜂蜜木小馒头 + 糖果粉圆钮)+ 会转的立轴(两颗圆珠)与叉形夹。
# 坐标都在 TargetStand(桌面 TABLE_TOP 处)局部;底座在内部抬高到毡面(FELT_TOP)上。


const FELT := SeatLayout.FELT_TOP - SeatLayout.TABLE_TOP
const SKIRT_RADIUS := 0.044   # 裙边很矮(≤ 2 mm):牌堆里有少量牌会伸进 r < 0.045
const BODY_TOP := FELT + 0.019
const CLIP_BOTTOM := 0.091    # 叉形夹叶片下端(牌底在 STAND_HEIGHT − 0.006 = 0.094)
const LEAF_OFFSET := 0.0012   # 两片叶片在牌法线方向(立架局部 Z)的偏移


static func base(f: MeshForge) -> void:
	# s0 = 木(蜂蜜色车削):矮裙边上一只圆鼓鼓的小馒头(r ≤ 0.031,二次打磨 2026-10-10 换掉 ogee 线脚);
	# s1 = prop:裙边上的柔黄铜细线、顶上一颗糖果粉圆钮(轴承帽)
	f.surface(&"wood")
	f.part_space = true
	var bun := PackedVector2Array([Vector2(0.0, FELT), Vector2(SKIRT_RADIUS, FELT), Vector2(SKIRT_RADIUS, FELT + 0.0012),
		Vector2(SKIRT_RADIUS - 0.0012, FELT + 0.0019), Vector2(0.032, FELT + 0.0019)])
	# 馒头:从 r 0.031 鼓起到顶面 r 0.0098 的四分之一椭圆(竖 BODY_TOP − 底),肩部圆润
	for k in 9:
		var a := PI / 2.0 * k / 8.0
		bun.append(Vector2(0.0098 + (0.031 - 0.0098) * cos(a), FELT + 0.0019 + (BODY_TOP - FELT - 0.0019) * sin(a)))
	bun.append(Vector2(0.0, BODY_TOP))
	f.lathe(bun, 48, PackedInt32Array([1, 2, 4]))
	f.part_space = false
	f.surface(&"metal")
	WorldMaterials.paint_prop(f, "brass_soft")
	f.lathe(PackedVector2Array([Vector2(0.0365, FELT + 0.0019), Vector2(0.0372, FELT + 0.0025), Vector2(0.0395, FELT + 0.0025),
		Vector2(0.0402, FELT + 0.0019)]), 48)
	WorldMaterials.paint_prop(f, "candy_pink")
	f.lathe(PackedVector2Array([Vector2(0.0, BODY_TOP - 0.0005), Vector2(0.0092, BODY_TOP - 0.0005), Vector2(0.0090, BODY_TOP + 0.0014),
		Vector2(0.0072, BODY_TOP + 0.0032), Vector2(0.0040, BODY_TOP + 0.0042), Vector2(0.0, BODY_TOP + 0.0045)]), 24, PackedInt32Array([1]))


static func clip(f: MeshForge, top: float) -> void:
	# 立轴(r 4.5 mm,两道珠环)+ 叉形夹:两片 1 mm 黄铜叶片夹住牌底 6 mm(不投影)
	var xf := MeshForge.xf
	f.surface(&"metal")
	WorldMaterials.paint_prop(f, "brass")
	var y0 := BODY_TOP
	f.lathe(PackedVector2Array([Vector2(0.0045, y0), Vector2(0.0042, CLIP_BOTTOM - 0.002), Vector2(0.0, CLIP_BOTTOM - 0.002)]), 16)
	# 立轴上两颗圆珠(代替细珠环):下面一颗大的糖果粉、上面一颗小的黄铜
	WorldMaterials.paint_prop(f, "candy_pink")
	f.sphere(0.0085, 16, xf.call(Vector3(0, 0.040, 0)))
	WorldMaterials.paint_prop(f, "brass")
	f.sphere(0.0062, 12, xf.call(Vector3(0, 0.0815, 0)))
	f.box(Vector3(0.026, 0.0035, 0.0044), xf.call(Vector3(0, CLIP_BOTTOM - 0.0005, 0)))
	for side in [-1.0, 1.0]:
		f.box(Vector3(0.022, top - CLIP_BOTTOM + 0.002, 0.001), xf.call(Vector3(0, (top + CLIP_BOTTOM) / 2.0 + 0.001, side * LEAF_OFFSET)))
		f.sphere(0.0016, 8, xf.call(Vector3(0, top - 0.002, side * (LEAF_OFFSET + 0.0006))))
