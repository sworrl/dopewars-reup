extends SceneTree

## Headless smoke test for OSRM integration.
## Run: godot --headless --path dopewars-reup --script scripts/dev/route_smoke.gd

func _init() -> void:
	# Manually init Router (we're not booting the main scene tree; autoloads aren't applied to --script).
	var router := preload("res://scripts/routing/router.gd").new()
	root.add_child(router)
	_run.call_deferred(router)

func _run(router: Node) -> void:
	await _print_trip("Steubenville→Pittsburgh (no plane: STB has no airport)",
		router, 40.3698, -80.6339, 40.4406, -79.9959, false, true)
	await _print_trip("Pittsburgh→Cleveland (plane available)",
		router, 40.4406, -79.9959, 41.4993, -81.6944, true, true)
	print("[smoke] done.")
	quit()

func _print_trip(title: String, router: Node, lat1: float, lon1: float, lat2: float, lon2: float,
		origin_airport: bool, dest_airport: bool) -> void:
	print("[smoke] %s:" % title)
	var options: Array = await TripPlanner.plan(router, lat1, lon1, lat2, lon2,
		origin_airport, dest_airport)
	for opt in options:
		var line: String
		if opt.available:
			var miles: float = opt.route.total_distance_m / 1609.344
			line = "%-28s %5.1f mi · %-8s · $%d" % [
				opt.label, miles, Travel.format_remaining(opt.eta_s), opt.cost_dollars]
		else:
			line = "%-28s — %s" % [opt.label, opt.unavailable_reason]
		print("[smoke]   " + line)
