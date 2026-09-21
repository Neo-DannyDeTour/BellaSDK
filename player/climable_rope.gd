@tool
## Generates procedural physics-driven ropes and chains for climbing and swinging.
class_name PhysicsClimbableRope3D
extends Node3D

# --------------------------------------
# CONSTANTS
# --------------------------------------

## Squared distance beyond which rope visual updates are culled.
const CULL_DISTANCE_SQUARED: float = 625.0

## Squared distance threshold for checking camera update frequencies.
const POSITION_EPSILON_SQUARED: float = 0.000001

# --------------------------------------
# EXPORTS
# --------------------------------------

@export_category("Rope Properties")
## Determines if the rope physics allow for swinging forces.
@export var is_swingable: bool = false

## The amount of force applied when the player swings.
@export var swing_force: float = 150.0

## The visual offset for the interaction label from the target point.
@export var label_offset_amount: float = 0.35

## The sound player triggered during standard climbing.
@export var rope_sound: AudioStreamPlayer3D

## The sound player triggered when rapidly sliding down.
@export var slide_sound: AudioStreamPlayer3D

## Time in seconds before the player can re-attach after releasing.
@export var reattach_cooldown: float = 0.5

@export_category("Slomo Settings")
## Determines if a slow-motion effect is triggered upon interaction.
@export var activate_slomo: bool = false

@export_category("Dimensions")
## The total vertical length of the generated rope.
@export_range(2.0, 30.0, 0.1) var rope_length: float = 5.0:
	set(value):
		rope_length = value
		_update_editor_preview()

@export_category("Physics Cable Options")
## Mass of each simulated link. Higher values reduce joint stretch.
@export var link_mass: float = 1.5

## The distance between each physically simulated rope link.
@export var link_spacing: float = 0.2

## The visual radius of the generated rope segments.
@export var thickness: float = 0.04

## The material color applied to the rope segments.
@export var cable_color: Color = Color(0.1, 0.1, 0.1)

## The radius of the detection area used for mid-air grabs.
@export var air_grab_radius: float = 0.8

@export_category("Chain Visuals")
## Optional 3D scene used for chain links when non-swingable.
@export var chain_scene: PackedScene

## Optional custom 3D mesh used for chain links when non-swingable.
@export var chain_mesh: Mesh

## Scale multiplier applied to custom chain meshes or scenes.
@export var chain_mesh_scale: Vector3 = Vector3.ONE

# --------------------------------------
# INTERNAL VARIABLES
# --------------------------------------

## The tween responsible for time scaling effects.
var slomo_tween: Tween

## Tracks if a player is currently attached to the rope.
var player_on_rope: bool = false

## Remaining time before the player can grab the rope again.
var _current_cooldown: float = 0.0

## Caches the current active camera for UI positioning and culling.
var _cached_camera: Camera3D

## Reference to the currently attached player character.
var _attached_player: CharacterBody3D = null

## The currently focused interaction component for UI anchoring.
var _focused_ic: Node

## Stores all dynamically generated rigid body links.
var _links: Array[RigidBody3D] = []

## Discrete visual nodes when using custom packed scenes.
var _visual_segments: Array[Node3D] = []

## Batched MultiMesh instance for hardware instanced rendering.
var _multimesh_instance: MultiMeshInstance3D

## Shared base cylinder mesh for standard ropes.
var _base_mesh: CylinderMesh

## Procedural torus mesh used as a fallback for chains.
var _default_chain_mesh: TorusMesh

## Shared cache preventing duplication of standard materials.
static var _material_cache: Dictionary = {}

# --------------------------------------
# NODE REFERENCES
# --------------------------------------

## The static anchor point where the rope begins.
@onready var anchor: StaticBody3D = $Anchor

## Original static rope body used as a template before generation.
@onready var original_rope_body: RigidBody3D = get_node_or_null("RopeBody") as RigidBody3D

## The UI label indicating interaction.
var interact_label: Label3D

# --------------------------------------
# ENGINE METHODS
# --------------------------------------


## Sets up UI label bindings, creates meshes, and builds the dynamic chain.
func _ready() -> void:
	if Engine.is_editor_hint():
		_update_editor_preview()
		return

	var orig_label: Label3D = get_node_or_null("RopeBody/Label3D") as Label3D
	if is_instance_valid(orig_label):
		orig_label.get_parent().remove_child(orig_label)
		add_child(orig_label)
		interact_label = orig_label
		interact_label.hide()

		var action_name: String = "interact"
		if InputMap.has_action(action_name):
			var events: Array[InputEvent] = InputMap.action_get_events(action_name)
			if not events.is_empty():
				var key_name: String = events[0].as_text().split(" ")[0]
				interact_label.text = "[" + key_name + "] CLIMB"

	_create_base_mesh()
	call_deferred("_build_dynamic_rope")


