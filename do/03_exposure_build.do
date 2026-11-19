* =============================================================================
* 03_exposure_build.do  --  war exposure from air raid alarms
*
* Two measures, built from the same alarm data:
*   PART A  the paper's measure (ABZ EP 2026, replication package
*           code/prep/prep_alarms.do): alarm counts, summed alarm hours and days with
*           an alarm, by oblast and month and over the whole war, with terciles
*           Low/Medium/High. Also by raion and month with the same method (not in the
*           paper). Kept as the reference.
*   PART B  my measure: hours a raion (district) is under alarm, i.e. any alarm
*           announced for its whole oblast or for the raion itself, with overlapping
*           alarms counted once; in Kyiv time, split into working and night hours.
*   PART C  VIINA measures (added 14 Nov 2026; plan: docs/exposure_viina_spec.md), by
*           robota.ua city and month: distance to the nearest Russian-held place, and
*           days with an attack (shelling, airstrike, drone) reported nearby; attack
*           days also by raion and oblast. Robustness variants, raion/oblast versions of
*           the distance and the fixed (window-average) exposure are written but
*           commented out at the end of this file.
*
* Why I need Part B (the robota sample runs to Nov 2026):
*   - From Sep-Dec 2025 alarms are announced raion by raion instead of oblast-wide.
*     The paper's method counts every row as an alarm and adds up overlapping
*     durations, so after the switch counts and hours rise mechanically (Lviv oblast,
*     2026: 403 summed hours, 68 hours actually under alarm).
*   - It gives one number per oblast. A raion measure also separates a front-line
*     raion from the oblast center (e.g. Nikopol vs Dnipro).
*
* Input : <sirens repo>/datasets/official_data_en.csv   official alarms, from 15 Mar 2022
*         <sirens repo>/datasets/volunteer_data_en.csv  volunteer alarms, from 25 Feb 2022
*         (github Vadimkin/ukrainian-air-raid-sirens-dataset, pulled 5 Nov 2026)
*         data/raw/ukrstat/kn_0122_ue.xls  UkrStat population by oblast, Feb 2022 (copied
*                                          from the replication package, data/raw/public/)
*         place names and codes: built by 03_geo_mappings.do, which this file runs first
*         Part C: VIINA/Data/event_1pd_latest_YYYY.zip and control_latest_2022.zip (VIINA
*         clone), data/temp/viina_*.csv of 00_viina_control.py, robota_city_raion.csv of
*         00_city_raion.py; all read by do/00_viina_exposure.py, which step V1 runs
*         with the settings of step 0
* Output: data/temp/population_2022.dta         population by oblast (Jan 2022 average)
*         data/analysis/alarms_events.dta       official alarms, one row per alarm
*         Part A:
*         data/analysis/abz_oblast_month.dta    oblast x month (months with alarms only)
*         data/analysis/abz_raion_month.dta     raion x month (months with alarms only)
*         data/analysis/abz_oblast_exposure.dta oblast, whole period: totals and terciles
*         Part B:
*         data/analysis/alarms_raion_day.dta    raion x day (days with an alarm only)
*         data/analysis/alarms_raion_month.dta  raion x month, balanced (zeros kept)
*         Part C (balanced, Jan 2021 - Oct 2026; occupied units missing, with a flag):
*         data/analysis/viina_city_month.dta    city x month: distance to the front,
*                                               proximity, bands, front moves, attack days
*         data/analysis/viina_raion_month.dta   raion x month: attack days in the raion
*         data/analysis/viina_oblast_month.dta  oblast x month: attack days in the oblast
*         data/temp/viina_city_month.csv, viina_events_clean.csv, viina_events_precision.csv,
*         viina_line2014_check.csv              (written by 00_viina_exposure.py)
*         data/temp/logs/00_viina_exposure.log, data/temp/logs/03_exposure_build.log
*
* Codes (from 03_geo_mappings.do): oblast = the paper's code (Kyiv city in Kyiv oblast,
* 39); oblast_pcode and raion_pcode = codes of the map (OCHA COD-AB); Kyiv city is its
* own raion, UA8000.
*
* THE TWO ALARM SOURCES (see the python files in the sirens repo's processors folder)
*   OFFICIAL  read from the Telegram channel of the state alert system (@air_alert_ua).
*             Each message names the oblast/raion/hromada (as hashtags) and says whether
*             the alarm starts or ends. Starts on 15 Mar 2022. If an alarm gets no "end"
*             message and a new one starts more than 3 hours later, the old one is closed
*             after 1 hour, WITHOUT a flag (255 alarms last exactly 1 hour, of ~185,000).
*             !! The repo stopped adding official alarms on 7 Sep 2026 (checked 5 Nov 2026;
*             the volunteer file is still updated). So Part B ends in Aug 2026.
*             !! The repo repeats a block of ~114,000 rows: exact duplicates are dropped.
*   VOLUNTEER read from the eTryvoga Telegram channel (@UkraineAlarmSignal), whose
*             messages are free text: the oblast is guessed from keywords (city names,
*             "Київська" ...) and start/end from words ("тривога", "відбій"). Oblast level
*             only. If no "end" message comes, the alarm is closed after 30 minutes and
*             flagged naive = True (5% of rows).
*   Agreement, oblast level, minute by minute (checked 5 Nov 2026; Jaccard index =
*   minutes both sources mark as alarm / minutes either marks):
*             15 Mar-30 Apr 2022: 0.86 (each covers ~92% of the other's minutes);
*             2022 0.91, 2023 0.89; later lower as official alarms move to raions.
*   Use: Part A uses official alarms only, as the paper. Part B uses volunteer alarms
*   only to fill the gap before the official data start (25 Feb - 15 Mar 2022).
*   Caveats: 24 Feb and most of 25 Feb are in neither source; in those weeks the
*   volunteer channel is thin where the war was worst (Kharkiv: 32 hours, 67% "naive";
*   Donetsk 70% naive; Kherson almost nothing). There, alarms understate exposure: the
*   occupation/hostilities status (to be added) has to do the work.
*
* PART A: differences from the paper's code (results are otherwise the same)
*   (a) Exact duplicate rows are dropped (step 3b). The paper's download had none.
*   (b) Alarms are cut at $abz_last_day (step 0): the paper's download ends on
*       28 Oct 2025. With the cut, the result was checked against the paper's code
*       run on the paper's download (5 Nov 2026): same terciles, same days with alarms
*       in every oblast-month, same hours and counts except Zhytomyr (+14 alarms, +31
*       hours) and Poltava (+1 alarm), added to the repo after the paper's download.
*   (c) Outputs also carry oblast_ua, the oblast name used by robota.ua (01_clean.do).
*   (d) Place names and codes come from one table (03_geo_mappings.do) instead of two
*       long lists of -replace- lines.
*   (e) The paper calls the oblast code "region"; here it is "oblast" everywhere.
*
* PART B: choices (each can be changed in step 0 or the step named)
*   - Kyiv local time (UTC+2, summer UTC+3), so days and working hours are local.
*   - Working hours: Monday-Friday, 9:00-18:00 local. Public holidays are not removed
*     (they were suspended under martial law from 2022). Night: 22:00-6:00 local.
*   - Hromada-level alarms (one municipality, from 2022 on the front line) cover only
*     part of a raion: they are NOT in the main measure, but in hours_any (step B2).
*   - Kyiv city is its own unit (UA8000), with its own alarms ("Kyiv City").
*   - Crimea, Sevastopol and Luhansk oblast: no alarm data (Luhansk and Crimea have a
*     "permanent" alarm since 2022 that the source does not list). Measures are missing
*     there.
*   - Occupied raions: measures are also missing in a raion-month where more than half
*     the raion's people live in places held by Russia (occupied_raion, from VIINA; see
*     03_geo_mappings.do, step 5). Below that the alarms describe the part Ukraine holds,
*     where the vacancies are; occ_share (0-1) stays in the file as a variable of its own.
*     The daily file (alarms_raion_day) is not cut: apply the flag when using it.
*
* Needs: ssc install encoder; Python 3 with pandas, numpy, scipy (launched as "py")
* Run after do/00_city_raion.py and do/00_viina_control.py (for 03_geo_mappings.do).
* =============================================================================

clear all
set more off

* --- Step 0. Paths and settings ---------------------------------------------
if "$project" == "" global project "`c(pwd)'/.."   // set by 00_main.do; else run from the repo root
global do      "$project/Project/do"
global sirens  "$project/ukrainian-air-raid-sirens-dataset/datasets"
global raw     "$project/Project/data/raw/ukrstat"
global xwalk   "$project/Project/data/crosswalks"
global out     "$project/Project/data/analysis"
global temp    "$project/Project/data/temp"

* Part A: alarms that ENDED by this day (UTC). 28oct2025 = the paper's download,
* whose last alarm ended on 28 Oct 2025 at 23:47 UTC. See step A0.
global abz_last_day "28oct2025"

* Part B
global last_day    "31aug2026"   // last day kept (local time): official data stop on 7 Sep 2026
global work_from   9             // working hours, local time, Monday-Friday
global work_to     18
global night_from  22            // night hours, local time
global night_to    6

* Part C (VIINA measures). All settings of Part C are here; the Python helper
* (do/00_viina_exposure.py) receives them from this block, so change them only here.
if "$viina" == "" global viina "$project/VIINA/Data"   // VIINA clone (set in 00_main.do)
global viina_first_month   "2021-01"  // first month of the VIINA panels (Jan 2021 = baseline)
global front_days_share    0.5        // a place is Russian-held in a month if held on at
                                      //   least this share of the month's days
global attack_radius_km    15         // radius for "attack days near the city"
global front_move_km       50         // a "front move": distance changes by at least this...
global front_move_within_km 200       //   ...while the city is within this distance
global viina_variants      0          // 1 = also build the robustness variants (see the
                                      //   commented-out section at the end of this file)

* --- Step 1. Place names and codes --------------------------------------------
* 03_geo_mappings.do builds the oblast and raion tables (data/crosswalks/geo_*.dta).
* It runs first because it starts with -clear all- and keeps its own log.
do "$do/03_geo_mappings.do"

set linesize 200      // wide log, so lists fit on one line
cap mkdir "$out"
cap mkdir "$temp"
cap log close
cap mkdir "$project/Project/data/temp/logs"
log using "$project/Project/data/temp/logs/03_exposure_build.log", replace text

* 1a. Oblast name in the alarm data -> codes (Crimea and Sevastopol have no name there)
use "$xwalk/geo_oblasts.dta" if name_alarm != "", clear
keep name_alarm oblast oblast_pcode _ID
tempfile names_alarm
save `names_alarm'

* 1b. Oblast name in the population file -> code
use "$xwalk/geo_oblasts.dta" if name_pop != "", clear
keep name_pop oblast
tempfile names_pop
save `names_pop'

* 1c. One row per oblast (Kyiv city and Kyiv oblast are one: 39), for _ID and oblast_ua
use "$xwalk/geo_oblasts.dta", clear
keep oblast _ID oblast_ua
duplicates drop
isid oblast
tempfile oblast_info
save `oblast_info'

* --- Programs -------------------------------------------------------------------
* paper_monthly (Part A): the paper's monthly aggregation, for any place unit (oblast
* or raion). Input: one row per alarm and place, with start and end (UTC). An alarm can
* run past midnight: to count the days with an alarm correctly, each alarm is copied
* once for every day it touches. Then, by place and month:
*   n_alarms      each alarm is counted once, in the month of the day it starts;
*   total_dur_hr  its whole duration also goes to the month it starts;
*   days_touched  each place-day with at least one alarm is counted once.
* Points to keep in mind (all as in the paper):
*   - days are UTC days (Kyiv time is UTC+2/+3);
*   - alarms that overlap (e.g. an oblast alarm and a raion alarm at the same time)
*     add up, so total_dur_hr can exceed the hours in a month;
*   - a month without any alarm in a place has no row (it is not a zero row).
capture program drop paper_monthly
program define paper_monthly
    args place
    gen long copy_id = _n
    gen start_day = dofc(started_at)
    gen end_day   = dofc(finished_at)
    expand end_day - start_day + 1
    bysort copy_id: gen day = start_day + _n - 1
    gen month = mofd(day)

    bysort copy_id (day):  gen byte first_day_of_alarm = _n == 1
    bysort `place' day:    gen byte first_alarm_of_day = _n == 1
    gen double dur_first = dur_sec if first_day_of_alarm

    collapse (sum) n_alarms = first_day_of_alarm  total_dur_sec = dur_first ///
                   days_touched = first_alarm_of_day, by(`place' month)
    gen double total_dur_hr = total_dur_sec / 3600
    drop total_dur_sec
    * days in the calendar month (full month also in Mar 2022, when the data start on the 15th)
    gen days_in_ym = dofm(month + 1) - dofm(month)
    gen double share_days_touched = days_touched / days_in_ym
    format month %tmMon_CCYY

    label var month              "Month"
    label var days_in_ym         "Days in month"
    label var n_alarms           "Number of alarms (month of start)"
    label var total_dur_hr       "Total alarm duration, hours (month of start)"
    label var days_touched       "Days with >= 1 alarm"
    label var share_days_touched "Share of days with >= 1 alarm"
end

* kyiv_time (Part B): Kyiv local time from a UTC time. Summer time (UTC+3) runs from the
* last Sunday of March to the last Sunday of October, at 01:00 UTC both times (EU rule,
* which Ukraine follows; a 2024 law to drop summer time was never signed).
capture program drop kyiv_time
program define kyiv_time
    args utc local
    tempvar y sum_from sum_to
    gen int `y' = year(dofc(`utc'))
    gen double `sum_from' = cofd(mdy(3, 31, `y')  - dow(mdy(3, 31, `y')))  + msofhours(1)
    gen double `sum_to'   = cofd(mdy(10, 31, `y') - dow(mdy(10, 31, `y'))) + msofhours(1)
    gen double `local' = `utc' + msofhours(2 + (`utc' >= `sum_from' & `utc' < `sum_to'))
    format `local' %tcDDmonCCYY_HH:MM
end

* raion_days (Part B): from alarms (raion_pcode start end, UTC) to one row per raion
* and local day:
*   1. union: alarms of the same raion that overlap become one spell (counted once);
*   2. each spell is cut at local midnight;
*   3. per day: hours under alarm, of which working and night hours, and spells started.
capture program drop raion_days
program define raion_days
    * 1. union of overlapping alarms
    sort raion_pcode start end
    by raion_pcode: gen double reach = end if _n == 1
    by raion_pcode: replace reach = max(end, reach[_n-1]) if _n > 1   // latest end so far
    by raion_pcode: gen long spell = sum(_n == 1 | start > reach[_n-1])
    collapse (min) start (max) end, by(raion_pcode spell)

    * 2. cut at local midnight
    kyiv_time start ls
    kyiv_time end   le
    replace le = ls if le < ls                     // end-of-summer-time hour, rare
    gen first_day = dofc(ls)
    expand dofc(le) - first_day + 1
    bysort raion_pcode spell: gen day = first_day + _n - 1
    format day %td
    gen double a = max(ls, cofd(day))              // piece of the spell on this day
    gen double b = min(le, cofd(day + 1))

    * 3. hours, working hours, night hours, spells started
    gen double hours = (b - a) / msofhours(1)
    gen double work_hours = max(0, min(b, cofd(day) + msofhours($work_to)) ///
        - max(a, cofd(day) + msofhours($work_from))) / msofhours(1) if inrange(dow(day), 1, 5)
    replace work_hours = 0 if work_hours == .
    gen double night_hours = (max(0, min(b, cofd(day) + msofhours($night_to)) - a) ///
        + max(0, b - max(a, cofd(day) + msofhours($night_from)))) / msofhours(1)
    gen byte spell_start = day == first_day
    collapse (sum) hours work_hours night_hours n_spells = spell_start, by(raion_pcode day)
end

* --- Step 2. Population (UkrStat, January 2022) ------------------------------
* The file has four columns of numbers: present and resident population, each on
* 1 Feb 2022 and as the January 2022 average. The paper uses the January average of
* the RESIDENT population (column E), i.e. before the invasion and its displacement.
import excel "$raw/kn_0122_ue.xls", cellrange(B4:F30) firstrow clear
keep E F
rename (E F) (population name_pop)
drop if name_pop == "Ukraine"

merge 1:1 name_pop using `names_pop', assert(match) nogenerate

