extends Node

## Supabase connection layer (autoload `Supa`). Auth + RPC + Edge Functions over plain HTTP.
##
## The client sends INTENTS ONLY — it never sends a price, a cash figure, or a timestamp. The
## server computes and validates every consequence (see the Threat Posture doc). This is just the
## transport; game flows call Supa.rpc("buy", {...}) etc.
##
## DORMANT UNTIL CONFIGURED: fill in URL + ANON_KEY in scripts/net/supa_config.gd. Empty config =
## offline mode (the local single-player game keeps working, firewalled from online — a modded
## local client can never touch the online world).

const Cfg = preload("res://scripts/net/supa_config.gd")

var access_token: String = ""
var user_id: String = ""

signal signed_in(ok: bool)

func _ready() -> void:
	# DEV: auto-sign-in the dev/admin account so dev builds are always logged in. No-op offline.
	var dl := Cfg.dev_login()
	if configured() and String(dl.get("email", "")) != "":
		_dev_login.call_deferred()

func _dev_login() -> void:
	var dl := Cfg.dev_login()
	var r := await sign_in(String(dl.get("email", "")), String(dl.get("password", "")))
	if r.get("ok", false):
		var st := await call_rpc("get_my_state")
		var tier := "?"
		if st.get("ok", false) and typeof(st.get("json")) == TYPE_DICTIONARY:
			tier = String((st["json"] as Dictionary).get("tier", "?"))
		Notify.good("Signed in as %s (%s)" % [dl.get("email", ""), tier], "Backend online")
	else:
		Notify.warn("Dev login failed: %s" % String(r.get("error", "")), "Backend")
	signed_in.emit(r.get("ok", false))

func configured() -> bool:
	return Cfg.url() != "" and Cfg.anon_key() != ""

func is_signed_in() -> bool:
	return access_token != ""

# ---- auth (GoTrue) ------------------------------------------------------

func sign_up(email: String, password: String) -> Dictionary:
	return await _auth("/auth/v1/signup", {"email": email, "password": password})

func sign_in(email: String, password: String) -> Dictionary:
	return await _auth("/auth/v1/token?grant_type=password", {"email": email, "password": password})

## Anonymous sign-in — handy for quick beta/test accounts (enable it in Supabase auth settings).
func sign_in_anonymous() -> Dictionary:
	return await _auth("/auth/v1/signup", {})

## Update the signed-in user (GoTrue PUT /user). Used for change-password / change-email, and to
## LINK an email+password onto an anonymous account (upgrade at billing — captures PII only then).
func update_password(new_password: String) -> Dictionary:
	return await _post(Cfg.url() + "/auth/v1/user", {"password": new_password}, true, HTTPClient.METHOD_PUT)

func update_email(new_email: String) -> Dictionary:
	return await _post(Cfg.url() + "/auth/v1/user", {"email": new_email}, true, HTTPClient.METHOD_PUT)

func link_email(email: String, password: String) -> Dictionary:
	# Converts an anonymous user into a permanent one without losing their progress.
	return await _post(Cfg.url() + "/auth/v1/user", {"email": email, "password": password}, true, HTTPClient.METHOD_PUT)

## Sign out: revoke the session server-side and clear local tokens.
func sign_out() -> void:
	if access_token != "":
		await _post(Cfg.url() + "/auth/v1/logout", {}, true)
	access_token = ""
	user_id = ""
	signed_in.emit(false)

func _auth(path: String, body: Dictionary) -> Dictionary:
	var res := await _post(Cfg.url() + path, body, false)
	if res.get("ok", false):
		var d: Dictionary = res.get("json", {})
		access_token = d.get("access_token", "")
		var u: Dictionary = d.get("user", {})
		user_id = u.get("id", "")
	return res

# ---- RPC (PostgREST) — the main game call path --------------------------

## Call a server-authoritative function, e.g. await Supa.rpc("buy", {"p_drug":"weed","p_grams":28}).
func call_rpc(fn: String, params: Dictionary = {}) -> Dictionary:
	return await _post(Cfg.url() + "/rest/v1/rpc/" + fn, params, true)

## Invoke an Edge Function (external-call logic like travel/OSRM).
func invoke(fn: String, body: Dictionary = {}) -> Dictionary:
	return await _post(Cfg.url() + "/functions/v1/" + fn, body, true)

# ---- transport ----------------------------------------------------------

func _post(url: String, body: Dictionary, auth: bool, method: int = HTTPClient.METHOD_POST) -> Dictionary:
	if not configured():
		return {"ok": false, "error": "offline"}
	var req := HTTPRequest.new()
	add_child(req)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + Cfg.anon_key(),
	])
	if auth and access_token != "":
		headers.append("Authorization: Bearer " + access_token)
	elif auth:
		headers.append("Authorization: Bearer " + Cfg.anon_key())
	var err := req.request(url, headers, method, JSON.stringify(body))
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "request_failed"}
	var r: Array = await req.request_completed
	req.queue_free()
	var code: int = r[1]
	var text := (r[3] as PackedByteArray).get_string_from_utf8()
	var json: Variant = JSON.parse_string(text)
	if code >= 200 and code < 300:
		return {"ok": true, "code": code, "json": json}
	# Surface the server's error (postgres RAISE messages come back here).
	var msg := ""
	if typeof(json) == TYPE_DICTIONARY:
		msg = json.get("message", json.get("error", ""))
	return {"ok": false, "code": code, "error": msg, "json": json}
