extends GutTest
# 斗地主的身份帽(瓜皮帽 / 草帽)按物种贴合(穿模修复 2026-10-10,DdzHats.FIT 由 tools/ddz_hat_fit.gd 按真实网格量出):
# 8 个物种 × 两顶帽子,走游戏里戴帽的同一个入口(DdzHats.put_on),判定按真实三角形(TriangleMesh 线段求交,两个方向都查):
# - 帽子不碰头(颅骨、眼、眉),也不整顶埋在头里:帽口一圈往上看不到头的表面;帽口离头顶不超过 FLOAT(坐在头上,不是飘着);
# - 帽子不碰耳朵(草帽在帽檐上开了耳洞,耳朵从洞里穿出去不算碰);
# - 帽顶不超过 HEAD_TOP(Head 局部;铭牌在上面)。

const Probe := preload("res://tests/clip_probe.gd")
const HEAD_TOP := 0.7     # 同 tools/ddz_hat_fit.gd:铭牌 1.92 − 坐直时头枢轴 ≈1.12 − 欢呼蹦起 0.08,留 2 cm
const FLOAT := 0.025      # 帽口最低的一点离下面的头不超过这么远(同 tools/ddz_hat_fit.gd 的 RIM_MAX)
const FLOAT_EXCEPT := {"crocodile:farmer": 0.05}   # 鳄鱼头顶两个眼包把草帽垫高,帽口离扁平的头顶 ≈4.5 cm
const RIM_SAMPLES := 16


func after_each():
	Probe.clear()


static func _edges(mi: MeshInstance3D) -> Array:
	var faces := mi.mesh.get_faces()
	var out := []
	for i in range(0, faces.size(), 3):
		for e in 3:
			out.append([mi.global_transform * faces[i + e], mi.global_transform * faces[i + (e + 1) % 3]])
	return out


static func _hits(a: MeshInstance3D, b: MeshInstance3D) -> bool:
	return Probe.segments_hit(_edges(a), b) > 0 or Probe.segments_hit(_edges(b), a) > 0


func test_every_species_wears_both_hats_without_clipping():
	for s in Species.count():
		var p := Patron.new(s)
		add_child_autofree(p)
		var head_parts := []
		var ears := []
		for node in p.head.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null or not mi.visible or mi.name in ["Tongue", "HatMesh"]:
				continue
			(ears if mi.name == "EarMesh" else head_parts).append(mi)
		for role in [DdzState.ROLE_LANDLORD, DdzState.ROLE_FARMER]:
			var holder := DdzHats.put_on(p, role, false)
			assert_not_null(holder, "%s 戴上 %s" % [Species.IDS[s], role])
			var hat: MeshInstance3D = holder.get_node("HatMesh")
			var label := "%s %s" % [Species.IDS[s], role]
			assert_false(p.head.get_node("Hat/HatMesh").visible, label + ":原来的帽子藏起来")
			for part in head_parts:
				assert_false(_hits(hat, part), label + ":帽子碰到 " + part.name)
			for ear in ears:
				assert_false(_hits(hat, ear), label + ":帽子碰到耳朵")
			# 帽口一圈:往上看不到头(不在头里),往下离头不远(坐在头上)
			var to_head := p.head.global_transform.affine_inverse()
			var r: float = DdzProps.RIM_RADIUS["landlord" if role == DdzState.ROLE_LANDLORD else "farmer"]
			var nearest := INF
			for k in RIM_SAMPLES:
				var a := TAU * k / RIM_SAMPLES
				var rim: Vector3 = hat.global_transform * Vector3(sin(a) * r, 0.0, cos(a) * r)
				for part in head_parts:
					assert_eq(Probe.segments_hit([[rim, rim + Vector3.UP * 0.6]], part), 0, label + ":帽口在头里")
				var down := _distance_down(rim, head_parts)
				nearest = minf(nearest, down)
			assert_lt(nearest, FLOAT_EXCEPT.get("%s:%s" % [Species.IDS[s], role], FLOAT) + 0.001, label + ":帽子飘在头上 %.3f 米" % nearest)
			var top: float = (to_head * hat.global_transform * hat.mesh.get_aabb()).end.y
			assert_lte(top, HEAD_TOP, label + ":帽顶 %.3f" % top)
			DdzHats.take_off(p)
			assert_true(p.head.get_node("Hat/HatMesh").visible, label + ":摘帽后原来的帽子回来")
		await wait_frames(1)


func test_role_hat_metrics_include_the_hat():
	# 探头的软碰撞按戴着的帽子算头的大小(Patron.head_metrics 按头上挂的东西重量)
	var p := Patron.new(0)
	add_child_autofree(p)
	var bare: Dictionary = p.head_metrics().duplicate()
	DdzHats.put_on(p, DdzState.ROLE_FARMER, false)
	var hatted := p.head_metrics()
	assert_ne(hatted, bare, "戴上草帽后重量")
	DdzHats.take_off(p)
	await wait_frames(1)
	assert_eq(p.head_metrics(), bare, "摘帽后回到原来的尺寸")


func _distance_down(from: Vector3, parts: Array) -> float:
	var best := INF
	for part in parts:
		var mi := part as MeshInstance3D
		var inv := mi.global_transform.affine_inverse()
		var hit := Probe.tri_mesh(mi.mesh).intersect_segment(inv * from, inv * (from + Vector3.DOWN * 0.5))
		if not hit.is_empty():
			best = minf(best, from.distance_to(mi.global_transform * Vector3(hit["position"])))
	return best
