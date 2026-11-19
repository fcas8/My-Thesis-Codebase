* =============================================================================
* 07_decomposition.do  --  extensive vs. intensive margin of the D1-D3 effects
*
* Splits each D1-D3 coefficient of 06_designs.do into an extensive and an intensive
* part. With an exponential mean, ln E[Y] = ln E[A] + ln E[Y/A], so
*     beta_total = beta_extensive + beta_intensive,
* where A is the extensive outcome:
*   D1  location x quarter:            A = employers posting in the location (n_emp);
*                                      intensive = postings per employer posting
*   D2  employer x quarter:            A = 1(employer posts in the quarter);
*                                      intensive = postings when active
*   D3  employer x location x quarter: A = 1(employer posts in the location);
*                                      intensive = postings per active branch
* beta_total (Y) and beta_extensive (A) are estimated by PPML; beta_intensive is their
* difference. This avoids running PPML on the active cells only (selected on a post-
* treatment outcome): the intensive part is an accounting residual, not the effect on
* units that would stay active anyway.
*
* Estimation: both outcomes are stacked in one PPML, every fixed effect and the exposure
* interacted with the outcome. The point estimates equal the separate regressions; the
* stacking gives their covariance (clustered by raion) for the SE of the difference.
*
* KNOWN BIAS (to be corrected): Y counts SAMPLED postings (about a third of all IDs). A
* unit with few true postings often shows none in the sample, so a fall in postings per
* unit also lowers the share of units seen active: the extensive part is overstated and
* the intensive part understated, most in D3 (cells with 0-2 sampled postings) and least
* in D1. The total is not affected. D2 and D3 also miss entry (incumbents and pre-war
* locations only): new employers and new branches are not in these panels.
*
* Input : data/temp/designs/06_panel_*.dta   (06_designs.do, estimation panels)
* Output: output/tables/07_decomposition.xlsx/.tex   all designs and measures
*         output/figures/07_decomposition.pdf        components, first set of fixed effects
*         data/temp/designs/07_estimates.dta         every estimate
*         data/temp/logs/07_decomposition.log
*         Every output is listed in output_inventory.xlsx (Project folder).
*
* Choices (18 Nov 2026): same samples, fixed effects and clusters as 06_designs.do, both
* sets of fixed effects. Activity is by quarter (the identity needs the same cell as Y),
* not absorbing exit.
*
* Needs: ppmlhdfe. Run after 06_designs.do. Takes ~2 h (D3 stacked regressions).
* =============================================================================

clear all
set more off
set linesize 200

* --- Step 0. Paths ----------------------------------------------------------------
if "$project" == "" global project "`c(pwd)'/.."   // set by 00_main.do; else run from the repo root
global tab     "$project/Project/output/tables"
global fig     "$project/Project/output/figures"
global tmp6    "$project/Project/data/temp/designs"
global temp    "$project/Project/data/temp"
global do      "$project/Project/do"

cap log close
log using "$temp/logs/07_decomposition.log", replace text

do "$do/00_programs.do"


