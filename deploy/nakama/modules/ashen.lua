-- Ashen Crown's server-side Nakama module (loaded from Nakama's data/modules).
--
-- The Battlegrounds stash is the game server's: players read their own (permission_read 1) but never write it.
--  * The dedicated game server reads and writes it through bg_stash_read / bg_stash_write, called server to server
--    with Nakama's runtime http_key (no user session), so no player can call them.
--  * Players can't write or delete anything in the "battlegrounds" collection through the generic storage API either
--    (the before-hooks below), so a fresh account can't create its own stash before the server does.
--
-- Joining a raid: the game client never sends its Nakama session over the game's UDP connection (that traffic isn't
-- encrypted). It asks for a one-time join ticket over HTTPS (bg_ticket: random, 60 seconds), sends only the ticket to
-- the game server, which redeems it (bg_ticket_redeem, http_key) for the player's user id; a ticket works once.
local nk = require("nakama")

local COLLECTION = "battlegrounds"
local KEY = "stash"
local TICKETS = "bg_tickets"
local SYSTEM_USER = "00000000-0000-0000-0000-000000000000"
local TICKET_SECS = 60

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

-- A signed-in player asks for a join ticket (over HTTPS, with their session).
local function ticket(context, payload)
  if context.user_id == nil or context.user_id == "" then
    error({ "sign in first", 16 })   -- 16 = UNAUTHENTICATED
  end
  -- two random (crypto/rand) v4 UUIDs: 244 random bits
  local t = string.gsub(nk.uuid_v4() .. nk.uuid_v4(), "-", "")
  nk.storage_write({ {
    collection = TICKETS, key = t, user_id = SYSTEM_USER,
    value = { user_id = context.user_id, expires = nk.time() + TICKET_SECS * 1000 },
    permission_read = 0, permission_write = 0,
  } })
  return nk.json_encode({ ticket = t })
end

-- The game server turns a ticket into the player's user id, once.
local function ticket_redeem(context, payload)
  server_only(context)
  local p = nk.json_decode(payload)
  if type(p.ticket) ~= "string" or #p.ticket < 16 then
    return '{"user_id":""}'
  end
  local objs = nk.storage_read({ { collection = TICKETS, key = p.ticket, user_id = SYSTEM_USER } })
  if #objs == 0 then
    return '{"user_id":""}'
  end
  nk.storage_delete({ { collection = TICKETS, key = p.ticket, user_id = SYSTEM_USER } })
  local v = objs[1].value
  if v.expires < nk.time() then
    return '{"user_id":""}'
  end
  return nk.json_encode({ user_id = v.user_id })
end

-- No client writes or deletes in the server's collections.
local function guard_write(context, payload)
  for _, o in ipairs(payload.objects or {}) do
    if o.collection == COLLECTION or o.collection == TICKETS then
      error({ "the Battlegrounds stash is kept by the game server", 7 })
    end
  end
  return payload
end

local function guard_delete(context, payload)
  for _, o in ipairs(payload.object_ids or {}) do
    if o.collection == COLLECTION or o.collection == TICKETS then
      error({ "the Battlegrounds stash is kept by the game server", 7 })
    end
  end
  return payload
end

nk.register_rpc(stash_read, "bg_stash_read")
nk.register_rpc(stash_write, "bg_stash_write")
nk.register_rpc(ticket, "bg_ticket")
nk.register_rpc(ticket_redeem, "bg_ticket_redeem")
nk.register_req_before(guard_write, "WriteStorageObjects")
nk.register_req_before(guard_delete, "DeleteStorageObjects")
