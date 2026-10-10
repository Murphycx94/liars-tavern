class_name Patron
extends Node3D
# 酒客角色:坐在椅子上的卡通动物。原点在座位地面,面朝 -Z(牌桌中心)。
# 坐姿:身体前倾趴在牌桌上,双手搭在桌面——拿着牌也一样,牌扇自己立在胸前(爪子去扶牌会挡住牌面)。
# 待机:呼吸、眨眼、眼神与头部跟随;动作:出牌伸手、拍桌、举枪(坐直)、中弹倒下、庆祝(坐直);
# 结算时胜者跳舞、旁人鼓掌、出局的人抽一下手(PatronDance,规格 2026-10-09-winner-celebration)。


const ARM_LENGTH := 0.45   # 动森式大头离肩更远:举枪时手要离头心 ≈0.64 m 才能把枪口抵在太阳穴(Q 版 0.4)
const SHOULDER := Vector3(0.21, 0.38, -0.02)   # 动森式:躯干压扁加宽后肩更低,肩宽不变(举枪够得着大头;Q 版 0.205, 0.485;最初 0.21, 0.52)
const PAW_RADIUS := 0.058
const PAW_SCALE := Vector3(1, 0.8, 1.1)
const PAW_CLEAR := PAW_RADIUS * 1.1 + 0.01   # clear_of_head:手掌离头的椭球至少这么远(爪子半径按最长的轴 + 1 cm)
const HEAD_PIVOT := Vector3(0, 0.62, -0.02)   # 动森式:下巴压在领口上,看不见脖子(Q 版 0.615;最初 0.65)
# 弹簧脖子:头按座位坐标的水平偏移伸出去,脖子从领口自动拉长连到头
const NECK_BASE := Vector3(0, 0.55, -0.02)   # 物种 LOOK 按压扁前写,构建时乘 PatronParts.BODY_SQUASH
# 头最远水平伸出(米;原 0.85,后扩到 2.55,2026-10-09 按用户要求定为 3 米,能探过桌心、伸到对面);头平着伸出去,高度不变。
# 所有物种一样(含长吻的鳄鱼),不按吻长少伸
const NECK_REACH := 3.0
# 头只能往前、往两侧探,不往后(+Z,朝越肩镜头):往后会挡在镜头和自己的手牌之间
const NECK_MAX_BACK := 0.0
const NECK_STIFFNESS := 60.0  # 弹簧刚度与阻尼:临界阻尼(2√刚度),头跟手又停得稳,不过冲不回晃
const NECK_DAMPING := 15.5
const NECK_MIN_THICKNESS := 0.55   # 拉长时脖子变细,最细到原粗细的这个比例
const NECK_MAX_STEP := 1.0 / 60.0  # 弹簧积分的最大步长(秒):掉帧时分步积分,不会弹飞
# 探头的软碰撞(穿模修复 2026-10-10):有牌桌(guard)时,头每个积分小步都被推出别人的头与身体、立牌等「挡」形状,
# 从牌扇、烛台等「抬」形状上面拱过去(见 ClipGuard);同步的仍是原始探头偏移,各端按自己的场景各自推、各自抬。
# 截短后的目标限速 NECK_GOAL_SPEED 米/秒(按 WASD 探头是 0.9 米/秒,照常跟手;绕过障碍物时目标跳开的那一下变成滑过去)
const NECK_GOAL_SPEED := 2.0
const HIP := Vector3(0, 0.5, 0.12)
# 前倾角(弧度,绕髋部):坐着时趴向牌桌,单节手臂才够得着桌面;轮到自己时再多倾一点
const SEATED_LEAN := 0.18
const TURN_LEAN := 0.13
# 举枪、庆祝时坐直——仍留一点前倾,空着的那只手才搭得到桌面
const SITTING_UP_LEAN := 0.08
# 低头的余量:看向的俯仰按物种下限(LOOK anim.look_pitch_min)截断之后,待机噪声(0.05)与说话点头(PatronAntics.NOD 0.075)
# 还会再往下压;总俯仰最低到下限 − 这么多(前倾时再按世界俯仰抬回来,见 head_pitch_floor)
const HEAD_DIP_ROOM := 0.125
# 搭在桌上的手:掌心离身体中线的横向距离;拍桌落点更靠里
const PAW_SPREAD := 0.15
const SLAM_SPREAD := 0.08
# 出牌手势:双手抬离桌面、朝桌心前推(座位坐标)
const REACH_POINT := Vector3(0.06, SeatLayout.TABLE_TOP + 0.14, -0.75)
const HAND_RAISED := Vector3(0.24, 0.82, -0.32)
# —— 举枪几何(枪口相对头心的位置全在这一处)——
# 手在以肩为心、一臂长的球面上,沿 GUN_APPROACH(头局部,从头心指向举枪的一侧)一族方向找手位,
# 使枪管轴线穿过头心时枪口离头心 = 持枪净空 + GUN_CLEARANCE(枪口贴在太阳穴外 8 mm)。
# 持枪净空 = 物种 LOOK 的 gun_clearance(按实际头部网格量的,已含 Q 版头的缩放);没给时用头缩放 1.0 的默认值
# 乘以 head_scale()(头绕头心等比放大,太阳穴表面跟着往外移)。HAND_GUN_HEAD 是头缩放 1.0、默认净空下的解
# (= gun_hand_target(DEFAULT_GUN_CLEARANCE)),测试校验;运行时一律现算
const GUN_CLEARANCE := 0.008
const DEFAULT_GUN_CLEARANCE := 0.17
const GUN_APPROACH := Vector3(0.9656, 0.2414, -0.0966)   # = Vector3(1, 0.25, -0.1).normalized()
const HAND_GUN_HEAD := Vector3(0.4447, 0.7619, -0.0599)   # 动森式肩、头枢轴、臂长重算(Q 版 0.4393, 0.8066, -0.0613)
const GUN_TWIST_TIME := 0.18   # 手位到了之后转手(不转枪)对准头心的时长
const GUN_DROP := Vector3(0.24, 0.0, -0.42)          # 中弹后枪落在面前的桌沿(座位坐标,高度另按毡面算)
const HAND_CHEER := Vector3(0.32, 1.0, -0.12)
const HAND_DEAD := Vector3(0.28, 0.0, 0.05)
# 他人的牌扇(穿模修复 2026-10-10,规格 2026-10-08-cozy-toon-style-design §穿模修复):在 CardTable.FAN_BASIS(竖立、牌面朝持牌者)
# 基础上再上仰 FAN_TILT_DEG,牌面迎向持牌者的视线、牌背斜朝上给别人看。动森式大头的下巴压在领口上、两条手臂几乎平搭在桌沿,
# 胸前已经没有空地(原来摆在 HIP + (0, 0.46, −0.37):实测 8 个物种静坐时牌扇上半截埋进下巴、外侧几张插进手臂)。
# 改成立在两只爪子前方的桌面上空:FAN_SEAT_POS 是座位坐标(不跟着前倾转,只跟着身体蹦跳、侧挪平移),略缩小 FAN_SCALE。
# 转头包络(低头到物种下限、前倾、左右转)里吻尖与帽檐都够不着,轮到他前倾时爪子也碰不到;牌的最低角高出毡面。
# 物种 LOOK 可写 "fan": {"pos", "tilt", "scale"} 单独调(目前都用默认值)。见 fan_rest_transform / table_fan_transform
const FAN_SEAT_POS := Vector3(0, 0.9, -0.62)
const FAN_TILT_DEG := -25.0
const FAN_SCALE := 0.9
enum { FAN_TABLE, FAN_HAND, FAN_FP, FAN_LAP }   # 牌扇怎么摆:立在桌面上空(他人)/ hold_fan 给的固定位置 / 第一人称跟着眼睛 / 出局扣在面前桌上
# 第三人称下自己的牌扇:举在右肩外侧、比头更靠近越肩镜头,头怎么探都只会在牌后面;牌面朝向镜头,
# 高度让牌扇停在回合横幅之上(座位坐标,相对髋部;越肩机位按它取景)
const SELF_FAN_POS := Vector3(0.48, 0.88, 0.16)
const SELF_FAN_SCALE := 1.25
# 第一人称(V 切换,规格 2026-10-08-first-person-toggle):眼睛 = 头心(头枢轴上方 0.12)再往上、往桌心挪一点(座位坐标),
# 落在大头里面靠前的位置——自己的头只投影不渲染,往下看时胸口与领口也在镜头后面。
# 牌扇按镜头坐标摆在画面右下、像拿在手里(FP_FAN_CAM:右、下、前),跟着眼睛平移,探头、前倾时牌在画面里不动
const FP_EYE_OFFSET := Vector3(0, 0.07, -0.12)
const VIEW_FOLLOW := 10.0   # 第一人称镜头追转头目标的速度(每秒):比头本身(3)快,跟手又不跳
const FP_FAN_CAM := Vector3(0.22, -0.12, -0.55)
const FP_FAN_SCALE := 1.0
# 第一人称探头时手里的牌扇往眼睛收:以眼睛为中心按 FP_FAN_NEAR 等比缩小、拉近,画面上一模一样(透视下以视点为中心缩放不变形),
# 但不再伸到眼前 0.55 米外戳进别人的头、立牌(牌留在头自己的碰撞范围里)。脖子水平伸出 FP_FAN_PULL 米时收到底
const FP_FAN_NEAR := 0.4
const FP_FAN_PULL := 0.3
# 探头往前时他人(自己在别人屏幕上)立在桌面上空的牌扇矮下去:以牌底为中心缩到 FAN_TUCK_SCALE、落到毡面上,
# 头和伸长的脖子从上面过去,不再从牌里穿过;不转、不往前伸,扫不到前面桌上的东西。脖子往前伸 FAN_TUCK.x 米开始收,FAN_TUCK.y 米收到底
const FAN_TUCK := Vector2(0.04, 0.18)
const FAN_TUCK_SCALE := 0.45
const FAN_SAG := 0.05      # 立着的牌扇两侧最低的牌角比中间那张的牌底低这么多(扇形下沉 + 转角,缩放 1 时)
# 自己举着的牌扇(越肩 / 第一人称)收起来:镜头离开座位去拍特写、翻牌时,牌扇落回桌面上空、矮下去(同探头时的收法),
# 不再挡在特写镜头前;回座后再举起来(试玩挑错 2026-10-10:骗子酒馆第一人称翻牌机位就在自己头上,右半屏被 5 张大牌挡住)。
# FAN_STOW_SPEED:每秒收 / 举这么多(0..1)
const FAN_STOW_SPEED := 4.0
const FAN_STACK := 0.032   # 扣着平放时牌底抬高的一叠牌(斗地主地主最多 20 张,每张错开 1.6 mm × 缩放)
const FP_SPEECH_AHEAD := Vector3(0, 0.12, -0.7)   # 第一人称时自己的快捷语气泡挂在眼前上方(座位坐标,相对眼睛):头顶在镜头背后
# 庆祝:原地蹦几下,每次起跳/落下的时长(秒)与高度(米)
const CHEER_BOUNCES := 3
const CHEER_BOUNCE_TIME := 0.22
const CHEER_JUMP := 0.08
# 出局时打飞的帽子等散落物:挂到父节点(TableWorld)下并打上此标记,由 TableWorld 回收
const DEBRIS_GROUP := &"patron_debris"
const GREY := Color(0.42, 0.42, 0.42)   # 褪色的灰(patron.gdshader 里同值)
const FADE_TIME := 1.4
const DIE_BODY_ROT := Vector3(0.55, 0.15, -0.5)
const DIE_HEAD_ROT := Vector3(0.3, 0.3, -0.4)
# 出局时牌扇扣在面前的桌面上(穿模修复 2026-10-10:原来扣在大腿上,实测整扇牌都埋进躯干与裤子里):
# 立在桌面上空的牌扇绕牌底往持牌者这边倒下、牌背朝上平放(身子往后仰,倒下的牌扫过的地方够不着头和手);
# 越肩 / 第一人称举着的牌扇从手里按座位坐标直接落到同一位置。DIE_FAN_TIME 秒落定
const DIE_FAN_TIME := 0.4
const DIE_FAN_SWING := Vector3(0, 0.3, -0.45)   # 举在手里的牌先往上、往桌心抛出去(贝塞尔控制点,座位坐标)再落到桌上
# 丢番茄(规格 2026-10-08):抛的人右手往后上方蓄力再甩向目标;被砸的人左爪抹一下脸(身体局部坐标,相对头的位置)
const HAND_WINDUP := Vector3(0.34, 0.92, 0.14)
const THROW_WINDUP := 0.16      # 蓄力时长(秒):番茄在这之后出手
const THROW_FLING := 0.1
const THROW_RECOVER := 0.32     # 甩完之后停多久再把手搭回桌上
const WIPE_FACE := Vector3(-0.06, -0.04, -0.36)
const SPEECH_ABOVE_HEAD := 0.34 # 快捷语气泡挂在头心之上这么高(没有铭牌时)
# 炸弹猫:偷看时左爪捂嘴(身体局部坐标,相对头的位置);拆弹时两只爪子在胸前比划(座位坐标),每步这么久
const COVER_MOUTH := Vector3(0.02, -0.1, -0.34)
const COVER_MOUTH_HOLD := 0.7
const SNIP_LEFT := Vector3(-0.08, SeatLayout.TABLE_TOP + 0.24, -0.5)
const SNIP_RIGHT := Vector3(0.09, SeatLayout.TABLE_TOP + 0.27, -0.48)
const SNIP_STEP := 0.09
const SNIP_TIME := 0.9
const PEEK_GLASS := Vector3(0.15, -0.04, -0.3)    # 炸弹猫「偷看」:右爪举着放大镜凑到脸旁(相对头枢轴,身体坐标)
const PLEAD_PAWS := Vector3(0.035, -0.2, -0.3)    # 炸弹猫「讨要」:双爪合十抵在下巴下
const SNEAK_LEAN := 0.36                          # 炸弹猫「溜了」:身子往一侧一缩
# 炸弹猫「甩锅」:头被拍扁(竖向压扁、横向撑开)。前后不放大:头枢轴在下巴,前后一放大,鳄鱼的长吻就往前捅进自己的牌扇
const BONK_SQUASH := Vector3(1.22, 0.68, 1.0)
const SNEAK_SHIFT := 0.13
const NAMEPLATE_HEIGHT := 1.92   # 名牌挂点离座位地面:Q 版大头的帽顶坐直时 ≈1.70 m、欢呼蹦起 ≈1.78 m(之前 1.82)

