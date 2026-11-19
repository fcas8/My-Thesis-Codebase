* =============================================================================
* 06_designs.do  --  main designs D1-D3: vacancy posting and three exposure measures
*
* Three PPML designs with time-varying exposure (Paper/main.tex, section "Empirical
* strategy"; first written down in Meetings/identification_designs.tex):
*   D1  regional          E[Y_lt]  = exp(a_l  + d_t  + b E_lt)
*   D2  within-employer   E[Y_it]  = exp(a_i  + d_t  + b E_it),  E_it = sum_l w_il E_lt
*   D3  within-employer,  E[Y_ilt] = exp(a_il + g_it + b E_lt)
*       across locations
* One table per design. Columns: three exposure measures, each with two sets of fixed
* effects:
*   alarms    share of the quarter's days with an alarm anywhere in the raion
*             (location l = raion)
*   front     proximity to the front, -ln(km to the nearest Russian-held place),
*             quarterly mean of the monthly value (location l = city)
*   attacks   share of the quarter's days with an attack (shelling, airstrike, drone)
*             within 15 km of the city (location l = city)
*
* Input : data/analysis/robota_vacancies_clean.dta   (01_clean.do)
*         data/temp/robota_city_raion.csv            (00_city_raion.py: city -> raion)
*         data/analysis/alarms_raion_month.dta       (03 step B3: raion x month)
*         data/analysis/viina_city_month.dta         (03 step V2: city x month)
* Output: output/tables/06_d1.xlsx/.tex              D1, all three measures
*         output/tables/06_d2.xlsx/.tex              D2
*         output/tables/06_d3.xlsx/.tex              D3
*         output/figures/06_coefplot.pdf             all estimates, effect in % with 95% CI
*         data/temp/designs/06_estimates.dta         every estimate, one row per column
*         data/temp/designs/06_panel_d1_raion.dta    estimation panels (read by
*         data/temp/designs/06_panel_d1_city.dta       07_decomposition.do); D1 panels
*         data/temp/designs/06_panel_d2.dta            also count employers posting
*         data/temp/designs/06_panel_d3_raion.dta      (n_emp)
*         data/temp/designs/06_panel_d3_city.dta
*         data/temp/designs/06_exposure_raion_q.dta  alarms, raion x quarter
*         data/temp/designs/06_exposure_city_q.dta   front and attacks, city x quarter
*         data/temp/logs/06_designs.log
*         Every output is listed in output_inventory.xlsx (Project folder).
*
* Choices (Step 0; 15 Nov 2026):
*   - Sample: civilian core vacancies only (same groups as 04_descriptives.do: no
*     likely re-ads, employment-center reposts, jobs abroad or military employers).
*     D2 and D3 also drop postings without an employer id and recruitment agencies.
*   - Outcome Y: number of SAMPLED postings created in the cell (creation date). The
*     sampling fraction is a constant, absorbed by the fixed effects in PPML, so no
*     weights. Zeros are kept: panels are balanced.
*   - Period t: quarter, 2020q4 - 2026q2 (23 quarters) for all measures. The official
*     alarm series ends 7 Sep 2026, so 2026q3 is incomplete and dropped.
*   - Alarms (raion): days with an alarm anywhere in the raion (days_any, 03 step B3)
*     summed over the quarter / calendar days of the quarter. 0 before the invasion;
*     days before 25 Feb 2022 count as days without alarms (2022q1 partly treated).
*     Missing for raions without alarm data (Crimea, Sevastopol, Luhansk) and occupied
*     raions in any month of the quarter.
*   - Front (city): mean over the quarter's months of front_proximity (03 step V2c).
*     Before the invasion it is the distance to the 2014 line; VIINA starts in Jan 2021,
*     so 2020q4 takes the Jan 2021 value (the 2014 line did not move).
*     Interpretation: +ln 2 = distance halved.
*   - Attacks (city): attack days within 15 km summed over the quarter / calendar days
*     of the quarter. 0 before 24 Feb 2022 (VIINA events start then; 2020q4 set to 0).
*   - Front and attacks are missing for a city occupied (or whose own place is Russian-
*     held) in any month of the quarter. Cities without a point (no VIINA measure):
*     their postings are dropped from the front and attacks columns.
*   - Units missing in every war quarter are dropped from all quarters.
*   - D2: employers (no agencies) with >= 3 core postings created before 24 Feb 2022
*     with a known raion: the same employers in every column. w_il = share of those
*     postings in location l (raion for alarms, city for front and attacks), fixed.
*     E_it = w-weighted mean over the locations with exposure, missing if those carry
*     less than half the weight. Y_it counts the employer's postings in all locations.
*   - D3: employers with >= 3 pre-war postings in >= 2 locations (raions for alarms,
*     cities for front and attacks); location set = the pre-war one (postings in new
*     locations are left out). Panel employer x pre-war location x quarter.
*   - Size band x quarter fixed effects in every column (16 Nov 2026): pre-war
*     population band of the location (GeoNames population of the city's VIINA
*     settlement: unknown/0, <10k, 10-50k, 50-200k, 200k-1M, >=1M; a raion takes the
*     band of its largest city; D2: band of the employer's main pre-war city). They
*     nest the quarter effects and absorb time paths that differ by city size: news
*     coverage of big cities in VIINA, demand moving to big cities. (Without them, D3
*     attacks came out positive: +0.32***/+0.36***; checks of 16 Nov 2026.)
*   - Fixed effects, second column of each measure: D1 and D3 add oblast x quarter
*     (oblast of the location); D2 adds employer-sector x quarter
*     (sector = most frequent employer industry, branch_id).
*   - Inference: clustered by raion for all columns (D2: the employer's main pre-war
*     raion), so that nearby cities sharing a shock are in one cluster. Placebo checks
*     (13 Nov 2026) found employer clustering over-rejects. Stars: normal p-values from
*     the clustered SE; randomization inference still to do.
*   - Robustness (oblast level, hours under alarm) left out for now.
*
* Needs: ppmlhdfe, reghdfe, ftools (ssc install ...)
* Run after 03_exposure_build.do (00_main.do runs it after 05). Takes ~25 min.
* =============================================================================

clear all
set more off
set linesize 200

* --- Step 0. Paths and settings ---------------------------------------------
if "$project" == "" global project "`c(pwd)'/.."   // set by 00_main.do; else run from the repo root
global data    "$project/Project/data/analysis"
global xwalk   "$project/Project/data/crosswalks"
global temp    "$project/Project/data/temp"
global tab     "$project/Project/output/tables"          // final tables only
global fig     "$project/Project/output/figures"
global tmp6    "$project/Project/data/temp/designs"      // everything else from this file
global do      "$project/Project/do"

global q_first = tq(2020q4)      // first full quarter in the sample
global q_last  = tq(2026q2)      // last quarter with alarm data for all its days
global inv_day = td(24feb2022)   // pre-war footprint: postings created before this day
global min_pre = 3               // D2, D3: minimum pre-war postings with a location

cap mkdir "$tmp6"
cap mkdir "$temp/logs"
cap log close
log using "$temp/logs/06_designs.log", replace text

do "$do/00_programs.do"


* --- Step 1. Alarms, raion x quarter ------------------------------------------
* From the balanced raion x month file (Feb 2022 - Aug 2026). days_any is already
* missing for raions without alarm data and for occupied raion-months.
use raion_pcode month days_any using "$data/alarms_raion_month.dta", clear
gen q = qofd(dofm(month))
keep if inrange(q, $q_first, $q_last)
gen byte miss = days_any == .
collapse (sum) days_any (max) miss, by(raion_pcode q)
gen days_q = dofq(q + 1) - dofq(q)                // calendar days (Jan 2022 not in the file: 0)
gen double alarms = days_any / days_q
replace alarms = . if miss
tempfile war
save `war'

* pre-war quarters: 0, except raions without alarm data
use raion_pcode no_alarm_data using "$xwalk/geo_raions.dta", clear
expand tq(2021q4) - $q_first + 1
bysort raion_pcode: gen q = $q_first + _n - 1
gen double alarms = cond(no_alarm_data, ., 0)
append using `war'
bysort raion_pcode: egen n_war = count(alarms) if q >= tq(2022q1)
bysort raion_pcode (n_war): replace n_war = n_war[1]
replace alarms = . if n_war == 0
keep raion_pcode q alarms
format q %tq
label var q      "Quarter"
label var alarms "Share of the quarter's days with an alarm anywhere in the raion"
isid raion_pcode q
save "$tmp6/06_exposure_raion_q.dta", replace

* --- Step 2. Front and attacks, city x quarter ---------------------------------
use city_id month front_proximity attack_days_near using "$data/viina_city_month.dta", clear
* 2020q4: Jan 2021 values (front: 2014 line; attacks: 0)
preserve
    keep if month == tm(2021m1)
    expand 3
    bysort city_id: replace month = tm(2020m10) + _n - 1
    tempfile q2020
    save `q2020'
restore
append using `q2020'
gen q = qofd(dofm(month))
keep if inrange(q, $q_first, $q_last)
gen byte miss = front_proximity == . | attack_days_near == .
collapse (mean) front = front_proximity (sum) attack_days = attack_days_near ///
    (max) miss (count) n_months = month, by(city_id q)
assert n_months == 3
gen days_q = dofq(q + 1) - dofq(q)
gen double attacks = attack_days / days_q
replace front   = . if miss
replace attacks = . if miss
bysort city_id: egen n_war = count(front) if q >= tq(2022q1)
bysort city_id (n_war): replace n_war = n_war[1]
replace front   = . if n_war == 0
replace attacks = . if n_war == 0
keep city_id q front attacks
format q %tq
label var q       "Quarter"
label var front   "Proximity to the front, -ln(km to the nearest Russian-held place), mean"
label var attacks "Share of the quarter's days with an attack within 15 km"
isid city_id q
save "$tmp6/06_exposure_city_q.dta", replace

* exposure summary, war quarters
use "$tmp6/06_exposure_raion_q.dta", clear
tabstat alarms if q >= tq(2022q2), by(q) stats(n mean sd min max) format(%5.2f)
use "$tmp6/06_exposure_city_q.dta", clear
tabstat front attacks if q >= tq(2022q2), by(q) stats(n mean sd) format(%5.2f)


* --- Step 3. Civilian core vacancies, located ------------------------------------
import delimited using "$temp/robota_city_raion.csv", varnames(1) stringcols(6) clear
keep city_id raion_pcode
tempfile cityraion
save `cityraion'

* cities with a VIINA measure
use "$tmp6/06_exposure_city_q.dta", clear
keep city_id
duplicates drop
gen byte city_viina = 1
tempfile cityviina
save `cityviina'

use id created_date city_id notebook_id is_agency ses_posting readvert military ///
    oblast branch_id using "$data/robota_vacancies_clean.dta", clear
gen q = qofd(created_date)
keep if inrange(q, $q_first, $q_last)
* civilian core (04_descriptives.do step 2)
gen byte core = !(readvert == 1 | ses_posting == 1 | oblast == "Інші країни" | military == 1)
tab core
keep if core
merge m:1 city_id using `cityraion', keep(master match) nogenerate
merge m:1 city_id using `cityviina', keep(master match) nogenerate
replace raion_pcode = "" if raion_pcode == "."
replace city_viina = 0 if city_viina == .
gen byte prewar = created_date < $inv_day
count if raion_pcode == ""
display as text "core postings without a raion: " r(N) " of " _N
count if !city_viina
display as text "core postings in a city without a VIINA measure: " r(N) " of " _N
* city id only where the city has a VIINA measure (the location of front and attacks)
gen city = city_id if city_viina
* employer sector: the most frequent industry of the employer's postings
bysort notebook_id: egen sector = mode(branch_id), minmode
replace sector = . if notebook_id == .
keep id q notebook_id is_agency raion_pcode city prewar sector
format q %tq
tempfile vac
save `vac'

* raion and oblast of each city (oblast x quarter FE and clusters in city panels)
use `cityraion', clear
rename city_id city
replace raion_pcode = "" if raion_pcode == "."
rename raion_pcode city_raion
* pre-war population band of each city (GeoNames population of its VIINA settlement;
* 0 = unknown, mostly villages): absorbs time paths that differ by city size (news
* coverage of big cities, demand moving to big cities)
preserve
    import delimited using "$temp/viina_settlements.csv", varnames(1) clear
    keep geonameid population
    tempfile setpop
    save `setpop'
    import delimited using "$temp/viina_city_settlement.csv", varnames(1) clear
    merge m:1 geonameid using `setpop', keep(master match) nogenerate
    rename city_id city
    keep city population
    tempfile citypop
    save `citypop'
restore
merge 1:1 city using `citypop', keep(master match) nogenerate
gen byte size_bin = 0
replace size_bin = 1 if population > 0 & population < 10000
replace size_bin = 2 if population >= 10000 & population < 50000
replace size_bin = 3 if population >= 50000 & population < 200000
replace size_bin = 4 if population >= 200000 & population < 1000000
replace size_bin = 5 if population >= 1000000 & population < .
label define size_lbl 0 "unknown (0)" 1 "< 10k" 2 "10-50k" 3 "50-200k" 4 "200k-1M" 5 ">= 1M"
label values size_bin size_lbl
tab size_bin
tempfile city_geo
save `city_geo'

* band of a raion = band of its largest city
use `city_geo' if city_raion != "", clear
collapse (max) population, by(city_raion)
rename city_raion raion_pcode
gen byte size_bin = 0
replace size_bin = 1 if population > 0 & population < 10000
replace size_bin = 2 if population >= 10000 & population < 50000
replace size_bin = 3 if population >= 50000 & population < 200000
replace size_bin = 4 if population >= 200000 & population < 1000000
replace size_bin = 5 if population >= 1000000 & population < .
tab size_bin
keep raion_pcode size_bin
tempfile raion_size
save `raion_size'


* --- Programs ------------------------------------------------------------------
* est_ppml: run one PPML column on exposure variable x and post its results.
*   est_ppml <col> , table() measure() x() ulabel() y() cl() uvar() absorb() fe()
*   ulabel() = what a unit is (text); uvar() = variable identifying the units;
*   cl() = cluster variable; fe() = short names of the fixed effects in the column.
capture program drop est_ppml
program define est_ppml
    syntax anything(name=col), Table(string) Measure(string) X(varname) ULabel(string) ///
        Y(varname) CL(varname) UVar(varname) Absorb(string) FE(string)
    ppmlhdfe `y' `x', absorb(`absorb') vce(cluster `cl')
    tempvar smp tag rr
    gen byte `smp' = e(sample)
    local b  = _b[`x']
    local se = _se[`x']
    local N  = e(N)
    local nc = e(N_clust)
    egen `tag' = tag(`uvar') if `smp'
    quietly count if `tag' == 1
    local nu = r(N)
    quietly summarize `y' if `smp'
    local npost = r(sum)
    * how much exposure is left after the fixed effects (identifying variation)
    quietly reghdfe `x' if `smp', absorb(`absorb') resid(`rr')
    quietly summarize `rr' if `smp'
    local sdE = r(sd)
    post est_post (`col') ("`table'") ("`measure'") ("`ulabel'") (`b') (`se') (`N') ///
        (`nu') (`nc') (`npost') (`sdE') ("`fe'")
end

postfile est_post col str4 table str8 measure str24 unit double(b se) long(N n_units ///
    n_clust n_postings) double(sd_E_resid) str80 fe ///
    using "$tmp6/06_estimates.dta", replace


* --- Step 4. D1: location x quarter -----------------------------------------------
* Counts per location-quarter: postings y and employers posting n_emp (employers with an
* id; n_emp is used by the margins decomposition, 07_decomposition.do).
* 4a. Alarms: raion x quarter
use `vac' if raion_pcode != "", clear
bysort raion_pcode q notebook_id: gen byte first_emp = _n == 1 & notebook_id < .
collapse (count) y = id (sum) n_emp = first_emp, by(raion_pcode q)
tempfile cnt
save `cnt'
use "$tmp6/06_exposure_raion_q.dta", clear
merge 1:1 raion_pcode q using `cnt', keep(master match) nogenerate
replace y = 0 if y == .
replace n_emp = 0 if n_emp == .
merge m:1 raion_pcode using `raion_size', keep(master match) nogenerate
replace size_bin = 0 if size_bin == .
egen loc    = group(raion_pcode)
gen oblast_pcode = substr(raion_pcode, 1, 4)
egen obl_q  = group(oblast_pcode q)
egen size_q = group(size_bin q)
save "$tmp6/06_panel_d1_raion.dta", replace
est_ppml 1, table(D1) measure(alarms) x(alarms) ulabel(raion) y(y) cl(loc) uvar(loc) ///
    absorb(loc size_q) fe(loc sizeq)
est_ppml 2, table(D1) measure(alarms) x(alarms) ulabel(raion) y(y) cl(loc) uvar(loc) ///
    absorb(loc obl_q size_q) fe(loc oblq sizeq)

* 4b. Front and attacks: city x quarter
use `vac' if city < ., clear
bysort city q notebook_id: gen byte first_emp = _n == 1 & notebook_id < .
collapse (count) y = id (sum) n_emp = first_emp, by(city q)
save `cnt', replace
use "$tmp6/06_exposure_city_q.dta", clear
rename city_id city
merge 1:1 city q using `cnt', keep(master match) nogenerate
replace y = 0 if y == .
replace n_emp = 0 if n_emp == .
merge m:1 city using `city_geo', keep(master match) nogenerate
egen loc   = group(city)
egen cl    = group(city_raion)
gen oblast_pcode = substr(city_raion, 1, 4)
egen obl_q = group(oblast_pcode q)
egen size_q = group(size_bin q)
save "$tmp6/06_panel_d1_city.dta", replace
local c = 3
foreach m in front attacks {
    est_ppml `c', table(D1) measure(`m') x(`m') ulabel(city) y(y) cl(cl) uvar(loc) ///
        absorb(loc size_q) fe(loc sizeq)
    local ++c
    est_ppml `c', table(D1) measure(`m') x(`m') ulabel(city) y(y) cl(cl) uvar(loc) ///
        absorb(loc obl_q size_q) fe(loc oblq sizeq)
    local ++c
}


* --- Step 5. D2: employer x quarter, exposure of the pre-war footprint ---------------
* 5a. Sample and main raion (for clusters): >= min_pre pre-war postings with a raion
use `vac' if notebook_id < . & is_agency == 0 & prewar & raion_pcode != "", clear
bysort notebook_id: gen n_pre = _N
keep if n_pre >= $min_pre
tempfile prewar_post
save `prewar_post'
collapse (count) n_l = id, by(notebook_id raion_pcode)
gen negn = -n_l
bysort notebook_id (negn raion_pcode): keep if _n == 1
keep notebook_id raion_pcode
rename raion_pcode main_raion
* size band of the employer's main pre-war city (most pre-war postings)
preserve
    use `prewar_post' if city < ., clear
    collapse (count) n_c = id, by(notebook_id city)
    gen negc = -n_c
    bysort notebook_id (negc city): keep if _n == 1
    merge m:1 city using `city_geo', keepusing(size_bin) keep(master match) nogenerate
    keep notebook_id size_bin
    tempfile emp_size
    save `emp_size'
restore
merge 1:1 notebook_id using `emp_size', keep(master match) nogenerate
replace size_bin = 0 if size_bin == .
tempfile d2_emp
save `d2_emp'

* 5b. Employer x quarter counts, all locations
use `vac' if notebook_id < . & is_agency == 0, clear
merge m:1 notebook_id using `d2_emp', keep(match) nogenerate
collapse (count) y = id (first) sector main_raion, by(notebook_id q)
tempfile d2_cnt
save `d2_cnt'

* 5c. Footprint exposure: E_it = sum_l w_il E_lt over locations with exposure
*     (alarms over raions; front and attacks over cities)
local nq = $q_last - $q_first + 1
foreach lev in raion city {
    use `prewar_post', clear
    if "`lev'" == "city" keep if city < .
    gen n_tot = n_pre                  // weights over ALL the employer's pre-war postings
    local lvar = cond("`lev'" == "raion", "raion_pcode", "city")
    rename `lvar' loc
    collapse (count) n_l = id (first) n_tot, by(notebook_id loc)
    gen double w = n_l / n_tot
    expand `nq'
    bysort notebook_id loc: gen q = $q_first + _n - 1
    if "`lev'" == "raion" {
        rename loc raion_pcode
        merge m:1 raion_pcode q using "$tmp6/06_exposure_raion_q.dta", keep(master match) nogenerate
        local ms alarms
    }
    else {
        rename loc city_id
        merge m:1 city_id q using "$tmp6/06_exposure_city_q.dta", keep(master match) nogenerate
        local ms front attacks
    }
    foreach m of local ms {
        gen double wE_`m' = w * `m'
        gen double wok_`m' = w * (`m' < .)
    }
    collapse (sum) wE_* wok_*, by(notebook_id q)
    foreach m of local ms {
        gen double `m' = wE_`m' / wok_`m'
        replace `m' = . if wok_`m' < 0.5
    }
    keep notebook_id q `ms'
    tempfile d2_`lev'
    save `d2_`lev''
}

* 5d. Panel and estimates
use `d2_emp', clear
expand `nq'
bysort notebook_id: gen q = $q_first + _n - 1
merge 1:1 notebook_id q using `d2_cnt', keepusing(y sector) keep(master match) nogenerate
replace y = 0 if y == .
bysort notebook_id (sector): replace sector = sector[1]
merge 1:1 notebook_id q using `d2_raion', keep(master match) nogenerate
merge 1:1 notebook_id q using `d2_city', keep(master match) nogenerate
egen cl    = group(main_raion)
egen sec_q  = group(sector q)
egen size_q = group(size_bin q)
save "$tmp6/06_panel_d2.dta", replace
local c = 1
foreach m in alarms front attacks {
    est_ppml `c', table(D2) measure(`m') x(`m') ulabel(employer) y(y) cl(cl) ///
        uvar(notebook_id) absorb(notebook_id size_q) fe(emp sizeq)
    local ++c
    est_ppml `c', table(D2) measure(`m') x(`m') ulabel(employer) y(y) cl(cl) ///
        uvar(notebook_id) absorb(notebook_id sec_q size_q) fe(emp secq sizeq)
    local ++c
}


* --- Step 6. D3: employer x pre-war location x quarter ------------------------------
local c = 1
foreach lev in raion city {
    local lv = cond("`lev'" == "raion", "raion_pcode", "city")
    use `vac' if notebook_id < . & is_agency == 0, clear
    if "`lev'" == "raion" drop if raion_pcode == ""
    else                  drop if city == .
    * employers with >= min_pre pre-war postings in >= 2 locations
    preserve
    keep if prewar
    bysort notebook_id: gen n_pre = _N
    bysort notebook_id `lv': gen byte first_l = _n == 1
    bysort notebook_id: egen n_loc = total(first_l)
    keep if n_pre >= $min_pre & n_loc >= 2
    contract notebook_id `lv'
    drop _freq
    tempfile locset
    save `locset'
    restore

    collapse (count) y = id, by(notebook_id `lv' q)
    tempfile cnt
    save `cnt'

    use `locset', clear
    expand `nq'
    bysort notebook_id `lv': gen q = $q_first + _n - 1
    merge 1:1 notebook_id `lv' q using `cnt', keep(master match) nogenerate
    replace y = 0 if y == .
    if "`lev'" == "raion" {
        merge m:1 raion_pcode q using "$tmp6/06_exposure_raion_q.dta", keep(master match) nogenerate
        merge m:1 raion_pcode using `raion_size', keep(master match) nogenerate
        gen loc_raion = raion_pcode
        local ms alarms
    }
    else {
        rename city city_id
        merge m:1 city_id q using "$tmp6/06_exposure_city_q.dta", keep(master match) nogenerate
        rename city_id city
        merge m:1 city using `city_geo', keep(master match) nogenerate
        gen loc_raion = city_raion
        local ms front attacks
    }
    egen emp_loc = group(notebook_id `lv')
    egen emp_q   = group(notebook_id q)
    egen cl      = group(loc_raion)
    gen oblast_pcode = substr(loc_raion, 1, 4)
    egen obl_q   = group(oblast_pcode q)
    replace size_bin = 0 if size_bin == .
    egen size_q  = group(size_bin q)
    save "$tmp6/06_panel_d3_`lev'.dta", replace
    foreach m of local ms {
        est_ppml `c', table(D3) measure(`m') x(`m') ulabel(employer x `lev') y(y) cl(cl) ///
            uvar(emp_loc) absorb(emp_loc emp_q size_q) fe(emploc empq sizeq)
        local ++c
        est_ppml `c', table(D3) measure(`m') x(`m') ulabel(employer x `lev') y(y) cl(cl) ///
            uvar(emp_loc) absorb(emp_loc emp_q obl_q size_q) fe(emploc empq oblq sizeq)
        local ++c
    }
}
postclose est_post


* --- Step 7. Tables ------------------------------------------------------------------
* One table per design. Columns: alarms (1-2), front (3-4), attacks (5-6). Coefficients
* are stacked: each measure has its own row, filled in its columns only.
use "$tmp6/06_estimates.dta", clear
list table col measure unit b se N n_units n_clust sd_E_resid, noobs sep(0)
label var b          "Coefficient on exposure"
label var se         "Standard error, clustered by raion"
label var sd_E_resid "SD of exposure net of the fixed effects"
save "$tmp6/06_estimates.dta", replace

capture program drop make_table
program define make_table
    args des
    use "$tmp6/06_estimates.dta" if table == "`des'", clear
    sort col
    local K = _N
    forvalues k = 1/`K' {
        local m`k'  = measure[`k']
        * location level: raion for alarms, city for front and attacks (D2: of the weights)
        local u`k'  = cond("`m`k''" == "alarms", "raion", "city")
        * stars from the clustered SE (normal approximation, as ppmlhdfe's z test)
        local pv = 2 * normal(-abs(b[`k'] / se[`k']))
        local st = cond(`pv' < 0.01, "***", cond(`pv' < 0.05, "**", cond(`pv' < 0.10, "*", "")))
        local b`k'  = strtrim(string(b[`k'], "%9.3f")) + "`st'"
        local s`k'  = "(" + strtrim(string(se[`k'], "%9.3f")) + ")"
        * effect: +10 pp for alarms and attacks; distance halved (+ln 2) for front
        local step  = cond("`m`k''" == "front", ln(2), 0.1)
        local p`k'  = strtrim(string(100 * (exp(`step' * b[`k']) - 1), "%9.1f"))
        local v`k'  = strtrim(string(100 * sd_E_resid[`k'], "%9.1f"))
        local fe`k' = fe[`k']
        local n`k'  = strtrim(string(N[`k'], "%12.0fc"))
        local nu`k' = strtrim(string(n_units[`k'], "%12.0fc"))
        local nc`k' = strtrim(string(n_clust[`k'], "%12.0fc"))
        local np`k' = strtrim(string(n_postings[`k'], "%12.0fc"))
    }
    clear
    set obs 24
    gen byte row_type = 2
    gen str48 label = ""
    forvalues k = 1/`K' {
        gen str24 c`k' = ""
        label var c`k' "(`k')"
    }
    label var label " "
    * row layout
    local r_alarms  3
    local r_front   5
    local r_attacks 7
    replace row_type = 1 in 1
    replace label = "Estimates" in 1
    replace label = "Location level" in 2
    replace label = "Alarms: share of days with an alarm in the raion" in 3
    replace row_type = 3 in 4
    replace label = "Front: proximity, -ln km to Russian-held place" in 5
    replace row_type = 3 in 6
    replace label = "Attacks: share of days with an attack within 15 km" in 7
    replace row_type = 3 in 8
    replace label = "Effect on postings, %" in 9
    replace label = "SD of exposure net of fixed effects (x 100)" in 10
    replace row_type = 1 in 11
    replace label = "Fixed effects" in 11
    replace label = "Location" in 12
    replace label = "Quarter" in 13
    replace label = "Oblast x quarter" in 14
    replace label = "Size band x quarter (pre-war population)" in 15
    replace label = "Employer" in 16
    replace label = "Employer sector x quarter" in 17
    replace label = "Employer x location" in 18
    replace label = "Employer x quarter" in 19
    replace row_type = 1 in 20
    replace label = "Sample" in 20
    replace label = "Observations" in 21
    replace label = "Units" in 22
    replace label = "Clusters (raions)" in 23
    replace label = "Postings (sampled)" in 24
    forvalues k = 1/`K' {
        replace c`k' = "`u`k''" in 2
        local r = `r_`m`k'''
        replace c`k' = "`b`k''" in `r'
        replace c`k' = "`s`k''" in `=`r' + 1'
        replace c`k' = "`p`k''" in 9
        replace c`k' = "`v`k''" in 10
        local i = 12
        foreach f in loc q oblq sizeq emp secq emploc empq {
            if strpos(" `fe`k'' ", " `f' ") replace c`k' = "Yes" in `i'
            local ++i
        }
        replace c`k' = "`n`k''"  in 21
        replace c`k' = "`nu`k''" in 22
        replace c`k' = "`nc`k''" in 23
        replace c`k' = "`np`k''" in 24
    }
    * drop fixed-effect rows no column uses
    gen byte used = row_type != 2 | !inrange(_n, 12, 19)
    forvalues k = 1/`K' {
        replace used = 1 if c`k' != ""
    }
    keep if used
    drop used
    list, noobs sep(0) abbreviate(20)
    local dl = lower("`des'")
    export_panel_table using "$tab/06_`dl'", ///
        title("`des', PPML, civilian core vacancies: alarms (raion), front and attacks (city)")
