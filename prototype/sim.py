#!/usr/bin/env python3
"""ステージ1「独房棟」の経済シミュレータ（Phase 0 数値プロトタイプ）。

設計上の制約（docs/07 Phase 0、docs/09 NFR-30）:
  - 固定タイムステップ 60Hz で進む。描画は一切持たない
  - 同じ seed と同じ設定からは必ず同じ結果になる
  - 数値は全て prototype/data/stage01.json から読む

このファイルはゲームロジックだけを持つ。プロファイル比較と表の出力は
run_balance.py の側にある。
"""
from __future__ import annotations

import json
import math
import random
from dataclasses import dataclass, field
from pathlib import Path

TICK_HZ = 60
DT = 1.0 / TICK_HZ

DATA_PATH = Path(__file__).parent / "data" / "stage01.json"


@dataclass
class Profile:
    """プレイヤーの振る舞い。これを変えて同じ経済を別の遊び方で回す。"""
    name: str
    taps_per_sec: float          # 画面を触っている間のタップ速度
    active_ratio: float = 1.0    # 起きている時間のうち、実際に触っている割合
    purchase_pause_sec: float = 2.5   # 購入操作のために手が止まる時間
    inspection_choice: str = "bribe"  # "hide" か "bribe"
    max_sec: float = 6 * 3600


@dataclass
class Snapshot:
    t: float
    currency: float
    lifetime: float
    cps_auto: float
    cps_manual: float
    layer: int
    skills: int


@dataclass
class State:
    currency: float = 0.0
    lifetime: float = 0.0
    layer: int = 0
    layer_damage: float = 0.0
    combo: int = 0
    since_last_tap: float = 0.0
    tap_credit: float = 0.0
    purchase_pause: float = 0.0
    boost_remaining: float = 0.0
    boost_cooldown: float = 0.0
    next_inspection: float = 0.0
    owned: set = field(default_factory=set)
    subs: dict = field(default_factory=dict)
    hidden_taken: set = field(default_factory=set)
    spent: float = 0.0
    manual_income: float = 0.0
    auto_income: float = 0.0


