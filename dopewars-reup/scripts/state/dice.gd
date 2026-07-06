class_name Dice

## Reusable D&D 5e / BG3-style d20 check engine. One place for every skill/save check so busts,
## perception, haggling and searches all roll and read the same way. Pure and static — no state.
##
## A check is:  d20 (optionally with advantage/disadvantage) + modifier  vs  DC.
## Natural 1 always fails and natural 20 always succeeds (5e crit rule), regardless of the modifier.
##
## Advantage (adv = +1) rolls 2d20 and keeps the higher; disadvantage (adv = -1) keeps the lower.
## Perks and situational bonuses feed in as `modifier`; environmental danger raises `dc`.

const ADVANTAGE := 1
const NONE := 0
const DISADVANTAGE := -1

## The outcome of one check. Transient (never saved) — carries everything a caller/UI needs.
class Result extends RefCounted:
	var d20: int            # the die actually used (after advantage/disadvantage)
	var d20a: int           # the two raw dice (d20b == d20a when there's no adv/disadv)
	var d20b: int
	var modifier: int
	var dc: int
	var total: int          # d20 + modifier
	var adv: int            # ADVANTAGE / NONE / DISADVANTAGE
	var label: String
	var success: bool
	var crit_fail: bool     # natural 1
	var crit_succeed: bool  # natural 20

	## Human-readable roll line, e.g. "Perception: d20(14) +3 WIS = 17 vs DC 15 → SPOTTED!".
	## Callers pass their own verbs so a bust reads "BUSTED"/"PASSED", a spot reads "SPOTTED"/"missed".
	func text(pass_word := "SUCCESS", fail_word := "FAIL", mod_name := "") -> String:
		var adv_str := ""
		if adv == ADVANTAGE:
			adv_str = " adv(%d,%d)" % [d20a, d20b]
		elif adv == DISADVANTAGE:
			adv_str = " dis(%d,%d)" % [d20a, d20b]
		var mod_str := "%+d" % modifier
		if mod_name != "":
			mod_str += " " + mod_name
		var bang := "!" if crit_fail or crit_succeed else ""
		return "%s: d20(%d)%s %s = %d vs DC %d → %s%s" % [
			label if label != "" else "Check", d20, adv_str, mod_str, total, dc,
			pass_word if success else fail_word, bang]

## Roll a raw d20 with optional advantage/disadvantage. Returns [used, a, b].
static func roll_d20(adv := NONE) -> Array:
	var a := randi_range(1, 20)
	var b := randi_range(1, 20)
	var used := a
	if adv == ADVANTAGE:
		used = maxi(a, b)
	elif adv == DISADVANTAGE:
		used = mini(a, b)
	return [used, a, b]

## Run a full check: d20 + modifier vs dc. `adv` is ADVANTAGE / NONE / DISADVANTAGE.
static func check(modifier: int, dc: int, adv := NONE, label := "") -> Result:
	var dice := roll_d20(adv)
	var r := Result.new()
	r.d20 = dice[0]
	r.d20a = dice[1]
	r.d20b = dice[2]
	r.modifier = modifier
	r.dc = dc
	r.adv = adv
	r.label = label
	r.total = r.d20 + modifier
	r.crit_fail = r.d20 == 1
	r.crit_succeed = r.d20 == 20
	# Nat 1 fails no matter what; nat 20 succeeds no matter what; otherwise compare to the DC.
	r.success = r.crit_succeed or (not r.crit_fail and r.total >= dc)
	return r

## Convenience: does a check pass? (when you don't need the breakdown).
static func passes(modifier: int, dc: int, adv := NONE) -> bool:
	return check(modifier, dc, adv).success
