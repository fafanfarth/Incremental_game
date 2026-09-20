extends Control
## 入口。Game セッションを繋いでステージ1を開くだけ。
##
## Phase 1 の範囲はステージ1の垂直スライス。廊下（ハブ）と他の棟は Phase 2 以降。

func _ready() -> void:
	Game.attach(self)
	Game.start_stage("stage01")