* --- Programs ----------------------------------------------------------------------
* est_dec: stacked PPML of the total outcome y and the extensive outcome a on exposure x;
* posts beta_total, beta_extensive and beta_intensive = their difference.
*   est_dec <col>, table() measure() x() y() a() cl() absorb() fe()
capture program drop est_dec
program define est_dec
    syntax anything(name=col), Table(string) Measure(string) X(varname) Y(varname) ///
        A(varname) CL(varname) Absorb(string) FE(string)
    preserve
    keep if `x' < .
    local kv "`y' `a' `x' `cl' `absorb' q"
    local kv : list uniq kv
    keep `kv'
    gen long __id = _n
    expand 2
    bysort __id: gen byte k = _n                  // 1 = total, 2 = extensive
    gen double yk    = cond(k == 1, `y', `a')
    gen double x_tot = `x' * (k == 1)
    gen double x_ext = `x' * (k == 2)
    local ab ""
    foreach f of local absorb {
        local ab "`ab' `f'#k"
    }
    ppmlhdfe yk x_tot x_ext, absorb(`ab') vce(cluster `cl')
    local bt = _b[x_tot]
    local st = _se[x_tot]
    local be = _b[x_ext]
    local se = _se[x_ext]
    lincom x_tot - x_ext
    local bi = r(estimate)
    local si = r(se)
    quietly count if e(sample) & k == 1
    local N = r(N)
    local nc = e(N_clust)
    * mean of the extensive outcome in the pre-war quarters (share active / employers)
    quietly summarize `a' if e(sample) & k == 1 & q < tq(2022q1)
    local abar = r(mean)
    post dec_post (`col') ("`table'") ("`measure'") (`bt') (`st') (`be') (`se') (`bi') ///
        (`si') (`N') (`nc') (`abar') ("`fe'")
    restore
end

postfile dec_post col str4 table str8 measure double(b_tot se_tot b_ext se_ext b_int ///
    se_int) long(N n_clust) double(a_mean) str40 fe using "$tmp6/07_estimates.dta", replace


* --- Step 1. D1: location x quarter (A = employers posting) ----------------------------
use "$tmp6/06_panel_d1_raion.dta", clear
est_dec 1, table(D1) measure(alarms) x(alarms) y(y) a(n_emp) cl(loc) ///
    absorb(loc size_q) fe(loc sizeq)
est_dec 2, table(D1) measure(alarms) x(alarms) y(y) a(n_emp) cl(loc) ///
    absorb(loc obl_q size_q) fe(loc oblq sizeq)
use "$tmp6/06_panel_d1_city.dta", clear
local c = 3
foreach m in front attacks {
    est_dec `c', table(D1) measure(`m') x(`m') y(y) a(n_emp) cl(cl) ///
        absorb(loc size_q) fe(loc sizeq)
    local ++c
    est_dec `c', table(D1) measure(`m') x(`m') y(y) a(n_emp) cl(cl) ///
        absorb(loc obl_q size_q) fe(loc oblq sizeq)
    local ++c
}


* --- Step 2. D2: employer x quarter (A = employer posts) -------------------------------
use "$tmp6/06_panel_d2.dta", clear
gen byte active = y > 0
local c = 1
foreach m in alarms front attacks {
    est_dec `c', table(D2) measure(`m') x(`m') y(y) a(active) cl(cl) ///
        absorb(notebook_id size_q) fe(emp sizeq)
    local ++c
    est_dec `c', table(D2) measure(`m') x(`m') y(y) a(active) cl(cl) ///
        absorb(notebook_id sec_q size_q) fe(emp secq sizeq)
    local ++c
}


* --- Step 3. D3: employer x pre-war location x quarter (A = employer posts there) -------
local c = 1
foreach lev in raion city {
    use "$tmp6/06_panel_d3_`lev'.dta", clear
    gen byte active = y > 0
    local ms = cond("`lev'" == "raion", "alarms", "front attacks")
    foreach m of local ms {
        est_dec `c', table(D3) measure(`m') x(`m') y(y) a(active) cl(cl) ///
            absorb(emp_loc emp_q size_q) fe(emploc empq sizeq)
        local ++c
        est_dec `c', table(D3) measure(`m') x(`m') y(y) a(active) cl(cl) ///
            absorb(emp_loc emp_q obl_q size_q) fe(emploc empq oblq sizeq)
        local ++c
    }
}
postclose dec_post


* --- Step 4. Table ---------------------------------------------------------------------
* Rows: design (panel) x measure (coefficient, SE below). Columns: total, extensive,
* intensive, for each set of fixed effects. Coefficients as in the 06 tables.
use "$tmp6/07_estimates.dta", clear
label var b_tot "Total: PPML of postings"
label var b_ext "Extensive: PPML of the extensive outcome"
label var b_int "Intensive: total - extensive"
label var a_mean "Mean of the extensive outcome, pre-war quarters"
save "$tmp6/07_estimates.dta", replace
list table col measure b_tot b_ext b_int se_tot se_ext se_int N a_mean, noobs sep(0)

