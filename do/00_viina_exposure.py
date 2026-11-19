"""00_viina_exposure.py -- distance to the front and attacks nearby, by robota.ua city and month

Called by 03_exposure_build.do (Part C), which passes the settings below, so that they are
set in one place (step 0 of that file). Can also be run on its own (defaults = Stata's):
    python do/00_viina_exposure.py --viina "<VIINA Data folder>" [--front_days_share 0.5]
        [--attack_radius_km 15] [--first_month 2021-01] [--variants 0]

What it builds (plan: docs/exposure_viina_spec.md):
  MEASURE 1  distance from each city to the nearest Russian-held populated place, by month.
  MEASURE 2  days in the month with at least one attack (shelling, airstrike, drone) reported
             within a radius of the city.

SOURCES
  VIINA 2.0 (Zhukov, github zhukovyuri/VIINA; license ODbL; cite Zhukov 2023, Journal of
  Comparative Economics 51(4)). Clone of 6 Nov 2026, data to 27 Oct 2026.
  - Control of places: data/temp/viina_settlement_month.csv, made by 00_viina_control.py from
    VIINA's daily control files. For each of 33,141 places and month: days held by Russia under
    my both-sources rule (VIINA's own vote AND DeepStateMap say "RU"; VIINA's vote alone where
    DeepStateMap has no status, i.e. until March 2022). Place coordinates and raion:
    data/temp/viina_settlements.csv.
  - Events: VIINA/Data/event_1pd_latest_YYYY.zip, 24 Feb 2022 - 27 Oct 2026. One row per event
    type x place x day ("one per day" filter of VIINA: repeated reports of the same kind of event
    in the same place on the same day are one event). Each row has the date, the place (GeoNames
    id), its coordinates, how precisely it is located (GEO_PRECISION), and 0/1 flags for event
    types (t_*) and actors (a_*), predicted by VIINA's text classifier.
  - Cities: data/temp/robota_city_raion.csv (00_city_raion.py): each robota.ua city's point
    (median of its vacancies' pins) and raion. Cities abroad or without pins have no point and
    are not in the output.

MEASURE 1: WHICH PLACES ARE RUSSIAN-HELD IN A MONTH (the "front set")
  A place is in the front set of month m if it is Russian-held on at least a share
  --front_days_share (default 0.5) of the month's days with data. Three periods:
  1. Jan 2021 - Feb 2022: the reconstructed 2014 line, the same in every month. VIINA has no
     control data before 23 Feb 2022, so the pre-war line is rebuilt from later data: places in
     Crimea, Sevastopol, Donetsk or Luhansk oblast (raion codes UA01, UA85, UA14, UA44) that are
     in the front set in EVERY month from Feb 2022 to Oct 2026. February 2022 covers only 23-28
     Feb, so places taken later in 2022 (Mariupol, Melitopol, Sievierodonetsk...) drop out.
     February 2022 also uses this line: under the half-of-days rule the five invasion days are a
     minority of the month.
     Known errors: slightly too small (places held before 2022 and retaken later are missing);
     a village at the old line taken on 24-26 Feb could slip in. Check: the file
     viina_line2014_check.csv compares the line with VIINA's status on 23 Feb 2022 alone.
  2. Mar 2022: DeepStateMap is missing, so control is VIINA's vote alone, in effect Wikipedia's
     map, which shaded the areas Russian columns moved through (overstates control in the north,
     e.g. Sumy and Chernihiv oblasts). Kept, and flagged as low quality in Stata (Feb-Mar 2022).
  3. Apr 2022 - Oct 2026: the both-sources rule.

  Distance: great-circle (haversine) distance, Earth radius 6,371 km. Computed exactly with a
  k-d tree on 3-D unit vectors: the straight-line (chord) distance c between two unit vectors
  converts to the great-circle distance as 2 * R * arcsin(c / 2).

MEASURE 2: WHICH EVENTS ARE KEPT
  - type: artillery, airstrike or drone (t_artillery_b, t_airstrike_b or t_uav_b = 1);
  - precision: located at least at a settlement (GEO_PRECISION = ADM3 or STREET). Events placed
    only at oblast or raion level have no usable point. Share dropped by year:
    viina_events_precision.csv;
  - location: not in a place that is in the front set that month (those are mostly Ukrainian
    strikes on occupied territory, not exposure of the places I study).
  Attack days near a city = number of days in the month with at least one kept event within
  --attack_radius_km (default 15 km) of the city point. Days rather than events, because VIINA is
  built from news: big cities and high-profile strikes get many more reports than a village
  shelled every day. Before 24 Feb 2022 the value is 0 (no events).

OUTPUTS (data/temp)
  viina_city_month.csv        one row per city x month, Jan 2021 - Oct 2026, balanced:
                              city_id, month, dist_front_km, city_place_held (the city's own
                              place is in the front set), attack_days_near.
  viina_events_clean.csv      the kept events: id, date, month, place, coordinates, raion of the
                              event point, type and actor flags (03 counts attack days by raion
                              and oblast from it).
  viina_events_precision.csv  by year: events of the kept types, dropped for precision, dropped
                              as located in Russian-held places.
  viina_line2014_check.csv    the 2014 line against VIINA's status on 23 Feb 2022, by oblast.
  With --variants 1 (robustness, used by the commented-out section at the end of 03), also:
  viina_city_month_variants.csv  distance to Russian-held or contested places; attack days within
                              5 and 30 km; number of events nearby; distance-weighted sum of
                              events (weight exp(-km/10) up to 50 km); days with lethal attacks,
                              property damage, ground combat; attack days without events
                              attributed only to Ukrainian forces.
  viina_place_month.csv       place x month distance to the front (for raion and oblast
                              population-weighted versions of measure 1).
  Not built yet (see the spec): distance to the Russian and Belarusian borders (needs country
  polygons, e.g. Natural Earth) and a daily version of the distance.
"""
import argparse
import json
import sys
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.spatial import cKDTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from importlib import import_module
geo = import_module("00_city_raion")          # point-in-polygon functions (raion of each event)

