extends Control

## Bethesda-style chargen, redesigned per spec:
##   • Class is the gatekeeper: each class has a FIXED base stat array (all <7) and
##     a small BONUS budget (1-5 points) reflecting real-life experience.
##   • Player picks class FIRST → sees base locked → spends bonus on stats they want.
##   • Stat caps after allocation: non-primary 8, primary 10.
##   • Player picks 1 starter perk; class default is preselected.
##   • Class also seeds starting XP (0-1500), giving starting level 0-3.
##
## Stat scale 1-15 (D&D 5e mod = floor((score-10)/2)).

const MAP_SCENE := "res://scenes/map.tscn"
const STAT_NAMES := ["STR", "DEX", "CON", "INT", "WIS", "CHA"]
const STAT_DESCS := {
	"STR": "Combat damage, intimidation, foot-carry capacity",
	"DEX": "Stealth, driving, sleight-of-hand, lockpick, getaway",
	"CON": "Toughness, drug tolerance, prison survival, addiction resistance",
	"INT": "Chemistry, business, investigation, planning",
	"WIS": "Streetwise, threat detection, sense motive",
	"CHA": "Negotiation, deception, leadership, recruitment",
}
const NON_PRIMARY_CAP := 8
const PRIMARY_CAP := 10

@onready var handle_edit: LineEdit = %HandleEdit
@onready var class_list: VBoxContainer = %ClassList
@onready var stats_box: VBoxContainer = %StatsBox
@onready var points_label: Label = %PointsLabel
@onready var perk_list: VBoxContainer = %PerkList
@onready var perk_header: Label = %PerkHeader
@onready var summary_label: RichTextLabel = %Summary
@onready var begin_btn: Button = %Begin

var _picked_class_id: String = ""
var _allocated: Dictionary = {}     # stat → int (additions on top of base)
var _picked_perk: String = ""

var _stat_value_labels: Dictionary = {}
var _stat_minus_btns: Dictionary = {}
var _stat_plus_btns: Dictionary = {}

var __class_group: ButtonGroup
var __perk_group: ButtonGroup

func _ready() -> void:
	# Apply the global 3D-bevel theme. Recolors when a class is picked.
	theme = ThemeFactory.make(ThemeFactory.RE_UP_RED)
	handle_edit.text_changed.connect(func(_t): _refresh_summary())
	__class_group = ButtonGroup.new()
	__perk_group = ButtonGroup.new()
	_build_class_rows()
	_build_stat_rows()
	begin_btn.pressed.connect(_on_begin)
	_refresh_summary()
	Anim.wire_button_haptics(self)
	Anim.pass_touch($Scroll)          # let drags over class/stat buttons still scroll the page
	_setup_wizard()                   # single-page steps + swipe, no long scroll
	Anim.fade_in(self, 0.3)

# ---- single-page step wizard (no scrolling; swipe or Back/Next) -----------

var _step := 0
var _steps: Array = []
var _back_btn: Button
var _next_btn: Button
var _dots: Label
const _STEP_TITLES := ["Who you are", "Your stats", "Your edge", "Confirm"]

func _setup_wizard() -> void:
	var inner := $Scroll/V/Pad/Inner
	_steps = [
		[inner.get_node("HandleLabel"), inner.get_node("HandleEdit"), inner.get_node("ClassHeader"), inner.get_node("ClassList")],
		[inner.get_node("StatsHeader"), inner.get_node("PointsLabel"), inner.get_node("StatsBox")],
		[inner.get_node("PerkHeader"), inner.get_node("PerkList")],
		[inner.get_node("SummaryHeader"), inner.get_node("Summary")],
	]
	_dots = Label.new()
	_dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dots.add_theme_font_size_override("font_size", 22)
	inner.add_child(_dots)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	inner.add_child(nav)
	_back_btn = Button.new()
	_back_btn.text = "Back"
	_back_btn.custom_minimum_size = Vector2(0, 96)
	_back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_btn.pressed.connect(_prev_step)
	nav.add_child(_back_btn)
	_next_btn = Button.new()
	_next_btn.custom_minimum_size = Vector2(0, 96)
	_next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_btn.pressed.connect(_next_step)
	nav.add_child(_next_btn)
	begin_btn.visible = false          # the wizard's "Begin" is the last-step Next
	_show_step(0)

func _show_step(n: int) -> void:
	_step = clampi(n, 0, _steps.size() - 1)
	for i in _steps.size():
		for node in _steps[i]:
			node.visible = (i == _step)
	_back_btn.disabled = _step == 0
	var last := _step == _steps.size() - 1
	_next_btn.text = "Begin" if last else "Next  ›"
	_dots.text = "%s   (%d/%d)" % [_STEP_TITLES[_step], _step + 1, _steps.size()]
	if last:
		_refresh_summary()
	$Scroll.scroll_vertical = 0

func _next_step() -> void:
	if _step == 0 and _picked_class_id == "":
		return                          # must pick a class first
	if _step == _steps.size() - 1:
		_on_begin()
		return
	_show_step(_step + 1)

func _prev_step() -> void:
	_show_step(_step - 1)

