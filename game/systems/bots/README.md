# Bot players (game/systems/bots/)

Bots in real online matches, for admins' testing (jj): on staging, the lobby list an admin sees always has a test
lobby of every mode one seat short, every other seat a bot. Joining it fills it and the match starts at once.

- **The lobby service** (`deploy/lobbies/service.py`, `--standing`, on in staging's unit) keeps them:
  - `STANDING` lists them: Battlegrounds solo and duo (4 seats), Arena 1v1, 2v2 and 3v3.
  - They exist on each admin's own build.
  - Their bot seats are members with `"bot": true`.
  - Only admins (Nakama's `admin_status`) see or join them.
  - A joined one is replaced on the next list.
- **The match server** (`match_bots.gd`, `MatchBots`) plays the bot seats.
  - Once the people have arrived, `MatchInstance` makes a hero for each seat at their level, run by the Sandbox's
    `BotBrain` (`game/maps/arena/bot_brain.gd`).
  - A bot sits in `Net.players` (`"bot": true`, a peer id from `BOT_PID`) and in `MatchInstance.members` with its
    team, so teams, PvP stand-ins, monsters' targets, rounds and the roster treat it as a player.
  - Its state goes out as `Net.cl_bot_state`, and its skills' fx as `Net.server_fx`.
  - Anything Net would send to a player reaches the bot's hero on the server instead (`Net.is_bot`): its hits
    (`Net.hit_player`), the raid's statuses and the Arena's round reset.
- **Tests:** `tests/bot_game.sh arena|duo <out>` runs the service, the match server and one admin client
  (`tests/bot_match_test.gd`): the lobby is one short, joining starts it, the bots are there and move; in the Arena
  the bot fights you, in a duo one bot is your pair. `deploy/lobbies/test_service.py` covers the standing lobbies.
