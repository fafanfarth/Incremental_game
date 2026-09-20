class_name NullPlatform
extends PlatformImpl
## エディタと CI。基底の既定値をそのまま使う。
##
## このクラスで全ステージをクリアできることが、Steam 版が成立することの証明になる（NFR-44）。

func id() -> String:
	return "null"
