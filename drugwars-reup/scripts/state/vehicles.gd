class_name Vehicles
extends RefCounted

## Loads data/vehicles.json: used-vehicle listings the player can buy in-game to raise their
## hold capacity and unlock a personal transport mode. See [[dopewars-logistics]].

const PATH := "res://data/vehicles.json"

# Which Travel.Mode each listing class maps to, and the marketplace search term for the
# real-listings link. Only these three are owned personal vehicles (bus/rideshare/plane are hired).
const MODE_KEY := {
	Travel.Mode.BIKE: "bike",
	Travel.Mode.MOTORCYCLE: "motorcycle",
	Travel.Mode.CAR: "car",
}

static var _listings: Dictionary = {}

static func _load() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if typeof(doc) == TYPE_DICTIONARY:
		_listings = doc.get("listings", {})

## Listings (Array[Dictionary]) for a Travel.Mode, or [] if it isn't a buyable vehicle.
static func for_mode(mode: int) -> Array:
	if _listings.is_empty():
		_load()
	var out: Array = _listings.get(MODE_KEY.get(mode, ""), [])
	return out

## Default trunk capacity for a mode before the player owns one (for the locked-row "holds ~N lb"
## preview). Uses the cheapest listing's trunk.
static func base_trunk_lb(mode: int) -> float:
	var l := for_mode(mode)
	if l.is_empty():
		return 0.0
	return float(l[0].get("trunk_lb", 0))
