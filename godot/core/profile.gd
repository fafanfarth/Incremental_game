class_name SimProfile
extends RefCounted
## プレイヤーの振る舞い。実在のプレイヤーではなく、
## バランスの回帰を検出するための固定された物差し（prototype/README.md と同じ定義）。

var name: String = "手動"
var taps_per_sec: float = 4.0
var active_ratio: float = 1.0
var purchase_pause_sec: float = 2.5
var inspection_choice: String = "bribe"  # "hide" か "bribe"
var max_sec: float = 8.0 * 3600.0
## true ならシミュレータとして taps_per_sec から自動でタップを発生させる。
## 実機のプレイでは false にし、UI から player_action() を呼ぶ。
## 収入の見積り（tap_rate_nominal）には影響しない。
var simulated: bool = true


static func manual() -> SimProfile:
	return SimProfile.new()


## 実機のプレイ用。自動タップはせず、見積りだけ想定値を使う
static func live() -> SimProfile:
	var p := SimProfile.new()
	p.name = "プレイ"
	p.simulated = false
	p.purchase_pause_sec = 0.0
	p.max_sec = INF
	return p


static func idle() -> SimProfile:
	var p := SimProfile.new()
	p.name = "放置のみ"
	p.taps_per_sec = 0.1
	return p
