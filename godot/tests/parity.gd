extends SceneTree
## GDScript 実装と Python シミュレータが一致することを確かめる（NFR-46）。
##
##   godot --headless --script godot/tests/parity.gd -- stage01 1 1530.5
##
## 引数: ステージID / seed / Python 側のクリア秒数
## 差が 1% 以上なら異常終了する。
##
## このテストがあるかぎり、バランス調整を data/ の編集だけで回せる状態が保たれる。
## 片方だけ直すと必ずここで落ちる。

const TOLERANCE := 0.01

const CORES := {
	"stage01": "res://core/stages/stage01.gd",
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("使い方: -- <stage_id> <seed> <expected_sec>")
		quit(2)
		return

	var stage_id := args[0]
	var seed := int(args[1])
	var expected := float(args[2])

	if not CORES.has(stage_id):
		push_error("未移植のステージ: %s" % stage_id)
		quit(2)
		return

	var data_path := "res://data/%s.json" % stage_id
	var text := FileAccess.get_file_as_string(data_path)
	if text == "":
		push_error("データが読めない: %s" % data_path)
		quit(2)
		return
	var data: Dictionary = JSON.parse_string(text)

	var core: StageCore = load(CORES[stage_id]).new()
	var sim := Sim.new(SimProfile.manual(), data, core, seed)
	sim.run()

	if sim.cleared_at < 0.0:
		push_error("%s: 時間内にクリアできなかった" % stage_id)
		quit(1)
		return

	var diff: float = absf(sim.cleared_at - expected) / expected
	var line := "%s seed=%d : GDScript %.1f秒 / Python %.1f秒 / 差 %.2f%%" % [
		stage_id, seed, sim.cleared_at, expected, diff * 100.0]

	if diff >= TOLERANCE:
		push_error("%s  → 許容 %.0f%% を超過" % [line, TOLERANCE * 100.0])
		quit(1)
		return

	print("%s  → 一致" % line)
	quit(0)
