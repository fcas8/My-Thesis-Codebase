* =============================================================================
* 04_descriptives.do  --  robota.ua vacancy sample: descriptive statistics
*
* No war exposure here: this file describes the sample and the market over time.
*
* Input : data/analysis/robota_vacancies_clean.dta   (from 01_clean.do)
*         data/temp/robota_city_raion.csv            (from 00_city_raion.py: city -> raion)
*         data/crosswalks/ua_raions.csv              (English oblast names)
*         data/raw/macro/  prices and exchange rates, downloaded 9 Nov 2026:
*           nbu_cpi_headline.csv   National Bank of Ukraine, open data, CPI (whole country,
*                                  all items), rows as published:
*                                  https://bank.gov.ua/NBUStatService/v1/statdirectory/
*                                  inflation?start=20190101&end=20261101&period=m&json
*                                  !! dt is the month AFTER the reference month (row dt =
*                                  2022-04-01 holds March 2022: m/m 4.5%, y/y 13.7%).
*                                  tzep: PCPM_ = % change on previous month,
*                                  PCCM_ = on same month a year before, DTPY_ = since
*                                  December, PCCP_ = average of the year so far.
*                                  Last reference month: Sep 2026.
*           nbu_usd_daily.csv      NBU official UAH per USD, daily:
*                                  https://bank.gov.ua/NBU_Exchange/exchange_site?start=
*                                  20200101&end=20261108&valcode=usd&sort=exchangedate&json
*           wb_ppp_private_consumption.csv  World Bank WDI PA.NUS.PRVT.PP: PPP conversion
*                                  factor, household consumption, UAH per international $
*                                  (annual, to 2025; ICP 2021 benchmark)
* Output: output/figures/04_*.pdf                    figures (list at each step)
*         output/tables/04_*.xlsx and .tex           final tables (export_table, 00_programs.do)
*         data/temp/descriptives/04_*.csv            the numbers behind the figures
*         data/temp/logs/04_descriptives.log
*         Every output is listed in output_inventory.xlsx (Project folder).
*
* Choices (Step 0; agreed 9 Nov 2026):
*   - Unit: the new vacancy, dated by its creation date (created_date, 01_clean.do step 5),
*     not by its latest publication. Counts are estimated: sums of the sampling weight.
*   - Months: Oct 2020 - Oct 2026, the full months in the sample (sampling starts at the
*     ids of 27 Sep 2020; the export is from 9 Nov 2026). So "2020" is Oct-Dec only, and
*     2026 is Jan-Oct.
*   - Pre-war baseline: calendar 2021 (a full year of seasons). Changes are measured
*     against its monthly average. "After" window for before/after comparisons: Jan
*     2023 on (after the 2022 collapse and rebound).
*   - Groups (grp), mutually exclusive, assigned in this order (the later wins):
*       1 civilian core     everything not below: the main sample for every figure
*       3 likely re-ads     readvert (01 step 7)
*       2 State employment centers  ses_posting: bulk uploads, almost none before 2023
*       4 jobs abroad       oblast "Інші країни"
*       5 military          military (01 step 6): recruitment ads
*     Military is shown as its own series; "Military industry" (civilian defense
*     manufacturing, branch 49) stays in the core and is also shown on its own.
*   - Wages: monthly wage of the posting (01 step 6), civilian core. Three versions:
*       nominal UAH; real (constant 2021 UAH, NBU CPI, 2021 average = 100); real in 2021
*       international $ (real UAH / 2021 PPP factor, 8.66 UAH per $). And nominal USD at
*       the NBU monthly average rate. Real series end in Sep 2026 (last CPI month).
*   - Oblast: robota.ua's oblast of the city; Kyiv city (raion UA8000) is split out of
*     Kyiv oblast. Macro-areas: Kyiv city; West; Center-North (incl. Kyiv oblast);
*     South; East (step 2).
*
* Needs: reghdfe, ftools (ssc install reghdfe / ftools)
* Run after 01_clean.do (00_main.do runs it last).
* =============================================================================

clear all
set more off
set linesize 200

* --- Step 0. Paths and settings ---------------------------------------------
if "$project" == "" global project "`c(pwd)'/.."   // set by 00_main.do; else run from the repo root
global data    "$project/Project/data/analysis"
global xwalk   "$project/Project/data/crosswalks"
global temp    "$project/Project/data/temp"
global macro   "$project/Project/data/raw/macro"
global fig     "$project/Project/output/figures"
global tab     "$project/Project/output/tables"          // final tables only
global tmp4    "$project/Project/data/temp/descriptives" // data behind the figures
global do      "$project/Project/do"

cap mkdir "$fig"
cap mkdir "$tmp4"
cap mkdir "$temp/logs"
cap log close
log using "$temp/logs/04_descriptives.log", replace text
do "$do/00_programs.do"                    // export_table

global first_month = tm(2020m10)   // first full month in the sample
global last_month  = tm(2026m10)   // last full month in the 9 Nov 2026 export
global base_from   = tm(2021m1)    // pre-war baseline
global base_to     = tm(2021m12)
global post_from   = tm(2023m1)    // "after" window: from here to $last_month
global inv_day     = td(24feb2022)

set scheme stcolor
graph set window fontface "Arial"

* Common pieces of the monthly figures
local inv_x = tm(2022m2) + 0.77    // 24 Feb within February
local events xline(`inv_x', lcolor(cranberry) lwidth(medthick)) ///
    xline(`=tm(2022m10)' `=tm(2024m5)', lcolor(gs9) lpattern(dash))
