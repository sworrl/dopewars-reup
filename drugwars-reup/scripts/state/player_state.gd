extends Node

## Autoload singleton: cash, inventory, position, current travel.
## v0.1 = local-only (saves to user://save.json). v0.2 = server-authoritative via Supabase Edge Functions.
##
## Naming: drug type ids match data/drugs.json (added in v0.2). For v0.1 only "weed" exists.

const SAVE_PATH := "user://save.json"
const STARTING_CASH := 2000
const CARRY_BASE_LB := 30      # base capacity on foot
const CARRY_PER_STR_MOD_LB := 10  # +10 lb per +1 STR mod
const CARRY_MIN_LB := 5        # floor: a very low-STR character can still carry a little (never 0/negative)

signal cash_changed(new_cash: int)
signal inventory_changed()
signal position_changed(lat: float, lon: float)
signal travel_started(travel: Travel)
signal travel_arrived(city_id: String)
signal travel_canceled()
signal busted_at_airport(city_id: String, items_seized: Dictionary, roll_text: String)
signal travel_arrived_clean(city_id: String, roll_text: String)   # passed TSA

var cash: int = STARTING_CASH
var inventory: Dictionary = {}        # drug_id → grams
var lat: float = 40.3698              # Steubenville
var lon: float = -80.6339
var current_city_id: String = "steubenville_oh"
var travel: Travel = null
# Personal vehicles the player owns, as Travel.Mode ints (bike/motorcycle/car). Empty = foot
# and paid services only; locked vehicle rows in the trip planner offer a marketplace link.
# Placeholder for the full "vehicles are characters" system (fuel/reg/stats) later.
var owned_vehicle_modes: Array = []
# Details per owned vehicle, keyed by String(mode_int) so it survives JSON round-trips:
# { "3": {"listing_id","name","trunk_lb","price"} }. The best trunk raises the hold cap.
var owned_vehicles: Dictionary = {}
# The player's current phone (RPG gear). Empty = no phone. Holds the model's static fields plus
# dynamic "battery" (0-100) and "os" ("stock"/"graphene"). See [[dopewars-phones-as-gear]].
var phone: Dictionary = {}

signal phone_changed()

# Trap houses keyed by city_id: {tier_id, name, storage_lb, slots, stash:{drug->grams},
# employees:[{id,name,push_per_day,skim,heat}], last_tick:unix}. Employees push stashed product
# while you're away. See [[dopewars-logistics]].
var trap_houses: Dictionary = {}

signal trap_houses_changed()

# Map intel the player has gathered, keyed by city_id: {t:unix_learned, danger, market, competition,
# acc}. A remembered, decaying, perception-blurred read of each city — never the raw truth. See Intel.
var intel: Dictionary = {}
signal intel_changed()

# Cosmetics — flair ONLY, no gameplay effect (no-pay-to-win). CRED is an earned currency; `store`
# items cost it, `supporter`/`award`/`earned` items are granted. equipped holds one active id per
# category. See Cosmetics; mirrors the server's cred/owned/equipped model for later sync.
var cred: int = 0
var owned_cosmetics: Array = []
var equipped: Dictionary = {}
signal cred_changed(new_cred: int)
signal cosmetics_changed()
# Set when a trip completes; the HUD reads it on _ready and shows a "while you were away"
# report. Transient (not persisted) — the completion happens on the same launch the HUD
# then reads it, so the live toast and this cold-open report never both fire.
var pending_arrival: Dictionary = {}

# Character (set during chargen; stays put after).
var handle: String = ""
var class_id: String = ""
# Stats: 1-15 scale, D&D 5e mod = floor((score-10)/2). Class-locked base + chargen allocation.
var stats: Dictionary = {"STR": 10, "DEX": 10, "CON": 10, "INT": 10, "WIS": 10, "CHA": 10}
# Perks: array of perk ids. Effects are aggregated and applied via effective_*() helpers.
var perks: Array = []
var _perk_effects_cache: Dictionary = {}     # rebuilt on perk change
var _perk_cache_dirty: bool = true