var species_index := 0
var alive := true
var body: Node3D
var head: Node3D
var fan: Node3D
var _fan_mode := FAN_TABLE
var _fan_hold := Transform3D()   # FAN_HAND:身体局部的固定变换;FAN_FP:座位坐标(眼睛在 rest_eye 时),每帧跟着眼睛平移,画面里不动
var _fan_alive = null   # 出局前的 [牌扇模式, 变换];reset_pose 时放回
var _fan_drop := 0.0    # 出局时牌扇倒下的进度(0..1,FAN_LAP 模式)
var _fan_stow := 0.0    # 举着的牌扇收起来的进度(0 = 举着,1 = 收在桌面上空)
var _fan_stow_target := 0.0
var _fan_drop_from := Transform3D()   # 出局那一刻牌扇的座位坐标变换(越肩 / 第一人称举着的牌从这里落下)
var _head_hidden := false
var _hidden_parts := {}  # 第一人称时藏起来的几何体 -> [原 cast_shadow, 原 layers](恢复用)
var right_hand: Node3D

var _arm_l: Node3D
var _arm_r: Node3D
var _eye: MeshInstance3D       # 两只眼一个网格,patron_eye.gdshader 画眼睑/虹膜/高光/×
var _look := Vector4.ZERO      # 左右瞳孔偏移(眼面坐标),写进眼睛的实例参数
var _paw_r: MeshInstance3D
var _fist: MeshInstance3D      # 握枪时右手换成拳头
var _legs: MeshInstance3D      # 腿、鞋、尾巴(座位坐标,跟着蹦跳)
var _look_data: Dictionary     # 物种外观(species/*.gd 的 LOOK)
var _neck_base := NECK_BASE
var _brow_y := 0.222
var _brows: Array = []
var _ears: Array = []
var _hat: Node3D
var _fade_targets: Array[GeometryInstance3D] = []   # 出局时褪色的部件(帽子打飞后仍在列表里)
var _look_target := Vector3.ZERO
var _has_look := false
var _time := 0.0
var _phase := 0.0
var _blink_in := 2.0
var _breath_rate := 1.0
var _lean := SEATED_LEAN
var _sitting_up := false   # 举枪、庆祝时坐直
var _steady := false       # 枪抵着太阳穴:头不再随噪声晃
var _arms_locked := false
var _resting := {}         # 手臂 → 是否搭在桌上:搭着的手每帧按身体姿态重新落点(单手动作时另一只手照样搭着)
var _arm_serial := 0       # 每次手臂补间加一;歇手补间结束时据此判断期间有没有新动作
var _cheer_tweens: Array[Tween] = []   # 庆祝中的蹦跳与举手,复位时中止
var _noise := FastNoiseLite.new()
var _neck: Node3D
var _neck_target := Vector3.ZERO     # 座位坐标的头部偏移目标
var _neck_offset := Vector3.ZERO     # 当前偏移(弹簧积分)
var _neck_velocity := Vector3.ZERO
var _wipe_tween: Tween = null      # 被番茄砸中后抹脸的补间(出局、复位时中止)
var _view_angles := Vector2.ZERO   # 第一人称镜头跟着的转头角度 (yaw, pitch):只含看向目标,不含待机晃动与表演,追得比头快
var _antics: PatronAntics          # Q 版搞笑表演(冒汗、发抖、星星、待机小动作……),见 patron_antics.gd
var _dance: PatronDance = null     # 结算庆祝:跳舞 / 鼓掌 / 出局抽手(只在庆祝期间存在),见 patron_dance.gd
var guard: ClipGuard = null        # 牌桌的穿模防护(TableWorld 落座时给;没有时探头不做软碰撞,如主菜单的形象、单独测试)
var guard_id := -1                 # 在牌桌上的 pid:查询形状时跳过自己的头和身体
var _blockers: Array = []          # 这一帧要躲的「挡」形状(_guard_target 取)
var _guard_fwd := Vector2(0, -1)   # 座位朝向(牌桌坐标的水平方向)
var _neck_goal := Vector3.ZERO     # 软碰撞时弹簧追的目标(截短后的探头目标,限速 NECK_GOAL_SPEED 滑过去)
# 第一人称的观感留白(只在本机,SeatCamera 设):自己的头在软碰撞里按这么大一圈算(别人的头也离自己的镜头这么远),
# 一桌人都往桌心探头时邻座的大头不会贴在镜头上挡掉半个画面(试玩挑错 2026-10-10)
var guard_extra := 0.0
var _head_metrics := {}            # 头的解析尺寸(head_metrics),头上挂的东西变了才重量
var _metrics_key := -1


func _init(p_species_index := 0) -> void:
	species_index = p_species_index
	_phase = species_index * 1.7
	_noise.seed = species_index * 31 + 7
	_build()


func _process(delta: float) -> void:
	_time += delta
	if alive:
		_animate_idle(delta)
	_update_neck(delta)
	_antics.tick(delta)


# —— 构建 ——

func _build() -> void:
	# 每个动画枢轴下的静态零件合成一份共享网格(按「物种:部件」缓存,所有酒客共用一份酒客材质);
	# 枢轴的名字、层级、变换都和合并前一样,动画代码不变。脖子根、眉、耳、帽的位置按物种外观
	var spec := PatronParts.species(species_index)
	_look_data = SpeciesLooks.look(species_index)
	_neck_base = _look_data["neck"].get("base", NECK_BASE) * Vector3(1.0, PatronParts.BODY_SQUASH, 1.0)
	MeshKit.add(self, PatronParts.chair_mesh(), null).name = "Chair"
	_legs = _add_part(self, PatronParts.part_mesh(spec, "legs"), "Legs")
	_legs.extra_cull_margin = 0.12   # 尾巴在顶点着色器里摆,会超出包围盒
	var tail: Dictionary = _look_data.get("tail", {})
	if not tail.is_empty():
		_legs.set_instance_shader_parameter("tail", Vector4(_phase, tail.get("sway", 0.12), 0.0, 0.0))
		_legs.set_instance_shader_parameter("tail_root", tail["path"][0])
	body = MeshKit.pivot(self, HIP, "Body")
	body.rotation.x = -SEATED_LEAN
	_add_part(body, PatronParts.part_mesh(spec, "body"), "BodyMesh")
	_neck = MeshKit.pivot(body, _neck_base, "Neck")
	_add_part(_neck, PatronParts.part_mesh(spec, "neck"), "NeckMesh")
	_build_head(spec)
	_fit_neck()
	_arm_l = _build_arm(-1.0, spec)
	_arm_r = _build_arm(1.0, spec)
	right_hand = _arm_r.get_node("Hand")
	fan = MeshKit.pivot(body, Vector3.ZERO, "Fan")
	_place_fan()
	_resting = {_arm_l: true, _arm_r: true}
	_plant_paws()
	_antics = PatronAntics.new()
	add_child(_antics)
	_antics.setup(self)
	head_metrics()


