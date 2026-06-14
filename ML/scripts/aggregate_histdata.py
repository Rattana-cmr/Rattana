"""
aggregate_histdata.py — Convert HistData M1 OHLC to M15, merge with MT5 bars.

HistData CSV format (per file or inside ZIP):
    20090102 000100;1073.750;1073.750;1073.750;1073.750;0
    YYYYMMDD HHMMSS;Open;High;Low;Close;Volume  (semicolon-delimited)

Usage:
    python aggregate_histdata.py --histdata PATH_TO_ZIP_OR_DIR [--mt5-bars PATH] [--output PATH]

Output: single M15 CSV compatible with label_signals.py (Date,Open,High,Low,Close,Volume)
"""

import argparse
import sys
import zipfile
from io import StringIO
from pathlib import Path

import numpy as np
import pandas as pd


DEFAULT_MT5_BARS = Path(__file__).parent.parent / "data" / "XAUUSD_M15_Bars.csv"
DEFAULT_OUTPUT   = Path(__file__).parent.parent / "data" / "XAUUSD_M15_Extended.csv"


# ── HistData reader ───────────────────────────────────────────────────────────

def read_histdata_csv(text: str) -> pd.DataFrame:
    """Parse a single HistData M1 CSV string."""
    df = pd.read_csv(
        StringIO(text),
        sep=";",
        header=None,
        names=["DateTime", "Open", "High", "Low", "Close", "Volume"],
        dtype={"DateTime": str},
    )
    # DateTime format: "20090102 000100"
    df["ts"] = pd.to_datetime(df["DateTime"], format="%Y%m%d %H%M%S")
    df = df.drop(columns=["DateTime"])
    df = df[df["Close"] > 0].copy()
    return df.set_index("ts").sort_index()


def load_histdata(source: Path) -> pd.DataFrame:
    """Load HistData M1 from a ZIP file or a directory of ZIPs/CSVs."""
    frames = []

    def _read_file(name: str, text: str):
        if name.upper().endswith(".CSV"):
            df = read_histdata_csv(text)
            frames.append(df)
            print(f"  {name}: {len(df):,} M1 bars  "
                  f"({df.index[0].date()} → {df.index[-1].date()})")

    if source.is_file() and source.suffix.lower() == ".zip":
        # Single ZIP — may contain per-year ZIPs or CSVs
        with zipfile.ZipFile(source) as outer:
            for entry in sorted(outer.namelist()):
                if entry.upper().endswith(".ZIP"):
                    # Nested ZIP
                    inner_bytes = outer.read(entry)
                    import io
                    with zipfile.ZipFile(io.BytesIO(inner_bytes)) as inner:
                        for ientry in sorted(inner.namelist()):
                            if ientry.upper().endswith(".CSV"):
                                text = inner.read(ientry).decode("utf-8", errors="replace")
                                _read_file(ientry, text)
                elif entry.upper().endswith(".CSV"):
                    text = outer.read(entry).decode("utf-8", errors="replace")
                    _read_file(entry, text)

    elif source.is_dir():
        # Directory of ZIPs or CSVs
        for f in sorted(source.iterdir()):
            if f.suffix.lower() == ".zip":
                with zipfile.ZipFile(f) as z:
                    for entry in sorted(z.namelist()):
                        if entry.upper().endswith(".CSV"):
                            text = z.read(entry).decode("utf-8", errors="replace")
                            _read_file(entry, text)
            elif f.suffix.lower() == ".csv":
                text = f.read_text(encoding="utf-8", errors="replace")
                _read_file(f.name, text)

    if not frames:
        raise ValueError(f"No M1 CSV data found in: {source}")

    combined = pd.concat(frames).sort_index()
    combined = combined[~combined.index.duplicated(keep="first")]
    print(f"\nTotal M1 bars loaded: {len(combined):,}  "
          f"({combined.index[0].date()} → {combined.index[-1].date()})")
    return combined


# ── M1 → M15 aggregation ─────────────────────────────────────────────────────

