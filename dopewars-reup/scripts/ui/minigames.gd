extends CanvasLayer

## Interactive VS mini-games — you PLAY the fight, you don't just watch a dice roll. Each game returns
## a performance score 0..1; the win threshold is set by the opponent's power vs yours (your weapons +
## stats make it easier). Touch-first, quick, adversarial. Used by street encounters and challenges.
##
## Usage:  var mg = preload("res://scripts/ui/minigames.gd").new(); add_child(mg)
##         var r = await mg.run("random", my_power, opp_power); mg.queue_free()
##         # r = {won: bool, score: float, game: String}

const GAMES := ["shootout", "fistfight", "standoff", "getaway"]
const ACCENT := Color(0.92, 0.20, 0.25)
const FONT_DISPLAY := preload("res://assets/fonts/BigShouldersDisplay-Black.ttf")

var _root: Control
var _vp: Vector2

func _ready() -> void:
	layer = 95   # above everything

func run(game: String, my_power: int, opp_power: int) -> Dictionary:
	if game == "random":
		game = GAMES[randi() % GAMES.size()]
	_vp = get_viewport().get_visible_rect().size
	_root = ColorRect.new()
	_root.color = Color(0.02, 0.03, 0.05, 0.96)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	add_child(_root)

	# Your edge lowers the score you need to win (weapons + stats matter).
	var edge := my_power - opp_power
	var win_at := clampf(0.55 - edge * 0.03, 0.2, 0.85)

	await _intro(game)
	var score := 0.0
	match game:
		"shootout": score = await _shootout()
		"fistfight": score = await _fistfight()
		"standoff": score = await _standoff()
		_: score = await _getaway()
	var won := score >= win_at
	await _outro(won, score)
	return {"won": won, "score": score, "game": game}

# ---- shared bits ----------------------------------------------------------

func _label(text: String, size: int, col: Color, y: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.anchor_right = 1.0
	l.position.y = y
	_root.add_child(l)
	return l

func _intro(game: String) -> void:
	var titles := {
		"shootout": ["SHOOTOUT", "Tap the targets before they vanish."],
		"fistfight": ["FISTFIGHT", "Tap each strike in the ring, in time."],
		"standoff": ["STANDOFF", "Draw at the sweet spot — not too early, not too late."],
		"getaway": ["GETAWAY", "Tap when the dot is in the zone."],
	}
	var t: Array = titles.get(game, ["FIGHT", "Go."])
	var big := _label(t[0], 56, ACCENT, _vp.y * 0.35)
	big.add_theme_font_override("font", FONT_DISPLAY)
	var sub := _label(t[1], 26, Color(0.85, 0.85, 0.9), _vp.y * 0.35 + 80)
	await get_tree().create_timer(1.4).timeout
	big.queue_free()
	sub.queue_free()

func _outro(won: bool, score: float) -> void:
	# a quick full-screen flash sells the result
	var flash := ColorRect.new()
	flash.color = Color(0.35, 0.8, 0.45, 0.0) if won else Color(0.9, 0.2, 0.25, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(flash)
	var ft := flash.create_tween()
	ft.tween_property(flash, "color:a", 0.35, 0.08)
	ft.tween_property(flash, "color:a", 0.0, 0.5)
	if won:
		Rumble.win()
	else:
		Rumble.loss()
	var big := _label("YOU WON" if won else "YOU LOST", 60, Color(0.35, 0.8, 0.45) if won else ACCENT, _vp.y * 0.4)
	big.add_theme_font_override("font", FONT_DISPLAY)
	_label("performance %d%%" % int(score * 100), 24, Color(0.8, 0.8, 0.85), _vp.y * 0.4 + 90)
	await get_tree().create_timer(1.3).timeout

func _hud(text: String) -> Label:
	return _label(text, 30, Color(0.9, 0.9, 0.95), 40)

# ---- shootout: aim / reaction ---------------------------------------------

func _shootout() -> float:
	var hud := _hud("")
	var hits := 0
	var spawned := 0
	var elapsed := 0.0
	while elapsed < 8.0:
		spawned += 1
		var t := _spawn_target()
		var alive: Array = [true]
		t.pressed.connect(func():
			if alive[0]:
				alive[0] = false
				hits += 1
				Rumble.hit()
				t.queue_free())
		hud.text = "Hits: %d" % hits
		var wait := randf_range(0.55, 0.95)
		await get_tree().create_timer(wait).timeout
		elapsed += wait
		if is_instance_valid(t):
			t.queue_free()
	hud.queue_free()
	return clampf(float(hits) / maxf(float(spawned), 1.0), 0.0, 1.0)

func _spawn_target() -> Button:
	var b := Button.new()
	var r := 120.0
	b.custom_minimum_size = Vector2(r, r)
	b.size = Vector2(r, r)
	b.position = Vector2(randf_range(40, _vp.x - r - 40), randf_range(180, _vp.y - r - 120))
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT
	sb.set_corner_radius_all(int(r / 2))
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	_root.add_child(b)
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(0.3, 0.3), 0.9).from(Vector2.ONE)
	return b

# ---- fistfight: rhythm / QTE ----------------------------------------------

func _fistfight() -> float:
	var hud := _hud("")
	var landed := 0
	var rounds := 6
	for i in range(rounds):
		hud.text = "Round %d/%d — landed %d" % [i + 1, rounds, landed]
		var hit: Array = [false]
		var b := Button.new()
		b.text = "HIT"
		b.add_theme_font_size_override("font_size", 40)
		b.custom_minimum_size = Vector2(200, 200)
		b.position = Vector2(randf_range(60, _vp.x - 260), randf_range(220, _vp.y - 320))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.2, 0.22, 0.3)
		sb.border_color = ACCENT
		sb.set_border_width_all(6)
		sb.set_corner_radius_all(20)
		b.add_theme_stylebox_override("normal", sb)
		b.pressed.connect(func():
			if not hit[0]:
				hit[0] = true
				Rumble.hit())
		_root.add_child(b)
		# shrinking ring = the timing window
		var ring := b.create_tween()
		ring.tween_property(b, "scale", Vector2(0.5, 0.5), 0.85).from(Vector2(1.4, 1.4))
		await get_tree().create_timer(0.9).timeout
		if hit[0]:
			landed += 1
		if is_instance_valid(b):
			b.queue_free()
		await get_tree().create_timer(0.2).timeout
	hud.queue_free()
	return float(landed) / float(rounds)

