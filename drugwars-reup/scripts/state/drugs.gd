class_name Drugs
extends RefCounted

## Loads data/drugs.json and data/region_drug_profiles.json once, exposes lookup helpers.
## v0.1-content. v0.2 = pulls from server / Postgres view.

const DRUGS_PATH := "res://data/drugs.json"
const PROFILES_PATH := "res://data/region_drug_profiles.json"

static var _drugs: Array = []
static var _by_id: Dictionary = {}
static var _profiles: Dictionary = {}

static func all() -> Array:
	if _drugs.is_empty():
		_load()
	return _drugs

static func by_id(id: String) -> Dictionary:
	if _by_id.is_empty():
		_load()
	return _by_id.get(id, {})

static func region_demand(region_id: String, drug_id: String) -> float:
	if _profiles.is_empty():
		_load()
	var region: Dictionary = _profiles.get(region_id, {})
	var demand: Dictionary = region.get("demand", {})
	return float(demand.get(drug_id, 1.0))

# Stash-size art tiers. A "unit" is one dose/pill/gram (weight_per_unit_g), so 500 oxy pills
# and 500 g of weed both read as a bulk seizure even though their gram weights differ wildly.
enum Tier { SMALL, MID, BULK }
const _TIER_SUFFIX := {Tier.SMALL: "", Tier.MID: "_mid", Tier.BULK: "_bulk"}
const _MID_UNITS := 30.0
const _BULK_UNITS := 500.0

static func size_tier(drug_id: String, grams: int) -> int:
	var d := by_id(drug_id)
	var per_unit := float(d.get("weight_per_unit_g", 1.0))
	if per_unit <= 0.0:
		per_unit = 1.0
	var units := float(grams) / per_unit
	if units >= _BULK_UNITS:
		return Tier.BULK
	if units >= _MID_UNITS:
		return Tier.MID
	return Tier.SMALL

## Product art for a given stash size. Falls back to the base {id}.png when the tiered
## asset hasn't been generated yet (asset batches land incrementally).
static func icon_path(drug_id: String, grams: int) -> String:
	var suffix: String = _TIER_SUFFIX[size_tier(drug_id, grams)]
	if suffix != "":
		var tiered := "res://assets/sprites/items/%s%s.png" % [drug_id, suffix]
		if ResourceLoader.exists(tiered):
			return tiered
	return "res://assets/sprites/items/%s.png" % drug_id

static func region_heat(region_id: String) -> int:
	if _profiles.is_empty():
		_load()
	var region: Dictionary = _profiles.get(region_id, {})
	return int(region.get("heat", 30))

static func region_od_baseline(region_id: String) -> int:
	if _profiles.is_empty():
		_load()
	var region: Dictionary = _profiles.get(region_id, {})
	return int(region.get("od_baseline_per_100k", 0))

static func _load() -> void:
	var f := FileAccess.open(DRUGS_PATH, FileAccess.READ)
	if f:
		var doc: Variant = JSON.parse_string(f.get_as_text())
		if typeof(doc) == TYPE_DICTIONARY and doc.has("drugs"):
			_drugs = doc.drugs
			for d in _drugs:
				_by_id[d.id] = d
	f = FileAccess.open(PROFILES_PATH, FileAccess.READ)
	if f:
		var doc: Variant = JSON.parse_string(f.get_as_text())
		if typeof(doc) == TYPE_DICTIONARY and doc.has("regions"):
			_profiles = doc.regions
