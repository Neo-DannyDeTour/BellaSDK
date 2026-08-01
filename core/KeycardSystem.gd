extends Node

signal card_picked_up(card_id: StringName)
signal card_used(card_id: StringName)

# The inventory now dynamically tracks StringName IDs instead of Enums
var _inventory: Array[StringName] = []


func add_card(card_id: StringName) -> void:
	print("KeycardSystem: Added card ID ", card_id, " to inventory.")
	if not _inventory.has(card_id):
		_inventory.append(card_id)
		card_picked_up.emit(card_id)


func has_card(card_id: StringName) -> bool:
	return _inventory.has(card_id)


func consume_card(card_id: StringName) -> void:
	print("KeycardSystem: Consumed card ID ", card_id, ".")
	if _inventory.has(card_id):
		_inventory.erase(card_id)
		card_used.emit(card_id)
