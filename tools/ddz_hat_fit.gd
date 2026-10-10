extends SceneTree
# 斗地主身份帽的逐物种贴合(穿模修复 2026-10-10):按真实网格(TriangleMesh)找每个物种戴瓜皮帽 / 草帽的大小与高度,
# 打印成 DdzHats.FIT 的表。运行时不读网格,只查这张表;tests/test_ddz_hats.gd 按同样的判定守住结果。
# 用法:godot --headless --path . -s tools/ddz_hat_fit.gd [-- --verbose]
# 贴合方法(帽子按 DdzHats.TILT 歪戴,帽口中心在头心正上方、略往后 Z_BACK):
# - 帽口半径的目标 = 脸的半宽 × TARGET(瓜皮帽像一顶小帽盖住头顶,草帽的帽冠稍小、帽檐比头宽);
# - 从目标大小往下缩(每档 4%,最小 MIN_K):每档先从高处往下二分找到帽子刚碰到头(颅骨、眼、眉)的高度,再抬 GAP 留缝;
#   耳朵不碰帽子就收下;碰到时,耳朵穿过帽檐(草帽)记成帽檐上的耳洞,穿过帽冠 / 瓜皮帽就再缩一档;
# - 帽顶不超过 HEAD_TOP(Head 局部 0.66,铭牌在上面)。

const Probe := preload("res://tests/clip_probe.gd")
const TARGET := {"landlord": 0.72, "farmer": 0.6}
const MIN_K := 0.5
const Z_TRIES := [DdzHats.Z_BACK, 0.05, 0.09]   # 帽口中心往后挪的几档(Head 局部)
const DEPTHS := [1.0, 1.2, 1.4, 1.6]   # 帽子竖向加深的几档
const RIM_OK := 0.02                 # 帽口离头这么近就不再往后挪着找
const RIM_MAX := 0.025               # 帽口离头超过这么多(悬着)就再缩一档
const GAP := 0.004
const HEAD_TOP := 0.7   # 帽顶上限(Head 局部):铭牌 1.92 − 坐直时头枢轴 ≈1.12 − 欢呼蹦起 0.08 = 0.72,留 2 cm

var opts := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var lines := []
	for s in Species.count():
		var p := Patron.new(s)
		root.add_child(p)
		var row := []
		for role in ["landlord", "farmer"]:
			row.append(DdzHats.fit_entry(_fit(p, role)))
		lines.append("\t\"%s\": {\"landlord\": %s, \"farmer\": %s}," % [Species.IDS[s], row[0], row[1]])
		p.free()
	print("const FIT := {")
	for l in lines:
		print(l)
	print("}")
	quit()


func _fit(p: Patron, role: String) -> Dictionary:
	var head_parts := []
	var ears := []
	for node in p.head.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible or mi.name in ["Tongue", "HatMesh"]:
			continue
		if mi.name == "EarMesh":
			ears.append(mi)
		else:
			head_parts.append(mi)
	var face: AABB = (p.head.get_node("HeadMesh") as MeshInstance3D).get_aabb()
	var half := maxf(-face.position.x, face.end.x)
	var base_r: float = DdzProps.RIM_RADIUS[role]
	var holder := MeshInstance3D.new()
	p.head.add_child(holder)
	var best := {}
	var fallback := {}
	var k := 1.0
	while k >= MIN_K - 0.001:
		var scale: float = half * TARGET[role] * k / base_r
		var entry := _try(p, holder, role, scale, head_parts, ears, face)
		if not entry.is_empty():
			if fallback.is_empty():
				fallback = entry   # 最大的一档合格的(鳄鱼头顶的眼包把帽子垫高,哪一档帽口都悬着:戴大的)
			if entry["gap"] <= RIM_MAX:
				best = entry
				break
		k -= 0.04
	if best.is_empty():
		best = fallback   # 哪一档帽口都悬得比 RIM_MAX 高:取最大的一档
	holder.free()
	if best.is_empty():
		push_warning("%s %s 没找到合适的帽子" % [Species.IDS[p.species_index], role])
	return best


func _try(p: Patron, holder: MeshInstance3D, role: String, scale: float, head_parts: Array, ears: Array, face: AABB) -> Dictionary:
	# 一个大小:帽口中心先放在头顶正上方,不行再往后挪(坐在耳朵后面);帽子再按几档加深(竖向放大),
	# 让帽口一圈往下贴着头(圆帽顶比大头的弧度平,只按头顶接触时帽口会悬空几厘米)。合格的里面取帽口离头最近的
	var best := {}
	var best_gap := INF
	for z in Z_TRIES:
		for m in DEPTHS:
			var entry := _place(p, holder, role, scale, z, m, head_parts, ears, face)
			if entry.is_empty():
				continue
			var gap := rim_gap(holder, role, head_parts)
			if gap < best_gap - 0.002:
				best = entry
				best_gap = gap
				best["gap"] = gap
		if not best.is_empty() and best_gap <= RIM_OK:
			break
	if not best.is_empty() and opts.has("verbose"):
		print("  %s %s s=%.3f z=%.2f m=%.2f 帽口离头 %.3f" % [Species.IDS[p.species_index], role, scale, best["z"], best["m"], best_gap])
	return best


