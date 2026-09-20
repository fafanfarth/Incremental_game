#!/usr/bin/env python3
"""各ステージの倍率スタックを減衰させて、目標プレイ時間に合わせる。

倍率が大きいほど終盤の収入が跳ね、同じコスト階梯を短時間で登り切ってしまう。
そこで倍率効果の値に指数 d を掛け（v -> v**d）、d を二分探索して目標に寄せる。
d < 1 は倍率を弱める＝ステージを長くする。

  python3 prototype/tune.py            # 全ステージを探索して係数を表示
  python3 prototype/tune.py --apply    # 探索結果を JSON に焼き込む
"""
from __future__ import annotations

import argparse
import copy
import json
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cores import CORES  # noqa: E402
from sim import Profile, Sim, load  # noqa: E402

DATA = Path(__file__).parent / "data"

# 値が「倍率」である効果だけを減衰させる。個数・確率・上限は触らない
MULT_TYPES = {
    "manual_mult", "auto_mult", "tap_mult", "line_speed", "roll_speed",
    "scratch_mult", "spawn_speed", "haul_mult", "sync_mult",
}

TARGET_MIN = {"stage01": 25, "stage02": 35, "stage03": 40, "stage04": 45, "stage05": 55}


def damp(data: dict, d: float) -> dict:
    out = copy.deepcopy(data)
    for sk in out["skills"]:
        for e in sk["effects"]:
            if e["type"] in MULT_TYPES and isinstance(e.get("value"), (int, float)):
                e["value"] = round(max(1.0, e["value"] ** d), 3)
    return out


def measure(stage: str, data: dict, seeds: int = 3) -> float:
    times = []
    for seed in range(1, seeds + 1):
        s = Sim(Profile("手動", taps_per_sec=4.0, max_sec=200 * 60),
                copy.deepcopy(data), CORES[stage](), seed=seed).run(snapshot_every=1e9)
        times.append((s.cleared_at or 200 * 60) / 60)
    return statistics.median(times)


def search(stage: str, lo: float = 0.25, hi: float = 1.0, steps: int = 8):
    base = load(stage)
    target = TARGET_MIN[stage]
    best = (None, 1e9, None)
    for _ in range(steps):
        mid = (lo + hi) / 2
        t = measure(stage, damp(base, mid))
        if abs(t - target) < abs(best[1] - target):
            best = (mid, t, None)
        if t > target:      # 遅すぎる → 倍率を戻す
            lo = mid
        else:               # 速すぎる → さらに減衰
            hi = mid
    return best[0], best[1]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--stages", nargs="*", default=None)
    a = ap.parse_args()
    stages = a.stages or [f"stage{i:02d}" for i in (2, 3, 4, 5)]
    for st in stages:
        d, t = search(st)
        print(f"{st}: 減衰係数 {d:.3f} → 手動 {t:.1f}分（目標 {TARGET_MIN[st]}分）")
        if a.apply:
            json.dump(damp(load(st), d), open(DATA / f"{st}.json", "w", encoding="utf-8"),
                      ensure_ascii=False, indent=2)
            print(f"  → {st}.json に焼き込み")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
