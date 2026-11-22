/*==============================================================================
  analysis.do  --  the single Stata do-file of this project
  Good Health at Low Cost Is Not Financial Protection: Evidence from the Revised SDG 3.8.2

  HOW TO RUN (any PC; Stata 17 or newer):
      cd "<path to the repository root>"
      do stata/analysis.do
  Type the two commands by hand (do not paste multi-line text into Stata).
  Needs the SSC packages ftools, require, reghdfe, estout (installed below if missing).
  All data are frozen in data/ and data/raw/; nothing is downloaded unless you
  set  global redownload 1  before Section 4 (not needed to reproduce).

  The analysis was developed in stages; each stage is one numbered SECTION below and
  keeps its own header, which records what it adds. Sections run in this order and
  each one reads the files written by the earlier ones:
      Section 1  V1 analysis            -> results/results_estimates.*, results_numeric.*
      Section 2  v3 numbers             -> results/results_v3.*, pairs_same_survey.csv
      Section 3  v4 numbers             -> results/results_v4.*, panel_v4.dta
      Section 4  Extension 1 (DHS)      -> results/results_e1.*
      Section 5  v6 additions           -> results/results_v6.*
  (Older headers below refer to the former file names 02_analysis.do, 05_revision_
   analysis.do, 07_v4_analysis.do, 10_extension1_analysis.do, 12_v6_analysis.do;
   these are now Sections 1-5 of this file.)
==============================================================================*/
==============================================================================*/
version 17
clear all
set more off

global root "`c(pwd)'"
foreach f in data/panel.dta data/fp_surveys.dta data/countries_fy2027.dta {
    capture confirm file "$root/`f'"
    if _rc {
        di as error "Cannot find `f' under: $root"
        di as error "cd to the repository root first, then: do stata/analysis.do"
        exit 601
    }
}
if c(stata_version) < 17 {
    di as error "Stata 17 or newer is required (this is Stata `c(stata_version)')."
    exit 9
}
capture mkdir "$root/results"

