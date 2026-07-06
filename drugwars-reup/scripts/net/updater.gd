extends Node

## In-app auto-updater (autoload `Updater`). Sideloaded builds get no Play Store updates, so on launch
## the game checks a public version manifest published by the GitHub release pipeline. If a newer
## SIGNED build exists it offers a branded modal — update now, or later (postpone to the next open).
##
## On Android: download the APK, verify its SHA-256 against the manifest, then hand off to the system
## package installer (which shows Android's own "install unknown apps" consent). On desktop/Steam:
## open the release page — those platforms update through their own channels.
##
## Nothing here is trusted blindly: the APK is signed with our release key AND checksum-verified
## before we ever launch the installer. A failed/mismatched download never installs and never blocks
## play — the check is silent on any error (offline, no release yet, etc.).

const MANIFEST_URL := "https://github.com/sworrl/dopewars-reup/releases/latest/download/latest.json"
const RELEASES_PAGE := "https://github.com/sworrl/dopewars-reup/releases/latest"
const APK_TMP := "user://update.apk"
const CHECK_DELAY_S := 3.2   # let the branded loading splash finish before a modal can ever appear

signal update_available(info: Dictionary)
signal download_progress(pct: float)
signal download_failed(reason: String)

var _postponed := false      # "Later" = stay quiet until the next app open (a fresh session)
var _checked := false
var _modal: CanvasLayer = null

func current_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))

func _ready() -> void:
	# One check per launch, after the splash. Fire-and-forget; the modal appears only if needed.
	await get_tree().create_timer(CHECK_DELAY_S).timeout
	check()

## Fetch the manifest and, if it advertises a newer version, raise update_available + show the modal.
func check() -> void:
	if _checked or _postponed:
		return
	_checked = true
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			return   # offline / no release yet — silent, never blocks play
		var info: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(info) != TYPE_DICTIONARY:
			return
		if _is_newer(String(info.get("version", "")), current_version()):
			update_available.emit(info)
			_show_modal(info)
	)
	if req.request(MANIFEST_URL) != OK:
		req.queue_free()
		_checked = false   # let a later manual check() retry

## Semantic-version compare: is `a` strictly newer than `b`? ("1.2.10" beats "1.2.9").
func _is_newer(a: String, b: String) -> bool:
	var pa := a.lstrip("v").split(".")
	var pb := b.lstrip("v").split(".")
	for i in range(3):
		var x: int = int(pa[i]) if i < pa.size() else 0
		var y: int = int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false

func _show_modal(info: Dictionary) -> void:
	if is_instance_valid(_modal):
		return
	_modal = (preload("res://scripts/ui/update_modal.gd") as Script).new()
	get_tree().root.add_child(_modal)
	_modal.setup(info)
	_modal.chose_update.connect(_on_update_now.bind(info))
	_modal.chose_later.connect(_on_later)

func _on_later() -> void:
	_postponed = true   # next app open (fresh session) offers it again

func _on_update_now(info: Dictionary) -> void:
	if OS.get_name() != "Android":
		OS.shell_open(String(info.get("url", RELEASES_PAGE)))   # desktop/Steam → release page
		return
	_download(info)

# ---- Android: download, verify, hand off to the package installer -----------

func _download(info: Dictionary) -> void:
	var url := String(info.get("url", ""))
	if url == "":
		download_failed.emit("no download url")
		return
	var req := HTTPRequest.new()
	req.download_file = APK_TMP
	add_child(req)

	# Poll byte progress so the modal can show a real bar (HTTPRequest has no per-chunk signal).
	var poll := Timer.new()
	poll.wait_time = 0.2
	add_child(poll)
	poll.timeout.connect(func() -> void:
		var total := req.get_body_size()
		if total > 0:
			download_progress.emit(clampf(float(req.get_downloaded_bytes()) / float(total), 0.0, 1.0))
	)
	poll.start()

	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		poll.stop(); poll.queue_free(); req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			download_failed.emit("Download failed (%d)" % code)
			return
		var want := String(info.get("sha256", "")).to_lower()
		if want != "" and _sha256(APK_TMP) != want:
			download_failed.emit("Checksum mismatch — not installing")
			return
		download_progress.emit(1.0)
		_install_apk()
	)
	if req.request(url) != OK:
		poll.stop(); poll.queue_free(); req.queue_free()
		download_failed.emit("Couldn't start download")

func _sha256(path: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	while not f.eof_reached():
		ctx.update(f.get_buffer(1 << 16))
	f.close()
	return ctx.finish().hex_encode()

## Launch the system package installer on the downloaded APK via a FileProvider content URI.
## Uses AndroidRuntime + JavaClassWrapper (no custom plugin). The <provider> + file_paths.xml in the
## Android manifest expose user:// (the app's internal files dir) as "<pkg>.fileprovider".
func _install_apk() -> void:
	var rt: Object = Engine.get_singleton("AndroidRuntime")
	if rt == null:
		download_failed.emit("No Android runtime")
		return
	var activity: Object = rt.getActivity()
	var context: Object = rt.getApplicationContext()
	var pkg := String(context.getPackageName())

	var Intent: Object = JavaClassWrapper.wrap("android.content.Intent")
	var FileProvider: Object = JavaClassWrapper.wrap("androidx.core.content.FileProvider")
	var File: Object = JavaClassWrapper.wrap("java.io.File")

	var apk_abs := ProjectSettings.globalize_path(APK_TMP)
	var file: Object = File.File(apk_abs)   # JavaClassWrapper constructor: Class.Class(args)
	var uri: Object = FileProvider.getUriForFile(context, pkg + ".fileprovider", file)

	var intent: Object = Intent.Intent(Intent.ACTION_VIEW)
	intent.setDataAndType(uri, "application/vnd.android.package-archive")
	intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_GRANT_READ_URI_PERMISSION)

	# startActivity must run on the UI thread.
	var launch := func() -> void: activity.startActivity(intent)
	activity.runOnUiThread(rt.createRunnableFromGodotCallable(launch))
