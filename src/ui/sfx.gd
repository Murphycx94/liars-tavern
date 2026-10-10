extends Node
# 程序化音效(autoload "Sfx"):运行时合成全部音效,无需音频文件。
# 启动后逐帧预热生成,首次播放未生成的音效时即时生成。SFX 总线带轻微房间混响。


const RATE := 22050
const POOL_SIZE := 12
const BUS := "SFX"
const AMBIENCE_SECONDS := 6.0
const AMBIENCE_CROSSFADE := 0.4
const VOLUMES := {
	"deal": -10.0, "slide": -8.0, "slap": -6.0, "flip": -8.0, "sweep": -9.0, "slam": -2.0,
	"bell": -6.0, "cock": -4.0, "spin": -5.0, "click": -2.0, "bang": 0.0, "heartbeat": -3.0,
	"ui_click": -14.0, "ui_hover": -22.0, "whoosh": -12.0, "sting_lie": -6.0, "sting_truth": -8.0,
	"win": -6.0, "join": -10.0, "thud": -4.0,
	"chips": -9.0, "chips_push": -7.0, "fold": -14.0,   # 德州:筹码碰撞 / 全下推筹码 / 轻推牌(规格 §6.7)
	"tomato_throw": -12.0, "tomato_splat": -4.0,        # 丢番茄:出手的短 whoosh / 湿的「啪叽」
	# 炸弹猫:导火索嘶嘶 / 爆炸(比枪声更闷更大)/ 剪线咔嚓 / 「不行!」拍桌 / 洗牌哗哗
	"fuse": -9.0, "boom": 0.0, "snip": -4.0, "nope_slap": -3.0, "riffle": -9.0,
	# 结算庆祝:礼炮「砰」+ 纸屑沙沙 / 开场的小号「哒哒哒—哒!」/ 一阵掌声
	"cannon_pop": -5.0, "fanfare": -8.0, "applause": -15.0,
	"quip": -11.0,                                      # 快捷对话:轻快的两声「啵」
	# 炸弹猫道具效果(规格 2026-10-10):平底锅「当」/ 弹簧「啵嘤」/ 盖章「砰」/ 洗牌龙卷风 / 叮铃闪光 / 小气泡「啵」/
	# 溜走的滑哨「嗖」/ 踮脚小碎步 / 松一口气「呼」
	"bonk": -6.0, "boing": -9.0, "stamp": -3.0, "tornado": -10.0, "sparkle": -14.0, "pop": -12.0, "sneak": -11.0,
	"tiptoe": -15.0, "sigh": -12.0,
	# 吹牛骰子:骰盅里哗啦哗啦 / 扣盅「啪」/ 开盅骰子磕碰 / 丢骰子「啵」/ 计数「叮」/ 掀盅沿偷看
	"dice_shake": -8.0, "cup_slam": -4.0, "dice_clack": -9.0, "die_pop": -8.0, "count_tick": -13.0, "dice_peek": -16.0,
	# 斗地主:牌拍在桌上「啪」/ 不出时敲桌两下 / 叫分的木鱼「笃」/ 小火箭升空的「咻——」/ 烟花「砰啪」/ 纸飞机滑翔 /
	# 春天的风铃 / 只剩一两张时的「叮叮」报警(炸弹沿用炸弹猫的 boom)
	"card_slap": -5.0, "knock": -8.0, "bid": -9.0, "rocket": -9.0, "firework": -8.0, "plane": -12.0, "chime": -9.0, "alarm": -12.0,
}
const CHIP_CLATTER_COUNT := 4         # 一次下注落下几枚筹码的碰撞声
const CHIP_PUSH_COUNT := 14           # 全下推一整摞
const CHIP_CLICK_SECONDS := 0.035
const CHIP_FREQ := Vector2(1900.0, 3400.0)   # 筹码是硬塑料:比金属咔哒低、比牌纸脆

