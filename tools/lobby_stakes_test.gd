extends SceneTree
var fails:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
 checks+=1;print("[ESCROW] ","ok " if ok else "FAIL ",label)
 if not ok:fails+=1
func run():
 var store=load("res://scripts/lobby_stakes.gd")
 var path:="user://lobby_escrow_test/"
 DirAccess.make_dir_recursive_absolute(path)
 var game={"char_dir":path,"playing":false,"cloud":null}
 var original:={"base":"short_sword","name":"Trial sword"}
 store.write(path+"hero.json",{"hero":{"inventory":[original,null,null]}})
 store.write(store.journal_path(game),{})
 var entry:Dictionary=store.prepare(game,"room","hero",0)
 check(not entry.is_empty() and entry.item.has("uid"),"selected item stamped and journalled")
 var save:Dictionary=store.read(path+"hero.json")
 check(save.hero.inventory[0]==null,"stake removed from saved inventory")
 save.hero.inventory[0]=original.duplicate();store.write(path+"hero.json",save)
 store.finish_removal(game,"room")
 check(store.read(path+"hero.json").hero.inventory[0]!=null,"retry does not consume a second identical item")
 var reward:={"id":"room:user","character":"hero","items":[entry.item,{"base":"shield","uid":"another-unique-item"}]}
 check(store.apply(game,reward),"winner receives own and opponent stakes")
 check(store.read(path+"hero.json").hero.inventory.filter(func(it):return it!=null).size()==3,"exact item count")
 check(store.apply(game,reward),"receipt replay accepted idempotently")
 check(store.read(path+"hero.json").hero.inventory.size()==3,"replay cannot expand bag")
 check(store.read(store.journal_path(game)).is_empty(),"settlement clears journal")
 check(not store.apply(game,{"id":"full:user","character":"hero","items":[entry.item]}),"full bag leaves rewards pending")
 # Reproduce process stopping after journal write but before removal.
 store.write(path+"hero.json",{"hero":{"inventory":[original,null,null]}})
 store.write(store.journal_path(game),{"crash":{"character":"hero","item":entry.item,"slot":0}})
 store.finish_removal(game,"crash")
 check(store.read(path+"hero.json").hero.inventory[0]==null,"crash recovery finishes item removal")
 # Reproduce process stopping after receipt application but before journal cleanup.
 save=store.read(path+"hero.json");save["lobby_receipts"]=["crash:user"];store.write(path+"hero.json",save)
 check(store.apply(game,{"id":"crash:user","character":"hero","items":[entry.item]}),"already saved receipt recovers")
 check(store.read(store.journal_path(game)).is_empty(),"receipt replay still clears interrupted journal")
 print("[ESCROW] done ",checks," checks / ",fails," failures");quit(1 if fails else 0)
