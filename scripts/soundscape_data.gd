extends Resource
class_name SoundscapeData

@export_group("Ambient Loop")
@export var ambient_track: AudioStream

@export_group("Random One-Shots")
@export var random_sounds: Array[AudioStream]
@export var random_volume_db: float = 0.0  # <--- ADD THIS LINE
@export var min_interval: float = 3.0
@export var max_interval: float = 10.0