end

make_table D1
make_table D2
make_table D3


* --- Step 8. Coefficient plot: all designs and measures ---------------------------------
* Effect on postings in % with 95% CI (clustered SE), the "Effect on postings, %" row of
* the tables: +10 pp of days for alarms and attacks, distance to the front halved.
* One panel per measure; rows = designs; two markers = the two sets of fixed effects.
set scheme stcolor
graph set window fontface "Arial"
use "$tmp6/06_estimates.dta", clear
gen double step = cond(measure == "front", ln(2), 0.1)
gen double pct  = 100 * (exp(step * b) - 1)
gen double lo   = 100 * (exp(step * (b - invnormal(0.975) * se)) - 1)
gen double hi   = 100 * (exp(step * (b + invnormal(0.975) * se)) - 1)
gen byte fe2    = mod(col, 2) == 0                   // second set: + oblast/sector x quarter
gen double yy   = 4 - real(substr(table, 2, 1)) + cond(fe2, -0.15, 0.15)
gen byte mo     = cond(measure == "alarms", 1, cond(measure == "front", 2, 3))
label define mo_lbl 1 "Alarms: +10 pp of days" 2 "Front: distance halved" 3 "Attacks: +10 pp of days"
label values mo mo_lbl
twoway (rcap lo hi yy if !fe2, horizontal lcolor(navy)) ///
       (scatter yy pct if !fe2, mcolor(navy) msymbol(O)) ///
       (rcap lo hi yy if fe2, horizontal lcolor(maroon)) ///
       (scatter yy pct if fe2, mcolor(maroon) msymbol(D)), ///
    by(mo, rows(1) xrescale note("") legend(position(6)) imargin(medsmall)) subtitle(, size(medlarge) fcolor(gs14) lcolor(gs14)) ///
    xline(0, lcolor(gs10) lpattern(dash)) ///
    ylabel(3 "D1 location" 2 "D2 employer" 1 "D3 employer x location", angle(0) nogrid labsize(medlarge)) ///
    yscale(range(0.5 3.5)) ytitle("") xtitle("Effect on postings, % (95% CI)", size(medlarge)) ///
    legend(order(2 "Size band x quarter FE" 4 "+ oblast x quarter (D1, D3) / sector x quarter (D2)") ///
        rows(1) size(medlarge)) ///
    xlabel(, labsize(medlarge)) xsize(10) ysize(3.4)
graph export "$fig/06_coefplot.pdf", replace

log close