func _build_head(spec: Dictionary) -> void:
	head = MeshKit.pivot(body, HEAD_PIVOT, "Head")
	_add_part(head, PatronParts.part_mesh(spec, "head"), "HeadMesh")
	_eye = _add_part(head, PatronParts.part_mesh(spec, "eyes"), "Eyes")
	_eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var eyes: Dictionary = _look_data["eyes"]
	var iris: Color = eyes.get("iris", Color(0.4, 0.28, 0.12))
	var lid_color: Color = PatronParts.palette(spec)["fur"]
	_eye.set_instance_shader_parameter("iris_color", Vector3(iris.r, iris.g, iris.b))
	_eye.set_instance_shader_parameter("lid_color", Vector3(lid_color.r, lid_color.g, lid_color.b))
	_eye.set_instance_shader_parameter("lid_rest", eyes.get("lid_rest", 0.12))
	_eye.set_instance_shader_parameter("pupil_shape", float(eyes.get("pupil", 0)))
	_eye.set_instance_shader_parameter("lashes", 1.0 if eyes.get("lashes", false) else 0.0)
	_eye.set_instance_shader_parameter("lid", 0.0)
	_eye.set_instance_shader_parameter("lid_tilt", 0.0)
	_eye.set_instance_shader_parameter("dead", 0.0)
	_eye.set_instance_shader_parameter("look", Vector4.ZERO)
	var brow_pos := PatronParts.brow_point(_look_data)   # Q 版:LOOK 坐标按头心放大(PatronParts.head_point)
	_brow_y = brow_pos.y
	var brow_mesh := PatronParts.part_mesh(spec, "brow")
	for side in [-1.0, 1.0]:
		var brow := MeshKit.pivot(head, Vector3(brow_pos.x * side, brow_pos.y, brow_pos.z))
		_add_part(brow, brow_mesh, "BrowMesh")
		_brows.append(brow)
	var ears: Dictionary = _look_data.get("ears", {})
	if ears.get("kind", "none") != "none":
		var ear_mesh := PatronParts.part_mesh(spec, "ear")
		var pivot := PatronParts.head_point(_look_data, ears["pivot"])
		var rot: Vector3 = ears.get("rot", Vector3.ZERO)
		for side in [-1.0, 1.0]:
			var ear := MeshKit.pivot(head)
			ear.transform = MeshForge.xf(Vector3(pivot.x * side, pivot.y, pivot.z), Vector3(rot.x, rot.y * side, rot.z * side))
			_add_part(ear, ear_mesh, "EarMesh")
			_ears.append(ear)
	var hat: Dictionary = _look_data.get("hat", {})
	_hat = MeshKit.pivot(head, Vector3.ZERO, "Hat")
	_hat.transform = MeshForge.xf(PatronParts.head_point(_look_data, hat.get("pivot", Vector3(0, 0.255, 0.01))),
		hat.get("rot", Vector3(-6, 0, 9)))
	_add_part(_hat, PatronParts.part_mesh(spec, "hat"), "HatMesh")


func _build_arm(side: float, spec: Dictionary) -> Node3D:
	var pivot := MeshKit.pivot(body, _mirror(SHOULDER, side), "ArmR" if side > 0 else "ArmL")
	_add_part(pivot, PatronParts.part_mesh(spec, "arm"), "ArmMesh")
	var hand := MeshKit.pivot(pivot, Vector3(0, 0, -ARM_LENGTH), "Hand")
	var paw := _add_part(hand, PatronParts.part_mesh(spec, "paw_r" if side > 0 else "paw_l"), "PawMesh")
	if side > 0:
		_paw_r = paw
		_fist = _add_part(hand, PatronParts.part_mesh(spec, "fist"), "FistMesh")
		_fist.visible = false
	return pivot


func _set_fist(on: bool) -> void:
	# 握枪时右手换成拳头(枪挂在 Hand 上,张开的爪会把握把吞进掌心)
	if _fist == null:
		return
	_fist.visible = on
	_paw_r.visible = not on


func _add_part(parent: Node3D, mesh: ArrayMesh, node_name: String) -> MeshInstance3D:
	# 合并网格的材质挂在网格上(共享网格 + 共享材质才能自动实例化);出局褪色的目标收进 _fade_targets
	var inst := MeshKit.add(parent, mesh, null)
	inst.name = node_name
	_fade_targets.append(inst)
	return inst


# —— 待机 ——

func _animate_idle(delta: float) -> void:
	var breath := sin(_time * 1.6 * _breath_rate + _phase)
	body.scale = Vector3(1.0 - breath * 0.004, 1.0 + breath * 0.012, 1.0)
	var lean := SITTING_UP_LEAN if _sitting_up else _lean
	body.rotation.x = lerpf(body.rotation.x, -lean + breath * 0.01, minf(delta * 4.0, 1.0))
	_plant_paws()
	var yaw := 0.0
	var pitch := 0.0
	if _has_look:
		var local := body.to_local(_look_target) - head.position
		yaw = clampf(atan2(-local.x, -local.z), -0.7, 0.7)
		pitch = clampf(atan2(local.y, Vector2(local.x, local.z).length()), _look_data.get("anim", {}).get("look_pitch_min", -0.45), 0.35)
	# 枪抵着太阳穴时屏住不动(头一晃,只隔 8 mm 的枪口就戳进头里);搞笑表演的头部偏移同样屏住
	var wobble := 0.0 if _steady else 1.0
	_view_angles = _view_angles.lerp(Vector2(yaw, pitch), minf(delta * VIEW_FOLLOW, 1.0))
	yaw += (_noise.get_noise_1d(_time * 0.4) * 0.08 + _antics.head_add.y) * wobble
	pitch += (_noise.get_noise_1d(_time * 0.3 + 40.0) * 0.05 + _antics.head_add.x + _antics.nod) * wobble
	pitch = maxf(pitch, head_pitch_floor(_look_data, -body.rotation.x))
	head.rotation.y = lerpf(head.rotation.y, yaw, minf(delta * 3.0, 1.0))
	head.rotation.x = lerpf(head.rotation.x, pitch, minf(delta * 3.0, 1.0))
	head.rotation.z = lerpf(head.rotation.z, (_noise.get_noise_1d(_time * 0.25 + 90.0) * 0.06 + _antics.head_add.z) * wobble,
		minf(delta * 12.0, 1.0))
	_update_look(delta)
	_legs.position.y = maxf(body.position.y - HIP.y, 0.0)   # 腿跟着蹦跳,下沉时不入地
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_in = randf_range(1.8, 5.5)
		_blink()


static func head_pitch_floor(look: Dictionary, lean: float) -> float:
	# 低头的下限(含待机噪声、说话点头、表演的叠加):物种看向下限再留 HEAD_DIP_ROOM;身体比坐着(SEATED_LEAN)前倾得越多,
	# 头越要往上抬回来(按世界俯仰算):鳄鱼的长吻轮到他前倾时低头会戳进桌面(穿模修复 2026-10-10 实测)
	return float(look.get("anim", {}).get("look_pitch_min", -0.45)) - HEAD_DIP_ROOM + (lean - SEATED_LEAN)


func _update_look(delta: float) -> void:
	# 瞳孔看向目标:按两只眼各自的位置算方向,换成眼面坐标的偏移;变化很小时不写实例参数
	var target := Vector4.ZERO
	if _has_look:
		var eye_pos := PatronParts.head_point(_look_data, _look_data["eyes"]["pos"])
		var local := head.to_local(_look_target)
		for side in [-1.0, 1.0]:
			var dir := (local - Vector3(eye_pos.x * side, eye_pos.y, eye_pos.z)).normalized()
			var offset := Vector2(dir.x, dir.y) * 0.45
			if side < 0.0:
				target.x = offset.x
				target.y = offset.y
			else:
				target.z = offset.x
				target.w = offset.y
	var next := _look.lerp(target, minf(delta * 8.0, 1.0))
	if (next - _look).length() > 0.002:
		_look = next
		_eye.set_instance_shader_parameter("look", _look)


func _set_lid(value: float) -> void:
	_eye.set_instance_shader_parameter("lid", value)


func _blink() -> void:
	var speed: float = _look_data.get("anim", {}).get("blink_speed", 1.0)
	var tween := create_tween()
	tween.tween_method(_set_lid, 0.0, 1.0, 0.06 / speed)
	tween.tween_method(_set_lid, 1.0, 0.0, 0.08 / speed)
	if randf() < 0.4 and not _ears.is_empty() and not _steady:
		var ear: Node3D = _ears[randi() % _ears.size()]
		var base := ear.rotation.x
		var twitch := create_tween()
		twitch.tween_property(ear, "rotation:x", base - 0.3, 0.07)
		twitch.tween_property(ear, "rotation:x", base, 0.15)


# —— 弹簧脖子 ——

func set_neck_target(seat_offset: Vector3) -> void:
	_neck_target = clamp_neck(seat_offset)


static func clamp_neck(seat_offset: Vector3) -> Vector3:
	# 座位坐标的水平偏移(-Z 朝桌心):只取水平分量(头平着伸出去,高度不变),不往后,最远 NECK_REACH
	return Vector3(seat_offset.x, 0.0, minf(seat_offset.z, NECK_MAX_BACK)).limit_length(NECK_REACH)


func neck_offset() -> Vector3:
	return _neck_offset