# XP and level — no cap. Class starting_xp determines starting level (0-3).
# Curve: 100 → L1, 500 → L2, then 100 * level^2.32 (hits 100/500 at L1/L2, then steepens).
# XP gain scales with level (small bonus); curve outpaces gain so leveling slows at high level.
var xp: int = 0

signal xp_changed(new_xp: int)
signal level_up(new_level: int)

func stat_mod(stat: String) -> int:
	var score := effective_stat(stat)
	return int(floor(float(score - 10) / 2.0))

func effective_stat(stat: String) -> int:
	# Base stat + perk stat_bonus.
	var base := int(stats.get(stat, 10))
	var eff := _ensure_perk_effects()
	var bonuses: Dictionary = eff.get("stat_bonus", {})
	return base + int(bonuses.get(stat, 0))

func level() -> int:
	# Highest n such that xp_for_level(n) <= xp. Walks up from 0 until threshold exceeds xp.
	var n := 0
	while xp >= xp_for_level(n + 1):
		n += 1
		if n > 999:                     # belt-and-suspenders
			break
	return n

static func xp_for_level_for_xp(target_xp: int) -> int:
	# What level a given XP value lands at. Static so chargen can preview class starting level.
	var n := 0
	while target_xp >= xp_for_level(n + 1):
		n += 1
		if n > 999:
			break
	return n

static func xp_for_level(n: int) -> int:
	# Total XP required to reach level n (cumulative, NOT per-level delta).
	# n=0 → 0 ;  n=1 → 100 ;  n=2 → 500 ;  n>=3 → 100 * n^2.32
	if n <= 0:
		return 0
	if n == 1:
		return 100
	if n == 2:
		return 500
	return int(round(100.0 * pow(float(n), 2.32)))

func xp_to_next_level() -> int:
	return xp_for_level(level() + 1) - xp

func xp_gain_multiplier() -> float:
	# XP gained from activities scales slowly with level. Levels 0-9 → 1.0-1.9x.
	# Level curve outpaces this, so each level still takes longer despite the bigger income.
	return 1.0 + 0.10 * float(level())

func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	var prev_level := level()
	var scaled := int(round(float(amount) * xp_gain_multiplier()))
	xp += scaled
	xp_changed.emit(xp)
	var new_level := level()
	if new_level > prev_level:
		var earned := 0
		for l in range(prev_level + 1, new_level + 1):
			level_up.emit(l)
			earned += 100 + 25 * l     # CRED is earned by playing — leveling grants flair currency
		cred += earned
		cred_changed.emit(cred)
	save_to_disk()

func add_perk(perk_id: String) -> void:
	if perk_id in perks:
		return
	perks.append(perk_id)
	_perk_cache_dirty = true
	save_to_disk()

func has_perk(perk_id: String) -> bool:
	return perk_id in perks

func _ensure_perk_effects() -> Dictionary:
	if _perk_cache_dirty:
		_perk_effects_cache = Perks.aggregate_effects(perks)
		_perk_cache_dirty = false
	return _perk_effects_cache

func perk_effect(key: String, default = null):
	return _ensure_perk_effects().get(key, default)

# ---- skill checks (the shared way stats affect outcomes) --------------------
# Every gameplay check — perception, stealth, negotiation, searches — routes through here so the
# Dice engine, ability modifiers, and perk advantage/disadvantage all apply consistently. Perks
# grant `skill_advantage`/`skill_disadvantage` naming a skill (e.g. Cold Read → "insight").

func _perk_grants(key: String, skill: String) -> bool:
	var v = perk_effect(key, null)
	if v == null:
		return false
	if v is Array:
		return skill in v
	return String(v) == skill

## Named skill check tied to an ability score. `extra_mod` folds in situational bonuses (heat, gear).
func skill_check(skill: String, ability: String, dc: int, extra_mod: int = 0, label: String = "") -> Dice.Result:
	var adv := Dice.NONE
	if _perk_grants("skill_advantage", skill):
		adv = Dice.ADVANTAGE
	elif _perk_grants("skill_disadvantage", skill):
		adv = Dice.DISADVANTAGE
	return Dice.check(stat_mod(ability) + extra_mod, dc, adv, label if label != "" else skill.capitalize())

