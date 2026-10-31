## Procedural Gothic gate with a pointed arch, [PowerComponent], and [Area3D].
## Starts closed (red) and opens (eldritch green) when energized by buttons.
@tool
class_name GothicEnergyGate
extends Node3D

## Emitted when [member is_gate_open] changes; passes the new open state.
signal gate_open_state_changed(is_open: bool)

## Emitted when [member is_field_powered] changes; passes powered state.
signal field_power_changed(is_powered: bool)

## Emitted when a [Node3D] enters the central [Area3D] gate threshold.
signal body_entered_field(body: Node3D)

## File path to the spatial gate shader inside the vfx directory.
const SHADER_PATH: String = "res://vfx/gothic_energy_gate.gdshader"

## Metadata tag used to identify and clean up generated child nodes.
const META_PART: StringName = &"generated_gate_part"

## Normalized vertical heights for the 3 side emitters on each pillar.
const EMITTER_RATIOS: PackedFloat32Array = [0.22, 0.50, 0.78]

## Physics mask for Player, Interactive, Debris, and Enemies.
const FIELD_TRIGGER_MASK: int = (
	CollisionLayers.MASK_PLAYER
	| CollisionLayers.MASK_INTERACTIVE
	| CollisionLayers.MASK_DEBRIS
	| CollisionLayers.MASK_ENEMIES
)

## Physics mask for Player (Layer 2) used by the proximity shock detector.
const PLAYER_LAYER_MASK: int = CollisionLayers.MASK_PLAYER

@export_group("Gate Dimensions")
## Inner horizontal width between the left and right Gothic pillars.
@export var gate_width: float = 3.0:
	set(value):
		gate_width = maxf(1.2, value)
		if is_inside_tree():
			_rebuild()

## Height of the vertical stone pillars before the pointed arch begins.
@export var pillar_height: float = 2.8:
	set(value):
		pillar_height = maxf(1.5, value)
		if is_inside_tree():
			_rebuild()

## Vertical rise of the pointed Gothic arch above [member pillar_height].
@export var arch_rise: float = 1.2:
	set(value):
		arch_rise = maxf(0.4, value)
		if is_inside_tree():
			_rebuild()

@export_group("Gate Logic & Power")
## Whether the gate is open (eldritch green). False means closed (red).
@export var is_gate_open: bool = false:
	set(value):
		is_gate_open = value
		if is_inside_tree():
			_apply_gate_state(false)

## Whether the energy barrier itself has power to project the shader field.
@export var is_field_powered: bool = true:
	set(value):
		is_field_powered = value
		if is_inside_tree():
			_apply_gate_state(false)

## Blocks physical passage with a [StaticBody3D] while the gate is closed.
@export var block_passage_when_closed: bool = true:
	set(value):
		block_passage_when_closed = value
		if is_inside_tree():
			_apply_gate_state(false)

## Optional global event name matching [member LogicButton.global_event_name].
@export var listen_event_name: String = ""

## Optional chained nodes notified when this gate opens or closes.
@export var downstream_targets: Array[Node] = []

## Distance in meters at which the player triggers the electricity vignette.
@export var proximity_shock_distance: float = 2.2:
	set(value):
		proximity_shock_distance = maxf(0.25, value)
		if is_inside_tree():
			_update_proximity_shape()

## Whether proximity electricity vignette triggers in both open/closed states.
@export var proximity_shock_when_open: bool = true

@export_group("Shader Colors & Ripples")
## Crimson red color displayed when the gate is closed.
@export var closed_color: Color = Color(0.95, 0.12, 0.18, 1.0):
	set(value):
		closed_color = value
		if is_inside_tree():
			_sync_shader_uniforms()

## Eldritch green color displayed when the gate is open.
@export var open_color: Color = Color(0.18, 0.95, 0.42, 1.0):
	set(value):
		open_color = value
		if is_inside_tree():
			_sync_shader_uniforms()

## Intensity multiplier for the dual-layer swirling Voronoi caustics.
@export var caustic_intensity: float = 1.75:
	set(value):
		caustic_intensity = maxf(0.0, value)
		if is_inside_tree():
			_sync_shader_uniforms()

