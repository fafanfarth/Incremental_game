#!/usr/bin/env python3
"""全ステージ共通のシミュレーションエンジン（Phase 0 数値プロトタイプ）。

設計上の制約（docs/07 Phase 0、docs/09 NFR-30）:
  - 固定タイムステップ 60Hz で進む。描画は一切持たない
  - 同じ seed と同じ JSON からは必ず同じ結果になる
  - 数値は全て prototype/data/stageNN.json から読む

ステージ固有の稼ぎ方は cores.py の StageCore が持つ。
このファイルは「通貨・スキル・購入方針・抜き打ち検査・賄賂」だけを扱う。
"""
from __future__ import annotations

import json
import math
import random
from dataclasses import dataclass, field
from pathlib import Path

TICK_HZ = 60
DT = 1.0 / TICK_HZ

DATA_DIR = Path(__file__).parent / "data"


def load(stage: str) -> dict:
    return json.loads((DATA_DIR / f"{stage}.json").read_text(encoding="utf-8"))


@dataclass
class Profile:
    """プレイヤーの振る舞い。これを変えて同じ経済を別の遊び方で回す。"""
    name: str
    taps_per_sec: float
    active_ratio: float = 1.0
    purchase_pause_sec: float = 2.5
    inspection_choice: str = "bribe"   # "hide" か "bribe"
    max_sec: float = 8 * 3600


@dataclass
class Snapshot:
    t: float
    currency: float
    lifetime: float
    cps_auto: float
    cps_manual: float
    skills: int
    note: str = ""


@dataclass
class State:
    currency: float = 0.0
    lifetime: float = 0.0
    spent: float = 0.0
    purchase_pause: float = 0.0
    boost_remaining: float = 0.0
    boost_mult_active: float = 1.0
    next_inspection: float = 0.0
    owned: set = field(default_factory=set)
    repeats: dict = field(default_factory=dict)
    manual_income: float = 0.0
    auto_income: float = 0.0
    core: dict = field(default_factory=dict)