var muted := false
var _headless := false
var _cache := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _ambience: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_setup_bus()
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = BUS
		add_child(player)
		_players.append(player)
	_ambience = AudioStreamPlayer.new()
	_ambience.volume_db = -20.0
	add_child(_ambience)
	if DisplayServer.get_name() == "headless":
		# 无头模式没有音频输出(哑驱动也不回收回放对象),始终静音并跳过合成
		_headless = true
		muted = true
		return
	_warm_up()


func shutdown() -> void:
	# 退出前调用:停止播放并释放音频流。音频线程异步回收回放对象,调用方需再等两帧再退出
	for player in _players + [_ambience]:
		player.stop()
		player.stream = null
	_cache = {}


func play(sound: String, pitch_jitter := 0.04) -> void:
	if muted:
		return
	var player := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	player.stream = _stream(sound)
	player.volume_db = VOLUMES.get(sound, -6.0)
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	player.play()


func start_ambience() -> void:
	if _ambience.playing or muted:
		return
	_ambience.stream = _stream("ambience")
	_ambience.play()


func set_muted(value: bool) -> void:
	# 无头模式忽略取消静音。静音启动时环境音没开过,取消静音时补上
	muted = value or _headless
	AudioServer.set_bus_mute(0, muted)
	if not muted:
		start_ambience()


func _setup_bus() -> void:
	if AudioServer.get_bus_index(BUS) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, BUS)
	AudioServer.set_bus_send(idx, "Master")
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.45
	reverb.damping = 0.6
	reverb.wet = 0.16
	reverb.dry = 0.95
	AudioServer.add_bus_effect(idx, reverb)


func _warm_up() -> void:
	for sound in VOLUMES.keys() + ["ambience"]:
		await get_tree().process_frame
		_stream(sound)


func _stream(sound: String) -> AudioStreamWAV:
	if not _cache.has(sound):
		_cache[sound] = _synth(sound)
	return _cache[sound]


# —— 合成 ——

