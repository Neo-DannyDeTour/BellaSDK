## A custom [Resource] defining the logic identifiers and visual traits of a keycard.
##
## Assigned to both [KeycardPickup] and [KeycardLock] objects to synchronize clearance levels
## across the game world.
class_name KeycardData
extends Resource

@export_category("Card Identification")
## The unique ID you will type into your Locks (e.g., "A1", "Red", "Admin")
@export var card_id: StringName = &""

@export_category("Card Visuals")
## The primary bold text drawn on the 3D model of the card.
@export var display_letter: String = ""
## Optional secondary text or numbering drawn on the 3D model of the card.
@export var display_number: String = ""
## The base emission color and UI color of the keycard model.
@export var card_color: Color = Color.WHITE
## An optional 2D texture applied to the face of the card mesh.
@export var card_texture: Texture2D
