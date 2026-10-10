// 酒客眼睛:两只眼一个网格,巩膜、虹膜、瞳孔、高光、上眼睑、出局的 × 全画在着色器里(不自发光)。
// 顶点 CUSTOM0 = (眼面坐标 u, v ∈ [-1, 1],左右 -1/1,0):构建器把眼面贴在颅骨上(动森式「画在脸上」的大眼)。
// 眨眼、看向、表情、出局都是实例参数,所有酒客共用一份材质。光照用共享的柔和卡通光照(toon_light.gdshaderinc)。
// 动森式画法:大大的深色椭圆瞳孔占满眼睛大半,外面只留一圈物种色的虹膜边;一大一小两个高光;可选睫毛。
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/world/shaders/vertex_pbr.gdshaderinc"
// 眼面是贴片:边光会在眼眶一圈亮出白边,关掉;暗面多留一点光,眼睛在侧光下也看得清
#define TOON_NO_RIM
#define TOON_SHADOW 0.55
#define TOON_WRAP 0.6
#include "res://src/world/shaders/toon_light.gdshaderinc"

instance uniform vec4 look = vec4(0.0);            // 左眼 xy、右眼 zw 的瞳孔偏移(眼面坐标)
instance uniform float lid = 0.0;                  // 眨眼:0 睁开 → 1 闭上
instance uniform float lid_rest = 0.12;            // 物种默认眼睑(乌龟眼皮厚)
instance uniform float lid_tilt = 0.0;             // 表情:生气为正(眼睑内低外高),担心为负
instance uniform float dead = 0.0;                 // 出局:画 ×
instance uniform float fade = 0.0;                 // 出局褪灰(同 patron.gdshader)
instance uniform vec3 iris_color = vec3(0.45, 0.3, 0.12);   // sRGB,末尾统一转线性
instance uniform vec3 lid_color = vec3(0.5, 0.3, 0.15);
instance uniform float pupil_shape = 0.0;          // 0 圆、1 竖椭圆(猫、鳄鱼)、2 横椭圆(羊驼)
instance uniform float lashes = 0.0;
// Q 版搞笑表演(PatronAntics 驱动):
instance uniform float shock = 0.0;                // 吓到:眼睑全开、瞳孔缩成小黑点(枪口抵头、被喊骗子)
instance uniform float joy = 0.0;                  // 眯眼笑:眼睛画成 ^ 形弯线(松一口气、得意)
instance uniform float dizzy = 0.0;                // 晕乎乎:虹膜换成旋转的蚊香圈(中弹出局,和 × 交替)
instance uniform float plead = 0.0;                // 狗狗眼:瞳孔放大、眼睑全开、多两颗高光、下眼眶一弯泪光(炸弹猫讨要)

const vec3 SCLERA = vec3(0.74, 0.73, 0.7);    // 同 PatronParts.EYE_WHITE:奶白,不发蓝不过曝
const vec3 PUPIL = vec3(0.06, 0.045, 0.06);   // 深靛黑,不用纯黑
const vec3 GREY = vec3(0.42);
const float LID_REST_SCALE = 0.6;   // 物种默认眼睑整体少盖一点,眼睛更圆更亮(乌龟仍比别人眼皮厚)

varying vec3 eye;

void vertex() {
	eye = CUSTOM0.xyz;
}

float aa_step(float edge, float x) {
	float w = max(fwidth(x), 1e-4);
	return smoothstep(edge - w, edge + w, x);
}

