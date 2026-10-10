class_name AnimalVoice
extends RefCounted
# 动森式「动物话」(规格 2026-10-08 丢番茄与快捷语 §4):把一句话逐字念成该物种的叫声,程序合成,不用音频文件。
# - 每个字(汉字、字母、数字)一个音节;标点是停顿,句尾标点决定语调:「!」末尾音量和音高抬起、「?」句尾上扬、
#   「…」拖长下沉、「~」拖长带颤、「。」轻轻落下。
# - 音高 = 物种基准 × 按「字 + 位置」哈希给的小起伏 × 句内缓降 × 本人偏移档(按 pid 定,同物种两人略有不同);
#   同一 (物种, 句子, 偏移档) 每次合成逐样本相同。
# - layout() 只排时间表(便宜,无头时界面拿它逐字显示气泡、点头);render() 才真正合成采样;
#   stream() 按 (物种, 句子编号, 偏移档) 缓存成 AudioStreamWAV,prebuild() 把合成投到工作线程预热(纯数组运算)。
# 22050 Hz(同 Sfx);锯齿/方波用 polyBLEP 抑制混叠,每个音节两端升余弦淡入淡出(不咔哒),整句做直流隔离、
# 轻低通,再按峰值与响度归一(峰值 ≤ PEAK,不削顶)。


const RATE := 22050
const PEAK := 0.85            # 归一化后的峰值(约 -1.4 dBFS)
const TARGET_RMS := 0.2       # 响度归一的目标(峰值限制优先):方波的熊和正弦的羊驼听起来差不多响
const LEAD := 0.02            # 句首留白(秒)
const TAIL := 0.14            # 句尾余音(秒):最后一个音节的释放与房间混响
const EDGE_FADE := 0.004      # 音节两端最短的升余弦淡入淡出(秒)
const BUCKETS := 5            # 本人音高偏移档数
const BUCKET_STEP := 0.035    # 每档音高差(倍率):0.93 … 1.07
const WOBBLE := 0.08          # 按字哈希的音高起伏(±)
const FINAL_CONTOUR := 0.4    # 句尾音节里物种固有音高形状只保留这么多:句尾的升降(问句上扬、省略号下沉)盖过它
const DECLINE := 0.06         # 一句话从头到尾音高缓降(陈述句)
const LOWPASS_HZ := 6500.0    # 整句轻低通:去掉刺耳的高频
const FORMANT_BLOCK := 64     # 滑动共振峰每这么多个采样重算一次滤波系数
const HISS_HZ := 3800.0       # 鳄鱼嘶声、猪鼻息的噪声带中心
# 停顿(秒,按码位:全角、半角标点都认)
const PAUSES := {0x2C: 0.12, 0xFF0C: 0.12, 0x3001: 0.1, 0x3002: 0.14, 0x2E: 0.14, 0x21: 0.06, 0xFF01: 0.06,
	0x3F: 0.06, 0xFF1F: 0.06, 0x2026: 0.22, 0x7E: 0.06, 0xFF5E: 0.06, 0x20: 0.08}
const DEFAULT_PAUSE := 0.06
# 句尾标点 → 语调(按码位)
const ENDING_MARKS := [[[0x3F, 0xFF1F], "question"], [[0x21, 0xFF01], "exclaim"], [[0x2026], "trail"],
	[[0x7E, 0xFF5E], "tilde"]]
const ENDINGS := {
	# 句尾那个音节:时长倍率、整体音高倍率、句尾音高倍率(相对句首,决定升降)、音量倍率、颤音深度
	"exclaim": {"dur": 1.25, "pitch": 1.12, "end": 1.18, "amp": 1.25, "wiggle": 0.0},
	"question": {"dur": 1.3, "pitch": 1.0, "end": 1.45, "amp": 1.05, "wiggle": 0.0},
	"trail": {"dur": 1.8, "pitch": 0.97, "end": 0.72, "amp": 0.85, "wiggle": 0.0},
	"tilde": {"dur": 1.6, "pitch": 1.05, "end": 1.04, "amp": 1.0, "wiggle": 0.07},
	"statement": {"dur": 1.1, "pitch": 1.0, "end": 0.9, "amp": 1.0, "wiggle": 0.0},
}

