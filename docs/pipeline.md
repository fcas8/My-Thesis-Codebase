# Pipeline documentation

Technical documentation of the Stata/Python pipeline that turns the robota.ua vacancy sample
(my own collection) and the air-raid alarm and territorial-control data into analysis files,
descriptive figures and tables. State as of **14 Nov 2026**, export `20261114_112558`. Each
do-file's header has more detail.

---

## 1. Folder layout

```
Project/
├── README.md                    overview
├── docs/pipeline.md             this file
├── do/
│   ├── 00_main.do               runs everything, in order (the only file you need to run)
│   ├── 00_programs.do           shared Stata programs (export_table)
│   ├── 00_*.py                  Python helpers (things Stata does badly: Parquet, polygons, regex on text)
│   └── 01_clean.do … 07_decomposition.do   Stata stages
├── data/
│   ├── raw/                     macro/ (NBU CPI, NBU USD rate, WB PPP), ukrstat/ (population 2022)
│   ├── crosswalks/              code lists and place tables (robota_*.csv, geo_*.dta, ua_raions.csv, KSE occupation files)
│   ├── analysis/                analysis datasets (.dta)
│   └── temp/                    intermediate files, logs/ (one log per step), descriptives/ (data behind figures)
└── output/
    ├── figures/                 PDF figures (04_*, 05_*)
    └── tables/                  final tables only, each as .xlsx + .tex (04_*, 05_*)
```

The repository holds code, crosswalks and aggregate outputs only. `data/raw`, `data/temp`,
`data/analysis`, `*.dta` and `*.log` are git-ignored. The robota data hold contact first
names in the descriptions, so they are not shared.

External inputs, next to `Project/` (each is read-only for the pipeline):

| Folder | What | Version used |
|---|---|---|
| `Collector/data/exports/<timestamp>/` | robota.ua sample: `vacancies.csv`, `vacancies_with_text.parquet`, `year_summary.csv` | `20261114_112558` (26.1% of IDs in every year, weight 3.83) |
| `ukrainian-air-raid-sirens-dataset/` | alarm data (git clone, Vadimkin): `datasets/official_data_en.csv`, `volunteer_data_en.csv`; raion map `example/ukr_admin2.geojson` (OCHA COD-AB v05, 1 Sep 2025) | pulled 5 Nov 2026 |
| `VIINA/Data/` | territorial control by populated place and day (Zhukov, VIINA 2.0) | commit `a1ad3633`, data to 27 Oct 2026 |

## 2. How to run

1. Set `$export` in `do/00_main.do` (the **only** path to change), then run `00_main.do` in Stata.
2. Needs Python 3 with pandas, numpy, pyarrow, launched as `py`; Stata packages `encoder`,
   `reghdfe`, `ftools`.
3. Each Python helper's main output is deleted before it runs and checked afterwards, because
   `shell` does not pass Python errors back to Stata. If one is missing, the run stops; see
   `data/temp/logs/00_<name>.log`.
4. Each Stata stage writes its own log to `data/temp/logs/`.
5. Run stages through `00_main.do`. Run alone, 01 and 02 fall back to an older hard-coded
   export, and 01 then stops at the description-hash merge (the hash file belongs to the
   current export).

Flow:

```
export ──► 00_description_hash.py ─┐
       ──► 00_city_raion.py ───────┼──► 01_clean ──► 02_sample_checks (no data changes)
       ──► 00_text_features.py ─┐  │
VIINA  ──► 00_viina_control.py ─┼──┴──► 03_exposure_build (runs 03_geo_mappings first,
                                │                  and 00_viina_exposure.py in Part C)
sirens ──► 00_oblast_borders.py │                │
                                │     01 + 03 ──► 04_descriptives ──► descriptives_base.dta
                                └────────────────────────────────────► 05_descriptives_rq
```

## 3. What each script does

### Python helpers (run by `00_main.do`, in this order)

