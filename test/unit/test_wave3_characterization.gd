## Characterization tests locking Wave 3 public APIs, constants, and behavior.
class_name TestWave3Characterization
extends GutTest


## Verifies all existing [CollisionLayers] physics and render layer constants.
func test_collision_layers_constants() -> void:
	assert_eq(CollisionLayers.LAYER_ENVIRONMENT_IDX, 1)
	assert_eq(CollisionLayers.LAYER_PLAYER_IDX, 2)
	assert_eq(CollisionLayers.LAYER_INTERACTIVE_IDX, 3)
	assert_eq(CollisionLayers.LAYER_DEBRIS_IDX, 4)
	assert_eq(CollisionLayers.LAYER_ENEMIES_IDX, 5)
	assert_eq(CollisionLayers.MASK_NONE, 0)
	assert_eq(CollisionLayers.MASK_ENVIRONMENT, 1 << 0)
	assert_eq(CollisionLayers.MASK_PLAYER, 1 << 1)
	assert_eq(CollisionLayers.MASK_INTERACTIVE, 1 << 2)
	assert_eq(CollisionLayers.MASK_DEBRIS, 1 << 3)
	assert_eq(CollisionLayers.MASK_ENEMIES, 1 << 4)
	assert_eq(CollisionLayers.MASK_ALL, 0xFFFFFFFF)
	assert_eq(
		CollisionLayers.MASK_SOLID_WORLD,
		CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_INTERACTIVE
	)
	assert_eq(
		CollisionLayers.MASK_COMBAT_ENTITIES,
		CollisionLayers.MASK_PLAYER | CollisionLayers.MASK_ENEMIES
	)
	assert_eq(CollisionLayers.RENDER_LAYER_ENVIRONMENT_IDX, 1)
	assert_eq(CollisionLayers.RENDER_LAYER_PLAYER_IDX, 2)
	assert_eq(CollisionLayers.RENDER_LAYER_INTERACTIVE_IDX, 3)
	assert_eq(CollisionLayers.RENDER_LAYER_PORTALS_IDX, 4)
	assert_eq(CollisionLayers.RENDER_LAYER_VOLUMETRICS_IDX, 10)
	assert_eq(CollisionLayers.RENDER_MASK_NONE, 0)
	assert_eq(CollisionLayers.RENDER_MASK_VOLUMETRICS, 1 << 9)
	assert_eq(CollisionLayers.RENDER_MASK_ALL, 0xFFFFF)


## Verifies [MathUtils.damped_spring] and [MathUtils.damped_spring_v3] return dictionary keys.
func test_math_utils_damped_spring_contract() -> void:
	var scalar_res: Dictionary = MathUtils.damped_spring(0.0, 10.0, 0.0, 100.0, 10.0, 0.016)
	assert_true(scalar_res.has(&"position"), 'damped_spring should return &"position" key')
	assert_true(scalar_res.has(&"velocity"), 'damped_spring should return &"velocity" key')
	var scalar_pos: float = scalar_res[&"position"] as float
	var scalar_vel: float = scalar_res[&"velocity"] as float
	assert_gt(scalar_pos, 0.0)
	assert_gt(scalar_vel, 0.0)

	var vec_res: Dictionary = MathUtils.damped_spring_v3(
		Vector3.ZERO, Vector3(10.0, 0.0, 0.0), Vector3.ZERO, 100.0, 10.0, 0.016
	)
	assert_true(vec_res.has(&"position"), 'damped_spring_v3 should return &"position" key')
	assert_true(vec_res.has(&"velocity"), 'damped_spring_v3 should return &"velocity" key')
	var vec_pos: Vector3 = vec_res[&"position"] as Vector3
	assert_gt(vec_pos.x, 0.0)


## Verifies [PowerComponent] threshold tracking, clamping, and signals.
func test_power_component_behavior() -> void:
	var power: PowerComponent = PowerComponent.new()
	power.required_power = 2
	add_child_autofree(power)
	watch_signals(power)

	assert_eq(power.current_power, 0)
	assert_false(power.is_powered)

	power.add_power()
	assert_eq(power.current_power, 1)
	assert_false(power.is_powered)
	assert_signal_not_emitted(power, "powered_on")

	power.add_power()
	assert_eq(power.current_power, 2)
	assert_true(power.is_powered)
	assert_signal_emitted(power, "powered_on")

	power.remove_power()
	assert_eq(power.current_power, 1)
	assert_false(power.is_powered)
	assert_signal_emitted(power, "powered_off")

	power.remove_power()
	power.remove_power()
	assert_eq(power.current_power, 0, "remove_power should clamp at 0")

	power.required_power = 0
	assert_eq(power.required_power, 1, "required_power setter should clamp to >= 1")


