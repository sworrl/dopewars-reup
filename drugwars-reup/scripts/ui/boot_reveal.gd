extends Control

## First-launch boot reveal. The anti-glorification pillar lives here:
## the player picks their starting city, then sees the actual drug-crisis
## stats for that area (real CDC/DEA-derived numbers from region profiles)
## BEFORE character creation. "This is your block."
##
## Skipped when a save exists.

const NEXT_SCENE := "res://scenes/chargen.tscn"
const MAP_SCENE := "res://scenes/map.tscn"

@onready var title: Label = $Scroll/V/Title
@onready var subtitle: Label = $Scroll/V/Subtitle
@onready var stage1: VBoxContainer = $Scroll/V/Stage1
@onready var stage2: VBoxContainer = $Scroll/V/Stage2
@onready var city_list: VBoxContainer = $Scroll/V/Stage1/CityList
@onready var stats_label: RichTextLabel = $Scroll/V/Stage2/Stats
@onready var continue_btn: Button = $Scroll/V/Stage2/Continue
@onready var disclaimer: Label = $Scroll/V/Disclaimer

var _picked_city_id: String = ""

func _ready() -> void:
	if FileAccess.file_exists(PlayerState.SAVE_PATH):
		# Returning player — skip the reveal.
		get_tree().change_scene_to_file.call_deferred(MAP_SCENE)
		return
	theme = ThemeFactory.make(ThemeFactory.RE_UP_RED)
	title.add_theme_font_override("font", load("res://assets/fonts/BigShouldersDisplay-Black.ttf"))
	title.add_theme_font_size_override("font_size", 64)
	_show_stage1()
	for city in Cities.all():
		var b := Button.new()
		b.text = "%s, %s" % [city.name, city.state]
		b.add_theme_font_size_override("font_size", 36)
		b.custom_minimum_size = Vector2(0, 110)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_city_picked.bind(city.id))
		city_list.add_child(b)
	continue_btn.pressed.connect(_on_continue)
	Anim.wire_button_haptics(self)
	Anim.fade_in($Scroll/V/Title, 0.5)
	Anim.slide_in_from_bottom($Scroll/V/Stage1, 32.0, 0.45)

func _show_stage1() -> void:
	stage1.visible = true
	stage2.visible = false
	title.text = "Dope Wars: Re-Up Edition"
	subtitle.text = "Where are you?"

func _show_stage2() -> void:
	stage1.visible = false
	stage2.visible = true
	subtitle.text = "This is your block."

func _on_city_picked(city_id: String) -> void:
	_picked_city_id = city_id
	_render_local_stats(city_id)
	_show_stage2()
	Anim.slide_in_from_bottom($Scroll/V/Stage2, 48.0, 0.40)

func _render_local_stats(city_id: String) -> void:
	var c := Cities.by_id(city_id)
	var od := Drugs.region_od_baseline(city_id)
	var heat := Drugs.region_heat(city_id)
	var demand_pairs: Array = []
	for d in Drugs.all():
		demand_pairs.append([d.name, Drugs.region_demand(city_id, d.id), d.id])
	demand_pairs.sort_custom(func(a, b): return a[1] > b[1])
	var top3 = demand_pairs.slice(0, 3)

	var bb := "[font_size=44][b]%s, %s[/b][/font_size]\n" % [c.name, c.state]
	bb += "[font_size=24]Population: %s[/font_size]\n\n" % _comma(int(c.get("population", 0)))
	bb += "[font_size=26][color=#e6cb3c]Drug overdose deaths per year[/color]: ~%d per 100,000[/font_size]\n" % od
	bb += "[font_size=26][color=#e6cb3c]Local enforcement pressure[/color]: %d / 100[/font_size]\n\n" % heat
	bb += "[font_size=24][color=#cccccc]The drugs being moved here right now (highest local demand):[/color][/font_size]\n"
	for entry in top3:
		bb += "[font_size=24]  • %s[/font_size]\n" % entry[0]
	bb += "\n[font_size=20][color=#999999][i]These numbers are derived from CDC WONDER overdose data, DEA priority lists, and FBI crime stats for this real ZIP code. Every NPC overdose, bust, and broken family in the simulation corresponds to a pattern in real data. The game is fiction. The crisis is not.[/i][/color][/font_size]"
	stats_label.text = bb

func _on_continue() -> void:
	# Place the player at the chosen city's coords.
	var c := Cities.by_id(_picked_city_id)
	PlayerState.lat = float(c.lat)
	PlayerState.lon = float(c.lon)
	PlayerState.current_city_id = _picked_city_id
	# Don't save yet — chargen will set stats/class/cash and save once.
	get_tree().change_scene_to_file(NEXT_SCENE)

func _comma(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	out = s + out
	return ("-" + out) if n < 0 else out
