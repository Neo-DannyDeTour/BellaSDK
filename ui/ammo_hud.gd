## Dedicated HUD component displaying current and reserve ammunition numbers.
class_name AmmoHUD
extends Control

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

	if Events.has_signal("weapon_ammo_changed"):
		Events.weapon_ammo_changed.connect(_on_weapon_ammo_changed)

	if Events.has_signal("active_weapon_changed"):
		Events.active_weapon_changed.connect(_on_active_weapon_changed)


## Updates current and reserve ammo counter text.
## [param current] Loaded rounds.
## [param reserve] Spare rounds in inventory.
## [param _capacity] Maximum capacity of weapon magazine.
func _on_weapon_ammo_changed(current: int, reserve: int, _capacity: int) -> void:
	print("AmmoHUD: Updating counter display -> ", current, " / ", reserve)
	if is_instance_valid(current_label):
		current_label.text = str(current)
	if is_instance_valid(reserve_label):
		reserve_label.text = str(reserve)
	show()


## Responds to weapon slot changes.
## [param weapon_id] String identifier of active weapon.
func _on_active_weapon_changed(weapon_id: String) -> void:
	print("AmmoHUD: Active weapon changed to -> ", weapon_id)
	show()
