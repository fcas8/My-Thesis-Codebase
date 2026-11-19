* =============================================================================
* 05_descriptives_rq.do  --  descriptives by research question (no regressions on
*                            war exposure; exposure groups only to split the sample)
*
* One step per question:
*   Step 2  RQ1  Margins: do employers post less (intensive) or stop posting (extensive)?
*   Step 3  RQ6  Concentration: do small employers leave the market?
*   Step 4  RQ2  Relocation: does demand move to sheltered places?
*   Step 5  RQ3  Wages: do pay differentials widen?
*   Step 6  RQ4  Upskilling: do requirements rise?
*   Step 7  RQ5  Substitution: women, veterans, students, draft deferment
*   Step 8  RQ7  Military recruitment: who recruits, for what, where, at what pay
*
* Input : data/temp/descriptives_base.dta           (04_descriptives.do step 2: sample,
*                                                   groups, Kyiv city, areas, real wages)
*         data/temp/robota_text_features.csv        (00_text_features.py: tags and text)
*         data/temp/robota_text_features_labels.csv (value labels for isco1, isco2, occ_status, mil_*)
*         data/analysis/alarms_raion_month.dta      (03_exposure_build.do part B)
* Output: output/figures/05_*.pdf                    figures (list at each step)
*         output/tables/05_*.xlsx and .tex           final tables (export_table)
*         data/temp/descriptives/05_*.csv            the numbers behind the figures,
*                                                   review lists
*         data/temp/logs/05_descriptives_rq.log
*         Every output is listed in output_inventory.xlsx (Project folder).
*
* Choices (11 Nov 2026; the rest as in 04_descriptives.do):
*   - Sample: civilian core (grp 1) unless a step says otherwise; military (grp 5) in
*     step 8. Counts are estimated (sums of weights), except employer counts, which
*     are of SAMPLED vacancies (about 1 in 5.4 ids since the Nov 2026 export).
*   - Comparison periods: P0 = 2021, P1 = Jan 2023 - Oct 2026 (as in 04). Quarterly
*     figures run 2020q4 - 2026q3 (2026q4 would hold October only).
*   - "per" (period) for within-employer regressions: 0 = Oct 2020 - 23 Feb 2022
*     (pre-war), 2022 = 24 Feb - Dec 2022, then calendar years 2023-2026.
*   - Employer windows (steps 2-3): Oct 1 - Feb 23 of each winter, 2020/21 to
*     2025/26. Same calendar months every year, so seasonality cancels; the first
*     transition (2020/21 to 2021/22) is entirely pre-war and shows how much "exit"
*     and "entry" the sampling and normal churn create by themselves.
*   - Exposure groups of the raion (step 4 on): mean share of hours under alarm,
*     Mar 2022 - Aug 2025 (before alarms moved to raion level, Sep 2025), part B of
*     03_exposure_build.do. Kyiv city is its own group (a third of all vacancies);
*     other raions are split at the terciles of the raion distribution weighted by 2021
*     core vacancies. Big raions (oblast centers) are single lumps, so the groups are
*     not equal thirds: outside Kyiv city about 28% / 48% / 24% of 2021 vacancies are
*     low / middle / high. Kyiv city: 6.9% of hours under alarm. Raions occupied more than
*     half of the months or without alarm data (Crimea, Luhansk) are a fifth group.
*   - Requirements: experience required = text asks for N years, or robota.ua's
*     experience tag is 6 months or more; 3+ years likewise; "no experience" = the
*     text says so (robota.ua's "no experience" tag is given to most ads that do not
*     ask for experience, so it is a default rather than a statement). Higher
*     education = text or tag; English = robota.ua's language tag; software = at least
*     one software/tool tag.
*   - Text flags for gender and age fall sharply in 2022 in every group, which points to
*     platform moderation (the law bans such requirements), not to employers. Read the
*     2022 break in those series with care; changes after 2022 are comparable.
*   - Occupation (14 Nov 2026): ISCO-08 from the job title (00_text_features.py step 5):
*     major group (isco1; "Not classified" = ambiguous or no rule) in tables, sub-major
*     (isco2) for cells. Male-typed jobs = ISCO sub-majors 54 protective services, 71
*     building trades, 72 metal and machinery trades, 74 electrical trades, 83 drivers and
*     mobile plant operators, 93 laborers in mining, construction, manufacturing and
*     transport.
*   - Perks shown as robota.ua badges (bd_*) are kept apart from the text (tx_*) in
*     00_text_features.py. Here a vacancy offers shelter, backup power, deferment,
*     training, housing or targets veterans if the text OR a badge (OR a robota.ua tag,
*     where one exists) says so. Badge use rises and falls over time (step 1e prints by
*     year how much of each series comes from badges only).
*
* Purely descriptive: shares, counts, percentiles, accounting splits; no regressions
* (within-employer and adjusted designs are left for the main analysis).
* Run after 04_descriptives.do (00_main.do runs it last).
* =============================================================================

clear all
set more off
set linesize 200

* --- Step 0. Paths and settings ---------------------------------------------
if "$project" == "" global project "`c(pwd)'/.."   // set by 00_main.do; else run from the repo root
global data    "$project/Project/data/analysis"
global temp    "$project/Project/data/temp"
global fig     "$project/Project/output/figures"
global tab     "$project/Project/output/tables"
global tmp5    "$project/Project/data/temp/descriptives"
global do      "$project/Project/do"

cap mkdir "$tmp5"
cap log close
log using "$temp/logs/05_descriptives_rq.log", replace text
do "$do/00_programs.do"                    // export_table

global base_from = tm(2021m1)
global base_to   = tm(2021m12)
global post_from = tm(2023m1)
global last_month = tm(2026m10)
global inv_day   = td(24feb2022)
global last_q    = tq(2026q3)

set scheme stcolor
graph set window fontface "Arial"

* Common pieces of the quarterly and monthly figures
global qevents `"xline(`=tq(2022q1)+0.6', lcolor(cranberry) lwidth(medthick)) xline(`=tq(2022q4)' `=tq(2024q2)', lcolor(gs9) lpattern(dash))"'
global qfmt    `"xlabel(`=tq(2021q1)'(4)`=tq(2026q1)', format(%tqCCYY)) xtitle("")"'
global mevents `"xline(`=tm(2022m2)+0.77', lcolor(cranberry) lwidth(medthick)) xline(`=tm(2022m10)' `=tm(2024m5)', lcolor(gs9) lpattern(dash))"'
global mfmt    `"xlabel(`=tm(2021m1)'(6)`=tm(2026m7)', format(%tmMon_YY)) xtitle("")"'
global evnote  "Red line: full-scale invasion (24 Feb 2022). Dashed: strikes on energy begin (Oct 2022); mobilization law (May 2024)."

* qshares: quarterly weighted shares (%) of 0/1 variables, one line each.
*   qshares varlist [if], file() ytitle() legend() [colors() note() ylabel()]
*   Writes $fig/<file>.pdf and $tmp5/<file>.csv.
capture program drop qshares
program define qshares
    syntax varlist [if], FILE(string) YTItle(string) LEGend(string asis) ///
        [COLors(string) NOTe(string asis) YLABel(string asis)]
    preserve
    marksample touse, novarlist
    quietly keep if `touse' & yq <= $last_q
    collapse (mean) `varlist' [pw=weight], by(yq)
    if "`colors'" == "" local colors "navy cranberry dkorange dkgreen purple gs8 teal"
    local plots ""
    local i = 0
    foreach v of local varlist {
        quietly replace `v' = 100 * `v'
        local ++i
        local c : word `i' of `colors'
        local plots `plots' (connected `v' yq, lcolor(`c') mcolor(`c') msize(vsmall))
    }
    if `"`note'"' == "" local note `""$evnote""'
    twoway `plots', $qevents $qfmt ylabel(`ylabel', angle(0)) ytitle("`ytitle'") ///
        legend(`legend') note(`note', size(vsmall))
    graph export "$fig/`file'.pdf", replace
    format yq %tq
    export delimited using "$tmp5/`file'.csv", replace
    restore
end

* yearlab: turns a numeric year variable into the labels used in every table
capture program drop yearlab
program define yearlab
    args v
    tostring `v', replace
    replace `v' = "2020 (Oct-Dec)" if `v' == "2020"
    replace `v' = "2026 (Jan-Oct)" if `v' == "2026"
end

* --- Step 1. Data -------------------------------------------------------------
* 1a. Text features and their value labels (written as a small do-file, run after -use-)
import delimited using "$temp/robota_text_features_labels.csv", varnames(1) encoding("utf-8") clear
tempfile labdo
tempname fh
file open `fh' using `labdo', write text replace
forvalues i = 1/`=_N' {
    file write `fh' `"label define `=var[`i']'_lbl `=value[`i']' "`=label[`i']'", add"' _n
}
file close `fh'

import delimited using "$temp/robota_text_features.csv", varnames(1) clear
tempfile feat
save `feat'

* 1b. Exposure of each raion (see header)
use "$data/alarms_raion_month.dta", clear
keep if inrange(month, tm(2022m3), tm(2025m8))
collapse (mean) expo_share = share_hours occ_frac = occupied_raion (max) no_data = no_alarm_data, ///
    by(raion_pcode)
gen byte expo_out = no_data == 1 | occ_frac > 0.5
tempfile expo
save `expo'

* 1c. Merge on the 04 sample
use "$temp/descriptives_base.dta", clear
merge 1:1 id using `feat', assert(match using) keep(match) nogenerate
do `labdo'
label values isco1 isco1_lbl
label values isco2 isco2_lbl
label values occ_status occ_status_lbl
label values mil_role mil_role_lbl
label values mil_unit mil_unit_lbl
merge m:1 raion_pcode using `expo', keep(master match) nogenerate

summarize expo_share if raion_pcode == "UA8000", meanonly
display "Kyiv city: share of hours under alarm, Mar 2022 - Aug 2025 = " %5.3f r(mean)
_pctile expo_share [aw=weight] if core & year == 2021 & raion_pcode != "UA8000" & !expo_out, ///
    p(33.333 66.667)
