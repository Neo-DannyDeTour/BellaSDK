class_name KeycardData
extends Resource

@export_category("Card Identification")
## The unique ID you will type into your Locks (e.g., "A1", "Red", "Admin")
@export var card_id: StringName = &""

@export_category("Card Visuals")
## Display letter.
@export var display_letter: String = ""
## Optional: Use a String so you can leave it blank, or put "1", "2", etc.
@export var display_number: String = ""
## Card color.
@export var card_color: Color = Color.WHITE
## Card texture.
@export var card_texture: Texture2D
