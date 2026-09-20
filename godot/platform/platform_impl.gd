class_name PlatformImpl
extends RefCounted
## Platform 実装の基底。既定値は「SDK が無い環境」の振る舞い。
##
## 既定のまま何も上書きしなくてもゲームは最後までクリアできる（NFR-44）。
## これが Steam 版と CI の動作保証を兼ねている。

var host: Node


func setup(p_host: Node) -> void:
	host = p_host


func id() -> String:
	return "null"


func monetization_model() -> int:
	return 1  # Platform.Model.PREMIUM


func supports_ads() -> bool:
	return false


func supports_iap() -> bool:
	return false


func pointer_kind() -> int:
	return 1  # Platform.Pointer.MOUSE


func unlock_achievement(_id: String) -> void:
	pass


func submit_record(_board: String, _value: int) -> void:
	pass


func cloud_write(_payload: PackedByteArray) -> bool:
	return false


func cloud_read() -> PackedByteArray:
	return PackedByteArray()


func show_rewarded_ad(slot: String) -> void:
	host.rewarded_ad_finished.emit(slot, true)
