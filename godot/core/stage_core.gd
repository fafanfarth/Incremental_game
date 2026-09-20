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


## 反復購入の現在価格。repeat_items と UI からの購入で同じ式を使う
func repeat_cost(sim: Sim, item: Dictionary) -> float:
	var n: int = int(sim.repeats[item["id"]])
	return float(item["base_cost"]) * pow(float(item["growth"]), n)


func repeat_definition(sim: Sim, item_id: String) -> Dictionary:
	for item in catalog(sim):
		if item["id"] == item_id:
			return item
	return {}


## その反復購入を今買えるか（定員と前提を見る）
func repeat_available(sim: Sim, item: Dictionary) -> bool:
	if int(sim.repeats[item["id"]]) >= capacity(sim, item):
		return false
	var req: Variant = item.get("requires", null)
	return req == null or int(sim.repeats.get(req["id"], 0)) >= int(req["count"])


func repeat_items(sim: Sim) -> Array:
	var out: Array = []
	for item in catalog(sim):
		if repeat_available(sim, item):
			out.append({"id": item["id"], "cost": repeat_cost(sim, item)})
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


## プレイヤーが主アクション（タップ等）を1回行ったときの処理。
## シミュレータは profile.taps_per_sec から自動で叩くが、実機ではこちらを呼ぶ。
func player_action(_sim: Sim) -> void:
	pass


func note(_sim: Sim) -> String:
	return ""
