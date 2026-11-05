class_name BuildEnv
extends RefCounted
## Which backend this build talks to. The committed file is the local developer setup; CI rewrites it for the
## staging build (tools/ci/write_build_env.sh, from the repository's GitHub variables) before exporting, so a staging
## build can only ever reach staging and a production build only production. Nothing secret lives here: the Nakama
## server key is the public client key every copy of the game carries.
## A developer can point a local run elsewhere with user://env.cfg ([env] env=, bg_server=, party_queue=, nakama_url=, nakama_key=, cloud=).

const ENV := "local"
const BG_SERVER := "127.0.0.1:24567"
const NAKAMA_URL := "http://127.0.0.1:7350"
const NAKAMA_KEY := "defaultkey"
const CLOUD := "0"       # "1": characters and the Battlegrounds stash live in Nakama (staging and production builds)
const REV := "dev"       # the commit the build was made from (CI writes it; a deployed server reads res://DEPLOYED_REV)

const OVERRIDE := "user://env.cfg"
static var forced := {}  # tests: values that win over everything

static func value(key: String) -> String:
	if forced.has(key):
		return str(forced[key])
	var cf := ConfigFile.new()
	if cf.load(OVERRIDE) == OK and cf.has_section_key("env", key):
		return str(cf.get_value("env", key))
	match key:
		"env": return ENV
		"bg_server": return BG_SERVER
		"nakama_url": return NAKAMA_URL
		"nakama_key": return NAKAMA_KEY
		"cloud": return CLOUD
		"rev":
			if REV == "dev" and FileAccess.file_exists("res://DEPLOYED_REV"):
				return FileAccess.get_file_as_string("res://DEPLOYED_REV").strip_edges()
			return REV
		"coop_server": return BG_SERVER.split(":")[0] + ":24570"     # the online co-op server, beside the raid server
		"lobby_url": return NAKAMA_URL if ENV != "local" else "http://127.0.0.1:7352"
		"party_queue": return BG_SERVER.split(":")[0] + ":24569"
	return ""

static func env() -> String:
	return value("env")

static func cloud() -> bool:
	return value("cloud") == "1"
