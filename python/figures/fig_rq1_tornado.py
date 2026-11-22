"""Figure RQ1 - tornado: original vs revised SDG 3.8.2 for every country, by income group.

Each row is one of the 104 LMICs with both indicators from the same survey
(analysis.do Section 2, section 3). Bars to the left: original indicator (OOP > 10% of
budget); bars to the right: revised 2025 indicator (total financial hardship). Rows are
sorted by the revised value within each FY2027 income group. Dashed lines: group medians
(checked against Stata's bygroup.*). Marked rows: countries below the all-country median
on the original but at or above it on the revised indicator (reclass.* in Stata)."""
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
from matplotlib.lines import Line2D
import identity as I
import data as D
import data_v7 as V

G = 7.5                    # half-width of the central gap that holds the country code
XL, XR = -45, 66           # data limits (left = original, right = revised)


def fig_rq1():
    p = V.pairs_by_income()
    groups = [("LIC", "Low income"), ("LMC", "Lower-middle income"), ("UMC", "Upper-middle income")]
    nmax = max((p.income == g).sum() for g, _ in groups)
    fig = plt.figure(figsize=(I.W, 5.55))
    left0, width, gapw = 0.010, 0.314, 0.019
    for k, (g, name) in enumerate(groups):
        s = p[p.income == g].sort_values("fh_total", ascending=False).reset_index(drop=True)
        ax = fig.add_axes([left0 + k * (width + gapw), 0.150, width, 0.730])
        for i, r in s.iterrows():
            bgd = r.iso3 == "BGD"
            ax.barh(i, -r.cat10, left=-G, height=0.74, color=I.ORIG, ec=I.BGD if bgd else "none", lw=0.8 if bgd else 0)
            ax.barh(i, r.fh_total, left=G, height=0.74, color=I.REV, ec=I.BGD if bgd else "none", lw=0.8 if bgd else 0)
            ax.text(0, i, r.iso3, ha="center", va="center", fontsize=4.9,
                    color=I.BGD if bgd else (I.INK if r.switch else I.INK2),
                    fontweight="bold" if (bgd or r.switch) else "normal")
            if r.switch:
                ax.plot(-G - r.cat10 - 2.2, i, marker="o", ms=1.9, color=I.INK, mew=0)
        n = len(s)
        m10, mfh = D.R3[f"bygroup.{g}.cat10"], D.R3[f"bygroup.{g}.fh_total"]
        for x, col, val in ((-G - m10, I.ORIG_D, m10), (G + mfh, I.REV_D, mfh)):
            ax.plot([x, x], [-0.9, n - 0.4], ls=(0, (2.2, 1.6)), lw=0.8, color=col, zorder=4)
            ax.text(x, -1.25, f"{val:.1f}", ha="center", va="bottom", fontsize=7.2, fontweight="bold", color=col)
        ax.set_xlim(XL, XR); ax.set_ylim(nmax - 0.3, -2.9)
        ax.set_yticks([])
        for sp in ("left",):
            ax.spines[sp].set_visible(False)
        ticks = [-G - 30, -G - 15, -G, G, G + 20, G + 40]
        ax.set_xticks(ticks); ax.set_xticklabels(["30", "15", "0", "0", "20", "40"], fontsize=6.4)
        ax.axvline(-G, color=I.INK3, lw=0.5); ax.axvline(G, color=I.INK3, lw=0.5)
        for x in ticks:
            if abs(x) != G:
                ax.axvline(x, color=I.GRID, lw=0.5, zorder=0)
        # panel heading
        ax.text(0, 1.085, name, transform=ax.get_xaxis_transform(), ha="center", fontsize=8.4, fontweight="bold")
        nsw = int(s.switch.sum())
        sub = f"n = {n}" + (f"  ·  {nsw} switch" if nsw else "")
        ax.text(0, 1.05, sub, transform=ax.get_xaxis_transform(), ha="center", fontsize=6.9, color=I.INK2)
        ax.text(-G - 1, 1.012, "◂ Original", transform=ax.get_xaxis_transform(), ha="right", fontsize=6.6,
                color=I.ORIG_D, fontweight="bold")
        ax.text(G + 1, 1.012, "Revised ▸", transform=ax.get_xaxis_transform(), ha="left", fontsize=6.6,
                color=I.REV_D, fontweight="bold")
        if g == "LIC":     # use the empty space under the shortest panel for the key result
            ax.text(0, n + 3.2, f"Median rank across groups\nOriginal: lowest (3rd of 3)\nRevised: highest (1st of 3)",
                    ha="center", va="top", fontsize=6.9, color=I.INK, linespacing=1.45,
                    bbox=dict(boxstyle="round,pad=0.5", fc=I.REV_T, ec="none"))
    fig.text(0.5, 0.104, "Population affected (%)", ha="center", fontsize=7.6, color=I.INK)
    h = [Patch(fc=I.ORIG, label="Original SDG 3.8.2: OOP > 10% of budget"),
         Patch(fc=I.REV, label="Revised SDG 3.8.2 (2025): total financial hardship"),
         Line2D([], [], ls=(0, (2.2, 1.6)), color=I.INK2, lw=0.8, label="Group median (value on top)"),
         Line2D([], [], ls="", marker="o", ms=2.6, color=I.INK, label="Below median on original, at/above on revised"),
         Patch(fc="white", ec=I.BGD, lw=0.9, label="Bangladesh (2016)")]
    fig.legend(handles=h, loc="lower center", bbox_to_anchor=(0.5, 0.030), ncol=3, fontsize=6.6,
               columnspacing=1.2, handlelength=1.6, handletextpad=0.5)
    I.note(fig, I.m(f"{len(p)} LMICs, latest survey since 2005 with both indicators; rows sorted by the revised value; ISO3 codes.\n"
                    f"Spearman ρ with ln GDP per person: original +{D.R3['grad.cat10.rho']:.2f}, "
                    f"revised {D.R3['grad.fh_total.rho']:.2f} (n = {int(D.R3['grad.n'])})."), y=0.004)
    return I.save(fig, "figRQ1_tornado")
