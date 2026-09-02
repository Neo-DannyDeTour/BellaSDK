## A custom [Resource] representing a playable chapter in the game.
##
## This resource holds metadata for displaying chapters in the UI
## and loading their respective scenes.
class_name ChapterData
extends Resource

## The display name of the chapter.
@export var chapter_name: String
## A detailed description of the chapter shown in the UI.
@export_multiline var description: String
## A preview image representing the chapter visually.
@export var image: Texture2D
## The absolute file path to the scene (`.tscn` or `.scn`) that this chapter loads.
@export_file("*.scn", "*.tscn") var scene_path: String