local c1 = r(r1)
local c2 = r(r2)
display "Tercile cutoffs (share of hours under alarm): `c1', `c2'"
gen byte expo = .
replace expo = 2 if expo_share <= `c1'
replace expo = 3 if expo_share > `c1' & expo_share <= `c2'
replace expo = 4 if expo_share > `c2' & expo_share < .
replace expo = 5 if expo_out == 1
replace expo = 1 if raion_pcode == "UA8000"
label define expo_lbl 1 "Kyiv city" 2 "Low exposure" 3 "Middle exposure" 4 "High exposure" ///
    5 "Occupied or no alarm data"
label values expo expo_lbl
tab expo if core & year == 2021 [aw=weight], missing

* 1d. Time
gen yq = qofd(created_date)
format yq %tq
gen int per = 0 if created_date < $inv_day
replace per = year if created_date >= $inv_day
label define per_lbl 0 "Pre-war (Oct 2020 - 23 Feb 2022)" 2022 "2022 (from 24 Feb)" 2023 "2023" ///
    2024 "2024" 2025 "2025" 2026 "2026 (Jan-Oct)"
label values per per_lbl
gen byte P = 0 if inrange(ym, $base_from, $base_to)
replace P = 1 if ym >= $post_from
local m_base = $base_to - $base_from + 1
local m_post = $last_month - $post_from + 1

* 1e. Requirements and targeting (see header)
gen byte exp_req   = (tx_exp_years > 0 & tx_exp_years < .) | inrange(cl_exp, 0.5, 5)
gen byte exp3      = (tx_exp_years >= 3 & tx_exp_years < .) | inrange(cl_exp, 3, 5)
gen byte exp_none  = tx_exp_none == 1 & !exp_req
gen byte higher_ed = tx_higher_ed == 1 | cl_edu == 4
gen byte english   = cl_english == 1
gen byte soft      = cl_n_soft >= 1
gen byte training  = tx_training == 1 | bd_training == 1
gen byte intern    = cl_intern
gen byte remote    = cl_remote == 1 | tx_remote == 1
gen byte veteran   = tx_veteran == 1 | cl_veteran == 1 | bd_veteran == 1
gen byte disab     = tx_disab == 1 | cl_disab == 1
gen byte student   = tx_student == 1 | cl_student == 1
gen byte pension   = tx_pension == 1 | cl_pension == 1
gen byte idp       = tx_idp
gen byte female_seek = tx_female_seek
gen byte male_seek = tx_male_seek
gen byte fem_title = tx_fem_title
gen byte defer     = tx_defer == 1 | bd_defer == 1
gen byte shelter_air = tx_shelter_air == 1 | bd_shelter == 1
gen byte power     = tx_power == 1 | bd_power == 1
gen byte housing   = tx_housing == 1 | bd_housing == 1 | cl_housing == 1
gen byte male_typed = inlist(isco2, 54, 71, 72, 74, 83, 93)
* ISCO major group for tables: not classified (ambiguous, generic or no rule) shown as 99
gen byte isco1g = cond(isco1 < ., isco1, 99)
label copy isco1_lbl isco1g_lbl
label define isco1g_lbl 99 "Not classified", add
label values isco1g isco1g_lbl
* how much of each perk series comes from badges only (text and tags silent), core, by year
gen byte bdo_shelter = shelter_air & !tx_shelter_air
gen byte bdo_power   = power & !tx_power
gen byte bdo_defer   = defer & !tx_defer
gen byte bdo_train   = training & !tx_training
gen byte bdo_housing = housing & !tx_housing & !cl_housing
gen byte bdo_veteran = veteran & !tx_veteran & !cl_veteran
tabstat shelter_air bdo_shelter power bdo_power defer bdo_defer training bdo_train ///
    housing bdo_housing veteran bdo_veteran bd_any if core [aw=weight], ///
    by(year) statistics(mean) format(%5.3f)
drop bdo_*
tab isco1g year if core [aw=weight], col nofreq
* cross-check of the two experience sources (robota.ua tag vs my text parse), core
tab year exp_req if core [aw=weight], row nofreq
tab cl_exp year if core, missing col nofreq

compress
tempfile rq
save `rq'

* --- Step 2. RQ1 Margins: less posting or exit? ------------------------------------
* 2a. Who posts: core vacancies by the employer's entry cohort (year of its first
*     sampled vacancy: before the invasion, 2022 from 24 Feb, 2023, ...), and vacancies
*     without an employer id or posted by agencies. Shrinking pre-war layer = pre-war
*     employers post less or stop; new layers = entry. A firm first SAMPLED in 2023 may
*     have posted before without being sampled: new layers are an upper bound on entry.
*     Output: 05_margins_cohorts.pdf; data 05_margins_cohorts.csv
use `rq' if panel_candidate & !inlist(grp, 2, 5), clear
collapse (min) first_day = created_date, by(notebook_id)
tempfile first
save `first'
use `rq' if core, clear
merge m:1 notebook_id using `first', keep(master match) nogenerate
gen byte cohort = 0
replace cohort = 1 if panel_candidate & first_day < $inv_day
replace cohort = year(first_day) - 2020 if panel_candidate & first_day >= $inv_day   // 2 = 2022 ... 6 = 2026
collapse (sum) est = one [pw=weight], by(ym cohort)
reshape wide est, i(ym) j(cohort)
forvalues k = 0/6 {
    replace est`k' = 0 if est`k' == .
}
gen s1 = est1
forvalues k = 2/6 {
    gen s`k' = s`=`k'-1' + est`k'
}
gen s0 = s6 + est0
twoway (area s0 ym, color(gs13)) (area s6 ym, color(eltblue)) (area s5 ym, color(ebblue%60)) ///
    (area s4 ym, color(ltblue)) (area s3 ym, color(edkblue%60)) (area s2 ym, color(dkorange%70)) ///
    (area s1 ym, color(navy)), $mevents $mfmt ylabel(, format(%9.0fc) angle(0)) ///
    ytitle("Estimated new core vacancies per month") ///
    legend(order(7 "Employers seen before the invasion" 6 "First seen 2022" 5 "2023" 4 "2024" ///
    3 "2025" 2 "2026" 1 "No employer id / agency") cols(4) size(small) position(6) holes(2 3 4)) ///
    note("Cohort = date of the employer's first sampled vacancy (any group except state employment centers and military)." ///
    "$evnote", size(vsmall))
graph export "$fig/05_margins_cohorts.pdf", replace
drop s*
export delimited using "$tmp5/05_margins_cohorts.csv", replace

