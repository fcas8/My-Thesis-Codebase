# War exposure from VIINA: what to build and why

*Note written 14 November 2026. It is a plan for new exposure files in `do/03_exposure_build.do`,
next to the alarm measures already there.*

> **Status (14 Nov 2026, later the same day).** Built: `do/00_viina_exposure.py` and Part C of
> `do/03_exposure_build.do` (steps V1-V4, checks C4): city × month distance to the front and attack
> days within 15 km; attack days by raion and oblast; oblast occupation flag in
> `03_geo_mappings.do` (step 5c-bis). Variable names differ from this note where its short names
> were unclear: $F$ → `front_proximity`, $A$ → `attack_days_near`, `ctrl_lowq` →
> `control_low_quality`. Written but commented out (end of 03; Python side behind `--variants 1`):
> the robustness variants, the raion and oblast versions of measure 1, and the fixed exposure
> (`exposure_city_fixed.dta`). Not built: distances to the Russian and Belarusian borders (need
> country polygons) and the daily distance. One deviation: February 2022 uses the 2014 line
> (under the half-of-days rule, 23 of its 28 days are pre-invasion); it is still flagged
> `control_low_quality`, like March.

## Why add VIINA measures at all

The alarm data (Part B of 03) tell me how many hours a raion spent under air-raid alert. That is a
good measure of disruption, but it has two weaknesses for my design.
- **It is coarse.** An alarm usually covers a whole raion or oblast, so all cities in it get the
  same value. Within an oblast and quarter there is very little variation left: about 1.3
  percentage points.
- **It measures the threat of air attack only.** It says nothing about how close a city is to
  ground fighting, or whether it was actually hit.

