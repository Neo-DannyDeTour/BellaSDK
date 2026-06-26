@tool
class_name KeycardPickup
extends Node3D

@export var interact_component: Node
@export var top_face_sprite: Sprite3D

# Drag and drop your saved KeycardData resource here
@export var card_data: KeycardData:
	set(value):
		card_data = value
		_update_texture()


func _ready() -> void:
	if not Engine.is_editor_hint():
		if card_data != null:
			print("KeycardPickup: Initialized in world with ID ", card_data.card_id)
		if interact_component and interact_component.has_signal("interacted"):
			interact_component.interacted.connect(_on_interacted)

	_update_texture()


func _on_interacted(_interactor: Node) -> void:
	if card_data == null:
		print("KeycardPickup: Interaction failed. No card data assigned.")
		return

	print("KeycardPickup: Player interacted. Picking up card ID ", card_data.card_id)
	KeycardSystem.add_card(card_data.card_id)
	queue_free()


func _update_texture() -> void:
	if top_face_sprite == null:
		return

	if card_data != null and card_data.card_texture != null:
		top_face_sprite.texture = card_data.card_texture
	else:
		if not Engine.is_editor_hint():
			print("KeycardPickup: Missing Card Data or Texture.")
