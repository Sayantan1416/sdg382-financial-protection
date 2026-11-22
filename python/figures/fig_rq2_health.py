"""Figure RQ2 - Good health at low cost vs financial protection (one figure, two panels).

(a) 2019 cross-section (Design B, analysis.do Section 2 s.7 / analysis.do Section 1 B1, B3):
    life expectancy on ln health spending per person, OLS fit with its 95% confidence band
    (HC1 robust covariance, as in Stata's vce(robust)); coefficients and CIs read from
    results_estimates.csv. Marker shade/shape = FY2027 income group.
(b) Life-expectancy residual from (a) ("years above/below what spending predicts")
    against the revised SDG 3.8.2 total, latest survey since 2005; Spearman rho checked
    against Stata (eff.*)."""
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from scipy.stats import spearmanr
import identity as I
import data as D
import data_v7 as V


def band(b, x):
    """Fitted line and 95% CI band with HC1 covariance (Stata vce(robust))."""
    X = np.column_stack([np.ones(len(b)), b["lnche"]])
    y = b["le_who"].to_numpy()
    XtX = np.linalg.inv(X.T @ X)
    beta = XtX @ X.T @ y
    e = y - X @ beta
    n, k = X.shape
    V_ = XtX @ (X.T * e ** 2) @ X @ XtX * n / (n - k)
    from scipy.stats import t
    Xg = np.column_stack([np.ones(len(x)), x])
    fit = Xg @ beta
    se = np.sqrt(np.einsum("ij,jk,ik->i", Xg, V_, Xg))
    q = t.ppf(0.975, n - k)
    return fit, fit - q * se, fit + q * se, beta, np.sqrt(V_[1, 1])


