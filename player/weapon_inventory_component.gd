class_name WeaponInventoryComponent
extends Node
## Manages player weapon slots 1-5, quick switching, and active visibility.

## Pre-cached action names for inventory slot hotkeys to avoid string allocations.
const SLOT_ACTIONS: Array[StringName] = [
	&"weapon_slot_1",
	&"weapon_slot_2",
	&"weapon_slot_3",
	&"weapon_slot_4",
	&"weapon_slot_5",
]

## Action name for quick swapping to previous weapon slot.
const LAST_WEAPON_ACTION: StringName = &"last_weapon"

## Total number of available weapon inventory slots.
const MAX_SLOT_COUNT: int = 5

## References mapped to inventory slots 0 through 4.
var slots: Array[Node3D] = [null, null, null, null, null]

## Index of currently equipped slot (-1 when empty).
var current_slot_index: int = -1

## Index of previously equipped slot for fast swapping.
var previous_slot_index: int = -1

## Reference to the [member weapon_holder] 3D socket node.
@export var weapon_holder: Node3D

## Reference to the primary player [Camera3D] node.
@export var camera: Camera3D


## Connects child listeners and initializes slot states on ready.
func _ready() -> void:
	print("WeaponInventoryComponent: _ready() called. Initializing inventory.")
	_scan_existing_weapons()


## Intercepts numeric slot hotkeys 1-5 and quick swap with zero allocations.
func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return

	for i: int in range(MAX_SLOT_COUNT):
		var action_name: StringName = SLOT_ACTIONS[i]
		if InputMap.has_action(action_name) and event.is_action_pressed(action_name):
			print("WeaponInventoryComponent: Hotkey pressed for slot ", i + 1)
			select_slot(i)
			get_viewport().set_input_as_handled()
			return

	if InputMap.has_action(LAST_WEAPON_ACTION) and event.is_action_pressed(LAST_WEAPON_ACTION):
		print("WeaponInventoryComponent: Hotkey pressed for last weapon.")
		swap_to_previous()
		get_viewport().set_input_as_handled()


## Scans the [member weapon_holder] node for existing weapons in the scene.
func _scan_existing_weapons() -> void:
	if not is_instance_valid(weapon_holder):
		return
	for child: Node in weapon_holder.get_children():
		if child.has_method("shoot") and child is Node3D:
			register_weapon(child as Node3D)


## Registers a weapon into its preferred slot or first available free slot.
func register_weapon(weapon: Node3D) -> void:
	var weapon_tag_val: Variant = weapon.get("weapon_tag")
	var tag: String = str(weapon_tag_val) if weapon_tag_val != null else String(weapon.name)
	print("WeaponInventoryComponent: Registering weapon -> ", tag)

	var default_slot_val: Variant = weapon.get("default_slot")
	var slot_val: int = int(default_slot_val) if default_slot_val != null else 1
	var target_idx: int = clampi(slot_val - 1, 0, slots.size() - 1)

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
	select_slot(target_idx)


## Equips weapon in slot [param index] and broadcasts [signal Events.active_weapon_changed].
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
	var active_tag_val: Variant = active_gun.get("weapon_tag")
	var active_tag: String = (
		str(active_tag_val) if active_tag_val != null else String(active_gun.name)
	)
	if is_instance_valid(Events) and Events.has_signal("active_weapon_changed"):
		Events.active_weapon_changed.emit(active_tag)
	if active_gun.has_method("sync_ammo_ui"):
		active_gun.call("sync_ammo_ui")


## Swaps directly back to previously equipped weapon slot.
func swap_to_previous() -> void:
	print("WeaponInventoryComponent: Fast swapping to previous weapon.")
	if previous_slot_index != -1 and slots[previous_slot_index] != null:
		select_slot(previous_slot_index)


## Triggers primary fire on the currently equipped weapon in [member slots].
func shoot_active_weapon() -> void:
	print("WeaponInventoryComponent: shoot_active_weapon() called.")
	if current_slot_index >= 0 and is_instance_valid(slots[current_slot_index]):
		if slots[current_slot_index].has_method("shoot"):
			slots[current_slot_index].call("shoot", camera)


## Triggers reload on the currently equipped weapon in [member slots].
func reload_active_weapon() -> void:
	print("WeaponInventoryComponent: reload_active_weapon() called.")
	if current_slot_index >= 0 and is_instance_valid(slots[current_slot_index]):
		if slots[current_slot_index].has_method("reload"):
			slots[current_slot_index].call("reload")


## Adds reserve ammunition to weapons matching [param target_ammo_type].
func add_ammo(target_ammo_type: StringName, amount: int) -> bool:
	print("WeaponInventoryComponent: Adding ", amount, " rounds of ", target_ammo_type)
	var applied: bool = false

	for weapon: Node3D in slots:
		if is_instance_valid(weapon) and weapon.get("ammo_type") == target_ammo_type:
			var res_ammo: int = weapon.get("reserve_ammo") + amount
			weapon.set("reserve_ammo", res_ammo)
			var w_tag: String = str(weapon.get("weapon_tag"))
			print(w_tag, ": New reserve ammo count -> ", res_ammo)
			if weapon.has_method("sync_ammo_ui"):
				weapon.call("sync_ammo_ui")
			applied = true

	if is_instance_valid(Events) and Events.has_signal("ammo_collected"):
		Events.ammo_collected.emit(target_ammo_type, amount)
	return applied