func _synth(sound: String) -> AudioStreamWAV:
	match sound:
		"deal":
			return _wav(_noise_burst(0.07, 0.25, 0.004))
		"slide":
			return _wav(_noise_burst(0.16, 0.18, 0.03))
		"slap":
			return _wav(_mix([_noise_burst(0.05, 0.5, 0.001), _thump(130.0, 0.08, 0.7)]))
		"flip":
			return _wav(_mix([_noise_burst(0.05, 0.35, 0.002), _offset(_noise_burst(0.03, 0.5, 0.001), 0.04)]))
		"sweep":
			return _wav(_noise_burst(0.35, 0.12, 0.08))
		"slam":
			return _wav(_mix([_thump(70.0, 0.3, 1.0), _noise_burst(0.12, 0.6, 0.001), _rattle(0.35)]))
		"bell":
			return _wav(_bell(880.0, 1.6))
		"cock":
			return _wav(_mix([_metal_click(0.6), _offset(_metal_click(0.8), 0.09)]))
		"spin":
			return _wav(_ratchet(1.0))
		"click":
			return _wav(_mix([_metal_click(1.0), _thump(300.0, 0.04, 0.4)]))
		"bang":
			return _wav(_gunshot())
		"heartbeat":
			return _wav(_mix([_thump(52.0, 0.14, 1.0), _offset(_thump(46.0, 0.16, 0.8), 0.2)]))
		"ui_click":
			return _wav(_metal_click(0.4))
		"ui_hover":
			return _wav(_thump(900.0, 0.03, 0.3))
		"whoosh":
			return _wav(_whoosh(0.5))
		"sting_lie":
			return _wav(_mix([_saw_note(110.0, 0.35, 0.6), _offset(_saw_note(98.0, 0.7, 0.7), 0.3)]))
		"sting_truth":
			return _wav(_mix([_bell(523.0, 0.8), _offset(_bell(659.0, 0.8), 0.1), _offset(_bell(784.0, 1.0), 0.2)]))
		"win":
			return _wav(_mix([_bell(523.0, 1.2), _offset(_bell(659.0, 1.2), 0.15), _offset(_bell(784.0, 1.2), 0.3),
				_offset(_bell(1046.0, 1.6), 0.45)]))
		"join":
			return _wav(_mix([_bell(659.0, 0.6), _offset(_bell(988.0, 0.7), 0.08)]))
		"thud":
			return _wav(_mix([_thump(60.0, 0.35, 1.0), _noise_burst(0.2, 0.2, 0.01)]))
		"chips":
			return _wav(_mix([_chip_clatter(CHIP_CLATTER_COUNT, 0.22), _thump(180.0, 0.05, 0.3)]))
		"chips_push":
			# 推筹码:一摞筹码在绒布上滑过(闷噪声)+ 密集的碰撞
			return _wav(_mix([_noise_burst(0.45, 0.1, 0.08), _offset(_chip_clatter(CHIP_PUSH_COUNT, 0.5), 0.05)]))
		"fold":
			return _wav(_noise_burst(0.11, 0.2, 0.02))
		"tomato_throw":
			return _wav(_whoosh_up(0.24))
		"tomato_splat":
			return _wav(_splat())
		"fuse":
			return _wav(_fuse(1.4))
		"boom":
			return _wav(_explosion())
		"snip":
			return _wav(_mix([_metal_click(0.9), _offset(_noise_burst(0.05, 0.75, 0.001), 0.012), _offset(_metal_click(0.5), 0.07)]))
		"nope_slap":
			return _wav(_mix([_noise_burst(0.06, 0.6, 0.001), _thump(105.0, 0.14, 1.0), _rattle(0.28)]))
		"riffle":
			return _wav(_riffle(0.75))
		"cannon_pop":
			return _wav(_cannon_pop())
		"fanfare":
			return _wav(_fanfare())
		"applause":
			return _wav(_applause(2.8))
		"quip":
			return _wav(_mix([_thump(520.0, 0.05, 0.4), _offset(_bell(1175.0, 0.3), 0.04), _offset(_bell(1568.0, 0.25), 0.1)]))
		"bonk":
			return _wav(_mix([_pan_ring(), _thump(170.0, 0.09, 0.8), _metal_click(0.5)]))
		"boing":
			return _wav(_boing(0.5))
		"stamp":
			return _wav(_mix([_thump(78.0, 0.3, 1.0), _noise_burst(0.05, 0.7, 0.001), _offset(_thump(150.0, 0.08, 0.5), 0.01), _rattle(0.2)]))
		"tornado":
			return _wav(_mix([_swirl(1.15), _offset(_riffle(0.45), 0.08), _offset(_riffle(0.4), 0.72)]))
		"sparkle":
			return _wav(_mix([_bell(1568.0, 0.35), _offset(_bell(2093.0, 0.35), 0.05), _offset(_bell(2637.0, 0.35), 0.1),
				_offset(_bell(3136.0, 0.45), 0.15)]))
		"pop":
			return _wav(_mix([_blip(520.0, 980.0, 0.07, 0.8), _noise_burst(0.015, 0.6, 0.001)]))
		"sneak":
			return _wav(_mix([_blip(520.0, 1500.0, 0.26, 0.45), _whoosh_up(0.22)]))
		"tiptoe":
			return _wav(_mix([_thump(880.0, 0.03, 0.35), _offset(_thump(990.0, 0.03, 0.3), 0.11), _offset(_thump(930.0, 0.03, 0.3), 0.22)]))
		"sigh":
			return _wav(_sigh(0.55))
		"dice_shake":
			return _wav(_dice_rattle(0.85, 6.5))
		"cup_slam":
			return _wav(_mix([_thump(88.0, 0.26, 1.0), _noise_burst(0.07, 0.35, 0.001), _offset(_dice_clicks(4, 0.16, 0.5), 0.02)]))
		"dice_clack":
			return _wav(_mix([_dice_clicks(9, 0.34, 0.75), _noise_burst(0.12, 0.15, 0.01)]))
		"die_pop":
			return _wav(_mix([_blip(380.0, 1250.0, 0.11, 0.85), _offset(_dice_clicks(1, 0.04, 0.6), 0.0)]))
		"count_tick":
			return _wav(_mix([_bell(1320.0, 0.22), _thump(660.0, 0.03, 0.25)]))
		"dice_peek":
			return _wav(_mix([_noise_burst(0.14, 0.08, 0.04), _offset(_dice_clicks(2, 0.08, 0.3), 0.03)]))
		"card_slap":
			return _wav(_mix([_noise_burst(0.04, 0.65, 0.0008), _thump(160.0, 0.07, 0.8), _offset(_noise_burst(0.03, 0.3, 0.002), 0.012)]))
		"knock":
			return _wav(_mix([_thump(210.0, 0.07, 0.9), _noise_burst(0.02, 0.4, 0.001),
				_offset(_mix([_thump(190.0, 0.07, 0.8), _noise_burst(0.02, 0.4, 0.001)]), 0.14)]))
		"bid":
			return _wav(_mix([_thump(620.0, 0.09, 0.7), _offset(_bell(1240.0, 0.25), 0.005)]))
		"rocket":
			return _wav(_mix([_whoosh_up(0.6), _blip(400.0, 1800.0, 0.6, 0.25)]))
		"firework":
			return _wav(_firework())
		"plane":
			return _wav(_mix([_whoosh(0.9), _blip(700.0, 520.0, 0.9, 0.12)]))
		"chime":
			return _wav(_mix([_bell(1047.0, 1.0), _offset(_bell(1319.0, 1.0), 0.12), _offset(_bell(1568.0, 1.0), 0.24),
				_offset(_bell(2093.0, 1.2), 0.36), _offset(_bell(1568.0, 0.9), 0.5)]))
		"alarm":
			return _wav(_mix([_bell(1760.0, 0.18), _offset(_bell(1397.0, 0.18), 0.16), _offset(_bell(1760.0, 0.2), 0.32)]))
		"ambience":
			return _ambience_stream()
	push_warning("未知音效:" + sound)
	return _wav(PackedFloat32Array([0.0]))


