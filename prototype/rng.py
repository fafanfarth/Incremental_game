"""決定論的な乱数（xorshift32）。

Python の Mersenne Twister と Godot の RandomNumberGenerator は
まったく別の系列を出すため、そのままでは両実装の結果が一致しない。
parity ジョブを 1% の許容で成立させるには、両言語で同じ系列が要る。

32bit に収まる演算だけを使う。64bit 乗算のオーバーフロー（C++ では未定義動作）を
避けるため、シフトと XOR のみで構成している。
godot/core/rng.gd と1行ずつ対応させること。
"""

MASK32 = 0xFFFFFFFF
FALLBACK_SEED = 0x9E3779B9
WARMUP = 8


class DetRng:
    def __init__(self, seed: int = 1) -> None:
        self.state = (seed & MASK32) or FALLBACK_SEED
        for _ in range(WARMUP):
            self._next()

    def _next(self) -> int:
        x = self.state
        x ^= (x << 13) & MASK32
        x ^= x >> 17
        x ^= (x << 5) & MASK32
        self.state = x
        return x

    def random(self) -> float:
        return self._next() / 4294967296.0

    def uniform(self, a: float, b: float) -> float:
        return a + (b - a) * self.random()
