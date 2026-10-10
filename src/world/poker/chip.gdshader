// 筹码:底色取 MultiMesh 的逐实例颜色(按 sRGB 填写,这里换成线性);圆角车削网格,侧面一圈镶边色块、
// 顶面边缘接着色块、再加一道细环——远看也认得出是筹码而不是硬币。深色筹码配白镶边,浅色(象牙白、金)配深色镶边。
shader_type spatial;

// 柔和卡通光照(见 toon_light.gdshaderinc,取值同 prop):筹码与其他道具一样是哑光软胶
#define TOON_RIM 0.18
#define TOON_SHADOW_TINT vec3(0.86, 0.82, 1.0)
#include "res://src/world/shaders/toon_light.gdshaderinc"

uniform float radius = 0.024;
uniform float spots = 8.0;
uniform float spot_width = 0.38;        // 每个镶边色块占一个周期的比例
uniform float ring_at = 0.68;           // 顶面细环的位置(占半径的比例)
uniform float ring_width = 0.06;
uniform float rim_start = 0.86;         // 顶面从这里往外接上侧面的色块
uniform float light_luma = 0.45;        // 底色亮于此用深色镶边
uniform vec3 inlay_light : source_color = vec3(0.95, 0.92, 0.84);   // 奶油白镶边
uniform vec3 inlay_dark : source_color = vec3(0.30, 0.22, 0.20);    // 深可可镶边(不是近黑)

varying vec3 obj_pos;
varying vec3 obj_normal;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

void fragment() {
	vec3 base = srgb_to_linear(COLOR.rgb);
	float luma = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	vec3 inlay = mix(srgb_to_linear(inlay_light), srgb_to_linear(inlay_dark), step(light_luma, luma));
	float on_side = 1.0 - step(0.5, abs(obj_normal.y));
	float turn = atan(obj_pos.z, obj_pos.x) / 6.2831853 * spots;
	float spot = step(1.0 - spot_width, fract(turn));
	float r = length(obj_pos.xz) / radius;
	float on_rim = (1.0 - on_side) * step(rim_start, r);
	float ring = (1.0 - on_side) * (1.0 - smoothstep(ring_width * 0.5, ring_width, abs(r - ring_at)));
	float mask = max(max(on_side, on_rim) * spot, ring);
	ALBEDO = mix(base, inlay, mask);
	ROUGHNESS = 0.55;
	SPECULAR = 0.35;
}
