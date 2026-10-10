// 牌桌桌布:薄荷青绒面(卡通降噪:一层很淡的大尺度绒面噪声)+ 细密平纹织纹 + 柔和暗角 + 奶黄丝线刺绣圆环 + 绒面逆光光泽。
shader_type spatial;

#include "res://src/world/shaders/noise.gdshaderinc"
// 柔和卡通光照(见 toon_light.gdshaderinc)
#define TOON_RIM 0.3
#define TOON_SHADOW_TINT vec3(0.86, 0.9, 1.0)
#include "res://src/world/shaders/toon_light.gdshaderinc"

uniform vec3 felt_color : source_color = vec3(0.08, 0.31, 0.30);
uniform vec3 felt_edge : source_color = vec3(0.05, 0.22, 0.20);
uniform vec3 thread_color : source_color = vec3(0.92, 0.74, 0.40);
uniform float radius = 0.8;
uniform float inner_ring = 0.28;
uniform float outer_ring = 0.70;
uniform float weave_period = 0.003;   // 织纹一格(米)
uniform float weave_depth = 0.1;      // 织纹明暗幅度

varying vec3 obj_pos;

float ring_line(float r, float at, float width) {
	return 1.0 - smoothstep(width * 0.5, width, abs(r - at));
}

void fragment() {
	vec2 p = obj_pos.xz;
	float r = length(p);
	// 两层单倍频值噪声代替原来逐像素的 fbm:更省,也更干净
	float fuzz = value_noise(p * 90.0);
	float wear = value_noise(p * 5.0);
	// 柔和暗角(2026-10-10):从桌心就开始缓缓变暗、到毡边最深,桌心再提亮一点,像灯下的一块软垫
	float edge = smoothstep(radius * 0.18, radius * 1.02, r);
	vec3 col = mix(felt_color, felt_edge, edge * edge * (3.0 - 2.0 * edge));
	col *= 1.0 + 0.07 * (1.0 - smoothstep(0.0, radius * 0.55, r));
	col *= 0.95 + fuzz * 0.1;
	col *= 0.96 + wear * 0.08;
	// 细密的平纹织纹:经纬线每格交替压上压下(周期 weave_period);像素盖过半格时淡出,远处不出摩尔纹
	vec2 q = p / weave_period;
	float fw = max(fwidth(q.x), fwidth(q.y));
	vec2 f = fract(q) - 0.5;
	float over = mod(floor(q.x) + floor(q.y), 2.0);
	float thread_x = 1.0 - 4.0 * f.y * f.y;     // 沿 x 走的线:横截面中间鼓
	float thread_y = 1.0 - 4.0 * f.x * f.x;
	float weave = mix(thread_x, thread_y, over);
	col *= 1.0 + (weave - 0.5) * weave_depth * (1.0 - smoothstep(0.3, 0.7, fw));
	// 刺绣:内圈两股虚线针脚、外圈一道实线、再外一圈菱形针脚。金线是哑光丝线,不再亮得像霓虹灯
	float angle = atan(p.y, p.x);
	float dash = step(0.35, fract(angle * 96.0 / 6.2831853));
	float thread = max(ring_line(r, inner_ring - 0.0045, 0.003), ring_line(r, inner_ring + 0.0045, 0.003)) * dash;
	thread = max(thread, ring_line(r, outer_ring, 0.007));
	float diamond = abs(r - (outer_ring + 0.022)) + abs(fract(angle * 48.0 / 6.2831853) - 0.5) * 0.02;
	thread = max(thread, 1.0 - smoothstep(0.0, 0.0035, diamond));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(col + felt_color * rim * 0.5, thread_color, thread);
	ROUGHNESS = mix(0.95, 0.7, thread);
	METALLIC = 0.0;
	SPECULAR = mix(0.15, 0.3, thread);
}

void vertex() {
	obj_pos = VERTEX;
}
