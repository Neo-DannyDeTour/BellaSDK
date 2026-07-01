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
			
		if is_instance_valid(interact_component) and interact_component.has_signal("interacted"):
			interact_component.interacted.connect(_on_interacted)

	_update_texture()


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
			sys.add_card(card_data.card_id)

	queue_free()


func _update_texture() -> void:
	if not is_instance_valid(top_face_sprite):
		return

	if card_data != null and card_data.card_texture != null:
		top_face_sprite.texture = card_data.card_texture
	else:
		if not Engine.is_editor_hint():
			print("KeycardPickup: Missing Card Data or Texture.")
