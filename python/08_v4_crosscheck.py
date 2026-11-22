"""
08_v4_crosscheck.py  (V3 project, 18 Nov 2026)
Independent Python re-estimate of the main new v4 models, built from data/
only (does not read Stata output). Compares with results/results_v4.csv.
    python 08_v4_crosscheck.py
Needs: pandas, numpy, statsmodels
Writes: results/crosscheck_v4.csv
"""
from pathlib import Path
import numpy as np
import pandas as pd
import statsmodels.formula.api as smf

ROOT = Path(__file__).resolve().parent.parent
IN, OUT = ROOT / "data", ROOT / "results"

L = pd.read_csv(IN / "countries_fy2027.csv")[["iso3", "region", "income"]]
panel = pd.read_stata(IN / "panel.dta")
w4 = pd.read_csv(IN / "raw" / "wdi_v4_long_20261118.csv")
w4 = w4.pivot_table(index=["iso3", "year"], columns="var", values="value").reset_index()
panel = panel.merge(w4, on=["iso3", "year"], how="left")
panel = panel[panel.iso3.isin(L.iso3)]


def nearest(df, var, k=2):
    """value of var from the panel year nearest svy_year (exact first, then earlier)."""
    p = panel[["iso3", "year", var]].dropna()
    m = df.reset_index().merge(p, on="iso3", how="left")
    m["d"] = (m["year"] - m["svy_year"]).abs()
    m = m.sort_values(["index", "d", "year"]).drop_duplicates("index")
    m.loc[(m.d > k) | m.d.isna(), var] = np.nan
    return m.set_index("index")[var].reindex(df.index)


def latest(df, col):
    d = df.dropna(subset=[col]).sort_values("svy_year")
    return d.groupby("iso3").tail(1).copy()


# ---- WHO group breakdowns (2025 indicator) -------------------------------
h = pd.read_csv(IN / "raw" / "gho_FINANCIALHARDSHIP_PROPORTIONOFPOP_20261112.csv", dtype=str)
h = h[h.SpatialDim.isin(L.iso3)].copy()
h["svy_year"] = h.TimeDim.astype(int)
h["v"] = h.NumericValue.astype(float)
h = h[h.svy_year >= 2005]
code = {"WEALTHQUINTILE_WQ1": "q1", "WEALTHQUINTILE_WQ5": "q5",
        "HOUSEHOLD_COMP_BY_AGE_HH_COMP_ONLY_OLDER_ADULTS": "old",
        "HOUSEHOLD_COMP_BY_AGE_HH_COMP_ADULTS": "adults",
        "RESIDENCEAREATYPE_RUR": "rur", "RESIDENCEAREATYPE_URB": "urb"}
h["g"] = h.Dim1.map(code)
h = h.dropna(subset=["g"])
G = h.groupby(["SpatialDim", "svy_year", "g"]).v.mean().unstack().reset_index()
G = G.rename(columns={"SpatialDim": "iso3"})
G["gap_q"], G["gap_old"], G["gap_rur"] = G.q1 - G.q5, G.old - G.adults, G.rur - G.urb
for v in ["oop", "gdp_ppp", "pov_spl"]:
    G[v] = nearest(G, v)
G["lngdp"] = np.log(G.gdp_ppp)

# ---- national surveys -----------------------------------------------------
S = pd.read_stata(IN / "fp_surveys.dta").rename(columns={"year": "svy_year"})
S = S[(S.svy_year >= 2005) & S.iso3.isin(L.iso3)].drop(columns=["region", "income"])
S = S.merge(L, on="iso3")
for v in ["oop", "gdp_ppp", "uhc", "pov_spl"]:
    S[v] = nearest(S, v)
S["lngdp"] = np.log(S.gdp_ppp)

rows = []


def fit(key, formula, d, term):
    d = d.dropna(subset=[c for c in d.columns if c in formula])
    r = smf.ols(formula, d).fit(cov_type="HC1")
    rows.append({"key": key, "b": r.params[term], "p": r.pvalues[term], "n": int(r.nobs)})


for g in ["gap_q", "gap_old", "gap_rur"]:
    d = latest(G, g)
    fit(f"pov.{g}.base", f"{g} ~ oop + lngdp", d.dropna(subset=["oop", "lngdp"]), "oop")
    fit(f"pov.{g}.spl", f"{g} ~ oop + lngdp + pov_spl",
        d.dropna(subset=["oop", "lngdp", "pov_spl"]), "oop")
for v in ["fh_large", "fh_impov", "fh_total"]:
    d = latest(S, v).dropna(subset=["oop", "lngdp", "uhc", "pov_spl"])
    fit(f"comp.{v}.spl", f"{v} ~ oop + lngdp + uhc + pov_spl + C(region)", d, "oop")

out = pd.DataFrame(rows)
st = pd.read_csv(OUT / "results_v4.csv").set_index("key").value
out["stata_b"] = [st.get(k + ".b") for k in out.key]
out["stata_n"] = [st.get(k + ".n") for k in out.key]
out["abs_diff_b"] = (out.b - out.stata_b).abs()
out.to_csv(OUT / "crosscheck_v4.csv", index=False)
print(out.round(4).to_string(index=False))
