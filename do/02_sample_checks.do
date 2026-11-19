* =============================================================================
* 02_sample_checks.do  --  robota.ua vacancy sample: checks before analysis
*
* Input : data/analysis/robota_vacancies_clean.dta   (from 01_clean.do)
*         <export folder>/year_summary.csv           (sampling summary from the collector)
* Output: data/temp/logs/02_sample_checks.log         (all results)
*         data/temp/employer_link_candidates.csv     (employer ids to review by hand;
*                                                     in data/temp because it holds names)
*
* Nothing here changes the data. Each step prints a table and says what to look for.
* Run after 01_clean.do. $export is taken from 01_clean.do if it is still set.
* =============================================================================

clear all
set more off
set linesize 200      // wide log, so lists fit on one line

* --- Step 0. Paths ----------------------------------------------------------
if "$project" == "" global project "`c(pwd)'/.."   // set by 00_main.do; else run from the repo root
if "$export" == "" global export "$project/Collector/data/exports/20261110_094445"  // keep in line with 01_clean.do
global data    "$project/Project/data/analysis"
global temp    "$project/Project/data/temp"

cap mkdir "$temp"
cap log close
cap mkdir "$project/Project/data/temp/logs"
log using "$project/Project/data/temp/logs/02_sample_checks.log", replace text

use "$data/robota_vacancies_clean.dta", clear
local inv = tc(24feb2022 00:00:00)   // start of the full-scale invasion
local first_post_id = 9138846        // first post-invasion vacancy id (see docs/pipeline.md, §5.2)

* --- Step 1. Sample size and weights ----------------------------------------
* 1a. The weight must be the same for every vacancy of a sampling stratum (plan_year).
bysort plan_year: assert weight == weight[1]

* 1b. My counts must match the collector's own summary for the same export.
preserve
	import delimited using "$export/year_summary.csv", varnames(1) clear
	keep plan_year ids_in_range ids_visited vacancies_found hit_rate sampling_fraction weight
	rename weight weight_summary
	tempfile ys
	save `ys'
restore
preserve
	contract plan_year weight
	merge 1:1 plan_year using `ys', nogenerate
	assert _freq == vacancies_found
	assert abs(weight - weight_summary) < 1e-6
	* hit_rate = vacancies found / ids visited. A low rate means many ids lead nowhere
	* (deleted, unpublished or never used); it cannot tell these apart.
	list plan_year ids_visited vacancies_found hit_rate sampling_fraction weight, noobs sep(0)
restore

* 1c. Sampled and estimated (weighted) vacancies by calendar year of creation
table true_year, statistic(frequency) statistic(sum weight) nformat(%12.0fc)

* --- Step 2. Time: vacancy id against publication date ----------------------
* The period of a vacancy comes from its id. date_published is the LATEST
* (re)publication, so it can be later than creation but never earlier.

* 2a. The earliest publication date in each block of 100,000 ids should move forward
*     with the id. A block whose earliest date is before the previous block's is flagged.
preserve
	gen long idblock = floor(id / 100000) * 100000
	collapse (min) first_pub = pub_date (count) n = id, by(idblock)
	format first_pub %tcCCYY-NN-DD
	gen byte goes_back = first_pub < first_pub[_n-1] if _n > 1
	list, noobs sep(0)
	count if goes_back == 1
restore

* 2b. Published before the year the id says it was created: should be (almost) 0.
*     A few are expected just after a year cut-off: the cut-off ids (plan.json) are approximate.
count if pub_year < true_year
preserve
	keep if pub_year < true_year
	sort id
	list id true_year pub_date in 1/`=min(_N, 10)', noobs sep(0)
restore

* 2c. Invasion boundary. Share of vacancies published before 24 Feb 2022, by block of
*     1,000 ids around the boundary. It should fall to 0 at id 9,138,846.
preserve
	keep if inrange(id, 9120000, 9160000)
	gen long idblock = floor(id / 1000) * 1000
	gen byte before = pub_date < `inv'
	collapse (mean) share_before = before (count) n = id (min) first_pub = pub_date, by(idblock)
	format first_pub %tcCCYY-NN-DD_HH:MM
	format share_before %5.2f
	list, noobs sep(0)
restore
* post-invasion ids published before the invasion: must be 0 if the boundary is right
count if id >= `first_post_id' & pub_date < `inv'

