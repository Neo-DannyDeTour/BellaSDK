## Unit tests for the 3D articulated [Revolver] scene, rig, and shader layers.
extends GutTest

const REVOLVER_SCENE: PackedScene = preload("res://assets/weapons/revolver.tscn")


## Verifies 3D model, 5 meshes, 5 bones, and world render layer on spawn.
func test_revolver_scene_rig_and_world_layer() -> void:
	var rev: Revolver = REVOLVER_SCENE.instantiate() as Revolver
	add_child_autofree(rev)

	assert_eq(rev._mesh_instances.size(), 5, "RevolverModel should expose 5 MeshInstance3D parts.")
	assert_true(
		is_instance_valid(rev._skeleton), "RevolverModel should contain a valid Skeleton3D."
	)
	assert_gte(rev._cyl_bone_id, 0, "Skeleton3D should contain bone_cylinder.")
	assert_gte(rev._ham_bone_id, 0, "Skeleton3D should contain bone_hammer.")
	assert_gte(rev._trig_bone_id, 0, "Skeleton3D should contain bone_trigger.")
	assert_gte(rev._ejec_bone_id, 0, "Skeleton3D should contain bone_ejector.")

	var first_mesh: MeshInstance3D = rev._mesh_instances[0]
	assert_eq(
		first_mesh.layers,
		Revolver.RENDER_LAYER_INTERACTIVE,
		"Unequipped world revolver should render on Layer 3 (Interactive)."
	)
	assert_true(
		first_mesh.material_override is ShaderMaterial,
		"Revolver meshes should use shared ShaderMaterial override."
	)


## Verifies equipping switches to FPS render layer 2 and firing indexes the cylinder.
func test_revolver_equip_layer_and_fire_cycles_chamber() -> void:
	var rev: Revolver = REVOLVER_SCENE.instantiate() as Revolver
	add_child_autofree(rev)

	var dummy_player: CharacterBody3D = CharacterBody3D.new()
	add_child_autofree(dummy_player)
	var cam: Camera3D = Camera3D.new()
	dummy_player.add_child(cam)
	var holder: Node3D = Node3D.new()
	holder.name = "WeaponHolder"
	cam.add_child(holder)
	var inv: WeaponInventoryComponent = WeaponInventoryComponent.new()
	inv.name = "WeaponInventoryComponent"
	inv.weapon_holder = holder
	dummy_player.add_child(inv)

	rev.equip_to_player(dummy_player)
	assert_true(rev.is_equipped, "Revolver should be marked equipped.")
	assert_eq(
		rev._mesh_instances[0].layers,
		Revolver.RENDER_LAYER_PLAYER,
		"Equipped revolver should render on Layer 2 (Player)."
	)

	rev.visible = true
	var fired: bool = rev.shoot(cam)
	assert_true(fired, "Equipped revolver with ammo should fire.")
	assert_eq(rev._chamber_idx, 1, "Firing should advance cylinder chamber index to 1.")
	assert_gt(rev._heat_level, 0.0, "Firing should increase barrel heat shader level.")