* 2b. Winter windows (Oct 1 - Feb 23): change in sampled core vacancies of employers
*     between consecutive winters, split into continuing employers (intensive margin),
*     entrants and exiters (extensive margin). Each as % of the earlier window's
*     vacancies. Plus vacancies without employer id/agency, for completeness.
*     Output: 05_margins_windows (.xlsx, .tex), 05_margins_windows.pdf
use `rq' if core, clear
gen byte w = .
forvalues k = 0/5 {
    replace w = `k' if inrange(created_date, mdy(10, 1, 2020 + `k'), mdy(2, 23, 2021 + `k'))
}
keep if w < .
preserve
    keep if !panel_candidate
    collapse (rawsum) np = one, by(w)
    tempfile nonpanel
    save `nonpanel'
restore
keep if panel_candidate
collapse (rawsum) n = one, by(notebook_id w)
reshape wide n, i(notebook_id) j(w)
forvalues k = 0/5 {
    replace n`k' = 0 if n`k' == .
}
tempfile win
save `win'

tempname pf
tempfile dec
postfile `pf' t E0 V0 V1 dcont entry exit er er3 nentry vpe0 vpe_cont0 vpe_cont1 using `dec', replace
forvalues t = 1/5 {
    local s = `t' - 1
    quietly {
        count if n`s' > 0
        local E0 = r(N)
        summarize n`s', meanonly
        local V0 = r(sum)
        summarize n`t', meanonly
        local V1 = r(sum)
        gen d = n`t' - n`s' if n`s' > 0 & n`t' > 0
        summarize d, meanonly
        local dcont = r(sum)
        drop d
        summarize n`s' if n`s' > 0 & n`t' > 0, meanonly
        local vc0 = r(mean)
        summarize n`t' if n`s' > 0 & n`t' > 0, meanonly
        local vc1 = r(mean)
        summarize n`t' if n`s' == 0, meanonly
        local entry = r(sum)
        summarize n`s' if n`t' == 0, meanonly
        local exit = -r(sum)
        count if n`s' > 0 & n`t' == 0
        local er = r(N) / `E0'
        count if n`s' >= 3
        local E3 = r(N)
        count if n`s' >= 3 & n`t' == 0
        local er3 = r(N) / `E3'
        count if n`s' == 0 & n`t' > 0
        local nentry = r(N) / `E0'
    }
    post `pf' (`t') (`E0') (`V0') (`V1') (`dcont') (`entry') (`exit') (`er') (`er3') (`nentry') ///
        (`V0' / `E0') (`vc0') (`vc1')
}
postclose `pf'
use `dec', clear
assert abs(dcont + entry + exit - (V1 - V0)) < 1e-6
gen w = t
merge 1:1 w using `nonpanel', keep(master match) nogenerate
rename np npV1
drop w
gen w = t - 1
merge 1:1 w using `nonpanel', keep(master match) nogenerate
rename np npV0
drop w
gen tot_p   = 100 * (V1 - V0) / V0
gen dcont_p = 100 * dcont / V0
gen entry_p = 100 * entry / V0
gen exit_p  = 100 * exit / V0
gen net_p   = entry_p + exit_p                  // net entry (extensive margin)
gen np_p    = 100 * (npV1 - npV0) / npV0
foreach v in er er3 nentry {
    replace `v' = 100 * `v'
}
gen str40 trans = ""
forvalues t = 1/5 {
    replace trans = "`=2019+`t''/`=substr("`=2020+`t''", 3, 2)' to `=2020+`t''/`=substr("`=2021+`t''", 3, 2)'" if t == `t'
}
replace trans = trans + " (pre-war)" if t == 1
list trans E0 V0 V1 tot_p dcont_p entry_p exit_p np_p er er3 nentry vpe0 vpe_cont0 vpe_cont1, noobs sep(0) abbreviate(10)
export delimited using "$tmp5/05_margins_windows.csv", replace
preserve
    keep trans E0 V0 V1 tot_p dcont_p net_p entry_p exit_p er er3 nentry np_p
    order trans E0 V0 V1 tot_p dcont_p net_p entry_p exit_p er er3 nentry np_p
    format E0 V0 V1 %9.0fc
    format tot_p dcont_p net_p entry_p exit_p er er3 nentry np_p %6.1f
    label var trans   "Winter (Oct-Feb) to next winter"
    label var E0      "Employers, first winter"
    label var V0      "Vacancies, first winter"
    label var V1      "Vacancies, next winter"
    label var tot_p   "Change, %"
    label var dcont_p "... continuing employers, %"
    label var net_p   "... net entry, %"
    label var entry_p "...... of which entrants, %"
    label var exit_p  "...... of which exiters, %"
    label var er      "Exit rate, % of employers"
    label var er3     "Exit rate, employers with 3+ vacancies, %"
    label var nentry  "Entrants, % of first-winter employers"
    label var np_p    "No employer id / agency: change, %"
    export_transposed using "$tab/05_margins_windows", ///
        title("Sampled core vacancies of employers, winter to winter (Oct 1 - Feb 23): intensive vs extensive margin")
restore
* two columns per pair of winters: continuing employers (intensive margin) and net entry
* (extensive margin), with entrants stacked above zero, exiters below, and the net value
gen x_cont = t - 0.19
gen x_net  = t + 0.19
gen zero   = 0
twoway (rbar zero dcont_p x_cont, barwidth(0.34) color(navy)) ///
    (rbar zero entry_p x_net, barwidth(0.34) color(dkgreen)) ///
    (rbar exit_p zero x_net, barwidth(0.34) color(cranberry)) ///
    (scatter net_p x_net, msymbol(D) mcolor(black) msize(medsmall)), ///
    xlabel(1 "2020/21-21/22" 2 "2021/22-22/23" 3 "2022/23-23/24" 4 "2023/24-24/25" ///
    5 "2024/25-25/26", labsize(small) noticks) xscale(range(0.5 5.5)) xtitle("") ///
    yline(0, lcolor(gs8)) ylabel(, angle(0)) ytitle("% of the earlier winter's vacancies") ///
    legend(order(1 "Continuing employers (intensive)" 2 "Entrants" 3 "Exiters" ///
    4 "Net entry (entrants - exiters)") rows(2) position(6) size(small)) ///
    note("Sampled civilian core vacancies of employers with an id (no agencies), Oct 1 - Feb 23 of each winter." ///
    "Left column: change among employers posting in both winters. Right column: vacancies of entrants (up) and" ///
    "exiters (down); the diamond is their sum. The first pair of winters is entirely pre-war: its entry and exit" ///
    "show sampling noise and normal churn.", size(vsmall))
graph export "$fig/05_margins_windows.pdf", replace

* 2c. Index version, by war year (24 Feb - 23 Feb; base = 2021/22, the last pre-war
*     year; 2026/27 is incomplete and left out). Pre-war employers P = employers with an
*     id (no agencies) and >= 1 sampled core posting in the base year. For each year t:
*       N(t)    = employers of P with >= 1 sampled posting in t      (extensive)
*       V(t)    = their sampled postings
*       ybar(t) = V(t) / N(t)                                         (intensive)
*     so V(t)/V(b) = N(t)/N(b) * ybar(t)/ybar(b), each x 100 (= 100 in the base year).
*     Also: postings of all employers (P and employers not seen in the base year).
*     Sampling bias (Paper/slides): an employer is seen with probability
*     1 - (1-f)^Y, rising in its true postings Y, so cuts in Y move employers out of N:
*     the extensive index is an upper bound on exit, the intensive one a lower bound on
*     the cut per employer. Panel B: employers with >= 10 sampled base-year postings,
*     who stay visible unless they cut deeply (a check on the size of the bias).
*     Output: 05_margins_index.pdf; data in data/temp/descriptives/05_margins_index.csv
use notebook_id created_date one core panel_candidate using `rq' if core & panel_candidate, clear
gen int wy = .
forvalues k = 0/4 {
    replace wy = 2021 + `k' if inrange(created_date, mdy(2, 24, 2021 + `k'), mdy(2, 23, 2022 + `k'))
}
keep if wy < .
collapse (rawsum) y = one, by(notebook_id wy)
bysort notebook_id: egen yb = total(y * (wy == 2021))
tempfile ey
save `ey'
collapse (sum) Vall = y, by(wy)
tempfile vall
save `vall'
tempfile idx
local first = 1
foreach g in all big {
    use `ey' if yb >= cond("`g'" == "big", 10, 1), clear
    collapse (sum) V = y (count) N = y, by(wy)
    gen str3 group = "`g'"
    if `first' == 0 append using `idx'
    save `idx', replace
    local first = 0
}
merge m:1 wy using `vall', nogenerate
sort group wy
foreach v in V N Vall {
    by group: gen double i`v' = 100 * `v' / `v'[1]
}
gen double iY = 100 * iV / iN
format iV iN iY iVall %6.1f
list group wy N V iN iY iV iVall, noobs sepby(group)
export delimited using "$tmp5/05_margins_index.csv", replace
local xl xlabel(2021 "2021/22" 2022 "2022/23" 2023 "2023/24" 2024 "2024/25" 2025 "2025/26", labsize(small))
local ttl_all "A. All pre-war employers"
local ttl_big "B. Pre-war employers with 10+ sampled postings in 2021/22"
foreach g in all big {
    local leg legend(off)
    if "`g'" == "all" local leg legend(order(4 "All employers' postings" 1 "Pre-war employers' postings" ///
        2 "Employers still posting (extensive)" 3 "Postings per active employer (intensive)") ///
        cols(1) size(small) ring(0) position(11) region(lstyle(none) fcolor(none)))
    twoway (connected iV wy if group == "`g'", lcolor(black) mcolor(black) lwidth(medthick)) ///
        (connected iN wy if group == "`g'", lcolor(cranberry) mcolor(cranberry) msymbol(S)) ///
        (connected iY wy if group == "`g'", lcolor(navy) mcolor(navy) msymbol(T)) ///
        (line iVall wy if group == "`g'", lcolor(gs9) lpattern(dash)), ///
        yline(100, lcolor(gs12)) `xl' xtitle("") xscale(range(2020.8 2025.2)) ///
        ylabel(0(50)250, angle(0) format(%3.0f)) yscale(range(0 240)) ytitle("Index, 2021/22 = 100") ///
        title("`ttl_`g''", size(medsmall)) `leg' name(ix_`g', replace) nodraw
}
graph combine ix_all ix_big, cols(2) imargin(small) xsize(10) ysize(4.4) ycommon ///
    note("Sampled civilian core postings of employers with an id (no agencies), by war year (24 Feb - 23 Feb). Pre-war employers: at least one posting in 2021/22." ///
    "Pre-war employers postings = employers still posting x postings per active employer. Sampling a third of postings moves employers that cut back out of" ///
    "still posting: the extensive line is an upper bound on exit, the intensive line a lower bound on the cut per employer.", size(vsmall))
graph export "$fig/05_margins_index.pdf", replace
graph drop ix_all ix_big

* --- Step 3. RQ6 Concentration: do small employers leave? ---------------------------
* 3a. Exit rate by size in the earlier winter (sampled core vacancies: 1, 2-4, 5-9, 10+).
*     Small firms "exit" more even before the war only because one vacancy is easily
*     missed by the sampling: compare each transition with the pre-war one.
*     Output: 05_exit_by_size (.xlsx, .tex), 05_exit_by_size.pdf
use `win', clear
tempname pf
tempfile ebs
postfile `pf' t cls N rate using `ebs', replace
forvalues t = 1/5 {
    local s = `t' - 1
    gen byte cls = irecode(n`s', 0, 1, 4, 9) if n`s' > 0
    forvalues c = 1/4 {
        quietly count if cls == `c'
        local N = r(N)
        quietly count if cls == `c' & n`t' == 0
        post `pf' (`t') (`c') (`N') (100 * r(N) / `N')
    }
    drop cls
}
postclose `pf'
use `ebs', clear
label define cls_lbl 1 "1 vacancy" 2 "2-4" 3 "5-9" 4 "10+"
label values cls cls_lbl
twoway (connected rate t if cls == 1, lcolor(cranberry) mcolor(cranberry)) ///
    (connected rate t if cls == 2, lcolor(dkorange) mcolor(dkorange)) ///
    (connected rate t if cls == 3, lcolor(dkgreen) mcolor(dkgreen)) ///
    (connected rate t if cls == 4, lcolor(navy) mcolor(navy)), ///
    xlabel(1 "2020/21-21/22" 2 "2021/22-22/23" 3 "2022/23-23/24" 4 "2023/24-24/25" 5 "2024/25-25/26", labsize(small)) ///
    xtitle("") xline(1.5, lcolor(cranberry)) ylabel(0(20)100, angle(0)) ///
    ytitle("% of employers with no sampled vacancy next winter") ///
    legend(order(1 "1 vacancy" 2 "2-4" 3 "5-9" 4 "10+") title("Sampled vacancies in the earlier winter", size(small)) rows(1) position(6)) ///
    note("Civilian core, employers with an id (no agencies), Oct 1 - Feb 23 of each winter. Red line: invasion.", size(vsmall))
graph export "$fig/05_exit_by_size.pdf", replace
export delimited using "$tmp5/05_exit_by_size.csv", replace
drop N
reshape wide rate, i(cls) j(t)
format rate* %5.1f
label var cls "Sampled vacancies, earlier winter"
label var rate1 "2020/21 to 2021/22 (pre-war)"
label var rate2 "2021/22 to 2022/23"
label var rate3 "2022/23 to 2023/24"
label var rate4 "2023/24 to 2024/25"
label var rate5 "2024/25 to 2025/26"
export_table using "$tab/05_exit_by_size", ///
    title("Exit rate (% of employers with no sampled core vacancy in the next winter) by size")

