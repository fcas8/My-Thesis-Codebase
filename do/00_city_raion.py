"""00_city_raion.py -- in which raion is each robota.ua city? (used by 03_geo_mappings.do)

Air raid alarms are announced for an oblast or, more and more, for a single raion (district).
To give each vacancy the alarms of its own place, I need the raion of each robota.ua city.
Stata cannot do point-in-polygon on a GeoJSON file, so this script does it.

What it writes:
  data/crosswalks/ua_raions.csv      the 139 raions (incl. Kyiv city and Sevastopol) of the
                                     map, one row each: code, oblast and raion names
                                     (English as in the alarm data, and Ukrainian)
  data/temp/robota_city_raion.csv    one row per robota.ua city_id: the raion it lies in

How a city gets its raion:
  1. Take the coordinates of all the city's vacancies (latitude/longitude; 0 = missing), and
     keep those inside a box around Ukraine.
  2. Drop pins on robota.ua's two default points in Kyiv (DEFAULT_PINS below):
       50.4801, 30.5834      a placeholder for "Other countries" and for vacancies without
                             a real address (~11,000 vacancies in many cities); dropped for
                             every city;
       50.4500336, 30.5241361  Kyiv's own point (the city center); dropped for cities
                             other than Kyiv.
     Both lie in Kyiv city. Before this step (checked 14 Nov 2026, README section 6.3) they
     put 14 villages of Kyiv oblast into Kyiv city.
  3. Keep only the pins that fall in the city's own oblast (from robota.ua's city list,
     data/crosswalks/robota_city.csv). Some cities have many pins on a default spot in Kyiv
     (e.g. Horodok, Lviv oblast: about half), which would otherwise pull the point there.
     Kyiv city counts as part of Kyiv oblast here, as in robota.ua's list.
  4. The city's point is the pin closest to the median latitude and median longitude of the
     pins left. The median ignores the few postings with a wrong pin (a firm's head office,
     a typo); taking the closest real pin avoids a point that mixes the latitude of one pin
     with the longitude of another, which can fall where no pin is (few, scattered pins).
  5. The raion is the polygon that contains that point.
  Entries of robota.ua's city list that name a whole region, not a place (OBLAST_WIDE:
  "Zakarpattia", "Krym"), get no raion.
  Check columns: n_coord (vacancies with coordinates) and share_same (share of those whose
  own pin falls in the same raion). A low share_same means the city's pins are scattered;
  for a large city that is normal near a raion border.
  Cities without any coordinates get no raion (raion_pcode empty).

Map: example/ukr_admin2.geojson in the sirens repo (github Vadimkin/ukrainian-air-raid-
sirens-dataset). It is the OCHA/HDX "Ukraine - Subnational Administrative Boundaries"
(COD-AB) admin level 2, version v05, valid on 1 Sep 2025, so it already has the raion
names of the 2024 renaming (e.g. Krasnohradskyi -> Berestynskyi).

Run once per export, before 03_geo_mappings.do (from the Project folder):
    python do/00_city_raion.py "<export folder>"
Default export folder: the one below (keep in line with 01_clean.do).
"""
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

PROJECT = Path(__file__).resolve().parent.parent
THESIS = PROJECT.parent
DEFAULT_EXPORT = THESIS / "Collector" / "data" / "exports" / "20261105_072026"
GEOJSON = THESIS / "ukrainian-air-raid-sirens-dataset" / "example" / "ukr_admin2.geojson"
OUT_RAIONS = PROJECT / "data" / "crosswalks" / "ua_raions.csv"
OUT_CITIES = PROJECT / "data" / "temp" / "robota_city_raion.csv"

KYIV = 1                                   # robota.ua city_id of Kyiv
DEFAULT_PINS = {(50.4801, 30.5834): "placeholder",        # dropped for every city
                (50.4500336, 30.5241361): "kyiv_center"}  # dropped for cities other than Kyiv
OBLAST_WIDE = {8: "Zakarpattia", 12: "Krym"}               # city_ids naming a whole region


def rings(geometry):
    """Outer and inner rings of a Polygon or MultiPolygon, as numpy arrays (lon, lat)."""
    polys = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
    return [[np.asarray(r, dtype=float)[:, :2] for r in poly] for poly in polys]


def inside(lon, lat, polys):
    """True for each point inside the (multi)polygon: ray casting, holes excluded."""
    result = np.zeros(len(lon), dtype=bool)
    for poly in polys:
        in_poly = np.zeros(len(lon), dtype=bool)
        for ring in poly:                       # first ring = outer, others = holes
            x1, y1 = ring[:-1, 0], ring[:-1, 1]
            x2, y2 = ring[1:, 0], ring[1:, 1]
            for a, b, c, d in zip(x1, y1, x2, y2):
                crosses = ((b > lat) != (d > lat)) & (lon < (c - a) * (lat - b) / (d - b + 1e-300) + a)
                in_poly ^= crosses              # every crossing flips in/out
        result |= in_poly
    return result


def raion_of(lon, lat, raions):
    """Raion code for each point (empty string if in none)."""
    code = np.full(len(lon), "", dtype=object)
    for r in raions:
        lo0, la0, lo1, la1 = r["bbox"]
        cand = np.where((code == "") & (lon >= lo0) & (lon <= lo1) & (lat >= la0) & (lat <= la1))[0]
        if len(cand):
            hit = inside(lon[cand], lat[cand], r["polys"])
            code[cand[hit]] = r["code"]
    return code