# 物种叫声参数(下标同 Species.IDS)。f0 基频(Hz),syl 音节时长(秒),attack 起音(秒),
# wave 声源配比(sine / saw / square / sub 次谐波 / pulse 声门脉冲串 / h2 h3 二三次谐波 / noise 气声),
# formants [[频率, Q, 增益]] 或 path 共振峰滑动(按音节进度插值),dry 不经共振峰的直达比例,
# contour 音节内固有的音高形状 [[进度, 倍率]],tremolo / vibrato [速率 Hz, 深度],其余是各物种的特色
const PROFILES := [
	{   # 狐狸:高音短促的「嘤/呀」——带一点气声的上滑锯齿波,共振峰偏高
		"f0": 520.0, "syl": 0.075, "attack": 0.006, "release": 0.35,
		"wave": {"saw": 0.7, "sine": 0.3, "noise": 0.12},
		"formants": [[1150.0, 4.0, 1.0], [2700.0, 6.0, 0.55]], "dry": 0.25,
		"contour": [[0.0, 0.86], [0.6, 1.12], [1.0, 1.06]],
	},
	{   # 熊:低沉的「呜噢」——低频方波加次谐波,慢起慢收,喉音颤
		"f0": 125.0, "syl": 0.095, "attack": 0.028, "release": 0.45,
		"wave": {"square": 0.6, "sub": 0.45, "sine": 0.25},
		"formants": [[430.0, 3.0, 1.0], [860.0, 4.0, 0.6]], "dry": 0.3,
		"contour": [[0.0, 0.94], [0.4, 1.05], [1.0, 0.9]], "tremolo": [27.0, 0.3],
	},
	{   # 猪:「哼哼」——鼻音,低中频脉冲串,每个音节两下快速的喉部脉冲,起头带一点鼻息
		"f0": 190.0, "syl": 0.085, "attack": 0.004, "release": 0.3,
		"wave": {"pulse": 0.85, "noise": 0.06},
		"formants": [[280.0, 5.0, 1.0], [1000.0, 6.0, 0.35], [2400.0, 8.0, 0.2]], "dry": 0.15,
		"contour": [[0.0, 1.06], [1.0, 0.92]], "double_pulse": true, "snort": 0.35,
	},
	{   # 猫:「喵」——元音 i → a → u 的共振峰滑动,中高音,音高先扬后抑
		"f0": 430.0, "syl": 0.09, "attack": 0.01, "release": 0.35,
		"wave": {"saw": 0.38, "sine": 0.6},
		"path": [[0.0, 300.0, 2300.0], [0.45, 820.0, 1250.0], [1.0, 360.0, 800.0]], "dry": 0.2,
		"contour": [[0.0, 0.94], [0.45, 1.12], [1.0, 0.88]],
	},
	{   # 乌龟:慢吞吞的「咕噜」——很低的正弦加二三次谐波(小喇叭也听得到),轻微气泡调制,音节拉长到 1.4 倍
		"f0": 100.0, "syl": 0.119, "attack": 0.03, "release": 0.4,
		"wave": {"sine": 0.6, "h2": 0.45, "h3": 0.25},
		"formants": [[360.0, 2.5, 1.0]], "dry": 0.6,
		"contour": [[0.0, 1.0], [1.0, 0.94]], "bubble": [13.0, 0.45],
	},
	{   # 羊驼:「嗯~」——闭嘴哼鸣,正弦加鼻腔共振,带颤音,音高中等偏高
		"f0": 340.0, "syl": 0.09, "attack": 0.018, "release": 0.35,
		"wave": {"sine": 0.75, "saw": 0.15},
		"formants": [[260.0, 4.0, 0.9], [1100.0, 8.0, 0.35]], "dry": 0.6,
		"contour": [[0.0, 0.97], [0.5, 1.03], [1.0, 1.0]], "vibrato": [6.5, 0.035],
	},
	{   # 猴子:「呜哇 / 吱」——快速上下滑的高音,音节短,偶尔夹一个更高的「吱」
		"f0": 680.0, "syl": 0.07, "attack": 0.005, "release": 0.3,
		"wave": {"saw": 0.3, "sine": 0.65},
		"path": [[0.0, 380.0, 800.0], [0.6, 950.0, 1500.0], [1.0, 900.0, 1400.0]], "dry": 0.3,
		"contour": [[0.0, 0.8], [0.45, 1.32], [1.0, 0.92]], "zing": 4,
	},
	{   # 鳄鱼:低沉的「嘶咕」——噪声嘶声开头,接很低的咕噜,带颗粒感
		"f0": 80.0, "syl": 0.09, "attack": 0.004, "release": 0.35,
		"wave": {"square": 0.5, "pulse": 0.35},
		"formants": [[320.0, 3.0, 1.0], [720.0, 4.0, 0.55], [1800.0, 6.0, 0.2]], "dry": 0.2,
		"contour": [[0.0, 1.0], [1.0, 0.9]], "hiss": 0.3, "grain": 0.4,
	},
	{   # 熊猫:软软的「咩嘤」——像小羊一样带抖的哼叫,中低音,正弦为主加一点锯齿,快颤音
		"f0": 260.0, "syl": 0.09, "attack": 0.014, "release": 0.4,
		"wave": {"sine": 0.7, "saw": 0.25, "h2": 0.2},
		"formants": [[520.0, 3.5, 1.0], [1350.0, 6.0, 0.4]], "dry": 0.4,
		"contour": [[0.0, 0.96], [0.35, 1.06], [1.0, 0.95]], "vibrato": [11.0, 0.05],
	},
	{   # 企鹅:鼻音很重的「嘎嘎」——中低音锯齿加方波,共振峰偏亮、起音很脆,像小喇叭
		"f0": 155.0, "syl": 0.08, "attack": 0.003, "release": 0.3,
		"wave": {"saw": 0.6, "square": 0.35, "noise": 0.05},
		"formants": [[700.0, 4.0, 1.0], [1650.0, 5.0, 0.7], [2900.0, 7.0, 0.3]], "dry": 0.15,
		"contour": [[0.0, 1.1], [0.3, 1.0], [1.0, 0.86]], "tremolo": [33.0, 0.25],
	},
]

