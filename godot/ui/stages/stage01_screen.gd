extends Control
## ステージ1の画面。共通の枠に盤面と右パネルを挿す（docs/03 3.0b / 3.1）。
##
## 役割は「core を読んで表示する」ことと「操作を core に渡す」ことだけ。
## 経済の計算は一切ここに書かない。書くとシミュレータと乖離して CI の parity が落ちる。

const FRAME := preload("res://ui/frame/game_frame.tscn")
const BULK_STEPS := [1, 10, -1]   # -1 は「買えるだけ」

var _sim: Sim
var _core: CellBlockCore
var _frame: Control
var _board: Control
var _bulk_index := 0
var _rows: Dictionary = {}        # 反復購入ID -> 行のノード群


func _ready() -> void:
	_sim = Game.sim
	_core = _sim.core as CellBlockCore

	_frame = FRAME.instantiate()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	_frame.set_accent(Palette.stage("stage01"))
	_frame.action_pressed.connect(_on_action)
	_frame.tab_selected.connect(_on_tab)

	_board = preload("res://ui/stages/stage01_board.gd").new()
	_board.setup(_sim, _core)
	_board.wall_hit.connect(_on_dig)
	_frame.set_board(_board)

	_build_right_panel()
	_refresh()


func _physics_process(_delta: float) -> void:
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	# 入力はアクション経由（NFR-41）。Steam 版はバインドを足すだけで済む
	if event.is_action_pressed("act_primary"):
		_on_dig()


func _on_action(slot: String) -> void:
	match slot:
		"left", "right":
			_on_dig()
		"extra":
			_toggle_bulk()


func _on_dig() -> void:
	Game.player_action()


func _on_tab(id: String) -> void:
	if id == "tree":
		Game.open_skill_tree()


func _toggle_bulk() -> void:
	_bulk_index = (_bulk_index + 1) % BULK_STEPS.size()
	_update_actions()


func _bulk_label() -> String:
	var n: int = BULK_STEPS[_bulk_index]
	return "一括 ×MAX" if n < 0 else "一括 ×%d" % n


func _update_actions() -> void:
	_frame.set_actions("⛏ 削る（左）", "⛏ 削る（右）", _bulk_label())


## 子分の行を組む。数値は refresh で毎フレーム入れ替える
func _build_right_panel() -> void:
	_frame.clear_right_panel()
	_rows.clear()
	var slot: VBoxContainer = _frame.right_slot

	var heading := Label.new()
	heading.text = "子分"
	heading.add_theme_color_override("font_color", Palette.TEXT_DIM)
	slot.add_child(heading)

	for item in _core.catalog(_sim):
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", Palette.panel(Palette.SURFACE_HI))
		var rows := VBoxContainer.new()
		panel.add_child(rows)

		var title := Label.new()
		var cost := Label.new()
		cost.add_theme_color_override("font_color", Palette.TEXT_DIM)
		var buy := Button.new()
		buy.text = "買う"
		buy.pressed.connect(_on_buy.bind(String(item["id"])))

		rows.add_child(title)
		rows.add_child(cost)
		rows.add_child(buy)
		slot.add_child(panel)
		_rows[String(item["id"])] = {"title": title, "cost": cost, "buy": buy, "item": item}

	_update_actions()


func _on_buy(id: String) -> void:
	var n: int = BULK_STEPS[_bulk_index]
	if n < 0:
		while _sim.buy_repeat(id):
			pass
	else:
		_sim.buy_repeat_bulk(id, n)


func _refresh() -> void:
	if _sim == null:
		return
	var unit: String = _sim.data["currency"]["unit"]
	_frame.set_header(
		"%s %s" % [Fmt.amount(_sim.currency), unit],
		_sim.progress(), "100万", _sim.t)
	_board.refresh()

	for id in _rows:
		var row: Dictionary = _rows[id]
		var item: Dictionary = row["item"]
		var owned := int(_sim.repeats[id])
		var cap := _core.capacity(_sim, item)
		row["title"].text = "%s  ×%d / %d" % [_name_of(item), owned, cap]
		var available: bool = _core.repeat_available(_sim, item)
		if not available:
			row["cost"].text = "定員" if owned >= cap else "未解放"
			row["buy"].disabled = true
			continue
		var price := _core.repeat_cost(_sim, item)
		row["cost"].text = "%s %s   %s" % [Fmt.amount(price), unit, Fmt.rate(float(item["cps"]))]
		row["buy"].disabled = _sim.currency < price


func _name_of(item: Dictionary) -> String:
	const LABELS := {
		"rookie": "新入り", "veteran": "古株",
		"sweeper": "掃除夫", "trusty": "看守補佐",
	}
	return LABELS.get(String(item["id"]), String(item["id"]))