# ---- standoff: timing / nerve ---------------------------------------------

func _standoff() -> float:
	var hud := _hud("Draw in the green.")
	var good := 0
	var rounds := 3
	for i in range(rounds):
		var track := ColorRect.new()
		track.color = Color(1, 1, 1, 0.1)
		track.size = Vector2(_vp.x - 120, 60)
		track.position = Vector2(60, _vp.y * 0.5)
		_root.add_child(track)
		# sweet-spot zone near the far end
		var zone := ColorRect.new()
		zone.color = Color(0.35, 0.8, 0.45, 0.5)
		zone.size = Vector2(track.size.x * 0.18, 60)
		zone.position = Vector2(track.position.x + track.size.x * 0.74, track.position.y)
		_root.add_child(zone)
		var marker := ColorRect.new()
		marker.color = ACCENT
		marker.size = Vector2(14, 80)
		marker.position = Vector2(track.position.x, track.position.y - 10)
		_root.add_child(marker)
		var tapped: Array = [-1.0]
		var btn := _fullscreen_tap(func(): if tapped[0] < 0: tapped[0] = marker.position.x)
		var tw := marker.create_tween()
		tw.tween_property(marker, "position:x", track.position.x + track.size.x - 14, 1.1)
		await tw.finished
		btn.queue_free()
		var mx: float = tapped[0] if tapped[0] >= 0 else marker.position.x
		if mx >= zone.position.x and mx <= zone.position.x + zone.size.x:
			good += 1
			Rumble.hit()
			hud.text = "Clean draw!"
		else:
			hud.text = "Off."
		track.queue_free(); zone.queue_free(); marker.queue_free()
		await get_tree().create_timer(0.5).timeout
	hud.queue_free()
	return float(good) / float(rounds)

# ---- getaway: tracking ----------------------------------------------------

func _getaway() -> float:
	var hud := _hud("Tap when the dot is in the zone.")
	var hits := 0
	var rounds := 5
	for i in range(rounds):
		var zone := ColorRect.new()
		zone.color = Color(0.35, 0.8, 0.45, 0.35)
		zone.size = Vector2(160, 160)
		zone.position = Vector2(_vp.x * 0.5 - 80, _vp.y * 0.45 - 80)
		_root.add_child(zone)
		var dot := ColorRect.new()
		dot.color = ACCENT
		dot.size = Vector2(60, 60)
		dot.position = Vector2(60, _vp.y * 0.45 - 30 + randf_range(-40, 40))
		_root.add_child(dot)
		var tapped_in: Array = [false]
		var btn := _fullscreen_tap(func():
			var c := dot.position.x + 30
			if c >= zone.position.x and c <= zone.position.x + zone.size.x and not tapped_in[0]:
				tapped_in[0] = true
				Rumble.hit())
		var tw := dot.create_tween()
		tw.tween_property(dot, "position:x", _vp.x - 120, randf_range(0.9, 1.4))
		await tw.finished
		btn.queue_free()
		if tapped_in[0]:
			hits += 1
		hud.text = "%d/%d" % [hits, i + 1]
		zone.queue_free(); dot.queue_free()
		await get_tree().create_timer(0.35).timeout
	hud.queue_free()
	return float(hits) / float(rounds)

func _fullscreen_tap(cb: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.anchor_right = 1.0
	b.anchor_bottom = 1.0
	b.pressed.connect(cb)
	_root.add_child(b)
	return b
