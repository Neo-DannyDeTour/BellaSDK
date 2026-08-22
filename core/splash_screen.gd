## A simple UI node that displays splash screens randomly.
##
## This script picks a random [Texture2D] from the assigned array and shows it,
## waiting a set amount of time before transitioning to the main menu.
class_name SplashScreen
extends Control

## Drag and drop your images into this array in the inspector.
@export var splash_images: Array[Texture2D] = []

## The node used to display the selected texture.
@onready var texture_rect: TextureRect = $TextureRect


## Called when the node enters the scene tree for the first time.
## Randomizes the random number generator, selects a splash image,
## and starts a 3 second delay before loading the next scene.
func _ready() -> void:
	# Randomize the seed so we get a different result every time the game runs
	randomize()

	# Check to make sure the array isn't empty before trying to pull from it
	if splash_images.size() > 0:
		var random_index: int = randi() % splash_images.size()
		texture_rect.texture = splash_images[random_index]

	# Wait for a few seconds before transitioning (e.g., 3 seconds)
	await get_tree().create_timer(3.0).timeout

	# Change to your actual main menu or game scene
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
