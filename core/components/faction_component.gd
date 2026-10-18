class_name FactionComponent
extends Node
## Manages entity allegiances, relationship masks, and hostility checks via [Types.Faction].

## Emitted when [member faction] changes. Passes [param old_faction] and [param new_faction].
signal faction_changed(old_faction: Types.Faction, new_faction: Types.Faction)

## Primary [enum Types.Faction] allegiance assigned to this entity.
@export var faction: Types.Faction = Types.Faction.ENEMY

## Bitmask defining which [enum Types.Faction] flags this entity considers hostile.
@export_flags("Player:1", "Enemy:2", "Civilian:4", "Neutral:8", "Target:16")
var hostile_mask: int = 1

## Flag designating if entity is non-combatant and immune to targeting.
@export var is_passive: bool = false


## Initializes component state and logs registration details to output.
func _ready() -> void:
	print("FactionComponent: Initialized on ", get_parent().name, " as faction ", faction)


## Returns true if [param other] matches [member hostile_mask] and is active.
func is_hostile_to(other: FactionComponent) -> bool:
	if other == null or is_passive or other.is_passive:
		return false
	var is_enemy: bool = (hostile_mask & int(other.faction)) != 0
	if is_enemy:
		print("FactionComponent: Target ", other.get_parent().name, " evaluated as hostile.")
	return is_enemy


## Updates [member faction] and broadcasts the [signal faction_changed] signal.
func set_faction(new_faction: Types.Faction) -> void:
	if faction == new_faction:
		return
	print("FactionComponent: Changing faction from ", faction, " to ", new_faction)
	var old: Types.Faction = faction
	faction = new_faction
	faction_changed.emit(old, new_faction)


## Bitwise-adds target [enum Types.Faction] into [member hostile_mask].
func add_hostile_faction(target_faction: Types.Faction) -> void:
	print("FactionComponent: Adding hostile faction flag: ", target_faction)
	hostile_mask |= int(target_faction)


## Locates [FactionComponent] on [param node] or within its child components.
static func get_faction_component(node: Node) -> FactionComponent:
	if node == null:
		return null
	var direct: Node = node.get_node_or_null("Components/FactionComponent")
	if direct is FactionComponent:
		return direct as FactionComponent
	var root_child: Node = node.get_node_or_null("FactionComponent")
	if root_child is FactionComponent:
		return root_child as FactionComponent
	var comp: Node = NodeQuery.find_first_child_of_type(node, FactionComponent)
	if comp is FactionComponent:
		return comp as FactionComponent
	return null