var _swipe_x := 0.0
func _unhandled_input(ev: InputEvent) -> void:
	# Horizontal swipe changes step (Back/Next still work). Vertical drags stay for scrolling.
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.pressed:
			_swipe_x = t.position.x
		else:
			var dx := t.position.x - _swipe_x
			if dx <= -120.0:
				_next_step()
			elif dx >= 120.0:
				_prev_step()

# ---- class picker ---------------------------------------------------------

func _build_class_rows() -> void:
	for c in CharClasses.all():
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = __class_group
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 22)
		btn.custom_minimum_size = Vector2(0, 150)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Imagen-generated class portrait (somber documentary style), shown left of the text.
		var portrait := "res://assets/sprites/classes/%s.png" % c.id
		if ResourceLoader.exists(portrait):
			btn.icon = load(portrait)
			btn.expand_icon = false
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
			btn.add_theme_constant_override("icon_max_width", 120)
			btn.add_theme_constant_override("h_separation", 18)
		var starting_level := PlayerState.xp_for_level_for_xp(int(c.get("starting_xp", 0)))
		btn.text = "%s — %s\n  %+d bonus pts · primary %s · starts at level %d  ($%d)" % [
			c.name, c.blurb, int(c.bonus_points), c.primary_stat, starting_level,
			int(c.starting_cash)]
		btn.toggled.connect(_on_class_toggled.bind(c.id))
		class_list.add_child(btn)

func _on_class_toggled(pressed: bool, class_id: String) -> void:
	if not pressed:
		return
	_picked_class_id = class_id
	var c := CharClasses.by_id(class_id)
	_allocated = {}
	for s in STAT_NAMES:
		_allocated[s] = 0
	# Tint the whole UI with this class's accent color.
	theme = ThemeFactory.make(ThemeFactory.accent_for_class(class_id))
	_refresh_stat_rows()
	_picked_perk = c.get("default_perk", "")
	_rebuild_perk_list()
	_refresh_summary()
	Anim.release_pulse(self, ThemeFactory.accent_for_class(class_id), 0.45)

func _set_class_dependent_visibility(vis: bool) -> void:
	stats_box.visible = vis
	points_label.visible = vis
	perk_list.visible = vis
	perk_header.visible = vis

# ---- stat allocation ------------------------------------------------------

func _build_stat_rows() -> void:
	for s in STAT_NAMES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		stats_box.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = s
		name_lbl.custom_minimum_size = Vector2(80, 0)
		name_lbl.add_theme_font_size_override("font_size", 32)
		name_lbl.add_theme_color_override("font_color", Color(0.92, 0.20, 0.25))
		row.add_child(name_lbl)

		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(90, 90)
		minus.add_theme_font_size_override("font_size", 36)
		minus.pressed.connect(_on_stat_pressed.bind(s, -1))
		row.add_child(minus)

		var val_lbl := Label.new()
		val_lbl.custom_minimum_size = Vector2(90, 0)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val_lbl.add_theme_font_size_override("font_size", 32)
		row.add_child(val_lbl)

		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(90, 90)
		plus.add_theme_font_size_override("font_size", 36)
		plus.pressed.connect(_on_stat_pressed.bind(s, 1))
		row.add_child(plus)

		var desc_lbl := Label.new()
		desc_lbl.text = STAT_DESCS[s]
		desc_lbl.add_theme_font_size_override("font_size", 18)
		desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(desc_lbl)

		_stat_value_labels[s] = val_lbl
		_stat_minus_btns[s] = minus
		_stat_plus_btns[s] = plus

func _on_stat_pressed(stat: String, delta: int) -> void:
	var c := CharClasses.by_id(_picked_class_id)
	var base: int = int(c.base_stats.get(stat, 0))
	var primary: bool = (stat == String(c.primary_stat))
	var cap: int = PRIMARY_CAP if primary else NON_PRIMARY_CAP
	var current := _final_stat(stat)
	var target := current + delta
	if target < base or target > cap:
		return
	if delta > 0 and _spent_points() >= int(c.bonus_points):
		return
	_allocated[stat] = target - base
	_refresh_stat_rows()
	_refresh_summary()

func _final_stat(stat: String) -> int:
	if _picked_class_id == "":
		return 0
	var c := CharClasses.by_id(_picked_class_id)
	var base: int = int(c.base_stats.get(stat, 0))
	return base + int(_allocated.get(stat, 0))

func _spent_points() -> int:
	var sum := 0
	for s in STAT_NAMES:
		sum += int(_allocated.get(s, 0))
	return sum

