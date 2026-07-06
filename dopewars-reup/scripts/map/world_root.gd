extends Node2D

## Top-level scene controller: spawns markers, instantiates the HUD, wires signals
## between MapView, HUD, and PlayerState. v0.1 only.

@onready var map: MapView = $MapView as MapView

const LOCAL_ZOOM := 14   # town / block level — your operations and influence
const REGION_ZOOM := 9   # regional — cities + travel routes

var _player_marker: MapMarker
var _hud  # CanvasLayer with hud.gd
var _view_mode := "town"
var _overlay_dim := 0   # Intel.Dim: NONE → DANGER → MARKET → COMPETITION → …

func _ready() -> void:
	# Make sure the city you're standing in has intel (new game / pre-intel saves).
	if PlayerState.intel_snapshot(PlayerState.current_city_id).is_empty():
		PlayerState.gather_intel(PlayerState.current_city_id, true)
	_load_cities()
	_spawn_player_marker()
	_spawn_hud()
	# Re-apply the active overlay whenever intel changes (e.g. a fresh gather on arrival).
	PlayerState.intel_changed.connect(func():
		if _overlay_dim != 0:
			map.set_overlay(_overlay_dim))
	# Owned operations show as gold pins on the map.
	PlayerState.buildings_changed.connect(_refresh_building_markers)
	_refresh_building_markers()
	# When the player's lat/lon changes (travel tick), re-project the marker on the map.
	PlayerState.position_changed.connect(_on_position_changed)
	# A city was tapped — open trip mode picker.
	map.city_tapped.connect(_on_city_tapped)
	# Show / hide the active route polyline on the map, and swap zoom to match the task:
	# regional while traveling (see the route + cities), town-level when settled.
	PlayerState.travel_started.connect(func(t): map.show_route(t.route); _set_view("region"))
	PlayerState.travel_canceled.connect(func(): map.clear_route(); _set_view("town"))
	PlayerState.travel_arrived.connect(func(_id): map.clear_route(); _set_view("town"))
	# Start at the right zoom: regional if a trip is already underway, else your town.
	if PlayerState.travel != null:
		map.show_route(PlayerState.travel.route)
		_set_view("region")
	else:
		_set_view("town")
	print("[Re-Up] world ready. cities loaded; player at %s." % PlayerState.current_city_id)

func _set_view(mode: String) -> void:
	_view_mode = mode
	var z: int = REGION_ZOOM if mode == "region" else LOCAL_ZOOM
	map.set_zoom(z, PlayerState.lat, PlayerState.lon)
	if _hud != null:
		_hud.set_view_mode(mode)

func _toggle_view() -> void:
	_set_view("town" if _view_mode == "region" else "region")

func _load_cities() -> void:
	for c in Cities.all():
		var marker := MapMarker.new()
		marker.label_text = c.name
		marker.color = Color(0.20, 0.55, 0.95)  # city blue
		map.add_marker(marker, float(c.lat), float(c.lon), c.id)

var _building_markers: Array = []

func _refresh_building_markers() -> void:
	for m in _building_markers:
		if is_instance_valid(m):
			m.queue_free()
	_building_markers.clear()
	for key in PlayerState.buildings.keys():
		var b: Dictionary = PlayerState.buildings[key]
		var marker := MapMarker.new()
		marker.label_text = Buildings.display_name(String(b.get("kind", "")))
		marker.color = Color(0.95, 0.72, 0.28)   # gold: your operations
		marker.radius = 6.0
		map.add_marker(marker, float(b.get("lat", 0.0)), float(b.get("lon", 0.0)))
		_building_markers.append(marker)

func _spawn_player_marker() -> void:
	_player_marker = MapMarker.new()
	_player_marker.label_text = "you"
	_player_marker.color = Color(0.92, 0.20, 0.25)  # Re-Up red
	_player_marker.radius = 8.0
	_player_marker.z_index = 1   # draw above city markers
	map.add_marker(_player_marker, PlayerState.lat, PlayerState.lon)
	# Re-center the camera on the player's persisted position (not the map default).
	map.center_on(PlayerState.lat, PlayerState.lon)

func _spawn_hud() -> void:
	_hud = preload("res://scripts/ui/hud.gd").new()
	add_child(_hud)
	_hud.market_requested.connect(_on_market_requested)
	_hud.cancel_travel_requested.connect(_on_cancel_travel)
	_hud.zoom_toggle_requested.connect(_toggle_view)
	_hud.intel_overlay_requested.connect(_cycle_overlay)

## Cycle the map-intel overlay: Off → Danger → Market → Competition → Off.
func _cycle_overlay() -> void:
	_overlay_dim = (_overlay_dim + 1) % 4
	map.set_overlay(_overlay_dim)
	if _hud != null:
		_hud.set_overlay_label(Intel.dim_name(_overlay_dim))

func _on_position_changed(lat: float, lon: float) -> void:
	map.update_marker_position(_player_marker, lat, lon)

func _on_city_tapped(city_id: String) -> void:
	if PlayerState.travel != null:
		return  # in transit; ignore
	if PlayerState.current_city_id == city_id:
		return  # already here
	var c := Cities.by_id(city_id)
	if c.is_empty():
		return
	_hud.show_travel_confirm(float(c.lat), float(c.lon), city_id)

func _on_market_requested() -> void:
	_hud.show_market()

func _on_cancel_travel() -> void:
	PlayerState.cancel_travel()
