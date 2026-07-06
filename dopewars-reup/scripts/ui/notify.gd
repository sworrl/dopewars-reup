extends CanvasLayer

## Branded in-app notification system: glass toasts that slide down from the top and auto-dismiss.
## One place for every alert so they all look the same (proximity warnings, busts, deals, level-ups).
## Autoloaded, so any script can call `Notify.alert("…")` from anywhere.
##
## System-level Android notifications (for when the app is backgrounded) go through
## AndroidNotify.push() separately; this is the in-app layer that shows while you're playing.

const ACCENT := Color(0.92, 0.20, 0.25)
const KIND_COLOR := {
	"info": Color(0.55, 0.62, 0.78),
	"alert": Color(0.92, 0.20, 0.25),
	"warn": Color(0.90, 0.68, 0.20),
	"good": Color(0.35, 0.75, 0.45),
}

var _stack: VBoxContainer

func _ready() -> void:
	layer = 80   # above the HUD (10) but below nothing that matters
	_stack = VBoxContainer.new()
	_stack.add_theme_constant_override("separation", 10)
	_stack.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_stack.anchor_right = 1.0
	_stack.offset_top = 18
	_stack.offset_left = 18
	_stack.offset_right = -18
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)

func info(text: String, title: String = "") -> void: _toast(text, title, "info")
func alert(text: String, title: String = "") -> void: _toast(text, title, "alert")
func warn(text: String, title: String = "") -> void: _toast(text, title, "warn")
func good(text: String, title: String = "") -> void: _toast(text, title, "good")

## icon: optional res:// path to a small texture shown on the left.
func _toast(text: String, title: String, kind: String, hold: float = 3.6, icon: String = "") -> void:
	var accent: Color = KIND_COLOR.get(kind, ACCENT)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _toast_box(accent))
	panel.modulate.a = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	panel.add_child(hb)

	# Accent spine so alerts read at a glance without color-only reliance.
	var spine := ColorRect.new()
	spine.color = accent
	spine.custom_minimum_size = Vector2(6, 0)
	hb.add_child(spine)

	if icon != "" and ResourceLoader.exists(icon):
		var tex := TextureRect.new()
		tex.texture = load(icon)
		tex.custom_minimum_size = Vector2(64, 64)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hb.add_child(tex)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.add_theme_constant_override("margin_top", 8)
	hb.add_child(col)

	if title != "":
		var t := Label.new()
		t.text = title
		t.add_theme_font_size_override("font_size", 26)
		t.add_theme_color_override("font_color", accent)
		col.add_child(t)

	var body := Label.new()
	body.text = text
	body.add_theme_font_size_override("font_size", 24)
	body.add_theme_color_override("font_color", Color(0.92, 0.92, 0.94))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)

	_stack.add_child(panel)

	# Slide + fade in from above, hold, fade out, free.
	panel.position.y -= 20
	var tin := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT)
	tin.tween_property(panel, "modulate:a", 1.0, 0.28)
	tin.tween_property(panel, "position:y", panel.position.y + 20, 0.28).set_trans(Tween.TRANS_BACK)

	var out := create_tween()
	out.tween_interval(hold)
	out.tween_property(panel, "modulate:a", 0.0, 0.5)
	out.tween_callback(panel.queue_free)

	# Tap to dismiss early.
	panel.gui_input.connect(func(ev):
		if ev is InputEventScreenTouch and ev.pressed:
			panel.queue_free())

func _toast_box(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.10, 0.90)
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(1)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.45)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 10
	sb.anti_aliasing = true
	sb.content_margin_left = 0
	sb.content_margin_right = 16
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb
