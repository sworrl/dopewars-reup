extends CanvasLayer

## Programmatic HUD for v0.1: top status banner, contextual action button, travel/market modals.
## Built in code (no .tscn) to keep early scaffolding light. Migrate to a proper scene file
## once the layout stops churning.

signal market_requested()
signal cancel_travel_requested()
signal zoom_toggle_requested()
signal intel_overlay_requested()

const PANEL_BG := Color(0.05, 0.05, 0.05, 0.78)
const TEXT     := Color(0.95, 0.95, 0.95)
const ACCENT   := Color(0.92, 0.20, 0.25)

## Branded display face (Big Shoulders Display Black, OFL) for titles/wordmark.
const FONT_DISPLAY := preload("res://assets/fonts/BigShouldersDisplay-Black.ttf")

## How much product each hired-service mode lets you travel with (lb). Foot uses the player's
## body capacity; owned vehicles use their trunk. A bus/plane holds little because you're
## exposed to search and can't stuff a brick under the seat.
const SERVICE_CARRY_LB := {
	Travel.Mode.BUS: 70.0,
	Travel.Mode.RIDESHARE: 140.0,
	Travel.Mode.PLANE: 60.0,
}

var _top_panel: PanelContainer
var _status_label: Label
var _ticker_timer: Timer

var _action_btn: Button
var _action_glass: ColorRect
var _arrival_label: Label   # transient toast

func _ready() -> void:
	layer = 10
	Glass.ensure_backbuffer(self)   # lets the frosted-glass shader read the map behind the UI
	_build_top_panel()
	_build_action_button()
	_build_phone_button()
	_build_zoom_button()
	_build_intel_button()
	_build_arrival_toast()
	# Subtle entrance for the HUD on scene change.
	Anim.slide_in_from_bottom(_top_panel, 24.0, 0.35)
	_ticker_timer = Timer.new()
	_ticker_timer.wait_time = 1.0
	_ticker_timer.autostart = true
	_ticker_timer.timeout.connect(_refresh)
	add_child(_ticker_timer)
	PlayerState.cash_changed.connect(func(_v): _refresh())
	PlayerState.inventory_changed.connect(_refresh)
	PlayerState.position_changed.connect(func(_a, _b): _refresh())
	PlayerState.travel_started.connect(func(_t): _refresh())
	PlayerState.travel_canceled.connect(_refresh)
	PlayerState.travel_arrived.connect(_on_arrived)
	PlayerState.busted_at_airport.connect(_on_busted)
	PlayerState.travel_arrived_clean.connect(_on_clean_arrival)
	_refresh()
	# A trip that finished while the app was closed completes before this HUD exists,
	# so its live toast is lost. Surface it now as a "while you were away" report.
	if not PlayerState.pending_arrival.is_empty():
		_show_arrival_report(PlayerState.pending_arrival)
		PlayerState.pending_arrival = {}

# ---- top panel ----------------------------------------------------------

func _build_top_panel() -> void:
	# Frosted-glass backdrop that blurs the map beneath the status banner.
	var glass := Glass.background(Color(0.09, 0.11, 0.17, 0.55), 0.0, 4.0)
	glass.set_anchors_preset(Control.PRESET_TOP_WIDE)
	glass.offset_top = 0
	glass.offset_bottom = 200
	add_child(glass)

	_top_panel = PanelContainer.new()
	_top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_panel.offset_top = 0
	_top_panel.offset_bottom = 200
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)             # transparent — the glass shows through
	sb.border_width_bottom = 1
	sb.border_color = Color(1, 1, 1, 0.20)      # thin rim highlight along the bottom edge
	_top_panel.add_theme_stylebox_override("panel", sb)
	add_child(_top_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_top_panel.add_child(v)
	v.offset_left = 28
	v.offset_top = 28
	v.offset_right = -28
	v.offset_bottom = -28

	var title := Label.new()
	title.text = "DOPE WARS: RE-UP"
	title.add_theme_font_override("font", FONT_DISPLAY)
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", ACCENT)
	v.add_child(title)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 26)
	_status_label.add_theme_color_override("font_color", TEXT)
	v.add_child(_status_label)

# ---- action button ------------------------------------------------------

func _build_action_button() -> void:
	_action_glass = Glass.background(Color(0.55, 0.60, 0.75, 0.14), 28.0, 4.0)
	_action_glass.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_action_glass.offset_left = 28
	_action_glass.offset_top = -130
	_action_glass.offset_right = -28
	_action_glass.offset_bottom = -28
	_action_glass.visible = false
	add_child(_action_glass)

	_action_btn = Button.new()
	_action_btn.theme = ThemeFactory.make(ACCENT)   # frosted-glass button styling
	_action_btn.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_action_btn.offset_left = 28
	_action_btn.offset_top = -130
	_action_btn.offset_right = -28
	_action_btn.offset_bottom = -28
	_action_btn.text = ""
	_action_btn.visible = false
	_action_btn.add_theme_font_size_override("font_size", 36)
	_action_btn.pressed.connect(_on_action_pressed)
	_action_btn.pressed.connect(Anim.tap_press.bind(_action_btn))
	add_child(_action_btn)

func _on_action_pressed() -> void:
	if PlayerState.travel != null:
		cancel_travel_requested.emit()
	else:
		market_requested.emit()

# ---- zoom / view toggle -------------------------------------------------

var _zoom_btn: Button

func _build_zoom_button() -> void:
	_zoom_btn = Button.new()
	_zoom_btn.theme = ThemeFactory.make(ACCENT)
	_zoom_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_zoom_btn.offset_left = 20
	_zoom_btn.offset_right = 250
	_zoom_btn.offset_top = 210
	_zoom_btn.offset_bottom = 300
	_zoom_btn.add_theme_font_size_override("font_size", 24)
	_zoom_btn.pressed.connect(func(): zoom_toggle_requested.emit())
	_zoom_btn.pressed.connect(Anim.tap_press.bind(_zoom_btn))
	add_child(_zoom_btn)
	set_view_mode("town")