* --- Step 3. Repeats and re-advertisements -----------------------------------
* repeat = an earlier sampled vacancy has the same employer, title and city.
* A repeat is not always the same job advertised again: it can be several openings
* posted at once, or a new hiring round months later (new demand). Two clues:
*   - time since the earlier vacancy (created_date, from the id; see 01_clean.do step 5)
*   - identical description (desc_hash, from 00_description_hash.py)
* 01_clean.do flags only "identical text within 90 days" as a likely re-ad (readvert).
gen title_key = ustrlower(ustrtrim(name))
bysort notebook_id title_key city_id (id): gen gap_days = created_date - created_date[_n-1] ///
    if _n > 1 & notebook_id < .
bysort notebook_id title_key city_id (id): gen byte same_text = desc_hash == desc_hash[_n-1] ///
    if _n > 1 & notebook_id < .
drop title_key

* 3a. Repeats by time since the earlier vacancy, and how often the text is identical
gen gap_group = cond(gap_days <= 1, 1, cond(gap_days <= 7, 2, cond(gap_days <= 31, 3, ///
    cond(gap_days <= 92, 4, cond(gap_days <= 183, 5, cond(gap_days <= 365, 6, ///
    cond(gap_days <= 730, 7, 8))))))) if gap_days < .
label define gap_lbl 1 "<= 1 day" 2 "2-7 days" 3 "8-31 days" 4 "1-3 months" ///
    5 "3-6 months" 6 "6-12 months" 7 "1-2 years" 8 "> 2 years"
label values gap_group gap_lbl
label var gap_group "Time since earlier vacancy, same employer + title + city"
tabstat same_text, by(gap_group) statistics(n mean) format(%5.3f)

* 3b. Likely re-ads by year: a rise after the invasion could mean jobs got harder to fill
*     (e.g. mobilization), which would raise posting counts without more demand.
*     Shown with and without the state employment centers (ses_posting), whose bulk
*     uploads (Lviv center, 2025) create a spike of their own.
tabstat readvert, by(true_year) statistics(n mean) format(%5.3f)
tabstat readvert if ses_posting == 0, by(true_year) statistics(n mean) format(%5.3f)

* 3c. ...and by employer size (number of sampled vacancies): re-ads are easier to catch
*     for large employers, because their earlier posting is more often in the sample.
bysort notebook_id: gen emp_n = _N if notebook_id < .
gen emp_size = cond(emp_n <= 5, 1, cond(emp_n <= 20, 2, cond(emp_n <= 100, 3, 4))) if emp_n < .
label define size_lbl 1 "1-5" 2 "6-20" 3 "21-100" 4 "> 100"
label values emp_size size_lbl
tabstat readvert, by(emp_size) statistics(n mean) format(%5.3f)

* 3d. ...and by oblast, before and after the invasion. A threat to the design is if
*     re-ads rise more where the war hit harder.
table oblast post_invasion if ses_posting == 0, statistic(mean readvert) nformat(%5.3f)
drop gap_days same_text gap_group emp_n emp_size

* --- Step 4. Employer identity ----------------------------------------------
* 4a. One employer id, several names (5 cases on 5 Nov 2026: renames, brands, an agency)
gen cname = ustrlower(ustrtrim(company_name))
bysort notebook_id (cname): gen byte several_names = cname[1] != cname[_N] if notebook_id < .
egen tag_emp = tag(notebook_id) if notebook_id < .
count if several_names == 1 & tag_emp == 1
preserve
	keep if several_names == 1
	contract notebook_id company_name is_agency
	list, sepby(notebook_id) noobs
restore

* 4b. Deleted employer accounts. robota.ua seems to rename a deleted account to "delete";
*     its vacancies stay online but lose the real name.
gen byte deleted_account = inlist(cname, "delete", "deleted")
tab true_year deleted_account if notebook_id < .
count if deleted_account == 1 & tag_emp == 1
drop several_names

* 4c. Does notebook_id grow with the age of the account? Compare it with the id of the
*     employer's first sampled vacancy. A high correlation means newer accounts have
*     higher ids, which helps to tell new accounts from old ones in 4d.
preserve
	keep if notebook_id < .
	collapse (min) first_vac = id, by(notebook_id)
	spearman notebook_id first_vac
restore

