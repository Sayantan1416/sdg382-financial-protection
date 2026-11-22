"""Extra samples for the v7 figures (one figure per research question).

Builds on data.py: every number a figure shows is either read from the Stata results
files or recomputed here and compared with the value Stata wrote (D.check raises an
error on any mismatch).
"""
import numpy as np
import pandas as pd
from identity import INP
import data as D

HARD = INP / "raw" / "gho_FINANCIALHARDSHIP_PROPORTIONOFPOP_20261112.csv"


# ---------------------------------------------------------------- RQ1
def pairs_by_income():
    """Same-survey pairs with FY2027 income group and country name (05..., s.3)."""
    p = D.pairs().drop(columns=["income"]).merge(D.lmic(), on="iso3", how="left")
    med10, medfh = p["cat10"].median(), p["fh_total"].median()
    p["switch"] = (p["cat10"] < med10) & (p["fh_total"] >= medfh)       # reclass.* in 05
    D.check("Fig RQ1", "pairs switching below->at/above median", int(p["switch"].sum()), int(D.R3["reclass.n_switch_bad"]))
    D.check("Fig RQ1", "low-income switchers", int((p["switch"] & (p.income == "LIC")).sum()), int(D.R3["reclass.lic_switch"]))
    for g in ("LIC", "LMC", "UMC"):
        s = p[p.income == g]
        D.check("Fig RQ1", f"{g}: countries (n)", len(s), int(D.R3[f"bygroup.{g}.n"]))
        for v in ("cat10", "fh_total"):
            D.check("Fig RQ1", f"{g}: median {v}", s[v].median(), D.R3[f"bygroup.{g}.{v}"])
    return p


# ---------------------------------------------------------------- RQ3
GROUPS = {"q1": ("WEALTHQUINTILE_WQ1", None), "q5": ("WEALTHQUINTILE_WQ5", None),
          "old": ("HOUSEHOLD_COMP_BY_AGE_HH_COMP_ONLY_OLDER_ADULTS", None),
          "adults": ("HOUSEHOLD_COMP_BY_AGE_HH_COMP_ADULTS", None),
          "rur": ("RESIDENCEAREATYPE_RUR", None), "urb": ("RESIDENCEAREATYPE_URB", None),
          "h60": ("DEMOGRAPHIC_HEADOFHOUSEHOLD", "AGEGROUP_AGE60+"),
          "hlt60": ("DEMOGRAPHIC_HEADOFHOUSEHOLD", "AGEGROUP_AGELT60")}
GAPS = {"gap_q": ("q1", "q5"), "gap_rur": ("rur", "urb"), "gap_old": ("old", "adults"), "gap_h60": ("h60", "hlt60")}


def group_breakdowns():
    """WHO breakdowns of the 2025 indicator (analysis.do Section 2, section 4):
    LMICs, surveys since 2005, mean by country-year-group, latest survey per gap."""
    r = pd.read_csv(HARD, usecols=["SpatialDim", "TimeDim", "Dim1", "Dim2", "NumericValue"], dtype=str)
    r = r.rename(columns={"SpatialDim": "iso3", "TimeDim": "svy_year"})
    r["svy_year"] = pd.to_numeric(r["svy_year"]); r["v"] = pd.to_numeric(r["NumericValue"])
    r = r[r.iso3.isin(D.lmic().iso3) & (r.svy_year >= 2005)]
    r["g"] = ""
    for g, (d1, d2) in GROUPS.items():
        sel = (r.Dim1 == d1) & ((r.Dim2 == d2) if d2 else True)
        r.loc[sel, "g"] = g
    r = r[r.g != ""]
    w = r.groupby(["iso3", "svy_year", "g"])["v"].mean().unstack("g").reset_index()
    out = {}
    for gap, (a, b) in GAPS.items():
        s = w.dropna(subset=[a, b]).sort_values(["iso3", "svy_year"]).groupby("iso3").tail(1).copy()
        s["gap"] = s[a] - s[b]
        D.check("Fig RQ3", f"{gap}: countries (n)", len(s), int(D.R3[f"groups.{gap}.n"]))
        D.check("Fig RQ3", f"{gap}: median gap", s["gap"].median(), D.R3[f"groups.{gap}.median"], 1e-4)
        D.check("Fig RQ3", f"{gap}: countries with gap > 0", int((s["gap"] > 0).sum()), int(D.R3[f"groups.{gap}.n_pos"]))
        out[gap] = s[["iso3", "svy_year", a, b, "gap"]].rename(columns={a: "dis", b: "adv"})
    # Bangladesh values used in Fig RQ4 must match Stata's bgd_groups.*
    for y in (2016, 2022):
        row = w[(w.iso3 == "BGD") & (w.svy_year == y)].iloc[0]
        for g in ("q1", "q5", "old", "adults", "rur", "urb"):
            D.check("Fig RQ4", f"Bangladesh {y} {g}", row[g], D.R3[f"bgd_groups.{y}.{g}"], 1e-4)
    return out, w


# ---------------------------------------------------------------- RQ2
def design_b_full():
    """Design B sample with income group and the OOP-share rank (05..., s.7)."""
    b, beta = D.design_b()
    b = b.drop(columns=["income"], errors="ignore").merge(D.lmic()[["iso3", "income"]], on="iso3", how="left")
    b["rk_oop"] = b["oop"].rank(ascending=False, method="min")
    D.check("Fig RQ4", "Bangladesh OOP share 2019", b.loc[b.iso3 == "BGD", "oop"].iloc[0], D.R3["B.bgd_oop19"])
    D.check("Fig RQ4", "Bangladesh OOP rank (1 = highest)", int(b.loc[b.iso3 == "BGD", "rk_oop"].iloc[0]), int(D.R3["B.bgd_oop_rank"]))
    D.check("Fig RQ4", "median OOP share 2019", b["oop"].median(), D.R3["B.median_oop19"])
    return b, beta


def est_csv(model, term, k):
    """b, 95% CI, p, n, r2 of a V1 model (analysis.do Section 1 -> results_estimates.csv).
    The lo95/hi95 columns there use the normal approximation (b +/- 1.96 se); Stata's
    regress reports t-based intervals, so the CI is rebuilt here as b +/- t(n-k) se
    (k = number of coefficients incl. constant) -- this matches results_v6.csv."""
    from scipy.stats import t
    e = pd.read_csv(D.OUT / "results_estimates.csv")
    r = e[(e.model == model) & (e.term == term)].iloc[0]
    q = t.ppf(0.975, int(r.n) - k)
    return dict(b=r.b, lo=r.b - q * r.se, hi=r.b + q * r.se, p=r.p, n=int(r.n), r2=r.r2)
