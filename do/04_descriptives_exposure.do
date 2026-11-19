* =============================================================================
* 04_descriptives_exposure.do  --  descriptives of war exposure itself
*
* Describes the three exposure measures built by 03_exposure_build.do, before they are
* used with the vacancies. No regressions (descriptives stay raw: shares, means,
* percentiles and accounting decompositions). Four questions:
*   GEOGRAPHY    Where is exposure concentrated, and how does that change over time?
*                (step 3: maps of levels by year, of changes, of the front's evolution)
*   POPULATION   How many people live in highly exposed places? (step 4)
*   TIME         How much of the variation is within places over time, rather than
*                between places? (step 5: within/between decomposition)
*   MEASUREMENT  How different are the three measures, and do they flag the same places
*                as highly exposed? (step 6: correlations, overlap, top raions)
*   SAMPLE       How much of this variation does the robota.ua sample observe? (step 7:
*                coverage of the vacancies, population vs vacancies, empty cells,
*                occupation)
*
* THE THREE MEASURES (03_exposure_build.do)
*   alarm   Part B: days in the month with an air-raid alarm anywhere in the raion
*           (oblast-, raion- or hromada-level alarms; days_any), a count 0-31 like the
*           "days with alarms" of ABZ EP 2026. Raion x month, Mar 2022 - Aug 2026.
*   attack  Part C: days in the month with >= 1 reported shelling/airstrike/drone attack
*           (VIINA). Raion level: attacks inside the raion (viina_raion_month); city level:
*           within 15 km of the city (viina_city_month). Jan 2021 - Oct 2026.
*   front   Part C: distance from the city to the nearest Russian-held place (VIINA), and
*           front proximity = -ln(max(km, 1)). City x month, Jan 2021 - Oct 2026. Raion
*           level (built here, step 2b): population-weighted mean of the front proximity
*           of the raion's robota.ua cities; shown in km as exp(-mean proximity), i.e. the
*           geometric mean distance of the raion's towns. (The commented-out variant V6 of
*           03 would compute it over all VIINA places instead.)
*   Missing for occupied units (raion: > half the population under Russia; city: its
*   place held more than half the month) and, for alarms, for Crimea, Sevastopol and
*   Luhansk (no alarm data).
*
* Input : data/analysis/alarms_raion_month.dta, viina_raion_month.dta, viina_city_month.dta
*         data/temp/descriptives_base.dta     (04_descriptives.do: vacancies, groups)
*         data/crosswalks/geo_raions.dta, geo_city_occupation.dta, geo_oblasts.dta
*         data/temp/population_2022.dta       (03: UkrStat population by oblast, Jan 2022)
*         data/temp/viina_settlements.csv     (00_viina_control.py: places, GeoNames pop)
*         data/temp/viina_settlement_month.csv (00_viina_control.py: control by month)
*         data/temp/ua_raion_polygons.csv, ua_oblast_borders.csv (00_oblast_borders.py)
* Output: output/figures/04e_*.pdf              figures (list at each step)
*         output/tables/04e_*.xlsx and .tex     final tables (export_table, 00_programs.do)
*         data/temp/descriptives/04e_*          panels and the numbers behind the figures
*         data/temp/logs/04_descriptives_exposure.log
*         Every output is listed in output_inventory.xlsx (Project folder).
*
* Choices (step 0):
*   - War window: Mar 2022 - Aug 2026, the months all three measures cover (alarm data
*     start on 25 Feb 2022 and stop in Aug 2026). The VIINA measures are also shown for
*     2021 (the 2014 line) where that helps.
*   - Years in maps and tables: 2022 = Mar-Dec, 2026 = Jan-Aug.
*   - Raion population: the GeoNames population of the raion's places (VIINA place
*     list), rescaled so that each oblast sums to its UkrStat population of Jan 2022
*     (Kyiv city and oblast together, as in UkrStat's file; Crimea and Sevastopol keep
*     GeoNames). GeoNames covers towns better than villages, so rural raions are
*     understated within their oblast: an approximation, fixed at the pre-war level
*     (no displacement).
*   - City population (weights for the raion front measure and the distance bands):
*     the GeoNames population of the city's VIINA place.
*   - "High exposure": a raion-month in the top 20% of the pooled distribution of the
*     measure over the war window (raion-months with a measure, unweighted), with the
*     cutoff fixed over time. Strictly above the 80th percentile: alarm and attack days are
*     counts with many ties, so slightly fewer than 20% (actual shares in the log).
*   - Sample: civilian core vacancies (04_descriptives.do), weighted counts; "sampled" =
*     vacancies in my sample (no weights).
*   - Maps: longitude scaled by cos(48.5 deg) (equirectangular projection at Ukraine's
*     center latitude), so the country keeps its shape. Holes in raion polygons dropped.
*
* Needs: grmap (official Stata since version 15; enabled with -grmap, activate-).
* Run after 03_exposure_build.do and 04_descriptives.do (00_main.do runs it after 04).
* =============================================================================

clear all
set more off
set linesize 200

* --- Step 0. Paths and settings ---------------------------------------------
if "$project" == "" global project "`c(pwd)'/.."   // set by 00_main.do; else run from the repo root
global data    "$project/Project/data/analysis"
global xwalk   "$project/Project/data/crosswalks"
global temp    "$project/Project/data/temp"
global fig     "$project/Project/output/figures"
global tab     "$project/Project/output/tables"          // final tables only
global tmpe    "$project/Project/data/temp/descriptives" // panels, data behind figures
global do      "$project/Project/do"

cap mkdir "$fig"
cap mkdir "$tmpe"
cap mkdir "$temp/logs"
cap log close
log using "$temp/logs/04_descriptives_exposure.log", replace text
do "$do/00_programs.do"                    // export_table
capture grmap, activate                    // official spmap: enable once

global war_from  = tm(2022m3)    // war window: all three measures
global war_to    = tm(2026m8)    // last month with alarm data
global v_from    = tm(2021m1)    // VIINA panels
global v_to      = tm(2026m10)
global hi_pct    = 80            // "high exposure" = above this percentile (pooled)
if "$front_days_share" == "" global front_days_share 0.5   // as in 03, step 0
global xk = cos(48.5 * _pi / 180)                           // map projection (header)

set scheme stcolor
graph set window fontface "Arial"

local inv_x = tm(2022m2) + 0.77    // 24 Feb within February
local tfmt xlabel(`=tm(2021m1)'(6)`=tm(2026m7)', format(%tmMon_YY)) xtitle("")
local yrlab_2022 "2022 (Mar-Dec)"
local yrlab_2023 "2023"
local yrlab_2024 "2024"
local yrlab_2025 "2025"
local yrlab_2026 "2026 (Jan-Aug)"

* --- Step 1. Inputs -------------------------------------------------------------
* 1a. Raions: the map id (_ID) used by the filled maps
use "$xwalk/geo_raions.dta", clear
keep raion_pcode raion_en oblast oblast_pcode oblast_en_map no_alarm_data area_km2
sort raion_pcode
gen int _ID = _n
tempfile raions
save `raions'

* raion polygons as a Stata shapefile (_ID, _X, _Y; a missing row starts each ring)
import delimited using "$temp/ua_raion_polygons.csv", varnames(1) stringcols(1) clear
gen long seq = _n
merge m:1 raion_pcode using `raions', keepusing(_ID) assert(match) nogenerate
gen double _X = lon * $xk
gen double _Y = lat
sort _ID seq
keep _ID _X _Y
save "$tmpe/04e_raion_shp.dta", replace

* oblast and country borders for the maps' overlay (spmap line(): a missing row starts
* each line) and, in map coordinates, for the twoway maps of step 3c
import delimited using "$temp/ua_oblast_borders.csv", varnames(1) clear
gen long seq = _n
gen double bx = lon * $xk
rename lat by
save "$tmpe/04e_borders_twoway.dta", replace
drop if bx == .
bysort path (seq): gen byte first = _n == 1
expand 2 if first, generate(dup)
replace bx = . if dup
replace by = . if dup
gsort path seq -dup
gen int _ID = path
gen byte country = kind == "country"
rename (bx by) (_X _Y)
keep _ID _X _Y country
save "$tmpe/04e_borders_line.dta", replace

* 1b. Raion population (see header): GeoNames, rescaled to UkrStat oblast totals
import delimited using "$temp/viina_settlements.csv", varnames(1) stringcols(6) ///
    encoding("utf-8") clear
keep if raion_pcode != ""
collapse (sum) pop_gn = population, by(raion_pcode)
merge 1:1 raion_pcode using `raions', keepusing(oblast) nogenerate
replace pop_gn = 0 if pop_gn == .
bysort oblast: egen double pop_gn_oblast = total(pop_gn)
merge m:1 oblast using "$temp/population_2022.dta", keep(master match) nogenerate
gen double pop = cond(population < ., population * pop_gn / pop_gn_oblast, pop_gn)
label var pop "Population, Jan 2022 (GeoNames shares within UkrStat oblast totals)"
summarize pop
display "Total population of the 139 raions (millions): " %5.2f r(sum) / 1e6
keep raion_pcode pop
tempfile raion_pop
save `raion_pop'

* 1c. City population: GeoNames population of the city's VIINA place
import delimited using "$temp/viina_settlements.csv", varnames(1) stringcols(6) ///
    encoding("utf-8") clear