* --- Step 4d. Same firm, several employer ids? -------------------------------
* A firm that moved (e.g. away from occupied areas) may have opened a new account.
* Its old id then looks like a firm that stopped posting: a false exit.
* Two ids count as possibly the same firm if their names match after removing case,
* punctuation and legal forms (ТОВ, ФОП, ООО, ...) AND they are in the same industry.
* Name matches alone are noisy: generic names ("Аврора", "Мрія") belong to many firms.
preserve
	keep if notebook_id < . & is_agency == 0 & deleted_account == 0
	gen nm = usubinstr(cname, "ё", "е", .)
	replace nm = ustrregexra(nm, "[^\p{L}\p{N} ]", " ")
	replace nm = ustrregexra(nm, "\b(тов|тд|пп|фоп|флп|ооо|чп|пат|прат|ат|ао|зао|оао|llc|ltd|inc|кп|дп)\b", " ")
	replace nm = ustrtrim(ustrregexra(nm, "\s+", " "))
	drop if nm == ""

	* one row per employer id
	bysort notebook_id: egen nm_mode     = mode(nm), minmode
	bysort notebook_id: egen branch_mode = mode(branch_id), minmode
	bysort notebook_id: egen oblast_mode = mode(oblast), minmode
	gen byte pre = id < `first_post_id'
	collapse (sum) n_pre = pre n_post = post_invasion (min) first_vac = id (max) last_vac = id ///
		(firstnm) nm = nm_mode branch = branch_mode oblast = oblast_mode, by(notebook_id)

	* ids that share a name and an industry with at least one other id
	bysort nm branch: gen n_ids_same_name = _N
	count if n_ids_same_name > 1

	* baseline firms that show no post-invasion posting, and whether another id with the
	* same name and industry does post after the invasion (a possible new account)
	bysort nm branch: egen other_posts_after = max(n_post > 0)
	foreach k in 1 3 5 {
		di as text _n "Baseline firms with at least `k' sampled pre-invasion vacancies:"
		count if n_pre >= `k'
		count if n_pre >= `k' & n_post == 0
		count if n_pre >= `k' & n_post == 0 & n_ids_same_name > 1 & other_posts_after == 1
	}

	* list for manual review: every id in a name group that contains a baseline firm
	* (>= 3 pre-invasion vacancies) with no post-invasion vacancy, next to an id that posts after
	gen byte stopper = n_pre >= 3 & n_post == 0 & n_ids_same_name > 1 & other_posts_after == 1
	bysort nm branch: egen review_group = max(stopper)
	keep if review_group == 1
	gen same_firm = ""            // to fill by hand: yes / no / unsure
	sort nm branch first_vac
	label values branch branch_lbl
	list nm notebook_id branch oblast n_pre n_post first_vac last_vac, sepby(nm) noobs
	* never overwrite the review file (same_firm may be filled by hand): write a new one next to it
	capture confirm file "$temp/employer_link_candidates.csv"
	local outfile = cond(_rc, "employer_link_candidates.csv", "employer_link_candidates_new.csv")
	export delimited nm notebook_id branch oblast n_pre n_post first_vac last_vac same_firm ///
		using "$temp/`outfile'", replace
	di as text "candidate list written to $temp/`outfile'"
restore
drop cname tag_emp

