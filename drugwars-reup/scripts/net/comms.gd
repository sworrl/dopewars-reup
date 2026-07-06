extends Node

## Multiplayer comms client (autoload `Comms`). Thin wrappers over the deployed multiplayer RPCs
## (0012) plus a proximity-awareness poll: while online AND opted into presence, it periodically
## checks local earshot and alerts you when another operator is active nearby — observable activity
## → awareness, per the info-asymmetry pillar. Server-authoritative; the client only sends intents.

const AWARE_INTERVAL_S := 20.0

var opted_in := false
var _seen_local: Dictionary = {}   # dedupe key → true, so each overheard line alerts once
var _timer: Timer

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = AWARE_INTERVAL_S
	_timer.timeout.connect(_poll_awareness)
	add_child(_timer)

func online() -> bool:
	return Supa.is_signed_in()

## Opt in/out of presence. When opted in (and online), starts the awareness poll.
func set_presence(on: bool) -> void:
	opted_in = on
	if online():
		await Supa.call_rpc("update_presence", {"p_opted_in": on})
	if on and online():
		_timer.start()
	else:
		_timer.stop()

# ---- crews -----------------------------------------------------------------

## Your crew, or {} if you're not in one (server returns null then).
func my_crew() -> Dictionary:
	if not online():
		return {}
	var r := await Supa.call_rpc("my_crew")
	var j: Variant = r.get("json")
	return j if (r.get("ok", false) and typeof(j) == TYPE_DICTIONARY) else {}

func create_crew(crew_name: String, tag: String) -> Dictionary:
	return await _rpc("create_crew", {"p_name": crew_name, "p_tag": tag})

func join_crew(crew_id: int) -> Dictionary:
	return await _rpc("join_crew", {"p_crew": crew_id})

func leave_crew() -> Dictionary:
	return await _rpc("leave_crew")

# ---- messages --------------------------------------------------------------

func send_local(body: String) -> Dictionary:
	return await _rpc("send_message", {"p_scope": "local", "p_body": body})

func send_crew(body: String) -> Dictionary:
	return await _rpc("send_message", {"p_scope": "crew", "p_body": body})

func hear_local(radius: float = 0.05) -> Array:
	return await _rows("hear_local", {"p_radius": radius})

func crew_chat() -> Array:
	return await _rows("my_crew_chat")

func whispers() -> Array:
	return await _rows("my_whispers")

# ---- transport helpers -----------------------------------------------------

## Call a scalar-jsonb RPC; normalize to {ok:true, ...} or {ok:false, error}.
func _rpc(fn: String, params: Dictionary = {}) -> Dictionary:
	if not online():
		return {"ok": false, "error": "sign in to use comms"}
	var r := await Supa.call_rpc(fn, params)
	var j: Variant = r.get("json")
	if r.get("ok", false) and typeof(j) == TYPE_DICTIONARY and (j as Dictionary).get("ok", false):
		return j
	var msg := ""
	if typeof(j) == TYPE_DICTIONARY and (j as Dictionary).has("message"):
		msg = String((j as Dictionary).get("message"))
	else:
		msg = String(r.get("error", "server error"))
	return {"ok": false, "error": msg}

## Call a table-returning RPC; return the row Array (empty on error/offline).
func _rows(fn: String, params: Dictionary = {}) -> Array:
	if not online():
		return []
	var r := await Supa.call_rpc(fn, params)
	var j: Variant = r.get("json")
	return j if (r.get("ok", false) and typeof(j) == TYPE_ARRAY) else []

func _poll_awareness() -> void:
	if not (online() and opted_in):
		return
	var rows := await hear_local()
	for row in rows:
		var h := String(row.get("handle", ""))
		if h == "" or h == PlayerState.handle:
			continue   # skip your own chatter
		var key := "%s|%s" % [h, String(row.get("at", ""))]
		if _seen_local.has(key):
			continue
		_seen_local[key] = true
		Notify.alert("You catch %s talking nearby." % h, "Someone's around")
