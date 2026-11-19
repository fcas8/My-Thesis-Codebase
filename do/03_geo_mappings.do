* =============================================================================
* 03_geo_mappings.do  --  oblast and raion tables shared by the exposure files
*
* Every source names places its own way: the alarm data ("Lvivska oblast",
* "Lvivskyi raion"), the UkrStat population file ("Lviv"), robota.ua ("Львівська
* область"), the paper's code (44) and the map (pcode UA46). This file puts all the
* names side by side, once, so 03_exposure_build.do only merges.
* It also says, month by month, how much of each raion (and which robota.ua cities)
* Russia occupies (step 5, from VIINA).
*
* Input : data/crosswalks/ua_raions.csv       the 139 raions of the map   } from
*         data/temp/robota_city_raion.csv     robota.ua city -> raion     } do/00_city_raion.py
*         data/temp/viina_settlements.csv     places, population, raion   } from
*         data/temp/viina_settlement_month.csv  control by place, month   } do/00_viina_control.py
*         data/temp/viina_city_settlement.csv   robota.ua city -> place   }
*         <sirens repo>/datasets/official_data_en.csv   (only to check the names, step 4)
* Output: data/crosswalks/geo_oblasts.dta      one row per oblast name in the sources
*         data/crosswalks/geo_raions.dta       one row per raion
*         data/crosswalks/geo_raion_names.dta  one row per raion name in the alarm data
*         data/crosswalks/geo_city_raion.dta   one row per robota.ua city
*         data/crosswalks/geo_raion_occupation.dta  one row per raion x month
*         data/crosswalks/geo_oblast_occupation.dta one row per oblast x month (map code)
*         data/crosswalks/geo_city_occupation.dta   one row per robota.ua city x month
*         data/temp/logs/03_geo_mappings.log
*
* Codes used everywhere:
*   oblast        the paper's oblast code (Work.ua coding), with the paper's English
*                 labels. Kyiv city = 39, as Kyiv oblast (the paper merges them).
*   oblast_pcode  oblast code of the map (OCHA COD-AB, based on the Ukrainian KATOTTH
*                 codifier): UA46 = Lviv oblast. Kyiv city has its own, UA80.
*   raion_pcode   raion code of the map: UA4606 = Lvivskyi raion. Kyiv city = UA8000.
*
* Called at the start of 03_exposure_build.do. Needs do/00_city_raion.py and
* do/00_viina_control.py run first.
* =============================================================================

clear all
set more off
set linesize 200

* --- Step 0. Paths ----------------------------------------------------------
if "$project" == "" global project "`c(pwd)'/.."   // set by 00_main.do; else run from the repo root
global sirens  "$project/ukrainian-air-raid-sirens-dataset/datasets"
global xwalk   "$project/Project/data/crosswalks"
global temp    "$project/Project/data/temp"

cap log close
cap mkdir "$project/Project/data/temp/logs"
log using "$project/Project/data/temp/logs/03_geo_mappings.log", replace text

