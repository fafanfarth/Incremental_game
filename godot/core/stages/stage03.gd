class_name CasinoCore
extends StageCore
## ステージ3「食堂棟」― 割合ベットの複利。
##
##     r = (実効期待値 − 1) × ベット率
##
## 本作で唯一、収入が「レート」ではなく「所持額に比例した成長率」になる。
## ベット率の上限（A系統）と疑念値（D系統）だけが律速であり、
## どちらかを一方的に強くすると即座に壊れる（docs/04 4.4）。
##
## prototype/cores.py の CasinoCore と1行ずつ対応する。片方だけ直さないこと。

func init_state(sim: Sim) -> void:
	super.init_state(sim)
	sim.core_state["suspicion"] = 0.0


## 実際に賭ける割合。
##
## 上限いっぱいで振り続けると疑念値が飽和して実効期待値が 1 を割る。
## 人間は「溜まったら絞って冷ます」ので、その振る舞いを再現する
## （docs/03 3.3 のアクセルとブレーキ）。
func bet_ratio(sim: Sim) -> float:
	var dc: Dictionary = sim.data["dice"]
	var base := float(dc["bet_ratio_base"])
	var top := sim.best("bet_ratio", base)
	var s := float(sim.core_state["suspicion"])
	if s >= float(dc["cool_down_at"]):
		return base
	if s >= float(dc["throttle_at"]):
		return base + (top - base) * 0.4
	return top


func ev(sim: Sim) -> float:
	var dc: Dictionary = sim.data["dice"]
	var base_ev := float(dc["ev_base"]) + sim.total("ev_add")
	var decay := float(dc["ev_at_max_suspicion"])
	var s := float(sim.core_state["suspicion"]) / 100.0
	return base_ev * (1.0 - s) + decay * s


## 1秒あたりの投擲回数。手動と自動投擲の合計。
func roll_rate(sim: Sim) -> float:
	var dc: Dictionary = sim.data["dice"]
	var rate := 0.0
	if sim.has("auto_roll"):
		rate += 1.0 / float(dc["auto_roll_sec"])
	rate += minf(sim.tap_rate_nominal(), 1.0 / float(dc["manual_roll_sec"]))
	return rate * sim.product("roll_speed")


## 複利を「いまの所持額に対する1秒あたりの増分」として表す。
func auto_rate(sim: Sim) -> float:
	var r := (ev(sim) - 1.0) * bet_ratio(sim)
	return maxf(0.0, sim.currency * r * roll_rate(sim))


## スクラッチ券。疑念値が上がらない安全な稼ぎ。
func manual_rate(sim: Sim) -> float:
	var sc: Dictionary = sim.data["scratch"]
	return sim.tap_rate_nominal() * float(sc["per_card"]) \
		* sim.product("scratch_mult") * sim.manual_mult()


func tick(sim: Sim, dt: float) -> void:
	var dc: Dictionary = sim.data["dice"]
	var rolls := roll_rate(sim) * dt
	if rolls > 0.0 and sim.currency > 0.0:
		var r := (ev(sim) - 1.0) * bet_ratio(sim)
		sim.gain_auto(sim.currency * r * rolls)
		var up := maxf(0.0, bet_ratio(sim) - float(dc["bet_ratio_base"])) \
			* float(dc["suspicion_per_bet"])
		sim.core_state["suspicion"] = float(sim.core_state["suspicion"]) + up * rolls * 100.0
	var decay := float(dc["suspicion_decay"]) * sim.product("suspicion_decay_mult")
	sim.core_state["suspicion"] = clampf(
		float(sim.core_state["suspicion"]) - decay * dt, 0.0, 100.0)
	sim.gain_manual(manual_rate(sim) * dt)


func note(sim: Sim) -> String:
	return "疑念%d%% 実効%.2f 率%d%%" % [
		int(round(float(sim.core_state["suspicion"]))), ev(sim), int(round(bet_ratio(sim) * 100.0))]
