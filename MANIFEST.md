# What is in this repository (abstract/report PDFs and LaTeX sources are intentionally excluded)

Paper (abstract text is not included in this repository): *Good Health at Low Cost Is Not Financial Protection: Evidence from the Revised SDG 3.8.2*
(HESA extended abstract). Full reproduction instructions: `README.txt` (written for the v6/v7 analysis).

| Item | Location |
|---|---|
| Stata: one do-file, `stata/analysis.do` (run from the repository root; Sections 1-5) | `stata/analysis.do` |
| Python: data download (frozen; do not re-run) | `python/01_download_data.py`, `python/00_download_v4_data.py` |
| Python: cross-checks | `python/08_v4_crosscheck.py`, `python/11_e1_crosscheck.py` |
| Python: figures (Figures 1-4 of the paper) | `python/figures/make_figures_v7.py` (+ `data.py`, `data_v7.py`, `identity.py`, `fig_rq1..4_*.py`) |
| Figure files (pdf/svg/png) | `figures/plots/figRQ1..RQ4*` |
| Figure-vs-Stata validation (61 PASS, 0 FAIL) | `figures/validation/validation_checks_v7.csv` |
| Fonts used in figures (GNU FreeSans, with licence) | `figures/fonts/` |
| Frozen input data (analysis panel, country list, survey list) | `data/*.csv`, `data/*.dta` |
| Frozen raw downloads (WHO GHO, World Bank WDI/OGHIST, DHS) | `data/raw/` |
| Stata results and logs | `results/` |
| Python package versions | `requirements.txt` |

Figures for the paper: `python python/figures/make_figures_v7.py` (needs numpy, pandas, scipy, matplotlib).

Not included on purpose: unrelated side projects (dengue, workforce, mental health), literature PDFs
(copyrighted), and earlier superseded versions V1-V4 (their code is contained in this version).
Code is MIT-licensed (`LICENSE`); the data are public (WHO, World Bank, DHS Program) and keep their providers' terms (check the DHS terms before publishing).