## Intensity multiplier for the 6 emitter concentric sphere wave patterns.
@export var sphere_ripple_strength: float = 1.35:
	set(value):
		sphere_ripple_strength = maxf(0.0, value)
		if is_inside_tree():
			_sync_shader_uniforms()

## Ring density of the concentric spherical ripples from the 6 emitters.
@export var ripple_frequency: float = 40.0:
	set(value):
		ripple_frequency = maxf(5.0, value)
		if is_inside_tree():
			_sync_shader_uniforms()

## Reference to the internal or attached [PowerComponent] driving gate state.
var power_component: PowerComponent = null

var _stone_mat: StandardMaterial3D
var _iron_mat: StandardMaterial3D
var _brass_mat: StandardMaterial3D
var _crystal_mat: StandardMaterial3D
var _field_mat: ShaderMaterial
var _field_area: Area3D
var _field_col: CollisionShape3D
var _blocker_body: StaticBody3D
var _blocker_col: CollisionShape3D
var _proximity_area: Area3D
var _proximity_col: CollisionShape3D
var _state_tween: Tween
var _current_open_blend: float = 0.0
var _nearby_player: Node3D = null


## Builds the procedural gate, binds [PowerComponent], and connects [Events].
func _ready() -> void:
	print("GothicEnergyGate: Initializing gate '", name, "'.")
	_current_open_blend = 1.0 if is_gate_open else 0.0
	set_physics_process(false)
	_rebuild()

	if not Engine.is_editor_hint():
		_setup_power_component()
		_connect_global_events()


## Computes distance-based electricity vignette intensity when player is near.
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if not is_instance_valid(_nearby_player) or not is_field_powered:
		_clear_proximity_shock()
		return

	if is_gate_open and not proximity_shock_when_open:
		_emit_electricity_vignette(0.0)
		return

	var local_pos: Vector3 = to_local(_nearby_player.global_position)
	var half_w: float = gate_width * 0.5 + 0.35
	var total_h: float = pillar_height + arch_rise

	var dx: float = maxf(0.0, absf(local_pos.x) - half_w)
	var dy: float = maxf(0.0, maxf(-local_pos.y, local_pos.y - total_h))
	var dz: float = absf(local_pos.z)
	var dist: float = sqrt(dx * dx + dy * dy + dz * dz)

	var raw_ratio: float = 1.0 - clampf(dist / proximity_shock_distance, 0.0, 1.0)
	var intensity: float = raw_ratio * raw_ratio
	_emit_electricity_vignette(intensity)


## Opens the gate (eldritch green) or closes it (crimson red) with a tween.
func set_gate_open(open_state: bool) -> void:
	print("GothicEnergyGate: Setting gate open state to ", open_state)
	is_gate_open = open_state
	_apply_gate_state(true)
	_notify_downstream_targets(is_gate_open)
	gate_open_state_changed.emit(is_gate_open)


## Toggles the gate between closed (red) and open (eldritch green).
func toggle_gate() -> void:
	print("GothicEnergyGate: Toggling gate open state to ", not is_gate_open)
	set_gate_open(not is_gate_open)


## Enables or disables the entire shader energy field power state.
func set_field_powered(powered: bool) -> void:
	print("GothicEnergyGate: Setting field power state to ", powered)
	is_field_powered = powered
	_apply_gate_state(true)
	field_power_changed.emit(is_field_powered)


## Receives normalized progress from [method OutputTransmitter3D.transmit_progress].
func set_progress(value: float) -> void:
	print("GothicEnergyGate: set_progress() received -> ", value)
	var clamped: float = clampf(value, 0.0, 1.0)
	is_gate_open = clamped >= 0.5
	_set_open_blend(clamped)
	if is_instance_valid(_blocker_col):
		var should_block: bool = block_passage_when_closed and not is_gate_open and is_field_powered
		_blocker_col.set_deferred(&"disabled", not should_block)


## Forwards power addition to [member power_component] or opens the gate.
func add_power() -> void:
	print("GothicEnergyGate: add_power() called on ", name)
	if is_instance_valid(power_component):
		power_component.add_power()
	else:
		set_gate_open(true)


