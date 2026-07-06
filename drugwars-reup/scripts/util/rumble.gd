class_name Rumble
extends RefCounted

## Tasteful gamepad rumble. Used sparingly per the input design memo:
## - bust event: heavy
## - arrival: light tap
## - travel start: light tap
## - never continuous, never during cosmetics

static var _enabled: bool = true

static func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		Input.stop_joy_vibration(0)

static func tap() -> void:
	if not _enabled: return
	Input.start_joy_vibration(0, 0.0, 0.45, 0.10)

static func bust() -> void:
	if not _enabled: return
	Input.start_joy_vibration(0, 0.85, 0.95, 0.60)

static func pulse_triple() -> void:
	if not _enabled: return
	# Used for "robbery defense window opened" alert (when wired in v0.3).
	Input.start_joy_vibration(0, 0.6, 0.8, 0.10)
	# Caller is responsible for follow-ups via Timer; this stub fires one pulse.
