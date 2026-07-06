extends Node

## Per-city, per-drug supply/demand market. Autoload singleton.
##
## Pricing model (v0.1-content, single-player local):
##   price = base_price × region_demand_multiplier × daily_volatility_factor × supply_pressure
##
## - base_price: from drugs.json
## - region_demand_multiplier: from region_drug_profiles.json
## - daily_volatility_factor: deterministic-per-(city,drug,day) random walk in [1-vol, 1+vol]
## - supply_pressure: starts at 1.0, drifts based on player buys/sells in that city,
##   slowly mean-reverts toward 1.0 over real-world hours.
##
## v0.2 = server-authoritative: all transactions go through Edge Functions; pressure
## is shared across all players in that city.

signal price_changed(city_id: String, drug_id: String, new_price: int)

const SAVE_PATH := "user://market_pressure.json"
const PRESSURE_MIN := 0.40
const PRESSURE_MAX := 2.50
const REVERSION_HALF_LIFE_SEC := 6 * 3600.0   # ~6 real hours
# How much one gram moves the pressure (compounded multiplicative).
const BUY_PRESSURE_PER_GRAM := 0.0008          # buying pushes price up
const SELL_PRESSURE_PER_GRAM := 0.0006         # selling pushes price down (slightly less)

var _pressure: Dictionary = {}     # "city_id|drug_id" → {factor: float, last_unix: float}

func _ready() -> void:
	_load_pressure()

func price_per_gram(city_id: String, drug_id: String) -> int:
	var drug := Drugs.by_id(drug_id)
	if drug.is_empty():
		return 0
	var base: float = float(drug.base_price_per_g)
	var demand: float = Drugs.region_demand(city_id, drug_id)
	var vol: float = float(drug.get("volatility", 0.2))
	var day := _current_day_index(Time.get_unix_time_from_system())
	var seed := "%s|%s|%d" % [city_id, drug_id, day]
	var rnd := _seed_to_unit(seed.hash())   # [0,1]
	var vol_factor: float = 1.0 + (rnd * 2.0 - 1.0) * vol
	var pressure := _current_pressure(city_id, drug_id)
	var p: float = base * demand * vol_factor * pressure
	return int(round(p))

func record_buy(city_id: String, drug_id: String, grams: int) -> void:
	_apply_pressure(city_id, drug_id, 1.0 + BUY_PRESSURE_PER_GRAM * grams)

func record_sell(city_id: String, drug_id: String, grams: int) -> void:
	_apply_pressure(city_id, drug_id, 1.0 / (1.0 + SELL_PRESSURE_PER_GRAM * grams))

func _apply_pressure(city_id: String, drug_id: String, mul: float) -> void:
	var k := "%s|%s" % [city_id, drug_id]
	var rec: Dictionary = _pressure.get(k, {"factor": 1.0, "last_unix": Time.get_unix_time_from_system()})
	# Apply pending mean-reversion before applying new shock.
	rec = _decay_to_now(rec)
	rec.factor = clampf(float(rec.factor) * mul, PRESSURE_MIN, PRESSURE_MAX)
	rec.last_unix = Time.get_unix_time_from_system()
	_pressure[k] = rec
	_save_pressure()
	price_changed.emit(city_id, drug_id, price_per_gram(city_id, drug_id))

func _current_pressure(city_id: String, drug_id: String) -> float:
	var k := "%s|%s" % [city_id, drug_id]
	if not _pressure.has(k):
		return 1.0
	var rec: Dictionary = _pressure[k]
	var decayed := _decay_to_now(rec)
	return float(decayed.factor)

func _decay_to_now(rec: Dictionary) -> Dictionary:
	var now := Time.get_unix_time_from_system()
	var dt: float = now - float(rec.get("last_unix", now))
	if dt <= 0.0:
		return rec
	# Exponential decay toward 1.0 with REVERSION_HALF_LIFE_SEC half-life.
	var k := pow(0.5, dt / REVERSION_HALF_LIFE_SEC)
	var f := float(rec.factor)
	rec.factor = 1.0 + (f - 1.0) * k
	rec.last_unix = now
	return rec

func _current_day_index(unix_seconds: float) -> int:
	return int(unix_seconds / 86400.0)

func _seed_to_unit(h: int) -> float:
	var u: int = (h % 0x7fffffff + 0x7fffffff) % 0x7fffffff
	return float(u) / 2147483647.0

func _save_pressure() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_pressure))

func _load_pressure() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if typeof(doc) == TYPE_DICTIONARY:
		_pressure = doc