VIINA (Zhukov's Violent Incident Information from News Articles, version 2.0) gives two things I
can use at the level of individual places:
- **Who controls each of about 33,000 settlements, day by day.** From this I can compute how far
  any city is from Russian-held territory.
- **Geolocated reports of violent events:** shelling, airstrikes, drone strikes and so on, each
  with a date and coordinates.

My scratch power checks (13 November) suggest the two VIINA measures are as usable as alarms.
- **Distance to the front** is the most credible of the three once regional shocks are absorbed
  with oblast × quarter fixed effects. It detects roughly a 7% change in postings per halving of
  distance.
- **Nearby attacks** detect roughly 4% per doubling.

Averaging all three into one index did worse than any of them alone, so the plan below builds them
as separate measures.

## The files that already exist

`do/00_viina_control.py` already turns VIINA's control data into three small files in
`data/temp/`:
- **`viina_settlements.csv`:** one row per place, with its coordinates, GeoNames population and the
  raion that contains it.
- **`viina_settlement_month.csv`:** for each place and month, how many days it was held by Russia.
  This uses my existing rule: a place counts as Russian-held on a day only if both VIINA's own
  vote and DeepStateMap say so.
- **`viina_city_settlement.csv`:** which VIINA place each robota.ua city falls in.

City coordinates come from `data/crosswalks/geo_city_raion.dta`. The event reports are in the
VIINA clone, `VIINA/Data/event_1pd_latest_YYYY.zip`. They are not processed yet.

## Measuring distance

All distances are great-circle distances between coordinates (the haversine formula, Earth radius
6,371 km). This is the standard choice and needs only a footnote. The quick power checks used a
flat approximation, which is a few percent off at the edges of the country; the final build should
not.

## Measure 1: distance to the front

### Which places count as Russian-held

Every distance measure needs, for each month, the set of places Russia held. Call it
$\mathcal{R}_m$. The basic rule: a place is in $\mathcal{R}_m$ if my both-sources rule marks it
Russian-held on at least half of the month's days.
- **Reminder of the both-sources rule:** VIINA's own vote and DeepStateMap must both say "Russian".
- **At the half-days threshold,** a place lost in the middle of a month switches in that month or
  the next, depending on the date.
- **The threshold is a judgment call.** Check sensitivity with "at least one day" and "every day".

VIINA does not give me this set equally well in every period. There are two problems, and they
lead to three periods with different rules.

**Problem 1: before the invasion there is no data.** VIINA's control data start on 23 February
2022, so for 2021 and early 2022 I have no observed control at all. Yet I need the pre-war line,
the 2014 line around Crimea and the occupied parts of Donetsk and Luhansk, to compute pre-war
distances.

**Problem 2: in the first five weeks of the war, one of my two sources is missing.** DeepStateMap
has no status for any place before April 2022.

| Month | Places counted Russian-held | Place-days without DeepStateMap |
|---|---|---|
| Feb 2022 (23–28 Feb) | 6,136 | 100% |
| Mar 2022 | 7,767 | 100% |
| Apr 2022 | 4,960 | 7% |
| May 2022 | 5,759 | 0% |

How missing DeepStateMap changes the rule:
- **Fallback:** when DeepStateMap is missing, my rule falls back on VIINA's vote alone.
- **What the vote is made of:** a majority of three inputs: DeepStateMap, Wikipedia's control map,
  and Wikipedia's map adjusted with VIINA's news reports. With DeepStateMap missing, the two
  inputs left are both Wikipedia, so early control is in effect Wikipedia's map.
- **Why that overstates Russian control:** in the first weeks that map shaded the broad areas
  Russian columns were moving through, not only places Russia held.
- **Evidence:** in the last days of February the vote already counts about 800 places in Sumy
  oblast and about 500 in Chernihiv oblast as Russian-held. The cities of Sumy and Chernihiv were
  never taken, and Russia had withdrawn from the north by early April. As soon as DeepStateMap
  appears in April, those oblasts disappear from the Russian-held set.
- **Not all wrong:** some of the early marks are real occupation, but in these weeks I cannot
  tell the two apart.

**The three periods**

| Period | Set of Russian-held places | Quality |
|---|---|---|
| Jan 2021 to 23 Feb 2022 | The reconstructed 2014 line (below), the same in every month | Good; slightly too small |
| 24 Feb to 31 Mar 2022 | VIINA's vote alone, because DeepStateMap is missing | Weak; overstates control in the north |
| Apr 2022 to Oct 2026 | The both-sources rule | Good |

**Period 1: the reconstructed 2014 line.** A place belongs to the line if both of these hold:
- it lies in Crimea, Sevastopol, Donetsk or Luhansk oblast (codes UA01, UA85, UA14, UA44);
- it is Russian-held in every month of VIINA's data, from February 2022 through October 2026.

How it behaves:
- **Size:** 2,610 places (Crimea 1,147, Luhansk 768, Donetsk 676, Sevastopol 19).
- **Not a hand-made list:** only the four oblast codes and the half-days threshold are fixed by
  hand.
- **Why it filters out the 2022 conquests:** "every month" includes February 2022, which covers
  only 23–28 February. Places taken later in 2022 were not Russian-held then, so they drop out
  even though Russia has held them since.
  - Kept: Horlivka and Debaltseve, held since 2014–15.
  - Dropped: Mariupol, Volnovakha, Starobilsk, Sievierodonetsk, Lysychansk and Melitopol.
- **Two small errors:**
  - Places held before the invasion but retaken by Ukraine later are missing, so the line is
    slightly too small.
  - A village right at the old line taken on 24–26 February could slip in.
  - Both affect a handful of places and barely move distances.
- **Why not just use the February–March 2022 status?** It overstates control too much. Using it
  put the median pre-war distance at about 128 km instead of about 515 km.
- **Recommended check, not done yet:** take the status on 23 February 2022 alone (the day before
  the invasion) from VIINA's daily files and compare it with this set. If Wikipedia's map was
  accurate that day, the two should nearly coincide.

**Period 2: the invasion weeks (default: keep, flag, test).** For February and March 2022 I use
VIINA's vote as it is, and mark these months with a quality flag (`ctrl_lowq` = 1). The main
regressions include them. One robustness check drops them.
- **Why this is the default:** with quarterly data the damage is limited. 2022 Q1 is mostly
  pre-invasion anyway (1 January to 23 February), so only March really carries the weak data, and
  a result should not hinge on one month. If dropping these months changes the conclusions, that
  is worth knowing and reporting.
- **What not to do:** fill these months with the April 2022 status. By April the north had been
  liberated, so that would erase the occupation of parts of Kyiv, Chernihiv and Sumy oblasts.
  That is the part of the invasion shock I most want to capture.
- **Alternative A, simplest:** treat all of 2022 Q1 as pre-invasion (2014 line) and start the
  time-varying front in 2022 Q2. It is clean, but loses the first weeks of the war for this
  measure. Alarms and attacks still cover them.
- **Alternative B, most work:** the Institute for the Study of War published daily control maps
  from 24 February 2022. Assigning their status to VIINA's places would fill the gap properly.
  Worth doing only if the robustness check shows the invasion weeks matter.

**Period 3: April 2022 onward.** Both sources are available and the both-sources rule applies as
in 03.

### The city measure

For a city $c$ in month $m$, the distance to the front is the distance to the nearest Russian-held
place:

$$D_{cm} = \min_{j \in \mathcal{R}_m} d(c, j).$$

In regressions use $F_{cm} = -\ln \max(D_{cm}, 1)$. The log because a move from 20 to 40 km
plausibly matters as much as one from 200 to 400 km. The minus sign so that higher values mean
more exposed, like the other measures. The cap at 1 km avoids taking the log of zero.

It is also worth storing distance bands (under 25 km, 25–50, 50–100, 100–200, over 200), for a
non-parametric version of the same regression.

Medians across robota cities give a sense of how much this measure moves:

| Period | Median distance to the front |
|---|---|
| 2021 | about 515 km |
| 2022 Q1 | about 128 km |
| 2022 Q2 | about 378 km |
| From 2023 | about 400 km |

Most of the variation within an employer therefore comes from a few episodes in 2022:
- the invasion itself
- the Russian withdrawal from the north in April
- the Kharkiv counteroffensive in September
- the liberation of Kherson in November

It is useful to flag these moves explicitly: for example, a city whose distance changed by at
least 50 km from one month to the next, while within 200 km in one of the two months. The analysis
can then treat them as events.

### Three variants worth having

- **Including contested places.** Measure the distance to places that are Russian-held or
  contested. This gives an upper bound on how close the fighting is.
- **Distance to the Russian border**, and separately to the Belarusian border. These don't change
  over time, but they matter after the invasion.
  - Cities in Sumy, Chernihiv or northern Kharkiv oblast are shelled across the border although no
    Russian-held settlement is near them, so distance to occupied territory alone understates
    their exposure.
  - **How to build the border line:** take the part of Ukraine's national boundary that lies
    within a kilometer of Russia's (or Belarus's) territory. Natural Earth country polygons are
    precise enough.
  - **"Threat distance":** the smaller of the front distance and the Russian-border distance, from
    March 2022.