* 3b. Share of core vacancies by the size of the posting employer in that year
*     (sampled core vacancies in the year: 1, 2-4, 5-19, 20+), and without employer id.
*     The count also falls when total posting falls, so read with 3a.
*     Output: 05_size_shares (.xlsx, .tex), 05_size_shares.pdf
use `rq' if core, clear
bysort notebook_id year: gen n_y = _N if panel_candidate
gen byte sizecl = 0
replace sizecl = 1 + (n_y >= 2) + (n_y >= 5) + (n_y >= 20) if panel_candidate
collapse (sum) est = one [pw=weight], by(year sizecl)
bysort year: egen tot = total(est)
gen share = 100 * est / tot
keep year sizecl share
reshape wide share, i(year) j(sizecl)
format share* %5.1f
list, noobs sep(0)
graph bar (asis) share1 share2 share3 share4 share0, over(year, relabel(1 "2020 Q4" 7 "2026 Jan-Oct") ///
    label(labsize(small))) stack bar(1, color(cranberry)) bar(2, color(dkorange)) bar(3, color(eltblue)) ///
    bar(4, color(navy)) bar(5, color(gs12)) ylabel(0(20)100, angle(0)) ytitle("% of civilian core vacancies") ///
    legend(order(1 "Employer with 1 sampled vacancy that year" 2 "2-4" 3 "5-19" 4 "20+" 5 "No employer id / agency") ///
    rows(2) position(6) size(small))
graph export "$fig/05_size_shares.pdf", replace
yearlab year
label var year   "Year"
label var share1 "1 sampled vacancy, %"
label var share2 "2-4, %"
label var share3 "5-19, %"
label var share4 "20+, %"
label var share0 "No employer id / agency, %"
order year share1 share2 share3 share4 share0
export_transposed using "$tab/05_size_shares", ///
    title("Civilian core vacancies by size of the posting employer in the year (sampled vacancies)")

* --- Step 4. RQ2 Relocation: does demand move to sheltered places? -------------------
* 4a. Share of core vacancies by exposure group, quarterly.
*     Output: 05_exposure_shares.pdf; data 05_exposure_shares.csv
use `rq' if core & expo < . & yq <= $last_q, clear
collapse (sum) est = one [pw=weight], by(yq expo)
bysort yq: egen tot = total(est)
gen share = 100 * est / tot
keep yq expo share
reshape wide share, i(yq) j(expo)
twoway (connected share1 yq, lcolor(navy) mcolor(navy) msize(vsmall)) ///
    (connected share2 yq, lcolor(dkgreen) mcolor(dkgreen) msize(vsmall)) ///
    (connected share3 yq, lcolor(gs8) mcolor(gs8) msize(vsmall)) ///
    (connected share4 yq, lcolor(dkorange) mcolor(dkorange) msize(vsmall)) ///
    (connected share5 yq, lcolor(cranberry) mcolor(cranberry) msize(vsmall)), ///
    $qevents $qfmt ylabel(, angle(0)) ytitle("% of civilian core vacancies") ///
    legend(order(1 "Kyiv city" 2 "Low exposure" 3 "Middle" 4 "High" 5 "Occupied / no alarm data") rows(1) size(small) position(6)) ///
    note("Exposure: raion's share of hours under alarm, Mar 2022 - Aug 2025; raions outside Kyiv city split at the 2021-vacancy-weighted terciles (about 28/48/24% of 2021 vacancies)." ///
    "$evnote", size(vsmall))
graph export "$fig/05_exposure_shares.pdf", replace
export delimited using "$tmp5/05_exposure_shares.csv", replace

* 4b. Is the shift within employers or between them? Change in the share of core
*     vacancies of employers (id, no agency) in (i) the West and (ii) high-exposure or
*     occupied raions, 2021 (P0) to Jan 2023 - Oct 2026 (P1), split as in Foster,
*     Haltiwanger and Krizan (2001):
*       within   = sum over continuing employers of w0 * (s1 - s0)   (they move their own posting)
*       between  = sum over continuing of (s0 - S0) * (w1 - w0)        (sheltered firms grow more)
*       cross    = sum over continuing of (s1 - s0) * (w1 - w0)
*       entry    = sum over entrants of w1 * (s1 - S0)
*       exit     = - sum over exiters of w0 * (s0 - S0)
*     w = employer's share of all employer vacancies in the period, s = share of its
*     vacancies in the place, S0 = aggregate share in P0. Sampled vacancies.
*     Output: 05_relocation_fhk (.xlsx, .tex)
use `rq' if core & panel_candidate & area < . & P < ., clear
gen byte west  = area == 2
gen byte front = inlist(expo, 4, 5) if expo < .
tempfile fhkin
save `fhkin'
tempname pf
tempfile fhk
postfile `pf' str12 outcome S0 S1 within between cross entry exit using `fhk', replace
foreach y in west front {
    use `fhkin' if `y' < ., clear
    collapse (rawsum) n = one (mean) s = `y', by(notebook_id P)
    reshape wide n s, i(notebook_id) j(P)
    quietly {
        gen byte cont = n0 < . & n1 < .
        foreach k in 0 1 {
            replace n`k' = 0 if n`k' == .
            summarize n`k', meanonly
            gen w`k' = n`k' / r(sum)
            gen ws`k' = w`k' * s`k'
            summarize ws`k', meanonly
            local S`k' = r(sum)
        }
        gen c_within  = w0 * (s1 - s0) if cont
        gen c_between = (s0 - `S0') * (w1 - w0) if cont
        gen c_cross   = (s1 - s0) * (w1 - w0) if cont
        gen c_entry   = w1 * (s1 - `S0') if n0 == 0
        gen c_exit    = -w0 * (s0 - `S0') if n1 == 0
        foreach c in within between cross entry exit {
            summarize c_`c', meanonly
            local `c' = r(sum)
        }
    }
    assert abs(`within' + `between' + `cross' + `entry' + `exit' - (`S1' - `S0')) < 1e-6
    post `pf' ("`y'") (`S0') (`S1') (`within') (`between') (`cross') (`entry') (`exit')
}
postclose `pf'
use `fhk', clear
foreach v in S0 S1 within between cross entry exit {
    replace `v' = 100 * `v'
}
gen change = S1 - S0
replace outcome = "West" if outcome == "west"
replace outcome = "High exposure or occupied" if outcome == "front"
order outcome S0 S1 change within between cross entry exit
format S0 S1 change within between cross entry exit %6.2f
list, noobs
label var outcome "Share of employer vacancies in"
label var S0      "2021, %"
label var S1      "2023-26, %"
label var change  "Change, pp"
label var within  "Within employers, pp"
label var between "Between continuing, pp"
label var cross   "Cross term, pp"
label var entry   "Entry, pp"
label var exit    "Exit, pp"
export_table using "$tab/05_relocation_fhk", ///
    title("Change in the geographic share of civilian core vacancies of employers, 2021 vs Jan 2023 - Oct 2026: within vs between employers")

* 4c. Continuing employers with 3+ sampled vacancies in each period: share of their
*     vacancies in their 2021 main macro-area, 2021 and 2023-26, and share posting in
*     more than one oblast. A fall in the own-area share in the East and South = the
*     employer moved or spread its hiring away from there.
*     Output: 05_relocation_within (.xlsx, .tex)
use `rq' if core & panel_candidate & area < . & P < ., clear
encode oblast_en, gen(obl)
bysort notebook_id P: gen n = _N
bysort notebook_id P obl: gen byte tag_obl = _n == 1
bysort notebook_id P: egen n_obl = total(tag_obl)
gen area0 = area if P == 0
bysort notebook_id: egen main0 = mode(area0), minmode
gen byte in_main = area == main0
collapse (first) n n_obl main0 (mean) in_main, by(notebook_id P)
reshape wide n n_obl in_main, i(notebook_id) j(P)
keep if n0 >= 3 & n1 >= 3 & n0 < . & n1 < .
gen byte multi0 = n_obl0 > 1
gen byte multi1 = n_obl1 > 1
gen one = 1
collapse (sum) firms = one (mean) in_main0 in_main1 multi0 multi1, by(main0)
foreach v in in_main0 in_main1 multi0 multi1 {
    replace `v' = 100 * `v'
}
label define area_lbl 1 "Kyiv city" 2 "West" 3 "Center-North" 4 "South" 5 "East", replace  // dropped by collapse
label values main0 area_lbl
decode main0, gen(area_s)
drop main0
order area_s firms in_main0 in_main1 multi0 multi1
format firms %9.0fc
format in_main* multi* %5.1f
list, noobs
label var area_s   "Main macro-area in 2021"
label var firms    "Employers"
label var in_main0 "Vacancies in that area, 2021, %"
label var in_main1 "... 2023-26, %"
label var multi0   "Posting in 2+ oblasts, 2021, %"
label var multi1   "... 2023-26, %"
export_table using "$tab/05_relocation_within", ///
    title("Continuing employers (3+ sampled core vacancies in 2021 and in Jan 2023 - Oct 2026): where they post")

* 4d. Other ways to shelter: remote work, relocation, shelters/generators, housing,
*     quarterly. Output: 05_adaptation.pdf
use `rq' if core, clear
qshares remote tx_reloc shelter_air power housing, file(05_adaptation) ///
    ytitle("% of civilian core vacancies") ///
    legend(order(1 "Remote work possible" 2 "Mentions relocation of the business" ///
    3 "Air-raid shelter" 4 "Generator / backup power / Starlink" 5 "Housing provided") ///
    rows(2) size(small) position(6)) ///
    note("Text of the ad, robota.ua badge (shelter, power, housing) or tag (remote, housing)." "$evnote")

* 4e. The same and draft deferment by exposure group, 2021 vs 2023-26.
*     Output: 05_adaptation_by_exposure (.xlsx, .tex)
use `rq' if core & expo < . & P < ., clear
collapse (mean) remote shelter_air power tx_reloc defer [pw=weight], by(expo P)
foreach v in remote shelter_air power tx_reloc defer {
    replace `v' = 100 * `v'
}
reshape wide remote shelter_air power tx_reloc defer, i(expo) j(P)
decode expo, gen(expo_s)
order expo_s remote0 remote1 shelter_air0 shelter_air1 power0 power1 tx_reloc0 tx_reloc1 defer0 defer1
drop expo
format remote* shelter_air* power* tx_* defer* %5.1f
list, noobs
label var expo_s      "Exposure group of the raion"
label var remote0     "Remote, 2021, %"
label var remote1     "Remote, 2023-26, %"
label var shelter_air0 "Air-raid shelter, 2021, %"
label var shelter_air1 "Air-raid shelter, 2023-26, %"
label var power0      "Backup power, 2021, %"
label var power1      "Backup power, 2023-26, %"
label var tx_reloc0   "Relocation, 2021, %"
label var tx_reloc1   "Relocation, 2023-26, %"
label var defer0      "Draft deferment, 2021, %"
label var defer1      "Draft deferment, 2023-26, %"
export_table using "$tab/05_adaptation_by_exposure", ///
    title("Civilian core vacancies mentioning remote work, air-raid shelters, backup power, relocation and draft deferment, by exposure group")