## Verifies [FrameGraph] defaults and visible-gated history sampling.
func test_frame_graph_sampling() -> void:
	var graph: FrameGraph = FrameGraph.new()
	add_child_autofree(graph)

	assert_eq(graph.max_points, 100)
	assert_almost_eq(graph.target_ms, 16.67, 0.001)
	assert_almost_eq(graph.ceiling_ms, 33.33, 0.001)

	graph.visible = false
	graph._process(0.016)
	assert_eq(graph.history.size(), 0, "Hidden FrameGraph should not record samples")

	graph.visible = true
	graph.max_points = 3
	graph._process(0.01)
	graph._process(0.02)
	graph._process(0.03)
	graph._process(0.04)
	assert_eq(graph.history.size(), 3, "History should cap at max_points")
	assert_almost_eq(graph.history[0], 20.0, 0.01)
	assert_almost_eq(graph.history[2], 40.0, 0.01)


## Verifies [RenderingContext] push constant alignment and descriptor helpers.
func test_rendering_context_pure_helpers() -> void:
	var packed: PackedByteArray = RenderingContext.create_push_constant([42, true, 1.5])
	assert_eq(packed.size(), 16, "Push constant should pad to 16-byte alignment")
	assert_eq(packed.decode_s32(0), 42)
	assert_eq(packed.decode_s32(4), 1)
	assert_almost_eq(packed.decode_float(8), 1.5, 0.0001)
	assert_eq(packed.decode_s32(12), 0)

	var dq: RenderingContext.DeletionQueue = RenderingContext.DeletionQueue.new()
	var rid_a: RID = RID()
	var pushed: RID = dq.push(rid_a)
	assert_eq(pushed, rid_a)
	assert_eq(dq.queue.size(), 1)
	dq.flush(null)
	assert_eq(dq.queue.size(), 0)

	var desc: RenderingContext.Descriptor = RenderingContext.Descriptor.new(
		RID(), RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	)
	assert_eq(desc.type, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)


## Verifies [TextureBaker] enums, contrast constant, and shader color naming.
func test_texture_baker_enums_and_helpers() -> void:
	assert_eq(TextureBaker.BakeResolution.RES_256, 256)
	assert_eq(TextureBaker.BakeResolution.RES_1024, 1024)
	assert_eq(TextureBaker.BakeResolution.RES_4096, 4096)
	assert_eq(TextureBaker.ArchitectureType.NONE, 0)
	assert_eq(TextureBaker.ArchitectureType.STAIRS, 8)
	assert_almost_eq(TextureBaker.CONTRAST_SHIFT, 0.12, 0.0001)

	var baker: TextureBaker = TextureBaker.new()
	add_child_autofree(baker)
	assert_eq(baker._get_color_name_from_shader(), "unknown")

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var shader: Shader = Shader.new()
	shader.code = "shader_type spatial;\nuniform vec4 bg_color_a : source_color;"
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("bg_color_a", Color(0.5, 0.5, 0.5, 1.0))
	mesh_inst.mesh = QuadMesh.new()
	mesh_inst.set_surface_override_material(0, mat)
	baker.background_mesh = mesh_inst
	baker.add_child(mesh_inst)
	assert_eq(baker._get_color_name_from_shader(), "grey")

	mat.set_shader_parameter("bg_color_a", Color(1.0, 0.0, 0.0, 1.0))
	assert_eq(baker._get_color_name_from_shader(), "red")


## Verifies [WaveCascadeParameters] defaults, clamping, and [signal scale_changed].
func test_wave_cascade_parameters() -> void:
	var params: WaveCascadeParameters = WaveCascadeParameters.new()
	watch_signals(params)

	assert_eq(params.tile_length, Vector2(50.0, 50.0))
	assert_almost_eq(params.wind_speed, 20.0, 0.001)
	assert_almost_eq(params.fetch_length, 550.0, 0.001)
	assert_true(params.should_generate_spectrum)

	params.should_generate_spectrum = false
	params.wind_speed = -5.0
	assert_almost_eq(params.wind_speed, 0.0001, 0.00001)
	assert_true(params.should_generate_spectrum)

	params.fetch_length = 0.0
	assert_almost_eq(params.fetch_length, 0.0001, 0.00001)

	params.displacement_scale = 1.5
	assert_signal_emitted(params, "scale_changed")


## Verifies [SoundscapeData] default resource configuration.
func test_soundscape_data_defaults() -> void:
	var data: SoundscapeData = SoundscapeData.new()
	assert_null(data.ambient_track)
	assert_eq(data.random_sounds.size(), 0)
	assert_almost_eq(data.random_volume_db, 0.0, 0.001)
	assert_almost_eq(data.min_interval, 3.0, 0.001)
	assert_almost_eq(data.max_interval, 10.0, 0.001)


## Verifies [BasaltMagnet], [CablePoint3D], and [PhysicsCurtain] defaults and ready hooks.
func test_interactable_leaf_defaults() -> void:
	var magnet: BasaltMagnet = BasaltMagnet.new()
	assert_almost_eq(magnet.push_force, 5.0, 0.001)
	assert_almost_eq(magnet.effect_radius, 5.0, 0.001)
	add_child_autofree(magnet)
	assert_false(magnet.visible, "BasaltMagnet should hide itself at runtime")

	var cable_pt: CablePoint3D = CablePoint3D.new()
	add_child_autofree(cable_pt)
	assert_almost_eq(cable_pt.droop, 2.0, 0.001)
	assert_eq(cable_pt.segments, 10)

	var curtain: PhysicsCurtain = PhysicsCurtain.new()
	curtain.default_stiffness = 0.75
	add_child_autofree(curtain)
	assert_almost_eq(curtain.linear_stiffness, 0.75, 0.001)
	curtain.is_interactable = false
	curtain.tug_curtain(2.0)
	assert_almost_eq(curtain.linear_stiffness, 0.75, 0.001)


