extends Node
## Lobby discovery stays separate from the active game connection.
var game
var panel
var rows
var detail
var status
var team_pick
var mode_buttons := {}
var solo_button: Button
var create_button
var rules: Label
var wager_pick
var item_pick
var stake_store = load("res://scripts/lobby_stakes.gd")
var selected_mode := "arena"
var team_size := 1
var room := {}
var rooms := []
var match_id := ""
var character := ""
## The overhaul (2026-11-06): a Battlegrounds member brings a class (a fresh run character, "run_<class>"), an Arena
## member a saved survivor (Survivors); single-player characters stay out of multiplayer.
var run_class := "archer"
var survivor := ""
var prep_box: VBoxContainer
var class_pick: OptionButton
var survivor_btn: Button
var survivor_lbl: Label
## The classes a run can start as (the class screen's order).
static func run_classes() -> Array:
 # (a run needs five skills to find: the Obsidian Wyrm has only the four shared ones until it gets its own kit)
 return ClassStage.CLASSES.filter(func(c): return Data.CLASSES.has(c) and RunBuild.skill_pool(c).size() >= RunBuild.SLOTS.size())
var busy := false
var polling := false
var poll_t := 0.0
var auth := ""
var identity := ""
var arena_hud: Label
var _returning := false
var admitted := false
var host_box: VBoxContainer
var view: MpLobbyView
## The lobby list's state for the view: the last request's error, and whether a list has arrived yet.
var last_error := ""
## A match that ended on the player (disconnected, closed): shown once on the multiplayer screen.
var notice := ""
var loaded := false
## After Start (Blaine, 2026-11-06: "a visible countdown when we click start"): while the match's server boots the
## lobby shows how long it has been starting; once it listens, everyone counts GO_SECS down together and goes in.
const GO_SECS := 3.0
var start_seen_ms := 0         # when this lobby was first seen "starting"
var go_t := -1.0               # the countdown to entering, once the server listens
var start_label: Label         # MpLobbyView's big line, updated every frame without a redraw
## The list's columns: title, width.
const COLUMNS := [["MODE", 130], ["LOBBY", 190], ["HOST", 140], ["FORMAT", 120], ["PLAYERS", 80], ["STATUS", 90]]

func setup(g) -> void:
 game=g
 var ui=game.ui
 # the screen (Blaine's overhaul, 2026-11-06): MpLobbyView draws it; this keeps the logic
 view=MpLobbyView.new();ui.menus.add_child(view);view.visible=false;panel=view
 # (controls the logic reads, never shown: the view draws its own)
 var hidden:=Control.new();hidden.name="logic";hidden.visible=false;view.add_child(hidden)
 host_box=VBoxContainer.new();hidden.add_child(host_box)
 detail=VBoxContainer.new();hidden.add_child(detail)
 rules=Label.new();hidden.add_child(rules)
 team_pick=OptionButton.new()
 for n in [1,2,3]:team_pick.add_item("%dv%d"%[n,n],n)
 team_pick.item_selected.connect(func(i):team_size=team_pick.get_item_id(i))
 hidden.add_child(team_pick)
 wager_pick=CheckButton.new();hidden.add_child(wager_pick)
 create_button=Button.new();hidden.add_child(create_button)
 _build_prep(ui)
 view.setup(self)
 arena_hud=ui._label("",23,ui.GOLD,true)
 arena_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
 arena_hud.offset_top=70;arena_hud.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 arena_hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
 ui.hud.add_child(arena_hud)

