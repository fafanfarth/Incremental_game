#!/usr/bin/env python3
"""バランスデータを data/ から godot/data/ へ同期する（NFR-45）。

数値の正は data/ ただ1箇所。godot/data/ は生成物であり、直接編集してはならない。

    python3 tools/sync_data.py            # 同期する
    python3 tools/sync_data.py --check    # 差分があれば異常終了（CI 用）
"""
from __future__ import annotations

import argparse
import filecmp
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "data"
DST = ROOT / "godot" / "data"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="同期せず、差分の有無だけを見る")
    a = ap.parse_args()

    DST.mkdir(parents=True, exist_ok=True)
    sources = sorted(SRC.glob("*.json"))
    if not sources:
        print(f"データが無い: {SRC}", file=sys.stderr)
        return 2

    stale: list[str] = []
    for src in sources:
        dst = DST / src.name
        if not dst.exists() or not filecmp.cmp(src, dst, shallow=False):
            stale.append(src.name)
            if not a.check:
                shutil.copy2(src, dst)

    # data/ から消えたものは godot/data/ からも消す
    for dst in sorted(DST.glob("*.json")):
        if not (SRC / dst.name).exists():
            stale.append(f"{dst.name}（余分）")
            if not a.check:
                dst.unlink()

    if a.check:
        if stale:
            print("godot/data/ が data/ と一致していない:", file=sys.stderr)
            for name in stale:
                print(f"  - {name}", file=sys.stderr)
            print("\n  python3 tools/sync_data.py  を実行してコミットすること",
                  file=sys.stderr)
            return 1
        print(f"godot/data/ は data/ と一致している（{len(sources)} ファイル）")
        return 0

    if stale:
        print(f"同期した: {', '.join(stale)}")
    else:
        print(f"変更なし（{len(sources)} ファイル）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
