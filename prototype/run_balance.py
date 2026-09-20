#!/usr/bin/env python3
"""ステージ1のバランス検証レポートを出す（Phase 0 の合格判定）。

  python3 prototype/run_balance.py            # 合格判定つきのレポート
  python3 prototype/run_balance.py --curve    # 成長曲線を 05章 5.2 と並べる
  python3 prototype/run_balance.py --seeds 20 # 試行数を変える
"""
from __future__ import annotations

import argparse
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from sim import Sim, Profile  # noqa: E402

# docs/07 Phase 0 の合格条件
GATES = {
    "手動": (20 * 60, 30 * 60),      # 25分 ±5
    "放置のみ": (45 * 60, 75 * 60),  # 60分 ±15
}

PROFILES = [
    Profile("手動", taps_per_sec=4.0),
    Profile("併用", taps_per_sec=1.2),
    Profile("放置のみ", taps_per_sec=0.1),
]

# docs/05 5.2 の設計曲線（分 → その時点の累計獲得）
DESIGN_CURVE = {2: 200, 6: 2500, 12: 20000, 20: 120000, 28: 500000, 35: 1750000}


def measure(profile: Profile, seeds: int):
    times, lifetimes = [], []
    for seed in range(1, seeds + 1):
        s = Sim(profile, seed=seed).run(snapshot_every=1e9)
        if s.cleared_at is None:
            times.append(float("inf"))
        else:
            times.append(s.cleared_at)
        lifetimes.append(s.s.lifetime)
    return times, lifetimes


def report(seeds: int) -> int:
    print(f"ステージ1「独房棟」バランス検証  （{seeds} 試行 / 固定60Hz / seed 1..{seeds}）\n")
    print(f"{'プロファイル':<10} {'タップ/秒':>8} {'中央値':>8} {'最短':>8} {'最長':>8} {'生涯獲得':>13}  判定")
    print("-" * 72)
    failed = 0
    for p in PROFILES:
        times, lifetimes = measure(p, seeds)
        med = statistics.median(times) / 60
        lo, hi = min(times) / 60, max(times) / 60
        life = statistics.median(lifetimes)
        gate = GATES.get(p.name)
        if gate is None:
            verdict = "―"
        elif all(gate[0] <= t <= gate[1] for t in times):
            verdict = "合格"
        else:
            verdict = f"不合格（{gate[0]//60}〜{gate[1]//60}分）"
            failed += 1
        print(f"{p.name:<10} {p.taps_per_sec:>8.1f} {med:7.1f}分 {lo:7.1f}分 {hi:7.1f}分 {life:13,.0f}  {verdict}")
    print()
    return failed


def curve() -> None:
    s = Sim(PROFILES[0], seed=1).run(snapshot_every=60)
    print("成長曲線（手動 4タップ/秒、seed 1）と 05章 5.2 の設計曲線\n")
    print(f"{'時刻':>6} {'累計獲得':>13} {'自動CPS':>10} {'手動CPS':>10} {'技':>4}   設計曲線")
    print("-" * 66)
    for h in s.history:
        m = int(round(h.t / 60))
        ref = f"   {DESIGN_CURVE[m]:>11,}" if m in DESIGN_CURVE else ""
        print(f"{h.t/60:5.1f}分 {h.lifetime:13,.0f} {h.cps_auto:10,.0f} {h.cps_manual:10,.0f} {h.skills:4d}{ref}")
    if s.cleared_at:
        print(f"\nクリア {s.cleared_at/60:.1f}分   生涯獲得 {s.s.lifetime:,.0f}   子分 {s.s.subs}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=10)
    ap.add_argument("--curve", action="store_true")
    a = ap.parse_args()
    if a.curve:
        curve()
        return 0
    return 1 if report(a.seeds) else 0


if __name__ == "__main__":
    raise SystemExit(main())
