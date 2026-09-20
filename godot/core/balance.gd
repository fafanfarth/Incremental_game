extends Node
## バランス数値のローダ（NFR-45）。
##
## 数値の正は リポジトリ直下の data/*.json ただ1箇所。
## godot/data/ はそこから同期された生成物で、直接編集してはならない。
## CI の data-sync ジョブが差分を検出して落とす。

const DATA_DIR := "res://data"

var _cache: Dictionary = {}


func stage(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var path := "%s/%s.json" % [DATA_DIR, id]
	var text := FileAccess.get_file_as_string(path)
	assert(text != "", "バランスデータが読めない: %s" % path)
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "バランスデータが壊れている: %s" % path)
	_cache[id] = parsed
	return parsed


func stage_ids() -> PackedStringArray:
	return PackedStringArray(["stage01", "stage02", "stage03", "stage04", "stage05"])
