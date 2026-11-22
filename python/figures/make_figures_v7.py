"""Figures for abstract v7: one figure per research question.

    python figures/src/make_figures_v7.py
Reads the Stata outputs (results/results_v3.csv, results_v4.csv, results_v6.csv,
results_estimates.csv, pairs_same_survey.csv) and the frozen inputs; writes
figures/plots/figRQ1..RQ4.{pdf,svg,png} and figures/validation/validation_checks_v7.csv.
Stops if any recomputed number differs from Stata."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import pandas as pd
import identity as I
I.use()
import data as D
import fig_rq1_tornado, fig_rq2_health, fig_rq3_groups, fig_rq4_bangladesh

made = [fig_rq1_tornado.fig_rq1(), fig_rq2_health.fig_rq2(), fig_rq3_groups.fig_rq3(), fig_rq4_bangladesh.fig_rq4()]
chk = pd.DataFrame(D.CHECKS).drop_duplicates(["figure", "check"])
chk.to_csv(I.VAL / "validation_checks_v7.csv", index=False)
print(f"{made} written to figures/plots/ (pdf, svg, png)")
print(f"{len(chk)} checks against Stata: {(chk.result == 'PASS').sum()} PASS, {(chk.result != 'PASS').sum()} FAIL")
if (chk.result != "PASS").any():
    sys.exit(1)