class Sim:
    def __init__(self, profile: Profile, data: dict | None = None, seed: int = 1):
        self.p = profile
        self.d = data if data is not None else json.loads(DATA_PATH.read_text(encoding="utf-8"))
        self.rng = random.Random(seed)
        self.s = State()
        self.s.next_inspection = self.d["inspection"]["first_sec"]
        for sub in self.d["subordinates"]:
            self.s.subs[sub["id"]] = 0
        self.skills = {sk["id"]: sk for sk in self.d["skills"]}
        self.t = 0.0
        self.history: list[Snapshot] = []
        self.log: list[tuple[float, str]] = []
        self.cleared_at: float | None = None

    # ---------- 派生値 ----------

    def _effects(self, etype: str):
        for sid in self.s.owned:
            for e in self.skills[sid]["effects"]:
                if e["type"] == etype:
                    yield e

    def _has(self, etype: str) -> bool:
        return any(True for _ in self._effects(etype))

    def _last(self, etype: str, default):
        """同種の効果は「置き換え」。上位ティアを買うと下位を上書きする。"""
        vals = [e["value"] for e in self._effects(etype)]
        return max(vals) if vals else default

    @property
    def boost_mult(self) -> float:
        if self.s.boost_remaining <= 0:
            return 1.0
        for e in self._effects("booster"):
            return e["mult"]
        return 1.0

    @property
    def manual_mult(self) -> float:
        """手動（タップ・層報酬・隠し物）にのみ乗る倍率。A系統。"""
        m = self.boost_mult
        for e in self._effects("manual_mult"):
            m *= e["value"]
        return m

    @property
    def auto_mult(self) -> float:
        """自動収入にのみ乗る倍率。C系統。A系統は乗らない。"""
        m = self.boost_mult
        for e in self._effects("sub_cps_mult"):
            m *= e["value"]
        return m

    @property
    def tap_power(self) -> float:
        """1タップが壁に与えるダメージ（＝通貨換算前の素の獲得量）。"""
        base = self.d["wall"]["tap_power_base"]
        base += sum(e["value"] for e in self._effects("tap_add"))
        for e in self._effects("tap_mult"):
            base *= e["value"]
        return base * self._last("tap_hits", 1)

    @property
    def combo_mult(self) -> float:
        c = self.d["combo"]
        cap = self._last("combo_cap", c["cap"])
        return 1.0 + min((self.s.combo // 10) * c["bonus_per_10"], cap)

    @property
    def cps_subs(self) -> float:
        total = sum(
            self.s.subs[sub["id"]] * sub["cps"] for sub in self.d["subordinates"]
        )
        total += sum(e["value"] for e in self._effects("flat_cps"))
        for e in self._effects("auto_from_tap"):
            total += self.tap_power * e["value"]
        return total

    def cps_auto_now(self, lights_out: bool) -> float:
        cps = self.cps_subs * self.auto_mult
        if lights_out:
            cps *= self._last("lights_out_auto_mult", self.d["lights_out"]["auto_mult"])
        return cps

    @property
    def lights_out(self) -> bool:
        lo = self.d["lights_out"]
        return (self.t % lo["period_sec"]) >= (lo["period_sec"] - lo["duration_sec"])

    def can_tap(self) -> bool:
        if self.s.purchase_pause > 0:
            return False
        if self.lights_out and not self._has("tap_during_lights_out"):
            return False
        return True

    # ---------- 購入 ----------

    def sub_cost(self, sub: dict) -> float:
        return sub["base_cost"] * (sub["growth"] ** self.s.subs[sub["id"]])

    def sub_available(self, sub: dict) -> bool:
        if self.s.subs[sub["id"]] >= sub.get("capacity", 10 ** 9):
            return False
        req = sub["requires"]
        return req is None or self.s.subs[req["id"]] >= req["count"]

    def skill_available(self, sk: dict) -> bool:
        return sk["id"] not in self.s.owned and all(r in self.s.owned for r in sk["requires"])

    def bribe_unlocked(self) -> bool:
        if self.d["bribe"]["unlock_rule"] != "all_branches_tier4":
            return True
        for br in ("A", "B", "C", "D"):
            if not any(
                self.skills[sid]["branch"] == br and self.skills[sid]["tier"] >= 4
                for sid in self.s.owned
            ):
                return False
        return True

    def _income_with(self, delta_cps: float = 0.0, delta_tap: float = 0.0) -> float:
        """おおまかな総収入レート。購入の良し悪しを比べるためだけに使う。"""
        tap_rate = self.p.taps_per_sec * self.p.active_ratio
        tap_rate += self._last("autotap", 0.0)
        manual = (self.tap_power + delta_tap) * 1.5 * tap_rate * self.manual_mult
        auto = (self.cps_subs + delta_cps) * self.auto_mult
        return manual + auto

    def _payback(self, cost: float, gain: float) -> float:
        return math.inf if gain <= 0 else cost / gain

    def try_purchase(self) -> bool:
        """払える中で最も回収の速いものを1つ買う。賄賂は常に最優先。"""
        if self.bribe_unlocked() and self.s.currency >= self.d["bribe"]["cost"]:
            self.s.currency -= self.d["bribe"]["cost"]
            self.s.spent += self.d["bribe"]["cost"]
            self.cleared_at = self.t
            self.log.append((self.t, "【賄賂】購入 → ステージクリア"))
            return True

        base = self._income_with()
        best, best_pb = None, math.inf

        for sub in self.d["subordinates"]:
            if not self.sub_available(sub):
                continue
            cost = self.sub_cost(sub)
            if cost > self.s.currency:
                continue
            gain = self._income_with(delta_cps=sub["cps"]) - base
            pb = self._payback(cost, gain)
            if pb < best_pb:
                best, best_pb = ("sub", sub, cost), pb

        for sk in self.d["skills"]:
            if not self.skill_available(sk) or sk["cost"] > self.s.currency:
                continue
            gain = self._simulated_gain(sk, base)
            pb = self._payback(sk["cost"], gain)
            if pb < best_pb:
                best, best_pb = ("skill", sk, sk["cost"]), pb

        if best is None:
            return False

        kind, item, cost = best
        self.s.currency -= cost
        self.s.spent += cost
        if kind == "sub":
            self.s.subs[item["id"]] += 1
        else:
            self.s.owned.add(item["id"])
            self.log.append((self.t, f"{item['id']} {item['name']} ({cost:,.0f})"))
        self.s.purchase_pause = self.p.purchase_pause_sec
        return True

    def _simulated_gain(self, sk: dict, base: float) -> float:
        """スキルを買ったと仮定して収入レートの差分を測る。効果ごとの分岐を避ける。"""
        self.s.owned.add(sk["id"])
        try:
            gain = self._income_with() - base
        finally:
            self.s.owned.discard(sk["id"])
        # 収入に直結しない枝（検査対策など）にも最低限の値を置き、死に枝にしない
        if gain <= 0:
            return sk["cost"] / 3600.0
        return gain

    # ---------- 1フレーム ----------

    def _gain(self, amount: float) -> None:
        self.s.currency += amount
        self.s.lifetime += amount

    def _do_tap(self) -> None:
        c = self.d["combo"]
        hold = self._last("combo_hold", c["hold_sec"])
        if self.s.since_last_tap <= c["chain_window_sec"] or self._has("combo_no_reset"):
            self.s.combo += 1
        elif self.s.since_last_tap > hold and not self._has("combo_no_reset"):
            self.s.combo = 1
        else:
            self.s.combo += 1
        self.s.since_last_tap = 0.0

        power = self.tap_power * self.combo_mult
        for e in self._effects("crit"):
            if self.rng.random() < e["chance"]:
                power *= e["mult"]
            break

        amount = power * self.manual_mult
        for e in self._effects("lucky"):
            if self.rng.random() < e["chance"]:
                amount += e["amount"] * self.manual_mult
            break
        self._gain(amount)
        self.s.manual_income += amount

        self.s.layer_damage += power
        w = self.d["wall"]
        while True:
            need = w["layer_damage_base"] * (w["layer_damage_growth"] ** self.s.layer)
            if self.s.layer_damage < need:
                break
            self.s.layer_damage -= need
            self.s.layer += 1
            reward = w["layer_reward_base"] * (w["layer_reward_growth"] ** self.s.layer)
            self._gain(reward * self.manual_mult)
            self.s.manual_income += reward * self.manual_mult
            self._check_hidden_item()

    def _check_hidden_item(self) -> None:
        """隠し物は『1回きりの固定報酬』。全体倍率もブーストも乗せない（docs/03 3.1）。

        乗せると層20の1個で45万が入り、成長曲線がそこで折れる（Phase 0 で判明）。
        """
        h = self.d["hidden_items"]
        if self.s.layer in h["layers"] and self.s.layer not in self.s.hidden_taken:
            self.s.hidden_taken.add(self.s.layer)
            w = self.d["wall"]
            base = w["layer_reward_base"] * (w["layer_reward_growth"] ** self.s.layer)
            mult = self._last("hidden_item_reward_mult", 1)
            self._gain(base * h["reward_multiple_of_layer"] * mult)

    def _run_inspection(self) -> None:
        ins = self.d["inspection"]
        if self.s.currency >= self.d["bribe"]["cost"]:
            return  # 100万到達後は検査なし（R-09）
        if self.p.inspection_choice == "bribe":
            self.s.currency *= 1 - ins["bribe_cost"]
            self.s.boost_remaining = max(self.s.boost_remaining, ins["bribe_boost_sec"])
        else:
            rate = self._last("hide_success_rate", ins["hide_success_rate"])
            if self.rng.random() >= rate:
                self.s.currency *= 1 - ins["hide_fail_loss"]
        self.s.next_inspection = self.t + self.rng.uniform(
            ins["interval_min_sec"], ins["interval_max_sec"]
        )

    def step(self) -> None:
        s = self.s
        s.since_last_tap += DT
        s.purchase_pause = max(0.0, s.purchase_pause - DT)
        s.boost_remaining = max(0.0, s.boost_remaining - DT)
        s.boost_cooldown = max(0.0, s.boost_cooldown - DT)

        hold = self._last("combo_hold", self.d["combo"]["hold_sec"])
        if s.since_last_tap > hold and not self._has("combo_no_reset"):
            s.combo = 0

        lo = self.lights_out
        auto = self.cps_auto_now(lo) * DT
        self._gain(auto)
        s.auto_income += auto

        rate = self._last("autotap", 0.0)
        if self.can_tap():
            rate += self.p.taps_per_sec * self.p.active_ratio
        s.tap_credit += rate * DT
        while s.tap_credit >= 1.0:
            s.tap_credit -= 1.0
            self._do_tap()

        for e in self._effects("booster"):
            if s.boost_cooldown <= 0 and s.boost_remaining <= 0:
                s.boost_remaining = e["duration_sec"]
                s.boost_cooldown = e["cooldown_sec"]
            break

        if self.t >= s.next_inspection:
            self._run_inspection()

        self.t += DT

    # ---------- 実行 ----------

    def run(self, snapshot_every: float = 30.0) -> "Sim":
        next_snap = 0.0
        next_buy = 0.0
        while self.t < self.p.max_sec and self.cleared_at is None:
            self.step()
            if self.t >= next_buy:
                while self.try_purchase():
                    if self.cleared_at is not None:
                        break
                next_buy = self.t + 0.5
            if self.t >= next_snap:
                self.history.append(
                    Snapshot(
                        t=self.t,
                        currency=self.s.currency,
                        lifetime=self.s.lifetime,
                        cps_auto=self.cps_auto_now(self.lights_out),
                        cps_manual=self.tap_power * self.combo_mult * self.manual_mult
                        * (self.p.taps_per_sec * self.p.active_ratio + self._last("autotap", 0.0)),
                        layer=self.s.layer,
                        skills=len(self.s.owned),
                    )
                )
                next_snap = self.t + snapshot_every
        return self