## Called by world_root when the map view changes. Button shows what tapping will DO.
func set_view_mode(mode: String) -> void:
	if not is_instance_valid(_zoom_btn):
		return
	_zoom_btn.text = "Region ⤢" if mode == "town" else "My town ⤡"

# ---- intel overlay toggle -----------------------------------------------

var _intel_btn: Button

func _build_intel_button() -> void:
	_intel_btn = Button.new()
	_intel_btn.theme = ThemeFactory.make(ACCENT)
	_intel_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_intel_btn.offset_left = 20
	_intel_btn.offset_right = 250
	_intel_btn.offset_top = 314
	_intel_btn.offset_bottom = 404
	_intel_btn.add_theme_font_size_override("font_size", 22)
	_intel_btn.pressed.connect(func(): intel_overlay_requested.emit())
	_intel_btn.pressed.connect(Anim.tap_press.bind(_intel_btn))
	add_child(_intel_btn)
	set_overlay_label("Off")

## Called by world_root as the overlay cycles. Shows the active dimension, tinted to its color.
func set_overlay_label(dim_name: String) -> void:
	if not is_instance_valid(_intel_btn):
		return
	_intel_btn.text = "Intel: %s" % dim_name
	var tint := TEXT
	match dim_name:
		"Danger":      tint = Color(0.95, 0.45, 0.48)
		"Market":      tint = Color(0.50, 0.85, 0.58)
		"Competition": tint = Color(0.95, 0.78, 0.42)
	_intel_btn.add_theme_color_override("font_color", tint)

# ---- phone button -------------------------------------------------------

var _phone_btn: Button

func _build_phone_button() -> void:
	_phone_btn = Button.new()
	_phone_btn.theme = ThemeFactory.make(ACCENT)
	_phone_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_phone_btn.anchor_left = 1.0
	_phone_btn.anchor_right = 1.0
	_phone_btn.offset_left = -230
	_phone_btn.offset_right = -20
	_phone_btn.offset_top = 210
	_phone_btn.offset_bottom = 300
	_phone_btn.add_theme_font_size_override("font_size", 26)
	_phone_btn.pressed.connect(_show_phone)
	_phone_btn.pressed.connect(Anim.tap_press.bind(_phone_btn))
	add_child(_phone_btn)
	_refresh_phone_btn()
	PlayerState.phone_changed.connect(_refresh_phone_btn)

	var trap_btn := Button.new()
	trap_btn.theme = ThemeFactory.make(ACCENT)
	trap_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	trap_btn.anchor_left = 1.0
	trap_btn.anchor_right = 1.0
	trap_btn.offset_left = -230
	trap_btn.offset_right = -20
	trap_btn.offset_top = 314
	trap_btn.offset_bottom = 404
	trap_btn.text = "Trap house"
	trap_btn.add_theme_font_size_override("font_size", 24)
	trap_btn.pressed.connect(_show_trap_house)
	trap_btn.pressed.connect(Anim.tap_press.bind(trap_btn))
	add_child(trap_btn)

func _refresh_phone_btn() -> void:
	if not is_instance_valid(_phone_btn):
		return
	if PlayerState.has_phone():
		var bat := PlayerState.phone_battery()
		_phone_btn.text = "Phone %d%%" % bat
		# Low battery reads red so it's glanceable.
		var c := ACCENT if bat <= 20 else Color(0.9, 0.9, 0.92)
		_phone_btn.add_theme_color_override("font_color", c)
	else:
		_phone_btn.text = "Get phone"

# ---- arrival toast ------------------------------------------------------

func _build_arrival_toast() -> void:
	_arrival_label = Label.new()
	_arrival_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_arrival_label.offset_top = 230
	_arrival_label.offset_left = 28
	_arrival_label.offset_right = -28
	_arrival_label.offset_bottom = 380
	_arrival_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrival_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_arrival_label.add_theme_font_size_override("font_size", 36)
	_arrival_label.add_theme_color_override("font_color", ACCENT)
	_arrival_label.modulate.a = 0.0
	add_child(_arrival_label)

func _on_arrived(city_id: String) -> void:
	PlayerState.pending_arrival = {}   # live toast covers it; don't also show a cold-open report
	var c := Cities.by_id(city_id)
	_arrival_label.add_theme_color_override("font_color", ACCENT)
	_arrival_label.text = "Arrived in %s" % c.get("name", city_id)
	_flash_arrival(2.0)
	Rumble.tap()
	_refresh()

func _on_busted(city_id: String, _seized: Dictionary, roll_text: String) -> void:
	PlayerState.pending_arrival = {}   # live toast covers it (bust doesn't emit travel_arrived)
	var c := Cities.by_id(city_id)
	_arrival_label.add_theme_color_override("font_color", Color(1, 0.6, 0.2))
	_arrival_label.text = "BUSTED at %s — drugs seized.\n%s" % [c.get("name", city_id), roll_text]
	_flash_arrival(6.0)
	Rumble.bust()
	_refresh()

func _on_clean_arrival(city_id: String, roll_text: String) -> void:
	var c := Cities.by_id(city_id)
	_arrival_label.add_theme_color_override("font_color", ACCENT)
	_arrival_label.text = "Arrived in %s.\n%s" % [c.get("name", city_id), roll_text]
	_flash_arrival(3.0)
	Rumble.tap()