keep geonameid population
tempfile place_pop
save `place_pop'
use city_id geonameid using "$xwalk/geo_city_occupation.dta", clear
duplicates drop
isid city_id
merge m:1 geonameid using `place_pop', keep(master match) nogenerate
rename population city_pop
replace city_pop = 0 if city_pop == .
keep city_id city_pop
tempfile city_pop
save `city_pop'

* 1d. Civilian core vacancies by city x month and raion x month, and in 2021
use city_id raion_pcode core weight ym using "$temp/descriptives_base.dta" if core, clear
gen byte one = 1
preserve
    collapse (sum) vac_est = weight vac_n = one, by(city_id ym)
    rename ym month
    tempfile vac_city
    save `vac_city'
restore
preserve
    keep if inrange(ym, tm(2021m1), tm(2021m12))
    collapse (sum) vac2021 = weight, by(city_id)
    replace vac2021 = vac2021 / 12
    tempfile vac2021_city
    save `vac2021_city'
restore
keep if raion_pcode != ""
preserve
    collapse (sum) vac_est = weight vac_n = one, by(raion_pcode ym)
    rename ym month
    tempfile vac_raion
    save `vac_raion'
restore
keep if inrange(ym, tm(2021m1), tm(2021m12))
collapse (sum) vac2021 = weight, by(raion_pcode)
replace vac2021 = vac2021 / 12
tempfile vac2021_raion
save `vac2021_raion'

* --- Step 2. Panels ---------------------------------------------------------------
* 2a. City x month (robota.ua cities in Ukraine with a point, Jan 2021 - Oct 2026; cities
*     abroad also have a point in viina_city_month but no raion: left out)
*     Output: data/temp/descriptives/04e_city_month.dta
use "$data/viina_city_month.dta" if raion_pcode != "", clear   // abroad: no raion
merge m:1 raion_pcode month using "$data/alarms_raion_month.dta", ///
    keepusing(days_any) keep(master match) nogenerate
merge m:1 city_id using `city_pop', keep(master match) nogenerate
replace city_pop = 0 if city_pop == .
merge 1:1 city_id month using `vac_city', keep(master match) nogenerate
merge m:1 city_id using `vac2021_city', keep(master match) nogenerate
foreach v in vac_est vac_n vac2021 {
    replace `v' = 0 if `v' == .
}
gen double alarm  = days_any
gen double attack = attack_days_near
gen double front  = front_proximity
gen byte war = inrange(month, $war_from, $war_to)
gen int year = year(dofm(month))
label var alarm    "Alarm: days with an alarm (city's raion)"
label var attack   "Attack days within 15 km"
label var front    "Front proximity, -ln(km)"
label var city_pop "City population (GeoNames)"
label var vac_est  "Core vacancies in the month (estimated)"
label var vac_n    "Core vacancies in the month (sampled)"
label var vac2021  "Core vacancies per month in 2021 (estimated)"
compress
save "$tmpe/04e_city_month.dta", replace

* 2b. Raion x month (139 raions, Jan 2021 - Oct 2026). The raion front measure: mean
*     front proximity of the raion's (non-occupied) cities, weighted by city
*     population; equal weights if no city of the raion has a known population.
*     Output: data/temp/descriptives/04e_raion_month.dta
keep if front < .
bysort raion_pcode month: egen n_pop = total(city_pop > 0)
gen double wf = cond(n_pop > 0, city_pop, 1)
collapse (mean) front (count) n_cities_front = front [aw = wf], by(raion_pcode month)
tempfile front_raion
save `front_raion'

use "$data/viina_raion_month.dta", clear
merge 1:1 raion_pcode month using "$data/alarms_raion_month.dta", ///
    keepusing(days_any) keep(master match) nogenerate
merge m:1 raion_pcode using `raions', keepusing(_ID oblast_en_map no_alarm_data area_km2) ///
    assert(match) nogenerate
merge 1:1 raion_pcode month using `front_raion', keep(master match) nogenerate
merge m:1 raion_pcode using `raion_pop', assert(match) nogenerate
merge 1:1 raion_pcode month using `vac_raion', keep(master match) nogenerate
merge m:1 raion_pcode using `vac2021_raion', keep(master match) nogenerate
foreach v in vac_est vac_n vac2021 {
    replace `v' = 0 if `v' == .
}
replace front = . if occupied_raion
gen double alarm   = days_any
gen double attack  = attack_days_raion
gen double front_km = exp(-front)
gen byte war = inrange(month, $war_from, $war_to)
gen int year = year(dofm(month))

* high exposure: above the pooled 80th percentile of the war window (header)
foreach v in alarm attack front {
    _pctile `v' if war, p($hi_pct)
    global cut_`v' = r(r1)
    gen byte hi_`v' = `v' > ${cut_`v'} if `v' < . & war
}
display "High-exposure cutoffs (p$hi_pct, raion-months Mar 2022 - Aug 2026):"
display "  alarm  > " %5.1f $cut_alarm " days with an alarm in the month"
display "  attack > " %5.1f $cut_attack " attack days in the month"
display "  front  > " %5.2f $cut_front " proximity, i.e. closer than " %5.1f exp(-$cut_front) " km"
global cutkm_front = exp(-$cut_front)
summarize hi_alarm hi_attack hi_front           // actual shares (ties: counts below 20%)

label var alarm      "Alarm: days with an alarm in the raion"
label var attack     "Attack days in the raion"
label var front      "Front proximity of the raion's cities, -ln(km)"
label var front_km   "Distance to the front, km (geometric mean of the raion's cities)"
label var pop        "Population, Jan 2022 (approximate, see header)"
label var vac_est    "Core vacancies in the month (estimated)"
label var vac_n      "Core vacancies in the month (sampled)"
label var vac2021    "Core vacancies per month in 2021 (estimated)"
label var hi_alarm   "High exposure: alarm (above pooled p$hi_pct)"
label var hi_attack  "High exposure: attack days (above pooled p$hi_pct)"
label var hi_front   "High exposure: front (above pooled p$hi_pct)"
sort raion_pcode month
compress
save "$tmpe/04e_raion_month.dta", replace

* how many raion-months have each measure, war window
count if war
foreach v in alarm attack front {
    count if war & `v' < .
}

* --- Step 3. Geography: maps -----------------------------------------------------
* 3a. Levels by year, one figure per measure (2022 = Mar-Dec, 2026 = Jan-Aug). Mean of
*     the months with a measure; a raion is "occupied or no data" in a year if it has a
*     measure in fewer than half of the year's months. Same classes in every year.
*     Output: 04e_map_alarm_levels.pdf, 04e_map_front_levels.pdf;
*             data in data/temp/descriptives/04e_raion_year.csv
*     (Attacks are mapped by settlement instead, step 3a-bis: events are located at
*     settlements, and raion means mix front villages with quiet towns.)
use "$tmpe/04e_raion_month.dta" if war, clear
collapse (mean) alarm attack front (count) n_alarm = alarm n_attack = attack ///
    n_front = front n_months = month, by(raion_pcode _ID year)
foreach v in alarm attack front {
    replace `v' = . if n_`v' < n_months / 2
}
gen double front_km = exp(-front)
keep raion_pcode _ID year alarm attack front front_km
export delimited using "$tmpe/04e_raion_year.csv", replace
reshape wide alarm attack front front_km, i(raion_pcode _ID) j(year)
tempfile raion_year
save `raion_year'

local shp   "$tmpe/04e_raion_shp.dta"
local lines line(data("$tmpe/04e_borders_line.dta") by(country) color(gs6 gs3) size(vthin thin))
local common id(_ID) ocolor(white ..) osize(vvthin ..) ndfcolor(gs13) ndocolor(white) ///
    ndsize(vvthin) ndlabel("Occupied or no data") `lines' legstyle(2) legjunction(" to ") ///
    legend(size(vsmall) position(7) ring(0) region(lstyle(none) fcolor(none)) symxsize(3) keygap(1))

