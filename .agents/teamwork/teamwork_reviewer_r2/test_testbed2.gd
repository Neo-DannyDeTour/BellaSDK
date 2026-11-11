extends SceneTree


func _init() -> void:
	print("Testing loading testbed2.tscn...")
	var scn: PackedScene = ResourceLoader.load("res://levels/testbed2.tscn") as PackedScene
	assert(scn != null, "testbed2.tscn failed to load!")
	print("Successfully loaded testbed2.tscn!")
	quit(0)
