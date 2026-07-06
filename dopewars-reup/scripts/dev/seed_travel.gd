extends SceneTree

## Dev-only: fetch a real OSRM route Steubenville→Pittsburgh and write
## a save.json with that walk in progress. Then `godot --path …` will boot
## with the trip already going so we can screenshot the route + banner.

func _init() -> void:
	var router := preload("res://scripts/routing/router.gd").new()
	root.add_child(router)
	_run.call_deferred(router)

func _run(router: Node) -> void:
	print("[seed] requesting driving route Steubenville→Pittsburgh…")
	# Steubenville → Cleveland: ~100 highway miles, gives a polyline visible at z=9.
	var route: Route = await router.fetch("driving", 40.3698, -80.6339, 41.4993, -81.6944)
	if route == null:
		printerr("[seed] route fetch failed")
		quit(1)
		return
	# 12h walk so the trip is in mid-progress when the game boots.
	var miles: float = route.total_distance_m / 1609.344
	var walk_seconds: float = (miles / 3.0) * 3600.0
	var now := Time.get_unix_time_from_system()
	var save_dict: Dictionary = {
		"cash": 2000,
		"inventory": {},
		"lat": 40.3698,
		"lon": -80.6339,
		"current_city_id": "",
		"travel": {
			"mode": int(Travel.Mode.WALK),
			"dest_city_id": "cleveland_oh",
			"started_at": now - walk_seconds * 0.35,    # 35% along
			"eta_at": now + walk_seconds * 0.65,
			"route": route.to_dict(),
		},
	}
	var path := "user://save.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(save_dict, "  "))
	print("[seed] wrote %s (route %.1f mi, %d polyline pts)" % [
		ProjectSettings.globalize_path(path), miles, route.polyline_latlon.size()])
	quit()
