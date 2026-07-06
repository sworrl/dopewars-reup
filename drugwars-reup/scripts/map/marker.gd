class_name MapMarker
extends Node2D

## Simple POI/player marker. Draws a colored disc with a label below.
## Position is set by MapView via add_marker(node, lat, lon).

@export var label_text: String = ""
@export var color: Color = Color(0.9, 0.2, 0.25)  # Re-Up red
@export var radius: float = 6.0
@export var outline_color: Color = Color(0.05, 0.05, 0.05)
@export var label_color: Color = Color(0.95, 0.95, 0.95)

func _draw() -> void:
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
