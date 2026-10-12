extends GutTest
# 丢番茄的程序化音效(规格 §5):出手的短 whoosh 与湿的「啪叽」都能合成出非空、几乎不削波的采样,且有音量表项。


const SfxScript := preload("res://src/ui/sfx.gd")
const SOUNDS := ["tomato_throw", "tomato_splat"]

var sfx: Node


func before_each():
	sfx = autofree(SfxScript.new())
	sfx._rng.seed = 1   # 噪声随机:不定种子时削波比例偶尔落在阈值上下,测试时好时坏


func test_tomato_sounds_have_volume_entries():
	for sound in SOUNDS:
		assert_true(SfxScript.VOLUMES.has(sound), sound)


func test_tomato_sounds_are_short_audible_and_not_clipping():
	for sound in SOUNDS:
		var wav: AudioStreamWAV = sfx._synth(sound)
		var samples := int(wav.data.size() / 2.0)
		assert_between(samples, int(0.1 * SfxScript.RATE), int(0.6 * SfxScript.RATE), "%s 时长" % sound)
		var peak := 0
		var clipped := 0
		for i in range(0, wav.data.size(), 2):
			var v := absi(wav.data.decode_s16(i))
			peak = maxi(peak, v)
			if v >= 32000:
				clipped += 1
		assert_gt(peak, 2000, "%s 不是静音" % sound)
		assert_lt(float(clipped) / samples, 0.002, "%s 几乎不削波" % sound)
		assert_lt(absi(wav.data.decode_s16(wav.data.size() - 2)), 600, "%s 结尾收干净" % sound)