## Perception (WIS) — noticing subtle tells: another operator's shady move, an ambush, thin intel.
func perception_check(dc: int, extra_mod: int = 0) -> Dice.Result:
	return skill_check("perception", "WIS", dc, extra_mod, "Perception")

## Stealth (DEX) — not being noticed while doing something illegal in the open.
func stealth_check(dc: int, extra_mod: int = 0) -> Dice.Result:
	return skill_check("stealth", "DEX", dc, extra_mod, "Stealth")

# ---- map intel (perception-gated, decaying) --------------------------------

## Read a city's streets and store a perceived intel snapshot. Being present is a strong read;
## WIS/perception sharpens it (a crit is near-perfect, a fumble a bad read); a smarter phone helps.
func gather_intel(city_id: String, present: bool = true) -> void:
	if city_id == "":
		return
	var r := perception_check(12)
	var quality := (0.55 if present else 0.30)   # you simply see more when you're standing there
	if r.crit_succeed:
		quality += 0.35
	elif r.success:
		quality += 0.03 * float(r.margin)
	elif r.crit_fail:
		quality -= 0.25
	else:
		quality += 0.02 * float(r.margin)          # margin is negative on a miss
	quality += 0.04 * float(int(phone.get("tier", 0)))   # smart phone pulls supplementary intel
	var snap := Intel.observe(city_id, clampf(quality, 0.1, 1.0))
	snap["t"] = Time.get_unix_time_from_system()
	intel[city_id] = snap
	intel_changed.emit()
	save_to_disk()

## Current perceived snapshot for a city with live (decayed) confidence, or {} if never gathered.
func intel_snapshot(city_id: String) -> Dictionary:
	if not intel.has(city_id):
		return {}
	var snap: Dictionary = intel[city_id]
	var conf := Intel.confidence(snap, float(snap.get("t", 0.0)), Time.get_unix_time_from_system())
	return {
		"danger": float(snap.get("danger", 0.0)),
		"market": float(snap.get("market", 0.0)),
		"competition": float(snap.get("competition", 0.0)),
		"confidence": conf,
	}

# ---- cosmetics (flair only, CRED-earned) -----------------------------------

func owns_cosmetic(id: String) -> bool:
	return id in owned_cosmetics

func equipped_in(category: String) -> String:
	return String(equipped.get(category, ""))

func add_cred(amount: int) -> void:
	if amount <= 0:
		return
	cred += amount
	cred_changed.emit(cred)
	save_to_disk()

## Grant an owned cosmetic (award/earned/supporter, or a completed purchase). Idempotent.
func grant_cosmetic(id: String) -> bool:
	if id == "" or Cosmetics.by_id(id).is_empty() or id in owned_cosmetics:
		return false
	owned_cosmetics.append(id)
	cosmetics_changed.emit()
	save_to_disk()
	return true

## Buy a store cosmetic with CRED. Only source=="store" items are purchasable — mirrors the server's
## buy_cosmetic block on non-store items, so money can never buy an advantage or a granted-only item.
func buy_cosmetic(id: String) -> Dictionary:
	var item := Cosmetics.by_id(id)
	if item.is_empty():
		return {"ok": false, "error": "no such item"}
	if not Cosmetics.is_purchasable(item):
		return {"ok": false, "error": "not for sale"}
	if id in owned_cosmetics:
		return {"ok": false, "error": "already owned"}
	var cost := int(item.get("cost", 0))
	if cred < cost:
		return {"ok": false, "error": "not enough CRED"}
	cred -= cost
	owned_cosmetics.append(id)
	cred_changed.emit(cred)
	cosmetics_changed.emit()
	save_to_disk()
	return {"ok": true}

func equip_cosmetic(id: String) -> bool:
	if not owns_cosmetic(id):
		return false
	var item := Cosmetics.by_id(id)
	if item.is_empty():
		return false
	equipped[item.category] = id
	cosmetics_changed.emit()
	save_to_disk()
	return true

func unequip_category(category: String) -> void:
	if equipped.has(category):
		equipped.erase(category)
		cosmetics_changed.emit()
		save_to_disk()

