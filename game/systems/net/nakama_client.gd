class_name NakamaClient
extends Node
## A small Nakama client over its REST API (https://heroiclabs.com/docs/nakama/api/), enough for sign-in and storage:
## authenticate a device id (made once per PC, Battlegrounds.client_id), then read and write the player's own storage
## objects. Each call awaits one HTTPRequest. Where it connects comes from BuildEnv (local, staging or production).
## tools/nakama_check.gd exercises it against a running server.

var url := ""
var server_key := ""
var token := ""           # the session after authenticate_device
var user_id := ""
var last_error := ""
var timeout := 8.0

func _init(base_url := "", key := "") -> void:
	url = (base_url if base_url != "" else BuildEnv.value("nakama_url")).trim_suffix("/")
	server_key = key if key != "" else BuildEnv.value("nakama_key")

## Signs in (creating the account the first time) with this device's id. True on success.
func authenticate_device(device_id: String, username := "") -> bool:
	var path := "/v2/account/authenticate/device?create=true"
	if username != "":
		path += "&username=" + username.uri_encode()
	var auth := "Basic " + Marshalls.utf8_to_base64(server_key + ":")
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, path, {"id": device_id}, auth)
	if not r.has("token"):
		return false
	token = str(r["token"])
	user_id = _jwt_field(token, "uid")
	return true

## Writes objects into the player's storage: [{collection, key, value: Dictionary}]. True on success.
func write_objects(objs: Array) -> bool:
	var out := []
	for o in objs:
		out.append({"collection": o["collection"], "key": o["key"], "value": JSON.stringify(o["value"]),
			"permission_read": 1, "permission_write": 1})
	var r: Dictionary = await _call(HTTPClient.METHOD_PUT, "/v2/storage", {"objects": out})
	return r.has("acks")

## Reads one of the player's storage objects; {} when it isn't there (or on an error, see last_error).
func read_object(collection: String, key: String) -> Dictionary:
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "/v2/storage",
		{"object_ids": [{"collection": collection, "key": key, "user_id": user_id}]})
	var objs: Array = r.get("objects", [])
	if objs.is_empty():
		return {}
	var v = JSON.parse_string(str(objs[0].get("value", "{}")))
	return v if v is Dictionary else {}

## Every object the player keeps in `collection` (up to 100): [{key, value: Dictionary, update_time}].
func list_objects(collection: String) -> Array:
	var r: Dictionary = await _call(HTTPClient.METHOD_GET, "/v2/storage/%s?user_id=%s&limit=100" % [collection.uri_encode(), user_id], {})
	var out := []
	for o in r.get("objects", []):
		var v = JSON.parse_string(str(o.get("value", "{}")))
		out.append({"key": str(o.get("key", "")), "value": v if v is Dictionary else {}, "update_time": str(o.get("update_time", ""))})
	return out

## Server side: whose session token this is (the user id), checked by Nakama itself; "" if it isn't valid.
func verify_session(session_token: String) -> String:
	var r: Dictionary = await _call(HTTPClient.METHOD_GET, "/v2/account", {}, "Bearer " + session_token)
	var u = r.get("user", {})
	return str(u.get("id", "")) if u is Dictionary else ""

## A signed-in player's RPC (with their session), e.g. bg_ticket. {} on an error (see last_error).
func user_rpc(id: String, payload: Dictionary) -> Dictionary:
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "/v2/rpc/%s?unwrap" % id, payload)
	if r.has("payload") and r["payload"] is String:
		var v = JSON.parse_string(r["payload"])
		return v if v is Dictionary else {}
	return r

## Server side: one of the game's server-only RPCs (deploy/nakama/modules/ashen.lua), with the runtime http_key.
func server_rpc(id: String, payload: Dictionary, http_key: String) -> Dictionary:
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "/v2/rpc/%s?http_key=%s&unwrap" % [id, http_key.uri_encode()], payload, "-")
	if r.has("payload") and r["payload"] is String:
		var v = JSON.parse_string(r["payload"])
		return v if v is Dictionary else {}
	return r

func delete_objects(objs: Array) -> bool:
	var ids := []
	for o in objs:
		ids.append({"collection": o["collection"], "key": o["key"]})
	var r: Dictionary = await _call(HTTPClient.METHOD_PUT, "/v2/storage/delete", {"object_ids": ids})
	return last_error == "" and r is Dictionary

func _call(method: int, path: String, body: Dictionary, auth := "") -> Dictionary:
	last_error = ""
	var req := HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if auth != "-":
		headers.append("Authorization: " + (auth if auth != "" else "Bearer " + token))
	var err := req.request(url + path, headers, method, JSON.stringify(body) if method != HTTPClient.METHOD_GET else "")
	if err != OK:
		req.queue_free()
		last_error = "request failed to start (%d)" % err
		return {}
	var res: Array = await req.request_completed
	req.queue_free()
	var code: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		last_error = "no connection (result %d)" % res[0]
		return {}
	if code < 200 or code >= 300:
		last_error = "HTTP %d: %s" % [code, text.substr(0, 200)]
		return {}
	var d = JSON.parse_string(text) if text != "" else {}
	return d if d is Dictionary else {}

## A field of the session token's payload (the user id is "uid").
static func _jwt_field(jwt: String, field: String) -> String:
	var parts := jwt.split(".")
	if parts.size() < 2:
		return ""
	var p := parts[1].replace("-", "+").replace("_", "/")
	while p.length() % 4 != 0:
		p += "="
	var d = JSON.parse_string(Marshalls.base64_to_utf8(p))
	return str(d.get(field, "")) if d is Dictionary else ""
