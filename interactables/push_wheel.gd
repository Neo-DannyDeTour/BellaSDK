class_name PushWheel
extends StaticBody3D

const DOUBLE_TAP_DELAY: float = 0.3

@export_category("Transmitter")
@export var transmitter: OutputTransmitter3D
@export var transmitter_targets: Array[Node3D] = []:
	set(value):
		transmitter_targets = value
		_update_transmitter_targets()

@export_category("Wheel Setup")
@export var is_broken_variant: bool = false:
	set(value):
		is_broken_variant = value
		_update_visual_state()

@export var pickable_stick_scene: PackedScene

@export_category("Node References")
@export var wheel: AnimatableBody3D
@export var intact_sticks: Node3D
@export var broken_stubs: Node3D
@export var restored_handle: Node3D

@export_category("Wheel Settings")
@export var turn_duration: float = 5.0
@export var visual_rotations: float = 1.0
@export var turn_clockwise: bool = true
@export var allow_reverse: bool = true

@export_category("Wheel Alignment")
@export var stick_count: int = 4
@export var stick_radius: float = 1.5
@export var push_stand_offset: float = 0.8
@export var restored_stick_index: int = 0

@export var can_be_detached: bool = false:
	set(value):
		can_be_detached = value
		if can_be_detached:
			lock_when_finished = false

@export var lock_when_finished: bool = false:
	set(value):
		lock_when_finished = value
		if lock_when_finished:
			can_be_detached = false

@export var spin_axis: Vector3 = Vector3(0, 1, 0)
@export var outline_material: ShaderMaterial

var progress: float = 0.0
var is_focused: bool = false
var is_locked: bool = false
var is_installed: bool = true

var install_cooldown: float = 0.0
var last_interact_time: float = 0.0
var initial_rotation: Vector3

var current_active_anchor: Marker3D = null
var _was_powered_on: bool = false
var _stick_collisions: Array[CollisionShape3D] = []


func _ready() -> void:
	_update_transmitter_targets()
	_update_visual_state()
	
	if Engine.is_editor_hint():
		return
		
	print("PushWheel: Initialized. Broken Variant = ", is_broken_variant)

	if is_instance_valid(wheel):
		initial_rotation = wheel.rotation_degrees
		_update_stick_collisions()
	else:
		push_error("PushWheel: 'Wheel' reference is missing!")

	var interact_comp: Node = get_node_or_null("Interact_Component")
	if is_instance_valid(interact_comp):
		interact_comp.focused.connect(_on_focused)
		interact_comp.unfocused.connect(_on_unfocused)
		interact_comp.interacted.connect(_on_interacted)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if install_cooldown > 0.0:
		install_cooldown -= delta

	if not is_installed:
		_check_for_installation()

	var just_pressed: bool = is_focused and Input.is_action_just_pressed("interact")
	if is_installed and can_be_detached and just_pressed:
		var current_time: float = Time.get_ticks_msec() / 1000.0
		if current_time - last_interact_time <= DOUBLE_TAP_DELAY:
			print("PushWheel: Double tap detected. Detaching stick.")
			_detach_stick()
			last_interact_time = 0.0
		else:
			last_interact_time = current_time


func _update_stick_collisions() -> void:
	if not is_instance_valid(wheel):
		return
		
	print("PushWheel: Updating physical collisions for sticks.")
	
	for col in _stick_collisions:
		if is_instance_valid(col):
			col.queue_free()
	_stick_collisions.clear()

	if is_broken_variant and not is_installed:
		print("PushWheel: Broken variant missing stick. No collisions generated.")
		return

	var angle_step: float = TAU / float(max(1, stick_count))
	var indices_to_generate: Array[int] = []

	if not is_broken_variant:
		for i in range(stick_count):
			indices_to_generate.append(i)
	elif is_installed:
		indices_to_generate.append(restored_stick_index)

	for i in indices_to_generate:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		
		box.size = Vector3(stick_radius, 0.2, 0.2)
		col.shape = box
		
		wheel.add_child(col)
		_stick_collisions.append(col)
		
		var angle: float = i * angle_step
		var stick_dir := Vector3(cos(angle), 0.0, sin(angle))
		
		col.position = stick_dir * (stick_radius * 0.5)
		col.rotation.y = -angle
		
	print("PushWheel: Generated ", indices_to_generate.size(), " stick collision(s).")


func _update_transmitter_targets() -> void:
	if is_instance_valid(transmitter):
		transmitter.targets = transmitter_targets
		if not Engine.is_editor_hint():
			print("PushWheel: Synced ", transmitter_targets.size(), " targets.")


