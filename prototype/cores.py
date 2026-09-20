#!/usr/bin/env python3
"""ステージごとの稼ぎ方（StageCore）。

各コアは「そのステージで最も壊れやすい部分」を再現することを優先し、
遊びとしての細部（見た目・演出・操作感）は持たない。
Phase 0 の目的は経済の検証であって、ゲームを動かすことではない。

| ステージ | 再現する危険 |
|---|---|
| 1 独房棟 | 層報酬の発散と、反復購入の回収時間 |
| 2 労役棟 | 加工チェーンの価値が ×12 ずつ跳ねる指数 |
| 3 食堂棟 | 期待値プラスの複利。ベット率と疑念値だけが律速 |
| 4 医務棟 | ランク価値 3^(R-1) と盤面の有限性のせめぎ合い |
| 5 時計塔 | 平均倍率 E[M] と基礎搬出量の積 |
"""
from __future__ import annotations

import math


class StageCore:
    """共通の骨。ステージ固有の部分だけを各コアが上書きする。"""

    def init_state(self, sim) -> None:
        for item in self.catalog(sim):
            sim.s.repeats.setdefault(item["id"], 0)

    def catalog(self, sim) -> list[dict]:
        return sim.d.get("repeats", [])

    def can_act(self, sim) -> bool:
        """手動操作ができるか（ステージ1の消灯時間など）。"""
        return True

    def repeat_items(self, sim) -> list[dict]:
        out = []
        for item in self.catalog(sim):
            n = sim.s.repeats[item["id"]]
            if n >= self.capacity(sim, item):
                continue
            req = item.get("requires")
            if req and sim.s.repeats.get(req["id"], 0) < req["count"]:
                continue
            out.append({"id": item["id"], "cost": item["base_cost"] * item["growth"] ** n})
        return out

    def capacity(self, sim, item: dict) -> int:
        return item.get("capacity", 10 ** 9) + int(sim.total("repeat_capacity"))

    def buy_repeat(self, sim, item_id: str) -> None:
        sim.s.repeats[item_id] += 1

    def gain_if_repeat(self, sim, item_id: str) -> float:
        sim.s.repeats[item_id] += 1
        try:
            return self.estimated_income(sim)
        finally:
            sim.s.repeats[item_id] -= 1

    def estimated_income(self, sim) -> float:
        return self.manual_rate(sim) + self.auto_rate(sim)

    def manual_rate(self, sim) -> float:
        raise NotImplementedError

    def auto_rate(self, sim) -> float:
        raise NotImplementedError

    def tick(self, sim, dt: float) -> None:
        raise NotImplementedError

    def note(self, sim) -> str:
        return ""


