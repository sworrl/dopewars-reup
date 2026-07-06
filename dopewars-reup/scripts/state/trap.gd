class_name Trap
extends RefCounted

## Loads data/trap.json: trap-house tiers + hireable employees. See [[dopewars-logistics]].
## An in-game "day" is short so a passive operation pays off within a play session.

const PATH := "res://data/trap.json"
const DAY_SECONDS := 360.0   # 6 real minutes = one in-game day of pushing

static var _house_tiers: Array = []
static var _employees: Array = []

static func _load() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if typeof(doc) == TYPE_DICTIONARY:
		_house_tiers = doc.get("house_tiers", [])
		_employees = doc.get("employees", [])

static func house_tiers() -> Array:
	if _house_tiers.is_empty():
		_load()
	return _house_tiers

static func employees() -> Array:
	if _employees.is_empty():
		_load()
	return _employees

static func house_tier(id: String) -> Dictionary:
	for t in house_tiers():
		if t.get("id", "") == id:
			return t
	return {}

static func employee_type(id: String) -> Dictionary:
	for e in employees():
		if e.get("id", "") == id:
			return e
	return {}
