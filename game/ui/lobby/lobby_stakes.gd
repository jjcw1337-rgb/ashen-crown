extends RefCounted
## Crash-safe local side of selected-item escrow. Server receipts are applied once to the target character.
## This protects normal saves/retries; the game's existing editable offline saves are not an anti-cheat boundary.
static func read(path: String) -> Dictionary:
 if not FileAccess.file_exists(path):return {}
 var data=JSON.parse_string(FileAccess.get_file_as_string(path))
 return data if data is Dictionary else {}
static func write(path: String,data: Dictionary) -> bool:
 var f:=FileAccess.open(path+".pending",FileAccess.WRITE)
 if f==null:return false
 f.store_string(JSON.stringify(data));f.close()
 return DirAccess.rename_absolute(path+".pending",path)==OK
static func journal_path(game) -> String:return game.char_dir+"arena_escrow.journal"
static func prepare(game,id: String,character: String,index: int) -> Dictionary:
 var journal:=read(journal_path(game))
 if journal.has(id):return journal[id]
 var path:String=game.char_dir+character+".json"
 var save:=read(path)
 var inv:Array=save.get("hero",{}).get("inventory",[])
 if index<0 or index>=inv.size() or not inv[index] is Dictionary:return {}
 var item:Dictionary=inv[index].duplicate(true)
 if not item.has("uid"):SharedStash.stamp(item)
 var entry:={"character":character,"item":item,"slot":index}
 journal[id]=entry
 # Journal first; recovery can finish removing the selected item before sending the same offer again.
 if not write(journal_path(game),journal):return {}
 return finish_removal(game,id)
static func finish_removal(game,id: String) -> Dictionary:
 var journal:=read(journal_path(game))
 if not journal.has(id):return {}
 var entry:Dictionary=journal[id]
 var path:String=game.char_dir+str(entry.character)+".json"
 var save:=read(path)
 if save.is_empty():return {}
 var locked:Array=save.get("lobby_locked",[])
 if id in locked:return entry
 var inv:Array=save.get("hero",{}).get("inventory",[])
 var index:=int(entry.slot)
 # Inventory removal and its marker commit together. A retry must never consume a second identical item.
 if index>=0 and index<inv.size() and inv[index] is Dictionary:
  var original:Dictionary=inv[index].duplicate(true);var expected:Dictionary=entry.item.duplicate(true)
  original.erase("uid");expected.erase("uid")
  if original==expected:inv[index]=null
 for i in inv.size():
  if inv[i] is Dictionary and str(inv[i].get("uid",""))==str(entry.item.uid):inv[i]=null
 locked.append(id);save["lobby_locked"]=locked;save.hero.inventory=inv
 save["played"]=maxi(int(save.get("played",0))+1,int(Time.get_unix_time_from_system()*1000))
 if not write(path,save):return {}
 if game.playing and game.char_id==str(entry.character):game.hero.inventory=inv.duplicate(true)
 if game.cloud!=null:game.cloud.push(str(entry.character),save)
 return entry
static func apply(game,receipt: Dictionary) -> bool:
 var path:String=game.char_dir+str(receipt.character)+".json"
 var save:=read(path)
 if save.is_empty():return false
 var applied:Array=save.get("lobby_receipts",[])
 if str(receipt.id) in applied:
  clear_journal(game,str(receipt.id));return true
 var inv:Array=save.hero.get("inventory",[])
 var items:Array=receipt.get("items",[])
 var slots:=[]
 for i in inv.size():
  if inv[i]==null:slots.append(i)
 if slots.size()<items.size():return false # Leave the receipt pending until the player frees space.
 for i in items.size():inv[int(slots[i])]=items[i]
 applied.append(str(receipt.id));save["lobby_receipts"]=applied;save.hero.inventory=inv
 var locked:Array=save.get("lobby_locked",[]);locked.erase(str(receipt.id).split(":")[0]);save["lobby_locked"]=locked
 save["played"]=maxi(int(save.get("played",0))+1,int(Time.get_unix_time_from_system()*1000))
 if not write(path,save):return false
 clear_journal(game,str(receipt.id))
 if game.cloud!=null:game.cloud.push(str(receipt.character),save)
 return true

static func clear_journal(game,id: String) -> void:
 var journal:=read(journal_path(game));journal.erase(id.split(":")[0]);write(journal_path(game),journal)