* --- Step 5. Can I tell a firm stopped posting? -----------------------------
* I see about a fraction f (~10%) of each firm's vacancies. A firm with Y vacancies in
* a period shows none in the sample with probability (1-f)^Y. So "no sampled vacancy
* after the invasion" means little for small firms: below Y of about 28 (f = 10%) the
* chance of seeing none, even if the firm kept posting, is over 5%.
* Table: baseline firms by number of sampled pre-invasion vacancies, and share with none after.
preserve
	keep if panel_candidate == 1
	gen byte pre = id < `first_post_id'
	collapse (sum) n_pre = pre n_post = post_invasion, by(notebook_id)
	keep if n_pre >= 1
	gen n_pre_group = cond(n_pre == 1, 1, cond(n_pre == 2, 2, cond(n_pre <= 4, 3, ///
		cond(n_pre <= 9, 5, cond(n_pre <= 19, 10, 20)))))
	label define npre_lbl 1 "1" 2 "2" 3 "3-4" 5 "5-9" 10 "10-19" 20 "20+"
	label values n_pre_group npre_lbl
	gen byte none_after = n_post == 0
	tabstat none_after, by(n_pre_group) statistics(n mean) format(%5.3f)
restore

* --- Step 6. Salaries ---------------------------------------------------------
* 6a. Distribution by year (UAH per month, after the rules in 01 step 6). Look for jumps in p1/p99.
tabstat wage, by(true_year) statistics(n p1 p10 p50 p90 p99) format(%9.0fc)
* 6b. Which rule built the wage, by year
tab true_year wage_rule, row nofreq
* 6c. Pay below half the minimum wage (not monthly): its stated period, and the amounts in each period
tab pay_unit if pay_posted < ., missing
tabstat pay_posted, by(pay_unit) statistics(n p10 p50 p90) format(%9.0fc)
* 6d. Very high monthly wages: up to ~200,000 these are mostly real (IT seniors, directors,
*     jobs abroad, army contracts with combat pay). Above 500,000 they were all typos
*     (5,000,500), made-up maxima, or one-off army bonuses (1,000,000 for 18-24 contracts),
*     so 01 sets them to missing (wage_rule 4). Listed here to check new exports.
count if wage > 200000 & wage < .
preserve
	keep if wage_rule == 4
	list id true_year name salary salary_from salary_to salary_comment, noobs sep(0)
restore
* 6e. Military employers (01 step 6): wages by year with and without them, and the most
*     common military ranges (should be the pay tiers: base, +30,000, +100,000)
tabstat wage if military == 0, by(true_year) statistics(n p50 p90) format(%9.0fc)
tabstat wage if military == 1, by(true_year) statistics(n p25 p50 p75) format(%9.0fc)
preserve
	keep if military == 1 & salary_from < . & salary_to < .
	contract salary_from salary_to
	gsort -_freq
	list in 1/10, noobs sep(0)
restore

* --- Step 7. Geography -------------------------------------------------------
* 7a. No oblast (places the city list does not assign) and postings abroad
count if oblast == ""
count if oblast == "Інші країни"
* 7b. Coordinates outside a box around Ukraine (lat 44-52.5, lon 22-40.5)
count if latitude < . & (!inrange(latitude, 44, 52.5) | !inrange(longitude, 22, 40.5))
* 7c. Share of vacancies by oblast before and after the invasion
tab oblast post_invasion, column nofreq
* 7d. Oblasts occupied in part since 2022 (or 2014), by year
gen byte occupied_oblast = inlist(oblast, "Донецька область", "Луганська область", ///
    "Херсонська область", "Запорізька область", "Крим")
tabstat occupied_oblast, by(true_year) statistics(mean) format(%5.3f)
drop occupied_oblast
* 7e. Share of military postings by oblast, 2025-26: high in frontline oblasts, so counts
*     of postings by oblast need a version without them
table oblast if true_year >= 2025, statistic(mean military) statistic(frequency) nformat(%5.3f mean)

* --- Step 8. Composition over time -------------------------------------------
* Sudden jumps in these shares point to changes on the platform, not in the labor market.
tabstat is_agency ses_posting military test_or_anon panel_candidate has_wage verified_company is_active, ///
    by(true_year) statistics(mean) format(%5.3f)
tab true_year publication_type, row nofreq
tab true_year schedule_id, row nofreq

* --- Step 9. Missing values ---------------------------------------------------
misstable summarize, all

log close



/* Notes after run (5/11, 11:25)
- A few postings noted as 2021 but in reality 30/12/2020
- Reposts increasing over time -> Determine how they are treated
	Added ses_posting and readvert in the clean do file
- One employer id, several names (5 cases on 5 Nov 2026: renames, brands, an agency)
- 41 deleted accounts, 112 vacancies in total. -> No cost to "exist" on the platform though
- One name and industry, several IDs: 20 cases, candidate links csv saved for robustness checks in analysis
- Salaries: drop inverted ranges? maybe not a good idea. Look into comments and description for implausibly low salaries. Same for high salaries. Expand list to full list of vacancies.
	Done in 01 step 6 (wage_rule 1-4); pay below half the minimum wage kept in pay_posted/pay_unit (mw by creation date)

Notes after run (6/11, 12:41; export 20261106_123402, 12% sample, 279,509 vacancies)
- Weights and estimated totals stable vs 5/11 (2026: 310,623 vs 310,503)
- Employment-center postings pull the pooled wage down (median ~12,000; 37% of 2025 wages):
	median 2025 21,000 pooled vs 26,500 without ses_posting. Wage series need a version without them
- readvert rises with the sampling fraction (2.3% -> 2.6%): compare rates within an export only
- 2026 p1 wage = 8,647 = 2026 minimum wage
- Employer link candidates: 25 at k >= 3 (was 20), written to employer_link_candidates_new.csv

Notes after run (9/11, 11:21; export 20261109_111319, 15.9% sample, 370,070 vacancies; via 00_main.do)
- All checks pass; estimated totals stable (2026: 311,538 vs 310,623); wage rules and medians unchanged
- readvert 3.2% (was 2.6%): 2025 at 5.9% is all ses_posting (2.0% without)
- One employer id, several names: 10 (was 6), incl. a typo, a brigade spelled two ways, a "delete" account
- Employer link candidates: 38 at k >= 3 (was 25)
- Rule 4 (> 500,000): 25 postings, same kinds as before (army 18-24 contracts, typos, made-up maxima)
- 00/01/02 fallback export still 6 Nov: run through 00_main.do (01 alone stops at the hash merge)
- Army ranges: many "base to base + 100,000" (combat top-up); rule 2 gives some the lower bound, others the midpoint
	Done in 01 step 6: military flag + wage_rule 5 (military range: lower bound); checks in 6e and 7e
*/