## Forwards power removal to [member power_component] or closes the gate.
func remove_power() -> void:
	print("GothicEnergyGate: remove_power() called on ", name)
	if is_instance_valid(power_component):
		power_component.remove_power()
	else:
		set_gate_open(false)


## Compatibility hook for [OutputTransmitter3D] calling power_on() directly.
func power_on() -> void:
	print("GothicEnergyGate: power_on() received -> Opening gate.")
	add_power()


## Compatibility hook for [OutputTransmitter3D] calling power_off() directly.
func power_off() -> void:
	print("GothicEnergyGate: power_off() received -> Closing gate.")
	remove_power()


## Propagates open/close power signals to any configured [member downstream_targets].
func _notify_downstream_targets(active: bool) -> void:
	if downstream_targets.is_empty():
		return
	print("GothicEnergyGate: Notifying downstream targets -> active: ", active)
	for target: Node in downstream_targets:
		if not is_instance_valid(target) or target == self:
			continue
		if active:
			if target.has_method(&"add_power"):
				target.call(&"add_power")
			elif target.has_method(&"power_on"):
				target.call(&"power_on")
		else:
			if target.has_method(&"remove_power"):
				target.call(&"remove_power")
			elif target.has_method(&"power_off"):
				target.call(&"power_off")


## Finds or creates a child [PowerComponent] named "PowerComponent".
func _setup_power_component() -> void:
	print("GothicEnergyGate: Configuring PowerComponent integration.")
	var existing: Node = get_node_or_null("PowerComponent")
	if existing is PowerComponent:
		power_component = existing as PowerComponent
	else:
		for child: Node in get_children():
			if child is PowerComponent:
				power_component = child as PowerComponent
				power_component.name = "PowerComponent"
				break

	if not is_instance_valid(power_component):
		power_component = PowerComponent.new()
		power_component.name = "PowerComponent"
		add_child(power_component)

	if not power_component.powered_on.is_connected(_on_power_component_powered_on):
		power_component.powered_on.connect(_on_power_component_powered_on)
	if not power_component.powered_off.is_connected(_on_power_component_powered_off):
		power_component.powered_off.connect(_on_power_component_powered_off)


## Connects to [signal Events.level_event_triggered] for cross-scene buttons.
func _connect_global_events() -> void:
	if is_instance_valid(Events) and Events.has_signal(&"level_event_triggered"):
		if not Events.level_event_triggered.is_connected(_on_level_event_triggered):
			Events.level_event_triggered.connect(_on_level_event_triggered)


## Opens the gate (eldritch green) when [signal PowerComponent.powered_on] fires.
func _on_power_component_powered_on() -> void:
	print("GothicEnergyGate: PowerComponent powered_on -> Opening gate (Eldritch Green).")
	set_gate_open(true)


## Closes the gate (crimson red) when [signal PowerComponent.powered_off] fires.
func _on_power_component_powered_off() -> void:
	print("GothicEnergyGate: PowerComponent powered_off -> Closing gate (Red).")
	set_gate_open(false)


## Responds to [LogicButton] global event broadcasts matching this gate.
func _on_level_event_triggered(event_name: String, is_active: bool) -> void:
	if listen_event_name.is_empty() or event_name != listen_event_name:
		return
	print("GothicEnergyGate: Global event '", event_name, "' -> active: ", is_active)
	set_gate_open(is_active)


## Rebuilds all procedural materials, Gothic geometry, and [Area3D] nodes.
func _rebuild() -> void:
	if not is_inside_tree():
		return

	for child: Node in get_children():
		if is_instance_valid(child) and child.has_meta(META_PART):
			child.queue_free()

	_build_materials()
	_build_gothic_frame()
	_build_energy_field()
	_current_open_blend = 1.0 if is_gate_open else 0.0
	_apply_gate_state(false)


