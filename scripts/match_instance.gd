extends Node
## One disposable game world owned by the lobby service. Admission tokens are redeemed once on loopback.
var game
var config := {}
var members := {} # peer -> authenticated member
var elapsed := 0.0
var begun := false
var ending := false
var announced := false
var empty_t := 0.0
var report_t := 0.0

func start(g, path: String, port: int) -> void:
 game=g
 var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
 if not parsed is Dictionary or not parsed.has("worker_key"):
  get_tree().quit(2);return
 config=parsed
 game.net.server=true
 game.test_immortal=true
 game.playing=true
 game.ui.hide_title()
 Engine.max_fps=30
 var mode: String=str(config.mode)
 if mode=="battlegrounds":
  await Battlegrounds.start_server(game,port)
 elif mode=="arena":
  game.bg=load("res://scripts/arena_match.gd").new()
  game.bg.game=game
  game.add_child(game.bg)
  game.net.host(port,int(config.capacity))
  await game.load_zone(0,"arena","start")
 else:
  game.coop_server=CoopServer.new()
  game.coop_server.game=game
  game.add_child(game.coop_server)
  game.net.coop_server=true
  game.net.host(port,int(config.capacity))
  await game.load_zone(0,Vigil.ZONE,"start")
 await request("listening",{})
 announced=true

func request(op: String, args: Dictionary) -> Dictionary:
 var req:=HTTPRequest.new()
 req.timeout=8
 add_child(req)
 var body:=args.duplicate()
 body["op"]=op;body["id"]=config.id
 var err:=req.request(str(config.broker)+"/worker",PackedStringArray(["Content-Type: application/json","X-Worker-Key: "+str(config.worker_key)]),HTTPClient.METHOD_POST,JSON.stringify(body))
 if err!=OK:
  req.queue_free();return {}
 var result:Array=await req.request_completed
 req.queue_free()
 if int(result[0])!=HTTPRequest.RESULT_SUCCESS or int(result[1])!=200:return {}
 var decoder:=JSON.new()
 if decoder.parse((result[3] as PackedByteArray).get_string_from_utf8())!=OK:return {}
 var data=decoder.data
 return data if data is Dictionary else {}

func admit(pid: int, ticket: String) -> bool:
 if ending or members.has(pid):return false
 var member: Dictionary=await request("redeem",{"ticket":ticket})
 if not member.has("user") or not game.net.active or not game.net.multiplayer.get_peers().has(pid):return false
 for other in members.values():
  if other.user==member.user:return false
 members[pid]=member
 if game.bg!=null:
  game.bg.uids[pid]="nk:"+str(member.user)
  game.bg.carried[pid]=[]
  if game.bg.nk!=null:
   var role:Dictionary=await game.bg.nk.server_rpc("admin_check",{"user_id":member.user},game.bg.nk_key)
   game.bg.admins[pid]=bool(role.get("admin",false))
 return true

func spawn(pid: int) -> Vector3:
 if str(config.mode)=="arena":
  var team:=int(members.get(pid,{}).get("team",0))
  var peers:Array=members.keys().filter(func(peer):return int(members[peer].team)==team)
  return Vector3(-12 if team==0 else 12,0,(peers.find(pid)-(int(config.team_size)-1)*0.5)*5)
 if game.bg!=null:return game.bg.spawn_point()
 return game.world.free_spot_near(game.world.spawns.get("start",Vector3.ZERO),2)

func left(pid: int) -> void:
 # Keep match membership for team results; release the account to browse other lobbies.
 if members.has(pid):request("depart",{"user":members[pid].user})
 if not begun and not ending: finish("aborted","A player disconnected before the match began.")

func _process(delta: float) -> void:
 if not announced or ending or game.world==null or game._busy:return
 elapsed+=delta
 if game.bg!=null:game.bg.park_hero()
 elif game.coop_server!=null:game.coop_server.park_hero()
 report_t-=delta
 if begun and report_t<=0:
  report_t=10
  request("state",{"state":"playing","joinable":str(config.mode)=="waves" or (str(config.mode)=="battlegrounds" and game.bg.raid_t<Battlegrounds.JOIN_CLOSE)})
 if not begun:
  if report_t<=0:
   report_t=10
   print("[MATCH] Waiting for arrivals: ",game.net.players.size(),"/",config.members.size(),"; states=",game.net.players.values().map(func(row):return row.hero.net_has))
  var expected:int=config.members.size()
  var ready:bool=game.net.players.size()==expected
  for row in game.net.players.values():
   ready=ready and row.hero.net_has
  if ready:
   begun=true
   await request("state",{"state":"playing"})
   if str(config.mode)=="arena":game.bg.begin_round()
   elif str(config.mode)=="waves":game.world.get_meta("vigil").begin()
   else:game.bg.raid_t=0;game.bg.start_prep("")
  elif elapsed>120:finish("aborted","Players did not arrive in time.")
 else:
  empty_t=empty_t+delta if game.net.players.is_empty() else 0.0
  if empty_t>10:finish("finished","Everyone has left.")
  if str(config.mode)=="battlegrounds" and game.bg.state=="reset":finish("finished","The raid has ended.")
  elif str(config.mode)=="waves" and game.world.get_meta("vigil").state=="lost":finish("finished","The Last Flame has fallen.")

func finish(state: String, reason: String, winner := -1) -> void:
 if ending:return
 ending=true
 print("[MATCH] ",state,": ",reason)
 await request("state",{"state":state,"reason":reason,"winner":winner})
 if game.net.active and not game.net.players.is_empty():game.net.rpc("cl_match_end",reason)
 # Deliver the result, then close from the server before clients all leave simultaneously.
 # This also stops ENet relaying snapshots into peers whose channels are already gone.
 await get_tree().create_timer(2).timeout
 game.net.shutdown(true)
 await get_tree().create_timer(10).timeout
 var tree:=get_tree()
 Hero.striker=null
 tree.create_timer(0.5).timeout.connect(tree.quit)
 game.queue_free()
