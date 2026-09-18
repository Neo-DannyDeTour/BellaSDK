## Manages player weapon slots 1-5, quick switching, and active visibility.
class_name WeaponInventoryComponent
extends Node

## References mapped to inventory slots 0 through 4.
var slots: Array[Node3D] = [null, null, null, null, null]
## Index of currently equipped slot (-1 when empty).
var current_slot_index: int = -1
## Index of previously equipped slot for fast swapping.
var previous_slot_index: int = -1

## Reference to the WeaponHolder 3D socket node.
@export var weapon_holder: Node3D
## Reference to the player camera node.
@export var camera: Camera3D


## Connects child listeners and initializes slot states.
func _ready() -> void:
	print("WeaponInventoryComponent: _ready() called. Initializing inventory.")
	_scan_existing_weapons()


## Intercepts numeric slot hotkeys 1-5 and quick swap.
## [param event] The incoming engine [InputEvent].
func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return

	for i: int in range(5):
		var action_name: StringName = StringName("weapon_slot_" + str(i + 1))
		if InputMap.has_action(action_name) and event.is_action_pressed(action_name):
			print("WeaponInventoryComponent: Hotkey pressed for slot ", i + 1)
			select_slot(i)
			get_viewport().set_input_as_handled()
			return

	if InputMap.has_action(&"last_weapon") and event.is_action_pressed(&"last_weapon"):
		print("WeaponInventoryComponent: Hotkey pressed for last weapon.")
		swap_to_previous()
		get_viewport().set_input_as_handled()


## Scans the WeaponHolder node for weapons already in the scene.
func _scan_existing_weapons() -> void:
	if not is_instance_valid(weapon_holder):
		return
	for child: Node in weapon_holder.get_children():
		if child.has_method("shoot") and child is Node3D:
			register_weapon(child as Node3D)


## Registers a weapon into its preferred slot or first free slot.
func register_weapon(weapon: Node3D) -> void:
	var tag: String = (
		str(weapon.get("weapon_tag")) if weapon.get("weapon_tag") != null else weapon.name
	)
	print("WeaponInventoryComponent: Registering weapon -> ", tag)

	# Determine target index (0-based) from weapon's default_slot (1-based)
	var slot_val: int = int(weapon.get("default_slot")) if weapon.get("default_slot") != null else 1
	var target_idx: int = clampi(slot_val - 1, 0, slots.size() - 1)

	# If preferred slot is occupied by an existing weapon, displace or search free slot
	if slots[target_idx] != null and slots[target_idx] != weapon:
		var placed: bool = false
		for i: int in range(slots.size()):
			if slots[i] == null:
				target_idx = i
				placed = true
				break
		if not placed:
			print("WeaponInventoryComponent: All slots full. Overriding slot ", target_idx + 1)

	slots[target_idx] = weapon
	print("WeaponInventoryComponent: Assigned ", tag, " to slot ", target_idx + 1)

	# Immediately switch to newly acquired weapon
	select_slot(target_idx)


## Selects a specific inventory slot [param index] (0 to 4).
func select_slot(index: int) -> void:
	if index < 0 or index >= slots.size():
		return
	if slots[index] == null:
		print("WeaponInventoryComponent: Slot ", index + 1, " is empty.")
		return
	if current_slot_index == index:
		return

	print("WeaponInventoryComponent: Switching to slot ", index + 1)
	if current_slot_index != -1:
		previous_slot_index = current_slot_index

	current_slot_index = index

	for i: int in range(slots.size()):
		var w: Node3D = slots[i]
		if is_instance_valid(w):
			var is_active: bool = i == current_slot_index
			w.visible = is_active
			w.set_process(is_active)
			w.set_physics_process(is_active)

	var active_gun: Node3D = slots[current_slot_index]
	var active_tag: String = (
		str(active_gun.get("weapon_tag"))
		if active_gun.get("weapon_tag") != null
		else active_gun.name
	)
	if is_instance_valid(Events) and Events.has_signal("active_weapon_changed"):
		Events.active_weapon_changed.emit(active_tag)
	if active_gun.has_method("sync_ammo_ui"):
		active_gun.call("sync_ammo_ui")


## Swaps directly back to previously equipped weapon.
func swap_to_previous() -> void:
	print("WeaponInventoryComponent: Fast swapping to previous weapon.")
	if previous_slot_index != -1 and slots[previous_slot_index] != null:
		select_slot(previous_slot_index)


## Fires the active weapon. Called by InteractionScanner.
func shoot_active_weapon() -> void:
	if current_slot_index >= 0 and is_instance_valid(slots[current_slot_index]):
		if slots[current_slot_index].has_method("shoot"):
			slots[current_slot_index].call("shoot", camera)


## Triggers reload on the currently equipped weapon.
func reload_active_weapon() -> void:
	print("WeaponInventoryComponent: reload_active_weapon() called.")
	if current_slot_index >= 0 and is_instance_valid(slots[current_slot_index]):
		if slots[current_slot_index].has_method("reload"):
			slots[current_slot_index].call("reload")


## Adds ammunition to reserve pool for weapons matching [param target_ammo_type].
## [param target_ammo_type] Identifier string matching weapon ammo types.
## [param amount] Number of rounds to add to reserve.
## [return] True if ammunition was accepted.
func add_ammo(target_ammo_type: StringName, amount: int) -> bool:
	print("WeaponInventoryComponent: Adding ", amount, " rounds of ", target_ammo_type)
	var applied: bool = false

	for weapon: Node3D in slots:
		if is_instance_valid(weapon) and weapon.get("ammo_type") == target_ammo_type:
			var res_ammo: int = int(weapon.get("reserve_ammo")) + amount
			weapon.set("reserve_ammo", res_ammo)
			var w_tag: String = str(weapon.get("weapon_tag"))
			print(w_tag, ": New reserve ammo count -> ", res_ammo)
			if weapon.has_method("sync_ammo_ui"):
				weapon.call("sync_ammo_ui")
			applied = true

	if is_instance_valid(Events) and Events.has_signal("ammo_collected"):
		Events.ammo_collected.emit(target_ammo_type, amount)
	return applied
