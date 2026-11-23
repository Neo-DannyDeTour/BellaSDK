"""Spanish Cadastre (Dirección General del Catastro) facade photos for an area.

Licence (Licencia de descarga de productos catastrales, §5-§8): original cadastral information may
NOT be published or sold as-is; public and commercial use IS allowed after a transformation that
yields a different work (e.g. a 3D building generated from the photo). Keep the downloaded originals
local/private, and credit "Fuente: Dirección General del Catastro".

  1. parcels in the area   INSPIRE WFS (CadastralParcel), queried in small tiles
  2. facade photo per parcel   OVCFotoFachada service, one request at a time, politely throttled
Resumable: existing photos are skipped; index.json records every parcel and its status.
"""
from __future__ import annotations

import json
import re
import time
import urllib.request
from pathlib import Path

WFS = ("https://ovc.catastro.meh.es/INSPIRE/wfsCP.aspx?service=wfs&version=2.0.0&request=GetFeature"
       "&typeNames=CP:CadastralParcel&srsName=EPSG::25831&bbox={x0},{y0},{x1},{y1}")
PHOTO = ("https://ovc.catastro.meh.es/OVCServWeb/OVCWcfLibres/OVCFotoFachada.svc/"
         "RecuperarFotoFachadaGet?ReferenciaCatastral={rc}")
UA = {"User-Agent": "video2mocap/0.2 (github.com/freddysae0/video2mocap)"}


def _get(url: str, timeout: int = 60, tries: int = 4) -> bytes:
    for k in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
                return r.read()
        except Exception:
            if k == tries - 1:
                raise
            time.sleep(5 * (k + 1))
    return b""


def area_polygon_utm(geojson: str | Path, name: str):
    """A named polygon from a GeoJSON (WGS84 lon/lat) -> shapely polygon in EPSG:25831."""
    from pyproj import Transformer
    from shapely.geometry import shape
    from shapely.ops import transform

    d = json.loads(Path(geojson).read_text(encoding="utf-8"))
    feat = next(f for f in d["features"] if name.lower() in json.dumps(f["properties"], ensure_ascii=False).lower()
                and f["properties"].get("NOM", name).lower() == name.lower())
    tr = Transformer.from_crs("EPSG:4326", "EPSG:25831", always_xy=True)
    return transform(tr.transform, shape(feat["geometry"]))


def parcels_in(poly, tile_m: float = 250.0, delay_s: float = 1.0) -> list[dict]:
    from shapely.geometry import Polygon

    x0, y0, x1, y1 = poly.bounds
    out: dict[str, dict] = {}
    x = x0
    while x < x1:
        y = y0
        while y < y1:
            gml = _get(WFS.format(x0=x, y0=y, x1=x + tile_m, y1=y + tile_m)).decode("iso-8859-1", "ignore")
            for block in gml.split("<cp:CadastralParcel ")[1:]:
                rc = re.search(r"<cp:nationalCadastralReference>([^<]+)", block)
                pos = re.search(r"<gml:posList[^>]*>([^<]+)", block)
                area = re.search(r"<cp:areaValue[^>]*>([^<]+)", block)
                if not rc or not pos:
                    continue
                v = [float(t) for t in pos.group(1).split()]
                pg = Polygon(list(zip(v[0::2], v[1::2])))
                if not pg.is_valid:
                    pg = pg.buffer(0)
                c = pg.representative_point()
                if poly.contains(c):
                    out[rc.group(1)] = {"rc": rc.group(1), "x": round(c.x, 2), "y": round(c.y, 2),
                                        "area_m2": float(area.group(1)) if area else round(pg.area, 1)}
            time.sleep(delay_s)
            y += tile_m
        x += tile_m
    return sorted(out.values(), key=lambda p: p["rc"])


def fetch_photos(parcels: list[dict], out_dir: Path, delay_s: float = 1.0, log=print) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    index_path = out_dir / "index.json"
    index = json.loads(index_path.read_text(encoding="utf-8")) if index_path.exists() else {}
    for k, p in enumerate(parcels):
        rc = p["rc"]
        dst = out_dir / f"{rc}.jpg"
        if rc in index and index[rc].get("status") in ("ok", "no_photo"):
            continue
        entry = dict(p)
        try:
            data = _get(PHOTO.format(rc=rc))
            if data[:3] == b"\xff\xd8\xff" and len(data) > 8000:
                dst.write_bytes(data)
                entry.update(status="ok", bytes=len(data))
            else:  # the service answers with an error page or a tiny placeholder
                entry.update(status="no_photo", bytes=len(data))
        except Exception as e:
            entry.update(status="error", error=str(e)[:200])
        index[rc] = entry
        if k % 25 == 0 or k == len(parcels) - 1:
            index_path.write_text(json.dumps(index, indent=1), encoding="utf-8")
            ok = sum(1 for v in index.values() if v["status"] == "ok")
            log(f"[catastro] {k + 1}/{len(parcels)} parcels, {ok} photos")
        time.sleep(delay_s)
    index_path.write_text(json.dumps(index, indent=1), encoding="utf-8")
    return index