static var _cache := {}       # "物种:句子编号:偏移档" -> {"stream": AudioStreamWAV, "layout": Dictionary}
static var _layouts := {}     # 同键 -> layout(界面逐字显示用,无头时也有)
static var _jobs := {}        # 同键 -> {"task": int, "result": Dictionary}:工作线程预热中


# —— 对外 ——

static func bucket_for(pid: int) -> int:
	# 本人音高偏移档:按 pid 定(各端一致)
	return posmod(hash(pid), BUCKETS)


static func bucket_factor(bucket: int) -> float:
	return 1.0 + (clampi(bucket, 0, BUCKETS - 1) - (BUCKETS - 1) / 2.0) * BUCKET_STEP


static func phrase_layout(species: int, phrase_id: int, bucket: int) -> Dictionary:
	var key := _key(species, phrase_id, bucket)
	if not _layouts.has(key):
		_layouts[key] = layout(species, Banter.phrase_text(phrase_id), bucket)
	return _layouts[key]


static func phrase_stream(species: int, phrase_id: int, bucket: int) -> AudioStreamWAV:
	# 缓存命中直接给;还在工作线程里就等它算完;都没有就当场合成(约几十毫秒)
	var key := _key(species, phrase_id, bucket)
	if not _cache.has(key):
		var samples: PackedFloat32Array
		if _jobs.has(key):
			var job: Dictionary = _jobs[key]
			WorkerThreadPool.wait_for_task_completion(job["task"])
			_jobs.erase(key)
			samples = job["result"]["samples"]
		else:
			samples = render(species, Banter.phrase_text(phrase_id), bucket)
		_cache[key] = to_wav(samples)
	return _cache[key]


