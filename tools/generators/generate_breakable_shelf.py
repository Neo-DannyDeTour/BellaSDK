#!/usr/bin/env python3
"""Generates Godot 4 breakable wooden shelf (.gdshader, .gd, .tscn).

Usage: python3 tools/generate_breakable_shelf.py [output_dir]
Default output: <repo>/props/breakable_shelf
"""

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "props" / "breakable_shelf"
RES_DIR = "res://" + OUT_DIR.resolve().relative_to(REPO).as_posix()


def tabify(src: str) -> str:
    """Converts leading 4-space groups to tabs (source templates use spaces)."""
    return re.sub(
        r"(?m)^( {4})+",
        lambda m: "\t" * (len(m.group(0)) // 4),
        src,
    )


SHADER_CODE = tabify("""shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(0.76, 0.78, 0.75, 1.0);
uniform vec4 wood_color : source_color = vec4(0.36, 0.23, 0.13, 1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.88;
instance uniform float albedo_alpha : hint_range(0.0, 1.0) = 1.0;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
    local_pos = VERTEX;
    local_normal = NORMAL;
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
    float grain = sin(local_pos.x * 60.0 + local_pos.z * 12.0 + hash(local_pos.xz) * 4.0);
    float wear = clamp(grain * 0.5 + 0.5, 0.0, 1.0);
    bool is_outer = abs(local_normal.x) > 0.5 || local_normal.y > 0.5 || abs(local_normal.z) > 0.5;
    vec3 base = mix(wood_color.rgb, paint_color.rgb, is_outer ? 0.82 : 0.25);
    ALBEDO = mix(base, wood_color.rgb * 0.7, wear * 0.25);
    ROUGHNESS = roughness_val;
    ALPHA = albedo_alpha;
}
""")

GDSCRIPT_CODE = tabify("""## Breakable 5-plank wooden shelf prop.
##
## Operates as a single [RigidBody3D] on the Interactive physics layer until broken
## by [method take_damage] or high-velocity impact, then wakes 5 pre-allocated
## child [RigidBody3D] planks on the Debris layer and fades them out.
# class_name BreakableShelf
extends RigidBody3D

## Emitted when the shelf breaks into debris planks. [param origin] is the world position.
@warning_ignore("unused_signal")
signal broken(origin: Vector3)

## Per-instance shader uniform driving plank fade-out.
const SHADER_ALPHA_PARAM: StringName = &"albedo_alpha"
## Collision layer used by debris planks.
const LAYER_DEBRIS: int = CollisionLayers.MASK_DEBRIS
## Mask for debris planks: environment and other debris.
const MASK_DEBRIS: int = CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_DEBRIS
## Seconds debris stays opaque before fading.
const FADE_DELAY_SEC: float = 4.0
## Seconds the debris fade-out lasts.
const FADE_DURATION_SEC: float = 1.0

## Damage the intact shelf absorbs before breaking.
@export var max_health: float = 20.0
## Squared linear speed (m/s) on contact that triggers impact fracture.
@export var impact_velocity_sq_threshold: float = 16.0
## Outward impulse strength applied to planks on break.
@export var burst_impulse: float = 2.2

## Remaining health of the intact shelf.
var _health: float = 20.0
## True once the shelf has begun breaking.
var _is_broken: bool = false
## Active fade tween for debris planks.
var _fade_tween: Tween = null
## Cached debris plank bodies.
var _gib_bodies: Array[RigidBody3D] = []
## Cached debris plank meshes.
var _gib_meshes: Array[MeshInstance3D] = []
## Cached debris plank collision shapes.
var _gib_shapes: Array[CollisionShape3D] = []

## Container for the intact plank meshes.
@onready var _intact_visuals: Node3D = $IntactVisuals
## Container for the pre-allocated debris planks.
@onready var _gibs_root: Node3D = $Gibs


## Validates node structure, caches plank references, and configures physics state.
func _ready() -> void:
    set_process(false)
    set_physics_process(false)
    assert(_intact_visuals != null, "BreakableShelf: Missing IntactVisuals node.")
    assert(_gibs_root != null, "BreakableShelf: Missing Gibs root node.")
    _health = max_health
    for child: Node in _gibs_root.get_children():
        var gib: RigidBody3D = child as RigidBody3D
        if gib != null:
            _gib_bodies.append(gib)
            var mesh: MeshInstance3D = gib.get_node_or_null("Mesh") as MeshInstance3D
            var shape: CollisionShape3D = gib.get_node_or_null("Shape") as CollisionShape3D
            assert(mesh != null and shape != null, "BreakableShelf: Malformed gib child.")
            _gib_meshes.append(mesh)
            _gib_shapes.append(shape)
    assert(_gib_bodies.size() == 5, "BreakableShelf: Expected 5 plank gibs.")
    body_entered.connect(_on_body_entered)


## Cleans up active tweens on tree exit.
func _exit_tree() -> void:
    if _fade_tween != null and _fade_tween.is_valid():
        _fade_tween.kill()


## Applies damage and breaks the shelf when health reaches zero.
func take_damage(amount: float, hit_pos: Vector3, impulse: Vector3 = Vector3.ZERO) -> void:
    if _is_broken or amount <= 0.0:
        return
    _health -= amount
    print("BreakableShelf: damaged, remaining=", _health)
    if _health <= 0.0:
        _trigger_break(hit_pos, impulse)
    elif impulse != Vector3.ZERO:
        apply_impulse(impulse, hit_pos - global_position)


## Evaluates physics collision velocity to trigger impact fracture.
func _on_body_entered(_body: Node) -> void:
    if _is_broken:
        return
    if linear_velocity.length_squared() >= impact_velocity_sq_threshold:
        _trigger_break(global_position, linear_velocity * 0.35)


## Schedules deferred transition from intact body to debris planks.
func _trigger_break(hit_pos: Vector3, impulse: Vector3) -> void:
    if _is_broken:
        return
    _is_broken = true
    print("BreakableShelf: broken at ", global_position)
    call_deferred(&"_execute_break_deferred", hit_pos, impulse)


## Swaps intact collision/visuals for independent debris planks and starts fade timer.
func _execute_break_deferred(hit_pos: Vector3, impulse: Vector3) -> void:
    if not is_inside_tree():
        return
    broken.emit(global_position)
    freeze = true
    collision_layer = 0
    collision_mask = 0
    _intact_visuals.visible = false
    for child: Node in get_children():
        var col: CollisionShape3D = child as CollisionShape3D
        if col != null:
            col.disabled = true
    _gibs_root.visible = true
    var parent_node: Node = get_parent()
    for i: int in range(_gib_bodies.size()):
        var gib: RigidBody3D = _gib_bodies[i]
        var shape: CollisionShape3D = _gib_shapes[i]
        var g_xform: Transform3D = gib.global_transform
        if parent_node != null:
            gib.reparent(parent_node, true)
        gib.global_transform = g_xform
        shape.disabled = false
        gib.collision_layer = LAYER_DEBRIS
        gib.collision_mask = MASK_DEBRIS
        gib.freeze = false
        gib.linear_velocity = linear_velocity
        gib.angular_velocity = angular_velocity
        var offset: Vector3 = gib.global_position - hit_pos
        var dist_sq: float = maxf(offset.length_squared(), 0.04)
        var dir: Vector3 = offset.normalized() if dist_sq > 0.0001 else Vector3.UP
        gib.apply_central_impulse(dir * (burst_impulse / dist_sq) + impulse * 0.25)
    if _fade_tween != null and _fade_tween.is_valid():
        _fade_tween.kill()
    _fade_tween = create_tween()
    _fade_tween.tween_interval(FADE_DELAY_SEC)
    _fade_tween.tween_method(_set_gibs_alpha, 1.0, 0.0, FADE_DURATION_SEC)
    _fade_tween.tween_callback(_cleanup_gibs)


## Updates per-instance alpha uniform on all valid plank meshes.
func _set_gibs_alpha(alpha: float) -> void:
    for mesh: MeshInstance3D in _gib_meshes:
        if is_instance_valid(mesh):
            mesh.set_instance_shader_parameter(SHADER_ALPHA_PARAM, alpha)


## Frees spawned debris planks and the root shelf node.
func _cleanup_gibs() -> void:
    for gib: RigidBody3D in _gib_bodies:
        if is_instance_valid(gib):
            gib.queue_free()
    queue_free()
""")

# Plank layout (name, width, height, depth, pos_x, pos_y, pos_z)
# Outer dimensions: 0.50m W x 0.80m H x 0.40m D, board thickness 0.02m
PLANKS = [
    ("PlankLeft", 0.02, 0.80, 0.40, -0.24, 0.40, 0.0),
    ("PlankRight", 0.02, 0.80, 0.40, 0.24, 0.40, 0.0),
    ("PlankTop", 0.46, 0.02, 0.40, 0.0, 0.79, 0.0),
    ("PlankMid", 0.46, 0.02, 0.38, 0.0, 0.48, 0.0),
    ("PlankBottom", 0.46, 0.02, 0.40, 0.0, 0.03, 0.0),
]

# Mirrors CollisionLayers: INTERACTIVE=1<<2, ENV|PLAYER|INTERACTIVE|ENEMIES, RENDER_INTERACTIVE
LAYER_INTERACTIVE = 1 << 2
MASK_INTACT = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 4)
RENDER_INTERACTIVE = 1 << 2


