class_name ThemeFactory
extends RefCounted

## Builds a Theme resource with 3D-look button styles (gradient bg, drop shadow,
## bevel highlight) tinted by an accent color. Per-class palettes live in CLASS_ACCENTS;
## fall back to RE_UP_RED for the global default.
##
## Press/release animation is wired separately by Anim — this just supplies the visuals.

const RE_UP_RED := Color(0.92, 0.20, 0.25)

## Per-class accent colors. Used to tint StyleBox bevels, label headers, focus rings.
const CLASS_ACCENTS := {
	"hustler":    Color(0.95, 0.45, 0.20),  # corner-orange
	"cook":       Color(0.30, 0.80, 0.65),  # bio-lab teal
	"muscle":     Color(0.85, 0.20, 0.20),  # bouncer red
	"hacker":     Color(0.30, 0.95, 0.55),  # phosphor green
	"ex_cop":     Color(0.30, 0.55, 0.95),  # police blue
	"trust_fund": Color(0.95, 0.85, 0.30),  # gold
	"veteran":    Color(0.55, 0.70, 0.40),  # OD-green
	"junkie":     Color(0.65, 0.45, 0.85),  # purple haze
	"pharm_tech": Color(0.85, 0.85, 0.95),  # off-white pharma
	"biker":      Color(0.85, 0.75, 0.20),  # patch yellow
}

static func accent_for_class(class_id: String) -> Color:
	return CLASS_ACCENTS.get(class_id, RE_UP_RED)

## Build a fresh "liquid glass" Theme. accent tints the rim / focus / press glow.
## Surfaces are translucent frosted panels with a bright rim highlight and soft shadow;
## the real backdrop blur is supplied by the glass shader (see glass.gdshader / Glass helper),
## while these styleboxes give the tint, rim and rounding that read as glass even without it.
static func make(accent: Color) -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 32

	# Button states — frosted glass with an accent-tinted press glow.
	var btn_normal   := _make_glass_box(Color(0.62, 0.68, 0.82, 0.12), Color(1, 1, 1, 0.22), 20)
	var btn_hover    := _make_glass_box(Color(0.70, 0.76, 0.90, 0.18), Color(1, 1, 1, 0.32), 20)
	var btn_pressed  := _make_glass_box(Color(accent.r, accent.g, accent.b, 0.30), Color(accent.r, accent.g, accent.b, 0.75), 20)
	var btn_focus    := _make_glass_box(Color(0.62, 0.68, 0.82, 0.14), Color(accent.r, accent.g, accent.b, 0.85), 20, 3)
	var btn_disabled := _make_glass_box(Color(0.30, 0.30, 0.34, 0.10), Color(1, 1, 1, 0.08), 20)

	theme.set_stylebox("normal",   "Button", btn_normal)
	theme.set_stylebox("hover",    "Button", btn_hover)
	theme.set_stylebox("pressed",  "Button", btn_pressed)
	theme.set_stylebox("focus",    "Button", btn_focus)
	theme.set_stylebox("disabled", "Button", btn_disabled)
	theme.set_color("font_color",          "Button", Color(0.96, 0.97, 1.0))
	theme.set_color("font_hover_color",    "Button", Color.WHITE)
	theme.set_color("font_pressed_color",  "Button", accent.lightened(0.4))
	theme.set_color("font_disabled_color", "Button", Color(0.55, 0.55, 0.60, 0.6))
	theme.set_constant("h_separation", "Button", 12)

	# PanelContainer — frosted glass surface.
	theme.set_stylebox("panel", "PanelContainer",
		_make_glass_box(Color(0.55, 0.60, 0.74, 0.10), Color(1, 1, 1, 0.18), 24))

	# LineEdit — recessed glass slab.
	theme.set_stylebox("normal", "LineEdit",
		_make_glass_box(Color(0.10, 0.11, 0.16, 0.35), Color(1, 1, 1, 0.14), 16))
	theme.set_stylebox("focus", "LineEdit",
		_make_glass_box(Color(0.12, 0.13, 0.18, 0.40), Color(accent.r, accent.g, accent.b, 0.8), 16, 3))
	theme.set_color("font_color",            "LineEdit", Color(0.96, 0.97, 1.0))
	theme.set_color("font_placeholder_color","LineEdit", Color(0.70, 0.72, 0.80, 0.6))
	theme.set_color("caret_color",           "LineEdit", accent)
	theme.set_color("selection_color",       "LineEdit", Color(accent.r, accent.g, accent.b, 0.35))

	return theme

## Frosted-glass StyleBoxFlat: translucent fill, bright rim, big rounding, soft drop shadow.
static func _make_glass_box(fill: Color, rim: Color, radius: int, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = rim
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 22
	sb.content_margin_top = 16
	sb.content_margin_right = 22
	sb.content_margin_bottom = 16
	return sb

