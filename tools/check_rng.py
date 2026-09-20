#!/usr/bin/env python3
"""DetRng が Python と GDScript で同じ系列を出すか確かめる。

parity ジョブは1往復に10分かかるため、乱数の一致だけを数秒で切り分けられるようにする。

    python3 tools/check_rng.py
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "prototype"))

from rng import DetRng  # noqa: E402

SEEDS = [1, 2, 3]
COUNT = 5


def main() -> int:
    expected = {}
    for seed in SEEDS:
        # next_float だけでなく range_float も見る。
        # range_float の中で修飾なしに randf() を呼ぶと Godot のグローバル関数に
        # 解決されてしまう。前回はここを見ていなかったため不具合を通していた
        r = DetRng(seed)
        seq = [r.next_float() for _ in range(COUNT)]
        r2 = DetRng(seed)
        seq += [r2.range_float(240.0, 480.0) for _ in range(COUNT)]
        expected[str(seed)] = seq

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "rng.json"
        path.write_text(json.dumps(expected), encoding="utf-8")
        cmd = ["godot", "--headless", "--path", str(ROOT / "godot"),
               "--script", "res://tests/rng_check.gd", "--", str(path)]
        r = subprocess.run(cmd, capture_output=True, text=True)
        print((r.stdout + r.stderr).strip())
        if r.returncode != 0:
            print("\n乱数が一致していない。これが直るまで parity は通らない。", file=sys.stderr)
            return 1
    print("\n乱数は一致している。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
