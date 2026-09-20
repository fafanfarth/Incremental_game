extends Node
## プラットフォーム依存の窓口（12章 12.2-③ / NFR-42）。
##
## 実績・クラウドセーブ・課金・広告・ランキングは、すべてこのシングルトン経由で呼ぶ。
## ゲームロジックが Game Center や Steamworks を直接知ることは無い。
##
## Steam 版を出すときの作業は SteamPlatform を1つ足すことだけになる。
##
## 実装は platform/impl/ に置く:
##   MobilePlatform … Game Center / Google Play / IAP / リワード広告
##   SteamPlatform  … Steamworks。広告と IAP は無効を返す
##   NullPlatform   … エディタと CI。何もしないが必ず成功を返す

signal rewarded_ad_finished(slot: String, granted: bool)
signal purchase_finished(product: String, granted: bool)

enum Model { FREE_TO_PLAY, PREMIUM }
enum Pointer { TOUCH, MOUSE, GAMEPAD }

var _impl: PlatformImpl


func _ready() -> void:
	_impl = _select_impl()
	_impl.setup(self)
	print("[Platform] %s / %s" % [_impl.id(), Model.keys()[monetization_model()]])


func _select_impl() -> PlatformImpl:
	# Steam 版は書き出し時に feature tag "steam" を付けて切り替える。
	# エディタと CI は必ず NullPlatform（SDK 無しで全機能が動くことの保証 / NFR-44）。
	if OS.has_feature("steam"):
		return SteamPlatform.new()
	if OS.get_name() in ["Android", "iOS"] and not OS.has_feature("editor"):
		return MobilePlatform.new()
	return NullPlatform.new()


## 収益モデル。PREMIUM では広告ボタンを一切表示せず、
## 有料アンロック相当の内容を最初から適用する（12章 12.3）。
func monetization_model() -> int:
	return _impl.monetization_model()


func supports_ads() -> bool:
	return _impl.supports_ads()


func supports_iap() -> bool:
	return _impl.supports_iap()


func pointer_kind() -> int:
	return _impl.pointer_kind()


func unlock_achievement(id: String) -> void:
	_impl.unlock_achievement(id)


func submit_record(board: String, value: int) -> void:
	_impl.submit_record(board, value)


func cloud_write(payload: PackedByteArray) -> bool:
	return _impl.cloud_write(payload)


func cloud_read() -> PackedByteArray:
	return _impl.cloud_read()


## リワード広告。広告が無い環境では「見たことにして報酬を与える」。
## FR-62（ロード失敗時も報酬を付与）と、PREMIUM で進行が詰まらないことの両方を満たす。
func show_rewarded_ad(slot: String) -> void:
	if not supports_ads():
		rewarded_ad_finished.emit(slot, true)
		return
	_impl.show_rewarded_ad(slot)
