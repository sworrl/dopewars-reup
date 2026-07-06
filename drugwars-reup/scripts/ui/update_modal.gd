extends CanvasLayer

## Branded "update available" modal. Two choices: UPDATE NOW, or LATER (postpone to next open).
## Matches the app's glass / ACCENT-red styling. While the new build downloads it swaps the buttons
## for a live progress bar. Driven by the `Updater` autoload; emits the player's choice back to it.

signal chose_update
signal chose_later

const ACCENT   := Color(0.92, 0.20, 0.25)
const PANEL_BG := Color(0.06, 0.06, 0.07, 0.96)
const TEXT     := Color(0.95, 0.95, 0.95)
const MUTED    := Color(0.70, 0.74, 0.82)
const FONT_DISPLAY := preload("res://assets/fonts/BigShouldersDisplay-Black.ttf")

var _bar: ProgressBar
var _status: Label
var _buttons: HBoxContainer

func _ready() -> void:
	layer = 90   # above toasts (80) and the HUD

## Build the card from a manifest dict: {version, notes, url, sha256}.
func setup(info: Dictionary) -> void:
	# Live viewport when running; fall back to the display size if called before we're in a tree.
	var view := get_viewport()
	var vp := view.get_visible_rect().size if view != null else Vector2(DisplayServer.window_get_size())

	# Dim scrim that also swallows taps on whatever's behind (must choose, can't tap past it).
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.62)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.anchor_right = 1.0
	scrim.anchor_bottom = 1.0
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_box())
	card.custom_minimum_size = Vector2(minf(vp.x - 80.0, 560.0), 0.0)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.anchor_left = 0.5
	card.anchor_top = 0.5
	card.anchor_right = 0.5
	card.anchor_bottom = 0.5
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	card.add_child(col)

	# Accent spine + title
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var spine := ColorRect.new()
	spine.color = ACCENT
	spine.custom_minimum_size = Vector2(6, 44)
	head.add_child(spine)
	var title := Label.new()
	title.text = "UPDATE AVAILABLE"
	title.add_theme_font_override("font", FONT_DISPLAY)
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", ACCENT)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)

	# Version line: current → new
	var ver := Label.new()
	ver.text = "v%s  →  v%s" % [Updater.current_version(), String(info.get("version", "?"))]
	ver.add_theme_font_size_override("font_size", 26)
	ver.add_theme_color_override("font_color", TEXT)
	col.add_child(ver)

	# Release notes (optional)
	var notes_text := String(info.get("notes", "")).strip_edges()
	if notes_text != "":
		var notes := Label.new()
		notes.text = notes_text
		notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notes.add_theme_font_size_override("font_size", 22)
		notes.add_theme_color_override("font_color", MUTED)
		col.add_child(notes)

	# Progress bar + status (hidden until "Update now")
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 14)
	_bar.add_theme_stylebox_override("background", _bar_bg())
	_bar.add_theme_stylebox_override("fill", _bar_fill())
	_bar.visible = false
	col.add_child(_bar)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", MUTED)
	_status.visible = false
	col.add_child(_status)

	# Buttons: UPDATE NOW (filled) / LATER (ghost)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(_buttons)

	var later := _ghost_button("Later")
	later.pressed.connect(func() -> void:
		chose_later.emit()
		queue_free()
	)
	_buttons.add_child(later)

	var now := _accent_button("Update now")
	now.pressed.connect(_on_update_pressed)
	_buttons.add_child(now)

	# Live-drive the bar from the updater during download.
	Updater.download_progress.connect(func(p: float) -> void:
		if is_instance_valid(_bar):
			_bar.value = p
	)
	Updater.download_failed.connect(func(reason: String) -> void:
		if is_instance_valid(_status):
			_status.add_theme_color_override("font_color", ACCENT)
			_status.text = reason + " — tap Update now to retry."
		if is_instance_valid(_buttons):
			_buttons.visible = true   # let them retry
	)

func _on_update_pressed() -> void:
	# Desktop just opens the release page; close the modal. Android starts a tracked download.
	chose_update.emit()
	if OS.get_name() != "Android":
		queue_free()
		return
	_buttons.visible = false
	_bar.visible = true
	_status.visible = true
	_status.add_theme_color_override("font_color", MUTED)
	_status.text = "Downloading the new build…"

# ---- styling helpers --------------------------------------------------------

func _card_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(22)
	sb.border_color = Color(1, 1, 1, 0.06)
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 24
	return sb

func _bar_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.10)
	sb.set_corner_radius_all(7)
	return sb

func _bar_fill() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT
	sb.set_corner_radius_all(7)
	return sb

func _accent_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = ACCENT
	normal.set_corner_radius_all(12)
	normal.set_content_margin_all(14)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", normal)
	return b

func _ghost_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", MUTED)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.06)
	normal.set_corner_radius_all(12)
	normal.set_content_margin_all(14)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", normal)
	return b
