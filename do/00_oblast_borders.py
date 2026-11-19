"""00_oblast_borders.py -- oblast and country borders as lines, for maps drawn in Stata.

Stata draws a map here as plain lines (twoway line lat lon, cmissing(n)), so it needs the
borders as lists of points. The map I have is by raion (139 raions); oblast borders are
the raion edges that separate two oblasts, plus the country border.

How (no GIS library needed):
  1. Read every raion ring from the map and cut it into edges between consecutive vertices.
  2. An edge inside an oblast is shared by two raions of that oblast; an oblast border edge
     is shared by raions of two different oblasts; a country border edge belongs to one
     raion only. Keep the last two kinds. Shared edges are found by their two end points
     (the map's raions share vertices exactly along common borders).
  3. Join the kept edges into polylines and thin them (Douglas-Peucker, tolerance below)
     so the PDF stays small.

Map: example/ukr_admin2.geojson in the sirens repo (OCHA COD-AB admin level 2, v05,
1 Sep 2025), as in 00_city_raion.py. Kyiv city (UA80) and Sevastopol count as oblasts.

Output: data/temp/ua_oblast_borders.csv  columns path, kind (country / oblast), lon, lat;
        one row per point, a row with empty lon/lat between paths (for cmissing(n)).
        data/temp/ua_raion_polygons.csv  (added 14 Nov 2026, for the filled raion maps of
        04_descriptives_exposure.do, drawn with Stata's grmap) columns raion_pcode, lon,
        lat: the outer ring of every polygon of each raion, thinned with the same
        tolerance; each ring starts with a row with empty lon/lat (the format of a Stata
        shapefile, _X/_Y). Holes are left out: they are small enclaves, invisible at the
        size of the map.

Run (from the Project folder), after cloning the sirens repo:
    python do/00_oblast_borders.py "<sirens repo folder>"
"""
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

PROJECT = Path(__file__).resolve().parent.parent
DEFAULT_SIRENS = PROJECT.parent / "ukrainian-air-raid-sirens-dataset"
OUT = PROJECT / "data" / "temp" / "ua_oblast_borders.csv"
OUT_POLY = PROJECT / "data" / "temp" / "ua_raion_polygons.csv"
TOL = 0.01      # thinning tolerance, degrees (~1 km): invisible at the size of the map
ROUND = 7       # decimals used to match shared vertices


def rings(geometry):
    polys = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
    return [r for poly in polys for r in poly]


def thin(pts, tol):
    """Douglas-Peucker simplification of a polyline (list of (lon, lat))."""
    if len(pts) < 3:
        return pts
    a = np.asarray(pts)
    keep = np.zeros(len(a), dtype=bool)
    keep[0] = keep[-1] = True
    stack = [(0, len(a) - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        p, q = a[i], a[j]
        seg = q - p
        norm = np.hypot(*seg)
        mid = a[i + 1:j]
        if norm == 0:
            d = np.hypot(*(mid - p).T)
        else:
            d = np.abs(seg[0] * (mid[:, 1] - p[1]) - seg[1] * (mid[:, 0] - p[0])) / norm
        k = int(np.argmax(d))
        if d[k] > tol:
            keep[i + 1 + k] = True
            stack += [(i, i + 1 + k), (i + 1 + k, j)]
    return [tuple(x) for x in a[keep]]


def main():
    sirens = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SIRENS
    gj = json.loads((sirens / "example" / "ukr_admin2.geojson").read_text(encoding="utf-8"))

    # 1-2. edges, and the oblasts each edge belongs to
    owners = defaultdict(list)                     # undirected edge -> oblast codes
    for f in gj["features"]:
        obl = f["properties"]["adm1_pcode"]
        for ring in rings(f["geometry"]):
            pts = [(round(x[0], ROUND), round(x[1], ROUND)) for x in ring]
            for u, v in zip(pts[:-1], pts[1:]):
                if u != v:
                    owners[frozenset((u, v))].append(obl)
    kept = {}
    for e, obls in owners.items():
        if len(obls) == 1:
            kept[e] = "country"
        elif len(set(obls)) > 1:
            kept[e] = "oblast"
    print(f"edges: {len(owners)}, kept: {len(kept)} ({Counter(kept.values())})")

    # 3. join edges of the same kind into polylines
    out_rows, n_paths = [], 0
    for kind in ("country", "oblast"):
        adj = defaultdict(set)
        for e, k in kept.items():
            if k == kind:
                u, v = tuple(e)
                adj[u].add(v)
                adj[v].add(u)
        used = set()

        def walk(start, nxt):
            path = [start, nxt]
            used.add(frozenset((start, nxt)))
            cur = nxt
            while True:
                cand = [w for w in adj[cur] if frozenset((cur, w)) not in used]
                if len(adj[cur]) != 2 or not cand:   # stop at junctions and ends
                    break
                w = cand[0]
                used.add(frozenset((cur, w)))
                path.append(w)
                cur = w
            return path

        # start at junctions/ends first, then whatever is left (closed loops)
        starts = [u for u in adj if len(adj[u]) != 2] + list(adj)
        for u in starts:
            for v in list(adj[u]):
                if frozenset((u, v)) not in used:
                    path = thin(walk(u, v), TOL)
                    n_paths += 1
                    out_rows += [(n_paths, kind, x, y) for x, y in path]
                    out_rows.append((n_paths, kind, None, None))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8") as fh:
        fh.write("path,kind,lon,lat\n")
        for p, k, x, y in out_rows:
            fh.write(f"{p},{k},{'' if x is None else f'{x:.5f}'},{'' if y is None else f'{y:.5f}'}\n")
    print(f"paths: {n_paths}, points: {sum(r[2] is not None for r in out_rows)} -> {OUT}")

    # 4. raion polygons (outer rings only), for filled maps
    n_rings, n_pts = 0, 0
    with OUT_POLY.open("w", encoding="utf-8") as fh:
        fh.write("raion_pcode,lon,lat\n")
        for f in gj["features"]:
            pc = f["properties"]["adm2_pcode"]
            g = f["geometry"]
            polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
            for poly in polys:
                ring = thin([(x[0], x[1]) for x in poly[0]], TOL)
                if len(ring) < 4:
                    continue
                n_rings += 1
                fh.write(f"{pc},,\n")
                for x, y in ring:
                    n_pts += 1
                    fh.write(f"{pc},{x:.5f},{y:.5f}\n")
    print(f"raion rings: {n_rings}, points: {n_pts} -> {OUT_POLY}")


if __name__ == "__main__":
    main()
