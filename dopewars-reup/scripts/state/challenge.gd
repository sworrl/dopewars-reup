class_name Challenge
extends RefCounted

## Adversarial challenge resolver — the fair, server-adjudicable core under fights/standoffs/chases.
## Two sides contest as an opposed d20 best-of-3, each adding their "power" (stats + best weapon's
## threat). The margin says how decisive it was (drives the loser's injury + the stakes). This handles
## NPC fights and async player-vs-player (both offline). Real-time VS mini-games (reflex games when
## both players are online) layer on top of this same outcome model.

class Outcome extends RefCounted:
	var winner: int = 0     # 1 = side A, -1 = side B, 0 = draw
	var a_wins: int = 0
	var b_wins: int = 0
	var margin: int = 0     # a_wins - b_wins (−3..3); |margin| = how decisive
	var log: Array = []     # per-round lines for the UI

	func summary(a_name := "You", b_name := "Rival") -> String:
		if winner > 0:   return "%s win %d–%d." % [a_name, a_wins, b_wins]
		if winner < 0:   return "%s win %d–%d." % [b_name, b_wins, a_wins]
		return "A draw, %d–%d." % [a_wins, b_wins]

static func _roll(power: int) -> int:
	return Dice.roll_d20()[0] + power

## Resolve a contest. Best-of-3 opposed rolls; higher total takes the round.
static func fight(a_power: int, b_power: int, a_name := "You", b_name := "Rival") -> Outcome:
	var o := Outcome.new()
	for i in range(3):
		var ta := _roll(a_power)
		var tb := _roll(b_power)
		if ta > tb:
			o.a_wins += 1
		elif tb > ta:
			o.b_wins += 1
		o.log.append("Round %d — %s %d vs %s %d" % [i + 1, a_name, ta, b_name, tb])
	o.margin = o.a_wins - o.b_wins
	o.winner = signi(o.margin)
	return o
