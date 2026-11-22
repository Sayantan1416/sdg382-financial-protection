"""Visual identity shared by all four figures.

Encodings (identical in every figure):
  Original SDG 3.8.2 ......... warm stone, light   (#B4AC9C)
  Revised SDG 3.8.2 (2025) ... deep teal, dark     (#1F6B70)
  Bangladesh ................. vermillion diamond  (#C4472B)
  Pakistan ................... ink square
  p < 0.05 ................... filled marker;  p >= 0.05 ... hollow marker
  Income group (ordinal) ..... lightness ramp + marker shape (low = darkest)
The indicator pair differs in hue AND lightness, so it survives colour-vision
deficiency and grayscale printing. Typeface: GNU FreeSans (Helvetica-class TrueType,
GPL with font exception), bundled in ../fonts so output is identical on every computer.
Width 6.3 in = \\textwidth of the abstract; insert with \\includegraphics{file.pdf}.
"""
from pathlib import Path
import logging
logging.getLogger('matplotlib.font_manager').setLevel(logging.ERROR)
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager as fm

PROJECT = Path(__file__).resolve().parent.parent.parent   # <project>
ROOT = PROJECT / "figures"                              # <project>/figures
OUT, INP = PROJECT / "results", PROJECT / "data"       # Stata outputs / frozen inputs
FIG, VAL = ROOT / "plots", ROOT / "validation"
FIG.mkdir(exist_ok=True); VAL.mkdir(exist_ok=True)
for f in (ROOT / "fonts").glob("*.ttf"):
    fm.fontManager.addfont(str(f))

W = 6.3                                   # \textwidth, inches
INK, INK2, INK3 = "#1E1E1E", "#5A5A5A", "#8A8A8A"
RULE, GRID = "#C9C9C9", "#ECECEC"
ORIG, ORIG_D = "#B4AC9C", "#7F7868"       # stone (fill, edge/text)
REV, REV_D = "#1F6B70", "#174F53"         # teal
REV_T, ORIG_T = "#E4EFEF", "#F3F0EA"      # tints for bands / zones
BGD, PAK = "#C4472B", INK
INCOME = {"LIC": dict(label="Low income", fill="#2B2B2B", marker="o"),
          "LMC": dict(label="Lower-middle income", fill="#8C8C8C", marker="s"),
          "UMC": dict(label="Upper-middle income", fill="#D2D2D2", marker="^")}
IND = {"cat10": dict(name="Original SDG 3.8.2", short="Original", rule="OOP spending > 10% of household budget",
                     fill=ORIG, dark=ORIG_D, tint=ORIG_T),
       "fh_total": dict(name="Revised SDG 3.8.2 (2025)", short="Revised", rule="Financial hardship, total",
                        fill=REV, dark=REV_D, tint=REV_T)}

def use():
    plt.rcParams.update({
        "font.family": "FreeSans", "font.size": 8, "axes.labelsize": 8,
        "axes.titlesize": 8.5, "xtick.labelsize": 7.5, "ytick.labelsize": 7.5,
        "legend.fontsize": 7.5, "axes.edgecolor": INK2, "axes.linewidth": 0.55,
        "axes.labelcolor": INK, "xtick.color": INK2, "ytick.color": INK2,
        "xtick.major.width": 0.55, "ytick.major.width": 0.55,
        "xtick.major.size": 2.8, "ytick.major.size": 2.8,
        "axes.spines.top": False, "axes.spines.right": False,
        "legend.frameon": False, "axes.unicode_minus": True,
        "pdf.fonttype": 42, "svg.fonttype": "none", "savefig.dpi": 600,
        "mathtext.fontset": "custom", "mathtext.rm": "FreeSans",
        "mathtext.it": "FreeSans:italic",
    })

def tag(ax, letter, title, sub=None, x=0.0):
    """Panel label: bold letter + title, optional grey line beneath."""
    ax.text(x, 1.10 if sub else 1.03, f"{letter}", transform=ax.transAxes, fontsize=9,
            fontweight="bold", color=INK, va="bottom")
    ax.text(x + 0.045, 1.10 if sub else 1.03, title, transform=ax.transAxes, fontsize=8.5,
            fontweight="bold", color=INK, va="bottom")
    if sub:
        ax.text(x + 0.045, 1.03, sub, transform=ax.transAxes, fontsize=7.3, color=INK2, va="bottom")

def note(fig, text, y=0.012):
    fig.text(0.012, y, text, fontsize=6.6, color=INK2, va="bottom", ha="left")

def m(s):
    return s.replace("-", "−")

def ygrid(ax):
    ax.grid(axis="y", color=GRID, lw=0.6); ax.set_axisbelow(True)

def save(fig, name):
    for ext in ("pdf", "svg", "png"):
        fig.savefig(FIG / f"{name}.{ext}")
    plt.close(fig)
    return name
