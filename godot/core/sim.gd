class_name Sim
extends RefCounted
## 全ステージ共通のシミュレーションエンジン（12章 12.2-④ / NFR-43）。
##
## Node に依存しない。描画も持たない。固定タイムステップ 60Hz で進む。
## 同じ seed と同じ JSON からは必ず同じ結果になる。
##
## prototype/sim.py の移植であり、両者が一致することを CI の parity ジョブが保証する。
## 片方だけ直してはならない（NFR-46）。

const TICK_HZ := 60
const DT := 1.0 / float(TICK_HZ)

var profile: SimProfile
var data: Dictionary
var core: StageCore
var rng: DetRng

var t: float = 0.0
var cleared_at: float = -1.0

var currency: float = 0.0
var lifetime: float = 0.0
var spent: float = 0.0
var purchase_pause: float = 0.0
var boost_remaining: float = 0.0
var boost_mult_active: float = 1.0
var next_inspection: float = INF
var owned: Dictionary = {}          # スキルID -> true
var repeats: Dictionary = {}        # 反復購入ID -> 個数
var core_state: Dictionary = {}

var _skills: Dictionary = {}        # スキルID -> 定義
var _log: Array[String] = []

## [経過秒, 生涯獲得] の並び。parity の診断に使う
var checkpoints: Array = []

## 抜き打ち検査が実際に発生した時刻。parity の診断に使う
var inspection_times: Array = []


func _init(p_profile: SimProfile, p_data: Dictionary, p_core: StageCore, p_seed: int = 1) -> void:
	profile = p_profile
	data = p_data
	core = p_core
	rng = DetRng.new(p_seed)
	for sk in data["skills"]:
		_skills[sk["id"]] = sk
	if data.has("inspection"):
		next_inspection = float(data["inspection"]["first_sec"])
	core.init_state(self)


# ---------- スキル効果 ----------

func effects(etype: String) -> Array:
	var out: Array = []
	for sid in owned:
		for e in _skills[sid]["effects"]:
			if e["type"] == etype:
				out.append(e)
	return out


func has(etype: String) -> bool:
	return not effects(etype).is_empty()


## 同種の効果は置き換え。上位ティアが下位を上書きする。
func best(etype: String, fallback: float) -> float:
	var v := fallback
	var found := false
	for e in effects(etype):
		var x := float(e["value"])
		if not found or x > v:
			v = x
			found = true
	return v


func product(etype: String) -> float:
	var m := 1.0
	for e in effects(etype):
		m *= float(e["value"])
	return m


func total(etype: String) -> float:
	var s := 0.0
	for e in effects(etype):
		s += float(e["value"])
	return s


func boost() -> float:
	return boost_mult_active if boost_remaining > 0.0 else 1.0


## 手動由来の獲得にのみ乗る倍率（A系統）。自動収入には乗せない。
## これを破ると反復購入の回収時間が数百分の1に潰れて経済が崩壊する（11章 11.2-③）。
func manual_mult() -> float:
	return product("manual_mult") * boost()


## 自動収入にのみ乗る倍率（C系統）。A系統は乗らない。
func auto_mult() -> float:
	return product("auto_mult") * boost()


## 実際にこのフレームで発生するタップ速度。購入操作中は手が止まる。
func tap_rate() -> float:
	var rate := best("autotap", 0.0)
	if profile.simulated and purchase_pause <= 0.0 and core.can_act(self):
		rate += profile.taps_per_sec * profile.active_ratio
	return rate


## 購入判断と表示に使う平常時のタップ速度。
## 購入直後は tap_rate が 0 になるため、そのまま判断に使うと
## 「手動収入ゼロ」と誤認して手動系スキルを一切買わなくなる。
func tap_rate_nominal() -> float:
	return best("autotap", 0.0) + profile.taps_per_sec * profile.active_ratio


# ---------- 購入 ----------

func skill_available(sk: Dictionary) -> bool:
	if owned.has(sk["id"]):
		return false
	for r in sk["requires"]:
		if not owned.has(r):
			return false
	return true


func bribe_unlocked() -> bool:
	if data["bribe"].get("unlock_rule", "") != "all_branches_tier4":
		return true
	for br in ["A", "B", "C", "D"]:
		var ok := false
		for sid in owned:
			var sk: Dictionary = _skills[sid]
			if sk["branch"] == br and int(sk["tier"]) >= 4:
				ok = true
				break
		if not ok:
			return false
	return true


## 払える中で最も回収の速いものを1つ買う。賄賂は常に最優先。
func try_purchase() -> bool:
	var bribe_cost := float(data["bribe"]["cost"])
	if bribe_unlocked() and currency >= bribe_cost:
		currency -= bribe_cost
		spent += bribe_cost
		cleared_at = t
		_log.append("【賄賂】購入 → ステージクリア")
		return true

	var base := core.estimated_income(self)
	var best_kind := ""
	var best_item: Variant = null
	var best_cost := 0.0
	var best_pb := INF

	for item in core.repeat_items(self):
		var cost := float(item["cost"])
		if cost > currency:
			continue
		var gain: float = core.gain_if_repeat(self, item["id"]) - base
		if gain <= 0.0:
			continue
		var pb := cost / gain
		if pb < best_pb:
			best_kind = "repeat"
			best_item = item
			best_cost = cost
			best_pb = pb

	for sk in data["skills"]:
		var cost := float(sk["cost"])
		if not skill_available(sk) or cost > currency:
			continue
		owned[sk["id"]] = true
		var gain: float = core.estimated_income(self) - base
		owned.erase(sk["id"])
		# 収入に直結しない枝も死に枝にしないため、最低限の評価値を置く
		if gain <= 0.0:
			gain = cost / 3600.0
		var pb := cost / gain
		if pb < best_pb:
			best_kind = "skill"
			best_item = sk
			best_cost = cost
			best_pb = pb

	if best_kind == "":
		return false

	currency -= best_cost
	spent += best_cost
	if best_kind == "repeat":
		core.buy_repeat(self, best_item["id"])
	else:
		owned[best_item["id"]] = true
		_log.append("%s %s (%d)" % [best_item["id"], best_item["name"], int(best_cost)])
	purchase_pause = profile.purchase_pause_sec
	return true


