// 卡牌 v2:所有骗子酒馆的牌共用一份网格(圆角薄片,带厚度)与这一份材质,牌型差异全在实例参数里。
// 牌面与牌背在 faces 数组纹理里(层序见 CardFaces.LAYERS,0 = 牌背);烫金遮罩在 foil 里,驱动金属度与高光;
// 德州牌背面取 back_texture(德州自己的牌背)。侧边是奶油纸芯色(哑光,不再是烫金),正反面贴着牌边有一圈 1 mm 的软压暗:牌看起来有厚度,不像一张平纸。德州牌(52 张)每张一份材质:single_face 时正面取 card_texture,背面取 back_texture。
// 实例参数:face(正面层)、both_faces(桌心立牌两面都显示正面)、glow / glow_color(高亮光晕)。
shader_type spatial;
render_mode diffuse_burley, cull_back;

uniform sampler2DArray faces : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2DArray foil : hint_default_black, filter_linear_mipmap;
uniform sampler2D card_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D back_texture : source_color, filter_linear_mipmap_anisotropic;
uniform bool single_face = false;
uniform float self_illum = 0.03;
// 牌面纸色压暗、哑光:平放在吊灯光圈下时不至于过曝成一片白,点数仍清楚
uniform float albedo_scale = 0.7;
uniform float ink_contrast = 1.35;   // >1 让油墨更深、纸面基本不变
uniform vec3 edge_color : source_color = vec3(0.86, 0.7, 0.5);   // 侧边:暖焦糖色纸芯
uniform vec3 card_size = vec3(0.12, 0.1733, 0.0146667);          // 宽、高、圆角(米,= Card3D 的常量)
uniform float rim_width = 0.0011;                                 // 牌边软压暗的宽度(米)
uniform float rim_shade = 0.82;                                   // 牌边最暗处的亮度倍数
instance uniform int face = 0;
instance uniform float both_faces = 0.0;
instance uniform vec4 glow_color : source_color = vec4(1.0, 0.82, 0.4, 1.0);
instance uniform float glow = 0.0;

varying float side;   // +1 正面、−1 背面、0 侧边(按网格原法线)

void vertex() {
	side = NORMAL.y;
}

void fragment() {
	vec3 tex;
	float gold;
	bool front = side > 0.5 || (side < -0.5 && both_faces > 0.5);
	bool edge_side = side > -0.5 && side < 0.5;
	if (edge_side) {
		tex = edge_color;
		gold = 0.0;
	} else if (front) {
		if (single_face) {
			tex = texture(card_texture, UV).rgb;
			gold = 0.0;
		} else {
			tex = texture(faces, vec3(UV, float(face))).rgb;
			gold = texture(foil, vec3(UV, float(face))).r;
		}
	} else if (single_face) {
		tex = texture(back_texture, UV).rgb;
		gold = 0.0;
	} else {
		tex = texture(faces, vec3(UV, 0.0)).rgb;
		gold = texture(foil, vec3(UV, 0.0)).r;
	}
	vec2 edge_dist = min(UV, 1.0 - UV);
	float edge = 1.0 - smoothstep(0.0, 0.14, min(edge_dist.x, edge_dist.y * 0.7));
	// 圆角矩形的有向距离(米,牌内为负):贴着牌边压暗一圈
	vec2 q = abs((UV - 0.5) * card_size.xy) - (card_size.xy * 0.5 - card_size.z);
	float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - card_size.z;
	float rim = edge_side ? 0.0 : smoothstep(-rim_width, 0.0, sd);
	ALBEDO = pow(tex, vec3(ink_contrast)) * albedo_scale * mix(1.0, rim_shade, rim);
	METALLIC = gold * 0.5;
	ROUGHNESS = mix(edge_side ? 0.75 : 0.8, 0.3, gold);
	SPECULAR = mix(0.12, 0.5, gold);
	EMISSION = tex * self_illum + glow_color.rgb * glow * (0.04 + edge * 1.3);
}