func _ready() -> void:
	load_from_disk()

func _process(_dt: float) -> void:
	if travel == null:
		return
	var now := Time.get_unix_time_from_system()
	var pos := travel.position(now)
	lat = pos.x
	lon = pos.y
	position_changed.emit(lat, lon)
	if travel.is_complete(now):
		_complete_travel()

func start_travel(route: Route, dest_city_id: String, mode: Travel.Mode,
		effective_duration_s: float, cost_dollars: int = 0) -> bool:
	if travel != null:
		push_warning("[player] already traveling; ignored")
		return false
	if cost_dollars > 0 and not change_cash(-cost_dollars):
		return false  # not enough cash; UI should have prevented this
	var now := Time.get_unix_time_from_system()
	travel = Travel.make(route, dest_city_id, mode, effective_duration_s, now, current_city_id)
	current_city_id = ""
	travel_started.emit(travel)
	save_to_disk()
	return true

func cancel_travel() -> void:
	if travel == null:
		return
	# Return to the city we departed from — otherwise the player is stranded "off-grid"
	# with no market access until they complete another full trip.
	var origin_id := travel.origin_city_id
	travel = null
	if origin_id != "":
		current_city_id = origin_id
		var c := Cities.by_id(origin_id)
		if not c.is_empty():
			lat = float(c.lat)
			lon = float(c.lon)
			position_changed.emit(lat, lon)
	travel_canceled.emit()
	save_to_disk()

func _complete_travel() -> void:
	var dest_id := travel.dest_city_id
	var arrived_via_plane := travel.mode == Travel.Mode.PLANE
	var dest_pos := travel.dest_latlon()
	lat = dest_pos.x
	lon = dest_pos.y
	current_city_id = dest_id
	travel = null
	position_changed.emit(lat, lon)

	# Arriving, you read the local scene — a fresh, present intel gather on the new city.
	gather_intel(dest_id, true)

	# A trip drains the phone battery.
	drain_phone()

	# Commercial flight drug screening — D&D-style stealth DC roll via the shared Dice engine.
	# DC scales with regional heat AND phone traceability (a tracked phone tips the cops off;
	# a burner or GraphineOS keeps you quieter). Player rolls d20 + DEX modifier.
	# Perks: tsa_check_advantage rolls 2d20 keep-higher.
	if arrived_via_plane and not inventory.is_empty():
		var heat := Drugs.region_heat(dest_id)
		var dc := 14 + int(heat / 20) + int(phone_trace() / 40)   # +0..+2 from a tracked phone
		var adv := Dice.ADVANTAGE if bool(perk_effect("tsa_check_advantage", false)) else Dice.NONE
		var r := Dice.check(stat_mod("DEX"), dc, adv, "TSA")
		var caught := not r.success
		var roll_text := r.text("PASSED", "BUSTED", "DEX")
		if caught:
			var seized := inventory.duplicate()
			inventory.clear()
			inventory_changed.emit()
			pending_arrival = {"kind": "busted", "city_id": dest_id, "seized": seized, "roll_text": roll_text}
			busted_at_airport.emit(dest_id, seized, roll_text)
			save_to_disk()
			return
		pending_arrival = {"kind": "clean", "city_id": dest_id, "roll_text": roll_text}
		travel_arrived_clean.emit(dest_id, roll_text)

	if pending_arrival.is_empty():
		pending_arrival = {"kind": "arrived", "city_id": dest_id}
	travel_arrived.emit(dest_id)
	save_to_disk()

func change_cash(delta: int) -> bool:
	var new_cash := cash + delta
	if new_cash < 0:
		return false
	cash = new_cash
	cash_changed.emit(cash)
	save_to_disk()
	return true

func grams_carried() -> int:
	var total := 0
	for v in inventory.values():
		total += int(v)
	return total

func pounds_carried() -> float:
	return grams_carried() / 453.592