def fig_rq2():
    b, _ = V.design_b_full()
    e, med = D.efficiency("fh_total")
    e = e.merge(D.lmic()[["iso3", "income"]], on="iso3", how="left", suffixes=("_s", ""))
    B1, B3 = V.est_csv("B1 LE ~ lnche", "lnche", 2), V.est_csv("B3 LE ~ lnche + lngdp", "lnche", 3)
    D.check("Fig RQ2", "B3 95% CI lower (t-based) = results_v6", B3["lo"], D.R6["B.lnche_gdp.lo"], 1e-6)
    D.check("Fig RQ2", "B3 95% CI upper (t-based) = results_v6", B3["hi"], D.R6["B.lnche_gdp.hi"], 1e-6)
    xs = np.linspace(b["lnche"].min() - 0.05, b["lnche"].max() + 0.05, 200)
    fit, lo, hi, beta, se = band(b, xs)
    D.check("Fig RQ2", "B1 slope (python vs Stata)", beta[1], B1["b"], 1e-6)
    D.check("Fig RQ2", "B1 robust SE (python HC1 vs Stata)", se,
            float(D.pd.read_csv(D.OUT / "results_estimates.csv").query("model == 'B1 LE ~ lnche'").se.iloc[0]), 1e-6)

    fig = plt.figure(figsize=(I.W, 3.35))
    axa = fig.add_axes([0.075, 0.25, 0.47, 0.63])
    axb = fig.add_axes([0.655, 0.25, 0.33, 0.63])

    # ---- (a) regression
    axa.fill_between(np.exp(xs), lo, hi, color=I.REV_T, lw=0, zorder=1)
    axa.plot(np.exp(xs), fit, color=I.REV, lw=1.4, zorder=2)
    for g, st in I.INCOME.items():
        s = b[(b.income == g) & (b.iso3 != "BGD")]
        axa.scatter(s["che_ppp"], s["le_who"], s=13, marker=st["marker"], fc=st["fill"], ec=I.INK2, lw=0.35,
                    alpha=0.9, zorder=3)
    bd = b[b.iso3 == "BGD"].iloc[0]
    axa.plot([bd.che_ppp] * 2, [bd.pred, bd.le_who], color=I.BGD, lw=1.0, zorder=4)
    axa.scatter(bd.che_ppp, bd.le_who, s=46, marker="D", fc=I.BGD, ec="white", lw=0.6, zorder=5)
    axa.annotate(I.m(f"Bangladesh: {bd.le_who:.1f} years,\n+{bd.res:.1f} above prediction\n"
                     f"(rank {int(D.R3['B.bgd_rank'])} of {int(D.R3['B.n'])})"),
                 (bd.che_ppp, bd.le_who), xytext=(36, 79.5), textcoords="data", fontsize=6.7,
                 color=I.BGD, ha="left", va="top", arrowprops=dict(arrowstyle="-", color=I.BGD, lw=0.6))
    axa.set_xscale("log"); axa.set_ylim(41, 82)
    axa.set_xticks([50, 100, 200, 500, 1000, 2000]); axa.set_xticklabels(["50", "100", "200", "500", "1,000", "2,000"])
    axa.set_xlabel("Health spending per person, 2019 (PPP $, log scale)")
    axa.set_ylabel("Life expectancy at birth, 2019 (years)")
    I.ygrid(axa)
    pf = lambda p: "p < 0.001" if p < 0.001 else f"p = {p:.2f}"
    M = lambda x: I.m(f"{x:.2f}")
    txt = (f"Spending only:  {M(B1['b'])} years per log-unit\n"
           f"   95% CI {M(B1['lo'])} to {M(B1['hi'])}, {pf(B1['p'])}, R² = {B1['r2']:.2f}, n = {B1['n']}\n"
           f"+ ln GDP per person:  {M(B3['b'])}\n"
           f"   95% CI {M(B3['lo'])} to {M(B3['hi'])}, {pf(B3['p'])}, n = {B3['n']}")
    axa.text(0.985, 0.035, txt, transform=axa.transAxes, ha="right", va="bottom", fontsize=6.5, color=I.INK,
             linespacing=1.35, bbox=dict(boxstyle="round,pad=0.45", fc=(1, 1, 1, 0.8), ec=I.RULE, lw=0.5))
    I.tag(axa, "a", "More spending, longer life, until income is added")

    # ---- (b) over-performance vs hardship
    axb.axvline(0, color=I.INK3, lw=0.6, zorder=1)
    axb.axhline(med, color=I.REV, lw=0.7, ls=(0, (2.2, 1.6)), zorder=1)
    for g, st in I.INCOME.items():
        s = e[(e.income == g) & (e.iso3 != "BGD")]
        axb.scatter(s["res"], s["fh_total"], s=13, marker=st["marker"], fc=st["fill"], ec=I.INK2, lw=0.35,
                    alpha=0.9, zorder=3)
    be = e[e.iso3 == "BGD"].iloc[0]
    axb.scatter(be.res, be.fh_total, s=46, marker="D", fc=I.BGD, ec="white", lw=0.6, zorder=5)
    axb.annotate(f"Bangladesh {int(be.svy_year)}", (be.res, be.fh_total), xytext=(-4, 9), textcoords="offset points",
                 fontsize=6.7, color=I.BGD, ha="right")
    rho = spearmanr(e["res"], e["fh_total"]).statistic
    axb.text(0.97, 0.97, I.m(f"Spearman ρ = {rho:.2f} (revised)\n"
                             f"ρ = {D.R3['eff.cat10.rho']:.2f} (original)\nn = {len(e)}"),
             transform=axb.transAxes, ha="right", va="top", fontsize=6.6, linespacing=1.35,
             bbox=dict(boxstyle="round,pad=0.4", fc="white", ec=I.RULE, lw=0.5))
    axb.text(-14.8, med + 1.2, f"median {med:.1f}%", fontsize=6.3, color=I.REV_D)
    axb.set_xlim(-15.5, 11.5)
    axb.set_xlabel("Life expectancy above (+) or below (−)\nwhat spending predicts (years)")
    axb.set_ylabel("Revised SDG 3.8.2: total hardship (%)")
    I.ygrid(axb)
    I.tag(axb, "b", "Healthier than expected ≠ protected", x=-0.06)

    h = [Line2D([], [], ls="", marker=st["marker"], mfc=st["fill"], mec=I.INK2, mew=0.4, ms=4.2, label=st["label"])
         for st in I.INCOME.values()] + \
        [Line2D([], [], color=I.REV, lw=1.4, label="OLS fit, 95% CI"),
         Line2D([], [], ls="", marker="D", mfc=I.BGD, mec="white", ms=5, label="Bangladesh")]
    fig.legend(handles=h, loc="lower center", bbox_to_anchor=(0.5, 0.0), ncol=5, fontsize=6.7, columnspacing=1.1,
               handletextpad=0.35)
    return I.save(fig, "figRQ2_health_protection")
