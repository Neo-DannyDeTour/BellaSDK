## Unit tests for [MuzzleFlash] scenes, Volumetric Render Layer 10, and weapon wiring.
extends GutTest

const REVOLVER_SCENE: PackedScene = preload("res://assets/weapons/revolver.tscn")
const SHOTGUN_SCENE: PackedScene = preload("res://assets/weapons/shotgun.tscn")


## Verifies Revolver mounts MuzzleFlash under MuzzlePoint with intact 5-mesh model.
func test_revolver_mounts_muzzle_flash_and_keeps_five_meshes() -> void:
	var rev: Revolver = REVOLVER_SCENE.instantiate() as Revolver
	add_child_autofree(rev)

	assert_eq(
		rev._mesh_instances.size(), 5, "RevolverModel must retain exactly 5 MeshInstance3D parts."
	)
	var flash: MuzzleFlash = rev.get_node_or_null("MuzzlePoint/MuzzleFlash") as MuzzleFlash
	assert_not_null(flash, "Revolver must mount MuzzleFlash under MuzzlePoint.")
	assert_eq(rev.muzzle_flash, flash, "HitscanWeapon.muzzle_flash must cache MuzzleFlash.")
	_assert_muzzle_flash_invariants(flash, 0.048, 4.8, 5.5, 8, 3)


## Verifies Shotgun mounts MuzzleFlash under MuzzlePoint with heavy blast settings.
func test_shotgun_mounts_muzzle_flash_and_render_layers() -> void:
	var sg: Shotgun = SHOTGUN_SCENE.instantiate() as Shotgun
	add_child_autofree(sg)

	var flash: MuzzleFlash = sg.get_node_or_null("MuzzlePoint/MuzzleFlash") as MuzzleFlash
	assert_not_null(flash, "Shotgun must mount MuzzleFlash under MuzzlePoint.")
	assert_eq(sg.muzzle_flash, flash, "HitscanWeapon.muzzle_flash must cache MuzzleFlash.")
	_assert_muzzle_flash_invariants(flash, 0.070, 8.5, 9.0, 22, 7)


## Verifies firing Revolver and Shotgun triggers MuzzleFlash quads, light, and particles.
func test_firing_weapons_triggers_muzzle_flash() -> void:
	var cam: Camera3D = Camera3D.new()
	add_child_autofree(cam)

	var rev: Revolver = REVOLVER_SCENE.instantiate() as Revolver
	add_child_autofree(rev)
	rev.is_equipped = true
	var rev_fired: bool = rev.shoot(cam)
	assert_true(rev_fired, "Equipped Revolver should fire cleanly.")
	_assert_triggered_state(rev.muzzle_flash)

	var sg: Shotgun = SHOTGUN_SCENE.instantiate() as Shotgun
	add_child_autofree(sg)
	sg.is_equipped = true
	var sg_fired: bool = sg.shoot(cam)
	assert_true(sg_fired, "Equipped Shotgun should fire cleanly.")
	_assert_triggered_state(sg.muzzle_flash)


## Verifies bare .new() HitscanWeapon and Shotgun remain safe without a MuzzleFlash node.
func test_bare_new_weapon_remains_safe_without_muzzle_flash() -> void:
	var cam: Camera3D = Camera3D.new()
	add_child_autofree(cam)

	var bare_shotgun: Shotgun = Shotgun.new()
	add_child_autofree(bare_shotgun)
	bare_shotgun.is_equipped = true
	assert_null(bare_shotgun.muzzle_flash, "Bare Shotgun.new() should have null muzzle_flash.")
	assert_true(
		bare_shotgun.shoot(cam), "Bare Shotgun.new() must shoot safely without MuzzleFlash."
	)


## Checks Render Layer 10, disabled processing, hidden idle state, and particle counts.
func _assert_muzzle_flash_invariants(
	flash: MuzzleFlash,
	expected_duration: float,
	expected_energy: float,
	expected_range: float,
	expected_sparks: int,
	expected_smoke: int
) -> void:
	assert_false(flash.is_processing(), "MuzzleFlash _process must be disabled.")
	assert_false(flash.is_physics_processing(), "MuzzleFlash _physics_process must be disabled.")
	assert_almost_eq(flash.flash_duration, expected_duration, 0.001, "flash_duration mismatch.")
	assert_almost_eq(flash.light_energy_peak, expected_energy, 0.01, "light_energy_peak mismatch.")
	assert_almost_eq(flash.light_range, expected_range, 0.01, "light_range mismatch.")

	var rig: Node3D = flash.get_node_or_null("FlashRig") as Node3D
	assert_not_null(rig, "FlashRig child must exist.")
	assert_false(rig.visible, "FlashRig must start hidden.")
	assert_eq(rig.get_child_count(), 3, "FlashRig must hold 1 star + 2 crossed side jets.")
	for child: Node in rig.get_children():
		assert_true(child is MeshInstance3D, "FlashRig children must be MeshInstance3D.")
		var mesh: MeshInstance3D = child as MeshInstance3D
		assert_eq(
			mesh.layers,
			CollisionLayers.RENDER_MASK_VOLUMETRICS,
			"Flash quad must use Volumetric Render Layer 10 (512)."
		)

	var light: OmniLight3D = flash.get_node_or_null("FlashLight") as OmniLight3D
	assert_not_null(light, "FlashLight OmniLight3D must exist.")
	assert_false(light.shadow_enabled, "FlashLight must disable shadows.")
	assert_eq(light.light_energy, 0.0, "FlashLight must start zeroed.")

	var sparks: GPUParticles3D = flash.get_node_or_null("PowderSparks") as GPUParticles3D
	assert_not_null(sparks, "PowderSparks GPUParticles3D must exist.")
	assert_eq(sparks.layers, CollisionLayers.RENDER_MASK_VOLUMETRICS, "Sparks must use Layer 10.")
	assert_true(sparks.one_shot, "PowderSparks must be one_shot.")
	assert_eq(sparks.amount, expected_sparks, "PowderSparks particle amount mismatch.")

	var smoke: GPUParticles3D = flash.get_node_or_null("BarrelSmoke") as GPUParticles3D
	assert_not_null(smoke, "BarrelSmoke GPUParticles3D must exist.")
	assert_eq(smoke.layers, CollisionLayers.RENDER_MASK_VOLUMETRICS, "Smoke must use Layer 10.")
	assert_false(smoke.local_coords, "BarrelSmoke must use local_coords = false.")
	assert_true(smoke.one_shot, "BarrelSmoke must be one_shot.")
	assert_eq(smoke.amount, expected_smoke, "BarrelSmoke particle amount mismatch.")


## Checks post-trigger active state on FlashRig, FlashLight, and particle emitters.
func _assert_triggered_state(flash: MuzzleFlash) -> void:
	var rig: Node3D = flash.get_node("FlashRig") as Node3D
	var light: OmniLight3D = flash.get_node("FlashLight") as OmniLight3D
	assert_true(rig.visible, "FlashRig should become visible immediately on trigger().")
	assert_gt(light.light_energy, 0.0, "FlashLight energy should spike on trigger().")