func foot_capacity_lb() -> float:
	# What you can carry on your body: base + STR-modifier scaling + perk carry bonuses.
	var perk_bonus := float(perk_effect("carry_lb_bonus", 0.0))
	# Floor the innate (STR-derived) capacity so a low-STR build isn't stuck at 0/negative;
	# perks stack additively on top so they always add real value.
	var innate := maxf(float(CARRY_MIN_LB), float(CARRY_BASE_LB) + float(CARRY_PER_STR_MOD_LB) * stat_mod("STR"))
	return innate + perk_bonus

func vehicle_capacity_lb() -> float:
	# Best trunk among owned vehicles — a stash spot on wheels that raises your hold cap.
	var best := 0.0
	for v in owned_vehicles.values():
		best = maxf(best, float(v.get("trunk_lb", 0)))
	return best

func capacity_lb() -> float:
	# Total hold cap = what you can carry on foot PLUS your biggest vehicle trunk. This is the
	# accumulation ceiling; per-mode TRAVEL carry limits (a bus holds less than your car) are
	# checked separately at travel time.
	return foot_capacity_lb() + vehicle_capacity_lb()

func owns_vehicle_mode(mode: int) -> bool:
	return owned_vehicles.has(str(mode))

func vehicle_trunk_lb(mode: int) -> float:
	return float((owned_vehicles.get(str(mode), {}) as Dictionary).get("trunk_lb", 0))

## Buy a used vehicle listing for `mode`. Charges cash, records the vehicle, unlocks the mode.
func buy_vehicle(mode: int, listing: Dictionary) -> bool:
	var price := int(listing.get("price", 0))
	if not change_cash(-price):
		return false
	owned_vehicles[str(mode)] = {
		"listing_id": listing.get("id", ""),
		"name": listing.get("name", ""),
		"trunk_lb": int(listing.get("trunk_lb", 0)),
		"price": price,
	}
	if not (mode in owned_vehicle_modes):
		owned_vehicle_modes.append(mode)
	inventory_changed.emit()   # HUD re-reads capacity from this
	save_to_disk()
	return true

# ---- phone (RPG gear) ---------------------------------------------------

func has_phone() -> bool:
	return not phone.is_empty()

func phone_battery() -> int:
	return int(phone.get("battery", 0))

## Effective police traceability: the hardened OS drops it hard; a dead phone can't be tracked at all.
func phone_trace() -> int:
	if not has_phone() or phone_battery() <= 0:
		return 0
	if phone.get("os", "stock") == "graphene":
		return Phones.graphene_trace()
	return int(phone.get("trace", 0))

func phone_can_flash_graphene() -> bool:
	return has_phone() and bool(phone.get("graphene_supported", false)) \
		and phone.get("os", "stock") != "graphene"

## Buy a phone listing (replaces the current phone; no trade-in in v1).
func buy_phone(listing: Dictionary) -> bool:
	var price := int(listing.get("price", 0))
	if not change_cash(-price):
		return false
	phone = listing.duplicate(true)
	phone["battery"] = 100
	phone["os"] = "stock"
	phone_changed.emit()
	save_to_disk()
	return true

## Charge the phone. kind "wired" (fast) or "wireless" (convenient, some phones can't).
func charge_phone(kind: String) -> bool:
	if not has_phone():
		return false
	var amt := int(phone.get("charge_wired", 0)) if kind == "wired" else int(phone.get("charge_wireless", 0))
	if amt <= 0:
		return false   # e.g. wireless on a phone that doesn't support it
	phone["battery"] = mini(100, phone_battery() + amt)
	phone_changed.emit()
	save_to_disk()
	return true

func flash_graphene() -> bool:
	if not phone_can_flash_graphene():
		return false
	phone["os"] = "graphene"
	phone_changed.emit()
	save_to_disk()
	return true

## Battery cost of a trip. Called on travel completion.
func drain_phone() -> void:
	if not has_phone():
		return
	phone["battery"] = maxi(0, phone_battery() - int(phone.get("drain_per_trip", 0)))
	phone_changed.emit()

# ---- trap houses --------------------------------------------------------

func has_trap_house(city_id: String) -> bool:
	return trap_houses.has(city_id)