local tfmt xlabel(`=tm(2021m1)'(6)`=tm(2026m7)', format(%tmMon_YY)) xtitle("")
local evnote "Red line: full-scale invasion (24 Feb 2022). Dashed: strikes on energy begin (Oct 2022); mobilization law (May 2024)."

* --- Step 1. Prices and exchange rates ----------------------------------------
* 1a. CPI index, 2021 average = 100, chained from month-on-month changes
import delimited using "$macro/nbu_cpi_headline.csv", varnames(1) stringcols(1) clear
keep if tzep == "PCPM_"
gen ym = mofd(date(dt, "YMD")) - 1          // dt is the month after the reference month
format ym %tm
sort ym
assert ym == ym[_n-1] + 1 if _n > 1          // no gaps
gen double cpi = exp(sum(ln(1 + value / 100)))
summarize cpi if inrange(ym, tm(2021m1), tm(2021m12)), meanonly
replace cpi = 100 * cpi / r(mean)
* check against the published y/y rate: Dec 2022 = 26.6%, Dec 2023 = 5.1%
tsset ym
gen yoy = 100 * (cpi / L12.cpi - 1)
list ym cpi yoy if inlist(ym, tm(2021m12), tm(2022m12), tm(2023m12), tm(2024m12), tm(2025m12)), noobs
keep ym cpi
tempfile cpi
save `cpi'

* 1b. UAH per USD, monthly average of the NBU daily rate
import delimited using "$macro/nbu_usd_daily.csv", varnames(1) stringcols(1) clear
gen ym = mofd(date(exchangedate, "DMY"))
collapse (mean) usd = rate_per_unit, by(ym)
tempfile usd
save `usd'

* 1c. PPP factor for 2021
import delimited using "$macro/wb_ppp_private_consumption.csv", varnames(1) clear
list, noobs sep(0)
summarize ppp_lcu_per_intl_usd if year == 2021, meanonly
global ppp2021 = r(mean)
display "PPP factor 2021 (UAH per international $): $ppp2021"

* 1d. City -> raion (only to split Kyiv city out of Kyiv oblast)
import delimited using "$temp/robota_city_raion.csv", varnames(1) clear
keep city_id raion_pcode
tempfile cityraion
save `cityraion'

* 1e. English oblast names (crosswalk names are the robota.ua ones without " область")
import delimited using "$xwalk/ua_raions.csv", varnames(1) encoding("utf-8") clear
contract oblast_ua oblast_en
drop _freq
tempfile oblast_en
save `oblast_en'

* --- Step 2. Analysis sample -------------------------------------------------
use "$data/robota_vacancies_clean.dta", clear
gen ym = mofd(created_date)
format ym %tm
gen year = year(created_date)
* vacancies outside the full months (end of Sep 2020, early Nov 2026)
count if !inrange(ym, $first_month, $last_month)
keep if inrange(ym, $first_month, $last_month)

* Groups (see header)
gen byte grp = 1
replace grp = 3 if readvert == 1
replace grp = 2 if ses_posting == 1
replace grp = 4 if oblast == "Інші країни"
replace grp = 5 if military == 1
label define grp_lbl 1 "Civilian core" 2 "State employment centers" 3 "Likely re-ads" ///
    4 "Jobs abroad" 5 "Military"
label values grp grp_lbl
gen byte core = grp == 1
gen byte defense_ind = branch_id == 49
gen byte one = 1
tab year grp, row nofreq

* Kyiv city, English oblast names and macro-areas
merge m:1 city_id using `cityraion', keep(master match) nogenerate
gen oblast_ua = usubinstr(oblast, " область", "", .)
merge m:1 oblast_ua using `oblast_en', keep(master match) nogenerate
replace oblast_en = "Crimea"    if oblast == "Крим"
replace oblast_en = "Kyiv city" if raion_pcode == "UA8000"
replace oblast_en = ""          if oblast == "Інші країни"
tab oblast if oblast_en == "" & oblast != "", missing   // should be abroad and "" only

gen byte area = .
replace area = 1 if oblast_en == "Kyiv city"
replace area = 2 if inlist(oblast_en, "Volynska", "Zakarpatska", "Ivano-Frankivska", ///
    "Lvivska", "Rivnenska", "Ternopilska", "Chernivetska", "Khmelnytska")
replace area = 3 if inlist(oblast_en, "Kyivska", "Vinnytska", "Zhytomyrska", "Cherkaska", ///
    "Kirovohradska", "Poltavska", "Chernihivska", "Sumska")
replace area = 4 if inlist(oblast_en, "Odeska", "Mykolaivska", "Khersonska", "Zaporizka", "Crimea")
replace area = 5 if inlist(oblast_en, "Kharkivska", "Dnipropetrovska", "Donetska", "Luhanska")
label define area_lbl 1 "Kyiv city" 2 "West" 3 "Center-North" 4 "South" 5 "East"
label values area area_lbl
tab area if core, missing

* Wages in three units (see header)
merge m:1 ym using `cpi', keep(master match) nogenerate
merge m:1 ym using `usd', keep(master match) nogenerate
gen wage_real = wage * 100 / cpi           // constant 2021 UAH
gen wage_ppp  = wage_real / $ppp2021       // 2021 international $
gen wage_usd  = wage / usd                 // current USD
gen lw_real   = ln(wage_real)

tempfile base
save `base'
* the same sample for 05_descriptives_rq.do (groups, Kyiv city, areas, wages)
save "$temp/descriptives_base.dta", replace

* --- Step 3. Table 1: the sample over time ------------------------------------------
* One table to see the sample at a glance, by year of creation (columns). Rows come in
* panels; each row gives the number of SAMPLED vacancies (or employer accounts) and,
* in parentheses just below, its % of the year's total, like standard errors in a
* regression table. Shares of categories add up to 100 within a panel. Last column: all
* years together (Oct 2020 - Oct 2026; for accounts, distinct accounts over the period).
*   Vacancies       sampled and estimated (sum of weights) vacancies; multi-city batch
*                   (01 step 7: same employer + title in 2+ cities, same quarter);
*                   with a monthly wage
*   Group           the five groups of the header
*   Macro-area      Step 2; "abroad / no oblast" = jobs abroad and places without one
*   Industry        employer's industry (robota.ua): the 10 largest overall, the rest in
*                   "other industries" (incl. code 0, not in robota.ua's list)
*   Schedule        full-time, part-time, shift work; other = remote, project, intern,
*                   seasonal and code 0
*   Professional level   robota.ua's 1-6 scale (labels inferred from titles, 01 step 8d)
*   Subscription package publication_type: the posting package the employer paid for
*   Employer accounts    one row per employer id x year with a sampled vacancy, all
*                   groups. Account type, in this order: state employment center
*                   (ses_posting), military employer, recruitment agency, direct employer.
*                   "New" = first sampled vacancy in that year (all 2020 accounts are new
*                   by construction). Size = sampled vacancies in the year (about 1 in 6.3
*                   of the account's vacancies).
* Output: 04_table1_by_year (.xlsx, .tex), written by export_panel_table (00_programs.do)

* Helper programs. Each adds rows to the table file $t1 (one row per year):
*   t1_panel "title"            starts a new panel
*   t1_count [if], label() [weight(var)]   count only (no % row)
*   t1_flag var [if], label()   count of var == 1, % of the year's rows
*   t1_cat var [if]             count of each category, % of the year's rows
*   t1_stat var, label() kind() a year-level statistic already in memory
*                               (kind 3: whole number; kind 4: one decimal)
capture program drop t1_panel
program define t1_panel
    args title
    global t1_panel = $t1_panel + 1
    global t1_title$t1_panel `"`title'"'
end
capture program drop t1_post
program define t1_post
    args kind
    gen byte panel = $t1_panel
    gen byte kind = `kind'
    gen long ord = $t1_row * 100 + key
    global t1_row = $t1_row + 1
    keep panel kind ord label year n pct
    append using "$t1"
    save "$t1", replace
end
capture program drop t1_count
program define t1_count
    syntax [if], label(string) [weight(varname)]
    preserve
    if `"`if'"' != "" keep `if'
    if "`weight'" == "" gen double n = 1
    else gen double n = `weight'
    collapse (sum) n, by(year)
    gen double pct = .
    gen label = "`label'"
    gen key = 0
    t1_post 2
    restore
end
capture program drop t1_flag
program define t1_flag
    syntax varname [if], label(string)
    preserve
    if `"`if'"' != "" keep `if'
    gen byte f = `varlist' == 1                  // missing counts as 0
    collapse (sum) n = f (count) tot = f, by(year)
    gen double pct = 100 * n / tot
    gen label = "`label'"
    gen key = 0
    t1_post 1
    restore
end
capture program drop t1_cat
program define t1_cat
    syntax varname [if]
    preserve
    if `"`if'"' != "" keep `if'
    gen double n = 1
    collapse (sum) n, by(year `varlist')
    fillin year `varlist'                        // a category absent in a year shows 0
    replace n = 0 if _fillin
    bysort year: egen double tot = total(n)
    gen double pct = 100 * n / tot
    decode `varlist', gen(label)
    rename `varlist' key
    t1_post 1
    restore
end
capture program drop t1_stat
program define t1_stat
    syntax varname, label(string) kind(integer)
    preserve
    gen double n = `varlist'
    gen double pct = .
    gen label = "`label'"
    gen key = 0
    t1_post `kind'
    restore
end

clear
gen byte panel = .
gen byte kind = .
gen long ord = .
gen str1 label = ""
gen int year = .
gen double n = .
gen double pct = .
tempfile t1
save `t1', emptyok
global t1 "`t1'"
global t1_panel = 0
global t1_row = 1

* 3a. Vacancies
use `base', clear
* categories built for the table only
gen byte area6 = cond(area < ., area, 6)
label define area6_lbl 1 "Kyiv city" 2 "West" 3 "Center-North" 4 "South" 5 "East" ///
    6 "Abroad / no oblast"
label values area6 area6_lbl

* industry: the 10 largest over the whole period, the rest together
bysort branch_id: gen long ind_n = _N
egen ind_tag = tag(branch_id)
gsort -ind_tag -ind_n
gen ind_rank = sum(ind_tag) if ind_tag & branch_id != 0
replace ind_rank = . if branch_id == 0
bysort branch_id (ind_rank): replace ind_rank = ind_rank[1]
gen byte ind10 = cond(ind_rank <= 10, ind_rank, 11)
forvalues r = 1/10 {
    levelsof branch_id if ind_rank == `r', local(b)
    local blab : label branch_lbl `b'
    label define ind10_lbl `r' `"`blab'"', add
}
label define ind10_lbl 11 "Other industries", add
label values ind10 ind10_lbl
drop ind_n ind_tag ind_rank

