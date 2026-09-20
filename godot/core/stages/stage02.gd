class_name WorkshopCore
extends StageCore
## ステージ2「労役棟」― 加工チェーン（価値が ×12 ずつ跳ねる）。
##
## 再現する危険: 加工段階ごとの ×12。機械の種類を1つ増やすだけで産出価値が
## 12倍になるため、レーン数や速度より段階数が圧倒的に効く（11章 11.7-①）。
##
## prototype/cores.py の WorkshopCore と1行ずつ対応する。片方だけ直さないこと。

func init_state(sim: Sim) -> void:
	super.init_state(sim)
	sim.core_state["clog"] = 0.0


## 到達している加工段階。1=部品 … 4=精密品
func depth(sim: Sim) -> int:
	return 1 + int(sim.total("chain_depth"))


func lanes(sim: Sim) -> int:
	return int(sim.data["line"]["lanes_base"]) + int(sim.total("lanes"))


## 1個あたりの価値。
##
## 加工1段で価値は ×12 になるが、k個の入力から1個しかできない。
## 正味の倍率は 12/k であり、これを入れないと段数だけで ×20,736 になって
## 35分ぶんの成長予算を1つの要素が食い潰す。
func item_value(sim: Sim) -> float:
	var ln: Dictionary = sim.data["line"]
	var k := maxf(1.0, float(ln["inputs_per_item"]) - sim.total("yield_improve"))
	return pow(float(ln["value_growth"]) / k, depth(sim))


## 1秒あたりに右端へ抜ける個数。
func throughput(sim: Sim) -> float:
	var ln: Dictionary = sim.data["line"]
	var level := float(sim.repeats.get("machine", 0))
	var speed := float(ln["lane_rate"]) * (1.0 + float(ln["level_bonus"]) * level)
	speed *= sim.product("line_speed")
	return float(lanes(sim)) * speed


func auto_rate(sim: Sim) -> float:
	return throughput(sim) * item_value(sim) * sim.auto_mult()


## 詰まり解消と残業。手動は産出そのものではなく「割り込みで上乗せ」する。
func manual_rate(sim: Sim) -> float:
	var ln: Dictionary = sim.data["line"]
	return sim.tap_rate_nominal() * float(ln["clog_bonus_items"]) * item_value(sim) \
		* sim.manual_mult()


func tick(sim: Sim, dt: float) -> void:
	sim.gain_auto(auto_rate(sim) * dt)
	sim.gain_manual(manual_rate(sim) * dt)


func note(sim: Sim) -> String:
	return "段%d 列%d 機Lv%d" % [depth(sim), lanes(sim), int(sim.repeats.get("machine", 0))]
