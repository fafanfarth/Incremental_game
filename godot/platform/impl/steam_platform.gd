class_name SteamPlatform
extends PlatformImpl
## Steam 版（12章 12.7）。GodotSteam の GDExtension 版を使う。
##
## GDExtension を選ぶ理由: エンジン本体の再ビルドが要らないため、
## モバイル側は素の Godot のままでいられる。
##
## 買い切りなので広告と IAP は無効。有料アンロック相当は最初から適用される。

func id() -> String:
	return "steam"


func monetization_model() -> int:
	return 1  # Platform.Model.PREMIUM


func supports_ads() -> bool:
	return false


func supports_iap() -> bool:
	return false


func pointer_kind() -> int:
	return 1  # Platform.Pointer.MOUSE


func unlock_achievement(_id: String) -> void:
	# TODO(Phase 8): Steam.setAchievement(id) / Steam.storeStats()
	# 実績IDはモバイル版と同一のものを使う。定義を二重に持たない
	pass


func cloud_write(_payload: PackedByteArray) -> bool:
	# TODO(Phase 8): Steam Cloud。セーブ形式はモバイルと同一（NFR-48）
	return false
