-- Ashen Crown's server-side Nakama module (loaded from Nakama's data/modules).
-- The Battlegrounds stash is owned by the game server: players can read their own (permission_read 1) but never
-- write it (permission_write 0). The dedicated game server reads and writes it through these RPCs, called
-- server-to-server with Nakama's runtime http_key (no user session), so a player can't call them.
local nk = require("nakama")

local COLLECTION = "battlegrounds"
local KEY = "stash"

local function server_only(context)
  if context.user_id ~= nil and context.user_id ~= "" then
    error({ "server only", 7 })   -- 7 = PERMISSION_DENIED
  end
end

local function stash_read(context, payload)
  server_only(context)
  local p = nk.json_decode(payload)
  local objs = nk.storage_read({ { collection = COLLECTION, key = KEY, user_id = p.user_id } })
  if #objs > 0 and objs[1].value.items ~= nil and #objs[1].value.items > 0 then
    return nk.json_encode({ items = objs[1].value.items })
  end
  return '{"items":[]}'   -- (an empty Lua table would encode as {} instead of [])
end

local function stash_write(context, payload)
  server_only(context)
  local p = nk.json_decode(payload)
  nk.storage_write({ {
    collection = COLLECTION, key = KEY, user_id = p.user_id,
    value = { items = p.items or {} }, permission_read = 1, permission_write = 0,
  } })
  return nk.json_encode({ ok = true, count = #(p.items or {}) })
end

nk.register_rpc(stash_read, "bg_stash_read")
nk.register_rpc(stash_write, "bg_stash_write")
