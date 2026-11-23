"""v2m command line.

  v2m run      VIDEO --out DIR [--fast] [--fbx] [--max-people N] full pipeline (backend + post + review)
  v2m post     RAW.npz --rig NAME --out CLEAN.npz                post-process one motion
  v2m review   MOTION.npz --out SHEET.png [--track-dir DIR]      key-frame contact sheet for review
  v2m edit     MOTION.npz EDITS.json --out EDITED.npz            apply reviewer edits (then re-run post)
  v2m export   MOTION.npz --bvh OUT.bvh [--fbx OUT.fbx]          BVH (and FBX through Blender)
  v2m view     RUN_DIR                                         web viewer: video + one stick figure per person + 3D
  v2m face     capture | from-body | sync | attach             face curves (ARKit-52) and merging with a body
  v2m scan     PHOTOS|VIDEO --out DIR                          photogrammetry: textured 3D mesh
  v2m metrics  MOTION.npz                                        quality numbers as JSON
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .io.bvh import write_bvh
from .motion import Motion
from .pipeline import postprocess
from .process.edit import apply_edits, load_edits
from .qa.metrics import report
from .qa.review import render_contact_sheet, select_keyframes
from .rigs import PROFILES


def _rig(name: str):
    if name not in PROFILES:
        sys.exit(f"unknown rig '{name}'. known: {', '.join(PROFILES)}")
    return PROFILES[name]


def cmd_post(a) -> None:
    raw = Motion.load(a.motion)
    out, metrics = postprocess(raw, _rig(a.rig))
    out.save(a.out)
    Path(a.out).with_suffix(".metrics.json").write_text(json.dumps(metrics, indent=2))
    print(json.dumps(metrics["final"], indent=2))


def cmd_review(a) -> None:
    m = Motion.load(a.motion)
    frames = select_keyframes(m, max_frames=a.max_frames)
    video_frames, camera, kp2d = None, None, None
    if a.track_dir:
        from .review_io import load_review_inputs

        video_frames, camera, kp2d = load_review_inputs(a.track_dir, frames)
    path = render_contact_sheet(m, frames, a.out, video_frames, camera, kp2d, title=Path(a.motion).name)
    print(json.dumps({"sheet": str(path), "frames": frames}))


def cmd_edit(a) -> None:
    m = apply_edits(Motion.load(a.motion), load_edits(a.edits))
    m.save(a.out)
    print(f"wrote {a.out}")


def cmd_export(a) -> None:
    m = Motion.load(a.motion)
    if a.bvh:
        write_bvh(m, a.bvh)
        print(f"wrote {a.bvh}")
    if a.fbx:
        from .blender import bvh_to_fbx

        src = a.bvh or str(Path(a.fbx).with_suffix(".bvh"))
        if not a.bvh:
            write_bvh(m, src)
        bvh_to_fbx(src, a.fbx, blender=a.blender)
        print(f"wrote {a.fbx}")
    if getattr(a, "glb", None):
        from .blender import bvh_to_glb

        src = a.bvh or str(Path(a.glb).with_suffix(".bvh"))
        if not a.bvh and not Path(src).exists():
            write_bvh(m, src)
        bvh_to_glb(src, a.glb, blender=a.blender, fps=m.fps)
        print(f"wrote {a.glb}")


def cmd_view(a) -> None:
    from .viewer.export import serve

    serve(a.run_dir, port=a.port, open_browser=not a.no_browser)


def cmd_face(a) -> None:
    from .face.attach import attach_face
    from .face.capture import FaceTake, capture_face, capture_face_from_track

    if a.face_cmd == "capture":
        take = capture_face(a.video)
        take.save(a.out)
        print(json.dumps({"take": a.out, "frames": take.num_frames, **take.meta}, indent=2))
    elif a.face_cmd == "from-body":
        take = capture_face_from_track(a.run_dir, a.person)
        out = Path(a.run_dir) / f"face_take_person{a.person}.npz"
        take.save(out)
        attach_face(a.run_dir, a.person, out, offset_s=0.0)
        print(json.dumps({"take": str(out), **take.meta}, indent=2))
    elif a.face_cmd == "sync":
        from .face.sync import sync_offset

        print(json.dumps(sync_offset(a.body_video, a.face_video, a.method), indent=2))
    elif a.face_cmd == "attach":
        offset = a.offset
        if offset is None:
            from .face.sync import sync_offset
            from .viewer.export import _source_video

            run = json.loads((Path(a.run_dir) / "run.json").read_text())
            body_video = Path(a.run_dir) / _source_video(run, Path(a.run_dir))
            take = FaceTake.load(a.take)
            res = sync_offset(body_video, take.meta["source"], a.sync)
            offset = res["offset_s"]
            print(json.dumps(res, indent=2))
        print(attach_face(a.run_dir, a.person, a.take, offset_s=offset, time_scale=a.time_scale))
    elif a.face_cmd == "export-godot":
        from .face.godot_export import export_face_to_godot_tres

        head_rest_quat = None
        if a.head_rest_quat:
            parts = [float(v.strip()) for v in a.head_rest_quat.split(",")]
            if len(parts) != 4:
                sys.exit("--head-rest-quat must have 4 comma-separated floats: w,x,y,z")
            head_rest_quat = tuple(parts)
        out = export_face_to_godot_tres(
            a.take,
            a.out,
            head_mesh_path=a.head_path,
            lash_mesh_path=a.lash_path,
            skeleton_path=a.skeleton_path,
            glb_path=a.glb,
            head_rest_quat=head_rest_quat,
            neutral_center=a.neutral_center,
        )
        print(f"wrote {out}")


def cmd_scan(a) -> None:
    from .scan.pipeline import ScanConfig, scan

    cfg = ScanConfig(max_images=a.max_images, resolution_level=a.resolution_level, decimate=a.decimate,
                     refine=not a.no_refine, matcher=a.matcher, clean=a.clean)
    print(json.dumps(scan(a.source, a.out, cfg), indent=2))


def cmd_catastro(a) -> None:
    from .scan.catastro import area_polygon_utm, fetch_photos, parcels_in

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    plist = out / "parcels.json"
    if plist.exists():
        parcels = json.loads(plist.read_text(encoding="utf-8"))
    else:
        parcels = parcels_in(area_polygon_utm(a.geojson, a.name), delay_s=a.delay)
        plist.write_text(json.dumps(parcels, indent=1), encoding="utf-8")
    print(f"[catastro] {len(parcels)} parcels in {a.name}")
    if not a.list_only:
        idx = fetch_photos(parcels, out / "photos", delay_s=a.delay)
        print(json.dumps({s: sum(1 for v in idx.values() if v["status"] == s) for s in ("ok", "no_photo", "error")}))


def cmd_metrics(a) -> None:
    print(json.dumps(report(Motion.load(a.motion)), indent=2))


def cmd_run(a) -> None:
    from .run import run_video

    extra = ["--no_imgfeat"] if a.fast else []
    run_video(a.video, a.out, static_cam=not a.moving_cam, max_people=a.max_people, backend=a.backend,
              extra=extra, fbx=a.fbx, glb=getattr(a, "glb", False))


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(prog="v2m", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("run")
    s.add_argument("video")
    s.add_argument("--out", required=True)
    s.add_argument("--moving-cam", action="store_true",
                   help="camera moves (needs visual odometry; not supported yet - static is assumed)")
    s.add_argument("--fbx", action="store_true", help="also export FBX through Blender")
    s.add_argument("--glb", action="store_true", help="also export Godot 4.7+ GLB through Blender")
    s.add_argument("--fast", action="store_true", help="GEM-X keypoints-only mode: less memory, lower quality")
    s.add_argument("--max-people", type=int, default=8)
    s.add_argument("--backend", default="gemx")
    s.set_defaults(fn=cmd_run)

    s = sub.add_parser("post")
    s.add_argument("motion")
    s.add_argument("--rig", default="soma77")
    s.add_argument("--out", required=True)
    s.set_defaults(fn=cmd_post)

    s = sub.add_parser("review")
    s.add_argument("motion")
    s.add_argument("--out", required=True)
    s.add_argument("--track-dir", help="track folder with video frames/camera/2D keypoints for overlays")
    s.add_argument("--max-frames", type=int, default=16)
    s.set_defaults(fn=cmd_review)

    s = sub.add_parser("edit")
    s.add_argument("motion")
    s.add_argument("edits")
    s.add_argument("--out", required=True)
    s.set_defaults(fn=cmd_edit)

    s = sub.add_parser("export")
    s.add_argument("motion")
    s.add_argument("--bvh")
    s.add_argument("--fbx")
    s.add_argument("--glb")
    s.add_argument("--blender", help="path to blender executable (auto-detected if omitted)")
    s.set_defaults(fn=cmd_export)

    s = sub.add_parser("view", help="open the web viewer for a run folder")
    s.add_argument("run_dir")
    s.add_argument("--port", type=int, default=8765)
    s.add_argument("--no-browser", action="store_true")
    s.set_defaults(fn=cmd_view)

    s = sub.add_parser("face", help="face capture: curves from a face take, sync and attach to a person")
    fs = s.add_subparsers(dest="face_cmd", required=True)
    f = fs.add_parser("capture", help="face take video -> 52 ARKit curves + head rotation")
    f.add_argument("video")
    f.add_argument("--out", required=True)
    f = fs.add_parser("from-body", help="face from the body video itself (head crops), attached to a person")
    f.add_argument("run_dir")
    f.add_argument("--person", type=int, required=True)
    f = fs.add_parser("sync", help="offset between a body video and a face video (clap or audio)")
    f.add_argument("body_video")
    f.add_argument("face_video")
    f.add_argument("--method", default="auto", choices=["auto", "clap", "audio"])
    f = fs.add_parser("attach", help="merge a face take onto a person of a run")
    f.add_argument("run_dir")
    f.add_argument("--person", type=int, required=True)
    f.add_argument("--take", required=True)
    f.add_argument("--offset", type=float, help="seconds, t_face = t_body + offset (default: sync by audio)")
    f.add_argument("--sync", default="auto", choices=["auto", "clap", "audio"])
    f.add_argument("--time-scale", type=float, default=1.0)
    f = fs.add_parser("export-godot", help="export face take or merged face.npz to Godot 4.7+ Animation .tres")
    f.add_argument("take")
    f.add_argument("--out", required=True)
    f.add_argument("--head-path", default="BellaModel/Bella_Armature/Skeleton3D/Bella_Head")
    f.add_argument("--lash-path", default="BellaModel/Bella_Armature/Skeleton3D/Bella_Eyelashes")
    f.add_argument("--skeleton-path", default="BellaModel/Bella_Armature/Skeleton3D")
    f.add_argument("--glb", default=None, help="rigged .glb to read Head bone local rest rotation from")
    f.add_argument("--head-rest-quat", default=None, help="Head bone rest quaternion as 'w,x,y,z' (overrides --glb)")
    f.add_argument(
        "--neutral-center",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="subtract mean head pose before composing with Head rest pose (default: True)",
    )
    s.set_defaults(fn=cmd_face)

    s = sub.add_parser("scan", help="photos or video -> textured 3D mesh (COLMAP + OpenMVS)")
    s.add_argument("source", help="folder of photos or a video file")
    s.add_argument("--out", required=True)
    s.add_argument("--max-images", type=int, default=300)
    s.add_argument("--resolution-level", type=int, default=1, help="0 full, 1 half (8 GB GPU), 2 quarter")
    s.add_argument("--decimate", type=float, default=1.0)
    s.add_argument("--no-refine", action="store_true")
    s.add_argument("--matcher", default="exhaustive", choices=["exhaustive", "sequential"])
    s.add_argument("--clean", action="store_true", help="remove people and licence plates with Codex first")
    s.set_defaults(fn=cmd_scan)

    s = sub.add_parser("catastro", help="download Spanish Cadastre facade photos for an area (keep them private)")
    s.add_argument("--geojson", required=True, help="GeoJSON (WGS84) with the area polygon")
    s.add_argument("--name", required=True, help='feature name, e.g. "el Raval"')
    s.add_argument("--out", required=True)
    s.add_argument("--delay", type=float, default=1.0, help="seconds between requests (be polite)")
    s.add_argument("--list-only", action="store_true")
    s.set_defaults(fn=cmd_catastro)

    s = sub.add_parser("metrics")
    s.add_argument("motion")
    s.set_defaults(fn=cmd_metrics)

    a = p.parse_args(argv)
    a.fn(a)


if __name__ == "__main__":
    main()