PROJECT = Path(__file__).resolve().parent.parent
THESIS = PROJECT.parent
DEFAULT_VIINA = THESIS / "VIINA" / "Data"
GEOJSON = THESIS / "ukrainian-air-raid-sirens-dataset" / "example" / "ukr_admin2.geojson"
TEMP = PROJECT / "data" / "temp"
EARTH_KM = 6371.0
EVENT_YEARS = range(2022, 2027)
LINE2014_OBLASTS = ("UA01", "UA85", "UA14", "UA44")   # Crimea, Sevastopol, Donetsk, Luhansk
LAST_PREWAR_MONTH = "2022-02"     # months up to here use the 2014 line
TYPE_FLAGS = ["t_artillery_b", "t_airstrike_b", "t_uav_b"]
KEEP_FLAGS = TYPE_FLAGS + ["t_civcas_b", "t_property_b", "t_firefight_b", "t_armor_b",
                           "a_rus_b", "a_ukr_b"]


# --- helpers -----------------------------------------------------------------------------
def unit_vectors(lat, lon):
    """Points on the unit sphere (x, y, z) from latitude and longitude in degrees."""
    la, lo = np.radians(np.asarray(lat, float)), np.radians(np.asarray(lon, float))
    return np.column_stack([np.cos(la) * np.cos(lo), np.cos(la) * np.sin(lo), np.sin(la)])


def chord_to_km(chord):
    """Straight-line distance between unit vectors -> great-circle distance in km."""
    return 2 * EARTH_KM * np.arcsin(np.clip(np.asarray(chord) / 2, 0, 1))


def km_to_chord(km):
    """Great-circle distance in km -> straight-line distance between unit vectors."""
    return 2 * np.sin(km / (2 * EARTH_KM))


