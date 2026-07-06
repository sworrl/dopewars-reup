class_name TripPlanner
extends RefCounted

## Enumerates transport modes between two points.
##
## v0.1.5 strategy: fetch ONE driving route from OSRM (the public demo only has the
## driving profile properly indexed — walking/cycling endpoints fall back to driving
## anyway). Compute each mode's ETA from the route's distance using a mode-specific
## speed; apply per-mode overhead (boarding, hail, stops). When we self-host OSRM
## with foot/bike profiles, swap to per-mode polylines for true pedestrian/bike paths.
##
## v0.1.5: every mode is "available" (no vehicle-ownership gate) — chargen lands v0.2.

class TripOption:
	extends RefCounted
	var mode: Travel.Mode
	var label: String
	var sublabel: String = ""
	var icon: String
	var route: Route                  # may be null on routing failure
	var eta_s: float = 0.0
	var cost_dollars: int = 0
	var available: bool = true
	var unavailable_reason: String = ""
	var needs_purchase: bool = false  # locked personal vehicle the player could go buy
	var marketplace_query: String = ""

# Speeds in MPH. -1 means "trust OSRM's driving estimate as-is."
const MODE_SPEED_MPH := {
	Travel.Mode.WALK: 3.0,
	Travel.Mode.WALK_OFFROAD: 2.0,    # cross-country, no roads
	Travel.Mode.BIKE: 12.0,
	Travel.Mode.MOTORCYCLE: 55.0,
	Travel.Mode.CAR: -1.0,
	Travel.Mode.BUS: -1.0,
	Travel.Mode.RIDESHARE: -1.0,
	Travel.Mode.PLANE: 500.0,
}

const MODE_DURATION_FACTOR := {
	Travel.Mode.CAR: 1.0,
	Travel.Mode.BUS: 1.3,
	Travel.Mode.RIDESHARE: 1.0,
}

const MODE_OVERHEAD_S := {
	Travel.Mode.WALK: 0.0,
	Travel.Mode.WALK_OFFROAD: 0.0,
	Travel.Mode.BIKE: 0.0,
	Travel.Mode.MOTORCYCLE: 0.0,
	Travel.Mode.CAR: 0.0,
	Travel.Mode.BUS: 600.0,
	Travel.Mode.RIDESHARE: 300.0,
	Travel.Mode.PLANE: 5400.0,
}

const MODE_COST_BASE := {
	Travel.Mode.WALK: 0,
	Travel.Mode.WALK_OFFROAD: 0,
	Travel.Mode.BIKE: 0,
	Travel.Mode.MOTORCYCLE: 0,
	Travel.Mode.CAR: 0,
	Travel.Mode.BUS: 5,
	Travel.Mode.RIDESHARE: 2,
	Travel.Mode.PLANE: 50,
}

const MODE_COST_PER_MILE := {
	Travel.Mode.WALK: 0.0,
	Travel.Mode.WALK_OFFROAD: 0.0,
	Travel.Mode.BIKE: 0.0,
	Travel.Mode.MOTORCYCLE: 0.06,
	Travel.Mode.CAR: 0.15,
	Travel.Mode.BUS: 0.10,
	Travel.Mode.RIDESHARE: 1.50,
	Travel.Mode.PLANE: 1.00,
}

const MODE_LABEL := {
	Travel.Mode.WALK: "Walk",
	Travel.Mode.WALK_OFFROAD: "Hike (off-road)",
	Travel.Mode.BIKE: "Bike",
	Travel.Mode.MOTORCYCLE: "Motorcycle",
	Travel.Mode.CAR: "Car",
	Travel.Mode.BUS: "Bus (Wolfline)",
	Travel.Mode.RIDESHARE: "Rideshare (Boober/Splift)",
	Travel.Mode.PLANE: "Flight (commercial)",
}

const MODE_SUBLABEL := {
	Travel.Mode.WALK: "on roads",
	Travel.Mode.WALK_OFFROAD: "through woods/fields · slower, no road",
	Travel.Mode.PLANE: "TSA bag screening at gate",
}

## Bespoke transport art (no emoji). Paths to Imagen-generated icons.
const MODE_ICON := {
	Travel.Mode.WALK: "res://assets/sprites/transport/walk.png",
	Travel.Mode.WALK_OFFROAD: "res://assets/sprites/transport/walk_offroad.png",
	Travel.Mode.BIKE: "res://assets/sprites/transport/bike.png",
	Travel.Mode.MOTORCYCLE: "res://assets/sprites/transport/motorcycle.png",
	Travel.Mode.CAR: "res://assets/sprites/transport/car.png",
	Travel.Mode.BUS: "res://assets/sprites/transport/bus.png",
	Travel.Mode.RIDESHARE: "res://assets/sprites/transport/rideshare.png",
	Travel.Mode.PLANE: "res://assets/sprites/transport/plane.png",
}

## Personal vehicles the player must OWN to use. Services (bus/rideshare/plane) are hireable,
## not owned. A locked owned-vehicle row offers a real used-marketplace search link.
const OWNED_VEHICLE_MODES := [Travel.Mode.BIKE, Travel.Mode.MOTORCYCLE, Travel.Mode.CAR]
const MODE_MARKETPLACE_QUERY := {
	Travel.Mode.BIKE: "used bicycle",
	Travel.Mode.MOTORCYCLE: "used motorcycle",
	Travel.Mode.CAR: "cheap used car",
}