| Script | Task | Main outputs |
|---|---|---|
| `00_description_hash.py` | Reads descriptions from the Parquet file. For each vacancy: an MD5 fingerprint of the whitespace-collapsed description (so Stata can compare texts without holding them), its length, and the **pay period** stated for the salary (`hour/day/week/month/piece/thousands`), read first from `salary_comment`, then from the ~45 characters after the salary figure in the text. | `data/temp/robota_description_hash.csv` |
| `00_city_raion.py` | Point-in-polygon. Lists the 139 raions of the map. Gives each robota.ua city a raion: takes all its vacancies' pins inside a box around Ukraine, drops robota.ua's default pins in Kyiv (a placeholder, and Kyiv's center for other cities), keeps pins in the city's own oblast, takes the real pin closest to the **median** lat/lon, and finds the raion that holds that point. Region-wide entries ("Zakarpattia", "Krym") get no raion. Reports `n_coord` and `share_same` (share of the city's pins in the same raion) as checks. | `data/crosswalks/ua_raions.csv`, `data/temp/robota_city_raion.csv` |
| `00_viina_control.py` | From VIINA's daily status by place: days held by Russia, days contested, and single-source checks, per place and month. Also finds the raion of every place and the VIINA place of every robota city point. **Rule:** a place is Russian-held on a day only if VIINA's vote AND DeepStateMap both say RU (VIINA's vote alone where DeepStateMap has no status, i.e. until about April 2022). | `data/temp/viina_settlements.csv`, `viina_settlement_month.csv`, `viina_city_settlement.csv` |
| `00_oblast_borders.py` | Oblast and country borders as polylines for Stata maps: raion edges shared by two oblasts, plus edges used by one raion only, joined and thinned (Douglas-Peucker, ~1 km). Also the raion polygons (outer rings) for the filled maps of `04_descriptives_exposure.do`. | `data/temp/ua_oblast_borders.csv`, `ua_raion_polygons.csv` |
| `00_viina_exposure.py` | **Run by `03_exposure_build.do` (step V1), not by `00_main.do`**, with the settings of 03's step 0. For each robota city × month (Jan 2021–Oct 2026): great-circle distance to the nearest Russian-held VIINA place (2014 line rebuilt from VIINA up to Feb 2022; VIINA's vote alone in Mar 2022; both-sources rule from Apr 2022), and days with an attack (artillery/airstrike/drone event, located at settlement level, not in a Russian-held place) within 15 km. Also the kept events, a precision table and a check of the 2014 line against 23 Feb 2022. Variants only with `--variants 1`. | `data/temp/viina_city_month.csv`, `viina_events_clean.csv`, `viina_events_precision.csv`, `viina_line2014_check.csv` |
| `00_text_features.py` | Features of each vacancy for 05, by a dictionary approach (codebook: §7). (A) robota.ua tags `cl_*`. (B) Regex flags on title + description `tx_*` (experience, education, training, gender, target groups, age caps, deferment, military registration, air-raid shelter, backup power, remote, relocation, housing). (C) Badge flags `bd_*`, kept apart from the text. (D) ISCO-08 of the title (`isco1`, `isco2`) through the KSE occupation crosswalk plus robota additions. (E) Military role and unit type. | `data/temp/robota_text_features.csv`, `robota_text_features_labels.csv` |

### Stata stages

**`00_programs.do`**: defines `export_table`, which writes the data in memory as a final table
in `.xlsx` (headers = variable labels) and `.tex` (booktabs `tabular`, LaTeX characters escaped).

**`01_clean.do`**: robota.ua vacancy sample to `data/analysis/robota_vacancies_clean.dta`.
No vacancy is dropped.
1. Import `vacancies.csv`; check `id` is unique.
2. Zeros that mean missing: coordinates, salaries, `notebook_id`, `district_id`.
3. Dates: `pub_date` (latest publication) and `fetch_date`.
4. **Period from the id.** `post_invasion = id >= 9,138,846`. **`created_date`** = running
   minimum of `date_published` over this id and all higher ids (see §5.2).
5. **Wage** (monthly UAH) with `wage_rule`. Use the single salary, else the range midpoint,
   else the one bound. 1 = inverted range → missing. 2 = upper > 5 × lower → lower bound.
   3 = below half the minimum wage at creation → missing (amount kept in `pay_posted`, unit
   in `pay_unit`). 4 = above 500,000 → missing. 5 = military range → lower bound. Minimum
   wage schedule `mw` hard-coded by date. Flags `has_wage`, `wage_below_mw`.
6. Flags: `military` (branch 48 "Defence of Ukraine", plus military units, ТЦК, brigades and
   National Guard filed under branch 9, police excluded); `panel_candidate` (has an employer id
   and is neither an agency nor a state employment center); `test_or_anon`; `ses_posting`
   (state employment center uploads: name matches an employment center AND branch 9);
   `readvert` (an earlier sampled vacancy with the same employer, title, city and identical
   description hash, created at most 90 days before).
   **Multi-city batches.** robota.ua stores one city per vacancy id, so the same job title
   advertised in several cities is several ids. Batch = same employer + same title
   (lowercase, punctuation ignored) + same quarter of `created_date`. `multicity` = the batch
   has sampled vacancies in 2+ cities; `n_cities_batch` = its distinct cities in the sample
   (a lower bound: I see ~26% of ids); `broadcast` = multi-city batch with identical text
   and identical posted pay in every copy and no address in any (`desc_address`, from
   `00_description_hash.py`): possibly one job advertised in several cities. Missing for
   postings without employer id and for employment centers (their "copies" are different
   registered vacancies sharing a common title). Manual reading of Q3 2026 batches (14 Nov):
   mostly genuine local openings with a template text (pay differs by city, store addresses),
   so multi-city vacancies count as local postings; use `broadcast` for robustness. On export
   `20261114_112558`: `multicity` = 8.6% of eligible vacancies (6–10% by year), of which
   15% `broadcast`.
7. Value labels from `data/crosswalks/robota_*.csv`; oblast from robota.ua's city list.

**`02_sample_checks.do`**: checks only, results in the log, changes no data.
Weights constant within stratum and equal to the collector's `year_summary.csv`; id vs
publication date (blocks of 100k ids, publication before the id's year, sharpness of the
invasion boundary); repeats and re-ads by time gap, year, employer size, oblast; employer
identity (several names per id, deleted accounts, `notebook_id` vs account age, same firm
under several ids → `data/temp/employer_link_candidates*.csv` for manual review; it never
overwrites a file already filled in by hand); how detectable "exit" is by employer size;
wage distributions and rules; geography; composition over time; missing values.
The notes at the bottom of the file record the results of earlier runs.

**`03_exposure_build.do`**: war exposure from air-raid alarms. Runs `03_geo_mappings.do` first.
- Population: UkrStat resident population, January 2022 average (Kyiv city + oblast summed).
- `alarms_events.dta`: official alarms, one row per alarm, exact duplicates dropped (~114k
  repeated rows in the repo), oblast/raion codes attached.
- **Part A (replicates ABZ EP 2026, reference only):** official alarms that ended by
  28 Oct 2025; per oblast-month: number of alarms, summed duration (overlaps add up), days
  with an alarm (UTC days); totals over the whole period and terciles across the 20
  non-occupied oblasts. Also by raion with the same method (not in the paper).
  → `abz_oblast_month`, `abz_raion_month`, `abz_oblast_exposure`.
- **Part B (my measure):** hours a raion is under alarm. An alarm counts for a raion if it
  was announced for its oblast or for the raion itself. Overlapping alarms are merged (a
  union of intervals). Times are Kyiv local time. Hours split into working hours (Mon–Fri
  9–18) and night hours (22–6). `hours_any` adds hromada-level alarms (upper bound).
  Volunteer data fill 25 Feb–15 Mar 2022 only. Ends 31 Aug 2026.
  → `alarms_raion_day` (days with an alarm only) and `alarms_raion_month` (balanced, zeros
  kept, `share_hours`, `share_days`). Missing for Crimea, Sevastopol, Luhansk (no data) and
  for raion-months with `occupied_raion = 1`.
- **Part C (VIINA measures, plan in `docs/exposure_viina_spec.md`):** step V1 runs
  `00_viina_exposure.py`; V2 city × month `dist_front_km`, `front_proximity` (= −ln(max(km,1))),
  `front_band`, `front_move`, `control_low_quality` (Feb–Mar 2022), `attack_days_near` (count,
  share, log); V3–V4 attack days inside each raion and oblast. Balanced Jan 2021–Oct 2026;
  occupied units missing with a flag. All Part C settings are globals in step 0. Robustness
  variants, raion/oblast versions of the distance and the fixed exposure are written but
  commented out at the end of the file.
- Checks C1–C4, including Part B vs Part A by oblast and Part C spot checks (Kherson, Nikopol,
  Lviv), precision and the 2014 line.

**`03_geo_mappings.do`**: place tables shared by the exposure files (`data/crosswalks/geo_*.dta`).
Oblast table (paper code, map pcode, names in the alarm, UkrStat and robota sources, paper map
`_ID`, `no_alarm_data`). Raion table and raion names in the alarm data (with names from before
the 2024 renaming). City → raion. An assert that every place name in the alarm data is matched.
**Occupation:** raion × month `occ_share` = days-weighted share of the raion's GeoNames
population in Russian-held places; `occupied_raion = occ_share > 0.5`. City × month
`occupied_city` = the city's place held by Russia for more than half the month.

**`04_descriptives.do`**: descriptives of the sample and the market, no exposure. Saves
`data/temp/descriptives_base.dta` for 05. Steps: CPI / USD / PPP (1); sample and groups (2);
Table 1 by year (3); counts monthly, seasonal, daily around the invasion (4); military and the
defense industry (5); industry shares and levels (6); professional level (7); wages:
disclosure, levels in UAH/real/PPP/USD, by group, a composition-adjusted series, kernel
densities (8); geography: map of the main city of each oblast, macro-area shares, oblast
change (9); employer panel: active/new/last seen, pre-war employers seen again,
concentration, relocation across macro-areas (10).

**`04_descriptives_exposure.do`**: descriptives of the three exposure measures themselves
(alarm share of hours by raion; VIINA attack days; distance to the front), war window Mar 2022 -
Aug 2026, no regressions. Builds a raion x month panel (population Jan 2022 = GeoNames shares
within UkrStat oblast totals; raion front = population-weighted proximity of its robota cities)
and a city x month panel. Maps of levels by year, changes (2025 vs 2022) and the front's
evolution (filled maps with Stata's `grmap`); population-weighted series and high-exposure
(pooled top 20%) population shares; within/between variance decomposition; correlations and
overlap of high-exposure units; sample coverage, population vs vacancies, empty cells,
occupation. Outputs `04e_*`.

**`05_descriptives_rq.do`**: descriptives by research question. Exposure groups only split
the sample; there are no regressions on exposure. RQ1 margins (entry cohorts; winter windows
Oct 1–Feb 23 split into continuing / entry / exit). RQ6 concentration (exit by size; shares
by employer size). RQ2 relocation (shares by exposure group; Foster-Haltiwanger-Krizan
within/between/entry/exit split; continuing employers' own-area share; adaptation such as
remote work, shelters, deferment). RQ3 wages (percentile gaps, spread within occupation ×
level cells, gaps vs Kyiv city, occupations' vacancies vs wages, experience premium). RQ4
upskilling (requirements over time and by exposure). RQ5 substitution (women, veterans,
students, pensioners, deferment; women in male-typed jobs; by occupation and industry). RQ7
military recruitment (units, roles, pay, where, competition with civilian job families).

## 4. Analysis files

| File (`data/analysis/`) | Unit | Built by |
|---|---|---|
| `robota_vacancies_clean.dta` | vacancy (`id` unique) | 01 |
| `alarms_events.dta` | official alarm | 03 |
| `abz_oblast_month.dta`, `abz_raion_month.dta` | oblast/raion × month, months with alarms only | 03 Part A |
| `abz_oblast_exposure.dta` | oblast, whole period, terciles | 03 Part A |
| `alarms_raion_day.dta` | raion × local day, days with an alarm only, **occupation flag not applied** | 03 Part B |
| `alarms_raion_month.dta` | raion × month, Feb 2022–Aug 2026, balanced | 03 Part B |
| `viina_city_month.dta` | robota city × month, Jan 2021–Oct 2026, balanced: distance to the front, attack days | 03 Part C |
| `viina_raion_month.dta`, `viina_oblast_month.dta` | raion/oblast × month, Jan 2021–Oct 2026: attack days in the unit | 03 Part C |
| `data/crosswalks/geo_raion_occupation.dta`, `geo_oblast_occupation.dta`, `geo_city_occupation.dta` | raion/oblast/city × month | 03_geo_mappings |

Codes: `oblast` = the paper's code (Kyiv city inside Kyiv oblast, 39); `oblast_pcode`,
`raion_pcode` = OCHA COD-AB codes (Kyiv city is its own raion, `UA8000`). Merge key with the
vacancies: `oblast_ua` (robota.ua oblast name) or `raion_pcode` via `geo_city_raion`.

## 5. Main methodological points

### 5.1 Sampling design ("plan A")
- The collector visits the **same random fraction of vacancy ids in every year's id range**
  (`plan_year`). Weight = ids in range ÷ ids visited, the same for every stratum (3.83 in the
  current export). Weighted counts estimate all vacancies, and the share sampled is the same
  in every period, so employer and period fixed effects absorb it in a PPML.
- About 25% of ids lead to nothing (deleted, unpublished or unused); these cannot be told apart.
- Employer-level statements carry sampling noise: a firm with Y vacancies in a period is
  missed entirely with probability (1−f)^Y. "Exit" means something only for large employers,
  and every exit/entry series is compared with the pre-war 2020/21→2021/22 transition, which
  shows how much churn the sampling creates by itself.

### 5.2 Time
- The **period comes from the id**, never from `date_published` (the latest republication).
- `created_date` = min of `date_published` over this and all later ids. Ids grow with time,
  and a publication date is never earlier than creation, so this is an upper bound on creation
  that never goes back in time.
- Invasion boundary: first post-invasion id 9,138,846. 04/05 define pre-war by `created_date`
  < 24 Feb 2022; 02 uses the id. The two agree up to the boundary.
- Windows used in 04/05: full months Oct 2020–Oct 2026; baseline P0 = calendar 2021; "after"
  P1 = Jan 2023–Oct 2026; quarterly figures 2020q4–2026q3.

### 5.3 Unit and sample groups (04/05)
Unit = new vacancy by creation date; counts = sums of weights; employer counts = sampled
vacancies. Groups are mutually exclusive, and a later rule overrides an earlier one:
1 civilian core → 3 likely re-ads → 2 state employment centers → 4 jobs abroad → 5 military.
The **civilian core** is the main sample. The defense industry (branch 49) stays in the core.

### 5.4 Wages
Posted monthly wage in UAH (01 step 6). Real = constant 2021 UAH (NBU CPI, 2021 = 100); PPP
= real ÷ 2021 PPP factor (8.66 UAH per international $); USD at the NBU monthly average rate.
Real series end in Sep 2026 (last CPI month). All wage series describe postings that **state** a
wage, and that set changes over time (04 step 8a shows disclosure).

### 5.5 Geography
City → oblast from robota.ua's city list. City → raion from the real pin closest to the median of the city's pins, robota.ua's default pins in Kyiv excluded (Python). Kyiv city
is split out of Kyiv oblast in 04/05 (raion UA8000). Macro-areas: Kyiv city, West,
Center-North, South, East.

### 5.6 Exposure
- Part A replicates the paper as a reference. Part B is "mine": hours under alarm by raion.
  Overlaps are merged, times are local, the panel is balanced, and it ends Aug 2026.
- Main measure = alarms that cover the whole raion (oblast or raion level). Hromada alarms
  only in `hours_any`.
- Occupied raion-months and areas without data are **missing**, not zero.
- 05 groups raions by mean `share_hours` over **Mar 2022–Aug 2025** (before alarms moved to
  raion level): Kyiv city / low / middle / high (terciles weighted by 2021 core vacancies) /
  occupied or no data. The **fixed exposure window and the regression design are still open.**
- Power check of 13 Nov 2026 (scripts not kept): in a within-employer, across-location design,
  more sample does not raise power (the noise is location × time shocks). Inference must allow
  for location-time correlation; clustering by employer alone over-rejects.

### 5.7 Classification of jobs and text
Full codebook in §7. Occupation is ISCO-08 from the job title: the KSE work.ua crosswalk (`occupation_rules.csv`, 146 ordered regex rules → 86 groups with ISCO codes) plus 31 robota rules
(`occupation_rules_robota.csv`). Military role and unit come from ordered regexes, where the first match wins. Requirements and perks combine robota.ua tags, badges and my text parse (definitions in the 05 header).

## 7. Codebook: `00_text_features.py`

A **dictionary (keyword) approach**: no model and no training data. Every feature is a
robota.ua tag or badge read from the vacancy's JSON, or a hand-written regular expression
(Ukrainian + Russian, some English) on the vacancy's text. The output has one row per vacancy:
`data/temp/robota_text_features.csv` (all vacancies of the export, every group), plus
`robota_text_features_labels.csv` (value labels). It is used only by `05_descriptives_rq.do`.
Shares in the tables are filled in from the script's log
(% of **all** vacancies, unweighted, all years; for numeric variables the mean among
non-missing).

### 7.1 Steps

| Step | What it does |
|---|---|
| 0. Input | From the Parquet file: `name` (title), `company_name`, `description_text`, `clusters_json`, `languages_json`, `extra_json` |
| 1. Tags → `cl_*` | robota.ua's own tags (`clusters_json`: dimension → values, in Russian). The same tagger runs on every vacancy, so the coding is uniform across years. Lookup tables `EXP`, `EDU`, `SOFT` |
| 2. Normalize | `text` = title + description (badges **not** included). Lower case; every apostrophe form → `'`; all whitespace, including non-breaking spaces, → one space; Latin look-alike letters inside Cyrillic words → Cyrillic (вiйськовий). Matching uses Python's `re` on object-dtype strings (pandas' default Arrow strings use RE2, where `\w` and `\b` miss Cyrillic). `tx_lang`: Ukrainian if letters only in Ukrainian (іїєґ) outnumber letters only in Russian (ыэъё) 3 to 1, Russian the reverse, English if Latin letters are more than twice the Cyrillic ones |
| 3. Text flags → `tx_*` | One pattern per feature (§7.3). Some flags first blank out known false-positive phrases (`drop()`): armored, payment deferral, building shelters, place of residence |
| 4. Badges → `bd_*` | Perk labels in `extra_json`: robota.ua's standard badges (Russian, e.g. "Офис с бомбоубежищем") and employers' own. Kept apart because badge use changes over time |
| 5. Occupation → `isco1`, `isco2` | ISCO-08 from the title through the KSE crosswalk plus robota additions (§7.4) |
| 6. Military → `mil_role`, `mil_unit` | Role from the title (7 patterns), unit type from the employer name (9 patterns); first match wins. Meaningful only for military ads |
| 7. Save | 0/1 as int8; numeric with missing: `cl_exp`, `cl_edu`, `tx_exp_years`, `isco1`, `isco2` |

### 7.2 robota.ua tags (`cl_*`) and badges (`bd_*`)

| Variable | Source | Share / mean |
|---|---|---|
| `cl_exp` | "Опыт работы": Без опыта = 0; от 6 месяцев = 0.5; от 1…5 лет = 1…5 (max if several); missing = no tag | mean 0.41 years |
| `cl_edu` | "Образование": Среднее 1, Середня спеціальна 2, Неоконченное высшее 3, Высшее 4 (max) | mean 3.8 |
| `cl_english` | "Знание языка" includes Английский, or `languages_json` has `languageId == 1` (assumed to be English) | 12.9% |
| `cl_n_soft` | number of distinct values in software/tool dimensions (ПО, Язык программирования, База данных, Графический редактор, analytics/marketing tools…) | mean 0.49 |
| `cl_remote`, `cl_parttime`, `cl_intern`, `cl_rotation` | "Вид занятости": Удаленная работа / Неполная занятость / Стажировка/практика / Вахта | 11.4 / 10.1 / 1.4 / 0.7% |
| `cl_housing`, `cl_disab`, `cl_student`, `cl_pension`, `cl_veteran` | "Дополнительные сведения": housing provided / people with disability / students / pensioners / veterans | 4.4 / 5.2 / 4.4 / 0.04 / 0.01% |
| `cl_lic_c` | "Категория водительских прав": category C (truck) | 2.6% |
| `bd_any` | any badge | 40.9% |
| `bd_shelter` | бомбоубежищ, бомбосхов, укритт, укрыти | 2.1% |
| `bd_power` | генератор, бесперебойн / безперебійн (uninterrupted power or internet), Starlink | 6.8% |
| `bd_defer` | бронир, бронюв, бронь, відстроч, отсроч ("Бронирование сотрудников") | 2.6% |
| `bd_training` | обучени, навчанн ("Бесплатное обучение", "Компенсация обучения") | 18.2% |
| `bd_housing` | проживани, житл, жиль, общежит, гуртож | 1.9% |
| `bd_veteran` | ветеран ("Отдаем предпочтение ветеранам") | 0.7% |

### 7.3 Text flags (`tx_*`)

All are 0/1 except `tx_exp_years` and `tx_lang`. Stems are shown (`…` = any ending); UA and RU
forms are both in the code.

| Variable | Keywords (abridged; full regex in the script) | Share / mean |
|---|---|---|
| `tx_exp_none` | без досвіду / без опыта, досвід не обов'язковий / не потрібен, можна без досвіду, no experience; **not** if "без досвіду не розглядаємо" | 10.3% |
| `tx_exp_years` | **lowest** N of: "досвід … від/не менше/понад N рок…" (also від року = 1, пів року = 0.5), "N років досвіду", "experience of N years"; ranges → lower bound; months ÷ 12; kept if 0 < N ≤ 15 | mean 2.0 years |
| `tx_higher_ed` | вища/вищу/вищої (+ up to 2 words) освіта, высшее образование, бакалавр, магістр, higher education; **not** if "незакінчена/неповна вища" | 17.9% |
| `tx_english` | англійськ…, english, intermediate, IELTS, TOEFL (read with `tx_lang`: close to 1 in English-language ads) | 13.1% |
| `tx_training` | training **the employer gives**: навчимо, навчання за рахунок компанії / на робочому місці, безкоштовне/оплачуване навчання, корпоративне навчання, стажування, наставник, ментор, навчання з нуля, програма адаптації | 14.5% |
| `tx_female_seek` / `tx_male_seek` | hiring verb (шукаємо, потрібна, запрошуємо, ищем, требуется…) + up to 4 words + жінок/дівчат… or чоловіків/хлопців…; "стать: жіноча/чоловіча"; "тільки для …". "Жінок та чоловіків" sets both | 0.3% / 0.3% |
| `tx_fem_title` | feminine form in the **title**: suffix after "/" or "(" (Касир(ка)); slash pair (Водій/Водійка); a list of feminine job nouns | 1.5% |
| `tx_veteran` | ветеран…, УБД, учасник бойових дій | 1.5% |
| `tx_disab` | інвалідніст…, з інвалідністю, обмеженими можливостями | 1.2% |
| `tx_idp` | ВПО (whole word), переселен…, внутрішньо переміщ… | 0.9% |
| `tx_student` / `tx_pension` | студент / пенсіонер…, пенсійного віку | 2.9% / 0.2% |
| `tx_age_cap` | "віком (від NN) до NN", "до NN років", "не старше NN" with NN = 16–70; **not** after діт…/дитин…/учн… (children's ages) | 1.9% |
| `tx_defer` | бронювання / бронь / бронир… / відстрочк… after blanking out armored (броньований, бронированный, бронежилет) and payment deferral (відстрочка платежу/оплати/поставки); booking ads (квитків, готелів, столиків, менеджер з бронювання, travel) dropped unless they mention mobilization (мобіліз…, військовозобов'язан…, ТЦК, критично важливе підприємство) | 3.2% |
| `tx_critical` | критично важливе підприємство, критичн… для економіки/оборони, критична інфраструктура | 0.2% |
| `tx_milreg` | військовий квиток, військовий облік, військовозобов'язан…, военный билет/учет, Резерв+ | 1.3% |
| `tx_shelter_air` | укриття / укрытие, бомбосховище, бомбоубежище, протирадіаційне; **not** "будівництво укриттів" | 0.9% |
| `tx_power` | генератор (not "генератор ідей/лідів"), Starlink, блекаут, без світла, відключення світла, автономне/резервне/безперебійне живлення, ДБЖ, EcoFlow; **not** if the title is about generators, Starlink, inverters, solar panels, batteries | 1.7% |
| `tx_shelter` | `tx_shelter_air` or `tx_power` (the former single flag) | 2.2% |
| `tx_remote` | віддалена/дистанційна/удаленная робота / формат / режим, працювати віддалено, з дому, remote, work from home | 7.0% |
| `tx_reloc` | релокац…, переїхали з, перевезли виробництво, переміщене / евакуйоване підприємство | 0.3% |
| `tx_housing` | житло (not житловий), жилье, проживання, гуртожиток, оренда житла, компенсація оренди; **not** "місце проживання", "проживаючі в …" | 6.1% |

### 7.4 Occupation: ISCO-08 from the title

The same procedure as the KSE work.ua pipeline (Stata, not included here), ported to Python:
1. Standardize the title (first 100 characters, lower case, one apostrophe and hyphen form,
   "." between letters → "-", spaces collapsed).
2. Find the matching rules with the **lowest priority number**: 0 generic titles
   (адміністратор, менеджер, оператор… → ambiguous); 1 helpers and heads of a named
   function; 2 specific compounds; 3 engineers and technologists; 4 core occupation nouns.
3. One group at that priority → `occ_status` 1, with `occ_code`, `isco1`, `isco2`. Several
   groups → keep the ISCO level they share: 2-digit (status 2), 1-digit (3), none (4,
   ambiguous). 5 generic title; 6 no rule.

Rules: `data/crosswalks/occupation_rules.csv` (146 rules, built and reviewed for work.ua
titles) plus `occupation_rules_robota.csv` (31 rules added on 14 Nov 2026 for the most
frequent unclassified robota titles: mining, call-center spellings, rail, conductors,
public service, quality control, meter readers, stokers, …). Groups:
`occupation_groups.csv` (86 KSE groups plus 7 new: MINING, PUBLIC_ADMIN, LIBRARIAN,
RAIL_OP, TRANSPORT_ATT, QC_INSPECT, METER_READ), each with its ISCO-08 1/2/3-digit codes.

| Variable | Meaning |
|---|---|
| `occ_code` | harmonized group (93 groups), only when `occ_status == 1` |
| `occ_status` | 1 classified … 6 no rule (above) |
| `isco1` | ISCO-08 major group 0–9, missing if not classified (status 4–6) |
| `isco2` | ISCO-08 sub-major group (e.g. 83 drivers and mobile plant operators), missing if not known (status 3–6, or a group with no 2-digit code) |

Coverage on export `20261114_112558`: `occ_status` 1 for 83.6% of vacancies, 2–3 for 1.7%, ambiguous or generic 3.5%, no rule 11.2%; an ISCO major group is known for 84.0% (old 10 groups: 78%), stable across years (82.5–83.9%, Russian and Ukrainian titles alike). Major groups: 0 armed forces 0.8%, 1 managers 5.2, 2 professionals 21.3, 3 technicians 14.1, 4 clerks 5.9, 5 service and sales 15.9, 6 agriculture 0.2, 7 crafts 8.0, 8 operators 6.0, 9 elementary 6.6, not classified 16.0.
In 05, `male_typed` = ISCO sub-majors 54 protective services, 71 building trades, 72
metal/machinery trades, 74 electrical trades, 83 drivers and mobile plant operators, 93
laborers in mining/construction/manufacturing/transport. That definition is an
assumption.

**Military** (`mil_role`, title; first wins): 1 drones/unmanned (БПЛА, дрон, FPV, НРК) · 2
medics · 3 combat (стрілець, штурмовик, снайпер, кулеметник, артилерист, танкіст, командир…)
· 4 drivers · 5 communications/EW/IT · 6 engineering and trades (сапер, механік, електрик…)
· 7 support (кухар, діловод, бухгалтер, психолог, рекрутер, логіст…) · 0 generic. `mil_unit`
(employer name; first wins): 1 TCC · 2 drone forces · 3 National Guard · 4
assault/airborne/marines · 5 mechanized/tank/artillery · 6 territorial defense · 7 border
guard/police · 8 navy/air force/special forces/intelligence · 9 other recruiting centers ·
0 other. `mil_1824` = 18–24 contract mentioned; `mil_choose` = "choose your unit" / transfer
wording.
