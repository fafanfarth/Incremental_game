# Godot 4 プロジェクト

設計は [docs/12-godot-architecture.md](../docs/12-godot-architecture.md)。
**Steam 移植のために今決めておく必要があった項目**が `project.godot` に固定してある。

## 構成

| ディレクトリ | 役割 |
|---|---|
| `core/` | 決定論コア。Node に依存しない。60Hz 固定。`prototype/`（Python）と同じ結果を出す |
| `platform/` | 実績・クラウド・課金・広告の窓口。Steam 版は `SteamPlatform` を足すだけ |
| `ui/` | 画面。`core/` を読むが書き換えない |
| `data/` | **生成物。直接編集しない。** 正は リポジトリ直下の `data/` |
| `tests/` | ヘッドレスで回る検証 |

## 触る前に知っておくこと

1. **バランス数値は `data/`（リポジトリ直下）だけを編集する。**
   `godot/data/` は `tools/sync_data.py` が同期する生成物で、CI が差分を検出して落とす。
2. **`core/` を直したら `prototype/` も直す。** 逆も同じ。
   CI の parity ジョブが 1% 以上のずれで落ちる（NFR-46）。
   検証は **5ステージ × 手動/放置の2プロファイル**で回る。
   手動だけでは自動収入側の経路が通らないため、両方を見ている。
3. **UI は必ずアンカー基準で置く。** 絶対座標は Steam 版で全部組み直しになる（NFR-40）。
4. **入力は InputMap のアクション経由**で扱う。タッチイベントを直接見ない（NFR-41）。
5. **プラットフォームSDKを直接呼ばない。** すべて `Platform` 経由（NFR-42）。

## 動かす

```bash
# Godot を動かさずにできる確認
python3 tools/lint_gdscript.py     # インデント・括弧・Godot 3 の書き方
python3 tools/sync_data.py --check # godot/data が data と一致しているか

# エディタで開く（Platform は NullPlatform になる）
godot --path godot

# ヘッドレスで起動確認
godot --headless --path godot --quit-after 120

# Python 実装との一致を確かめる
python3 tools/check_parity.py
```

## 状態

| 項目 | 状態 |
|---|---|
| プロジェクト設定（画面・入力・物理・レンダラ） | 完了 |
| Platform 抽象と3実装の骨格 | 完了。中身は Phase 5 / Phase 8 |
| 決定論コア（エンジン＋全5ステージ） | 移植済み。**CI で検証済み**（Python 実装と差 0.00%） |
| 画面 | `ui/boot.tscn` は起動確認用の暫定。Phase 1 で本物に置き換える |

> **CI は緑**（run #5）。parity ジョブは実際に3件の不具合を検出してから通った。
> この土台の上で Phase 1 の実装を進めてよい。
