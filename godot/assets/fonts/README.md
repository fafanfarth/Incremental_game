# フォント

いずれも SIL Open Font License 1.1。同梱・改変・商用利用が可能。

| ファイル | 書体 | 収録字数 | サイズ | 出典 |
|---|---|---|---|---|
| `NotoSansJP-Regular.ttf` | Noto Sans JP | 16,732 | 5.1MB | Google Fonts |
| `NotoSansJP-Bold.ttf` | Noto Sans JP Bold | 16,732 | 5.1MB | Google Fonts |
| `ZenKakuGothicNew-Regular.ttf` | Zen Kaku Gothic New | 7,737 | 2.2MB | Google Fonts |
| `MPLUS1p-Regular.ttf` | M PLUS 1p | 8,331 | 1.6MB | Google Fonts |

## なぜ同梱が必須か

**Godot 4 の既定フォント（Open Sans）に CJK は含まれない。**
同梱しないと、本作の UI は実機で日本語が全て豆腐（□）になる。
エディタ上では OS のフォントで補完されて気づかないことがあるので注意。

## 選定中

実機で `ui/debug/font_preview` を開くと、同じ画面のテキストを書体ごとに切り替えて
見比べられる。決まったら `ui/typography.gd` の `DEFAULT` を変え、
**使わない書体のファイルは削除する**（NFR-23 のダウンロードサイズ）。

観点:

- **数字の読みやすさ**。カウンタは毎フレーム変わるので、字幅が揃わないと桁が踊る
- 小さいサイズでの漢字の潰れ（右パネルの 14〜16px）
- 監獄という舞台に合うか
