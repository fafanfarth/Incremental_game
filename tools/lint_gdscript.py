#!/usr/bin/env python3
"""GDScript の機械的に検出できる誤りだけを見る簡易チェック。

Godot を動かせない環境でも、よくある取り違えは落とせる。
本物の検証は CI の parity ジョブ（godot --headless）が行う。

    python3 tools/lint_gdscript.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = ROOT / "godot"

PAIRS = {")": "(", "]": "[", "}": "{"}


def check(path: Path) -> list[str]:
    errs: list[str] = []
    text = path.read_text(encoding="utf-8")
    stack: list[tuple[str, int]] = []

    for lineno, line in enumerate(text.splitlines(), start=1):
        body = line.rstrip()
        if not body:
            continue

        # インデントはタブで統一する（Godot の既定）
        indent = re.match(r"^[ \t]*", body).group(0)
        if " " in indent:
            errs.append(f"{path.name}:{lineno}: インデントに空白が混ざっている")

        # 全角空白は Godot が構文エラーにする
        if "　" in body:
            errs.append(f"{path.name}:{lineno}: 全角空白が含まれている")

        # 括弧の対応（文字列とコメントは除く）
        stripped = re.sub(r'"[^"]*"', '""', body)
        stripped = stripped.split("#")[0]
        for ch in stripped:
            if ch in "([{":
                stack.append((ch, lineno))
            elif ch in PAIRS:
                if not stack or stack[-1][0] != PAIRS[ch]:
                    errs.append(f"{path.name}:{lineno}: 括弧 '{ch}' が対応していない")
                    stack.clear()
                    break
                stack.pop()

    if stack:
        ch, lineno = stack[0]
        errs.append(f"{path.name}:{lineno}: 括弧 '{ch}' が閉じられていない")

    # Godot 3 の書き方が残っていないか
    for lineno, line in enumerate(text.splitlines(), start=1):
        if re.search(r"\byield\s*\(", line):
            errs.append(f"{path.name}:{lineno}: yield() は Godot 4 では await")
        if re.search(r"\bexport\s+var\b", line):
            errs.append(f"{path.name}:{lineno}: export var は Godot 4 では @export")
        if ".empty()" in line:
            errs.append(f"{path.name}:{lineno}: .empty() は Godot 4 では .is_empty()")

    return errs


def main() -> int:
    files = sorted(GODOT.rglob("*.gd"))
    if not files:
        print("GDScript が見つからない", file=sys.stderr)
        return 2
    errs: list[str] = []
    for f in files:
        errs += check(f)
    if errs:
        for e in errs:
            print(e, file=sys.stderr)
        return 1
    print(f"{len(files)} ファイル: 問題なし")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
