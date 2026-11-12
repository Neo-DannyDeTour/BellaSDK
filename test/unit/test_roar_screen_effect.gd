## Unit tests for monster roar shockwave screen distortion and event handling.
extends GutTest

## Preloaded UI scene containing ScreenEffectsManager and RoarOverlay.
const UI_SCENE: PackedScene = preload("res://ui/ui.tscn")

## Cached UI node instance created per test.
var _ui_instance: Node


## Cleans up instantiated nodes after each test.
func after_each() -> void:
	print("Tearing down roar screen effect test fixture.")
	if is_instance_valid(_ui_instance):
		_ui_instance.queue_free()
		_ui_instance = null


## Validates that monster_roared signal exists on Events singleton.
func test_monster_roared_signal_exists() -> void:
	print("Testing monster_roared signal presence on Events.")
	assert_true(
		Events.has_signal(&"monster_roared"), "Events singleton must declare monster_roared signal."
	)


## Validates that ScreenEffectsManager contains RoarOverlay with ShaderMaterial.
func test_roar_overlay_configured_in_ui() -> void:
	print("Testing RoarOverlay presence and material configuration.")
	_ui_instance = UI_SCENE.instantiate()
	add_child_autofree(_ui_instance)

	var effects_mgr: Node = _ui_instance.get_node_or_null("ScreenEffectsManager")
	assert_not_null(effects_mgr, "ScreenEffectsManager must exist in ui.tscn.")

	var roar_overlay: ColorRect = effects_mgr.get_node_or_null("RoarOverlay") as ColorRect
	assert_not_null(roar_overlay, "RoarOverlay must exist under ScreenEffectsManager.")
	assert_false(roar_overlay.visible, "RoarOverlay must be hidden initially.")

	var shader_mat: ShaderMaterial = roar_overlay.material as ShaderMaterial
	assert_not_null(shader_mat, "RoarOverlay must possess a valid ShaderMaterial.")
	assert_not_null(shader_mat.shader, "ShaderMaterial must hold a valid Shader resource.")


## Validates that emitting monster_roared triggers RoarOverlay visibility and tween.
func test_monster_roared_activates_overlay() -> void:
	print("Testing RoarOverlay activation on monster_roared signal.")
	_ui_instance = UI_SCENE.instantiate()
	add_child_autofree(_ui_instance)

	var effects_mgr: Node = _ui_instance.get_node_or_null("ScreenEffectsManager")
	var roar_overlay: ColorRect = effects_mgr.get_node_or_null("RoarOverlay") as ColorRect
	assert_not_null(roar_overlay, "RoarOverlay must be present.")

	Events.monster_roared.emit(0.2)
	assert_true(
		roar_overlay.visible, "RoarOverlay must become visible upon monster_roared emission."
	)
