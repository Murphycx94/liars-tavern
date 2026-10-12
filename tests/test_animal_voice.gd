extends GutTest
# 动物话合成(规格 §4、§7):确定性、8 个物种分得开、句尾语调方向、时长范围、不削顶、两端不咔哒。


const RATE := AnimalVoice.RATE


func after_all():
	AnimalVoice.clear_cache()


func test_same_input_renders_identical_samples():
	for species in [0, 3, 7]:
		var a := AnimalVoice.render(species, "这把稳了~", 1)
		var b := AnimalVoice.render(species, "这把稳了~", 1)
		assert_eq(a.size(), b.size())
		assert_true(a == b, "%s 两次合成逐样本相同" % Species.IDS[species])


func test_pitch_bucket_changes_pitch_but_not_timing():
	var low := AnimalVoice.layout(5, "你骗人!", 0)
	var high := AnimalVoice.layout(5, "你骗人!", AnimalVoice.BUCKETS - 1)
	assert_eq(low["duration"], high["duration"])
	assert_gt(high["syllables"][0]["f0_start"], low["syllables"][0]["f0_start"] * 1.1)


func test_bucket_for_pid_is_stable_and_in_range():
	for pid in [1, 2, 123456, 99999999]:
		var b := AnimalVoice.bucket_for(pid)
		assert_between(b, 0, AnimalVoice.BUCKETS - 1)
		assert_eq(AnimalVoice.bucket_for(pid), b)


func test_one_syllable_per_spoken_character_and_reveal_times_are_monotonic():
	var text := "哈哈,ok 1!"
	var plan := AnimalVoice.layout(2, text, 2)
	assert_eq(plan["syllables"].size(), 5, "哈 哈 o k 1")
	var reveal: PackedFloat32Array = plan["reveal"]
	assert_eq(reveal.size(), text.length())
	for i in range(1, reveal.size()):
		assert_true(reveal[i] >= reveal[i - 1], "逐字出现的时刻不倒退")
	assert_lt(reveal[-1], plan["duration"])


func test_syllables_are_about_70_to_95_ms_except_turtle_and_endings():
	for species in Species.count():
		var plan := AnimalVoice.layout(species, "一二三四五六", 2)
		for syl: Dictionary in plan["syllables"]:
			if syl["last"] or syl["zing"]:
				continue
			if species == Species.index_of("turtle"):
				assert_between(syl["dur"], 0.1, 0.14, "乌龟拉长到约 1.4 倍")
			else:
				assert_between(syl["dur"], 0.06, 0.105, Species.IDS[species])


func test_every_phrase_lasts_between_0_4_and_2_5_seconds():
	for species in Species.count():
		for phrase_id in Banter.PHRASES.size():
			for bucket in [0, AnimalVoice.BUCKETS - 1]:
				var plan := AnimalVoice.layout(species, Banter.PHRASES[phrase_id], bucket)
				assert_between(plan["duration"], 0.4, 2.5, "%s「%s」" % [Species.IDS[species], Banter.PHRASES[phrase_id]])


func test_rendered_length_matches_layout_and_peaks_are_normalized_without_clipping():
	for species in Species.count():
		var plan := AnimalVoice.layout(species, Banter.PHRASES[4], 2)
		var samples := AnimalVoice.render(species, Banter.PHRASES[4], 2)
		assert_eq(samples.size(), int(ceil(plan["duration"] * RATE)))
		var peak := 0.0
		for v in samples:
			peak = maxf(peak, absf(v))
		assert_between(peak, 0.3, AnimalVoice.PEAK + 0.001, "%s 峰值" % Species.IDS[species])
		assert_lt(absf(samples[0]), 0.01, "句首不咔哒")
		assert_lt(absf(samples[-1]), 0.01, "句尾不咔哒")


func test_endings_shape_the_final_syllable_pitch():
	for species in Species.count():
		var q: Dictionary = AnimalVoice.layout(species, "好吗?", 2)["syllables"][-1]
		var e: Dictionary = AnimalVoice.layout(species, "好吗!", 2)["syllables"][-1]
		var t: Dictionary = AnimalVoice.layout(species, "好吗…", 2)["syllables"][-1]
		var plain: Dictionary = AnimalVoice.layout(species, "好吗", 2)["syllables"][-1]
		assert_gt(q["f0_end"], q["f0_start"] * 1.3, "问句句尾上扬")
		assert_gt(e["f0_end"], e["f0_start"], "感叹句尾音高抬起")
		assert_gt(e["amp"], plain["amp"], "感叹句尾音量抬起")
		assert_lt(t["f0_end"], t["f0_start"] * 0.8, "省略号下沉")
		assert_gt(t["dur"], plain["dur"] * 1.4, "省略号拖长")