* Kyiv city and Kyiv oblast are added up
collapse (sum) population, by(oblast)
label values oblast oblast_lab
label var population "Resident population, Jan 2022 average (UkrStat)"
save "$temp/population_2022.dta", replace

* --- Step 3. Official alarms: one row per alarm --------------------------------
* 3a. Import. Times are in UTC ("2022-03-15 16:10:34+00:00").
import delimited using "$sirens/official_data_en.csv", varnames(1) delimiters(",") ///
    encoding("utf-8") stringcols(_all) clear
count

* 3b. Exact duplicate rows: the same alarm written twice
duplicates report
duplicates drop

* 3c. Keep the place, the level, start and end
drop source
drop if oblast == "Lubenskyi raion"   // data error in the paper's download (1 row); gone since
gen double started  = clock(substr(started_at,  1, 19), "YMDhms")
gen double finished = clock(substr(finished_at, 1, 19), "YMDhms")
format started finished %tcDDmonCCYY_HH:MM:SS
assert started < . & finished < . & finished >= started
drop started_at finished_at
rename (started finished) (started_at finished_at)

* 3d. Oblast codes. Kyiv City -> oblast 39 (Kyiv oblast), but it keeps its own
*     oblast_pcode (UA80).
rename oblast name_alarm
merge m:1 name_alarm using `names_alarm', keep(master match)
assert _merge == 3                 // fails if the data bring a new oblast name
drop _merge name_alarm

* 3e. Raion code of raion- and hromada-level alarms (old raion names included)
rename raion raion_alarm
merge m:1 oblast_pcode raion_alarm using "$xwalk/geo_raion_names.dta", ///
    keepusing(raion_pcode) keep(master match)
assert _merge == 3 if raion_alarm != ""   // fails if the data bring a new raion name
assert raion_alarm == "" if _merge == 1
drop _merge
rename raion_alarm raion

* 3f. Level of the alarm (oblast / raion / hromada) and duration
encoder level, replace
gen long dur_sec = (finished_at - started_at) / 1000

label var oblast       "Oblast (code of the paper; Kyiv city in Kyiv oblast)"
label var oblast_pcode "Oblast code of the map (Kyiv city UA80)"
label var _ID          "Map polygon ID (paper)"
label var raion        "Raion (district), if the alarm is for a raion or hromada"
label var raion_pcode  "Raion code of the map, if the alarm is for a raion or hromada"
label var hromada      "Hromada (municipality), if the alarm is for a hromada"
label var level        "Level of the alarm"
label var started_at   "Alarm start (UTC)"
label var finished_at  "Alarm end (UTC)"
label var dur_sec      "Duration (seconds)"

order _ID oblast oblast_pcode raion raion_pcode hromada level started_at finished_at dur_sec
sort oblast started_at
compress
save "$out/alarms_events.dta", replace


* =============================================================================
* PART A. THE PAPER'S MEASURE
* =============================================================================

* --- Step A0. Same period as the paper ------------------------------------------
* The source writes an alarm only once it is over, so a download holds the alarms
* that had ENDED by that day: the cut is on the end date. (Cutting on the start date
* would add, for Kharkiv, one hromada alarm from 12 May 2024 to 6 Jan 2026: 14,497
* hours that the paper does not have.)
use "$out/alarms_events.dta", clear
keep if dofc(finished_at) <= td($abz_last_day)
tempfile abz_events
save `abz_events'

