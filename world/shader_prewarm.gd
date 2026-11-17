extends Node3D
## Frees shader-prewarm proxy meshes after two rendered frames at startup.

## Number of process frames to keep prewarm meshes alive.
var _frames_left: int = 2


## Enables per-frame countdown on startup.
func _ready() -> void:
	set_process(true)


## Counts down rendered frames and frees this node once shaders have compiled.
func _process(_delta: float) -> void:
	_frames_left -= 1
	if _frames_left <= 0:
		set_process(false)
		queue_free()