## Creates smooth modern [StandardMaterial3D] resources for stone and metal.
func _build_materials() -> void:
	var stone_noise: FastNoiseLite = FastNoiseLite.new()
	stone_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	stone_noise.frequency = 0.035
	stone_noise.fractal_octaves = 4

	var stone_norm: NoiseTexture2D = NoiseTexture2D.new()
	stone_norm.width = 512
	stone_norm.height = 512
	stone_norm.seamless = true
	stone_norm.as_normal_map = true
	stone_norm.bump_strength = 10.0
	stone_norm.noise = stone_noise

	var stone_rough: NoiseTexture2D = NoiseTexture2D.new()
	stone_rough.width = 512
	stone_rough.height = 512
	stone_rough.seamless = true
	stone_rough.noise = stone_noise

	_stone_mat = StandardMaterial3D.new()
	_stone_mat.albedo_color = Color(0.20, 0.22, 0.21)
	_stone_mat.roughness = 0.86
	_stone_mat.roughness_texture = stone_rough
	_stone_mat.normal_enabled = true
	_stone_mat.normal_texture = stone_norm
	_stone_mat.uv1_triplanar = true
	_stone_mat.uv1_scale = Vector3(0.75, 0.75, 0.75)

	var iron_noise: FastNoiseLite = FastNoiseLite.new()
	iron_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	iron_noise.frequency = 0.07

	var iron_norm: NoiseTexture2D = NoiseTexture2D.new()
	iron_norm.width = 512
	iron_norm.height = 512
	iron_norm.seamless = true
	iron_norm.as_normal_map = true
	iron_norm.bump_strength = 5.0
	iron_norm.noise = iron_noise

	_iron_mat = StandardMaterial3D.new()
	_iron_mat.albedo_color = Color(0.11, 0.13, 0.12)
	_iron_mat.metallic = 0.88
	_iron_mat.roughness = 0.48
	_iron_mat.normal_enabled = true
	_iron_mat.normal_texture = iron_norm
	_iron_mat.uv1_triplanar = true

	_brass_mat = StandardMaterial3D.new()
	_brass_mat.albedo_color = Color(0.42, 0.36, 0.20)
	_brass_mat.metallic = 0.82
	_brass_mat.roughness = 0.38
	_brass_mat.normal_enabled = true
	_brass_mat.normal_texture = iron_norm
	_brass_mat.uv1_triplanar = true

	var init_col: Color = open_color if is_gate_open else closed_color
	_crystal_mat = StandardMaterial3D.new()
	_crystal_mat.albedo_color = init_col.lightened(0.35)
	_crystal_mat.roughness = 0.15
	_crystal_mat.emission_enabled = true
	_crystal_mat.emission = init_col
	_crystal_mat.emission_energy_multiplier = 4.0


## Generates pillars, pointed arch voussoirs, and 6 crystal cage emitters.
func _build_gothic_frame() -> void:
	var half_w: float = gate_width * 0.5
	var root: Node3D = Node3D.new()
	root.name = "GothicFrame"
	root.set_meta(META_PART, true)
	add_child(root)

	for side: float in [-1.0, 1.0]:
		var x_pos: float = side * (half_w + 0.22)

		_add_box_to(root, Vector3(x_pos, 0.14, 0.0), Vector3(0.64, 0.28, 0.64), _stone_mat)
		_add_box_to(root, Vector3(x_pos, 0.34, 0.0), Vector3(0.52, 0.14, 0.52), _stone_mat)

		var p_size: Vector3 = Vector3(0.38, pillar_height, 0.44)
		_add_box_to(root, Vector3(x_pos, pillar_height * 0.5, 0.0), p_size, _stone_mat)
		_add_box_to(root, Vector3(x_pos, pillar_height, 0.0), Vector3(0.54, 0.18, 0.54), _stone_mat)

		var pipe_x: float = side * (half_w + 0.05)
		_add_cyl_to(
			root,
			Vector3(pipe_x, pillar_height * 0.5, 0.15),
			0.035,
			0.035,
			pillar_height,
			12,
			_iron_mat
		)
		_add_cyl_to(
			root,
			Vector3(pipe_x, pillar_height * 0.5, -0.15),
			0.028,
			0.028,
			pillar_height,
			12,
			_iron_mat
		)

		var box_pos: Vector3 = Vector3(x_pos - side * 0.04, pillar_height * 0.88, 0.0)
		_add_box_to(root, box_pos, Vector3(0.28, 0.38, 0.32), _iron_mat)
		_add_box_to(root, box_pos, Vector3(0.30, 0.06, 0.34), _brass_mat)

		for ratio: float in EMITTER_RATIOS:
			var ey: float = pillar_height * ratio
			_build_cage_emitter(root, Vector3(side * half_w, ey, 0.0), -side)

	_build_pointed_arch(root, half_w)