## What a member brings: the class for a Battlegrounds run, the survivor for the Arena. Shown on the right while
## hosting and in a lobby.
func _build_prep(ui) -> void:
 prep_box=VBoxContainer.new();prep_box.name="prep";prep_box.add_theme_constant_override("separation",6)
 var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10);prep_box.add_child(row)
 row.add_child(ui._label("Class:",15,ui.DIM))
 class_pick=OptionButton.new();class_pick.name="class_pick";class_pick.custom_minimum_size.x=220
 for c in run_classes():class_pick.add_item(str(Data.CLASSES[c]["name"]))
 class_pick.item_selected.connect(func(i):run_class=str(run_classes()[i]);game._save_setting("battlegrounds","class",run_class))
 row.add_child(class_pick)
 var row2:=HBoxContainer.new();row2.add_theme_constant_override("separation",10);prep_box.add_child(row2)
 survivor_lbl=ui._label("",15,ui.GOLD);survivor_lbl.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;survivor_lbl.custom_minimum_size.x=250;row2.add_child(survivor_lbl)
 survivor_btn=ui._iron_button("Survivors",140,40,16);survivor_btn.name="survivors";survivor_btn.pressed.connect(func():ui.run_ui.open_roster(func(id):survivor=id;draw(),survivor));row2.add_child(survivor_btn)
 var saved=game._load_setting("battlegrounds","class","archer") if game.has_method("_load_setting") else "archer"
 if run_classes().has(str(saved)):run_class=str(saved)
 host_box.get_parent().add_child(prep_box)     # (between hosting and the lobby's own detail: there in both)
 class_pick.select(maxi(0,run_classes().find(run_class)))

## The member's character for the lobby service: "run_<class>" in Battlegrounds, the survivor's id in the Arena.
func member_character(mode := "") -> String:
 if mode=="":mode=str(room.get("mode",selected_mode))
 if mode=="sandbox":return "sandbox_"+run_class
 if mode=="arena":return survivor
 return "run_"+run_class

func member_name(mode := "") -> String:
 if mode=="":mode=str(room.get("mode",selected_mode))
 if mode=="arena":
  var d:Dictionary=Survivors.read(survivor)
  return str(d.get("name","Survivor")) if not d.is_empty() else "Survivor"
 return str(Data.CLASSES.get(run_class,{}).get("name","Adventurer"))

func _draw_prep() -> void:
 if prep_box==null:return
 var mode:=str(room.get("mode",selected_mode))
 class_pick.get_parent().visible=mode in ["battlegrounds","sandbox"]
 class_pick.disabled=not room.is_empty()
 survivor_btn.get_parent().visible=mode=="arena"
 survivor_btn.disabled=not room.is_empty()
 if mode=="arena":
  if Survivors.read(survivor).is_empty():survivor=""
  var all:Array=Survivors.list()
  if survivor=="" and not all.is_empty():survivor=str(all[0]["id"])
  survivor_lbl.text=("Survivor: %s (%s)"%[member_name("arena"),Survivors.summary(Survivors.read(survivor))]) if survivor!="" else "No survivors yet: bring one out of a Battlegrounds run alive and press Save Character."

func open(mode := "") -> void:
 if game.net.server:return
 if game.playing and game.net.active:
  game.ui.message("Leave your current game before joining another lobby.");return
 if room.get("members",{}).has(identity):character=str(room.members[identity].character)
 if mode!="":selected_mode=mode
 if not MpMode.mode_on(selected_mode):selected_mode=MpMode.MODES[0]
 game.ui.close_all();panel.show();draw();refresh()
 if not game.playing:recover_stakes()

func url() -> String:
 return str(BuildEnv.value("lobby_url")).trim_suffix("/")
