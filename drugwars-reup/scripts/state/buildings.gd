class_name Buildings
extends RefCounted

## Occupiable operations tied to REAL map locations. Kinds + costs mirror the server exactly
## (0009_harden.sql sets the price server-side by kind, so a client can never forge it). Local play
## uses this table; when online, acquire/release route through the acquire_building / release_building
## RPCs and the server is the authority.

# kind → {name, cost, blurb}. Order = cheapest → priciest (how the store lists them).
const KINDS := {
	"stash_spot":  {"name": "Stash spot",  "cost": 250,  "blurb": "A hidden cache. Cheap, low capacity, low heat."},
	"corner":      {"name": "Corner",      "cost": 500,  "blurb": "A claimed selling corner. Foot traffic, more heat."},
	"trap_house":  {"name": "Trap house",  "cost": 1200, "blurb": "A working trap. Crew pushes product while you're gone."},
	"stash_house": {"name": "Stash house", "cost": 4000, "blurb": "Serious storage. Big capacity, discreet."},
	"front":       {"name": "Front",       "cost": 6000, "blurb": "A legit-looking business. Launders cash, lowers heat."},
}

static func kind_ids() -> Array:
	return KINDS.keys()

static func cost(kind: String) -> int:
	return int(KINDS.get(kind, {}).get("cost", 1000))

static func display_name(kind: String) -> String:
	return String(KINDS.get(kind, {}).get("name", kind.capitalize()))

static func blurb(kind: String) -> String:
	return String(KINDS.get(kind, {}).get("blurb", ""))

## Stable key for a map location (dedupes across taps / OSM id gaps): OSM id when known, else a
## coordinate bucket rounded to ~11m so the same spot maps to the same building.
static func location_key(osm_id: String, lat: float, lon: float) -> String:
	if osm_id != "":
		return "osm:" + osm_id
	return "geo:%.4f,%.4f" % [lat, lon]
