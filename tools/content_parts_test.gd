extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
 call_deferred("run")
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(message)
func extract(scene: PackedScene) -> Array:
 var src := scene.instantiate()
 var out: Array = []
 for child in src.find_children("*", "MeshInstance3D", true, false):
  var mi := child as MeshInstance3D
  out.append({"mesh":mi.mesh,"position":mi.position})
 src.free()
 return out
func run() -> void:
 var paths: Array = [PlagueVialFx.SHARDS_GLB, PlagueExperimentFx.SHARDS_GLB]
 ResCache.prepare("parts-a", paths)
 ResCache.prepare("parts-b", paths)
 check((await ResCache.wait_ready(self,"parts-a")).ready,"prepared fragment scenes")
 var report: Array = []
 for path in paths:
  var scene := ResCache.get_res(path) as PackedScene
  var original := extract(scene)
  var parts := ResCache.mesh_parts(path)
  check(not parts.is_empty() and parts.size()==original.size(),"same fragment count")
  for i in parts.size():
   check(parts[i].mesh==original[i].mesh and parts[i].position==original[i].position,"same mesh identity and local offset")
  var built: int = ResCache.metrics().mesh_parts_builds
  var samples: Array = []
  for repeat in 3:
   var start := Time.get_ticks_usec()
   for i in 30: extract(scene)
   var before := Time.get_ticks_usec()-start
   start=Time.get_ticks_usec()
   for i in 30: ResCache.mesh_parts(path)
   samples.append({"extract_30_us":before,"cached_30_us":Time.get_ticks_usec()-start})
  check(ResCache.metrics().mesh_parts_builds==built,"repeated calls never instantiate again")
  report.append({"path":path,"fragments":parts.size(),"samples":samples})
 check(ResCache.metrics().derived_mesh_sets==2,"two owned derived sets")
 ResCache.release("parts-a")
 check(ResCache.metrics().derived_mesh_sets==2,"other owner retains recipes")
 ResCache.release("parts-b")
 check(ResCache.metrics().derived_mesh_sets==0,"last owner releases recipes")
 check(ResCache.metrics().sync_misses.is_empty(),"no synchronous resource miss")
 print("[PARTS] ",JSON.stringify(report))
 print("[PARTS] ",checks," checks / ",failures," failures")
 quit(1 if failures else 0)
