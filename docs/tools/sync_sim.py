#!/usr/bin/env python3
"""ステージ5（時計塔）の平均産出倍率 E[M] を求める検証スクリプト。

5人の衛兵がそれぞれ周期 T で巡回し、そのうち duty×T の間だけ持ち場を離れる。
同時に離れている人数を k とすると産出倍率は 4^(k-1)（k=0 なら 0）。
位相をすべて 0 に揃えた状態で、最小公倍数の区間を数値積分する。

使い方:
    python3 docs/tools/sync_sim.py                # 03章の表を再現
    python3 docs/tools/sync_sim.py 8 8 8 8 16     # 任意の構成を評価
"""
import sys
from functools import reduce
from math import comb, gcd


def avg_multiplier(periods, duty=0.40, base=4, steps_per_sec=200):
    """位相を 0 に揃えたときの平均倍率。"""
    cycle = reduce(lambda a, b: a * b // gcd(a, b), periods)
    steps = int(cycle * steps_per_sec)
    total = 0.0
    for s in range(steps):
        t = s / steps_per_sec
        k = sum(1 for T in periods if (t % T) < duty * T)
        total += 0 if k == 0 else base ** (k - 1)
    return total / steps


def avg_multiplier_independent(n=5, duty=0.40, base=4):
    """周期が噛み合わず、窓の開閉が独立とみなせる場合の解析値。"""
    return sum(
        comb(n, k) * duty ** k * (1 - duty) ** (n - k) * base ** (k - 1)
        for k in range(1, n + 1)
    )


def main():
    if len(sys.argv) > 1:
        periods = [int(a) for a in sys.argv[1:]]
        for duty in (0.40, 0.50):
            print(f"{periods}  duty={duty:.2f}  E[M] = {avg_multiplier(periods, duty):.1f}")
        return

    print(f"独立とみなせる場合の基準値      : {avg_multiplier_independent():.1f}")
    for periods in ([5, 7, 11, 17, 23], [6, 6, 12, 12, 24], [6, 6, 6, 12, 24], [8, 8, 8, 8, 16]):
        print(f"{str(periods):24}: {avg_multiplier(periods):.1f}")
    print("\nデューティ上限 0.50（S5-D2）:")
    for periods in ([6, 6, 12, 12, 24], [8, 8, 8, 8, 16]):
        print(f"{str(periods):24}: {avg_multiplier(periods, duty=0.50):.1f}")


if __name__ == "__main__":
    main()
