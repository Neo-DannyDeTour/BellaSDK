extends Area3D

@export var trigger_once: bool = true

var triggered: bool = false
@onready var overlay: ColorRect = $CanvasLayer/ColorRect
@onready var anim: AnimationPlayer = $CanvasLayer/ColorRect/AnimationPlayer


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if trigger_once and triggered:
		return

	triggered = true
	anim.play("fade_to_black")
