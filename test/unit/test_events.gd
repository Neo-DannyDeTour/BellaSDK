extends GutTest


func before_each() -> void:
	print("TestEvents: Setting up test environment.")


func after_each() -> void:
	print("TestEvents: Tearing down test environment.")


func test_events_singleton_exists() -> void:
	print("TestEvents: Verifying Events singleton exists.")
	assert_not_null(Events, "Events singleton should exist.")


func test_events_has_visual_toggles() -> void:
	print("TestEvents: Verifying visual toggle signals.")
	var hc_signal: bool = Events.has_signal("high_contrast_toggled")
	assert_true(hc_signal, "Should have high_contrast_toggled signal.")

	var cb_signal: bool = Events.has_signal("colorblind_mode_changed")
	assert_true(cb_signal, "Should have colorblind_mode_changed signal.")

	var sub_signal: bool = Events.has_signal("subtitles_toggled")
	assert_true(sub_signal, "Should have subtitles_toggled signal.")

	var console_signal: bool = Events.has_signal("console_toggle_requested")
	assert_true(console_signal, "Should have console_toggle_requested signal.")
