class_name Cities
extends RefCounted

## Loads data/cities.json once, exposes lookup helpers.
## v0.1 = JSON file. v0.2+ = pulled from server / Postgres view.

const PATH := "res://data/cities.json"

static var _cache: Array = []

static func all() -> Array:
	if _cache.is_empty():
		_load()
	return _cache

static func by_id(id: String) -> Dictionary:
	for c in all():
		if c.id == id:
			return c
	return {}

static func _load() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("[cities] cannot open " + PATH)
		return
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if typeof(doc) != TYPE_DICTIONARY or not doc.has("cities"):
		push_error("[cities] malformed")
		return
	_cache = doc.cities
