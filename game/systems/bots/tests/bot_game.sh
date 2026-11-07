#!/bin/bash
# bot_game.sh <arena|duo> <outdir> [broker_port] [worker_port]: the lobby service (dev, --standing) on loopback, the match
# server it launches, and one admin client (bot_match_test.gd) joining a standing lobby. Run from the repo root.
mode=$1; out=$2; bp=${3:-7461}; wp=${4:-24711}
G=/Users/blaine/Applications/Godot_v4.4.1.app/Contents/MacOS/Godot
mkdir -p "$out/state"
python3 deploy/lobbies/service.py --dev --standing --state "$out/state" --game . --godot "$G" --port $bp --first-port $wp --ports 1 --slots 1 > "$out/broker.log" 2>&1 &
b=$!
for i in $(seq 1 40); do nc -z 127.0.0.1 $bp 2>/dev/null && break; sleep 0.25; done
"$G" --headless --path . -s tools/_late.gd -- $mode res://game/systems/bots/tests/bot_match_test.gd --broker http://127.0.0.1:$bp > "$out/client.log" 2>&1 &
c=$!
for i in $(seq 1 420); do kill -0 $c 2>/dev/null || break; sleep 1; done
kill $c 2>/dev/null; sleep 2
pkill -f "port $wp" 2>/dev/null; kill $b 2>/dev/null