static func is_cached(species: int, phrase_id: int, bucket: int) -> bool:
	return _cache.has(_key(species, phrase_id, bucket))


static func prebuild(species: int, bucket: int) -> void:
	# 这位物种、这个偏移档的 8 句全部投到工作线程(纯数组运算,不碰节点与资源);poll() 每帧收回
	for phrase_id in Banter.PHRASES.size():
		var key := _key(species, phrase_id, bucket)
		if _cache.has(key) or _jobs.has(key):
			continue
		var job := {"result": {}}
		var text: String = Banter.PHRASES[phrase_id]
		job["task"] = WorkerThreadPool.add_task(func(): job["result"]["samples"] = render(species, text, bucket),
			false, "AnimalVoice " + key)
		_jobs[key] = job


static func poll() -> void:
	# 主线程每帧调用:算完的转成 AudioStreamWAV 进缓存(每个任务都要 wait 一次才回收)
	for key in _jobs.keys():
		var job: Dictionary = _jobs[key]
		if WorkerThreadPool.is_task_completed(job["task"]):
			WorkerThreadPool.wait_for_task_completion(job["task"])
			_jobs.erase(key)
			_cache[key] = to_wav(job["result"]["samples"])


static func clear_cache() -> void:
	for job: Dictionary in _jobs.values():
		WorkerThreadPool.wait_for_task_completion(job["task"])
	_jobs = {}
	_cache = {}
	_layouts = {}


static func _key(species: int, phrase_id: int, bucket: int) -> String:
	return "%d:%d:%d" % [species, phrase_id, bucket]


# —— 时间表 ——

static func is_spoken(ch: String) -> bool:
	# 念出声的字:汉字、字母、数字;其余(标点、空格、符号)是停顿
	var code := ch.unicode_at(0)
	if (code >= 0x4E00 and code <= 0x9FFF) or (code >= 0x3400 and code <= 0x4DBF):
		return true
	if code >= 0x30 and code <= 0x39:
		return true
	return ch.to_lower() != ch.to_upper()


static func ending_of(text: String) -> String:
	# 最后一个念出声的字之后的标点决定句尾语调
	var tail := ""
	for i in range(text.length() - 1, -1, -1):
		if is_spoken(text[i]):
			break
		tail = text[i] + tail
	if tail.contains("..."):
		return "trail"
	for mark: Array in ENDING_MARKS:
		for code: int in mark[0]:
			if tail.contains(String.chr(code)):
				return mark[1]
	return "statement"


static func layout(species: int, text: String, bucket: int) -> Dictionary:
	# {"syllables": [{"t", "dur", "f0_start", "f0_end", "amp", "wiggle", "zing", "char"}], "reveal": [每个字出现的时刻],
	#  "duration": 总时长, "ending": 句尾语调}。纯计算:同样的输入永远同样的输出
	var p: Dictionary = PROFILES[clampi(species, 0, PROFILES.size() - 1)]
	var spoken: Array[int] = []
	for i in text.length():
		if is_spoken(text[i]):
			spoken.append(i)
	var ending := ending_of(text)
	var shape: Dictionary = ENDINGS[ending]
	var base_f0: float = p["f0"] * bucket_factor(bucket)
	var syllables := []
	var reveal := PackedFloat32Array()
	reveal.resize(text.length())
	var t := LEAD
	var count := spoken.size()
	for i in text.length():
		var ch := text[i]
		if not is_spoken(ch):
			reveal[i] = t
			t += PAUSES.get(ch.unicode_at(0), DEFAULT_PAUSE) if i > 0 else 0.0
			continue
		var k := spoken.find(i)
		var last := k == count - 1
		var h := _hash01(species, ch, i)
		var dur: float = p["syl"] * lerpf(0.9, 1.1, _hash01(species, ch, i + 101))
		var decline := DECLINE * (float(k) / maxf(count - 1, 1)) if ending != "question" else 0.0
		var f0 := base_f0 * (1.0 + WOBBLE * (h * 2.0 - 1.0)) * (1.0 - decline)
		var f0_end := f0
		var amp := 1.0
		var wiggle := 0.0
		var zing := false
		if last:
			dur *= shape["dur"]
			f0 *= shape["pitch"]
			f0_end = f0 * shape["end"]
			amp = shape["amp"]
			wiggle = shape["wiggle"]
		elif p.has("zing") and int(h * 1000.0) % int(p["zing"]) == 0:
			zing = true   # 猴子偶尔夹一个更高更短的「吱」
			dur *= 0.7
			f0 *= 2.1
			f0_end = f0 * 1.18
		reveal[i] = t
		syllables.append({"t": t, "dur": dur, "f0_start": f0, "f0_end": f0_end, "amp": amp, "wiggle": wiggle,
			"zing": zing, "char": i, "last": last})
		t += dur
	return {"syllables": syllables, "reveal": reveal, "duration": t + TAIL, "ending": ending}