def nearest_km(points_from, points_to):
    """For each point in points_from, great-circle km to the nearest point in points_to."""
    if len(points_to) == 0:
        return np.full(len(points_from), np.nan)
    chord, _ = cKDTree(points_to).query(points_from)
    return chord_to_km(chord)


def load_raions():
    gj = json.loads(GEOJSON.read_text(encoding="utf-8"))
    out = []
    for f in gj["features"]:
        polys = geo.rings(f["geometry"])
        pts = np.vstack([r for poly in polys for r in poly])
        out.append({"code": f["properties"]["adm2_pcode"], "polys": polys,
                    "bbox": (*pts.min(axis=0), *pts.max(axis=0))})
    return out


def days_near(events, city_vec, radius_km, city_ids):
    """City x month count of distinct days with >= 1 event within radius_km of the city."""
    if events.empty:
        return pd.DataFrame(columns=["city_id", "month", "days"])
    hits = cKDTree(city_vec).query_ball_point(unit_vectors(events.lat, events.lon),
                                              km_to_chord(radius_km))
    pairs = [(city_ids[c], d) for cities, d in zip(hits, events.date) for c in cities]
    if not pairs:
        return pd.DataFrame(columns=["city_id", "month", "days"])
    p = pd.DataFrame(pairs, columns=["city_id", "date"]).drop_duplicates()
    p["month"] = p.date.str[:4] + "-" + p.date.str[4:6]
    return p.groupby(["city_id", "month"]).size().rename("days").reset_index()


