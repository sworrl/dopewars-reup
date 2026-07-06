extends Node

## Async OSRM router with per-(profile,origin,dest) cache. Autoload singleton.
##
## Backend defaults to the public OSRM demo server. That server is rate-limited and
## explicitly "not for production" — fine for dev. Override BASE_URL when we self-host.
##
## Usage:
##   var route_or_null = await Router.fetch(profile, lat1, lon1, lat2, lon2)

const BASE_URL := "https://router.project-osrm.org"
const USER_AGENT := "DrugWarsReUp/0.1-dev (https://github.com/; pre-alpha)"
const REQUEST_TIMEOUT := 15.0
const COORD_ROUND := 4   # ~10m precision; cache key dedupe

var _cache: Dictionary = {}        # String key → Route
var _in_flight: Dictionary = {}    # String key → Array of pending callables to resume

signal _route_done(key: String, route: Route)

static func _key(profile: String, lat1: float, lon1: float, lat2: float, lon2: float) -> String:
	var r := COORD_ROUND
	return "%s|%.*f,%.*f→%.*f,%.*f" % [profile, r, lat1, r, lon1, r, lat2, r, lon2]

func fetch(profile: String, lat1: float, lon1: float, lat2: float, lon2: float) -> Route:
	var key := _key(profile, lat1, lon1, lat2, lon2)
	if _cache.has(key):
		return _cache[key]
	if _in_flight.has(key):
		# Coalesce: another caller is fetching this same route. Wait for it.
		while _in_flight.has(key):
			await _route_done
		return _cache.get(key, null)
	_in_flight[key] = true
	var route := await _do_fetch(profile, lat1, lon1, lat2, lon2)
	# Only cache successes — caching a null (failed/offline) route would poison this
	# city-pair permanently, so a transient failure could never be retried.
	if route != null:
		_cache[key] = route
	_in_flight.erase(key)
	_route_done.emit(key, route)
	return route

## Fetch up to 3 realistic route alternatives (for the plot-trip picker). Cached per key.
func fetch_routes(profile: String, lat1: float, lon1: float, lat2: float, lon2: float) -> Array:
	var key := "R|" + _key(profile, lat1, lon1, lat2, lon2)
	if _cache.has(key):
		return _cache[key]
	var routes: Array = await _do_fetch_all(profile, lat1, lon1, lat2, lon2)
	if not routes.is_empty():
		_cache[key] = routes
	return routes

func _do_fetch_all(profile: String, lat1: float, lon1: float, lat2: float, lon2: float) -> Array:
	var url := "%s/route/v1/%s/%f,%f;%f,%f?overview=full&geometries=geojson&steps=false&alternatives=3" % [
		BASE_URL, profile, lon1, lat1, lon2, lat2]
	var req := HTTPRequest.new()
	req.timeout = REQUEST_TIMEOUT
	add_child(req)
	var err := req.request(url, PackedStringArray(["User-Agent: " + USER_AGENT]))
	if err != OK:
		req.queue_free()
		return []
	var result: Array = await req.request_completed
	req.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
		return []
	var doc: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if typeof(doc) != TYPE_DICTIONARY or doc.get("code", "") != "Ok":
		return []
	var out: Array = []
	for r in doc.get("routes", []):
		var coords: Array = (r.get("geometry", {}) as Dictionary).get("coordinates", [])
		if coords.is_empty():
			continue
		out.append(Route.from_osrm(coords, float(r.get("distance", 0.0)),
			float(r.get("duration", 0.0)), profile))
	return out

func _do_fetch(profile: String, lat1: float, lon1: float, lat2: float, lon2: float) -> Route:
	var url := "%s/route/v1/%s/%f,%f;%f,%f?overview=full&geometries=geojson&steps=false&alternatives=false" % [
		BASE_URL, profile, lon1, lat1, lon2, lat2]
	var req := HTTPRequest.new()
	req.timeout = REQUEST_TIMEOUT
	add_child(req)
	var headers := PackedStringArray(["User-Agent: " + USER_AGENT])
	var err := req.request(url, headers)
	if err != OK:
		req.queue_free()
		push_warning("[router] HTTPRequest.request err=%d" % err)
		return null
	var result: Array = await req.request_completed
	req.queue_free()
	# request_completed signal: (result, response_code, headers, body)
	var http_result: int = result[0]
	var code: int = result[1]
	var body: PackedByteArray = result[3]
	if http_result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("[router] %s %d→%d profile=%s" % [url, code, http_result, profile])
		return null
	var doc: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(doc) != TYPE_DICTIONARY:
		push_warning("[router] non-JSON response")
		return null
	if doc.get("code", "") != "Ok":
		push_warning("[router] OSRM code=%s" % doc.get("code", "?"))
		return null
	var routes: Array = doc.get("routes", [])
	if routes.is_empty():
		return null
	var first: Dictionary = routes[0]
	var geom: Dictionary = first.get("geometry", {})
	var coords: Array = geom.get("coordinates", [])
	if coords.is_empty():
		return null
	return Route.from_osrm(coords, float(first.get("distance", 0.0)),
		float(first.get("duration", 0.0)), profile)
