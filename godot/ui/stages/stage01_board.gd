extends Control
## ステージ1「独房棟」の盤面（docs/03 3.1）。
##
## 中央は**表示専用**。削る操作は下辺の左右ボタンで行う（NFR-02 / NFR-03b）。
## 壁本体もタップできるが、これは「当たった」感触のための補助。
##
## core を読むだけで、書き換えない（NFR-43）。状態の更新は Sim 側にしかない。

signal wall_hit()

const CRACK_ROWS := 5

var _sim: Sim
var _core: CellBlockCore

var _wall: Panel
var _layer_label: Label
var _combo_label: Label
var _hint_label: Label
var _dark_overlay: ColorRect
var _cracks: Array[ColorRect] = []


func setup(sim: Sim, core: CellBlockCore) -> void:
	_sim = sim
	_core = core


func _ready() -> void:
	var rows := VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.add_theme_constant_override("separation", 12)
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(rows)

	_wall = Panel.new()
	_wall.custom_minimum_size = Vector2(0, 220)
	_wall.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wall.add_theme_stylebox_override("panel", Palette.panel(Palette.SURFACE_HI, Palette.LINE, 4))
	_wall.gui_input.connect(_on_wall_input)
	rows.add_child(_wall)

	var cracks := VBoxContainer.new()
	cracks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cracks.add_theme_constant_override("separation", 6)
	cracks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wall.add_child(cracks)
	for i in range(CRACK_ROWS):
		var crack := ColorRect.new()
		crack.color = Palette.LINE
		crack.custom_minimum_size = Vector2(0, 3)
		crack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crack.modulate.a = 0.0
		cracks.add_child(crack)
		_cracks.append(crack)

	_layer_label = _make_label(rows, Palette.TEXT)
	_combo_label = _make_label(rows, Palette.GOLD)
	_hint_label = _make_label(rows, Palette.TEXT_DIM)

	_dark_overlay = ColorRect.new()
	_dark_overlay.color = Color(0, 0, 0, 0.72)
	_dark_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dark_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dark_overlay.visible = false
	add_child(_dark_overlay)

	var dark_text := Label.new()
	dark_text.text = "消灯時間\n手動では削れない。子分が働いている"
	dark_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dark_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dark_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark_text.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_dark_overlay.add_child(dark_text)


func _make_label(parent: Node, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _on_wall_input(event: InputEvent) -> void:
	# タッチはプロジェクト設定で InputEventMouseButton に正規化される（12章 12.2-②）
	if event is InputEventMouseButton and event.pressed:
		wall_hit.emit()


func refresh() -> void:
	if _sim == null:
		return
	var layer := int(_sim.core_state["layer"])
	var wall: Dictionary = _sim.data["wall"]
	var need := float(wall["layer_damage_base"]) * pow(float(wall["layer_damage_growth"]), layer)
	var done := float(_sim.core_state["layer_damage"])
	_layer_label.text = "第 %d 層 / 残り %s" % [layer, Fmt.amount(maxf(0.0, need - done))]

	var combo := int(_sim.core_state["combo"])
	var bonus := (_core.combo_mult(_sim) - 1.0) * 100.0
	if combo > 0:
		_combo_label.text = "COMBO ×%d   +%d%%" % [combo, int(round(bonus))]
	else:
		_combo_label.text = " "

	_hint_label.text = _next_hidden_hint(layer)
	_dark_overlay.visible = not _core.can_act(_sim)

	for i in range(_cracks.size()):
		var threshold := float(i + 1) / float(_cracks.size())
		var ratio := 0.0 if need <= 0.0 else done / need
		_cracks[i].modulate.a = 0.85 if ratio >= threshold else 0.0


## 次の隠し物までの距離を常に出す。時間ボーナスの予告も兼ねる（09章 9.6）
func _next_hidden_hint(layer: int) -> String:
	var taken: Dictionary = _sim.core_state["hidden"]
	var best_layer := -1
	for v in _sim.data["hidden_items"]["layers"]:
		var n := int(v)
		if n > layer and not taken.has(n):
			if best_layer < 0 or n < best_layer:
				best_layer = n
	if best_layer < 0:
		return "隠し物はもう無い"
	return "隠し物まで あと %d 層" % (best_layer - layer)
