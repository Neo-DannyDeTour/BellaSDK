## Unit tests for the Types single source of truth enumeration and bitmask helper functions.
class_name TestTypes
extends GutTest


## Setup method executed before each test case.
func before_each() -> void:
	print("TestTypes: before_each() setup started.")


## Teardown method executed after each test case.
func after_each() -> void:
	print("TestTypes: after_each() cleanup completed.")


## Verifies conversion of ItemCategory enum values to human-readable display strings.
func test_item_category_to_string() -> void:
	print("TestTypes: test_item_category_to_string() executing.")
	assert_eq(
		Types.item_category_to_string(Types.ItemCategory.WEAPON),
		"Weapon",
		"WEAPON category should resolve to 'Weapon'."
	)
	assert_eq(
		Types.item_category_to_string(Types.ItemCategory.AMMO),
		"Ammunition",
		"AMMO category should resolve to 'Ammunition'."
	)
	assert_eq(
		Types.item_category_to_string(Types.ItemCategory.KEYCARD),
		"Keycard",
		"KEYCARD category should resolve to 'Keycard'."
	)
	assert_eq(
		Types.item_category_to_string(Types.ItemCategory.CONSUMABLE),
		"Consumable",
		"CONSUMABLE category should resolve to 'Consumable'."
	)
	assert_eq(
		Types.item_category_to_string(Types.ItemCategory.NOTE),
		"Document",
		"NOTE category should resolve to 'Document'."
	)
	assert_eq(
		Types.item_category_to_string(Types.ItemCategory.QUEST),
		"Quest Item",
		"QUEST category should resolve to 'Quest Item'."
	)
	assert_eq(
		Types.item_category_to_string(Types.ItemCategory.NONE),
		"Item",
		"NONE category should resolve to default 'Item'."
	)


## Verifies conversion of Faction enum values to human-readable display strings.
func test_faction_to_string() -> void:
	print("TestTypes: test_faction_to_string() executing.")
	assert_eq(
		Types.faction_to_string(Types.Faction.PLAYER),
		"Player",
		"PLAYER faction should resolve to 'Player'."
	)
	assert_eq(
		Types.faction_to_string(Types.Faction.ENEMY),
		"Hostile",
		"ENEMY faction should resolve to 'Hostile'."
	)
	assert_eq(
		Types.faction_to_string(Types.Faction.CIVILIAN),
		"Civilian",
		"CIVILIAN faction should resolve to 'Civilian'."
	)
	assert_eq(
		Types.faction_to_string(Types.Faction.NEUTRAL),
		"Neutral",
		"NEUTRAL faction should resolve to 'Neutral'."
	)
	assert_eq(
		Types.faction_to_string(Types.Faction.TARGET),
		"Target",
		"TARGET faction should resolve to 'Target'."
	)
	assert_eq(
		Types.faction_to_string(Types.Faction.NONE),
		"None",
		"NONE faction should resolve to 'None'."
	)


## Verifies conversion of DamageType enum values to human-readable display strings.
func test_damage_type_to_string() -> void:
	print("TestTypes: test_damage_type_to_string() executing.")
	assert_eq(
		Types.damage_type_to_string(Types.DamageType.PHYSICAL),
		"Kinetic",
		"PHYSICAL damage should resolve to 'Kinetic'."
	)
	assert_eq(
		Types.damage_type_to_string(Types.DamageType.FIRE),
		"Thermal",
		"FIRE damage should resolve to 'Thermal'."
	)
	assert_eq(
		Types.damage_type_to_string(Types.DamageType.ELECTRIC),
		"Electric",
		"ELECTRIC damage should resolve to 'Electric'."
	)
	assert_eq(
		Types.damage_type_to_string(Types.DamageType.STEAM),
		"Scald",
		"STEAM damage should resolve to 'Scald'."
	)
	assert_eq(
		Types.damage_type_to_string(Types.DamageType.FALL),
		"Impact",
		"FALL damage should resolve to 'Impact'."
	)
	assert_eq(
		Types.damage_type_to_string(Types.DamageType.TOXIC),
		"Biohazard",
		"TOXIC damage should resolve to 'Biohazard'."
	)
	assert_eq(
		Types.damage_type_to_string(Types.DamageType.GENERIC),
		"Generic",
		"GENERIC damage should resolve to 'Generic'."
	)


## Verifies correctness of composite physics bitmask constants.
func test_collision_masks() -> void:
	print("TestTypes: test_collision_masks() executing.")
	var expected_solid: int = Types.MASK_ENVIRONMENT | Types.MASK_INTERACTIVE
	assert_eq(
		Types.MASK_SOLID_WORLD,
		expected_solid,
		"MASK_SOLID_WORLD should combine MASK_ENVIRONMENT and MASK_INTERACTIVE."
	)

	var expected_combat: int = Types.MASK_PLAYER | Types.MASK_ENEMIES
	assert_eq(
		Types.MASK_COMBAT_ENTITIES,
		expected_combat,
		"MASK_COMBAT_ENTITIES should combine MASK_PLAYER and MASK_ENEMIES."
	)
