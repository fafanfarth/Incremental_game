class_name MobilePlatform
extends PlatformImpl
## iOS / Android。Game Center・Google Play・IAP・リワード広告。
##
## 実装は Phase 5 まで着手しない（12章 12.6）。
## Phase 1〜4 は NullPlatform で開発し、広告の無い環境で完全に動くことを常に保つ。

func id() -> String:
	return "mobile"


func monetization_model() -> int:
	return 0  # Platform.Model.FREE_TO_PLAY


func supports_ads() -> bool:
	return true


func supports_iap() -> bool:
	return true


func pointer_kind() -> int:
	return 0  # Platform.Pointer.TOUCH


func unlock_achievement(_id: String) -> void:
	# TODO(Phase 5): Game Center / Play Games Services
	pass


func show_rewarded_ad(slot: String) -> void:
	# TODO(Phase 5): AdMob。ロード失敗時も報酬を与えること（FR-62）
	host.rewarded_ad_finished.emit(slot, true)
