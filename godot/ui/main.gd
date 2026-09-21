extends Control
## 入口。Game セッションを繋いでステージ1を開くだけ。
##
## Phase 1 の範囲はステージ1の垂直スライス。廊下（ハブ）と他の棟は Phase 2 以降。

## フォント選定中は起動時に比較画面を出せる。
## 実機で `--font-preview` 相当の確認をしたいときは PREVIEW を true にする
const PREVIEW := false


func _ready() -> void:
	# Godot 既定のフォントに CJK は無い。ここで必ず差し替える
	theme = Typography.build_theme()

	if PREVIEW:
		var preview := preload("res://ui/debug/font_preview.tscn").instantiate()
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(preview)
		return

	Game.attach(self)
	Game.start_stage("stage01")
