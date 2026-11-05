## Unit tests for [RenderDiagnosticsPanel] clouds audit and summary banners.
class_name TestDiagnosticsCloudsAudit
extends GutTest


## Lightweight mock overriding RD compute lifecycle methods for headless unit testing.
class MockSunshineClouds:
	extends SunshineCloudsGD

	func initialize_compute() -> void:
		pass

	func clear_compute() -> void:
		pass

	func refresh_compute() -> void:
		pass


## Verifies summary banner formatting across 0, 1, and 2 active compute passes.
func test_format_clouds_summary_banner() -> void:
	print("TestDiagnosticsCloudsAudit: test_format_clouds_summary_banner() called.")
	var panel: RenderDiagnosticsPanel = RenderDiagnosticsPanel.new()
	autofree(panel)

	var empty_records: Array[Dictionary] = []
	var banner_off: String = panel._format_clouds_summary_banner(empty_records)
	assert_true(banner_off.contains("Off (0 active)"), "Empty records should show Off.")

	var single_active: Array[Dictionary] = [{"is_active": true}]
	var banner_one: String = panel._format_clouds_summary_banner(single_active)
	assert_true(banner_one.contains("1 Active Compute"), "Single record should show 1 Active.")

	var two_active: Array[Dictionary] = [{"is_active": true}, {"is_active": true}]
	var banner_two: String = panel._format_clouds_summary_banner(two_active)
	assert_true(
		banner_two.contains("CRITICAL: 2 ACTIVE COMPUTE PASSES"), "Two should trigger CRITICAL."
	)


## Verifies that _audit_clouds_instances detects multiple active SunshineCloudsGD passes.
func test_audit_detects_multiple_clouds_in_compositors() -> void:
	print("TestDiagnosticsCloudsAudit: test_audit_detects_multiple_clouds_in_compositors() called.")
	var ui_scene: Node = preload("res://ui/ui.tscn").instantiate()
	add_child_autofree(ui_scene)

	var panel: RenderDiagnosticsPanel = (
		ui_scene.find_child("DiagnosticsPanel", true, false) as RenderDiagnosticsPanel
	)
	assert_not_null(panel, "DiagnosticsPanel must be present in ui.tscn.")

	var world_env: WorldEnvironment = WorldEnvironment.new()
	var comp: Compositor = Compositor.new()
	var cloud1: MockSunshineClouds = MockSunshineClouds.new()
	var cloud2: MockSunshineClouds = MockSunshineClouds.new()
	cloud1.enabled = true
	cloud2.enabled = true

	var effects: Array[CompositorEffect] = [cloud1, cloud2]
	comp.compositor_effects = effects
	world_env.compositor = comp
	add_child_autofree(world_env)

	var audited: Array[Dictionary] = panel._audit_clouds_instances()
	var active_count: int = 0
	for rec: Dictionary in audited:
		var is_act: Variant = rec.get("is_active", false)
		if is_act is bool and is_act:
			active_count += 1

	assert_eq(
		active_count, 2, "Diagnostics audit must detect exactly 2 active cloud compute passes."
	)


## Verifies that _audit_spike_root_causes flags clouds, fence stall, and geometry overload.
func test_spike_root_causes_detection() -> void:
	print("TestDiagnosticsCloudsAudit: test_spike_root_causes_detection() called.")
	var panel: RenderDiagnosticsPanel = RenderDiagnosticsPanel.new()
	autofree(panel)

	var nominal: String = panel._audit_spike_root_causes(5.0, 5.0, 1.0, 5000, 100, [])
	assert_true(nominal.contains("nominal"), "Low metrics should be reported as nominal.")

	var clouds_active: Array[Dictionary] = [{"is_active": true}]
	var spiked: String = panel._audit_spike_root_causes(
		127.0, 120.0, 2.0, 850000, 273, clouds_active
	)
	assert_true(
		spiked.contains("CLOUDS COMPUTE OVERLOAD"),
		"High GPU with clouds should flag CLOUDS COMPUTE OVERLOAD."
	)
	assert_true(
		spiked.contains("VULKAN FENCE STALL"),
		"High GPU and CPU together should flag VULKAN FENCE STALL."
	)
	assert_true(
		spiked.contains("GEOMETRY OVERLOAD"), "Primitives > 200k should flag GEOMETRY OVERLOAD."
	)
