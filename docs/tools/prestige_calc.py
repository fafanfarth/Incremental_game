#!/usr/bin/env python3
"""08章（周回と永久スキル表）の数値を検算するスクリプト。

- 記録抹消で得られる脱獄章
- 永久スキル表 30項目の総額

使い方:
    python3 docs/tools/prestige_calc.py
    python3 docs/tools/prestige_calc.py 5000000     # 各棟の生涯獲得額を指定
"""
import math
import sys

STAGES = 5

# (最大Lv, base) — Lv n のコストは base × n
TABLE = {
    "A 記憶": [("既視感", 5, 3), ("手順の記憶", 5, 4), ("顔なじみ", 3, 25),
               ("先回り", 5, 8), ("助走", 5, 6), ("前科", 10, 10)],
    "B 手癖": [("硬い指", 10, 2), ("連打", 5, 5), ("見切り", 5, 6),
               ("二本指", 1, 40), ("一撃", 5, 8), ("筋肉", 5, 7)],
    "C 段取り": [("居眠り", 10, 3), ("長い夜", 5, 6), ("使い走り", 5, 12),
                 ("段取り", 5, 8), ("まとめ買い", 3, 15), ("留守番", 1, 80)],
    "D 度胸": [("引きの強さ", 10, 4), ("下振れ保険", 5, 7), ("図太さ", 5, 5),
               ("悪運", 5, 9), ("賭け師", 3, 20), ("時計読み", 5, 10)],
    "E 自由": [("早送り", 3, 10), ("巻き戻し", 3, 18), ("賭けの記録", 1, 1),
               ("区画の記録", 1, 20), ("恩赦", 4, 100), ("第二区画", 1, 200)],
}


def item_total(max_lv, base):
    """その項目を最大Lvまで上げる総コスト。"""
    return base * max_lv * (max_lv + 1) // 2


def medals(lifetime_per_stage, veteran_bonus=0.0):
    """記録抹消で得られる脱獄章。"""
    per = math.floor(3 * math.sqrt(lifetime_per_stage / 1_000_000))
    return int(per * STAGES * (1 + veteran_bonus))


def main():
    if len(sys.argv) > 1:
        life = float(sys.argv[1])
        print(f"各棟の生涯獲得額 {life:,.0f} → 獲得章 {medals(life)}")
        return

    print("■ 記録抹消で得られる脱獄章")
    for label, life in [("最短クリアのみ", 1_750_000), ("継承 L1 まで", 5_000_000),
                        ("継承 L2 まで", 25_000_000), ("継承 L4 まで", 630_000_000)]:
        print(f"  {label:18} 各棟 {life:>12,} → {medals(life):>4}章")

    print("\n■ 永久スキル表の総額")
    grand = 0
    for category, items in TABLE.items():
        subtotal = sum(item_total(lv, base) for _, lv, base in items)
        grand += subtotal
        detail = "  ".join(f"{name} {item_total(lv, base)}" for name, lv, base in items)
        print(f"  {category:8} 小計 {subtotal:>5}   ({detail})")
    print(f"  {'総額':8}      {grand:>5}章")


if __name__ == "__main__":
    main()
