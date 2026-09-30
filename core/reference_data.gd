class_name ReferenceData
extends Resource
## Palette and texture resource registry mapping enum categories to UI assets.

## Primary brand color for active UI accents and focus indicators.
@export var primary_color: Color = Color(0.12, 0.53, 0.90, 1.0)

## Secondary color for supporting UI elements and subheaders.
@export var secondary_color: Color = Color(0.45, 0.45, 0.50, 1.0)

## Accent color for highlighted interactables and interactive prompts.
@export var accent_color: Color = Color(1.0, 0.75, 0.0, 1.0)

## Danger alert color for health damage, warnings, and hazard zones.
@export var danger_color: Color = Color(0.90, 0.20, 0.20, 1.0)

## Success color for completed objectives and full ammo indicators.
@export var success_color: Color = Color(0.20, 0.85, 0.35, 1.0)

## Dark glass background tint for UI panel backdrops.
@export var dark_glass_color: Color = Color(0.05, 0.05, 0.08, 0.85)

## Default fallback texture assigned when a requested icon is missing.
@export var fallback_texture: Texture2D = null

## Mapping of [enum Types.ItemCategory] integer values to icon textures.
@export var item_category_icons: Dictionary[Types.ItemCategory, Texture2D] = {}


## Resolves an icon texture for a specific item category with fallback support.
func get_category_icon(category: Types.ItemCategory) -> Texture2D:
	if item_category_icons.has(category):
		var tex: Texture2D = item_category_icons[category]
		if is_instance_valid(tex):
			print("[ReferenceData] Retrieved category icon for: ", category)
			return tex
	print("[ReferenceData] Using fallback icon for category: ", category)
	return fallback_texture