func setup_trap_house(city_id: String, tier: Dictionary) -> bool:
	if has_trap_house(city_id):
		return false
	if not change_cash(-int(tier.get("setup_cost", 0))):
		return false
	trap_houses[city_id] = {
		"tier_id": tier.get("id", ""),
		"name": tier.get("name", "Trap house"),
		"storage_lb": int(tier.get("storage_lb", 0)),
		"slots": int(tier.get("slots", 1)),
		"stash": {},
		"employees": [],
		"last_tick": Time.get_unix_time_from_system(),
	}
	trap_houses_changed.emit()
	save_to_disk()
	return true

func house_stash_grams(city_id: String) -> int:
	var h: Dictionary = trap_houses.get(city_id, {})
	var total := 0
	for v in (h.get("stash", {}) as Dictionary).values():
		total += int(v)
	return total

func house_stash_free_lb(city_id: String) -> float:
	var h: Dictionary = trap_houses.get(city_id, {})
	return float(h.get("storage_lb", 0)) - house_stash_grams(city_id) / 453.592

## Move product from your carry into the house stash (frees your carry, bounded by storage).
func stash_to_house(city_id: String, drug_id: String, grams: int) -> bool:
	if not has_trap_house(city_id) or grams <= 0:
		return false
	if int(inventory.get(drug_id, 0)) < grams:
		return false
	if grams / 453.592 > house_stash_free_lb(city_id):
		return false
	inventory[drug_id] = int(inventory.get(drug_id, 0)) - grams
	if inventory[drug_id] <= 0:
		inventory.erase(drug_id)
	var stash: Dictionary = trap_houses[city_id]["stash"]
	stash[drug_id] = int(stash.get(drug_id, 0)) + grams
	inventory_changed.emit()
	trap_houses_changed.emit()
	save_to_disk()
	return true

## Pull product back out of the house onto your person (bounded by your carry capacity).
func take_from_house(city_id: String, drug_id: String, grams: int) -> bool:
	if not has_trap_house(city_id) or grams <= 0:
		return false
	var stash: Dictionary = trap_houses[city_id]["stash"]
	if int(stash.get(drug_id, 0)) < grams:
		return false
	if not can_carry_more(grams):
		return false
	stash[drug_id] = int(stash.get(drug_id, 0)) - grams
	if stash[drug_id] <= 0:
		stash.erase(drug_id)
	inventory[drug_id] = int(inventory.get(drug_id, 0)) + grams
	inventory_changed.emit()
	trap_houses_changed.emit()
	save_to_disk()
	return true

func hire_employee(city_id: String, emp: Dictionary) -> bool:
	if not has_trap_house(city_id):
		return false
	var h: Dictionary = trap_houses[city_id]
	if (h["employees"] as Array).size() >= int(h.get("slots", 1)):
		return false
	if not change_cash(-int(emp.get("hire_cost", 0))):
		return false
	h["employees"].append({
		"id": emp.get("id", ""), "name": emp.get("name", "Worker"),
		"push_per_day": int(emp.get("push_per_day", 0)),
		"skim": float(emp.get("skim", 0.1)), "heat": float(emp.get("heat", 0.1)),
	})
	trap_houses_changed.emit()
	save_to_disk()
	return true

## Settle passive sales since the last tick: employees push stashed product at the local price,
## pocketing their skim. Returns a report Dictionary for the UI. Called when the house is opened.
func accrue_trap_house(city_id: String) -> Dictionary:
	if not has_trap_house(city_id):
		return {}
	var h: Dictionary = trap_houses[city_id]
	var emps: Array = h.get("employees", [])
	var now := Time.get_unix_time_from_system()
	var elapsed_days: float = (now - float(h.get("last_tick", now))) / Trap.DAY_SECONDS
	h["last_tick"] = now
	if emps.is_empty() or elapsed_days <= 0.0:
		return {"sold": 0, "net": 0, "days": elapsed_days}
	var push_budget := 0.0
	var skim_sum := 0.0
	for e in emps:
		push_budget += float(e.get("push_per_day", 0)) * elapsed_days
		skim_sum += float(e.get("skim", 0.1))
	var avg_skim: float = skim_sum / float(emps.size())
	# Sell highest-value grams first.
	var stash: Dictionary = h["stash"]
	var priced: Array = []
	for drug_id in stash.keys():
		priced.append([drug_id, Market.price_per_gram(city_id, drug_id)])
	priced.sort_custom(func(a, b): return a[1] > b[1])
	var sold_grams := 0
	var gross := 0
	for entry in priced:
		if push_budget <= 0.0:
			break
		var drug_id: String = entry[0]
		var price: int = entry[1]
		var avail := int(stash.get(drug_id, 0))
		var take := int(min(float(avail), push_budget))
		if take <= 0:
			continue
		stash[drug_id] = avail - take
		if stash[drug_id] <= 0:
			stash.erase(drug_id)
		sold_grams += take
		gross += take * price
		push_budget -= float(take)
	var net := int(round(float(gross) * (1.0 - avg_skim)))
	if net > 0:
		cash += net
		cash_changed.emit(cash)
	trap_houses_changed.emit()
	save_to_disk()
	return {"sold": sold_grams, "gross": gross, "net": net, "skim": int(gross - net), "days": elapsed_days}

