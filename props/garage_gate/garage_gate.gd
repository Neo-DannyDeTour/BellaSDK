@tool
## Procedural sectional garage gate controller.
## Drives a 2-stage opening sequence: Phase 1 expands vertical slack between panels to expose
## peeking slots at eye level; Phase 2 pulls the separated panels up the curved overhead track.
# class_name GarageGate
extends Node3D

## Emitted when the gate finishes opening or closing; [param is_open] reports the new state.
signal gate_state_changed(is_open: bool)

## Total number of articulated panel segments.
const PANEL_COUNT: int = 4
## Total width of each panel in meters.
const PANEL_WIDTH: float = 3.0
## Total height of each panel in meters including interlocking teeth.
const PANEL_HEIGHT: float = 0.60
## Thickness of panel slabs in meters.
const PANEL_DEPTH: float = 0.05
## Separation gap in meters exposed during Phase 1 slack expansion.
const SLACK_GAP: float = 0.038
## Normalized timeline fraction reserved for vertical tooth unseating.
const PHASE_1_RATIO: float = 0.15
## Height in meters of vertical track segment before overhead bend.
const TRACK_VERTICAL_H: float = 2.05
## Radius in meters of the 90-degree track curve transition.
const TRACK_RADIUS: float = 0.35
## Length in meters of horizontal overhead track run.
const TRACK_HORIZONTAL_L: float = 2.40
## Maximum linear distance in meters traveled along guide track.
const MAX_TRAVEL_DIST: float = 2.35
## Maximum 3D audible range in meters for the gate motor player.
const MOTOR_AUDIO_MAX_DIST: float = 25.0
## Fade-out duration in seconds when stopping the motor audio loop.
const MOTOR_FADE_OUT_SEC: float = 0.15
## Audio bus name used for gate sound effects.
const SFX_BUS: StringName = &"SFX"
## Pre-allocated shader parameter name for per-panel grime variation.
const PARAM_WEAR_OFFSET: StringName = &"wear_offset"
## Preloaded default glTF asset containing panel and frame meshes.
const DEFAULT_GATE_GLB: PackedScene = preload("res://props/garage_gate/garage_gate.glb")
## Preloaded default panel shader material with instance uniform support.
const DEFAULT_PANEL_MAT: ShaderMaterial = preload("res://props/garage_gate/garage_panel_mat.tres")
## Preloaded default weathered galvanized steel material for the static frame.
const DEFAULT_FRAME_MAT: Material = preload("res://props/garage_gate/garage_frame_mat.tres")
## Preloaded default continuous motor audio stream.
const DEFAULT_MOTOR_SFX: AudioStream = preload("res://props/garage_gate/sfx/gate_motor_loop.wav")
## Preloaded default mechanical latch/impact audio stream.
const DEFAULT_STOP_SFX: AudioStream = preload("res://props/garage_gate/sfx/gate_stop_clunk.wav")

## Mesh primitive for articulated panel sections.
@export var panel_mesh: Mesh:
	set(value):
		panel_mesh = value
		if is_inside_tree() and Engine.is_editor_hint():
			_rebuild_gate()

## Mesh primitive for static side tracks, jambs, and torsion assembly.
@export var frame_mesh: Mesh:
	set(value):
		frame_mesh = value
		if is_inside_tree() and Engine.is_editor_hint():
			_rebuild_gate()

## Shader material override for panels with per-instance wear uniform.
@export var panel_material: ShaderMaterial:
	set(value):
		panel_material = value
		if is_inside_tree() and Engine.is_editor_hint():
			_rebuild_gate()

## Material override for the static frame, tracks, and torsion hardware.
@export var frame_material: Material:
	set(value):
		frame_material = value
		if is_inside_tree() and Engine.is_editor_hint():
			_rebuild_gate()

## Duration in seconds for full open/close animation.
@export var open_duration: float = 5.0
## Continuous motor and chain gear sound played while the gate moves.
@export var motor_loop_sfx: AudioStream = DEFAULT_MOTOR_SFX
## One-shot mechanical clunk played via [AudioPool] when the gate stops.
@export var stop_sfx: AudioStream = DEFAULT_STOP_SFX

## Current open/closed state flag of the garage gate.
var is_open: bool = false

## Normalized progress of the open animation from 0.0 (closed) to 1.0 (open).
var _open_progress: float = 0.0
## Active Tween driving gate kinematics.
var _tween: Tween
## Active Tween fading out motor loop audio on stop.
var _audio_fade_tween: Tween
## Procedural 3D guide curve defining the overhead roller track.
var _guide_curve: Curve3D
## Articulated panel physics bodies in bottom-to-top order.
var _panels: Array[AnimatableBody3D] = []
## Visual mesh instances parented to articulated panel bodies.
var _panel_meshes: Array[MeshInstance3D] = []
## Spatial audio player mounted at the overhead torsion shaft.
var _motor_player: AudioStreamPlayer3D