* --- Step A1. Oblast x month ------------------------------------------------------
paper_monthly oblast

* per 100,000 residents
merge m:1 oblast using "$temp/population_2022.dta", assert(match) nogenerate
gen double n_alarms_per_res = n_alarms / (population / 100000)

* map ID and robota.ua oblast name, labels, save
merge m:1 oblast using `oblast_info', keep(master match) nogenerate

label var oblast           "Oblast (code of the paper; Kyiv city in Kyiv oblast)"
label var oblast_ua        "Oblast name as in robota.ua (merge key with 01_clean.do)"
label var n_alarms_per_res "Alarms per 100k residents"
label var population       "Resident population, Jan 2022 average"

order _ID oblast oblast_ua month days_in_ym n_alarms n_alarms_per_res population ///
      total_dur_hr days_touched share_days_touched
sort oblast month
isid oblast month
compress
save "$out/abz_oblast_month.dta", replace

* --- Step A2. Raion x month, with the paper's method (not in the paper) -------------
* Each alarm is given to every raion it covers, then counted as in step A1:
*   oblast-level alarm   -> every raion of the oblast (Kyiv City -> the city, UA8000;
*                           Kyiv oblast alarms do not cover the city here)
*   raion-level alarm    -> that raion
*   hromada-level alarm  -> the raion the hromada is in (the paper counts every level)
* So an oblast alarm counts once in each raion, and overlaps still add up. There is no
* population by raion, hence no per-resident measure.
use `abz_events', clear
decode level, generate(level_name)
preserve
    keep if level_name == "oblast"
    drop raion_pcode
    joinby oblast_pcode using "$xwalk/geo_raions.dta", unmatched(master)
    assert _merge == 3
    tempfile abz_by_oblast
    save `abz_by_oblast'
restore
keep if inlist(level_name, "raion", "hromada")
append using `abz_by_oblast'
keep raion_pcode started_at finished_at dur_sec

paper_monthly raion_pcode

merge m:1 raion_pcode using "$xwalk/geo_raions.dta", ///
    keepusing(oblast oblast_pcode raion_en raion_ua) keep(master match)
assert _merge == 3
drop _merge
merge m:1 oblast using `oblast_info', keepusing(oblast_ua) keep(master match) nogenerate

label var raion_pcode "Raion code of the map (OCHA COD-AB); Kyiv city UA8000"
label var oblast      "Oblast (code of the paper; Kyiv city in Kyiv oblast)"
label var oblast_ua   "Oblast name as in robota.ua (merge key with 01_clean.do)"
order raion_pcode raion_en raion_ua oblast oblast_pcode oblast_ua month days_in_ym ///
      n_alarms total_dur_hr days_touched share_days_touched
sort raion_pcode month
isid raion_pcode month
compress
save "$out/abz_raion_month.dta", replace

* --- Step A3. Oblast: whole period and terciles --------------------------------
* Sums over the months. NB: days_in_ym is summed over the months WITH alarms only,
* so share_days_touched_overall is the share of days with an alarm in those months
* (as in the paper; it matters only for oblasts with months without any alarm).
use "$out/abz_oblast_month.dta", clear
collapse (sum) n_alarms n_alarms_per_res total_dur_hr days_touched days_in_ym, ///
    by(oblast _ID population)
gen double share_days_touched_overall = days_touched / days_in_ym
gen double n_alarms_per_10 = n_alarms_per_res / 10

* Crimea and Sevastopol: occupied since 2014, no alarm data, measures missing
set obs `=_N + 2'
replace oblast = 19 in -2
replace oblast = 27 in -1
replace _ID = oblast in -2/-1