decode schedule_id, gen(sched_s)
gen byte sched4 = cond(sched_s == "full-time", 1, cond(sched_s == "part-time", 2, ///
    cond(sched_s == "shift work", 3, 4)))
label define sched4_lbl 1 "Full-time" 2 "Part-time" 3 "Shift work" 4 "Other / not set"
label values sched4 sched4_lbl
drop sched_s

gen byte level7 = cond(prof_level_id == 0, 7, prof_level_id)
label define level7_lbl 1 "1 Workers / sales staff" 2 "2 Entry-level / junior" ///
    3 "3 Specialist" 4 "4 Senior specialist / lead" 5 "5 Head of unit / middle mgmt" ///
    6 "6 Director / top mgmt" 7 "Not set"
label values level7 level7_lbl
tab publication_type, missing

* "All years" column: a second copy of every vacancy with year = 9999
expand 2, gen(all_years)
replace year = 9999 if all_years

t1_panel "Vacancies"
t1_count, label("Sampled vacancies")
t1_count, label("Estimated vacancies (sum of weights)") weight(weight)
t1_flag multicity, label("Multi-city batch")
t1_flag has_wage, label("With a monthly wage")
t1_panel "Group"
t1_cat grp
t1_panel "Macro-area"
t1_cat area6
t1_panel "Industry (10 largest)"
t1_cat ind10
t1_panel "Schedule"
t1_cat sched4
t1_panel "Professional level"
t1_cat level7
t1_panel "Subscription package"
t1_cat publication_type

* 3b. Employer accounts: one row per employer id x year
use `base' if notebook_id < ., clear
bysort notebook_id: egen first_year = min(year)
foreach v in ses_posting military is_agency verified_company {
    bysort notebook_id: egen acc_`v' = max(`v')
}
* "All years" column: one row per account over the whole period, year = 9999
preserve
    collapse (count) nvac = id (first) acc_*, by(notebook_id)
    gen year = 9999
    tempfile acc_all
    save `acc_all'
restore
collapse (count) nvac = id (first) first_year acc_*, by(notebook_id year)
append using `acc_all'
gen byte acc_type = cond(acc_ses_posting == 1, 3, cond(acc_military == 1, 4, ///
    cond(acc_is_agency == 1, 2, 1)))
label define acc_lbl 1 "Direct employer" 2 "Recruitment agency" ///
    3 "State employment center" 4 "Military employer"
label values acc_type acc_lbl
gen byte new_acc = year == first_year      // blank in the "All years" column (3c)
gen byte size4 = cond(nvac == 1, 1, cond(nvac <= 4, 2, cond(nvac <= 19, 3, 4)))
label define size_lbl4 1 "1 sampled vacancy" 2 "2-4" 3 "5-19" 4 "20 or more"
label values size4 size_lbl4

t1_panel "Employer accounts"
t1_count, label("Active accounts (with a sampled vacancy)")
t1_flag new_acc, label("New (first sampled vacancy)")
t1_flag acc_verified_company, label("Verified by robota.ua")
t1_panel "Account type"
t1_cat acc_type
t1_panel "Account size (sampled vacancies in the year / period)"
t1_cat size4
* concentration, direct employers only (a few employment-center and military accounts post
* thousands of vacancies): mean vacancies per employer; share of the top 1% of employers
keep if acc_type == 1
gsort year -nvac
by year: gen r = _n
by year: gen N = _N
gen nvac_top1 = nvac * (r <= ceil(N / 100))
collapse (mean) mean_vac = nvac (sum) nvac nvac_top1, by(year)
gen share_top1 = 100 * nvac_top1 / nvac
t1_stat mean_vac, label("Direct employers: mean sampled vacancies") kind(4)
t1_stat share_top1, label("Direct employers: % of vacancies by top 1%") kind(4)

* 3c. Layout: one column per year; a % row below each count row; panel titles
use "$t1", clear
gen c = ""
replace c = strtrim(string(n, "%12.0fc")) if inlist(kind, 1, 2, 3)
replace c = strtrim(string(n, "%5.1f"))   if kind == 4
gen p = "(" + strtrim(string(pct, "%5.1f")) + ")" if kind == 1
keep panel ord kind label year c p
reshape wide c p, i(panel ord) j(year)
replace c9999 = "" if label == "New (first sampled vacancy)"   // every account is new once
replace p9999 = "" if label == "New (first sampled vacancy)"
expand 2 if kind == 1, gen(pct_row)
gen byte row_type = cond(pct_row, 3, 2)
foreach y of numlist 2020/2026 9999 {
    replace c`y' = p`y' if pct_row
}
replace label = "" if pct_row
drop p2020 p2021 p2022 p2023 p2024 p2025 p2026 p9999     // (reshape interleaves c and p: no ranges)
local np = $t1_panel
local N0 = _N
set obs `=_N + `np''
forvalues k = 1/`np' {
    replace panel = `k' in `=`N0' + `k''
    replace ord = -1 in `=`N0' + `k''
    replace row_type = 1 in `=`N0' + `k''
    replace label = `"${t1_title`k'}"' in `=`N0' + `k''
}
sort panel ord row_type
keep row_type label c2020 c2021 c2022 c2023 c2024 c2025 c2026 c9999
order row_type label
label var label " "
label var c9999 "All years"
foreach y of numlist 2020/2026 {
    local ylab "`y'"
    if `y' == 2020 local ylab "2020 (Oct-Dec)"
    if `y' == 2026 local ylab "2026 (Jan-Oct)"
    label var c`y' "`ylab'"
}
list, noobs sep(0) abbreviate(14)
export_panel_table using "$tab/04_table1_by_year", title("Sample by year of creation")

* --- Step 4. Counts over time -------------------------------------------------
* Output: 04_counts_by_group.pdf   estimated vacancies per month, stacked by group
*         04_counts_index.pdf      core and all vacancies, 2021 average = 100
*         04_counts_seasonal.pdf   core by calendar month, one line per year
*         data/temp/descriptives/04_counts_monthly.csv (data behind the figures)
use `base', clear
collapse (sum) est = one [pw=weight], by(ym grp)
reshape wide est, i(ym) j(grp)
forvalues k = 1/5 {
    replace est`k' = 0 if est`k' == .
}
tsset ym
gen s1 = est1
forvalues k = 2/5 {
    gen s`k' = s`=`k'-1' + est`k'
}
twoway (area s5 ym, color(cranberry%70)) (area s4 ym, color(gs10)) ///
    (area s3 ym, color(orange%60)) (area s2 ym, color(eltgreen)) (area s1 ym, color(navy%80)), ///
    `events' `tfmt' ylabel(, format(%9.0fc) angle(0)) ytitle("Estimated new vacancies per month") ///
    legend(order(5 "Civilian core" 4 "State employment centers" 3 "Likely re-ads" ///
    2 "Jobs abroad" 1 "Military") rows(1) size(small) position(6)) ///
    note("`evnote'", size(vsmall))