* --- Step 1. Oblasts ----------------------------------------------------------
* One row per oblast name found in the sources. Columns:
*   oblast        paper's code (Work.ua coding); Crimea 19, Sevastopol 27
*   oblast_pcode  map code (Kyiv city UA80, separate from Kyiv oblast UA32)
*   name_alarm    name in the alarm data (Kyiv city has its own rows there: "Kyiv City")
*   name_pop      name in the UkrStat population file (kn_0122_ue.xls)
*   oblast_ua     name in robota.ua's city list (data/crosswalks/robota_city.csv),
*                 which also puts Kyiv city in Kyiv oblast
*   _ID           polygon of the oblast in the paper's map (prep_map.do)
clear
input int oblast str4 oblast_pcode str25 name_alarm str16 name_pop str50 oblast_ua byte _ID
33 "UA05" "Vinnytska oblast"        "Vinnytsya"       "Вінницька область"        20
34 "UA12" "Dnipropetrovska oblast"  "Dnipropetrovsk"  "Дніпропетровська область" 24
35 "UA14" "Donetska oblast"         "Donetsk"         "Донецька область"         10
36 "UA18" "Zhytomyrska oblast"      "Zhytomyr"        "Житомирська область"       4
37 "UA23" "Zaporizka oblast"        "Zaporizhzhya"    "Запорізька область"       11
38 "UA26" "Ivano-Frankivska oblast" "Ivano-Frankivsk" "Івано-Франківська область" 13
39 "UA32" "Kyivska oblast"          "Kyiv"            "Київська область"          5
39 "UA80" "Kyiv City"               "City of Kyiv"    "Київська область"          5
40 "UA35" "Kirovohradska oblast"    "Kirovohrad"      "Кіровоградська область"   25
42 "UA44" "Luhanska oblast"         "Luhansk"         "Луганська область"         9
43 "UA07" "Volynska oblast"         "Volyn"           "Волинська область"         2
44 "UA46" "Lvivska oblast"          "Lviv"            "Львівська область"        12
45 "UA48" "Mykolaivska oblast"      "Mykolayiv"       "Миколаївська область"     18
46 "UA51" "Odeska oblast"           "Odesa"           "Одеська область"          17
47 "UA53" "Poltavska oblast"        "Poltava"         "Полтавська область"       23
48 "UA56" "Rivnenska oblast"        "Rivne"           "Рівненська область"        3
49 "UA59" "Sumska oblast"           "Sumy"            "Сумська область"           7
50 "UA61" "Ternopilska oblast"      "Ternopyl"        "Тернопільська область"    15
51 "UA21" "Zakarpatska oblast"      "Zakarpattya"     "Закарпатська область"     14
52 "UA63" "Kharkivska oblast"       "Kharkiv"         "Харківська область"        8
53 "UA65" "Khersonska oblast"       "Kherson"         "Херсонська область"        1
54 "UA68" "Khmelnytska oblast"      "Khmelnytskiy"    "Хмельницька область"      21
55 "UA71" "Cherkaska oblast"        "Cherkasy"        "Черкаська область"        22
56 "UA74" "Chernihivska oblast"     "Chernihiv"       "Чернігівська область"      6
57 "UA73" "Chernivetska oblast"     "Chernivtsi"      "Чернівецька область"      16
19 "UA01" ""                        ""                "Крим"                     19
27 "UA85" ""                        ""                "Севастополь"              27
end
* NB: robota.ua gives no oblast for Sevastopol (oblast is "" in 01_clean.do), so
* "Севастополь" matches nothing there.

* Crimea, Sevastopol and Luhansk oblast have no alarm data: Luhansk and Crimea have a
* "permanent" alarm since 2022 that the sirens repo does not list (datasets/README.md).
gen byte no_alarm_data = inlist(oblast, 19, 27, 42)

* English labels for the paper's codes (as in the paper)
label define oblast_lab 19 "Crimea" 27 "Sevastopol" 33 "Vinnytsia" 34 "Dnipro" ///
    35 "Donetsk" 36 "Zhytomyr" 37 "Zaporijia" 38 "Ivano-Frankivsk" 39 "Kyiv" ///
    40 "Kirovohrad" 42 "Luhansk" 43 "Lutsk" 44 "Lviv" 45 "Mykolayiv" 46 "Odessa" ///
    47 "Poltava" 48 "Rivne" 49 "Sumy" 50 "Ternopil" 51 "Uzhhorod" 52 "Kharkiv" ///
    53 "Kherson" 54 "Khmelnytskyi" 55 "Cherkasy" 56 "Chernihiv" 57 "Chernivtsi"
label values oblast oblast_lab

label var oblast        "Oblast (code of the paper; Kyiv city in Kyiv oblast)"
label var oblast_pcode  "Oblast code of the map (OCHA COD-AB); Kyiv city UA80"
label var name_alarm    "Oblast name in the alarm data"
label var name_pop      "Oblast name in the UkrStat population file"
label var oblast_ua     "Oblast name as in robota.ua (merge key with 01_clean.do)"
label var _ID           "Map polygon ID (paper)"
label var no_alarm_data "No alarm data (Crimea, Sevastopol, Luhansk oblast)"
isid oblast_pcode
sort oblast oblast_pcode
save "$xwalk/geo_oblasts.dta", replace