# --------------------------------------------------------------------------
# ステージ1：独房棟 ― 壁削りと子分（反復購入の逓増コスト）
# --------------------------------------------------------------------------
class CellBlockCore(StageCore):
    def init_state(self, sim) -> None:
        super().init_state(sim)
        c = sim.s.core
        c.update(layer=0, layer_damage=0.0, combo=0, since_tap=0.0,
                 tap_credit=0.0, hidden=set())

    def can_act(self, sim) -> bool:
        lo = sim.d["lights_out"]
        dark = (sim.t % lo["period_sec"]) >= (lo["period_sec"] - lo["duration_sec"])
        return (not dark) or sim.has("tap_during_lights_out")

    def _dark(self, sim) -> bool:
        lo = sim.d["lights_out"]
        return (sim.t % lo["period_sec"]) >= (lo["period_sec"] - lo["duration_sec"])

    def tap_power(self, sim) -> float:
        base = sim.d["wall"]["tap_power_base"] + sim.total("tap_add")
        base *= sim.product("tap_mult")
        return base * sim.best("tap_hits", 1)

    def combo_mult(self, sim) -> float:
        c = sim.d["combo"]
        cap = sim.best("combo_cap", c["cap"])
        return 1.0 + min((sim.s.core["combo"] // 10) * c["bonus_per_10"], cap)

    def _subs_cps(self, sim) -> float:
        total = sum(sim.s.repeats[i["id"]] * i["cps"] for i in self.catalog(sim))
        total += sim.total("flat_cps")
        for e in sim.effects("auto_from_tap"):
            total += self.tap_power(sim) * e["value"]
        return total

    def manual_rate(self, sim) -> float:
        per_tap = self.tap_power(sim) * self.combo_mult(sim)
        w = sim.d["wall"]
        # 層報酬はタップダメージに比例する。層 n での比を近似に使う
        n = sim.s.core["layer"]
        ratio = (w["layer_reward_base"] / w["layer_damage_base"]) * \
                (w["layer_reward_growth"] / w["layer_damage_growth"]) ** n
        return per_tap * (1 + ratio) * sim.manual_mult * sim.tap_rate_nominal

    def auto_rate(self, sim) -> float:
        cps = self._subs_cps(sim) * sim.auto_mult
        if self._dark(sim):
            cps *= sim.best("lights_out_auto_mult", sim.d["lights_out"]["auto_mult"])
        return cps

    def _do_tap(self, sim) -> None:
        c, cfg = sim.s.core, sim.d["combo"]
        hold = sim.best("combo_hold", cfg["hold_sec"])
        if c["since_tap"] <= cfg["chain_window_sec"] or sim.has("combo_no_reset") \
                or c["since_tap"] <= hold:
            c["combo"] += 1
        else:
            c["combo"] = 1
        c["since_tap"] = 0.0

        power = self.tap_power(sim) * self.combo_mult(sim)
        for e in sim.effects("crit"):
            if sim.rng.next_float() < e["chance"]:
                power *= e["mult"]
            break
        amount = power * sim.manual_mult
        for e in sim.effects("lucky"):
            if sim.rng.next_float() < e["chance"]:
                amount += e["amount"] * sim.manual_mult
            break
        sim.gain_manual(amount)

        c["layer_damage"] += power
        w = sim.d["wall"]
        while True:
            need = w["layer_damage_base"] * w["layer_damage_growth"] ** c["layer"]
            if c["layer_damage"] < need:
                break
            c["layer_damage"] -= need
            c["layer"] += 1
            reward = w["layer_reward_base"] * w["layer_reward_growth"] ** c["layer"]
            sim.gain_manual(reward * sim.manual_mult)
            self._hidden(sim)

    def _hidden(self, sim) -> None:
        """隠し物は固定報酬。全体倍率もブーストも乗せない（11章 11.2-②）。"""
        h, c, w = sim.d["hidden_items"], sim.s.core, sim.d["wall"]
        if c["layer"] in h["layers"] and c["layer"] not in c["hidden"]:
            c["hidden"].add(c["layer"])
            base = w["layer_reward_base"] * w["layer_reward_growth"] ** c["layer"]
            sim.gain_manual(base * h["reward_multiple_of_layer"]
                            * sim.best("hidden_item_reward_mult", 1))

    def tick(self, sim, dt: float) -> None:
        c = sim.s.core
        c["since_tap"] += dt
        hold = sim.best("combo_hold", sim.d["combo"]["hold_sec"])
        if c["since_tap"] > hold and not sim.has("combo_no_reset"):
            c["combo"] = 0
        sim.gain_auto(self.auto_rate(sim) * dt)
        c["tap_credit"] += sim.tap_rate * dt
        while c["tap_credit"] >= 1.0:
            c["tap_credit"] -= 1.0
            self._do_tap(sim)

    def note(self, sim) -> str:
        return f"層{sim.s.core['layer']}"


# --------------------------------------------------------------------------
# ステージ2：労役棟 ― 加工チェーン（価値が ×12 ずつ跳ねる）
# --------------------------------------------------------------------------
class WorkshopCore(StageCore):
    """レーン数 × 処理速度 × 完成品の価値。

    危険なのは加工段階ごとの ×12。機械の種類を1つ増やすだけで産出価値が
    12倍になるため、レーン数や速度より段階数が圧倒的に効く。
    """

    def init_state(self, sim) -> None:
        super().init_state(sim)
        sim.s.core.update(clog=0.0)

    def depth(self, sim) -> int:
        """到達している加工段階。1=部品 … 4=精密品"""
        return 1 + int(sim.total("chain_depth"))

    def lanes(self, sim) -> int:
        return sim.d["line"]["lanes_base"] + int(sim.total("lanes"))

    def item_value(self, sim) -> float:
        """1個あたりの価値。

        加工1段で価値は ×12 になるが、**k個の入力から1個しかできない**。
        正味の倍率は 12/k であり、これを入れないと段数だけで ×20,736 になって
        35分ぶんの成長予算を1つの要素が食い潰す（11章 11.7-①）。
        """
        ln = sim.d["line"]
        k = max(1.0, ln["inputs_per_item"] - sim.total("yield_improve"))
        return (ln["value_growth"] / k) ** self.depth(sim)

    def throughput(self, sim) -> float:
        """1秒あたりに右端へ抜ける個数。"""
        ln = sim.d["line"]
        speed = ln["lane_rate"] * (1 + ln["level_bonus"] * sim.s.repeats.get("machine", 0))
        speed *= sim.product("line_speed")
        return self.lanes(sim) * speed

    def auto_rate(self, sim) -> float:
        return self.throughput(sim) * self.item_value(sim) * sim.auto_mult

    def manual_rate(self, sim) -> float:
        """詰まり解消と残業。手動は産出そのものではなく『割り込みで上乗せ』する。"""
        ln = sim.d["line"]
        return (sim.tap_rate_nominal * ln["clog_bonus_items"] * self.item_value(sim)
                * sim.manual_mult)

    def tick(self, sim, dt: float) -> None:
        sim.gain_auto(self.auto_rate(sim) * dt)
        sim.gain_manual(self.manual_rate(sim) * dt)

    def note(self, sim) -> str:
        return f"段{self.depth(sim)} 列{self.lanes(sim)} 機Lv{sim.s.repeats.get('machine',0)}"


# --------------------------------------------------------------------------
# ステージ3：食堂棟 ― 割合ベットの複利
# --------------------------------------------------------------------------
class CasinoCore(StageCore):
    """所持額に対する割合ベット。1回振るごとに所持額が ×(1 + r)。

        r = (実効期待値 − 1) × ベット率
        実効期待値 = 素の期待値 − 疑念値による劣化

    ここが本作で唯一、収入が「レート」ではなく「所持額に比例した成長率」になる。
    ベット率の上限（A系統）と疑念値（D系統）だけが律速であり、
    どちらかを一方的に強くすると即座に壊れる（docs/04 4.4）。
    """

    def init_state(self, sim) -> None:
        super().init_state(sim)
        sim.s.core.update(suspicion=0.0, roll_credit=0.0, scratch_credit=0.0)

    def bet_ratio(self, sim) -> float:
        """実際に賭ける割合。

        上限いっぱいで振り続けると疑念値が飽和して実効期待値が 1 を割る。
        人間は「溜まったら絞って冷ます」ので、その振る舞いを再現する
        （docs/03 3.3 のアクセルとブレーキ）。
        """
        dc = sim.d["dice"]
        top = sim.best("bet_ratio", dc["bet_ratio_base"])
        s = sim.s.core["suspicion"]
        if s >= dc["cool_down_at"]:
            return dc["bet_ratio_base"]
        if s >= dc["throttle_at"]:
            return dc["bet_ratio_base"] + (top - dc["bet_ratio_base"]) * 0.4
        return top

    def ev(self, sim) -> float:
        dc = sim.d["dice"]
        ev = dc["ev_base"] + sim.total("ev_add")
        decay = dc["ev_at_max_suspicion"]
        s = sim.s.core["suspicion"] / 100.0
        return ev * (1 - s) + decay * s

    def roll_rate(self, sim) -> float:
        """1秒あたりの投擲回数。手動と自動投擲の合計。"""
        dc = sim.d["dice"]
        rate = 0.0
        if sim.has("auto_roll"):
            rate += 1.0 / dc["auto_roll_sec"]
        rate += min(sim.tap_rate_nominal, 1.0 / dc["manual_roll_sec"])
        return rate * sim.product("roll_speed")

    def auto_rate(self, sim) -> float:
        """複利を『いまの所持額に対する1秒あたりの増分』として表す。"""
        r = (self.ev(sim) - 1.0) * self.bet_ratio(sim)
        return max(0.0, sim.s.currency * r * self.roll_rate(sim))

    def manual_rate(self, sim) -> float:
        """スクラッチ券。疑念値が上がらない安全な稼ぎ。"""
        sc = sim.d["scratch"]
        return sim.tap_rate_nominal * sc["per_card"] * sim.product("scratch_mult") * sim.manual_mult

    def tick(self, sim, dt: float) -> None:
        c, dc = sim.s.core, sim.d["dice"]
        rolls = self.roll_rate(sim) * dt
        if rolls > 0 and sim.s.currency > 0:
            r = (self.ev(sim) - 1.0) * self.bet_ratio(sim)
            sim.gain_auto(sim.s.currency * r * rolls)
            up = max(0.0, self.bet_ratio(sim) - dc["bet_ratio_base"]) * dc["suspicion_per_bet"]
            c["suspicion"] += up * rolls * 100
        decay = dc["suspicion_decay"] * sim.product("suspicion_decay_mult")
        c["suspicion"] = max(0.0, min(100.0, c["suspicion"] - decay * dt))
        sim.gain_manual(self.manual_rate(sim) * dt)

    def note(self, sim) -> str:
        return f"疑念{sim.s.core['suspicion']:.0f}% 実効{self.ev(sim):.2f} 率{self.bet_ratio(sim):.0%}"


# --------------------------------------------------------------------------
# ステージ4：医務棟 ― マージ（在庫回転 vs 指数価値）
# --------------------------------------------------------------------------
class InfirmaryCore(StageCore):
    """R1 の生成速度が律速。育てるほど R1 あたりの価値は (3/2)^(R-1) で伸びるが、
    育てている間は盤面を占有して生成が止まる。

    換金ランク R を決めると、1個作るのに R1 が 2^(R-1) 個必要で、
    価値は 3^(R-1)。盤面の占有率から実効の生成速度が決まる。
    """

    def init_state(self, sim) -> None:
        super().init_state(sim)
        sim.s.core.update(rank=1)

    def cells(self, sim) -> int:
        return sim.d["board"]["cells_base"] + int(sim.total("cells"))

    def gen_rate(self, sim) -> float:
        """1秒あたりに湧く R1 の数。"""
        b = sim.d["board"]
        return (1.0 / b["spawn_sec"]) * sim.product("spawn_speed") * sim.best("spawn_batch", 1)

    def best_rank(self, sim) -> int:
        """盤面に収まる範囲で、R1 あたりの価値が最大になる換金ランク。"""
        b = sim.d["board"]
        cap = sim.d["board"]["max_rank"] + int(sim.total("max_rank"))
        best, best_v = 1, 0.0
        for r in range(1, cap + 1):
            need = 2 ** (r - 1)
            if need > self.cells(sim) * b["occupancy"]:
                break
            v = (b["value_growth"] / 2.0) ** (r - 1)
            if v > best_v:
                best, best_v = r, v
        return best

    def _value_per_r1(self, sim) -> float:
        b = sim.d["board"]
        potency = 1 + b["potency_bonus"] * sim.s.repeats.get("potency", 0)
        return (b["value_growth"] / 2.0) ** (self.best_rank(sim) - 1) * potency

    def auto_rate(self, sim) -> float:
        """自動合成アームが回している分。"""
        if not sim.has("auto_merge"):
            return 0.0
        share = sim.best("auto_merge", 0.0)
        return (self.gen_rate(sim) * self._value_per_r1(sim) * share
                * sim.d["board"]["base_value"] * sim.auto_mult)

    def manual_rate(self, sim) -> float:
        b = sim.d["board"]
        hands = min(1.0, sim.tap_rate_nominal / b["taps_for_full_speed"])
        return (self.gen_rate(sim) * self._value_per_r1(sim) * hands
                * b["base_value"] * sim.manual_mult)

    def tick(self, sim, dt: float) -> None:
        sim.gain_auto(self.auto_rate(sim) * dt)
        sim.gain_manual(self.manual_rate(sim) * dt)
        sim.s.core["rank"] = self.best_rank(sim)

    def note(self, sim) -> str:
        return f"R{sim.s.core['rank']} 盤{self.cells(sim)}"


# --------------------------------------------------------------------------
# ステージ5：時計塔 ― 同期（E[M] × 基礎搬出量）
# --------------------------------------------------------------------------
class ClockTowerCore(StageCore):
    """産出 = 基礎搬出量 B × 平均倍率 E[M]。

    E[M] は巡回周期の組み方で決まる。プレイヤーの最適解は
    docs/tools/sync_sim.py で検証済みの値をそのまま段階表として持つ。
    """

    TABLE = [13.0, 36.2, 40.7, 64.2]   # レーン数と範囲拡張に応じた E[M]

    def init_state(self, sim) -> None:
        super().init_state(sim)
        sim.s.core.update(em=1.0)

    def lanes(self, sim) -> int:
        return sim.d["tower"]["lanes_base"] + int(sim.total("lanes"))

    def em(self, sim) -> float:
        """同時に開く窓の数に応じた平均倍率。"""
        t = sim.d["tower"]
        lanes = self.lanes(sim)
        if lanes <= 1:
            em = t["duty_base"]
        else:
            idx = min(lanes - 2, len(self.TABLE) - 1)
            em = self.TABLE[idx]
            if sim.has("range_expand"):
                em = self.TABLE[-1]
        duty = t["duty_base"] + sim.total("duty_add")
        em *= duty / t["duty_base"]
        return em * sim.product("sync_mult")

    def base_haul(self, sim) -> float:
        t = sim.d["tower"]
        b = t["haul_base"] * (1 + t["level_bonus"] * sim.s.repeats.get("haul", 0))
        return b * sim.product("haul_mult")

    def auto_rate(self, sim) -> float:
        if not sim.has("auto_haul"):
            return 0.0
        return (self.base_haul(sim) * self.em(sim) * sim.best("auto_haul", 0.0)
                * sim.auto_mult)

    def manual_rate(self, sim) -> float:
        t = sim.d["tower"]
        hands = min(1.0, sim.tap_rate_nominal / t["taps_for_full_speed"])
        return self.base_haul(sim) * self.em(sim) * hands * sim.manual_mult

    def tick(self, sim, dt: float) -> None:
        sim.gain_auto(self.auto_rate(sim) * dt)
        sim.gain_manual(self.manual_rate(sim) * dt)
        sim.s.core["em"] = self.em(sim)

    def note(self, sim) -> str:
        return f"{self.lanes(sim)}本 E[M]{self.em(sim):.0f}"


CORES = {
    "stage01": CellBlockCore,
    "stage02": WorkshopCore,
    "stage03": CasinoCore,
    "stage04": InfirmaryCore,
    "stage05": ClockTowerCore,
}
