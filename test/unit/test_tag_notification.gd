## Unit tests for [TagNotification] HUD display, stacked dogtag layout, and dismiss timer.
class_name TestTagNotification
extends GutTest

## The [TagNotification] instance under test.
var tag_hud: TagNotification = null


## Prepares the TagNotification HUD node before each test.
func before_each() -> void:
	print("TestTagNotification: before_each() setup started.")
	tag_hud = TagNotification.new()
	add_child_autofree(tag_hud)
	print("TestTagNotification: before_each() setup completed.")


## Verifies weapon pickup event registers tag and starts dismiss timer.
func test_weapon_pickup_registers_and_starts_timer() -> void:
	print("TestTagNotification: test_weapon_pickup_registers_and_starts_timer() running.")
	Events.weapon_tag_displayed.emit("shotgun")

	var timer: Timer = tag_hud.get_node_or_null("DismissTimer") as Timer
	assert_not_null(timer, "Dismiss timer node should exist as a child.")
	assert_true(timer.is_inside_tree(), "Dismiss timer should be inside tree.")
	assert_false(timer.is_stopped(), "Dismiss timer should be running after pickup.")
	assert_eq(tag_hud._active_weapon, "shotgun", "Active weapon tag should match collected weapon.")


## Verifies re-selecting the same active weapon restarts the timer.
func test_same_weapon_swap_restarts_dismiss_timer() -> void:
	print("TestTagNotification: test_same_weapon_swap_restarts_dismiss_timer() running.")
	Events.weapon_tag_displayed.emit("shotgun")

	var timer: Timer = tag_hud.get_node_or_null("DismissTimer") as Timer
	assert_not_null(timer, "Dismiss timer node should exist.")

	# Advance time slightly:
	timer.start(1.0)
	assert_almost_eq(timer.time_left, 1.0, 0.1, "Timer was modified for test.")

	# Re-selecting shotgun should restart timer back to full DISPLAY_DURATION:
	Events.active_weapon_changed.emit("shotgun")
	assert_almost_eq(
		timer.time_left,
		TagNotification.DISPLAY_DURATION,
		0.1,
		"Dismiss timer should be reset to full DISPLAY_DURATION on same weapon selection."
	)


## Verifies swapping between collected weapons updates active weapon and restarts timer.
func test_swap_between_collected_weapons() -> void:
	print("TestTagNotification: test_swap_between_collected_weapons() running.")
	Events.weapon_tag_displayed.emit("shotgun")
	Events.weapon_tag_displayed.emit("revolver")

	assert_eq(tag_hud._active_weapon, "revolver", "Active weapon should be revolver.")

	Events.active_weapon_changed.emit("shotgun")
	assert_eq(tag_hud._active_weapon, "shotgun", "Active weapon should swap to shotgun.")

	var timer: Timer = tag_hud.get_node_or_null("DismissTimer") as Timer
	assert_not_null(timer, "Dismiss timer node should exist.")
	assert_false(timer.is_stopped(), "Timer should be active after weapon swap.")
