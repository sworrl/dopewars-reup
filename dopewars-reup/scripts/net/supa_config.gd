extends RefCounted

## PUBLIC, safe-to-commit Supabase config. NO secrets live here.
##
## Real secrets — anon/publishable keys and any dev auto-login credentials — live in the GITIGNORED
## file `supa_local.gd` (copy `supa_local.example.gd` → `supa_local.gd` and fill it in). If that
## file is absent, the build runs OFFLINE (local single-player only, firewalled from the backend).
## This keeps keys and passwords out of the public repo while a local/dev build can still connect.
##
## ACTIVE picks the environment (staging vs prod). The project URL is public, so it's fine here.

const ACTIVE := "prod"

const URLS := {
	"staging": "",
	"prod":    "https://wnrtrhhdxazqzdcpspsg.supabase.co",
	# local supabase from the Android emulator would be "http://10.0.2.2:54321"
}

static func _local() -> Dictionary:
	if ResourceLoader.exists("res://scripts/net/supa_local.gd"):
		var s: Script = load("res://scripts/net/supa_local.gd")
		if s != null:
			return s.new().data()
	return {}

static func url() -> String:
	return URLS.get(ACTIVE, "")

static func anon_key() -> String:
	return _local().get("anon_keys", {}).get(ACTIVE, "")

## Optional dev auto-login {email, password}. Empty in public builds (secrets are in supa_local.gd).
static func dev_login() -> Dictionary:
	return _local().get("dev_login", {})
