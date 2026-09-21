extends Control
## フォント選定用の比較画面。実機で書体を切り替えて見比べる。
##
## 見るべきは3つ:
##   1. 毎フレーム変わるカウンタで桁が踊らないか（等幅数字が効いているか）
##   2. 右パネル相当の小さい文字（14px）で漢字が潰れないか
##   3. 監獄という舞台に合うか
##
## 決まったら ui/typography.gd の DEFAULT を変え、使わないフォントは削除する。

const SAMPLE_SMALL := "看守への賄賂 / 前提未達 / 定員 / 未解放 / 倍率の内訳"
const SAMPLE_BODY := "第 7 層 / 残り 2,140   消灯時間：手動では削れない"
const SAMPLE_HEAD := "独房棟 ― 壁を削ってタバコを稼ぐ"

var _face: int = Typography.DEFAULT
var _rows: VBoxContainer
var _counter: Label
var _face_label: Label
var _t := 0.0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 14)
	margin.add_child(_rows)

	_face_label = _add(SAMPLE_HEAD, &"Head", Palette.TEXT)
	_counter = _add("", &"Counter", Palette.GOLD)
	_add(SAMPLE_BODY, &"", Palette.TEXT)
	_add(SAMPLE_SMALL, &"Small", Palette.TEXT_DIM)
	_add("0123456789  ×12  +120%  1.2万  34.5万  100万", &"Numeric", Palette.TEXT)

	var switch := Button.new()
	switch.text = "書体を切り替える"
	switch.pressed.connect(_cycle)
	_rows.add_child(switch)

	var note := Label.new()
	note.theme_type_variation = &"Small"
	note.text = "カウンタは毎フレーム変わる。桁が左右に踊らないかを見ること"
	note.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_rows.add_child(note)

	_apply()


func _add(text: String, variation: StringName, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	if variation != &"":
		label.theme_type_variation = variation
	label.add_theme_color_override("font_color", color)
	_rows.add_child(label)
	return label


func _process(delta: float) -> void:
	# 実際のカウンタと同じく毎フレーム変わる値を出す
	_t += delta * 137.0
	_counter.text = "%s 本" % Fmt.amount(1234.0 + _t)


func _cycle() -> void:
	var faces := Typography.FILES.keys()
	_face = faces[(faces.find(_face) + 1) % faces.size()]
	_apply()


func _apply() -> void:
	Typography.set_face(_face)
	theme = Typography.build_theme(_face)
	_face_label.text = "%s ― %s" % [Typography.LABELS[_face], SAMPLE_HEAD]
