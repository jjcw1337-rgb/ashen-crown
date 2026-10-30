class_name AdminKey
extends RefCounted
## The owner's admin key: the only way (besides running from the Godot editor) to get the developer tools
## (the F8 testing panel, unlock-all-acts; Game.dev_tools) in any build, live or preview.
## user://admin.key holds a name and an RSA signature of "ashen-crown-admin|v1|<name>" made with the
## owner's private key, which never goes in the repo. The game checks it against PUBLIC_KEY below, so a
## key can't be forged, copied text edited, or made up: only a key signed by the owner works.
## Make one: godot --headless -s tools/admin_key.gd -- <private.pem> "<name>" <out admin.key>
## (then put it in %APPDATA%\Godot\app_userdata\Ashen Crown\ on that PC).

const PATH := "user://admin.key"
const PREFIX := "ashen-crown-admin|v1|"
const PUBLIC_KEY := """-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAyARtUs+NQU4qVIlkONWY
n7vUFqybUv9Jxj3Q/6TmA4GWATxnoHG7+c1C0DVXxn+H8pzCfmiWbc1gD5z7Hecs
43sfWR2Hbj1ghB2sTSVN6Pjxcq0lFX+dt1UNxiFELX+JUy6BbxnstU/n3PHxPqiH
TaMaernqlZ0FV0Sb5o6akcneV0T+KJCNcWe2RuOJ0FQiClRa19k/uKawOV2wcwV8
+VVmGQtxaOfSkaHRty8no90+fRh7jbsRNNF8UgkKMFlQg55dx5pibkIgL167WWEW
CvmI5B0DOrbTvI1Syrz5LKJUj4WX2/DjVa2LgdBarBoikDRPtMa6PXEDowCrPxdQ
N/pbK/Yx15bbQaGNEb+k+jBVw+PjloFm/t8SWFoQVygBHznVXDKGNtppKgjiE03a
qKhsuHiwwO3ogYtmITfWHeYtRuI1lVrawYBeEZc4gCmwH3ryCkvVgjphrzR4RCQI
mvtQu53fIU5y64obOj3K7ZdjGiOjrWkO5iGLyrb74A/PAgMBAAE=
-----END PUBLIC KEY-----"""

## The admin's name if this PC holds a valid admin key, else "".
static func holder() -> String:
	if not FileAccess.file_exists(PATH):
		return ""
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return ""
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY or not d.has("name") or not d.has("sig"):
		return ""
	var nm := str(d["name"])
	return nm if verify(nm, Marshalls.base64_to_raw(str(d["sig"]))) else ""

## Is `sig` the owner's signature for admin `nm`?
static func verify(nm: String, sig: PackedByteArray) -> bool:
	if nm == "" or sig.is_empty():
		return false
	var key := CryptoKey.new()
	if key.load_from_string(PUBLIC_KEY, true) != OK:
		return false
	return Crypto.new().verify(HashingContext.HASH_SHA256, digest(nm), sig, key)

static func digest(nm: String) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update((PREFIX + nm).to_utf8_buffer())
	return h.finish()
