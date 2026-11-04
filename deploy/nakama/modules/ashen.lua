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
-- The admins (Blaine's progression overhaul: "a persistent admin flag or role ... a way to designate our accounts as
-- admins. Enforce authorization on the server"): one object per admin account, owned by the system user, that only
-- the server can write (admin_set, http_key; tools/admin_role.sh). admin_status tells a signed-in player whether they
-- are one (the game shows its admin tools); admin_check tells the game server (the Battlegrounds server refuses a
-- non-admin carrying "Go to level 20" gear).
local ADMINS = "admins"

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

local function is_admin(user_id)
  if user_id == nil or user_id == "" then
    return false
  end
  local objs = nk.storage_read({ { collection = ADMINS, key = user_id, user_id = SYSTEM_USER } })
  return #objs > 0
end

-- A signed-in player: am I an admin? (and my account id, to be designated one)
local function admin_status(context, payload)
  if context.user_id == nil or context.user_id == "" then
    return '{"admin":false,"user_id":""}'
  end
  return nk.json_encode({ admin = is_admin(context.user_id), user_id = context.user_id })
end

-- The game server: is this account an admin?
local function admin_check(context, payload)
  server_only(context)
  local p = nk.json_decode(payload)
  return nk.json_encode({ admin = is_admin(p.user_id) })
end

-- The server (http_key, tools/admin_role.sh): make an account an admin, or not.
local function admin_set(context, payload)
  server_only(context)
  local p = nk.json_decode(payload)
  if type(p.user_id) ~= "string" or #p.user_id < 8 then
    error({ "user_id needed", 3 })   -- 3 = INVALID_ARGUMENT
  end
  if p.admin then
    nk.storage_write({ {
      collection = ADMINS, key = p.user_id, user_id = SYSTEM_USER,
      value = { name = p.name or "", since = nk.time() }, permission_read = 0, permission_write = 0,
    } })
  else
    nk.storage_delete({ { collection = ADMINS, key = p.user_id, user_id = SYSTEM_USER } })
  end
  return nk.json_encode({ user_id = p.user_id, admin = p.admin and true or false })
end

-- No client writes or deletes in the server's collections.
local function guard_write(context, payload)
  for _, o in ipairs(payload.objects or {}) do
    if o.collection == COLLECTION or o.collection == TICKETS or o.collection == ADMINS then
      error({ "the Battlegrounds stash is kept by the game server", 7 })
    end
  end
  return payload
end

local function guard_delete(context, payload)
  for _, o in ipairs(payload.object_ids or {}) do
    if o.collection == COLLECTION or o.collection == TICKETS or o.collection == ADMINS then
      error({ "the Battlegrounds stash is kept by the game server", 7 })
    end
  end
  return payload
end

nk.register_rpc(stash_read, "bg_stash_read")
nk.register_rpc(stash_write, "bg_stash_write")
nk.register_rpc(ticket, "bg_ticket")
nk.register_rpc(ticket_redeem, "bg_ticket_redeem")
nk.register_rpc(admin_status, "admin_status")
nk.register_rpc(admin_check, "admin_check")
nk.register_rpc(admin_set, "admin_set")
nk.register_req_before(guard_write, "WriteStorageObjects")
nk.register_req_before(guard_delete, "DeleteStorageObjects")

-- Telemetry and error reports (docs/nightly/TELEMETRY.md, the game's scripts/telemetry.gd): performance samples and
-- errors go into two tables of Nakama's own database, which Grafana reads (role grafana_ro, SELECT only) and the
-- nightly triage job queries. Players send with their session ("telemetry"), the dedicated servers with the runtime
-- http_key ("telemetry_server"). A batch holds at most MAX_ROWS of each; long strings are cut.
local MAX_ROWS = 20

local function setup_tables()
  nk.sql_exec([[
    CREATE TABLE IF NOT EXISTS tm_sample (
      id bigserial PRIMARY KEY, ts timestamptz NOT NULL DEFAULT now(), user_id text, session text,
      build text, env text, os text, gpu text, zone text, run int, class text, level int, x real, z real, preset int,
      bg boolean, enemies int, boss boolean, partners int, dead boolean,
      secs real, fps_avg real, fps_low1 real, frame_p99 real, hitches int, vram_mb int, res text)]], {})
  nk.sql_exec([[
    CREATE TABLE IF NOT EXISTS tm_error (
      id bigserial PRIMARY KEY, ts timestamptz NOT NULL DEFAULT now(), user_id text, session text, source text,
      kind text, fingerprint text, message text, at text, count int, build text, env text, zone text,
      context jsonb, crumbs jsonb, tail text)]], {})
  nk.sql_exec("CREATE INDEX IF NOT EXISTS tm_sample_ts ON tm_sample (ts)", {})
  nk.sql_exec("CREATE INDEX IF NOT EXISTS tm_error_fp ON tm_error (fingerprint, ts)", {})
  -- one row per issue (a fingerprint): how often, how many players, when, on which builds
  nk.sql_exec([[
    CREATE OR REPLACE VIEW tm_issue AS
    SELECT fingerprint, kind, source, min(message) AS message, min(at) AS at, sum(count) AS events,
      count(DISTINCT user_id) AS players, count(DISTINCT session) AS sessions, min(ts) AS first_seen,
      max(ts) AS last_seen, string_agg(DISTINCT build, ' ') AS builds, string_agg(DISTINCT zone, ' ') AS zones
    FROM tm_error GROUP BY fingerprint, kind, source]], {})
  -- (the role exists once deploy/staging/kpi_setup.sh has run; without it there's nothing to grant)
  pcall(nk.sql_exec, "GRANT SELECT ON tm_sample, tm_error, tm_issue TO grafana_ro", {})
end
local ok, err = pcall(setup_tables)
if not ok then
  nk.logger_error("telemetry tables: " .. tostring(err))
end

local function cut(v, n)
  if v == nil then return nil end
  return string.sub(tostring(v), 1, n)
end

local function num(v)
  if type(v) == "number" then return v end
  return nil
end

local function bool(v)
  if type(v) == "boolean" then return v end
  return nil
end

local function store(user_id, source, p)
  local session = cut(p.session, 64)
  local n = 0
  for i, s in ipairs(p.samples or {}) do
    if i > MAX_ROWS then break end
    nk.sql_exec([[INSERT INTO tm_sample (user_id, session, build, env, os, gpu, zone, run, class, level, x, z, preset,
        bg, enemies, boss, partners, dead, secs, fps_avg, fps_low1, frame_p99, hitches, vram_mb, res)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25)]], {
      user_id, session, cut(s.build, 40), cut(s.env, 20), cut(s.os, 40), cut(s.gpu, 120), cut(s.zone, 40), num(s.run),
      cut(s.class, 40), num(s.level), num(s.x), num(s.z), num(s.preset), bool(s.bg), num(s.enemies), bool(s.boss),
      num(s.partners), bool(s.dead), num(s.secs), num(s.fps_avg), num(s.fps_low1), num(s.frame_p99), num(s.hitches),
      num(s.vram_mb), cut(s.res, 20) })
    n = n + 1
  end
  for i, e in ipairs(p.errors or {}) do
    if i > MAX_ROWS then break end
    local c = type(e.context) == "table" and e.context or {}
    nk.sql_exec([[INSERT INTO tm_error (user_id, session, source, kind, fingerprint, message, at, count, build, env, zone,
        context, crumbs, tail)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::jsonb,$13::jsonb,$14)]], {
      user_id, cut(e.session, 64) or session, source, cut(e.kind, 20), cut(e.fingerprint, 32), cut(e.message, 500),
      cut(e.at, 300), num(e.count) or 1, cut(c.build, 40), cut(c.env, 20), cut(c.zone, 40),
      cut(nk.json_encode(c), 4000), cut(nk.json_encode(e.crumbs or {}), 12000), cut(e.tail, 8000) })
    n = n + 1
  end
  return nk.json_encode({ ok = true, rows = n })
end

local function telemetry(context, payload)
  if context.user_id == nil or context.user_id == "" then
    error({ "sign in first", 16 })
  end
  return store(context.user_id, "client", nk.json_decode(payload))
end

local function telemetry_server(context, payload)
  server_only(context)
  return store("server", "server", nk.json_decode(payload))
end

nk.register_rpc(telemetry, "telemetry")
nk.register_rpc(telemetry_server, "telemetry_server")

-- The Last Flame's leaderboard (Blaine: "tracks your wave ranking with a leaderboard added to the main title page";
-- scripts/flame_board.gd). Authoritative, so the generic leaderboard API can't write it: only flame_submit, which
-- keeps each account's best (score = waves held; subscore = 5 - party size, so a smaller party ranks above a bigger
-- one on the same wave). flame_top lists the best ten for the title's Hall of the Last Flame.
local FLAME = "last_flame"
local FLAME_MAX_WAVES = 1000
local okf, errf = pcall(nk.leaderboard_create, FLAME, true, "desc", "best", nil, {})
if not okf then
  nk.logger_info("last_flame leaderboard: " .. tostring(errf))
