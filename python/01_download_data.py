"""
01_download_data.py
Fetches every dataset used in the audit of
"Good Health at Low Cost Is Not Financial Protection" from the official APIs
and saves analysis-ready files in ../data/.

Sources (queried live; no manual downloads needed):
  - World Bank API (WDI + country income/region list):  https://api.worldbank.org/v2
  - WHO Global Health Observatory OData API:            https://ghoapi.azureedge.net/api

Run from anywhere:   python 01_download_data.py
Requires:            pip install requests pandas
Outputs (in data/):
  raw/   untouched API pulls, date-stamped
  countries_fy2027.csv / .dta   131 LMICs with income group and region
  panel.dta / panel.csv         country-year panel 2000-2023 (LMICs only)
  fp_surveys.dta / .csv         financial-protection survey points (national totals)
  download_checks.txt           Bangladesh check values vs the audit
"""
from datetime import date
from pathlib import Path
import sys

import pandas as pd
import requests

ROOT = Path(__file__).resolve().parent.parent       # project folder
INP = ROOT / "data"
RAW = INP / "raw"
RAW.mkdir(parents=True, exist_ok=True)
STAMP = date.today().strftime("%Y%m%d")

WB = "https://api.worldbank.org/v2"
GHO = "https://ghoapi.azureedge.net/api"
S = requests.Session()


def get_json(url, params=None):
    r = S.get(url, params=params, timeout=120)
    r.raise_for_status()
    return r.json()


# ---------------------------------------------------------------- countries
print("Countries ...")
c = get_json(f"{WB}/country", {"format": "json", "per_page": 400})[1]
ctry = pd.DataFrame([{
    "iso3": x["id"], "country": x["name"],
    "region": x["region"]["id"], "region_name": x["region"]["value"],
    "income": x["incomeLevel"]["id"],
} for x in c if x["region"]["id"] != "NA"])          # drop aggregates
ctry.to_csv(RAW / f"wb_countries_{STAMP}.csv", index=False)
lmic = ctry[ctry.income.isin(["LIC", "LMC", "UMC"])].copy()
print("  LMICs:", len(lmic), dict(lmic.income.value_counts()))
lmic.to_csv(INP / "countries_fy2027.csv", index=False)
lmic.to_stata(INP / "countries_fy2027.dta", write_index=False, version=118)
LM = set(lmic.iso3)

# ---------------------------------------------------------------- WDI
WDI = {
    "SH.XPD.OOPC.CH.ZS": "oop",       # OOP % current health expenditure
    "SH.XPD.GHED.CH.ZS": "gov",       # domestic general govt % CHE
    "SH.XPD.EHEX.CH.ZS": "ext",       # external % CHE
    "SH.XPD.CHEX.PP.CD": "che_ppp",   # CHE per capita, current PPP $
    "SH.XPD.CHEX.PC.CD": "che_usd",   # CHE per capita, current US$
    "SH.XPD.CHEX.GD.ZS": "che_gdp",   # CHE % GDP
    "NY.GDP.PCAP.PP.KD": "gdp_ppp",   # GDP pc, constant 2021 PPP $
    "SP.DYN.LE00.IN": "le_wb",        # life expectancy (UN WPP via WDI)
    "SH.DYN.MORT": "u5mr",            # under-5 mortality per 1,000 (UN IGME)
}
frames = []
for code, short in WDI.items():
    print("WDI", code, "...")
    j = get_json(f"{WB}/country/all/indicator/{code}",
                 {"format": "json", "per_page": 20000, "date": "2000:2023"})
    if len(j) < 2 or j[1] is None:
        sys.exit(f"ERROR: WDI indicator {code} returned no data: {j[0]}")
    d = pd.DataFrame([{"iso3": x["countryiso3code"], "year": int(x["date"]),
                       "var": short, "value": x["value"]}
                      for x in j[1] if x["value"] is not None])
    print("   last updated:", j[0].get("lastupdated"), "| rows:", len(d))
    frames.append(d)
wdi = pd.concat(frames)
wdi.to_csv(RAW / f"wdi_long_{STAMP}.csv", index=False)
wdi_w = wdi.pivot_table(index=["iso3", "year"], columns="var",
                        values="value").reset_index()


