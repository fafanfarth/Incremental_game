class_name ClockTowerCore
extends StageCore
## ステージ5「時計塔」― 同期（E[M] × 基礎搬出量）。
##
## 産出 = 基礎搬出量 B × 平均倍率 E[M]。
## E[M] は巡回周期の組み方で決まる。プレイヤーの最適解は
## docs/tools/sync_sim.py で数値積分した実測値をそのまま段階表として持つ。
##
## prototype/cores.py の ClockTowerCore と1行ずつ対応する。片方だけ直さないこと。

## レーン数と範囲拡張に応じた E[M]。sync_sim.py の出力と一致していること
const TABLE: Array[float] = [13.0, 36.2, 40.7, 64.2]


func init_state(sim: Sim) -> void:
	super.init_state(sim)
	sim.core_state["em"] = 1.0


func lanes(sim: Sim) -> int:
	return int(sim.data["tower"]["lanes_base"]) + int(sim.total("lanes"))


## 同時に開く窓の数に応じた平均倍率。
func em(sim: Sim) -> float:
	var t: Dictionary = sim.data["tower"]
	var duty_base := float(t["duty_base"])
	var n := lanes(sim)
	var value := 0.0
	if n <= 1:
		value = duty_base
	else:
		var idx := mini(n - 2, TABLE.size() - 1)
		value = TABLE[idx]
		if sim.has("range_expand"):
			value = TABLE[TABLE.size() - 1]
	var duty := duty_base + sim.total("duty_add")
	value *= duty / duty_base
	return value * sim.product("sync_mult")


func base_haul(sim: Sim) -> float:
	var t: Dictionary = sim.data["tower"]
	var level := float(sim.repeats.get("haul", 0))
	var b := float(t["haul_base"]) * (1.0 + float(t["level_bonus"]) * level)
	return b * sim.product("haul_mult")


func auto_rate(sim: Sim) -> float:
	if not sim.has("auto_haul"):
		return 0.0
	return base_haul(sim) * em(sim) * sim.best("auto_haul", 0.0) * sim.auto_mult()


func manual_rate(sim: Sim) -> float:
	var t: Dictionary = sim.data["tower"]
	var hands := minf(1.0, sim.tap_rate_nominal() / float(t["taps_for_full_speed"]))
	return base_haul(sim) * em(sim) * hands * sim.manual_mult()


func tick(sim: Sim, dt: float) -> void:
	sim.gain_auto(auto_rate(sim) * dt)
	sim.gain_manual(manual_rate(sim) * dt)
	sim.core_state["em"] = em(sim)


func note(sim: Sim) -> String:
	return "%d本 E[M]%d" % [lanes(sim), int(round(em(sim)))]
