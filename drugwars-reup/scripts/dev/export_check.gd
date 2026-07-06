extends SceneTree

## Run via: godot --headless --editor --path drugwars-reup --script scripts/dev/export_check.gd
##
## Calls EditorExportPlatform.can_export() on each defined preset and dumps the
## validation messages that Godot's CLI export hides behind the generic
## "Cannot export project ... due to configuration errors" wrapper.

func _initialize() -> void:
	var all = Engine.get_singleton_list()
	print("[export_check] singletons available (%d):" % all.size())
	for s in all:
		if "Export" in s or "Editor" in s:
			print("[export_check]   - %s" % s)
	var ee = null
	for try_name in ["EditorExport", "ProjectExport", "EditorInterface"]:
		if Engine.has_singleton(try_name):
			ee = Engine.get_singleton(try_name)
			print("[export_check] using singleton '%s' → %s" % [try_name, ee])
			break
	if ee == null:
		push_error("[export_check] no usable export singleton — see list above")
		quit(1)
		return
	if not ee.has_method("get_export_preset_count"):
		print("[export_check] singleton lacks get_export_preset_count(); methods:")
		for m in ee.get_method_list():
			if "export" in m.name.to_lower() or "preset" in m.name.to_lower():
				print("[export_check]   - %s" % m.name)
		quit(1)
		return
	var preset_count: int = ee.get_export_preset_count()
	print("[export_check] %d export preset(s) defined." % preset_count)
	for i in preset_count:
		var preset = ee.get_export_preset(i)
		var preset_name = preset.get_name()
		var platform = preset.get_export_platform()
		var platform_name = platform.get_name() if platform else "?"
		print("[export_check] --- preset[%d] name='%s' platform='%s' ---" % [i, preset_name, platform_name])
		if platform == null:
			continue

		var msgs: Array = []
		var ok = platform.can_export(preset, msgs)
		print("[export_check]   can_export() → %s" % ok)
		if msgs is Array and not msgs.is_empty():
			print("[export_check]   messages (%d):" % msgs.size())
			for m in msgs:
				print("[export_check]     · %s" % str(m))

		if platform.has_method("get_message_count"):
			var n: int = platform.get_message_count()
			if n > 0:
				print("[export_check]   platform.get_message_count() = %d" % n)
				for j in n:
					var cat = platform.get_message_category(j) if platform.has_method("get_message_category") else "?"
					var msg = platform.get_message_text(j) if platform.has_method("get_message_text") else (
						platform.get_message(j) if platform.has_method("get_message") else "?")
					print("[export_check]     [%s] %s" % [cat, msg])
	quit()
