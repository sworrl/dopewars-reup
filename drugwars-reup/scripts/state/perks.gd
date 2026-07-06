class_name Perks
extends RefCounted

## Loads data/perks.json and exposes lookups + effect aggregation.
## See PlayerState for how individual effect keys are applied to gameplay systems.

const PATH := "res://data/perks.json"

static var _all: Array = []
static var _by_id: Dictionary = {}

static func all() -> Array:
	if _all.is_empty():
		_load()
	return _all

static func by_id(id: String) -> Dictionary:
	if _by_id.is_empty():
		_load()
	return _by_id.get(id, {})

## Returns array of perks available at chargen for a given class:
##   - all universal tier-1 perks
##   - this class's class-locked perks (any tier)
##   - excluded: hidden perks (must be unlocked in-game)
static func chargen_available_for_class(class_id: String) -> Array:
	var out: Array = []
	for p in all():
		if p.get("hidden", false):
			continue
		var lock = p.get("class_lock", null)
		if lock == null and int(p.get("tier", 1)) == 1:
			out.append(p)
		elif lock == class_id:
			out.append(p)
	return out

## Sums numeric effects from a list of perk ids (e.g. carry_lb_bonus).
## Multiplicatives are accumulated as (1+sum_of_deltas) — e.g. 0.10 + 0.05 = 1.15x.
## Returns dict of effect → number (or true for booleans).
static func aggregate_effects(perk_ids: Array) -> Dictionary:
	var agg: Dictionary = {}
	for pid in perk_ids:
		var p := by_id(pid)
		var eff: Dictionary = p.get("effect", {})
		for k in eff.keys():
			var v = eff[k]
			if k == "stat_bonus":
				if not agg.has("stat_bonus"):
					agg["stat_bonus"] = {}
				for stat_k in v.keys():
					agg["stat_bonus"][stat_k] = int(agg["stat_bonus"].get(stat_k, 0)) + int(v[stat_k])
			elif typeof(v) == TYPE_BOOL:
				agg[k] = agg.get(k, false) or bool(v)
			elif typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				agg[k] = float(agg.get(k, 0.0)) + float(v)
			else:
				# Strings, dicts, arrays: keep last-write-wins (rarely used at chargen tier)
				agg[k] = v
	return agg

static func _load() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("[perks] cannot open " + PATH)
		return
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if typeof(doc) != TYPE_DICTIONARY or not doc.has("perks"):
		push_error("[perks] malformed")
		return
	_all = doc.perks
	for p in _all:
		_by_id[p.id] = p
