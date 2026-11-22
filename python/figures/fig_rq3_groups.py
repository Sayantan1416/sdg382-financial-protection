"""Figure RQ3 - Who bears hardship: four group comparisons under the 2025 indicator.

Each panel is one WHO breakdown of the revised SDG 3.8.2 (analysis.do Section 2,
section 4; latest survey since 2005 per country). Every vertical stroke is one country,
running from the advantaged group's hardship to the disadvantaged group's; countries are
sorted by the gap. Common 0-100% scale so the four gaps can be compared directly.
Badges: OOP coefficient on the gap -- main model (ln GDP + societal poverty headcount,
results_v4.csv pov.*.spl) for three gaps; for the head-of-household gap no poverty-adjusted
model exists, so the ln-GDP-only model from results_v3.csv is shown and flagged."""
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
import identity as I
import data as D
import data_v7 as V

PANELS = [("gap_q", "Poorest vs richest fifth", "Poorest fifth", "Richest fifth", "pov.gap_q.spl", "robust"),
          ("gap_rur", "Rural vs urban residents", "Rural", "Urban", "pov.gap_rur.spl", "fragile"),
          ("gap_old", "Older-only vs working-age households", "Older-only", "Working-age", "pov.gap_old.spl", "robust"),
          ("gap_h60", "Head aged 60+ vs younger head", "Head 60+", "Head < 60", None, "none")]
DIS, ADV = I.REV, "#CFC8BA"


def fig_rq3():
    G, _ = V.group_breakdowns()
    fig, axs = plt.subplots(2, 2, figsize=(I.W, 4.55), sharey=True)
    fig.subplots_adjust(left=0.075, right=0.99, top=0.885, bottom=0.135, hspace=0.62, wspace=0.07)
    for ax, (gap, title, dlab, alab, key, rob) in zip(axs.flat, PANELS):
        s = G[gap].sort_values("gap").reset_index(drop=True)
        n, npos, med = len(s), int((s.gap > 0).sum()), s.gap.median()
        for i, r in s.iterrows():
            bgd = r.iso3 == "BGD"
            col = I.BGD if bgd else (DIS if r.gap > 0 else I.INK3)
            ax.plot([i, i], [r.adv, r.dis], color=col, lw=1.5 if bgd else 0.95, alpha=1 if bgd else 0.55,
                    solid_capstyle="round", zorder=2 + bgd)
        ax.scatter(s.index, s.adv, s=5, color=ADV, ec=I.ORIG_D, lw=0.25, zorder=4)
        ax.scatter(s.index, s.dis, s=6, color=DIS, ec=I.REV_D, lw=0.25, zorder=4)
        b = s[s.iso3 == "BGD"]
        if len(b):
            i, r = b.index[0], b.iloc[0]
            ax.scatter([i, i], [r.adv, r.dis], s=22, marker="D", color=I.BGD, ec="white", lw=0.5, zorder=6)
            ax.annotate(f"BGD {int(r.svy_year)}", (i, (r.dis + r.adv) / 2), xytext=(-5, 0), textcoords="offset points", ha="right",
                        va="center", fontsize=6.3, color=I.BGD, fontweight="bold", zorder=7,
                        bbox=dict(boxstyle="round,pad=0.15", fc="white", ec="none", alpha=0.85))
        ax.set_xlim(-2, n + 1); ax.set_ylim(0, 104)
        ax.set_xticks([])
        ax.spines["bottom"].set_color(I.RULE)
        ax.text(0.5, -0.07, f"{n} countries, sorted by gap →", transform=ax.transAxes, ha="center", va="top",
                fontsize=6.4, color=I.INK3)
        I.ygrid(ax)
        # heading: what share of countries the disadvantaged group is worse off, and the median gap
        ax.text(0, 1.17, title, transform=ax.transAxes, fontsize=8.3, fontweight="bold", color=I.INK)
        ax.text(0, 1.055, f"{dlab} worse off in {npos} of {n} countries  ·  median gap {med:.1f} pp",
                transform=ax.transAxes, fontsize=6.9, color=I.INK2)
        # OOP badge
        if key:
            m = D.est(key)
            pv = "p < 0.001" if m["p"] < 0.001 else f"p = {m['p']:.3f}"
            badge = f"+1 pt OOP share → gap {m['b']:+.2f} pp ({pv})"
            note = {"robust": "holds in all checks", "fragile": "not robust to outliers"}[rob]
        else:
            b3 = D.R3
            badge = I.m(f"+1 pt OOP share → gap {b3['groups.gap_h60.reg.b']:+.2f} pp (p = {b3['groups.gap_h60.reg.p']:.2f})ᵃ")
            note = "no association"
        strong = rob == "robust"
        ax.text(0.025, 0.95, badge + "\n" + note, transform=ax.transAxes, ha="left", va="top", fontsize=6.5,
                color=I.INK if strong else I.INK2, fontweight="bold" if strong else "normal", linespacing=1.35,
                bbox=dict(boxstyle="round,pad=0.4", fc=I.REV_T if strong else "#F2F2F2", ec="none"))
    for ax in axs[:, 0]:
        ax.set_ylabel("Financial hardship (%)")
    D.check("Fig RQ3", "poorest-richest main OOP coefficient (2 dp)", round(D.est("pov.gap_q.spl")["b"], 2), 0.60, 1e-9)
    h = [Line2D([], [], ls="", marker="o", mfc=DIS, mec=I.REV_D, ms=4, label="Disadvantaged group"),
         Line2D([], [], ls="", marker="o", mfc=ADV, mec=I.ORIG_D, ms=4, label="Advantaged group"),
         Line2D([], [], color=DIS, lw=1.2, alpha=0.6, label="Gap > 0 (one country)"),
         Line2D([], [], color=I.INK3, lw=1.2, alpha=0.6, label="Gap ≤ 0"),
         Line2D([], [], ls="", marker="D", mfc=I.BGD, mec="white", ms=4.5, label="Bangladesh")]
    fig.legend(handles=h, loc="lower center", bbox_to_anchor=(0.5, 0.035), ncol=5, fontsize=6.7,
               columnspacing=1.2, handletextpad=0.4)
    I.note(fig, "Revised SDG 3.8.2, latest survey since 2005. OOP badges: OLS, robust SE, adjusted for ln GDP per person and the "
                "societal poverty headcount;\nᵃ ln GDP only (no poverty-adjusted model for this gap). "
                "Associations, not causal effects.", y=0.0)
    return I.save(fig, "figRQ3_group_gaps")
