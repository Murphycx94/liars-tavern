// 炸弹猫道具效果里会淡出的薄片件(冲击波圈、速度线、脚印、印章印、聚光柱、气泡底、闪光十字):
// 不打光、双面、透明混合、不投影;颜色 = 顶点色(sRGB,MeshForge 写的)× 实例 tint,透明度 = 实例 alpha。
// 所有这类件共用两份材质(平放 / 公告板),淡出、变色全走实例参数,不 duplicate 材质。
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform bool billboard = false;   // 公告板:始终正对镜头(保留节点缩放)
instance uniform float alpha = 1.0;
instance uniform vec4 tint : source_color = vec4(1.0);

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	if (billboard) {
		mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		bb = bb * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * bb;
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	ALBEDO = to_linear(COLOR.rgb * tint.rgb);
	ALPHA = clamp(alpha * tint.a, 0.0, 1.0);
}
