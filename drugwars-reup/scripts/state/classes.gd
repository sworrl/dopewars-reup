class_name CharClasses
extends RefCounted

const PATH := "res://data/classes.json"

static var _cache: Array = []
static var _by_id: Dictionary = {}

static func all() -> Array:
	if _cache.is_empty():
		_load()
	return _cache

static func by_id(id: String) -> Dictionary:
	if _by_id.is_empty():
		_load()
	return _by_id.get(id, {})

static func _load() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if typeof(doc) != TYPE_DICTIONARY or not doc.has("classes"):
		return
	_cache = doc.classes
	for c in _cache:
		_by_id[c.id] = c
