class_name Cosmetics
extends RefCounted

## Loads data/cosmetics.json (client mirror of the backend catalog, matched by id). Cosmetics are
## FLAIR ONLY — no item affects gameplay, honoring the no-pay-to-win pillar. `store` items are bought
## with CRED (an earned currency); `supporter`/`award`/`earned` items are granted, never purchasable.

const PATH := "res://data/cosmetics.json"

const RARITY_COLOR := {
	"common":    Color(0.72, 0.75, 0.80),
	"uncommon":  Color(0.45, 0.78, 0.52),
	"rare":      Color(0.36, 0.62, 0.95),
	"epic":      Color(0.72, 0.45, 0.95),
	"legendary": Color(0.95, 0.72, 0.28),
	"mythic":    Color(0.95, 0.35, 0.42),
	"exclusive": Color(0.95, 0.85, 0.45),
}

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

## Distinct categories, in catalog order (emblem, title, nameplate, frame, …).
static func categories() -> Array:
	var out: Array = []
	for c in all():
		if not out.has(c.category):
			out.append(c.category)
	return out

static func by_category(cat: String) -> Array:
	var out: Array = []
	for c in all():
		if c.category == cat:
			out.append(c)
	return out

## Only the CRED-buyable items (source == "store"). Everything else is granted.
static func is_purchasable(item: Dictionary) -> bool:
	return String(item.get("source", "")) == "store"

static func rarity_color(rarity: String) -> Color:
	return RARITY_COLOR.get(rarity, Color(0.8, 0.8, 0.8))

static func art_path(id: String) -> String:
	return String(by_id(id).get("art", ""))

static func _load() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("[cosmetics] cannot open " + PATH)
		return
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if typeof(doc) != TYPE_DICTIONARY or not doc.has("cosmetics"):
		push_error("[cosmetics] malformed")
		return
	_cache = doc.cosmetics