func _refresh_stat_rows() -> void:
	if _picked_class_id == "":
		return
	var c := CharClasses.by_id(_picked_class_id)
	var bonus: int = int(c.bonus_points)
	var spent := _spent_points()
	for s in STAT_NAMES:
		var primary: bool = (s == String(c.primary_stat))
		var cap: int = PRIMARY_CAP if primary else NON_PRIMARY_CAP
		var base: int = int(c.base_stats.get(s, 0))
		var final_val := _final_stat(s)
		var mod := int(floor(float(final_val - 10) / 2.0))
		var lbl: Label = _stat_value_labels[s]
		lbl.text = "%d (%+d)" % [final_val, mod]
		lbl.add_theme_color_override("font_color",
			Color(0.92, 0.80, 0.24) if primary else Color(0.95, 0.95, 0.95))
		var minus_btn: Button = _stat_minus_btns[s]
		var plus_btn: Button = _stat_plus_btns[s]
		minus_btn.disabled = (final_val <= base)
		plus_btn.disabled = (final_val >= cap) or (spent >= bonus)
	points_label.text = "Bonus: %d / %d spent" % [spent, bonus]
	points_label.add_theme_color_override("font_color",
		Color(0.40, 0.85, 0.40) if spent == bonus else Color(0.85, 0.85, 0.85))

# ---- perks ----------------------------------------------------------------

func _rebuild_perk_list() -> void:
	for child in perk_list.get_children():
		child.queue_free()
	if _picked_class_id == "":
		return
	var available := Perks.chargen_available_for_class(_picked_class_id)
	available.sort_custom(func(a, b):
		var a_locked = a.get("class_lock", null) != null
		var b_locked = b.get("class_lock", null) != null
		if a_locked != b_locked:
			return a_locked
		return a.id < b.id)

	for perk in available:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = __perk_group
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 22)
		btn.custom_minimum_size = Vector2(0, 100)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var locked: bool = perk.get("class_lock", null) != null
		var prefix := "[CLASS] " if locked else ""
		btn.text = "%s%s — %s" % [prefix, perk.name, perk.blurb]
		btn.button_pressed = (perk.id == _picked_perk)
		btn.toggled.connect(_on_perk_toggled.bind(perk.id))
		perk_list.add_child(btn)
	Anim.pass_touch(perk_list)         # new perk buttons must also pass drags to the scroll

func _on_perk_toggled(pressed: bool, perk_id: String) -> void:
	if pressed:
		_picked_perk = perk_id
	_refresh_summary()

# ---- summary --------------------------------------------------------------

func _refresh_summary() -> void:
	var bb := ""
	if handle_edit.text.strip_edges() == "":
		bb += "[color=#999]Enter a handle.[/color]\n"
	else:
		bb += "Handle: [b]%s[/b]\n" % handle_edit.text.strip_edges()
	if _picked_class_id == "":
		bb += "[color=#999]Pick a class.[/color]\n"
	else:
		var c := CharClasses.by_id(_picked_class_id)
		var starting_level := PlayerState.xp_for_level_for_xp(int(c.get("starting_xp", 0)))
		bb += "Class: [b]%s[/b]  [color=#999]· level %d · cash $%d[/color]\n" % [
			c.name, starting_level, int(c.starting_cash)]
		bb += "[color=#bbb]Stats:[/color] "
		for s in STAT_NAMES:
			var primary: bool = (s == String(c.primary_stat))
			var v := _final_stat(s)
			var mod := int(floor(float(v - 10) / 2.0))
			var color := "#e6cb3c" if primary else ("#888" if mod == 0 else ("#88e" if mod > 0 else "#c66"))
			bb += " [color=%s]%s %d (%+d)[/color]" % [color, s, v, mod]
		bb += "\n"
		var str_v := _final_stat("STR")
		var str_mod := int(floor(float(str_v - 10) / 2.0))
		var capacity := maxi(PlayerState.CARRY_MIN_LB, 30 + 10 * str_mod)
		bb += "[color=#bbb]Foot carry (no perks):[/color] %d lb\n" % capacity
		var spent := _spent_points()
		var bonus: int = int(c.bonus_points)
		if spent < bonus:
			bb += "[color=#c66]Spend %d more bonus point%s.[/color]\n" % [
				bonus - spent, "" if (bonus - spent) == 1 else "s"]
	if _picked_perk == "":
		bb += "[color=#999]Pick a starter perk.[/color]\n"
	else:
		var p := Perks.by_id(_picked_perk)
		bb += "Perk: [b]%s[/b]  [color=#999]%s[/color]\n" % [p.name, p.blurb]

	summary_label.text = bb

	begin_btn.disabled = (
		handle_edit.text.strip_edges() == ""
		or _picked_class_id == ""
		or _picked_perk == ""
		or not _is_bonus_satisfied())

func _is_bonus_satisfied() -> bool:
	if _picked_class_id == "":
		return false
	var c := CharClasses.by_id(_picked_class_id)
	return _spent_points() == int(c.bonus_points)

# ---- commit ---------------------------------------------------------------

func _on_begin() -> void:
	for s in STAT_NAMES:
		PlayerState.stats[s] = _final_stat(s)
	PlayerState.handle = handle_edit.text.strip_edges()
	PlayerState.class_id = _picked_class_id
	PlayerState.perks = []
	PlayerState.add_perk(_picked_perk)
	var c := CharClasses.by_id(_picked_class_id)
	PlayerState.cash = int(c.get("starting_cash", PlayerState.STARTING_CASH))
	PlayerState.xp = int(c.get("starting_xp", 0))
	PlayerState.save_to_disk()
	get_tree().change_scene_to_file(MAP_SCENE)