## Builds the pointed Gothic arch segments above [member pillar_height].
func _build_pointed_arch(parent: Node3D, half_w: float) -> void:
	var segments: int = 9
	for side: float in [-1.0, 1.0]:
		for i: int in range(segments):
			var t0: float = float(i) / float(segments)
			var t1: float = float(i + 1) / float(segments)
			var x0: float = side * (half_w + 0.18) * (1.0 - pow(t0, 1.45))
			var y0: float = pillar_height + arch_rise * t0
			var x1: float = side * (half_w + 0.18) * (1.0 - pow(t1, 1.45))
			var y1: float = pillar_height + arch_rise * t1

			var mid: Vector3 = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.0)
			var dx: float = x1 - x0
			var dy: float = y1 - y0
			var seg_len: float = sqrt(dx * dx + dy * dy) + 0.06
			var angle: float = atan2(dy, dx) - PI * 0.5

			var stone_seg: MeshInstance3D = _add_box_to(
				parent, mid, Vector3(0.34, seg_len, 0.46), _stone_mat
			)
			stone_seg.rotation.z = angle
			var iron_rib: MeshInstance3D = _add_box_to(
				parent, mid, Vector3(0.14, seg_len, 0.28), _iron_mat
			)
			iron_rib.rotation.z = angle

			if i % 2 == 1:
				var normal: Vector3 = (
					Vector3(side * cos(angle), sin(angle) * side, 0.0).normalized()
				)
				var spike_pos: Vector3 = mid + normal * 0.28
				var spike: MeshInstance3D = _add_cyl_to(
					parent, spike_pos, 0.0, 0.04, 0.24, 6, _iron_mat
				)
				spike.rotation.z = angle - side * PI * 0.5

	var apex_y: float = pillar_height + arch_rise
	_add_box_to(parent, Vector3(0.0, apex_y + 0.05, 0.0), Vector3(0.36, 0.42, 0.52), _stone_mat)
	_add_box_to(parent, Vector3(0.0, apex_y + 0.05, 0.0), Vector3(0.38, 0.08, 0.54), _brass_mat)
	_add_cyl_to(parent, Vector3(0.0, apex_y + 0.42, 0.0), 0.0, 0.065, 0.38, 8, _iron_mat)


## Constructs a wrought-iron cage emitter with a glowing crystal core.
func _build_cage_emitter(parent: Node3D, pos: Vector3, dir_x: float) -> void:
	var holder: Node3D = Node3D.new()
	parent.add_child(holder)
	holder.position = pos
	holder.rotation.z = -dir_x * PI * 0.5

	_add_cyl_to(holder, Vector3(0.0, -0.04, 0.0), 0.16, 0.18, 0.05, 10, _brass_mat)
	_add_cyl_to(holder, Vector3(0.0, 0.02, 0.0), 0.12, 0.13, 0.07, 10, _iron_mat)
	_add_cyl_to(holder, Vector3(0.0, 0.18, 0.0), 0.11, 0.11, 0.025, 10, _brass_mat)

	_add_cyl_to(holder, Vector3(0.0, 0.09, 0.0), 0.055, 0.01, 0.08, 6, _crystal_mat)
	_add_cyl_to(holder, Vector3(0.0, 0.17, 0.0), 0.0, 0.055, 0.08, 6, _crystal_mat)

	for i: int in range(6):
		var angle: float = float(i) * TAU / 6.0
		var rx: float = cos(angle) * 0.105
		var rz: float = sin(angle) * 0.105
		_add_box_to(holder, Vector3(rx, 0.11, rz), Vector3(0.02, 0.16, 0.02), _iron_mat)
		var tip_pos: Vector3 = Vector3(rx * 0.85, 0.22, rz * 0.85)
		var tip: MeshInstance3D = _add_cyl_to(holder, tip_pos, 0.0, 0.018, 0.07, 4, _iron_mat)
		tip.rotation.z = cos(angle) * 0.35
		tip.rotation.x = -sin(angle) * 0.35


