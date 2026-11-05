extends Node
## Lobby discovery stays separate from the active game connection.
var game
var panel
var rows
var detail
var status
var team_pick
var mode_buttons := {}
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
var busy := false
var polling := false
var poll_t := 0.0
var auth := ""
var identity := ""
var arena_hud: Label
var _returning := false
var admitted := false

func setup(g) -> void:
 game=g
 var ui=game.ui
 panel=PanelContainer.new()
 panel.name="multiplayer_lobbies"
 ui._ornate(panel,0.3,18)
 ui.menus.add_child(panel)
 panel.visible=false
 var vb:=VBoxContainer.new();vb.add_theme_constant_override("separation",12);panel.add_child(vb)
 var heading=ui._label("MULTIPLAYER",36,ui.GOLD,true);vb.add_child(heading)
 vb.add_child(ui._label("Create a lobby, gather your party, then start when everyone is ready.",16))
 var cards:=HBoxContainer.new();cards.add_theme_constant_override("separation",12);vb.add_child(cards)
 for entry in [["battlegrounds","BATTLEGROUNDS\nThe Hollow Crypt"],["waves","ENDLESS WAVES\nThe Last Flame"],["arena","ARENA\n1v1 · 2v2 · 3v3"]]:
  var id:String=entry[0]
  var b=ui._iron_button(entry[1],300,90,20)
  b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  b.pressed.connect(func():selected_mode=id;draw())
  cards.add_child(b);mode_buttons[id]=b
 rules=ui._label("",16,ui.GOLD);rules.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;vb.add_child(rules)
 var options:=HBoxContainer.new();vb.add_child(options)
 team_pick=OptionButton.new()
 for n in [1,2,3]:team_pick.add_item("%dv%d"%[n,n],n)
 team_pick.item_selected.connect(func(i):team_size=team_pick.get_item_id(i))
 options.add_child(team_pick)
 wager_pick=CheckButton.new();wager_pick.text="Play for items";options.add_child(wager_pick)
 var create=ui._iron_button("Create Lobby",220,48,20);create.pressed.connect(func():action("create",{"mode":selected_mode,"team_size":team_size,"name":"Adventurers","wager":wager_pick.button_pressed}));options.add_child(create);create_button=create
 var solo=ui._iron_button("Play Waves Solo",240,48,20);solo.pressed.connect(play_solo_waves);options.add_child(solo)
 status=ui._label("",15,ui.GOLD);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;vb.add_child(status)
 var scroll:=ScrollContainer.new();scroll.custom_minimum_size.y=160;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;vb.add_child(scroll)
 rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(rows)
 detail=VBoxContainer.new();vb.add_child(detail)
 var claim=ui._iron_button("Collect Arena Rewards",280,42,18);claim.pressed.connect(collect);vb.add_child(claim)
 var back=ui._iron_button("Back",160,46,18);back.pressed.connect(func():panel.hide());vb.add_child(back)
 panel.minimum_size_changed.connect(fit.call_deferred)
 get_viewport().size_changed.connect(fit)
 fit.call_deferred()
 arena_hud=ui._label("",23,ui.GOLD,true)
 arena_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
 arena_hud.offset_top=70;arena_hud.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 arena_hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
 ui.hud.add_child(arena_hud)

func fit() -> void:
 panel.size=Vector2(1040,710)
 var available:=get_viewport().get_visible_rect().size
 var factor:=minf(1,minf((available.x-32)/panel.size.x,(available.y-32)/panel.size.y))
 panel.scale=Vector2.ONE*factor;panel.pivot_offset=panel.size*0.5;panel.position=(available-panel.size)*0.5

func open(mode := "") -> void:
 if game.net.server:return
 if game.playing and game.net.active:
  game.ui.message("Leave your current game before joining another lobby.");return
 character=game.char_id if game.playing else game.ui.home.sel
 if room.get("members",{}).has(identity):character=str(room.members[identity].character)
 if character=="":game.ui.message("Create or select a character first.");return
 if mode!="":selected_mode=mode
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
 args["character"]=character
 var chars:Array=game.list_characters()
 for c in chars:
  if str(c.id)==character:args["player"]=str(c.get("name","Adventurer"))
 var result:Dictionary=await request(op,args)
 if result.has("error"):status.text=str(result.error)
 elif result.has("lobby"):
  room={} if op=="leave" else result.lobby
  if op in ["create","join"] and game.party_queue!=null:game.party_queue.stop()
  status.text="";draw()
 busy=false
 await refresh()