class Sim:
    def __init__(self, profile: Profile, data: dict, core, seed: int = 1):
        self.p = profile
        self.d = data
        self.core = core
        self.rng = random.Random(seed)
        self.s = State()
        self.skills = {sk["id"]: sk for sk in self.d["skills"]}
        self.t = 0.0
        self.history: list[Snapshot] = []
        self.log: list[tuple[float, str]] = []
        self.cleared_at: float | None = None
        ins = self.d.get("inspection")
        self.s.next_inspection = ins["first_sec"] if ins else math.inf
        self.core.init_state(self)

    # ---------- スキル効果 ----------

    def effects(self, etype: str):
        for sid in self.s.owned:
            for e in self.skills[sid]["effects"]:
                if e["type"] == etype:
                    yield e

    def has(self, etype: str) -> bool:
        return any(True for _ in self.effects(etype))

    def best(self, etype: str, default):
        """同種の効果は置き換え。上位ティアが下位を上書きする。"""
        vals = [e["value"] for e in self.effects(etype)]
        return max(vals) if vals else default

    def product(self, etype: str) -> float:
        m = 1.0
        for e in self.effects(etype):
            m *= e["value"]
        return m

    def total(self, etype: str) -> float:
        return sum(e["value"] for e in self.effects(etype))

    @property
    def boost(self) -> float:
        return self.s.boost_mult_active if self.s.boost_remaining > 0 else 1.0

    @property
    def manual_mult(self) -> float:
        """手動由来の獲得にのみ乗る倍率（A系統）。自動収入には乗せない。"""
        return self.product("manual_mult") * self.boost

    @property
    def auto_mult(self) -> float:
        """自動収入にのみ乗る倍率（C系統）。A系統は乗らない。"""
        return self.product("auto_mult") * self.boost

    @property
    def tap_rate(self) -> float:
        """実際にこのフレームで発生するタップ速度。購入操作中は手が止まる。"""
        rate = self.best("autotap", 0.0)
        if self.s.purchase_pause <= 0 and self.core.can_act(self):
            rate += self.p.taps_per_sec * self.p.active_ratio
        return rate

    @property
    def tap_rate_nominal(self) -> float:
        """購入判断と表示に使う平常時のタップ速度。

        購入の直後は tap_rate が 0 になるため、そのまま購入方針に使うと
        「手動収入ゼロ」と誤認して手動系スキルを一切買わなくなる。
        """
        return self.best("autotap", 0.0) + self.p.taps_per_sec * self.p.active_ratio

    # ---------- 購入 ----------

    def skill_available(self, sk: dict) -> bool:
        return sk["id"] not in self.s.owned and all(r in self.s.owned for r in sk["requires"])

    def bribe_unlocked(self) -> bool:
        if self.d["bribe"].get("unlock_rule") != "all_branches_tier4":
            return True
        return all(
            any(self.skills[sid]["branch"] == br and self.skills[sid]["tier"] >= 4
                for sid in self.s.owned)
            for br in ("A", "B", "C", "D")
        )

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

        base = self.core.estimated_income(self)
        best, best_pb = None, math.inf

        for item in self.core.repeat_items(self):
            if item["cost"] > self.s.currency:
                continue
            gain = self.core.gain_if_repeat(self, item["id"]) - base
            pb = self._payback(item["cost"], gain)
            if pb < best_pb:
                best, best_pb = ("repeat", item, item["cost"]), pb

        for sk in self.d["skills"]:
            if not self.skill_available(sk) or sk["cost"] > self.s.currency:
                continue
            self.s.owned.add(sk["id"])
            try:
                gain = self.core.estimated_income(self) - base
            finally:
                self.s.owned.discard(sk["id"])
            # 収入に直結しない枝も死に枝にしないため、最低限の評価値を置く
            if gain <= 0:
                gain = sk["cost"] / 3600.0
            pb = self._payback(sk["cost"], gain)
            if pb < best_pb:
                best, best_pb = ("skill", sk, sk["cost"]), pb

        if best is None:
            return False

        kind, item, cost = best
        self.s.currency -= cost
        self.s.spent += cost
        if kind == "repeat":
            self.core.buy_repeat(self, item["id"])
        else:
            self.s.owned.add(item["id"])
            self.log.append((self.t, f"{item['id']} {item['name']} ({cost:,.0f})"))
        self.s.purchase_pause = self.p.purchase_pause_sec
        return True

    # ---------- 1フレーム ----------

    def gain_manual(self, amount: float) -> None:
        self.s.currency += amount
        self.s.lifetime += amount
        self.s.manual_income += amount

    def gain_auto(self, amount: float) -> None:
        self.s.currency += amount
        self.s.lifetime += amount
        self.s.auto_income += amount

    def _start_boost(self, mult: float, sec: float) -> None:
        self.s.boost_mult_active = mult
        self.s.boost_remaining = max(self.s.boost_remaining, sec)

    def _run_inspection(self) -> None:
        ins = self.d["inspection"]
        if self.s.currency >= self.d["bribe"]["cost"]:
            return  # 100万到達後は検査なし（R-09）
        if self.p.inspection_choice == "bribe":
            self.s.currency *= 1 - ins["bribe_cost"]
            self._start_boost(ins["bribe_boost_mult"], ins["bribe_boost_sec"])
        else:
            rate = self.best("hide_success_rate", ins["hide_success_rate"])
            if self.rng.random() < rate:
                self._start_boost(ins["hide_boost_mult"], ins["hide_boost_sec"])
            else:
                self.s.currency *= 1 - ins["hide_fail_loss"]
        self.s.next_inspection = self.t + self.rng.uniform(
            ins["interval_min_sec"], ins["interval_max_sec"]
        )

    def step(self) -> None:
        s = self.s
        s.purchase_pause = max(0.0, s.purchase_pause - DT)
        s.boost_remaining = max(0.0, s.boost_remaining - DT)

        self.core.tick(self, DT)

        for e in self.effects("booster"):
            if s.boost_remaining <= 0 and not s.core.get("_boost_cd", 0) > self.t:
                self._start_boost(e["mult"], e["duration_sec"])
                s.core["_boost_cd"] = self.t + e["cooldown_sec"]
            break

        if self.t >= s.next_inspection:
            self._run_inspection()

        self.t += DT

    def run(self, snapshot_every: float = 30.0) -> "Sim":
        next_snap, next_buy = 0.0, 0.0
        while self.t < self.p.max_sec and self.cleared_at is None:
            self.step()
            if self.t >= next_buy:
                while self.try_purchase() and self.cleared_at is None:
                    pass
                next_buy = self.t + 0.5
            if self.t >= next_snap:
                self.history.append(Snapshot(
                    t=self.t, currency=self.s.currency, lifetime=self.s.lifetime,
                    cps_auto=self.core.auto_rate(self), cps_manual=self.core.manual_rate(self),
                    skills=len(self.s.owned), note=self.core.note(self),
                ))
                next_snap = self.t + snapshot_every
        return self
