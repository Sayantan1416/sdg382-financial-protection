"""
00_download_v4_data.py  (added in V3, 18 Nov 2026)
Fetches the extra public data used for abstract version 4.
Standard library only (no pip installs needed). Run from anywhere:
    python 00_download_v4_data.py
Saves untouched files in data/raw/ with today's date stamp:
  wdi_v4_long_<date>.csv    iso3, year, var, value for
        SI.POV.SOPO  poverty headcount at the societal poverty line (%)
        SI.POV.DDAY  poverty headcount at the international poverty line (%)
        SP.POP.65UP.TO.ZS  population aged 65+ (% of total)
  OGHIST_<date>.xlsx        World Bank historical income classification
  download_v4_log.txt       what was downloaded, row counts, lastupdated
"""
import csv, json, time, urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
RAW.mkdir(parents=True, exist_ok=True)
STAMP = date.today().strftime("%Y%m%d")
LOG = []

def get(url, tries=4):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (research download)"})
            with urllib.request.urlopen(req, timeout=180) as r:
                return r.read()
        except Exception as e:
            LOG.append(f"  retry {i+1} {url[:90]}: {e}")
            time.sleep(5 * (i + 1))
    raise SystemExit(f"FAILED: {url}")

rows = []
for code, var in [("SI.POV.SOPO", "pov_spl"), ("SI.POV.DDAY", "pov_ipl"), ("SP.POP.65UP.TO.ZS", "pop65")]:
    page, pages = 1, 1
    while page <= pages:
        url = (f"https://api.worldbank.org/v2/country/all/indicator/{code}"
               f"?format=json&per_page=5000&date=1990:2024&page={page}")
        j = json.loads(get(url))
        pages = j[0]["pages"]
        upd = j[0].get("lastupdated")
        for x in j[1] or []:
            if x["value"] is not None and x["countryiso3code"]:
                rows.append([x["countryiso3code"], int(x["date"]), var, x["value"]])
        page += 1
    LOG.append(f"{code} -> {var}: pages {pages}, lastupdated {upd}")
    print(code, "done")

out = RAW / f"wdi_v4_long_{STAMP}.csv"
with open(out, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["iso3", "year", "var", "value"])
    w.writerows(rows)
LOG.append(f"wrote {out.name}: {len(rows)} rows")

x = get("https://datacatalogfiles.worldbank.org/ddh-published/0037712/DR0090754/OGHIST.xlsx")
(RAW / f"OGHIST_{STAMP}.xlsx").write_bytes(x)
LOG.append(f"wrote OGHIST_{STAMP}.xlsx: {len(x)} bytes")

(RAW / "download_v4_log.txt").write_text(f"Downloaded {date.today()}\n" + "\n".join(LOG) + "\n")
print("\n".join(LOG))
print("DONE")
