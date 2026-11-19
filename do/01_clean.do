* =============================================================================
* 01_clean.do  --  robota.ua vacancy sample: basic cleaning
*
* Input : <export folder>/vacancies.csv   (one row per sampled vacancy)
*         data/temp/robota_description_hash.csv  (from do/00_description_hash.py, run first:
*         description hash and the pay period stated in the text)
* Output: data/analysis/robota_vacancies_clean.dta
*
* Run from 00_main.do, which sets the export folder ($export). Run on its own, it uses
* the folder below; to use a newer export (e.g. after the 20% run), change it in 00_main.do
* and here.
* =============================================================================

clear all
set more off

* --- Step 0. Paths ----------------------------------------------------------
if "$project" == "" global project "`c(pwd)'/.."   // set by 00_main.do; else run from the repo root
if "$export" == "" global export "$project/Collector/data/exports/20261110_094445"  // set by 00_main.do
global out     "$project/Project/data/analysis"
global dict    "$project/Project/data/crosswalks"   // robota_*.csv code lists (see step 8)
global temp    "$project/Project/data/temp"         // description hashes (see step 7)

cap mkdir "$out"
cap log close
cap mkdir "$project/Project/data/temp/logs"
log using "$project/Project/data/temp/logs/01_clean.log", replace text

* --- Step 1. Import ---------------------------------------------------------
* UTF-8 with BOM; JSON columns contain quotes and commas, hence bindquote(strict).
* asdouble keeps full precision for weight and coordinates.
import delimited using "$export/vacancies.csv", encoding("utf-8") ///
    bindquote(strict) varnames(1) asdouble clear
confirm variable id                 // fails if the BOM ended up in the first name
count

* --- Step 2. One row per vacancy --------------------------------------------
isid id

* --- Step 3. Zeros that mean "missing" --------------------------------------
* latitude/longitude = 0.0 : location not given
* salary = 0.0             : no single salary given
* notebook_id = 0          : no employer ID
replace latitude  = . if latitude  == 0
replace longitude = . if longitude == 0
replace salary    = . if salary    == 0
replace salary_from = . if salary_from == 0
replace salary_to   = . if salary_to   == 0
replace notebook_id = . if notebook_id == 0
replace district_id = . if district_id == 0   // 0 always has an empty district_name; only Kyiv has districts

* --- Step 4. Dates ----------------------------------------------------------
* date_published looks like 2021-03-22T16:01:00.733 ; fetched_at like 2026-10-30T05:47:01+00:00
* Keep date and time. NB: date_published is the LATEST (re)publication date;
* the period of a vacancy comes from its id (step 5), not from this date.
gen double pub_date   = clock(subinstr(substr(date_published, 1, 23), "T", " ", 1), "YMDhms")
gen double fetch_date = clock(subinstr(substr(fetched_at, 1, 19), "T", " ", 1), "YMDhms")
format pub_date fetch_date %tc
format pub_date fetch_date %tc
drop date_published fetched_at

gen pub_year  = year(dofc(pub_date))
gen pub_month = month(dofc(pub_date))
gen pub_day   = day(dofc(pub_date))
gen double pub_time = mod(pub_date, 24*60*60*1000)
format pub_time %tcHH:MM:SS.sss

* --- Step 5. Period from the vacancy id -------------------------------------
* First post-invasion id = 9,138,846 (estimated from publication dates, see docs/pipeline.md, §5.2).
* true_year is already in the file (built from the ids in plan.json).
gen byte post_invasion = id >= 9138846

* Creation date, from the id. robota.ua gives no creation date (only date_published,
* the LATEST publication; the collector stores it as is). Two facts give one:
*   - ids grow with time: a later id was created later;
*   - date_published can only be later than creation (republishing moves it forward).
* So for any vacancy j with an id at least as high as i's:
*       created_i <= created_j <= date_published_j
* and the creation of i is at most the EARLIEST date_published among i and all later ids:
*       created_i <= min over j >= i of date_published_j
* That minimum is the estimate. It is close to the truth when, soon after i, there is a
* sampled vacancy never republished; at 10% sampling the next sampled id is ~13 ids away,
* so usually minutes or hours (on the 6 Nov 2026 export the longest stretch of vacancies
* sharing one date was ~50 vacancies, ~400 ids: hours). It never goes back in time.
* It needs date_published >= creation for every vacancy: one wrong early date would pull
* earlier ids back. Check (6 Nov 2026): no vacancy dated more than 7 days earlier than
* the previous method (5th percentile of date_published in blocks of 10,000 ids, which
* dated vacancies late in a block up to a week too early).
gsort -id
gen double min_later_pub = pub_date
replace min_later_pub = min(pub_date, min_later_pub[_n-1]) if _n > 1   // running minimum, from the top id down
sort id
gen created_date = dofc(min_later_pub)
format created_date %td
drop min_later_pub

