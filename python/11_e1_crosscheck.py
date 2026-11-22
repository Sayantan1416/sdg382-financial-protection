"""11_e1_crosscheck.py - independent Python re-computation of Extension 1
(stata/analysis.do, Section 4). Reads the frozen DHS files and results/pairs_same_survey.csv,
recomputes n and Spearman rho for windows 0-3 and the hidden-need medians, and
compares them with results/results_e1.csv. Run after Stata:  python 11_e1_crosscheck.py
Needs pandas, scipy."""
from pathlib import Path
import pandas as pd
from scipy.stats import spearmanr

R = Path(__file__).resolve().parent.parent
d = pd.read_csv(R / "data/raw/dhs_RH_PAHC_W_MON_20261120.csv")
c = pd.read_csv(R / "data/raw/dhs_countries_20261120.csv")
d = d.merge(c[["DHS_CountryCode", "ISO3_CountryCode"]], on="DHS_CountryCode")
d = d.rename(columns={"ISO3_CountryCode": "iso3", "SurveyYear": "dhs_year", "Value": "money"})[["iso3", "dhs_year", "money"]]
p = pd.read_csv(R / "results/pairs_same_survey.csv")
p["old_low"] = p.cat10 < p.cat10.median(); p["new_high"] = p.fh_total >= p.fh_total.median()
m = p.merge(d, on="iso3"); m["gap"] = (m.dhs_year - m.svy_year).abs()
m = m.sort_values(["gap", "dhs_year"]).groupby("iso3").head(1)
S = pd.read_csv(R / "results/results_e1.csv").set_index("key").value
rows = []
for w in range(4):
    s = m[m.gap <= w]
    for k, v in ((f"win{w}.n", len(s)), (f"win{w}.rho_cat10", spearmanr(s.money, s.cat10).statistic),
                 (f"win{w}.rho_fh", spearmanr(s.money, s.fh_total).statistic)):
        rows.append((k, v, S[k]))
s = m[(m.gap <= 2) & m.old_low]
rows += [("hidden.newhigh1.money_median", s[s.new_high].money.median(), S["hidden.newhigh1.money_median"]),
         ("hidden.newhigh0.money_median", s[~s.new_high].money.median(), S["hidden.newhigh0.money_median"])]
out = pd.DataFrame(rows, columns=["key", "python", "stata"])
out["match"] = (out.python - out.stata).abs() < 1e-4
out.to_csv(R / "results/crosscheck_e1.csv", index=False)
print(out.to_string(index=False))
print("ALL MATCH" if out.match.all() else "MISMATCH")
