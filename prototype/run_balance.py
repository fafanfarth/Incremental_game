#!/usr/bin/env python3
"""全ステージのバランス検証レポート（Phase 0 の合格判定）。

  python3 prototype/run_balance.py                 # 全ステージの合格判定
  python3 prototype/run_balance.py --stage 3       # 1ステージだけ
  python3 prototype/run_balance.py --curve 1       # 成長曲線を出す
  python3 prototype/run_balance.py --seeds 8
"""
from __future__ import annotations

import argparse
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cores import CORES  # noqa: E402
from sim import Profile, Sim, load  # noqa: E402

# 合格条件は2つ。
#   1. 手動クリアが docs/05 5.3 の目標時間 ±20% に入る
#   2. 放置のみ ÷ 手動 の比が 1.5〜4.0 に入る
#      1.5 未満 = 触る意味がない（FR-14 違反）/ 4.0 超 = 放置プレイが苦行
# 放置の絶対時間は設計時の見積りではなく実測を正とする（11章 11.5）
TARGETS = {
    "stage01": ("独房棟", 25),
    "stage02": ("労役棟", 35),
    "stage03": ("食堂棟", 40),
    "stage04": ("医務棟", 45),
    "stage05": ("時計塔", 55),
}
RATIO_MIN, RATIO_MAX = 1.5, 4.0

MANUAL = Profile("手動", taps_per_sec=4.0)
IDLE = Profile("放置のみ", taps_per_sec=0.1)


def clear_times(stage: str, profile: Profile, seeds: int) -> list[float]:
    out = []
    for seed in range(1, seeds + 1):
        s = Sim(profile, load(stage), CORES[stage](), seed=seed).run(snapshot_every=1e9)
        out.append((s.cleared_at or profile.max_sec) / 60)
    return out


def gate(times: list[float], target: float, tol: float) -> bool:
    return all(target * (1 - tol) <= t <= target * (1 + tol) for t in times)


def report(stages: list[str], seeds: int) -> int:
    print(f"バランス検証  （{seeds} 試行 / 固定60Hz / seed 1..{seeds}）\n")
    header = (f"{'ステージ':<10} {'手動 中央値':>11} {'範囲':>14} {'目標':>7} | "
              f"{'放置 中央値':>11} {'比':>6} | 判定")
    print(header)
    print("-" * len(header))
    failed = 0
    for st in stages:
        name, tm = TARGETS[st]
        man = clear_times(st, MANUAL, seeds)
        idl = clear_times(st, IDLE, max(2, seeds // 2))
        mm, mi = statistics.median(man), statistics.median(idl)
        ratio = mi / mm
        ok = gate(man, tm, 0.20) and RATIO_MIN <= ratio <= RATIO_MAX
        if not ok:
            failed += 1
        print(f"{name:<10} {mm:10.1f}分 {f'{min(man):.1f}〜{max(man):.1f}':>14} {tm:6}分 | "
              f"{mi:10.1f}分 {ratio:5.2f} | {'合格' if ok else '不合格'}")
    print(f"\n合格条件: 手動が目標 ±20% / 放置÷手動 が {RATIO_MIN}〜{RATIO_MAX}\n")
    return failed


def curve(stage: str) -> None:
    s = Sim(MANUAL, load(stage), CORES[stage](), seed=1).run(snapshot_every=120)
    name = TARGETS[stage][0]
    print(f"{name} の成長曲線（手動 4タップ/秒、seed 1）\n")
    print(f"{'時刻':>6} {'累計獲得':>14} {'自動CPS':>10} {'手動CPS':>10} {'技':>4}  備考")
    print("-" * 62)
    for h in s.history:
        print(f"{h.t/60:5.1f}分 {h.lifetime:14,.0f} {h.cps_auto:10,.0f} "
              f"{h.cps_manual:10,.0f} {h.skills:4d}  {h.note}")
    if s.cleared_at:
        print(f"\nクリア {s.cleared_at/60:.1f}分   生涯獲得 {s.s.lifetime:,.0f}   反復購入 {s.s.repeats}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=6)
    ap.add_argument("--stage", type=int)
    ap.add_argument("--curve", type=int)
    a = ap.parse_args()
    if a.curve:
        curve(f"stage{a.curve:02d}")
        return 0
    stages = [f"stage{a.stage:02d}"] if a.stage else sorted(TARGETS)
    root = Path(__file__).resolve().parent.parent
    stages = [s for s in stages if (root / "data" / f"{s}.json").exists()]
    return 1 if report(stages, a.seeds) else 0


if __name__ == "__main__":
    raise SystemExit(main())
