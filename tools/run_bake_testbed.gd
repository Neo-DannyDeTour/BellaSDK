class_name RunBakeTestbed
extends SceneTree
## Headless CLI runner executing the map baker on the testbed level.

## Resource path to the shared map baker script.
const BAKER_SCRIPT_PATH: String = "res://tools/bake_and_chunkify_map.gd"


## Initializes autoload-safe headless execution and quits with exit status.
func _initialize() -> void:
	var baker_script: GDScript = ResourceLoader.load(BAKER_SCRIPT_PATH) as GDScript
	if baker_script == null:
		push_error("RunBakeTestbed: Failed to load ", BAKER_SCRIPT_PATH)
		quit(1)
		return
	var err: Variant = await baker_script.call(&"run_bake", self)
	if not (err is int) or err != OK:
		push_error("RunBakeTestbed: Bake failed with error ", err)
		quit(1)
		return
	print("RunBakeTestbed: Bake completed successfully.")
	quit(0)
