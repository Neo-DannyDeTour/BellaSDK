## Unit tests for FactionComponent verifying allegiance, hostile masks, and target lookup.
class_name TestFactionComponent
extends GutTest

## Primary test instance for FactionComponent.
var _faction_comp: FactionComponent = null

## Secondary test instance for FactionComponent checks.
var _other_faction_comp: FactionComponent = null

## Parent container node for primary component testing.
var _parent_node: Node3D = null

## Parent container node for secondary component testing.
var _other_parent_node: Node3D = null


## Sets up clean FactionComponent test instances and parent nodes.
func before_each() -> void:
	print("TestFactionComponent: before_each() setup started.")
	_parent_node = Node3D.new()
	_parent_node.name = "PrimaryNode"
	_faction_comp = FactionComponent.new()
	_parent_node.add_child(_faction_comp)
	add_child_autofree(_parent_node)

	_other_parent_node = Node3D.new()
	_other_parent_node.name = "SecondaryNode"
	_other_faction_comp = FactionComponent.new()
	_other_parent_node.add_child(_other_faction_comp)
	add_child_autofree(_other_parent_node)


## Tears down component references after test execution.
func after_each() -> void:
	print("TestFactionComponent: after_each() cleanup.")
	_faction_comp = null
	_other_faction_comp = null
	_parent_node = null
	_other_parent_node = null


## Verifies default initial values on FactionComponent.
func test_default_values() -> void:
	print("TestFactionComponent: test_default_values() called.")
	assert_eq(_faction_comp.faction, Types.Faction.ENEMY, "Default faction should be ENEMY.")
	assert_eq(_faction_comp.hostile_mask, 1, "Default hostile mask should be 1 (PLAYER).")
	assert_false(_faction_comp.is_passive, "Default is_passive should be false.")


## Verifies hostility checks between opposing and friendly factions.
func test_is_hostile_to() -> void:
	print("TestFactionComponent: test_is_hostile_to() called.")
	_faction_comp.faction = Types.Faction.ENEMY
	_faction_comp.hostile_mask = int(Types.Faction.PLAYER)

	_other_faction_comp.faction = Types.Faction.PLAYER

	assert_true(
		_faction_comp.is_hostile_to(_other_faction_comp), "Enemy should be hostile to Player."
	)

	_other_faction_comp.faction = Types.Faction.CIVILIAN
	assert_false(
		_faction_comp.is_hostile_to(_other_faction_comp),
		"Enemy should not be hostile to Civilian when mask is 1."
	)


## Verifies passive entity immunity from hostility evaluations.
func test_passive_immunity() -> void:
	print("TestFactionComponent: test_passive_immunity() called.")
	_faction_comp.faction = Types.Faction.ENEMY
	_faction_comp.hostile_mask = int(Types.Faction.PLAYER)
	_other_faction_comp.faction = Types.Faction.PLAYER

	_other_faction_comp.is_passive = true
	assert_false(
		_faction_comp.is_hostile_to(_other_faction_comp),
		"Passive entities should not be considered hostile."
	)

	_other_faction_comp.is_passive = false
	_faction_comp.is_passive = true
	assert_false(
		_faction_comp.is_hostile_to(_other_faction_comp),
		"Passive self should not mark targets hostile."
	)


## Verifies faction setter logic and signal emission.
func test_set_faction() -> void:
	print("TestFactionComponent: test_set_faction() called.")
	watch_signals(_faction_comp)

	_faction_comp.set_faction(Types.Faction.NEUTRAL)
	assert_eq(_faction_comp.faction, Types.Faction.NEUTRAL, "Faction should update to NEUTRAL.")
	assert_signal_emitted_with_parameters(
		_faction_comp, "faction_changed", [Types.Faction.ENEMY, Types.Faction.NEUTRAL]
	)


## Verifies bitwise adding hostile factions to mask.
func test_add_hostile_faction() -> void:
	print("TestFactionComponent: test_add_hostile_faction() called.")
	_faction_comp.hostile_mask = int(Types.Faction.PLAYER)
	_faction_comp.add_hostile_faction(Types.Faction.CIVILIAN)

	var expected_mask: int = int(Types.Faction.PLAYER) | int(Types.Faction.CIVILIAN)
	assert_eq(_faction_comp.hostile_mask, expected_mask, "Hostile mask should include CIVILIAN.")


## Verifies static helper method for locating component on nodes.
func test_get_faction_component() -> void:
	print("TestFactionComponent: test_get_faction_component() called.")
	var found: FactionComponent = FactionComponent.get_faction_component(_parent_node)
	assert_eq(found, _faction_comp, "Should locate direct child FactionComponent.")

	var null_found: FactionComponent = FactionComponent.get_faction_component(null)
	assert_null(null_found, "Should return null for null node input.")
