class_name Travel
extends Resource

## A trip in progress. Real-time: positions interpolate along a Route polyline
## (real road geometry from OSRM) based on (now - started_at) / (eta_at - started_at).
##
## Effective duration is supplied by TripPlanner, which applies mode-specific
## multipliers (bus stops, rideshare hail, plane boarding) on top of OSRM's raw estimate.

# GA is appended (value 8) so existing saved trips keep their mode ints.
enum Mode { WALK, BIKE, MOTORCYCLE, CAR, BUS, RIDESHARE, PLANE, WALK_OFFROAD, GA }

const MODE_LABEL := {
	Mode.WALK: "walking",
	Mode.BIKE: "biking",
	Mode.MOTORCYCLE: "riding",
	Mode.CAR: "driving",
	Mode.BUS: "on the bus",
	Mode.RIDESHARE: "in a ride",
	Mode.PLANE: "flying",
	Mode.WALK_OFFROAD: "hiking",
	Mode.GA: "flying yourself",
}

@export var mode: Mode = Mode.WALK
@export var dest_city_id: String = ""
@export var origin_city_id: String = ""   # city departed from; used to restore on cancel
@export var started_at: float = 0.0
@export var eta_at: float = 0.0
@export var route: Route = null

static func make(r: Route, dest_city: String, m: Mode, effective_duration_s: float,
		now_unix: float, origin_city: String = "") -> Travel:
	var t := Travel.new()
	t.route = r
	t.mode = m
	t.dest_city_id = dest_city
	t.origin_city_id = origin_city
	t.started_at = now_unix
	t.eta_at = now_unix + effective_duration_s
	return t

func progress(now_unix: float) -> float:
	var span := eta_at - started_at
	if span <= 0.0:
		return 1.0
	return clampf((now_unix - started_at) / span, 0.0, 1.0)

func position(now_unix: float) -> Vector2:
	# Returns Vector2(lat, lon).
	if route == null:
		return Vector2.ZERO
	return route.position_at_progress(progress(now_unix))

func origin_latlon() -> Vector2:
	return route.polyline_latlon[0] if route != null and route.polyline_latlon.size() > 0 else Vector2.ZERO

func dest_latlon() -> Vector2:
	if route == null or route.polyline_latlon.is_empty():
		return Vector2.ZERO
	return route.polyline_latlon[route.polyline_latlon.size() - 1]

func is_complete(now_unix: float) -> bool:
	return now_unix >= eta_at

func remaining_seconds(now_unix: float) -> float:
	return maxf(eta_at - now_unix, 0.0)

func miles_total() -> float:
	return route.total_distance_m / 1609.344 if route != null else 0.0

func mode_label() -> String:
	return MODE_LABEL[mode]

func to_dict() -> Dictionary:
	return {
		"mode": int(mode),
		"dest_city_id": dest_city_id,
		"origin_city_id": origin_city_id,
		"started_at": started_at,
		"eta_at": eta_at,
		"route": route.to_dict() if route != null else null,
	}

static func from_dict(d: Dictionary) -> Travel:
	var t := Travel.new()
	t.mode = d.get("mode", Mode.WALK) as Mode
	t.dest_city_id = d.get("dest_city_id", "")
	t.origin_city_id = d.get("origin_city_id", "")
	t.started_at = float(d.get("started_at", 0.0))
	t.eta_at = float(d.get("eta_at", 0.0))
	var r = d.get("route", null)
	t.route = Route.from_dict(r) if typeof(r) == TYPE_DICTIONARY else null
	return t

static func format_remaining(seconds: float) -> String:
	var s := int(seconds)
	if s <= 0:
		return "arriving"
	var d := s / 86400
	var h := (s % 86400) / 3600
	var m := (s % 3600) / 60
	if d > 0:
		return "%dd %dh" % [d, h]
	if h > 0:
		return "%dh %dm" % [h, m]
	return "%dm" % maxi(m, 1)