func _place(p: Patron, holder: MeshInstance3D, role: String, scale: float, z: float, m: float, head_parts: Array, ears: Array,
		face: AABB) -> Dictionary:
	var entry := {"s": scale, "y": 0.0, "z": z, "m": m, "holes": []}
	holder.mesh = DdzProps.hat(role, [])
	var y := _seat(p, holder, entry, head_parts, face) + GAP
	# 留缝之后再确认一遍(头顶不是处处单调的弧面:鼓包、卷毛),碰到就每 2 mm 往上抬
	var lifts := 0
	while _touching(holder, entry, y, head_parts) and lifts < 15:
		y += 0.002
		lifts += 1
	entry["y"] = y
	holder.transform = DdzHats.head_transform(entry)
	var holes := []
	var ok := true
	var why := ""
	for ear in ears:
		if _hits(holder, ear):
			var hole = _hole_for(holder, ear, role)
			if hole == null:
				ok = false
				why = "耳朵穿过帽冠"
				break
			holes.append(hole)
	if ok and not holes.is_empty():
		entry["holes"] = holes
		holder.mesh = DdzProps.hat(role, holes)
		for ear in ears:
			if _hits(holder, ear):
				ok = false
				why = "开洞后耳朵仍碰到帽子 %s" % [holes]
		for part in head_parts:
			if _hits(holder, part):
				ok = false
				why = "开洞后碰到头"
	var top: float = (holder.transform * holder.mesh.get_aabb()).end.y
	if ok and top <= HEAD_TOP:
		return entry
	if opts.has("verbose"):
		print("    %s %s s=%.3f z=%.2f m=%.2f 不行:%s 帽顶 %.3f" % [Species.IDS[p.species_index], role, scale, z, m, why, top])
	return {}


static func rim_gap(holder: MeshInstance3D, role: String, parts: Array) -> float:
	# 帽口一圈往下到头的最近距离(tests/test_ddz_hats.gd 同一口径)
	var r: float = DdzProps.RIM_RADIUS[role]
	var best := INF
	for k in 16:
		var a := TAU * k / 16.0
		var rim := holder.global_transform * Vector3(sin(a) * r, 0.0, cos(a) * r)
		for part in parts:
			var mi := part as MeshInstance3D
			var inv := mi.global_transform.affine_inverse()
			var hit := Probe.tri_mesh(mi.mesh).intersect_segment(inv * rim, inv * (rim + Vector3.DOWN * 0.5))
			if not hit.is_empty():
				best = minf(best, rim.distance_to(mi.global_transform * Vector3(hit["position"])))
	return best


func _seat(p: Patron, holder: MeshInstance3D, entry: Dictionary, parts: Array, face: AABB) -> float:
	# 从头顶上方每 1 cm 往下放,第一次碰到头之后在最后一段里二分(整顶埋进头里时表面不相交,不能直接二分)
	var hi := face.end.y + 0.3
	var lo := hi
	while lo > PatronParts.HEAD_CENTER.y:
		lo -= 0.01
		if _touching(holder, entry, lo, parts):
			break
		hi = lo
	for i in 12:
		var mid := (hi + lo) * 0.5
		if _touching(holder, entry, mid, parts):
			lo = mid
		else:
			hi = mid
	return hi


func _touching(holder: MeshInstance3D, entry: Dictionary, y: float, parts: Array) -> bool:
	entry["y"] = y
	holder.transform = DdzHats.head_transform(entry)
	for part in parts:
		if _hits(holder, part):
			return true
	return false


static func _edges(mi: MeshInstance3D) -> Array:
	var faces := mi.mesh.get_faces()
	var out := []
	for i in range(0, faces.size(), 3):
		out.append([mi.global_transform * faces[i], mi.global_transform * faces[i + 1]])
		out.append([mi.global_transform * faces[i + 1], mi.global_transform * faces[i + 2]])
		out.append([mi.global_transform * faces[i + 2], mi.global_transform * faces[i]])
	return out


static func _hits(a: MeshInstance3D, b: MeshInstance3D) -> bool:
	# 两个网格的表面相交:a 的三角形边穿过 b,或 b 的边穿过 a
	if not (a.global_transform * a.mesh.get_aabb()).intersects(b.global_transform * b.mesh.get_aabb()):
		return false
	return Probe.segments_hit(_edges(a), b) > 0 or Probe.segments_hit(_edges(b), a) > 0


static func _hole_for(holder: MeshInstance3D, ear: MeshInstance3D, role: String):
	# 耳朵穿过帽檐的地方(帽子局部,建模单位):耳朵网格的三角形边与帽檐上下表面的交点,取包围圆;只给草帽的帽檐开洞
	if role != "farmer":
		return null
	var to_hat := holder.global_transform.affine_inverse() * ear.global_transform
	var faces := ear.mesh.get_faces()
	var pts := []
	for i in range(0, faces.size(), 3):
		for e in 3:
			var a: Vector3 = to_hat * faces[i + e]
			var b: Vector3 = to_hat * faces[i + (e + 1) % 3]
			for top in [true, false]:
				for t in 9:
					# 沿边取点,落在帽檐上下表面之间(按半径查表面高度)的都算穿过
					var q := a.lerp(b, t / 8.0)
					var r := Vector2(q.x, q.z).length()
					if r < DdzProps.STRAW_BRIM_R + 0.01 and q.y <= DdzProps._brim_y(r, true) + 0.004 and q.y >= DdzProps._brim_y(r, false) - 0.004:
						if r < DdzProps.STRAW_CROWN_R + 0.006:
							return null   # 耳朵穿的是帽冠:这一档不行
						pts.append(Vector2(q.x, q.z))
	if pts.is_empty():
		return null
	var c := Vector2.ZERO
	for q in pts:
		c += q
	c /= pts.size()
	var rad := 0.0
	for q in pts:
		rad = maxf(rad, c.distance_to(q))
	return Vector3(c.x, c.y, rad + DdzProps.HOLE_PAD)