graph export "$fig/04_counts_by_group.pdf", replace

gen all = s5
summarize est1 if inrange(ym, $base_from, $base_to), meanonly
gen idx_core = 100 * est1 / r(mean)
summarize all if inrange(ym, $base_from, $base_to), meanonly
gen idx_all = 100 * all / r(mean)
twoway (line idx_core ym, lcolor(navy) lwidth(medthick)) (line idx_all ym, lcolor(gs8) lpattern(dash)), ///
    yline(100, lcolor(gs12)) `events' `tfmt' ylabel(, angle(0)) ///
    ytitle("Index, 2021 monthly average = 100") ///
    legend(order(1 "Civilian core" 2 "All vacancies") rows(1) position(6)) ///
    note("`evnote'", size(vsmall))
graph export "$fig/04_counts_index.pdf", replace

* Seasonality: does 2020 (Oct-Dec only) look like 2021? Is there a common monthly pattern?
gen yr = year(dofm(ym))
gen mo = month(dofm(ym))
local plots ""
local leg ""
local i = 0
forvalues y = 2020/2026 {
    local ++i
    local plots `plots' (connected est1 mo if yr == `y', msize(small))
    local leg `leg' `i' "`y'"
}
twoway `plots', xlabel(1 "Jan" 2 "Feb" 3 "Mar" 4 "Apr" 5 "May" 6 "Jun" 7 "Jul" 8 "Aug" ///
    9 "Sep" 10 "Oct" 11 "Nov" 12 "Dec") xtitle("") ylabel(, format(%9.0fc) angle(0)) ///
    ytitle("Estimated new vacancies, civilian core") legend(order(`leg') rows(1) position(6))
graph export "$fig/04_counts_seasonal.pdf", replace
* the same in numbers: core by year and month
table mo yr, statistic(sum est1) nformat(%9.0fc)

drop s1-s5 yr mo
export delimited using "$tmp4/04_counts_monthly.csv", replace

* 4b. Daily, around the invasion. Output: 04_counts_daily_invasion.pdf
use `base' if inrange(created_date, td(01jan2022), td(30apr2022)), clear
gen w_core = weight * core
collapse (sum) est_all = weight est_core = w_core, by(created_date)
tsset created_date
tsfill
replace est_all = 0 if est_all == .
replace est_core = 0 if est_core == .
foreach v in all core {
    gen ma_`v' = (L3.est_`v' + L2.est_`v' + L.est_`v' + est_`v' + F.est_`v' + F2.est_`v' + F3.est_`v') / 7
}
twoway (bar est_core created_date, color(navy%30)) (line ma_core created_date, lcolor(navy) lwidth(medthick)) ///
    (line ma_all created_date, lcolor(gs8) lpattern(dash)), ///
    xline(`=td(24feb2022)', lcolor(cranberry) lwidth(medthick)) ///
    xlabel(`=td(01jan2022)' `=td(01feb2022)' `=td(01mar2022)' `=td(01apr2022)' `=td(30apr2022)', format(%tdDD_Mon)) ///
    xtitle("") ylabel(, format(%9.0fc) angle(0)) ytitle("Estimated new vacancies per day") ///
    legend(order(1 "Civilian core, daily" 2 "Civilian core, 7-day average" 3 "All, 7-day average") ///
    rows(1) size(small) position(6))
graph export "$fig/04_counts_daily_invasion.pdf", replace

* --- Step 5. Military and defense industry -----------------------------------
* Output: 04_military.pdf; data in data/temp/descriptives/04_military_monthly.csv
use `base', clear
gen byte mil = grp == 5
gen byte def = defense_ind & grp != 5
collapse (sum) mil def all = one [pw=weight], by(ym)
gen mil_share = 100 * mil / all
twoway (line mil ym, lcolor(cranberry) lwidth(medthick)) (line def ym, lcolor(dkorange)) ///
    (line mil_share ym, yaxis(2) lcolor(gs8) lpattern(dash)), ///
    `events' `tfmt' ylabel(, format(%9.0fc) angle(0)) ylabel(, angle(0) axis(2)) ///
    ytitle("Estimated new vacancies per month") ytitle("Military, % of all vacancies", axis(2)) ///
    legend(order(1 "Military employers" 2 "Military industry (civilian)" 3 "Military share (right)") ///
    rows(1) size(small) position(6)) note("`evnote'", size(vsmall))
graph export "$fig/04_military.pdf", replace
export delimited using "$tmp4/04_military_monthly.csv", replace

* --- Step 6. Industry (employer's sector), civilian core -----------------------
* Output: 04_industry_by_year (.xlsx, .tex)   share of each industry, by year
*         04_industry_change (.xlsx, .tex)    2021 vs Jan 2023 - Oct 2026: shares and levels
*         04_industry_share_change.pdf   change in share, percentage points
*         04_industry_level.pdf     monthly average in 2023-26, 2021 = 100
use `base' if core, clear
collapse (sum) est = one [pw=weight], by(year branch_id)
bysort year: egen tot = total(est)
gen share = 100 * est / tot
keep year branch_id share
reshape wide share, i(branch_id) j(year)
decode branch_id, gen(industry)
drop if branch_id == 0                    // code not in robota.ua's list
gsort -share2021
drop branch_id
order industry
format share* %5.1f
label var industry "Employer industry"
forvalues y = 2020/2026 {
    label var share`y' "`y'"
}
label var share2020 "2020 (Oct-Dec)"
label var share2026 "2026 (Jan-Oct)"
export_table using "$tab/04_industry_by_year", ///
    title("Share of civilian core vacancies by employer industry and year, %")

