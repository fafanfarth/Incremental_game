extends SceneTree
## DetRng が Python 実装と同じ系列を出すか確かめる。
##
##   godot --headless --script res://tests/rng_check.gd -- <期待値JSONの絶対パス>
##
## 期待値JSON: {"1": [0.466910, ...], "2": [...]}（seed -> 先頭の randf 列）
##
## parity ジョブは1往復に10分かかる。乱数が合っているかだけを数秒で切り分けられるよう、
## これを parity の前に走らせる。

const TOLERANCE := 1e-9


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("使い方: -- <期待値JSONの絶対パス>")
		quit(2)
		return

	var f := FileAccess.open(args[0], FileAccess.READ)
	if f == null:
		push_error("期待値JSONが読めない: %s" % args[0])
		quit(2)
		return
	var expected: Variant = JSON.parse_string(f.get_as_text())
	if not (expected is Dictionary):
		push_error("期待値JSONが壊れている")
		quit(2)
		return

	var failed := false
	for key in expected:
		var want: Array = expected[key]
		var rng := DetRng.new(int(key))
		var got: Array[float] = []
		for _i in range(want.size()):
			got.append(rng.randf())

		var line := "seed=%s\n  GDScript %s\n  Python   %s" % [
			key, _fmt(got), _fmt(want)]
		var ok := true
		for i in range(want.size()):
			if absf(got[i] - float(want[i])) > TOLERANCE:
				ok = false
				break
		if ok:
			print("%s\n  → 一致" % line)
		else:
			failed = true
			push_error("%s\n  → 食い違い" % line)

	quit(1 if failed else 0)


func _fmt(values: Array) -> String:
	var parts: Array[String] = []
	for v in values:
		parts.append("%.9f" % float(v))
	return ", ".join(parts)