func refresh() -> void:
 if polling:return
 polling=true
 var result:Dictionary=await request("list",{})
 if result.has("error"):status.text=str(result.error)
 else:rooms=result.get("lobbies",[])
 if not room.is_empty():
  var requested_id:String=str(room.id)
  var current:Dictionary=await request("get",{"id":requested_id})
  if current.has("lobby") and str(room.get("id",""))==requested_id:
   room=current.lobby
   if str(room.state)=="waiting":
    var pending:Dictionary=stake_store.finish_removal(game,str(room.id))
    if not pending.is_empty():await request("stake",{"id":room.id,"item":pending.item})
   if str(room.state) in ["starting","playing"] and str(room.get("address",""))!="" and match_id=="":enter_match()
   elif str(room.state) in ["aborted","finished","closed"] and match_id=="":status.text=str(room.get("reason","Lobby closed."));room={}
 draw();polling=false

func draw() -> void:
 if not room.is_empty():
  selected_mode=str(room.mode)
  team_size=int(room.get("team_size",1));team_pick.select(team_size-1)
  wager_pick.button_pressed=bool(room.get("wager",false))
 team_pick.disabled=not room.is_empty();wager_pick.disabled=not room.is_empty()
 var selected_item:int=item_pick.get_selected_id() if is_instance_valid(item_pick) and item_pick.item_count>0 else -1
 for child in rows.get_children():child.queue_free()
 for child in detail.get_children():child.queue_free()
 team_pick.visible=selected_mode=="arena"
 wager_pick.visible=selected_mode=="arena"
 if selected_mode!="arena":wager_pick.button_pressed=false
 var ui=game.ui
 create_button.disabled=not room.is_empty()
 var display_mode:String=str(room.get("mode",selected_mode))
 rules.text={"arena":"Best of three: first team to win two rounds wins. Casual matches keep your equipment. Item matches risk only the items everyone explicitly locks.","battlegrounds":"Extraction raid: death or leaving without extracting loses worn and carried items, belt contents and gold. Levels and town stash stay safe. Ready accepts these rules.","waves":"Defend the Last Flame against endless waves. Start alone or with up to four players; others can join your active lobby."}.get(display_mode,"")
 for id in mode_buttons:
  mode_buttons[id].modulate=Color(1.3,1.12,0.8) if id==selected_mode else Color.WHITE
  mode_buttons[id].disabled=not room.is_empty()
 for r in rooms:
  var rid:String=str(r.id)
  var b=ui._iron_button("%s · %s · %d/%d · %s"%[r.name,str(r.mode).capitalize(),int(r.get("joined",r.members.size())),r.capacity,str(r.state).capitalize()],900,48,18)
  b.disabled=not bool(r.get("joinable",false)) or not room.is_empty()
  b.pressed.connect(func():join_lobby(rid,str(r.mode)))
  rows.add_child(b)
 if rooms.is_empty():rows.add_child(ui._label("No lobbies yet. Create one and invite others to join.",18))
 if not room.is_empty():
  detail.add_child(ui._label(str(room.name)+" · "+str(room.state).capitalize(),22,ui.GOLD,true))
  var roster:=GridContainer.new();roster.columns=2;roster.add_theme_constant_override("h_separation",24);detail.add_child(roster)
  for uid in room.members:
   var m:Dictionary=room.members[uid]
   roster.add_child(ui._label("%s · %s · %s"%[m.name,("Ember" if int(m.team)==0 else "Frost") if room.mode=="arena" else "Party","Ready" if m.ready else "Not ready"],16))
  if bool(room.get("wager",false)) and room.state=="waiting":
   detail.add_child(ui._label("ITEM MATCH: Ready accepts the displayed stakes. Winners keep their stake and split the losing team's items.",14,ui.GOLD))
   var stakes:=GridContainer.new();stakes.columns=2;stakes.add_theme_constant_override("h_separation",24);detail.add_child(stakes)
   for m in room.members.values():
    stakes.add_child(ui._label(str(m.name)+": "+str(m.get("stake",{}).get("name","No item committed")),14))
   item_pick=OptionButton.new()
   var save:Dictionary=stake_store.read(game.char_dir+character+".json")
   var inv:Array=save.get("hero",{}).get("inventory",[])
   for i in inv.size():
    if inv[i] is Dictionary and str(inv[i].get("base",""))!="gold":item_pick.add_item(str(inv[i].get("name",inv[i].get("base","Item"))),i)
   for n in item_pick.item_count:
    if item_pick.get_item_id(n)==selected_item:item_pick.select(n)
   detail.add_child(item_pick)
   var commit=ui._iron_button("Lock Selected Item",250,42,17);commit.disabled=item_pick.item_count==0
   if room.members.get(identity,{}).has("stake"):
    commit.text="Item Locked";commit.disabled=true;item_pick.disabled=true
   commit.pressed.connect(commit_stake);detail.add_child(commit)
  var bar:=HBoxContainer.new();detail.add_child(bar)
  for option in [["Ready","ready",{"ready":true}],["Not Ready","ready",{"ready":false}],["Start Match","start",{}],["Leave Lobby","leave",{}]]:
   var op:String=option[1];var args:Dictionary=option[2]
   var b=ui._iron_button(option[0],210,44,18);b.disabled=str(room.state)!="waiting"
   if op=="start":b.disabled=b.disabled or str(room.owner)!=identity
   b.pressed.connect(func():action(op,args));bar.add_child(b)
  if room.mode=="arena" and room.state=="waiting":
   var teams:=HBoxContainer.new();detail.add_child(teams)
   for t in [0,1]:
    var b=ui._iron_button("Join "+("Ember" if t==0 else "Frost"),220,42,17)
    b.pressed.connect(func():action("team",{"team":t}));teams.add_child(b)