* class breaks and colors (light = low exposure)
local brk_alarm  "0 10 20 25 28 31"   // days are near the ceiling in most of the country
local col_alarm  `""255 255 178" "254 204 92" "253 141 60" "240 59 32" "189 0 38""'
local brk_attack "0 0.5 2 5 10 31"
local col_attack `""255 255 212" "254 217 142" "254 153 41" "217 95 14" "153 52 4""'
* front: distance in km, so dark = close
local brk_front  "0 25 50 100 200 400 900"
local col_front  `""103 0 13" "203 24 29" "251 106 74" "252 187 161" "254 229 217" "247 247 247""'
local var_front  "front_km"
local var_alarm  "alarm"
local var_attack "attack"
local ttl_alarm  "Days per month with an alarm in the raion"
local ttl_attack "Attack days per month in the raion"
local ttl_front  "Distance to the front (km; geometric mean of the raion's towns)"

foreach m in alarm front {
    local glist ""
    foreach y in 2022 2023 2024 2025 2026 {
        grmap `var_`m''`y' using "`shp'", `common' clmethod(custom) clbreaks(`brk_`m'') ///
            fcolor(`col_`m'') title("`yrlab_`y''", size(medsmall)) name(g`y', replace)
        local glist `glist' g`y'
    }
    graph combine `glist', cols(3) imargin(tiny) xsize(10) ysize(5.6) ///
        title("`ttl_`m''", size(medsmall)) ///
        note("Raion means over the months of each year. Gray: occupied (more than half the raion's people under Russia) or no alarm data, in at least half the year's months." ///
        "Lines: oblast and country borders (OCHA COD-AB, 2025).", size(vsmall))
    graph export "$fig/04e_map_`m'_levels.pdf", replace
    graph drop `glist'
}

* 3a-bis. Attacks by settlement, by year (2022 = Mar-Dec, 2026 = Jan-Aug). Each dot is a
*     place where at least one attack was reported in the year: the events kept in 03
*     (artillery, airstrike or drone; located at least at a settlement; not in a
*     Russian-held place that month), grouped by their point rounded to 0.01 degrees
*     (~1 km, so street-level reports join their settlement). Color: attack days per
*     month at the place = days with >= 1 such event / months of the year in the war
*     window. Places with no attack in the year are not drawn.
*     Output: 04e_map_attack_levels.pdf; data in data/temp/descriptives/04e_place_year_attacks.csv
import delimited using "$temp/viina_events_clean.csv", varnames(1) stringcols(2 8) clear
drop month                                          // text "YYYY-MM"; rebuilt below
keep if raion_pcode != ""                           // inside Ukraine (drops strikes on Russia)
gen day = daily(date, "YMD")
gen month = mofd(day)
keep if inrange(month, $war_from, $war_to)
gen double px = round(lon, 0.01) * $xk             // map coordinates (header)
gen double py = round(lat, 0.01)
gen int year = year(day)
duplicates drop px py day, force                    // one row per place and day
collapse (count) attack_days = day, by(px py year)
gen months = cond(year == 2022, 10, cond(year == 2026, 8, 12))   // war window
gen double attack_pm = attack_days / months
label var attack_days "Days with >= 1 attack at the place in the year"
label var attack_pm   "Attack days per month at the place"
export delimited using "$tmpe/04e_place_year_attacks.csv", replace
tabstat attack_pm, by(year) statistics(n p50 p90 max) format(%6.2f)   // places and spread

* classes (light = low), and the plotting order: low classes first, hot spots on top
gen byte class = 1 + (attack_pm >= 0.5) + (attack_pm >= 2) + (attack_pm >= 5) + (attack_pm >= 10)
sort class
append using "$tmpe/04e_borders_twoway.dta"
local glist ""
local i = 0
foreach y in 2022 2023 2024 2025 2026 {
    local ++i
    local leg legend(off)
    if `i' == 1 local leg legend(order(3 "Under 0.5" 4 "0.5-2" 5 "2-5" 6 "5-10" 7 "10 or more") ///
        title("Attack days per month", size(vsmall)) cols(1) ring(0) position(7) ///
        size(vsmall) symxsize(2) keygap(1) region(lstyle(none) fcolor(none)))
    twoway (line by bx if kind == "oblast", sort(seq) cmissing(n) lcolor(gs12) lwidth(vthin)) ///
        (line by bx if kind == "country", sort(seq) cmissing(n) lcolor(gs6) lwidth(thin)) ///
        (scatter py px if year == `y' & class == 1, msymbol(o) msize(vtiny) mcolor("254 217 142")) ///
        (scatter py px if year == `y' & class == 2, msymbol(o) msize(tiny) mcolor("254 153 41")) ///
        (scatter py px if year == `y' & class == 3, msymbol(o) msize(small) mcolor("236 112 20")) ///
        (scatter py px if year == `y' & class == 4, msymbol(o) msize(small) mcolor("204 76 2")) ///
        (scatter py px if year == `y' & class == 5, msymbol(o) msize(medsmall) mcolor("140 45 4")), ///
        xscale(off range(`=22 * $xk' `=40.3 * $xk')) yscale(off range(44.3 52.5)) aspectratio(0.69) ///
        xlabel(none, nogrid) ylabel(none, nogrid) plotregion(lstyle(none)) ///
        title("`yrlab_`y''", size(medsmall)) `leg' name(a`i', replace) nodraw
    local glist `glist' a`i'
}
graph combine `glist', cols(3) imargin(tiny) xsize(10) ysize(5.6) ///
    title("Attack days per month, by settlement", size(medsmall)) ///
    note("Dots: places with at least one reported shelling, airstrike or drone attack in the year (VIINA; located at least at a settlement, outside Russian-held places)." ///
    "Days with an attack at the place / months of the year (2022: Mar-Dec; 2026: Jan-Aug). Coverage falls: Liveuamap, the main source of local reports, gives ~16,800 attack reports in 2024," ///
    "~5,700 in 2025 and ~1,550 in 2026, so places with an attack drop from ~3,000 (2024) to ~270 (2026), mostly large cities.", size(vsmall))
graph export "$fig/04e_map_attack_levels.pdf", replace
graph drop `glist'