* --- Step 6. Salary ---------------------------------------------------------
* A posting gives either one salary or a range (salary_from - salary_to), in UAH
* (robota.ua converts dollar salaries to hryvnias). The raw fields are kept as they are;
* wage is the monthly wage, built as follows (wage_rule records which rule applied):
*   single salary if given; otherwise the midpoint of the range; otherwise the one bound.
*   1 inverted range (from > to; 15 postings, mostly typos like 5051-51): missing.
*   2 upper bound more than 5 times the lower (e.g. 20,000-1,000,000): lower bound,
*     since the midpoint would be driven by a made-up maximum.
*   3 below half the monthly minimum wage in force when the vacancy was created (mw,
*     below): not a monthly wage. Half the minimum is what a half-time (0.5 rate) job
*     must pay at least. Reading the comments and descriptions, amounts below it are
*     pay per hour (30-200), per day or shift (300-2,000), per piece, or a number in
*     thousands (14 = 14,000); few real monthly wages lie between a quarter and half of
*     the minimum. wage is missing; the posted amount is kept in pay_posted, with its
*     unit in pay_unit when the posting states it (step 7, from 00_description_hash.py).
*   Monthly wages from half the minimum up to the minimum are kept and flagged
*   (wage_below_mw): mostly part-time jobs.
*   4 above 500,000 UAH (about 10,000 EUR) a month: missing. On 5 Nov 2026 these were
*     17 postings, none a real monthly wage: typos (5,000,500), made-up maxima, equity
*     instead of salary, and the one-off 1,000,000 of the army's 18-24 contracts
*     (monthly army pay is at most ~195,000).
*   5 range posted by a military employer (military, below): lower bound. Army ranges
*     follow the pay tiers, not uncertainty about one wage: ~20,000 basic pay, +30,000
*     in the combat zone (~50,000), +100,000 in combat (~120,000). On 9 Nov 2026, 61% of
*     military ranges were exactly "base to base + 30,000 / 70,000 / 100,000" (20,000-
*     120,000, 25,000-125,000, 50,000-120,000, 20,000-50,000), and 2/3 of the rest top
*     out at 100,000 or more. The lower bound is the guaranteed pay. Before this rule,
*     rule 2 gave 20,000-120,000 the lower bound but 25,000-125,000 the midpoint (75,000).

* Military employer: industry "Defence of Ukraine" (48; brigades, recruiting centers of the
* armed forces and National Guard), plus military offices filed under "Governmental Sector"
* (9): territorial recruitment centers (ТЦК), brigades, military units. Police battalions
* are left out. "Military industry" (49) is civilian defense manufacturing: not included.
* Used by rule 5 above, and as a sample flag: these are recruitment ads, 3.4% of 2026
* postings and a quarter of Donetsk oblast's (2025-26), so analyses of labor demand
* should be shown without them.
gen byte military = branch_id == 48 | (branch_id == 9 ///
    & ustrregexm(ustrlower(company_name), "тцк|бригад|військов\w* частин|національн\w* гвард|\bнгу\b|\bзсу\b|\bтро\b|батальйон|полк|морськ\w* піхот|десантн|прикордонн\w* загін|сил оборони|сил безпілотн") ///
    & !ustrregexm(ustrlower(company_name), "поліці"))

gen wage = salary
gen byte wage_rule = 0
replace wage_rule = 1 if wage == . & salary_from > salary_to & salary_from < . & salary_to < .
replace wage_rule = 5 if wage == . & wage_rule == 0 & military == 1 & salary_from < . & salary_to < .
replace wage_rule = 2 if wage == . & wage_rule == 0 & salary_from < . & salary_to > 5 * salary_from & salary_to < .
replace wage = (salary_from + salary_to) / 2 if wage == . & wage_rule == 0 & salary_from < . & salary_to < .
replace wage = salary_from if wage == . & wage_rule != 1 & salary_from < .
replace wage = salary_to   if wage == . & wage_rule != 1 & salary_to   < .
* Monthly minimum wage (UAH), by date it took effect (State Budget laws; finance.ua):
gen mw = 4723
replace mw = 5000 if created_date >= td(01sep2020)
replace mw = 6000 if created_date >= td(01jan2021)
replace mw = 6500 if created_date >= td(01dec2021)
replace mw = 6700 if created_date >= td(01oct2022)
replace mw = 7100 if created_date >= td(01jan2024)
replace mw = 8000 if created_date >= td(01apr2024)
replace mw = 8647 if created_date >= td(01jan2026)