## Initializes static frame, procedural track curve, audio player, and panel bodies.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	if Engine.is_editor_hint():
		_clear_generated_nodes()

	if panel_mesh == null or frame_mesh == null:
		_extract_default_meshes()
	if panel_material == null:
		panel_material = DEFAULT_PANEL_MAT
	if frame_material == null:
		frame_material = DEFAULT_FRAME_MAT

	if panel_mesh == null:
		return

	_build_frame()
	_build_guide_curve()
	_build_panels()
	if not Engine.is_editor_hint():
		_build_motor_audio()
	_apply_gate_kinematics(0.0)


## Cleans up active tweens and editor preview nodes on exit.
func _exit_tree() -> void:
	if is_instance_valid(_tween) and _tween.is_valid():
		_tween.kill()
	if is_instance_valid(_audio_fade_tween) and _audio_fade_tween.is_valid():
		_audio_fade_tween.kill()
	if Engine.is_editor_hint():
		_clear_generated_nodes()


## Toggles gate between open and closed states.
func toggle_gate() -> void:
	set_gate_open(not is_open)


## Animates gate to target state using a single Tween and starts motor audio.
func set_gate_open(target_open: bool) -> void:
	if is_open == target_open and (_tween == null or not _tween.is_running()):
		return
	is_open = target_open
	print("GarageGate: transitioning to is_open=", is_open)

	_tween = Utilities.reset_tween(self, _tween)
	if _tween == null:
		return

	_start_motor_audio()

	var target_val: float = 1.0 if is_open else 0.0
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_apply_gate_kinematics, _open_progress, target_val, open_duration)
	_tween.tween_callback(_on_tween_finished)


## Reconstructs frame and panel instances when export properties change in editor.
func _rebuild_gate() -> void:
	if not is_inside_tree() or not Engine.is_editor_hint():
		return
	_clear_generated_nodes()
	if panel_mesh != null:
		_build_frame()
		_build_guide_curve()
		_build_panels()
		_apply_gate_kinematics(0.0)


## Clears previously spawned frame and panel instances to prevent editor duplicates.
func _clear_generated_nodes() -> void:
	for child: Node in get_children():
		if (
			child.name == "FrameMesh"
			or child.name == "MotorAudioPlayer"
			or child.name.begins_with("Panel_")
		):
			child.queue_free()
	_panels.clear()
	_panel_meshes.clear()


## Extracts default meshes from [constant DEFAULT_GATE_GLB] if exports are unassigned.
func _extract_default_meshes() -> void:
	if DEFAULT_GATE_GLB == null:
		return
	var root: Node = DEFAULT_GATE_GLB.instantiate()
	if not is_instance_valid(root):
		return
	var panel_node: Node = root.find_child("SM_GaragePanel", true, false)
	if panel_node is MeshInstance3D and panel_mesh == null:
		panel_mesh = (panel_node as MeshInstance3D).mesh
	var frame_node: Node = root.find_child("SM_GarageFrame", true, false)
	if frame_node is MeshInstance3D and frame_mesh == null:
		frame_mesh = (frame_node as MeshInstance3D).mesh
	root.queue_free()


## Instantiates static track and torsion spring assembly on Render Layer 1.
func _build_frame() -> void:
	if frame_mesh == null:
		return
	var frame_inst: MeshInstance3D = MeshInstance3D.new()
	frame_inst.name = "FrameMesh"
	frame_inst.mesh = frame_mesh
	frame_inst.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
	if frame_material != null:
		frame_inst.material_override = frame_material
	add_child(frame_inst)


## Constructs the vertical -> 90-deg arc -> horizontal overhead Curve3D in Godot space (-Z back).
func _build_guide_curve() -> void:
	_guide_curve = Curve3D.new()
	_guide_curve.bake_interval = 0.02
	_guide_curve.add_point(Vector3(0.0, 0.0, 0.0))
	_guide_curve.add_point(Vector3(0.0, TRACK_VERTICAL_H, 0.0))

	var arc_steps: int = 10
	for i: int in range(1, arc_steps + 1):
		var ang: float = (PI * 0.5) * (float(i) / float(arc_steps))
		var py: float = TRACK_VERTICAL_H + TRACK_RADIUS * sin(ang)
		var pz: float = -TRACK_RADIUS * (1.0 - cos(ang))
		_guide_curve.add_point(Vector3(0.0, py, pz))

	_guide_curve.add_point(
		Vector3(0.0, TRACK_VERTICAL_H + TRACK_RADIUS, -(TRACK_RADIUS + TRACK_HORIZONTAL_L))
	)


