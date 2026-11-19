"""00_viina_control.py -- who controls each place, by month (needed by 03_geo_mappings.do)

Source: VIINA 2.0 (Zhukov, github zhukovyuri/VIINA; license ODbL, cite Zhukov 2023, Journal of
Comparative Economics 51(4)). Cloned 6 Nov 2026, commit a1ad3633 (data update of 27 Oct 2026).
I use the GeoNames version of the territorial control data:
  Data/control_latest_YYYY.zip   one row per populated place and day, 23 Feb 2022 - 27 Oct 2026,
                                 with status UA / RU / CONTESTED. "status" is a majority vote of
                                 DeepStateMap, Wikipedia maps and Wikipedia "boosted" by VIINA's
                                 own news reports; ties go to DeepStateMap.
  Data/gn_UA_tess.geojson        the 33,141 populated places (GeoNames, feature code PPL*), with
                                 coordinates, POPULATION, and a polygon around each place; the
                                 polygons tile the whole country.
The GeoNames version is used (not the KATOTTH one, kontrol_*) because it has population.

RULE: a place counts as held by Russia on a day only if BOTH VIINA's vote (status) and
DeepStateMap (status_dsm) say RU. Where DeepStateMap has no status (all places until
March 2022, ~7% of people in April 2022, ~0 later), VIINA's vote alone decides.
Each source alone makes errors, in opposite directions (checked 6 Nov 2026):
  - VIINA's vote counts Wikipedia twice (Wikipedia's map, and Wikipedia "boosted" by
    VIINA's news). From June 2026 Wikipedia's map puts Nikopol and Marhanets
    (Dnipropetrovsk oblast, ~150,000 people, on the Ukrainian-held bank of the Dnipro)
    under Russia; when ISW stopped reporting in July 2026, the vote turned them Russian.
  - status_dsm marks Kherson city (~290,000 people, Ukrainian-held since Nov 2022) and
    Antonivka as Russian in every month, while Wikipedia and ISW say Ukraine. Probably
    VIINA assigns DeepStateMap's status to a place's polygon, and Kherson's polygon
    reaches across the Dnipro into the occupied left bank.
Both single-source versions are kept for checks: days_ru_viina and days_ru_dsm.

Stata cannot read the daily files comfortably (about 500 MB of text a year) nor do polygon
work, so this script does three things and writes small files to data/temp:

  viina_settlements.csv       one row per place: geonameid, name, population (GeoNames; 0 =
                              unknown, true for most villages), coordinates, and raion_pcode,
                              the raion of my map (OCHA COD-AB) that contains the place.
  viina_settlement_month.csv  one row per place and month: days with data, days with status
                              RU, days CONTESTED (RULE below), days without a DeepStateMap
                              status, days RU by each source alone (checks). Daily status is kept in counts, so a place
                              occupied half of a month counts half (03_geo_mappings.do, step 5).
  viina_city_settlement.csv   one row per robota.ua city with a point (from 00_city_raion.py):
                              the place whose polygon contains the city point.

Run once (from the Project folder), after 00_city_raion.py, before 03_exposure_build.do:
    python do/00_viina_control.py "<VIINA Data folder>"
Default VIINA folder: the clone next to the Project folder (below).
"""
import json
import sys
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from importlib import import_module
geo = import_module("00_city_raion")          # reuse the point-in-polygon functions

PROJECT = Path(__file__).resolve().parent.parent
THESIS = PROJECT.parent
DEFAULT_VIINA = THESIS / "VIINA" / "Data"
GEOJSON = THESIS / "ukrainian-air-raid-sirens-dataset" / "example" / "ukr_admin2.geojson"
TEMP = PROJECT / "data" / "temp"
YEARS = range(2022, 2027)


def load_raions():
    gj = json.loads(GEOJSON.read_text(encoding="utf-8"))
    out = []
    for f in gj["features"]:
        polys = geo.rings(f["geometry"])
        pts = np.vstack([r for poly in polys for r in poly])
        out.append({"code": f["properties"]["adm2_pcode"], "polys": polys,
                    "bbox": (*pts.min(axis=0), *pts.max(axis=0))})
    return out


