class_name SoundscapeData
extends Resource

## The background ambient audio track to loop.
@export_group("Ambient Loop")
@export var ambient_track: AudioStream

## An array of random sound effects to play occasionally.
@export_group("Random One-Shots")
@export var random_sounds: Array[AudioStream]
## The volume adjustment for the random one-shot sounds.
@export var random_volume_db: float = 0.0
## Minimum interval in seconds between playing random sounds.
@export var min_interval: float = 3.0
## Maximum interval in seconds between playing random sounds.
@export var max_interval: float = 10.0