end

local function flame_submit(context, payload)
  if context.user_id == nil or context.user_id == "" then
    error({ "sign in first", 16 })
  end
  local p = nk.json_decode(payload)
  local waves = math.floor(num(p.waves) or -1)
  local party = math.floor(num(p.party) or 1)
  if waves < 1 or waves > FLAME_MAX_WAVES then
    error({ "waves out of range", 3 })
  end
  if party < 1 then party = 1 end
  if party > 4 then party = 4 end
  local name = string.gsub(cut(p.name, 24) or "", "[^%w%s'%-_]", "")
  if name == "" then name = "A hero" end
  local cls = string.gsub(cut(p.cls, 16) or "", "[^%w_]", "")
  nk.leaderboard_record_write(FLAME, context.user_id, name, waves, 5 - party, { cls = cls, party = party })
  return nk.json_encode({ ok = true, waves = waves })
end

local function flame_top(context, payload)
  if context.user_id == nil or context.user_id == "" then
    error({ "sign in first", 16 })
  end
  local p = nk.json_decode(payload ~= "" and payload or "{}")
  local limit = math.floor(num(p.limit) or 10)
  if limit < 1 then limit = 1 end
  if limit > 25 then limit = 25 end
  local records = nk.leaderboard_records_list(FLAME, nil, limit, nil, 0)
  local out = {}
  for i, r in ipairs(records or {}) do
    local md = r.metadata or {}
    out[#out + 1] = { rank = r.rank or i, name = r.username or "?", owner = r.owner_id, waves = r.score,
      party = md.party or (5 - (r.subscore or 4)), cls = md.cls or "" }
  end
  if #out == 0 then
    return '{"records":[]}'
  end
  return nk.json_encode({ records = out })
end

nk.register_rpc(flame_submit, "flame_submit")
nk.register_rpc(flame_top, "flame_top")
