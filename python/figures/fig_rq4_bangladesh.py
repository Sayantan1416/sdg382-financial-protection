"""Figure RQ4 - Bangladesh: good health at low cost, poor financial protection.

(a) Bangladesh's position among LMICs on each measure, from best to worst
    (position = (rank - 1) / (n - 1), rank and n from Stata: B.bgd_rank, B.bgd_oop_rank,
    bgd2016_rank.*, levels.*.bgd_rank in results_v3.csv). Other countries use their latest
    survey since 2005, as in the abstract's former Table 1.
(b) Bangladesh's revised-indicator hardship by population group in each survey
    (results_v3.csv bgd_groups.*; 2016 and 2022 also recomputed in data_v7)."""
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
import identity as I
import data as D
import data_v7 as V

R = D.R3


def half_up(x):
    return f"{int(x * 10 + 0.5 + 1e-9) / 10:.1f}"


def rows():
    nB = int(R["B.n"])
    return [
        # label, [(year, value text, rank, n, worst_is_high)], median text
        ("Life expectancy vs spending (2019)", [(2019, f"+{R['B.bgd_res']:.1f} y", int(R["B.bgd_rank"]), nB, False)],
         "years above prediction", "health"),
        ("Out-of-pocket share of health spending (2019)",
         [(2019, f"{R['B.bgd_oop19']:.1f}%", int(R["B.bgd_oop_rank"]), nB, True)], f"median {R['B.median_oop19']:.1f}%", "fin"),
        ("Original: OOP > 10% of budget (2016)",
         [(2016, f"{half_up(R['bgd2016.cat10'])}%", int(R["bgd2016_rank.cat10.rank"]), int(R["bgd2016_rank.cat10.n"]), True)],
         f"median {R['levels.cat10.median']:.1f}%", "fin"),
        ("Original: OOP > 25% of budget (2016)",
         [(2016, f"{half_up(R['bgd2016.cat25'])}%", int(R["bgd2016_rank.cat25.rank"]), int(R["bgd2016_rank.cat25.n"]), True)],
         f"median {R['levels.cat25.median']:.1f}%", "fin"),
    ] + [
        (f"Revised: {lab} (2016 → 2022)",
         [(2016, f"{half_up(R[f'bgd2016.{v}'])}%", int(R[f"bgd2016_rank.{v}.rank"]), int(R[f"bgd2016_rank.{v}.n"]), True),
          (2022, f"{R[f'bgd2022.{v}']:.1f}%", int(R[f"levels.{v}.bgd_rank"]), int(R[f"levels.{v}.n"]), True)],
         f"median {R[f'levels.{v}.median']:.1f}%", "fin")
        for v, lab in (("fh_large", "large spending"), ("fh_total", "total hardship"), ("fh_impov", "impoverishing"))]


def pos(rank, n, worst_is_high):
    """0 = best position among LMICs, 1 = worst."""
    return (n - rank) / (n - 1) if worst_is_high else (rank - 1) / (n - 1)


