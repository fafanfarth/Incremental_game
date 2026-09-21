class_name Typography
## 書体と文字サイズを1箇所に集める（フォント選定中）。
##
## **Godot 4 の既定フォントに CJK は含まれない。** 同梱しないと実機で
## 日本語が全て豆腐になるため、ここで必ず差し替える。
##
## 数字は等幅にする。カウンタは毎フレーム変わるので、字幅が揃っていないと
## 桁が左右に踊って読めなくなる。

enum Face { NOTO, ZEN, MPLUS }

const FILES := {
	Face.NOTO: "res://assets/fonts/NotoSansJP-Regular.ttf",
	Face.ZEN: "res://assets/fonts/ZenKakuGothicNew-Regular.ttf",
	Face.MPLUS: "res://assets/fonts/MPLUS1p-Regular.ttf",
}

const BOLD_FILES := {
	Face.NOTO: "res://assets/fonts/NotoSansJP-Bold.ttf",
}

const LABELS := {
	Face.NOTO: "Noto Sans JP",
	Face.ZEN: "Zen Kaku Gothic New",
	Face.MPLUS: "M PLUS 1p",
}

## 選定が済んだらここを変え、使わないフォントのファイルは消す
const DEFAULT := Face.NOTO

## 文字サイズ。実機で小さすぎたらここだけ直す
const SIZE_COUNTER := 30   # 上部バーの通貨
const SIZE_HEAD := 20      # 見出し
const SIZE_BODY := 17      # 本文・ボタン
const SIZE_SMALL := 14     # 右パネルの補足

static var _current: Face = DEFAULT


static func face() -> Face:
	return _current


static func set_face(value: Face) -> void:
	_current = value


static func font(face_id: int = -1) -> FontFile:
	var id: int = _current if face_id < 0 else face_id
	return load(FILES[id]) as FontFile


static func bold_font(face_id: int = -1) -> FontFile:
	var id: int = _current if face_id < 0 else face_id
	return load(BOLD_FILES.get(id, FILES[id])) as FontFile


## 数字が等幅になる書体変種。カウンタと価格はこれを使う
static func tabular(face_id: int = -1) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = font(face_id)
	# tnum = 等幅数字。対応していない書体では無視されるだけで害はない
	v.opentype_features = {_tag("tnum"): 1}
	return v


static func _tag(text: String) -> int:
	return TextServerManager.get_primary_interface().name_to_tag(text)


## 画面全体に適用する Theme を組む。.tres を持たずコードで作る
static func build_theme(face_id: int = -1) -> Theme:
	var theme := Theme.new()
	var body := font(face_id)
	var digits := tabular(face_id)

	theme.default_font = body
	theme.default_font_size = SIZE_BODY

	theme.set_type_variation(&"Counter", &"Label")
	theme.set_font(&"font", &"Counter", digits)
	theme.set_font_size(&"font_size", &"Counter", SIZE_COUNTER)

	theme.set_type_variation(&"Numeric", &"Label")
	theme.set_font(&"font", &"Numeric", digits)
	theme.set_font_size(&"font_size", &"Numeric", SIZE_BODY)

	theme.set_type_variation(&"Small", &"Label")
	theme.set_font_size(&"font_size", &"Small", SIZE_SMALL)

	theme.set_type_variation(&"Head", &"Label")
	theme.set_font_size(&"font_size", &"Head", SIZE_HEAD)

	theme.set_font_size(&"font_size", &"Button", SIZE_BODY)
	return theme
