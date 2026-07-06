class_name MapView
extends Node2D

## Pannable OSM map. Owns a camera; positions tile sprites in world space using
## Web-Mercator pixel coords at the current zoom. Markers (player, cities) are
## children that re-project their lat/lon on every camera move.
##
## Distinguishes drag (>= TAP_PIXEL_THRESHOLD movement) from tap. On tap,
## hit-tests city markers within TAP_HIT_RADIUS_PX and emits `city_tapped`.
##
## v0.1: fixed zoom, drag-to-pan, tap-to-pick-city. Pinch/scroll zoom in v0.1.5.

signal city_tapped(city_id: String)

const TAP_PIXEL_THRESHOLD := 8.0      # below this = tap, above = drag
const TAP_HIT_RADIUS_PX   := 36.0     # generous tap target around marker center

@export var initial_lat: float = 40.3698   # Steubenville, OH
@export var initial_lon: float = -80.6339
@export var zoom: int = 14                 # town/block level by default; z=9 regional for travel
@export var view_padding_tiles: int = 1    # extra tile ring around viewport for smooth pan

@onready var camera: Camera2D = %Camera
@onready var tile_root: Node2D = %TileRoot
@onready var marker_root: Node2D = %MarkerRoot
@onready var provider: TileProvider = %TileProvider

var _tile_sprites: Dictionary = {}         # Vector2i (x, y) → Sprite2D
var _last_viewport_tiles: Rect2i = Rect2i()
var _press_start_screen: Vector2 = Vector2.ZERO
var _press_active: bool = false
var _drag_started: bool = false
var _route_line: Line2D = null
var _current_route: Route = null

func _ready() -> void:
	provider.tile_ready.connect(_on_tile_ready)
	provider.tile_failed.connect(_on_tile_failed)
	camera.position = Geo.latlon_to_world_px(initial_lat, initial_lon, zoom)
	_refresh_visible_tiles()
	_reposition_markers()

const GAMEPAD_PAN_PX_PER_SEC := 600.0

func _process(dt: float) -> void:
	# Gamepad / WASD / d-pad map panning. Stick analog scales naturally with `get_axis`.
	var pan := Vector2(
		Input.get_axis("pan_left", "pan_right"),
		Input.get_axis("pan_up", "pan_down"))
	if pan.length_squared() > 0.0:
		camera.position += pan * GAMEPAD_PAN_PX_PER_SEC * dt
		_reposition_markers()
	_refresh_visible_tiles()

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_press_release(mb.pressed, mb.position)
	elif ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		_handle_press_release(st.pressed, st.position)
	elif ev is InputEventMouseMotion and _press_active:
		var mm := ev as InputEventMouseMotion
		_handle_motion(mm.position, mm.relative)
	elif ev is InputEventScreenDrag and _press_active:
		var sd := ev as InputEventScreenDrag
		_handle_motion(sd.position, sd.relative)

func _handle_press_release(pressed: bool, screen_pos: Vector2) -> void:
	if pressed:
		_press_active = true
		_drag_started = false
		_press_start_screen = screen_pos
	else:
		var was_drag := _drag_started
		_press_active = false
		_drag_started = false
		if not was_drag:
			_try_tap(screen_pos)

func _handle_motion(screen_pos: Vector2, relative: Vector2) -> void:
	var moved_total: float = (screen_pos - _press_start_screen).length()
	if moved_total >= TAP_PIXEL_THRESHOLD:
		_drag_started = true
	if _drag_started:
		camera.position -= relative
		_reposition_markers()

func _try_tap(screen_pos: Vector2) -> void:
	var world := camera.get_screen_center_position() - get_viewport_rect().size * 0.5 + screen_pos
	var best_id := ""
	var best_dist := TAP_HIT_RADIUS_PX
	for m in marker_root.get_children():
		if not (m is Node2D) or not m.has_meta("city_id"):
			continue
		var d := (m as Node2D).global_position.distance_to(world)
		if d < best_dist:
			best_dist = d
			best_id = m.get_meta("city_id")
	if best_id != "":
		city_tapped.emit(best_id)

var _overlay_dim: int = 0   # Intel.Dim.NONE

## Apply a map-intel overlay dimension (Intel.Dim) to every city marker, reading the player's
## perceived, decaying snapshots. NONE clears the halos; unknown cities get no halo either.
func set_overlay(dim: int) -> void:
	_overlay_dim = dim
	for m in marker_root.get_children():
		if not (m is MapMarker) or not m.has_meta("city_id"):
			continue
		var marker := m as MapMarker
		if dim == 0:
			marker.set_intel(0, 0.0, 0.0, Color.WHITE)
			continue
		var snap := PlayerState.intel_snapshot(String(m.get_meta("city_id")))
		if snap.is_empty():
			marker.set_intel(0, 0.0, 0.0, Color.WHITE)   # never scouted → shows nothing
			continue
		var key := Intel.dim_name(dim).to_lower()        # danger / market / competition
		marker.set_intel(dim, float(snap.get(key, 0.0)),
			float(snap.get("confidence", 0.0)), Intel.dim_color(dim))