* 3b. Changes: 2025 (last full year) minus 2022 (Mar-Dec). Front: % change in the
*     (geometric mean) distance, so a negative change = the front came closer.
*     Output: 04e_map_changes.pdf
use `raion_year', clear
gen double d_alarm  = alarm2025 - alarm2022
gen double d_attack = attack2025 - attack2022
gen double d_front  = 100 * (front_km2025 / front_km2022 - 1)
summarize d_alarm d_attack d_front, detail
local div  `""33 102 172" "103 169 207" "209 229 240" "247 247 247" "253 219 199" "239 138 98" "178 24 43""'
local divr `""178 24 43" "239 138 98" "253 219 199" "247 247 247" "209 229 240" "103 169 207" "33 102 172""'
grmap d_alarm using "`shp'", `common' clmethod(custom) ///
    clbreaks(-31 -5 -2 -0.5 0.5 2 5 31) fcolor(`div') ///
    title("A. Alarm days per month: change", size(medsmall)) name(c1, replace)
grmap d_attack using "`shp'", `common' clmethod(custom) ///
    clbreaks(-31 -5 -2 -0.5 0.5 2 5 31) fcolor(`div') ///
    title("B. Attack days per month: change", size(medsmall)) name(c2, replace)
grmap d_front using "`shp'", `common' clmethod(custom) ///
    clbreaks(-100 -25 -10 -2 2 10 25 1000) fcolor(`divr') ///
    title("C. Distance to the front: % change", size(medsmall)) name(c3, replace)
graph combine c1 c2 c3, cols(3) imargin(tiny) xsize(10) ysize(3.2) ///
    note("2025 against Mar-Dec 2022, raion means. Red = more exposed in 2025 (more alarm days, more attack days, front closer). Gray: occupied or no data in one of the two years." ///
    "B: VIINA's reports fall over time (~51,000 attack reports in 2022, ~10,000 in 2026), partly a fall in news coverage, so part of the decline is measurement.", size(vsmall))
graph export "$fig/04e_map_changes.pdf", replace
graph drop c1 c2 c3

* 3c. Evolution of the front: Russian-held places (VIINA, rule of 03: held on at least
*     $front_days_share of the month's days; before the invasion the reconstructed 2014
*     line) and robota.ua cities colored by their distance to the front.
*     Output: 04e_map_front_evolution.pdf
import delimited using "$temp/viina_settlements.csv", varnames(1) stringcols(6) ///
    encoding("utf-8") clear
keep geonameid lat lon raion_pcode
tempfile places
save `places'
import delimited using "$temp/viina_settlement_month.csv", varnames(1) clear
rename month month_str
gen month = monthly(month_str, "YM")
gen byte held = days_ru / days >= $front_days_share
* the 2014 line (as in 00_viina_exposure.py): held in every month, in the four oblasts
bysort geonameid: egen n_held = total(held)
quietly levelsof month
local n_m : word count `r(levels)'
merge m:1 geonameid using `places', keep(match) nogenerate
gen byte line2014 = n_held == `n_m' & inlist(substr(raion_pcode, 1, 4), "UA01", "UA85", "UA14", "UA44")
local panels "`=tm(2022m1)' `=tm(2022m3)' `=tm(2022m12)' `=tm(2023m12)' `=tm(2024m12)' `=tm(2026m10)'"
preserve
    keep if line2014 & month == tm(2022m3)
    replace month = tm(2022m1)
    keep geonameid month lat lon
    tempfile line
    save `line'
restore
keep if held & inlist(month, `=tm(2022m3)', `=tm(2022m12)', `=tm(2023m12)', `=tm(2024m12)', `=tm(2026m10)')
keep geonameid month lat lon
append using `line'
gen double hx = lon * $xk
rename lat hy
gen byte layer = 1
* number of Russian-held places in each panel month
tab month
* for a light PDF: one dot per ~5 km grid cell, opaque (invisible at the size of the map)
replace hx = round(hx, 0.05)
replace hy = round(hy, 0.05)
duplicates drop month hx hy, force
tempfile held
save `held'

use city_id raion_pcode month dist_front_km front_band using "$data/viina_city_month.dta" ///
    if raion_pcode != "", clear
merge m:1 city_id using "$xwalk/geo_city_raion.dta", keepusing(lat lon) keep(master match) nogenerate
keep if inlist(month, `=tm(2022m1)', `=tm(2022m3)', `=tm(2022m12)', `=tm(2023m12)', `=tm(2024m12)', `=tm(2026m10)')
keep if dist_front_km < .
gen double cx = lon * $xk
rename lat cy
gen byte layer = 2
append using `held'
append using "$tmpe/04e_borders_twoway.dta"
local i = 0
local glist ""
foreach t of local panels {
    local ++i
    local tl : display %tmMon_CCYY `t'
    if `t' == tm(2022m1) local tl "Jan 2022 (2014 line)"
    if `t' == tm(2022m3) local tl "Mar 2022 (VIINA vote only)"
    local leg legend(off)
    if `i' == 1 local leg legend(order(3 "Russian-held place" 8 "City < 25 km from front" ///
        7 "25-50 km" 6 "50-100 km" 5 "100-200 km" 4 "200 km or more") cols(1) ring(0) ///
        position(7) size(vsmall) symxsize(2) keygap(1) region(lstyle(none) fcolor(none)))
    twoway (line by bx if kind == "oblast", sort(seq) cmissing(n) lcolor(gs12) lwidth(vthin)) ///
        (line by bx if kind == "country", sort(seq) cmissing(n) lcolor(gs6) lwidth(thin)) ///
        (scatter hy hx if layer == 1 & month == `t', msymbol(o) msize(vtiny) mcolor("150 70 70")) ///
        (scatter cy cx if layer == 2 & month == `t' & front_band == 4, msymbol(o) msize(tiny) mcolor(gs11)) ///
        (scatter cy cx if layer == 2 & month == `t' & front_band == 3, msymbol(o) msize(tiny) mcolor("254 196 79")) ///
        (scatter cy cx if layer == 2 & month == `t' & front_band == 2, msymbol(o) msize(tiny) mcolor("254 153 41")) ///
        (scatter cy cx if layer == 2 & month == `t' & front_band == 1, msymbol(o) msize(tiny) mcolor("217 72 1")) ///
        (scatter cy cx if layer == 2 & month == `t' & front_band == 0, msymbol(o) msize(tiny) mcolor("127 39 4")), ///
        xscale(off range(`=22 * $xk' `=40.3 * $xk')) yscale(off range(44.3 52.5)) aspectratio(0.69) ///
        xlabel(none, nogrid) ylabel(none, nogrid) plotregion(lstyle(none)) ///
        title("`tl'", size(medsmall)) `leg' name(f`i', replace) nodraw
    local glist `glist' f`i'
}
graph combine `glist', cols(3) imargin(tiny) xsize(10) ysize(5.6) ///
    note("Russian-held: places held on at least half the month's days (both-sources rule of 03; Mar 2022: VIINA's vote only, overstates the north). Jan 2022: the reconstructed 2014 line." ///
    "Dots for cities: robota.ua cities with a map point (occupied cities left out).", size(vsmall))
graph export "$fig/04e_map_front_evolution.pdf", replace
graph drop `glist'

* 3d. Slide maps: Mar-Dec 2022 only, one PDF per measure, each at the level the designs
*     use it (06_designs.do): alarms by raion; front and attacks by robota.ua city
*     (distance to the front; attack days within $attack_radius_km km). Unlike step
*     3a-bis, the attack map shows the city measure, not where events were reported.
*     Larger legends, no title or note (the slide gives them). 2022 only, so the folder
*     doesn't fill up with one file per year; the year-by-year figures are steps 3a, 3a-bis.
*     Output: 04e_map2022_alarm.pdf, 04e_map2022_front.pdf, 04e_map2022_attack.pdf;
*             data behind the city maps in data/temp/descriptives/04e_city_2022.csv
* legend text is large: these maps are shown at ~1/3 of a slide's width
local slideleg size(large) symxsize(4) symysize(4) keygap(1) rowgap(0.3) region(lstyle(none) fcolor(none))
local mapframe xscale(off range(`=22 * $xk' `=40.3 * $xk')) yscale(off range(44.3 52.5)) ///
    aspectratio(0.69) xlabel(none, nogrid) ylabel(none, nogrid) plotregion(lstyle(none))

* alarms: raion means over Mar-Dec 2022 (as the 2022 panel of step 3a)
use `raion_year', clear
grmap alarm2022 using "`shp'", id(_ID) ocolor(white ..) osize(vvthin ..) ndfcolor(gs13) ///
    ndocolor(white) ndsize(vvthin) ndlabel("Occupied or no data") `lines' legstyle(2) ///
    legjunction(" to ") clmethod(custom) clbreaks(`brk_alarm') fcolor(`col_alarm') ///
    legend(position(7) ring(0) `slideleg') xsize(5) ysize(3.6)
graph export "$fig/04e_map2022_alarm.pdf", replace

* robota.ua cities, Mar-Dec 2022: front = geometric mean distance (mean of -ln km, as
*     in the analysis); attacks = attack days within $attack_radius_km km per month.
*     Cities with a measure in at least half the months (occupied months are missing).
use city_id raion_pcode month front_proximity attack_days_near using "$data/viina_city_month.dta" ///
    if raion_pcode != "" & inrange(month, $war_from, tm(2022m12)), clear
collapse (mean) front_proximity attack_pm = attack_days_near ///
    (count) n_m = front_proximity, by(city_id)
keep if n_m >= 5
gen double km = exp(-front_proximity)
merge 1:1 city_id using "$xwalk/geo_city_raion.dta", keepusing(lat lon) keep(match) nogenerate
gen byte band = (km >= 25) + (km >= 50) + (km >= 100) + (km >= 200)   // 0 = < 25 km
gen byte aclass = (attack_pm > 0) + (attack_pm >= 2) + (attack_pm >= 5) + (attack_pm >= 10)
label var km        "Distance to the front, km (geometric mean, Mar-Dec 2022)"
label var attack_pm "Attack days per month within $attack_radius_km km (Mar-Dec 2022)"
export delimited city_id km band attack_pm aclass lat lon using "$tmpe/04e_city_2022.csv", replace
tab band
tab aclass
gen double cx = lon * $xk
rename lat cy
tempfile city2022
save `city2022'

* front map. Gray-red: places Russia held in Dec 2022 (from step 3c).
gen byte layer = 2
append using `held'
keep if layer == 2 | month == tm(2022m12)
append using "$tmpe/04e_borders_twoway.dta"
twoway (line by bx if kind == "oblast", sort(seq) cmissing(n) lcolor(gs12) lwidth(vthin)) ///
    (line by bx if kind == "country", sort(seq) cmissing(n) lcolor(gs6) lwidth(thin)) ///
    (scatter hy hx if layer == 1, msymbol(o) msize(vtiny) mcolor("200 165 165")) ///
    (scatter cy cx if layer == 2 & band == 4, msymbol(o) msize(vsmall) mcolor(gs12)) ///
    (scatter cy cx if layer == 2 & band == 3, msymbol(o) msize(small) mcolor("254 196 79")) ///
    (scatter cy cx if layer == 2 & band == 2, msymbol(o) msize(small) mcolor("254 153 41")) ///
    (scatter cy cx if layer == 2 & band == 1, msymbol(o) msize(small) mcolor("217 72 1")) ///
    (scatter cy cx if layer == 2 & band == 0, msymbol(o) msize(small) mcolor("127 39 4")), ///
    `mapframe' legend(order(8 "Under 25 km" 7 "25-50 km" 6 "50-100 km" 5 "100-200 km" ///
    4 "200 km or more" 3 "Russian-held (Dec 2022)") cols(1) ring(0) position(7) `slideleg') ///
    xsize(5) ysize(3.6)
graph export "$fig/04e_map2022_front.pdf", replace

* attack map: each city's attack days per month within $attack_radius_km km
use `city2022', clear
append using "$tmpe/04e_borders_twoway.dta"
twoway (line by bx if kind == "oblast", sort(seq) cmissing(n) lcolor(gs12) lwidth(vthin)) ///
    (line by bx if kind == "country", sort(seq) cmissing(n) lcolor(gs6) lwidth(thin)) ///
    (scatter cy cx if aclass == 0, msymbol(o) msize(vsmall) mcolor(gs12)) ///
    (scatter cy cx if aclass == 1, msymbol(o) msize(small) mcolor("254 217 142")) ///
    (scatter cy cx if aclass == 2, msymbol(o) msize(small) mcolor("254 153 41")) ///
    (scatter cy cx if aclass == 3, msymbol(o) msize(small) mcolor("204 76 2")) ///
    (scatter cy cx if aclass == 4, msymbol(o) msize(small) mcolor("140 45 4")), ///
    `mapframe' legend(order(7 "10 or more" 6 "5-10" 5 "2-5" 4 "Under 2" 3 "None") ///
    title("Days per month", size(large)) cols(1) ring(0) position(7) `slideleg') ///
    xsize(5) ysize(3.6)
graph export "$fig/04e_map2022_attack.pdf", replace

* --- Step 4. Population-weighted exposure ----------------------------------------
* 4a. Monthly means of each measure across raions (raions with a measure), with three
*     weights: population (Jan 2022), equal (each raion counts once) and 2021 core
*     vacancies (what the sample sees, before the war). Front: geometric mean distance.
*     Output: 04e_exposure_series.pdf; data in data/temp/descriptives/04e_exposure_series.csv
use "$tmpe/04e_raion_month.dta", clear
gen byte w_eq = 1
local k = 0
foreach w in pop w_eq vac2021 {
    local ++k
    preserve
        collapse (mean) alarm_`k' = alarm attack_`k' = attack front_`k' = front [aw = `w'], by(month)
        tempfile s`k'
        save `s`k''
    restore
}
* high exposure: share of the population of raions with a measure; and the share of
* the total population in occupied raions
foreach v in alarm attack front {
    gen double pop_`v' = pop if `v' < .
    gen double pop_hi_`v' = pop * hi_`v'
}
gen double pop_occ = pop * occupied_raion
collapse (sum) pop pop_occ pop_alarm pop_hi_alarm pop_attack pop_hi_attack pop_front pop_hi_front, by(month)
foreach v in alarm attack front {
    gen double sh_hi_`v' = 100 * pop_hi_`v' / pop_`v' if month >= $war_from & month <= $war_to
}
gen double sh_occ = 100 * pop_occ / pop
keep month sh_*
forvalues k = 1/3 {
    merge 1:1 month using `s`k'', nogenerate
}
* no VIINA events before 23 Feb 2022 (its first day): attack days are not measured then
forvalues k = 1/3 {
    gen double front_km_`k' = exp(-front_`k')
    replace alarm_`k' = . if !inrange(month, $war_from, $war_to)
    replace attack_`k' = . if month < tm(2022m2)
}
format month %tmMon_CCYY
sort month
export delimited using "$tmpe/04e_exposure_series.csv", replace
tempfile series
save `series'

local leg3 legend(order(1 "Population-weighted" 2 "Raions, equal weights" 3 "2021 vacancy-weighted") ///
    cols(1) ring(0) position(11) size(vsmall) region(lstyle(none) fcolor(none)))
twoway (line alarm_1 month, lcolor(navy) lwidth(medthick)) (line alarm_2 month, lcolor(gs8) lpattern(dash)) ///
    (line alarm_3 month, lcolor(cranberry)) if month >= $war_from, ///
    xline(`inv_x', lcolor(cranberry%50)) `tfmt' ylabel(, angle(0)) ytitle("Days with an alarm") ///
    title("A. Alarm", size(medsmall)) `leg3' name(e1, replace) nodraw
twoway (line attack_1 month, lcolor(navy) lwidth(medthick)) (line attack_2 month, lcolor(gs8) lpattern(dash)) ///
    (line attack_3 month, lcolor(cranberry)), ///
    xline(`inv_x', lcolor(cranberry%50)) `tfmt' ylabel(, angle(0)) ytitle("Attack days in the raion") ///
    title("B. Attack days", size(medsmall)) legend(off) name(e2, replace) nodraw
twoway (line front_km_1 month, lcolor(navy) lwidth(medthick)) (line front_km_2 month, lcolor(gs8) lpattern(dash)) ///
    (line front_km_3 month, lcolor(cranberry)), ///
    xline(`inv_x', lcolor(cranberry%50)) `tfmt' ylabel(, angle(0)) ytitle("Distance to the front, km") ///
    title("C. Front (geometric mean distance)", size(medsmall)) legend(off) name(e3, replace) nodraw
graph combine e1 e2 e3, cols(3) xsize(11) ysize(3.6) ///
    note("Means across raions with a measure, each month. Attack days: VIINA starts on 23 Feb 2022. Front: exp(-mean proximity), the geometric mean distance; before Mar 2022 the 2014 line; Mar 2022 VIINA's vote only.", size(vsmall))
graph export "$fig/04e_exposure_series.pdf", replace
graph drop e1 e2 e3

* 4b. Share of the population in high-exposure raions (cutoffs: step 2b), and in
*     occupied raions. Output: 04e_high_exposure_population.pdf
twoway (line sh_hi_alarm month, lcolor(navy) lwidth(medthick)) (line sh_hi_attack month, lcolor(dkorange)) ///
    (line sh_hi_front month, lcolor(cranberry)) (line sh_occ month, lcolor(gs8) lpattern(dash)) ///
    if month >= tm(2022m2), `tfmt' ylabel(, angle(0)) ytitle("% of the population") ///
    legend(order(1 "High alarm" 2 "High attack days" 3 "High front proximity" ///
    4 "In occupied raions (% of all)") rows(1) size(small) position(6)) ///
    note("High exposure: raion-month above the pooled 80th percentile of Mar 2022 - Aug 2026 (alarm > `: display %3.1f $cut_alarm' days; attack > `: display %2.0f $cut_attack' days; towns closer than `: display %3.0f $cutkm_front' km)." ///
    "Shares of the population (Jan 2022) of the raions with a measure; occupied raions: share of the population of all 139 raions.", size(vsmall))
graph export "$fig/04e_high_exposure_population.pdf", replace

* 4c. Distance bands at the city level: share of the population (GeoNames, robota.ua
*     cities) and of the month's core vacancies within 25 / 50 / 100 km of the front.
*     Output: 04e_front_bands.pdf; data in data/temp/descriptives/04e_front_bands.csv
use "$tmpe/04e_city_month.dta" if dist_front_km < ., clear
foreach r in 25 50 100 {
    gen byte within`r' = dist_front_km < `r'
}
preserve
    collapse (mean) p25 = within25 p50 = within50 p100 = within100 [aw = city_pop], by(month)
    tempfile bp
    save `bp'
restore
collapse (mean) v25 = within25 v50 = within50 v100 = within100 [aw = vac_est], by(month)
merge 1:1 month using `bp', nogenerate
foreach v of varlist p* v* {
    replace `v' = 100 * `v'
}
format month %tmMon_CCYY
export delimited using "$tmpe/04e_front_bands.csv", replace
tempfile bands
save `bands'
twoway (line p25 month, lcolor(cranberry) lwidth(medthick)) (line p50 month, lcolor(dkorange) lwidth(medthick)) ///
    (line p100 month, lcolor(gold) lwidth(medthick)) (line v25 month, lcolor(cranberry) lpattern(dash)) ///
    (line v50 month, lcolor(dkorange) lpattern(dash)) (line v100 month, lcolor(gold) lpattern(dash)), ///
    xline(`inv_x', lcolor(cranberry%50)) `tfmt' ylabel(, angle(0)) ytitle("%") ///
    legend(order(1 "Population, < 25 km" 2 "< 50 km" 3 "< 100 km" 4 "Core vacancies, < 25 km" ///
    5 "< 50 km" 6 "< 100 km") rows(2) size(small) position(6)) ///
    note("Solid: share of the population of robota.ua cities (GeoNames) within each distance of the front; dashed: share of the month's civilian core vacancies." ///
    "Occupied cities left out. Jan 2021 - Feb 2022: distance to the reconstructed 2014 line; Mar 2022: VIINA's vote only.", size(vsmall))
graph export "$fig/04e_front_bands.pdf", replace

* 4d. Table by year: population-weighted means and high-exposure shares.
*     Output: 04e_exposure_by_year (.xlsx, .tex)
use `series', clear
merge 1:1 month using `bands', keepusing(p50) nogenerate
gen int year = year(dofm(month))
keep if month <= $war_to                     // 2026: Jan-Aug for every column
drop if inrange(month, tm(2022m1), tm(2022m2)) // the invasion month apart
collapse (mean) alarm_1 attack_1 front_1 sh_hi_alarm sh_hi_attack sh_hi_front p50 sh_occ, by(year)
gen double front_km = exp(-front_1)
drop front_1
tostring year, replace
replace year = "2022 (Mar-Dec)" if year == "2022"
replace year = "2026 (Jan-Aug)" if year == "2026"
order year alarm_1 attack_1 front_km sh_hi_alarm sh_hi_attack sh_hi_front p50 sh_occ
format alarm_1 attack_1 sh_* p50 %5.1f
format front_km %5.0f
label var year        "Year"
label var alarm_1     "Alarm days per month"
label var attack_1    "Attack days per month"
label var front_km    "Distance to front, km"
label var sh_hi_alarm  "Pop. in high-alarm raions, %"
label var sh_hi_attack "Pop. in high-attack raions, %"
label var sh_hi_front  "Pop. in high-front raions, %"
label var p50         "City pop. < 50 km from front, %"
label var sh_occ      "Pop. in occupied raions, %"
list, noobs sep(0) abbrev(14)
export_transposed using "$tab/04e_exposure_by_year", ///
    title("Exposure by year: population-weighted means across raions and shares of the population in high-exposure raions")

* --- Step 5. Time: within and between variation ----------------------------------
* Accounting decomposition of each measure's variance over the war window (Mar 2022 -
* Aug 2026), with nested (weighted) means: total = between oblasts + between raions
* within the oblast [+ between cities within the raion] + within the unit over time.
* The shares add up to 100. Two more columns, not part of the sum: the variance left
* after removing the unit's mean AND the national month mean (two-way demeaned), and
* the SD within oblast x month (what is left for comparisons between places of the
* same oblast in the same month).
* Panels: raion-month (equal weights; population weights); city-month weighted by 2021
* core vacancies (the sample's view before the war); city-month weighted by the month's
* core vacancies (what the sample observes).
* Output: 04e_variance_decomposition (.xlsx, .tex)
capture program drop vardec
program define vardec, rclass
    syntax varname [if], w(varname) levels(string) time(varname) obltime(varlist)
    marksample touse
    markout `touse' `w' `levels' `obltime', strok
    quietly {
        replace `touse' = 0 if `w' == 0
        summarize `varlist' [aw = `w'] if `touse'
        local m = r(mean)
        return scalar N    = r(N)
        return scalar mean = r(mean)
        tempvar d prev mt e ot sw swx mL
        gen double `d' = (`varlist' - `m')^2 if `touse'
        summarize `d' [aw = `w'] if `touse'
        local V = r(mean)
        return scalar sd = sqrt(`V')
        gen double `prev' = `m'
        local k = 0
        foreach L of local levels {
            local ++k
            capture drop `sw' `swx' `mL'
            bysort `L': egen double `sw'  = total(cond(`touse', `w', 0))
            bysort `L': egen double `swx' = total(cond(`touse', `w' * `varlist', 0))
            gen double `mL' = `swx' / `sw'
            replace `d' = (`mL' - `prev')^2 if `touse'
            summarize `d' [aw = `w'] if `touse'
            return scalar b`k' = 100 * r(mean) / `V'
            replace `prev' = `mL'
        }
        replace `d' = (`varlist' - `prev')^2 if `touse'
        summarize `d' [aw = `w'] if `touse'
        return scalar within = 100 * r(mean) / `V'
        * two-way demeaned
        capture drop `sw' `swx'
        bysort `time': egen double `sw'  = total(cond(`touse', `w', 0))
        bysort `time': egen double `swx' = total(cond(`touse', `w' * `varlist', 0))
        gen double `mt' = `swx' / `sw'
        replace `d' = (`varlist' - `prev' - `mt' + `m')^2 if `touse'
        summarize `d' [aw = `w'] if `touse'
        return scalar twoway = 100 * r(mean) / `V'
        * within oblast x month
        capture drop `sw' `swx'
        bysort `obltime': egen double `sw'  = total(cond(`touse', `w', 0))
        bysort `obltime': egen double `swx' = total(cond(`touse', `w' * `varlist', 0))
        gen double `ot' = `swx' / `sw'
        replace `d' = (`varlist' - `ot')^2 if `touse'
        summarize `d' [aw = `w'] if `touse'
        return scalar ot_sd = sqrt(r(mean))
        return scalar ot_share = 100 * r(mean) / `V'
    }
