extends Control
## スキルツリー画面（docs/04 4.1）。
##
## 4系統 × 6段 ＋ T7【賄賂】。賄賂はイベントではなく**ツリーの最終ノード**であり、
## 他と同じ見た目で、一回り大きく中央最下部に置く（04章 4.7.1）。
##
## ノードの状態は4つ:
##   購入済み / 購入可能 / 資金不足 / 前提未達

const FRAME := preload("res://ui/frame/game_frame.tscn")
const BRANCHES := ["A", "B", "C", "D"]
const BRANCH_NAMES := {"A": "単価", "B": "頻度", "C": "自動化", "D": "固有"}

var _sim: Sim
var _frame: Control
var _buttons: Dictionary = {}     # スキルID -> Button
var _bribe_button: Button
var _bribe_note: Label


func _ready() -> void:
	_sim = Game.sim

	_frame = FRAME.instantiate()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	_frame.set_accent(Palette.stage(String(_sim.data["id"])))
	_frame.set_actions("", "", "")
	_frame.tab_selected.connect(_on_tab)

	_frame.set_board(_build_grid())
	_build_right_panel()
	_refresh()


func _physics_process(_delta: float) -> void:
	_refresh()


func _on_tab(id: String) -> void:
	if id == "corridor":
		Game.open_stage()


func _build_grid() -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)

	var grid := GridContainer.new()
	grid.columns = BRANCHES.size()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(grid)

	for id in BRANCHES:
		var head := Label.new()
		head.text = "%s %s" % [id, BRANCH_NAMES[id]]
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_color_override("font_color", Palette.branch(id))
		grid.add_child(head)

	for tier in range(1, 7):
		for id in BRANCHES:
			grid.add_child(_node_button(id, tier))

	# T7【賄賂】は他のノードと同じ仕組みで、一回り大きく最下部に置く
	_bribe_button = Button.new()
	_bribe_button.custom_minimum_size = Vector2(0, 64)
	_bribe_button.pressed.connect(_on_bribe)
	root.add_child(_bribe_button)

	_bribe_note = Label.new()
	_bribe_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bribe_note.add_theme_color_override("font_color", Palette.TEXT_DIM)
	root.add_child(_bribe_note)
	return root


func _node_button(branch: String, tier: int) -> Button:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 52)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for sk in _sim.data["skills"]:
		if sk["branch"] == branch and int(sk["tier"]) == tier:
			var id := String(sk["id"])
			button.pressed.connect(_on_buy.bind(id))
			_buttons[id] = button
			break
	return button


func _build_right_panel() -> void:
	_frame.clear_right_panel()
	var slot: VBoxContainer = _frame.right_slot
	var heading := Label.new()
	heading.text = "倍率の内訳"
	heading.add_theme_color_override("font_color", Palette.TEXT_DIM)
	slot.add_child(heading)
	for key in ["manual", "auto", "tap", "cps"]:
		var label := Label.new()
		label.name = key
		slot.add_child(label)


func _on_buy(id: String) -> void:
	_sim.buy_skill(id)


func _on_bribe() -> void:
	if _sim.buy_bribe():
		Game.on_stage_cleared()


func _refresh() -> void:
	if _sim == null:
		return
	var unit: String = _sim.data["currency"]["unit"]
	_frame.set_header("%s %s" % [Fmt.amount(_sim.currency), unit],
		_sim.progress(), "100万", _sim.t)

	for sk in _sim.data["skills"]:
		var id := String(sk["id"])
		if not _buttons.has(id):
			continue
		var button: Button = _buttons[id]
		var cost := float(sk["cost"])
		if _sim.owned.has(id):
			button.text = "%s\n取得済み" % sk["name"]
			button.disabled = true
			button.modulate = Color(1, 1, 1, 0.55)
		elif not _sim.skill_available(sk):
			button.text = "%s\n前提未達" % sk["name"]
			button.disabled = true
			button.modulate = Color(1, 1, 1, 0.35)
		else:
			button.text = "%s\n%s %s" % [sk["name"], Fmt.amount(cost), unit]
			button.disabled = _sim.currency < cost
			button.modulate = Color(1, 1, 1, 1.0 if not button.disabled else 0.7)

	var goal := _sim.goal()
	if _sim.cleared_at >= 0.0:
		_bribe_button.text = "【賄賂】支払い済み"
		_bribe_button.disabled = true
		_bribe_note.text = "扉は開いた"
	elif not _sim.bribe_unlocked():
		_bribe_button.text = "【看守への賄賂】  %s %s" % [Fmt.amount(goal), unit]
		_bribe_button.disabled = true
		_bribe_note.text = "4系統すべてで T4 以上を1つ取ると点灯する"
	else:
		_bribe_button.text = "【看守への賄賂】  %s %s" % [Fmt.amount(goal), unit]
		_bribe_button.disabled = _sim.currency < goal
		_bribe_note.text = ("看守を呼べる" if not _bribe_button.disabled
			else "あと %s %s" % [Fmt.amount(goal - _sim.currency), unit])

	var slot: VBoxContainer = _frame.right_slot
	_set_row(slot, "manual", "手動倍率  ×%.2f" % _sim.manual_mult())
	_set_row(slot, "auto", "自動倍率  ×%.2f" % _sim.auto_mult())
	_set_row(slot, "tap", "手動収入  %s" % Fmt.rate(_sim.core.manual_rate(_sim)))
	_set_row(slot, "cps", "自動収入  %s" % Fmt.rate(_sim.core.auto_rate(_sim)))


func _set_row(slot: VBoxContainer, key: String, text: String) -> void:
	var node := slot.get_node_or_null(NodePath(key))
	if node is Label:
		node.text = text
