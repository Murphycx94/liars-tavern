class_name DdzHats
# 斗地主的身份帽(定地主时戴上,新的一手摘掉):地主戴小瓜皮帽,农民戴草帽(网格见 DdzProps,所有人共用)。
# 帽子挂在酒客自己帽子的枢轴(Head/Hat)下面:跳舞时的抛帽、点头、晃脑都带着它;酒客原来的帽子网格(HatMesh)先藏起来,
# 摘帽时放回。穿模修复(2026-10-10):原来按主颅骨椭球摆,大头的实际表面比主颅骨鼓得多,帽子整个陷进头里、耳朵从帽子里戳出来。
# 现在按物种查 FIT(tools/ddz_hat_fit.gd 按真实网格量出来的大小与高度):帽子坐在头顶上、留 4 mm 缝,高耳朵的物种
# 瓜皮帽缩到两只耳朵中间,草帽在帽檐上给耳朵开洞(DdzProps.straw_hat(holes));tests/test_ddz_hats.gd 守住。
# 挂在头下面的东西,第一人称藏头(Patron.set_head_hidden)时一并只投影不渲染(戴帽时头已藏着也会被 node_added 接住)。


# 贴合表:tools/ddz_hat_fit.gd 生成(帽子 / 物种外观改了就重跑,再跑 tests/test_ddz_hats.gd)
const FIT := {
	"fox": {"landlord": {"s": 2.3305, "m": 1.00, "y": 0.4243, "z": 0.090, "holes": []}, "farmer": {"s": 2.4113, "m": 1.00, "y": 0.4271, "z": 0.090, "holes": [Vector3(-0.1229, -0.0441, 0.0370), Vector3(0.1292, -0.0413, 0.0328)]}},
	"bear": {"landlord": {"s": 2.3474, "m": 1.00, "y": 0.4255, "z": 0.090, "holes": []}, "farmer": {"s": 2.6450, "m": 1.00, "y": 0.4211, "z": 0.090, "holes": []}},
	"pig": {"landlord": {"s": 2.2454, "m": 1.00, "y": 0.4377, "z": 0.090, "holes": []}, "farmer": {"s": 2.5301, "m": 1.00, "y": 0.4308, "z": 0.090, "holes": [Vector3(-0.1015, -0.0825, 0.0390)]}},
	"cat": {"landlord": {"s": 1.6257, "m": 1.00, "y": 0.4248, "z": 0.090, "holes": []}, "farmer": {"s": 1.8017, "m": 1.40, "y": 0.4275, "z": 0.090, "holes": [Vector3(-0.1074, -0.0609, 0.0523), Vector3(0.1091, -0.0569, 0.0514)]}},
	"turtle": {"landlord": {"s": 1.9907, "m": 1.00, "y": 0.4219, "z": 0.010, "holes": []}, "farmer": {"s": 2.3498, "m": 1.20, "y": 0.4169, "z": 0.010, "holes": []}},
	"alpaca": {"landlord": {"s": 1.3354, "m": 1.00, "y": 0.5566, "z": 0.090, "holes": []}, "farmer": {"s": 1.4799, "m": 1.00, "y": 0.5581, "z": 0.010, "holes": [Vector3(-0.1373, -0.0166, 0.0403), Vector3(0.1346, -0.0069, 0.0358)]}},
	"monkey": {"landlord": {"s": 2.3907, "m": 1.00, "y": 0.4088, "z": 0.050, "holes": []}, "farmer": {"s": 2.3705, "m": 1.00, "y": 0.4009, "z": 0.010, "holes": []}},
	"crocodile": {"landlord": {"s": 2.2107, "m": 1.00, "y": 0.4303, "z": 0.050, "holes": []}, "farmer": {"s": 2.3826, "m": 1.00, "y": 0.4432, "z": 0.010, "holes": []}},
}

const NODE := "DdzRoleHat"
const ROLE_META := &"ddz_role"
const TILT := Vector3(-6, 0, 5)  # 歪戴一点(度),Q 版更俏皮
const Z_BACK := 0.01             # 帽口中心比头心略往后(Head 局部)
const POP_TIME := 0.42