# --- main --------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--viina", default=str(DEFAULT_VIINA))
    ap.add_argument("--front_days_share", type=float, default=0.5)
    ap.add_argument("--attack_radius_km", type=float, default=15.0)
    ap.add_argument("--first_month", default="2021-01")
    ap.add_argument("--variants", type=int, default=0)
    a = ap.parse_args()
    viina = Path(a.viina)
    print(f"settings: front_days_share={a.front_days_share}, attack_radius_km="
          f"{a.attack_radius_km}, first_month={a.first_month}, variants={a.variants}")

    # --- 1. Places, monthly control, and the front set ------------------------------------
    places = pd.read_csv(TEMP / "viina_settlements.csv", dtype={"raion_pcode": str})
    places["raion_pcode"] = places.raion_pcode.fillna("")
    sm = pd.read_csv(TEMP / "viina_settlement_month.csv")
    sm["held"] = sm.days_ru / sm.days >= a.front_days_share
    sm["held_or_contested"] = (sm.days_ru + sm.days_contested) / sm.days >= a.front_days_share
    viina_months = sorted(sm.month.unique())                       # 2022-02 ... 2026-10

    # 1a. The reconstructed 2014 line: held in every month, in the four oblasts
    months_held = sm[sm.held].groupby("geonameid").size()
    always = months_held[months_held == len(viina_months)].index
    in_old_oblasts = places.raion_pcode.str[:4].isin(LINE2014_OBLASTS)
    line = places[places.geonameid.isin(always) & in_old_oblasts]
    print(f"2014 line: {len(line)} places "
          f"{line.raion_pcode.str[:4].value_counts().to_dict()}")

    # 1b. Front set by month: the line up to Feb 2022, the monthly rule from Mar 2022
    all_months = [str(p) for p in pd.period_range(a.first_month, viina_months[-1], freq="M")]
    def front_ids(month, column="held"):
        if month <= LAST_PREWAR_MONTH:
            return set(line.geonameid)
        return set(sm.loc[(sm.month == month) & sm[column], "geonameid"])
    place_vec = dict(zip(places.geonameid, unit_vectors(places.lat, places.lon)))

    # --- 2. Cities and their distance to the front -------------------------------------------
    city_place = pd.read_csv(TEMP / "viina_city_settlement.csv")   # city -> its VIINA place
    cities = pd.read_csv(TEMP / "robota_city_raion.csv").dropna(subset=["lat"])
    cities = cities.merge(city_place, on="city_id", how="left")
    city_vec = unit_vectors(cities.lat, cities.lon)
    city_ids = cities.city_id.to_numpy()

    rows, place_rows = [], []
    for m in all_months:
        ids = front_ids(m)
        front_vec = np.array([place_vec[g] for g in ids if g in place_vec])
        dist = nearest_km(city_vec, front_vec)
        rows.append(pd.DataFrame({"city_id": city_ids, "month": m, "dist_front_km": dist,
                                  "city_place_held": cities.geonameid.isin(ids).astype(int)}))
        if a.variants:
            ids_c = front_ids(m, "held_or_contested") if m > LAST_PREWAR_MONTH else ids
            vec_c = np.array([place_vec[g] for g in ids_c if g in place_vec])
            rows[-1]["dist_front_contested_km"] = nearest_km(city_vec, vec_c)
            place_rows.append(pd.DataFrame({
                "geonameid": places.geonameid, "month": m,
                "dist_front_km": nearest_km(unit_vectors(places.lat, places.lon), front_vec),
                "place_held": places.geonameid.isin(ids).astype(int)}))
    city_month = pd.concat(rows, ignore_index=True)

    # --- 3. Events: keep artillery / airstrike / drone, located, outside the front set -------
    events, precision = [], []
    held_pairs = set(zip(sm.loc[sm.held, "geonameid"], sm.loc[sm.held, "month"]))
    line_ids = set(line.geonameid)
    for y in EVENT_YEARS:
        z = zipfile.ZipFile(viina / f"event_1pd_latest_{y}.zip")
        e = pd.read_csv(z.open(z.infolist()[0]), dtype={"date": str, "GEO_PRECISION": str})
        e[KEEP_FLAGS] = e[KEEP_FLAGS].fillna(0).astype(int)
        e = e[(e[TYPE_FLAGS] == 1).any(axis=1)].copy()
        n_type = len(e)
        precise = e.GEO_PRECISION.isin(["ADM3", "STREET"])
        e = e[precise].copy()
        e["month"] = e.date.str[:4] + "-" + e.date.str[4:6]
        gid = e.geonameid.astype("Int64")
        in_front = [(g in line_ids) if m <= LAST_PREWAR_MONTH else ((g, m) in held_pairs)
                    for g, m in zip(gid.fillna(-1).astype(int), e.month)]
        e["in_front_set"] = np.array(in_front, dtype=bool)
        precision.append({"year": y, "events_kept_types": n_type,
                          "dropped_imprecise": int((~precise).sum()),
                          "share_dropped_imprecise": round(float((~precise).mean()), 4),
                          "dropped_in_russian_held_place": int(e.in_front_set.sum()),
                          "events_kept": int((~e.in_front_set).sum())})
        events.append(e[~e.in_front_set])
        print(f"  events {y}: {precision[-1]}")
    ev = pd.concat(events, ignore_index=True).rename(columns={"latitude": "lat",
                                                              "longitude": "lon"})
    ev = ev[ev.date >= "20220224"]                                  # war only (none earlier)
    ev["raion_pcode"] = geo.raion_of(ev.lon.to_numpy(float), ev.lat.to_numpy(float),
                                     load_raions())
    ev_out = ev[["event_id_1pd", "date", "month", "geonameid", "asciiname", "lat", "lon",
                 "raion_pcode", "n_reports"] + KEEP_FLAGS]
    ev_out.to_csv(TEMP / "viina_events_clean.csv", index=False, encoding="utf-8")
    pd.DataFrame(precision).to_csv(TEMP / "viina_events_precision.csv", index=False)

    # --- 4. Attack days near each city --------------------------------------------------
    near = days_near(ev, city_vec, a.attack_radius_km, city_ids).rename(
        columns={"days": "attack_days_near"})
    city_month = city_month.merge(near, on=["city_id", "month"], how="left")
    city_month["attack_days_near"] = city_month.attack_days_near.fillna(0).astype(int)
    city_month[["city_id", "month", "dist_front_km", "city_place_held",
                "attack_days_near"]].to_csv(TEMP / "viina_city_month.csv", index=False)
    print(f"city x month: {len(city_month)} rows, {city_month.city_id.nunique()} cities, "
          f"{all_months[0]} to {all_months[-1]}")

    # --- 5. Check: the 2014 line against VIINA's status on 23 Feb 2022 ------------------
    z = zipfile.ZipFile(viina / "control_latest_2022.zip")
    day0 = set()
    for ch in pd.read_csv(z.open(z.infolist()[0]), usecols=["geonameid", "date", "status"],
                          dtype={"date": str, "status": str}, chunksize=2_000_000):
        ch = ch[(ch.date == "20220223") & (ch.status == "RU")]
        day0 |= set(ch.geonameid.astype(float).astype(int))
    p = places.assign(oblast_pcode=places.raion_pcode.str[:4],
                      in_line=places.geonameid.isin(line_ids),
                      ru_23feb=places.geonameid.isin(day0))
    chk = (p[p.in_line | p.ru_23feb].groupby("oblast_pcode")
           .agg(in_line=("in_line", "sum"), russian_23feb=("ru_23feb", "sum"),
                both=("in_line", lambda s: (s & p.loc[s.index, "ru_23feb"]).sum()))
           .reset_index())
    chk.to_csv(TEMP / "viina_line2014_check.csv", index=False)
    print("2014 line vs 23 Feb 2022:\n" + chk.to_string(index=False))

    # --- 6. Variants (robustness; only with --variants 1) ---------------------------------
    if a.variants:
        v = city_month[["city_id", "month", "dist_front_contested_km"]].copy()
        for r in (5, 30):
            d = days_near(ev, city_vec, r, city_ids).rename(columns={"days": f"attack_days_{r}km"})
            v = v.merge(d, on=["city_id", "month"], how="left")
        subsets = {"lethal_days_near": ev.t_civcas_b == 1,
                   "damage_days_near": ev.t_property_b == 1,
                   "ground_combat_days_near": (ev.t_firefight_b == 1) | (ev.t_armor_b == 1),
                   "attack_days_near_strict": ~((ev.a_ukr_b == 1) & (ev.a_rus_b == 0))}
        for name, keep in subsets.items():
            d = days_near(ev[keep], city_vec, a.attack_radius_km, city_ids).rename(
                columns={"days": name})
            v = v.merge(d, on=["city_id", "month"], how="left")
        # number of events nearby, and distance-weighted sum (exp(-km/10), up to 50 km)
        counts, weighted = [], []
        for m in all_months:
            sub = ev[ev.month == m]
            if sub.empty:
                counts.append(np.zeros(len(city_ids))); weighted.append(np.zeros(len(city_ids)))
                continue
            t = cKDTree(unit_vectors(sub.lat, sub.lon))
            near_r = t.query_ball_point(city_vec, km_to_chord(a.attack_radius_km))
            counts.append(np.array([len(x) for x in near_r]))
            sv = unit_vectors(sub.lat, sub.lon)
            near50 = t.query_ball_point(city_vec, km_to_chord(50))
            weighted.append(np.array([
                np.exp(-chord_to_km(np.linalg.norm(sv[idx] - city_vec[i], axis=1)) / 10).sum()
                if idx else 0.0 for i, idx in enumerate(near50)]))
        v = v.merge(pd.DataFrame({"city_id": np.tile(city_ids, len(all_months)),
                                  "month": np.repeat(all_months, len(city_ids)),
                                  "attack_events_near": np.concatenate(counts),
                                  "attack_weighted_sum": np.concatenate(weighted)}),
                    on=["city_id", "month"], how="left")
        v = v.fillna({c: 0 for c in v.columns if c not in ("city_id", "month",
                                                          "dist_front_contested_km")})
        v.to_csv(TEMP / "viina_city_month_variants.csv", index=False)
        pd.concat(place_rows).merge(places[["geonameid", "raion_pcode", "population"]],
                                    on="geonameid").to_csv(TEMP / "viina_place_month.csv",
                                                           index=False)
        print("variants written")


if __name__ == "__main__":
    main()
