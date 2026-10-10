extends GutTest
# 顶部提示条:最多同时 MAX_TOASTS 条;进牌桌时 clear() 收掉等待厅留下的进出提示(原来开局运镜时还挂着,压住右上的九宫格)。


func test_clear_removes_every_toast_at_once():
	var toasts := ToastLayer.new()
	add_child_autofree(toasts)
	toasts.show_toast("客2 走进了酒馆")
	toasts.show_toast("客3 走进了酒馆")
	assert_eq(toasts.get_child_count(), 2)
	toasts.clear()
	assert_eq(toasts.get_child_count(), 0, "马上从界面上拿掉,不等淡出")
	toasts.show_toast("第一人称视角")
	assert_eq(toasts.get_child_count(), 1, "之后照常显示新的提示")


func test_oldest_toast_makes_room():
	var toasts := ToastLayer.new()
	add_child_autofree(toasts)
	for i in ToastLayer.MAX_TOASTS + 2:
		toasts.show_toast("提示 %d" % i)
	assert_eq(toasts.get_child_count(), ToastLayer.MAX_TOASTS)