* occupied oblasts form their own group
gen byte occupied = inlist(oblast, 35, 42, 53, 37, 19, 27)

* terciles among the 20 oblasts not occupied (1 = lowest exposure)
label define terc_lab 1 "Low" 2 "Medium" 3 "High"
foreach v in total_dur_hr days_touched n_alarms_per_res {
    xtile `v'_terc = `v' if occupied == 0, nq(3)
    label values `v'_terc terc_lab
}

merge 1:1 oblast using `oblast_info', keepusing(oblast_ua) assert(match) nogenerate

label var n_alarms                   "Number of alarms, whole period"
label var n_alarms_per_res           "Alarms per 100k residents, whole period"
label var n_alarms_per_10            "Alarms per 10k residents, whole period"
label var total_dur_hr               "Total alarm duration, hours, whole period"
label var days_touched               "Days with >= 1 alarm, whole period"
label var days_in_ym                 "Days in the months with >= 1 alarm"
label var share_days_touched_overall "Share of days with alarms (months with alarms)"
label var occupied                   "Occupied in part (Kherson, Zaporizhzhia, Donetsk, Luhansk, Crimea, Sevastopol)"
label var total_dur_hr_terc          "Tercile of alarm hours (non-occupied oblasts)"
label var days_touched_terc          "Tercile of days with alarms (non-occupied oblasts)"
label var n_alarms_per_res_terc      "Tercile of alarms per resident (non-occupied oblasts)"

order _ID oblast oblast_ua population n_alarms n_alarms_per_res n_alarms_per_10 ///
      total_dur_hr days_touched days_in_ym share_days_touched_overall occupied
sort oblast
isid oblast
compress
save "$out/abz_oblast_exposure.dta", replace


* =============================================================================
* PART B. MY MEASURE: HOURS UNDER ALARM BY RAION
* =============================================================================

* --- Step B1. Alarms and the raions they cover --------------------------------------
* B1a. Volunteer alarms, only before the official data start (first: 15 Mar 2022 16:10 UTC)
import delimited using "$sirens/volunteer_data_en.csv", varnames(1) delimiters(",") ///
    encoding("utf-8") stringcols(_all) clear
rename (started_at finished_at) (started_str finished_str)
gen double started_at  = clock(substr(started_str, 1, 19), "YMDhms")
gen double finished_at = clock(substr(finished_str, 1, 19), "YMDhms")
keep if started_at < tc(15mar2022 16:10:34)
rename region name_alarm
merge m:1 name_alarm using `names_alarm', keepusing(oblast_pcode) keep(master match)
assert _merge == 3
gen level_name = "oblast"
gen byte source = 2
keep oblast_pcode level_name started_at finished_at source
count
tempfile volunteer
save `volunteer'

* B1b. Official alarms (all of them), plus the volunteer ones
use "$out/alarms_events.dta", clear
decode level, generate(level_name)
gen byte source = 1
keep oblast_pcode raion_pcode level_name started_at finished_at source
append using `volunteer'
label define source_lbl 1 "official" 2 "volunteer"
label values source source_lbl
rename (started_at finished_at) (start end)

* B1c. Cut at the last day (by end time, local)
kyiv_time end end_local
keep if dofc(end_local) <= td($last_day)
drop end_local
tab level_name source

* B1d. Oblast-wide alarms: one copy for every raion of the oblast (Kyiv City -> UA8000)
preserve
    keep if level_name == "oblast"
    drop raion_pcode
    joinby oblast_pcode using "$xwalk/geo_raions.dta", unmatched(master)
    assert _merge == 3
    keep raion_pcode start end source level_name
    tempfile by_oblast
    save `by_oblast'
restore
keep if inlist(level_name, "raion", "hromada")
keep raion_pcode start end source level_name
append using `by_oblast'

gen byte whole_raion = inlist(level_name, "oblast", "raion")
label var whole_raion "Alarm covers the whole raion (oblast or raion level)"
tab level_name whole_raion

* --- Step B2. Raion x day -------------------------------------------------------------
* Two versions:
*   hours      whole-raion alarms only (oblast or raion level): the main measure
*   hours_any  adds hromada-level alarms: some part of the raion under alarm (upper bound)

* B2a. Main, and the hours that come from volunteer data
preserve
    keep if whole_raion & source == 2
    raion_days
    keep raion_pcode day hours
    rename hours hours_vol
    tempfile vol
    save `vol'
restore
preserve
    keep if whole_raion
    raion_days
    merge 1:1 raion_pcode day using `vol', nogenerate
    replace hours_vol = 0 if hours_vol == .
    tempfile main
    save `main'
restore

* B2b. Any alarm in the raion, hromada-level included
raion_days
keep raion_pcode day hours
rename hours hours_any
merge 1:1 raion_pcode day using `main', nogenerate
foreach v in hours work_hours night_hours n_spells hours_vol {
    replace `v' = 0 if `v' == .      // days with only a hromada alarm
}

label var raion_pcode "Raion code of the map (OCHA COD-AB); Kyiv city UA8000"
label var day         "Day (Kyiv time)"
label var hours       "Hours under alarm (whole-raion alarms)"
label var work_hours  "... of which working hours (Mon-Fri $work_from-$work_to)"
label var night_hours "... of which night hours ($night_from-$night_to)"
label var n_spells    "Alarm spells started (overlapping alarms = one spell)"
label var hours_vol   "... of hours, from volunteer data (before 15 Mar 2022)"
label var hours_any   "Hours with an alarm anywhere in the raion (incl. hromada level)"
order raion_pcode day hours work_hours night_hours n_spells hours_vol hours_any
sort raion_pcode day
compress
save "$out/alarms_raion_day.dta", replace

* --- Step B3. Raion x month, balanced ------------------------------------------------
gen month = mofd(day)
gen byte alarm_day = hours > 0
gen byte any_day   = hours_any > 0
collapse (sum) hours work_hours night_hours n_spells hours_vol hours_any ///
    days_alarm = alarm_day days_any = any_day, by(raion_pcode month)
tempfile monthly
save `monthly'

* every raion x every month, Feb 2022 to $last_day; months without alarms get zeros
use "$xwalk/geo_raions.dta", clear
keep raion_pcode oblast oblast_pcode raion_en raion_ua no_alarm_data
merge m:1 oblast using `oblast_info', keepusing(oblast_ua) keep(master match) nogenerate
local m0 = tm(2022m2)
local m1 = mofd(td($last_day))
expand `m1' - `m0' + 1
bysort raion_pcode: gen month = `m0' + _n - 1
merge 1:1 raion_pcode month using `monthly', assert(master match) nogenerate

* Occupation (03_geo_mappings.do, step 5, from VIINA). Alarms are announced only for
* territory Ukraine controls, so in a raion where most people live under Russian
* occupation they say nothing: set the measures to missing there, as for the raions
* without alarm data. occ_share and con_share are kept as variables of their own.
merge 1:1 raion_pcode month using "$xwalk/geo_raion_occupation.dta", ///
    keepusing(occ_share con_share occ_share_n occupied_raion) keep(master match)
assert _merge == 3 if raion_pcode != "UA3200"   // Chornobyl zone: no populated places
drop _merge
replace occupied_raion = 0 if occupied_raion == .

