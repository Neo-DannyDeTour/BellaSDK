class_name MockSystemMenu
extends Node

var is_stunned: bool = false
var is_debug_allowed: bool = false
var is_paused: bool = false
var is_menu_open: bool = false
var flying: bool = false
var noclip_speed_multiplier: float = 8.0


func _init() -> void:
	pass


func toggle_pause() -> void:
	pass


func toggle_noclip() -> void:
	pass


func process_noclip(_delta: float) -> void:
	pass