func can_carry_more(grams: int) -> bool:
	return (grams_carried() + grams) / 453.592 <= capacity_lb()

func adjust_inventory(drug_id: String, delta_grams: int) -> bool:
	var have := int(inventory.get(drug_id, 0))
	var new_amt := have + delta_grams
	if new_amt < 0:
		return false
	if delta_grams > 0 and not can_carry_more(delta_grams):
		return false
	if new_amt == 0:
		inventory.erase(drug_id)
	else:
		inventory[drug_id] = new_amt
	inventory_changed.emit()
	save_to_disk()
	return true

func to_dict() -> Dictionary:
	return {
		"cash": cash,
		"inventory": inventory,
		"lat": lat, "lon": lon,
		"current_city_id": current_city_id,
		"handle": handle,
		"class_id": class_id,
		"stats": stats,
		"perks": perks,
		"xp": xp,
		"owned_vehicle_modes": owned_vehicle_modes,
		"owned_vehicles": owned_vehicles,
		"phone": phone,
		"trap_houses": trap_houses,
		"intel": intel,
		"cred": cred,
		"owned_cosmetics": owned_cosmetics,
		"equipped": equipped,
		"travel": travel.to_dict() if travel != null else null,
	}

func load_dict(d: Dictionary) -> void:
	cash = int(d.get("cash", STARTING_CASH))
	inventory = d.get("inventory", {})
	lat = float(d.get("lat", 40.3698))
	lon = float(d.get("lon", -80.6339))
	current_city_id = d.get("current_city_id", "steubenville_oh")
	handle = d.get("handle", "")
	class_id = d.get("class_id", "")
	stats = d.get("stats", {"STR": 10, "DEX": 10, "CON": 10, "INT": 10, "WIS": 10, "CHA": 10})
	perks = d.get("perks", [])
	xp = int(d.get("xp", 0))
	owned_vehicles = d.get("owned_vehicles", {})
	phone = d.get("phone", {})
	trap_houses = d.get("trap_houses", {})
	intel = d.get("intel", {})
	cred = int(d.get("cred", 0))
	owned_cosmetics = d.get("owned_cosmetics", [])
	equipped = d.get("equipped", {})
	# Derive the modes list from owned_vehicles so the ints stay clean (JSON round-trips numbers
	# as floats). Fall back to any legacy owned_vehicle_modes for older saves without owned_vehicles.
	if owned_vehicles.is_empty():
		owned_vehicle_modes = d.get("owned_vehicle_modes", [])
	else:
		owned_vehicle_modes = []
		for k in owned_vehicles.keys():
			owned_vehicle_modes.append(int(k))
	_perk_cache_dirty = true
	var t = d.get("travel", null)
	travel = Travel.from_dict(t) if typeof(t) == TYPE_DICTIONARY else null

func save_to_disk() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[player] cannot write " + SAVE_PATH)
		return
	f.store_string(JSON.stringify(to_dict(), "  "))

func load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if typeof(doc) != TYPE_DICTIONARY:
		return
	load_dict(doc)
	# If a travel was in progress and clock is past ETA, complete on next _process tick.
	# (Handled naturally by travel.is_complete check.)
