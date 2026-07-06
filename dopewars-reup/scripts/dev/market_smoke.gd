extends SceneTree

## Headless smoke for the multi-drug market.

var _market: Node

func _initialize() -> void:
	_market = preload("res://scripts/state/market.gd").new()
	root.add_child(_market)
	_run.call_deferred()

func _run() -> void:
	print("[market] price grid (city × drug, current day):")
	var cities := ["steubenville_oh", "wheeling_wv", "morgantown_wv", "pittsburgh_pa", "columbus_oh", "cleveland_oh"]
	var drugs := ["weed", "cocaine", "meth", "heroin", "fentanyl", "oxy"]
	var header := "%-18s" % "city"
	for d in drugs:
		header += " %8s" % d
	print("[market] " + header)
	for c in cities:
		var row := "%-18s" % c
		for d in drugs:
			row += " %8d" % _market.price_per_gram(c, d)
		print("[market] " + row)
	print("[market]")
	print("[market] supply/demand: buy 1000g fentanyl in Steubenville, observe price shift")
	var p0: int = _market.price_per_gram("steubenville_oh", "fentanyl")
	_market.record_buy("steubenville_oh", "fentanyl", 1000)
	var p1: int = _market.price_per_gram("steubenville_oh", "fentanyl")
	print("[market]   before: $%d → after: $%d (+%d, %.1f%%)" % [p0, p1, p1 - p0, 100.0 * (p1 - p0) / p0])
	print("[market]   pittsburgh_pa fentanyl: $%d (unaffected — local pressure)" % _market.price_per_gram("pittsburgh_pa", "fentanyl"))
	print("[market] done.")
	quit()