func _update_neck(delta: float) -> void:
	var target := _neck_target if alive else Vector3.ZERO
	var guarded := guard != null and alive and is_inside_tree() \
		and (target.length_squared() > 0.000001 or _neck_offset.length_squared() > 0.000001)
	if guarded:
		# 截短后的目标在绕过障碍物的一瞬可能一下跳开很远:目标点本身限速滑过去,头不会猛甩
		var want := _guard_target(target)
		_neck_goal += (want - _neck_goal).limit_length(NECK_GOAL_SPEED * delta)
		target = _neck_goal
	else:
		_neck_goal = target
	var left := delta
	while left > 0.0:
		var step := minf(left, NECK_MAX_STEP)
		var goal := target
		if guarded:
			goal.y = _neck_lift()
		var accel := (goal - _neck_offset) * NECK_STIFFNESS - _neck_velocity * NECK_DAMPING
		_neck_velocity += accel * step
		_neck_offset += _neck_velocity * step
		if guarded:
			_guard_neck()
		left -= step
	# 偏移按座位坐标给出:换到(前倾、出局时歪倒的)身体局部坐标,头才是水平地探出去
	head.position = HEAD_PIVOT + body.quaternion.inverse() * _neck_offset
	_fit_neck()
	_place_fan(delta)


func _head_base() -> Vector3:
	# 脖子没探出时的头心(座位坐标,含此刻的前倾、呼吸与蹦跳)
	return body.transform * (HEAD_PIVOT + Vector3(0, 0.12, 0))


func _seat_frame() -> Transform3D:
	# 座位在牌桌坐标里的变换(去掉登场缩放)
	return transform.orthonormalized()


func _guard_target(target: Vector3) -> Vector3:
	# 这一帧要躲的形状(按帧取一次),并把探头目标沿直线截到第一个碰撞之前(ClipGuard.ray_clamp)
	var seat := _seat_frame()
	var base := _head_base()
	var home := seat * base
	var fwd3 := -seat.basis.z
	_guard_fwd = Vector2(fwd3.x, fwd3.z).normalized()
	var m := guard_metrics()
	_blockers = guard.blockers_for(guard_id, Vector2(home.x, home.z), _guard_fwd, m)
	var to := seat * (base + Vector3(target.x, 0.0, target.z))
	var t := ClipGuard.ray_clamp(_blockers, Vector2(home.x, home.z), Vector2(to.x, to.z), _guard_fwd, m)
	return Vector3(target.x * t, 0.0, target.z * t)


func _guard_neck() -> void:
	# 把头推出「挡」形状:位置投影到形状外面,速度去掉往里的分量(贴着边滑,不弹)
	var seat := _seat_frame()
	var c := seat * (_head_base() + _neck_offset)
	var m := guard_metrics()
	var res := ClipGuard.push_out(_blockers, Vector2(c.x, c.z), _guard_fwd, m, c.y - m["below"])
	var h: Vector2 = res[0]
	if h.is_equal_approx(Vector2(c.x, c.z)):
		return
	_neck_offset += seat.basis.inverse() * Vector3(h.x - c.x, 0.0, h.y - c.z)
	var n: Vector2 = res[1]
	var normal := seat.basis.inverse() * Vector3(n.x, 0.0, n.y)
	var into := _neck_velocity.dot(normal)
	if into < 0.0:
		_neck_velocity -= normal * into


func _neck_lift() -> float:
	# 头此刻的水平位置要抬多高才从「抬」形状上面过去(灯下封顶)
	var seat := _seat_frame()
	var c := seat * (_head_base() + Vector3(_neck_offset.x, 0.0, _neck_offset.z))
	var m := head_metrics()
	var h := Vector2(c.x, c.z)
	var base := seat * (body.transform * _neck_base)
	var length := (HEAD_PIVOT - _neck_base).length()
	var span := (seat * (body.transform * (HEAD_PIVOT + body.quaternion.inverse() * Vector3(_neck_offset.x, 0.0, _neck_offset.z)))) - base
	var thickness := clampf(sqrt(length / maxf(span.length(), 0.001)), NECK_MIN_THICKNESS, 1.0)
	var radius: float = _look_data["neck"].get("radius", 0.08) * thickness
	var lift := ClipGuard.lift_needed(guard.shapes(), h, c.y, _guard_fwd, m, guard_id, base, radius)
	return minf(lift, ClipGuard.ceiling_cap(h, c.y, m))


func head_metrics() -> Dictionary:
	# 头的解析尺寸(Head 局部,相对头心 PatronParts.HEAD_CENTER):由头上各部件网格的包围盒换算,运行时不读网格。
	# rx / front / back:含帽、耳的水平半宽、往前(吻、帽檐)、往后;above:帽顶、耳尖;below:下巴;mx:脸本身的半宽(拱过矮东西用)。
	# 按头上挂的东西缓存:换帽子(斗地主的地主帽 / 草帽挂在 Head/Hat 下)、帽子被打飞时重量一次,平时只比一下子节点数
	var key := head.get_child_count() * 1000 + (_hat.get_child_count() if _hat != null else -1)
	if key == _metrics_key and not _head_metrics.is_empty():
		return _head_metrics
	_metrics_key = key
	var box := AABB()
	var first := true
	for node in head.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible or mi.name == "Tongue" or not _visible_under(mi, head):
			continue
		var b: AABB = _relative(head, mi) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var face: AABB = (head.get_node("HeadMesh") as MeshInstance3D).get_aabb()
	var c := PatronParts.HEAD_CENTER
	_head_metrics = {
		"rx": maxf(-box.position.x, box.end.x), "front": c.z - box.position.z, "back": box.end.z - c.z,
		"above": box.end.y - c.y, "below": c.y - face.position.y, "mx": maxf(-face.position.x, face.end.x),
	}
	return _head_metrics


func guard_metrics() -> Dictionary:
	# 软碰撞里水平方向用的头部尺寸:head_metrics 再加第一人称的观感留白 guard_extra(只在本机)
	var m := head_metrics()
	if guard_extra <= 0.0:
		return m
	var out := m.duplicate()
	for key in ["rx", "front", "back"]:
		out[key] = m[key] + guard_extra
	return out


static func _visible_under(node: Node3D, root: Node3D) -> bool:
	# 从 node 到 root 一路都可见(不依赖是否在场景树里;藏起来的原帽子 HatMesh 不算)
	var n: Node = node
	while n != null and n != root:
		if n is Node3D and not (n as Node3D).visible:
			return false
		n = n.get_parent()
	return true


static func _relative(root: Node3D, node: Node3D) -> Transform3D:
	# node 在 root 局部坐标里的变换(不依赖是否在场景树里)
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _fit_neck() -> void:
	var span := head.position - _neck_base
	var length := maxf(span.length(), 0.001)
	var thickness := clampf(sqrt((HEAD_PIVOT - _neck_base).length() / length), NECK_MIN_THICKNESS, 1.0)
	_neck.basis = Basis(Quaternion(Vector3.UP, span / length)) * Basis.from_scale(Vector3(thickness, length, thickness))


func look_at_point(point: Vector3) -> void:
	_look_target = point
	_has_look = true


func head_position() -> Vector3:
	return head.global_transform * Vector3(0, 0.12, 0)


func view_angles() -> Vector2:
	# 第一人称镜头的转头角度 (yaw 左正, pitch 上正),相对身体朝向;没看任何东西时回到 0
	return _view_angles


func eye_position() -> Vector3:
	# 第一人称的眼睛(全局)
	return global_transform * eye_local()


func eye_local() -> Vector3:
	# 第一人称的眼睛(座位坐标):头心(不含转头,只含前倾、呼吸、蹦跳与脖子偏移)+ FP_EYE_OFFSET
	return body.transform * (head.position + Vector3(0, 0.12, 0)) + FP_EYE_OFFSET


static func rest_eye() -> Vector3:
	# 坐着(SEATED_LEAN)、脖子没探出时的眼睛,座位坐标:第一人称镜头的朝向、手里牌扇的位置都按它定
	return HIP + Basis(Vector3.RIGHT, -SEATED_LEAN) * (HEAD_PIVOT + Vector3(0, 0.12, 0)) + FP_EYE_OFFSET


func nameplate_anchor() -> Vector3:
	return global_transform * Vector3(0, NAMEPLATE_HEIGHT, 0.1)


func speech_anchor() -> Vector3:
	# 没有铭牌的人(越肩机位下的自己)快捷语气泡挂在头顶上方:跟着头晃、探头。
	# 第一人称坐在座位上(头藏着)时头顶在镜头背后,改挂在眼前上方
	if _head_hidden:
		return global_transform * (eye_local() + FP_SPEECH_AHEAD)
	return head_position() + Vector3.UP * SPEECH_ABOVE_HEAD


func set_active(active: bool) -> void:
	_lean = SEATED_LEAN + (TURN_LEAN if active else 0.0)
	_breath_rate = 1.8 if active else 1.0


func set_expression(kind: String) -> void:
	var angles := {"neutral": 0.0, "angry": -0.38, "worried": 0.4, "happy": 0.15, "smug": -0.15}
	var lift := 0.02 if kind in ["worried", "happy"] else 0.0
	var tween := create_tween().set_parallel()
	for i in _brows.size():
		var side := -1.0 if i == 0 else 1.0
		tween.tween_property(_brows[i], "rotation:z", angles.get(kind, 0.0) * -side, 0.18)
		tween.tween_property(_brows[i], "position:y", _brow_y + lift, 0.18)
	var tilts := {"angry": 0.25, "worried": -0.2}
	tween.tween_method(func(v: float): _eye.set_instance_shader_parameter("lid_tilt", v),
		float(_eye.get_instance_shader_parameter("lid_tilt")), tilts.get(kind, 0.0), 0.18)


# —— 手臂 ——

func rest_arms(animate := true) -> void:
	# 双手搭回桌上;动作进行中(动作锁)时不打断,动作结束后由动作自己调用。
	# 搭好之后每帧重新落点,呼吸、前倾都不会让手悬空或按进桌里
	if _arms_locked:
		return
	var tween := pose_arms(rest_target(-1.0), rest_target(1.0), 0.3 if animate else 0.0)
	var serial := _arm_serial
	tween.finished.connect(func():
		if serial == _arm_serial:
			_resting = {_arm_l: true, _arm_r: true})


