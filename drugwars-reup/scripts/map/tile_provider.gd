class_name TileProvider
extends Node

## OSM raster tile fetcher with on-disk cache.
##
## Cache layout: user://tiles/<z>/<x>/<y>.png (Godot user:// → app data dir on Android,
## ~/.local/share/godot/app_userdata/<project>/ on Linux dev).
##
## Concurrency: caps active HTTP fetches to MAX_PARALLEL (politeness for OSM tile server).
## Pending requests are queued; when an HTTPRequest finishes, the next queued URL is started.
##
## Attribution: callers are responsible for displaying "© OpenStreetMap contributors".

const MAX_PARALLEL := 2

## OSM official tile server. Per usage policy, swap to a paid provider (Stadia, MapTiler,
## self-hosted) before launch. For dev/test it's fine if we cache aggressively and
## set a real User-Agent. https://operations.osmfoundation.org/policies/tiles/
const TILE_URL_TEMPLATE := "https://tile.openstreetmap.org/%d/%d/%d.png"
const USER_AGENT := "DrugWarsReUp/0.1-dev (https://github.com/; pre-alpha; contact: replace-before-launch)"

signal tile_ready(z: int, x: int, y: int, texture: Texture2D)
signal tile_failed(z: int, x: int, y: int, reason: String)

var _active: int = 0
var _queue: Array[Vector3i] = []  # (z, x, y)
var _in_flight: Dictionary = {}   # Vector3i → HTTPRequest

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tiles"))

## Request a tile. Emits tile_ready (or tile_failed) when available.
## If cached, emits synchronously on the next frame.
func request_tile(z: int, x: int, y: int) -> void:
	var n := Geo.world_tile_count(z)
	if x < 0 or x >= n or y < 0 or y >= n:
		tile_failed.emit(z, x, y, "out_of_bounds")
		return
	var key := Vector3i(z, x, y)
	if _in_flight.has(key):
		return  # already fetching
	var path := _cache_path(z, x, y)
	if FileAccess.file_exists(path):
		_emit_cached.call_deferred(z, x, y, path)
		return
	_queue.append(key)
	_pump()

func _emit_cached(z: int, x: int, y: int, path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		# Cache poisoned (truncated/corrupt). Re-fetch.
		DirAccess.remove_absolute(path)
		_queue.append(Vector3i(z, x, y))
		_pump()
		return
	tile_ready.emit(z, x, y, ImageTexture.create_from_image(img))

func _pump() -> void:
	while _active < MAX_PARALLEL and not _queue.is_empty():
		var key: Vector3i = _queue.pop_front()
		_start_fetch(key.x, key.y, key.z)  # x=z, y=x, z=y in Vector3i

func _start_fetch(z: int, x: int, y: int) -> void:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	var key := Vector3i(z, x, y)
	_in_flight[key] = req
	_active += 1
	req.request_completed.connect(_on_completed.bind(z, x, y, req))
	var url := TILE_URL_TEMPLATE % [z, x, y]
	var headers := PackedStringArray(["User-Agent: " + USER_AGENT])
	var err := req.request(url, headers)
	if err != OK:
		_finish_fetch(z, x, y, req)
		tile_failed.emit(z, x, y, "request_error_%d" % err)

func _on_completed(result: int, code: int, _hdr: PackedStringArray, body: PackedByteArray,
		z: int, x: int, y: int, req: HTTPRequest) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish_fetch(z, x, y, req)
		tile_failed.emit(z, x, y, "http_%d_result_%d" % [code, result])
		return
	var img := Image.new()
	if img.load_png_from_buffer(body) != OK:
		_finish_fetch(z, x, y, req)
		tile_failed.emit(z, x, y, "decode_error")
		return
	var path := _cache_path(z, x, y)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	_finish_fetch(z, x, y, req)
	tile_ready.emit(z, x, y, ImageTexture.create_from_image(img))

func _finish_fetch(z: int, x: int, y: int, req: HTTPRequest) -> void:
	_in_flight.erase(Vector3i(z, x, y))
	req.queue_free()
	_active -= 1
	_pump()

func _cache_path(z: int, x: int, y: int) -> String:
	return "user://tiles/%d/%d/%d.png" % [z, x, y]