- **A daily version.** Average the daily nearest distance over the month, instead of using the
  month's majority status. This captures fast moves such as Kyiv oblast in March 2022. It needs the
  large daily files, so build it only if the monthly version proves too coarse.

### Raion and oblast versions

The distance from a raion's centroid would be misleading, because raions are large and their
populations are not centered. Two better options:
- **Population share near the front:** the share of the raion's population living within 25, 50
  or 100 km of the front.
- **Population-weighted average of $F$** over the raion's places.

Both need population weights, and here GeoNames is weak: its population is 0 ("unknown") for most
villages.
- **Proposed default:** use the GeoNames population where it is known. If a raion has no place
  with a known population, give its places equal weight.
- **Alternative, closer to my sample:** weight cities by their robota.ua postings in 2021. These
  weights are fixed before the war, so they don't respond to it.
- **Oblast:** same procedure. Places in Russian-held territory are left out of these averages.

## Measure 2: attacks nearby

### Which events to keep

VIINA classifies each report by type. Keep a report if all of the following hold:
- **Type:** it involves artillery, an airstrike or a drone (the `t_artillery_b`, `t_airstrike_b`
  and `t_uav_b` flags).
- **Precision:** it is located at least to a settlement (`GEO_PRECISION` ADM3 or STREET).
  - Reports placed only at the oblast or raion level have no usable point and are dropped. In a
    2024 sample that is about 22% of reports; the build should record the share by year.
- **Location:** it did not happen in a place that was Russian-held that month. Those are mostly
  Ukrainian strikes on occupied territory, not exposure of the places I study.
  - VIINA's actor flags (`a_rus_b`, `a_ukr_b`) allow a stricter variant that also drops reports
    attributed only to Ukrainian forces. It is worth keeping as a check.

Three subsets are worth building as separate measures:
- **Lethal attacks:** reports with civilian casualties.
- **Damage:** reports of property damage.
- **Ground combat:** firefights and armor.

### From events to a city measure

The main concern with VIINA is that it is built from news. Large cities and high-profile strikes
get many more reports than a village shelled every day. A raw count of reports within some radius
therefore partly measures media attention.

The proposed main measure limits this by counting **days with at least one attack within 15 km**
of the city in the month, rather than the number of reports. For a city $c$ and month $m$:

$$A_{cm} = \#\{\text{days } t \text{ in } m : \text{at least one kept event within 15 km of } c \text{ on day } t\}.$$

