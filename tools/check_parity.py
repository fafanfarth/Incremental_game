#!/usr/bin/env python3
"""Python シミュレータの結果を基準に、Godot 実装との一致を確かめる（NFR-46）。

Python 側でクリア秒数を出し、その値を Godot のヘッドレス実行に渡して
差が 1% 未満であることを確認する。

    python3 tools/check_parity.py
    python3 tools/check_parity.py --seeds 3
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "prototype"))

from cores import CORES  # noqa: E402
from sim import Profile, Sim, load  # noqa: E402

# GDScript に移植済みのステージだけを対象にする。
# 移植したらここに足す（godot/tests/parity.gd の CORES も同時に）
PORTED = ["stage01"]


def python_clear_sec(stage: str, seed: int) -> float:
    s = Sim(Profile("手動", taps_per_sec=4.0), load(stage), CORES[stage](), seed=seed)
    s.run(snapshot_every=1e9)
    if s.cleared_at is None:
        raise SystemExit(f"{stage}: Python 側が時間内にクリアできなかった")
    return s.cleared_at


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=2)
    a = ap.parse_args()

    failed = 0
    for stage in PORTED:
        for seed in range(1, a.seeds + 1):
            expected = python_clear_sec(stage, seed)
            cmd = ["godot", "--headless", "--path", str(ROOT / "godot"),
                   "--script", "res://tests/parity.gd", "--",
                   stage, str(seed), f"{expected:.4f}"]
            r = subprocess.run(cmd, capture_output=True, text=True)
            out = (r.stdout + r.stderr).strip()
            print(out or f"{stage} seed={seed}: 出力なし")
            if r.returncode != 0:
                failed += 1
    if failed:
        print(f"\n{failed} 件が一致しなかった。"
              "GDScript と Python のどちらか片方だけを直していないか確認すること。",
              file=sys.stderr)
        return 1
    print("\nすべて一致した。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
