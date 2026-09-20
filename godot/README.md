# Godot 4 プロジェクト

設計は [docs/12-godot-architecture.md](../docs/12-godot-architecture.md)。
**Steam 移植のために今決めておく必要があった項目**が `project.godot` に固定してある。

## 構成

| ディレクトリ | 役割 |
|---|---|
| `core/` | 決定論コア。Node に依存しない。60Hz 固定。`prototype/`（Python）と同じ結果を出す |
| `platform/` | 実績・クラウド・課金・広告の窓口。Steam 版は `SteamPlatform` を足すだけ |
| `ui/` | 画面。`core/` を読むが書き換えない |
| `ui/frame/` | 全ステージ共通の骨格（上部バー・左レール・中央・右パネル・下辺） |
| `ui/format.gd` | 数値の表示規則（05章 5.8）。表示はすべてここを通す |
| `ui/theme.gd` | 配色。色を直接ハードコードしない |
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
   新しい画面は `ui/frame/game_frame.tscn` を土台にする。自前で枠を組まない。
4. **入力は InputMap のアクション経由**で扱う。タッチイベントを直接見ない（NFR-41）。
5. **プラットフォームSDKを直接呼ばない。** すべて `Platform` 経由（NFR-42）。
6. **経済の計算を `ui/` に書かない。** 書いた瞬間にシミュレータと乖離し、parity が落ちる。
   画面は `core` を読んで表示し、操作を `core` に渡すだけ。
7. **数値の表示は `Fmt` を通す。** 直接 `str()` しない（05章 5.8）。
8. **`tests/` からオートロードを識別子で書かない。**
   `godot --script` ではオートロードがスクリプトのコンパイル後に登録されるため、
   `Game.foo()` と書くと「Identifier not found」で落ちる。
   `root.get_node_or_null(^"/root/Game")` のように実行時に取る。
   ゲーム本体（`ui/`）は通常起動なので識別子で書いてよい。

## 動かす

```bash
# Godot を動かさずにできる確認
python3 tools/lint_gdscript.py     # インデント・括弧・Godot 3 の書き方
python3 tools/sync_data.py --check # godot/data が data と一致しているか

# エディタで開く（Platform は NullPlatform になる）
godot --path godot

# ヘッドレスで起動確認
godot --headless --path godot --quit-after 120

# 画面が組み上がるか
godot --headless --path godot --script res://tests/ui_smoke.gd

# Python 実装との一致を確かめる
python3 tools/check_parity.py
```

## 状態

| 項目 | 状態 |
|---|---|
| プロジェクト設定（画面・入力・物理・レンダラ） | 完了 |
| Platform 抽象と3実装の骨格 | 完了。中身は Phase 5 / Phase 8 |
| 決定論コア（エンジン＋全5ステージ） | 移植済み。**CI で検証済み**（Python 実装と差 0.00%） |
| 共通の枠（`ui/frame/`） | 完成。全ステージが再利用する |
| ステージ1の画面 | 壁削り・コンボ・子分・消灯時間・スキルツリー。**CI の ui-smoke で組み上がることのみ確認済み** |
| ステージ2〜5 の画面 | 未着手（Phase 2 / Phase 3） |
| セーブ・オフライン進行 | 未着手 |

> **CI は緑**（run #5）。parity ジョブは実際に3件の不具合を検出してから通った。
> この土台の上で Phase 1 の実装を進めてよい。