const ROAD_MODES: Array = [Travel.Mode.WALK, Travel.Mode.BIKE, Travel.Mode.MOTORCYCLE,
		Travel.Mode.CAR, Travel.Mode.BUS, Travel.Mode.RIDESHARE]

## Returns Array[TripOption], populated once routing finishes.
##
## Plane mode requires `origin_is_airport` AND `dest_is_airport` — there's no
## commercial flight from a city without an airport (player must drive to one).
## Fetch the realistic driving-route alternatives for the plot-trip picker (Array[Route]).
static func plan_routes(router: Node, origin_lat: float, origin_lon: float,
		dest_lat: float, dest_lon: float) -> Array:
	return await router.fetch_routes("driving", origin_lat, origin_lon, dest_lat, dest_lon)

static func plan(router: Node, origin_lat: float, origin_lon: float,
		dest_lat: float, dest_lon: float,
		origin_is_airport: bool = false,
		dest_is_airport: bool = false,
		owned_modes: Array = []) -> Array:
	var routes: Array = await router.fetch_routes("driving", origin_lat, origin_lon, dest_lat, dest_lon)
	var driving_route: Route = routes[0] if not routes.is_empty() else null
	return options_for_route(driving_route, origin_lat, origin_lon, dest_lat, dest_lon,
		origin_is_airport, dest_is_airport, owned_modes)

## Build the per-mode options for a SPECIFIC chosen driving route (road modes follow it;
## off-road and plane are straight-line and route-independent).
static func options_for_route(driving_route: Route, origin_lat: float, origin_lon: float,
		dest_lat: float, dest_lon: float,
		origin_is_airport: bool, dest_is_airport: bool, owned_modes: Array) -> Array:
	var options: Array = []

	# Road modes — share the OSRM driving polyline.
	for m in ROAD_MODES:
		options.append(_build_road_option(m, driving_route))

	# Off-road hike — straight-line through woods/fields, slower per mile.
	var offroad_route := Route.make_straight(origin_lat, origin_lon, dest_lat, dest_lon, "offroad", 2.0)
	options.append(_build_road_option(Travel.Mode.WALK_OFFROAD, offroad_route))

	# Plane mode — commercial only, both ends must be airport-served.
	if origin_is_airport and dest_is_airport:
		var plane_route := Route.make_straight(origin_lat, origin_lon, dest_lat, dest_lon, "plane", 500.0)
		options.append(_build_plane_option(plane_route))
	else:
		var p := TripOption.new()
		p.mode = Travel.Mode.PLANE
		p.label = MODE_LABEL[Travel.Mode.PLANE]
		p.sublabel = MODE_SUBLABEL.get(Travel.Mode.PLANE, "")
		p.icon = MODE_ICON[Travel.Mode.PLANE]
		p.available = false
		if not origin_is_airport and not dest_is_airport:
			p.unavailable_reason = "no airport at origin or destination"
		elif not origin_is_airport:
			p.unavailable_reason = "no airport at your current location"
		else:
			p.unavailable_reason = "no airport at destination"
		options.append(p)

	# Access-gating: lock personal vehicles the player doesn't own; offer a marketplace link.
	for o in options:
		if o.mode in OWNED_VEHICLE_MODES and not (o.mode in owned_modes):
			o.available = false
			o.needs_purchase = true
			o.marketplace_query = MODE_MARKETPLACE_QUERY.get(o.mode, "")
			o.unavailable_reason = "You don't own a %s" % MODE_LABEL[o.mode].to_lower()

	return options

static func _build_road_option(mode: Travel.Mode, route: Route) -> TripOption:
	var o := TripOption.new()
	o.mode = mode
	o.label = MODE_LABEL[mode]
	o.sublabel = MODE_SUBLABEL.get(mode, "")
	o.icon = MODE_ICON[mode]
	o.route = route
	if route == null:
		o.available = false
		o.unavailable_reason = "routing failed"
		return o
	var miles: float = route.total_distance_m / 1609.344
	var speed_setting: float = float(MODE_SPEED_MPH[mode])
	var base_seconds: float
	if speed_setting > 0.0:
		base_seconds = (miles / speed_setting) * 3600.0
	else:
		var factor: float = float(MODE_DURATION_FACTOR.get(mode, 1.0))
		base_seconds = route.total_duration_s * factor
	o.eta_s = base_seconds + float(MODE_OVERHEAD_S[mode])
	o.cost_dollars = int(round(float(MODE_COST_BASE[mode]) + float(MODE_COST_PER_MILE[mode]) * miles))
	return o

static func _build_plane_option(route: Route) -> TripOption:
	var o := TripOption.new()
	o.mode = Travel.Mode.PLANE
	o.label = MODE_LABEL[Travel.Mode.PLANE]
	o.sublabel = MODE_SUBLABEL.get(Travel.Mode.PLANE, "")
	o.icon = MODE_ICON[Travel.Mode.PLANE]
	o.route = route
	var miles: float = route.total_distance_m / 1609.344
	o.eta_s = (miles / float(MODE_SPEED_MPH[Travel.Mode.PLANE])) * 3600.0 \
		+ float(MODE_OVERHEAD_S[Travel.Mode.PLANE])
	o.cost_dollars = int(round(float(MODE_COST_BASE[Travel.Mode.PLANE]) \
		+ float(MODE_COST_PER_MILE[Travel.Mode.PLANE]) * miles))
	return o