## Updates cooldowns, executes distance checks, and refreshes link visuals.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _current_cooldown > 0.0:
		_current_cooldown -= delta

	if not is_instance_valid(_cached_camera):
		_cached_camera = get_viewport().get_camera_3d()

	if is_instance_valid(_cached_camera) and not player_on_rope:
		var cam_pos: Vector3 = _cached_camera.global_position
		if anchor.global_position.distance_squared_to(cam_pos) > CULL_DISTANCE_SQUARED:
			return

	_update_visuals()

	if not player_on_rope and is_instance_valid(_focused_ic) and is_instance_valid(interact_label):
		_update_label_position()


# --------------------------------------
# EDITOR PREVIEW
# --------------------------------------


## Synchronizes template nodes in the Godot 3D editor viewport.
func _update_editor_preview() -> void:
	if not is_inside_tree():
		return

	var rope_mesh: MeshInstance3D = get_node_or_null("RopeBody/MeshInstance3D") as MeshInstance3D
	var rope_col: CollisionShape3D = (
		get_node_or_null("RopeBody/CollisionShape3D") as CollisionShape3D
	)
	var rope_body: RigidBody3D = get_node_or_null("RopeBody") as RigidBody3D
	var rope_anchor: StaticBody3D = get_node_or_null("Anchor") as StaticBody3D
	var pivot: Joint3D = get_node_or_null("Pivot") as Joint3D

	if is_instance_valid(rope_mesh) and rope_mesh.mesh:
		rope_mesh.mesh.height = rope_length
		rope_mesh.position.y = -rope_length * 0.5

	if is_instance_valid(rope_col) and rope_col.shape:
		rope_col.shape.height = rope_length
		rope_col.position.y = -rope_length * 0.5

	if is_instance_valid(rope_anchor):
		rope_anchor.position.y = 0.0
	if is_instance_valid(pivot):
		pivot.position.y = 0.0
	if is_instance_valid(rope_body):
		rope_body.position = Vector3.ZERO


# --------------------------------------
# VISUALS & OPTIMIZATION
# --------------------------------------


## Evaluates link positions and updates batched MultiMesh or discrete segments.
func _update_visuals() -> void:
	if _links.is_empty():
		return

	var needs_update: bool = false
	if player_on_rope:
		needs_update = true
	else:
		for link: RigidBody3D in _links:
			if is_instance_valid(link) and not link.is_sleeping():
				needs_update = true
				break

	if not needs_update:
		return

	var p1: Vector3 = anchor.global_position
	var is_batched: bool = is_instance_valid(_multimesh_instance)
	var mmesh: MultiMesh = _multimesh_instance.multimesh if is_batched else null

	for i: int in range(_links.size()):
		var link: RigidBody3D = _links[i]
		if not is_instance_valid(link):
			continue

		var p2: Vector3 = link.global_position
		var center: Vector3 = p1.lerp(p2, 0.5)
		var dir: Vector3 = p2 - p1
		var dist: float = p1.distance_to(p2)

		var seg_basis: Basis = Basis()
		if dir.length_squared() > POSITION_EPSILON_SQUARED:
			var norm_dir: Vector3 = dir.normalized()
			var up: Vector3 = Vector3.UP if absf(norm_dir.y) < 0.99 else Vector3.RIGHT
			seg_basis = Basis.looking_at(norm_dir, up)
			seg_basis = seg_basis.rotated(seg_basis.x, PI / 2.0)

			if not is_swingable and i % 2 == 1:
				seg_basis = seg_basis.rotated(seg_basis.y, PI / 2.0)

		var seg_scale: Vector3 = Vector3.ONE
		if is_swingable:
			seg_scale = Vector3(1.0, dist, 1.0)
		elif chain_scene == null and chain_mesh == null:
			seg_scale = Vector3.ONE
		else:
			seg_scale = chain_mesh_scale

		seg_basis = seg_basis.scaled(seg_scale)

		if is_batched:
			var local_pos: Vector3 = center - _multimesh_instance.global_position
			var xform: Transform3D = Transform3D(seg_basis, local_pos)
			mmesh.set_instance_transform(i, xform)
		elif i < _visual_segments.size():
			var seg: Node3D = _visual_segments[i]
			seg.global_position = center
			seg.basis = seg_basis

		p1 = p2


