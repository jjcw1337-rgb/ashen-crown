# Multiplayer authority (audit, 2026-11-06)

Who decides what, today, in the three arrangements: **(a)** player-hosted co-op (the host player's game: ENet
LAN/direct or Steam, `Net.is_host`), **(b)** dedicated Battlegrounds/Arena matches (a headless worker the lobby
service starts per lobby, `deploy/lobbies/service.py`, `scripts/match_instance.gd`), the always-on co-op server
that was **(c)** here is gone (2026-11-06).

The **lobby owner** (`service.py` `r['owner']`) only presses Start and is reassigned if they leave; the **match**
runs on the worker, which alone reports the result (per-match `worker_key`, loopback only). So the lobby/UI is
already compatible with "players create sessions, trusted infrastructure runs them". What the worker trusts, though,
is mostly the clients.

| System | Who decides | Key code | Gap |
|---|---|---|---|
| Movement | each client, all arrangements | `Net.pl_state` → `Hero.apply_net_state` (snaps if >6 m off) | no speed/teleport check; every range check (extraction, pickup, PvP, stash, chopping) uses the client's position |
| Damage to monsters | client computes; host applies | `Enemy.take_damage` → `Net.sv_enemy_hit` | amount, crit, target unchecked (no range/rate); `sv_enemy_stun` unclamped |
| Damage to players (monsters) | host decides the hit; the victim's client applies it | `Net.cl_take_hit`, life back via `pl_state` | a modified client ignores hits |
| PvP damage (b) | attacker's client | `Net.sv_pvp_hit` → `Battlegrounds.pvp_pair` (raid on, both alive, ≤30 m), clamp 0-5000 | no rate limit; amount trusted within the clamp |
| Cooldowns, mana | client | `Hero.cds` | never validated by any server |
| Enemy deaths, loot rolls | host / worker | `Enemy._die` → `Game.on_enemy_killed`, `_drop_loot_roll` | but client-reported damage can kill anything |
| Experience | host triggers, client computes and stores | `Net.share_xp` → `cl_xp` → `Hero.add_xp` | no zone/distance filter; local save |
| Ground item pickup | host, first come | `Net.sv_pickup` → `cl_grant` | no distance/ownership check; gold scaled by the client's own stat |
| Item creation | host spawns what a client sends | `Net.sv_drop` | **a client can create any item** |
| BG carried items, death | client save is the truth; server list is advisory | `carried`, `Net.sv_bg_died` (drops the client's list, ≤80, no death check), `Game.bg_strip` (client) | **`sv_bg_died` also creates items** and can wipe the server's record |
| BG extraction | client keeps what it holds | `Net.sv_extract` (distance on client position) → local save | nothing server-side records the extracted items |
| BG stash | client/Nakama-writable collections | `cloud_saves.gd` (`characters`, `stash`); the server-only stash RPCs in `ashen.lua` are unused | player-writable |
| Arena result | worker, from client-reported life/death | `arena_match.gd`, `service.py` `settle` | client-reported life decides the winner |
| Arena stakes | client-submitted item dicts | `service.py` stake op, `lobby_stakes.gd` (local escrow, self-described "not an anti-cheat boundary") | ownership never proven |
| Character saves | client (local JSON + a Nakama copy the player can write) | `Game.save_game`, `CloudSaves.sync` (newest `played` wins) | contents never checked; only the character id is matched to the lobby ticket |

`any_peer` RPCs that change host/server state without real checks: `sv_enemy_hit`, `sv_enemy_stun`, `sv_drop`,
`sv_pickup`, `sv_bg_died`, `sv_pvp_hit` (clamped only), `pl_state`, `pl_gear`, `sv_travel` (skips the party vote),
`sv_portal`, `sv_bg_hello`'s uid without Nakama, `cl_team_buff` (unclamped duration). Reasonably guarded: `sv_chop`,
`sv_inter`, `sv_switch`, `sv_vote_cancel`, `sv_bg_admin`, `sv_bg_stash` (range on client position).

## What this means

- **Nothing about Battlegrounds or Arena progression is verified today.** Survivors built from client saves, or
  results from client-reported combat, must not be described as trustworthy. Fine for development and friends.
- **Player-hosted co-op (a)** gives the host's PC full authority (loot, XP, enemies): acceptable for friends, but
  its characters must not feed Battlegrounds/Arena survivors.

## What developer-controlled outcomes would need (recommended, not built)

1. **Server-owned run state**: the Battlegrounds worker keeps each run character's level, skills, passives, gear and
   consumables itself (granted by its own reward rolls), and at a successful exit writes the survivor to Nakama with a
   server key (a collection players can read but not write). Arena workers load survivors from there, never from the
   client.
2. **Server-side combat validation**: damage from skills the server knows the player has, within cooldowns, range and
   a per-second budget; incoming damage applied by the server; positions checked for speed.
3. **Remove item creation by clients**: `sv_drop` only for items the server knows the player holds; `sv_bg_died`
   drops the server's own record.
4. **Escrow on the server** for Arena stakes (items held in the server-written survivor record).
