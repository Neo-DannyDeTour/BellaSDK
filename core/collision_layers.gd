## Centralized physics and render collision layer constants for [CollisionLayers].
class_name CollisionLayers
extends Object

## Physics layer 1 index for static and procedural environment geometry.
const LAYER_ENVIRONMENT_IDX: int = 1
## Physics layer 2 index for player character colliders.
const LAYER_PLAYER_IDX: int = 2
## Physics layer 3 index for interactive props and puzzle elements.
const LAYER_INTERACTIVE_IDX: int = 3
## Physics layer 4 index for debris and breakable glass shards.
const LAYER_DEBRIS_IDX: int = 4
## Physics layer 5 index for enemies, turrets, and hazards.
const LAYER_ENEMIES_IDX: int = 5

## Bitmask disabling all physics collision layers.
const MASK_NONE: int = 0
## Bitmask matching physics layer 1 environment geometry.
const MASK_ENVIRONMENT: int = 1 << 0
## Bitmask matching physics layer 2 player colliders.
const MASK_PLAYER: int = 1 << 1
## Bitmask matching physics layer 3 interactive objects.
const MASK_INTERACTIVE: int = 1 << 2
## Bitmask matching physics layer 4 debris objects.
const MASK_DEBRIS: int = 1 << 3
## Bitmask matching physics layer 5 enemy entities.
const MASK_ENEMIES: int = 1 << 4
## Bitmask enabling all 32 physics collision layers.
const MASK_ALL: int = 0xFFFFFFFF

## Render layer 1 index for environment models and level geometry.
const RENDER_LAYER_ENVIRONMENT_IDX: int = 1
## Render layer 2 index for player meshes and first-person viewmodels.
const RENDER_LAYER_PLAYER_IDX: int = 2
## Render layer 3 index for interactable object visual meshes.
const RENDER_LAYER_INTERACTIVE_IDX: int = 3
## Render layer 4 index for portal viewports and teleporters.
const RENDER_LAYER_PORTALS_IDX: int = 4
## Render layer 10 index for volumetric lighting and fog passes.
const RENDER_LAYER_VOLUMETRICS_IDX: int = 10

## Cull mask disabling all render layers.
const RENDER_MASK_NONE: int = 0
## Cull mask matching render layer 1 environment visuals.
const RENDER_MASK_ENVIRONMENT: int = 1 << 0
## Cull mask matching render layer 2 player visuals.
const RENDER_MASK_PLAYER: int = 1 << 1
## Cull mask matching render layer 3 interactable visuals.
const RENDER_MASK_INTERACTIVE: int = 1 << 2
## Cull mask matching render layer 4 portal visuals.
const RENDER_MASK_PORTALS: int = 1 << 3
## Cull mask matching render layer 10 volumetric visuals.
const RENDER_MASK_VOLUMETRICS: int = 1 << 9
## Standard 20-bit cull mask enabling all standard render layers.
const RENDER_MASK_ALL: int = 0xFFFFF


## Converts a 1-based layer index into its corresponding single-bit mask.
static func layer_to_mask(layer_index: int) -> int:
	if layer_index < 1 or layer_index > 32:
		return 0
	return 1 << (layer_index - 1)


## Checks if the specified bitmask contains the given 1-based layer index.
static func has_layer(mask: int, layer_index: int) -> bool:
	if layer_index < 1 or layer_index > 32:
		return false
	return (mask & (1 << (layer_index - 1))) != 0