## Verifies [HexShield] layer setup, dimension syncing, damage, and shatter signal.
func test_hex_shield_damage_and_shatter() -> void:
	var shield: HexShield = HexShield.new()
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	shield.add_child(mesh_inst)
	shield.add_child(col_shape)
	shield.max_health = 50
	shield.shield_size = Vector2(4.0, 2.5)
	add_child_autofree(shield)
	watch_signals(shield)

	assert_eq(shield.collision_layer, HexShield.LAYER_ENEMIES)
	assert_eq(shield.collision_mask, 0)
	var quad: QuadMesh = mesh_inst.mesh as QuadMesh
	assert_not_null(quad)
	assert_eq(quad.size, Vector2(4.0, 2.5))
	var box: BoxShape3D = col_shape.shape as BoxShape3D
	assert_not_null(box)
	assert_eq(box.size, Vector3(4.0, 2.5, shield.collider_thickness))

	shield.shield_size = Vector2(0.01, 0.01)
	assert_eq(shield.shield_size, Vector2(0.2, 0.2), "shield_size should clamp to >= 0.2")

	shield.take_damage(20, Vector3.ZERO)
	assert_signal_not_emitted(shield, "shield_shattered")
	shield.take_damage(30, Vector3.ZERO)
	assert_signal_emitted(shield, "shield_shattered")


## Verifies [HissResonanceVolume] render layer assignment and resonance signals.
func test_hiss_resonance_volume() -> void:
	var volume: HissResonanceVolume = HissResonanceVolume.new()
	var effect_mesh: MeshInstance3D = MeshInstance3D.new()
	effect_mesh.name = "EffectMesh"
	volume.add_child(effect_mesh)
	add_child_autofree(volume)
	watch_signals(volume)

	assert_eq(HissResonanceVolume.VOLUMETRIC_RENDER_LAYER, 512)
	assert_eq(effect_mesh.layers, 512)

	var dummy_body: Node3D = Node3D.new()
	add_child_autofree(dummy_body)
	volume._on_body_entered(dummy_body)
	assert_signal_emitted_with_parameters(volume, "resonance_state_changed", [true])
	volume._on_body_exited(dummy_body)
	assert_signal_emitted_with_parameters(volume, "resonance_state_changed", [false])


## Verifies [RotatingLamp] visuals, toggle state, and [WindController] rotation tracking.
func test_rotating_lamp_and_wind_controller() -> void:
	var lamp: RotatingLamp = RotatingLamp.new()
	var rotor: Node3D = Node3D.new()
	rotor.name = "Rotor"
	var spot: SpotLight3D = SpotLight3D.new()
	spot.name = "SpotLight3D"
	var light_mesh: MeshInstance3D = MeshInstance3D.new()
	light_mesh.name = "LightMesh"
	light_mesh.mesh = BoxMesh.new()
	rotor.add_child(spot)
	rotor.add_child(light_mesh)
	lamp.add_child(rotor)
	add_child_autofree(lamp)

	assert_true(lamp.is_active)
	lamp.lamp_energy = 7.5
	assert_almost_eq(spot.light_energy, 7.5, 0.001)
	lamp.toggle_lamp()
	assert_false(lamp.is_active)
	assert_false(spot.visible)

	var wind: WindController = WindController.new()
	add_child_autofree(wind)
	assert_almost_eq(wind.wind_intensity, 1.0, 0.001)
	assert_almost_eq(wind.wind_speed, 1.0, 0.001)
	wind.rotate_y(0.5)
	wind._process(0.016)
	assert_true(wind.previous_rotation.is_equal_approx(wind.basis))


## Verifies [AutoScrollContainer] and [DoorSlide] initial state contracts.
func test_auto_scroll_and_door_slide_defaults() -> void:
	var scroll: AutoScrollContainer = AutoScrollContainer.new()
	var child_ctrl: Control = Control.new()
	scroll.add_child(child_ctrl)
	add_child_autofree(scroll)

	assert_eq(scroll.scrollable, child_ctrl)
	assert_true(scroll.animate)
	assert_almost_eq(scroll.transition_time, 0.2, 0.001)
	assert_eq(scroll.gamepad_scroll_speed, 5)

	var door: DoorSlide = DoorSlide.new()
	var anim: AnimationPlayer = AnimationPlayer.new()
	anim.name = "Anim"
	var timer: Timer = Timer.new()
	timer.name = "CloseTimer"
	door.add_child(anim)
	door.add_child(timer)
	add_child_autofree(door)

	assert_false(door.is_moving)
	assert_false(door.is_open)
	assert_false(door.player_detected)
	assert_false(door.pending_open)