func push(delta_amount: float) -> void:
	if is_locked or not is_installed:
		return

	var applied_amount: float = delta_amount / turn_duration

	if not allow_reverse and applied_amount < 0.0:
		applied_amount = 0.0

	progress += applied_amount
	progress = clampf(progress, 0.0, 1.0)
	
	print("PushWheel: Player pushed wheel. Current progress: ", progress)

	if lock_when_finished and progress >= 1.0:
		is_locked = true
		print("PushWheel: Locked at 100% progress.")

	_update_visuals()
	_check_transmitter_power()
	
	if is_instance_valid(transmitter) and transmitter.has_method("transmit_progress"):
		transmitter.transmit_progress(progress)
	else:
		for target in transmitter_targets:
			if is_instance_valid(target) and target.has_method("set_progress"):
				target.set_progress(progress)


func _check_transmitter_power() -> void:
	if is_instance_valid(transmitter):
		if progress >= 1.0 and not _was_powered_on:
			print("PushWheel: Progress 100%. Triggering Transmitter.")
			transmitter.power_on()
			_was_powered_on = true
		elif progress < 1.0 and _was_powered_on:
			print("PushWheel: Progress < 100%. Turning off Transmitter.")
			transmitter.power_off()
			_was_powered_on = false
	else:
		if progress >= 1.0 and not _was_powered_on:
			print("PushWheel: Progress 100%. Triggering targets directly.")
			for target in transmitter_targets:
				if is_instance_valid(target) and target.has_method("power_on"):
					target.power_on()
			_was_powered_on = true
		elif progress < 1.0 and _was_powered_on:
			print("PushWheel: Progress < 100%. Turning off targets directly.")
			for target in transmitter_targets:
				if is_instance_valid(target) and target.has_method("power_off"):
					target.power_off()
			_was_powered_on = false


func _update_visuals() -> void:
	if is_instance_valid(wheel):
		var dir_multi: float = -1.0 if turn_clockwise else 1.0
		var total_angle: float = 360.0 * visual_rotations * dir_multi * progress
		wheel.rotation_degrees = initial_rotation + (spin_axis * total_angle)


func _on_interacted(character: CharacterBody3D) -> void:
	print("PushWheel: _on_interacted called by player.")
	
	if not is_installed or is_locked:
		return

	var state_machine: Node = character.get_node_or_null("StateMachine")
	
	if is_instance_valid(state_machine) and state_machine.get("state") != null:
		if state_machine.state.name == "PushWheel":
			print("PushWheel: Player already attached. Ignoring duplicate call.")
			return

	print("PushWheel: Requesting transition to PushWheel state.")
	
	# Retrieve the cached hit_point directly from the component
	var interact_comp: Interact_Component = get_node_or_null("Interact_Component") as Interact_Component
	var hit_point: Vector3 = Vector3.ZERO
	
	if is_instance_valid(interact_comp):
		hit_point = interact_comp.last_hit_position
		
	# Use hit_point if valid, fallback to character position
	var target_pos: Vector3 = hit_point if hit_point != Vector3.ZERO else character.global_position
	var target_t: Transform3D = get_interaction_transform(target_pos)
	
	if is_instance_valid(state_machine) and state_machine.has_method("transition_to"):
		state_machine.transition_to("PushWheel", {
			"wheel": self,
			"target_transform": target_t
		})


func _check_for_installation() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return

	var current_held_item: Node3D = null
	var int_comp: Node = player.get("interaction_component")
	var scanner: Node = null

	if is_instance_valid(int_comp):
		current_held_item = int_comp.get("held_item")
		scanner = int_comp.get("interaction_scanner")
		
		if not is_instance_valid(current_held_item) and is_instance_valid(scanner):
			current_held_item = scanner.get("held_object")

	if is_instance_valid(current_held_item) and current_held_item is PickableObject:
		if install_cooldown <= 0.0:
			var dist: float = global_position.distance_to(current_held_item.global_position)
			if dist < 2.0: 
				_install_stick(current_held_item, int_comp, scanner)


func _install_stick(held_item: Node3D, int_comp: Node, scanner: Node) -> void:
	print("PushWheel: Removing stick from player hands for installation.")
	
	if is_instance_valid(int_comp) and "held_item" in int_comp:
		int_comp.set("held_item", null)
		
	if is_instance_valid(scanner) and "held_object" in scanner:
		scanner.set("held_object", null)
		if scanner.has_method("set_heavy_lifting"):
			scanner.set_heavy_lifting(false)
		if scanner.get("weapon_holder"):
			scanner.get("weapon_holder").show()

	held_item.queue_free()

	is_installed = true
	is_locked = false

	if is_instance_valid(broken_stubs): 
		broken_stubs.hide()
	if is_instance_valid(restored_handle): 
		restored_handle.show()

	_update_stick_collisions()
	print("PushWheel: Stick Auto-Installed! Wheel is now functional.")