foreach v in hours work_hours night_hours n_spells hours_vol hours_any days_alarm days_any {
    replace `v' = 0 if `v' == .
    replace `v' = . if no_alarm_data | occupied_raion
}

* days with alarm data in the month: Feb 2022 only from 25 Feb (first volunteer record)
gen days_covered = dofm(month + 1) - dofm(month)
replace days_covered = 4 if month == tm(2022m2)
gen double share_hours = hours / (24 * days_covered)
gen double share_days  = days_alarm / days_covered

format month %tmMon_CCYY
label var month         "Month (Kyiv time)"
label var oblast_ua     "Oblast name as in robota.ua (merge key with 01_clean.do)"
label var hours         "Hours under alarm (whole-raion alarms)"
label var work_hours    "... of which working hours (Mon-Fri $work_from-$work_to)"
label var night_hours   "... of which night hours ($night_from-$night_to)"
label var n_spells      "Alarm spells started"
label var hours_vol     "... of hours, from volunteer data (before 15 Mar 2022)"
label var hours_any     "Hours with an alarm anywhere in the raion (incl. hromada level)"
label var days_alarm    "Days with an alarm (whole-raion alarms)"
label var days_any      "Days with an alarm anywhere in the raion"
label var days_covered  "Days of the month with alarm data"
label var share_hours   "Share of the month's hours under alarm"
label var share_days    "Share of the month's days with an alarm"
order raion_pcode raion_en raion_ua oblast oblast_pcode oblast_ua no_alarm_data month ///
      days_covered hours work_hours night_hours n_spells days_alarm share_hours share_days
sort raion_pcode month
isid raion_pcode month
compress
save "$out/alarms_raion_month.dta", replace


* =============================================================================
* PART C. VIINA MEASURES: DISTANCE TO THE FRONT AND ATTACKS NEARBY
* =============================================================================
* Plan and reasons: docs/exposure_viina_spec.md. Why: alarms cover whole raions or
* oblasts (little variation within an oblast and quarter) and measure only the threat
* of air attack. VIINA (Zhukov's Violent Incident Information from News Articles 2.0)
* gives control of ~33,000 places by day and geolocated reports of violent events, so
* exposure can be measured at the level of each robota.ua city.
*
* Two measures, kept separate (an average of the measures did worse than each alone in
* the power checks of 13 Nov 2026):
*   MEASURE 1  distance from the city to the nearest Russian-held populated place
*              (dist_front_km), and front_proximity = -ln(max(km, 1)): higher = more
*              exposed; the log because 20 -> 40 km plausibly matters as much as
*              200 -> 400 km; the cap at 1 km avoids the log of zero.
*   MEASURE 2  attack days near the city: days in the month with at least one reported
*              shelling, airstrike or drone strike within $attack_radius_km km.
* Which places are Russian-held, which events are kept, and how distances are computed
* (great-circle, haversine) is documented in do/00_viina_exposure.py. In short:
*   - Jan 2021 - Feb 2022: the reconstructed 2014 line (VIINA starts on 23 Feb 2022);
*   - Mar 2022: VIINA's vote alone (DeepStateMap starts in April): overstates Russian
*     control in the north; Feb-Mar 2022 are flagged (control_low_quality);
*   - Apr 2022 - Oct 2026: the both-sources rule, as for the occupation flags.
* Built here (active): city x month (both measures), and raion x month and oblast x
* month attack days (days with at least one attack inside the unit).
* Not active yet (commented-out section at the end of this file): robustness variants,
* raion and oblast versions of measure 1, and the fixed (window-average) exposure.
*
* Caveats for the thesis: VIINA's events come from news (big cities and high-profile
* strikes get more reports; counting days rather than reports limits this); the number
* of events falls over time (~51,000 attack reports in 2022, ~10,000 in 2026), partly
* coverage; front variation is concentrated in a few 2022 episodes.

* --- Step V1. Run the Python helper with the settings of step 0 ---------------------
* -shell- does not report Python errors back to Stata: the helper's main output is
* deleted first and checked afterwards (log: data/temp/logs/00_viina_exposure.log).
capture erase "$temp/viina_city_month.csv"
shell set PYTHONIOENCODING=utf-8&& py "$do/00_viina_exposure.py" --viina "$viina" ///
    --front_days_share $front_days_share --attack_radius_km $attack_radius_km ///
    --first_month $viina_first_month --variants $viina_variants ///
    > "$temp/logs/00_viina_exposure.log" 2>&1
capture confirm file "$temp/viina_city_month.csv"
if _rc {
    display as error "00_viina_exposure.py failed: see $temp/logs/00_viina_exposure.log"
    exit 601
}

* months of the VIINA panels, as Stata months
local v_first = monthly("$viina_first_month", "YM")
local v_last  = tm(2026m10)                        // last month of VIINA's control data

* --- Step V2. City x month: both measures ---------------------------------------------
* V2a. Import (one row per robota.ua city with a point, Jan 2021 - Oct 2026)
import delimited using "$temp/viina_city_month.csv", varnames(1) clear
rename month month_str
gen month = monthly(month_str, "YM")
format month %tmMon_CCYY
drop month_str
assert inrange(month, `v_first', `v_last')

* V2b. Raion, oblast and name of each city
merge m:1 city_id using "$xwalk/geo_city_raion.dta", keepusing(raion_pcode) ///
    keep(master match) nogenerate
merge m:1 raion_pcode using "$xwalk/geo_raions.dta", ///
    keepusing(raion_en oblast oblast_pcode) keep(master match) nogenerate
merge m:1 oblast using `oblast_info', keepusing(oblast_ua) keep(master match) nogenerate
preserve
    import delimited using "$xwalk/robota_city.csv", varnames(1) encoding("utf-8") ///
        bindquote(strict) clear
    keep id en
    rename (id en) (city_id city_name_en)
    tempfile city_names
    save `city_names'
restore
merge m:1 city_id using `city_names', keep(master match) nogenerate

* V2c. Measure 1: proximity, distance bands, front moves
gen double front_proximity = -ln(max(dist_front_km, 1))
egen byte front_band = cut(dist_front_km), at(0 25 50 100 200 100000) icodes
label define front_band_lbl 0 "under 25 km" 1 "25-50 km" 2 "50-100 km" 3 "100-200 km" ///
    4 "200 km or more"
label values front_band front_band_lbl

* a "front move": the distance changed by at least $front_move_km km from the previous
* month while the city was within $front_move_within_km km in one of the two months
* (the invasion, the withdrawal from the north in April 2022, Kharkiv in September,
* Kherson in November...). Lets the analysis treat these moves as events.
xtset city_id month
gen double dist_front_change_km = dist_front_km - L.dist_front_km
gen byte front_move = abs(dist_front_change_km) >= $front_move_km ///
    & min(dist_front_km, L.dist_front_km) <= $front_move_within_km ///
    if dist_front_change_km < .

* months whose control comes from VIINA's vote alone (see the header of Part C)
gen byte control_low_quality = inlist(month, tm(2022m2), tm(2022m3))

* V2d. Measure 2: attack days as a share of the month's days, and in logs
gen days_in_month = dofm(month + 1) - dofm(month)
gen double attack_days_share = attack_days_near / days_in_month
gen double ln_attack_days = ln(1 + attack_days_near)

* V2e. Occupation. From Feb 2022: occupied_city of 03_geo_mappings.do (the city's place
*     held by Russia more than half the month, as in the alarm files). Before: the city's
*     place is on the reconstructed 2014 line (city_place_held). Measures are set to
*     missing for occupied cities, and when the city's own place is in the front set.
merge 1:1 city_id month using "$xwalk/geo_city_occupation.dta", ///
    keepusing(occupied_city) keep(master match) nogenerate
replace occupied_city = city_place_held if month < tm(2022m2)
replace occupied_city = 0 if occupied_city == .
foreach v in dist_front_km front_proximity front_band dist_front_change_km front_move ///
        attack_days_near attack_days_share ln_attack_days {
    replace `v' = . if occupied_city | city_place_held
}

