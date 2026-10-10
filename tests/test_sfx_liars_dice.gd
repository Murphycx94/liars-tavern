extends GutTest
# 吹牛骰子新增的程序化音效:dice_shake(骰盅里哗啦哗啦)、cup_slam(扣盅)、dice_clack(开盅磕碰)、die_pop(丢骰子「啵」)、
# count_tick(计数「叮」)、dice_peek(掀盅沿)都能合成出非空、不削波的采样,且有音量表项;摇盅声盖得住整段摇盅。


const SfxScript := preload("res://src/ui/sfx.gd")
const DICE_SOUNDS := ["dice_shake", "cup_slam", "dice_clack", "die_pop", "count_tick", "dice_peek"]

var sfx: Node


func before_each():
	sfx = autofree(SfxScript.new())


func _samples(wav: AudioStreamWAV) -> int:
	return int(wav.data.size() / 2.0)   # 16 位单声道


func test_dice_sounds_have_volume_entries():
	for sound in DICE_SOUNDS:
		assert_true(SfxScript.VOLUMES.has(sound), sound)


func test_dice_sounds_synthesize_non_empty_audio():
	for sound in DICE_SOUNDS:
		var wav: AudioStreamWAV = sfx._synth(sound)
		assert_gt(_samples(wav), int(0.03 * SfxScript.RATE), "%s 至少 30 毫秒" % sound)
		var peak := 0
		for i in range(0, wav.data.size(), 2):
			peak = maxi(peak, absi(wav.data.decode_s16(i)))
		assert_gt(peak, 1500, "%s 不是静音" % sound)
		assert_true(peak <= 32000, "%s 不削波" % sound)


func test_shake_rattle_covers_the_whole_shake():
	assert_gte(_samples(sfx._synth("dice_shake")), int(LiarsDiceCups.SHAKE_TIME * SfxScript.RATE), "摇多久响多久")
	assert_gt(_samples(sfx._synth("dice_shake")), _samples(sfx._synth("cup_slam")))