## "While you were away": a trip finished during app-closed time. Shown once, as a modal
## the player must acknowledge (a fading toast is too easy to miss for an offline event).
func _show_arrival_report(report: Dictionary) -> void:
	var city := Cities.by_id(report.get("city_id", ""))
	var city_name: String = city.get("name", report.get("city_id", ""))
	var kind: String = report.get("kind", "arrived")

	var body := ""
	match kind:
		"busted":
			body = "You were BUSTED at %s while you were away.\n\nSeized at the gate:\n" % city_name
			var seized: Dictionary = report.get("seized", {})
			for drug_id in seized.keys():
				var d := Drugs.by_id(drug_id)
				body += "  • %d g %s\n" % [int(seized[drug_id]), d.get("name", drug_id)]
			body += "\n%s" % report.get("roll_text", "")
			Rumble.bust()
		"clean":
			body = "You arrived in %s.\nYou cleared the TSA screening with your cargo intact.\n\n%s" % [
				city_name, report.get("roll_text", "")]
			Rumble.tap()
		_:
			body = "You arrived in %s while you were away." % city_name
			Rumble.tap()

	var dlg := AcceptDialog.new()
	dlg.title = "While you were away"
	dlg.ok_button_text = "Got it"
	add_child(dlg)
	_glassify_dialog(dlg)
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())

	var vp := get_viewport().get_visible_rect().size
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	dlg.add_child(col)
	col.add_child(_sheet_header(dlg.title))
	var lbl := Label.new()
	lbl.text = body
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(vp.x * 0.8, 0)   # constrain wrap; dialog auto-heights to fit
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color",
		Color(1, 0.6, 0.2) if kind == "busted" else TEXT)
	col.add_child(lbl)

	dlg.popup_centered()

func _flash_arrival(hold: float) -> void:
	var tween := create_tween()
	tween.tween_property(_arrival_label, "modulate:a", 1.0, 0.25)
	tween.tween_interval(hold)
	tween.tween_property(_arrival_label, "modulate:a", 0.0, 0.5)

# ---- refresh ------------------------------------------------------------

func _refresh() -> void:
	var cash := "$%s" % _comma(PlayerState.cash)
	var lbs := "%.1f / %.0f lb" % [PlayerState.pounds_carried(), PlayerState.capacity_lb()]
	var status := ""
	if PlayerState.travel != null:
		var now := Time.get_unix_time_from_system()
		var remaining := PlayerState.travel.remaining_seconds(now)
		var dest_id: String = PlayerState.travel.dest_city_id
		var dest := Cities.by_id(dest_id)
		status = "%s to %s — %s left" % [
			PlayerState.travel.mode_label().capitalize(),
			dest.get("name", dest_id),
			Travel.format_remaining(remaining)]
		_action_btn.text = "Cancel travel"
		_action_btn.visible = true
	elif PlayerState.current_city_id != "":
		var c := Cities.by_id(PlayerState.current_city_id)
		status = "In %s, %s · cash %s · %s" % [c.get("name", "?"), c.get("state", "?"), cash, lbs]
		_action_btn.text = "Market"
		_action_btn.visible = true
	else:
		status = "Off-grid · cash %s · %s" % [cash, lbs]
		_action_btn.visible = false
	if _action_glass:
		_action_glass.visible = _action_btn.visible
	if PlayerState.travel != null:
		# Travel line has no cash/carry — append them on a second line.
		_status_label.text = "%s\nCash %s · %s" % [status, cash, lbs]
	else:
		# In-city and off-grid status already include cash/carry.
		_status_label.text = status

func _comma(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	out = s + out
	return ("-" + out) if n < 0 else out

# ---- modals: trip mode picker -------------------------------------------

func show_travel_confirm(dest_lat: float, dest_lon: float, dest_city_id: String) -> void:
	if PlayerState.travel != null:
		return
	var dest := Cities.by_id(dest_city_id)
	var dlg := AcceptDialog.new()
	dlg.title = "Travel to %s, %s" % [dest.get("name", dest_city_id), dest.get("state", "?")]
	dlg.ok_button_text = "Cancel"
	add_child(dlg)
	_glassify_dialog(dlg)
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.confirmed.connect(func(): dlg.queue_free())

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	dlg.add_child(root)
	root.add_child(_sheet_header(dlg.title))

	var loading := Label.new()
	loading.text = "Looking up routes…"
	root.add_child(loading)

	var vp := get_viewport().get_visible_rect().size
	dlg.popup_centered(Vector2i(int(vp.x * 0.96), int(vp.y * 0.92)))

	# Plot the trip: fetch realistic route alternatives from OSRM, let the player pick one,
	# then show the per-mode options for the chosen route.
	var dest_is_airport: bool = bool(dest.get("commercial_airport", false))
	var origin_city := Cities.by_id(PlayerState.current_city_id)
	var origin_is_airport: bool = bool(origin_city.get("commercial_airport", false))
	var o_lat := PlayerState.lat
	var o_lon := PlayerState.lon
	var routes: Array = await TripPlanner.plan_routes(Router, o_lat, o_lon, dest_lat, dest_lon)

	if not is_instance_valid(loading):
		return  # dialog closed during fetch
	loading.queue_free()

	var modes_box := VBoxContainer.new()
	modes_box.add_theme_constant_override("separation", 6)

	var current_route: Array = [routes[0] if not routes.is_empty() else null]
	var rebuild_modes_ref: Array = [null]   # lets the closure re-invoke itself after a purchase
	var refresh := func(): rebuild_modes_ref[0].call(current_route[0])
	var rebuild_modes := func(route):
		current_route[0] = route
		for c in modes_box.get_children():
			c.queue_free()
		var opts := TripPlanner.options_for_route(route, o_lat, o_lon, dest_lat, dest_lon,
			origin_is_airport, dest_is_airport, PlayerState.owned_vehicle_modes)
		for opt in opts:
			modes_box.add_child(_build_trip_row(opt, dest_city_id, dlg, refresh))
	rebuild_modes_ref[0] = rebuild_modes

	if routes.size() > 1:
		var hdr := Label.new()
		hdr.text = "Plot trip — choose a route"
		hdr.add_theme_font_size_override("font_size", 26)
		hdr.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		root.add_child(hdr)
		var group := ButtonGroup.new()
		for i in routes.size():
			var r: Route = routes[i]
			var miles: float = r.total_distance_m / 1609.344
			var rb := Button.new()
			rb.toggle_mode = true
			rb.button_group = group
			rb.text = "Route %d — %.1f mi · ~%s driving" % [i + 1, miles, Travel.format_remaining(r.total_duration_s)]
			rb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			rb.add_theme_font_size_override("font_size", 24)
			rb.custom_minimum_size = Vector2(0, 88)
			rb.button_pressed = (i == 0)
			rb.toggled.connect(func(on): if on: rebuild_modes.call(r))
			root.add_child(rb)

	# Scroll the mode list so all rows stay reachable in short (landscape) viewports.
	var modes_scroll := ScrollContainer.new()
	modes_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modes_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modes_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes_scroll.add_child(modes_box)
	root.add_child(modes_scroll)
	rebuild_modes.call(routes[0] if not routes.is_empty() else null)

# ---- glass helpers ------------------------------------------------------

## Turn an AcceptDialog into a frosted-glass sheet: translucent dark frost + rim, and the
## glass button/input theme for everything inside it.
func _glassify_dialog(dlg: AcceptDialog) -> void:
	dlg.theme = ThemeFactory.make(ACCENT)
	# Borderless: no OS title bar, no X, no window chrome — a clean frosted glass sheet.
	dlg.borderless = true
	dlg.transparent = true
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.09, 0.14, 0.82)   # readable dark frost, map shows through
	panel.set_corner_radius_all(30)
	panel.set_border_width_all(1)
	panel.border_color = Color(1, 1, 1, 0.22)         # bright rim = glass edge
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 24
	panel.anti_aliasing = true
	panel.set_content_margin_all(22)
	dlg.add_theme_stylebox_override("panel", panel)

