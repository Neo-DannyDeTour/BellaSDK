## A resource that stores references to materials for precompilation.
##
## [ShaderCache] is used during loading screens to forcibly compile shaders
## before gameplay starts, preventing stuttering when the materials are first seen.
class_name ShaderCache
extends Resource

## The array of [Material] instances to be compiled.
@export var materials: Array[Material] = []


## Called by the loading system to verify the cache size.
func initialize() -> void:
	print("ShaderCache: Initializing cache with %d materials." % materials.size())