end

tempname pf
tempfile dec
postfile `pf' str24 measure str40 panel N mean sd b_obl b_raion b_city within twoway ot_sd ///
    using `dec', replace
local mlab_alarm  "Alarm days"
local mlab_attack "Attack days"
local mlab_front  "Front proximity (-ln km)"

use "$tmpe/04e_raion_month.dta" if war, clear
gen byte w_eq = 1
foreach w in w_eq pop {
    local pl = cond("`w'" == "w_eq", "Raion-month, equal weights", "Raion-month, population")
    foreach v in alarm attack front {
        vardec `v', w(`w') levels(oblast raion_pcode) time(month) obltime(oblast month)
        post `pf' ("`mlab_`v''") ("`pl'") (r(N)) (r(mean)) (r(sd)) (r(b1)) (r(b2)) (.) ///
            (r(within)) (r(twoway)) (r(ot_sd))
    }
}
use "$tmpe/04e_city_month.dta" if war & raion_pcode != "", clear
foreach w in vac2021 vac_est {
    local pl = cond("`w'" == "vac2021", "City-month, 2021 vacancies", "City-month, vacancies of the month")
    foreach v in alarm attack front {
        vardec `v', w(`w') levels(oblast raion_pcode city_id) time(month) obltime(oblast month)
        post `pf' ("`mlab_`v''") ("`pl'") (r(N)) (r(mean)) (r(sd)) (r(b1)) (r(b2)) (r(b3)) ///
            (r(within)) (r(twoway)) (r(ot_sd))
    }
}
postclose `pf'
use `dec', clear
format N %9.0fc
format mean sd ot_sd %6.2f
format b_* within twoway %5.1f
label var measure "Measure"
label var panel   "Unit, weights"
label var N       "Unit-months"
label var mean    "Mean"
label var sd      "SD"
label var b_obl   "Between oblasts, %"
label var b_raion "Between raions in oblast, %"
label var b_city  "Between cities in raion, %"
label var within  "Within unit over time, %"
label var twoway  "Left after unit and month means, %"
label var ot_sd   "SD within oblast x month"
list, noobs sep(3) abbrev(12)
export_table using "$tab/04e_variance_decomposition", ///
    title("Within/between decomposition of the exposure measures, Mar 2022 - Aug 2026")