## A glass sheet's header: title in accent + a hairline divider, replacing the old window title bar.
func _sheet_header(text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 34)
	lbl.add_theme_color_override("font_color", ACCENT)
	v.add_child(lbl)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.12)
	rule.custom_minimum_size = Vector2(0, 2)
	v.add_child(rule)
	return v

## Translucent glass slab for list rows inside dialogs.
func _glass_row_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.60, 0.74, 0.10)
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.anti_aliasing = true
	sb.set_content_margin_all(18)
	return sb

## How much product this mode can travel with (lb). Foot = body capacity; owned vehicle = its
## trunk (or the cheapest listing's trunk as a preview when not yet owned); services are fixed.
func _mode_carry_lb(mode: int) -> float:
	match mode:
		Travel.Mode.WALK, Travel.Mode.WALK_OFFROAD:
			return PlayerState.foot_capacity_lb()
		Travel.Mode.BIKE, Travel.Mode.MOTORCYCLE, Travel.Mode.CAR:
			return PlayerState.vehicle_trunk_lb(mode) if PlayerState.owns_vehicle_mode(mode) \
				else Vehicles.base_trunk_lb(mode)
	return float(SERVICE_CARRY_LB.get(mode, 9999.0))

func _build_trip_row(opt, dest_city_id: String, dlg: AcceptDialog, refresh: Callable) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _glass_row_stylebox())

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	row.add_child(hb)

	var icon := TextureRect.new()
	if ResourceLoader.exists(opt.icon):
		icon.texture = load(opt.icon)
	icon.custom_minimum_size = Vector2(104, 104)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not opt.available:
		icon.modulate = Color(1, 1, 1, 0.35)   # dim locked / unavailable modes
	hb.add_child(icon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	hb.add_child(info)

	var label := Label.new()
	label.text = opt.label
	label.add_theme_font_size_override("font_size", 32)
	info.add_child(label)

	if opt.sublabel != "":
		var sub := Label.new()
		sub.text = opt.sublabel
		sub.add_theme_font_size_override("font_size", 20)
		sub.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		info.add_child(sub)

	# Carry check: can this mode haul what the player is currently holding?
	var carried := PlayerState.pounds_carried()
	var cap := _mode_carry_lb(opt.mode)
	var over_capacity: bool = opt.available and carried > cap + 0.05

	var detail := Label.new()
	detail.add_theme_font_size_override("font_size", 24)
	detail.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	if opt.available:
		var miles: float = opt.route.total_distance_m / 1609.344
		var eta := Travel.format_remaining(opt.eta_s)
		detail.text = "%.1f mi · %s · $%d · holds %.0f lb" % [miles, eta, opt.cost_dollars, cap]
	else:
		detail.text = "— %s" % opt.unavailable_reason
	info.add_child(detail)

	if over_capacity:
		var warn := Label.new()
		warn.text = "Carrying %.1f lb — won't fit. Sell some or take a bigger ride." % carried
		warn.add_theme_font_size_override("font_size", 20)
		warn.add_theme_color_override("font_color", ACCENT)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(warn)

	if opt.needs_purchase:
		# Locked personal vehicle: buy a used one in-game to unlock this mode + raise hold cap.
		var buy := Button.new()
		buy.text = "Buy one"
		buy.custom_minimum_size = Vector2(160, 100)
		buy.add_theme_font_size_override("font_size", 26)
		buy.tooltip_text = "Browse used %s listings" % opt.marketplace_query
		buy.pressed.connect(func(): _show_vehicle_listings(opt.mode, opt.marketplace_query, refresh))
		hb.add_child(buy)
	elif over_capacity:
		# Can't haul the current stash this way — jump to the market to sell some down.
		var sell := Button.new()
		sell.text = "Sell\nfirst"
		sell.custom_minimum_size = Vector2(140, 100)
		sell.add_theme_font_size_override("font_size", 24)
		sell.pressed.connect(func():
			dlg.queue_free()
			market_requested.emit())
		hb.add_child(sell)
	else:
		var go := Button.new()
		go.text = "GO"
		go.custom_minimum_size = Vector2(140, 100)
		go.add_theme_font_size_override("font_size", 32)
		go.disabled = (not opt.available) or (opt.cost_dollars > PlayerState.cash)
		if not opt.available:
			go.tooltip_text = opt.unavailable_reason
		elif opt.cost_dollars > PlayerState.cash:
			go.tooltip_text = "Need $%d" % opt.cost_dollars
		go.pressed.connect(func():
			var ok := PlayerState.start_travel(opt.route, dest_city_id, opt.mode,
				opt.eta_s, opt.cost_dollars)
			if ok:
				dlg.queue_free())
		hb.add_child(go)

	return row

## Used-vehicle marketplace: pick a listing to buy in-game (unlocks the mode + raises hold cap),
## or open real local listings. `refresh` re-renders the travel modes so the row unlocks live.
func _show_vehicle_listings(mode: int, marketplace_query: String, refresh: Callable) -> void:
	var dlg := AcceptDialog.new()
	var kind: String = {Travel.Mode.BIKE: "bikes", Travel.Mode.MOTORCYCLE: "motorcycles",
		Travel.Mode.CAR: "cars"}.get(mode, "vehicles")
	dlg.title = "Used %s for sale nearby" % kind
	dlg.ok_button_text = "Close"
	add_child(dlg)
	_glassify_dialog(dlg)
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.confirmed.connect(func(): dlg.queue_free())

	var vscroll := ScrollContainer.new()
	vscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dlg.add_child(vscroll)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vscroll.add_child(root)
	root.add_child(_sheet_header(dlg.title))

	for listing in Vehicles.for_mode(mode):
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _glass_row_stylebox())
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 18)
		row.add_child(hb)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 3)
		hb.add_child(info)

		var name_lbl := Label.new()
		name_lbl.text = String(listing.get("name", "?"))
		name_lbl.add_theme_font_size_override("font_size", 30)
		info.add_child(name_lbl)

		var spec := Label.new()
		spec.text = "$%s · trunk holds %d lb" % [_comma(int(listing.get("price", 0))), int(listing.get("trunk_lb", 0))]
		spec.add_theme_font_size_override("font_size", 22)
		spec.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		info.add_child(spec)

		var cond := Label.new()
		cond.text = String(listing.get("condition", ""))
		cond.add_theme_font_size_override("font_size", 19)
		cond.add_theme_color_override("font_color", Color(0.62, 0.62, 0.62))
		cond.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(cond)

		var buy := Button.new()
		buy.custom_minimum_size = Vector2(150, 96)
		buy.add_theme_font_size_override("font_size", 26)
		var price := int(listing.get("price", 0))
		buy.text = "Buy"
		buy.disabled = price > PlayerState.cash
		if buy.disabled:
			buy.tooltip_text = "Need $%s" % _comma(price)
		buy.pressed.connect(func():
			if PlayerState.buy_vehicle(mode, listing):
				dlg.queue_free()
				refresh.call())
		hb.add_child(buy)
		root.add_child(row)

	# Real-world listings link, kept from the original design: search local used inventory.
	var find := Button.new()
	find.text = "Search real local listings ↗"
	find.add_theme_font_size_override("font_size", 22)
	find.custom_minimum_size = Vector2(0, 76)
	find.pressed.connect(func():
		var origin_city := Cities.by_id(PlayerState.current_city_id)
		var q := ("%s %s" % [marketplace_query, String(origin_city.get("name", ""))]).strip_edges()
		OS.shell_open("https://www.facebook.com/marketplace/search/?query=" + q.uri_encode()))
	root.add_child(find)

	var vp := get_viewport().get_visible_rect().size
	dlg.popup_centered(Vector2i(int(vp.x * 0.94), int(vp.y * 0.8)))