## Instantiates meshes and configures shared materials for rope links.
func _create_base_mesh() -> void:
	print("PhysicsClimbableRope3D: Generating base visual meshes.")
	_base_mesh = CylinderMesh.new()
	_base_mesh.top_radius = thickness
	_base_mesh.bottom_radius = thickness
	_base_mesh.height = 1.0
	_base_mesh.radial_segments = 8
	_base_mesh.rings = 1

	_default_chain_mesh = TorusMesh.new()
	_default_chain_mesh.outer_radius = link_spacing * 0.65
	_default_chain_mesh.inner_radius = link_spacing * 0.35
	_default_chain_mesh.rings = 16
	_default_chain_mesh.ring_segments = 8

	if not _material_cache.has(cable_color):
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = cable_color
		mat.roughness = 0.8
		_material_cache[cable_color] = mat

	_base_mesh.material = _material_cache[cable_color]
	_default_chain_mesh.material = _material_cache[cable_color]


## Positions the floating interaction prompt relative to the player camera.
func _update_label_position() -> void:
	if not is_instance_valid(_cached_camera):
		_cached_camera = get_viewport().get_camera_3d()

	if is_instance_valid(_cached_camera) and is_instance_valid(_focused_ic):
		var hit_point_val: Variant = _focused_ic.get("last_hit_position")
		var hit_point: Vector3 = Vector3.ZERO

		if hit_point_val is Vector3:
			hit_point = hit_point_val
		else:
			hit_point = _focused_ic.global_position

		var cam_right: Vector3 = _cached_camera.global_transform.basis.x
		var cam_up: Vector3 = _cached_camera.global_transform.basis.y
		var offset_r: Vector3 = cam_right * label_offset_amount
		var offset_u: Vector3 = cam_up * 0.1
		interact_label.global_position = hit_point + offset_r + offset_u


# --------------------------------------
# GENERATION LOGIC
# --------------------------------------


## Instantiates rigid bodies, joints, and collision shapes along the rope length.
func _build_dynamic_rope() -> void:
	print("PhysicsClimbableRope3D: Building dynamic rope hierarchy.")
	var interact_template: Node = null
	var highlight_template: Node = null

	if is_instance_valid(original_rope_body):
		interact_template = original_rope_body.get_node_or_null("InteractComponent")
		highlight_template = original_rope_body.get_node_or_null("HighlightComponent")

	var total_links: int = int(rope_length / link_spacing)
	var previous_body: PhysicsBody3D = anchor

	var can_use_multimesh: bool = chain_scene == null
	if can_use_multimesh:
		_multimesh_instance = MultiMeshInstance3D.new()
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = total_links

		if is_swingable:
			mm.mesh = _base_mesh
		elif chain_mesh != null:
			mm.mesh = chain_mesh
		else:
			mm.mesh = _default_chain_mesh

		_multimesh_instance.multimesh = mm
		_multimesh_instance.top_level = true
		add_child(_multimesh_instance)

	for i: int in range(total_links):
		var link: RigidBody3D = RigidBody3D.new()
		link.mass = link_mass
		link.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		link.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		link.angular_damp = 2.5
		link.linear_damp = 1.5

		if not is_swingable:
			link.axis_lock_angular_x = true
			link.axis_lock_angular_y = true
			link.axis_lock_angular_z = true

		add_child(link)
		var link_offset: Vector3 = Vector3.DOWN * link_spacing * (i + 1)
		link.global_position = anchor.global_position + link_offset

		var col: CollisionShape3D = CollisionShape3D.new()
		var cap: CapsuleShape3D = CapsuleShape3D.new()
		cap.radius = thickness
		cap.height = link_spacing
		col.shape = cap
		link.add_child(col)

		if is_instance_valid(interact_template):
			var ic: Node = interact_template.duplicate()
			link.add_child(ic)
			ic.focused.connect(_on_link_focused.bind(ic))
			ic.unfocused.connect(_on_link_unfocused.bind(ic))
			ic.interacted.connect(_on_link_interacted.bind(link))

		if is_instance_valid(highlight_template):
			var hc: Node = highlight_template.duplicate()
			link.add_child(hc)

		var air_area: Area3D = Area3D.new()
		air_area.collision_layer = 0
		# Physics Layer 2: Player (1 << 1 = 2)
		air_area.collision_mask = 2

		var air_col: CollisionShape3D = CollisionShape3D.new()
		var air_shape: CapsuleShape3D = CapsuleShape3D.new()
		air_shape.radius = air_grab_radius
		air_shape.height = link_spacing + (air_grab_radius * 2.0)
		air_col.shape = air_shape
		air_area.add_child(air_col)
		link.add_child(air_area)
		air_area.body_entered.connect(_on_air_area_entered.bind(link))

		for prev: RigidBody3D in _links:
			link.add_collision_exception_with(prev)

		_links.append(link)

		var joint: PinJoint3D = PinJoint3D.new()
		add_child(joint)
		var p_mid: Vector3 = previous_body.global_position.lerp(link.global_position, 0.5)
		joint.global_position = p_mid
		joint.node_a = joint.get_path_to(previous_body)
		joint.node_b = joint.get_path_to(link)

		previous_body = link

		if not can_use_multimesh:
			var segment: Node3D = chain_scene.instantiate() as Node3D
			segment.scale = chain_mesh_scale
			segment.top_level = true
			add_child(segment)
			_visual_segments.append(segment)

	if is_instance_valid(original_rope_body):
		original_rope_body.queue_free()