func _detach_stick() -> void:
	if not is_instance_valid(pickable_stick_scene):
		push_warning("PushWheel: Cannot detach. No Pickable Scene assigned!")
		return

	var player: Node3D = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return

	var spawned_stick: Node3D = pickable_stick_scene.instantiate()
	if is_instance_valid(outline_material) and "outline_material" in spawned_stick:
		spawned_stick.outline_material = outline_material

	get_tree().current_scene.add_child(spawned_stick)
	
	if is_instance_valid(wheel):
		spawned_stick.global_position = wheel.global_position
		spawned_stick.global_rotation = wheel.global_rotation
	else:
		spawned_stick.global_position = global_position

	var int_comp: Node = player.get("interaction_component")
	var scanner: Node = null
	if is_instance_valid(int_comp):
		scanner = int_comp.get("interaction_scanner")
	
	var hold_pos: Marker3D = player.get("hold_position")
	if is_instance_valid(scanner) and scanner.get("hold_position"):
		hold_pos = scanner.get("hold_position")

	if is_instance_valid(int_comp) and "held_item" in int_comp:
		int_comp.set("held_item", spawned_stick)
		
	if is_instance_valid(scanner) and "held_object" in scanner:
		scanner.set("held_object", spawned_stick)
		if scanner.has_method("set_heavy_lifting"):
			scanner.set_heavy_lifting(true)
		if scanner.get("weapon_holder"):
			scanner.get("weapon_holder").hide()

	if spawned_stick.has_method("pick_up"):
		spawned_stick.pick_up(hold_pos, player)

	is_installed = false
	is_locked = false
	install_cooldown = 1.0
	
	if is_instance_valid(broken_stubs): 
		broken_stubs.show()
	if is_instance_valid(restored_handle): 
		restored_handle.hide()

	_update_stick_collisions()
	print("PushWheel: Stick detached and returned to player hands.")


func _on_focused() -> void:
	if is_locked:
		return
	is_focused = true
	print("PushWheel: Focused by player.")


func _on_unfocused() -> void:
	is_focused = false
	print("PushWheel: Unfocused by player.")


func get_interaction_transform(target_pos: Vector3) -> Transform3D:
	print("PushWheel: Calculating fluid interaction transform for target point.")
	if not is_instance_valid(wheel):
		return global_transform

	var local_pos: Vector3 = wheel.to_local(target_pos)
	var angle: float = atan2(local_pos.z, local_pos.x)

	var angle_step: float = TAU / float(max(1, stick_count))
	var snapped_angle: float = round(angle / angle_step) * angle_step

	var stick_local_dir := Vector3(cos(snapped_angle), 0.0, sin(snapped_angle))
	var stick_center := stick_local_dir * stick_radius

	var tangent := spin_axis.cross(stick_local_dir).normalized()
	var vector_to_target := local_pos - stick_center
	
	var is_right_side: bool = tangent.dot(vector_to_target) > 0.0
	var side_multiplier: float = 1.0 if is_right_side else -1.0

	var stand_local_pos := stick_center + (tangent * push_stand_offset * side_multiplier)

	var global_stand_pos: Vector3 = wheel.to_global(stand_local_pos)
	
	# Keep the player's ground height stable while referencing the hit point
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		global_stand_pos.y = player.global_position.y

	var global_look_target: Vector3 = wheel.to_global(stick_center)
	global_look_target.y = global_stand_pos.y

	var target_transform := Transform3D()
	target_transform.origin = global_stand_pos
	target_transform.basis = Basis.looking_at(global_look_target - global_stand_pos, Vector3.UP)

	if not is_instance_valid(current_active_anchor):
		current_active_anchor = Marker3D.new()
		current_active_anchor.name = "PlayerAnchor"
		wheel.add_child(current_active_anchor)

	current_active_anchor.global_transform = target_transform
	print("PushWheel: Assigned dynamic rotating anchor to wheel.")

	return target_transform


func _update_visual_state() -> void:
	if not is_inside_tree():
		return
		
	print("PushWheel: Updating visual state. Broken variant: ", is_broken_variant)

	if is_broken_variant:
		is_installed = false
		if is_instance_valid(intact_sticks): 
			intact_sticks.hide()
		if is_instance_valid(broken_stubs): 
			broken_stubs.show()
		if is_instance_valid(restored_handle): 
			restored_handle.hide()
	else:
		is_installed = true
		if is_instance_valid(intact_sticks): 
			intact_sticks.show()
		if is_instance_valid(broken_stubs): 
			broken_stubs.hide()
		if is_instance_valid(restored_handle): 
			restored_handle.hide()

	if not Engine.is_editor_hint() and is_instance_valid(wheel):
		_update_stick_collisions()