# ---- modals: phone ------------------------------------------------------

func _show_phone() -> void:
	if not PlayerState.has_phone():
		_show_phone_listings(_show_phone)   # no phone yet — go buy one, then reopen the panel
		return
	var dlg := AcceptDialog.new()
	dlg.title = "Phone"
	dlg.ok_button_text = "Close"
	add_child(dlg)
	_glassify_dialog(dlg)
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.confirmed.connect(func(): dlg.queue_free())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dlg.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	var rebuild_ref: Array = [null]
	var rebuild := func():
		for c in content.get_children():
			c.queue_free()
		_populate_phone_panel(content, dlg, rebuild_ref[0])
	rebuild_ref[0] = rebuild
	rebuild.call()

	var vp := get_viewport().get_visible_rect().size
	dlg.popup_centered(Vector2i(int(vp.x * 0.94), int(vp.y * 0.86)))

func _populate_phone_panel(content: VBoxContainer, dlg: AcceptDialog, rebuild: Callable) -> void:
	content.add_child(_sheet_header("Phone"))
	var p: Dictionary = PlayerState.phone
	var graphene: bool = p.get("os", "stock") == "graphene"

	var art_path := Phones.art_path(p.get("id", ""))
	if ResourceLoader.exists(art_path):
		var art := TextureRect.new()
		art.texture = load(art_path)
		art.custom_minimum_size = Vector2(0, 300)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		content.add_child(art)

	var name_lbl := Label.new()
	name_lbl.text = "%s  ·  Tier %d" % [p.get("name", "?"), int(p.get("tier", 1))]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 32)
	content.add_child(name_lbl)

	# Battery bar.
	var bat := PlayerState.phone_battery()
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = bat
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 44)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT if bat <= 20 else Color(0.35, 0.75, 0.45)
	fill.set_corner_radius_all(8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.10)
	bg.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	content.add_child(bar)
	var bat_lbl := Label.new()
	bat_lbl.text = "Battery %d%%%s" % [bat, "  ·  DEAD — charge it" if bat <= 0 else ""]
	bat_lbl.add_theme_font_size_override("font_size", 22)
	bat_lbl.add_theme_color_override("font_color", Color(0.82, 0.82, 0.85))
	content.add_child(bat_lbl)

	# OS + traceability.
	var os_lbl := Label.new()
	os_lbl.text = "OS: %s" % ("GraphineOS (hardened)" if graphene else "Stock")
	os_lbl.add_theme_font_size_override("font_size", 24)
	os_lbl.add_theme_color_override("font_color", Color(0.35, 0.75, 0.45) if graphene else Color(0.90, 0.68, 0.20))
	content.add_child(os_lbl)

	var trace := PlayerState.phone_trace()
	var trace_lbl := Label.new()
	var trace_word := "low" if trace <= 30 else ("moderate" if trace <= 60 else "high")
	trace_lbl.text = "Police traceability: %s (%d/100)" % [trace_word, trace]
	trace_lbl.add_theme_font_size_override("font_size", 24)
	trace_lbl.add_theme_color_override("font_color", Color(0.35, 0.75, 0.45) if trace <= 30 else (Color(0.90, 0.68, 0.20) if trace <= 60 else ACCENT))
	content.add_child(trace_lbl)

	if not graphene and bool(p.get("graphene_supported", false)):
		var hint := Label.new()
		hint.text = "This model can run GraphineOS — flash it to go dark."
		hint.add_theme_font_size_override("font_size", 19)
		hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.64))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(hint)

	# Actions.
	var wired := Button.new()
	wired.text = "Charge (wired)  +%d%%" % int(p.get("charge_wired", 0))
	wired.custom_minimum_size = Vector2(0, 96)
	wired.add_theme_font_size_override("font_size", 26)
	wired.disabled = bat >= 100
	wired.pressed.connect(func(): if PlayerState.charge_phone("wired"): rebuild.call())
	content.add_child(wired)

	var wl_amt := int(p.get("charge_wireless", 0))
	var wireless := Button.new()
	wireless.text = ("Charge (wireless)  +%d%%" % wl_amt) if wl_amt > 0 else "No wireless charging"
	wireless.custom_minimum_size = Vector2(0, 96)
	wireless.add_theme_font_size_override("font_size", 26)
	wireless.disabled = wl_amt <= 0 or bat >= 100
	wireless.pressed.connect(func(): if PlayerState.charge_phone("wireless"): rebuild.call())
	content.add_child(wireless)

	if PlayerState.phone_can_flash_graphene():
		var flash := Button.new()
		flash.text = "Flash GraphineOS (free, de-Googles it)"
		flash.custom_minimum_size = Vector2(0, 96)
		flash.add_theme_font_size_override("font_size", 24)
		flash.pressed.connect(func():
			if PlayerState.flash_graphene():
				Notify.good("Trace dropped to %d/100." % PlayerState.phone_trace(), "GraphineOS flashed")
				rebuild.call())
		content.add_child(flash)

	var change := Button.new()
	change.text = "Buy a different phone"
	change.custom_minimum_size = Vector2(0, 96)
	change.add_theme_font_size_override("font_size", 24)
	change.pressed.connect(func():
		dlg.queue_free()
		_show_phone_listings(_show_phone))
	content.add_child(change)