# ---------- プレイヤーからの操作（UI が呼ぶ） ----------

signal purchased(kind: String, id: String)
signal cleared()

## 主アクションを1回。ステージごとの意味は StageCore.player_action が決める
func player_action() -> void:
	core.player_action(self)


func skill_by_id(id: String) -> Dictionary:
	return _skills.get(id, {})


func can_buy_skill(id: String) -> bool:
	var sk: Dictionary = _skills.get(id, {})
	return not sk.is_empty() and skill_available(sk) and currency >= float(sk["cost"])


func buy_skill(id: String) -> bool:
	if not can_buy_skill(id):
		return false
	var sk: Dictionary = _skills[id]
	currency -= float(sk["cost"])
	spent += float(sk["cost"])
	owned[id] = true
	_log.append("%s %s (%d)" % [id, sk["name"], int(float(sk["cost"]))])
	purchased.emit("skill", id)
	return true


func repeat_price(id: String) -> float:
	var item := core.repeat_definition(self, id)
	return INF if item.is_empty() else core.repeat_cost(self, item)


func can_buy_repeat(id: String) -> bool:
	var item := core.repeat_definition(self, id)
	if item.is_empty() or not core.repeat_available(self, item):
		return false
	return currency >= core.repeat_cost(self, item)


func buy_repeat(id: String) -> bool:
	if not can_buy_repeat(id):
		return false
	var item := core.repeat_definition(self, id)
	var cost := core.repeat_cost(self, item)
	currency -= cost
	spent += cost
	core.buy_repeat(self, id)
	purchased.emit("repeat", id)
	return true


## 買えるだけ買う（×10 / ×MAX ボタン用）。買えた数を返す
func buy_repeat_bulk(id: String, count: int) -> int:
	var bought := 0
	while bought < count and buy_repeat(id):
		bought += 1
	return bought


func can_buy_bribe() -> bool:
	return cleared_at < 0.0 and bribe_unlocked() and currency >= float(data["bribe"]["cost"])


func buy_bribe() -> bool:
	if not can_buy_bribe():
		return false
	var cost := float(data["bribe"]["cost"])
	currency -= cost
	spent += cost
	cleared_at = t
	_log.append("【賄賂】購入 → ステージクリア")
	cleared.emit()
	return true


func goal() -> float:
	return float(data["bribe"]["cost"])


func progress() -> float:
	return clampf(currency / goal(), 0.0, 1.0)


# ---------- 1フレーム ----------

func gain_manual(amount: float) -> void:
	currency += amount
	lifetime += amount


func gain_auto(amount: float) -> void:
	currency += amount
	lifetime += amount


func start_boost(mult: float, sec: float) -> void:
	boost_mult_active = mult
	boost_remaining = maxf(boost_remaining, sec)


func _run_inspection() -> void:
	var ins: Dictionary = data["inspection"]
	if currency >= float(data["bribe"]["cost"]):
		return  # 100万到達後は検査なし（R-09）
	if profile.inspection_choice == "bribe":
		currency *= 1.0 - float(ins["bribe_cost"])
		start_boost(float(ins["bribe_boost_mult"]), float(ins["bribe_boost_sec"]))
	else:
		var rate := best("hide_success_rate", float(ins["hide_success_rate"]))
		if rng.next_float() < rate:
			start_boost(float(ins["hide_boost_mult"]), float(ins["hide_boost_sec"]))
		else:
			currency *= 1.0 - float(ins["hide_fail_loss"])
	inspection_times.append(t)
	next_inspection = t + rng.range_float(
		float(ins["interval_min_sec"]), float(ins["interval_max_sec"]))


func step() -> void:
	purchase_pause = maxf(0.0, purchase_pause - DT)
	boost_remaining = maxf(0.0, boost_remaining - DT)

	core.tick(self, DT)

	var boosters := effects("booster")
	if not boosters.is_empty():
		var e: Dictionary = boosters[0]
		var cd := float(core_state.get("_boost_cd", 0.0))
		if boost_remaining <= 0.0 and cd <= t:
			start_boost(float(e["mult"]), float(e["duration_sec"]))
			core_state["_boost_cd"] = t + float(e["cooldown_sec"])

	if t >= next_inspection:
		_run_inspection()

	t += DT


## ヘッドレスで一気に回す。実機では _physics_process から step() を1回ずつ呼ぶ。
##
## snapshot_every を渡すと checkpoints に [経過秒, 生涯獲得] を積む。
## prototype/sim.py の run() と記録位置を揃えてあること。
func run(snapshot_every: float = 0.0) -> Sim:
	var next_buy := 0.0
	var next_snap := 0.0
	while t < profile.max_sec and cleared_at < 0.0:
		step()
		if t >= next_buy:
			while try_purchase() and cleared_at < 0.0:
				pass
			next_buy = t + 0.5
		if snapshot_every > 0.0 and t >= next_snap:
			checkpoints.append([t, lifetime])
			next_snap = t + snapshot_every
	return self


func purchase_log() -> Array[String]:
	return _log