gen pay_posted = wage if wage < mw / 2
replace wage_rule = 3 if wage < mw / 2
replace wage = . if wage < mw / 2
replace wage_rule = 4 if wage > 500000 & wage < .
replace wage = . if wage_rule == 4
gen byte has_wage = wage < .
gen byte wage_below_mw = wage < mw if wage < .
label define wage_rule_lbl 0 "0 as posted" 1 "1 inverted range: missing" ///
    2 "2 wide range: lower bound" 3 "3 below half min. wage: not monthly, missing" ///
    4 "4 above 500,000: missing" 5 "5 military range: lower bound"
label values wage_rule wage_rule_lbl

* --- Step 7. Who can enter the employer panel -------------------------------

* Test (3) and Anonymous (4) publication types: real vacancies, kept but flagged.
* Anonymous ones have no employer id, so panel_candidate already excludes them.
gen byte test_or_anon = inlist(publication_type, 3, 4)

* Posted by the State Employment Service: regional employment centers (обласний центр
* зайнятості, ОЦЗ) upload vacancies of many employers under their own account. Almost
* none before 2023, then 27% of sampled vacancies in 2025 (Lviv center alone: ~7,200).
* Rule: name mentions an employment center AND industry is "Governmental Sector" (9);
* this keeps out look-alikes (an NGO, a Polish recruiter). 27 accounts on 5 Nov 2026.
gen byte ses_posting = ustrregexm(ustrlower(company_name), "центр зайнятост|оцз|міськрайцентр зайнятост") ///
    & branch_id == 9

* Agencies, state employment centers, and postings without an employer ID stay in aggregate counts only.
gen byte panel_candidate = notebook_id < . & is_agency == 0 & ses_posting == 0

* Likely re-advertisement of the same job: an earlier sampled vacancy has the same
* employer, title, city AND identical description, created at most 90 days before.
* Other repeats of employer + title + city are mostly new demand (several openings
* posted at once, or a new hiring round months later), so they are not flagged.
* Caveat: I see ~10% of postings, so most re-advertisements have their earlier
* posting outside the sample. The flag catches only part of them.
* The description is compared through a hash (fingerprint) made by 00_description_hash.py.
confirm file "$temp/robota_description_hash.csv"   // run do/00_description_hash.py first
preserve
import delimited using "$temp/robota_description_hash.csv", varnames(1) stringcols(2 4) clear
tempfile hashes
save `hashes'
restore
merge 1:1 id using `hashes'
assert _merge == 3          // fails if the hash file comes from a different export
drop _merge
replace pay_unit = "" if pay_posted == .   // only used for amounts below half the minimum wage (step 6)

gen title_key = ustrlower(ustrtrim(name))
gen byte readvert = 0 if notebook_id < . & desc_hash != ""
bysort notebook_id title_key city_id desc_hash (id): replace readvert = 1 ///
    if _n > 1 & readvert < . & created_date - created_date[_n-1] <= 90
drop title_key

* Multi-city batches: one city per vacancy id, so an employer that advertises the same
* job title in several cities creates one vacancy (id) per city. Batch = same employer
* and same title (lowercase, punctuation ignored), created in the same calendar quarter.
*   multicity       1 if the batch has sampled vacancies in 2+ cities
*   n_cities_batch  distinct cities of the batch in the sample (true number is higher:
*                   I see ~26% of ids)
*   broadcast       multi-city batch whose copies all have the same text and the same
*                   posted pay, and none names an address (desc_address, from
*                   00_description_hash.py): possibly ONE job advertised in several cities
* Manual reading of Q3 2026 batches (14 Nov 2026): mostly genuine local openings with a
* template text. Chains (pharmacies, banks, supermarkets, Nova Poshta) reuse the text,
* but pay differs by city in ~43% of batch vacancies and a third name the store address.
* Broadcast candidates are ~7% (regional sales and medical representatives, B2B jobs).
* So multi-city vacancies are kept as local postings; broadcast is for robustness.
* Missing for postings without an employer id and for state employment centers: their
* "copies" are different registered vacancies (own vacancy number, own employer) that
* only share a common title.
gen title_norm = ustrtrim(ustrregexra(ustrlower(name), "[^\p{L}\p{N}]+", " "))
gen int created_q = qofd(created_date)
egen long batch = group(notebook_id title_norm created_q) if notebook_id < . & ses_posting == 0
bysort batch city_id: gen byte first_city = _n == 1 if batch < .
bysort batch: egen int n_cities_batch = total(first_city) if batch < .
gen byte multicity = n_cities_batch >= 2 if batch < .
gen pay_key = string(salary) + "|" + string(salary_from) + "|" + string(salary_to)
bysort batch (desc_hash): gen byte same_text = desc_hash[1] == desc_hash[_N] & desc_hash[1] != "" if batch < .
bysort batch (pay_key): gen byte same_pay = pay_key[1] == pay_key[_N] if batch < .
bysort batch: egen byte any_address = max(desc_address) if batch < .
gen byte broadcast = multicity & same_text & same_pay & any_address == 0 if batch < .
drop title_norm created_q batch first_city pay_key same_text same_pay any_address