def build_tscn() -> str:
    lines = [
        "[gd_scene load_steps=14 format=3]",
        "",
        f'[ext_resource type="Script" path="{RES_DIR}/breakable_shelf.gd" id="1_script"]',
        f'[ext_resource type="Shader" path="{RES_DIR}/breakable_shelf.gdshader" id="2_shader"]',
        "",
        '[sub_resource type="ShaderMaterial" id="ShaderMaterial_shelf"]',
        "render_priority = 0",
        'shader = ExtResource("2_shader")',
        "",
    ]

    for idx, (_, w, h, d, _, _, _) in enumerate(PLANKS, start=1):
        lines.extend([
            f'[sub_resource type="BoxMesh" id="BoxMesh_{idx}"]',
            'material = SubResource("ShaderMaterial_shelf")',
            f"size = Vector3({w}, {h}, {d})",
            "",
            f'[sub_resource type="BoxShape3D" id="BoxShape3D_{idx}"]',
            f"size = Vector3({w}, {h}, {d})",
            "",
        ])

    lines.extend([
        '[node name="BreakableShelf" type="RigidBody3D"]',
        f"collision_layer = {LAYER_INTERACTIVE}",
        f"collision_mask = {MASK_INTACT}",
        "mass = 8.0",
        "contact_monitor = true",
        "max_contacts_reported = 2",
        'script = ExtResource("1_script")',
        "",
    ])

    for idx, (name, _, _, _, x, y, z) in enumerate(PLANKS, start=1):
        lines.extend([
            f'[node name="Col_{name}" type="CollisionShape3D" parent="."]',
            f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, {y}, {z})",
            f'shape = SubResource("BoxShape3D_{idx}")',
            "",
        ])

    lines.extend(['[node name="IntactVisuals" type="Node3D" parent="."]', ""])

    for idx, (name, _, _, _, x, y, z) in enumerate(PLANKS, start=1):
        lines.extend([
            f'[node name="Mesh_{name}" type="MeshInstance3D" parent="IntactVisuals"]',
            f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, {y}, {z})",
            f"layers = {RENDER_INTERACTIVE}",
            f'mesh = SubResource("BoxMesh_{idx}")',
            "",
        ])

    lines.extend(['[node name="Gibs" type="Node3D" parent="."]', "visible = false", ""])

    for idx, (name, _, _, _, x, y, z) in enumerate(PLANKS, start=1):
        lines.extend([
            f'[node name="Gib_{name}" type="RigidBody3D" parent="Gibs"]',
            f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, {y}, {z})",
            "collision_layer = 0",
            "collision_mask = 0",
            "mass = 1.6",
            "freeze = true",
            "",
            f'[node name="Mesh" type="MeshInstance3D" parent="Gibs/Gib_{name}"]',
            f"layers = {RENDER_INTERACTIVE}",
            f'mesh = SubResource("BoxMesh_{idx}")',
            "",
            f'[node name="Shape" type="CollisionShape3D" parent="Gibs/Gib_{name}"]',
            f'shape = SubResource("BoxShape3D_{idx}")',
            "disabled = true",
            "",
        ])

    return "\n".join(lines)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "breakable_shelf.gdshader").write_text(SHADER_CODE, encoding="utf-8")
    (OUT_DIR / "breakable_shelf.gd").write_text(GDSCRIPT_CODE, encoding="utf-8")
    (OUT_DIR / "breakable_shelf.tscn").write_text(build_tscn(), encoding="utf-8")
    print(f"Generated breakable_shelf.{{gdshader,gd,tscn}} in {OUT_DIR}")


if __name__ == "__main__":
    main()