def aggregate_m1_to_m15(m1: pd.DataFrame) -> pd.DataFrame:
    """Resample M1 OHLC to M15. Returns Date-string indexed like MT5 export."""
    m15 = m1.resample("15min", closed="left", label="left").agg(
        Open=("Open",   "first"),
        High=("High",   "max"),
        Low=("Low",     "min"),
        Close=("Close", "last"),
        Volume=("Volume","sum"),
    ).dropna(subset=["Open"])

    m15 = m15[m15["Close"] > 0]
    m15.index.name = "ts"
    m15 = m15.reset_index()
    # Format to match MT5 export: "2022.03.16 00:00"
    m15["Date"] = m15["ts"].dt.strftime("%Y.%m.%d %H:%M")
    m15 = m15[["Date", "Open", "High", "Low", "Close", "Volume"]]
    return m15


# ── Merge with MT5 bars ───────────────────────────────────────────────────────

def merge_with_mt5(histdata_m15: pd.DataFrame, mt5_path: Path) -> pd.DataFrame:
    """Combine HistData-derived M15 with existing MT5 M15 export, dedup."""
    mt5 = pd.read_csv(mt5_path)
    mt5_ts = pd.to_datetime(mt5["Date"], format="%Y.%m.%d %H:%M")
    hist_ts = pd.to_datetime(histdata_m15["Date"], format="%Y.%m.%d %H:%M")

    mt5_start  = mt5_ts.min()
    hist_end   = hist_ts.max()

    print(f"\nHistData M15 coverage:  {hist_ts.min().date()} → {hist_ts.max().date()}")
    print(f"MT5 bars coverage:      {mt5_ts.min().date()} → {mt5_ts.max().date()}")

    if hist_end >= mt5_start:
        overlap_days = (hist_end - mt5_start).days
        print(f"Overlap: {overlap_days} days — MT5 bars take priority in overlap window")

    # Combine, dedup keeping MT5 rows in overlap
    combined = pd.concat([histdata_m15, mt5], ignore_index=True)
    combined["ts"] = pd.to_datetime(combined["Date"], format="%Y.%m.%d %H:%M")
    combined = combined.sort_values("ts")
    # Keep MT5 data in overlap (it appears second → keep="last")
    combined = combined.drop_duplicates(subset=["ts"], keep="last")
    combined = combined.drop(columns=["ts"]).reset_index(drop=True)

    return combined


# ── Main ──────────────────────────────────────────────────────────────────────

def run(histdata_source: Path, mt5_bars: Path, output: Path):
    print("\n" + "="*60)
    print(" HistData M1 → M15 Aggregation & Merge")
    print("="*60)

    print(f"\n[1/4] Loading HistData M1 from: {histdata_source}")
    m1 = load_histdata(histdata_source)

    print(f"\n[2/4] Aggregating M1 → M15 ...")
    m15 = aggregate_m1_to_m15(m1)
    print(f"  M15 bars produced: {len(m15):,}")

    print(f"\n[3/4] Merging with MT5 bars: {mt5_bars.name}")
    merged = merge_with_mt5(m15, mt5_bars)
    print(f"  Combined M15 bars: {len(merged):,}")

    merged_ts = pd.to_datetime(merged["Date"], format="%Y.%m.%d %H:%M")
    print(f"  Coverage: {merged_ts.min().date()} → {merged_ts.max().date()}")

    print(f"\n[4/4] Saving to: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    merged.to_csv(output, index=False)
    print(f"  ✓ Saved {len(merged):,} bars")

    print("\n" + "="*60)
    print(" Next step:")
    print(f"  python ML/scripts/label_signals.py \\")
    print(f"    --bars {output} \\")
    print(f"    --signals ML/data/ICT_ATLAS_Historical_Extension.csv \\")
    print(f"    --output ML/data/ICT_ATLAS_Extended_Signals_Labeled.csv")
    print("="*60)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--histdata",   type=Path, required=True,
                        help="Path to HistData ZIP file or directory of ZIPs/CSVs")
    parser.add_argument("--mt5-bars",  type=Path, default=DEFAULT_MT5_BARS,
                        help="Existing MT5 M15 bars CSV")
    parser.add_argument("--output",    type=Path, default=DEFAULT_OUTPUT,
                        help="Output path for merged M15 CSV")
    args = parser.parse_args()
    run(args.histdata, args.mt5_bars, args.output)


if __name__ == "__main__":
    main()