def fig_rq4():
    V.group_breakdowns()           # validates Bangladesh 2016/2022 group values against Stata
    V.design_b_full()              # validates OOP share, OOP rank and median OOP share
    fig = plt.figure(figsize=(I.W, 5.3))

    # ---------------- (a) position strip
    ax = fig.add_axes([0.385, 0.53, 0.30, 0.385])
    rs = rows()
    ax.axvspan(0, 0.5, color="#EEF4F4", zorder=0); ax.axvspan(0.5, 1, color="#F8ECE8", zorder=0)
    ax.axvline(0.5, color=I.INK3, lw=0.6, ls=(0, (2, 1.5)), zorder=1)
    for y, (lab, pts, med, kind) in enumerate(rs):
        ax.plot([0, 1], [y, y], color=I.RULE, lw=0.6, zorder=1)
        xs = [pos(r, n, w) for _, _, r, n, w in pts]
        if len(xs) == 2:
            ax.annotate("", (xs[1], y), (xs[0], y), arrowprops=dict(arrowstyle="-|>", color=I.BGD, lw=0.9,
                                                                    shrinkA=3.5, shrinkB=4.5, mutation_scale=7), zorder=3)
        for k, ((yr, val, r, n, w), x) in enumerate(zip(pts, xs)):
            last = k == len(pts) - 1
            ax.scatter(x, y, s=34 if last else 24, marker="D", zorder=4,
                       fc=(I.REV if kind == "health" else I.BGD) if last else "white",
                       ec=I.REV if kind == "health" else I.BGD, lw=0.9)
        ax.text(-0.04, y, lab, transform=ax.get_yaxis_transform(), ha="right", va="center", fontsize=7.2)
        # right-hand value column
        if kind == "health":
            yr, val, r, n, w = pts[0]
            rt = f"{val}  ·  {r}nd best of {n}"
        else:
            rt = (f"{pts[0][1]} → {pts[1][1]}  ·  {pts[0][2]} → {pts[1][2]} of {pts[1][3]}" if len(pts) == 2
                  else f"{pts[0][1]}  ·  {pts[0][2]} of {pts[0][3]}")
        ax.text(1.04, y + 0.05, rt, transform=ax.get_yaxis_transform(), va="center", fontsize=6.5,
                color=I.REV_D if kind == "health" else I.INK)
        ax.text(1.04, y + 0.38, med, transform=ax.get_yaxis_transform(), va="center", fontsize=5.8, color=I.INK3)
    ax.set_xlim(-0.03, 1.03); ax.set_ylim(len(rs) - 0.45, -0.8)
    ax.set_yticks([]); ax.spines["left"].set_visible(False); ax.spines["bottom"].set_color(I.RULE)
    ax.set_xticks([0, 0.5, 1]); ax.set_xticklabels(["Best", "LMIC median", "Worst"], fontsize=6.8)
    ax.text(0.01, -0.62, "better than median", ha="left", fontsize=6.0, color=I.REV_D, style="italic")
    ax.text(0.99, -0.62, "worse than median", ha="right", fontsize=6.0, color=I.BGD, style="italic")
    ax.text(1.04, -0.62, "Bangladesh value: rank (1 = worst)", transform=ax.get_yaxis_transform(), fontsize=6.3,
            color=I.INK2, fontweight="bold")
    ax.text(-1.27, 1.105, "a", transform=ax.transAxes, fontsize=9, fontweight="bold")
    ax.text(-1.22, 1.105, "Where Bangladesh stands among LMICs", transform=ax.transAxes, fontsize=8.5,
            fontweight="bold")

    # ---------------- (b) groups over survey years
    years = [2005, 2010, 2016, 2022]
    pairs = [("q1", "q5", "Poorest vs richest fifth", "Poorest", "Richest"),
             ("old", "adults", "Older-only vs working-age", "Older-only", "Working-age"),
             ("rur", "urb", "Rural vs urban", "Rural", "Urban")]
    w, x0 = 0.285, 0.075
    for k, (a, b, title, la, lb) in enumerate(pairs):
        bx = fig.add_axes([x0 + k * (w + 0.035), 0.105, w, 0.235])
        va = [R[f"bgd_groups.{y}.{a}"] for y in years]
        vb = [R[f"bgd_groups.{y}.{b}"] for y in years]
        bx.fill_between(years, vb, va, color=I.REV_T, lw=0, zorder=1)
        bx.plot(years, va, color=I.REV, lw=1.6, marker="o", ms=3.4, zorder=3)
        bx.plot(years, vb, color=I.ORIG_D, lw=1.2, marker="o", ms=3.0, mfc="white", zorder=3)
        for y_, v1, v2 in ((2016, va[2], vb[2]), (2022, va[3], vb[3])):
            bx.text(y_ + (0.4 if y_ == 2022 else 0), v1 + 4, f"{v1:.0f}", ha="center" if y_ == 2016 else "left",
                    fontsize=6.3, color=I.REV_D, fontweight="bold")
            bx.text(y_ + (0.4 if y_ == 2022 else 0), v2 - 9, f"{v2:.0f}", ha="center" if y_ == 2016 else "left",
                    fontsize=6.3, color=I.ORIG_D)
        g16, g22 = va[2] - vb[2], va[3] - vb[3]
        bx.text(0.02, 1.13, title, transform=bx.transAxes, fontsize=7.6, fontweight="bold")
        bx.text(0.02, 1.03, f"gap {g16:.1f} → {g22:.1f} pp (2016 → 2022)", transform=bx.transAxes, fontsize=6.5,
                color=I.INK if abs(g22 - g16) > 5 else I.INK2, fontweight="bold" if abs(g22 - g16) > 5 else "normal")
        bx.text(2004.6, va[0] + 5, la, fontsize=6.3, color=I.REV_D)
        bx.text(2005.2, max(vb[0], vb[1]) + 3, lb, ha="left", fontsize=6.3, color=I.ORIG_D)
        bx.set_ylim(0, 100); bx.set_xlim(2003.5, 2025)
        bx.set_xticks(years); bx.set_xticklabels([str(y) for y in years], fontsize=6.4)
        if k == 0:
            bx.set_ylabel("Financial hardship (%)", fontsize=7)
        else:
            bx.set_yticklabels([])
        I.ygrid(bx)
        if k == 0:
            bx.text(-0.22, 1.32, "b", transform=bx.transAxes, fontsize=9, fontweight="bold")
            bx.text(-0.13, 1.32, "Who bears it in Bangladesh: revised indicator by population group, each survey",
                    transform=bx.transAxes, fontsize=8.5, fontweight="bold")
    D.check("Fig RQ4", "Bangladesh poorest fifth 2022 (abstract 90.8)", round(R["bgd_groups.2022.q1"], 1), 90.8, 1e-9)
    D.check("Fig RQ4", "Bangladesh richest fifth 2022 (abstract 13.6)", round(R["bgd_groups.2022.q5"], 1), 13.6, 1e-9)
    I.note(fig, "(a) Diamonds: Bangladesh (hollow 2016, filled 2022); other countries use their latest survey since 2005, "
                "so comparisons cross survey years.\n(b) Hardship = revised SDG 3.8.2 total for each group, WHO estimates.",
           y=0.004)
    return I.save(fig, "figRQ4_bangladesh")