func rest_target(side: float, spread := PAW_SPREAD) -> Vector3:
	# 手搭在桌上的落点(身体局部坐标):按当前肩位,手臂伸直一臂之长、掌底贴着桌面
	var shoulder := body.transform * _mirror(SHOULDER, side)
	var paw_y := SeatLayout.TABLE_TOP + PAW_RADIUS * PAW_SCALE.y
	var dy := paw_y - shoulder.y
	var reach := sqrt(maxf(ARM_LENGTH * ARM_LENGTH - dy * dy, 0.0))
	var dx := spread * side - shoulder.x
	var dz := -sqrt(maxf(reach * reach - dx * dx, 0.0))
	return _to_body(Vector3(shoulder.x + dx, paw_y, shoulder.z + dz))


func _plant_paws() -> void:
	if _resting.get(_arm_l, false):
		_set_arm(_arm_l, rest_target(-1.0))
	if _resting.get(_arm_r, false):
		_set_arm(_arm_r, rest_target(1.0))


func present_hand_to(viewer: Vector3) -> void:
	# 第三人称:把牌扇移到右胸前并放大,牌面法线指向镜头、牌顶朝上,越肩即可看清点数
	# 按座位的静止姿态计算(登场缩放动画期间 global 坐标不可靠),并抵消坐姿前倾
	var seat_basis := global_basis.orthonormalized()
	var fan_seat := HIP + SELF_FAN_POS
	var fan_world := global_position + seat_basis * fan_seat
	var normal := (viewer - fan_world).normalized()
	var bottom := -(Vector3.UP - normal * Vector3.UP.dot(normal)).normalized()
	var world_basis := Basis(normal.cross(bottom), normal, bottom)
	hold_fan(_in_seat(Transform3D((seat_basis.inverse() * world_basis).scaled(Vector3.ONE * SELF_FAN_SCALE), fan_seat)))


func present_hand_first_person(seat: Transform3D, view: Transform3D, cam_offset := FP_FAN_CAM, fan_scale := FP_FAN_SCALE) -> void:
	# 第一人称:牌扇拿在镜头右下方(cam_offset),牌面正对眼睛、牌顶朝画面上方;之后每帧跟着眼睛平移
	# (探头、轮到自己前倾、呼吸都不会让牌在画面里挪动)。seat = 座位的静止变换,view = 脖子没探出时的第一人称机位
	_fan_mode = FAN_FP
	_fan_hold = first_person_fan(seat, view, cam_offset, fan_scale)
	_place_fan()


func hold_fan(xform: Transform3D) -> void:
	# 越肩:自己的牌扇停在 xform(身体局部),不再跟着眼睛走、也不再立在桌面上空
	_fan_mode = FAN_HAND
	_fan_hold = xform
	fan.transform = xform


func rest_fan() -> void:
	# 牌扇回到默认的「立在两爪前方的桌面上空」(他人的牌扇;自己从越肩 / 第一人称的举牌位置放回去时用)
	_fan_mode = FAN_TABLE
	_place_fan()


func holds_fan_first_person() -> bool:
	return _fan_mode == FAN_FP


func fan_mode() -> int:
	return _fan_mode


static func fan_rest_transform(look := {}) -> Transform3D:
	# 纯函数:他人牌扇的静止摆放(座位坐标):FAN_SEAT_POS、上仰 FAN_TILT_DEG、缩放 FAN_SCALE,物种 LOOK 的 "fan" 可覆盖。
	# 牌扇节点里的牌按 CardTable.fan_slot / BombCatLayout.fan_slot 排开(新玩法的牌扇也挂在 Patron.fan 下即可,不用自己摆)
	var spec: Dictionary = look.get("fan", {})
	var tilt: float = spec.get("tilt", FAN_TILT_DEG)
	var s: float = spec.get("scale", FAN_SCALE)
	return Transform3D((CardTable.FAN_BASIS * Basis(Vector3.RIGHT, deg_to_rad(tilt))).scaled(Vector3.ONE * s),
		spec.get("pos", FAN_SEAT_POS))


func table_fan_transform() -> Transform3D:
	# 此刻立在桌面上空的牌扇(座位坐标):静止摆放 + 身体的平移(吓一跳、庆祝蹦起、拆弹发抖、溜了侧挪时牌跟着动);
	# 探头往前时往前倒、平放到毡面上(fan_tucked)
	var rest := fan_rest_transform(_look_data).translated(body.position - HIP)
	var tuck := smoothstep(FAN_TUCK.x, FAN_TUCK.y, -_neck_offset.z) if alive else 0.0
	return fan_tucked(rest, tuck) if tuck > 0.0 else rest


static func fan_tucked(rest: Transform3D, amount: float, backward := false) -> Transform3D:
	# 纯函数:立着的牌扇(座位坐标)收起 amount(0 = 原样,1 = 收到底)。
	# 探头时(默认):不转、不往前伸,以中间那张的牌底为中心缩到 FAN_TUCK_SCALE、落到毡面上:矮下去让头和伸长的脖子从上面过,
	# 也不扫到前面桌上的东西(斗地主对手的出牌行)。
	# 出局时(backward):绕牌底往持牌者这边倒下、牌背朝上扣在桌上(身子已经往后仰开,爪子也离开了桌面)
	var top := (rest.basis * Vector3(0, 0, -1)).normalized()            # 牌顶方向(卡牌本地 −Z)
	var height := (rest.basis * Vector3(0, 0, Card3D.HEIGHT)).length()   # 牌高(含缩放)
	var pivot := rest.origin - top * height * 0.5                        # 中间那张牌的底边
	if not backward:
		var k := lerpf(1.0, FAN_TUCK_SCALE, amount)
		# 两侧的牌比中间低(扇形下沉 + 转角),缩小后仍让最低的牌角高出毡面
		var floor_y := SeatLayout.FELT_TOP + FAN_SAG * k + 0.004
		var low := Vector3(pivot.x, lerpf(pivot.y, floor_y, amount), pivot.z)
		return Transform3D(rest.basis.scaled_local(Vector3.ONE * k), low + (rest.origin - pivot) * k)
	var lean := asin(clampf(-top.z, -1.0, 1.0))                          # 牌顶已经往桌心倒了多少(弧度,前倾为正)
	var turn := Basis(Vector3.RIGHT, (PI / 2.0 + lean) * amount)
	# 扣着放时一层层往下叠(牌扇里后面的牌在下面):底边抬高一叠牌的厚度
	var drop := Vector3(0, (SeatLayout.FELT_TOP + FAN_STACK - pivot.y) * amount, 0.0)
	return Transform3D(turn * rest.basis, pivot + drop + turn * (rest.origin - pivot))


func fan_dead_transform() -> Transform3D:
	# 出局后扣在面前桌上的牌扇(座位坐标)
	return fan_tucked(fan_rest_transform(_look_data), 1.0, true)


func set_fan_stowed(on: bool) -> void:
	# 自己举着的牌扇(hold_fan / present_hand_first_person)收到桌面上空、矮下去;false 举回来。按 FAN_STOW_SPEED 平滑过渡。
	# SeatCamera 每帧按镜头在不在座位上调;立在桌面上空的牌扇(别人的)不受影响
	_fan_stow_target = 1.0 if on else 0.0


func is_fan_stowed() -> bool:
	return _fan_stow_target > 0.5


func _place_fan(delta := 0.0) -> void:
	# 每帧(_update_neck 末尾):立在桌面上空 / 第一人称两种模式按座位坐标摆,再换到身体局部(抵消前倾与呼吸缩放);
	# 举着的牌扇收起来时朝「桌面上空、矮下去」插过去
	_fan_stow = move_toward(_fan_stow, _fan_stow_target, FAN_STOW_SPEED * delta)
	var stowing := _fan_stow > 0.0 and alive and (_fan_mode == FAN_HAND or _fan_mode == FAN_FP)
	match _fan_mode:
		FAN_TABLE:
			fan.transform = body.transform.affine_inverse() * table_fan_transform()
		FAN_FP:
			if alive:
				var held := first_person_fan_now()
				if stowing:
					held = blend_transform(held, stowed_fan_transform(), smoothstep(0.0, 1.0, _fan_stow))
				fan.transform = body.transform.affine_inverse() * held
		FAN_HAND:
			if stowing:
				var held := blend_transform(body.transform * _fan_hold, stowed_fan_transform(), smoothstep(0.0, 1.0, _fan_stow))
				fan.transform = body.transform.affine_inverse() * held
			elif not fan.transform.is_equal_approx(_fan_hold):
				fan.transform = _fan_hold
		FAN_LAP:
			var xf: Transform3D
			if _fan_drop_from.origin == Vector3.INF:
				xf = fan_tucked(fan_rest_transform(_look_data), _fan_drop * _fan_drop, true)
			else:
				# 举在手里的牌:先往上、往桌心抛,再落到面前桌上(二次贝塞尔,起步快):往后仰倒的大头正朝举牌的肩头这边歪下来
				var to := fan_dead_transform()
				var from := _fan_drop_from
				var bend := from.origin + DIE_FAN_SWING
				var t := 1.0 - (1.0 - _fan_drop) * (1.0 - _fan_drop)
				var turn := from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), t)
				var size := from.basis.get_scale().lerp(to.basis.get_scale(), t)
				xf = Transform3D(Basis(turn).scaled(size), from.origin.lerp(bend, t).lerp(bend.lerp(to.origin, t), t))
			fan.transform = body.transform.affine_inverse() * xf


func stowed_fan_transform() -> Transform3D:
	# 收起来的牌扇(座位坐标):桌面上空的位置、矮下去(同探头时)
	return fan_tucked(fan_rest_transform(_look_data).translated(body.position - HIP), 1.0)


static func blend_transform(a: Transform3D, b: Transform3D, t: float) -> Transform3D:
	# 带缩放的变换插值:转角球面插值,缩放、位置线性插值
	var turn := a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), t)
	return Transform3D(Basis(turn).scaled(a.basis.get_scale().lerp(b.basis.get_scale(), t)), a.origin.lerp(b.origin, t))


func first_person_fan_now() -> Transform3D:
	# 第一人称手里的牌扇此刻在座位坐标里的变换:跟着眼睛平移;探头时以眼睛为中心收拢(FP_FAN_NEAR),画面不变
	var eye := eye_local()
	var xf := _fan_hold
	xf.origin += eye - rest_eye()
	var reach := Vector2(_neck_offset.x, _neck_offset.z).length()
	var k := lerpf(1.0, FP_FAN_NEAR, smoothstep(0.02, FP_FAN_PULL, reach))
	if k < 1.0:
		xf = Transform3D(xf.basis * k, eye + (xf.origin - eye) * k)
	return xf