* 4f. Flows between oblasts within employers. Continuing employers (id, no agency) with
*     $flow_k+ sampled core vacancies on each side of a comparison. For each employer e
*     and oblast o: share of its vacancies there on each side, s0 and s1, and d = s1 - s0.
*     Oblasts where d < 0 send, oblasts where d > 0 receive; the employer's flow from i
*     to j is loss_i x gain_j / R, where R = sum of its gains (= sum of its losses) is the
*     share of its vacancies that changed oblast (0 = same geography, 1 = all elsewhere).
*     Averaged over employers (each counts once): flows in percentage points of the
*     average employer's vacancies. The map shows NET flows between each pair of oblasts
*     (i to j minus j to i), which cancels most of the noise from small samples.
*     Windows of the same length and calendar months on both sides (16 Nov 2026): with a
*     longer second window an employer shows more of its places there, which spreads its
*     shares from its main city to others, a flow that is not there. A simple
*     illustration: sample sizes still differ by year with the volume of posting.
*     Comparisons (one column each in the table):
*       placebo  Oct 2020 - May 2021 vs Jun 2021 - Jan 2022 (8 months each, pre-war):
*                what sampling noise and normal churn produce by themselves
*       2023, 2024, 2025   2021 vs that year
*       2026     Jan-Oct 2021 vs Jan-Oct 2026
*     Map: placebo and 2021 vs 2025 (latest full year).
*     Oblast points: the city with most sampled core vacancies in 2021 (Kyiv city apart).
*     Output: 05_relocation_flows (.xlsx, .tex), 05_relocation_flows_map.pdf;
*             data in 05_relocation_flows.csv (all net flows), 05_relocation_flows_oblast.csv
global flow_k     = 3      // minimum sampled vacancies on each side
global flow_top   = 15     // arrows drawn: the 15 largest net flows of 2021 vs 2025;
                           // the placebo panel draws its flows above the same threshold

import delimited using "$temp/robota_city_raion.csv", varnames(1) clear
keep city_id lat lon
tempfile cityxy
save `cityxy'

use `rq' if core & panel_candidate & oblast_en != "" & oblast_en != "Crimea", clear
encode oblast_en, gen(obl)
preserve                                     // oblast point and macro-area
    keep if year == 2021 & city_id < .
    contract obl area city_id
    bysort obl (_freq): keep if _n == _N
    merge 1:1 city_id using `cityxy', keep(match) nogenerate
    decode city_id, gen(city)
    keep obl area city lat lon
    tempfile oblxy
    save `oblxy'
restore
gen byte Q = 0 if inrange(created_date, td(01oct2020), td(31may2021))
replace Q = 1 if inrange(created_date, td(01jun2021), td(31jan2022))
foreach y in 2023 2024 2025 {
    gen byte Y`y' = 0 if inrange(ym, tm(2021m1), tm(2021m12))
    replace Y`y' = 1 if inrange(ym, tm(`y'm1), tm(`y'm12))
}
gen byte Y2026 = 0 if inrange(ym, tm(2021m1), tm(2021m10))
replace Y2026 = 1 if inrange(ym, tm(2026m1), tm(2026m10))
keep notebook_id obl one Q Y2023 Y2024 Y2025 Y2026
tempfile flowin
save `flowin'

local comps Q Y2023 Y2024 Y2025 Y2026
tempname pf
tempfile fstats flows oblnet
postfile `pf' str8 comp emp vac0 vac1 R_mean R_vw R0 R50 net1 net2 net3 net4 net5 using `fstats', replace
local first = 1
foreach c of local comps {
    * employers with $flow_k+ on each side
    use `flowin' if `c' < ., clear
    rename `c' side
    bysort notebook_id: egen n0 = total(side == 0)
    bysort notebook_id: egen n1 = total(side == 1)
    keep if n0 >= $flow_k & n1 >= $flow_k
    keep notebook_id obl one side n0 n1
    collapse (rawsum) n = one (first) n0 n1, by(notebook_id side obl)
    gen s = n / cond(side == 0, n0, n1)
    drop n
    reshape wide s, i(notebook_id obl) j(side)
    foreach k in 0 1 {
        replace s`k' = 0 if s`k' == .
    }
    gen d = s1 - s0
    gen gain = max(d, 0)
    gen loss = max(-d, 0)
    bysort notebook_id: egen R = total(gain)
    egen byte tag_e = tag(notebook_id)
    quietly {
        count if tag_e
        local E = r(N)
        summarize R if tag_e, meanonly
        local R_mean = 100 * r(mean)
        summarize R [aw=n0] if tag_e, meanonly
        local R_vw = 100 * r(mean)
        count if tag_e & R < 1e-9
        local R0 = 100 * r(N) / `E'
        count if tag_e & R >= 0.5 - 1e-9
        local R50 = 100 * r(N) / `E'
        summarize n0 if tag_e, meanonly
        local vac0 = r(sum)
        summarize n1 if tag_e, meanonly
        local vac1 = r(sum)
    }
    * net change in the average employer's share, by oblast and macro-area (pp)
    preserve
        collapse (sum) d, by(obl)
        replace d = 100 * d / `E'
        merge 1:1 obl using `oblxy', keep(master match) keepusing(area) nogenerate
        forvalues a = 1/5 {
            summarize d if area == `a', meanonly
            local net`a' = r(sum)
        }
        gen comp = "`c'"
        keep comp obl d
        if `first' save `oblnet'
        else {
            append using `oblnet'
            save `oblnet', replace
        }
    restore
    post `pf' ("`c'") (`E') (`vac0') (`vac1') (`R_mean') (`R_vw') (`R0') (`R50') ///
        (`net1') (`net2') (`net3') (`net4') (`net5')

    * bilateral flows: every sending oblast of an employer to every receiving one
    preserve
        keep if loss > 0
        keep notebook_id obl loss R
        rename obl o
        tempfile orig
        save `orig'
    restore
    keep if gain > 0
    keep notebook_id obl gain
    rename obl dd
    joinby notebook_id using `orig'
    gen f = loss * gain / R
    collapse (sum) f, by(o dd)
    replace f = 100 * f / `E'
    gen comp = "`c'"
    if `first' save `flows'
    else {
        append using `flows'
        save `flows', replace
    }
    local first = 0
}
postclose `pf'

* table: comparisons across, statistics down
use `fstats', clear
gen long ord = .
local i = 0
foreach c of local comps {
    local ++i
    replace ord = `i' if comp == "`c'"
}
collapse (mean) emp vac0 vac1 R_mean R_vw R0 R50 net1 net2 net3 net4 net5, by(ord comp)
sort ord
drop ord
replace comp = "Pre-war placebo"     if comp == "Q"
replace comp = "2021 vs 2023"        if comp == "Y2023"
replace comp = "2021 vs 2024"        if comp == "Y2024"
replace comp = "2021 vs 2025"        if comp == "Y2025"
replace comp = "Jan-Oct 2021 vs 2026" if comp == "Y2026"
format emp vac0 vac1 %9.0fc
format R_* R0 R50 net* %6.1f
list, noobs abbreviate(10)
label var emp    "Continuing employers"
label var vac0   "Sampled vacancies, first window"
label var vac1   "Sampled vacancies, second window"
label var R_mean "Vacancies that changed oblast, mean over employers, %"
label var R_vw   "... weighted by first-window vacancies, %"
label var R0     "Employers with the same oblast mix, %"
label var R50    "Employers with half or more elsewhere, %"
label var net1   "Net change in share: Kyiv city, pp"
label var net2   "... West, pp"
label var net3   "... Center-North, pp"
label var net4   "... South, pp"
label var net5   "... East, pp"
export_transposed using "$tab/05_relocation_flows", ///
    title("Relocation within employers: oblast mix of continuing employers ($flow_k+ sampled core vacancies on each side; windows of equal length). Placebo: Oct 2020 - May 2021 vs Jun 2021 - Jan 2022")

use `oblnet', clear
collapse (sum) d, by(comp obl)
merge m:1 obl using `oblxy', keep(master match) nogenerate
label values obl obl
order comp obl city area d
format d %6.2f
export delimited using "$tmp5/05_relocation_flows_oblast.csv", replace

* net flows between each pair of oblasts
use `flows', clear
gen a = min(o, dd)
gen b = max(o, dd)
gen sf = cond(o == a, f, -f)
collapse (sum) net = sf (sum) gross = f, by(comp a b)
gen from = cond(net >= 0, a, b)
gen to   = cond(net >= 0, b, a)
replace net = abs(net)
drop a b
replace comp = "P" if comp == "Y2025"      // the war panel of the map
tempfile flows
save `flows'

* map of net flows
use `flows', clear
foreach e in from to {
    rename `e' obl
    merge m:1 obl using `oblxy', keep(master match) keepusing(city lat lon) nogenerate
    rename (obl city lat lon) (`e' city_`e' lat_`e' lon_`e')
}
gsort comp -net
format net gross %6.2f
list comp city_from city_to net gross if comp == "P" in 1/25, noobs sep(0)
export delimited comp city_from city_to net gross lat_* lon_* using "$tmp5/05_relocation_flows.csv", replace
quietly summarize net if comp == "P"
local nmax = r(max)
preserve
    keep if comp == "P"
    gsort -net
    local thr = net[$flow_top]