use `base' if core, clear
gen byte period = 1 if inrange(ym, $base_from, $base_to)
replace period = 2 if ym >= $post_from
drop if period == .
collapse (sum) est = one [pw=weight], by(period branch_id)
bysort period: egen tot = total(est)
gen share = 100 * est / tot
drop tot
reshape wide est share, i(branch_id) j(period)
foreach v in est1 est2 share1 share2 {
    replace `v' = 0 if `v' == .
}
local m_base = $base_to - $base_from + 1
local m_post = $last_month - $post_from + 1
gen dshare = share2 - share1
gen level  = 100 * (est2 / `m_post') / (est1 / `m_base')   // monthly averages
decode branch_id, gen(industry)
drop if branch_id == 0                    // code not in robota.ua's list
gsort -dshare
list industry share1 share2 dshare level, noobs sep(0) abbreviate(10)
preserve
    keep industry share1 share2 dshare level
    format share1 share2 dshare %5.1f
    format level %5.0f
    label var industry "Employer industry"
    label var share1   "Share 2021, %"
    label var share2   "Share 2023-26, %"
    label var dshare   "Change, pp"
    label var level    "Vacancies per month, 2021 = 100"
    export_table using "$tab/04_industry_change", ///
        title("Civilian core vacancies by industry: 2021 vs Jan 2023 - Oct 2026")
restore
graph hbar (asis) dshare, over(industry, sort(dshare) descending label(labsize(vsmall))) ///
    bar(1, color(navy)) ytitle("Change in share of core vacancies, pp" "(Jan 2023 - Oct 2026 vs 2021)", size(small)) graphregion(margin(r+8)) ///
    ysize(8) xsize(6.5)
graph export "$fig/04_industry_share_change.pdf", replace
graph hbar (asis) level, over(industry, sort(level) descending label(labsize(vsmall))) ///
    bar(1, color(navy)) yline(100, lcolor(cranberry)) ///
    ytitle("Vacancies per month, Jan 2023 - Oct 2026" "(2021 = 100)", size(small)) graphregion(margin(r+8)) ysize(8) xsize(6.5)
graph export "$fig/04_industry_level.pdf", replace

* --- Step 7. Professional level, civilian core ---------------------------------
* Output: 04_proflevel_by_year.pdf, 04_proflevel_by_year (.xlsx, .tex)
* Level labels are inferred from job titles (01 step 8d): robota.ua publishes none.
use `base' if core, clear
collapse (sum) est = one [pw=weight], by(year prof_level_id)
bysort year: egen tot = total(est)
gen share = 100 * est / tot
keep year prof_level_id share
reshape wide share, i(year) j(prof_level_id)
format share* %5.1f
list, noobs sep(0)
preserve
    tostring year, replace
    replace year = "2020 (Oct-Dec)" if year == "2020"
    replace year = "2026 (Jan-Oct)" if year == "2026"
    label var year   "Year"
    label var share0 "0 not set"
    label var share1 "1 workers / sales"
    label var share2 "2 entry / junior"
    label var share3 "3 specialist"
    label var share4 "4 senior / lead"
    label var share5 "5 head of unit"
    label var share6 "6 director / top mgmt"
    export_transposed using "$tab/04_proflevel_by_year", ///
        title("Civilian core vacancies by professional level (inferred) and year, %")
restore
graph bar (asis) share0-share6, over(year, relabel(1 "2020 Q4" 7 "2026 Jan-Oct") label(labsize(small))) stack xsize(7.5) ///
    bar(1, color(gs12)) ytitle("% of civilian core vacancies") ylabel(0(20)100, angle(0)) ///
    legend(order(7 "Director / top mgmt" 6 "Head of unit" 5 "Senior / lead" ///
    4 "Specialist" 3 "Entry / junior" 2 "Workers / sales" 1 "Not set") ///
    cols(1) position(3) size(small))
graph export "$fig/04_proflevel_by_year.pdf", replace

* --- Step 8. Wages, civilian core -----------------------------------------------
* 8a. Share of vacancies that state a monthly wage. Output: 04_wage_disclosure.pdf
*     If disclosure changes, the wage series below describe a changing set of jobs.
use `base' if inlist(grp, 1, 2, 5), clear
collapse (mean) has_wage [pw=weight], by(ym grp)
replace has_wage = 100 * has_wage
reshape wide has_wage, i(ym) j(grp)
twoway (line has_wage1 ym, lcolor(navy) lwidth(medthick)) (line has_wage2 ym, lcolor(eltgreen)) ///
    (line has_wage5 ym, lcolor(cranberry)), `events' `tfmt' ylabel(0(20)100, angle(0)) ///
    ytitle("% of vacancies with a monthly wage") ///
    legend(order(1 "Civilian core" 2 "State employment centers" 3 "Military") rows(1) position(6)) ///
    note("`evnote'", size(vsmall))
graph export "$fig/04_wage_disclosure.pdf", replace

* 8b. Levels. Output: 04_wage_ppp.pdf (median and quartiles, 2021 international $)
*     04_wage_index.pdf (median: nominal UAH, real UAH, USD; 2021 = 100)
*     data behind them: data/temp/descriptives/04_wages_monthly.csv
use `base' if core & wage < ., clear
collapse (p25) p25 = wage_ppp (p50) p50 = wage_ppp (p75) p75 = wage_ppp ///
    (p50) nom = wage real = wage_real usd = wage_usd (rawsum) n = one [pw=weight], by(ym)
twoway (rarea p25 p75 ym, color(navy%20) lwidth(none)) (line p50 ym, lcolor(navy) lwidth(medthick)), ///
    `events' `tfmt' ylabel(, format(%9.0fc) angle(0)) ///
    ytitle("Monthly wage, 2021 international $ (PPP)") ///
    legend(order(2 "Median" 1 "25th-75th percentile") rows(1) position(6)) ///
    note("Posted monthly wage, deflated by the NBU CPI to 2021 UAH and converted at the 2021 PPP factor ($ppp2021 UAH per $)." ///
    "`evnote'", size(vsmall))
graph export "$fig/04_wage_ppp.pdf", replace
foreach v in nom real usd {
    summarize `v' if inrange(ym, $base_from, $base_to), meanonly
    gen idx_`v' = 100 * `v' / r(mean)
}
twoway (line idx_nom ym, lcolor(gs8)) (line idx_real ym, lcolor(navy) lwidth(medthick)) ///
    (line idx_usd ym, lcolor(dkorange)), yline(100, lcolor(gs12)) `events' `tfmt' ylabel(, angle(0)) ///
    ytitle("Median posted wage, 2021 average = 100") ///
    legend(order(1 "Nominal UAH" 2 "Real UAH (CPI)" 3 "USD (NBU rate)") rows(1) position(6)) ///
    note("`evnote'", size(vsmall))
graph export "$fig/04_wage_index.pdf", replace
export delimited using "$tmp4/04_wages_monthly.csv", replace

* 8c. Median wage by year and group, to compare the core with the excluded groups.
*     Output: 04_wages_by_group_year (.xlsx, .tex)
use `base' if wage < ., clear
collapse (p50) wage wage_real wage_ppp (rawsum) n = one [pw=weight], by(year grp)
format wage* %9.0fc
format n %9.0fc
list, noobs sepby(year)
tostring year, replace
replace year = "2020 (Oct-Dec)" if year == "2020"
replace year = "2026 (Jan-Oct)" if year == "2026"
label var year      "Year"
label var grp       "Group"
label var wage      "Median, UAH"
label var wage_real "Median, 2021 UAH"
label var wage_ppp  "Median, 2021 int. \$ (PPP)"
label var n         "Sampled vacancies with wage"
export_transposed using "$tab/04_wages_by_group_year", panel(grp) ///
    title("Median posted monthly wage by year and group. Real wages to Sep 2026.")

* 8d. Composition-adjusted wage. Is the change in the median a change in pay, or in which
*     jobs are posted? Month effects on the log real wage, adding fixed effects one block
*     at a time (cumulative), on the same sample:
*       b0 raw            month dummies only (= mean log wage by month)
*       b1 industry       + one FE per employer industry (40)
*       b2 industry x level  industry FE replaced by one FE per industry x professional-
*                         level cell (40 x 7): level pay gaps may differ by industry
*       b3 + city         + one FE per city (separate from the cells, not interacted)
*       b4 + schedule     + one FE per schedule (full-time, part-time, ...)
*     Each line is set to 0 on its 2021 average, so 10 = about 10% above 2021.
*     The gap between two lines is what that block of FEs explains: a change in the mix
*     of industries, levels, cities or schedules over time.
*     Output: 04_wage_adjusted.pdf; data in data/temp/descriptives/04_wage_adjusted.csv
use `base' if core & lw_real < ., clear
levelsof ym, local(months)
local fe1 branch_id
local fe2 branch_id#prof_level_id
local fe3 branch_id#prof_level_id city_id
local fe4 branch_id#prof_level_id city_id schedule_id
tempfile adj
tempname pf
postfile `pf' ym spec b using `adj', replace
forvalues s = 1/4 {
    reghdfe lw_real i.ym [pw=weight], absorb(`fe`s'')
    foreach m of local months {
        capture local b = _b[`m'.ym]
        if _rc local b = 0                      // base month
        post `pf' (`m') (`s') (`b')
    }
}
postclose `pf'
collapse (mean) b0 = lw_real [pw=weight], by(ym)
tempfile raw
save `raw'
use `adj', clear
reshape wide b, i(ym) j(spec)
merge 1:1 ym using `raw', assert(match) nogenerate
format ym %tm
foreach v in b0 b1 b2 b3 b4 {
    summarize `v' if inrange(ym, $base_from, $base_to), meanonly
    replace `v' = 100 * (`v' - r(mean))
}
order ym b0 b1 b2 b3 b4
twoway (line b0 ym, lcolor(gs10)) (line b1 ym, lcolor(dkorange)) (line b2 ym, lcolor(eltgreen)) ///
    (line b3 ym, lcolor(cranberry)) (line b4 ym, lcolor(navy) lwidth(medthick)), ///
    yline(0, lcolor(gs12)) `events' `tfmt' ylabel(, angle(0)) ///
    ytitle("Log real wage, x100, 2021 = 0") ///
    legend(order(1 "Raw (month dummies only)" 2 "+ industry FE" ///
    3 "Industry × level cell FE" 4 "Cell FE + city FE" 5 "Cell FE + city FE + schedule FE") ///
    cols(2) size(small) position(6)) ///
    note("Fixed effects added cumulatively. Industry × level: one FE per industry-level cell. City and schedule FEs are separate (not interacted)." ///
    "`evnote'", size(vsmall))
graph export "$fig/04_wage_adjusted.pdf", replace
export delimited using "$tmp4/04_wage_adjusted.csv", replace

* 8e. Distribution of real wages by period (kernel densities of the log real wage, civilian
*     core, sampling weights), in the three periods used throughout:
*       1 pre-war baseline   $base_from - $base_to (2021)
*       2 first war months   Mar 2022 - Dec 2022 (collapse and rebound)
*       3 after              $post_from - Sep 2026 (last CPI month)
*     The x axis is in 2021 UAH on a log scale. Output: 04_wage_kernels.pdf
use `base' if core & lw_real < ., clear
gen byte period = 1 if inrange(ym, $base_from, $base_to)
replace period = 2 if inrange(ym, tm(2022m3), tm(2022m12))
replace period = 3 if ym >= $post_from
keep if period < .
summarize lw_real, detail
local lo = r(p1)
local hi = r(p99)
local plots ""
local cols navy dkorange cranberry
local wid thick medium medium
forvalues k = 1/3 {
    local c : word `k' of `cols'
    local w : word `k' of `wid'
    local plots `plots' (kdensity lw_real if period == `k' & inrange(lw_real, `lo', `hi') [aw=weight], ///
        lcolor(`c') lwidth(`w'))
}
local leg 1 "2021 (pre-war)" 2 "Mar-Dec 2022" 3 "Jan 2023 - Sep 2026"
local xl ""
foreach w in 5000 7500 10000 15000 20000 30000 50000 75000 {
    local xl `xl' `=ln(`w')' "`: display %9.0fc `w''"
}
twoway `plots', xlabel(`xl', labsize(small)) xtitle("Monthly posted wage, 2021 UAH (log scale)") ///
    ylabel(, angle(0)) ytitle("Density") legend(order(`leg') rows(1) position(6)) ///
    note("Civilian core vacancies with a monthly wage, deflated by the NBU CPI; 1st-99th percentile of the pooled distribution.", size(vsmall))
graph export "$fig/04_wage_kernels.pdf", replace

* --- Step 9. Geography, civilian core -------------------------------------------
* 9a. Map: change in core vacancies of each oblast (all its cities; Kyiv city on its own),
*     as arrows up (increase) or down (decrease), drawn at the oblast's main city (most
*     core vacancies in 2021: the oblast center in practice). Two comparisons:
*       A  short run: Mar-May 2022 vs Mar-May 2021 (same months, so no seasonality)
*       B  long run:  Jan 2023 - Oct 2026 vs 2021, monthly averages (as in 9c)
*     Background: country and oblast borders (data/temp/ua_oblast_borders.csv, from
*     do/00_oblast_borders.py).
*     Arrow length: $map_scale degrees of latitude = 100%, no cap (a decrease cannot go
*     below -100%; the largest increase: Zakarpattia, panel B).
*     Output: 04_map_oblast_change.pdf; data in data/temp/descriptives/04_oblast_change_arrows.csv
global map_scale = 1.2

* city coordinates (00_city_raion.py: mean of the vacancies' coordinates in each city)
import delimited using "$temp/robota_city_raion.csv", varnames(1) clear
keep city_id lat lon
tempfile cityxy
save `cityxy'

use `base' if core & city_id < ., clear
gen byte pA0 = inrange(ym, tm(2021m3), tm(2021m5))
gen byte pA1 = inrange(ym, tm(2022m3), tm(2022m5))
gen byte pB0 = inrange(ym, $base_from, $base_to)
gen byte pB1 = ym >= $post_from
foreach v in pA0 pA1 pB0 pB1 {
    gen w_`v' = weight * `v'
}
collapse (sum) eA0 = w_pA0 eA1 = w_pA1 eB0 = w_pB0 eB1 = w_pB1 (rawsum) n2021 = pB0, ///
    by(city_id oblast_en)
drop if oblast_en == "" | oblast_en == "Crimea"
foreach v in eA0 eA1 eB0 eB1 {
    bysort oblast_en: egen double o_`v' = total(`v')  // oblast totals, all cities
    replace `v' = o_`v'
    drop o_`v'
}
bysort oblast_en (n2021): keep if _n == _N           // main city: where the arrow is drawn
gen pctA = 100 * (eA1 / eA0 - 1)
gen pctB = 100 * ((eB1 / `m_post') / (eB0 / `m_base') - 1)
merge 1:1 city_id using `cityxy', keep(match) nogenerate
decode city_id, gen(city)
gsort -n2021
format eA0 eA1 eB0 eB1 %9.0fc
format pctA pctB %6.1f
list oblast_en city n2021 pctA pctB, noobs sep(0)
export delimited oblast_en city n2021 eA0 eA1 eB0 eB1 pctA pctB lat lon ///
    using "$tmp4/04_oblast_change_arrows.csv", replace
foreach p in A B {
    gen y2`p'  = lat + $map_scale * pct`p' / 100
    gen lab`p' = cond(pct`p' > 0, "+", "") + string(round(pct`p'), "%4.0f")
}
gen byte labpos = cond(city == "Brovary", 9, 3)    // next to Kyiv: label on the left
keep city lat lon pctA pctB y2A y2B labA labB labpos
tempfile cities
save `cities'

* borders: one row per point, an empty row between paths (drawn with cmissing(n))
import delimited using "$temp/ua_oblast_borders.csv", varnames(1) clear
rename (lon lat) (b_lon b_lat)
gen long order = _n
append using `cities'
local ref_top = 45 + $map_scale * 0.5
local titleA "A. Mar-May 2022 vs Mar-May 2021"
local titleB "B. Jan 2023 - Oct 2026 vs 2021 (monthly averages)"
foreach p in A B {
    twoway (line b_lat b_lon if kind != "country", sort(order) cmissing(n) lcolor(gs12) lwidth(vthin)) ///
        (line b_lat b_lon if kind != "oblast", sort(order) cmissing(n) lcolor(gs7) lwidth(thin)) ///
        (pcarrow lat lon y2`p' lon if pct`p' >= 0, lcolor(dkgreen) mcolor(dkgreen) lwidth(medthick) ///
            msize(medsmall) barbsize(medsmall)) ///
        (pcarrow lat lon y2`p' lon if pct`p' < 0, lcolor(cranberry) mcolor(cranberry) lwidth(medthick) ///
            msize(medsmall) barbsize(medsmall)) ///
        (scatter lat lon, msymbol(o) msize(vsmall) mcolor(black)) ///
        (scatter y2`p' lon, msymbol(none) mlabel(lab`p') mlabvposition(labpos) mlabsize(vsmall) mlabcolor(gs4)) ///
        (pcarrowi 45 23 `ref_top' 23, lcolor(gs6) mcolor(gs6) msize(medsmall) barbsize(medsmall)), ///
        text(`=(45 + `ref_top') / 2' 23.25 "+50%", place(e) size(vsmall) color(gs6)) ///
        xscale(range(22 40.5) off) yscale(range(44 53) off) aspectratio(0.72) ///
        xlabel(none, nogrid) ylabel(none, nogrid) title("`title`p''", size(medsmall)) ///
        plotregion(lstyle(none)) legend(off) name(map`p', replace) nodraw
}
graph combine mapA mapB, cols(2) imargin(small) xsize(10) ysize(4.6) ///
    note("Arrows: % change in civilian core vacancies of each oblast (Kyiv city on its own), drawn at its main city. Green up = increase, red down = decrease;" ///
    "$map_scale degrees of latitude = 100%. Gray lines: oblast borders (OCHA COD-AB, 2025), including Crimea and the occupied areas.", size(vsmall))
graph export "$fig/04_map_oblast_change.pdf", replace
graph drop mapA mapB

* 9b. Shares of the macro-areas, monthly. Output: 04_area_shares.pdf
use `base' if core & area < ., clear
collapse (sum) est = one [pw=weight], by(ym area)
bysort ym: egen tot = total(est)
gen share = 100 * est / tot
keep ym area share
reshape wide share, i(ym) j(area)
twoway (line share1 ym, lcolor(navy) lwidth(medthick)) (line share2 ym, lcolor(dkgreen)) ///
    (line share3 ym, lcolor(gs8)) (line share4 ym, lcolor(dkorange)) (line share5 ym, lcolor(cranberry)), ///
    `events' `tfmt' ylabel(, angle(0)) ytitle("% of civilian core vacancies") ///
    legend(order(1 "Kyiv city" 2 "West" 3 "Center-North" 4 "South" 5 "East") rows(1) position(6)) ///
    note("`evnote'", size(vsmall))
graph export "$fig/04_area_shares.pdf", replace

* 9c. Oblasts: 2021 against Jan 2023 - Oct 2026.
*     Output: 04_oblast_change (.xlsx, .tex), 04_oblast_change.pdf
use `base' if core & oblast_en != "", clear
gen byte period = 1 if inrange(ym, $base_from, $base_to)
replace period = 2 if ym >= $post_from
drop if period == .
collapse (sum) est = one [pw=weight], by(period oblast_en)
bysort period: egen tot = total(est)
gen share = 100 * est / tot
drop tot
reshape wide est share, i(oblast_en) j(period)
local m_base = $base_to - $base_from + 1
local m_post = $last_month - $post_from + 1
gen level  = 100 * (est2 / `m_post') / (est1 / `m_base')
gen dshare = share2 - share1
gsort -level
format est* %9.0fc
format share* dshare level %6.1f
list, noobs sep(0)
gen pct = level - 100                         // % change in vacancies per month
preserve
    gen est1m = est1 / `m_base'
    gen est2m = est2 / `m_post'
    keep oblast_en est1m est2m pct share1 share2 dshare
    order oblast_en est1m est2m pct share1 share2 dshare
    gsort -pct
    format est1m est2m %9.0fc
    format pct share1 share2 dshare %6.1f
    label var oblast_en "Oblast"
    label var est1m     "Vacancies per month, 2021"
    label var est2m     "Vacancies per month, 2023-26"
    label var pct       "Change, %"
    label var share1    "Share 2021, %"
    label var share2    "Share 2023-26, %"
    label var dshare    "Change in share, pp"
    export_table using "$tab/04_oblast_change", ///
        title("Civilian core vacancies by oblast: 2021 vs Jan 2023 - Oct 2026 (estimated)")
restore
drop if oblast_en == "Crimea"                // 5 vacancies in all
* % change in vacancies per month, post minus pre; green = increase, red = decrease
gen pct_up   = pct if pct >= 0
gen pct_down = pct if pct < 0
graph hbar (asis) pct_up pct_down, over(oblast_en, sort(pct) descending label(labsize(small))) ///
    nofill stack bar(1, color(dkgreen)) bar(2, color(cranberry)) yline(0, lcolor(gs8)) legend(off) ///
    blabel(bar, format(%4.0f) size(vsmall)) ylabel(-100(25)50, angle(0)) yscale(range(-115 60)) ///
    ytitle("% change in vacancies per month," "Jan 2023 - Oct 2026 vs 2021", size(small)) ysize(7) xsize(6.5)
graph export "$fig/04_oblast_change.pdf", replace

* --- Step 10. Employer panel ------------------------------------------------------
* Employers: employer id, not an agency (panel_candidate); state employment centers and
* military employers left out. Counts are of SAMPLED vacancies (about 1 in 6.3): a firm
* with few vacancies can be active and still not appear in a year (02 step 5).
use `base' if panel_candidate & !inlist(grp, 2, 5), clear
gen byte pre = created_date < $inv_day

* 10a. Totals
egen tag_emp = tag(notebook_id)
count if tag_emp
display "Employers in the panel: " r(N)
bysort notebook_id: egen any_pre = max(pre)
count if tag_emp & any_pre
display "...of which with a sampled pre-war vacancy: " r(N)
drop tag_emp any_pre

* 10b. By year: active, new (first sampled vacancy that year) and last seen that year.
*      2020 (Oct-Dec) employers are all "new" and 2026 employers all "last seen" by
*      construction: the sample starts and ends there.
*      Output: 04_employers_by_year (.xlsx, .tex)
preserve
    bysort notebook_id: egen first_year = min(year)
    bysort notebook_id: egen last_year  = max(year)
    contract notebook_id year first_year last_year
    gen byte new  = year == first_year
    gen byte last = year == last_year
    collapse (count) active = notebook_id (sum) new last, by(year)
    gen share_new = 100 * new / active
    format active new last %9.0fc
    format share_new %5.1f
    list, noobs sep(0)
    tostring year, replace
    replace year = "2020 (Oct-Dec)" if year == "2020"
    replace year = "2026 (Jan-Oct)" if year == "2026"
    label var year      "Year"
    label var active    "Employers with a sampled vacancy"
    label var new       "First seen this year"
    label var last      "Last seen this year"
    label var share_new "New, %"
    export_transposed using "$tab/04_employers_by_year", ///
        title("Employers by year (sampled vacancies; no agencies, employment centers or military)")
restore

* 10c. Pre-war employers: how many, and how many post again after the invasion.
*      k = minimum number of sampled pre-war vacancies (Oct 2020 - 23 Feb 2022).
*      The share seen again rises with k: firms with more pre-war vacancies are larger
*      (more likely to survive) and post more, so a post-war vacancy is more likely to
*      be sampled. The shares mix survival with detection.
*      Output: 04_employers_prewar (.xlsx, .tex)
*              04_employers_counts.pdf    raw counts, as in the 3 Nov slides (fig_panel):
*                                         pre >= k; pre >= k and any post; pre >= k and post >= k
*              04_employers_survival.pdf  share with a sampled vacancy in each year
preserve
    gen byte post = 1 - pre
    forvalues y = 2022/2026 {
        gen byte a`y' = year == `y' & post
    }
    collapse (sum) n_pre = pre n_post = post (max) a2022-a2026, by(notebook_id)
    gen byte any_post = n_post > 0
    tempfile prewar
    tempname pf
    postfile `pf' k n_emp n_any n_postk any_post a2022 a2023 a2024 a2025 a2026 using `prewar', replace
    foreach k in 1 3 5 10 20 {
        quietly count if n_pre >= `k'
        local n = r(N)
        quietly count if n_pre >= `k' & n_post >= 1
        local n_any = r(N)
        quietly count if n_pre >= `k' & n_post >= `k'
        local n_postk = r(N)
        foreach v in any_post a2022 a2023 a2024 a2025 a2026 {
            quietly summarize `v' if n_pre >= `k', meanonly
            local m_`v' = r(mean)
        }
        post `pf' (`k') (`n') (`n_any') (`n_postk') (`m_any_post') ///
            (`m_a2022') (`m_a2023') (`m_a2024') (`m_a2025') (`m_a2026')
    }
    postclose `pf'
    use `prewar', clear
    format n_emp n_any n_postk %9.0fc
    format any_post a20* %5.3f
    list, noobs sep(0)
    save `prewar', replace                       // already inside -preserve-: keep a copy
        foreach v in any_post a2022 a2023 a2024 a2025 a2026 {
            replace `v' = 100 * `v'
        }
        format any_post a20* %5.1f
        label var k        "k"
        label var n_emp    "Pre-war employers, pre >= k"
        label var n_any    "... with any post-war vacancy"
        label var n_postk  "... with >= k post-war vacancies"
        label var any_post "Any post-war, %"
        label var a2022    "2022 (from 24 Feb), %"
        label var a2023    "2023, %"
        label var a2024    "2024, %"
        label var a2025    "2025, %"
        label var a2026    "2026 (Jan-Oct), %"
        export_table using "$tab/04_employers_prewar", ///
            title("Pre-war employers with at least k sampled vacancies (Oct 2020 - 23 Feb 2022): how many post again")
    use `prewar', clear

    * Raw counts: three bars per k, log scale, numbers on top
    gen j = _n                                   // position of the k group
    gen x1 = 4 * j - 1
    gen x2 = 4 * j
    gen x3 = 4 * j + 1
    foreach v in n_emp n_any n_postk {
        gen lab_`v' = strtrim(string(`v', "%9.0fc"))
    }
    local xl ""
    forvalues i = 1/`=_N' {
        local xl `xl' `=4*`i'' "k = `=k[`i']'"
    }
    twoway (bar n_emp x1, base(100) barwidth(0.95) color(gs11)) ///
        (bar n_any x2, base(100) barwidth(0.95) color(purple%55)) ///
        (bar n_postk x3, base(100) barwidth(0.95) color(purple)) ///
        (scatter n_emp x1, msymbol(none) mlabel(lab_n_emp) mlabposition(12) mlabsize(vsmall) mlabcolor(black)) ///
        (scatter n_any x2, msymbol(none) mlabel(lab_n_any) mlabposition(12) mlabsize(vsmall) mlabcolor(black)) ///
        (scatter n_postk x3, msymbol(none) mlabel(lab_n_postk) mlabposition(12) mlabsize(vsmall) mlabcolor(black)), ///
        yscale(log range(100 100000)) ylabel(100 "100" 1000 "1,000" 10000 "10,000" 100000 "100,000", angle(0)) ///
        ytitle("Employers (log scale)") xlabel(`xl', noticks) xtitle("") xscale(range(2 `=4*_N+2')) ///
        legend(order(1 "pre {&ge} k" 2 "pre {&ge} k & any post" 3 "pre {&ge} k & post {&ge} k") ///
        title("Sampled vacancies before / after 24 Feb 2022", size(small)) cols(1) ring(0) position(1) size(small)) ///
        note("Employers with an id, not agencies; state employment centers and military employers left out. Sampled vacancies (about 1 in 6.3).", size(vsmall))
    graph export "$fig/04_employers_counts.pdf", replace
    drop j x1 x2 x3 lab_*

    keep k a2022-a2026
    reshape long a, i(k) j(yr)
    replace a = 100 * a
    twoway (connected a yr if k == 1) (connected a yr if k == 3) (connected a yr if k == 5) ///
        (connected a yr if k == 10) (connected a yr if k == 20), ///
        xlabel(2022 "2022 (from 24 Feb)" 2023 2024 2025 2026 "2026 (Jan-Oct)") xtitle("") ///
        xscale(range(2021.7 2026.4)) ///
        ylabel(0(20)100, format(%3.0f) angle(0)) ytitle("% of pre-war employers with a sampled vacancy") ///
        legend(order(1 "k = 1" 2 "k = 3" 3 "k = 5" 4 "k = 10" 5 "k = 20") rows(1) position(6) ///
        title("Pre-war employers with at least k sampled vacancies", size(small)))
    graph export "$fig/04_employers_survival.pdf", replace
restore

* 10d. Concentration: share of core vacancies posted by the top 1% of employers and by
*      the 10 largest, by year; median sampled vacancies per employer.
*      Output: 04_employers_concentration (.xlsx, .tex)
preserve
    keep if core
    collapse (rawsum) n = one, by(year notebook_id)
    gsort year -n
    by year: gen r = _n
    by year: gen N = _N
    gen n_top1  = n * (r <= ceil(N / 100))
    gen n_top10 = n * (r <= 10)
    collapse (sum) n n_top1 n_top10 (p50) med_per_emp = n (count) employers = r, by(year)
    gen share_top1  = 100 * n_top1 / n
    gen share_top10 = 100 * n_top10 / n
    format share_* %5.1f
    format n employers %9.0fc
    list year employers med_per_emp share_top1 share_top10, noobs sep(0)
    keep year employers n med_per_emp share_top1 share_top10
    order year employers n med_per_emp share_top1 share_top10
    tostring year, replace
    replace year = "2020 (Oct-Dec)" if year == "2020"
    replace year = "2026 (Jan-Oct)" if year == "2026"
    label var year        "Year"
    label var employers   "Employers"
    label var n           "Sampled core vacancies"
    label var med_per_emp "Median vacancies per employer"
    label var share_top1  "Top 1% of employers, % of vacancies"
    label var share_top10 "10 largest employers, % of vacancies"
    export_transposed using "$tab/04_employers_concentration", ///
        title("Concentration of civilian core vacancies across employers (sampled)")
restore

* 10e. Relocation: employers with at least 3 sampled vacancies before AND after the
*      invasion, by macro-area where most of their vacancies were. Rows: before; columns:
*      after. Firms posting in several places can change their main area without moving:
*      read this as an upper bound. Output: 04_employers_relocation (.xlsx, .tex)
preserve
    keep if area < .
    bysort notebook_id pre: egen area_main = mode(area), minmode
    encode oblast_en, gen(obl)
    bysort notebook_id pre: egen obl_main = mode(obl), minmode
    bysort notebook_id pre: gen n = _N
    collapse (first) area_main obl_main n, by(notebook_id pre)
    reshape wide area_main obl_main n, i(notebook_id) j(pre)
    keep if n1 >= 3 & n0 >= 3 & n1 < . & n0 < .
    label values area_main1 area_main0 area_lbl
    label var area_main1 "Main area before the invasion"
    label var area_main0 "Main area after"
    tab area_main1 area_main0, row
    gen byte moved_area   = area_main1 != area_main0
    gen byte moved_oblast = obl_main1 != obl_main0
    summarize moved_area moved_oblast
    * cross table: rows = main area before, columns = main area after, cells = employers
    contract area_main1 area_main0
    reshape wide _freq, i(area_main1) j(area_main0)
    egen total = rowtotal(_freq*)
    label define area_lbl 1 "Kyiv city" 2 "West" 3 "Center-North" 4 "South" 5 "East", replace  // dropped by contract
    label values area_main1 area_lbl
    forvalues a = 1/5 {
        replace _freq`a' = 0 if _freq`a' == .
        label var _freq`a' "`: label area_lbl `a''"
    }
    format _freq* total %9.0fc
    label var area_main1 "Main area: before (rows), after (columns)"
    label var total      "Total"
    export_table using "$tab/04_employers_relocation", ///
        title("Employers with >= 3 sampled vacancies before and after the invasion: main macro-area before (rows) and after (columns)")
restore

log close
