extends Control
## 起動確認用の暫定シーン。Phase 1 で本物の画面に置き換える。
##
## いま確かめているのは3つだけ:
##   1. Platform が正しい実装を選んでいるか（12章 12.2-③）
##   2. バランスデータが読めているか（NFR-45）
##   3. 決定論コアが 60Hz で回っているか（NFR-43）

@onready var _label: Label = $Margin/Rows/Status
var _sim: Sim
var _ticks := 0


func _ready() -> void:
	var data := Balance.stage("stage01")
	_sim = Sim.new(SimProfile.manual(), data, CellBlockCore.new(), 1)
	_refresh()


## シミュレーションは _physics_process（60Hz 固定）。描画レートから独立させる。
## ここを _process に書くと、ハードモードの残り時間が端末ごとに変わる。
func _physics_process(_delta: float) -> void:
	if _sim.cleared_at >= 0.0:
		return
	_sim.step()
	_ticks += 1
	if _ticks % 30 == 0:
		while _sim.try_purchase() and _sim.cleared_at < 0.0:
			pass
	if _ticks % 15 == 0:
		_refresh()


func _refresh() -> void:
	var stage := Balance.stage("stage01")
	var unit: String = stage["currency"]["unit"]
	var goal := float(stage["goal"])
	_label.text = "\n".join([
		"Platform : %s（広告 %s / 課金 %s）" % [
			"PREMIUM" if Platform.monetization_model() == Platform.Model.PREMIUM else "F2P",
			"あり" if Platform.supports_ads() else "なし",
			"あり" if Platform.supports_iap() else "なし"],
		"ステージ : %s" % stage["name"],
		"所持     : %s %s  /  目標 %s" % [
			String.num(_sim.currency, 0), unit, String.num(goal, 0)],
		"経過     : %.1f 秒（%d tick）" % [_sim.t, _ticks],
		"スキル   : %d / %d" % [_sim.owned.size(), stage["skills"].size()],
		"",
		"クリア   : %s" % ("%.1f 分" % (_sim.cleared_at / 60.0) if _sim.cleared_at >= 0.0 else "―"),
	])
