class_name Fmt
## 数値の表示規則（docs/05 5.8）。表示に関わる文字列はすべてここを通す。
##
##   〜9,999            8,240
##   1万〜9,999万        1.2万 / 34.5万 / 1,000万
##   1億〜               1.2億
##   秒間収入            +1,240 /秒
##
## 目標額は常に「100万」と表記する。1,000,000 とは書かない（05章 5.8）。

const MAN := 10000.0
const OKU := 100000000.0


static func amount(value: float) -> String:
	var v := absf(value)
	var sign_text := "-" if value < 0.0 else ""
	if v < MAN:
		return sign_text + _grouped(int(v))
	if v < OKU:
		return sign_text + _scaled(v / MAN) + "万"
	return sign_text + _scaled(v / OKU) + "億"


## 秒間収入。"+1,240 /秒"
static func rate(value: float) -> String:
	return "+%s /秒" % amount(value)


## 残り時間や経過時間。"08:42"
static func clock(seconds: float) -> String:
	var total := int(maxf(0.0, seconds))
	return "%02d:%02d" % [total / 60, total % 60]


## 回収期間。ハードモードでは残り時間と直接比べる（09章 9.6）
static func payback(seconds: float) -> String:
	if seconds >= 3600.0 or is_inf(seconds):
		return "―"
	return clock(seconds)


static func _scaled(v: float) -> String:
	# 1万台は小数第1位まで、それ以上は桁区切りの整数にする
	if v < 100.0:
		return "%.1f" % v
	return _grouped(int(round(v)))


static func _grouped(n: int) -> String:
	var text := str(absi(n))
	var out := ""
	var count := 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