* V2f. Labels, order, save
label var city_id              "robota.ua city id"
label var city_name_en         "City (English name, robota.ua)"
label var month                "Month"
label var raion_pcode          "Raion of the city (map code)"
label var raion_en             "Raion (English, map)"
label var oblast               "Oblast (code of the paper; Kyiv city in Kyiv oblast)"
label var oblast_pcode         "Oblast code of the map (Kyiv city UA80)"
label var oblast_ua            "Oblast name as in robota.ua (merge key with 01_clean.do)"
label var dist_front_km        "Distance to the nearest Russian-held place, km (great-circle)"
label var front_proximity      "Proximity to the front: -ln(max(distance in km, 1))"
label var front_band           "Distance to the front, band"
label var dist_front_change_km "Change in distance to the front from the previous month, km"
label var front_move           "Front move: distance changed >= $front_move_km km, within $front_move_within_km km"
label var city_place_held      "The city's own place is in the month's Russian-held set"
label var control_low_quality  "Control from VIINA's vote alone (Feb-Mar 2022): weak"
label var attack_days_near     "Days with >= 1 attack (shelling/airstrike/drone) within $attack_radius_km km"
label var attack_days_share    "Share of the month's days with an attack within $attack_radius_km km"
label var ln_attack_days       "ln(1 + attack days within $attack_radius_km km)"
label var days_in_month        "Days in the month"
label var occupied_city        "City occupied in the month (2014 line before Feb 2022)"
order city_id city_name_en raion_pcode raion_en oblast oblast_pcode oblast_ua month ///
      occupied_city control_low_quality dist_front_km front_proximity front_band ///
      dist_front_change_km front_move attack_days_near attack_days_share ln_attack_days
sort city_id month
isid city_id month
compress
save "$out/viina_city_month.dta", replace

* --- Step V3. Raion x month: attack days inside the raion ------------------------------
* Days with at least one kept event located in the raion. The event's raion is the
* raion that contains its point (00_viina_exposure.py).
import delimited using "$temp/viina_events_clean.csv", varnames(1) stringcols(2 8) clear
drop month                                            // text "YYYY-MM"; rebuilt below
keep if raion_pcode != ""
gen day = daily(date, "YMD")
gen month = mofd(day)
duplicates drop raion_pcode day, force                // one row per raion and day
collapse (count) attack_days_raion = day, by(raion_pcode month)
tempfile raion_attacks
save `raion_attacks'

* every raion x every month, months without attacks are zeros
use "$xwalk/geo_raions.dta", clear
keep raion_pcode raion_en oblast oblast_pcode
merge m:1 oblast using `oblast_info', keepusing(oblast_ua) keep(master match) nogenerate
expand `v_last' - `v_first' + 1
bysort raion_pcode: gen month = `v_first' + _n - 1
format month %tmMon_CCYY
merge 1:1 raion_pcode month using `raion_attacks', assert(master match) nogenerate
replace attack_days_raion = 0 if attack_days_raion == .

* occupation: the flag of 03_geo_mappings.do from Feb 2022. Before (no VIINA data):
* raions of Crimea, Sevastopol, Donetsk and Luhansk oblast that are occupied in every
* month from Feb 2022 (the raion version of the reconstructed 2014 line).
merge 1:1 raion_pcode month using "$xwalk/geo_raion_occupation.dta", ///
    keepusing(occ_share occupied_raion) keep(master match) nogenerate
bysort raion_pcode: egen byte always_occupied = min(occupied_raion)
replace occupied_raion = always_occupied ///
    & inlist(oblast_pcode, "UA01", "UA85", "UA14", "UA44") if month < tm(2022m2)
replace occupied_raion = 0 if occupied_raion == .     // Chornobyl zone: no places
drop always_occupied
gen days_in_month = dofm(month + 1) - dofm(month)
gen double attack_days_raion_share = attack_days_raion / days_in_month
replace attack_days_raion       = . if occupied_raion
replace attack_days_raion_share = . if occupied_raion

label var raion_pcode             "Raion code of the map (OCHA COD-AB); Kyiv city UA8000"
label var raion_en                "Raion (English, map)"
label var oblast                  "Oblast (code of the paper; Kyiv city in Kyiv oblast)"
label var oblast_pcode            "Oblast code of the map (Kyiv city UA80)"
label var oblast_ua               "Oblast name as in robota.ua (merge key with 01_clean.do)"
label var month                   "Month"
label var attack_days_raion       "Days with >= 1 attack (shelling/airstrike/drone) in the raion"
label var attack_days_raion_share "Share of the month's days with an attack in the raion"
label var days_in_month           "Days in the month"
label var occupied_raion          "Raion occupied (> half its people under Russia; 2014 line before Feb 2022)"
label var occ_share               "Share of the raion's population in places held by Russia"
order raion_pcode raion_en oblast oblast_pcode oblast_ua month occupied_raion occ_share ///
      attack_days_raion attack_days_raion_share
sort raion_pcode month
isid raion_pcode month
compress
save "$out/viina_raion_month.dta", replace

* --- Step V4. Oblast x month: attack days inside the oblast -----------------------------
* Oblast = map code (Kyiv city UA80 and Sevastopol UA85 are units of their own).
import delimited using "$temp/viina_events_clean.csv", varnames(1) stringcols(2 8) clear
drop month                                            // text "YYYY-MM"; rebuilt below
keep if raion_pcode != ""
gen oblast_pcode = substr(raion_pcode, 1, 4)
gen day = daily(date, "YMD")
gen month = mofd(day)
duplicates drop oblast_pcode day, force
collapse (count) attack_days_oblast = day, by(oblast_pcode month)
tempfile oblast_attacks
save `oblast_attacks'

use "$xwalk/geo_oblasts.dta", clear
keep oblast oblast_pcode oblast_ua
isid oblast_pcode
expand `v_last' - `v_first' + 1
bysort oblast_pcode: gen month = `v_first' + _n - 1
format month %tmMon_CCYY
merge 1:1 oblast_pcode month using `oblast_attacks', assert(master match) nogenerate
replace attack_days_oblast = 0 if attack_days_oblast == .

* occupation, same rule as for raions (Crimea and Sevastopol before Feb 2022)
merge 1:1 oblast_pcode month using "$xwalk/geo_oblast_occupation.dta", ///
    keepusing(occ_share occupied_oblast) keep(master match) nogenerate
bysort oblast_pcode: egen byte always_occupied = min(occupied_oblast)
replace occupied_oblast = always_occupied ///
    & inlist(oblast_pcode, "UA01", "UA85", "UA14", "UA44") if month < tm(2022m2)
drop always_occupied
gen days_in_month = dofm(month + 1) - dofm(month)
gen double attack_days_oblast_share = attack_days_oblast / days_in_month
replace attack_days_oblast       = . if occupied_oblast
replace attack_days_oblast_share = . if occupied_oblast

label var oblast                   "Oblast (code of the paper; Kyiv city in Kyiv oblast)"
label var oblast_pcode             "Oblast code of the map (Kyiv city UA80)"
label var oblast_ua                "Oblast name as in robota.ua (merge key with 01_clean.do)"
label var month                    "Month"
label var attack_days_oblast       "Days with >= 1 attack (shelling/airstrike/drone) in the oblast"
label var attack_days_oblast_share "Share of the month's days with an attack in the oblast"
label var days_in_month            "Days in the month"
label var occupied_oblast          "Oblast occupied (> half its people under Russia; 2014 line before Feb 2022)"
label var occ_share                "Share of the oblast's population in places held by Russia"
order oblast_pcode oblast oblast_ua month occupied_oblast occ_share ///
      attack_days_oblast attack_days_oblast_share
