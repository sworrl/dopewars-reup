class_name Geo
extends RefCounted

## Web Mercator (EPSG:3857) coordinate math for OSM-style 256px tiles.
## Reference: https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames

const TILE_SIZE := 256
const MAX_LAT := 85.0511287798  # Web Mercator clamp; lat outside this distorts to infinity
const MIN_LAT := -85.0511287798

static func clamp_lat(lat: float) -> float:
	return clampf(lat, MIN_LAT, MAX_LAT)

## Lat/lon → integer tile (x, y) at zoom z. Used to pick which PNG to fetch.
static func latlon_to_tile(lat: float, lon: float, z: int) -> Vector2i:
	var n := 1 << z
	var lat_r := deg_to_rad(clamp_lat(lat))
	var x := int(floorf((lon + 180.0) / 360.0 * n))
	var y := int(floorf((1.0 - asinh(tan(lat_r)) / PI) / 2.0 * n))
	return Vector2i(x, y)

## Lat/lon → fractional world-pixel coords at zoom z (y flipped to match screen).
## At zoom z, world is `(256 * 2^z)` pixels wide. Used to position markers.
static func latlon_to_world_px(lat: float, lon: float, z: int) -> Vector2:
	var n := float(1 << z)
	var lat_r := deg_to_rad(clamp_lat(lat))
	var x := (lon + 180.0) / 360.0 * n * TILE_SIZE
	var y := (1.0 - asinh(tan(lat_r)) / PI) / 2.0 * n * TILE_SIZE
	return Vector2(x, y)

## Inverse: world pixel coords at zoom z → lat/lon. Used when player drags map.
static func world_px_to_latlon(world_px: Vector2, z: int) -> Vector2:
	var n := float(1 << z)
	var lon := world_px.x / (n * TILE_SIZE) * 360.0 - 180.0
	var lat_n := PI * (1.0 - 2.0 * world_px.y / (n * TILE_SIZE))
	var lat := rad_to_deg(atan(sinh(lat_n)))
	return Vector2(lat, lon)

## Great-circle distance (Haversine), miles. For travel-time calculation.
static func miles_between(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	const R_MI := 3958.7613
	var p1 := deg_to_rad(lat1)
	var p2 := deg_to_rad(lat2)
	var dp := deg_to_rad(lat2 - lat1)
	var dl := deg_to_rad(lon2 - lon1)
	var a := sin(dp / 2.0) ** 2 + cos(p1) * cos(p2) * sin(dl / 2.0) ** 2
	return R_MI * 2.0 * atan2(sqrt(a), sqrt(1.0 - a))

## Number of tiles wide/tall the world is at zoom z.
static func world_tile_count(z: int) -> int:
	return 1 << z
