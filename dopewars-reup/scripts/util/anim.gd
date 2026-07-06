extends Node

## UI animation helpers. Autoload singleton: `Anim.fade_in(node)`, etc.
##
## All animations target the highest available refresh rate (vsync=mailbox in
## project.godot, max_fps=0). Tweens are time-based, so they stay smooth at any
## display rate from 60 to 240 Hz.
##
## Reduced-motion respect: set _reduced_motion = true to collapse durations toward 0.

var _reduced_motion: bool = false

func set_reduced_motion(on: bool) -> void:
	_reduced_motion = on

func _dur(seconds: float) -> float:
	return 0.001 if _reduced_motion else seconds

# ---- generic ---------------------------------------------------------------

func fade_in(node: CanvasItem, duration: float = 0.25) -> Tween:
	node.modulate.a = 0.0
	var t := node.create_tween()
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "modulate:a", 1.0, _dur(duration))
	return t

func fade_out(node: CanvasItem, duration: float = 0.18) -> Tween:
	var t := node.create_tween()
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(node, "modulate:a", 0.0, _dur(duration))
	return t

func slide_in_from_bottom(node: Control, distance: float = 64.0, duration: float = 0.32) -> Tween:
	# A Container drives its children's positions; tweening `position` here fights the
	# layout and strands the node (it never gets re-laid-out). Fade instead.
	if node.get_parent() is Container:
		return fade_in(node, duration)
	var dest := node.position
	node.position = dest + Vector2(0, distance)
	node.modulate.a = 0.0
	var t := node.create_tween().set_parallel(true)
	t.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "position", dest, _dur(duration))
	t.tween_property(node, "modulate:a", 1.0, _dur(duration * 0.85))
	return t

func slide_in_from_right(node: Control, distance: float = 80.0, duration: float = 0.30) -> Tween:
	# See slide_in_from_bottom: container children can't have `position` tweened.
	if node.get_parent() is Container:
		return fade_in(node, duration)
	var dest := node.position
	node.position = dest + Vector2(distance, 0)
	node.modulate.a = 0.0
	var t := node.create_tween().set_parallel(true)
	t.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "position", dest, _dur(duration))
	t.tween_property(node, "modulate:a", 1.0, _dur(duration * 0.85))
	return t

func pop_in(node: Control, duration: float = 0.30) -> Tween:
	node.scale = Vector2(0.85, 0.85)
	node.modulate.a = 0.0
	var pivot := node.size * 0.5
	node.pivot_offset = pivot
	var t := node.create_tween().set_parallel(true)
	t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", Vector2.ONE, _dur(duration))
	t.tween_property(node, "modulate:a", 1.0, _dur(duration * 0.7))
	return t

func tap_press(node: Control, duration: float = 0.10) -> Tween:
	# Two-stage: press squashes (sells "you pushed it down"); release springs back
	# overshooting slightly (sells "it rebounded") with a subtle accent flash on the snap.
	var pivot := node.size * 0.5
	node.pivot_offset = pivot
	var t := node.create_tween()
	# PRESS — squash quickly, slight darken via modulate to sell "depressed".
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_parallel(true)
	t.tween_property(node, "scale", Vector2(0.92, 0.92), _dur(duration))
	t.tween_property(node, "modulate", Color(0.85, 0.85, 0.85, 1.0), _dur(duration))
	t.chain().set_parallel(true).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# RELEASE — spring back past 1.0 and settle, modulate flashes brighter then back.
	t.tween_property(node, "scale", Vector2.ONE, _dur(duration * 2.0))
	t.tween_property(node, "modulate", Color(1.10, 1.10, 1.10, 1.0), _dur(duration * 1.2))
	t.chain().tween_property(node, "modulate", Color(1, 1, 1, 1.0), _dur(0.18))
	return t

func release_pulse(node: Control, accent: Color = Color(0.92, 0.20, 0.25), duration: float = 0.30) -> Tween:
	# Quick accent-color flash + scale lift — used on confirmation actions (Begin, GO).
	var t := node.create_tween().set_parallel(true)
	t.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "modulate", Color(accent.r * 1.3, accent.g * 1.3, accent.b * 1.3, 1.0), _dur(duration * 0.4))
	t.chain().tween_property(node, "modulate", Color(1, 1, 1, 1), _dur(duration * 0.6))
	return t

func shake(node: Control, intensity: float = 8.0, duration: float = 0.30) -> Tween:
	var origin := node.position
	var t := node.create_tween()
	var steps := 6
	for i in steps:
		var dx := intensity * (1.0 if i % 2 == 0 else -1.0) * (1.0 - float(i) / steps)
		t.tween_property(node, "position", origin + Vector2(dx, 0), _dur(duration / steps))
	t.tween_property(node, "position", origin, _dur(0.05))
	return t

func color_flash(node: CanvasItem, color: Color, hold: float = 0.10) -> Tween:
	var orig := node.modulate
	var t := node.create_tween()
	t.tween_property(node, "modulate", color, _dur(0.06))
	t.tween_interval(_dur(hold))
	t.tween_property(node, "modulate", orig, _dur(0.18))
	return t

# ---- helpers --------------------------------------------------------------

## Hook every Button under `root` to animate on press. One-shot — call after the
## subtree is fully built. Skips buttons already wired (looks for a meta tag).
func wire_button_haptics(root: Node) -> void:
	for child in root.get_children():
		if child is Button and not child.has_meta("_anim_wired"):
			(child as Button).set_meta("_anim_wired", true)
			(child as Button).pressed.connect(tap_press.bind(child))
		wire_button_haptics(child)