## Phone marketplace. on_bought re-opens the phone panel after a purchase.
func _show_phone_listings(on_bought: Callable) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Get a phone"
	dlg.ok_button_text = "Close"
	add_child(dlg)
	_glassify_dialog(dlg)
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.confirmed.connect(func(): dlg.queue_free())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dlg.add_child(scroll)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)
	root.add_child(_sheet_header(dlg.title))

	for listing in Phones.all():
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _glass_row_stylebox())
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 16)
		row.add_child(hb)

		var art_path := Phones.art_path(listing.get("id", ""))
		if ResourceLoader.exists(art_path):
			var art := TextureRect.new()
			art.texture = load(art_path)
			art.custom_minimum_size = Vector2(96, 96)
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			hb.add_child(art)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		hb.add_child(info)
		var nm := Label.new()
		var tags := "Tier %d · trace %d" % [int(listing.get("tier", 1)), int(listing.get("trace", 0))]
		if bool(listing.get("graphene_supported", false)):
			tags += " · GraphineOS-capable"
		nm.text = String(listing.get("name", "?"))
		nm.add_theme_font_size_override("font_size", 28)
		info.add_child(nm)
		var meta := Label.new()
		meta.text = "$%s · %s" % [_comma(int(listing.get("price", 0))), tags]
		meta.add_theme_font_size_override("font_size", 20)
		meta.add_theme_color_override("font_color", Color(0.82, 0.82, 0.85))
		info.add_child(meta)
		var note := Label.new()
		note.text = String(listing.get("note", ""))
		note.add_theme_font_size_override("font_size", 18)
		note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.64))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(note)

		var buy := Button.new()
		buy.text = "Buy"
		buy.custom_minimum_size = Vector2(140, 96)
		buy.add_theme_font_size_override("font_size", 26)
		var price := int(listing.get("price", 0))
		buy.disabled = price > PlayerState.cash
		if buy.disabled:
			buy.tooltip_text = "Need $%s" % _comma(price)
		buy.pressed.connect(func():
			if PlayerState.buy_phone(listing):
				dlg.queue_free()
				on_bought.call())
		hb.add_child(buy)
		root.add_child(row)

	var vp := get_viewport().get_visible_rect().size
	dlg.popup_centered(Vector2i(int(vp.x * 0.96), int(vp.y * 0.86)))