static func put_on(patron: Patron, role: String, pop := true) -> Node3D:
	# role:DdzState.ROLE_LANDLORD / ROLE_FARMER;其他值等于摘帽。返回帽子节点(没有帽子枢轴时为空)
	take_off(patron)
	if role != DdzState.ROLE_LANDLORD and role != DdzState.ROLE_FARMER:
		return null
	var pivot := _pivot(patron)
	if pivot == null:
		return null
	var own := pivot.get_node_or_null("HatMesh")
	if own is Node3D:
		own.visible = false
	var holder := Node3D.new()
	holder.name = NODE
	holder.set_meta(ROLE_META, role)
	var entry := fit_for(patron.species_index, role)
	var mesh := DdzProps.landlord_hat() if role == DdzState.ROLE_LANDLORD else DdzProps.straw_hat(entry.get("holes", []))
	var inst := MeshKit.add(holder, mesh, null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_ON)
	inst.name = "HatMesh"
	pivot.add_child(holder)
	var rest := rest_transform(patron, pivot)
	holder.transform = rest
	if pop:
		# 「啵」地一下:从小弹到比原来大一点再落回去
		var basis := rest.basis
		holder.transform = Transform3D(basis.scaled(Vector3.ONE * 0.05), rest.origin + basis.y.normalized() * 0.08)
		var tween := holder.create_tween()
		tween.tween_method(func(t: float) -> void:
			var k := 1.0 + 0.32 * sin(t * PI) * (1.0 - t)
			var lift := 0.08 * (1.0 - t) * (1.0 - t)
			holder.transform = Transform3D(basis.scaled(Vector3.ONE * maxf(t * k, 0.05)), rest.origin + basis.y.normalized() * lift),
			0.0, 1.0, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return holder


static func take_off(patron: Patron) -> void:
	var pivot := _pivot(patron)
	if pivot == null:
		return
	var old := pivot.get_node_or_null(NODE)
	if old != null:
		pivot.remove_child(old)
		old.queue_free()
	var own := pivot.get_node_or_null("HatMesh")
	if own is Node3D:
		own.visible = true


static func role_of(patron: Patron) -> String:
	var pivot := _pivot(patron)
	var hat: Node = pivot.get_node_or_null(NODE) if pivot != null else null
	return str(hat.get_meta(ROLE_META, "")) if hat != null else ""


static func hat_node(patron: Patron) -> Node3D:
	var pivot := _pivot(patron)
	return pivot.get_node_or_null(NODE) if pivot != null else null


static func rest_transform(patron: Patron, pivot: Node3D) -> Transform3D:
	# 帽子枢轴局部:按物种贴合表(FIT)摆在 Head 局部,再抵消枢轴自己的位置与歪戴角度
	var role := str(pivot.get_node(NODE).get_meta(ROLE_META, DdzState.ROLE_FARMER)) if pivot.has_node(NODE) else DdzState.ROLE_FARMER
	return pivot.transform.affine_inverse() * head_transform(fit_for(patron.species_index, role))


static func fit_for(species_index: int, role: String) -> Dictionary:
	# 物种 × 身份的贴合:{"s": 缩放, "m": 竖向加深, "y": 帽口中心高度, "z": 前后(Head 局部), "holes": 草帽耳洞};表里没有时按保守值
	var id: String = Species.IDS[posmod(species_index, Species.count())]
	var key := "landlord" if role == DdzState.ROLE_LANDLORD else "farmer"
	return FIT.get(id, {}).get(key, {"s": 2.0, "y": 0.45, "holes": []})


static func head_transform(entry: Dictionary) -> Transform3D:
	# 帽子在 Head 局部的变换:帽口中心 (0, y, z)(z 缺省 Z_BACK;高耳朵的物种往后挪,坐在耳朵后面),歪戴 TILT,横向缩放 s、竖向 s × m
	var s: float = entry.get("s", 2.0)
	var depth: float = entry.get("m", 1.0)   # 竖向加深:圆帽顶比大头平,加深后帽口往下贴着头
	return Transform3D(Basis.from_euler(TILT * PI / 180.0) * Basis.from_scale(Vector3(s, s * depth, s)),
		Vector3(0, entry.get("y", 0.45), entry.get("z", Z_BACK)))


static func fit_entry(entry: Dictionary) -> String:
	# tools/ddz_hat_fit.gd 打印 FIT 表用
	var holes := []
	for h in entry.get("holes", []):
		holes.append("Vector3(%.4f, %.4f, %.4f)" % [h.x, h.y, h.z])
	return "{\"s\": %.4f, \"m\": %.2f, \"y\": %.4f, \"z\": %.3f, \"holes\": [%s]}" % [entry.get("s", 0.0), entry.get("m", 1.0),
		entry.get("y", 0.0), entry.get("z", Z_BACK), ", ".join(holes)]


static func _pivot(patron: Patron) -> Node3D:
	if patron == null or not is_instance_valid(patron) or patron.head == null:
		return null
	return patron.head.get_node_or_null("Hat")
