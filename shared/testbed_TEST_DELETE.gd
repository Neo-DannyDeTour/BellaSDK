extends Node3D


func _ready() -> void:
	print("Node ready: Initializing environment diagnostic check.")
	verify_scene_environments()


func _process(_delta: float) -> void:
	pass


func verify_scene_environments() -> void:
	print("Running environment diagnostic tool...")

	var root: Window = get_tree().get_root()
	var env_nodes: Array[Node] = root.find_children("*", "WorldEnvironment", true, false)

	print("Found %d WorldEnvironment nodes in the active tree." % env_nodes.size())

	for env_node: Node in env_nodes:
		print("Active Environment path: ", env_node.get_path())

	if env_nodes.size() > 1:
		print("WARNING: Multiple environments detected. Delete the conflicting node.")