gen byte fe2 = mod(col, 2) == 0
gen byte mo  = cond(measure == "alarms", 1, cond(measure == "front", 2, 3))
foreach s in tot ext int {
    gen double p_`s' = 2 * normal(-abs(b_`s' / se_`s'))
    gen str12 sb_`s' = strtrim(string(b_`s', "%9.3f")) + ///
        cond(p_`s' < 0.01, "***", cond(p_`s' < 0.05, "**", cond(p_`s' < 0.10, "*", "")))
    gen str12 ss_`s' = "(" + strtrim(string(se_`s', "%9.3f")) + ")"
}
keep table mo fe2 sb_* ss_*
reshape wide sb_tot sb_ext sb_int ss_tot ss_ext ss_int, i(table mo) j(fe2)
* two rows per measure (coefficient, SE), one panel title per design
expand 2
bysort table mo: gen byte r = _n
gen byte row_type = cond(r == 1, 2, 3)
gen str80 label = cond(mo == 1, "Alarms (raion)", cond(mo == 2, "Front (city)", "Attacks (city)"))
replace label = "" if r == 2
local j = 0
foreach f in 0 1 {
    foreach s in tot ext int {
        local ++j
        gen str12 c`j' = cond(r == 1, sb_`s'`f', ss_`s'`f')
    }
}
keep table mo r row_type label c1-c6
gen byte o = 1
preserve
    keep table
    duplicates drop
    gen byte row_type = 1
    gen str80 label = "D1: location x quarter (extensive = employers posting)" if table == "D1"
    replace label = "D2: employer x quarter (extensive = employer posts)" if table == "D2"
    replace label = "D3: employer x location x quarter (extensive = posts there)" if table == "D3"
    gen byte o = 0
    tempfile heads
    save `heads'
restore
append using `heads'
sort table o mo r
keep row_type label c1-c6
label var label " "
label var c1 "Total"
label var c2 "Extensive"
label var c3 "Intensive"
label var c4 "Total "
label var c5 "Extensive "
label var c6 "Intensive "
list, noobs sep(0) abbreviate(20)
export_panel_table using "$tab/07_decomposition", ///
    title("Margins of the D1-D3 effects, PPML; (1)-(3) size band x quarter FE, (4)-(6) + oblast x quarter (D1, D3) / sector x quarter (D2)")


* --- Step 5. Figure ----------------------------------------------------------------------
* Components in log points x 100 for the same steps as the 06 tables (+10 pp of days for
* alarms and attacks, distance halved for front), so that extensive + intensive = total.
* First set of fixed effects (size band x quarter).
set scheme stcolor
graph set window fontface "Arial"
use "$tmp6/07_estimates.dta" if mod(col, 2) == 1, clear
gen double step = cond(measure == "front", ln(2), 0.1)
gen byte mo = cond(measure == "alarms", 1, cond(measure == "front", 2, 3))
label define mo_lbl 1 "Alarms: +10 pp of days" 2 "Front: distance halved" 3 "Attacks: +10 pp of days"
label values mo mo_lbl
gen byte d = real(substr(table, 2, 1))
keep d mo step b_* se_*
reshape long b_ se_, i(d mo) j(comp) string
gen double est = 100 * step * b_
gen double lo  = 100 * step * (b_ - invnormal(0.975) * se_)
gen double hi  = 100 * step * (b_ + invnormal(0.975) * se_)
gen double yy  = 4 - d + cond(comp == "tot", 0.22, cond(comp == "ext", 0, -0.22))
twoway (rcap lo hi yy if comp == "tot", horizontal lcolor(gs6)) ///
       (scatter yy est if comp == "tot", mcolor(gs6) msymbol(O)) ///
       (rcap lo hi yy if comp == "ext", horizontal lcolor(navy)) ///
       (scatter yy est if comp == "ext", mcolor(navy) msymbol(D)) ///
       (rcap lo hi yy if comp == "int", horizontal lcolor(maroon)) ///
       (scatter yy est if comp == "int", mcolor(maroon) msymbol(S)), ///
    by(mo, rows(1) xrescale note("") legend(position(6)) imargin(medsmall)) subtitle(, size(medlarge) fcolor(gs14) lcolor(gs14)) ///
    xline(0, lcolor(gs10) lpattern(dash)) ///
    ylabel(3 "D1 location" 2 "D2 employer" 1 "D3 employer x location", angle(0) nogrid labsize(medlarge)) ///
    yscale(range(0.5 3.5)) ytitle("") ///
    xtitle("Effect on ln postings x 100 (95% CI)", size(medlarge)) ///
    legend(order(2 "Total" 4 "Extensive" 6 "Intensive") rows(1) size(medlarge)) ///
    xlabel(, labsize(medlarge)) xsize(10) ysize(3.4)
graph export "$fig/07_decomposition.pdf", replace

log close