func request(op: String,p: Dictionary) -> Dictionary:
 if game.cloud!=null:
  if not await game.cloud.ensure():return {"error":"Could not sign in. Try again."}
  auth="Bearer "+game.cloud.nk.token;identity=game.cloud.nk.user_id
 elif auth=="":
  if url().begins_with("http://127.0.0.1:"):
   auth="Bearer dev-"+Battlegrounds.client_id()
   identity=auth.sha256_text().substr(0,24)
  else:return {"error":"Sign in to use online lobbies."}
 var req:=HTTPRequest.new();req.timeout=8;add_child(req)
 var body:=p.duplicate();body["op"]=op;body["version"]=BuildEnv.value("rev")
 var err:=req.request(url()+"/lobbies",PackedStringArray(["Content-Type: application/json","Authorization: "+auth]),HTTPClient.METHOD_POST,JSON.stringify(body))
 if err!=OK:req.queue_free();return {"error":"Lobby service unavailable."}
 var result:Array=await req.request_completed;req.queue_free()
 var decoder:=JSON.new()
 var data=null
 if int(result[0])==HTTPRequest.RESULT_SUCCESS and decoder.parse((result[3] as PackedByteArray).get_string_from_utf8())==OK:
  data=decoder.data
 if game.cloud!=null and data is Dictionary and data.get("error","")=="Your session expired. Sign in again.":
  game.cloud.signed_in=false # The next request renews the existing device session.
 return data if data is Dictionary else {"error":"Lobby service unavailable. Your current game is unchanged."}

func action(op: String,extra := {}) -> void:
 if busy:return
 busy=true
 var args:Dictionary=extra.duplicate()
 if not args.has("id"):args["id"]=str(room.get("id",""))
 var mode_for:=str(args.get("mode",room.get("mode",selected_mode)))
 character=member_character(mode_for)
 if character=="" and op in ["create","join"]:
  status.text="Choose a survivor first: Arena fights use characters saved from the Battlegrounds."
  busy=false;return
 args["character"]=character
 args["player"]=member_name(mode_for)
 var result:Dictionary=await request(op,args)
 if result.has("error"):status.text=str(result.error)
 elif result.has("lobby"):
  room={} if op=="leave" else result.lobby
  status.text="";draw()
 busy=false
 await refresh()

func refresh() -> void:
 if polling:return
 polling=true
 var result:Dictionary=await request("list",{})
 if result.has("error"):status.text=str(result.error);last_error=str(result.error)
 else:rooms=result.get("lobbies",[]);last_error="";loaded=true
 if not room.is_empty():
  var requested_id:String=str(room.id)
  var current:Dictionary=await request("get",{"id":requested_id})
  if current.has("lobby") and str(room.get("id",""))==requested_id:
   room=current.lobby
   if str(room.state)=="waiting":
    var pending:Dictionary=stake_store.finish_removal(game,str(room.id))
    if not pending.is_empty():await request("stake",{"id":room.id,"item":pending.item})
   if str(room.state) in ["starting","playing"] and str(room.get("address",""))!="" and match_id=="" and go_t<0.0:go_t=GO_SECS
   elif str(room.state) in ["aborted","finished","closed"] and match_id=="":status.text=str(room.get("reason","Lobby closed."));room={}
 draw();polling=false

func draw() -> void:
 if not room.is_empty():
  selected_mode=str(room.mode)
  team_size=int(room.get("team_size",1));team_pick.select(team_size-1)
  wager_pick.button_pressed=bool(room.get("wager",false))
  var mine:Dictionary=room.members.get(identity,{})
  var ch:=str(mine.get("character",""))
  if ch.begins_with("run_") and run_classes().has(ch.trim_prefix("run_")):run_class=ch.trim_prefix("run_")
  elif ch.begins_with("sandbox_") and run_classes().has(ch.trim_prefix("sandbox_")):run_class=ch.trim_prefix("sandbox_")
  elif Survivors.is_survivor(ch):survivor=ch
 if not MpMode.mode_on(selected_mode):selected_mode=MpMode.MODES[0]
 _draw_prep()
 if view!=null and view.visible:view.render()

const MODE_NAMES := {"battlegrounds": "Battlegrounds", "waves": "Endless Waves", "arena": "Arena", "sandbox": "Sandbox"}