* --- Step 2. Raions -----------------------------------------------------------------
* ua_raions.csv: the 139 raions of the map (OCHA COD-AB admin 2, valid 1 Sep 2025, so
* with the names of the 2024 renaming), incl. Kyiv city (UA8000) and Sevastopol (UA8500).
import delimited using "$xwalk/ua_raions.csv", encoding("utf-8") varnames(1) ///
    stringcols(_all) clear
destring area_km2, replace
rename (oblast_en oblast_ua raion_en raion_ua) (oblast_en_map oblast_ua_map raion_en raion_ua)
merge m:1 oblast_pcode using "$xwalk/geo_oblasts.dta", ///
    keepusing(oblast name_alarm no_alarm_data) assert(match) nogenerate
rename name_alarm oblast_alarm
gen raion_alarm = raion_en + " raion"     // as in the alarm data: "Lvivskyi raion"

label var raion_pcode   "Raion code of the map (OCHA COD-AB); Kyiv city UA8000"
label var oblast_alarm  "Oblast name in the alarm data"
label var raion_alarm   "Raion name in the alarm data"
label var raion_en      "Raion (English, map)"
label var raion_ua      "Raion (Ukrainian, map)"
label var oblast_en_map "Oblast (English, map)"
label var oblast_ua_map "Oblast (Ukrainian, map)"
label var area_km2      "Area, km2"
order raion_pcode oblast oblast_pcode raion_en raion_ua oblast_en_map oblast_ua_map ///
      oblast_alarm raion_alarm no_alarm_data area_km2
isid raion_pcode
sort raion_pcode
save "$xwalk/geo_raions.dta", replace

* Raion names in the alarm data: today's names, plus OLD names of raions renamed in
* 2024 (decommunisation law) that still appear in some rows of the alarm data.
* Krasnohradskyi -> Berestynskyi, Chervonohradskyi -> Sheptytskyi,
* Volodymyr-Volynskyi -> Volodymyrskyi
preserve
    clear
    input str6 raion_pcode str30 raion_alarm
    "UA6306" "Krasnohradskyi raion"
    "UA4612" "Chervonohradskyi raion"
    "UA0702" "Volodymyr-Volynskyi raion"
    end
    merge 1:1 raion_pcode using "$xwalk/geo_raions.dta", ///
        keepusing(oblast_pcode oblast_alarm) keep(match) nogenerate
    assert _N == 3
    tempfile old_names
    save `old_names'
restore
keep raion_pcode oblast_pcode oblast_alarm raion_alarm
drop if oblast_alarm == ""            // Crimea, Sevastopol: not in the alarm data
append using `old_names'
label var raion_alarm "Raion name in the alarm data (incl. names before the 2024 renaming)"
isid oblast_alarm raion_alarm
sort raion_pcode raion_alarm
save "$xwalk/geo_raion_names.dta", replace

* --- Step 3. robota.ua city -> raion (from do/00_city_raion.py) ----------------------
* Cities abroad and cities without coordinates have no raion (2.7% of vacancies).
import delimited using "$temp/robota_city_raion.csv", varnames(1) clear ///
    stringcols(6)
confirm string variable raion_pcode
label var city_id     "robota.ua city id"
label var n_vac       "Vacancies of the city in the export"
label var n_coord     "... with coordinates in the city's oblast"
label var lat         "City point: median latitude"
label var lon         "City point: median longitude"
label var raion_pcode "Raion of the city point"
label var share_same  "Share of the city's pins in that raion"
isid city_id
save "$xwalk/geo_city_raion.dta", replace
tab raion_pcode if raion_pcode == "", missing      // cities without a raion

