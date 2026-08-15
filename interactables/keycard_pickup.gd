@tool
## A 3D world item representing an obtainable keycard.
##
## Reads from an assigned [KeycardData] resource to automatically update its visual sprite
## and broadcast its clearance ID to the global game state when collected.
class_name KeycardPickup
extends Node3D

## The component that handles raycast collisions and generates interaction signals.
@export var interact_component: Node
## The [Sprite3D] node used to render the card's specific face texture.
@export var top_face_sprite: Sprite3D

## The custom [KeycardData] resource defining the clearance level and visuals of this drop.
@export var card_data: KeycardData:
	set(value):
		card_data = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_texture()


## Connects interaction signals and refreshes the sprite based on the assigned data.
func _ready() -> void:
	if not Engine.is_editor_hint():
		if card_data != null:
			print("KeycardPickup: Initialized in world with ID ", card_data.card_id)

		if is_instance_valid(interact_component) and interact_component.has_signal("interacted"):
			interact_component.connect("interacted", _on_interacted)

	_update_texture()


## Triggers global events to register the keycard into the player's inventory and removes the item.
## [param _interactor]: The player character node triggering the pickup.
func _on_interacted(_interactor: Node) -> void:
	if card_data == null:
		print("KeycardPickup: Interaction failed. No card data assigned.")
		return

	print("KeycardPickup: Player interacted. Broadcasting collection of ID: ", card_data.card_id)

	# 1. NEW: Global broadcast for UI, audio, and standard systems
	Events.keycard_collected.emit(card_data.card_id)

	# 2. OPTIONAL FALLBACK: If you still use a dedicated Autoload for the data structure
	if has_node("/root/KeycardSystem"):
		var sys: Node = get_node("/root/KeycardSystem")
		if sys.has_method("add_card"):
			sys.call("add_card", card_data.card_id)

	queue_free()


## Applies the 2D texture from the [KeycardData] resource to the 3D sprite node.
func _update_texture() -> void:
	if not is_instance_valid(top_face_sprite):
		return

	if card_data != null and card_data.card_texture != null:
		top_face_sprite.texture = card_data.card_texture
	else:
		if not Engine.is_editor_hint():
			print("KeycardPickup: Missing Card Data or Texture.")