restore
display "Arrows drawn: net flow >= " %5.3f `thr' " pp (largest: " %5.3f `nmax' ")"
keep if net >= `thr'
* shorten arrows so they stop short of the city dots
gen x1 = lon_from + 0.07 * (lon_to - lon_from)
gen y1 = lat_from + 0.07 * (lat_to - lat_from)
gen x2 = lon_to - 0.07 * (lon_to - lon_from)
gen y2 = lat_to - 0.07 * (lat_to - lat_from)
gen w = 0.5 + 3.5 * net / `nmax'           // line width in points, same scale in both panels
foreach c in Q P {
    local arr_`c' ""
    forvalues i = 1/`=_N' {
        if comp[`i'] != "`c'" continue
        local arr_`c' `arr_`c'' (pcarrowi `=y1[`i']' `=x1[`i']' `=y2[`i']' `=x2[`i']', ///
            lcolor(navy%75) mcolor(navy%75) lwidth(`=w[`i']'pt) msize(`=1.2 + 0.4 * w[`i']') barbsize(`=0.6 + 0.25 * w[`i']'))
    }
    count if comp == "`c'"
    local n_`c' = r(N)
}
* background: borders, oblast points with the cities' names
import delimited using "$temp/ua_oblast_borders.csv", varnames(1) clear
rename (lon lat) (b_lon b_lat)
gen long order = _n
append using `oblxy'
local titleQ "A. Pre-war placebo: Oct 2020 - May 2021 vs Jun 2021 - Jan 2022"
local titleP "B. War: 2021 vs 2025"
foreach c in Q P {
    twoway (line b_lat b_lon if kind != "country", sort(order) cmissing(n) lcolor(gs12) lwidth(vthin)) ///
        (line b_lat b_lon if kind != "oblast", sort(order) cmissing(n) lcolor(gs7) lwidth(thin)) ///
        `arr_`c'' ///
        (scatter lat lon, msymbol(o) msize(vsmall) mcolor(black) mlabel(city) mlabsize(tiny) ///
            mlabcolor(gs6) mlabposition(6)), ///
        xscale(range(22 40.5) off) yscale(range(44 53) off) aspectratio(0.72) ///
        xlabel(none, nogrid) ylabel(none, nogrid) ///
        title("`title`c''", size(medsmall)) subtitle("`n_`c'' net flows above the threshold", size(small)) ///
        plotregion(lstyle(none)) legend(off) name(flow`c', replace) nodraw
}
graph combine flowQ flowP, cols(2) imargin(small) xsize(10) ysize(4.8) ///
    note("Net flows of vacancy shares between oblasts within continuing employers ($flow_k+ sampled civilian core vacancies on each side), averaged over employers." ///
    "Windows of equal length on both sides: 8 months in A, 12 in B." ///
    "Arrow width proportional to the flow (largest: `: display %4.2f `nmax'' pp of the average employer's vacancies). Drawn: the $flow_top largest flows of panel B and, in panel A, the flows above the same" ///
    "threshold (`: display %4.2f `thr'' pp). Each oblast is placed at its city with most sampled vacancies in 2021; Kyiv city apart from Kyiv oblast.", size(vsmall))
graph export "$fig/05_relocation_flows_map.pdf", replace
graph drop flowQ flowP

* --- Step 5. RQ3 Wages: do pay differentials widen? -----------------------------------
* 5a. Spread of the posted real wage, quarterly: log-point gaps between percentiles.
*     Output: 05_wage_spread.pdf; data 05_wage_spread.csv
use `rq' if core & lw_real < . & yq <= $last_q, clear
collapse (p10) p10 = lw_real (p50) p50 = lw_real (p90) p90 = lw_real [pw=weight], by(yq)
gen d9010 = 100 * (p90 - p10)
gen d9050 = 100 * (p90 - p50)
gen d5010 = 100 * (p50 - p10)
twoway (connected d9010 yq, lcolor(navy) mcolor(navy) msize(vsmall)) ///
    (connected d9050 yq, lcolor(dkorange) mcolor(dkorange) msize(vsmall)) ///
    (connected d5010 yq, lcolor(cranberry) mcolor(cranberry) msize(vsmall)), ///
    $qevents $qfmt ylabel(, angle(0)) ytitle("Log points x 100") ///
    legend(order(1 "90th - 10th percentile" 2 "90th - 50th" 3 "50th - 10th") rows(1) position(6)) ///
    note("Posted monthly real wage (2021 UAH), civilian core." "$evnote", size(vsmall))
graph export "$fig/05_wage_spread.pdf", replace
export delimited using "$tmp5/05_wage_spread.csv", replace

* 5b. By year: percentile gaps and SD of the log real wage; and the same gaps within
*     the ISCO sub-major group x professional level cells (median over cells of
*     each cell's 90-10 gap, cells with 50+ sampled wages in the year). If the overall
*     spread grows but the within-cell spread does not, the gaps are between jobs.
*     Output: 05_wage_dispersion (.xlsx, .tex)
use `rq' if core & lw_real < ., clear
preserve
    keep if isco2 < .
    collapse (p10) c10 = lw_real (p90) c90 = lw_real (rawsum) nc = one [aw=weight], ///
        by(year isco2 prof_level_id)
    keep if nc >= 50
    gen c9010 = 100 * (c90 - c10)
    collapse (p50) d9010_cell = c9010 (count) cells = c9010, by(year)
    tempfile cells
    save `cells'
restore
collapse (p10) p10 = lw_real (p50) p50 = lw_real (p90) p90 = lw_real (sd) sd_raw = lw_real ///
    (rawsum) n = one [aw=weight], by(year)
merge 1:1 year using `cells', nogenerate
gen d9010 = 100 * (p90 - p10)
gen d9050 = 100 * (p90 - p50)
gen d5010 = 100 * (p50 - p10)
replace sd_raw = 100 * sd_raw
keep year n d9010 d9050 d5010 sd_raw d9010_cell cells
order year n d9010 d9050 d5010 sd_raw d9010_cell cells
format n cells %9.0fc
format d* sd* %5.1f
list, noobs sep(0)
yearlab year
label var year       "Year"
label var n          "Sampled vacancies with wage"
label var d9010      "90-10 gap, log pts"
label var d9050      "90-50 gap"
label var d5010      "50-10 gap"
label var sd_raw     "SD of log wage x 100"
label var d9010_cell "90-10 gap within cells (median)"
label var cells      "Cells"
export_transposed using "$tab/05_wage_dispersion", ///
    title("Dispersion of posted real wages, civilian core (2026: Jan-Sep). Cells: ISCO sub-major group x professional level, 50+ wages")

* 5c. Regional gaps: median real wage of each exposure group relative to Kyiv city, by
*     year (raw medians, no adjustment for the job mix).
*     Output: 05_wage_gaps_exposure.pdf; data 05_wage_gaps_exposure.csv
use `rq' if core & wage_real < . & expo < . & year >= 2021, clear
collapse (p50) wr = wage_real (rawsum) n = one [pw=weight], by(year expo)
bysort year (expo): gen gap = 100 * (wr / wr[1] - 1)       // expo 1 = Kyiv city
list, noobs sepby(year)
twoway (connected gap year if expo == 2, lcolor(dkgreen) mcolor(dkgreen)) ///
    (connected gap year if expo == 3, lcolor(gs8) mcolor(gs8)) ///
    (connected gap year if expo == 4, lcolor(dkorange) mcolor(dkorange)) ///
    (connected gap year if expo == 5 & year <= 2022, lcolor(cranberry) mcolor(cranberry)), ///
    yline(0, lcolor(gs12)) xline(2022.15, lcolor(cranberry)) xlabel(2021(1)2026) xtitle("") ylabel(, angle(0)) ///
    ytitle("Median real wage, % difference from Kyiv city") ///
    legend(order(1 "Low exposure" 2 "Middle" 3 "High" 4 "Occupied / no alarm data") rows(1) position(6)) ///
    note("Civilian core, posted monthly wage deflated by the NBU CPI; raw medians. 2026: Jan-Sep." ///
    "Occupied / no alarm data shown to 2022 only (fewer than 10 sampled wages a year after).", size(vsmall))
graph export "$fig/05_wage_gaps_exposure.pdf", replace
export delimited using "$tmp5/05_wage_gaps_exposure.csv", replace

* 5d. Occupations: change in vacancies and in the median real wage, 2021 vs 2023-26.
*     By ISCO major group. Do the manual groups that mobilization drains most (7 crafts,
*     8 operators and drivers; mostly men) raise pay more?
*     Output: 05_occupation_change (.xlsx, .tex), 05_occupation_wage_vs_vacancies.pdf
use `rq' if core & P < ., clear
gen wr1 = wage_real if P == 1 & ym <= tm(2026m9)
gen wr0 = wage_real if P == 0
gen e0 = weight * (P == 0)
gen e1 = weight * (P == 1)
gen hw0 = has_wage if P == 0
gen hw1 = has_wage if P == 1
collapse (sum) e0 e1 (p50) wr0 wr1 (mean) hw0 hw1 [pw=weight], by(isco1g)
gen vac_pct  = 100 * ((e1 / `m_post') / (e0 / `m_base') - 1)
gen wage_pct = 100 * (wr1 / wr0 - 1)
gen sh0 = 100 * e0 / `m_base'
replace hw0 = 100 * hw0
replace hw1 = 100 * hw1
decode isco1g, gen(occ)
gsort -wage_pct
list occ vac_pct wage_pct wr0 wr1 hw0 hw1, noobs sep(0)
export delimited using "$tmp5/05_occupation_change.csv", replace
gen byte mt = inlist(isco1g, 7, 8)
* figure: groups with 300+ core vacancies a month in 2021 only (armed-forces titles at
* civilian employers and agriculture are tiny; they stay in the table). Short labels;
* positions (clock) set by hand so that labels of nearby points do not overlap.
gen big = e0 / `m_base' >= 300
gen occs = occ
replace occs = "Crafts" if isco1g == 7
replace occs = "Operators, drivers" if isco1g == 8
replace occs = "Technicians" if isco1g == 3
replace occs = "Service, sales" if isco1g == 5
replace occs = "Clerical" if isco1g == 4
replace occs = "Elementary" if isco1g == 9
gen byte lpos = 3
replace lpos = 11 if isco1g == 7      // crafts
replace lpos = 4  if isco1g == 8      // operators
replace lpos = 9  if isco1g == 2      // professionals
replace lpos = 12 if isco1g == 3      // technicians
replace lpos = 4  if isco1g == 99     // not classified
twoway (scatter wage_pct vac_pct if mt & big, mcolor(cranberry) mlabel(occs) mlabvposition(lpos) mlabsize(vsmall) mlabcolor(cranberry)) ///
    (scatter wage_pct vac_pct if !mt & big, mcolor(navy) mlabel(occs) mlabvposition(lpos) mlabsize(vsmall) mlabcolor(navy)), ///
    xline(0, lcolor(gs12)) ylabel(, angle(0)) xscale(range(-60 5)) ///
    xtitle("% change in vacancies per month, 2023-26 vs 2021") ytitle("% change in median real wage") ///
    legend(order(1 "Crafts, operators and drivers (ISCO 7-8)" 2 "Other") rows(1) position(6)) ///
    note("Civilian core; ISCO-08 major group from the job title. Real wages to Sep 2026." ///
    "Groups with 300+ vacancies a month in 2021 (armed forces and agriculture are in the table only).", size(vsmall))
graph export "$fig/05_occupation_wage_vs_vacancies.pdf", replace
keep occ e0 vac_pct wr0 wr1 wage_pct hw0 hw1
replace e0 = e0 / `m_base'
order occ e0 vac_pct wr0 wr1 wage_pct hw0 hw1
format e0 wr0 wr1 %9.0fc
format vac_pct wage_pct hw0 hw1 %6.1f
label var occ      "ISCO-08 major group (job title)"
label var e0       "Vacancies per month, 2021"
label var vac_pct  "Change in vacancies, %"
label var wr0      "Median real wage, 2021"
label var wr1      "Median real wage, 2023-26"
label var wage_pct "Change in wage, %"
label var hw0      "With wage, 2021, %"
label var hw1      "With wage, 2023-26, %"
export_table using "$tab/05_occupation_change", ///
    title("Civilian core by ISCO-08 major group: vacancies and median posted real wage (2021 UAH), 2021 vs Jan 2023 - Oct 2026")

* 5e. Experience premium: median real wage by required experience, 2021 = 100.
*     Output: 05_wage_by_experience.pdf; data 05_wage_by_experience.csv
use `rq' if core & wage_real < . & year >= 2021, clear
gen byte expcat = 2
replace expcat = 1 if exp_none
replace expcat = 3 if exp_req & !exp3
replace expcat = 4 if exp3
collapse (p50) wr = wage_real [pw=weight], by(year expcat)
bysort expcat (year): gen idx = 100 * wr / wr[1]
list, noobs sepby(expcat)
twoway (connected idx year if expcat == 1, lcolor(dkgreen) mcolor(dkgreen)) ///
    (connected idx year if expcat == 2, lcolor(gs8) mcolor(gs8)) ///
    (connected idx year if expcat == 3, lcolor(dkorange) mcolor(dkorange)) ///
    (connected idx year if expcat == 4, lcolor(navy) mcolor(navy)), ///
    yline(100, lcolor(gs12)) xline(2022.15, lcolor(cranberry)) xlabel(2021(1)2026) xtitle("") ylabel(, angle(0)) ///
    ytitle("Median real wage, 2021 = 100") ///
    legend(order(1 "No experience needed" 2 "Not stated" 3 "Under 3 years required" 4 "3+ years") rows(1) size(small) position(6)) ///
    note("Civilian core, posted monthly wage deflated by the NBU CPI. 2026: Jan-Sep.", size(vsmall))
graph export "$fig/05_wage_by_experience.pdf", replace
export delimited using "$tmp5/05_wage_by_experience.csv", replace

* --- Step 6. RQ4 Upskilling: do requirements rise? ------------------------------------
* 6a. Requirements, quarterly. Output: 05_requirements.pdf, 05_requirements_easing.pdf
use `rq' if core, clear
qshares exp_req exp3 higher_ed english soft, file(05_requirements) ///
    ytitle("% of civilian core vacancies") ///
    legend(order(1 "Experience required" 2 "3+ years" 3 "Higher education" 4 "English" ///
    5 "Software skill") rows(1) size(small) position(6))
qshares exp_none training intern, file(05_requirements_easing) ///
    ytitle("% of civilian core vacancies") ///
    legend(order(1 "No experience needed" 2 "Training offered" 3 "Internship") rows(1) position(6))

* 6b. By exposure group, 2021 vs 2023-26. Output: 05_requirements_by_exposure (.xlsx, .tex)
use `rq' if core & expo < . & P < ., clear
collapse (mean) exp_req exp_none higher_ed english [pw=weight], by(expo P)
foreach v in exp_req exp_none higher_ed english {
    replace `v' = 100 * `v'
}
reshape wide exp_req exp_none higher_ed english, i(expo) j(P)
foreach v in exp_req exp_none higher_ed english {
    gen d_`v' = `v'1 - `v'0
}
decode expo, gen(expo_s)
keep expo_s exp_req0 d_exp_req exp_none0 d_exp_none higher_ed0 d_higher_ed english0 d_english
order expo_s exp_req0 d_exp_req exp_none0 d_exp_none higher_ed0 d_higher_ed english0 d_english
format exp_* d_* higher* english* %5.1f
list, noobs
label var expo_s      "Exposure group of the raion"
label var exp_req0    "Experience required, 2021, %"
label var d_exp_req   "Change, pp"
label var exp_none0   "No experience, 2021, %"
label var d_exp_none  "Change, pp"
label var higher_ed0  "Higher education, 2021, %"
label var d_higher_ed "Change, pp"
label var english0    "English, 2021, %"
label var d_english   "Change, pp"
export_table using "$tab/05_requirements_by_exposure", ///
    title("Requirements in civilian core vacancies by exposure group: 2021 and change to Jan 2023 - Oct 2026")

* --- Step 7. RQ5 Substitution: whom do employers turn to? ------------------------------
* 7a. Quarterly shares. Output: 05_targeting_gender.pdf, 05_targeting_groups.pdf,
*     05_mobilization.pdf
use `rq' if core, clear
qshares female_seek male_seek fem_title, file(05_targeting_gender) ///
    ytitle("% of civilian core vacancies") colors(cranberry navy dkorange) ///
    legend(order(1 "Seeks women explicitly" 2 "Seeks men explicitly" 3 "Feminine job title") rows(1) position(6)) ///
    note("Seeks = a hiring verb next to women/men (incl. 'women and men'). Feminine title: the title gives the feminine form of the job (e.g. driver m./f.)." ///
    "The 2022 drop in explicit gender words is probably platform moderation." "$evnote")
qshares veteran disab student pension idp, file(05_targeting_groups) ///
    ytitle("% of civilian core vacancies") ///
    legend(order(1 "Veterans" 2 "People with disabilities" 3 "Students" 4 "Pensioners" 5 "Displaced (IDPs)") rows(1) size(small) position(6))
qshares defer tx_milreg tx_critical tx_age_cap, file(05_mobilization) ///
    ytitle("% of civilian core vacancies") colors(navy dkorange dkgreen gs8) ///
    legend(order(1 "Draft deferment offered" 2 "Military registration papers" 3 "Critical enterprise" ///
    4 "Age cap") rows(1) size(small) position(6))

* 7b. Women in male-typed jobs: feminine titles and explicit search for women, in
*     male-typed occupations (ISCO 54, 71, 72, 74, 83, 93; see header) vs the rest. Output: 05_women_male_jobs.pdf
use `rq' if core, clear
gen byte fem_any = fem_title | female_seek
gen byte fa_m = fem_any if male_typed
gen byte fa_o = fem_any if !male_typed
gen byte df_m = defer if male_typed
gen byte df_o = defer if !male_typed
qshares fa_m fa_o df_m df_o, file(05_women_male_jobs) colors(cranberry dkorange navy eltblue) ///
    ytitle("% of civilian core vacancies in the group") ///
    legend(order(1 "Women: male-typed jobs" 2 "Women: other jobs" 3 "Draft deferment: male-typed" ///
    4 "Draft deferment: other") rows(2) size(small) position(6)) ///
    note("Women = feminine job title or explicit search for women. Male-typed: ISCO-08 protective services, building, metal/machinery and electrical trades, drivers, laborers." ///
    "$evnote")

* 7c. By occupation group: 2021 vs Jan 2025 - Oct 2026 (after the mobilization law).
*     Output: 05_targeting_by_occupation (.xlsx, .tex)
use `rq' if core & (year == 2021 | ym >= tm(2025m1)), clear
gen byte late = ym >= tm(2025m1)
gen byte fem_any = fem_title | female_seek
collapse (mean) fem_any male_seek defer veteran student [pw=weight], by(isco1g late)
foreach v in fem_any male_seek defer veteran student {
    replace `v' = 100 * `v'
}
reshape wide fem_any male_seek defer veteran student, i(isco1g) j(late)
decode isco1g, gen(occ)
order occ fem_any0 fem_any1 male_seek0 male_seek1 defer0 defer1 veteran0 veteran1 student0 student1
drop isco1g
format fem_* male_* defer* veteran* student* %5.1f
list, noobs sep(0)
label var occ        "ISCO-08 major group (job title)"
label var fem_any0   "Women, 2021, %"
label var fem_any1   "Women, 2025-26, %"
label var male_seek0 "Men, 2021, %"
label var male_seek1 "Men, 2025-26, %"
label var defer0     "Deferment, 2021, %"
label var defer1     "Deferment, 2025-26, %"
label var veteran0   "Veterans, 2021, %"
label var veteran1   "Veterans, 2025-26, %"
label var student0   "Students, 2021, %"
label var student1   "Students, 2025-26, %"
export_table using "$tab/05_targeting_by_occupation", ///
    title("Civilian core vacancies by ISCO-08 major group: whom they address, 2021 vs Jan 2025 - Oct 2026")

* 7d. Draft deferment by industry, Jan 2025 - Oct 2026 (industries with 300+ sampled
*     core vacancies). Output: 05_deferment_by_industry (.xlsx, .tex)
use `rq' if core & ym >= tm(2025m1) & branch_id != 0, clear
collapse (mean) defer male_typed (rawsum) n = one [pw=weight], by(branch_id)
keep if n >= 300
replace defer = 100 * defer
replace male_typed = 100 * male_typed
decode branch_id, gen(industry)
gsort -defer
keep industry n defer male_typed
order industry n defer male_typed
format n %9.0fc
format defer male_typed %5.1f
list, noobs sep(0)
label var industry   "Employer industry"
label var n          "Sampled vacancies"
label var defer      "Draft deferment offered, %"
label var male_typed "Male-typed jobs, %"
export_table using "$tab/05_deferment_by_industry", ///
    title("Civilian core vacancies offering draft deferment by industry, Jan 2025 - Oct 2026")

* --- Step 8. RQ7 Military recruitment ------------------------------------------------------
* Military ads (grp 5: armed forces, National Guard, border guard, TCCs; 01 step 6),
* from 2023 (before, a handful). Unit type from the employer name, role from the title
* (00_text_features.py).
* 8a. Estimated military ads per quarter by unit type. Output: 05_military_units.pdf
use `rq' if grp == 5 & year >= 2023 & yq <= $last_q, clear
gen byte ut = mil_unit
replace ut = 0 if inlist(mil_unit, 7, 8)              // small groups into "other"
collapse (sum) est = one [pw=weight], by(yq ut)
reshape wide est, i(yq) j(ut)
foreach k in 0 1 2 3 4 5 6 9 {
    capture gen est`k' = 0
    replace est`k' = 0 if est`k' == .
}
gen s1 = est1
gen s2 = s1 + est9
gen s3 = s2 + est2
gen s4 = s3 + est3
gen s5 = s4 + est4
gen s6 = s5 + est5
gen s7 = s6 + est6
gen s8 = s7 + est0
twoway (bar s8 yq, color(gs12) barwidth(0.8)) (bar s7 yq, color(olive_teal) barwidth(0.8)) ///
    (bar s6 yq, color(dkgreen) barwidth(0.8)) (bar s5 yq, color(maroon) barwidth(0.8)) ///
    (bar s4 yq, color(navy) barwidth(0.8)) (bar s3 yq, color(dkorange) barwidth(0.8)) ///
    (bar s2 yq, color(eltblue) barwidth(0.8)) (bar s1 yq, color(gs6) barwidth(0.8)), ///
    xline(`=tq(2024q2)', lcolor(gs9) lpattern(dash)) xlabel(`=tq(2023q1)'(2)`=tq(2026q3)', format(%tqCCYY!qq) labsize(small)) ///
    xtitle("") ylabel(, format(%9.0fc) angle(0)) ytitle("Estimated military ads per quarter") ///
    legend(order(8 "TCC (draft offices)" 7 "Recruiting centers (other)" 6 "Drone forces" 5 "National Guard" ///
    4 "Assault, airborne, marines" 3 "Mechanized, tank, artillery" 2 "Territorial defense" 1 "Other") ///
    cols(3) size(small) position(6)) note("Dashed: mobilization law (May 2024). Unit type from the employer name.", size(vsmall))
graph export "$fig/05_military_units.pdf", replace
drop s*
export delimited using "$tmp5/05_military_units.csv", replace

* 8b. Roles and unit types by year (shares of military ads), with mentions.
*     Output: 05_military_by_year (.xlsx, .tex)
use `rq' if grp == 5 & year >= 2023, clear
forvalues r = 0/7 {
    gen byte r`r' = mil_role == `r'
}
gen byte women = female_seek | fem_title
bysort year notebook_id: gen byte tag_emp = _n == 1 & notebook_id < .
collapse (rawsum) n = one tag_emp (mean) r0-r7 mil_1824 mil_choose women has_wage [pw=weight], by(year)
foreach v of varlist r0-r7 mil_1824 mil_choose women has_wage {
    replace `v' = 100 * `v'
}
order year n tag_emp r1 r3 r2 r4 r5 r6 r7 r0 has_wage mil_1824 mil_choose women
format n tag_emp %9.0fc
format r* mil_* women has_wage %5.1f
list, noobs sep(0)
yearlab year
label var year     "Year"
label var n        "Sampled military ads"
label var tag_emp  "Distinct employers (sampled)"
label var r1       "Drones, %"
label var r3       "Combat, %"
label var r2       "Medics, %"
label var r4       "Drivers, %"
label var r5       "Comms/EW/IT, %"
label var r6       "Engineering/trades, %"
label var r7       "Support, %"
label var r0       "Generic/other, %"
label var has_wage "With wage, %"
label var mil_1824 "Mentions 18-24 contract, %"
label var mil_choose "Choose unit/transfer, %"
label var women    "Addresses women, %"
export_transposed using "$tab/05_military_by_year", ///
    title("Military recruitment ads by year: roles (from the title) and content")

* 8c. Review list: the employers posting most military ads, 2024 - Oct 2026 (names in
*     Ukrainian, so not a paper table). Output: data/temp/descriptives/05_military_top_units.csv
use `rq' if grp == 5 & year >= 2024, clear
decode mil_unit, gen(unit_type)
collapse (rawsum) n = one (first) unit_type, by(company_name)
gsort -n
keep in 1/40
list company_name unit_type n in 1/20, noobs sep(0)
export delimited company_name unit_type n using "$tmp5/05_military_top_units.csv", replace

* 8d. Pay: median posted nominal wage, military vs civilian core, and share stating a
*     wage, quarterly from 2023. Output: 05_military_pay.pdf; data 05_military_pay.csv
use `rq' if inlist(grp, 1, 5) & year >= 2023 & yq <= $last_q, clear
gen wm = wage if grp == 5
gen wc = wage if grp == 1
gen hm = has_wage if grp == 5
gen hc = has_wage if grp == 1
collapse (p50) wm wc (mean) hm hc [pw=weight], by(yq)
replace hm = 100 * hm
replace hc = 100 * hc
twoway (connected wm yq, lcolor(cranberry) mcolor(cranberry)) (connected wc yq, lcolor(navy) mcolor(navy)) ///
    (line hm yq, yaxis(2) lcolor(cranberry) lpattern(dash)) (line hc yq, yaxis(2) lcolor(navy) lpattern(dash)), ///
    xline(`=tq(2024q2)', lcolor(gs9) lpattern(dash)) xlabel(`=tq(2023q1)'(2)`=tq(2026q3)', format(%tqCCYY!qq) labsize(small)) ///
    xtitle("") ylabel(, format(%9.0fc) angle(0)) ylabel(0(20)100, axis(2) angle(0)) ///
    ytitle("Median posted monthly wage, UAH") ytitle("% stating a wage (dashed)", axis(2)) ///
    legend(order(1 "Military: median wage" 2 "Civilian core: median wage" 3 "Military: % with wage" ///
    4 "Civilian core: % with wage") rows(2) size(small) position(6)) ///
    note("Nominal UAH. Dashed vertical: mobilization law (May 2024).", size(vsmall))
graph export "$fig/05_military_pay.pdf", replace
export delimited using "$tmp5/05_military_pay.csv", replace

* 8e. Where they recruit: military ads as % of all vacancies (all groups) by oblast,
*     Jan 2024 - Oct 2026. Output: 05_military_by_oblast.pdf; data 05_military_by_oblast.csv
use `rq' if ym >= tm(2024m1) & oblast_en != "" & oblast_en != "Crimea", clear
gen byte mil = grp == 5
collapse (mean) mil (rawsum) n_mil = mil [pw=weight], by(oblast_en)
replace mil = 100 * mil
gsort -mil
list, noobs sep(0)
graph hbar (asis) mil, over(oblast_en, sort(mil) descending label(labsize(small))) bar(1, color(cranberry)) ///
    blabel(bar, format(%4.1f) size(vsmall)) ytitle("Military ads, % of all vacancies, Jan 2024 - Oct 2026", size(small)) ///
    ysize(7) xsize(6.5)
graph export "$fig/05_military_by_oblast.pdf", replace
export delimited using "$tmp5/05_military_by_oblast.csv", replace

* 8f. Competition with civilian employers for the same skills: military ads as % of
*     military + civilian core ads, by matching job family and year.
*     Output: 05_military_competition (.xlsx, .tex)
use `rq' if inlist(grp, 1, 5) & year >= 2023, clear
gen byte fam = .
replace fam = 1 if (grp == 5 & mil_role == 4) | (grp == 1 & occ_code == "DRIVER")         // drivers
replace fam = 2 if (grp == 5 & mil_role == 2) | (grp == 1 & inlist(occ_code, "HEALTH_DOC", "HEALTH_ASSOC")) // medical
replace fam = 3 if (grp == 5 & mil_role == 6) | (grp == 1 & isco1 == 7)                  // trades
replace fam = 4 if (grp == 5 & mil_role == 5) | (grp == 1 & inlist(isco2, 25, 35))       // IT/comms
replace fam = 5 if (grp == 5 & mil_role == 7) | (grp == 1 & (isco1 == 4 | inlist(occ_code, "COOK", ///
    "ACCOUNT", "HR_PROF", "SOC_PSY", "LEGAL", "CLEANER")))                                // support/office
keep if fam < .
gen byte mil = grp == 5
collapse (mean) mil [pw=weight], by(fam year)
replace mil = 100 * mil
reshape wide mil, i(fam) j(year)
label define fam_lbl 1 "Drivers" 2 "Medical staff (doctors, nurses, paramedics)" 3 "Trades (ISCO 7)" ///
    4 "IT and communications (ISCO 25, 35)" 5 "Support and office (clerks, cooks, accountants, HR, lawyers, cleaners)"
label values fam fam_lbl
format mil* %5.2f
list, noobs
label var fam     "Job family"
label var mil2023 "2023"
label var mil2024 "2024"
label var mil2025 "2025"
label var mil2026 "2026 (Jan-Oct)"
export_table using "$tab/05_military_competition", ///
    title("Military ads as % of military + civilian core ads in the same job family")

log close
