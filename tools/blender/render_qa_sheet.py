#!/usr/bin/env python3
"""Headless Blender QA contact-sheet renderer for /3d, /animate, and /pbr.

Renders visual inspection sheets so agents (and Swarm critics) can inspect
3D geometry, animations, and PBR tiling without colliding on a live viewport.

Modes:
  turntable --input <file.glb> --output <sheet.png>
  anim      --input <file.glb> --output <sheet.png> [--action <name>]
  pbr       --albedo <a.png> --normal <n.png> --orm <o.png> --output <sheet.png>
  face      --input <file.glb> --output <sheet.png> [--tile-size 448]
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import bpy
import numpy as np
from mathutils import Quaternion, Vector


def _parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Render headless QA contact sheet")
    sub = parser.add_subparsers(dest="mode", required=True)

    t_p = sub.add_parser("turntable", help="2x2 Front/Right/Back/3-4 mesh sheet")
    t_p.add_argument("--input", type=Path, required=True)
    t_p.add_argument("--output", type=Path, required=True)
    t_p.add_argument("--tile-size", type=int, default=384)

    a_p = sub.add_parser("anim", help="5-frame 0/25/50/75/100% animation strip")
    a_p.add_argument("--input", type=Path, required=True)
    a_p.add_argument("--output", type=Path, required=True)
    a_p.add_argument("--action", type=str, default=None)
    a_p.add_argument("--tile-size", type=int, default=320)

    p_p = sub.add_parser("pbr", help="2x1 Tiled plane + shader ball PBR preview")
    p_p.add_argument("--albedo", type=Path, required=True)
    p_p.add_argument("--normal", type=Path, default=None)
    p_p.add_argument("--orm", type=Path, default=None)
    p_p.add_argument("--output", type=Path, required=True)
    p_p.add_argument("--tile-size", type=int, default=384)

    f_p = sub.add_parser("face", help="2x3 Portrait & ARKit facial expression QA sheet")
    f_p.add_argument("--input", type=Path, required=True)
    f_p.add_argument("--output", type=Path, required=True)
    f_p.add_argument("--tile-size", type=int, default=448)

    return parser.parse_args(argv)


def _clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _configure_render(res: int, samples: int = 16) -> None:
    scene = bpy.context.scene
    # Prefer Cycles CPU for reliable headless rendering without OpenGL/EGL display
    for engine in ("CYCLES", "BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue

    if scene.render.engine == "CYCLES":
        scene.cycles.device = "CPU"
        scene.cycles.samples = samples
        scene.cycles.use_denoising = False
        scene.cycles.transparent_max_bounces = 24

    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"

    # Neutral studio world
    world = bpy.data.worlds.new("QAWorld")
    scene.world = world
    world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg is not None:
        bg.inputs[0].default_value = (0.22, 0.22, 0.22, 1.0)
        bg.inputs[1].default_value = 0.8


def _setup_studio_lights(center: Vector, radius: float) -> None:
    dist = max(radius * 2.5, 2.0)
    light_specs = [
        ("KeyLight", (dist, -dist, dist * 1.2), 3.0 * dist * dist),
        ("FillLight", (-dist * 1.2, -dist * 0.5, dist * 0.6), 1.2 * dist * dist),
        ("RimLight", (0.0, dist * 1.2, dist * 0.9), 1.8 * dist * dist),
    ]
    for name, offset, energy in light_specs:
        ldata = bpy.data.lights.new(name=name, type="AREA")
        ldata.energy = energy
        ldata.size = max(radius * 1.2, 1.0)
        lobj = bpy.data.objects.new(name=name, object_data=ldata)
        bpy.context.scene.collection.objects.link(lobj)
        lobj.location = center + Vector(offset)
        direction = center - lobj.location
        lobj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def _create_camera() -> bpy.types.Object:
    cdata = bpy.data.cameras.new("QACam")
    cdata.lens = 50.0
    cobj = bpy.data.objects.new("QACam", cdata)
    bpy.context.scene.collection.objects.link(cobj)
    bpy.context.scene.camera = cobj
    return cobj


def _aim_camera(cam: bpy.types.Object, target: Vector, yaw_deg: float, pitch_deg: float, dist: float) -> None:
    yaw = math.radians(yaw_deg)
    pitch = math.radians(pitch_deg)
    offset = Vector((
        math.sin(yaw) * math.cos(pitch),
        -math.cos(yaw) * math.cos(pitch),
        math.sin(pitch),
    )) * dist
    cam.location = target + offset
    direction = target - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def _character_meshes() -> List[bpy.types.Object]:
    """Return renderable character meshes, hiding glTF importer helper shapes (e.g. Icosphere)."""
    out: List[bpy.types.Object] = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        in_hidden_gltf = any(c.name == "glTF_not_exported" for c in obj.users_collection)
        if in_hidden_gltf or obj.name.startswith("Icosphere"):
            obj.hide_render = True
            continue
        out.append(obj)
    return out


def _scene_mesh_bounds() -> Tuple[Vector, float]:
    meshes = _character_meshes()
    if not meshes:
        return Vector((0.0, 0.0, 0.5)), 1.0
    mins = Vector((float("inf"), float("inf"), float("inf")))
    maxs = Vector((float("-inf"), float("-inf"), float("-inf")))
    for obj in meshes:
        for corner in obj.bound_box:
            pt = obj.matrix_world @ Vector(corner)
            mins.x = min(mins.x, pt.x)
            mins.y = min(mins.y, pt.y)
            mins.z = min(mins.z, pt.z)
            maxs.x = max(maxs.x, pt.x)
            maxs.y = max(maxs.y, pt.y)
            maxs.z = max(maxs.z, pt.z)
    center = (mins + maxs) * 0.5
    radius = max((maxs - mins).length * 0.5, 0.25)
    return center, radius


def _render_to_array(tmp_path: Path) -> np.ndarray:
    bpy.context.scene.render.filepath = str(tmp_path)
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(str(tmp_path), check_existing=False)
    try:
        w, h = img.size[0], img.size[1]
        arr = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(arr)
        return arr.reshape((h, w, 4))
    finally:
        bpy.data.images.remove(img)


def _stitch_grid(tiles: List[np.ndarray], cols: int, rows: int, out_path: Path) -> None:
    h, w, _ = tiles[0].shape
    sheet = np.zeros((h * rows, w * cols, 4), dtype=np.float32)
    sheet[:, :, 3] = 1.0
    for idx, tile in enumerate(tiles):
        r, c = divmod(idx, cols)
        # Blender images are bottom-to-top, so row 0 goes at the top of the sheet
        y0 = (rows - 1 - r) * h
        x0 = c * w
        sheet[y0 : y0 + h, x0 : x0 + w, :] = tile

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_img = bpy.data.images.new(
        name="QASheet", width=w * cols, height=h * rows, alpha=False, float_buffer=False
    )
    try:
        out_img.pixels.foreach_set(sheet.ravel())
        out_img.filepath_raw = str(out_path)
        out_img.file_format = "PNG"
        out_img.save()
    finally:
        bpy.data.images.remove(out_img)


def run_turntable(glb_path: Path, out_path: Path, tile_size: int) -> None:
    _clear_scene()
    _configure_render(tile_size)
    bpy.ops.import_scene.gltf(filepath=str(glb_path))
    center, radius = _scene_mesh_bounds()
    _setup_studio_lights(center, radius)
    cam = _create_camera()
    dist = radius * 3.1

    # Front, Right, Back, 3/4 Hero
    angles = [(0.0, 8.0), (90.0, 8.0), (180.0, 8.0), (35.0, 22.0)]
    tiles: List[np.ndarray] = []
    tmp_path = Path("/tmp") / f"qa_tile_{out_path.stem}.png"
    for yaw, pitch in angles:
        _aim_camera(cam, center, yaw, pitch, dist)
        tiles.append(_render_to_array(tmp_path))
    tmp_path.unlink(missing_ok=True)
    _stitch_grid(tiles, cols=2, rows=2, out_path=out_path)
    print(f"Turntable QA sheet saved: {out_path}")


def run_anim(glb_path: Path, out_path: Path, action_name: Optional[str], tile_size: int) -> None:
    _clear_scene()
    _configure_render(tile_size)
    bpy.ops.import_scene.gltf(filepath=str(glb_path))

    arm = next((o for o in bpy.context.scene.objects if o.type == "ARMATURE"), None)
    action = None
    if action_name and action_name in bpy.data.actions:
        action = bpy.data.actions[action_name]
    elif bpy.data.actions:
        action = bpy.data.actions[0]

    if arm is not None and action is not None:
        if arm.animation_data is None:
            arm.animation_data_create()
        for track in arm.animation_data.nla_tracks:
            track.mute = True
        arm.animation_data.action = action
        f_start, f_end = action.frame_range
    else:
        f_start, f_end = 1.0, 30.0

    bpy.context.scene.frame_set(int(round(f_start)))
    center, radius = _scene_mesh_bounds()
    _setup_studio_lights(center, radius)
    cam = _create_camera()
    _aim_camera(cam, center, yaw_deg=35.0, pitch_deg=15.0, dist=radius * 3.3)

    fracs = [0.0, 0.25, 0.50, 0.75, 1.0]
    tiles: List[np.ndarray] = []
    tmp_path = Path("/tmp") / f"qa_anim_{out_path.stem}.png"
    for frac in fracs:
        frame = int(round(f_start + (f_end - f_start) * frac))
        bpy.context.scene.frame_set(frame)
        tiles.append(_render_to_array(tmp_path))
    tmp_path.unlink(missing_ok=True)
    _stitch_grid(tiles, cols=5, rows=1, out_path=out_path)
    print(f"Animation QA strip saved: {out_path} (action={action.name if action else 'none'})")


def _build_pbr_material(albedo: Path, normal: Optional[Path], orm: Optional[Path]) -> bpy.types.Material:
    mat = bpy.data.materials.new("QAPBRMat")
    mat.use_nodes = True
    tree = mat.node_tree
    nodes = tree.nodes
    links = tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")

    tex_coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (2.0, 2.0, 2.0)
    links.new(tex_coord.outputs["UV"], mapping.inputs["Vector"])

    alb_node = nodes.new("ShaderNodeTexImage")
    alb_node.image = bpy.data.images.load(str(albedo))
    links.new(mapping.outputs["Vector"], alb_node.inputs["Vector"])
    links.new(alb_node.outputs["Color"], bsdf.inputs["Base Color"])

    if orm is not None and orm.is_file():
        orm_node = nodes.new("ShaderNodeTexImage")
        orm_node.image = bpy.data.images.load(str(orm))
        orm_node.image.colorspace_settings.name = "Non-Color"
        sep = nodes.new("ShaderNodeSeparateColor")
        links.new(mapping.outputs["Vector"], orm_node.inputs["Vector"])
        links.new(orm_node.outputs["Color"], sep.inputs["Color"])
        links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    if normal is not None and normal.is_file():
        norm_tex = nodes.new("ShaderNodeTexImage")
        norm_tex.image = bpy.data.images.load(str(normal))
        norm_tex.image.colorspace_settings.name = "Non-Color"
        norm_map = nodes.new("ShaderNodeNormalMap")
        links.new(mapping.outputs["Vector"], norm_tex.inputs["Vector"])
        links.new(norm_tex.outputs["Color"], norm_map.inputs["Color"])
        links.new(norm_map.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def run_pbr(
    albedo: Path,
    normal: Optional[Path],
    orm: Optional[Path],
    out_path: Path,
    tile_size: int,
) -> None:
    _clear_scene()
    _configure_render(tile_size)
    mat = _build_pbr_material(albedo, normal, orm)

    # Tile 1: 2x2 Tiled Flat Plane (checks macro-tiling checkerboard)
    bpy.ops.mesh.primitive_plane_add(size=2.0, location=(0.0, 0.0, 0.0))
    plane = bpy.context.active_object
    plane.data.materials.append(mat)
    _setup_studio_lights(Vector((0.0, 0.0, 0.0)), 1.2)
    cam = _create_camera()

    tmp_path = Path("/tmp") / f"qa_pbr_{out_path.stem}.png"
    _aim_camera(cam, Vector((0.0, 0.0, 0.0)), yaw_deg=0.0, pitch_deg=78.0, dist=3.0)
    tile_plane = _render_to_array(tmp_path)

    # Tile 2: Shader Ball Sphere (checks roughness/specular/normal relief)
    bpy.data.objects.remove(plane, do_unlink=True)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=0.85, location=(0.0, 0.0, 0.0))
    sphere = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    sphere.data.materials.append(mat)
    _aim_camera(cam, Vector((0.0, 0.0, 0.0)), yaw_deg=25.0, pitch_deg=18.0, dist=2.8)
    tile_sphere = _render_to_array(tmp_path)

    tmp_path.unlink(missing_ok=True)
    _stitch_grid([tile_plane, tile_sphere], cols=2, rows=1, out_path=out_path)
    print(f"PBR QA sheet saved: {out_path}")


def _face_frame_bounds() -> Tuple[Vector, float]:
    """Frame Bella_Head (with fallback to top 18% of scene mesh bounds)."""
    meshes = _character_meshes()
    head_obj = next((o for o in meshes if o.name == "Bella_Head"), None)
    if head_obj is None:
        head_obj = next((o for o in meshes if "head" in o.name.lower()), None)

    if head_obj is not None:
        pts = [head_obj.matrix_world @ Vector(c) for c in head_obj.bound_box]
        mins = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        maxs = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        center = (mins + maxs) * 0.5 + Vector((0.0, 0.0, 0.01))
        ext = maxs - mins
        radius = max(ext.x, ext.y, ext.z) * 0.55
        return center, max(radius, 0.10)

    mins = Vector((float("inf"), float("inf"), float("inf")))
    maxs = Vector((float("-inf"), float("-inf"), float("-inf")))
    for obj in meshes:
        for corner in obj.bound_box:
            pt = obj.matrix_world @ Vector(corner)
            mins.x = min(mins.x, pt.x)
            mins.y = min(mins.y, pt.y)
            mins.z = min(mins.z, pt.z)
            maxs.x = max(maxs.x, pt.x)
            maxs.y = max(maxs.y, pt.y)
            maxs.z = max(maxs.z, pt.z)
    if not meshes:
        return Vector((0.0, 0.0, 1.50)), 0.14
    z_lo = mins.z + 0.82 * (maxs.z - mins.z)
    center = Vector((0.5 * (mins.x + maxs.x), 0.5 * (mins.y + maxs.y), 0.5 * (z_lo + maxs.z)))
    radius = max((maxs.z - z_lo) * 0.55, 0.12)
    return center, radius


def _reset_face_state(
    meshes: List[bpy.types.Object],
    arm: Optional[bpy.types.Object],
) -> None:
    for obj in meshes:
        if obj.data is not None and obj.data.shape_keys is not None:
            for kb in obj.data.shape_keys.key_blocks:
                if kb != obj.data.shape_keys.reference_key:
                    kb.value = 0.0
    if arm is not None:
        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
            pb.location = Vector((0.0, 0.0, 0.0))
    bpy.context.view_layer.update()


def _apply_shape_keys(
    meshes: List[bpy.types.Object],
    weights: Dict[str, float],
    target_prefixes: Optional[Tuple[str, ...]] = None,
) -> None:
    for obj in meshes:
        if target_prefixes and not any(obj.name.startswith(p) for p in target_prefixes):
            continue
        if obj.data is None or obj.data.shape_keys is None:
            continue
        kbs = obj.data.shape_keys.key_blocks
        for name, val in weights.items():
            if name in kbs:
                kbs[name].value = val


def _rotate_pose_bone_world_axis(
    arm: Optional[bpy.types.Object],
    bone_name: str,
    world_axis: Vector,
    angle_deg: float,
) -> None:
    if arm is None or bone_name not in arm.pose.bones:
        return
    pb = arm.pose.bones[bone_name]
    pb.rotation_mode = "QUATERNION"
    # Convert desired world-space axis into bone local space at rest
    bone_world_rot = (arm.matrix_world.to_3x3() @ pb.bone.matrix_local.to_3x3()).normalized()
    local_axis = (bone_world_rot.inverted() @ world_axis.normalized()).normalized()
    pb.rotation_quaternion = Quaternion(local_axis, math.radians(angle_deg))


def run_face(glb_path: Path, out_path: Path, tile_size: int) -> None:
    _clear_scene()
    _configure_render(tile_size, samples=24)
    bpy.ops.import_scene.gltf(filepath=str(glb_path))
    bpy.context.view_layer.update()

    meshes = _character_meshes()
    arm = next((o for o in bpy.context.scene.objects if o.type == "ARMATURE"), None)
    if arm is not None and arm.animation_data is not None:
        arm.animation_data.action = None
        for track in arm.animation_data.nla_tracks:
            track.mute = True
    _reset_face_state(meshes, arm)

    center, radius = _face_frame_bounds()
    # Soft 3-point portrait studio lighting centered on head (calibrated so white hair & skin don't clip)
    light_specs = [
        ("FaceKey", (0.65, -0.85, 0.45), 14.0, 0.85),
        ("FaceFill", (-0.75, -0.65, 0.15), 7.5, 1.05),
        ("FaceRim", (0.15, 0.85, 0.55), 9.0, 0.75),
    ]
    for name, offset, energy, size in light_specs:
        ldata = bpy.data.lights.new(name=name, type="AREA")
        ldata.energy = energy
        ldata.size = size
        lobj = bpy.data.objects.new(name=name, object_data=ldata)
        bpy.context.scene.collection.objects.link(lobj)
        lobj.location = center + Vector(offset)
        lobj.rotation_euler = (center - lobj.location).to_track_quat("-Z", "Y").to_euler()

    cam = _create_camera()
    cam.data.lens = 85.0
    # 85mm on 36mm sensor: dist = half_span * (85 / 18); 1.25x margin frames hair + collar cleanly
    dist = radius * 1.32 * (85.0 / 18.0)

    specs: List[Tuple[str, float, float, Dict[str, float], Optional[Tuple[str, ...]], float, float]] = [
        ("Neutral Front (0°)", 0.0, 2.0, {}, None, 0.0, 0.0),
        ("Neutral 3/4 (35°)", 35.0, 5.0, {}, None, 0.0, 0.0),
        ("Neutral Side (90°)", 90.0, 2.0, {}, None, 0.0, 0.0),
        (
            "Happy (pic2 check)",
            0.0,
            2.0,
            {
                "mouthSmileLeft": 0.82,
                "mouthSmileRight": 0.82,
                "cheekSquintLeft": 0.45,
                "cheekSquintRight": 0.45,
                "eyeSquintLeft": 0.28,
                "eyeSquintRight": 0.28,
                "jawOpen": 0.18,
                "mouthUpperUpLeft": 0.22,
                "mouthUpperUpRight": 0.22,
                "mouthLowerDownLeft": 0.10,
                "mouthLowerDownRight": 0.10,
            },
            None,
            4.0,
            0.0,
        ),
        (
            "Blink + Gaze Left",
            0.0,
            2.0,
            {"eyeBlinkLeft": 1.0, "eyeBlinkRight": 0.0},
            ("Bella_Head", "Bella_Eyelashes"),
            0.0,
            20.0,
        ),
        (
            "Jaw Open + Oral Cavity",
            8.0,
            -4.0,
            {
                "jawOpen": 0.85,
                "mouthLowerDownLeft": 0.35,
                "mouthLowerDownRight": 0.35,
            },
            None,
            19.0,
            0.0,
        ),
    ]

    tiles: List[np.ndarray] = []
    tmp_path = Path("/tmp") / f"qa_face_{out_path.stem}.png"
    for label, yaw_deg, pitch_deg, sk_weights, sk_targets, jaw_deg, eye_yaw_deg in specs:
        _reset_face_state(meshes, arm)
        if sk_weights:
            _apply_shape_keys(meshes, sk_weights, target_prefixes=sk_targets)
        if abs(jaw_deg) > 1e-4:
            # Blender world +X rotation drops -Y forward chin/lower-teeth downward (-Z)
            _rotate_pose_bone_world_axis(arm, "Jaw", Vector((1.0, 0.0, 0.0)), jaw_deg)
        if abs(eye_yaw_deg) > 1e-4:
            # Blender world +Z rotation turns -Y forward pupil toward +X (character left)
            _rotate_pose_bone_world_axis(arm, "RightEye", Vector((0.0, 0.0, 1.0)), eye_yaw_deg)
        bpy.context.view_layer.update()
        _aim_camera(cam, center, yaw_deg, pitch_deg, dist)
        tiles.append(_render_to_array(tmp_path))
        print(f"[face QA] Rendered tile: {label}")

    _reset_face_state(meshes, arm)
    tmp_path.unlink(missing_ok=True)
    _stitch_grid(tiles, cols=3, rows=2, out_path=out_path)
    print(f"Face QA sheet saved: {out_path}")


def main() -> int:
    args = _parse_args()
    if args.mode == "turntable":
        run_turntable(args.input, args.output, args.tile_size)
    elif args.mode == "anim":
        run_anim(args.input, args.output, args.action, args.tile_size)
    elif args.mode == "pbr":
        run_pbr(args.albedo, args.normal, args.orm, args.output, args.tile_size)
    elif args.mode == "face":
        run_face(args.input, args.output, args.tile_size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
