extends Node
## 進行中のゲームを1つ持ち、60Hz で回す（NFR-43 / NFR-30）。
##
## UI と core の橋渡し。**シミュレーションは _physics_process でしか進めない。**
## _process に書くと、ハードモードの残り時間が端末ごとに変わる。
##
## 自動購入の方針（Sim.try_purchase）はシミュレータ専用であり、ここでは呼ばない。
## 実機では UI から buy_skill / buy_repeat / buy_bribe を呼ぶ。

signal stage_started(id: String)
signal stage_cleared(id: String)

const CORES := {
	"stage01": preload("res://core/stages/stage01.gd"),
	"stage02": preload("res://core/stages/stage02.gd"),
	"stage03": preload("res://core/stages/stage03.gd"),
	"stage04": preload("res://core/stages/stage04.gd"),
	"stage05": preload("res://core/stages/stage05.gd"),
}

const SCREENS := {
	"stage01": "res://ui/stages/stage01_screen.gd",
}

var sim: Sim
var stage_id := ""

var _host: Node = null
var _current: Control = null


func _ready() -> void:
	set_physics_process(false)


func attach(host: Node) -> void:
	_host = host


func start_stage(id: String, seed_value: int = 1) -> void:
	stage_id = id
	var core: StageCore = CORES[id].new()
	sim = Sim.new(SimProfile.live(), Balance.stage(id), core, seed_value)
	set_physics_process(true)
	stage_started.emit(id)
	open_stage()


func _physics_process(_delta: float) -> void:
	if sim != null and sim.cleared_at < 0.0:
		sim.step()


func player_action() -> void:
	if sim != null:
		sim.player_action()


func open_stage() -> void:
	if SCREENS.has(stage_id):
		_show(load(SCREENS[stage_id]))


func open_skill_tree() -> void:
	_show(load("res://ui/tree/skill_tree_screen.gd"))


func on_stage_cleared() -> void:
	set_physics_process(false)
	stage_cleared.emit(stage_id)


func _show(script: Script) -> void:
	if _host == null:
		return
	if _current != null:
		_current.queue_free()
	var screen: Control = script.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host.add_child(screen)
	_current = screen
