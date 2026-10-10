// 墙饰共享材质(DecorAtlas 图集 + SurfaceNoise):模式写在顶点 UV2.x 上,参数在 UV2.y,所以纸面、外景、烟熏镜、
// 地毯、布料、余烬可以合进同一个 surface。COLOR.rgb = sRGB 色调,COLOR.a = 烘焙 AO。
// 0 纸 / 画布:ALBEDO = 图集 × 色调 × AO(夹到 ≤ 0.8),纸纤维 ±4%
// 1 外景:不受光,EMISSION = 图集 × 参数(最亮处——月亮、灯笼——再加一点,够得着辉光)
// 2 烟熏镜:近黑的金属面,烟熏斑驳的粗糙度、四周暗角、离边 4 cm 的金线、自下而上的暖色微光
// 3 动森式毛绒地毯(2026-10-10 重做):UV 是相对毯心的米制坐标,参数是地毯编号;rug_sizes[i] = (半宽, 半长, 包边 / 流苏宽, 款式)。
//   款式 0 圆形主毯(玫瑰色绳纹包边、针脚、鼠尾草绿圈、奶油黄星星圈)、1 条纹长毯(包边 + 两端流苏)、2 门口小椭圆毯(绿包边、小花);
//   图案全部解析绘制、按屏幕导数抗锯齿(近看不糊不起锯齿),主毯随牌桌放大(rug_scale)
// 4 布料:色调 × 织纹,边缘一点绒光
// 5 余烬:炭黑底,细胞边线上滚动的橙红辉光
shader_type spatial;
render_mode cull_disabled;

#include "res://src/world/shaders/vertex_pbr.gdshaderinc"
#include "res://src/world/shaders/surface.gdshaderinc"
// 柔和卡通光照(见 toon_light.gdshaderinc)
#define TOON_RIM 0.12
#define TOON_SHADOW_TINT vec3(0.86, 0.82, 1.0)
#include "res://src/world/shaders/toon_light.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 rug_sizes[3];
uniform float rug_scale = 1.0;   // 主毯(0 号,圆心在原点)随牌桌放大的倍数:顶点 xz 绕原点缩放,图案跟着放大
uniform vec2 mirror_size = vec2(3.08, 1.67);

varying flat int mode;
varying flat float param;
varying vec3 world_pos;

