extends SceneTree
## Real queue sockets plus lifecycle/slot checks, without loading a game world.
var server
var peers: Array = []
var inbox := {}
var fails := 0
var mock := {"net": {"players": {}}, "difficulty": 0, "_busy": false}
func _initialize():
 call_deferred("run")
func check(ok: bool, label: String):
 print("[QUEUE] ", "ok " if ok else "FAIL ", label)
 if not ok: fails += 1
func wait_s(seconds: float):
 var until := Time.get_ticks_msec() + int(seconds * 1000)
 while Time.get_ticks_msec() < until:
  for p in peers:
   p.poll()
   while p.get_available_packet_count() > 0:
    inbox[p] = JSON.parse_string(p.get_packet().get_string_from_utf8())
  await process_frame
func until(condition: Callable, seconds := 4.0) -> bool:
 var end := Time.get_ticks_msec() + int(seconds * 1000)
 while not condition.call() and Time.get_ticks_msec() < end:
  await wait_s(0.05)
 return condition.call()
func connect_peer():
 var p := ENetMultiplayerPeer.new()
 p.create_client("127.0.0.1", 24779)
 peers.append(p)
 await until(func(): return p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)
 p.set_target_peer(1)
 p.put_packet(JSON.stringify({"v":1,"op":"join","max_act":0}).to_utf8_buffer())
 return p
func send(p, op: String, extra := {}):
 extra.merge({"v":1,"op":op})
 p.set_target_peer(1)
 p.put_packet(JSON.stringify(extra).to_utf8_buffer())
func run():
 Engine.max_fps = 120
 server = load("res://scripts/party_queue_server.gd").new()
 root.add_child(server)
 check(server.start(mock, 24779, 24770) == OK, "queue socket starts")
 var a = await connect_peer()
 await wait_s(0.7)
 check(inbox.get(a,{}).get("state","") == "queued", "one player waits without being transferred")
 var b = await connect_peer()
 await wait_s(0.8)
 check(inbox[a].state == "ready" and inbox[b].state == "ready", "two peers get the same ready check")
 check(inbox[a].match == inbox[b].match, "shared match id")
 check(server.free_slots() == 2, "ready check reserves two slots")
 send(a,"ready",{"match":"stale"})
 await wait_s(0.2)
 check(server.group.yes.is_empty(), "stale acceptance ignored")
 var match_id: String = inbox[a].match
 send(a,"ready",{"match":match_id})
 await until(func(): return inbox[a].get("accepted", false))
 check(inbox[a].state == "ready" and inbox[a].accepted, "one acceptance waits for partner")
 send(b,"cancel")
 await wait_s(0.7)
 check(inbox[a].state == "queued", "decline returns remaining player to search")
 peers.erase(b);b.close()
 b = await connect_peer()
 await wait_s(0.8)
 match_id = inbox[a].match
 send(a,"ready",{"match":match_id});send(b,"ready",{"match":match_id})
 await wait_s(0.7)
 check(inbox[a].state == "join" and inbox[b].state == "join", "both ready receive a destination")
 check(inbox[a].port == 24770 and inbox[a].ticket != inbox[b].ticket, "destination and separate one-time tickets")
 var ticket_a: String = inbox[a].ticket
 var ticket_b: String = inbox[b].ticket
 a.close();b.close();peers.clear()
 await wait_s(0.5)
 check(server.reservations.size() == 2, "reservations survive queue disconnect during handoff")
 mock.net.players = {10:{},11:{}}
 check(not server.admit(""), "direct joins cannot steal reserved slots")
 check(not server.admit("forged"), "unknown ticket refused")
 check(server.admit(ticket_a), "valid reservation admitted")
 mock.net.players[12] = {}
 check(not server.admit(ticket_a), "ticket replay refused")
 server.clock += 46
 check(not server.admit(ticket_b), "expired ticket refused")
 mock.net.players.clear()
 # AFK ready checks release nonresponders, preserving ready players.
 server.ready_secs = 1.8
 a = await connect_peer();b = await connect_peer()
 await wait_s(0.6)
 send(a,"ready",{"match":inbox[a].match})
 await until(func(): return inbox[a].state == "queued" and inbox[b].state == "expired", 5.0)
 check(inbox[a].state == "queued" and inbox[b].state == "expired", "AFK timeout requeues ready member and removes nonresponder")
 a.close();b.close();peers.clear()
 await wait_s(0.3)
 check(server.waiting.is_empty() and server.group.is_empty(), "disconnect clears queue and ready check")
 mock.difficulty = 1
 a = await connect_peer();b = await connect_peer()
 await wait_s(0.7)
 check(inbox[a].state == "queued" and inbox[b].state == "queued", "locked act is never offered")
 for p in peers:p.close()
 peers.clear()
 server.queue_free()
 await process_frame
 print("[QUEUE] done ", fails, " failures")
 quit(1 if fails else 0)
