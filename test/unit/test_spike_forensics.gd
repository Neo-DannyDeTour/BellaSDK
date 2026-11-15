## GUT test suite verifying [SpikeForensics] spike attribution and log serialization.
class_name TestSpikeForensics
extends GutTest

## Instance of the forensic profiler script under test.
var forensics: Node = null


## Instantiates and attaches an isolated [SpikeForensics] node before each test.
func before_each() -> void:
	var script_res: GDScript = load("res://core/spike_forensics.gd") as GDScript
	assert_not_null(script_res, "SpikeForensics script must load.")
	var raw_node: Object = script_res.new()
	if raw_node is Node:
		forensics = raw_node
		add_child_autofree(forensics)


## Verifies frames under threshold produce an empty record and emit no signal.
func test_normal_frame_ignored() -> void:
	watch_signals(forensics)
	var result: Variant = forensics.call("evaluate_frame_sample", 12.0)
	var record: Dictionary = result if result is Dictionary else {}
	assert_true(record.is_empty(), "Normal 12ms frame should not create a spike record.")
	assert_signal_not_emitted(forensics, "spike_detected")


## Verifies spiked frames emit [signal spike_detected] with attributed scopes and nodes.
func test_spike_frame_attributes_scope_and_nodes() -> void:
	watch_signals(forensics)
	forensics.call("begin_scope", &"ChunkMeshBuild")
	forensics.call("end_scope", &"ChunkMeshBuild")

	var spawned: Node3D = Node3D.new()
	spawned.name = "TestSpikeProp"
	add_child_autofree(spawned)

	var result: Variant = forensics.call("evaluate_frame_sample", 42.5)
	var record: Dictionary = result if result is Dictionary else {}

	assert_false(record.is_empty(), "42.5ms frame should generate a spike record.")
	assert_eq(record.get("severity", ""), "hitch", "Frames >= 33.33ms must be marked hitch.")
	assert_signal_emitted(forensics, "spike_detected")

	var scopes_raw: Variant = record.get("scopes", {})
	var scopes: Dictionary = scopes_raw if scopes_raw is Dictionary else {}
	assert_true(scopes.has("ChunkMeshBuild"), "Spike record must include active scope timing.")
