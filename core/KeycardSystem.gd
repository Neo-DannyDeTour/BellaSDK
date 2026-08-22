## Global autoload that tracks and manages collected keycards.
##
## The [KeycardSystem] is responsible for storing the player's keycard inventory.
## It uses [StringName] identifiers to dynamically support any number of keycards
## without requiring hardcoded enums. It emits signals when cards are acquired
## or consumed.
class_name KeycardSystem
extends Node

## Emitted when a new keycard is added to the inventory.
## [param card_id] The unique [StringName] identifier of the collected card.
signal card_picked_up(card_id: StringName)

## Emitted when a keycard is successfully consumed from the inventory.
## [param card_id] The unique [StringName] identifier of the used card.
signal card_used(card_id: StringName)

## The inventory now dynamically tracks [StringName] IDs instead of Enums.
## Stores all currently held keycard IDs.
var _inventory: Array[StringName] = []


## Adds a keycard to the inventory if it doesn't already exist.
## [param card_id] The unique [StringName] identifier of the card to add.
func add_card(card_id: StringName) -> void:
	print("KeycardSystem: Added card ID ", card_id, " to inventory.")
	if not _inventory.has(card_id):
		_inventory.append(card_id)
		card_picked_up.emit(card_id)


## Checks if a specific keycard is currently in the inventory.
## [param card_id] The unique [StringName] identifier of the card to check.
## Returns [code]true[/code] if the card is held, [code]false[/code] otherwise.
func has_card(card_id: StringName) -> bool:
	return _inventory.has(card_id)


## Removes a keycard from the inventory if it exists.
## [param card_id] The unique [StringName] identifier of the card to consume.
func consume_card(card_id: StringName) -> void:
	print("KeycardSystem: Consumed card ID ", card_id, ".")
	if _inventory.has(card_id):
		_inventory.erase(card_id)
		card_used.emit(card_id)