* 5b. How the cross-sectional spread changes: SD across raions and SD within oblast x
*     month, by month (population weights). Output: 04e_spread_over_time.pdf
use "$tmpe/04e_raion_month.dta" if war, clear
foreach v in alarm attack front {
    bysort month: egen double sw_ = total(cond(`v' < ., pop, 0))
    bysort month: egen double swx_ = total(cond(`v' < ., pop * `v', 0))
    gen double m_`v' = swx_ / sw_
    drop sw_ swx_
    bysort oblast month: egen double sw_ = total(cond(`v' < ., pop, 0))
    bysort oblast month: egen double swx_ = total(cond(`v' < ., pop * `v', 0))
    gen double om_`v' = swx_ / sw_
    drop sw_ swx_
    gen double d_`v'  = (`v' - m_`v')^2
    gen double dw_`v' = (`v' - om_`v')^2
}
collapse (mean) d_* dw_* [aw = pop], by(month)
foreach v in alarm attack front {
    gen double sd_`v'  = sqrt(d_`v')
    gen double sdw_`v' = sqrt(dw_`v')
}
keep month sd_* sdw_*
export delimited using "$tmpe/04e_spread_over_time.csv", replace
local k = 0
local lg legend(order(1 "Across raions" 2 "Within oblast x month") cols(1) ring(0) position(11) ///
    size(vsmall) region(lstyle(none) fcolor(none)))
foreach v in alarm attack front {
    local ++k
    twoway (line sd_`v' month, lcolor(navy) lwidth(medthick)) (line sdw_`v' month, lcolor(cranberry)), ///
        `tfmt' ylabel(, angle(0)) ytitle("SD") title("`mlab_`v''", size(medsmall)) ///
        `lg' name(s`k', replace) nodraw
    local lg legend(off)
}
graph combine s1 s2 s3, cols(3) xsize(11) ysize(3.6) ///
    note("Population-weighted SD across raions with a measure, by month; within oblast x month: deviations from the oblast's population-weighted mean.", size(vsmall))
graph export "$fig/04e_spread_over_time.pdf", replace
graph drop s1 s2 s3

* --- Step 6. Measurement: how different are the three measures? -------------------
* 6a. Correlations, raion-months of the war window with all three measures: pooled;
*     between (raion means); within (deviations from the raion mean); two-way demeaned
*     (also minus the national month mean). Pearson and Spearman (pooled, between).
*     City-month: the city versions (attack within 15 km, the city's own distance),
*     weighted by 2021 core vacancies (Pearson only). Output: 04e_correlations (.xlsx, .tex)
tempname pc
tempfile cor
postfile `pc' str40 sample str10 stat N r_aa r_af r_tf using `cor', replace

use "$tmpe/04e_raion_month.dta" if war & alarm < . & attack < . & front < ., clear
foreach v in alarm attack front {
    bysort raion_pcode: egen double rm_`v' = mean(`v')
    bysort month: egen double tm_`v' = mean(`v')
    summarize `v', meanonly
    gen double wi_`v' = `v' - rm_`v'
    gen double tw_`v' = `v' - rm_`v' - tm_`v' + r(mean)
}
quietly corr alarm attack front
matrix C = r(C)
post `pc' ("Raion-month, pooled") ("Pearson") (r(N)) (C[2,1]) (C[3,1]) (C[3,2])
quietly spearman alarm attack front, stats(rho)
matrix C = r(Rho)
post `pc' ("Raion-month, pooled") ("Spearman") (r(N)) (C[2,1]) (C[3,1]) (C[3,2])
quietly corr wi_alarm wi_attack wi_front
matrix C = r(C)
post `pc' ("Raion-month, within raion") ("Pearson") (r(N)) (C[2,1]) (C[3,1]) (C[3,2])
quietly corr tw_alarm tw_attack tw_front
matrix C = r(C)
post `pc' ("Raion-month, two-way demeaned") ("Pearson") (r(N)) (C[2,1]) (C[3,1]) (C[3,2])
preserve
    collapse (mean) alarm attack front (first) pop, by(raion_pcode)
    quietly corr alarm attack front
    matrix C = r(C)
    post `pc' ("Raion means (between)") ("Pearson") (r(N)) (C[2,1]) (C[3,1]) (C[3,2])
    quietly spearman alarm attack front, stats(rho)
    matrix C = r(Rho)
    post `pc' ("Raion means (between)") ("Spearman") (r(N)) (C[2,1]) (C[3,1]) (C[3,2])
    quietly corr alarm attack front [aw = pop]
    matrix C = r(C)
    post `pc' ("Raion means, population-weighted") ("Pearson") (r(N)) (C[2,1]) (C[3,1]) (C[3,2])
restore
use "$tmpe/04e_city_month.dta" if war & alarm < . & attack < . & front < . & vac2021 > 0, clear
quietly corr alarm attack front [aw = vac2021]
matrix C = r(C)
post `pc' ("City-month, 2021 vacancies") ("Pearson") (r(N)) (C[2,1]) (C[3,1]) (C[3,2])
quietly corr alarm attack front
matrix C = r(C)
post `pc' ("City-month, cities with 2021 vacancies") ("Pearson") (r(N)) (C[2,1]) (C[3,1]) (C[3,2])
postclose `pc'
use `cor', clear
format N %9.0fc
format r_* %5.2f
label var sample "Sample"
label var stat   "Statistic"
label var N      "Obs."
label var r_aa   "Alarm - attack"
label var r_af   "Alarm - front"
label var r_tf   "Attack - front"
list, noobs sep(0) abbrev(14)
export_table using "$tab/04e_correlations", ///
    title("Correlations between the exposure measures, Mar 2022 - Aug 2026")

* 6b. Do the measures flag the same raion-months as highly exposed? For each pair:
*     % of the high-A raion-months that are also high-B, and the Jaccard index (both /
*     either). Also raions (war-window means, top 20% of raions).
*     Output: 04e_high_overlap (.xlsx, .tex)
tempname po
tempfile ov
postfile `po' str28 unit str20 pair N n_a n_b both p_b_a p_a_b jacc using `ov', replace
use "$tmpe/04e_raion_month.dta" if war & alarm < . & attack < . & front < ., clear
preserve
    collapse (mean) alarm attack front, by(raion_pcode)
    foreach v in alarm attack front {
        _pctile `v', p($hi_pct)
        gen byte hi_`v' = `v' > r(r1)
    }
    tempfile rmeans
    save `rmeans'
restore
foreach u in rm r {
    if "`u'" == "r" use `rmeans', clear
    local ul = cond("`u'" == "rm", "Raion-months", "Raions (war-window means)")
    gen byte hi_all3 = hi_alarm & hi_attack & hi_front
    foreach p in "alarm attack" "alarm front" "attack front" {
        local a : word 1 of `p'
        local b : word 2 of `p'
        quietly count
        local N = r(N)
        quietly count if hi_`a'
        local na = r(N)
        quietly count if hi_`b'
        local nb = r(N)
        quietly count if hi_`a' & hi_`b'
        local nab = r(N)
        post `po' ("`ul'") ("`a' - `b'") (`N') (`na') (`nb') (`nab') (100 * `nab' / `na') ///
            (100 * `nab' / `nb') (100 * `nab' / (`na' + `nb' - `nab'))
    }
    quietly count if hi_alarm | hi_attack | hi_front
    local any = r(N)
    quietly count if hi_all3
    post `po' ("`ul'") ("all three") (_N) (.) (.) (r(N)) (.) (.) (100 * r(N) / `any')
}
postclose `po'
use `ov', clear
format N n_a n_b both %8.0fc
format p_b_a p_a_b jacc %5.1f
label var unit  "Unit"
label var pair  "Measures A - B"
label var N     "Units"
label var n_a   "High A"
label var n_b   "High B"
label var both  "High in both"
label var p_b_a "% of high A also high B"
label var p_a_b "% of high B also high A"
label var jacc  "Jaccard (both / either), %"
list, noobs sep(0) abbrev(14)
export_table using "$tab/04e_high_overlap", ///
    title("Overlap of high-exposure units across measures (top 20%), Mar 2022 - Aug 2026")

* 6c. Scatter of raion means over the war window, markers sized by population.
*     Output: 04e_measures_scatter.pdf
use "$tmpe/04e_raion_month.dta" if war, clear
collapse (mean) alarm attack front (first) pop oblast_en_map raion_en, by(raion_pcode)
gen double front_km = exp(-front)
twoway (scatter attack alarm [aw = pop], msymbol(Oh) mcolor(navy%60)), ytitle("Attack days per month") ///
    xtitle("Alarm days per month") ylabel(, angle(0)) title("A", size(medsmall)) name(p1, replace) nodraw
twoway (scatter front_km alarm [aw = pop], msymbol(Oh) mcolor(navy%60)), yscale(log reverse) ///
    ylabel(10 25 50 100 200 400 800, angle(0)) ytitle("Distance to front, km (log, reversed)") ///
    xtitle("Alarm days per month") title("B", size(medsmall)) name(p2, replace) nodraw
twoway (scatter front_km attack [aw = pop], msymbol(Oh) mcolor(navy%60)), yscale(log reverse) ///
    ylabel(10 25 50 100 200 400 800, angle(0)) ytitle("Distance to front, km (log, reversed)") ///
    xtitle("Attack days per month") title("C", size(medsmall)) name(p3, replace) nodraw
graph combine p1 p2 p3, cols(3) xsize(11) ysize(3.6) ///
    note("Raion means over Mar 2022 - Aug 2026 (months with a measure). Marker size: population (Jan 2022). Front: geometric mean distance of the raion's towns.", size(vsmall))
graph export "$fig/04e_measures_scatter.pdf", replace
graph drop p1 p2 p3

* 6d. Correlations across raions month by month (Pearson, raions with all three).
*     Output: 04e_corr_over_time.pdf; data in data/temp/descriptives/04e_corr_over_time.csv
use "$tmpe/04e_raion_month.dta" if war & alarm < . & attack < . & front < ., clear
tempname pt
tempfile ct
postfile `pt' month r_aa r_af r_tf N using `ct', replace
forvalues t = $war_from / $war_to {
    quietly corr alarm attack front if month == `t'
    matrix C = r(C)
    post `pt' (`t') (C[2,1]) (C[3,1]) (C[3,2]) (r(N))
}
postclose `pt'
use `ct', clear
format month %tmMon_CCYY
export delimited using "$tmpe/04e_corr_over_time.csv", replace
twoway (line r_aa month, lcolor(navy) lwidth(medthick)) (line r_af month, lcolor(cranberry) lwidth(medthick)) ///
    (line r_tf month, lcolor(dkorange) lwidth(medthick)), yline(0, lcolor(gs12)) ///
    xlabel(`=tm(2022m3)'(6)`=tm(2026m3)', format(%tmMon_YY)) xtitle("") ylabel(-0.2(0.2)1, angle(0)) ///
    ytitle("Correlation across raions") ///
    legend(order(1 "Alarm - attack" 2 "Alarm - front proximity" 3 "Attack - front proximity") rows(1) position(6)) ///
    note("Pearson correlation across raions with all three measures, each month (unweighted).", size(vsmall))
graph export "$fig/04e_corr_over_time.pdf", replace

* 6e. The most exposed raions by each measure (war-window means; raions with a measure
*     in at least half the months), with their rank on the other two. Top 10 of each.
*     Output: 04e_top_raions (.xlsx, .tex)
use "$tmpe/04e_raion_month.dta" if war, clear
collapse (mean) alarm attack front (count) n_a = alarm n_t = attack n_f = front ///
    n_m = month (first) pop oblast_en_map raion_en, by(raion_pcode)
foreach v in alarm attack front {
    local n = substr("`v'", 1, 1)
    if "`v'" == "attack" local n "t"
    replace `v' = . if n_`n' < n_m / 2
    egen int rk_`v' = rank(-`v'), unique
}
gen double front_km = exp(-front)
keep if rk_alarm <= 10 | rk_attack <= 10 | rk_front <= 10
egen double rk_mean = rowmean(rk_alarm rk_attack rk_front)
sort rk_mean
gen str60 raion = raion_en + " (" + oblast_en_map + ")"
keep raion alarm rk_alarm attack rk_attack front_km rk_front pop
replace pop = pop / 1000
order raion alarm rk_alarm attack rk_attack front_km rk_front pop
format alarm attack %5.1f
format front_km pop %6.0f
format rk_* %4.0f
label var raion     "Raion (oblast)"
label var alarm     "Alarm days per month"
label var rk_alarm  "Rank"
label var attack    "Attack days per month"
label var rk_attack "Rank "
label var front_km  "Distance to front, km"
label var rk_front  "Rank  "
label var pop       "Population, thousands"
list, noobs sep(0) abbrev(14)
export_table using "$tab/04e_top_raions", ///
    title("Most exposed raions by each measure (top 10 of each), means over Mar 2022 - Aug 2026, ranks among raions")

* --- Step 7. Sample: how much of this does robota.ua observe? -----------------------
* 7a. Coverage of the civilian core vacancies by year: which ones get each measure,
*     and why the others do not (mutually exclusive reasons, in this order).
*     (Jobs abroad are not in the civilian core.) Alarm: no raion (no map point or
*     region-wide entry) / month outside the war window (2021 - Feb 2022, Sep-Oct 2026) /
*     no alarm data (Crimea, Sevastopol, Luhansk) / occupied raion. VIINA city measures:
*     city without a map point / occupied city (or its place in the front set).
*     Output: 04e_sample_coverage (.xlsx, .tex)
use city_id raion_pcode oblast core weight ym using "$temp/descriptives_base.dta" if core, clear
keep if ym >= tm(2021m1)
rename ym month
gen int year = year(dofm(month))
merge m:1 raion_pcode month using "$data/alarms_raion_month.dta", ///
    keepusing(days_any occupied_raion) keep(master match) nogenerate
merge m:1 city_id month using "$tmpe/04e_city_month.dta", ///
    keepusing(front attack occupied_city city_place_held) keep(master match) generate(m_city)
merge m:1 raion_pcode using `raions', keepusing(no_alarm_data) keep(master match) nogenerate
gen byte abroad = oblast == "Інші країни"
gen byte a_ok      = days_any < . & inrange(month, $war_from, $war_to)
gen byte a_abroad  = abroad
gen byte a_noraion = !abroad & raion_pcode == ""
gen byte a_window  = !abroad & raion_pcode != "" & !inrange(month, $war_from, $war_to)
gen byte a_nodata  = !abroad & raion_pcode != "" & inrange(month, $war_from, $war_to) & no_alarm_data == 1
gen byte a_occ     = !abroad & raion_pcode != "" & inrange(month, $war_from, $war_to) & no_alarm_data != 1 & occupied_raion == 1
gen byte v_ok      = !abroad & front < .
gen byte v_nopoint = !abroad & m_city == 1
gen byte v_occ     = !abroad & m_city == 3 & front == .
assert a_abroad == 0                     // the core excludes jobs abroad (04, step 2)
assert a_ok + a_abroad + a_noraion + a_window + a_nodata + a_occ == 1
assert v_ok + abroad + v_nopoint + v_occ == 1
gen byte one = 1
collapse (rawsum) n = one (sum) est = one (mean) a_* v_ok v_nopoint v_occ [pw = weight], by(year)
foreach v of varlist a_* v_* {
    replace `v' = 100 * `v'
}
tostring year, replace
replace year = "2026 (Jan-Oct)" if year == "2026"
drop a_abroad
order year n est a_ok a_noraion a_window a_nodata a_occ v_ok v_nopoint v_occ
format n est %10.0fc
format a_* v_* %5.1f
label var year      "Year"
label var n         "Sampled core vacancies"
label var est       "Estimated"
label var a_ok      "With alarm measure, %"
label var a_noraion "No raion, %"
label var a_window  "Month without alarm data, %"
label var a_nodata  "Crimea/Luhansk (no data), %"
label var a_occ     "Occupied raion, %"
label var v_ok      "With front and attack measures, %"
label var v_nopoint "City without map point, %"
label var v_occ     "Occupied city, %"
list, noobs sep(0) abbrev(12)
export_transposed using "$tab/04e_sample_coverage", ///
    title("Civilian core vacancies: coverage of the exposure measures by year")

* 7b. Population against the sample, by year: share of the population and of core
*     vacancies in high-exposure raions; core vacancies per 10,000 residents per month
*     in high-exposure raions and in the others.
*     Output: 04e_population_vs_sample (.xlsx, .tex)
use "$tmpe/04e_raion_month.dta" if war, clear
tempname pp
tempfile pvs
postfile `pp' str24 year str24 measure pop_sh vac_sh vac2021_sh rate_hi rate_lo using `pvs', replace
foreach v in alarm attack front {
    foreach y in 2022 2023 2024 2025 2026 all {
        preserve
            keep if `v' < .
            if "`y'" != "all" keep if year == `y'
            collapse (sum) pop vac_est vac2021, by(hi_`v')
            quietly summarize pop
            local tp = r(sum)
            quietly summarize vac_est
            local tv = r(sum)
            quietly summarize vac2021
            local t21 = r(sum)
            quietly summarize pop if hi_`v' == 1
            local hp = r(sum)
            quietly summarize vac_est if hi_`v' == 1
            local hv = r(sum)
            quietly summarize vac2021 if hi_`v' == 1
            local h21 = r(sum)
            local yl = cond("`y'" == "all", "Mar 2022 - Aug 2026", "`yrlab_`y''")
            post `pp' ("`yl'") ("`mlab_`v''") (100 * `hp' / `tp') (100 * `hv' / `tv') ///
                (100 * `h21' / `t21') (1e4 * `hv' / `hp') (1e4 * (`tv' - `hv') / (`tp' - `hp'))
        restore
    }
}
postclose `pp'
use `pvs', clear
* rates: vacancies summed over raion-months / residents summed over raion-months, i.e.
* monthly vacancies per 10,000 residents
format pop_sh vac_sh vac2021_sh %5.1f
format rate_hi rate_lo %6.1f
label var year       "Period"
label var measure    "High exposure by"
label var pop_sh     "Population in high raions, %"
label var vac_sh     "Core vacancies in high raions, %"
label var vac2021_sh "2021 vacancies of those raions, %"
label var rate_hi    "Vacancies per 10k residents, high"
label var rate_lo    "Vacancies per 10k residents, other"
list, noobs sep(6) abbrev(14)
export_transposed using "$tab/04e_population_vs_sample", panel(measure) ///
    title("Population and civilian core vacancies in high-exposure raion-months (monthly vacancies per 10,000 residents)")

* 7c. Empty cells: raion-months of the war window by quintile of each measure (pooled,
*     raion-months with a measure): % with no sampled core vacancy, median sampled
*     vacancies, and the shares of population and vacancies.
*     Output: 04e_cells_by_quintile (.xlsx, .tex)
use "$tmpe/04e_raion_month.dta" if war, clear
tempname pq
tempfile cq
postfile `pq' str24 measure q n_cells cut_lo cut_hi zero p50_n lt10 pop_sh vac_sh using `cq', replace
foreach v in alarm attack front {
    preserve
        keep if `v' < .
        xtile q = `v', nq(5)
        quietly summarize pop
        local tp = r(sum)
        quietly summarize vac_est
        local tv = r(sum)
        levelsof q, local(qs)
        foreach k of local qs {
            quietly summarize `v' if q == `k'
            local lo = r(min)
            local hi = r(max)
            quietly count if q == `k'
            local nc = r(N)
            quietly count if q == `k' & vac_n == 0
            local z = r(N)
            quietly count if q == `k' & vac_n < 10
            local l10 = r(N)
            quietly summarize vac_n if q == `k', detail
            local med = r(p50)
            quietly summarize pop if q == `k'
            local ps = r(sum)
            quietly summarize vac_est if q == `k'
            local vs = r(sum)
            post `pq' ("`mlab_`v''") (`k') (`nc') (`lo') (`hi') (100 * `z' / `nc') (`med') ///
                (100 * `l10' / `nc') (100 * `ps' / `tp') (100 * `vs' / `tv')
        }
    restore
}
postclose `pq'
use `cq', clear
format q n_cells %6.0f
format cut_lo cut_hi %6.2f
format zero lt10 pop_sh vac_sh %5.1f
format p50_n %5.0f
label var measure "Measure"
label var q       "Quintile"
label var n_cells "Raion-months"
label var cut_lo  "From"
label var cut_hi  "To"
label var zero    "No sampled vacancy, %"
label var p50_n   "Median sampled vacancies"
label var lt10    "Fewer than 10 sampled, %"
label var pop_sh  "Population (raion-months), %"
label var vac_sh  "Core vacancies, %"
list, noobs sep(5) abbrev(14)
export_table using "$tab/04e_cells_by_quintile", ///
    title("Raion-months by quintile of each measure: sampled core vacancies per cell, Mar 2022 - Aug 2026")

* 7d. Occupation: raions and population under occupation, partly occupied raions, and
*     core vacancies posted in occupied raions or cities, by year.
*     Output: 04e_occupation_diagnostics (.xlsx, .tex)
use "$tmpe/04e_raion_month.dta" if month >= tm(2022m3), clear
gen byte partly = occ_share > 0 & occ_share <= 0.5 & occ_share < . & !occupied_raion
gen double pop_occ = pop * occupied_raion
gen double pop_partly = pop * partly
gen double vac_occ = vac_est * occupied_raion
gen double vac_partly = vac_est * partly
collapse (sum) occupied_raion partly pop_occ pop_partly pop vac_occ vac_partly vac_est ///
    (count) n_months = month, by(year raion_pcode)
collapse (sum) occupied_raion partly pop_occ pop_partly pop vac_occ vac_partly vac_est ///
    (max) n_months, by(year)
gen double r_occ    = occupied_raion / n_months
gen double r_partly = partly / n_months
gen double sh_pop_occ    = 100 * pop_occ / pop
gen double sh_pop_partly = 100 * pop_partly / pop
gen double sh_vac_partly = 100 * vac_partly / vac_est
keep year r_occ sh_pop_occ r_partly sh_pop_partly sh_vac_partly vac_occ
tempfile occ_r
save `occ_r'
use "$tmpe/04e_city_month.dta" if month >= tm(2022m3), clear
gen double vac_city_occ = vac_est * (occupied_city | city_place_held)
gen byte city_occ_w_vac = (occupied_city | city_place_held) & vac_n > 0
collapse (sum) vac_city_occ city_occ_w_vac, by(year)
merge 1:1 year using `occ_r', nogenerate
tostring year, replace
replace year = "2022 (Mar-Dec)" if year == "2022"
replace year = "2026 (Jan-Oct)" if year == "2026"
order year r_occ sh_pop_occ r_partly sh_pop_partly sh_vac_partly vac_occ vac_city_occ city_occ_w_vac
format r_occ r_partly %5.1f
format sh_* %5.1f
format vac_occ vac_city_occ city_occ_w_vac %8.0fc
label var year           "Year"
label var r_occ          "Occupied raions (monthly avg.)"
label var sh_pop_occ     "Pop. in occupied raions, %"
label var r_partly       "Partly occupied raions (avg.)"
label var sh_pop_partly  "Pop. in partly occupied, %"
label var sh_vac_partly  "Core vacancies in partly occupied, %"
label var vac_occ        "Core vacancies in occupied raions"
label var vac_city_occ   "Core vacancies in occupied cities"
label var city_occ_w_vac "Occupied city-months with a vacancy"
list, noobs sep(0) abbrev(14)
export_transposed using "$tab/04e_occupation_diagnostics", ///
    title("Occupation: raions and population under occupation, and core vacancies posted there, by year")

log close