# --------------------------------------
# ATTACHMENT & INTERACTION LOGIC
# --------------------------------------


## Displays the climbing prompt and activates slow motion if configured.
func _on_link_focused(ic: Node) -> void:
	if not player_on_rope:
		_focused_ic = ic
		if is_instance_valid(interact_label):
			interact_label.show()
		if activate_slomo:
			_set_slomo(0.3)


## Hides the interaction prompt and resets engine time scale.
func _on_link_unfocused(ic: Node) -> void:
	if _focused_ic == ic:
		_focused_ic = null
		if is_instance_valid(interact_label):
			interact_label.hide()
		if activate_slomo:
			_set_slomo(1.0)


## Receives player interaction input from ground proximity.
func _on_link_interacted(player: CharacterBody3D, link: RigidBody3D) -> void:
	if _current_cooldown > 0.0:
		print("PhysicsClimbableRope3D: Re-attach cooldown active.")
		return

	print("PhysicsClimbableRope3D: Player interact triggered.")
	_attach_to_link(player, link)


## Handles automatic mid-air player collision and attachment.
func _on_air_area_entered(body: Node3D, link: RigidBody3D) -> void:
	if player_on_rope or _current_cooldown > 0.0:
		return

	if body.has_method("is_on_floor") and body.has_method("_on_rope_grabbed"):
		if not body.call("is_on_floor"):
			print("PhysicsClimbableRope3D: Mid-air grab triggered.")
			_attach_to_link(body as CharacterBody3D, link)


## Attaches the player to a link, removing damping for free swinging.
func _attach_to_link(player: CharacterBody3D, link: RigidBody3D) -> void:
	print("PhysicsClimbableRope3D: Attaching player to rope link.")
	player_on_rope = true
	_attached_player = player
	_focused_ic = null

	if is_instance_valid(interact_label):
		interact_label.hide()

	if activate_slomo:
		_set_slomo(1.0)

	link.angular_damp = 0.0
	link.linear_damp = 0.0

	for l: RigidBody3D in _links:
		if is_instance_valid(l):
			l.add_collision_exception_with(player)

	if player.has_method("_on_rope_grabbed"):
		player.call("_on_rope_grabbed", link)


## Detaches the player, restores link damping, and starts re-attach cooldown.
func on_player_released() -> void:
	print("PhysicsClimbableRope3D: Player released the rope.")
	player_on_rope = false
	_current_cooldown = reattach_cooldown

	handle_rope_sounds(false, false)

	for link: RigidBody3D in _links:
		if is_instance_valid(link):
			link.angular_damp = 2.5
			link.linear_damp = 1.5
			if is_instance_valid(_attached_player):
				link.remove_collision_exception_with(_attached_player)

	_attached_player = null

	if activate_slomo:
		_set_slomo(1.0)


## Plays or halts looping audio streams for climbing and sliding.
func handle_rope_sounds(is_climbing: bool, is_sliding: bool) -> void:
	print("PhysicsClimbableRope3D: Updating audio playback states.")
	if is_instance_valid(rope_sound):
		if is_climbing and not is_sliding:
			if not rope_sound.playing:
				rope_sound.play()
		else:
			if rope_sound.playing:
				rope_sound.stop()

	if is_instance_valid(slide_sound):
		if is_sliding:
			if not slide_sound.playing:
				slide_sound.play()
		else:
			if slide_sound.playing:
				slide_sound.stop()


# --------------------------------------
# UTILITY
# --------------------------------------


## Tweens engine time scale smoothly for slow-motion effects.
func _set_slomo(target_scale: float) -> void:
	print("PhysicsClimbableRope3D: Engine time_scale set to ", target_scale)
	if is_instance_valid(slomo_tween):
		slomo_tween.kill()

	slomo_tween = create_tween()
	slomo_tween.set_ignore_time_scale(true)
	slomo_tween.tween_property(Engine, "time_scale", target_scale, 0.25)
