#!/usr/bin/env python3
"""09章（ハードモード「死線」）の時間配分を検証するスクリプト。

残り時間は開始時に与えられ、ステージクリアごとに加算される。
余剰は次のステージへ持ち越される。どこで時間切れになるかを追跡する。

使い方:
    python3 docs/tools/lethal_budget.py
    python3 docs/tools/lethal_budget.py 15 22 26 30 38    # 各棟のクリア所要(分)
"""
import sys

STAGES = ["独房棟", "労役棟", "食堂棟", "医務棟", "時計塔"]

# 難易度ごとの加算（分）: [開始, 棟1クリア後, 棟2クリア後, 棟3クリア後, 棟4クリア後]
GRANTS = {
    "死線 I":   [20, 25, 30, 35, 45],
    "死線 II":  [18, 21, 24, 28, 34],
    "死線 III": [16, 17, 19, 22, 27],
}

# プレイヤー像ごとの各棟クリア所要（分）
PROFILES = {
    "ストーリー標準":   [25, 35, 40, 45, 55],   # 05章 5.3
    "死線 初挑戦":      [19, 27, 31, 36, 45],   # 1周目クリア済み、死線は初めて
    "慣れた":           [15, 22, 26, 30, 38],   # 最適ルートをおおむね把握
    "熟練":             [13, 19, 22, 26, 33],
    "極限":             [11, 16, 19, 22, 28],   # 永久スキルなしでの実質的な下限
}

# 各難易度が「ちょうど抜けられる」ことを期待するプレイヤー像
TARGET = {"死線 I": "慣れた", "死線 II": "熟練", "死線 III": "極限"}


def run(clear_times, grants, verbose=False):
    """(クリアできたか, クリア時の残り分 または 時間切れした棟のindex, 不足分)"""
    remaining = grants[0]
    for i, need in enumerate(clear_times):
        if need > remaining:
            if verbose:
                print(f"    棟{i+1} {STAGES[i]}: 残り {remaining:5.1f}分 / 所要 {need:4.1f}分"
                      f"  → 時間切れ（{need - remaining:.1f}分 不足）")
            return False, i + 1, need - remaining
        remaining -= need
        if i + 1 < len(grants):
            remaining += grants[i + 1]
        if verbose:
            print(f"    棟{i+1} {STAGES[i]}: 所要 {need:4.1f}分  → クリア、加算後 {remaining:5.1f}分")
    return True, remaining, 0.0


def main():
    if len(sys.argv) > 1:
        times = [float(a) for a in sys.argv[1:]]
        for name, grants in GRANTS.items():
            print(f"[{name}] 総持ち時間 {sum(grants)}分")
            run(times, grants, verbose=True)
            print()
        return

    print("難易度別の総持ち時間")
    for name, grants in GRANTS.items():
        print(f"  {name:8} {sum(grants):>4}分   加算 {grants}")
    print()

    header = "プレイヤー像".ljust(14) + "所要計 " + "".join(n.ljust(14) for n in GRANTS)
    print(header)
    print("-" * len(header))
    for pname, times in PROFILES.items():
        row = pname.ljust(14) + f"{sum(times):>4}分  "
        for name, grants in GRANTS.items():
            ok, val, short = run(times, grants)
            row += (f"◯ 残{val:.0f}分" if ok else f"× 棟{val}で{short:.0f}分不足").ljust(14)
        print(row)

    print("\n各難易度が想定するプレイヤー像での余裕（9.9-1 の確認）")
    for name, grants in GRANTS.items():
        ok, val, short = run(PROFILES[TARGET[name]], grants)
        verdict = f"クリア、残り {val:.0f}分（総持ち時間の {val / sum(grants):.0%}）" if ok \
                  else f"失敗（棟{val}で {short:.0f}分不足）— 厳しすぎる"
        print(f"  {name:8} 想定={TARGET[name]:6} → {verdict}")


if __name__ == "__main__":
    main()