def main():
    export = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_EXPORT

    # --- 1. Raions from the map ------------------------------------------------
    gj = json.loads(GEOJSON.read_text(encoding="utf-8"))
    raions, rows = [], []
    for f in gj["features"]:
        p = f["properties"]
        polys = rings(f["geometry"])
        allpts = np.vstack([r for poly in polys for r in poly])
        raions.append({"code": p["adm2_pcode"], "polys": polys,
                       "bbox": (*allpts.min(axis=0), *allpts.max(axis=0))})
        rows.append({"raion_pcode": p["adm2_pcode"], "oblast_pcode": p["adm1_pcode"],
                     "oblast_en": p["adm1_name"], "raion_en": p["adm2_name"],
                     "oblast_ua": p["adm1_name1"], "raion_ua": p["adm2_name1"],
                     "area_km2": round(p["area_sqkm"], 1)})
    pd.DataFrame(rows).sort_values("raion_pcode").to_csv(OUT_RAIONS, index=False, encoding="utf-8")

    # --- 2. City points from the vacancies' coordinates -------------------------
    v = pd.read_csv(export / "vacancies.csv", usecols=["id", "city_id", "latitude", "longitude"],
                    encoding="utf-8-sig")
    n_vac = v.groupby("city_id").size().rename("n_vac")
    v = v[v.latitude.between(44, 52.5) & v.longitude.between(22, 40.5)].copy()

    # robota.ua's default points in Kyiv (step 2 in the docstring)
    pin = pd.Series(list(zip(v.latitude, v.longitude)), index=v.index).map(DEFAULT_PINS)
    drop = (pin == "placeholder") | ((pin == "kyiv_center") & (v.city_id != KYIV))
    print(f"pins on default points dropped: {drop.sum():,} "
          f"(placeholder {(pin == 'placeholder').sum():,}; "
          f"Kyiv center outside Kyiv {(drop & (pin == 'kyiv_center')).sum():,})")
    v = v[~drop & ~v.city_id.isin(OBLAST_WIDE)]

    v["raion_own"] = raion_of(v.longitude.to_numpy(), v.latitude.to_numpy(), raions)

    # keep pins in the city's own oblast. Oblasts are compared by their first word
    # ("Львівська"), with Kyiv city -> Kyiv oblast and the map's "Автономна ..." -> "Крим".
    def oblast_key(name):
        first = str(name).split(" ")[0] if isinstance(name, str) and name else ""
        return {"Київ": "Київська", "Автономна": "Крим", "м.": "Київська"}.get(first, first)
    raion_obl = {r["raion_pcode"]: oblast_key(r["oblast_ua"]) for r in rows}
    clist = pd.read_csv(PROJECT / "data" / "crosswalks" / "robota_city.csv", encoding="utf-8-sig",
                        usecols=["id", "oblast_ua", "country_id"]).set_index("id")
    abroad = clist.index[(clist.country_id != 0) | (clist.oblast_ua == "Інші країни")]
    city_obl = clist.oblast_ua.map(oblast_key)
    v = v[~v.city_id.isin(abroad)]                 # cities abroad get no raion
    v["pin_obl"] = v.raion_own.map(raion_obl).fillna("")
    v["city_obl"] = v.city_id.map(city_obl).fillna("")
    # (Zakarpattia towns and Crimea have no oblast in the list: all their pins are kept)
    v = v[(v.city_obl == "") | (v.pin_obl == v.city_obl)]

    # city point: the pin closest to the median lat and median lon (distance in km,
    # approximately: one degree of longitude is cos(lat) degrees of latitude)
    med = v.groupby("city_id")[["latitude", "longitude"]].transform("median")
    v["dist"] = np.hypot(v.latitude - med.latitude,
                         (v.longitude - med.longitude) * np.cos(np.radians(med.latitude)))
    best = v.loc[v.groupby("city_id")["dist"].idxmin(), ["city_id", "latitude", "longitude"]]
    city = v.groupby("city_id").agg(n_coord=("id", "size")).join(
        best.set_index("city_id").rename(columns={"latitude": "lat", "longitude": "lon"}))
    city["raion_pcode"] = raion_of(city.lon.to_numpy(), city.lat.to_numpy(), raions)
    v = v.merge(city[["raion_pcode"]], left_on="city_id", right_index=True)
    city["share_same"] = (v.raion_own == v.raion_pcode).groupby(v.city_id).mean().round(3)

    out = pd.concat([n_vac, city], axis=1).reset_index().rename(columns={"index": "city_id"})
    out["n_coord"] = out.n_coord.fillna(0).astype(int)
    out["raion_pcode"] = out.raion_pcode.fillna("")
    out.to_csv(OUT_CITIES, index=False, encoding="utf-8")

    print(f"{len(out)} cities; {(out.raion_pcode != '').sum()} with a raion, covering "
          f"{out.loc[out.raion_pcode != '', 'n_vac'].sum() / out.n_vac.sum():.1%} of vacancies")
    print(f"written: {OUT_RAIONS}\n         {OUT_CITIES}")


if __name__ == "__main__":
    main()
