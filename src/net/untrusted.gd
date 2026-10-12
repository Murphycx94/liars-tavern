class_name Untrusted
# 网络来的视图 / 事件字段的安全比较:GDScript 里不同类型直接 ==(如 String == bool、Dictionary == int)是脚本错误,
# 所以先比类型。21 点的界面与 3D 层都用它读房主发来的字段。


static func flag(value: Variant) -> bool:
	# 只有真正的 true 才算真
	return value is bool and value


static func same(value: Variant, want: Variant) -> bool:
	# 类型一样且相等(int 与 float 不混用)
	return typeof(value) == typeof(want) and value == want
