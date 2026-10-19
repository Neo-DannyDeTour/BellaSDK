## Dedicated HUD component displaying current and reserve ammunition numbers.
class_name AmmoHUD
extends Control

## Toggle state indicating whether infinite reserve ammunition is active.
var is_infinite_ammo: bool = false

## Cached numeric reserve ammo count for restoring upon toggle off.
var _cached_reserve: int = 0

## Label rendering currently loaded ammunition.
@onready var current_label: Label = (
	get_node_or_null("MarginContainer/HBoxContainer/CurrentAmmoLabel") as Label
)

## Label rendering reserve ammunition pool.
@onready var reserve_label: Label = (
	get_node_or_null("MarginContainer/HBoxContainer/ReserveAmmoLabel") as Label
)


## Connects global ammunition and inventory listeners on enter tree.
func _ready() -> void:
	print("AmmoHUD: Initializing ammunition display listeners.")
	hide()

	is_infinite_ammo = GlobalSettings.get_setting_bool("Accessibility", "infinite_ammo", false)

	if Events.has_signal("weapon_ammo_changed"):
		Events.weapon_ammo_changed.connect(_on_weapon_ammo_changed)

	if Events.has_signal("active_weapon_changed"):
		Events.active_weapon_changed.connect(_on_active_weapon_changed)

	if Events.has_signal("infinite_ammo_toggled"):
		Events.infinite_ammo_toggled.connect(_on_infinite_ammo_toggled)


## Cleans up event listeners on exit tree.
func _exit_tree() -> void:
	if (
		Events.has_signal("weapon_ammo_changed")
		and Events.weapon_ammo_changed.is_connected(_on_weapon_ammo_changed)
	):
		Events.weapon_ammo_changed.disconnect(_on_weapon_ammo_changed)

	if (
		Events.has_signal("active_weapon_changed")
		and Events.active_weapon_changed.is_connected(_on_active_weapon_changed)
	):
		Events.active_weapon_changed.disconnect(_on_active_weapon_changed)

	if (
		Events.has_signal("infinite_ammo_toggled")
		and Events.infinite_ammo_toggled.is_connected(_on_infinite_ammo_toggled)
	):
		Events.infinite_ammo_toggled.disconnect(_on_infinite_ammo_toggled)


## Updates current and reserve ammo counter text.
## [param current] Loaded rounds.
## [param reserve] Spare rounds in inventory.
## [param _capacity] Maximum capacity of weapon magazine.
func _on_weapon_ammo_changed(current: int, reserve: int, _capacity: int) -> void:
	print("AmmoHUD: Updating counter display -> ", current, " / ", reserve)
	_cached_reserve = reserve
	if is_instance_valid(current_label):
		current_label.text = str(current)
	if is_instance_valid(reserve_label):
		reserve_label.text = "∞" if is_infinite_ammo else str(reserve)
	show()


## Responds to weapon slot changes.
## [param weapon_id] String identifier of active weapon.
func _on_active_weapon_changed(weapon_id: String) -> void:
	print("AmmoHUD: Active weapon changed to -> ", weapon_id)
	show()


## Responds to infinite ammo toggle changes and refreshes reserve counter.
func _on_infinite_ammo_toggled(enabled: bool) -> void:
	print("AmmoHUD: Infinite ammo toggled -> ", enabled)
	is_infinite_ammo = enabled
	if is_instance_valid(reserve_label):
		reserve_label.text = "∞" if is_infinite_ammo else str(_cached_reserve)
