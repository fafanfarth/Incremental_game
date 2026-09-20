class_name DetRng
extends RefCounted
## 決定論的な乱数（xorshift32）。
##
## Godot の RandomNumberGenerator と Python の Mersenne Twister は
## まったく別の系列を出すため、そのままでは両実装の結果が一致しない。
## parity ジョブを 1% の許容で成立させるには、両言語で同じ系列が要る。
##
## 32bit に収まる演算だけを使う。64bit 乗算のオーバーフロー（C++ では未定義動作）を
## 避けるため、シフトと XOR のみで構成している。
## prototype/rng.py と1行ずつ対応させること。

const MASK32 := 0xFFFFFFFF
const FALLBACK_SEED := 0x9E3779B9
const WARMUP := 8

var state: int = 0


func _init(seed_value: int = 1) -> void:
	state = seed_value & MASK32
	if state == 0:
		state = FALLBACK_SEED
	for _i in range(WARMUP):
		_next()


func _next() -> int:
	var x := state
	x ^= (x << 13) & MASK32
	x ^= x >> 17
	x ^= (x << 5) & MASK32
	state = x
	return x


func randf() -> float:
	return float(_next()) / 4294967296.0


func randf_range(a: float, b: float) -> float:
	return a + (b - a) * randf()
