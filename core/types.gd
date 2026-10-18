class_name Types
extends RefCounted
## Single source of truth for global enumeration types, category identifiers, and bitmasks.

## Standard item classification categories.
enum ItemCategory {
	NONE,
	WEAPON,
	AMMO,
	KEYCARD,
	CONSUMABLE,
	NOTE,
	QUEST,
}

## Entity team factions formatted as bitflags for relationship and hostility filtering.
enum Faction {
	NONE = 0,
	PLAYER = 1 << 0,
	ENEMY = 1 << 1,
	CIVILIAN = 1 << 2,
	NEUTRAL = 1 << 3,
	TARGET = 1 << 4,
}

## Global game session execution states.
enum GameState {
	BOOT,
	MAIN_MENU,
	LOADING,
	GAMEPLAY,
	PAUSED,
	GAME_OVER,
}

## Elemental and physical damage type classifications.
enum DamageType {
	GENERIC,
	PHYSICAL,
	FIRE,
	ELECTRIC,
	STEAM,
	FALL,
	TOXIC,
}

## Item rarity tiers for visual indicators and pickup drop tables.
enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
}

## Physics collision bitmask for Layer 1 (Environment), aliased to [CollisionLayers].
const MASK_ENVIRONMENT: int = CollisionLayers.MASK_ENVIRONMENT

## Physics collision bitmask for Layer 2 (Player), aliased to [CollisionLayers].
const MASK_PLAYER: int = CollisionLayers.MASK_PLAYER

## Physics collision bitmask for Layer 3 (Interactive), aliased to [CollisionLayers].
const MASK_INTERACTIVE: int = CollisionLayers.MASK_INTERACTIVE

## Physics collision bitmask for Layer 4 (Debris), aliased to [CollisionLayers].
const MASK_DEBRIS: int = CollisionLayers.MASK_DEBRIS

## Physics collision bitmask for Layer 5 (Enemies), aliased to [CollisionLayers].
const MASK_ENEMIES: int = CollisionLayers.MASK_ENEMIES

## Composite bitmask checking solid world geometry, aliased to [CollisionLayers].
const MASK_SOLID_WORLD: int = CollisionLayers.MASK_SOLID_WORLD

## Composite bitmask checking combat targets, aliased to [CollisionLayers].
const MASK_COMBAT_ENTITIES: int = CollisionLayers.MASK_COMBAT_ENTITIES


## Converts an [enum ItemCategory] enum value to a human-readable display string.
static func item_category_to_string(category: ItemCategory) -> String:
	print("[Types] Resolved category string for: ", category)
	match category:
		ItemCategory.WEAPON:
			return "Weapon"
		ItemCategory.AMMO:
			return "Ammunition"
		ItemCategory.KEYCARD:
			return "Keycard"
		ItemCategory.CONSUMABLE:
			return "Consumable"
		ItemCategory.NOTE:
			return "Document"
		ItemCategory.QUEST:
			return "Quest Item"
		_:
			return "Item"


## Converts a [enum Faction] bitflag value to a human-readable display string.
static func faction_to_string(faction: Faction) -> String:
	print("[Types] Resolved faction string for: ", faction)
	match faction:
		Faction.PLAYER:
			return "Player"
		Faction.ENEMY:
			return "Hostile"
		Faction.CIVILIAN:
			return "Civilian"
		Faction.NEUTRAL:
			return "Neutral"
		Faction.TARGET:
			return "Target"
		_:
			return "None"


## Converts a [enum DamageType] enum value to a human-readable display string.
static func damage_type_to_string(damage_type: DamageType) -> String:
	print("[Types] Resolved damage type string for: ", damage_type)
	match damage_type:
		DamageType.PHYSICAL:
			return "Kinetic"
		DamageType.FIRE:
			return "Thermal"
		DamageType.ELECTRIC:
			return "Electric"
		DamageType.STEAM:
			return "Scald"
		DamageType.FALL:
			return "Impact"
		DamageType.TOXIC:
			return "Biohazard"
		_:
			return "Generic"
