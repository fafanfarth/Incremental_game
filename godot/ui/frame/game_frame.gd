extends Control
## 全ステージが共有する画面の骨格（docs/03 3.0b）。
##
##   上部バー   通貨・進捗・経過時間・設定（全ステージ完全共通）
##   左レール   タブ。左親指で届く
##   中央       盤面。**表示とドラッグ専用。連打はさせない**
##   右パネル   購入・アクション。右親指の可動域
##   下辺       主アクションを左右対称に2つ（NFR-03b）
##
## 配置はすべてアンカー基準（NFR-40）。絶対座標を使うと Steam 版で全部組み直しになる。
## 画面が横長になるほど中央が広がるだけで、レイアウトは破綻しない。

signal tab_selected(id: String)
signal action_pressed(slot: String)

const SAFE_MIN := 12.0

@onready var currency_label: Label = $TopBar/Row/Currency
@onready var progress: ProgressBar = $TopBar/Row/Progress
@onready var goal_label: Label = $TopBar/Row/Goal
@onready var timer_label: Label = $TopBar/Row/Timer
@onready var center: Control = $Center
@onready var right_slot: VBoxContainer = $RightPanel/Scroll/Slot
@onready var action_left: Button = $BottomBar/Row/ActionLeft
@onready var action_right: Button = $BottomBar/Row/ActionRight
@onready var action_extra: Button = $BottomBar/Row/Extra
@onready var left_rail: PanelContainer = $LeftRail
@onready var right_panel: PanelContainer = $RightPanel

var _accent: Color = Palette.GOLD


func _ready() -> void:
	_style()
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)

	for button in $LeftRail/Tabs.get_children():
		if button is Button:
			button.pressed.connect(_on_tab.bind(button.name.to_lower()))

	action_left.pressed.connect(func() -> void: action_pressed.emit("left"))
	action_right.pressed.connect(func() -> void: action_pressed.emit("right"))
	action_extra.pressed.connect(func() -> void: action_pressed.emit("extra"))


## ノッチとホームインジケータを避ける（NFR-03c）。
## 横持ちでは左右が削られるので、左レールと右パネルを内側に寄せる。
func _apply_safe_area() -> void:
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var left := SAFE_MIN
	var right := SAFE_MIN
	if screen.x > 0 and safe.size.x > 0 and safe.size.x < screen.x:
		var scale := float(size.x) / float(screen.x)
		left = maxf(SAFE_MIN, float(safe.position.x) * scale)
		right = maxf(SAFE_MIN, float(screen.x - safe.end.x) * scale)
	left_rail.offset_left = left
	left_rail.offset_right = left + 128.0
	right_panel.offset_left = -(340.0 + right)
	right_panel.offset_right = -right
	center.offset_left = left + 128.0
	center.offset_right = -(340.0 + right)


func _style() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)

	$TopBar.add_theme_stylebox_override("panel", Palette.panel(Palette.SURFACE))
	left_rail.add_theme_stylebox_override("panel", Palette.panel(Palette.SURFACE))
	right_panel.add_theme_stylebox_override("panel", Palette.panel(Palette.SURFACE))
	$BottomBar.add_theme_stylebox_override("panel", Palette.panel(Palette.SURFACE_HI))
	# カウンタは毎フレーム変わる。等幅数字にしないと桁が左右に踊る
	currency_label.theme_type_variation = &"Counter"
	currency_label.add_theme_color_override("font_color", Palette.GOLD)
	goal_label.theme_type_variation = &"Small"
	timer_label.theme_type_variation = &"Numeric"
	goal_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	timer_label.add_theme_color_override("font_color", Palette.TEXT_DIM)


func set_accent(color: Color) -> void:
	_accent = color
	currency_label.add_theme_color_override("font_color", color)


## 中央の盤面を差し替える。ステージを移るときはここだけが変わる
func set_board(node: Control) -> void:
	for child in center.get_children():
		child.queue_free()
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(node)


func clear_right_panel() -> void:
	for child in right_slot.get_children():
		child.queue_free()


func set_actions(left_text: String, right_text: String, extra_text: String) -> void:
	# 下辺の主アクションは左右対称。どちらの親指でも同じ操作ができる（NFR-03b）
	action_left.text = left_text
	action_right.text = right_text
	action_extra.text = extra_text
	action_extra.visible = extra_text != ""


func set_header(currency: String, ratio: float, goal_text: String, elapsed: float) -> void:
	currency_label.text = currency
	progress.value = ratio
	goal_label.text = goal_text
	timer_label.text = Fmt.clock(elapsed)


func _on_tab(id: String) -> void:
	tab_selected.emit(id)
