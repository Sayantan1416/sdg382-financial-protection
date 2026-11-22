"""Load the unchanged Stata outputs/inputs and rebuild each analysis sample.

Every sample-building step mirrors the Stata do-files line by line (cited below).
Each statistic that a figure shows is recomputed here and compared with the value
Stata wrote to results_v3.csv / results_v4.csv / results_v6.csv; check() records the comparison and
raises an error if they differ, so a figure can never silently drift from Stata.
"""
import numpy as np
import pandas as pd
from scipy.stats import spearmanr
from identity import OUT, INP

CHECKS = []          # rows for validation/validation_checks.csv

def check(figure, what, ours, stata, tol=1e-6):
    ok = (ours == stata) if isinstance(stata, (int, np.integer)) else abs(float(ours) - float(stata)) <= tol
    CHECKS.append(dict(figure=figure, check=what, python=ours, stata=stata,
                       result="PASS" if ok else "FAIL"))
    if not ok:
        raise AssertionError(f"[{figure}] {what}: python={ours} stata={stata}")

def results():
    r3 = pd.read_csv(OUT / "results_v3.csv").set_index("key")["value"]
    r4 = pd.read_csv(OUT / "results_v4.csv").set_index("key")["value"]
    r6 = pd.read_csv(OUT / "results_v6.csv").set_index("key")["value"]   # v6: analysis.do Section 5
    return r3, r4, r6

R3, R4, R6 = results()

def lmic():
    return pd.read_csv(INP / "countries_fy2027.csv")[["iso3", "country", "income"]]

def nearest(df, var, k=2):
    """Panel value of `var` from the year nearest svy_year within +/-k
    (exact year first, then the earlier year) -- Stata program nearest2."""
    pn = pd.read_csv(INP / "panel.csv")[["iso3", "year", var]].dropna()
    m = df.merge(pn.rename(columns={"year": "_y"}), on="iso3", how="left")
    m["_d"] = (m["_y"] - m["svy_year"]).abs()
    m = m.sort_values(["_d", "_y"]).groupby(["iso3", "svy_year"], as_index=False).head(1)
    m.loc[~(m["_d"] <= k), var] = np.nan
    return df.merge(m[["iso3", "svy_year", var]], on=["iso3", "svy_year"], how="left")

# ---------------------------------------------------------------- RQ1 samples
def pairs():
    """Latest survey since 2005 with both indicators (analysis.do Section 2, s.3)."""
    p = pd.read_csv(OUT / "pairs_same_survey.csv")
    check("all", "same-survey pairs (n)", len(p), int(R3["pairs.n"]))
    return p

def pairs_gdp():
    """Pairs with GDP per person matched within 2 years (grad.* sample, n = 102)."""
    p = nearest(pairs(), "gdp_ppp").dropna(subset=["gdp_ppp"])
    p["lngdp"] = np.log(p["gdp_ppp"])
    check("Fig 1", "countries with GDP (n)", len(p), int(R3["grad.n"]))
    for v in ("cat10", "fh_total"):
        check("Fig 1", f"Spearman {v} vs ln GDP", spearmanr(p[v], p["lngdp"]).statistic, R3[f"grad.{v}.rho"])
    return p

