class_name Aircraft
extends RefCounted

## Loads data/aircraft.json. General-aviation aircraft are ownable endgame assets that unlock the
## GA travel mode (flying yourself — no commercial TSA, but a ramp-check risk on arrival). See
## PlayerState for ownership + the ADS-B (trackability) mechanic.

const PATH := "res://data/aircraft.json"

static var _cache: Array = []

static func all() -> Array:
	if _cache.is_empty():
		_load()
	return _cache

static func by_id(id: String) -> Dictionary:
	for a in all():
		if a.id == id:
			return a
	return {}

static func _load() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("[aircraft] cannot open " + PATH)
		return
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if typeof(doc) != TYPE_DICTIONARY or not doc.has("aircraft"):
		push_error("[aircraft] malformed")
		return
	_cache = doc.aircraft