## Creates the shader quad, threshold [Area3D], blocker, and proximity volume.
func _build_energy_field() -> void:
	var total_h: float = pillar_height + arch_rise
	_field_mat = ShaderMaterial.new()
	if ResourceLoader.exists(SHADER_PATH):
		_field_mat.shader = load(SHADER_PATH) as Shader

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(gate_width, total_h)

	var field_inst: MeshInstance3D = MeshInstance3D.new()
	field_inst.name = "EnergyFieldMesh"
	field_inst.set_meta(META_PART, true)
	field_inst.layers = 1
	field_inst.mesh = quad
	field_inst.material_override = _field_mat
	field_inst.position = Vector3(0.0, total_h * 0.5, 0.0)
	add_child(field_inst)

	_field_area = Area3D.new()
	_field_area.name = "EnergyFieldArea3D"
	_field_area.set_meta(META_PART, true)
	_field_area.collision_layer = CollisionLayers.MASK_INTERACTIVE
	_field_area.collision_mask = FIELD_TRIGGER_MASK
	_field_area.position = Vector3(0.0, total_h * 0.5, 0.0)
	add_child(_field_area)

	var field_shape: BoxShape3D = BoxShape3D.new()
	field_shape.size = Vector3(gate_width, total_h, 0.25)
	_field_col = CollisionShape3D.new()
	_field_col.shape = field_shape
	_field_area.add_child(_field_col)

	_blocker_body = StaticBody3D.new()
	_blocker_body.name = "ClosedGateBlocker"
	_blocker_body.set_meta(META_PART, true)
	_blocker_body.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	_blocker_body.collision_mask = CollisionLayers.MASK_NONE
	_blocker_body.position = Vector3(0.0, total_h * 0.5, 0.0)
	add_child(_blocker_body)

	var blocker_shape: BoxShape3D = BoxShape3D.new()
	blocker_shape.size = Vector3(gate_width, total_h, 0.18)
	_blocker_col = CollisionShape3D.new()
	_blocker_col.shape = blocker_shape
	_blocker_body.add_child(_blocker_col)

	_proximity_area = Area3D.new()
	_proximity_area.name = "ProximityShockArea3D"
	_proximity_area.set_meta(META_PART, true)
	_proximity_area.collision_layer = CollisionLayers.MASK_NONE
	_proximity_area.collision_mask = PLAYER_LAYER_MASK
	_proximity_area.position = Vector3(0.0, total_h * 0.5, 0.0)
	add_child(_proximity_area)

	_proximity_col = CollisionShape3D.new()
	_proximity_area.add_child(_proximity_col)
	_update_proximity_shape()

	if not Engine.is_editor_hint():
		_field_area.body_entered.connect(_on_field_body_entered)
		_proximity_area.body_entered.connect(_on_proximity_body_entered)
		_proximity_area.body_exited.connect(_on_proximity_body_exited)


## Updates the [BoxShape3D] dimensions of the proximity shock detector.
func _update_proximity_shape() -> void:
	if not is_instance_valid(_proximity_col):
		return
	var total_h: float = pillar_height + arch_rise
	var prox_shape: BoxShape3D = BoxShape3D.new()
	prox_shape.size = Vector3(
		gate_width + proximity_shock_distance, total_h + 0.5, proximity_shock_distance * 2.0
	)
	_proximity_col.shape = prox_shape