static func first_person_fan(seat: Transform3D, view: Transform3D, cam_offset: Vector3, fan_scale: float) -> Transform3D:
	# 纯函数:第一人称手里的牌扇在座位坐标里的变换(德州的底牌也用它,只是 cam_offset 不同)。
	# 位置 = 机位 × cam_offset;牌面法线指向眼睛、牌顶朝镜头的上方;放大 fan_scale
	var fan_world := view * cam_offset
	var normal := (view.origin - fan_world).normalized()
	var up := view.basis.y.normalized()
	var bottom := -(up - normal * up.dot(normal)).normalized()
	var world_basis := Basis(normal.cross(bottom), normal, bottom)
	var seat_basis := seat.basis.orthonormalized()
	return Transform3D((seat_basis.inverse() * world_basis).scaled(Vector3.ONE * fan_scale),
		seat_basis.inverse() * (fan_world - seat.origin))


# —— 第一人称:藏起自己的头 ——

func set_head_hidden(hidden: bool) -> void:
	# 只在本机:头、眼、眉、耳、帽、脖子与挂在头上的表演件(汗珠、舌头……)不渲染,但照样投影(自己的影子还在桌上)。
	# 本来就不投影的(眼睛、眉、汗珠)挪到镜头不看的 LAYER_LOCAL_HIDDEN;藏着期间新挂到头上的东西(番茄印子等)也一并处理。
	# 恢复时按记下的原值放回,即使帽子已经被打飞、挂到了别处
	if hidden == _head_hidden:
		return
	_head_hidden = hidden
	if hidden:
		for root: Node in [head, _neck]:
			for node in root.find_children("*", "GeometryInstance3D", true, false):
				_hide_part(node)
		if is_inside_tree():
			get_tree().node_added.connect(_on_node_added)
	else:
		if is_inside_tree() and get_tree().node_added.is_connected(_on_node_added):
			get_tree().node_added.disconnect(_on_node_added)
		for node in _hidden_parts:
			if is_instance_valid(node):
				node.cast_shadow = _hidden_parts[node][0]
				node.layers = _hidden_parts[node][1]
		_hidden_parts.clear()


func is_head_hidden() -> bool:
	return _head_hidden


func _hide_part(node: GeometryInstance3D) -> void:
	if _hidden_parts.has(node) or not is_instance_valid(node):
		return
	_hidden_parts[node] = [node.cast_shadow, node.layers]
	if node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		node.layers = MeshKit.LAYER_LOCAL_HIDDEN   # 镜头不看这一层;它本来就不投影
	else:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


func _on_node_added(node: Node) -> void:
	# 延后一帧处理:挂件常在 add_child 之后才设 cast_shadow
	if node is GeometryInstance3D and (head.is_ancestor_of(node) or _neck.is_ancestor_of(node)):
		_hide_added.call_deferred(node)


func _hide_added(node: GeometryInstance3D) -> void:
	if _head_hidden and is_instance_valid(node) and (head.is_ancestor_of(node) or _neck.is_ancestor_of(node)):
		_hide_part(node)


func _exit_tree() -> void:
	set_head_hidden(false)


func pose_arms(left_target: Vector3, right_target: Vector3, duration: float, clear_face := false) -> Tween:
	# clear_face:手掌不许落进自己的大头里(见 clear_of_head);贴脸的动作(捂嘴、抹脸、举枪)不开
	var tween := create_tween().set_parallel()
	_tween_arm(tween, _arm_l, left_target, duration, Tween.TRANS_CUBIC, clear_face)
	_tween_arm(tween, _arm_r, right_target, duration, Tween.TRANS_CUBIC, clear_face)
	return tween


func pose_right(target: Vector3, duration: float, trans := Tween.TRANS_CUBIC, clear_face := false) -> Tween:
	var tween := create_tween()
	_tween_arm(tween, _arm_r, target, duration, trans, clear_face)
	return tween


func reach_toward_center() -> void:
	# 出牌手势:双手抬离桌面前推,再收回桌上
	if _arms_locked or not alive:
		return
	_arms_locked = true
	await pose_arms(_to_body(_mirror(REACH_POINT, -1.0)), _to_body(REACH_POINT), 0.22).finished
	await get_tree().create_timer(0.12).timeout
	_arms_locked = false
	rest_arms()


func slam_table() -> void:
	# 拍桌:抬手蓄力 → 砸下;在砸到桌面的瞬间返回,收手在后台进行
	if not alive:
		return
	_arms_locked = true
	set_expression("angry")
	await pose_right(HAND_RAISED, 0.2, Tween.TRANS_BACK, true).finished
	await pose_right(rest_target(1.0, SLAM_SPREAD), 0.08, Tween.TRANS_EXPO).finished
	_finish_slam()


func _finish_slam() -> void:
	await get_tree().create_timer(0.35).timeout
	_arms_locked = false
	rest_arms()


func cover_mouth(hold := COVER_MOUTH_HOLD) -> void:
	# 炸弹猫「偷看」:左爪捂着嘴偷乐一下再放回桌上;手被别的动作占着时只换个表情
	if not alive:
		return
	set_expression("smug")
	_antics.giggle(hold)
	if _arms_locked:
		return
	_arms_locked = true
	var tween := create_tween()
	_tween_arm(tween, _arm_l, head.position + COVER_MOUTH, 0.16)
	tween.tween_interval(hold)
	var serial := _arm_serial
	await tween.finished
	if alive and serial == _arm_serial:
		_arms_locked = false
		set_expression("neutral")
		rest_arms()


func snip_wires(duration := SNIP_TIME) -> void:
	# 炸弹猫「拆弹」:两只爪子在胸前手忙脚乱地比划(剪线),满头大汗;duration 之后在原地停住,
	# 由调用方接着 relief()(咔嚓,松一口气)。期间手不搭桌
	if not alive:
		return
	_arms_locked = true
	set_expression("worried")
	_antics.sweat(duration + 0.6)
	var tween := create_tween()
	var steps := maxi(int(duration / SNIP_STEP), 2)
	for i in steps:
		var side := 1.0 if i % 2 == 0 else -1.0
		var left := _to_body(SNIP_LEFT + Vector3(0.025 * side, 0.03 * side, 0.0))
		var right := _to_body(SNIP_RIGHT + Vector3(-0.03 * side, -0.025 * side, 0.01 * side))
		# 每一步左右手同时动(并行加进同一步),步与步之间用 0 秒的间隔隔开
		tween.set_parallel(true)
		_tween_arm(tween, _arm_l, left, SNIP_STEP, Tween.TRANS_SINE, true)
		_tween_arm(tween, _arm_r, right, SNIP_STEP, Tween.TRANS_SINE, true)
		tween.set_parallel(false)
		tween.tween_interval(0.0)
	var serial := _arm_serial
	await tween.finished
	if alive and serial == _arm_serial:
		_arms_locked = false
		rest_arms()