def main():
    viina = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_VIINA

    # --- 1. Places and their raion ---------------------------------------------------
    gj = json.loads((viina / "gn_UA_tess.geojson").read_text(encoding="utf-8"))
    places = pd.DataFrame([{"geonameid": int(f["properties"]["geonameid"]),
                            "name": f["properties"]["name"],
                            "population": int(f["properties"]["population"] or 0),
                            "lat": f["properties"]["latitude"],
                            "lon": f["properties"]["longitude"]} for f in gj["features"]])
    places["raion_pcode"] = geo.raion_of(places.lon.to_numpy(float), places.lat.to_numpy(float),
                                         load_raions())
    places.to_csv(TEMP / "viina_settlements.csv", index=False, encoding="utf-8")
    print(f"{len(places)} places; {(places.raion_pcode != '').mean():.2%} inside a raion; "
          f"{(places.population > 0).mean():.1%} with a population")

    # --- 2. Daily status -> counts by place and month ----------------------------------
    parts = []
    for y in YEARS:
        z = zipfile.ZipFile(viina / f"control_latest_{y}.zip")
        for ch in pd.read_csv(z.open(z.infolist()[0]),
                              usecols=["geonameid", "date", "status", "status_dsm"],
                              dtype={"date": str, "status": str, "status_dsm": str},
                              chunksize=2_000_000):
            ch["geonameid"] = ch.geonameid.astype(float).astype("int64")
            ch["month"] = ch.date.str[:4] + "-" + ch.date.str[4:6]
            # Main status (see RULE in the docstring): Russian only if VIINA's vote AND
            # DeepStateMap both say so; VIINA's vote alone where DeepStateMap has no status.
            ru_vote = ch.status == "RU"
            ru_dsm = ch.status_dsm == "RU"
            ch["days"] = ch.status.notna().astype(int)
            ch["days_ru"] = (ru_vote & (ru_dsm | ch.status_dsm.isna())).astype(int)
            ch["days_contested"] = ((ch.status == "CONTESTED") & ~ch.days_ru.astype(bool)).astype(int)
            ch["days_dsm_missing"] = ch.status_dsm.isna().astype(int)
            ch["days_ru_viina"] = ru_vote.astype(int)                          # checks
            ch["days_ru_dsm"] = (ru_dsm | (ch.status_dsm.isna() & ru_vote)).astype(int)
            parts.append(ch.groupby(["geonameid", "month"])[
                ["days", "days_ru", "days_contested", "days_dsm_missing",
                 "days_ru_viina", "days_ru_dsm"]].sum())
        print(f"  {y} read")
    sm = pd.concat(parts).groupby(level=[0, 1]).sum().reset_index()
    sm.to_csv(TEMP / "viina_settlement_month.csv", index=False)
    print(f"{len(sm)} place-months, {sm.month.min()} to {sm.month.max()}")

    # --- 3. robota.ua city -> place whose polygon contains the city point -------------
    cities = pd.read_csv(TEMP / "robota_city_raion.csv").dropna(subset=["lat"])
    cells = []
    for f in gj["features"]:
        polys = geo.rings(f["geometry"])
        pts = np.vstack([r for poly in polys for r in poly])
        cells.append({"code": str(int(f["properties"]["geonameid"])), "polys": polys,
                      "bbox": (*pts.min(axis=0), *pts.max(axis=0))})
    cities["geonameid"] = geo.raion_of(cities.lon.to_numpy(float), cities.lat.to_numpy(float), cells)
    cities[["city_id", "geonameid"]].to_csv(TEMP / "viina_city_settlement.csv", index=False)
    print(f"{(cities.geonameid != '').sum()} of {len(cities)} city points inside a place polygon")


if __name__ == "__main__":
    main()