## Applies open/closed colors, collision state, and optional smooth tweening.
func _apply_gate_state(animate: bool) -> void:
	var target_blend: float = 1.0 if is_gate_open else 0.0

	if is_instance_valid(_blocker_col):
		var should_block: bool = block_passage_when_closed and not is_gate_open and is_field_powered
		_blocker_col.set_deferred(&"disabled", not should_block)

	if is_instance_valid(_field_col):
		_field_col.set_deferred(&"disabled", not is_field_powered)

	if animate and is_inside_tree() and not Engine.is_editor_hint():
		if _state_tween and _state_tween.is_valid():
			_state_tween.kill()
		_state_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_state_tween.tween_method(_set_open_blend, _current_open_blend, target_blend, 0.4)
	else:
		_set_open_blend(target_blend)


## Interpolates crystal material and shader blend between red and eldritch green.
func _set_open_blend(blend_val: float) -> void:
	_current_open_blend = clampf(blend_val, 0.0, 1.0)
	var active_col: Color = closed_color.lerp(open_color, _current_open_blend)
	var power_lvl: float = 1.0 if is_field_powered else 0.0

	if is_instance_valid(_crystal_mat):
		_crystal_mat.albedo_color = active_col.lightened(0.35)
		_crystal_mat.emission = active_col
		_crystal_mat.emission_energy_multiplier = 0.3 + power_lvl * 4.0

	_sync_shader_uniforms()


## Pushes current colors, dimensions, and blend state to the shader material.
func _sync_shader_uniforms() -> void:
	if not is_instance_valid(_field_mat):
		return

	var total_h: float = maxf(0.1, pillar_height + arch_rise)
	var power_lvl: float = 1.0 if is_field_powered else 0.0

	_field_mat.set_shader_parameter(&"closed_color", closed_color)
	_field_mat.set_shader_parameter(&"open_color", open_color)
	_field_mat.set_shader_parameter(&"open_blend", _current_open_blend)
	_field_mat.set_shader_parameter(&"energy_level", power_lvl)
	_field_mat.set_shader_parameter(&"caustic_intensity", caustic_intensity)
	_field_mat.set_shader_parameter(&"sphere_ripple_strength", sphere_ripple_strength)
	_field_mat.set_shader_parameter(&"ripple_frequency", ripple_frequency)
	_field_mat.set_shader_parameter(&"aspect_ratio", gate_width / total_h)
	_field_mat.set_shader_parameter(&"arch_spring_ratio", pillar_height / total_h)


## Handles [signal Area3D.body_entered] when a body crosses the gate threshold.
func _on_field_body_entered(body: Node3D) -> void:
	print("GothicEnergyGate: Body entered gate field -> ", body.name)
	body_entered_field.emit(body)


## Starts distance tracking when the player enters the proximity [Area3D].
func _on_proximity_body_entered(body: Node3D) -> void:
	print("GothicEnergyGate: Player entered proximity shock zone -> ", body.name)
	_nearby_player = body
	set_physics_process(true)


## Stops distance tracking and clears electricity vignette on player exit.
func _on_proximity_body_exited(body: Node3D) -> void:
	if body == _nearby_player:
		print("GothicEnergyGate: Player exited proximity shock zone -> ", body.name)
		_clear_proximity_shock()


## Resets proximity player tracking and turns off the electricity vignette.
func _clear_proximity_shock() -> void:
	_nearby_player = null
	set_physics_process(false)
	_emit_electricity_vignette(0.0)


## Broadcasts proximity electricity intensity to [Events] for the HUD overlay.
func _emit_electricity_vignette(intensity: float) -> void:
	if is_instance_valid(Events) and Events.has_signal(&"electricity_vignette_changed"):
		Events.electricity_vignette_changed.emit(intensity)


## Spawns a [BoxMesh] attached to the specified parent [Node3D].
func _add_box_to(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var inst: MeshInstance3D = MeshInstance3D.new()
	inst.layers = 1
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	parent.add_child(inst)
	return inst


## Spawns a [CylinderMesh] attached to the specified parent [Node3D].
func _add_cyl_to(
	parent: Node3D,
	pos: Vector3,
	top_r: float,
	bot_r: float,
	height: float,
	segs: int,
	mat: Material
) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bot_r
	mesh.height = height
	mesh.radial_segments = segs
	var inst: MeshInstance3D = MeshInstance3D.new()
	inst.layers = 1
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	parent.add_child(inst)
	return inst
