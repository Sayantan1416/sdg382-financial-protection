TITLE    : Good Health at Low Cost Is Not Financial Protection:
           Evidence from the Revised SDG 3.8.2

Reproducibility package (Stata analysis, Python figures, frozen data).

------------------------------------------------------------------------------
HOW TO REPRODUCE EVERYTHING  (any PC, any folder; no OneDrive or fixed paths)
------------------------------------------------------------------------------
IMPORTANT: type the commands below into the Stata command window BY HAND, one line
at a time, and press Enter after each. Do not paste several lines at once: pasted
multi-line text runs as separate commands and can fail or run the wrong thing.

STEP 1  Download/unzip the repository anywhere (e.g. C:\Stata\). Do not rename subfolders.

STEP 2  Stata 17 or newer:
            cd "C:\...\<repository folder>"      <- your path
            do stata\analysis.do
        This runs, in order (about 2 minutes):
            Section 1  V1 analysis
            Section 2  v3 numbers (+ pairs_same_survey.csv)
            Section 3  v4 numbers
            Section 4  Extension 1 test (DHS)
            Section 5  v6 additions (log-ratio models, sensitivity, CI of the 2019
                       life-expectancy model)
        Last line on screen: "ALL DONE. Results: ... results_v6.csv".
        Packages: ftools, require, reghdfe, estout (SSC). stata/analysis.do installs any
        that are missing, so internet is needed ONCE; afterwards none is needed.
        Versions used are written to results\run_info_packages.log.
        Error "Cannot find ..." = Stata is not in the project folder: cd there first.

STEP 3  Python 3.10+ (optional checks and figures):
            python -m pip install -r requirements.txt
            python python\11_e1_crosscheck.py          Extension 1 re-computed (expects ALL MATCH)
            python python\08_v4_crosscheck.py          v4 models re-estimated
            python python\figures\make_figures_v7.py  Figures 1-4 (expects 61 PASS, 0 FAIL)
        Figures are written to figures\plots\ as PDF, SVG and 600-dpi PNG. The
        script reads the Stata outputs and stops if any number differs from Stata.
        Fonts are bundled in figures\fonts\ (GNU FreeSans).

DO NOT RUN to reproduce (they re-download data, and the sources change over time):
        01_download_data.py, 00_download_v4_data.py, and the optional DHS download block in analysis.do.
        The dated files in data\raw\ are the data used.

------------------------------------------------------------------------------
FOLDER TREE
  stata\analysis.do            the single Stata do-file (Sections 1-5; run from the repository root)
  python\                      all Python code
     01_download_data.py, 00_download_v4_data.py   original download scripts (frozen data)
     08_v4_crosscheck.py, 11_e1_crosscheck.py        Python replications of Stata results
     figures\                  code for Figures 1-4 (make_figures_v7.py; identity.py = style)
  figures\plots\             the four figures (pdf, svg, png)
  figures\fonts\              bundled fonts + licence (GNU FreeSans)
  figures\validation\         validation_checks_v7.csv (figures vs Stata)
  data\                      countries_fy2027, panel, fp_surveys (.csv/.dta)
  data\raw\                  frozen downloads: WHO GHO, WDI, OGHIST (12/18 Nov 2026),
                               DHS RH_PAHC_W_MON + DHS country codes (20 Nov 2026)
  results\                     every result written by the scripts (results_*.csv/.dta,
                               logs, tables)
  requirements.txt             Python package versions used

KEY DEFINITIONS AND LIMITS
  - Survey values matched to other data from the survey year, or the nearest year
    within +/-2 (earlier year if tied). Extension 1 uses the same rule for DHS surveys.
  - Large spending (2025 indicator): OOP above 40% but below 100% of the household
    budget net of the societal poverty line; impoverishing: above 100%, or any OOP
    by households already below the line.
  - The log ratio ln(q1/q5) is undefined where the richest fifth has zero hardship
    (10 countries) and unstable where it is close to zero.
  - The DHS measure is a reported financial barrier among women 15-49, not forgone
    care for the whole population; it is the only comparable LMIC source.
  - All results are associations.

DATA USE
  All data are public (WHO GHO/GHED, World Bank WDI and OGHIST, DHS Program API).

DHS CITATION (required by the DHS Program API terms and conditions)
  The DHS Program Indicator Data API, The Demographic and Health Surveys (DHS) Program.
  ICF. Originally funded by the United States Agency for International Development
  (USAID). Available from api.dhsprogram.com. [Accessed 11-20-2026]
  (The DHS files in data/raw/ were downloaded on 20 November 2026; citation and version
  can be queried at https://api.dhsprogram.com/rest/dhs/info/citation and .../info/version.)

LICENSE
  The code (stata/ and python/) is released under the MIT License (see LICENSE).
  This licence covers the code only. The data in data/ and the results derived from
  it come from WHO, the World Bank and the DHS Program and remain subject to those
  providers' terms. The bundled fonts (figures/fonts/) are GNU FreeSans under their
  own licence (figures/fonts/FreeFont-LICENSE.txt).