func sneak(duration := 0.6) -> void:
	# 炸弹猫「溜了」:身子往右一缩、踮脚往外挪一点(偷偷溜走),再弹回原位;只动身体的侧倾与左右位置(待机动画不碰这两个)
	if not alive:
		return
	set_expression("smug")
	var tween := create_tween()
	tween.tween_property(body, "rotation:z", -SNEAK_LEAN, duration * 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(body, "position:x", SNEAK_SHIFT, duration * 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(duration * 0.22)
	tween.tween_property(body, "rotation:z", 0.0, duration * 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(body, "position:x", HIP.x, duration * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	if alive:
		set_expression("neutral")


func bonk() -> void:
	# 炸弹猫「甩锅」:被平底锅当头一敲——头被拍扁再弹回(弹性),蚊香眼晕一下、耳朵炸开
	if not alive:
		return
	var tween := create_tween()
	tween.tween_property(head, "scale", BONK_SQUASH, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(head, "scale", Vector3.ONE, 0.55).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_antics.bonked(0.75)


func plead(hold := 0.9) -> void:
	# 炸弹猫「讨要」:双爪合十抵在下巴下、水汪汪的狗狗眼、歪着头;手被别的动作占着时只做表情
	if not alive:
		return
	set_expression("worried")
	_antics.plead(hold)
	if _arms_locked:
		return
	_arms_locked = true
	var tween := create_tween().set_parallel()
	_tween_arm(tween, _arm_l, head.position + _mirror(PLEAD_PAWS, -1.0), 0.16, Tween.TRANS_BACK)
	_tween_arm(tween, _arm_r, head.position + PLEAD_PAWS, 0.16, Tween.TRANS_BACK)
	tween.chain().tween_interval(hold)
	var serial := _arm_serial
	await tween.finished
	if alive and serial == _arm_serial:
		_arms_locked = false
		set_expression("neutral")
		rest_arms()


func peek_with_glass(hold := COVER_MOUTH_HOLD) -> void:
	# 炸弹猫「偷看」:右爪举着放大镜(放大镜由 BombCatFx 跟着右手摆)、左爪捂嘴偷乐;手被占着时只换表情
	if not alive:
		return
	set_expression("smug")
	_antics.giggle(hold)
	if _arms_locked:
		return
	_arms_locked = true
	var tween := create_tween().set_parallel()
	_tween_arm(tween, _arm_l, head.position + COVER_MOUTH, 0.16)
	_tween_arm(tween, _arm_r, head.position + PEEK_GLASS, 0.18, Tween.TRANS_BACK)
	tween.chain().tween_interval(hold)
	var serial := _arm_serial
	await tween.finished
	if alive and serial == _arm_serial:
		_arms_locked = false
		set_expression("neutral")
		rest_arms()


func hold_paws(left_seat: Vector3, right_seat: Vector3) -> void:
	# 吹牛骰子「摇盅」:两只爪子立刻按到这两点(座位坐标,扶在盅身两侧),骰盅层每帧跟着盅调用;
	# 期间手不搭桌、歇手补间不接管,直到 release_paws
	if not alive:
		return
	_arms_locked = true
	_resting = {}
	_arm_serial += 1
	_set_arm(_arm_l, _to_body(left_seat))
	_set_arm(_arm_r, _to_body(right_seat))


func release_paws() -> void:
	# 摇完扣下:手搭回桌上
	if not alive:
		return
	_arms_locked = false
	rest_arms()


func set_soot(amount: float, duration := 0.0) -> void:
	# 炸弹猫「爆炸」:头上的部件(脸、耳、吻……)盖上一层斑驳的黑灰(patron.gdshader 的实例参数 soot);0 = 干净
	var parts := _fade_targets.filter(func(t: GeometryInstance3D) -> bool: return is_instance_valid(t) and head.is_ancestor_of(t))
	if duration <= 0.0:
		for part in parts:
			part.set_instance_shader_parameter("soot", amount)
		return
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		for part in parts:
			if is_instance_valid(part):
				part.set_instance_shader_parameter("soot", v), 0.0, amount, duration)


func pick_up(gun: Node3D, duration: float) -> void:
	# 伸手到桌上的左轮,握住后挂到右手上(爪心 = 枪原点,枪管沿手的 −Z)。
	# 先放下视线:导演层刚让开枪者看自己的头,俯仰被夹住;这时清掉,举枪前头就回正了
	_arms_locked = true
	_has_look = false
	_steady = true
	var gun_local := body.to_local(gun.global_position)
	await pose_right(gun_local + Vector3(0, 0.03, 0), duration).finished
	gun.reparent(right_hand, true)
	_set_fist(true)
	var tween := create_tween()
	tween.tween_property(gun, "transform", Revolver3D.HOLD_OFFSET, 0.12)
	await tween.finished


func raise_gun_to_head(gun: Node3D, duration: float) -> void:
	# 手举到按物种净空求出的手位,再「转手不转枪」:枪相对手始终是 HOLD_OFFSET,拳头一直包着握把
	_sitting_up = true
	_has_look = false
	var tween := pose_right(gun_hand_target(_gun_clearance()), duration, Tween.TRANS_BACK)
	await tween.finished
	var aim := gun_pose(right_hand.global_position, head_position())
	# 身体呼吸是非均匀缩放:各个基先正交化
	var arm_basis := _arm_r.global_basis.orthonormalized()
	var hand_basis := arm_basis.inverse() * aim.basis * Revolver3D.HOLD_OFFSET.basis.inverse()
	var settle := create_tween()
	settle.tween_property(right_hand, "quaternion", hand_basis.orthonormalized().get_rotation_quaternion(), GUN_TWIST_TIME) \
		.set_trans(Tween.TRANS_SINE)
	set_expression("worried")
	await settle.finished


func _gun_clearance() -> float:
	return gun_clearance_for(species_index)


static func gun_clearance_for(index: int) -> float:
	# 物种的持枪净空(头心沿举枪方向到头部最外表面的距离,含毛、耳朵、帽子)
	var spec := PatronParts.species(index)
	if spec.has("gun_clearance"):
		return spec["gun_clearance"]
	var look := SpeciesLooks.look(index)
	if look.has("gun_clearance"):
		return look["gun_clearance"]
	return DEFAULT_GUN_CLEARANCE * head_scale()


static func head_scale() -> float:
	# 酒客头的等比缩放(子项目② 的大头版会加 PatronParts.HEAD_SCALE;没有时为 1.0)
	return float((PatronParts as Script).get_script_constant_map().get("HEAD_SCALE", 1.0))


static func gun_aim(origin: Vector3, center: Vector3) -> Basis:
	# 枪的朝向:枪管轴线(比枪原点高 BARREL_Y)穿过 center;定点迭代 3 次
	var aim := Basis.looking_at(center - origin, Vector3.UP)
	for i in 3:
		aim = Basis.looking_at(center - (origin + aim.y * Revolver3D.BARREL_Y), Vector3.UP)
	return aim


static func gun_pose(hand: Vector3, center: Vector3) -> Transform3D:
	# 握在 hand 处的枪对准 center 时的变换(枪原点 = 手位 + 手基 × HOLD_OFFSET,枪相对手不转)
	var aim := Basis.looking_at(center - hand, Vector3.UP)
	for i in 3:
		aim = gun_aim(hand + aim * Revolver3D.HOLD_OFFSET.origin, center)
	return Transform3D(aim, hand + aim * Revolver3D.HOLD_OFFSET.origin)


static func gun_hand_target(clearance: float) -> Vector3:
	# 纯函数(身体局部):名义头心 C0 = HEAD_PIVOT + (0, 0.12, 0);手在肩球面上沿 GUN_APPROACH 一族方向二分,
	# 使对准 C0 后 |枪口 − C0| = clearance + GUN_CLEARANCE
	var center := HEAD_PIVOT + Vector3(0, 0.12, 0)
	var want := clearance + GUN_CLEARANCE
	var lo := 0.25
	var hi := 2.0
	for i in 32:
		var mid := (lo + hi) * 0.5
		var hand := SHOULDER + (center + GUN_APPROACH * mid - SHOULDER).normalized() * ARM_LENGTH
		if (gun_pose(hand, center) * Revolver3D.MUZZLE_POS).distance_to(center) < want:
			lo = mid
		else:
			hi = mid
	return SHOULDER + (center + GUN_APPROACH * ((lo + hi) * 0.5) - SHOULDER).normalized() * ARM_LENGTH


func lower_gun(gun: Node3D, rest: Transform3D, table_parent: Node3D, duration: float) -> void:
	_sitting_up = false
	_steady = false
	set_expression("neutral")
	var untwist := create_tween()
	untwist.tween_property(right_hand, "quaternion", Quaternion.IDENTITY, duration)
	await pose_right(body.to_local(rest.origin) + Vector3(0, 0.03, 0), duration).finished
	gun.reparent(table_parent, true)
	_set_fist(false)
	var tween := create_tween()
	tween.tween_property(gun, "global_transform", rest, 0.15)
	await tween.finished
	_arms_locked = false
	rest_arms()


func relief() -> void:
	set_expression("happy")
	_antics.relief()
	var tween := create_tween()
	tween.tween_property(body, "position:y", HIP.y - 0.03, 0.25).set_trans(Tween.TRANS_SINE)
	tween.tween_property(body, "position:y", HIP.y, 0.4).set_trans(Tween.TRANS_SINE)


# —— 出局 / 庆祝 / 进出场 ——

func die(gun: Node3D = null, table_parent: Node3D = null) -> void:
	stop_dance()
	alive = false
	_arms_locked = true
	_stop_wipe()
	_eye.set_instance_shader_parameter("dead", 1.0)
	_set_fist(false)
	if gun != null and table_parent != null:
		gun.reparent(table_parent, true)
		var drop := create_tween()
		# 侧放(REST_ROLL:转轮与底帽同时着地),最低点在毡面上
		var landing := global_transform * Vector3(GUN_DROP.x, SeatLayout.FELT_TOP + Revolver3D.REST_HALF_WIDTH, GUN_DROP.z)
		drop.tween_property(gun, "global_position", landing, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		drop.parallel().tween_property(gun, "rotation", Vector3(0, gun.rotation.y + 1.8, PI / 2.0 + Revolver3D.REST_ROLL), 0.45)
	right_hand.quaternion = Quaternion.IDENTITY
	_steady = false
	var fall := create_tween().set_parallel()
	var body_rot: Vector3 = _look_data.get("anim", {}).get("die_body_rot", DIE_BODY_ROT)   # 乌龟侧倒,龟壳不穿椅背
	fall.tween_property(body, "rotation", body_rot, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 头往后仰、歪向一边(动森式大头往前栽会砸进自己的牌扇),脸朝上,头顶转星星
	fall.tween_property(head, "rotation", DIE_HEAD_ROT, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween_arm(fall, _arm_l, _mirror(HAND_DEAD, -1.0), 0.5, Tween.TRANS_BOUNCE)
	_tween_arm(fall, _arm_r, HAND_DEAD, 0.5, Tween.TRANS_BOUNCE)
	_knock_hat_off()
	_fan_alive = [_fan_mode, fan.transform if _fan_mode != FAN_FP else _fan_hold]
	_fan_drop_from = Transform3D(Basis(), Vector3.INF) if _fan_mode == FAN_TABLE else body.transform * fan.transform
	_fan_mode = FAN_LAP
	_fan_drop = 0.0
	fall.tween_property(self, "_fan_drop", 1.0, DIE_FAN_TIME)   # 立着的牌按 ease-in 倒下(在 _place_fan 里换算),举着的按 ease-out 送走
	fall.tween_method(_set_fade, 0.0, 1.0, FADE_TIME)
	if not _look_data.get("tail", {}).is_empty():
		fall.tween_method(func(v: float): _legs.set_instance_shader_parameter("tail",
			Vector4(_phase, _look_data["tail"].get("sway", 0.12), v, 0.0)), 0.0, 1.0, FADE_TIME)
	_antics.die()


func _set_fade(value: float) -> void:
	for target in _fade_targets:
		if is_instance_valid(target):
			target.set_instance_shader_parameter("fade", value)


func _knock_hat_off() -> void:
	if _hat == null:
		return
	var hat := _hat
	_hat = null
	var start := hat.global_position
	var landing := global_transform * Vector3(-0.35, 0.05, 0.45)
	# 重名的节点在 reparent 后会被改名,不能靠名字找回:打上散落物标记
	hat.add_to_group(DEBRIS_GROUP)
	hat.reparent(get_parent(), true)
	var tween := hat.create_tween()
	tween.tween_method(func(t: float):
		hat.global_position = start.lerp(landing, t) + Vector3.UP * sin(t * PI) * 0.45
		hat.rotation = Vector3(t * 4.0, t * 2.0, t * 1.4),
		0.0, 1.0, 0.8).set_ease(Tween.EASE_IN)


func celebrate() -> void:
	# 举起双手、原地蹦几下;蹦完解除动作锁(双手仍举着,直到下次持牌或 reset_pose)
	if not alive:
		return
	_arms_locked = true
	_sitting_up = true
	set_expression("happy")
	var bounce := create_tween().set_loops(CHEER_BOUNCES)
	bounce.tween_property(body, "position:y", HIP.y + CHEER_JUMP, CHEER_BOUNCE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bounce.tween_property(body, "position:y", HIP.y, CHEER_BOUNCE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_cheer_tweens = [bounce, pose_arms(_mirror(HAND_CHEER, -1.0), HAND_CHEER, 0.3, true)]
	_antics.celebrate()
	await bounce.finished
	_arms_locked = false


func reset_pose() -> void:
	# 回到等待厅 / 新一局开始:停下庆祝与舞步,解除动作锁,恢复中性表情、前倾坐姿、双手搭回桌上
	stop_dance()
	_kill_cheer()
	_stop_wipe()
	_arms_locked = false
	_sitting_up = false
	_neck_target = Vector3.ZERO
	set_expression("neutral")
	_set_fist(false)
	right_hand.quaternion = Quaternion.IDENTITY
	_steady = false
	set_head_hidden(false)   # 镜头若仍在第一人称,SeatCamera 下一帧再藏
	body.position = HIP
	head.scale = Vector3.ONE   # 炸弹猫被平底锅拍扁的头弹回原样
	if _fan_alive != null:
		_fan_mode = _fan_alive[0]
		if _fan_mode == FAN_HAND:
			fan.transform = _fan_alive[1]
		_fan_hold = _fan_alive[1]
		_fan_alive = null
	_place_fan()
	rest_arms(false)
	_antics.reset()


func _kill_cheer() -> void:
	for tween in _cheer_tweens:
		if tween.is_valid():
			tween.kill()
	_cheer_tweens = []


# —— 结算庆祝(规格 2026-10-09-winner-celebration)——

func dance(routine := -1, seed_value := 0) -> void:
	# 胜者跳舞,一直跳到 stop_dance / reset_pose;routine < 0 时按物种与种子挑一支(PatronDance.pick)。
	# 坐直、眯眼笑(^ ^)、挑眉,手臂、身体、头、帽子由 PatronDance 逐帧接管
	if not alive:
		return
	if routine < 0:
		routine = PatronDance.pick(species_index, seed_value)
	_start_dance(routine, seed_value)
	set_expression("happy")
	_antics._eye_to("joy", 1.0, 0.15)
	_antics._ears_to(-0.3, 0.08, 0.3)


func clap(seed_value := 0) -> void:
	# 没赢的人坐直了鼓掌(一阵一阵地拍,歇的时候偶尔挥拳),笑着看胜者
	if not alive:
		return
	_start_dance(PatronDance.CLAP, seed_value)
	set_expression("happy")


func twitch(seed_value := 0) -> void:
	# 出局倒着的人:隔一会儿抽一下手(仍然倒着、褪着色)
	if alive:
		return
	stop_dance()
	_dance = PatronDance.new()
	_dance.setup(self, PatronDance.TWITCH, seed_value)
	add_child(_dance)


func _start_dance(routine: int, seed_value: int) -> void:
	stop_dance()
	_kill_cheer()
	_stop_wipe()
	_arms_locked = true
	_sitting_up = true
	_arm_serial += 1   # 还没走完的歇手补间不再把手标成「搭在桌上」
	_dance = PatronDance.new()
	_dance.setup(self, routine, seed_value)
	add_child(_dance)


func stop_dance() -> void:
	# 收起舞步 / 鼓掌 / 抽手:帽子、腿、身体、耳朵、尾巴、牌扇复原;活着的人坐回去、双手搭回桌上。没在跳时什么也不做
	if _dance == null:
		return
	var was := _dance
	_dance = null
	if is_instance_valid(was):
		was.restore()
		remove_child(was)
		was.queue_free()
	if alive:
		_arms_locked = false
		_sitting_up = false
		_antics._eye("joy", 0.0)
		set_expression("neutral")
		rest_arms(false)


func is_dancing() -> bool:
	# 正在跳舞(胜者);鼓掌、抽手不算
	return _dance != null and _dance.is_dance()


func dance_routine() -> int:
	# 当前的庆祝动作(PatronDance 的枚举);没有时 -1
	return _dance.routine if _dance != null else -1


func startle() -> void:
	# 被吓一跳(有人喊「骗子!」拍桌、旁边有人中枪):原地一蹦、眼睛瞪圆、帽子弹起、耳朵炸开
	_antics.startle()


# —— 丢番茄与说话(规格 2026-10-08 丢番茄与快捷语 §5)——

func can_throw() -> bool:
	# 活着、手没被别的动作占着(举枪、拍桌、庆祝、抹脸)才做抛的动作;否则番茄直接从手里飞出去
	return alive and not _arms_locked


func throw_at(target: Vector3) -> void:
	# 右手往后上方蓄力 THROW_WINDUP 秒,再甩向目标(番茄在蓄力结束时出手,由 BanterFx 按同一时长放开)
	if not can_throw():
		return
	_arms_locked = true
	var windup := pose_right(HAND_WINDUP, THROW_WINDUP, Tween.TRANS_SINE, true)
	var serial := _arm_serial
	await windup.finished
	if not alive or serial != _arm_serial:
		return   # 期间出局或有别的手臂动作接管(举枪、复位……):交给它们收尾
	pose_right(body.to_local(target), THROW_FLING, Tween.TRANS_EXPO, true)
	serial = _arm_serial
	await get_tree().create_timer(THROW_FLING + THROW_RECOVER).timeout
	if alive and serial == _arm_serial:
		_arms_locked = false
		rest_arms()


func hit_by_tomato(_local_point: Vector3) -> void:
	# 被番茄砸中:吓一跳、眯眼嫌弃、摇头吐舌,手空着就用左爪抹一下脸;出局的不反应(番茄泥照样贴上)
	if not alive:
		return
	_antics.startle()
	if _sitting_up:
		return   # 举着枪、正在庆祝:只吓一跳,不打断动作
	_antics.disgust()
	if not _arms_locked:
		_wipe_face()


func _wipe_face() -> void:
	_arms_locked = true
	_stop_wipe()
	var face := head.position + WIPE_FACE
	var tween := create_tween()
	_wipe_tween = tween
	tween.tween_interval(0.12)   # 先愣一下
	_tween_arm(tween, _arm_l, face, 0.16)
	for side in [1.0, -1.0, 1.0]:
		_tween_arm(tween, _arm_l, face + Vector3(0.07 * side, 0.025, 0.0), 0.09, Tween.TRANS_SINE)
	var serial := _arm_serial
	await tween.finished
	if _wipe_tween != tween:
		return
	_wipe_tween = null
	if alive and serial == _arm_serial:   # 期间没有别的手臂动作(举枪、拍桌)接管
		_arms_locked = false
		rest_arms()


func _stop_wipe() -> void:
	if _wipe_tween != null and _wipe_tween.is_valid():
		_wipe_tween.kill()
	_wipe_tween = null


func talk(syllable_times: PackedFloat32Array) -> void:
	# 说话:头随每个音节轻点一下(出局的人照样能说,只是不点头)
	if alive:
		_antics.talk(syllable_times)


func skull_ellipsoid() -> Array:
	# 头部主颅骨的椭球 [中心, 半轴](Head 局部坐标,已含 Q 版放大):番茄落点、番茄泥贴在它表面上
	var skull: Array = _look_data["head"]["skull"][0]
	return [PatronParts.head_point(_look_data, skull[0]), skull[1] * PatronParts.head_scale(_look_data)]


func appear() -> void:
	scale = Vector3.ONE * 0.01
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Fx.smoke_puff(get_parent(), global_position + Vector3(0, 0.9, 0), 14, Color(0.9, 0.85, 0.78))


func vanish() -> void:
	Fx.smoke_puff(get_parent(), global_position + Vector3(0, 0.9, 0), 14, Color(0.9, 0.85, 0.78))
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


# —— 工具 ——

func _set_arm(arm: Node3D, target: Vector3) -> void:
	arm.quaternion = _arm_quat(arm, target)


func _tween_arm(tween: Tween, arm: Node3D, target: Vector3, duration: float, trans := Tween.TRANS_CUBIC, clear_face := false) -> void:
	_resting[arm] = false
	_arm_serial += 1
	tween.tween_property(arm, "quaternion", _arm_quat(arm, target, clear_face), maxf(duration, 0.001)) \
		.set_trans(trans).set_ease(Tween.EASE_IN_OUT if trans != Tween.TRANS_BACK else Tween.EASE_OUT)


func _arm_quat(arm: Node3D, target: Vector3, clear_face := false) -> Quaternion:
	var dir := target - arm.position
	if clear_face:
		dir = clear_of_head(arm.position, dir)
	var up := Vector3.UP if absf(dir.normalized().dot(Vector3.UP)) < 0.95 else Vector3.BACK
	return Basis.looking_at(dir, up).get_rotation_quaternion()


func clear_of_head(shoulder: Vector3, dir: Vector3) -> Vector3:
	# 穿模修复 2026-10-10:单节直臂指向 dir(身体局部)时,手掌在肩外一臂长处;若落进自己大头的椭球(head_metrics 的
	# 半宽、帽顶、下巴、前后,随头的转动与缩放,外扩爪子半径 PAW_CLEAR),沿头心径向推到椭球表面外,返回新的方向。
	# 欢呼、跳舞、鼓掌、拍桌抬手、丢番茄、拆弹用(大头比 Q 版大一倍,原来调好的举手位置会插进脸颊、耳朵、帽檐)
	var m := head_metrics()
	var center := PatronParts.HEAD_CENTER
	var paw := shoulder + dir.normalized() * ARM_LENGTH
	for i in 3:
		var local := head.transform.affine_inverse() * paw - center
		var radii := Vector3(m["rx"], m["above"] if local.y > 0.0 else m["below"], m["front"] if local.z < 0.0 else m["back"])
		var scaled := local / (radii + Vector3.ONE * PAW_CLEAR)
		var k := scaled.length()
		if k >= 1.0:
			break
		var out := local / maxf(k, 0.05) if k > 0.0001 else Vector3(0, radii.y + PAW_CLEAR, 0)
		paw = shoulder + (head.transform * (out + center) - shoulder).normalized() * ARM_LENGTH
	return paw - shoulder


func _to_body(seat_point: Vector3) -> Vector3:
	return body.transform.affine_inverse() * seat_point


static func _in_seat(seat_xform: Transform3D) -> Transform3D:
	# 座位坐标 → 前倾坐姿下的身体局部坐标:挂在身体上的东西坐着时停在座位里调好的位置
	return Transform3D(Basis(Vector3.RIGHT, -SEATED_LEAN), HIP).affine_inverse() * seat_xform


static func _mirror(v: Vector3, side: float) -> Vector3:
	return Vector3(v.x * side, v.y, v.z)
