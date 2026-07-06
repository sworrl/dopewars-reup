class_name Overpass
extends RefCounted

## Fetches REAL nearby map locations from the OpenStreetMap Overpass API so the player can occupy
## actual businesses/buildings around their position as operations. Read-only, best-effort: any
## failure returns an empty list and the UI falls back to a generic "unnamed location" occupy.
##
## Async static call — pass a Node to parent the transient HTTPRequest under.

const ENDPOINT := "https://overpass-api.de/api/interpreter"

## Returns an Array of {osm_id, name, lat, lon, category} within radius_m of (lat, lon).
static func fetch_near(parent: Node, lat: float, lon: float, radius_m: int = 450) -> Array:
	var q := ("[out:json][timeout:20];("
		+ "node(around:%d,%f,%f)[name][shop];" % [radius_m, lat, lon]
		+ "node(around:%d,%f,%f)[name][amenity];" % [radius_m, lat, lon]
		+ "way(around:%d,%f,%f)[name][building];" % [radius_m, lat, lon]
		+ ");out center 40;")
	var req := HTTPRequest.new()
	parent.add_child(req)
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])
	var err := req.request(ENDPOINT, headers, HTTPClient.METHOD_POST, "data=" + q.uri_encode())
	if err != OK:
		req.queue_free()
		return []
	var res: Array = await req.request_completed
	req.queue_free()
	var code: int = res[1]
	if code < 200 or code >= 300:
		return []
	return parse((res[3] as PackedByteArray).get_string_from_utf8())

## Parse an Overpass JSON response into occupiable-location dicts. Pure — unit-testable offline.
static func parse(json_text: String) -> Array:
	var doc: Variant = JSON.parse_string(json_text)
	if typeof(doc) != TYPE_DICTIONARY or not doc.has("elements"):
		return []
	var out: Array = []
	var seen := {}
	for el in doc["elements"]:
		var tags: Dictionary = el.get("tags", {})
		var name := String(tags.get("name", "")).strip_edges()
		if name == "":
			continue
		var p_lat: float
		var p_lon: float
		if el.has("lat") and el.has("lon"):
			p_lat = float(el["lat"]); p_lon = float(el["lon"])
		elif el.has("center"):
			p_lat = float(el["center"].get("lat", 0.0)); p_lon = float(el["center"].get("lon", 0.0))
		else:
			continue
		var osm_id := "%s/%d" % [String(el.get("type", "node")), int(el.get("id", 0))]
		# Prefer the most specific category tag for flavor.
		var category := String(tags.get("shop", tags.get("amenity", tags.get("building", "place"))))
		var key := name + "@%.4f,%.4f" % [p_lat, p_lon]
		if seen.has(key):
			continue
		seen[key] = true
		out.append({"osm_id": osm_id, "name": name, "lat": p_lat, "lon": p_lon, "category": category})
	return out
