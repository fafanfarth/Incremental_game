extends SceneTree
## GDScript 実装と Python シミュレータが一致することを確かめる（NFR-46）。
##
##   godot --headless --script res://tests/parity.gd -- <期待値JSONの絶対パス>
##
## 期待値JSON は tools/check_parity.py が書く:
##   {"stage": "stage01", "seed": 1, "profile": "manual",
##    "cleared_at": 1453.5, "snapshot_every": 60.0,
##    "checkpoints": [[60.0, 151.2], [120.0, 743.0], ...]}
##
## クリア時間だけでなく **途中経過も突き合わせる**。
## CI は1往復に数分かかるので、「どこで食い違ったか」がログに出ることが重要になる。

const TOLERANCE := 0.01          # クリア時間の許容差
const CHECKPOINT_TOLERANCE := 0.01

const CORES := {
	"stage01": "res://core/stages/stage01.gd",
	"stage02": "res://core/stages/stage02.gd",
	"stage03": "res://core/stages/stage03.gd",
	"stage04": "res://core/stages/stage04.gd",
	"stage05": "res://core/stages/stage05.gd",
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("使い方: -- <期待値JSONの絶対パス>")
		quit(2)
		return

	var expected: Variant = _read_json(args[0])
	if not (expected is Dictionary):
		push_error("期待値JSONが読めない: %s" % args[0])
		quit(2)
		return

	var stage_id: String = expected["stage"]
	if not CORES.has(stage_id):
		push_error("未移植のステージ: %s" % stage_id)
		quit(2)
		return

	var data: Variant = _read_json_res("res://data/%s.json" % stage_id)
	if not (data is Dictionary):
		push_error("データが読めない: %s" % stage_id)
		quit(2)
		return

	var profile_key: String = expected["profile"]
	var profile := SimProfile.idle() if profile_key == "idle" else SimProfile.manual()
	var core: StageCore = load(CORES[stage_id]).new()
	var snapshot_every := float(expected["snapshot_every"])

	var sim := Sim.new(profile, data, core, int(expected["seed"]))
	sim.run(snapshot_every)

	var label := "%s/%s seed=%d" % [stage_id, profile_key, int(expected["seed"])]

	# 検査の発生時刻を先に見る。ここがずれていれば乱数か検査の実装が原因と即断できる
	var want_ins: Array = expected.get("inspection_times", [])
	var got_ins: Array = sim.inspection_times.slice(0, want_ins.size())
	for i in range(mini(want_ins.size(), got_ins.size())):
		if absf(float(got_ins[i]) - float(want_ins[i])) > 0.05:
			var msg := "%s : 検査 %d 回目の時刻がずれている GDScript %.2f秒 / Python %.2f秒" % [
				label, i + 1, float(got_ins[i]), float(want_ins[i])]
			print("  GDScript の検査時刻 %s" % str(got_ins))
			print("  Python   の検査時刻 %s" % str(want_ins))
			push_error(msg)
			quit(1)
			return

	if sim.cleared_at < 0.0:
		push_error("%s : 時間内にクリアできなかった" % label)
		quit(1)
		return

	# まず途中経過。食い違い始めた地点が分かれば原因が特定しやすい
	var want: Array = expected["checkpoints"]
	var got: Array = sim.checkpoints
	var n := mini(want.size(), got.size())
	for i in range(n):
		var wt := float(want[i][0])
		var wl := float(want[i][1])
		var gl := float(got[i][1])
		var scale := maxf(absf(wl), 1.0)
		var d := absf(gl - wl) / scale
		if d >= CHECKPOINT_TOLERANCE:
			push_error("%s : %.0f秒 の時点で食い違い  GDScript %.1f / Python %.1f （差 %.1f%%）"
				% [label, wt, gl, wl, d * 100.0])
			_dump(sim, want, got, i)
			quit(1)
			return

	if want.size() != got.size():
		push_error("%s : チェックポイントの数が違う  GDScript %d / Python %d"
			% [label, got.size(), want.size()])
		quit(1)
		return

	var cleared := float(expected["cleared_at"])
	var diff: float = absf(sim.cleared_at - cleared) / cleared
	var line := "%s : GDScript %.1f秒 / Python %.1f秒 / 差 %.2f%%" % [
		label, sim.cleared_at, cleared, diff * 100.0]

	if diff >= TOLERANCE:
		push_error("%s  → 許容 %.0f%% を超過" % [line, TOLERANCE * 100.0])
		quit(1)
		return

	print("%s  → 一致" % line)
	quit(0)


## 食い違った前後を並べて出す。CI ログだけで原因を追えるようにするため
func _dump(sim: Sim, want: Array, got: Array, at: int) -> void:
	var from := maxi(0, at - 2)
	var to := mini(want.size(), at + 3)
	print("--- 食い違いの前後 ---")
	for i in range(from, to):
		var mark := " <<<" if i == at else ""
		print("  %6.0f秒  GDScript %14.1f  Python %14.1f%s"
			% [float(want[i][0]), float(got[i][1]), float(want[i][1]), mark])
	print("--- GDScript の状態 ---")
	print("  スキル %d / 反復購入 %s" % [sim.owned.size(), str(sim.repeats)])
	print("  所持 %.1f / 生涯 %.1f" % [sim.currency, sim.lifetime])


func _read_json(abs_path: String) -> Variant:
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _read_json_res(res_path: String) -> Variant:
	var text := FileAccess.get_file_as_string(res_path)
	if text == "":
		return null
	return JSON.parse_string(text)