func _ambience_stream() -> AudioStreamWAV:
	var loop := _ambience_loop(AMBIENCE_SECONDS)
	var wav := _wav(loop)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = loop.size()  # 末尾已交叉淡化进开头并截掉:整段采样正好一圈
	return wav


func _noise_burst(duration: float, cutoff: float, attack: float) -> PackedFloat32Array:
	# cutoff 为一阶低通系数(0..1):越小越闷
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := minf(t / maxf(attack, 0.0001), 1.0) * pow(1.0 - float(i) / n, 2.0)
		y += cutoff * (_rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * env * 1.6
	return out


func _thump(freq: float, duration: float, gain: float) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := freq * (1.0 + (1.0 - t) * 0.6)
		phase += TAU * f / RATE
		out[i] = sin(phase) * exp(-t * 5.0) * gain
	return out


func _metal_click(gain: float) -> PackedFloat32Array:
	var n := int(0.05 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 140.0)
		out[i] = (sin(TAU * 3100.0 * t) * 0.6 + sin(TAU * 5200.0 * t) * 0.3 + _rng.randf_range(-1, 1) * 0.5) * env * gain
	return out


func _ratchet(duration: float) -> PackedFloat32Array:
	# 转轮:间隔渐长的棘轮咔哒声
	var out := PackedFloat32Array()
	out.resize(int(duration * RATE))
	var t := 0.0
	var gap := 0.035
	while t < duration - 0.05:
		var click := _metal_click(0.5)
		var start := int(t * RATE)
		for i in click.size():
			if start + i < out.size():
				out[start + i] += click[i]
		t += gap
		gap *= 1.16
	return out


func _chip_clatter(count: int, duration: float) -> PackedFloat32Array:
	# 几枚筹码先后落下:每枚一声短促的双音敲击,时间与音高都带一点随机
	var out := PackedFloat32Array()
	out.resize(int(duration * RATE))
	var click_len := int(CHIP_CLICK_SECONDS * RATE)
	for k in count:
		var start := int(_rng.randf_range(0.0, duration - CHIP_CLICK_SECONDS) * RATE)
		var freq := _rng.randf_range(CHIP_FREQ.x, CHIP_FREQ.y)
		var gain := _rng.randf_range(0.35, 0.7)
		for i in click_len:
			if start + i < out.size():
				var t := float(i) / RATE
				out[start + i] += (sin(TAU * freq * t) * 0.6 + sin(TAU * freq * 1.9 * t) * 0.3) * exp(-t * 160.0) * gain
	return out


func _bell(freq: float, duration: float) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var partials := [[1.0, 1.0], [2.0, 0.5], [2.76, 0.35], [5.4, 0.15]]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for p in partials:
			v += sin(TAU * freq * p[0] * t) * p[1] * exp(-t * (2.2 + p[0] * 0.9))
		out[i] = v * 0.4 * minf(t * 400.0, 1.0)
	return out


func _saw_note(freq: float, duration: float, gain: float) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var saw := fmod(t * freq, 1.0) * 2.0 - 1.0 + (fmod(t * freq * 1.006, 1.0) * 2.0 - 1.0)
		y += 0.08 * (saw - y)
		var env := minf(t * 30.0, 1.0) * exp(-t * 2.5)
		out[i] = y * env * gain
	return out


func _rattle(duration: float) -> PackedFloat32Array:
	# 拍桌时杯瓶轻颤
	var out := PackedFloat32Array()
	out.resize(int(duration * RATE))
	for k in 5:
		var start := int(_rng.randf_range(0.02, duration - 0.06) * RATE)
		var freq := _rng.randf_range(2200.0, 4200.0)
		for i in int(0.04 * RATE):
			if start + i < out.size():
				var t := float(i) / RATE
				out[start + i] += sin(TAU * freq * t) * exp(-t * 90.0) * 0.15
	return out


func _gunshot() -> PackedFloat32Array:
	var n := int(1.6 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var tail := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var crack := _rng.randf_range(-1.0, 1.0) * exp(-t * 38.0)
		phase += TAU * (40.0 + 110.0 * exp(-t * 9.0)) / RATE
		var boom := sin(phase) * exp(-t * 4.5) * 0.9
		tail += 0.04 * (_rng.randf_range(-1.0, 1.0) - tail)
		var rumble := tail * exp(-t * 2.2) * 2.2
		y = crack * 1.1 + boom + rumble
		out[i] = clampf(y, -1.0, 1.0)
	return out


func _fuse(duration: float) -> PackedFloat32Array:
	# 导火索:高通的嘶嘶声,夹着随机的噼啪
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var crackle := 0.0
	for i in n:
		var t := float(i) / n
		var white := _rng.randf_range(-1.0, 1.0)
		low += 0.08 * (white - low)
		if _rng.randf() < 0.004:
			crackle = _rng.randf_range(0.5, 1.0)
		crackle *= 0.985
		var env := minf(t / 0.05, 1.0) * (1.0 - t * 0.4)
		out[i] = ((white - low) * 0.45 + white * crackle * 0.8) * env
	return out


func _explosion() -> PackedFloat32Array:
	# 爆炸:比枪声低、闷、长——起头一记重低音往下滑,接着翻滚的低通隆隆声,几乎没有清脆的爆裂
	var n := int(2.4 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var rumble := 0.0
	var mid := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * (28.0 + 70.0 * exp(-t * 5.0)) / RATE
		var boom := sin(phase) * exp(-t * 2.2) * 1.1
		var white := _rng.randf_range(-1.0, 1.0)
		rumble += 0.025 * (white - rumble)
		mid += 0.12 * (white - mid)
		var noise := rumble * exp(-t * 1.3) * 3.2 + mid * exp(-t * 9.0) * 0.9
		out[i] = clampf((boom + noise) * minf(t / 0.004, 1.0), -1.0, 1.0)
	return out


func _riffle(duration: float) -> PackedFloat32Array:
	# 洗牌:一串越来越密的纸牌拍打声
	var out := PackedFloat32Array()
	out.resize(int(duration * RATE))
	var t := 0.0
	var gap := 0.05
	while t < duration - 0.03:
		var burst := _noise_burst(0.018, 0.55, 0.001)
		var start := int(t * RATE)
		for i in burst.size():
			if start + i < out.size():
				out[start + i] += burst[i] * _rng.randf_range(0.4, 0.8)
		t += gap * _rng.randf_range(0.7, 1.3)
		gap = maxf(gap * 0.9, 0.012)
	return out


func _cannon_pop() -> PackedFloat32Array:
	# 礼炮:一记往下滑的闷「砰」(像拔开瓶塞的大号版)+ 很短的爆裂噪声,随后一阵越来越稀的纸屑沙沙声
	var n := int(0.12 * RATE)
	var pop := PackedFloat32Array()
	pop.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * (320.0 * exp(-t * 30.0) + 90.0) / RATE
		pop[i] = sin(phase) * exp(-t * 26.0) * minf(t / 0.002, 1.0)
	var rustle := PackedFloat32Array()
	rustle.resize(int(0.9 * RATE))
	var t := 0.02
	var gap := 0.006
	while t < 0.85:
		var flick := _noise_burst(0.012, 0.75, 0.001)
		var start := int(t * RATE)
		var gain := _rng.randf_range(0.08, 0.22) * (1.0 - t / 0.9)
		for i in flick.size():
			if start + i < rustle.size():
				rustle[start + i] += flick[i] * gain
		t += gap * _rng.randf_range(0.5, 1.5)
		gap *= 1.07
	var out := _mix([pop, _thump(85.0, 0.28, 0.9), _noise_burst(0.05, 0.55, 0.001), _offset(rustle, 0.03)])
	for i in out.size():
		out[i] *= 0.6   # 几层的起音叠在同一刻:整体压一点,不削波
	return out


func _brass(freq: float, duration: float, gain: float) -> PackedFloat32Array:
	# 卡通小号:锯齿波过一阶低通,截止频率在起音后很快张开(铜管的「啪」)再慢慢收,带一点颤音
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += freq * (1.0 + 0.006 * sin(TAU * 5.5 * t) * minf(t / 0.15, 1.0)) / RATE
		var saw := fmod(phase, 1.0) * 2.0 - 1.0
		var bright := 0.06 + 0.3 * minf(t / 0.03, 1.0) * exp(-t * 3.0)
		y += bright * (saw - y)
		var env := minf(t / 0.015, 1.0) * (1.0 - smoothstep(duration - 0.06, duration, t))
		out[i] = y * env * gain
	return out


func _fanfare() -> PackedFloat32Array:
	# 开场小号「哒哒哒—哒!」:三个短 G4,接一个长的 C5,最后那下叠上 E5、G5 成大三和弦,外加一声小钟点缀
	var layers := []
	for k in 3:
		layers.append(_offset(_brass(392.0, 0.12, 0.42), 0.15 * k))
	layers.append(_offset(_brass(523.25, 0.8, 0.45), 0.45))
	layers.append(_offset(_brass(659.25, 0.8, 0.28), 0.45))
	layers.append(_offset(_brass(783.99, 0.8, 0.24), 0.45))
	layers.append(_offset(_bell(1046.5, 1.0), 0.45))
	return _mix(layers)


func _applause(duration: float) -> PackedFloat32Array:
	# 掌声:很多下短促的拍手(带通的噪声脆响),起头密、慢慢稀下来
	var out := PackedFloat32Array()
	out.resize(int(duration * RATE))
	var t := 0.0
	while t < duration - 0.05:
		var density := lerpf(70.0, 12.0, t / duration)
		var clap := _noise_burst(0.016, 0.55, 0.0008)
		var start := int(t * RATE)
		var gain := _rng.randf_range(0.25, 0.6) * (1.0 - 0.6 * t / duration)
		var prev := 0.0
		for i in clap.size():
			if start + i < out.size():
				var hp := clap[i] - prev   # 去掉低频,拍手更脆
				prev = clap[i]
				out[start + i] += (clap[i] * 0.4 + hp * 1.8) * gain
		t += _rng.randf_range(0.3, 1.7) / density
	return out


func _firework() -> PackedFloat32Array:
	# 烟花:一声闷「砰」+ 一串细碎的噼啪(随机的短噪声点,越来越稀)
	var layers := [_thump(90.0, 0.25, 1.0), _noise_burst(0.12, 0.5, 0.001)]
	var t := 0.08
	for k in 14:
		layers.append(_offset(_noise_burst(0.012, 0.85, 0.0005), t))
		t += _rng.randf_range(0.02, 0.07) * (1.0 + k * 0.12)
	return _mix(layers)


func _whoosh(duration: float) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		var cutoff := 0.03 + 0.12 * sin(t * PI)
		y += cutoff * (_rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * sin(t * PI) * 1.5
	return out


func _whoosh_up(duration: float) -> PackedFloat32Array:
	# 番茄出手:短促、越来越亮的风声
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		y += (0.04 + 0.22 * t) * (_rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * sin(t * PI) * pow(1.0 - t, 0.5) * 2.2
	return out


func _splat() -> PackedFloat32Array:
	# 番茄砸中:低频的「啪」+ 湿漉漉的滤波噪声尾巴(截止频率往下掉,像汁水摊开)+ 两三滴往下滑音的小水滴
	var n := int(0.42 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var cutoff := 0.05 + 0.4 * exp(-t * 22.0)
		y += cutoff * (_rng.randf_range(-1.0, 1.0) - y)
		var gurgle := 0.75 + 0.25 * sin(TAU * 31.0 * t)
		out[i] = y * gurgle * exp(-t * 9.0) * minf(t / 0.0015, 1.0) * 1.2
	var layers := [out, _thump(95.0, 0.12, 0.7)]
	for k in 3:
		layers.append(_offset(_drip(_rng.randf_range(700.0, 1100.0), 0.05, 0.18), 0.07 + k * _rng.randf_range(0.05, 0.08)))
	return _mix(layers)


func _pan_ring() -> PackedFloat32Array:
	# 平底锅被敲:几组不成谐波的分音(锅是一块厚铁片),低一点的「当~」带一点颤
	var n := int(0.9 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var partials := [[392.0, 1.0, 5.0], [910.0, 0.55, 7.0], [1665.0, 0.32, 10.0], [2598.0, 0.18, 14.0]]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for p in partials:
			v += sin(TAU * p[0] * t * (1.0 + 0.004 * sin(TAU * 6.0 * t))) * p[1] * exp(-t * p[2])
		out[i] = v * 0.42 * minf(t * 600.0, 1.0)
	return out


func _boing(duration: float) -> PackedFloat32Array:
	# 弹簧「啵嘤」:音高往上滑、颤音越来越小
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 190.0 + 330.0 * (1.0 - exp(-t * 6.0)) + 60.0 * sin(TAU * 13.0 * t) * exp(-t * 4.0)
		phase += TAU * f / RATE
		out[i] = (sin(phase) * 0.8 + sin(phase * 2.0) * 0.15) * exp(-t * 4.5) * minf(t * 300.0, 1.0) * 0.8
	return out


func _swirl(duration: float) -> PackedFloat32Array:
	# 龙卷风:风声的亮度一圈圈起伏(像绕着转),中间最响
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		var cutoff := (0.03 + 0.12 * sin(t * PI)) * (0.65 + 0.35 * sin(TAU * 7.0 * t * (0.6 + t)))
		y += cutoff * (_rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * sin(t * PI) * 1.8
	return out


func _blip(from_freq: float, to_freq: float, duration: float, gain: float) -> PackedFloat32Array:
	# 一声短促的上滑正弦(小气泡、滑哨)
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * lerpf(from_freq, to_freq, t * t) / RATE
		out[i] = sin(phase) * sin(t * PI) * gain
	return out


func _sigh(duration: float) -> PackedFloat32Array:
	# 松一口气:越来越闷的气声 + 一点往下走的哼声
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		y += (0.12 - 0.1 * t) * (_rng.randf_range(-1.0, 1.0) - y)
		phase += TAU * (330.0 - 120.0 * t) / RATE
		var env := minf(t * 8.0, 1.0) * pow(1.0 - t, 1.5)
		out[i] = (y * 1.4 + sin(phase) * 0.12) * env
	return out


func _dice_clicks(count: int, duration: float, gain: float) -> PackedFloat32Array:
	# 骰子磕碰:几声短促的木 / 塑料「嗒」(两个泛音,很快衰减),时间与音高带随机,越往后越轻
	var out := PackedFloat32Array()
	out.resize(int(duration * RATE) + int(0.03 * RATE))
	for k in count:
		var at := _rng.randf_range(0.0, duration) if count > 1 else 0.0
		var start := int(at * RATE)
		var freq := _rng.randf_range(1700.0, 3300.0)
		var g := gain * _rng.randf_range(0.5, 1.0) * (1.0 - 0.5 * at / maxf(duration, 0.001))
		for i in int(0.03 * RATE):
			if start + i < out.size():
				var t := float(i) / RATE
				out[start + i] += (sin(TAU * freq * t) * 0.55 + sin(TAU * freq * 2.3 * t) * 0.25 + _rng.randf_range(-1, 1) * 0.2) \
					* exp(-t * 220.0) * g
	return out


func _dice_rattle(duration: float, hz: float) -> PackedFloat32Array:
	# 摇骰盅:皮盅里五颗骰子哗啦哗啦。每甩一下(hz)一阵密集的磕碰,外加一层闷闷的皮革摩擦声跟着节奏起伏
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var swing := absf(sin(PI * hz * t))
		y += 0.06 * (_rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * swing * 0.9 * minf(t * 20.0, 1.0) * minf((duration - t) * 12.0, 1.0)
	var beats := int(duration * hz)
	for b in beats:
		var clicks := _dice_clicks(5, 0.07, 0.42)
		var start := int((float(b) + 0.15) / hz * RATE)
		for i in clicks.size():
			if start + i < n:
				out[start + i] += clicks[i]
	return out


func _drip(freq: float, duration: float, gain: float) -> PackedFloat32Array:
	# 一滴水:很短的正弦,音高往下滑
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * freq * (1.0 - 0.45 * t) / RATE
		out[i] = sin(phase) * sin(t * PI) * gain
	return out


func _ambience_loop(duration: float) -> PackedFloat32Array:
	# 房间底噪(褐噪声)+ 壁炉噼啪,再做成首尾无缝的循环
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var brown := 0.0
	for i in n:
		brown = clampf(brown + _rng.randf_range(-1.0, 1.0) * 0.02, -1.0, 1.0)
		out[i] = brown * 0.35
	for k in int(duration * 9):
		var start := _rng.randi_range(0, n - 400)
		var length := _rng.randi_range(60, 380)
		var gain := _rng.randf_range(0.15, 0.6)
		for i in length:
			out[start + i] += _rng.randf_range(-1.0, 1.0) * gain * pow(1.0 - float(i) / length, 3.0)
	return seamless_loop(out, int(AMBIENCE_CROSSFADE * RATE))


static func seamless_loop(samples: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	# 把末尾 fade 个采样交叉淡化进开头,再截掉末尾:播完最后一个采样跳回开头时,
	# 开头正是原本紧接着的那个采样,循环点没有跳变(否则每圈都会咔哒一声)
	var n := samples.size()
	var overlap := clampi(fade, 0, floori(n / 2.0))
	var out := samples.duplicate()
	for i in overlap:
		var w := float(i) / overlap
		out[i] = samples[i] * w + samples[n - overlap + i] * (1.0 - w)
	out.resize(n - overlap)
	return out


func _offset(samples: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var pad := PackedFloat32Array()
	pad.resize(int(seconds * RATE))
	pad.append_array(samples)
	return pad


func _mix(layers: Array) -> PackedFloat32Array:
	var n := 0
	for layer in layers:
		n = maxi(n, layer.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for layer in layers:
		for i in layer.size():
			out[i] += layer[i]
	return out


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