# ---- modals: trap house -------------------------------------------------

func _show_trap_house() -> void:
	var city_id := PlayerState.current_city_id
	if city_id == "":
		Notify.info("Set one up once you've arrived somewhere.", "You're on the road")
		return
	# Settle passive sales the crew made while you were gone.
	if PlayerState.has_trap_house(city_id):
		var rep := PlayerState.accrue_trap_house(city_id)
		if int(rep.get("net", 0)) > 0:
			Notify.good("Crew moved %dg and netted you $%s (they skimmed $%s)." % [
				int(rep.get("sold", 0)), _comma(int(rep.get("net", 0))), _comma(int(rep.get("skim", 0)))],
				"While you were gone")

	var dlg := AcceptDialog.new()
	var city := Cities.by_id(city_id)
	dlg.title = "%s — operation" % city.get("name", city_id)
	dlg.ok_button_text = "Close"
	add_child(dlg)
	_glassify_dialog(dlg)
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.confirmed.connect(func(): dlg.queue_free())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dlg.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	var rebuild_ref: Array = [null]
	var rebuild := func():
		for c in content.get_children():
			c.queue_free()
		_populate_trap(content, city_id, rebuild_ref[0])
	rebuild_ref[0] = rebuild
	rebuild.call()

	var vp := get_viewport().get_visible_rect().size
	dlg.popup_centered(Vector2i(int(vp.x * 0.96), int(vp.y * 0.88)))

func _trap_header(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _populate_trap(content: VBoxContainer, city_id: String, rebuild: Callable) -> void:
	content.add_child(_sheet_header(Cities.by_id(city_id).get("name", "Operation")))
	if not PlayerState.has_trap_house(city_id):
		content.add_child(_trap_header("Set up an operation here. Stash product off your person and put a crew on it to push while you travel.", 24, Color(0.85, 0.85, 0.88)))
		for tier in Trap.house_tiers():
			var row := PanelContainer.new()
			row.add_theme_stylebox_override("panel", _glass_row_stylebox())
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 14)
			row.add_child(hb)
			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(info)
			info.add_child(_trap_header(String(tier.get("name", "?")), 28, Color(0.95, 0.95, 0.96)))
			info.add_child(_trap_header("$%s · holds %d lb · %d worker slots" % [_comma(int(tier.get("setup_cost", 0))), int(tier.get("storage_lb", 0)), int(tier.get("slots", 1))], 21, Color(0.82, 0.82, 0.85)))
			info.add_child(_trap_header(String(tier.get("note", "")), 18, Color(0.6, 0.6, 0.64)))
			var setup := Button.new()
			setup.text = "Set up"
			setup.custom_minimum_size = Vector2(150, 92)
			setup.add_theme_font_size_override("font_size", 24)
			setup.disabled = int(tier.get("setup_cost", 0)) > PlayerState.cash
			setup.pressed.connect(func(): if PlayerState.setup_trap_house(city_id, tier): rebuild.call())
			hb.add_child(setup)
			content.add_child(row)
		return

	var h: Dictionary = PlayerState.trap_houses[city_id]
	var used_lb: float = PlayerState.house_stash_grams(city_id) / 453.592
	content.add_child(_trap_header("%s · stash %.1f / %d lb" % [h.get("name", "Trap house"), used_lb, int(h.get("storage_lb", 0))], 30, ACCENT))

	# Crew.
	var emps: Array = h.get("employees", [])
	content.add_child(_trap_header("Crew (%d / %d)" % [emps.size(), int(h.get("slots", 1))], 26, Color(0.9, 0.9, 0.92)))
	for e in emps:
		content.add_child(_trap_header("• %s — pushes ~%dg/day, skims %d%%" % [e.get("name", "Worker"), int(e.get("push_per_day", 0)), int(round(float(e.get("skim", 0)) * 100.0))], 21, Color(0.78, 0.82, 0.78)))
	if emps.size() < int(h.get("slots", 1)):
		content.add_child(_trap_header("Hire:", 22, Color(0.7, 0.7, 0.74)))
		for emp in Trap.employees():
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 12)
			var lbl := _trap_header("%s — $%s · ~%dg/day · skim %d%%" % [emp.get("name", "?"), _comma(int(emp.get("hire_cost", 0))), int(emp.get("push_per_day", 0)), int(round(float(emp.get("skim", 0)) * 100.0))], 20, Color(0.82, 0.82, 0.85))
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(lbl)
			var hire := Button.new()
			hire.text = "Hire"
			hire.custom_minimum_size = Vector2(120, 72)
			hire.add_theme_font_size_override("font_size", 22)
			hire.disabled = int(emp.get("hire_cost", 0)) > PlayerState.cash
			hire.pressed.connect(func(): if PlayerState.hire_employee(city_id, emp): rebuild.call())
			hb.add_child(hire)
			content.add_child(hb)

	# Stash from carry / take back.
	content.add_child(_trap_header("Stash from your carry:", 24, Color(0.9, 0.9, 0.92)))
	var carry_any := false
	for drug_id in PlayerState.inventory.keys():
		carry_any = true
		var grams := int(PlayerState.inventory[drug_id])
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		var lbl := _trap_header("%s — %dg on you" % [Drugs.by_id(drug_id).get("name", drug_id), grams], 21, Color(0.82, 0.82, 0.85))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(lbl)
		var stash_btn := Button.new()
		stash_btn.text = "Stash all"
		stash_btn.custom_minimum_size = Vector2(150, 72)
		stash_btn.add_theme_font_size_override("font_size", 21)
		stash_btn.pressed.connect(func(): if PlayerState.stash_to_house(city_id, drug_id, grams): rebuild.call())
		hb.add_child(stash_btn)
		content.add_child(hb)
	if not carry_any:
		content.add_child(_trap_header("(nothing on you to stash)", 18, Color(0.55, 0.55, 0.6)))

	var stash: Dictionary = h.get("stash", {})
	if not stash.is_empty():
		content.add_child(_trap_header("In the stash (crew sells this):", 24, Color(0.9, 0.9, 0.92)))
		for drug_id in stash.keys():
			var grams := int(stash[drug_id])
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 12)
			var lbl := _trap_header("%s — %dg stashed" % [Drugs.by_id(drug_id).get("name", drug_id), grams], 21, Color(0.82, 0.82, 0.85))
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(lbl)
			var take_btn := Button.new()
			take_btn.text = "Take all"
			take_btn.custom_minimum_size = Vector2(150, 72)
			take_btn.add_theme_font_size_override("font_size", 21)
			take_btn.pressed.connect(func(): if PlayerState.take_from_house(city_id, drug_id, grams): rebuild.call())
			hb.add_child(take_btn)
			content.add_child(hb)