* --- dependencies -------------------------------------------------------------
foreach p in ftools require reghdfe estout {
    capture which `p'
    if _rc {
        di as txt "Installing `p' from SSC ..."
        ssc install `p', replace
    }
}
capture reghdfe, compile

* --- record the environment ---------------------------------------------------
file open RI using "$root/results/run_info.txt", write replace
file write RI "Run: `c(current_date)' `c(current_time)'" _n
local ed "`c(edition_real)'"
if "`ed'" == "" local ed = cond(c(MP), "MP", cond(c(SE), "SE", "BE"))
file write RI "Stata: `c(stata_version)' `ed' (c(edition_real); `c(processors)' processors in use) `c(os)' `c(machine_type)'" _n
file write RI "Stata born date: `c(born_date)'" _n
file write RI "Folder: $root" _n
file close RI
* package versions -> results/run_info_packages.log
capture log close _pk
log using "$root/results/run_info_packages.log", text replace name(_pk)
foreach p in ftools reghdfe estout require {
    capture noisily which `p'
}
log close _pk

*==============================================================================
*  SECTION 1: V1 analysis
*==============================================================================
/*==============================================================================
  02_analysis.do
  Replication and audit of: "Good Health at Low Cost Is Not Financial
  Protection: Evidence from 131 Low- and Middle-Income Countries"

  Inputs  (made by 01_download_data.py):  data/panel.dta, data/fp_surveys.dta
  Outputs (all in results/):
     analysis_log.smcl / .log / .pdf
     results_estimates.dta / .csv / .xlsx   every coefficient (b, se, p, n, r2)
     results_numeric.dta  / .csv            every other number (counts, medians,
                                            ranks, correlations, Bangladesh)
     crossA.dta/.csv, crossB.dta/.csv, bgd_trends.csv, south_asia.csv
     tables_A.rtf, tables_B.rtf, tables_C.rtf  (esttab tables)

  Sections
     0  Setup              1  Sample counts
     2  Analysis A (financial protection, cross-section)
     3  Analysis B (outcomes relative to spending, 2019 cross-section)
     4  Analysis C (within-country panel, 2000-2019)
     5  Bangladesh and South Asia
     6  Export
  Stata 17. Run from the project folder:
     cd "<project folder>"
     do stata/02_analysis.do
==============================================================================*/

version 17
clear all
set more off
set varabbrev off

*------------------------------------------------------------------------------
* 0. SETUP -- portable: every path is relative to the project folder
*------------------------------------------------------------------------------
global root "`c(pwd)'"
global in   "$root/data"
global out  "$root/results"
foreach f in panel.dta fp_surveys.dta {
    capture confirm file "$in/`f'"
    if _rc {
        di as error "Cannot find data/`f' under: $root"
        di as error "Set the working directory to the project folder first (cd ...)."
        exit 601
    }
}
capture mkdir "$out"
capture log close
log using "$out/analysis_log.smcl", replace
di as result "Project folder: $root"

* user-written packages (installed once from SSC)
foreach p in ftools require reghdfe estout {
    cap which `p'
    if _rc ssc install `p', replace
}
cap reghdfe, compile          // harmless if already compiled

* --- result files -------------------------------------------------------------
tempname R N
postfile `R' str4 section str40 model str24 term ///
    double(b se p n r2) using "$out/results_estimates.dta", replace
postfile `N' str4 section str60 item double value ///
    using "$out/results_numeric.dta", replace

* post one coefficient from the last model
cap program drop post_b
program define post_b
    args h section model term
    local b  = _b[`term']
    local se = _se[`term']
    if !missing(e(df_r)) local p = 2*ttail(e(df_r), abs(`b'/`se'))
    else                 local p = 2*normal(-abs(`b'/`se'))
    post `h' ("`section'") ("`model'") ("`term'") (`b') (`se') (`p') (e(N)) (e(r2))
end

* post one number
cap program drop post_n
program define post_n
    args h section item value
    post `h' ("`section'") ("`item'") (`value')
end

* attach, for each country, the value of `v' from the panel year nearest to
* the survey year (svy_year), within +/- 2 years; exact year wins, then earlier
cap program drop nearest
program define nearest
    args v
    preserve
        use iso3 year `v' using "$in/panel.dta", clear
        drop if missing(`v')
        rename year y_`v'
        tempfile t
        save `t'
    restore
    joinby iso3 using `t', unmatched(master)
    gen double d_`v' = abs(y_`v' - svy_year)
    bysort iso3 (d_`v' y_`v'): keep if _n == 1
    replace `v' = . if missing(d_`v') | d_`v' > 2
    drop _merge d_`v' y_`v'
end

*------------------------------------------------------------------------------
* 1. SAMPLE COUNTS
*------------------------------------------------------------------------------
use "$in/panel.dta", clear
quietly levelsof iso3, local(all)
post_n `N' "S" "LMICs (FY2027)" `: word count `all''
foreach g in LIC LMC UMC {
    quietly levelsof iso3 if income == "`g'", local(x)
    post_n `N' "S" "LMICs `g'" `: word count `x''
}

*------------------------------------------------------------------------------
* 2. ANALYSIS A -- FINANCIAL PROTECTION (one row per country)
*    Outcome: % population with OOP > 10% (25%) of budget, latest survey >=2005
*    Exposures/controls: measured in the survey year (+/- 2 years)
*------------------------------------------------------------------------------
use "$in/fp_surveys.dta", clear
keep if !missing(cat10) & year >= 2005
bysort iso3 (year): keep if _n == _N
rename year svy_year
keep iso3 country region income svy_year cat10 cat25
foreach v in oop gov ext gdp_ppp uhc {
    nearest `v'
}
* OOP in 2019 (alternative timing; the abstract does not say which year it used)
preserve
    use iso3 year oop if year == 2019 using "$in/panel.dta", clear
    rename oop oop19
    drop year
    tempfile o19
    save `o19'
restore
merge 1:1 iso3 using `o19', keep(master match) nogen

gen lngdp = ln(gdp_ppp)
encode region, gen(reg)
encode income, gen(inc)
label var cat10 "Catastrophic OOP >10% of budget (% pop)"
label var cat25 "Catastrophic OOP >25% of budget (% pop)"
label var oop   "OOP % of current health expenditure (survey year)"
label var gov   "Govt % of CHE (survey year)"
label var lngdp "ln GDP per capita, PPP 2021$"
label var uhc   "UHC service coverage index"

* descriptives
count
post_n `N' "A" "Countries with survey since 2005" r(N)
summ svy_year, detail
post_n `N' "A" "Survey year median" r(p50)
post_n `N' "A" "Survey year min" r(min)
post_n `N' "A" "Survey year max" r(max)
summ cat10, detail
post_n `N' "A" "cat10 median" r(p50)
post_n `N' "A" "cat10 p25" r(p25)
post_n `N' "A" "cat10 p75" r(p75)
local med10 = r(p50)
summ cat25, detail
post_n `N' "A" "cat25 median" r(p50)
count if !missing(cat10, oop, lngdp, uhc)
post_n `N' "A" "Countries with all controls" r(N)

* correlations
pwcorr cat10 oop
post_n `N' "A" "Pearson r cat10-oop" r(rho)
spearman cat10 oop
post_n `N' "A" "Spearman rho cat10-oop" r(rho)
pwcorr oop gov
post_n `N' "A" "Pearson r oop-gov" r(rho)

* Bangladesh rank (1 = highest catastrophic spending)
egen rank10 = rank(cat10), field
summ rank10 if iso3 == "BGD"
post_n `N' "A" "BGD rank cat10 (1=worst)" r(mean)
summ cat10 if iso3 == "BGD"
post_n `N' "A" "BGD cat10 / median" r(mean)/`med10'

* models (robust = HC1, as in the abstract; HC3 shown as robustness)
eststo clear
eststo A1: regress cat10 oop, vce(robust)
post_b `R' "A" "A1 cat10 ~ oop" oop
eststo A2: regress cat10 oop lngdp uhc i.reg, vce(robust)
post_b `R' "A" "A2 cat10 ~ oop + controls" oop
post_b `R' "A" "A2 cat10 ~ oop + controls" lngdp
post_b `R' "A" "A2 cat10 ~ oop + controls" uhc
estat vif
eststo A3: regress cat10 oop lngdp uhc i.reg c.svy_year, vce(robust)
post_b `R' "A" "A3 A2 + survey-year trend" oop
eststo A4: regress cat25 oop, vce(robust)
post_b `R' "A" "A4 cat25 ~ oop" oop
eststo A5: regress cat25 oop lngdp uhc i.reg, vce(robust)
post_b `R' "A" "A5 cat25 ~ oop + controls" oop
eststo A6: regress cat10 gov, vce(robust)
post_b `R' "A" "A6 cat10 ~ gov" gov
eststo A7: regress cat10 gov lngdp uhc i.reg, vce(robust)
post_b `R' "A" "A7 cat10 ~ gov + controls" gov
eststo A8: regress cat10 uhc lngdp, vce(robust)
post_b `R' "A" "A8 cat10 ~ uhc + lngdp" uhc

* robustness
regress cat10 oop lngdp uhc i.reg, vce(hc3)
post_b `R' "A" "R1 A2 with HC3 SEs" oop
regress cat10 oop19 lngdp uhc i.reg, vce(robust)
post_b `R' "A" "R2 A2 with OOP in 2019" oop19
regress cat10 oop lngdp uhc i.inc, vce(robust)
post_b `R' "A" "R3 income-group instead of region" oop
regress cat10 oop lngdp uhc i.reg if svy_year >= 2012, vce(robust)
post_b `R' "A" "R4 surveys 2012+" oop
quietly regress cat10 oop lngdp uhc i.reg
predict double cook if e(sample), cooksd
regress cat10 oop lngdp uhc i.reg if cook <= 4/e(N), vce(robust)
post_b `R' "A" "R5 drop Cook's D > 4/n" oop
gen cat10p = cat10/100
glm cat10p oop lngdp uhc i.reg, family(binomial) link(logit) vce(robust)
margins, dydx(oop) post
post_b `R' "A" "R6 fractional logit AME" oop
gen lncat10 = ln(cat10 + 0.5)
regress lncat10 oop lngdp uhc i.reg, vce(robust)
post_b `R' "A" "R7 ln(cat10+0.5)" oop

esttab A1 A2 A3 A4 A5 A6 A7 A8 using "$out/tables_A.rtf", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) r2 ///
    drop(*.reg, relax) label title("Analysis A: catastrophic health spending")

save "$out/crossA.dta", replace
export delimited using "$out/crossA.csv", replace

* --- A (2025 SDG definition): financial hardship -----------------------------
use "$in/fp_surveys.dta", clear
keep if !missing(fh_total) & year >= 2005
bysort iso3 (year): keep if _n == _N
rename year svy_year
keep iso3 region svy_year fh_total fh_impov fh_large
foreach v in oop gdp_ppp uhc {
    nearest `v'
}
gen lngdp = ln(gdp_ppp)
encode region, gen(reg)
count
post_n `N' "A" "FH2025: countries with survey since 2005" r(N)
summ fh_total, detail
post_n `N' "A" "FH2025: median" r(p50)
summ svy_year, detail
post_n `N' "A" "FH2025: survey year median" r(p50)
egen rankfh = rank(fh_total), field
summ rankfh if iso3 == "BGD"
post_n `N' "A" "FH2025: BGD rank (1=worst)" r(mean)
regress fh_total oop, vce(robust)
post_b `R' "A" "A9 fh2025 ~ oop" oop
regress fh_total oop lngdp uhc i.reg, vce(robust)
post_b `R' "A" "A10 fh2025 ~ oop + controls" oop
save "$out/crossA_fh2025.dta", replace

*------------------------------------------------------------------------------
* 3. ANALYSIS B -- OUTCOMES RELATIVE TO SPENDING, 2019
*------------------------------------------------------------------------------
use "$in/panel.dta" if year == 2019, clear
drop if missing(che_ppp)
gen lnche = ln(che_ppp)
gen lngdp = ln(gdp_ppp)
gen lnu5  = ln(u5mr)
encode region, gen(reg)
label var lnche "ln CHE per capita, PPP"
count
post_n `N' "B" "Countries with spending 2019" r(N)

eststo clear
eststo B1: regress le_who lnche, vce(robust)
post_b `R' "B" "B1 LE ~ lnche" lnche
post_n `N' "B" "B1 R2" e(r2)
post_n `N' "B" "B1 years per doubling" _b[lnche]*ln(2)
post_n `N' "B" "B1 n" e(N)
predict double res_le if e(sample), resid
eststo B2: regress lnu5 lnche, vce(robust)
post_b `R' "B" "B2 lnU5MR ~ lnche" lnche
post_n `N' "B" "B2 R2" e(r2)
predict double res_u5 if e(sample), resid
eststo B3: regress le_who lnche lngdp, vce(robust)
post_b `R' "B" "B3 LE ~ lnche + lngdp" lnche
post_b `R' "B" "B3 LE ~ lnche + lngdp" lngdp
predict double res_le_gdp if e(sample), resid
eststo B4: regress le_wb lnche, vce(robust)
post_b `R' "B" "B4 LE (UN WPP) ~ lnche" lnche
predict double res_le_wb if e(sample), resid
gen lnche2 = lnche^2
eststo B5: regress le_who lnche lnche2, vce(robust)
post_b `R' "B" "B5 quadratic" lnche2

* does the OOP share explain over/under-performance?
regress res_le oop, vce(robust)
post_b `R' "B" "B6 residual ~ oop" oop

* ranks (1 = largest positive residual / highest OOP)
* (egen rank ignores missing values; field = 1 for the largest, track = 1 for the smallest)
foreach r in res_le res_le_gdp res_le_wb {
    egen rk_`r' = rank(`r'), field
    summ rk_`r' if iso3 == "BGD"
    post_n `N' "B" "BGD rank `r'" r(mean)
    summ `r' if iso3 == "BGD"
    post_n `N' "B" "BGD `r'" r(mean)
}
egen rk_res_u5 = rank(res_u5), track
summ rk_res_u5 if iso3 == "BGD"
post_n `N' "B" "BGD rank lnU5MR residual (1=best)" r(mean)
summ res_le if iso3 == "LKA"
post_n `N' "B" "LKA res_le" r(mean)

* OOP rank and median among the B1 sample
summ oop if !missing(res_le), detail
post_n `N' "B" "OOP median (B1 sample)" r(p50)
egen rk_oop = rank(oop) if !missing(res_le), field
summ rk_oop if iso3 == "BGD"
post_n `N' "B" "BGD OOP rank (1=highest)" r(mean)

* link with catastrophic spending (Analysis A sample)
merge 1:1 iso3 using "$out/crossA.dta", keepusing(cat10) keep(master match) nogen
spearman res_le cat10
post_n `N' "B" "Spearman res_le vs cat10" r(rho)
post_n `N' "B" "Spearman n" r(N)
count if res_le > 3 & !missing(res_le) & cat10 < 8
post_n `N' "B" "Over-performers (>3y) with cat10 < 8" r(N)
count if res_le > 3 & !missing(res_le) & cat10 >= 8 & !missing(cat10)
post_n `N' "B" "Over-performers (>3y) with cat10 >= 8" r(N)

esttab B1 B2 B3 B4 B5 using "$out/tables_B.rtf", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) r2 label ///
    title("Analysis B: outcomes and health spending, 2019")

save "$out/crossB.dta", replace
export delimited using "$out/crossB.csv", replace

*------------------------------------------------------------------------------
* 4. ANALYSIS C -- WITHIN-COUNTRY PANEL 2000-2019 (two-way FE, clustered SE)
*------------------------------------------------------------------------------
use "$in/panel.dta" if inrange(year, 2000, 2019), clear
encode iso3, gen(cid)
xtset cid year
gen lnu5      = ln(u5mr)
gen lnche     = ln(che_ppp)                    // current PPP (as in abstract)
gen lnche_k   = ln(che_gdp/100 * gdp_ppp)      // constant 2021 PPP
gen lngdp     = ln(gdp_ppp)
label var lnche   "ln CHE pc (current PPP)"
label var lnche_k "ln CHE pc (constant PPP)"

eststo clear
eststo C1: reghdfe lnu5 lnche, absorb(cid year) vce(cluster cid)
post_b `R' "C" "C1 lnU5 ~ lnche (TWFE)" lnche
post_n `N' "C" "C1 countries" e(N_clust)
eststo C2: reghdfe lnu5 lnche lngdp, absorb(cid year) vce(cluster cid)
post_b `R' "C" "C2 C1 + lngdp" lnche
post_b `R' "C" "C2 C1 + lngdp" lngdp
post_n `N' "C" "C2 countries" e(N_clust)
eststo C3: reghdfe uhc oop, absorb(cid year) vce(cluster cid)
post_b `R' "C" "C3 UHC ~ oop (TWFE)" oop
post_n `N' "C" "C3 countries" e(N_clust)
eststo C4: reghdfe uhc oop lngdp lnche, absorb(cid year) vce(cluster cid)
post_b `R' "C" "C4 C3 + lngdp + lnche" oop
eststo C5: reghdfe uhc oop if inlist(year,2000,2005,2010,2015,2017,2019), ///
    absorb(cid year) vce(cluster cid)
post_b `R' "C" "C5 C3 reference years only" oop
eststo C6: reghdfe lnu5 L.lnche_k lngdp L.oop, absorb(cid year) vce(cluster cid)
post_b `R' "C" "C6 recommended: lags, const PPP" L.lnche_k
post_b `R' "C" "C6 recommended: lags, const PPP" L.oop
eststo C7: reghdfe lnu5 L.lnche_k lngdp L.oop, absorb(cid year cid#c.year) vce(cluster cid)
post_b `R' "C" "C7 C6 + country trends" L.lnche_k
eststo C8: reghdfe lnu5 L3.lnche_k lngdp L3.oop, absorb(cid year) vce(cluster cid)
post_b `R' "C" "C8 3-year lags" L3.lnche_k
eststo C9: reghdfe le_who lnche lngdp, absorb(cid year) vce(cluster cid)
post_b `R' "C" "C9 LE ~ lnche + lngdp" lnche
* first differences
reg D.lnu5 D.lnche_k D.lngdp i.year, vce(cluster cid)
post_b `R' "C" "C10 first differences" D.lnche_k

* balanced-panel count
bysort cid: egen nobs = total(!missing(lnu5, lnche))
quietly levelsof cid if nobs == 20, local(bal)
post_n `N' "C" "Countries fully observed 2000-2019" `: word count `bal''

esttab C1 C2 C3 C4 C5 C6 C7 C8 C9 using "$out/tables_C.rtf", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) label ///
    title("Analysis C: within-country panel, 2000-2019")

*------------------------------------------------------------------------------
* 5. BANGLADESH AND SOUTH ASIA
*------------------------------------------------------------------------------
use "$in/panel.dta" if iso3 == "BGD", clear
export delimited iso3 year oop gov ext che_ppp gdp_ppp le_who le_wb u5mr uhc ///
    using "$out/bgd_trends.csv", replace

use "$in/fp_surveys.dta" if inlist(iso3,"BGD","IND","NPL","PAK","BTN","LKA"), clear
export delimited using "$out/south_asia_surveys.csv", replace

use "$out/crossB.dta" if inlist(iso3,"BGD","IND","NPL","PAK","BTN","LKA"), clear
keep iso3 country le_who u5mr che_ppp oop uhc res_le res_le_gdp res_u5
export delimited using "$out/south_asia.csv", replace
foreach c in BGD IND NPL PAK BTN LKA {
    foreach v in le_who u5mr che_ppp oop uhc res_le res_le_gdp {
        summ `v' if iso3 == "`c'", meanonly
        post_n `N' "BD" "`c' `v' 2019" r(mean)
    }
}

*------------------------------------------------------------------------------
* 6. EXPORT
*------------------------------------------------------------------------------
postclose `R'
postclose `N'
use "$out/results_estimates.dta", clear
gen lo95 = b - 1.96*se
gen hi95 = b + 1.96*se
export delimited using "$out/results_estimates.csv", replace
export excel using "$out/results_estimates.xlsx", firstrow(variables) replace
list, sep(0) noobs abbrev(24)
use "$out/results_numeric.dta", clear
export delimited using "$out/results_numeric.csv", replace
list, sep(0) noobs abbrev(40)

log close
translate "$out/analysis_log.smcl" "$out/analysis_log.log", replace
translate "$out/analysis_log.smcl" "$out/analysis_log.pdf", replace
display as result "DONE"


*==============================================================================
*  SECTION 2: v3 analysis (same-survey comparison, thresholds)
*==============================================================================
/*==============================================================================
  05_revision_analysis.do
  Revision analyses for abstract version 3:
  "Good Health at Low Cost Is Not Financial Protection: How the 2025 Revision
   of SDG 3.8.2 Changes Which LMICs, and Which Households, Look Unprotected"

  Inputs (made by 01_download_data.py, already in data/):
     data/panel.dta, data/fp_surveys.dta, data/countries_fy2027.dta,
     data/raw/gho_FINANCIALHARDSHIP_PROPORTIONOFPOP_20261112.csv
  Outputs (results/):
     results_v3.csv            every number used in the abstract (key, value)
     pairs_same_survey.csv     countries with both indicators from one survey
     revision_log.smcl/.log/.pdf

  Sections
     0 Setup   1 Levels and Bangladesh   2 Design A (original indicator)
     3 Same-survey comparison of the two indicators (yardstick reversal)
     4 Who bears hardship (WHO group breakdowns)
     5 Within-country survey rounds   6 Threshold tests
     7 Design B (health per dollar, 2019)   8 Design C (annual panel)
     9 Export
  Stata 17. Run from the project folder:   cd "<project folder>"
                                           do stata/05_revision_analysis.do
  Run time: about 1-2 minutes.
==============================================================================*/

version 17
clear all
set more off
set varabbrev off

*------------------------------------------------------------------------------
* 0. SETUP -- portable: every path is relative to the project folder
*------------------------------------------------------------------------------
global root "`c(pwd)'"
global in   "$root/data"
global out  "$root/results"
global hard "raw/gho_FINANCIALHARDSHIP_PROPORTIONOFPOP_20261112.csv"
foreach f in panel.dta fp_surveys.dta countries_fy2027.dta $hard {
    capture confirm file "$in/`f'"
    if _rc {
        di as error "Cannot find data/`f' under: $root"
        di as error "Set the working directory to the project folder first (cd ...)."
        exit 601
    }
}
capture mkdir "$out"
capture log close
log using "$out/revision_log.smcl", replace
di as result "Project folder: $root"

foreach p in ftools require reghdfe {
    cap which `p'
    if _rc ssc install `p', replace
}
cap reghdfe, compile

set seed 20261117

* --- one results file: key (JSON-style path) and value ------------------------
tempname V
postfile `V' str60 key double value using "$out/results_v3.dta", replace

* put <postname> "<key>" <expression>   (the expression may contain spaces)
cap program drop put
program define put
    gettoken h 0 : 0
    gettoken key 0 : 0
    post `h' ("`key'") (`0')
end

* post b, p, lo, hi, n for one term of the last model (uses r(table))
cap program drop putb
program define putb
    args h key term
    tempname rt
    matrix `rt' = r(table)
    local c = colnumb(`rt', "`term'")
    post `h' ("`key'.b")  (`rt'[1,`c'])
    post `h' ("`key'.p")  (`rt'[4,`c'])
    post `h' ("`key'.lo") (`rt'[5,`c'])
    post `h' ("`key'.hi") (`rt'[6,`c'])
    post `h' ("`key'.n")  (e(N))
end

* attach to every row the panel value of `v' from the year nearest to svy_year
* (within +/- 2 years; exact year wins, then the earlier year) -- one row per
* country-survey, so this works for files with several surveys per country
cap program drop nearest2
program define nearest2
    args v
    tempvar row
    gen long `row' = _n
    preserve
        use iso3 year `v' using "$in/panel.dta", clear
        drop if missing(`v')
        rename year y_`v'
        tempfile t
        save `t'
    restore
    joinby iso3 using `t', unmatched(master)
    gen double d_`v' = abs(y_`v' - svy_year)
    bysort `row' (d_`v' y_`v'): keep if _n == 1
    replace `v' = . if missing(d_`v') | d_`v' > 2
    drop _merge d_`v' y_`v' `row'
end

* LMIC list
use "$in/countries_fy2027.dta", clear
keep iso3 country region income
tempfile L
save `L'
count
put `V' "data.n_lmic" r(N)
foreach g in LIC LMC UMC {
    count if income == "`g'"
    put `V' "data.n_by_income.`g'" r(N)
}

* survey file since 2005 with financing and income matched (+/- 2 years)
use "$in/fp_surveys.dta", clear
keep if year >= 2005
merge m:1 iso3 using `L', keep(match) nogen
rename year svy_year
foreach v in oop gov ext gdp_ppp uhc {
    nearest2 `v'
}
gen lngdp = ln(gdp_ppp)
encode region, gen(reg)
egen cid = group(iso3)
tempfile S
save `S'

*------------------------------------------------------------------------------
* 1. LEVELS: latest survey since 2005, per measure; Bangladesh value and rank
*------------------------------------------------------------------------------
foreach v in cat10 cat25 fh_total fh_impov fh_large {
    use `S', clear
    keep if !missing(`v')
    bysort iso3 (svy_year): keep if _n == _N
    count
    put `V' "levels.`v'.n" r(N)
    local n = r(N)
    summarize `v', detail
    put `V' "levels.`v'.median" r(p50)
    summarize svy_year, detail
    put `V' "levels.`v'.median_year" r(p50)
    egen rk = rank(`v'), field
    summarize `v' if iso3 == "BGD"
    put `V' "levels.`v'.bgd" r(mean)
    summarize svy_year if iso3 == "BGD"
    put `V' "levels.`v'.bgd_year" r(mean)
    summarize rk if iso3 == "BGD"
    put `V' "levels.`v'.bgd_rank" r(mean)
    * Bangladesh 2016 value ranked against every other country's latest survey
    preserve
        use `S', clear
        summarize `v' if iso3 == "BGD" & svy_year == 2016
        local b16 = r(mean)
    restore
    put `V' "bgd2016.`v'" `b16'
    count if `v' > `b16' & iso3 != "BGD"
    put `V' "bgd2016_rank.`v'.rank" r(N) + 1
    put `V' "bgd2016_rank.`v'.n" `n'
}
use `S', clear
foreach v in fh_total fh_impov fh_large {
    summarize `v' if iso3 == "BGD" & svy_year == 2022
    put `V' "bgd2022.`v'" r(mean)
}
use "$in/fp_surveys.dta", clear
keep if iso3 == "BGD" & !missing(fh_large)
sort year
put `V' "bgd_large_first.year" year[1]
put `V' "bgd_large_first.value" fh_large[1]

*------------------------------------------------------------------------------
* 2. DESIGN A: original indicator (10%), latest survey since 2005
*------------------------------------------------------------------------------
use `S', clear
keep if !missing(cat10)
bysort iso3 (svy_year): keep if _n == _N
count
put `V' "A.n_all" r(N)
summarize svy_year, detail
put `V' "A.median_svy" r(p50)
count if svy_year >= 2015
put `V' "A.n_since2015" r(N)
count if svy_year < 2010
put `V' "A.n_pre2010" r(N)
tempfile A
save `A'

regress cat10 oop, vce(robust)
putb `V' "A.m0" oop
regress cat10 oop lngdp uhc i.reg, vce(robust)
putb `V' "A.m1" oop
gen byte insA = e(sample)
regress cat25 oop lngdp uhc i.reg, vce(robust)
putb `V' "A.m25" oop
regress cat10 gov lngdp uhc i.reg, vce(robust)
putb `V' "A.mgov" gov
regress cat10 gov oop lngdp uhc i.reg, vce(robust)
putb `V' "A.jgov" gov
putb `V' "A.joop" oop
correlate gov oop if insA
put `V' "A.r_gov_oop" r(rho)
regress cat10 uhc lngdp if insA, vce(robust)
putb `V' "A.muhc" uhc
gen shares = oop + gov + ext
summarize shares if insA, detail
put `V' "data.shares_sum_median" r(p50)
* leave-one-out (jackknife) range of the OOP coefficient
keep if insA
local lo = .
local hi = .
forvalues i = 1/`=_N' {
    quietly regress cat10 oop lngdp uhc i.reg if _n != `i'
    local lo = min(`lo', _b[oop])
    local hi = max(`hi', _b[oop])
}
put `V' "A.jk_min" `lo'
put `V' "A.jk_max" `hi'
tempfile dA
save `dA'

*------------------------------------------------------------------------------
* 3. SAME-SURVEY COMPARISON: both indicators from one survey (latest such)
*------------------------------------------------------------------------------
use `S', clear
keep if !missing(cat10, fh_total)
bysort iso3 (svy_year): keep if _n == _N
count
put `V' "pairs.n" r(N)
summarize svy_year, detail
put `V' "pairs.median_year" r(p50)
foreach v in cat25 fh_total fh_impov fh_large {
    spearman cat10 `v'
    put `V' "pairs.rho_cat10_`v'" r(rho)
}
spearman cat25 fh_large
put `V' "pairs.rho_cat25_fh_large" r(rho)
export delimited iso3 svy_year income cat10 cat25 fh_total fh_impov fh_large ///
    using "$out/pairs_same_survey.csv", replace
tempfile P
save `P'

* medians by income group, reclassification, Pakistan
foreach g in LIC LMC UMC {
    count if income == "`g'"
    put `V' "bygroup.`g'.n" r(N)
    foreach v in cat10 fh_total fh_impov fh_large {
        summarize `v' if income == "`g'", detail
        put `V' "bygroup.`g'.`v'" r(p50)
    }
}
summarize cat10, detail
gen byte old_low = cat10 < r(p50)
summarize fh_total, detail
gen byte new_high = fh_total >= r(p50)
count
put `V' "reclass.n" r(N)
count if old_low & new_high
put `V' "reclass.n_switch_bad" r(N)
count if !old_low & !new_high
put `V' "reclass.n_switch_good" r(N)
count if old_low & new_high & income == "LIC"
put `V' "reclass.lic_switch" r(N)
count if income == "LIC"
put `V' "reclass.lic_n" r(N)
foreach v in svy_year cat10 fh_total {
    summarize `v' if iso3 == "PAK"
    local k = cond("`v'" == "svy_year", "year", "`v'")
    put `V' "pak.`k'" r(mean)
}

* income gradient of each indicator (region effects)
keep if !missing(lngdp)
count
put `V' "grad.n" r(N)
foreach v in cat10 cat25 fh_total fh_impov fh_large {
    spearman `v' lngdp
    put `V' "grad.`v'.rho" r(rho)
    regress `v' lngdp i.reg, vce(robust)
    putb `V' "grad.`v'" lngdp
}
* stacked test: does the income slope differ between the two indicators?
preserve
    expand 2
    bysort iso3: gen byte new = _n == 2
    gen y = cond(new, fh_total, cat10)
    regress y i.new##c.lngdp i.new##i.reg, vce(cluster cid)
    put `V' "grad.diff_b" -_b[1.new#c.lngdp]
    put `V' "grad.diff_p" 2*ttail(e(df_r), abs(_b[1.new#c.lngdp]/_se[1.new#c.lngdp]))
restore

* OOP slope of each indicator, same surveys, with controls
use `P', clear
keep if !missing(oop, lngdp, uhc)
count
put `V' "oopslope.n" r(N)
foreach v in cat10 fh_total fh_impov fh_large {
    regress `v' oop lngdp uhc i.reg, vce(robust)
    putb `V' "oopslope.`v'" oop
}
expand 2
bysort iso3: gen byte new = _n == 2
gen y = cond(new, fh_total, cat10)
regress y i.new##c.oop i.new##c.lngdp i.new##c.uhc i.new##i.reg, vce(cluster cid)
put `V' "oopslope.diff_b" _b[1.new#c.oop]
put `V' "oopslope.diff_p" 2*ttail(e(df_r), abs(_b[1.new#c.oop]/_se[1.new#c.oop]))

*------------------------------------------------------------------------------
* 4. WHO BEARS HARDSHIP: WHO breakdowns of the 2025 indicator
*------------------------------------------------------------------------------
import delimited using "$in/$hard", clear varnames(1) case(lower) stringcols(_all)
keep spatialdim timedim dim1 dim2 numericvalue
destring timedim numericvalue, replace
rename spatialdim iso3
rename timedim svy_year
merge m:1 iso3 using `L', keep(match) nogen keepusing(iso3)
keep if svy_year >= 2005
gen g = ""
replace g = "q1"     if dim1 == "WEALTHQUINTILE_WQ1"
replace g = "q5"     if dim1 == "WEALTHQUINTILE_WQ5"
replace g = "old"    if dim1 == "HOUSEHOLD_COMP_BY_AGE_HH_COMP_ONLY_OLDER_ADULTS"
replace g = "adults" if dim1 == "HOUSEHOLD_COMP_BY_AGE_HH_COMP_ADULTS"
replace g = "rur"    if dim1 == "RESIDENCEAREATYPE_RUR"
replace g = "urb"    if dim1 == "RESIDENCEAREATYPE_URB"
replace g = "h60"    if dim1 == "DEMOGRAPHIC_HEADOFHOUSEHOLD" & dim2 == "AGEGROUP_AGE60+"
replace g = "hlt60"  if dim1 == "DEMOGRAPHIC_HEADOFHOUSEHOLD" & dim2 == "AGEGROUP_AGELT60"
keep if g != ""
collapse (mean) numericvalue, by(iso3 svy_year g)
reshape wide numericvalue, i(iso3 svy_year) j(g) string
rename numericvalue* *
foreach y in 2005 2010 2016 2022 {
    foreach a in q1 q5 old adults rur urb h60 hlt60 {
        summarize `a' if iso3 == "BGD" & svy_year == `y'
        if r(N) put `V' "bgd_groups.`y'.`a'" r(mean)
    }
}
gen gap_q   = q1 - q5
gen gap_old = old - adults
gen gap_h60 = h60 - hlt60
gen gap_rur = rur - urb
foreach v in oop gdp_ppp {
    nearest2 `v'
}
gen lngdp = ln(gdp_ppp)
tempfile G
save `G'
foreach g in gap_q gap_old gap_h60 gap_rur {
    use `G', clear
    keep if !missing(`g')
    bysort iso3 (svy_year): keep if _n == _N
    count
    put `V' "groups.`g'.n" r(N)
    summarize `g', detail
    put `V' "groups.`g'.median" r(p50)
    count if `g' > 0
    put `V' "groups.`g'.n_pos" r(N)
    regress `g' oop lngdp, vce(robust)
    putb `V' "groups.`g'.reg" oop
}

*------------------------------------------------------------------------------
* 5. WITHIN-COUNTRY: all survey rounds since 2000, country and year effects
*------------------------------------------------------------------------------
use "$in/fp_surveys.dta", clear
keep if year >= 2000
merge m:1 iso3 using `L', keep(match) nogen
rename year svy_year
foreach v in oop gdp_ppp {
    nearest2 `v'
}
gen lngdp = ln(gdp_ppp)
egen cid = group(iso3)
tempfile S0
save `S0'
foreach v in cat10 fh_total fh_large fh_impov {
    use `S0', clear
    keep if !missing(`v', oop, lngdp)
    bysort iso3: keep if _N >= 2
    reghdfe `v' oop lngdp, absorb(cid svy_year) vce(cluster cid)
    putb `V' "fe.`v'" oop
    put `V' "fe.`v'.countries" e(N_clust)
    put `V' "fe.`v'.obs" e(N)
}

*------------------------------------------------------------------------------
* 6. THRESHOLD TESTS (Design A sample, n with complete controls)
*------------------------------------------------------------------------------
use `dA', clear
count
put `V' "threshold.n" r(N)
count if oop < 20
put `V' "threshold.n_below20" r(N)

* sup-Wald over break points 10-70% (each side at least 8 countries).
* Computed in Mata: OLS with HC1 robust variance, identical to
* "regress cat10 oop h lngdp uhc i.reg, vce(robust)" for each break point,
* but fast enough for the bootstrap (499 x 61 regressions in seconds).
capture mata: mata drop supw()
mata:
real rowvector supw(real colvector y, real matrix X0, real colvector oop, real scalar minn)
{
    real scalar best, at, c, k, n, w
    real colvector h, b, e
    real matrix X, XXi, V
    best = 0
    at = .
    n = rows(y)
    for (c = 10; c <= 70; c++) {
        h = (oop :- c) :* (oop :> c)
        if (sum(h :> 0) < minn | sum(h :== 0) < minn) continue
        X   = (X0, h)
        XXi = invsym(cross(X, X))
        b   = XXi * cross(X, y)
        e   = y - X * b
        k   = sum(diagonal(XXi) :!= 0)
        V   = XXi * cross(X, e:^2, X) * XXi * (n / (n - k))
        w   = b[cols(X)]^2 / V[cols(X), cols(X)]
        if (w > best) {
            best = w
            at = c
        }
    }
    return((best, at))
}
end
quietly tab reg, gen(rd_)
drop rd_1
gen byte cons = 1
mata: y = st_data(., "cat10"); X0 = st_data(., "oop lngdp uhc rd_* cons"); o = st_data(., "oop")
mata: r0 = supw(y, X0, o, 8); st_numscalar("W0", r0[1]); st_numscalar("at0", r0[2])
put `V' "threshold.supW" W0
put `V' "threshold.at" at0
* check: the same statistic from regress at the chosen break point
gen h = max(oop - at0, 0)
regress cat10 oop h lngdp uhc i.reg, vce(robust)
put `V' "threshold.check_regress" (_b[h]/_se[h])^2
drop h
* wild bootstrap under the linear null (Rademacher weights)
quietly regress cat10 oop lngdp uhc i.reg
predict double fit, xb
predict double res, residuals
local reps = 499
mata:
f  = st_data(., "fit")
u  = st_data(., "res")
w0 = st_numscalar("W0")
ex = 0
for (r = 1; r <= `reps'; r++) {
    ys = f + u :* (2 * (runiform(rows(u), 1) :< 0.5) :- 1)
    rr = supw(ys, X0, o, 8)
    if (rr[1] >= w0) ex++
}
st_numscalar("exceed", ex)
end
put `V' "threshold.p_boot" exceed/`reps'
put `V' "threshold.reps" `reps'
foreach c in 10 15 20 {
    capture drop h
    gen h = max(oop - `c', 0)
    regress cat10 oop h lngdp uhc i.reg, vce(robust)
    putb `V' "threshold.h`c'" h
}
capture drop h
gen oop2 = oop^2
regress cat10 oop oop2 lngdp uhc i.reg, vce(robust)
putb `V' "threshold.quad" oop2
put `V' "threshold.slope_change_20_70.0" 100*(_b[oop2] - invttail(e(df_r),0.025)*_se[oop2])
put `V' "threshold.slope_change_20_70.1" 100*(_b[oop2] + invttail(e(df_r),0.025)*_se[oop2])
regress cat10 c.oop##c.lngdp uhc i.reg, vce(robust)
putb `V' "threshold.inter_lngdp" c.oop#c.lngdp
* unadjusted slope by income group (all countries with OOP)
use `A', clear
foreach g in LIC LMC UMC {
    regress cat10 oop if income == "`g'", vce(robust)
    putb `V' "threshold.slope_`g'" oop
}

*------------------------------------------------------------------------------
* 7. DESIGN B: health per dollar, 2019
*------------------------------------------------------------------------------
use "$in/panel.dta", clear
keep if year == 2019
merge m:1 iso3 using `L', keep(match) nogen
count if !missing(che_ppp)
put `V' "data.n_spend_2019" r(N)
gen lnche = ln(che_ppp)
gen lngdp = ln(gdp_ppp)
gen lnu5  = ln(u5mr)
regress lnu5 lnche, vce(robust)
put `V' "B.u5_r2" e(r2)
put `V' "B.u5_n" e(N)
keep if !missing(le_who, lnche)
regress le_who lnche, vce(robust)
put `V' "B.n" e(N)
put `V' "B.r2" e(r2)
put `V' "B.per_doubling" _b[lnche]*ln(2)
predict double res, residuals
egen rk = rank(res), field
summarize res if iso3 == "BGD"
put `V' "B.bgd_res" r(mean)
summarize rk if iso3 == "BGD"
put `V' "B.bgd_rank" r(mean)
summarize res if iso3 == "LKA"
put `V' "B.lka_res" r(mean)
regress le_who lnche lngdp, vce(robust)
put `V' "B.n_gdp" e(N)
put `V' "B.lnche_gdp" _b[lnche]
put `V' "B.lnche_gdp_p" 2*ttail(e(df_r), abs(_b[lnche]/_se[lnche]))
predict double res_g if e(sample), residuals
egen rk_g = rank(res_g), field
summarize res_g if iso3 == "BGD"
put `V' "B.bgd_res_g" r(mean)
summarize rk_g if iso3 == "BGD"
put `V' "B.bgd_rank_g" r(mean)
summarize le_who if iso3 == "BGD"
put `V' "B.bgd_le" r(mean)
summarize che_ppp if iso3 == "BGD"
put `V' "B.bgd_che" r(mean)
summarize oop if iso3 == "BGD"
put `V' "B.bgd_oop19" r(mean)
egen rk_oop = rank(oop), field
summarize rk_oop if iso3 == "BGD"
put `V' "B.bgd_oop_rank" r(mean)
summarize oop, detail
put `V' "B.median_oop19" r(p50)
keep iso3 res res_g
tempfile Bres
save `Bres'
* efficiency (residual) against hardship under each indicator
foreach v in cat10 fh_total {
    use `S', clear
    keep if !missing(`v')
    bysort iso3 (svy_year): keep if _n == _N
    merge 1:1 iso3 using `Bres', keep(match) nogen
    count
    put `V' "eff.`v'.n" r(N)
    spearman res `v'
    put `V' "eff.`v'.rho" r(rho)
    spearman res_g `v'
    put `V' "eff.`v'.rho_g" r(rho)
    summarize `v', detail
    local m = r(p50)
    put `V' "eff.`v'.median" `m'
    count if res > 3 & `v' < `m'
    put `V' "eff.`v'.over_low" r(N)
    count if res > 3 & `v' >= `m'
    put `V' "eff.`v'.over_high" r(N)
}

*------------------------------------------------------------------------------
* 8. DESIGN C: annual panel 2000-2019, country and year effects
*------------------------------------------------------------------------------
use "$in/panel.dta", clear
keep if inrange(year, 2000, 2019)
merge m:1 iso3 using `L', keep(match) nogen
egen cid = group(iso3)
gen lnu5    = ln(u5mr)
gen lngdp   = ln(gdp_ppp)
gen lnche_k = ln(che_gdp/100 * gdp_ppp)
reghdfe lnu5 lnche_k, absorb(cid year) vce(cluster cid)
putb `V' "C.u5_noinc" lnche_k
put `V' "C.u5_noinc.countries" e(N_clust)
reghdfe lnu5 lnche_k lngdp, absorb(cid year) vce(cluster cid)
putb `V' "C.u5_inc" lnche_k
put `V' "C.u5_inc.countries" e(N_clust)
reghdfe uhc oop, absorb(cid year) vce(cluster cid)
putb `V' "C.uhc_noinc" oop
put `V' "C.uhc_noinc.countries" e(N_clust)
reghdfe uhc oop lngdp, absorb(cid year) vce(cluster cid)
putb `V' "C.uhc_inc" oop
put `V' "C.uhc_inc.countries" e(N_clust)

*------------------------------------------------------------------------------
* 9. EXPORT
*------------------------------------------------------------------------------
postclose `V'
use "$out/results_v3.dta", clear
format value %20.10g
export delimited using "$out/results_v3.csv", replace datafmt
list in 1/20, clean noobs
log close
translate "$out/revision_log.smcl" "$out/revision_log.log", replace translator(smcl2log)
capture translate "$out/revision_log.smcl" "$out/revision_log.pdf", replace translator(smcl2pdf)
di as result "DONE"


*==============================================================================
*  SECTION 3: v4 analysis (poverty-adjusted gap models)
*==============================================================================
/*==============================================================================
  07_v4_analysis.do   (V3 project, abstract version 4, 18 Nov 2026)
  Checks requested by the senior for abstract v4:
     1  poverty-adjusted models (wealth-quintile, older-household and
        rural-urban gaps; national large and impoverishing components)
     2  sample-selection table for every design + selection-bias check
     3  sensitivity: matching windows, income group at survey year,
        outliers, alternative specifications, threshold reassessment
  Run 05_revision_analysis.do first only if you want the v3 numbers again;
  this file is self-contained and needs only the files in data/.

  Inputs (data/):
     panel.dta, fp_surveys.dta, countries_fy2027.dta          (from 01_...py)
     raw/gho_FINANCIALHARDSHIP_PROPORTIONOFPOP_20261112.csv    (WHO GHO)
     raw/wdi_v4_long_20261118.csv   SI.POV.SOPO, SI.POV.DDAY, SP.POP.65UP.TO.ZS
     raw/OGHIST_20261118.xlsx       World Bank historical income groups
                                    (both made by 00_download_v4_data.py)
  Outputs (results/):
     results_v4.csv                 every number used in abstract v4 (key,value)
     sample_by_country_v4.csv       which country is in which design
     panel_v4.dta                   panel + poverty + pop65 (derived)
     v4_log.smcl / .log / .pdf
  Stata 17.  cd "<project folder>"  then  do stata/07_v4_analysis.do
  Run time: about 2-4 minutes (two 499-replication bootstraps).
==============================================================================*/

version 17
clear all
set more off
set varabbrev off

*------------------------------------------------------------------------------
* 0. SETUP
*------------------------------------------------------------------------------
global root "`c(pwd)'"
global in   "$root/data"
global out  "$root/results"
global hard "raw/gho_FINANCIALHARDSHIP_PROPORTIONOFPOP_20261112.csv"
global wdi4 "raw/wdi_v4_long_20261118.csv"
global oghist "raw/OGHIST_20261118.xlsx"
foreach f in panel.dta fp_surveys.dta countries_fy2027.dta $hard $wdi4 $oghist {
    capture confirm file "$in/`f'"
    if _rc {
        di as error "Cannot find data/`f' under: $root"
        di as error "Set the working directory to the project folder first (cd ...)."
        exit 601
    }
}
capture mkdir "$out"
capture log close
log using "$out/v4_log.smcl", replace
di as result "Project folder: $root"

* (no user-written packages needed: base Stata 17 only)
set seed 20261118

tempname V
postfile `V' str60 key double value using "$out/results_v4.dta", replace

cap program drop put
program define put
    gettoken h 0 : 0
    gettoken key 0 : 0
    post `h' ("`key'") (`0')
end

* b, p, lo, hi, n of one term of the last model
cap program drop putb
program define putb
    args h key term
    tempname rt
    matrix `rt' = r(table)
    local c = colnumb(`rt', "`term'")
    post `h' ("`key'.b")  (`rt'[1,`c'])
    post `h' ("`key'.p")  (`rt'[4,`c'])
    post `h' ("`key'.lo") (`rt'[5,`c'])
    post `h' ("`key'.hi") (`rt'[6,`c'])
    post `h' ("`key'.n")  (e(N))
end

* nearestk v k : attach the panel_v4 value of v from the year nearest svy_year,
* within +/- k years (exact year first, then the earlier year)
cap program drop nearestk
program define nearestk
    args v k
    tempvar row
    gen long `row' = _n
    preserve
        use iso3 year `v' using "$out/panel_v4.dta", clear
        drop if missing(`v')
        rename year y_`v'
        tempfile t
        save `t'
    restore
    capture drop `v'
    joinby iso3 using `t', unmatched(master)
    gen double d_`v' = abs(y_`v' - svy_year)
    bysort `row' (d_`v' y_`v'): keep if _n == 1
    replace `v' = . if missing(d_`v') | d_`v' > `k'
    gen byte dist_`v' = d_`v' if !missing(`v')
    drop _merge d_`v' y_`v' `row'
end

*------------------------------------------------------------------------------
* 1. BUILD: poverty, pop65 and historical income group
*------------------------------------------------------------------------------
use "$in/countries_fy2027.dta", clear
keep iso3 country region income
encode region, gen(reg)
tempfile L
save `L'

import delimited using "$in/$wdi4", clear varnames(1) case(lower)
reshape wide value, i(iso3 year) j(var) string
rename value* *
tempfile W4
save `W4'
use "$in/panel.dta", clear
merge 1:1 iso3 year using `W4', keep(master match) nogen
merge m:1 iso3 using `L', keep(match) nogen keepusing(iso3)
gen lngdp = ln(gdp_ppp)
save "$out/panel_v4.dta", replace
* poverty data points that fall outside 2000-2023 (panel years) are not needed:
* every survey used here is from 2000-2022 except a few 2023-2024 rounds
* (matched within the window to 2022-2023 poverty points if available)
count if !missing(pov_spl)
put `V' "data.pov_spl_points" r(N)
preserve
    keep if !missing(pov_spl)
    bysort iso3: keep if _n == 1
    count
    put `V' "data.pov_spl_countries" r(N)
restore

* historical income group: FYxx uses GNI of calendar year xx-2.
* A survey in year t is assigned the group published from GNI of year t
* (FY t+2); surveys after 2023 get the latest group in the file (FY25).
import excel using "$in/$oghist", sheet("Country Analytical History") ///
    cellrange(A12:AM240) allstring clear
rename A iso3
drop B
keep if ustrregexm(iso3, "^[A-Z]{3}$")   // drop blank and note rows
local y = 1987
foreach c of varlist C-AM {
    rename `c' g`y'
    local ++y
}
reshape long g, i(iso3) j(svy_year)
replace g = strtrim(g)
gen inc_hist = ""
replace inc_hist = "LIC" if g == "L"
replace inc_hist = "LMC" if g == "LM"
replace inc_hist = "UMC" if g == "UM"
replace inc_hist = "HIC" if g == "H"
drop g
drop if inc_hist == ""
merge m:1 iso3 using `L', keep(match) nogen keepusing(iso3)
* extend 2023 classification to 2024 (latest available, FY25)
expand 2 if svy_year == 2023, gen(dup)
replace svy_year = 2024 if dup
drop dup
tempfile H
save `H'

* --- survey files for any matching window k ---------------------------------
cap program drop build_S
program define build_S
    args k L H
    use "$in/fp_surveys.dta", clear
    keep if year >= 2005
    drop country region income
    merge m:1 iso3 using `L', keep(match) nogen
    rename year svy_year
    foreach v in oop gov ext gdp_ppp uhc pov_spl pov_ipl {
        nearestk `v' `k'
    }
    gen lngdp = ln(gdp_ppp)
    egen cid = group(iso3)
    merge m:1 iso3 svy_year using `H', keep(master match) nogen
end

cap program drop build_G
program define build_G
    args k L
    import delimited using "$in/$hard", clear varnames(1) case(lower) stringcols(_all)
    keep spatialdim timedim dim1 dim2 numericvalue
    destring timedim numericvalue, replace
    rename spatialdim iso3
    rename timedim svy_year
    merge m:1 iso3 using `L', keep(match) nogen keepusing(iso3)
    keep if svy_year >= 2005
    gen g = ""
    replace g = "q1"     if dim1 == "WEALTHQUINTILE_WQ1"
    replace g = "q5"     if dim1 == "WEALTHQUINTILE_WQ5"
    replace g = "old"    if dim1 == "HOUSEHOLD_COMP_BY_AGE_HH_COMP_ONLY_OLDER_ADULTS"
    replace g = "adults" if dim1 == "HOUSEHOLD_COMP_BY_AGE_HH_COMP_ADULTS"
    replace g = "rur"    if dim1 == "RESIDENCEAREATYPE_RUR"
    replace g = "urb"    if dim1 == "RESIDENCEAREATYPE_URB"
    replace g = "tot"    if dim1 == "FINANCIALHARDSHIPCOMPONENT_COMPONENT_TOTAL"
    keep if g != ""
    collapse (mean) numericvalue, by(iso3 svy_year g)
    reshape wide numericvalue, i(iso3 svy_year) j(g) string
    rename numericvalue* *
    gen gap_q   = q1 - q5
    gen gap_old = old - adults
    gen gap_rur = rur - urb
    merge m:1 iso3 using `L', keep(match) nogen
    foreach v in oop gdp_ppp uhc pov_spl pov_ipl pop65 {
        nearestk `v' `k'
    }
    gen lngdp = ln(gdp_ppp)
end

*------------------------------------------------------------------------------
* 2. POVERTY-ADJUSTED MODELS (base window +/- 2 years)
*------------------------------------------------------------------------------
build_S 2 `L' `H'
tempfile S
save `S'
build_G 2 `L'
tempfile G
save `G'

* how often the poverty point is from the survey year itself
use `G', clear
count if !missing(pov_spl)
put `V' "pov.match.n" r(N)
count if dist_pov_spl == 0
put `V' "pov.match.exact" r(N)

* correlation of the two poverty measures with income
use "$out/panel_v4.dta", clear
correlate pov_spl lngdp
put `V' "pov.r_spl_lngdp" r(rho)
correlate pov_spl pov_ipl
put `V' "pov.r_spl_ipl" r(rho)

foreach g in gap_q gap_old gap_rur {
    use `G', clear
    keep if !missing(`g')
    bysort iso3 (svy_year): keep if _n == _N
    * (a) v3 model, full sample
    regress `g' oop lngdp, vce(robust)
    putb `V' "pov.`g'.base" oop
    * (b) same model on the countries that have a poverty point
    regress `g' oop lngdp if !missing(pov_spl), vce(robust)
    putb `V' "pov.`g'.base_povsample" oop
    * (c) + societal poverty headcount
    regress `g' oop lngdp pov_spl, vce(robust)
    putb `V' "pov.`g'.spl" oop
    putb `V' "pov.`g'.spl_pov" pov_spl
    * (d) + extreme poverty headcount instead
    regress `g' oop lngdp pov_ipl, vce(robust)
    putb `V' "pov.`g'.ipl" oop
    putb `V' "pov.`g'.ipl_pov" pov_ipl
    * (e) poverty only (does OOP add anything?)
    regress `g' pov_spl lngdp if !missing(oop), vce(robust)
    put `V' "pov.`g'.r2_povonly" e(r2)
    regress `g' oop lngdp pov_spl, vce(robust)
    put `V' "pov.`g'.r2_full" e(r2)
    * (f) + region effects
    regress `g' oop lngdp pov_spl i.reg, vce(robust)
    putb `V' "pov.`g'.spl_reg" oop
}
* older-only gap: also control the population share aged 65+
use `G', clear
keep if !missing(gap_old)
bysort iso3 (svy_year): keep if _n == _N
regress gap_old oop lngdp pov_spl pop65, vce(robust)
putb `V' "pov.gap_old.pop65" oop
* the two ends of the quintile gap separately
foreach a in q1 q5 {
    use `G', clear
    keep if !missing(gap_q)
    bysort iso3 (svy_year): keep if _n == _N
    regress `a' oop lngdp pov_spl, vce(robust)
    putb `V' "pov.`a'.spl" oop
    putb `V' "pov.`a'.spl_pov" pov_spl
}

* national components of the 2025 indicator (latest survey since 2005)
foreach v in fh_total fh_large fh_impov cat10 {
    use `S', clear
    keep if !missing(`v')
    bysort iso3 (svy_year): keep if _n == _N
    regress `v' oop lngdp uhc i.reg, vce(robust)
    putb `V' "comp.`v'.base" oop
    regress `v' oop lngdp uhc i.reg if !missing(pov_spl), vce(robust)
    putb `V' "comp.`v'.base_povsample" oop
    regress `v' oop lngdp uhc pov_spl i.reg, vce(robust)
    putb `V' "comp.`v'.spl" oop
    putb `V' "comp.`v'.spl_pov" pov_spl
    regress `v' oop lngdp uhc pov_ipl i.reg, vce(robust)
    putb `V' "comp.`v'.ipl" oop
}
* yardstick reversal with poverty held constant (same-survey pairs)
use `S', clear
keep if !missing(cat10, fh_total)
bysort iso3 (svy_year): keep if _n == _N
tempfile P
save `P'
foreach v in cat10 fh_total fh_large fh_impov {
    regress `v' lngdp pov_spl i.reg, vce(robust)
    putb `V' "grad_pov.`v'" lngdp
}
preserve
    keep if !missing(lngdp, pov_spl)
    expand 2
    bysort iso3: gen byte new = _n == 2
    gen y = cond(new, fh_total, cat10)
    regress y i.new##c.lngdp i.new##c.pov_spl i.new##i.reg, vce(cluster cid)
    put `V' "grad_pov.diff_b" -_b[1.new#c.lngdp]
    put `V' "grad_pov.diff_p" 2*ttail(e(df_r), abs(_b[1.new#c.lngdp]/_se[1.new#c.lngdp]))
    put `V' "grad_pov.n" e(N)/2
restore

* survey years actually used by each survey-based sample (latest survey per country)
foreach v in cat10 fh_total {
    use `S', clear
    keep if !missing(`v')
    bysort iso3 (svy_year): keep if _n == _N
    summarize svy_year, detail
    put `V' "years.`v'.min" r(min)
    put `V' "years.`v'.max" r(max)
    put `V' "years.`v'.median" r(p50)
}
use `P', clear
summarize svy_year, detail
put `V' "years.pairs.min" r(min)
put `V' "years.pairs.max" r(max)
put `V' "years.pairs.median" r(p50)
list iso3 svy_year income inc_hist if inc_hist == "HIC", clean noobs
foreach g in gap_q gap_old gap_rur {
    use `G', clear
    keep if !missing(`g')
    bysort iso3 (svy_year): keep if _n == _N
    summarize svy_year, detail
    put `V' "years.`g'.min" r(min)
    put `V' "years.`g'.max" r(max)
    put `V' "years.`g'.median" r(p50)
    count if !missing(pov_spl, oop, lngdp)
    put `V' "years.`g'.pov_n" r(N)
    count if dist_pov_spl == 0 & !missing(oop, lngdp)
    put `V' "years.`g'.pov_exact" r(N)
}
use "$in/fp_surveys.dta", clear
keep if year >= 2000 & !missing(cat10)
summarize year
put `V' "years.rounds.min" r(min)
put `V' "years.rounds.max" r(max)

*------------------------------------------------------------------------------
* 3. SAMPLE SELECTION: who is in each design, and are they different?
*------------------------------------------------------------------------------
* design flags, one row per LMIC
use `L', clear
keep iso3 country region income reg
tempfile F
save `F'

* A: latest original-indicator survey since 2005
use `S', clear
keep if !missing(cat10)
bysort iso3 (svy_year): keep if _n == _N
gen byte A_out = 1
gen byte A_reg = !missing(cat10, oop, lngdp, uhc, reg)
keep iso3 A_out A_reg
merge 1:1 iso3 using `F', nogen
save `F', replace
* P: same-survey pairs; P_grad has income; P_oop has all controls
use `P', clear
gen byte P_out = 1
gen byte P_grad = !missing(lngdp)
gen byte P_oop = !missing(oop, lngdp, uhc)
keep iso3 P_out P_grad P_oop
merge 1:1 iso3 using `F', nogen
save `F', replace
* N: latest 2025-indicator survey
use `S', clear
keep if !missing(fh_total)
bysort iso3 (svy_year): keep if _n == _N
gen byte N_out = 1
gen byte N_reg = !missing(oop, lngdp, uhc)
gen byte N_pov = N_reg & !missing(pov_spl)
keep iso3 N_out N_reg N_pov
merge 1:1 iso3 using `F', nogen
save `F', replace
* G: group gaps
foreach g in gap_q gap_old gap_rur {
    use `G', clear
    keep if !missing(`g')
    bysort iso3 (svy_year): keep if _n == _N
    gen byte `g'_out = 1
    gen byte `g'_reg = !missing(oop, lngdp)
    gen byte `g'_pov = `g'_reg & !missing(pov_spl)
    keep iso3 `g'_*
    merge 1:1 iso3 using `F', nogen
    save `F', replace
}
* B: 2019 cross-section
use "$out/panel_v4.dta", clear
keep if year == 2019
gen byte B_out = !missing(che_ppp, le_who)
gen byte B_inc = B_out & !missing(lngdp)
gen byte B_u5  = !missing(che_ppp, u5mr)
keep iso3 B_*
merge 1:1 iso3 using `F', nogen
save `F', replace
* C: annual panel 2000-2019 (U5MR model with income)
use "$out/panel_v4.dta", clear
keep if inrange(year, 2000, 2019) & !missing(u5mr, che_gdp, gdp_ppp)
bysort iso3: gen nyr = _N
bysort iso3: keep if _n == 1
gen byte C_out = nyr >= 2
keep iso3 C_out
merge 1:1 iso3 using `F', nogen
save `F', replace
* D: survey rounds with country effects (original indicator, >= 2 rounds)
use "$in/fp_surveys.dta", clear
keep if year >= 2000 & !missing(cat10)
drop country region income
merge m:1 iso3 using `L', keep(match) nogen
rename year svy_year
foreach v in oop gdp_ppp {
    nearestk `v' 2
}
keep if !missing(cat10, oop, gdp_ppp)
bysort iso3: gen nr = _N
bysort iso3: keep if _n == 1
gen byte D_out = nr >= 2
keep iso3 D_out
merge 1:1 iso3 using `F', nogen
foreach v of varlist *_out *_reg *_grad *_oop *_pov *_inc *_u5 {
    replace `v' = 0 if missing(`v')
}
* 2017 characteristics for the bias check (median survey year)
preserve
    use "$out/panel_v4.dta", clear
    keep if year == 2017
    keep iso3 lngdp oop uhc u5mr gov
    tempfile C17
    save `C17'
restore
merge 1:1 iso3 using `C17', keep(master match) nogen
export delimited iso3 country income region A_out A_reg P_out P_grad P_oop ///
    N_out N_reg N_pov gap_q_out gap_q_reg gap_q_pov gap_old_out gap_old_reg ///
    gap_old_pov gap_rur_out gap_rur_reg gap_rur_pov B_out B_inc B_u5 C_out D_out ///
    using "$out/sample_by_country_v4.csv", replace

count
put `V' "sel.n_lmic" r(N)
foreach d in A_out A_reg P_out P_grad P_oop N_out N_reg N_pov gap_q_out gap_q_reg ///
    gap_q_pov gap_old_out gap_old_reg gap_old_pov gap_rur_out gap_rur_reg ///
    gap_rur_pov B_out B_inc B_u5 C_out D_out {
    count if `d'
    put `V' "sel.`d'.n" r(N)
    foreach g in LIC LMC UMC {
        count if `d' & income == "`g'"
        put `V' "sel.`d'.`g'" r(N)
    }
}
* included vs excluded: 2017 income, OOP share, service coverage, U5MR
foreach d in A_reg P_oop N_reg gap_q_pov gap_old_pov gap_rur_pov D_out {
    foreach x in lngdp oop uhc u5mr {
        summarize `x' if `d' == 1
        put `V' "bias.`d'.`x'.in" r(mean)
        summarize `x' if `d' == 0
        put `V' "bias.`d'.`x'.out" r(mean)
        put `V' "bias.`d'.`x'.n_out" r(N)
        capture ranksum `x', by(`d')
        if !_rc put `V' "bias.`d'.`x'.p" 2*normprob(-abs(r(z)))
    }
    * logit of inclusion on the four characteristics: joint test
    capture logit `d' lngdp oop uhc
    if !_rc {
        put `V' "bias.`d'.logit_p" e(p)
        put `V' "bias.`d'.logit_n" e(N)
    }
}

*------------------------------------------------------------------------------
* 4. SENSITIVITY
*------------------------------------------------------------------------------
* 4a. matching window (+/-0, 1, 2, 3 years)
foreach k in 0 1 2 3 {
    build_S `k' `L' `H'
    tempfile Sk
    save `Sk'
    keep if !missing(cat10)
    bysort iso3 (svy_year): keep if _n == _N
    regress cat10 oop lngdp uhc i.reg, vce(robust)
    putb `V' "win`k'.A" oop
    use `Sk', clear
    keep if !missing(cat10, fh_total)
    bysort iso3 (svy_year): keep if _n == _N
    keep if !missing(lngdp)
    spearman fh_total lngdp
    put `V' "win`k'.rho_new" r(rho)
    spearman cat10 lngdp
    put `V' "win`k'.rho_old" r(rho)
    expand 2
    bysort iso3: gen byte new = _n == 2
    gen y = cond(new, fh_total, cat10)
    regress y i.new##c.lngdp i.new##i.reg, vce(cluster cid)
    put `V' "win`k'.diff_b" -_b[1.new#c.lngdp]
    put `V' "win`k'.diff_p" 2*ttail(e(df_r), abs(_b[1.new#c.lngdp]/_se[1.new#c.lngdp]))
    put `V' "win`k'.diff_n" e(N)/2
    build_G `k' `L'
    tempfile Gk
    save `Gk'
    foreach g in gap_q gap_old gap_rur {
        use `Gk', clear
        keep if !missing(`g')
        bysort iso3 (svy_year): keep if _n == _N
        regress `g' oop lngdp, vce(robust)
        putb `V' "win`k'.`g'" oop
        regress `g' oop lngdp pov_spl, vce(robust)
        putb `V' "win`k'.`g'_pov" oop
    }
}

* 4b. income group at survey year (World Bank historical classification)
use `P', clear
count if missing(inc_hist)
put `V' "hist.n_missing" r(N)
count if inc_hist != income & !missing(inc_hist)
put `V' "hist.n_differs" r(N)
count if inc_hist == "HIC"
put `V' "hist.n_hic" r(N)
foreach g in LIC LMC UMC {
    count if inc_hist == "`g'"
    put `V' "hist.`g'.n" r(N)
    foreach v in cat10 fh_total {
        summarize `v' if inc_hist == "`g'", detail
        put `V' "hist.`g'.`v'" r(p50)
    }
}
summarize cat10, detail
gen byte old_low = cat10 < r(p50)
summarize fh_total, detail
gen byte new_high = fh_total >= r(p50)
count if old_low & new_high & inc_hist == "LIC"
put `V' "hist.lic_switch" r(N)
* ordered income group as the regressor instead of log GDP
gen byte incg = 1*(inc_hist == "LIC") + 2*(inc_hist == "LMC") + 3*(inc_hist == "UMC") ///
    + 4*(inc_hist == "HIC")
replace incg = . if incg == 0
spearman cat10 incg
put `V' "hist.rho_old" r(rho)
spearman fh_total incg
put `V' "hist.rho_new" r(rho)

* 4c. outliers and 4d. alternative specifications
* --- Design A ---
use `S', clear
keep if !missing(cat10)
bysort iso3 (svy_year): keep if _n == _N
keep if !missing(cat10, oop, lngdp, uhc, reg)
regress cat10 oop lngdp uhc i.reg
predict double cd, cooksd
count if cd > 4/e(N)
put `V' "alt.A.n_cook" r(N)
regress cat10 oop lngdp uhc i.reg if cd <= 4/e(N), vce(robust)
putb `V' "alt.A.cook" oop
summarize oop, detail
local p5 = r(p5)
local p95 = r(p95)
regress cat10 oop lngdp uhc i.reg if inrange(oop, `p5', `p95'), vce(robust)
putb `V' "alt.A.trim" oop
qreg cat10 oop lngdp uhc i.reg, vce(robust)
putb `V' "alt.A.qreg" oop
gen double cat10f = cat10/100
fracreg logit cat10f oop lngdp uhc i.reg, vce(robust)
margins, dydx(oop)
matrix M = r(table)
put `V' "alt.A.frac.b" 100*el(M,1,1)
put `V' "alt.A.frac.p" el(M,4,1)
put `V' "alt.A.frac.n" e(N)
regress cat10 oop lngdp uhc, vce(robust)
putb `V' "alt.A.noreg" oop
* --- income gradient of each indicator (pairs) ---
use `P', clear
keep if !missing(lngdp)
foreach v in cat10 fh_total {
    regress `v' lngdp i.reg
    predict double cd_`v', cooksd
    regress `v' lngdp i.reg if cd_`v' <= 4/e(N), vce(robust)
    putb `V' "alt.grad.`v'.cook" lngdp
    qreg `v' lngdp i.reg, vce(robust)
    putb `V' "alt.grad.`v'.qreg" lngdp
    gen double `v'f = `v'/100
    fracreg logit `v'f lngdp i.reg, vce(robust)
    margins, dydx(lngdp)
    matrix M = r(table)
    put `V' "alt.grad.`v'.frac.b" 100*el(M,1,1)
    put `V' "alt.grad.`v'.frac.p" el(M,4,1)
    regress `v' lngdp, vce(robust)
    putb `V' "alt.grad.`v'.noreg" lngdp
}
* --- group gaps ---
foreach g in gap_q gap_old gap_rur {
    use `G', clear
    keep if !missing(`g')
    bysort iso3 (svy_year): keep if _n == _N
    keep if !missing(`g', oop, lngdp)
    regress `g' oop lngdp
    predict double cd, cooksd
    regress `g' oop lngdp if cd <= 4/e(N), vce(robust)
    putb `V' "alt.`g'.cook" oop
    qreg `g' oop lngdp, vce(robust)
    putb `V' "alt.`g'.qreg" oop
    * ratio instead of difference (relative gap)
    if "`g'" == "gap_q"   gen double rel = ln(q1/q5)     if q5 > 0 & q1 > 0
    if "`g'" == "gap_old" gen double rel = ln(old/adults) if adults > 0 & old > 0
    if "`g'" == "gap_rur" gen double rel = ln(rur/urb)   if urb > 0 & rur > 0
    regress rel oop lngdp, vce(robust)
    putb `V' "alt.`g'.ln_ratio" oop
}

* 4e. threshold reassessment on the 2025 indicator (pairs with controls)
capture mata: mata drop supw()
capture mata: mata drop wboot()
mata:
real rowvector supw(real colvector y, real matrix X0, real colvector oop, real scalar minn)
{
    real scalar best, at, c, k, n, w
    real colvector h, b, e
    real matrix X, XXi, V
    best = 0
    at = .
    n = rows(y)
    for (c = 10; c <= 70; c++) {
        h = (oop :- c) :* (oop :> c)
        if (sum(h :> 0) < minn | sum(h :== 0) < minn) continue
        X   = (X0, h)
        XXi = invsym(cross(X, X))
        b   = XXi * cross(X, y)
        e   = y - X * b
        k   = sum(diagonal(XXi) :!= 0)
        V   = XXi * cross(X, e:^2, X) * XXi * (n / (n - k))
        w   = b[cols(X)]^2 / V[cols(X), cols(X)]
        if (w > best) {
            best = w
            at = c
        }
    }
    return((best, at))
}
real scalar wboot(real colvector f, real colvector u, real matrix X0, real colvector o, real scalar w0, real scalar reps)
{
    real scalar r, ex
    real colvector ys
    real rowvector rr
    ex = 0
    for (r = 1; r <= reps; r++) {
        ys = f + u :* (2 * (runiform(rows(u), 1) :< 0.5) :- 1)
        rr = supw(ys, X0, o, 8)
        if (rr[1] >= w0) ex++
    }
    return(ex)
}
end
foreach spec in base pov {
    use `S', clear
    keep if !missing(fh_total)
    bysort iso3 (svy_year): keep if _n == _N
    local ctl "lngdp uhc"
    if "`spec'" == "pov" local ctl "lngdp uhc pov_spl"
    keep if !missing(fh_total, oop, reg) & !missing(`=subinstr("`ctl'", " ", ",", .)')
    count
    put `V' "thr_new.`spec'.n" r(N)
    quietly tab reg, gen(rd_)
    drop rd_1
    gen byte cons = 1
    mata: y = st_data(., "fh_total"); X0 = st_data(., "oop `ctl' rd_* cons"); o = st_data(., "oop")
    mata: r0 = supw(y, X0, o, 8); st_numscalar("W0", r0[1]); st_numscalar("at0", r0[2])
    put `V' "thr_new.`spec'.supW" W0
    put `V' "thr_new.`spec'.at" at0
    quietly regress fh_total oop `ctl' i.reg
    predict double fit, xb
    predict double res, residuals
    mata: st_numscalar("exceed", wboot(st_data(., "fit"), st_data(., "res"), X0, o, st_numscalar("W0"), 499))
    put `V' "thr_new.`spec'.p_boot" exceed/499
    gen oop2 = oop^2
    regress fh_total oop oop2 `ctl' i.reg, vce(robust)
    putb `V' "thr_new.`spec'.quad" oop2
    capture drop h
    gen h = max(oop - 20, 0)
    regress fh_total oop h `ctl' i.reg, vce(robust)
    putb `V' "thr_new.`spec'.h20" h
}

*------------------------------------------------------------------------------
* 5. EXPORT
*------------------------------------------------------------------------------
postclose `V'
use "$out/results_v4.dta", clear
format value %20.10g
export delimited using "$out/results_v4.csv", replace datafmt
count
log close
translate "$out/v4_log.smcl" "$out/v4_log.log", replace translator(smcl2log)
capture translate "$out/v4_log.smcl" "$out/v4_log.pdf", replace translator(smcl2pdf)
di as result "DONE"


*==============================================================================
*  OPTIONAL: DHS download for Extension 1 (run once on 20 Nov 2026; frozen in
*  data/raw/). Skipped by default so the data used in the paper stay unchanged.
*  To re-download, set  global redownload 1  before running this file.
*==============================================================================
if "$redownload" == "1" {
    local stamp 20261120
    local api "https://api.dhsprogram.com/rest/dhs"
    
    * 1. indicator values, national level, all surveys
    copy "`api'/data?indicatorIds=RH_PAHC_W_MON&breakdown=national&perpage=5000&f=csv" ///
         "$root/data/raw/dhs_RH_PAHC_W_MON_`stamp'.csv", replace
    * 2. DHS country codes -> ISO3
    copy "`api'/countries?returnFields=DHS_CountryCode,ISO3_CountryCode,CountryName&perpage=1000&f=csv" ///
         "$root/data/raw/dhs_countries_`stamp'.csv", replace
    
    * 3. short log of what was downloaded
    import delimited using "$root/data/raw/dhs_RH_PAHC_W_MON_`stamp'.csv", clear varnames(1) case(lower)
    local nrows = _N
    describe, short
    file open L using "$root/data/raw/dhs_download_log.txt", write replace
    file write L "DHS API download for Extension 1 (care forgone because of cost)" _n
    file write L "Date: `c(current_date)' `c(current_time)'" _n
    file write L "Indicator: RH_PAHC_W_MON (getting money for treatment), breakdown=national" _n
    file write L "Rows downloaded: `nrows'" _n
    file write L "Files: dhs_RH_PAHC_W_MON_`stamp'.csv, dhs_countries_`stamp'.csv" _n
    file close L
    di as result "Downloaded `nrows' rows. Next: do stata/10_extension1_analysis.do"
    
}

*==============================================================================
*  SECTION 4: Extension 1 (DHS financial barrier)
*==============================================================================
/*==============================================================================
  10_extension1_analysis.do   (v5, 20 Nov 2026)
  EXTENSION 1 TEST: care forgone because of cost.
  Question (planned in abstract v4, section 7): does LOW hardship measured by
  the original SDG 3.8.2 hide cost barriers to care that the revised indicator
  picks up?

  Data (09_download_extension1.do, frozen copy in data/raw/):
    DHS indicator RH_PAHC_W_MON: % of women 15-49 for whom "getting money for
    treatment" is a big problem in accessing health care when sick (national,
    standard DHS surveys). This is the only comparable LMIC source (WHO/World
    Bank UHC Global Monitoring Report 2025, s. 2.3). It is a REPORTED FINANCIAL
    BARRIER among women, NOT observed forgone care for the whole population.
  Sample: the 104 same-survey pairs (results/pairs_same_survey.csv from 05),
    each matched to the DHS survey nearest the SDG 3.8.2 survey year within
    +/-2 years (exact year first, then the earlier year) -- the project's rule.
  Pre-specified statistics (nothing else is estimated):
    1. Spearman rho of the barrier with the original (cat10) and the revised
       (fh_total) indicator; n and survey-year gap.
    2. Hidden-need test: among countries in the LOWER half of the original
       indicator, compare the barrier between those in the upper vs lower half
       of the revised indicator (medians, Wilcoxon rank-sum).
    3. Validity checks: same rho with windows 0-3 years; OLS of the barrier on
       each indicator with ln GDP per person held constant (robust SE).
    4. Barrier median by FY2027 income group (descriptive).
  Inclusion rule for the abstract (set before running): report only if
    n >= 30 AND the result is stable across windows AND the hidden-need test
    supports the hypothesis (p < 0.05). Otherwise document as a limitation.

  Run AFTER 05_revision_analysis.do:  cd "<project folder>"; do stata/10_extension1_analysis.do
  Outputs: results/results_e1.csv/.dta, results/e1_sample.csv, results/e1_log.smcl/.log
==============================================================================*/
version 17
clear all
set more off
set varabbrev off

global root "`c(pwd)'"
global in   "$root/data"
global out  "$root/results"
global dhs  "raw/dhs_RH_PAHC_W_MON_20261120.csv"
global dhsc "raw/dhs_countries_20261120.csv"
foreach f in "$in/$dhs" "$in/$dhsc" "$out/pairs_same_survey.csv" "$in/panel.dta" {
    capture confirm file "`f'"
    if _rc {
        di as error "Missing: `f'"
        di as error "cd to the project folder; run 05_revision_analysis.do first (and 09 once for the DHS files)."
        exit 601
    }
}
capture log close
log using "$out/e1_log.smcl", replace

tempname V
postfile `V' str60 key double value using "$out/results_e1.dta", replace
cap program drop put
program define put
    gettoken h 0 : 0
    gettoken key 0 : 0
    post `h' ("`key'") (`0')
end

*--- 1. DHS barrier with ISO3 codes --------------------------------------------
import delimited using "$in/$dhsc", clear varnames(1) case(lower) stringcols(_all)
keep dhs_countrycode iso3_countrycode
rename iso3_countrycode iso3
tempfile C
save `C'
import delimited using "$in/$dhs", clear varnames(1) case(lower)
assert characteristiclabel == "Total" & surveytype == "DHS" & indicatorid == "RH_PAHC_W_MON"
keep dhs_countrycode surveyyear value
merge m:1 dhs_countrycode using `C', keep(match) nogen
rename (surveyyear value) (dhs_year money)
keep iso3 dhs_year money
duplicates drop iso3 dhs_year, force
tempfile D
save `D'
count
put `V' "dhs.n_surveys" r(N)

*--- 2. same-survey pairs + half splits (rule of 05_revision_analysis.do) -------
import delimited using "$out/pairs_same_survey.csv", clear varnames(1) case(lower)
quietly summarize cat10, detail
gen byte old_low  = cat10 < r(p50)
quietly summarize fh_total, detail
gen byte new_high = fh_total >= r(p50)
* ln GDP per person matched to the SDG survey year (+/-2, exact, then earlier)
gen long row = _n
preserve
    use iso3 year gdp_ppp using "$in/panel.dta", clear
    drop if missing(gdp_ppp)
    rename year y_g
    tempfile G
    save `G'
restore
joinby iso3 using `G', unmatched(master)
gen d_g = abs(y_g - svy_year)
bysort row (d_g y_g): keep if _n == 1
replace gdp_ppp = . if missing(d_g) | d_g > 2
gen lngdp = ln(gdp_ppp)
drop _merge d_g y_g
tempfile P
save `P'

*--- 3. match DHS survey nearest to svy_year, for windows 0-3 ------------------
joinby iso3 using `D', unmatched(master)
gen gap = abs(dhs_year - svy_year)
bysort row (gap dhs_year): keep if _n == 1
drop _merge row
tempfile M
save `M'

forvalues w = 0/3 {
    use `M', clear
    keep if gap <= `w'
    count
    put `V' "win`w'.n" r(N)
    spearman money cat10
    put `V' "win`w'.rho_cat10" r(rho)
    put `V' "win`w'.p_cat10" r(p)
    spearman money fh_total
    put `V' "win`w'.rho_fh" r(rho)
    put `V' "win`w'.p_fh" r(p)
}

*--- 4. main sample (+/-2 years) -----------------------------------------------
use `M', clear
keep if gap <= 2
export delimited iso3 svy_year dhs_year gap income cat10 fh_total money old_low new_high lngdp ///
    using "$out/e1_sample.csv", replace
count
put `V' "main.n" r(N)
quietly summarize gap
put `V' "main.gap_mean" r(mean)
count if gap == 0
put `V' "main.n_sameyear" r(N)
quietly summarize dhs_year
put `V' "main.dhs_year_min" r(min)
put `V' "main.dhs_year_max" r(max)
quietly summarize money, detail
put `V' "main.money_median" r(p50)
foreach g in LIC LMC UMC {
    quietly summarize money if income == "`g'", detail
    put `V' "main.`g'.n" r(N)
    put `V' "main.`g'.money_median" r(p50)
}
* hidden-need test
count if old_low == 1
put `V' "hidden.n_oldlow" r(N)
foreach s in 1 0 {
    quietly summarize money if old_low == 1 & new_high == `s', detail
    put `V' "hidden.newhigh`s'.n" r(N)
    put `V' "hidden.newhigh`s'.money_median" r(p50)
}
ranksum money if old_low == 1, by(new_high)
put `V' "hidden.ranksum_p" 2*normprob(-abs(r(z)))
* income-adjusted association (validity check)
foreach v in cat10 fh_total {
    regress money `v' lngdp, vce(robust)
    tempname rt
    matrix `rt' = r(table)
    put `V' "adj.`v'.b"  `rt'[1,1]
    put `V' "adj.`v'.p"  `rt'[4,1]
    put `V' "adj.`v'.lo" `rt'[5,1]
    put `V' "adj.`v'.hi" `rt'[6,1]
    put `V' "adj.`v'.n"  e(N)
    put `V' "adj.`v'.lngdp_p" `rt'[4,2]
}
* Bangladesh
quietly summarize money if iso3 == "BGD"
put `V' "bgd.money" r(mean)
quietly summarize dhs_year if iso3 == "BGD"
put `V' "bgd.dhs_year" r(mean)