In regressions use $\ln(1 + A_{cm})$, or the share of the month's days. Values before the invasion
are zero. For robustness:
- **Radii** of 5 and 30 km.
- **The plain count of reports.** This is what the power check used.
- **A distance-weighted sum,** where each event counts $e^{-\text{distance}/10\text{ km}}$, up
  to 50 km. It avoids the sharp cutoff of a radius.

For raions and oblasts, count the days with at least one attack inside the unit. Alternatively,
take the population-weighted average of attack days near each place, with the same weights as for
distance.

## Fixed exposure, for "after the invasion × exposure" designs

Whether the main regression uses exposure that changes over time or a fixed exposure interacted
with a post-invasion dummy is still open. To keep both doors open, the build also produces
per-city averages over two windows:
- the first year of the war, March 2022 to February 2023
- the whole period with alarm data, March 2022 to August 2026

These are computed for front distance, attack days and the alarm share of the city's raion, with
terciles among cities that were never occupied. The distance to the 2014 line is stored as well:
it is a natural pre-war control for the front measures.

## Output files

Four files in `data/analysis/`, balanced (every unit in every month from January 2021 to
October 2026), labeled in US spelling. Occupied units get missing values plus a flag, as in the
alarm files.
- **`viina_city_month.dta`** (city × month):
  - **distance:** to the front (with and without contested places), to the Russian and
    Belarusian borders, threat distance, $F$, distance band, front-move flag
  - **attacks:** attack days within 5, 15 and 30 km, report count, distance-weighted sum,
    lethal-attack days, ground-combat days
  - **flags and codes:** occupation flag, `ctrl_lowq` (1 in February–March 2022, when control
    comes from VIINA's vote alone), raion and oblast codes
- **`viina_raion_month.dta`** (raion × month): population shares within 25, 50 and 100 km of the
  front, population-weighted $F$, attack days in the raion, population-weighted attack days near
  places, the existing occupation flag, oblast codes and robota oblast name.
- **`viina_oblast_month.dta`:** the same at oblast level.
- **`exposure_city_fixed.dta`** (one row per city): the window averages, their terciles, and the
  distance to the 2014 line.

## How it fits into the pipeline

Stata cannot handle VIINA's daily files comfortably (around 500 MB of text a year), nor
nearest-neighbor searches over tens of thousands of points. The work therefore splits like this.
- **A new Python helper, `do/00_viina_exposure.py`,** run right after `00_viina_control.py` and
  written in the same style: a docstring stating source, rules and outputs, and relative paths.
  - It reads the event files and the control files and does all distance work. A k-d tree on
    unit-sphere coordinates keeps it fast and exact.
  - It writes small CSV files to `data/temp/`: a city × month file, a place × month file for the
    raion aggregation, and the cleaned event list.
- **A new Part C, "VIINA measures", in `03_exposure_build.do`**, in numbered steps: import the
  CSVs, add oblast codes and names from the crosswalks, aggregate to raion and oblast, apply the
  occupation flags, label and save.
- **A final checks step:**
  - **Agreement:** correlation with the alarm share after the invasion.
  - **Spot checks:**
    - Kherson city should be a few km from the front after November 2022.
    - Nikopol should not count as occupied in 2026. Both rules exist precisely to get these two
      right.
    - Lviv should stay above 500 km.
  - **Precision:** the share of events dropped by precision, by year.
  - **2014 line:** compare the reconstructed line with the status on 23 February 2022 alone.
- **Bookkeeping:**
  - `00_main.do` gets the new Python call.
  - The header of 03 lists the new inputs and outputs.
  - `output_inventory.xlsx` gets the new files.

## Caveats for the thesis text

- **News coverage.** VIINA's events reflect news coverage, so attacks are best treated as a
  complement to alarms, not a replacement. Counting attack days rather than reports reduces the
  problem but does not remove it.
- **The 2014 line** is reconstructed from 2022 data and is slightly too small.
- **February–March 2022 control** comes from VIINA's vote alone and overstates Russian control in
  the north. These months are flagged, and results should be shown without them.
- **"Russian-held"** depends on a majority-of-days threshold; report the sensitivity.
- **Coverage ends** on 27 October 2026 for VIINA and in August 2026 for alarms, so joint analyses
  stop in August 2026.
- **Front variation is concentrated in 2022.** Estimates using distance to the front lean on a few
  episodes in that year. The thesis should say so and show them separately.
