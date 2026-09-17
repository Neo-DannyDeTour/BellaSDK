## Manages player weapon slots 1-5, quick switching, and active visibility.
class_name WeaponInventoryComponent
extends Node

## References mapped to inventory slots 0 through 4.
var slots: Array[HitscanWeapon] = [null, null, null, null, null]
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
		if child is HitscanWeapon:
			register_weapon(child as HitscanWeapon)


## Registers a weapon into its preferred slot or first free slot.
func register_weapon(weapon: HitscanWeapon) -> void:
	print("WeaponInventoryComponent: Registering weapon -> ", weapon.weapon_tag)

	# Determine target index (0-based) from weapon's default_slot (1-based)
	var target_idx: int = clampi(weapon.default_slot - 1, 0, slots.size() - 1)

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
	print("WeaponInventoryComponent: Assigned ", weapon.weapon_tag, " to slot ", target_idx + 1)

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
		var w: HitscanWeapon = slots[i]
		if is_instance_valid(w):
			var is_active: bool = i == current_slot_index
			w.visible = is_active
			w.set_process(is_active)
			w.set_physics_process(is_active)

	var active_gun: HitscanWeapon = slots[current_slot_index]
	Events.active_weapon_changed.emit(active_gun.weapon_tag)
	active_gun.sync_ammo_ui()


## Swaps directly back to previously equipped weapon.
func swap_to_previous() -> void:
	print("WeaponInventoryComponent: Fast swapping to previous weapon.")
	if previous_slot_index != -1 and slots[previous_slot_index] != null:
		select_slot(previous_slot_index)


## Fires the active weapon. Called by InteractionScanner.
func shoot_active_weapon() -> void:
	if current_slot_index >= 0 and is_instance_valid(slots[current_slot_index]):
		slots[current_slot_index].shoot(camera)


## Triggers reload on the currently equipped weapon.
func reload_active_weapon() -> void:
	print("WeaponInventoryComponent: reload_active_weapon() called.")
	if current_slot_index >= 0 and is_instance_valid(slots[current_slot_index]):
		slots[current_slot_index].reload()


## Adds ammunition to reserve pool for weapons matching [param target_ammo_type].
## [param target_ammo_type] Identifier string matching weapon ammo types.
## [param amount] Number of rounds to add to reserve.
## [return] True if ammunition was accepted.
func add_ammo(target_ammo_type: StringName, amount: int) -> bool:
	print("WeaponInventoryComponent: Adding ", amount, " rounds of ", target_ammo_type)
	var applied: bool = false

	for weapon: HitscanWeapon in slots:
		if is_instance_valid(weapon) and weapon.ammo_type == target_ammo_type:
			weapon.reserve_ammo += amount
			print(weapon.weapon_tag, ": New reserve ammo count -> ", weapon.reserve_ammo)
			weapon.sync_ammo_ui()
			applied = true

	Events.ammo_collected.emit(target_ammo_type, amount)
	return applied