func center_on(lat: float, lon: float) -> void:
	camera.position = Geo.latlon_to_world_px(lat, lon, zoom)
	_reposition_markers()

## Switch zoom level (town ⇄ regional) and re-center on a focus point. Wipes the old tiles
## (they're keyed per-zoom), re-projects markers + route, and reloads tiles at the new zoom.
func set_zoom(z: int, focus_lat: float, focus_lon: float) -> void:
	z = clampi(z, 3, 18)
	if z != zoom:
		zoom = z
		for key in _tile_sprites.keys():
			(_tile_sprites[key] as Node).queue_free()
		_tile_sprites.clear()
		_last_viewport_tiles = Rect2i()
	camera.position = Geo.latlon_to_world_px(focus_lat, focus_lon, zoom)
	if _current_route != null:
		show_route(_current_route)   # re-project the polyline at the new zoom
	_reposition_markers()
	_refresh_visible_tiles()

func add_marker(node: Node2D, lat: float, lon: float, city_id: String = "") -> void:
	node.set_meta("lat", lat)
	node.set_meta("lon", lon)
	if city_id != "":
		node.set_meta("city_id", city_id)
	marker_root.add_child(node)
	_reposition_marker(node)

func update_marker_position(node: Node2D, lat: float, lon: float) -> void:
	node.set_meta("lat", lat)
	node.set_meta("lon", lon)
	_reposition_marker(node)

## Show a route polyline on the map. Call clear_route() when the trip ends.
func show_route(route: Route) -> void:
	clear_route()
	_current_route = route
	if route == null or route.polyline_latlon.size() < 2:
		return
	var line := Line2D.new()
	line.width = 5.0
	line.default_color = Color(0.92, 0.20, 0.25, 0.90)  # Re-Up red
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.z_index = 5   # above tile sprites (default z=0), below markers (z=10 on player)
	line.z_as_relative = false
	var pts := PackedVector2Array()
	pts.resize(route.polyline_latlon.size())
	for i in route.polyline_latlon.size():
		var ll := route.polyline_latlon[i]
		pts[i] = Geo.latlon_to_world_px(ll.x, ll.y, zoom)
	line.points = pts
	# Sit above tiles, below markers.
	tile_root.add_child(line)
	tile_root.move_child(line, tile_root.get_child_count() - 1)
	_route_line = line

func clear_route() -> void:
	if _route_line != null and is_instance_valid(_route_line):
		_route_line.queue_free()
	_route_line = null
	_current_route = null

func _reposition_markers() -> void:
	for m in marker_root.get_children():
		_reposition_marker(m)

func _reposition_marker(m: Node) -> void:
	if not (m is Node2D) or not m.has_meta("lat"):
		return
	var lat: float = m.get_meta("lat")
	var lon: float = m.get_meta("lon")
	(m as Node2D).global_position = Geo.latlon_to_world_px(lat, lon, zoom)

func _refresh_visible_tiles() -> void:
	var vp_size := get_viewport_rect().size
	var top_left_world := camera.position - vp_size * 0.5
	var bot_right_world := camera.position + vp_size * 0.5
	var top_tile := Vector2i(
		int(floorf(top_left_world.x / Geo.TILE_SIZE)) - view_padding_tiles,
		int(floorf(top_left_world.y / Geo.TILE_SIZE)) - view_padding_tiles)
	var bot_tile := Vector2i(
		int(floorf(bot_right_world.x / Geo.TILE_SIZE)) + view_padding_tiles,
		int(floorf(bot_right_world.y / Geo.TILE_SIZE)) + view_padding_tiles)
	var rect := Rect2i(top_tile, bot_tile - top_tile + Vector2i.ONE)
	if rect == _last_viewport_tiles:
		return
	_last_viewport_tiles = rect

	var n := Geo.world_tile_count(zoom)
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			if x < 0 or x >= n or y < 0 or y >= n:
				continue
			var key := Vector2i(x, y)
			if not _tile_sprites.has(key):
				_request_tile_sprite(x, y)
	for key in _tile_sprites.keys():
		if not rect.has_point(key):
			(_tile_sprites[key] as Node).queue_free()
			_tile_sprites.erase(key)

func _request_tile_sprite(x: int, y: int) -> void:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.position = Vector2(x * Geo.TILE_SIZE, y * Geo.TILE_SIZE)
	sprite.modulate = Color(1, 1, 1, 0)
	tile_root.add_child(sprite)
	_tile_sprites[Vector2i(x, y)] = sprite
	provider.request_tile(zoom, x, y)

func _on_tile_ready(z: int, x: int, y: int, tex: Texture2D) -> void:
	if z != zoom:
		return
	var key := Vector2i(x, y)
	if not _tile_sprites.has(key):
		return
	var sprite: Sprite2D = _tile_sprites[key]
	sprite.texture = tex
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 1.0, 0.15)

func _on_tile_failed(z: int, x: int, y: int, reason: String) -> void:
	push_warning("[map] tile fetch failed z=%d x=%d y=%d reason=%s" % [z, x, y, reason])
