extends SceneTree
## 画面がヘッドレスで組み上がるか確かめる。
##
##   godot --headless --script res://tests/ui_smoke.gd
##
## この環境では Godot を動かせないため、UI の誤りは CI でしか見つからない。
## 「シーンが読める」「ノードが生成できる」「数フレーム回しても落ちない」
## の3つだけを見る。見た目の正しさは人間が確認する。
##
## **注意**: `--script` 実行では、オートロード（Game / Platform / Balance）は
## このスクリプトのコンパイルより後、さらに `_initialize()` より後に登録される。
##   - 識別子として直接書く  → 「Identifier not found」でコンパイルに失敗
##   - _initialize ですぐ取る → root がまだツリーに入っておらず get_node が失敗
## したがって「1フレーム待ってから、root からの相対パスで取る」必要がある。

const SCENES := [
	"res://ui/main.tscn",
	"res://ui/frame/game_frame.tscn",
]

const SCREENS := [
	"res://ui/stages/stage01_screen.gd",
	"res://ui/tree/skill_tree_screen.gd",
]

const FRAMES := 20


## オートロードが root に入るまで数フレーム待って取る。
## 絶対パスは root がツリーに入るまで使えないので、root からの相対で引く。
func _autoload(node_name: String) -> Node:
	for i in range(30):
		var found := root.get_node_or_null(NodePath(node_name))
		if found != null:
			return found
		await process_frame
	return null


func _initialize() -> void:
	var failed := 0

	for path in SCENES:
		if not ResourceLoader.exists(path):
			push_error("シーンが無い: %s" % path)
			failed += 1
			continue
		var packed: PackedScene = load(path)
		var node: Node = packed.instantiate() if packed != null else null
		if node == null:
			push_error("インスタンス化に失敗: %s" % path)
			failed += 1
			continue
		print("シーン %s → 生成できた" % path)
		node.free()

	# 画面はセッションが走っていないと組めない。実機と同じ順序で起動する
	var game := await _autoload("Game")
	if game == null:
		push_error("オートロード Game が見つからない")
		quit(2)
		return

	var host := Control.new()
	root.add_child(host)
	game.attach(host)
	game.start_stage("stage01")

	for i in range(FRAMES):
		game.sim.step()
	print("ステージ1を %d フレーム進めた: 所持 %s / 層 %d"
		% [FRAMES, Fmt.amount(game.sim.currency), int(game.sim.core_state["layer"])])

	for path in SCREENS:
		var script: Script = load(path)
		if script == null:
			push_error("スクリプトが読めない: %s" % path)
			failed += 1
			continue
		var screen: Control = script.new()
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.add_child(screen)
		# _ready と数フレームの _physics_process を通す
		for i in range(3):
			await process_frame
		print("画面 %s → 組み上がった" % path)
		screen.queue_free()
		await process_frame

	# フォントの同梱と CJK 収録。ここが抜けると実機で日本語が全て豆腐になる
	for face in Typography.FILES:
		var path: String = Typography.FILES[face]
		if not ResourceLoader.exists(path):
			push_error("フォントが無い: %s" % path)
			failed += 1
			continue
		var f: FontFile = load(path)
		if f == null:
			push_error("フォントが読めない: %s" % path)
			failed += 1
			continue
		# 「賄」が出せなければ日本語 UI は成立しない
		if not f.has_char(0x8CC4):
			push_error("CJK が入っていない: %s" % path)
			failed += 1
			continue
		print("フォント %s → 日本語を出せる" % Typography.LABELS[face])

	var theme := Typography.build_theme()
	if theme == null or theme.default_font == null:
		push_error("テーマが組めない")
		failed += 1
	else:
		print("テーマ → 既定フォントと等幅数字を設定できた")

	# 表示規則（05章 5.8）
	var cases := {
		"8,240": Fmt.amount(8240.0),
		"1.2万": Fmt.amount(12000.0),
		"34.5万": Fmt.amount(345000.0),
		"1,000万": Fmt.amount(10000000.0),
		"1.2億": Fmt.amount(120000000.0),
	}
	for want in cases:
		if cases[want] != want:
			push_error("表示規則が違う: %s のはずが %s" % [want, cases[want]])
			failed += 1
	if failed == 0:
		print("表示規則 → 05章 5.8 のとおり")

	quit(1 if failed else 0)