## Spawns [constant PANEL_COUNT] panel bodies with collisions and shader wear.
func _build_panels() -> void:
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(PANEL_WIDTH, PANEL_HEIGHT, PANEL_DEPTH)

	for i: int in range(PANEL_COUNT):
		var body: AnimatableBody3D = AnimatableBody3D.new()
		body.name = "Panel_%d" % i
		body.sync_to_physics = false
		body.collision_layer = CollisionLayers.MASK_SOLID_WORLD
		body.collision_mask = CollisionLayers.MASK_NONE
		add_child(body)

		var col: CollisionShape3D = CollisionShape3D.new()
		col.name = "Collision"
		col.shape = box_shape
		col.position = Vector3(0.0, PANEL_HEIGHT * 0.5, 0.0)
		body.add_child(col)

		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		mesh_inst.name = "Mesh"
		mesh_inst.mesh = panel_mesh
		mesh_inst.layers = CollisionLayers.RENDER_MASK_INTERACTIVE
		if panel_material != null:
			mesh_inst.material_override = panel_material
		mesh_inst.set_instance_shader_parameter(PARAM_WEAR_OFFSET, float(i) / float(PANEL_COUNT))
		body.add_child(mesh_inst)

		_panels.append(body)
		_panel_meshes.append(mesh_inst)


## Creates the 3D motor audio player mounted at the overhead torsion drive shaft.
func _build_motor_audio() -> void:
	_motor_player = AudioStreamPlayer3D.new()
	_motor_player.name = "MotorAudioPlayer"
	_motor_player.bus = SFX_BUS
	_motor_player.max_distance = MOTOR_AUDIO_MAX_DIST
	_motor_player.unit_size = 4.0
	_motor_player.position = Vector3(0.0, 2.55, -0.08)
	add_child(_motor_player)


## Starts the continuous motor sound on [member _motor_player].
func _start_motor_audio() -> void:
	if not is_instance_valid(_motor_player) or motor_loop_sfx == null:
		return
	if is_instance_valid(_audio_fade_tween) and _audio_fade_tween.is_valid():
		_audio_fade_tween.kill()
	_motor_player.volume_db = 0.0
	_motor_player.stream = motor_loop_sfx
	_motor_player.play()


## Fades out and stops the continuous motor sound.
func _stop_motor_audio() -> void:
	if not is_instance_valid(_motor_player) or not _motor_player.playing:
		return
	_audio_fade_tween = Utilities.reset_tween(self, _audio_fade_tween)
	if _audio_fade_tween == null:
		_motor_player.stop()
		return
	_audio_fade_tween.tween_property(_motor_player, "volume_db", -40.0, MOTOR_FADE_OUT_SEC)
	_audio_fade_tween.tween_callback(_motor_player.stop)


## Evaluates 2-stage slack expansion and Curve3D transform sampling for all panels.
func _apply_gate_kinematics(progress: float) -> void:
	_open_progress = progress

	# Phase 1 (0.0 -> 0.15): Unseat interlocking teeth to reveal peeking holes across seams
	var slack_t: float = clampf(progress / PHASE_1_RATIO, 0.0, 1.0)
	# Phase 2 (0.15 -> 1.0): Pull separated stack along overhead track curve
	var travel_t: float = clampf((progress - PHASE_1_RATIO) / (1.0 - PHASE_1_RATIO), 0.0, 1.0)
	var base_travel: float = travel_t * MAX_TRAVEL_DIST

	for i: int in range(PANEL_COUNT):
		if i >= _panels.size():
			continue
		var body: AnimatableBody3D = _panels[i]
		if not is_instance_valid(body):
			continue

		var dist_bottom: float = (
			base_travel + float(i) * (PANEL_HEIGHT - 0.04) + (float(i) * SLACK_GAP * slack_t)
		)
		var dist_top: float = dist_bottom + PANEL_HEIGHT

		var p_bot: Vector3 = _guide_curve.sample_baked(dist_bottom, true)
		var p_top: Vector3 = _guide_curve.sample_baked(dist_top, true)

		# Chord vector between bottom and top hinge rollers dictates exact panel pitch
		var up_dir: Vector3 = (p_top - p_bot).normalized()
		var right_dir: Vector3 = Vector3.RIGHT
		var forward_dir: Vector3 = right_dir.cross(up_dir).normalized()

		body.transform = Transform3D(Basis(right_dir, up_dir, forward_dir), p_bot)


## Fires completion signal, fades motor audio, and triggers stop clunk via [AudioPool].
func _on_tween_finished() -> void:
	_stop_motor_audio()
	if stop_sfx != null and not Engine.is_editor_hint():
		var audio_pool: Node = get_node_or_null("/root/AudioPool")
		if is_instance_valid(audio_pool):
			audio_pool.call("play_sfx_3d", stop_sfx, global_position, SFX_BUS)
	print("GarageGate: state transition complete. is_open=", is_open)
	gate_state_changed.emit(is_open)