void vertex() {
	mode = int(UV2.x + 0.5);
	param = UV2.y;
	if (mode == 3 && param < 0.5) {
		VERTEX.xz *= rug_scale;
		NORMAL = normalize(vec3(NORMAL.x / rug_scale, NORMAL.y, NORMAL.z / rug_scale));
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// —— 动森式毛绒地毯 ——
// 配色(sRGB,用前转线性):燕麦奶油底、灰玫瑰包边、鼠尾草绿、奶油黄星星。明度贴近蜂蜜色地板、饱和度低,
// 衬着牌桌而不和薄荷毡面、牌抢眼;最深的颜色也带色相
const vec3 RUG_OAT = vec3(0.79, 0.68, 0.55);
const vec3 RUG_OAT_LIGHT = vec3(0.88, 0.80, 0.68);
const vec3 RUG_ROSE = vec3(0.80, 0.57, 0.55);
const vec3 RUG_ROSE_DEEP = vec3(0.68, 0.46, 0.45);
const vec3 RUG_SAGE = vec3(0.62, 0.70, 0.56);
const vec3 RUG_BLUSH = vec3(0.86, 0.67, 0.62);
const vec3 RUG_BUTTER = vec3(0.93, 0.72, 0.42);

float rug_band(float x, float a, float b, float w) {
	// [a, b] 区间的抗锯齿色带,过渡宽度 w 取屏幕导数
	return smoothstep(a - w, a + w, x) - smoothstep(b - w, b + w, x);
}

float rug_fill(float sd, float w) {
	// 有符号距离 sd < 0 的一侧填满,边缘抗锯齿
	return 1.0 - smoothstep(-w, w, sd);
}

float rug_ellipse(vec2 p, vec2 ab) {
	// 椭圆有符号距离的廉价近似(外正内负;圆是精确的)
	float k0 = length(p / ab);
	float k1 = length(p / (ab * ab));
	return k0 * (k0 - 1.0) / max(k1, 1e-5);
}

float rug_star(vec2 p, float r, float rf) {
	// 五角星有符号距离(尖朝 +y)
	const vec2 k1 = vec2(0.809016994, -0.587785252);
	const vec2 k2 = vec2(-0.809016994, -0.587785252);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

float rug_rope(float phase, float w_phase, float across) {
	// 绳纹包边:斜向股线之间一道浅缝(phase 沿边每股 +1,across 是横穿包边的 0..1);股线小于 3 像素时淡出,远处不闪
	float tri = abs(fract(phase + across * 1.3) - 0.5) * 2.0;
	float fade = 1.0 - smoothstep(0.12, 0.35, w_phase);
	return 1.0 - 0.13 * fade * smoothstep(0.55, 0.95, tri);
}

float rug_ring_dash(vec2 p, float r, float d, float d0, float dash_len, float aa) {
	// 沿边一圈虚线针脚,离外沿 d0;段数取整,atan 的接缝处也对得上
	float n = max(floor(TAU * r / dash_len + 0.5), 4.0);
	float phase = atan(p.y, p.x) / TAU * n;
	float w_phase = aa * n / (TAU * max(r, 1e-3));
	return rug_band(fract(phase), 0.18, 0.72, w_phase) * rug_band(d, d0 - 0.006, d0 + 0.006, aa);
}

vec3 rug_round(vec2 p, vec2 ab, float rim, float kind, out float shade, out float h) {
	// 圆 / 椭圆毛绒毯:p 相对毯心;返回 sRGB 颜色,shade 是乘在颜色上的明暗(绳纹、外沿接地暗),h 是凹凸高度(米)
	float r = length(p);
	float d = -rug_ellipse(p, ab);                // 离外沿的距离(向里为正)
	float aa = max(fwidth(d), 1e-5);
	float mean_r = max(r, 1e-3);
	float n_rope = floor(TAU * (ab.x + ab.y) * 0.5 / 0.045 + 0.5);
	float rope_phase = atan(p.y, p.x) / TAU * n_rope;
	float w_rope = (max(fwidth(r), 1e-5) + aa) * n_rope / (TAU * mean_r);   // 股线相位的屏幕导数(不对 atan 求导,接缝处不糊)
	bool main_rug = kind < 0.5;
	vec3 field = main_rug ? RUG_OAT : RUG_BLUSH;
	vec3 col = field;
	// 同心编织纹(动森式编织毯):一圈 3.2 cm,细到 5 像素以下就淡出
	float w_r = max(fwidth(r), 1e-5);
	float ripple = cos(TAU * r / 0.032) * (1.0 - smoothstep(0.0025, 0.006, w_r));   // 早点淡出,中景不起摩尔纹
	shade = 1.0 + 0.025 * ripple;
	h = ripple * 0.0004;
	if (main_rug) {
		// 包边内一道虚线针脚、一圈鼠尾草绿、星星与小圆点轮换的一圈、桌沿外一道细绿线
		col = mix(col, RUG_ROSE_DEEP, 0.8 * rug_ring_dash(p, r, d, rim + 0.035, 0.07, aa));
		col = mix(col, RUG_SAGE, rug_band(d, rim + 0.075, rim + 0.155, aa));
		float ring_r = ab.x - rim - 0.33;
		float n = 26.0;
		float sector = TAU / n;
		float idx = floor(atan(p.y, p.x) / sector + 0.5);
		float ac = idx * sector;
		vec2 radial = vec2(cos(ac), sin(ac));
		vec2 q = p - radial * ring_r;
		vec2 local = vec2(dot(q, vec2(-radial.y, radial.x)), dot(q, radial));
		float wq = max(fwidth(p.x) + fwidth(p.y), 1e-5) * 0.5;
		if (mod(abs(idx), 2.0) < 0.5) {
			col = mix(col, RUG_BUTTER, rug_fill(rug_star(local, 0.074, 0.55) - 0.013, wq));
		} else {
			col = mix(col, RUG_ROSE, rug_fill(length(q) - 0.022, wq));
		}
		col = mix(col, RUG_SAGE, rug_band(r, 1.05, 1.068, w_r));
	} else {
		// 门口小毯:淡玫瑰底、奶油虚线针脚一圈,正中一朵奶油黄小花(五片圆瓣 + 奶油花心)
		col = mix(col, RUG_OAT_LIGHT, 0.9 * rug_ring_dash(p, r, d, rim + 0.03, 0.05, aa));
		float wq = max(fwidth(p.x) + fwidth(p.y), 1e-5) * 0.5;
		float a = atan(p.y, p.x);
		float petal_a = (floor(a / (TAU / 5.0) + 0.5)) * TAU / 5.0;
		vec2 pc = vec2(cos(petal_a), sin(petal_a)) * 0.07;
		col = mix(col, RUG_BUTTER, rug_fill(length(p - pc) - 0.042, wq));
		col = mix(col, RUG_OAT_LIGHT, rug_fill(r - 0.032, wq));
	}
	// 毛绒包边:绳纹(主毯玫瑰色、门口小毯鼠尾草绿);外沿 1/3 压暗,像压在地板上
	float rim_mask = 1.0 - smoothstep(rim - aa, rim + aa, d);
	col = mix(col, main_rug ? RUG_ROSE : RUG_SAGE, rim_mask);
	shade = mix(shade, rug_rope(rope_phase, w_rope, d / rim), rim_mask);
	shade *= mix(0.8, 1.0, smoothstep(0.0, rim * 0.4, d));
	h *= 1.0 - rim_mask;
	return col;
}

vec3 rug_runner(vec2 p, vec2 ab, float fringe, out float shade, out float h) {
	// 圆角条纹长毯(纵向 p.y):玫瑰色包边,横向条纹按「绿宽条—玫瑰细线—奶油黄细条」对称排,两端流苏
	shade = 1.0;
	h = 0.0;
	float wy = max(fwidth(p.y), 1e-5);
	if (abs(p.y) > ab.y) {
		// 流苏:奶油色细绳,绳间暗缝,末梢变淡
		float wx = max(fwidth(p.x), 1e-5);
		float strand = abs(fract(p.x / 0.02) - 0.5);
		float gap = smoothstep(0.32, 0.48, strand) * (1.0 - smoothstep(0.08, 0.2, wx / 0.02));
		shade = 1.0 - 0.45 * gap;
		shade *= 1.0 - smoothstep(fringe * 0.6, fringe, abs(p.y) - ab.y) * 0.35;
		return RUG_OAT_LIGHT;
	}
	float corner = 0.05;
	vec2 qb = abs(p) - ab + corner;
	float d = -(length(max(qb, 0.0)) + min(max(qb.x, qb.y), 0.0) - corner);
	float aa = max(fwidth(d), 1e-5);
	float u = abs(fract(p.y / 0.44) - 0.5) * 0.44;   // 离条纹中心线的距离(0..0.22,连续)
	vec3 col = RUG_OAT;
	col = mix(col, RUG_SAGE, rug_band(u, -1.0, 0.05, wy));
	col = mix(col, RUG_ROSE, rug_band(u, 0.085, 0.1, wy));
	col = mix(col, RUG_BUTTER, rug_band(u, 0.19, 1.0, wy));
	// 顺长方向的细织纹
	float wx = max(fwidth(p.x), 1e-5);
	float weave = cos(TAU * p.x / 0.024) * (1.0 - smoothstep(0.003, 0.009, wx));
	shade = 1.0 + 0.03 * weave;
	h = weave * 0.0004;
	// 包边:玫瑰色,带一点斜绳纹;最外 1.5 cm 压暗
	float edge = 0.04;
	float bind = 1.0 - smoothstep(edge - aa, edge + aa, d);
	col = mix(col, RUG_ROSE, bind);
	float bw = (wx + wy) / 0.03;
	shade = mix(shade, rug_rope((p.x + p.y) / 0.03, bw, 0.0), bind);
	shade *= mix(0.86, 1.0, smoothstep(0.0, 0.015, d));
	h *= 1.0 - bind;
	return col;
}

void fragment() {
	vec3 tint = vp_srgb_to_linear(COLOR.rgb);
	float ao = COLOR.a;
	vec3 albedo = vec3(0.5);
	float rough = 0.88;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emission = vec3(0.0);
	if (mode == 0) {
		vec3 tex = texture(atlas, UV).rgb;
		float fibre = n_hi(world_pos.xy * 160.0 + world_pos.zz * 160.0) - 0.5;
		albedo = min(tex * tint * ao * (1.0 + fibre * 0.08), vec3(0.8));
	} else if (mode == 1) {
		vec3 tex = texture(atlas, UV).rgb;
		albedo = vec3(0.0);
		spec = 0.0;
		rough = 1.0;
		float boost = 1.0 + 5.0 * smoothstep(0.55, 0.9, luma(tex));
		emission = tex * tint * param * boost;
	} else if (mode == 2) {
		// UV:镜面局部米制坐标(原点在一角)
		vec2 d = min(UV, mirror_size - UV);
		float edge = min(d.x, d.y);
		float smoke = n_lo(UV * 3.0 + 11.0) * 0.7 + n_lo(UV * 9.0) * 0.3;
		float vignette = smoothstep(0.0, 0.45, edge);
		// 卡通:深青玻璃色的镜面(不是近黑的金属),缎面
		albedo = vec3(0.07, 0.12, 0.13);
		metal = 0.4;
		rough = 0.3 + 0.2 * smoke + (1.0 - vignette) * 0.15;
		float gold = 1.0 - smoothstep(0.0075, 0.0075 + max(max(fwidth(UV.x), fwidth(UV.y)), 0.001), abs(edge - 0.04 - 0.0075));
		albedo = mix(albedo * (0.75 + 0.25 * vignette), vec3(0.62, 0.45, 0.2), gold);
		rough = mix(rough, 0.45, gold);
		metal = mix(metal, 0.65, gold);
		float warm = (1.0 - smoothstep(0.0, mirror_size.y, UV.y)) * vignette * (0.6 + 0.4 * smoke);
		// 假反光:几道斜向的柔和亮带,读得出是镜面
		float streak = smoothstep(0.35, 0.0, abs(fract((UV.x + UV.y * 0.7) / 1.3) - 0.5)) * 0.5 + 0.5;
		emission = vec3(0.10, 0.07, 0.04) * warm * 0.7 * streak * (1.0 - gold);
	} else if (mode == 3) {
		int id = int(param + 0.5);
		vec4 rs = rug_sizes[id];
		float shade;
		float h;
		vec3 col = rs.w > 0.5 && rs.w < 1.5 ? rug_runner(UV, rs.xy, rs.z, shade, h) : rug_round(UV, rs.xy, rs.z, rs.w, shade, h);
		// 毛绒:两层低幅纤维噪声(细绒 + 大块深浅),卡通降噪只留一点
		float fibre = n_hi(world_pos.xz * 140.0) - 0.5;
		float mottle = n_lo(world_pos.xz * 1.6) - 0.5;
		albedo = col * shade * (1.0 + fibre * 0.07 + mottle * 0.06);
		albedo = vp_srgb_to_linear(clamp(albedo, vec3(0.06), vec3(0.85)));
		NORMAL = bump_normal(NORMAL, VERTEX, h, 1.0);
		rough = 0.95;
		spec = 0.3;
	} else if (mode == 4) {
		float weave = n_hi(vec2(world_pos.x + world_pos.z, world_pos.y) * 60.0);
		albedo = tint * ao * (0.94 + 0.12 * weave);
		rough = 0.9;
		float sheen = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0) * 0.35;
		albedo += tint * sheen;
	} else if (mode == 5) {
		vec2 p = world_pos.xz * 9.0 + vec2(TIME * 0.05, -TIME * 0.03);
		float cell = n_cell(p);
		float pulse = 0.7 + 0.3 * n_lo(world_pos.xz * 4.0 + vec2(TIME * 0.35, TIME * 0.2));
		float glow = pow(1.0 - cell, 6.0) * pulse;
		albedo = vec3(0.03, 0.025, 0.02) * ao;
		rough = 0.95;
		emission = vec3(1.0, 0.32, 0.06) * glow * 3.0 * param;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emission;
}
