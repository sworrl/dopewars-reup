extends Node

## Single entry point for player-facing alerts (proximity warnings, busts, level-ups).
##
## Today this shows the branded in-app Notify toast, which is the reliable path during active play.
## A background *system* notification (seen when the app is minimized) needs a small Godot Android
## plugin (AAR) exposing showNotification() — Godot 4.6.2's JavaClassWrapper can call static/instance
## Java methods but can't construct NotificationChannel/Notification.Builder, so it can't post one
## from pure GDScript. When that plugin lands, route _push_system() through it. push() never throws.

func _ready() -> void:
	if OS.get_name() == "Android":
		# Pre-request the Android 13+ notification permission so the future plugin can post silently.
		OS.request_permission("android.permission.POST_NOTIFICATIONS")
	# Game events that deserve an alert.
	PlayerState.level_up.connect(func(lvl): push("Level up", "You reached level %d." % lvl, "good"))

## Show an alert. kind: "alert" | "warn" | "info" | "good".
func push(title: String, text: String, kind: String = "alert") -> void:
	match kind:
		"good": Notify.good(text, title)
		"warn": Notify.warn(text, title)
		"info": Notify.info(text, title)
		_: Notify.alert(text, title)
	_push_system(title, text)

## Background system notification. No-op until the Android plugin ships (see class note).
func _push_system(_title: String, _text: String) -> void:
	pass