sort oblast_pcode month
isid oblast_pcode month
compress
save "$out/viina_oblast_month.dta", replace


* =============================================================================
* CHECKS
* =============================================================================

* --- Step C1. Part A ---------------------------------------------------------------
* period covered and alarms by level (all official alarms, before the paper's cut)
use "$out/alarms_events.dta", clear
summarize started_at, format
tab level

* exposure by oblast, most exposed first; do the three measures give the same groups?
use "$out/abz_oblast_exposure.dta", clear
gsort -total_dur_hr
list oblast total_dur_hr days_touched n_alarms_per_10 occupied total_dur_hr_terc, ///
    noobs sep(0) abbrev(20)
tab total_dur_hr_terc days_touched_terc
tab total_dur_hr_terc n_alarms_per_res_terc

* raions with the paper's method: whole period. In oblasts with only oblast-wide alarms
* every raion equals the oblast (e.g. Zakarpattia: 662 alarms, 697 hours).
use "$out/abz_raion_month.dta", clear
collapse (sum) n_alarms total_dur_hr days_touched, by(raion_pcode raion_en oblast)
gsort -total_dur_hr
list oblast raion_en n_alarms total_dur_hr days_touched in 1/10, noobs sep(0)

* --- Step C2. Part B ---------------------------------------------------------------
use "$out/alarms_raion_month.dta", clear
gen year = year(dofm(month))

* occupied raions: how many raion-months, and which raions were ever occupied
tab year occupied_raion if !no_alarm_data
preserve
    collapse (sum) months_occupied = occupied_raion (max) occ_share, ///
        by(raion_pcode oblast raion_en no_alarm_data)
    list oblast raion_en months_occupied occ_share if months_occupied > 0 & !no_alarm_data, ///
        noobs sep(0)
restore

* raion-months with a measure only (not occupied, alarm data available)
drop if no_alarm_data | occupied_raion

* hours under alarm per raion and year: mean and spread across raions
preserve
    collapse (sum) hours hours_any work_hours, by(raion_pcode year)
    tabstat hours hours_any work_hours, by(year) statistics(mean p10 p50 p90 max) format(%8.0f)
restore

* most and least exposed raions, Feb 2022 - Aug 2026 (raions never occupied)
preserve
    bysort raion_pcode: gen n_months = _N
    summarize n_months, meanonly
    keep if n_months == r(max)
    collapse (sum) hours hours_any, by(raion_pcode oblast raion_en)
    gsort -hours
    list oblast raion_en hours hours_any in 1/15, noobs sep(0)
    gsort hours
    list oblast raion_en hours hours_any in 1/5, noobs sep(0)
restore

* --- Step C3. Part B against Part A, Mar 2022 - Oct 2025, by oblast -----------------
* Before the switch to raion alarms (late 2025) the two should be close in oblasts with
* few raion/hromada alarms (the West). Mine is lower where the paper adds overlaps.
* Mine is the mean over the oblast's raions that were never occupied in the period
* (an occupied month has no measure), Kyiv city included (as in the paper).
* Result on 6 Nov 2026: ratio mine/paper 1.00-1.03 in the West (mine a bit higher:
* volunteer fill of 1-15 Mar 2022); 0.6-0.9 in most central/eastern oblasts; Kharkiv
* 0.37 and Dnipropetrovsk 0.11, where the paper adds up overlapping hromada alarms
* (Nikopol). Also: Lvivskyi raion's yearly hours equal an independent calculation in
* Python (union of intervals, Europe/Kyiv time) to the hour.
* What the checks show:
*   - before the occupation flag, occupied raions (Donetsk, Horlivka, Mariupol...) got
*     every Donetsk oblast alarm, ~18,700 hours; with the flag they are missing, and the
*     most exposed raions are on the Ukrainian-held front line (Kramatorsk, Kharkiv...);
*   - front-line hromadas under near-permanent alarm (Nikopol: hours_any ~8,000 a year)
*     are invisible in the main measure, which keeps whole-raion alarms only.
preserve
    use "$out/alarms_raion_month.dta", clear
    keep if inrange(month, tm(2022m3), tm(2025m10)) & !no_alarm_data
    bysort raion_pcode: egen ever_occupied = max(occupied_raion)
    drop if ever_occupied
    collapse (sum) hours, by(raion_pcode oblast)
    collapse (mean) hours_ours = hours, by(oblast)
    tempfile mine
    save `mine'
    use "$out/abz_oblast_month.dta", clear
    collapse (sum) hours_abz = total_dur_hr, by(oblast)
    merge 1:1 oblast using `mine', keep(match) nogenerate
    gen ratio = hours_ours / hours_abz
    gsort ratio
    list oblast hours_abz hours_ours ratio, noobs sep(0)
restore

* --- Step C4. Part C (VIINA measures) --------------------------------------------------
* C4a. Events: share dropped because located only at oblast/raion level, by year, and
*      events dropped because they are in Russian-held places
preserve
    import delimited using "$temp/viina_events_precision.csv", varnames(1) clear
    list, noobs sep(0) abbrev(30)
restore

* C4b. The reconstructed 2014 line against VIINA's status on 23 Feb 2022 alone (the day
*      before the invasion), by oblast: if Wikipedia's map was right that day, the two
*      should nearly coincide.
preserve
    import delimited using "$temp/viina_line2014_check.csv", varnames(1) clear
    list, noobs sep(0)
restore

* C4c. How much the distance to the front moves: median across cities, by period
use "$out/viina_city_month.dta", clear
gen period = cond(month <= tm(2021m12), 1, cond(month <= tm(2022m3), 2, ///
    cond(month <= tm(2022m12), 3, 4)))
label define period_lbl 1 "2021" 2 "Jan-Mar 2022" 3 "Apr-Dec 2022" 4 "2023-2026"
label values period period_lbl
tabstat dist_front_km attack_days_near, by(period) statistics(p25 p50 p75) format(%8.0f)
tab month if front_move == 1                    // when the front moves happen

* C4d. Spot checks
*   Kherson: a few km from the front after its liberation in November 2022
*   Nikopol: never occupied (the both-sources rule exists to get it right in 2026)
*   Lviv: always far from the front (above 500 km)
list city_name_en month dist_front_km attack_days_near occupied_city ///
    if city_name_en == "Kherson" & inlist(month, tm(2022m10), tm(2022m11), tm(2022m12), ///
    tm(2023m6), tm(2026m6)), noobs sep(0)
list city_name_en month dist_front_km attack_days_near occupied_city ///
    if city_name_en == "Nikopol" & month >= tm(2026m5), noobs sep(0)
summarize dist_front_km if city_name_en == "Lviv"
count if city_name_en == "Lviv" & dist_front_km < 500

* C4e. Agreement with the alarm measure after the invasion (Mar 2022 - Aug 2026):
*      the city's raion alarm share against the two VIINA measures
merge m:1 raion_pcode month using "$out/alarms_raion_month.dta", ///
    keepusing(share_hours) keep(master match) nogenerate
pwcorr share_hours front_proximity ln_attack_days ///
    if inrange(month, tm(2022m3), tm(2026m8)) & !occupied_city, obs

* C4f. Raion and oblast attack days: totals by year (non-occupied units)
use "$out/viina_raion_month.dta", clear
gen year = year(dofm(month))
tabstat attack_days_raion, by(year) statistics(mean p50 p90 max) format(%6.1f)


