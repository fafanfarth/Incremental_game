class_name CellBlockCore
extends StageCore
## ステージ1「独房棟」― 壁削りと子分（反復購入の逓増コスト）。
##
## 再現する危険: 層報酬の発散と、反復購入の回収時間（11章 11.2）。

func init_state(sim: Sim) -> void:
	super.init_state(sim)
	sim.core_state["layer"] = 0
	sim.core_state["layer_damage"] = 0.0
	sim.core_state["combo"] = 0
	sim.core_state["since_tap"] = 0.0
	sim.core_state["tap_credit"] = 0.0
	sim.core_state["hidden"] = {}


func _dark(sim: Sim) -> bool:
	var lo: Dictionary = sim.data["lights_out"]
	var period := float(lo["period_sec"])
	return fmod(sim.t, period) >= period - float(lo["duration_sec"])


func can_act(sim: Sim) -> bool:
	return not _dark(sim) or sim.has("tap_during_lights_out")


func tap_power(sim: Sim) -> float:
	var base := float(sim.data["wall"]["tap_power_base"]) + sim.total("tap_add")
	base *= sim.product("tap_mult")
	return base * sim.best("tap_hits", 1.0)


func combo_mult(sim: Sim) -> float:
	var c: Dictionary = sim.data["combo"]
	var cap := sim.best("combo_cap", float(c["cap"]))
	var steps := int(sim.core_state["combo"]) / 10
	return 1.0 + minf(float(steps) * float(c["bonus_per_10"]), cap)


func _subs_cps(sim: Sim) -> float:
	var t := 0.0
	for item in catalog(sim):
		t += float(sim.repeats[item["id"]]) * float(item["cps"])
	t += sim.total("flat_cps")
	for e in sim.effects("auto_from_tap"):
		t += tap_power(sim) * float(e["value"])
	return t


func manual_rate(sim: Sim) -> float:
	var per_tap := tap_power(sim) * combo_mult(sim)
	var w: Dictionary = sim.data["wall"]
	var n := int(sim.core_state["layer"])
	# 層報酬はタップダメージに比例する。層 n での比を近似に使う
	var ratio := (float(w["layer_reward_base"]) / float(w["layer_damage_base"])) \
		* pow(float(w["layer_reward_growth"]) / float(w["layer_damage_growth"]), n)
	return per_tap * (1.0 + ratio) * sim.manual_mult() * sim.tap_rate_nominal()


func auto_rate(sim: Sim) -> float:
	var cps := _subs_cps(sim) * sim.auto_mult()
	if _dark(sim):
		cps *= sim.best("lights_out_auto_mult", float(sim.data["lights_out"]["auto_mult"]))
	return cps


func _do_tap(sim: Sim) -> void:
	var cfg: Dictionary = sim.data["combo"]
	var hold := sim.best("combo_hold", float(cfg["hold_sec"]))
	var since := float(sim.core_state["since_tap"])
	if since <= float(cfg["chain_window_sec"]) or sim.has("combo_no_reset") or since <= hold:
		sim.core_state["combo"] = int(sim.core_state["combo"]) + 1
	else:
		sim.core_state["combo"] = 1
	sim.core_state["since_tap"] = 0.0

	var power := tap_power(sim) * combo_mult(sim)
	var crits := sim.effects("crit")
	if not crits.is_empty():
		var e: Dictionary = crits[0]
		if sim.rng.randf() < float(e["chance"]):
			power *= float(e["mult"])

	var amount := power * sim.manual_mult()
	var luckies := sim.effects("lucky")
	if not luckies.is_empty():
		var e2: Dictionary = luckies[0]
		if sim.rng.randf() < float(e2["chance"]):
			amount += float(e2["amount"]) * sim.manual_mult()
	sim.gain_manual(amount)

	sim.core_state["layer_damage"] = float(sim.core_state["layer_damage"]) + power
	var w: Dictionary = sim.data["wall"]
	while true:
		var need := float(w["layer_damage_base"]) \
			* pow(float(w["layer_damage_growth"]), int(sim.core_state["layer"]))
		if float(sim.core_state["layer_damage"]) < need:
			break
		sim.core_state["layer_damage"] = float(sim.core_state["layer_damage"]) - need
		sim.core_state["layer"] = int(sim.core_state["layer"]) + 1
		var reward := float(w["layer_reward_base"]) \
			* pow(float(w["layer_reward_growth"]), int(sim.core_state["layer"]))
		sim.gain_manual(reward * sim.manual_mult())
		_hidden(sim)


## 隠し物は固定報酬。全体倍率もブーストも乗せない（11章 11.2-②）。
func _hidden(sim: Sim) -> void:
	var h: Dictionary = sim.data["hidden_items"]
	var layer: int = int(sim.core_state["layer"])
	var taken: Dictionary = sim.core_state["hidden"]
	if taken.has(layer):
		return
	# JSON の数値は Godot では float で返るため、int の層番号と直接比較しない
	var matched := false
	for v in h["layers"]:
		if int(v) == layer:
			matched = true
			break
	if not matched:
		return
	taken[layer] = true
	var w: Dictionary = sim.data["wall"]
	var base := float(w["layer_reward_base"]) * pow(float(w["layer_reward_growth"]), layer)
	sim.gain_manual(base * float(h["reward_multiple_of_layer"])
		* sim.best("hidden_item_reward_mult", 1.0))


func tick(sim: Sim, dt: float) -> void:
	sim.core_state["since_tap"] = float(sim.core_state["since_tap"]) + dt
	var hold := sim.best("combo_hold", float(sim.data["combo"]["hold_sec"]))
	if float(sim.core_state["since_tap"]) > hold and not sim.has("combo_no_reset"):
		sim.core_state["combo"] = 0
	sim.gain_auto(auto_rate(sim) * dt)
	sim.core_state["tap_credit"] = float(sim.core_state["tap_credit"]) + sim.tap_rate() * dt
	while float(sim.core_state["tap_credit"]) >= 1.0:
		sim.core_state["tap_credit"] = float(sim.core_state["tap_credit"]) - 1.0
		_do_tap(sim)


func note(sim: Sim) -> String:
	return "層%d" % int(sim.core_state["layer"])
