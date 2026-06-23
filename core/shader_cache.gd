class_name ShaderCache
extends Resource

@export var materials: Array[Material] = []


func initialize() -> void:
	print("ShaderCache: Initializing cache with %d materials." % materials.size())
