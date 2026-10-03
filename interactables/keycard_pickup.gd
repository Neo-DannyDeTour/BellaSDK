@tool
## Obtains keycard clearance ID and updates visuals via [KeycardData].
class_name KeycardPickup
extends Node3D

## Component handling raycast collisions and interaction signals.
@export var interact_component: Node

## [Sprite3D] node rendering the specific card face texture.
@export var top_face_sprite: Sprite3D

## [KeycardData] resource defining clearance level and visuals.
@export var card_data: KeycardData:
	set(value):
		card_data = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_texture()


## Connects interaction signals and refreshes card texture.
func _ready() -> void:
	print("KeycardPickup: _ready() called.")
	if not Engine.is_editor_hint():
		if card_data != null:
			print("KeycardPickup: Initialized in world with ID ", card_data.card_id)

		if is_instance_valid(interact_component) and interact_component.has_signal("interacted"):
			interact_component.connect("interacted", _on_interacted)

	_update_texture()


## Emits global pickup event and registers card in [KeycardSystem].
func _on_interacted(_interactor: Node) -> void:
	if card_data == null:
		print("KeycardPickup: Interaction failed. No card data assigned.")
		return

	print("KeycardPickup: Player interacted. Broadcasting collection of ID: ", card_data.card_id)
	Events.keycard_collected.emit(card_data.card_id)

	var sys: Node = SystemLocator.get_keycard_system()
	if is_instance_valid(sys) and sys.has_method("add_card"):
		sys.call("add_card", card_data.card_id)

	queue_free()


## Applies texture from [KeycardData] to [member top_face_sprite].
func _update_texture() -> void:
	print("KeycardPickup: _update_texture() called.")
	if not is_instance_valid(top_face_sprite):
		return

	if card_data != null and card_data.card_texture != null:
		top_face_sprite.texture = card_data.card_texture
	else:
		if not Engine.is_editor_hint():
			print("KeycardPickup: Missing Card Data or Texture.")