postclose `V'
use "$out/results_e1.dta", clear
export delimited using "$out/results_e1.csv", replace
list, clean noobs
log close
translate "$out/e1_log.smcl" "$out/e1_log.log", replace
di as result "Extension 1 done: results/results_e1.csv"


*==============================================================================
*  SECTION 5: v6 additions
*==============================================================================
/*==============================================================================
  12_v6_analysis.do   (v6, 20 Nov 2026)  -- adds results; changes no v3/v4 result
  Corrections from the v5 audit (audit/audit_v5.pdf):
  Issue 1 (RQ3): relative poorest/richest gap with the SAME controls as the main
  absolute-gap model (07_v4_analysis.do, "pov.gap_q.spl": oop lngdp pov_spl,
  robust SE; region variant "spl_reg": + i.reg).
    a. reproduces the v4 log-ratio model (oop lngdp only; key alt.gap_q.ln_ratio)
    b. ln(q1/q5) on oop lngdp pov_spl
    c. ln(q1/q5) on oop lngdp pov_spl i.reg
    d. decomposition: ln(q1) and ln(q5) separately (same controls as b)
    e. levels of q1 and q5 in the sample (to explain absolute vs relative)
    f. SENSITIVITY (new in v6, labelled as such): b. excluding countries whose
       richest-fifth hardship is below 1% (log ratio unstable near zero)
  Interpretation issue (RQ2): store the 95% CI of the 2019 life-expectancy model
    with income (05_revision_analysis.do key B.lnche_gdp), reproduced here.
  Every reproduced value is checked against results_v3/v4 (stops if different).
  Uses results/panel_v4.dta from 07 (run by 00_master.do).
  Output: results/results_v6.csv / .dta, results/v6_log.smcl
==============================================================================*/
version 17
clear all
set more off
set varabbrev off
global root "`c(pwd)'"
global in   "$root/data"
global out  "$root/results"
global hard "raw/gho_FINANCIALHARDSHIP_PROPORTIONOFPOP_20261112.csv"
capture confirm file "$out/panel_v4.dta"
if _rc {
    di as error "Run 00_master.do (or 07_v4_analysis.do) first, from the project folder."
    exit 601
}
capture log close
log using "$out/v6_log.smcl", replace
tempname V
postfile `V' str60 key double value using "$out/results_v6.dta", replace
cap program drop put
program define put
    gettoken h 0 : 0
    gettoken key 0 : 0
    post `h' ("`key'") (`0')
