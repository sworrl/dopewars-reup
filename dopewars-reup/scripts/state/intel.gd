class_name Intel

## Map intel model — the info-asymmetry pillar made visible. Each city has three hidden "true"
## dimensions (danger / market / competition). The player never sees truth directly: they see a
## PERCEIVED snapshot they gathered, blurred by how well they read the scene (a WIS/perception roll)
## and decaying in confidence over time. Old intel goes fuzzy; you only sharpen it by being there.
##
## True values are all normalized 0..1. Pure/static — the player's gathered snapshots live in
## PlayerState.intel (persisted) so they survive between sessions like real remembered knowledge.

enum Dim { NONE, DANGER, MARKET, COMPETITION }

const HALF_LIFE_S := 3.0 * 86400.0   # gathered intel's confidence halves every ~3 real days
const MAX_NOISE := 0.35              # a totally cold read can be this far off the truth

## The three subtle overlay colors (danger red, market green, competition amber).
static func dim_color(dim: int) -> Color:
	match dim:
		Dim.DANGER:      return Color(0.92, 0.22, 0.26)
		Dim.MARKET:      return Color(0.35, 0.78, 0.46)
		Dim.COMPETITION: return Color(0.93, 0.68, 0.22)
		_:               return Color(0.6, 0.6, 0.6)

static func dim_name(dim: int) -> String:
	match dim:
		Dim.DANGER:      return "Danger"
		Dim.MARKET:      return "Market"
		Dim.COMPETITION: return "Competition"
		_:               return "Off"

## The hidden truth for a city: {danger, market, competition} each 0..1. Deterministic from data.
static func true_values(city_id: String) -> Dictionary:
	# Danger — cop/rival heat, straight off the regional profile.
	var danger := clampf(float(Drugs.region_heat(city_id)) / 100.0, 0.0, 1.0)

	# Market — how good this city is to move product: average demand across the catalog, normalized
	# from the ~0.6..1.5 multiplier range into 0..1.
	var sum := 0.0
	var count := 0
	for d in Drugs.all():
		sum += Drugs.region_demand(city_id, String(d.get("id", "")))
		count += 1
	var avg_demand := (sum / float(count)) if count > 0 else 1.0
	var market := clampf((avg_demand - 0.6) / (1.5 - 0.6), 0.0, 1.0)

	# Competition — rival operator density. No live rivals yet, so derive a stable value: bigger
	# markets draw more players, plus a deterministic per-city jitter so towns aren't uniform.
	var pop := float(Cities.by_id(city_id).get("population", 20000))
	var pop_norm := clampf((log(pop) - log(8000.0)) / (log(400000.0) - log(8000.0)), 0.0, 1.0)
	var jitter := float(hash(city_id) % 1000) / 1000.0
	var competition := clampf(0.6 * pop_norm + 0.4 * jitter, 0.0, 1.0)

	return {"danger": danger, "market": market, "competition": competition}

## Take a perceived reading of a city at `quality` 0..1 (1 = perfect). Returns the noisy snapshot the
## player will remember: each dimension nudged off truth by up to MAX_NOISE * (1 - quality).
static func observe(city_id: String, quality: float) -> Dictionary:
	var t := true_values(city_id)
	var sigma := MAX_NOISE * (1.0 - clampf(quality, 0.0, 1.0))
	var snap := {}
	for k in ["danger", "market", "competition"]:
		var noisy: float = float(t[k]) + (randfn(0.0, sigma) if sigma > 0.0 else 0.0)
		snap[k] = clampf(noisy, 0.0, 1.0)
	snap["acc"] = clampf(quality, 0.0, 1.0)   # accuracy at gather time (seeds confidence)
	return snap

## Current confidence in a stored snapshot: gather accuracy decayed by elapsed time. 0..1.
static func confidence(snap: Dictionary, learned_at: float, now: float) -> float:
	var age := maxf(0.0, now - learned_at)
	var decay := pow(0.5, age / HALF_LIFE_S)
	return clampf(float(snap.get("acc", 0.5)) * decay, 0.0, 1.0)
