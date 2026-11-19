* =============================================================================
* 00_main.do  --  runs the whole robota.ua pipeline, in order
*
* To rebuild everything (e.g. after a new export from the collector), change
* $export below and run this file. Each step writes its own log in data/temp/logs/.
* To rerun the Stata part only, set $run_python to 0 (below the paths).
*
*   Python helpers (things Stata cannot do well; each writes small files to data/temp)
*     00_description_hash.py  description fingerprints and pay period    (export)
*     00_city_raion.py        robota.ua city -> raion, raion list         (export, map)
*     00_viina_control.py     who controls each place, by month           (VIINA)
*     00_oblast_borders.py    oblast/country borders as lines, raion polygons (maps)
*     00_text_features.py     tags and text flags of each vacancy          (export)
*     00_viina_exposure.py    distance to the front, attacks nearby        (VIINA)
*                             -- NOT called here: 03_exposure_build.do (step V1) runs
*                             it with the settings of its step 0, so they are set once
*   Stata
*     00_programs.do          shared programs (export_table: final tables as .xlsx + .tex)
*     01_clean.do             vacancy sample: cleaning
*     02_sample_checks.do     checks before analysis (changes no data)
*     03_exposure_build.do    war exposure: the paper's alarm measure (A), mine (B) and
*                             the VIINA measures (C: distance to the front, attacks);
*                             runs 03_geo_mappings.do (names, codes, occupation) first
*     04_descriptives.do      descriptive figures and tables (no exposure)
*     04_descriptives_exposure.do  descriptives of the exposure measures themselves:
*                             maps, population, within/between, correlations, sample
*     05_descriptives_rq.do   descriptives by research question (margins, concentration,
*                             relocation, wages, upskilling, substitution, military)
*     06_designs.do           main designs D1-D3 (PPML): one table per design; alarms
*                             (raion), front and attacks (city); coefficient plot; ~25 min
*     07_decomposition.do     extensive vs. intensive margin of the D1-D3 effects; ~2 h
*
* External data, outside the Project folder (see each file's header):
*   Collector/data/exports/<date>/              robota.ua sample (my collector)
*   ukrainian-air-raid-sirens-dataset/          alarms (git clone, Vadimkin)
*   VIINA/Data/                                 territorial control and events (git
*                                               clone, Zhukov)
*
* Needs: Python 3 with pandas, numpy, pyarrow, scipy, launched as "py" (Windows launcher);
*        Stata packages: ssc install encoder
* =============================================================================

clear all
set more off

* --- Paths: the only place to change ------------------------------------------
global project "`c(pwd)'/.."   // run from the repo root (folder Project/); the parent holds Collector/, VIINA/, sirens
global export  "$project/Collector/data/exports/20261117_073901"   // robota.ua export to use
global viina   "$project/VIINA/Data"                               // VIINA clone, Data folder
global do      "$project/Project/do"
global temp    "$project/Project/data/temp"
global logs    "$project/Project/data/temp/logs"   // logs of every step
cap mkdir "$logs"

* --- What to run ----------------------------------------------------------------------
* 1 = run the Python helpers first (needed after a new export or a change to a helper).
* 0 = Stata only: reuse the helpers' files already in data/temp (checked, see below).
global run_python 0

* --- Python helpers -----------------------------------------------------------------
* -shell- does not report Python errors back to Stata. So each helper's main output is
* moved aside first (<file>.old) and checked afterwards: if the new file is missing, the
* helper failed (see its log in data/temp/logs/00_<name>.log) and the old file is put
* back, so a failed or interrupted helper never leaves data/temp without the file.
* An interrupt (Break) during a helper stops Stata before the old file is put back: the
* next call restores it from <file>.old.
* With $run_python = 0 nothing is run: each output is only checked to exist.
capture program drop run_python
program define run_python
    args script arg output
    capture confirm file "`output'"
    if _rc {                                    // left behind by an interrupted run?
        capture copy "`output'.old" "`output'"
        if !_rc display as text "`script'.py: restored `output' from the previous run"
    }
    if "$run_python" == "0" {
        capture confirm file "`output'"
        if _rc {
            display as error "`output' is missing: set run_python to 1 (or run do/`script'.py)"
            exit 601
        }
        display as text "`script'.py skipped (run_python = 0), using the existing file"
        exit
    }
    capture erase "`output'.old"
    capture copy "`output'" "`output'.old"
    capture erase "`output'"
    shell set PYTHONIOENCODING=utf-8&& py "$do/`script'.py" "`arg'" > "$logs/`script'.log" 2>&1
    capture confirm file "`output'"
    if _rc {
        capture copy "`output'.old" "`output'"
        display as error "`script'.py failed: see $logs/`script'.log (previous file kept)"
        exit 601
    }
    capture erase "`output'.old"
    display as text "`script'.py done"
end

run_python 00_description_hash "$export" "$temp/robota_description_hash.csv"
run_python 00_city_raion       "$export" "$temp/robota_city_raion.csv"
run_python 00_viina_control    "$viina"  "$temp/viina_settlement_month.csv"
run_python 00_oblast_borders   "$project/ukrainian-air-raid-sirens-dataset" "$temp/ua_oblast_borders.csv"
run_python 00_text_features    "$export" "$temp/robota_text_features.csv"

* --- Stata ---------------------------------------------------------------------------
do "$do/01_clean.do"
do "$do/02_sample_checks.do"
do "$do/03_exposure_build.do"
do "$do/04_descriptives.do"
do "$do/04_descriptives_exposure.do"
do "$do/05_descriptives_rq.do"
do "$do/06_designs.do"
do "$do/07_decomposition.do"

display as result "Pipeline finished: export $export"