func test_question_rises_and_ellipsis_sinks_in_the_audio():
	# 羊驼的声源最接近正弦(共振峰不抢基频):直接量合成结果里末音节前后两半的基频
	var alpaca := Species.index_of("alpaca")
	var q := _halves_f0(AnimalVoice.render(alpaca, "啊?", 2))
	var t := _halves_f0(AnimalVoice.render(alpaca, "啊…", 2))
	assert_gt(q[1], q[0] * 1.08, "问句上扬:%s" % [q])
	assert_lt(t[1], t[0] * 0.92, "省略号下沉:%s" % [t])


func test_species_are_clearly_distinct_in_pitch_or_brightness():
	# 每两个物种之间:基频或过零率(频谱质心的便宜替身)至少差 15%
	var metrics := []
	for species in Species.count():
		var samples := AnimalVoice.render(species, "啊啊啊", 2)
		metrics.append([_median_f0(samples), _zero_cross_rate(samples)])
	for a in Species.count():
		for b in range(a + 1, Species.count()):
			var f0_ratio := maxf(metrics[a][0], metrics[b][0]) / maxf(minf(metrics[a][0], metrics[b][0]), 1.0)
			var zcr_ratio := maxf(metrics[a][1], metrics[b][1]) / maxf(minf(metrics[a][1], metrics[b][1]), 1e-6)
			assert_gt(maxf(f0_ratio, zcr_ratio), 1.15, "%s vs %s: f0 %s / %s, zcr %s / %s" % [Species.IDS[a], Species.IDS[b],
				metrics[a][0], metrics[b][0], metrics[a][1], metrics[b][1]])


func test_phrase_stream_is_cached_per_species_phrase_and_bucket():
	AnimalVoice.clear_cache()
	var a := AnimalVoice.phrase_stream(1, 0, 2)
	assert_same(AnimalVoice.phrase_stream(1, 0, 2), a)
	assert_not_same(AnimalVoice.phrase_stream(1, 0, 3), a)
	assert_eq(a.mix_rate, RATE)
	assert_eq(a.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_true(AnimalVoice.is_cached(1, 0, 2))


func test_prebuild_runs_on_worker_threads_and_poll_commits():
	AnimalVoice.clear_cache()
	AnimalVoice.prebuild(6, 1)
	# 工作线程按真实时间算完:用墙钟限时,不数帧(测试以 --fixed-fps 跑时帧几乎不花时间)
	var deadline := Time.get_ticks_msec() + 10000
	while not AnimalVoice.is_cached(6, Banter.PHRASES.size() - 1, 1) and Time.get_ticks_msec() < deadline:
		AnimalVoice.poll()
		await get_tree().process_frame
	for phrase_id in Banter.PHRASES.size():
		assert_true(AnimalVoice.is_cached(6, phrase_id, 1))
	# 预热结果和当场合成一样
	var direct := AnimalVoice.to_wav(AnimalVoice.render(6, Banter.PHRASES[2], 1))
	assert_eq(AnimalVoice.phrase_stream(6, 2, 1).data, direct.data)


# —— 量测小工具 ——

func _voiced(samples: PackedFloat32Array) -> PackedFloat32Array:
	# 去掉首尾静音
	var first := 0
	var last := samples.size() - 1
	while first < last and absf(samples[first]) < 0.02:
		first += 1
	while last > first and absf(samples[last]) < 0.02:
		last -= 1
	return samples.slice(first, last + 1)


func _f0(frame: PackedFloat32Array) -> float:
	# 自相关:越过第一个过零点之后的最高峰
	var n := frame.size()
	var lo := int(RATE / 1500.0)
	var hi := mini(int(RATE / 60.0), n - 1)
	var ac := PackedFloat32Array()
	ac.resize(hi + 1)
	for lag in range(lo, hi + 1):
		var s := 0.0
		for i in n - lag:
			s += frame[i] * frame[i + lag]
		ac[lag] = s
	var start := lo
	while start < hi and ac[start] > 0.0:
		start += 1
	var best := start
	for lag in range(start, hi + 1):
		if ac[lag] > ac[best]:
			best = lag
	return RATE / float(best)


func _median_f0(samples: PackedFloat32Array) -> float:
	var voiced := _voiced(samples)
	var values := []
	for k in 3:
		var at := int(voiced.size() * (0.2 + 0.25 * k))
		values.append(_f0(voiced.slice(at, mini(at + 1024, voiced.size()))))
	values.sort()
	return values[1]


func _halves_f0(samples: PackedFloat32Array) -> Array:
	var voiced := _voiced(samples)
	var half := voiced.size() / 2
	var size := mini(768, half)
	return [_f0(voiced.slice(half / 2 - size / 2, half / 2 + size / 2)),
		_f0(voiced.slice(half + half / 2 - size / 2, half + half / 2 + size / 2))]


func _zero_cross_rate(samples: PackedFloat32Array) -> float:
	var voiced := _voiced(samples)
	var count := 0
	for i in range(1, voiced.size()):
		if (voiced[i - 1] < 0.0) != (voiced[i] < 0.0):
			count += 1
	return float(count) / voiced.size()