# ---------------------------------------------------------------- RQ2 samples
def design_b():
    """2019 cross-section: life expectancy on ln health spending per person
    (analysis.do Section 2, s.7). Residual = years above/below prediction."""
    pn = pd.read_csv(INP / "panel.csv")
    b = pn[pn["year"] == 2019].merge(lmic()[["iso3"]], on="iso3")
    b["lnche"], b["lngdp"] = np.log(b["che_ppp"]), np.log(b["gdp_ppp"])
    b = b.dropna(subset=["le_who", "lnche"]).copy()
    X = np.column_stack([np.ones(len(b)), b["lnche"]])
    beta, *_ = np.linalg.lstsq(X, b["le_who"], rcond=None)
    b["pred"] = X @ beta
    b["res"] = b["le_who"] - b["pred"]
    r2 = 1 - (b["res"] ** 2).sum() / ((b["le_who"] - b["le_who"].mean()) ** 2).sum()
    g = b.dropna(subset=["lngdp"]).copy()                           # + ln GDP model
    Xg = np.column_stack([np.ones(len(g)), g["lnche"], g["lngdp"]])
    bg, *_ = np.linalg.lstsq(Xg, g["le_who"], rcond=None)
    b["res_g"] = np.nan; b.loc[g.index, "res_g"] = g["le_who"] - Xg @ bg
    b["rank"] = b["res"].rank(ascending=False, method="min")          # egen rank(), field
    b["rank_g"] = b["res_g"].rank(ascending=False, method="min")
    bd = b[b.iso3 == "BGD"].iloc[0]
    check("Fig 3", "Design B countries (n)", len(b), int(R3["B.n"]))
    check("Fig 3", "Design B R-squared", r2, R3["B.r2"])
    check("Fig 3", "Design B + GDP countries (n)", len(g), int(R3["B.n_gdp"]))
    check("Fig 3", "Bangladesh residual, years", bd["res"], R3["B.bgd_res"])
    check("Fig 3", "Bangladesh rank (1 = best)", int(bd["rank"]), int(R3["B.bgd_rank"]))
    check("Fig 3", "Bangladesh residual with GDP", bd["res_g"], R3["B.bgd_res_g"])
    check("Fig 3", "Bangladesh rank with GDP", int(bd["rank_g"]), int(R3["B.bgd_rank_g"]))
    check("Fig 3", "Bangladesh life expectancy 2019", bd["le_who"], R3["B.bgd_le"])
    check("Fig 3", "Bangladesh spending per person", bd["che_ppp"], R3["B.bgd_che"], 1e-4)
    return b, beta

def latest_surveys(var):
    """Latest survey since 2005 with `var` for each FY2027 LMIC (05..., sample S)."""
    s = pd.read_csv(INP / "fp_surveys.csv")
    s = s[s["year"] >= 2005].drop(columns=["income", "country"], errors="ignore")
    s = s.merge(lmic(), on="iso3").rename(columns={"year": "svy_year"})
    s = s.dropna(subset=[var]).sort_values(["iso3", "svy_year"]).groupby("iso3").tail(1)
    return s

def efficiency(var):
    """Life-expectancy residual vs hardship (05..., 'efficiency against hardship')."""
    b, _ = design_b()
    e = latest_surveys(var).merge(b[["iso3", "res", "res_g", "le_who", "che_ppp"]], on="iso3")
    check("Fig 3", f"{var}: countries (n)", len(e), int(R3[f"eff.{var}.n"]))
    check("Fig 3", f"{var}: Spearman residual vs hardship", spearmanr(e["res"], e[var]).statistic, R3[f"eff.{var}.rho"])
    eg = e.dropna(subset=["res_g"])
    check("Fig 3", f"{var}: Spearman residual(+GDP) vs hardship", spearmanr(eg["res_g"], eg[var]).statistic, R3[f"eff.{var}.rho_g"])
    med = e[var].median()
    check("Fig 3", f"{var}: median hardship", med, R3[f"eff.{var}.median"])
    check("Fig 3", f"{var}: over-performers (>3 y) below median", int(((e.res > 3) & (e[var] < med)).sum()), int(R3[f"eff.{var}.over_low"]))
    check("Fig 3", f"{var}: over-performers (>3 y) at/above median", int(((e.res > 3) & (e[var] >= med)).sum()), int(R3[f"eff.{var}.over_high"]))
    return e, med

def est(key, R=R4):
    """b, lo, hi, p, n of one Stata estimate (putb output)."""
    return {k: R[f"{key}.{k}"] for k in ("b", "lo", "hi", "p", "n")}