func enter_match() -> void:
 match_id=str(room.id)
 admitted=false
 character=str(room.members[identity].character)
 game.save_game()
 game.party_join_ticket=str(room.ticket)
 panel.hide()
 if str(room.mode)=="battlegrounds":
  await game.start_battlegrounds(str(room.address),character)
 else:
  game.arena_mode=str(room.mode)=="arena"
  await game.start_join(str(room.address),character)
  if game.arena_mode:game.hero.recalc()

func play_solo_waves() -> void:
 if not room.is_empty():status.text="Leave your lobby before playing solo.";return
 panel.hide()
 if not game.playing:await game.start_game(true,"knight",character)
 game.waypoint_activity_go("vigil")

func finished(reason: String) -> void:
 if _returning:return
 _returning=true
 print("[LOBBY] Match ended: ",reason)
 game.ui.big_message(reason)
 await get_tree().create_timer(4).timeout
 game.net.shutdown()
 if game.arena_mode:
  game.arena_mode=false;game.arena_state={};game.load_game()
 elif game.bg_mode:
  if admitted:game.bg_strip()
  game.bg_mode=false
  if not admitted:game.load_game()
 match_id="";room={}
 await game.exit_to_title()
 await collect()
 game.ui.message(reason)
 _returning=false

func _process(delta: float) -> void:
 if game==null:return
 game.ui.quest_tracker.visible=not game.arena_mode and not game.bg_mode
 arena_hud.visible=game.arena_mode and not game.ui.any_panel_open()
 if game.arena_mode:
  var s:Dictionary=game.arena_state
  var score:Array=s.get("scores",[0,0])
  arena_hud.text="ARENA · Round %d · Ember %d — %d Frost · %s · %ds"%[int(s.get("round",1)),score[0],score[1],str(s.get("phase","waiting")).capitalize(),int(s.get("left",0))]
 poll_t-=delta
 if poll_t<=0 and (panel.visible or not room.is_empty()):poll_t=3;refresh()

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
 status.text="Collected %d arena result(s). Pending items wait here if your bag is full."%count

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
  game.ui.open_dialog("Battlegrounds", "Death or leaving without extracting loses worn and carried items, belt contents and gold. Joining an active raid enters immediately. Your levels and town stash are safe.", [["Join Lobby",func():action("join",{"id":id})],["Cancel",func():pass]])
 else:action("join",{"id":id})