## One row of the list: its columns and a Join button.
func _row(cells: Array, joinable: bool, join: Callable) -> Control:
 var ui=game.ui
 var p:=PanelContainer.new()
 p.add_theme_stylebox_override("panel",ui._box(Color(0.07,0.055,0.04,0.92),Color(0.32,0.25,0.15),1,3,6))
 var h:=HBoxContainer.new();h.add_theme_constant_override("separation",8);p.add_child(h)
 for i in cells.size():
  var l=ui._label(str(cells[i]),16 if i>0 else 15,ui.GOLD if i==0 else Color(0.9,0.85,0.76))
  l.custom_minimum_size.x=float(COLUMNS[i][1]);l.clip_text=true;h.add_child(l)
 var j=ui._iron_button("Join",110,38,16);j.disabled=not joinable;j.pressed.connect(join);h.add_child(j)
 return p

func _format(r: Dictionary) -> String:
 match str(r.mode):
  "arena":return "%dv%d%s"%[int(r.team_size),int(r.team_size)," · items" if bool(r.get("wager",false)) else ""]
  "battlegrounds":return "%s · %d max"%["Duo" if int(r.get("team_size",1))==2 else "Solo",int(r.capacity)]
  "waves":return "Co-op · %d max"%int(r.capacity)
  "sandbox":return "Practice · %d max"%int(r.capacity)
 return ""

## A new lobby's name: the host's character.
func _lobby_name() -> String:
 return "%s's %s"%[member_name(selected_mode),MODE_NAMES.get(selected_mode,"game")]
 return "Adventurers"

func enter_match() -> void:
 match_id=str(room.id)
 admitted=false
 character=str(room.members[identity].character)
 game.save_game()
 game.party_join_ticket=str(room.ticket)
 panel.hide()
 if str(room.mode)=="sandbox":
  await game.start_sandbox_join(str(room.address),character)
 elif str(room.mode)=="battlegrounds":
  await game.start_battlegrounds(str(room.address),"",character.trim_prefix("run_") if character.begins_with("run_") else run_class)
 else:
  game.arena_mode=str(room.mode)=="arena"
  await game.start_join(str(room.address),character)
  if game.arena_mode:game.hero.recalc()

func play_solo() -> void:
 if busy or game._busy or not room.is_empty():return
 if selected_mode=="sandbox":
  panel.hide()
  await game.open_sandbox(run_class)

func finished(reason: String) -> void:
 if _returning:return
 _returning=true
 print("[LOBBY] Match ended: ",reason)
 game.ui.big_message(reason)
 await get_tree().create_timer(4).timeout
 game.net.shutdown()
 if game.arena_mode and game.sandbox==null:
  game.arena_mode=false;game.arena_state={};game.load_game()
 elif game.bg_mode:
  if admitted:game.bg_strip()
  game.bg_mode=false
  if not admitted:game.load_game()
 match_id="";room={}
 var was_run:bool=game.hero!=null and game.hero.run!=null
 await game.exit_to_title()
 if was_run:game.hero.new_character() # (a run cut off by a lost connection is over: nothing of it is kept)
 await collect()
 game.ui.message(reason)
 _returning=false
 # back on the multiplayer screen with the mode and class or survivor chosen before, saying what happened
 open(selected_mode)
 notice=reason+(" The run was lost with the connection." if was_run else "")
 draw()

func _process(delta: float) -> void:
 if game==null:return
 arena_hud.visible=game.arena_mode and game.sandbox==null and not game.ui.any_panel_open()
 if game.arena_mode:
  var s:Dictionary=game.arena_state
  var score:Array=s.get("scores",[0,0])
  arena_hud.text="ARENA · Round %d · Ember %d — %d Frost · %s · %ds"%[int(s.get("round",1)),score[0],score[1],str(s.get("phase","waiting")).capitalize(),int(s.get("left",0))]
 _start_countdown(delta)
 poll_t-=delta
 if poll_t<=0 and (panel.visible or not room.is_empty()):poll_t=1.0 if str(room.get("state",""))=="starting" else 3.0;refresh()

