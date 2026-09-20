class_name Palette
## 配色を1箇所に集める。色を直接ハードコードしない。
##
## 舞台が監獄なので、彩度を落とした石とコンクリートを基調に、
## 通貨とクリアだけを暖色で立たせる。ステージごとに強調色を変える。

const BG := Color("#14161a")           # 背景（石）
const SURFACE := Color("#1e2229")      # パネル
const SURFACE_HI := Color("#2a2f38")   # パネル（強調）
const LINE := Color("#3a4049")         # 罫線
const TEXT := Color("#e6e8ea")
const TEXT_DIM := Color("#8b929c")
const DISABLED := Color("#4a505a")

const GOLD := Color("#d9a441")         # 通貨・クリア
const DANGER := Color("#c8553d")       # 警告・時間切れ
const OK := Color("#6a9a5b")

## 系統の色（docs/04 4.1）。A=赤 B=青 C=緑 D=紫
const BRANCH := {
	"A": Color("#b5564a"),
	"B": Color("#4a7fb5"),
	"C": Color("#5b9a6a"),
	"D": Color("#8a6ab5"),
}

## ステージごとの強調色
const STAGE := {
	"stage01": Color("#c9a227"),  # タバコ
	"stage02": Color("#b57a3a"),  # 作業票
	"stage03": Color("#b54a6a"),  # チップ
	"stage04": Color("#4aa5b5"),  # 錠剤
	"stage05": Color("#d9a441"),  # 金塊
}


static func branch(id: String) -> Color:
	return BRANCH.get(id, TEXT_DIM)


static func stage(id: String) -> Color:
	return STAGE.get(id, GOLD)


## 単色のパネル背景を作る。.tres を持たずにコードで組む
static func panel(bg: Color, border: Color = LINE, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb
