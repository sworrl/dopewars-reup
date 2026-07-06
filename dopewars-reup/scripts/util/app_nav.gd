extends Node

## Handles the Android back button / back-swipe gesture (project setting quit_on_go_back=false, so
## Godot hands the request here instead of quitting). Priority:
##   1. If the exit prompt is up  -> back dismisses it (stay).
##   2. If any dialog/popup is open -> back closes the topmost one.
##   3. Otherwise                  -> show an exit confirmation, warning the game keeps running.
## A single back never drops you out of the game unconfirmed.

var _confirm: ConfirmationDialog = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()

func _handle_back() -> void:
	# The exit prompt itself is open -> back means "keep playing".
	if _confirm != null and is_instance_valid(_confirm) and _confirm.visible:
		_confirm.hide()
		return
	# Close the topmost open in-game dialog (market, travel, phone, trap house, …).
	var subs := get_tree().root.get_embedded_subwindows()
	if not subs.is_empty():
		subs[subs.size() - 1].queue_free()
		return
	# Nothing left to back out of — confirm before leaving.
	_show_exit_confirm()

func _show_exit_confirm() -> void:
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = ConfirmationDialog.new()
	_confirm.theme = ThemeFactory.make(ThemeFactory.RE_UP_RED)
	_confirm.borderless = true   # no title bar, no X — glass sheet
	_confirm.transparent = true
	_confirm.title = "Leave the streets?"
	_confirm.dialog_text = "Leave the streets?\n\nThe game keeps running while you're gone — your crew keeps pushing, your phone keeps draining, rivals keep moving. Quit to your home screen?"
	_confirm.ok_button_text = "Quit"
	# Opaque frosted panel so it reads over the map (the theme alone is translucent).
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.09, 0.14, 0.97)
	panel.set_corner_radius_all(24)
	panel.set_border_width_all(1)
	panel.border_color = Color(0.92, 0.20, 0.25, 0.5)
	panel.set_content_margin_all(24)
	_confirm.add_theme_stylebox_override("panel", panel)
	var lbl := _confirm.get_label()
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(600, 0)
	_confirm.get_ok_button().add_theme_font_size_override("font_size", 28)
	var cancel := _confirm.get_cancel_button()
	cancel.text = "Keep playing"
	cancel.add_theme_font_size_override("font_size", 28)
	get_tree().root.add_child(_confirm)
	_confirm.confirmed.connect(func(): get_tree().quit())
	_confirm.canceled.connect(func(): if is_instance_valid(_confirm): _confirm.queue_free())
	_confirm.popup_centered(Vector2i(680, 360))
