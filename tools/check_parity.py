#!/usr/bin/env python3
"""Python シミュレータの結果を基準に、Godot 実装との一致を確かめる（NFR-46）。

Python 側で「途中経過つきの期待値」を作り、それを Godot のヘッドレス実行に渡す。
クリア時間だけでなくチェックポイントも突き合わせるので、
食い違ったときに **どこから食い違ったか** が CI のログに出る。

    python3 tools/check_parity.py
    python3 tools/check_parity.py --seeds 3 --stages stage01 stage03
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "prototype"))

from cores import CORES  # noqa: E402
from sim import Profile, Sim, load  # noqa: E402

# GDScript に移植済みのステージ。godot/tests/parity.gd の CORES と一致させる
PORTED = ["stage01", "stage02", "stage03", "stage04", "stage05"]

PROFILES = {
    "manual": Profile("手動", taps_per_sec=4.0),
    # 放置は自動収入の経路を通る。手動だけでは片側しか検証できない
    "idle": Profile("放置のみ", taps_per_sec=0.1),
}

SNAPSHOT_EVERY = 60.0


def expectation(stage: str, seed: int, profile_key: str) -> dict:
    s = Sim(PROFILES[profile_key], load(stage), CORES[stage](), seed=seed)
    s.run(snapshot_every=SNAPSHOT_EVERY)
    if s.cleared_at is None:
        raise SystemExit(f"{stage}/{profile_key}: Python 側が時間内にクリアできなかった")
    return {
        "stage": stage,
        "seed": seed,
        "profile": profile_key,
        "cleared_at": s.cleared_at,
        "snapshot_every": SNAPSHOT_EVERY,
        "checkpoints": [[h.t, h.lifetime] for h in s.history],
        "inspection_times": s.inspection_times[:8],
        "purchase_times": [[t, i] for t, i in s.purchase_times],
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=2)
    ap.add_argument("--stages", nargs="*", default=PORTED)
    a = ap.parse_args()

    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        for stage in a.stages:
            for profile_key in PROFILES:
                for seed in range(1, a.seeds + 1):
                    exp = expectation(stage, seed, profile_key)
                    path = Path(tmp) / f"{stage}_{profile_key}_{seed}.json"
                    path.write_text(json.dumps(exp), encoding="utf-8")
                    cmd = ["godot", "--headless", "--path", str(ROOT / "godot"),
                           "--script", "res://tests/parity.gd", "--", str(path)]
                    r = subprocess.run(cmd, capture_output=True, text=True)
                    out = (r.stdout + r.stderr).strip()
                    print(out or f"{stage}/{profile_key} seed={seed}: 出力なし")
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