* --- Step 8. Readable codes (value labels) ----------------------------------
* Code lists downloaded on 5 Nov 2026 from robota.ua's dictionary API and saved in
* data/crosswalks/ (columns: id, en, ua, ru; the city list also has the oblast):
*   robota_schedule.csv  <- https://api.rabota.ua/dictionary/schedule
*   robota_branch.csv    <- https://api.rabota.ua/dictionary/branch
*   robota_city.csv      <- https://api.rabota.ua/dictionary/city
* Two more lists, built by hand (see the "source" column in each file and step 8e):
*   robota_publication_type.csv  names from the API docs, codes by order (code 4 confirmed)
*   robota_prof_level.csv        NO official list: labels inferred from job titles

* make_labels: read one code list and turn it into a Stata value label.
* The (code, text) pairs are collected first and the label is defined after
* restore, because restore would also undo labels defined in between.
capture program drop make_labels
program define make_labels
    args file textcol lblname
    preserve
    import delimited using "`file'", encoding("utf-8") varnames(1) ///
        bindquote(strict) stringcols(_all) clear
    local pairs ""
    forvalues i = 1/`=_N' {
        local code = id[`i']
        local text = subinstr(`textcol'[`i'], char(96), char(39), .)  // backtick -> apostrophe (a backtick breaks Stata macros)
        local pairs `"`pairs' `code' `"`text'"'"'
    }
    restore
    label define `lblname' `pairs', add
end

* 8a. Schedule and employer industry (English names). Code 0 is in the data but not in the lists.
make_labels "$dict/robota_schedule.csv" en schedule_lbl
make_labels "$dict/robota_branch.csv"   en branch_lbl
label define schedule_lbl 0 "0 (not in robota.ua list)", add
label define branch_lbl   0 "0 (not in robota.ua list)", add
label values schedule_id schedule_lbl
label values branch_id   branch_lbl

* 8b. City (English names) and its oblast, taken from the same city list
make_labels "$dict/robota_city.csv" en city_lbl
label values city_id city_lbl

preserve
import delimited using "$dict/robota_city.csv", encoding("utf-8") varnames(1) ///
    bindquote(strict) clear
keep id oblast_ua
rename (id oblast_ua) (city_id oblast)
tempfile oblasts
save `oblasts'
restore
merge m:1 city_id using `oblasts', keep(master match)
count if _merge == 1                  // cities missing from the list (0 on 5 Nov 2026)
drop _merge
* NB: the list gives no oblast for a few places (e.g. Zakarpattia towns, Crimea): oblast is "" there.

* 8c. District: the data carry one name per district_id, so the label comes from the data
levelsof district_id, local(dcodes)
foreach d of local dcodes {
    levelsof district_name if district_id == `d', local(dname) clean
    if `"`dname'"' != "" label define district_lbl `d' `"`dname'"', add
}
capture label values district_id district_lbl

* 8d. Publication type (the robota.ua posting package) and professional level.
* publication_type: the API docs list Undefined, Optimum, Proffessional, Test, Anonymous,
*   Bussines without numbers; codes follow that order. Code 4 = Anonymous is confirmed:
*   every such posting is "Анонимный работодатель" with no employer id.
* prof_level_id: robota.ua publishes no names. The data show an ordered seniority scale
*   (1 workers ... 6 directors), so labels keep the number and say "(inferred)".
make_labels "$dict/robota_publication_type.csv" en pubtype_lbl
make_labels "$dict/robota_prof_level.csv"       en proflevel_lbl
label values publication_type pubtype_lbl
label values prof_level_id    proflevel_lbl