* --- Step 4. Check: every place name in the alarm data is in the tables --------------
import delimited using "$sirens/official_data_en.csv", varnames(1) delimiters(",") ///
    encoding("utf-8") stringcols(_all) clear
keep oblast raion level
duplicates drop
drop if oblast == "Lubenskyi raion"      // data error in old downloads

* oblast names
preserve
    keep oblast
    duplicates drop
    rename oblast name_alarm
    merge 1:m name_alarm using "$xwalk/geo_oblasts.dta", keep(master match)   // m: Crimea and Sevastopol share the name ""
    list name_alarm if _merge == 1       // should list nothing
    assert _merge == 3
restore

* raion names (raion- and hromada-level alarms)
keep if inlist(level, "raion", "hromada")
keep oblast raion
duplicates drop
rename (oblast raion) (oblast_alarm raion_alarm)
merge 1:1 oblast_alarm raion_alarm using "$xwalk/geo_raion_names.dta", keep(master match)
list oblast_alarm raion_alarm if _merge == 1    // should list nothing
assert _merge == 3

* --- Step 5. Occupation, by raion and month (VIINA) ------------------------------------
* Source: VIINA 2.0 territorial control (Zhukov; github zhukovyuri/VIINA, ODbL license;
* cite Zhukov 2023, Journal of Comparative Economics 51(4)). Clone of 6 Nov 2026, commit
* a1ad3633, data to 27 Oct 2026. For each populated place (GeoNames, 33,141) and day from
* 23 Feb 2022: status UA / RU / CONTESTED from DeepStateMap, Wikipedia maps, Wikipedia
* "boosted" by VIINA's news reports, and ISW, plus VIINA's majority vote of the first three.
* do/00_viina_control.py turns the daily status into days RU / CONTESTED per place and
* month, and finds the raion of each place and the place of each robota.ua city.
* RULE: a place is held by Russia on a day only if BOTH VIINA's vote and DeepStateMap say
* so (VIINA's vote alone before DeepStateMap starts, Mar-Apr 2022). Each source alone
* errs, in opposite directions: VIINA's vote counts Wikipedia twice and from July 2026
* puts Nikopol and Marhanets (~150,000 people, held by Ukraine) under Russia; VIINA's
* DeepStateMap status puts Kherson city (~290,000, held by Ukraine since Nov 2022) under
* Russia in every month. Details in do/00_viina_control.py. The single-source versions
* are kept as occ_share_viina and occ_share_dsm, for checks.
*
* Why VIINA: the official government list (Ministry of Development order 987, 2026) could
* not be downloaded (Nov 2026); DeepStateMap alone (github cyterat/deepstate-map-data)
* starts only in July 2024.

* 5a. Places and their weights.
*     A raion is "x% occupied" if x% of its pre-war people live in places held by Russia.
*     Population is GeoNames' (often an old census figure). Most villages have population 0
*     (= unknown), so in practice the weight is on towns. Where a raion has fewer than 3
*     places with a population (Kyiv city, Sevastopol, two more), all its places weigh the same.
import delimited using "$temp/viina_settlements.csv", varnames(1) encoding("utf-8") ///
    stringcols(6) clear
drop if raion_pcode == ""              // 17 places outside the map (border, sea)
bysort raion_pcode: egen n_with_pop = total(population > 0)
gen double weight = cond(n_with_pop >= 3, population, 1)
label var weight "Weight of the place in its raion (population, or 1; see step 5a)"
* same rule for oblasts (used in 5c-bis): population, or equal weights if fewer than 3
* places of the oblast have a population (Kyiv city UA80, Sevastopol UA85)
gen oblast_pcode = substr(raion_pcode, 1, 4)
bysort oblast_pcode: egen n_with_pop_oblast = total(population > 0)
gen double weight_oblast = cond(n_with_pop_oblast >= 3, population, 1)
label var weight_oblast "Weight of the place in its oblast (population, or 1; see step 5a)"
keep geonameid raion_pcode oblast_pcode population weight weight_oblast
tempfile places
save `places'

* 5b. Share of the month each place was held by Russia / contested
import delimited using "$temp/viina_settlement_month.csv", varnames(1) clear
rename month month_str
gen month = monthly(month_str, "YM")
format month %tmMon_CCYY
drop month_str
gen double ru_days_share    = days_ru / days
gen double con_days_share   = days_contested / days
gen double viina_days_share = days_ru_viina / days
gen double dsm_days_share   = days_ru_dsm / days
gen double nodsm_days_share = days_dsm_missing / days
merge m:1 geonameid using `places', keep(match) nogenerate

* 5c-bis. Oblast x month, same rule as for raions (added 14 Nov 2026 for the oblast
*     VIINA file of 03_exposure_build.do, Part C). Oblast = map code (Kyiv city UA80 apart).
preserve
    collapse (mean) occ_share = ru_days_share con_share = con_days_share [aw = weight_oblast], ///
        by(oblast_pcode month)
    gen byte occupied_oblast = occ_share > 0.5
    label var month           "Month"
    label var occ_share       "Share of the oblast's population in places held by Russia (days-weighted)"
    label var con_share       "Share of the oblast's population in contested places"
    label var occupied_oblast "Oblast occupied: occ_share > 0.5"
    isid oblast_pcode month
    sort oblast_pcode month
    compress
    save "$xwalk/geo_oblast_occupation.dta", replace
restore

* 5c. Raion x month: population-weighted (main) and plain share of places (check)
preserve
    collapse (mean) occ_share_n = ru_days_share con_share_n = con_days_share ///
        (count) n_places = geonameid, by(raion_pcode month)
    tempfile by_count
    save `by_count'
restore
collapse (mean) occ_share = ru_days_share con_share = con_days_share ///
    occ_share_viina = viina_days_share occ_share_dsm = dsm_days_share ///
    no_dsm_share = nodsm_days_share [aw = weight], ///
    by(raion_pcode month)
merge 1:1 raion_pcode month using `by_count', assert(match) nogenerate

* 5d. Flag: a raion-month is "occupied" if more than half its people were under Russia
gen byte occupied_raion = occ_share > 0.5
label var month          "Month"
label var occ_share      "Share of the raion's population in places held by Russia (days-weighted)"
label var con_share      "Share of the raion's population in contested places"
label var occ_share_viina "occ_share by VIINA's majority vote alone (check)"
label var occ_share_dsm   "occ_share by DeepStateMap alone (check)"
label var no_dsm_share   "Share of the raion's population without a DeepStateMap status"
label var occ_share_n    "Share of the raion's places held by Russia (unweighted, check)"
label var con_share_n    "Share of the raion's places contested (unweighted, check)"
label var n_places       "Places (GeoNames) in the raion"
label var occupied_raion "Raion occupied: occ_share > 0.5"
isid raion_pcode month
sort raion_pcode month
compress
save "$xwalk/geo_raion_occupation.dta", replace

tab month occupied_raion if inlist(month, tm(2022m3), tm(2022m6), tm(2022m10), ///
    tm(2023m1), tm(2024m1), tm(2025m1), tm(2026m1), tm(2026m10))

* 5e. robota.ua city x month: the place whose polygon contains the city point.
*     A city is "occupied" in a month if its place was held by Russia most of the month.
import delimited using "$temp/viina_city_settlement.csv", varnames(1) clear
tempfile city_place
save `city_place'
import delimited using "$temp/viina_settlement_month.csv", varnames(1) clear
rename month month_str
gen month = monthly(month_str, "YM")
format month %tmMon_CCYY
drop month_str
joinby geonameid using `city_place'
gen double city_ru_share = days_ru / days
gen byte occupied_city = city_ru_share > 0.5
keep city_id geonameid month city_ru_share occupied_city
label var geonameid     "GeoNames place containing the city point (VIINA)"
label var city_ru_share "Share of the month the city's place was held by Russia"
label var occupied_city "City occupied in the month (held by Russia > half the month)"
isid city_id month
sort city_id month
compress
save "$xwalk/geo_city_occupation.dta", replace

log close
