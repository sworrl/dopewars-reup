class_name Weapons
extends RefCounted

## Loads data/weapons.json. Two acquisition paths with REAL US legal mechanics:
##   legal (FFL/knife shop): NICS background check, serial on record (traceable), age gate, and for
##     NFA classes (full-auto, destructive devices) a Form-4 + $200 stamp + ~10-month wait — priced
##     so they're realistically out of reach for a street operator.
##   black market: no/filed serial, no check, faster — but illegal, adds heat, and carries bust/scam
##     risk. The real path for anything NFA.
## Threat is a combat stat used by the fights/challenges system.

const PATH := "res://data/weapons.json"

static var _cache: Array = []

static func all() -> Array:
	if _cache.is_empty():
		_load()
	return _cache

static func by_id(id: String) -> Dictionary:
	for w in all():
		if w.id == id:
			return w
	return {}

static func categories() -> Array:
	var out: Array = []
	for w in all():
		if not out.has(w.category):
			out.append(w.category)
	return out

static func by_category(cat: String) -> Array:
	var out: Array = []
	for w in all():
		if w.category == cat:
			out.append(w)
	return out

## Can this be bought legally at all (an FFL/shop will sell it)?
static func legal_available(w: Dictionary) -> bool:
	return bool(w.get("legal", {}).get("available", false))

## Requires the NFA process (Form 4, tax stamp, long wait) — full-auto + destructive devices.
static func is_nfa(w: Dictionary) -> bool:
	return bool(w.get("legal", {}).get("nfa", false))

static func legal_price(w: Dictionary):
	return w.get("legal", {}).get("price", null)

static func black_price(w: Dictionary) -> int:
	return int(w.get("black_market", {}).get("price", 0))

## Heat drawn by acquiring/carrying this off the black market.
static func black_heat(w: Dictionary) -> int:
	return int(w.get("black_market", {}).get("heat", 0))

static func _load() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("[weapons] cannot open " + PATH)
		return
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if typeof(doc) != TYPE_DICTIONARY or not doc.has("weapons"):
		push_error("[weapons] malformed")
		return
	_cache = doc.weapons
