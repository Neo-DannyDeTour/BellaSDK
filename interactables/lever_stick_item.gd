## World stick pickup item inheriting [PickableObject] used to repair a [WallLever].
class_name LeverStickItem
extends PickableObject

## Emitted when the carried stick mounts onto an incomplete [WallLever].
signal mounted_on_lever(lever: WallLever)

## Unique identifier used by inventory or puzzle systems.
@export var item_id: String = "lever_stick"

## Display name surfaced to UI inspection or HUD.
@export var item_name: String = "Iron Lever Handle"

## Area used while held to detect contact with a [WallLever].
@export var mount_detector: Area3D

## Prevents duplicate collection or mounting calls.
var _is_collected: bool = false


## Initializes dependencies, collisions, and detector signals.
func _ready() -> void:
	super._ready()
	print("LeverStickItem: _ready() initialized.")

	collision_layer = 4
	collision_mask = 1

	if not is_instance_valid(mount_detector):
		mount_detector = get_node_or_null("MountDetector") as Area3D

	if not is_instance_valid(mount_detector):
		_setup_runtime_mount_detector()
	else:
		mount_detector.monitoring = false
		if not mount_detector.body_entered.is_connected(_on_detector_body_entered):
			mount_detector.body_entered.connect(_on_detector_body_entered)
		if not mount_detector.area_entered.is_connected(_on_detector_area_entered):
			mount_detector.area_entered.connect(_on_detector_area_entered)


## Grabs stick, attaches to hold target, and enables detector.
func pick_up(target: Marker3D, player_node: Node3D) -> void:
	print("LeverStickItem: pick_up() invoked by ", player_node.name)
	super.pick_up(target, player_node)

	if is_instance_valid(mount_detector):
		mount_detector.set_deferred("monitoring", true)


## Drops stick to the ground and disables detector.
func drop() -> void:
	print("LeverStickItem: drop() invoked.")
	super.drop()

	if is_instance_valid(mount_detector):
		mount_detector.set_deferred("monitoring", false)


## Throws stick with impulse and disables detector.
func throw(impulse_vector: Vector3) -> void:
	print("LeverStickItem: throw() invoked with force: ", impulse_vector.length())
	super.throw(impulse_vector)

	if is_instance_valid(mount_detector):
		mount_detector.set_deferred("monitoring", false)


## Creates a runtime collision detector if absent.
func _setup_runtime_mount_detector() -> void:
	print("LeverStickItem: Creating runtime MountDetector.")
	mount_detector = Area3D.new()
	mount_detector.name = "MountDetector"
	mount_detector.collision_layer = 0
	mount_detector.collision_mask = 1 | 4

	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.4, 0.6, 0.4)
	shape.shape = box
	mount_detector.add_child(shape)
	add_child(mount_detector)
	mount_detector.monitoring = false

	mount_detector.body_entered.connect(_on_detector_body_entered)
	mount_detector.area_entered.connect(_on_detector_area_entered)


## Evaluates entered bodies for contact with [WallLever].
func _on_detector_body_entered(body: Node) -> void:
	print("LeverStickItem: Mount detector body entered by: ", body.name)
	if not is_held or _is_collected:
		return
	var lever: WallLever = body as WallLever
	if not is_instance_valid(lever):
		lever = body.get_owner() as WallLever
	if is_instance_valid(lever):
		_try_mount_on_lever(lever)


## Evaluates entered areas for contact with [WallLever].
func _on_detector_area_entered(area: Area3D) -> void:
	print("LeverStickItem: Mount detector area entered by: ", area.name)
	if not is_held or _is_collected:
		return
	var lever: WallLever = area.get_owner() as WallLever
	if is_instance_valid(lever):
		_try_mount_on_lever(lever)


## Mounts stick onto lever socket, notifies player, and frees node.
func _try_mount_on_lever(lever: WallLever) -> void:
	print("LeverStickItem: Attempting mounting into ", lever.name)
	if lever.is_complete:
		return

	_is_collected = true
	is_held = false

	if is_instance_valid(mount_detector):
		mount_detector.set_deferred("monitoring", false)

	if is_instance_valid(holder):
		var p_interact: Node = holder.get("interaction_component") as Node
		if is_instance_valid(p_interact) and p_interact.has_method("force_clear_hands"):
			p_interact.force_clear_hands()

	lever.install_stick()
	mounted_on_lever.emit(lever)
	queue_free()