* 8e. Yes/no variables
label define yesno 0 "no" 1 "yes"
label values is_active verified_company is_agency hot post_invasion has_wage wage_below_mw ///
    panel_candidate test_or_anon readvert ses_posting military desc_address multicity broadcast yesno

* --- Step 9. Labels, order, save --------------------------------------------
label var id             "Vacancy id (robota.ua)"
label var plan_year      "Sampling stratum (id range in plan.json)"
label var true_year      "Calendar year of creation, from id"
label var pub_date       "Latest publication date"
label var pub_year       "Latest publication year"
label var pub_month      "Latest publication month"
label var pub_day        "Latest publication day"
label var pub_time       "Latest publication time"
label var fetch_date     "Date the vacancy was collected"
label var is_active      "Vacancy still open at collection"
label var name           "Job title"
label var city_id        "City id"
label var city_name      "City name (Russian)"
label var oblast         "Oblast of the city (Ukrainian, robota.ua city list)"
label var district_id    "District id (Kyiv only; missing elsewhere or if not given)"
label var district_name  "District name (Kyiv only)"
label var latitude       "Latitude (missing if 0 in source)"
label var longitude      "Longitude (missing if 0 in source)"
label var salary         "Single salary (missing if 0)"
label var salary_from    "Salary range: lower bound"
label var salary_to      "Salary range: upper bound"
label var salary_comment "Salary comment (free text)"
label var schedule_id    "Schedule code"
label var prof_level_id  "Professional level, 0-6 (labels inferred from titles)"
label var branch_id      "Employer industry code"
label var branch_name    "Employer industry"
label var notebook_id    "Employer id (missing if none)"
label var company_name   "Employer name"
label var verified_company "Employer verified by robota.ua"
label var is_agency      "Posted by a recruitment agency"
label var publication_type "Publication type (posting package)"
label var hot            "Hot vacancy flag"
label var tags_json      "Tags (JSON)"
label var clusters_json  "Clusters (JSON)"
label var languages_json "Languages (JSON)"
label var weight         "Sampling weight (IDs in range / IDs visited)"
label var post_invasion  "(to be checked) Created on/after 24 Feb 2022 (id >= 9,138,846)"
label var wage           "Monthly wage, UAH (rules in step 6, see wage_rule)"
label var wage_rule      "Rule applied to build wage"
label var pay_posted     "Posted pay below half the min. wage (per hour/day/piece; see pay_unit)"
label var pay_unit       "Period of pay_posted, if stated (hour/day/week/month/piece/thousands)"
label var has_wage       "Monthly wage observed"
label var mw             "Monthly minimum wage at creation, UAH"
label var wage_below_mw  "Monthly wage below the minimum wage (mostly part-time)"
label var panel_candidate "Has employer id, not an agency, not an employment center"
label var test_or_anon   "Publication type Test or Anonymous (kept, flagged)"
label var created_date   "Creation date: earliest date_published at this or a later id (step 5)"
label var desc_hash      "Fingerprint of the description (same text = same hash)"
label var desc_len       "Length of the description, characters"
label var readvert       "Likely re-ad: same employer, title, city, text within 90 days"
label var ses_posting    "Posted by a state employment center (ОЦЗ), for other employers"
label var military       "Military employer (armed forces, National Guard, ТЦК; step 6)"
label var desc_address   "Description names a street address or precise workplace"
label var multicity      "Same employer + title sampled in 2+ cities, same quarter (step 7)"
label var n_cities_batch "Cities of the employer + title + quarter batch, in the sample"
label var broadcast      "Multi-city, same text and pay, no address: possibly one job"

order id plan_year true_year post_invasion pub_date pub_year pub_month pub_day ///
	  pub_time fetch_date is_active notebook_id company_name is_agency panel_candidate ///
	  name wage has_wage
compress
drop *_json
save "$out/robota_vacancies_clean.dta", replace

* --- Step 10. Quick checks --------------------------------------------------
tab true_year post_invasion
tab panel_candidate
tab publication_type test_or_anon
tab true_year readvert, row
tab true_year multicity, row nofreq
tab true_year broadcast if multicity == 1, row nofreq
tab true_year ses_posting, row nofreq
tab true_year military, row nofreq
sum wage, detail
tab wage_rule
tab true_year wage_below_mw, row nofreq
tab pay_unit if pay_posted < ., missing
tab schedule_id, missing
tab branch_id, missing
tab prof_level_id, missing
tab publication_type, missing
tab oblast, missing sort

// Only five: 
bysort notebook_id (company_name): gen byte mismatch = company_name[1] != company_name[_N]
list notebook_id company_name if mismatch, sepby(notebook_id)

log close