# ---------------------------------------------------------------- GHO
def gho(code):
    print("GHO", code, "...")
    v = get_json(f"{GHO}/{code}", {"$filter": "SpatialDimType eq 'COUNTRY'"})["value"]
    d = pd.DataFrame(v)
    d.to_csv(RAW / f"gho_{code}_{STAMP}.csv", index=False)
    return d


def gho_select(d, dim1, name):
    """Keep national totals: Dim1 == dim1 (or any if None) and no Dim2."""
    if dim1 is not None:
        d = d[d["Dim1"] == dim1]
    if "Dim2" in d:
        d = d[d["Dim2"].isna()]
    d = d[["SpatialDim", "TimeDim", "NumericValue"]].dropna()
    d.columns = ["iso3", "year", name]
    d["year"] = d["year"].astype(int)
    if d.duplicated(["iso3", "year"]).any():
        sys.exit(f"ERROR: duplicate country-years in {name}; check GHO filters")
    return d


le_who = gho_select(gho("WHOSIS_000001"), "SEX_BTSX", "le_who")
uhc = gho_select(gho("UHC_INDEX_REPORTED"), None, "uhc")
cat10 = gho_select(gho("FINPROTECTION_CATA_TOT_10_POP"), "RESIDENCEAREATYPE_TOTL", "cat10")
cat25 = gho_select(gho("FINPROTECTION_CATA_TOT_25_POP"), "RESIDENCEAREATYPE_TOTL", "cat25")
fh = gho("FINANCIALHARDSHIP_PROPORTIONOFPOP")
fh_tot = gho_select(fh, "FINANCIALHARDSHIPCOMPONENT_COMPONENT_TOTAL", "fh_total")
fh_imp = gho_select(fh, "FINANCIALHARDSHIPCOMPONENT_COMPONENT_IMPOV", "fh_impov")
fh_lrg = gho_select(fh, "FINANCIALHARDSHIPCOMPONENT_COMPONENT_LARGE", "fh_large")

# ---------------------------------------------------------------- panel
grid = lmic[["iso3", "country", "region", "income"]].merge(
    pd.DataFrame({"year": range(2000, 2024)}), how="cross")
panel = (grid.merge(wdi_w, on=["iso3", "year"], how="left")
             .merge(le_who, on=["iso3", "year"], how="left")
             .merge(uhc, on=["iso3", "year"], how="left"))
panel = panel.sort_values(["iso3", "year"])
panel.to_csv(INP / "panel.csv", index=False)
panel.to_stata(INP / "panel.dta", write_index=False, version=118,
               data_label="LMIC panel 2000-2023, WDI + WHO GHO")

# ---------------------------------------------------------------- surveys
fp = cat10.merge(cat25, on=["iso3", "year"], how="outer")
for d in (fh_tot, fh_imp, fh_lrg):
    fp = fp.merge(d, on=["iso3", "year"], how="outer")
fp = fp[fp.iso3.isin(LM)].merge(lmic[["iso3", "country", "region", "income"]], on="iso3")
fp = fp.sort_values(["iso3", "year"])
fp.to_csv(INP / "fp_surveys.csv", index=False)
fp.to_stata(INP / "fp_surveys.dta", write_index=False, version=118,
            data_label="Financial protection survey points, national totals")

# ---------------------------------------------------------------- checks
def val(df, iso, yr, col):
    s = df.loc[(df.iso3 == iso) & (df.year == yr), col]
    return None if s.empty else round(float(s.iloc[0]), 2)

checks = [
    ("LMIC count (FY2027)", len(lmic), 131),
    ("BGD OOP % CHE 2019", val(panel, "BGD", 2019, "oop"), 76.47),
    ("BGD CHE pc PPP 2019", val(panel, "BGD", 2019, "che_ppp"), 128.63),
    ("BGD WHO LE 2019", val(panel, "BGD", 2019, "le_who"), 73.4),
    ("BGD catastrophic >10% 2016", val(fp, "BGD", 2016, "cat10"), 24.42),
    ("BGD financial hardship 2022", val(fp, "BGD", 2022, "fh_total"), 41.7),
]
lines = [f"Download date: {date.today()}", "check | got | expected (audit, 12 Nov 2026)"]
for name, got, exp in checks:
    flag = "OK" if got is not None and abs(float(got) - exp) < 0.05 else "CHECK"
    lines.append(f"{name} | {got} | {exp} | {flag}")
(INP / "download_checks.txt").write_text("\n".join(lines), encoding="utf-8")
print("\n".join(lines))
print("\nDONE. Files written to", INP)