end
cap program drop putb
program define putb
    args h key term
    tempname rt
    matrix `rt' = r(table)
    local c = colnumb(`rt', "`term'")
    post `h' ("`key'.b")  (`rt'[1,`c'])
    post `h' ("`key'.p")  (`rt'[4,`c'])
    post `h' ("`key'.lo") (`rt'[5,`c'])
    post `h' ("`key'.hi") (`rt'[6,`c'])
    post `h' ("`key'.n")  (e(N))
end
* nearestk v k : attach the panel_v4 value of v from the year nearest svy_year,
* within +/- k years (exact year first, then the earlier year)
cap program drop nearestk
program define nearestk
    args v k
    tempvar row
    gen long `row' = _n
    preserve
        use iso3 year `v' using "$out/panel_v4.dta", clear
        drop if missing(`v')
        rename year y_`v'
        tempfile t
        save `t'
    restore
    capture drop `v'
    joinby iso3 using `t', unmatched(master)
    gen double d_`v' = abs(y_`v' - svy_year)
    bysort `row' (d_`v' y_`v'): keep if _n == 1
    replace `v' = . if missing(d_`v') | d_`v' > `k'
    gen byte dist_`v' = d_`v' if !missing(`v')
    drop _merge d_`v' y_`v' `row'
end


use "$in/countries_fy2027.dta", clear
keep iso3 country region income
encode region, gen(reg)
tempfile L
save `L'

cap program drop build_G
program define build_G
    args k L
    import delimited using "$in/$hard", clear varnames(1) case(lower) stringcols(_all)
    keep spatialdim timedim dim1 dim2 numericvalue
    destring timedim numericvalue, replace
    rename spatialdim iso3
    rename timedim svy_year
    merge m:1 iso3 using `L', keep(match) nogen keepusing(iso3)
    keep if svy_year >= 2005
    gen g = ""
    replace g = "q1"     if dim1 == "WEALTHQUINTILE_WQ1"
    replace g = "q5"     if dim1 == "WEALTHQUINTILE_WQ5"
    replace g = "old"    if dim1 == "HOUSEHOLD_COMP_BY_AGE_HH_COMP_ONLY_OLDER_ADULTS"
    replace g = "adults" if dim1 == "HOUSEHOLD_COMP_BY_AGE_HH_COMP_ADULTS"
    replace g = "rur"    if dim1 == "RESIDENCEAREATYPE_RUR"
    replace g = "urb"    if dim1 == "RESIDENCEAREATYPE_URB"
    replace g = "tot"    if dim1 == "FINANCIALHARDSHIPCOMPONENT_COMPONENT_TOTAL"
    keep if g != ""
    collapse (mean) numericvalue, by(iso3 svy_year g)
    reshape wide numericvalue, i(iso3 svy_year) j(g) string
    rename numericvalue* *
    gen gap_q   = q1 - q5
    gen gap_old = old - adults
    gen gap_rur = rur - urb
    merge m:1 iso3 using `L', keep(match) nogen
    foreach v in oop gdp_ppp uhc pov_spl pov_ipl pop65 {
        nearestk `v' `k'
    }
    gen lngdp = ln(gdp_ppp)
end


build_G 2 `L'
keep if !missing(gap_q)
bysort iso3 (svy_year): keep if _n == _N

* check: main absolute-gap model reproduces results_v4 (pov.gap_q.spl)
regress gap_q oop lngdp pov_spl, vce(robust)
putb `V' "check.abs_spl" oop
local chk_abs = _b[oop]
regress gap_q oop lngdp pov_spl i.reg, vce(robust)
putb `V' "check.abs_spl_reg" oop

gen double lnratio = ln(q1/q5) if q5 > 0 & q1 > 0
gen double lnq1 = ln(q1) if q1 > 0
gen double lnq5 = ln(q5) if q5 > 0
count if q5 == 0
put `V' "info.n_q5_zero" r(N)

* a. v4 model (reproduce)
regress lnratio oop lngdp, vce(robust)
putb `V' "ratio.v4_oop_gdp" oop
local chk_ratio = _b[oop]
* b. same controls as the main model
regress lnratio oop lngdp pov_spl, vce(robust)
putb `V' "ratio.spl" oop
putb `V' "ratio.spl_pov" pov_spl
gen byte inR = e(sample)
* c. + region effects
regress lnratio oop lngdp pov_spl i.reg, vce(robust)
putb `V' "ratio.spl_reg" oop
* d. decomposition (same sample as b)
regress lnq1 oop lngdp pov_spl if inR, vce(robust)
putb `V' "lnq1.spl" oop
regress lnq5 oop lngdp pov_spl if inR, vce(robust)
putb `V' "lnq5.spl" oop
regress q1 oop lngdp pov_spl if inR, vce(robust)
putb `V' "q1.spl" oop
regress q5 oop lngdp pov_spl if inR, vce(robust)
putb `V' "q5.spl" oop
* e. levels in the ratio sample
foreach v in q1 q5 {
    quietly summarize `v' if inR, detail
    put `V' "level.`v'.mean" r(mean)
    put `V' "level.`v'.median" r(p50)
    put `V' "level.`v'.min" r(min)
}
quietly summarize q5 if inR, detail
put `V' "level.q5.p10" r(p10)
* f. sensitivity: drop countries with q5 < 1% (labelled sensitivity, not main)
regress lnratio oop lngdp pov_spl if q5 >= 1, vce(robust)
putb `V' "ratio.sens_q5ge1" oop
count if inR & q5 < 1
put `V' "ratio.sens_q5ge1.dropped" r(N)

* --- RQ2: 2019 life expectancy on ln spending with ln GDP (05, Design B) -------
use "$in/panel.dta", clear
keep if year == 2019
merge m:1 iso3 using `L', keep(match) nogen
gen lnche = ln(che_ppp)
gen lngdp = ln(gdp_ppp)
keep if !missing(le_who, lnche)
regress le_who lnche lngdp, vce(robust)
putb `V' "B.lnche_gdp" lnche
local chk_B = _b[lnche]

* --- reproduction checks against the stored v3/v4 results --------------------
preserve
    import delimited using "$out/results_v4.csv", clear varnames(1) asdouble
    quietly summarize value if key == "pov.gap_q.spl.b"
    assert reldif(r(mean), `chk_abs') < 1e-8
    quietly summarize value if key == "alt.gap_q.ln_ratio.b"
    assert reldif(r(mean), `chk_ratio') < 1e-8
    import delimited using "$out/results_v3.csv", clear varnames(1) asdouble
    quietly summarize value if key == "B.lnche_gdp"
    assert reldif(r(mean), `chk_B') < 1e-8
restore
di as result "Reproduction checks passed (v4 gap, v4 ratio, v3 Design B)."

postclose `V'
use "$out/results_v6.dta", clear
export delimited using "$out/results_v6.csv", replace
list, clean noobs
log close
translate "$out/v6_log.smcl" "$out/v6_log.log", replace translator(smcl2log)
capture translate "$out/v6_log.smcl" "$out/v6_log.pdf", replace translator(smcl2pdf)
di as result "DONE"


di as result _n "ALL DONE. Results: results/results_v3.csv, results_v4.csv, results_e1.csv, results_v6.csv"
