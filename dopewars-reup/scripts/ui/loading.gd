extends Control

## Branded animated loading screen (the real main_scene). Shows the red-route key art with a slow
## Ken Burns push, the title revealing, and a red pulse running UP the plotted route (which doubles
## as the loading indicator — the whole game is about plotting a trip). Then routes onward:
## boot_reveal decides new-player city-pick vs returning-player map.

const NEXT_SCENE := "res://scenes/boot.tscn"
const ART := "res://assets/sprites/ui/boot_art.png"
const MIN_SHOW_S := 2.6          # hold long enough to read as branded, not a flash
const ROUTE_X_FRAC := 0.51       # the red route line sits just right of center in the art

func _ready() -> void:
	var vp := get_viewport().get_visible_rect().size

	var bg := ColorRect.new()
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.03, 0.03, 0.04)
	add_child(bg)

	# Key art, cover-filled, with a slow zoom push from center.
	var art := TextureRect.new()
	if ResourceLoader.exists(ART):
		art.texture = load(ART)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.anchor_right = 1.0
	art.anchor_bottom = 1.0
	art.pivot_offset = vp * 0.5
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	art.scale = Vector2.ONE
	var zoom := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	zoom.tween_property(art, "scale", Vector2(1.10, 1.10), MIN_SHOW_S + 0.8)

	# Darken toward the bottom so the title reads over the busy grid.
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.anchor_right = 1.0
	scrim.anchor_bottom = 1.0
	scrim.color = Color(0.02, 0.02, 0.04, 0.38)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	# A short bright-red comet running UP the route line — the "loading" motion.
	var pulse := ColorRect.new()
	pulse.color = Color(1.0, 0.16, 0.20, 0.9)
	pulse.size = Vector2(7, 150)
	pulse.position = Vector2(vp.x * ROUTE_X_FRAC - 3.5, vp.y)
	pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pulse)
	var run := create_tween().set_loops()
	run.tween_property(pulse, "position:y", -160.0, 1.5).from(vp.y).set_trans(Tween.TRANS_SINE)
	run.tween_interval(0.35)

	# Title block, centered, revealing.
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.anchor_right = 1.0
	vb.anchor_bottom = 1.0
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vb)

	var display_font := load("res://assets/fonts/BigShouldersDisplay-Black.ttf")
	var t1 := Label.new()
	t1.text = "DOPE WARS"
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.add_theme_font_override("font", display_font)
	t1.add_theme_font_size_override("font_size", 110)
	t1.add_theme_color_override("font_color", Color(0.92, 0.20, 0.25))
	vb.add_child(t1)

	var t2 := Label.new()
	t2.text = "RE-UP EDITION"
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t2.add_theme_font_override("font", display_font)
	t2.add_theme_font_size_override("font_size", 42)
	t2.add_theme_color_override("font_color", Color(0.88, 0.88, 0.90))
	vb.add_child(t2)

	var tag := Label.new()
	tag.text = "plotting your block…"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 22)
	tag.add_theme_color_override("font_color", Color(0.62, 0.62, 0.66))
	vb.add_child(tag)

	# Reveal the title, then pulse the tagline while we hold.
	vb.modulate.a = 0.0
	vb.position.y = 24
	var intro := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT)
	intro.tween_property(vb, "modulate:a", 1.0, 0.7)
	intro.tween_property(vb, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_BACK)
	var breathe := create_tween().set_loops()
	breathe.tween_property(tag, "modulate:a", 0.35, 0.8).set_delay(0.7)
	breathe.tween_property(tag, "modulate:a", 1.0, 0.8)

	# Hand off after the minimum hold.
	get_tree().create_timer(MIN_SHOW_S).timeout.connect(_go)

func _go() -> void:
	get_tree().change_scene_to_file(NEXT_SCENE)