# ---- modals: market -----------------------------------------------------

func show_market() -> void:
	if PlayerState.current_city_id == "":
		return
	var city_id := PlayerState.current_city_id
	var city := Cities.by_id(city_id)

	var dlg := AcceptDialog.new()
	dlg.title = "%s — Market" % city.get("name", city_id)
	dlg.ok_button_text = "Done"
	add_child(dlg)
	_glassify_dialog(dlg)
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dlg.add_child(root)
	root.add_child(_sheet_header(dlg.title))

	var status := Label.new()
	status.add_theme_font_size_override("font_size", 24)
	status.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 1400)   # don't force a width — fill the dialog
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var refresh_status := func():
		status.text = "Cash $%s · Carry %.1f / %.0f lb · Heat %d" % [
			_comma(PlayerState.cash),
			PlayerState.pounds_carried(),
			PlayerState.capacity_lb(),
			Drugs.region_heat(city_id)]
	refresh_status.call()

	var rows: Array = []
	for d in Drugs.all():
		var row := _build_market_row(city_id, d, refresh_status)
		list.add_child(row)
		rows.append(row)

	# Size to the actual logical viewport — hardcoded px overflowed the ~830px
	# logical width (window/stretch/scale=1.3) and pushed Sell off-screen.
	var vp := get_viewport().get_visible_rect().size
	dlg.popup_centered(Vector2i(int(vp.x * 0.96), int(vp.y * 0.92)))

func _build_market_row(city_id: String, drug: Dictionary, refresh_status: Callable) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _glass_row_stylebox())
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hb)

	# Evidence-bag product icon (anti-glorification: product as evidence). The art swaps by
	# stash size — a baggie when you hold little, a taped brick when you're holding weight.
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(92, 92)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hb.add_child(icon)

	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.add_theme_constant_override("separation", 4)
	hb.add_child(name_col)

	var name_lbl := Label.new()
	name_lbl.text = drug.name
	name_lbl.add_theme_font_size_override("font_size", 32)
	name_lbl.clip_text = true   # let the name column shrink so amount + Buy + Sell all fit
	name_col.add_child(name_lbl)

	var price_lbl := Label.new()
	price_lbl.add_theme_font_size_override("font_size", 22)
	price_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	price_lbl.clip_text = true
	name_col.add_child(price_lbl)

	var amt := SpinBox.new()
	amt.min_value = 1
	amt.max_value = 9999
	amt.step = 1
	amt.value = 28
	amt.suffix = "g"
	amt.custom_minimum_size = Vector2(180, 80)
	amt.add_theme_font_size_override("font_size", 26)
	hb.add_child(amt)

	# Buy/Sell stacked in a compact column so the row fits narrow phone widths
	# (side-by-side pushed Sell off the right edge, making it unreachable).
	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 8)
	hb.add_child(btn_col)

	var buy := Button.new()
	buy.text = "Buy"
	buy.custom_minimum_size = Vector2(150, 84)
	buy.add_theme_font_size_override("font_size", 26)
	btn_col.add_child(buy)

	var sell := Button.new()
	sell.text = "Sell"
	sell.custom_minimum_size = Vector2(150, 84)
	sell.add_theme_font_size_override("font_size", 26)
	btn_col.add_child(sell)

	var refresh_row := func():
		var p: int = Market.price_per_gram(city_id, drug.id)
		var have := int(PlayerState.inventory.get(drug.id, 0))
		price_lbl.text = "$%d/g  ·  you have %d g" % [p, have]
		icon.texture = load(Drugs.icon_path(drug.id, have))

	refresh_row.call()
	Market.price_changed.connect(func(c, d, _np):
		if c == city_id and d == drug.id:
			refresh_row.call())

	buy.pressed.connect(func():
		var grams := int(amt.value)
		var p: int = Market.price_per_gram(city_id, drug.id)
		var cost := grams * p
		if not PlayerState.can_carry_more(grams):
			refresh_status.call()
			return
		if not PlayerState.change_cash(-cost):
			refresh_status.call()
			return
		PlayerState.adjust_inventory(drug.id, grams)
		Market.record_buy(city_id, drug.id, grams)
		refresh_row.call()
		refresh_status.call())

	sell.pressed.connect(func():
		var grams := int(amt.value)
		var have := int(PlayerState.inventory.get(drug.id, 0))
		if grams > have:
			refresh_status.call()
			return
		PlayerState.adjust_inventory(drug.id, -grams)
		var p: int = Market.price_per_gram(city_id, drug.id)
		var revenue := grams * p
		PlayerState.change_cash(revenue)
		Market.record_sell(city_id, drug.id, grams)
		# Moving product is how you level: XP scales with the money you actually realize.
		PlayerState.add_xp(maxi(1, revenue / 40))
		refresh_row.call()
		refresh_status.call())

	return row
