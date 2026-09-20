class_name StageCore
extends RefCounted
## ステージごとの稼ぎ方の基底（prototype/cores.py の移植）。
##
## 各コアは「そのステージで最も壊れやすい部分」を再現することを優先する。

func init_state(sim: Sim) -> void:
	for item in catalog(sim):
		if not sim.repeats.has(item["id"]):
			sim.repeats[item["id"]] = 0


func catalog(sim: Sim) -> Array:
	return sim.data.get("repeats", [])


## 手動操作ができるか（ステージ1の消灯時間など）。
func can_act(_sim: Sim) -> bool:
	return true


func capacity(sim: Sim, item: Dictionary) -> int:
	var base: int = int(item.get("capacity", 1 << 30))
	return base + int(sim.total("repeat_capacity"))


func repeat_items(sim: Sim) -> Array:
	var out: Array = []
	for item in catalog(sim):
		var n: int = int(sim.repeats[item["id"]])
		if n >= capacity(sim, item):
			continue
		var req: Variant = item.get("requires", null)
		if req != null and int(sim.repeats.get(req["id"], 0)) < int(req["count"]):
			continue
		out.append({
			"id": item["id"],
			"cost": float(item["base_cost"]) * pow(float(item["growth"]), n),
		})
	return out


func buy_repeat(sim: Sim, item_id: String) -> void:
	sim.repeats[item_id] = int(sim.repeats[item_id]) + 1


func gain_if_repeat(sim: Sim, item_id: String) -> float:
	sim.repeats[item_id] = int(sim.repeats[item_id]) + 1
	var v := estimated_income(sim)
	sim.repeats[item_id] = int(sim.repeats[item_id]) - 1
	return v


func estimated_income(sim: Sim) -> float:
	return manual_rate(sim) + auto_rate(sim)


func manual_rate(_sim: Sim) -> float:
	return 0.0


func auto_rate(_sim: Sim) -> float:
	return 0.0


func tick(_sim: Sim, _dt: float) -> void:
	pass


func note(_sim: Sim) -> String:
	return ""
