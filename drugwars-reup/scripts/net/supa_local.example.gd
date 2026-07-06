extends RefCounted

## TEMPLATE — copy this to `supa_local.gd` (which is gitignored) and fill in your secrets.
## supa_local.gd holds the anon/publishable keys and (optionally) a dev auto-login account.
## It is NEVER committed. Without it, the build runs offline.

func data() -> Dictionary:
	return {
		# Settings → API → "anon" / "public" (eyJ…) OR the new "Publishable key" (sb_publishable_…).
		# The anon/publishable key is a CLIENT key, safe to ship in the APK — but keep it out of the
		# public source repo so forks don't hit your project by default.
		"anon_keys": {
			"prod":    "",
			"staging": "",
		},
		# Optional: auto-sign-in this account on launch (dev builds only). Leave email blank to disable.
		"dev_login": { "email": "", "password": "" },
	}