* =============================================================================
* NOT ACTIVE YET: ROBUSTNESS VARIANTS, RAION/OBLAST MEASURE 1, FIXED EXPOSURE
* =============================================================================
* To be switched on later, once the main design is settled. To use: set
* $viina_variants to 1 in step 0 (the Python helper then also writes
* viina_city_month_variants.csv and viina_place_month.csv) and remove the comment
* markers around the blocks below. Plan: docs/exposure_viina_spec.md.
/*

* --- Variant V5. City-level robustness variants -----------------------------------------
* Columns of viina_city_month_variants.csv (00_viina_exposure.py, step 6):
*   dist_front_contested_km   distance to places Russian-held OR contested (upper bound on
*                             how close the fighting is)
*   attack_days_5km, _30km    attack days with radii of 5 and 30 km
*   attack_events_near        number of kept events within $attack_radius_km km (reports,
*                             not days: what the 13 Nov power check used)
*   attack_weighted_sum       each event within 50 km weighs exp(-km/10): no sharp cutoff
*   lethal_days_near          days with an attack with civilian casualties nearby
*   damage_days_near          days with property damage nearby
*   ground_combat_days_near   days with firefights or armor nearby
*   attack_days_near_strict   attack days without events attributed only to Ukrainian forces
* Also to do: the sensitivity of the Russian-held set to $front_days_share (rerun with a
* share just above 0, i.e. "at least one day", and with 1, i.e. "every day").
import delimited using "$temp/viina_city_month_variants.csv", varnames(1) clear
rename month month_str
gen month = monthly(month_str, "YM")
format month %tmMon_CCYY
drop month_str
tempfile variants
save `variants'
use "$out/viina_city_month.dta", clear
merge 1:1 city_id month using `variants', keep(master match) nogenerate
gen double front_proximity_contested = -ln(max(dist_front_contested_km, 1))
foreach v of varlist dist_front_contested_km front_proximity_contested attack_days_5km ///
        attack_days_30km attack_events_near attack_weighted_sum lethal_days_near ///
        damage_days_near ground_combat_days_near attack_days_near_strict {
    replace `v' = . if occupied_city | city_place_held
}
label var dist_front_contested_km   "Distance to the nearest Russian-held or contested place, km"
label var front_proximity_contested "-ln(max(distance to Russian-held or contested place, 1))"
label var attack_days_5km           "Days with >= 1 attack within 5 km"
label var attack_days_30km          "Days with >= 1 attack within 30 km"
label var attack_events_near        "Attack events within $attack_radius_km km (count)"
label var attack_weighted_sum       "Attack events within 50 km, weighted exp(-km/10)"
label var lethal_days_near          "Days with an attack with civilian casualties nearby"
label var damage_days_near          "Days with an attack with property damage nearby"
label var ground_combat_days_near   "Days with firefights or armor nearby"
label var attack_days_near_strict   "Attack days nearby, excluding events attributed only to Ukraine"
save "$out/viina_city_month.dta", replace
* Not built yet: distance to the Russian and Belarusian borders, and "threat distance"
* (the smaller of front and Russian-border distance from March 2022). They need country
* polygons (e.g. Natural Earth): the border line = Ukraine's boundary within 1 km of
* Russia's (Belarus's) territory. A daily version of the distance needs the daily files.

* --- Variant V6. Raion and oblast versions of measure 1 ----------------------------------
* A raion centroid would mislead (raions are large and populations are not centered), so:
*   - share of the raion's population living within 25, 50 or 100 km of the front;
*   - population-weighted mean of front proximity over the raion's places.
* Weights: GeoNames population where known; if no place of the raion has a known
* population, equal weights. Places in Russian-held territory are left out.
* (Alternative closer to my sample: weight robota cities by their 2021 postings.)
import delimited using "$temp/viina_place_month.csv", varnames(1) stringcols(5) clear
rename month month_str
gen month = monthly(month_str, "YM")
format month %tmMon_CCYY
drop month_str
drop if raion_pcode == "" | place_held
gen oblast_pcode = substr(raion_pcode, 1, 4)
gen double front_proximity = -ln(max(dist_front_km, 1))
foreach r in 25 50 100 {
    gen byte within_`r'km = dist_front_km < `r'
}
foreach unit in raion oblast {
    preserve
        bysort `unit'_pcode month: egen n_known = total(population > 0)
        gen double weight = cond(n_known > 0, population, 1)
        collapse (mean) pop_share_25km = within_25km pop_share_50km = within_50km ///
            pop_share_100km = within_100km front_proximity_popw = front_proximity ///
            [aw = weight], by(`unit'_pcode month)
        label var pop_share_25km       "Share of the population within 25 km of the front"
        label var pop_share_50km       "Share of the population within 50 km of the front"
        label var pop_share_100km      "Share of the population within 100 km of the front"
        label var front_proximity_popw "Population-weighted front proximity"
        tempfile m1_`unit'
        save `m1_`unit''
    restore
}
use "$out/viina_raion_month.dta", clear
merge 1:1 raion_pcode month using `m1_raion', keep(master match) nogenerate
foreach v in pop_share_25km pop_share_50km pop_share_100km front_proximity_popw {
    replace `v' = . if occupied_raion
}
save "$out/viina_raion_month.dta", replace
use "$out/viina_oblast_month.dta", clear
merge 1:1 oblast_pcode month using `m1_oblast', keep(master match) nogenerate
foreach v in pop_share_25km pop_share_50km pop_share_100km front_proximity_popw {
    replace `v' = . if occupied_oblast
}
save "$out/viina_oblast_month.dta", replace

* --- Variant V7. Fixed exposure, for "after the invasion x exposure" designs -------------
* Per-city averages over two windows: the first year of the war (Mar 2022 - Feb 2023) and
* the whole period with alarm data (Mar 2022 - Aug 2026); for front distance, attack days
* and the alarm share of the city's raion; terciles among cities never occupied. The
* distance to the 2014 line (Jan 2021) is a natural pre-war control for the front measures.
use "$out/viina_city_month.dta", clear
merge m:1 raion_pcode month using "$out/alarms_raion_month.dta", ///
    keepusing(share_hours) keep(master match) nogenerate
bysort city_id: egen byte ever_occupied = max(occupied_city * (month >= tm(2022m3)))
gen double dist_2014_line_km = dist_front_km if month == tm(2021m1)
gen byte window_year1 = inrange(month, tm(2022m3), tm(2023m2))
gen byte window_all   = inrange(month, tm(2022m3), tm(2026m8))
foreach w in year1 all {
    foreach v in front_proximity attack_days_near share_hours {
        bysort city_id: egen double `v'_`w' = mean(cond(window_`w', `v', .))
    }
}
collapse (firstnm) city_name_en raion_pcode oblast oblast_pcode oblast_ua ever_occupied ///
    dist_2014_line_km front_proximity_* attack_days_near_* share_hours_*, by(city_id)
foreach v of varlist front_proximity_year1 front_proximity_all attack_days_near_year1 ///
        attack_days_near_all share_hours_year1 share_hours_all {
    xtile `v'_tercile = `v' if !ever_occupied, nq(3)
}
label var dist_2014_line_km      "Distance to the reconstructed 2014 line, km (pre-war)"
label var ever_occupied          "City occupied in some month from Mar 2022"
label var front_proximity_year1  "Mean front proximity, Mar 2022 - Feb 2023"
label var front_proximity_all    "Mean front proximity, Mar 2022 - Aug 2026"
label var attack_days_near_year1 "Mean attack days nearby per month, Mar 2022 - Feb 2023"
label var attack_days_near_all   "Mean attack days nearby per month, Mar 2022 - Aug 2026"
label var share_hours_year1      "Mean raion alarm share, Mar 2022 - Feb 2023"
label var share_hours_all        "Mean raion alarm share, Mar 2022 - Aug 2026"
compress
save "$out/exposure_city_fixed.dta", replace

*/

log close