static func _hash01(species: int, ch: String, i: int) -> float:
	return float(posmod(hash([species, ch, i]), 10007)) / 10006.0


# —— 合成 ——

static func render(species: int, text: String, bucket: int) -> PackedFloat32Array:
	# 整句采样(-1..1);同样的输入逐样本相同
	var plan := layout(species, text, bucket)
	var p: Dictionary = PROFILES[clampi(species, 0, PROFILES.size() - 1)]
	var out := PackedFloat32Array()
	out.resize(int(ceil(plan["duration"] * RATE)))
	for k in plan["syllables"].size():
		var syl: Dictionary = plan["syllables"][k]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([species, text, bucket, k])
		var samples := _syllable(p, syl, rng)
		var start := int(syl["t"] * RATE)
		for i in samples.size():
			if start + i < out.size():
				out[start + i] += samples[i]
	_finish(out)
	return out


static func _syllable(p: Dictionary, syl: Dictionary, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(syl["dur"] * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var wave: Dictionary = p["wave"]
	var zing: bool = syl["zing"]
	if zing:
		wave = {"sine": 0.8, "saw": 0.2, "noise": 0.05}
	var w_sine: float = wave.get("sine", 0.0)
	var w_saw: float = wave.get("saw", 0.0)
	var w_square: float = wave.get("square", 0.0)
	var w_sub: float = wave.get("sub", 0.0)
	var w_pulse: float = wave.get("pulse", 0.0)
	var w_h2: float = wave.get("h2", 0.0)
	var w_h3: float = wave.get("h3", 0.0)
	var w_noise: float = wave.get("noise", 0.0)
	var contour: Array = p["contour"] if not zing else [[0.0, 1.0], [1.0, 1.0]]
	var contour_strength := FINAL_CONTOUR if syl["last"] else 1.0
	var tremolo: Array = p.get("tremolo", [0.0, 0.0])
	var vibrato: Array = p.get("vibrato", [0.0, 0.0])
	var bubble: Array = p.get("bubble", [0.0, 0.0])
	var hiss: float = 0.0 if zing else p.get("hiss", 0.0)
	var grain: float = p.get("grain", 0.0)
	var snort: float = p.get("snort", 0.0)
	var dry: float = p["dry"]
	var attack: float = minf(p["attack"], syl["dur"] * 0.3)
	var release: float = p["release"]
	var double_pulse: bool = p.get("double_pulse", false)
	var path: Array = p.get("path", [])
	var formants: Array = p.get("formants", [])
	if not path.is_empty():
		formants = [[path[0][1], 5.0, 1.0], [path[0][2], 7.0, 0.6]]
	var filters := []
	for f in formants:
		filters.append(_Biquad.new(f[0], f[1], f[2]))
	var hiss_band := _Biquad.new(HISS_HZ, 1.2, 1.0)   # 嘶声 / 鼻息:带通噪声,不要 8 kHz 以上的刺耳成分
	var phase := 0.0
	var sub_phase := 0.0
	var grain_gain := 1.0
	var noise_lp := 0.0
	var bubble_phase := rng.randf() * TAU
	var f0_start: float = syl["f0_start"]
	var f0_end: float = syl["f0_end"]
	var wiggle: float = syl["wiggle"]
	var amp: float = syl["amp"]
	var edge := maxi(int(EDGE_FADE * RATE), 1)
	for i in n:
		var x := float(i) / n
		var t := float(i) / RATE
		if not path.is_empty() and i % FORMANT_BLOCK == 0:
			var f1 := _path_at(path, x, 1)
			var f2 := _path_at(path, x, 2)
			filters[0].tune(f1, 5.0)
			filters[1].tune(f2, 7.0)
		# 音高:句尾语调(线性)× 物种固有形状 × 颤音 / 拖腔的颤
		var f := lerpf(f0_start, f0_end, x) * lerpf(1.0, _contour_at(contour, x), contour_strength)
		if vibrato[1] > 0.0:
			f *= 1.0 + vibrato[1] * sin(TAU * vibrato[0] * t)
		if wiggle > 0.0:
			f *= 1.0 + wiggle * sin(TAU * 7.0 * t) * x
		var dt := f / RATE
		phase += dt
		if phase >= 1.0:
			phase -= 1.0
			if grain > 0.0:
				grain_gain = 1.0 - grain * rng.randf()   # 鳄鱼的颗粒感:每个周期音量随机跳一点
		sub_phase = fmod(sub_phase + dt * 0.5, 1.0)
		var s := 0.0
		if w_sine > 0.0:
			s += w_sine * sin(TAU * phase)
		if w_h2 > 0.0:
			s += w_h2 * sin(TAU * 2.0 * phase)
		if w_h3 > 0.0:
			s += w_h3 * sin(TAU * 3.0 * phase)
		if w_saw > 0.0:
			s += w_saw * (2.0 * phase - 1.0 - _blep(phase, dt))
		if w_square > 0.0:
			s += w_square * ((1.0 if phase < 0.5 else -1.0) + _blep(phase, dt) - _blep(fmod(phase + 0.5, 1.0), dt)) * 0.7
		if w_sub > 0.0:
			s += w_sub * sin(TAU * sub_phase)
		if w_pulse > 0.0:
			# 声门脉冲:每周期开头一个窄的升余弦鼓包(宽 18% 周期),减去均值去直流
			var width := 0.18
			var g := 0.5 - 0.5 * cos(TAU * phase / width) if phase < width else 0.0
			s += w_pulse * (g - width * 0.5) * 2.4
		var noise := rng.randf_range(-1.0, 1.0)
		if w_noise > 0.0:
			noise_lp += 0.35 * (noise - noise_lp)
			s += w_noise * noise_lp
		s *= grain_gain
		var voiced := s * dry
		for flt: _Biquad in filters:
			voiced += flt.process(s)
		# 起头的嘶声(鳄鱼)/鼻息(猪):高通噪声,很快衰减
		var lead := 0.0
		if hiss > 0.0:
			lead = hiss_band.process(noise) * 0.9 * pow(clampf(1.0 - x / hiss, 0.0, 1.0), 0.7)
			voiced *= smoothstep(hiss * 0.6, hiss * 1.1, x)
		elif snort > 0.0:
			lead = hiss_band.process(noise) * snort * pow(clampf(1.0 - x / 0.2, 0.0, 1.0), 1.5)
		var env := _envelope(x, t, attack, release, double_pulse)
		var mod := 1.0
		if tremolo[1] > 0.0:
			mod *= 1.0 - tremolo[1] * (0.5 + 0.5 * sin(TAU * tremolo[0] * t))
		if bubble[1] > 0.0:
			mod *= 1.0 - bubble[1] * pow(absf(sin(PI * bubble[0] * t + bubble_phase)), 3.0)
		var v := (voiced * env * mod + lead * minf(t / 0.002, 1.0)) * amp
		# 两端再各压一段升余弦:不管声源怎么跳,音节边界一定是零
		if i < edge:
			v *= 0.5 - 0.5 * cos(PI * float(i) / edge)
		elif i >= n - edge:
			v *= 0.5 - 0.5 * cos(PI * float(n - 1 - i) / edge)
		out[i] = v
	return out


static func _envelope(x: float, t: float, attack: float, release: float, double_pulse: bool) -> float:
	# 起音(秒)→ 保持 → 最后 release(占音节比例)的余弦收尾;猪是两个快速鼓包(「哼哼」)
	if double_pulse:
		var a := exp(-pow((x - 0.24) / 0.13, 2.0))
		var b := 0.8 * exp(-pow((x - 0.66) / 0.15, 2.0))
		return (a + b) * minf(t / maxf(attack, 0.001), 1.0)
	var rise := minf(t / maxf(attack, 0.001), 1.0)
	rise = rise * rise * (3.0 - 2.0 * rise)
	var fall := 1.0
	var start := 1.0 - release
	if x > start:
		fall = 0.5 + 0.5 * cos(PI * (x - start) / release)
	return rise * fall * (1.0 - 0.15 * x)


static func _contour_at(points: Array, x: float) -> float:
	for k in range(1, points.size()):
		if x <= points[k][0]:
			var a: Array = points[k - 1]
			var b: Array = points[k]
			var u: float = (x - a[0]) / maxf(b[0] - a[0], 0.0001)
			return lerpf(a[1], b[1], u * u * (3.0 - 2.0 * u))
	return points[-1][1]


static func _path_at(points: Array, x: float, column: int) -> float:
	for k in range(1, points.size()):
		if x <= points[k][0]:
			var a: Array = points[k - 1]
			var b: Array = points[k]
			var u: float = (x - a[0]) / maxf(b[0] - a[0], 0.0001)
			return lerpf(a[column], b[column], u)
	return points[-1][column]


static func _blep(t: float, dt: float) -> float:
	# polyBLEP:在波形跳变点两侧各一个采样内补一段多项式,抑制混叠
	if t < dt:
		var u := t / dt
		return u + u - u * u - 1.0
	if t > 1.0 - dt:
		var u := (t - 1.0) / dt
		return u * u + u + u + 1.0
	return 0.0


static func _finish(out: PackedFloat32Array) -> void:
	# 直流隔离 + 一阶低通 + 归一(峰值 ≤ PEAK,响度向 TARGET_RMS 靠)
	var a := 1.0 - exp(-TAU * LOWPASS_HZ / RATE)
	var lp := 0.0
	var x1 := 0.0
	var y1 := 0.0
	var peak := 0.0
	var energy := 0.0
	for i in out.size():
		var y := out[i] - x1 + 0.995 * y1
		x1 = out[i]
		y1 = y
		lp += a * (y - lp)
		out[i] = lp
		peak = maxf(peak, absf(lp))
		energy += lp * lp
	if peak <= 0.0:
		return
	var rms := sqrt(energy / out.size())
	var gain := minf(PEAK / peak, TARGET_RMS / maxf(rms, 1e-6))
	for i in out.size():
		out[i] *= gain


static func to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav


class _Biquad:
	# 恒定 0 dB 峰值的带通(RBJ cookbook),共振峰用;tune() 改中心频率
	var b0 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var gain := 1.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func _init(freq: float, q: float, p_gain: float) -> void:
		gain = p_gain
		tune(freq, q)

	func tune(freq: float, q: float) -> void:
		var w0 := TAU * clampf(freq, 40.0, RATE * 0.45) / RATE
		var alpha := sin(w0) / (2.0 * q)
		var a0 := 1.0 + alpha
		b0 = alpha / a0
		b2 = -alpha / a0
		a1 = -2.0 * cos(w0) / a0
		a2 = (1.0 - alpha) / a0

	func process(x: float) -> float:
		var y := b0 * x + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y * gain
