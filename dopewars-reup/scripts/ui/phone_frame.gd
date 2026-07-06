extends CanvasLayer

## Diegetic phone frame (autoload `PhoneFrame`). You're "playing on" your in-game phone, so the phone
## itself frames the whole game: a bezel whose bulk reflects the phone's tier (a cheap burner has a
## thick, cheap bezel; a flagship is thin and crisp), progressive screen cracks as it takes damage,
## and a red edge pulse when the battery is nearly dead. Drawn above the game, below toasts (80).
##
## Purely cosmetic and non-interactive (mouse ignored). Hidden when you have no phone — a new player
## with empty pockets sees the raw screen until they get a handset.

const MAX_CRACKS := 12

var _canvas: Control
var _cracks: Array = []          # cached crack polylines in normalized 0..1 space (stable per phone)
var _crack_seed_id := ""
var _pulse := 0.0

func _ready() -> void:
	layer = 70
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_frame)
	add_child(_canvas)
	PlayerState.phone_changed.connect(_refresh)
	get_viewport().size_changed.connect(func(): _canvas.queue_redraw())
	_refresh()

func _refresh() -> void:
	_canvas.visible = PlayerState.has_phone()
	_regen_cracks_if_needed()
	_canvas.queue_redraw()

func _process(dt: float) -> void:
	# Only spend a per-frame redraw when the battery is critically low (the pulsing red edge).
	if _canvas.visible and PlayerState.phone_battery() <= 15:
		_pulse = fmod(_pulse + dt, TAU)
		_canvas.queue_redraw()

## Crack geometry is fixed per phone (so it doesn't jitter); how MUCH of it shows scales with damage.
func _regen_cracks_if_needed() -> void:
	var pid := String(PlayerState.phone.get("id", ""))
	if pid == _crack_seed_id:
		return
	_crack_seed_id = pid
	_cracks.clear()
	if pid == "":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pid)
	var origin := Vector2(rng.randf_range(0.25, 0.75), rng.randf_range(0.3, 0.7))
	for i in range(MAX_CRACKS):
		var ang := rng.randf_range(0.0, TAU)
		var pts := PackedVector2Array([origin])
		var p := origin
		var steps := rng.randi_range(2, 4)
		for s in range(steps):
			ang += rng.randf_range(-0.6, 0.6)
			p += Vector2(cos(ang), sin(ang)) * rng.randf_range(0.05, 0.16)
			pts.append(p)
		_cracks.append(pts)

func _draw_frame() -> void:
	var sz := _canvas.size
	var tier := int(PlayerState.phone.get("tier", 0))

	# --- bezel: thicker + cheaper-looking at low tier, thin + crisp at high tier ---
	var cheapness := clampf(1.0 - float(tier) / 5.0, 0.0, 1.0)
	var thickness := 10.0 + 26.0 * cheapness
	var radius := 22.0 + 30.0 * (1.0 - cheapness)
	var bezel := StyleBoxFlat.new()
	bezel.bg_color = Color(0, 0, 0, 0)
	bezel.set_border_width_all(int(thickness))
	bezel.border_color = Color(0.02, 0.02, 0.03, 0.45 + 0.35 * cheapness)
	bezel.set_corner_radius_all(int(radius))
	_canvas.draw_style_box(bezel, Rect2(Vector2.ZERO, sz))

	# A cheap phone gets a little forehead notch/camera dot; a flagship stays clean.
	if cheapness > 0.4:
		_canvas.draw_circle(Vector2(sz.x * 0.5, thickness * 0.5), 3.0, Color(0.1, 0.1, 0.12, 0.7))

	# --- progressive cracks ---
	var damage := PlayerState.phone_damage()
	if damage >= 20 and not _cracks.is_empty():
		var shown := clampi(int(damage / 8), 0, _cracks.size())
		var a := clampf(0.12 + float(damage) / 180.0, 0.0, 0.6)
		for i in range(shown):
			var norm: PackedVector2Array = _cracks[i]
			var pts := PackedVector2Array()
			for n in norm:
				pts.append(Vector2(n.x * sz.x, n.y * sz.y))
			# dark under-stroke for depth, then a bright hairline
			_canvas.draw_polyline(pts, Color(0, 0, 0, a * 0.8), 2.5, true)
			_canvas.draw_polyline(pts, Color(0.9, 0.93, 1.0, a), 1.0, true)

	# --- critical-battery red edge pulse ---
	if PlayerState.phone_battery() <= 15:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(0, 0, 0, 0)
		glow.set_border_width_all(int(thickness + 6.0))
		var pa := 0.18 + 0.16 * (0.5 + 0.5 * sin(_pulse * 3.0))
		glow.border_color = Color(0.92, 0.16, 0.20, pa)
		glow.set_corner_radius_all(int(radius))
		_canvas.draw_style_box(glow, Rect2(Vector2.ZERO, sz))
