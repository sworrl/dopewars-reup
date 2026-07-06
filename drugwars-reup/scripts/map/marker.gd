class_name MapMarker
extends Node2D

## Simple POI/player marker. Draws a colored disc with a label below.
## Position is set by MapView via add_marker(node, lat, lon).

@export var label_text: String = ""
@export var color: Color = Color(0.9, 0.2, 0.25)  # Re-Up red
@export var radius: float = 6.0
@export var outline_color: Color = Color(0.05, 0.05, 0.05)
@export var label_color: Color = Color(0.95, 0.95, 0.95)

# Intel overlay state, set by MapView.set_overlay(). intel_dim == Intel.Dim.NONE (0) hides the halo.
var intel_dim: int = 0
var intel_value: float = 0.0
var intel_conf: float = 0.0
var intel_color: Color = Color.WHITE

## Set the perceived-intel halo for this city. Confidence sets how solid + how colored (vs grey and
## uncertain) it reads, so low-confidence intel looks faint and ambiguous — the info-asymmetry pillar.
func set_intel(dim: int, value: float, conf: float, col: Color) -> void:
	intel_dim = dim
	intel_value = value
	intel_conf = conf
	intel_color = col
	queue_redraw()

func _draw() -> void:
	# Subtle glow behind the marker, if an overlay dimension is active and we have intel here.
	if intel_dim != 0 and intel_conf > 0.02:
		var col := Color(0.6, 0.6, 0.62).lerp(intel_color, intel_conf)   # grey ⇄ colored by certainty
		var rings := 4
		for i in range(rings):
			var t := float(i) / float(rings - 1)                          # 0 outer … 1 inner
			var rr := (radius + 4.0) + (10.0 + 16.0 * intel_value) * (1.0 - t)
			var a := (0.05 + 0.22 * intel_value) * intel_conf * (0.4 + 0.6 * t)
			draw_circle(Vector2.ZERO, rr, Color(col.r, col.g, col.b, a))

	draw_circle(Vector2.ZERO, radius + 1.0, outline_color)
	draw_circle(Vector2.ZERO, radius, color)
	if label_text != "":
		var font := ThemeDB.fallback_font
		var size := 12
		var dim := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
		var pos := Vector2(-dim.x * 0.5, radius + size + 2.0)
		draw_string(font, pos + Vector2(1, 1), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			size, Color(0, 0, 0, 0.85))
		draw_string(font, pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, label_color)
