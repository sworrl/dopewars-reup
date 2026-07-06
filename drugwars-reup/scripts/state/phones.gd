class_name Phones
extends RefCounted

## Loads data/phones.json. Phones are RPG gear: tier (capability), trace (police traceability),
## battery, and whether the model can run the hardened OS. See [[dopewars-phones-as-gear]].

const PATH := "res://data/phones.json"
const GRAPHENE_TRACE_DEFAULT := 15

static var _phones: Array = []
static var _graphene_trace: int = GRAPHENE_TRACE_DEFAULT

static func _load() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if typeof(doc) == TYPE_DICTIONARY:
		_phones = doc.get("phones", [])
		_graphene_trace = int(doc.get("graphene_trace", GRAPHENE_TRACE_DEFAULT))

static func all() -> Array:
	if _phones.is_empty():
		_load()
	return _phones

static func by_id(id: String) -> Dictionary:
	for p in all():
		if p.get("id", "") == id:
			return p
	return {}

## Traceability once the hardened OS is (or isn't) flashed.
static func graphene_trace() -> int:
	if _phones.is_empty():
		_load()
	return _graphene_trace

static func art_path(id: String) -> String:
	return "res://assets/sprites/phones/%s.png" % id