void fragment() {
	vec2 uv = eye.xy;
	float side = eye.z;
	vec2 offset = side < 0.0 ? look.xy : look.zw;
	offset = clamp(offset, vec2(-0.3), vec2(0.3));
	vec2 q = uv - offset;
	// 瞳孔:竖着的大椭圆;猫、鳄鱼更窄(动森式圆瞳加一点细长),羊驼横宽
	vec2 pupil_scale = pupil_shape > 1.5 ? vec2(0.95, 1.25) : (pupil_shape > 0.5 ? vec2(1.75, 0.92) : vec2(1.05, 0.9));
	// 虹膜圈占眼睛的大部分,瞳孔又占虹膜的大部分;吓到时整团缩成针尖
	float iris_r = mix(mix(0.74, 0.36, shock), 0.8, plead);
	float pupil_r = mix(mix(0.6, 0.14, shock), 0.7, plead);
	vec2 qi = q * vec2(1.0, 0.92);
	float iris = 1.0 - aa_step(iris_r, length(qi));
	float pupil = 1.0 - aa_step(pupil_r, length(q * mix(pupil_scale, vec2(1.0), shock)));
	vec3 col = SCLERA;
	// 虹膜:下半部分亮一点(动森眼睛底部的一弯反光色)
	vec3 iris_col = iris_color * (0.8 + 0.35 * smoothstep(0.1, -0.6, q.y));
	vec3 pupil_col = mix(PUPIL, iris_color * 0.3, 0.25 * smoothstep(0.0, -0.6, q.y));
	float open_eye = (1.0 - dead) * (1.0 - joy);
	col = mix(col, iris_col, iris * open_eye);
	col = mix(col, pupil_col, pupil * open_eye);
	// 两个高光:左上一大、右下一小,跟着瞳孔走
	float spark = 1.0 - aa_step(0.2 + 0.07 * plead, length((q - vec2(-0.24, 0.27)) * vec2(1.0, 0.9)));
	spark = max(spark, 1.0 - aa_step(0.09, length(q - vec2(0.2, -0.2))));
	// 狗狗眼:再多两颗小高光,下沿一弯水汪汪的泪光
	float extra = max(1.0 - aa_step(0.1, length(q - vec2(0.24, 0.3))), 1.0 - aa_step(0.06, length(q - vec2(-0.32, -0.08))));
	spark = max(spark, extra * plead);
	float tear = (1.0 - aa_step(0.07, abs(length(qi) - iris_r * 0.82))) * smoothstep(-0.2, -0.5, q.y);
	col = mix(col, vec3(0.62, 0.84, 0.97), tear * iris * open_eye * plead);
	col = mix(col, vec3(0.97), spark * iris * open_eye * (1.0 - 0.6 * shock));
	// 晕乎乎:眼面画一圈旋转的蚊香(阿基米德螺线),出局时和 × 交替出现
	float r = length(uv);
	float a = atan(uv.y, uv.x * side) + TIME * 6.0;
	float spiral = abs(fract(r * 3.2 - a / (2.0 * PI)) - 0.5);
	col = mix(col, PUPIL, (1.0 - aa_step(0.13, spiral)) * step(r, 0.78) * dizzy);
	// 出局:两条对角线画 ×
	float x_mark = min(abs(uv.x - uv.y), abs(uv.x + uv.y)) * 0.7071;
	col = mix(col, PUPIL, (1.0 - aa_step(0.12, x_mark)) * step(r, 0.75) * dead * (1.0 - dizzy));
	// 眯眼笑:整只眼盖上眼皮色,中间一道 ^ 形弯线
	float arc = abs(uv.y + 0.15 - (1.0 - uv.x * uv.x) * 0.45);
	col = mix(col, lid_color, joy);
	col = mix(col, PUPIL, (1.0 - aa_step(0.11, arc)) * step(abs(uv.x), 0.8) * joy);
	// 上眼睑:从上往下盖,lid_tilt 让内外眼角高低不同(side 区分左右,x 朝外为正);吓到时眼睑全开
	float rest = lid_rest * LID_REST_SCALE * (1.0 - shock) * (1.0 - plead);
	float cover = (max(lid, rest) + lid_tilt * (uv.x * side) * 0.6) * (1.0 - joy);
	float lid_edge = 1.0 - 2.0 * clamp(cover, 0.0, 1.0);
	float covered = aa_step(lid_edge, uv.y);
	float lash_line = (1.0 - aa_step(0.06, abs(uv.y - lid_edge))) * step(cover, 0.98);
	col = mix(col, lid_color, covered);
	col = mix(col, PUPIL, lash_line * mix(0.35, 1.0, lashes) * (1.0 - covered));
	// 睫毛:外眼角两根短短的翘毛(画在眼面最外缘,只在 lashes 时)
	float outer = uv.x * side;
	float lash = (1.0 - aa_step(0.07, abs(uv.y - 0.55 - (outer - 0.6) * 0.9))) * step(0.62, outer) * step(r, 1.0);
	col = mix(col, PUPIL, lash * lashes * (1.0 - covered) * (1.0 - joy));
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, GREY * lum * 1.6, 0.85 * fade);
	ALBEDO = vp_srgb_to_linear(col);
	// 哑光贴片:眼面只在高光点那里亮(画上去的),整体不反光
	ROUGHNESS = mix(0.45, 0.85, covered);
	SPECULAR = 0.3;
}
