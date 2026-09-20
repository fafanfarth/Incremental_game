class_name InfirmaryCore
extends StageCore
## ステージ4「医務棟」― マージ（在庫回転 vs 指数価値）。
##
## R1 の生成速度が律速。育てるほど R1 あたりの価値は (3/2)^(R-1) で伸びるが、
## 育てている間は盤面を占有して生成が止まる。
##
## 換金ランク R を決めると、1個作るのに R1 が 2^(R-1) 個必要で、価値は 3^(R-1)。
## 盤面の占有率から到達できるランクの上限が決まる。
##
## prototype/cores.py の InfirmaryCore と1行ずつ対応する。片方だけ直さないこと。

func init_state(sim: Sim) -> void:
	super.init_state(sim)
	sim.core_state["rank"] = 1


func cells(sim: Sim) -> int:
	return int(sim.data["board"]["cells_base"]) + int(sim.total("cells"))


## 1秒あたりに湧く R1 の数。
func gen_rate(sim: Sim) -> float:
	var b: Dictionary = sim.data["board"]
	return (1.0 / float(b["spawn_sec"])) * sim.product("spawn_speed") \
		* sim.best("spawn_batch", 1.0)


## 盤面に収まる範囲で、R1 あたりの価値が最大になる換金ランク。
func best_rank(sim: Sim) -> int:
	var b: Dictionary = sim.data["board"]
	var cap := int(b["max_rank"]) + int(sim.total("max_rank"))
	var limit := float(cells(sim)) * float(b["occupancy"])
	var found := 1
	var found_v := 0.0
	for r in range(1, cap + 1):
		var need := pow(2.0, r - 1)
		if need > limit:
			break
		var v := pow(float(b["value_growth"]) / 2.0, r - 1)
		if v > found_v:
			found = r
			found_v = v
	return found


func _value_per_r1(sim: Sim) -> float:
	var b: Dictionary = sim.data["board"]
	var potency := 1.0 + float(b["potency_bonus"]) * float(sim.repeats.get("potency", 0))
	return pow(float(b["value_growth"]) / 2.0, best_rank(sim) - 1) * potency


## 自動合成アームが回している分。
func auto_rate(sim: Sim) -> float:
	if not sim.has("auto_merge"):
		return 0.0
	var share := sim.best("auto_merge", 0.0)
	return gen_rate(sim) * _value_per_r1(sim) * share \
		* float(sim.data["board"]["base_value"]) * sim.auto_mult()


func manual_rate(sim: Sim) -> float:
	var b: Dictionary = sim.data["board"]
	var hands := minf(1.0, sim.tap_rate_nominal() / float(b["taps_for_full_speed"]))
	return gen_rate(sim) * _value_per_r1(sim) * hands \
		* float(b["base_value"]) * sim.manual_mult()


func tick(sim: Sim, dt: float) -> void:
	sim.gain_auto(auto_rate(sim) * dt)
	sim.gain_manual(manual_rate(sim) * dt)
	sim.core_state["rank"] = best_rank(sim)


func note(sim: Sim) -> String:
	return "R%d 盤%d" % [int(sim.core_state["rank"]), cells(sim)]
