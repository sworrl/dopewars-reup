class_name Route
extends Resource

## A real-road route returned by OSRM. polyline_latlon is the raw OSRM geometry
## (lat in x, lon in y — note OSRM gives [lon, lat] but we normalize to lat-first
## for consistency with the rest of the codebase). cumulative_m[i] is the total
## meters traveled to reach polyline_latlon[i]; cumulative_m[-1] == total_distance_m.
##
## position_at_progress(p) walks the polyline by *distance* fraction, which assumes
## uniform speed. Good enough for visualization at v0.1.5. OSRM also returns per-
## segment durations we could use for non-uniform speed later.

@export var polyline_latlon: PackedVector2Array     # Vector2(lat, lon)
@export var cumulative_m: PackedFloat32Array
@export var total_distance_m: float = 0.0
@export var total_duration_s: float = 0.0           # OSRM's estimate at its profile speed
@export var profile: String = ""                     # "walking" | "cycling" | "driving"

static func make_straight(start_lat: float, start_lon: float, end_lat: float, end_lon: float,
		profile_name: String, speed_mph: float) -> Route:
	# For modes OSRM doesn't handle (plane, or when network is unavailable). 2-point line.
	var r := Route.new()
	r.profile = profile_name
	r.polyline_latlon = PackedVector2Array([Vector2(start_lat, start_lon), Vector2(end_lat, end_lon)])
	var miles := Geo.miles_between(start_lat, start_lon, end_lat, end_lon)
	var meters := miles * 1609.344
	r.cumulative_m = PackedFloat32Array([0.0, meters])
	r.total_distance_m = meters
	r.total_duration_s = (miles / speed_mph) * 3600.0
	return r

static func from_osrm(geometry_coords: Array, distance_m: float, duration_s: float,
		profile_name: String) -> Route:
	# OSRM GeoJSON LineString: coords are [lon, lat] pairs. Normalize.
	var poly := PackedVector2Array()
	poly.resize(geometry_coords.size())
	for i in geometry_coords.size():
		var c: Array = geometry_coords[i]
		poly[i] = Vector2(float(c[1]), float(c[0]))  # (lat, lon)
	var cum := PackedFloat32Array()
	cum.resize(poly.size())
	cum[0] = 0.0
	for i in range(1, poly.size()):
		var prev := poly[i - 1]
		var cur := poly[i]
		var seg_mi := Geo.miles_between(prev.x, prev.y, cur.x, cur.y)
		cum[i] = cum[i - 1] + seg_mi * 1609.344
	var r := Route.new()
	r.polyline_latlon = poly
	r.cumulative_m = cum
	r.total_distance_m = distance_m if distance_m > 0.0 else cum[cum.size() - 1]
	r.total_duration_s = duration_s
	r.profile = profile_name
	return r

func position_at_progress(p: float) -> Vector2:
	# p ∈ [0,1] along the route by distance. Returns lat/lon.
	if polyline_latlon.size() < 2:
		return polyline_latlon[0] if polyline_latlon.size() == 1 else Vector2.ZERO
	if p <= 0.0:
		return polyline_latlon[0]
	if p >= 1.0:
		return polyline_latlon[polyline_latlon.size() - 1]
	var target_m := p * total_distance_m
	# Binary search for segment.
	var lo := 0
	var hi := cumulative_m.size() - 1
	while lo + 1 < hi:
		var mid := (lo + hi) / 2
		if cumulative_m[mid] <= target_m:
			lo = mid
		else:
			hi = mid
	var seg_start := cumulative_m[lo]
	var seg_end := cumulative_m[lo + 1]
	var seg_span := seg_end - seg_start
	var local_t: float = 0.0 if seg_span <= 0.0 else (target_m - seg_start) / seg_span
	return polyline_latlon[lo].lerp(polyline_latlon[lo + 1], local_t)

func to_dict() -> Dictionary:
	# Persisted across sessions so an in-progress trip survives app close.
	var poly: Array = []
	for v in polyline_latlon:
		poly.append([v.x, v.y])
	return {
		"profile": profile,
		"poly": poly,
		"cum": Array(cumulative_m),
		"total_distance_m": total_distance_m,
		"total_duration_s": total_duration_s,
	}

static func from_dict(d: Dictionary) -> Route:
	var r := Route.new()
	r.profile = d.get("profile", "")
	r.total_distance_m = float(d.get("total_distance_m", 0.0))
	r.total_duration_s = float(d.get("total_duration_s", 0.0))
	var raw_poly: Array = d.get("poly", [])
	r.polyline_latlon = PackedVector2Array()
	r.polyline_latlon.resize(raw_poly.size())
	for i in raw_poly.size():
		var p: Array = raw_poly[i]
		r.polyline_latlon[i] = Vector2(float(p[0]), float(p[1]))
	var raw_cum: Array = d.get("cum", [])
	r.cumulative_m = PackedFloat32Array()
	r.cumulative_m.resize(raw_cum.size())
	for i in raw_cum.size():
		r.cumulative_m[i] = float(raw_cum[i])
	return r