## The start's visible countdown (see GO_SECS): the server's boot time, then 3 · 2 · 1, then in.
func _start_countdown(delta: float) -> void:
 var starting:=not room.is_empty() and str(room.get("state","")) in ["starting","playing"] and match_id==""
 if not starting:
  start_seen_ms=0;go_t=-1.0;return
 if start_seen_ms==0:start_seen_ms=Time.get_ticks_msec()
 if go_t>=0.0:
  go_t-=delta
  if go_t<=0.0:
   go_t=-1.0
   if start_label!=null and is_instance_valid(start_label):start_label.text="Entering..."
   enter_match()
   return
 if start_label!=null and is_instance_valid(start_label):start_label.text=start_text()

func start_text() -> String:
 if go_t>=0.0:return "Match starts in %d" % ceili(go_t)
 var s:=int((Time.get_ticks_msec()-start_seen_ms)/1000)
 return "Starting the server...  %d:%02d" % [s/60,s%60]

func commit_stake() -> void:
 if busy or room.is_empty() or item_pick.item_count==0:return
 if game.playing:game.save_game()
 var index:int=item_pick.get_selected_id()
 var item_name:String=item_pick.get_item_text(item_pick.selected)
 var inventory:Array=stake_store.read(game.char_dir+character+".json").get("hero",{}).get("inventory",[])
 if index<0 or index>=inventory.size() or not inventory[index] is Dictionary:return
 var expected:Dictionary=inventory[index].duplicate(true)
 game.ui.open_dialog("Play for Items", "Lock %s as your stake? You cannot use or trade it while this lobby is active. If your team loses, the other team receives it. Cancelling before the match refunds it." % item_name, [["Lock Item",func():_commit_stake(index,expected)],["Cancel",func():pass]])
func _commit_stake(index: int,expected := {}) -> void:
 if busy or room.is_empty() or str(room.state)!="waiting":return
 if not expected.is_empty():
  if game.playing:game.save_game()
  var inventory:Array=stake_store.read(game.char_dir+character+".json").get("hero",{}).get("inventory",[])
  if index<0 or index>=inventory.size() or inventory[index]!=expected:
   status.text="That item changed. Select your stake again.";return
 var entry:Dictionary=stake_store.prepare(game,str(room.id),character,index)
 if entry.is_empty():status.text="Could not save the item stake.";return
 await action("stake",{"item":entry.item})
func collect() -> void:
 if game.playing:status.text="Return to the home screen to collect arena items safely.";return
 var result:Dictionary=await request("receipts",{})
 var count:=0
 for receipt in result.get("receipts",[]):
  if stake_store.apply(game,receipt):
   await request("ack",{"receipt":receipt.id});count+=1
 if count>0:status.text="Collected %d arena result(s). Pending items wait here if your bag is full."%count

func recover_stakes() -> void:
 # A cancelled/expired lobby cannot later accept this offer. Recover only after an explicit service response.
 var journal:Dictionary=stake_store.read(stake_store.journal_path(game))
 for id in journal:
  var entry:Dictionary=stake_store.finish_removal(game,id)
  if entry.is_empty():continue
  var result:Dictionary=await request("get",{"id":id})
  if not result.has("lobby"):continue
  var r:Dictionary=result.lobby
  var member:Dictionary=r.members.get(identity,{})
  if r.state=="waiting" and not member.is_empty():
   room=r
   await request("stake",{"id":id,"item":entry.item})
  elif member.get("stake",{}).is_empty():
   stake_store.apply(game,{"id":id+":"+identity,"character":entry.character,"items":[entry.item]})
 await collect()

func join_lobby(id: String,mode: String) -> void:
 if mode=="battlegrounds":
  game.ui.open_dialog("Battlegrounds", "You join as a fresh %s at level 0. Joining an active raid enters immediately. Nothing of your single-player characters is at risk." % member_name("battlegrounds"), [["Join Lobby",func():action("join",{"id":id})],["Cancel",func():pass]])
 else:action("join",{"id":id})
