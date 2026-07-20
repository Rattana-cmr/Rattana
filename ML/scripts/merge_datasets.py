"""
merge_datasets.py — Merge two trade CSV files, remove duplicates, validate.

Usage:
    python merge_datasets.py <file_a> <file_b> --output <merged.csv>

Deduplication key: SetupID (unique per trade signal).
Files are sorted by OpenTime after merging.
"""

import argparse
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).parent.parent))


def merge(path_a: Path, path_b: Path, output: Path, dry_run: bool = False):
    df_a = pd.read_csv(path_a, parse_dates=["OpenTime", "CloseTime"])
    df_b = pd.read_csv(path_b, parse_dates=["OpenTime", "CloseTime"])

    print(f"\nFile A: {path_a.name}  — {len(df_a)} trades")
    print(f"File B: {path_b.name}  — {len(df_b)} trades")

    # Validate column compatibility
    cols_a = set(df_a.columns)
    cols_b = set(df_b.columns)
    missing_in_b = cols_a - cols_b
    missing_in_a = cols_b - cols_a

    if missing_in_b:
        print(f"\n⚠ Columns in A but not B: {sorted(missing_in_b)}")
    if missing_in_a:
        print(f"\n⚠ Columns in B but not A: {sorted(missing_in_a)}")

    # Combine
    combined = pd.concat([df_a, df_b], ignore_index=True)
    n_before = len(combined)

    # Deduplicate on SetupID (primary key)
    combined.sort_values("OpenTime", inplace=True)
    combined.drop_duplicates(subset=["SetupID"], keep="first", inplace=True)
    n_after = len(combined)
    n_dupes = n_before - n_after

    combined.reset_index(drop=True, inplace=True)

    # Date range of merged dataset
    date_start = combined["OpenTime"].min().strftime("%Y-%m-%d")
    date_end   = combined["OpenTime"].max().strftime("%Y-%m-%d")

    print(f"\nMerge summary:")
    print(f"  Combined rows:    {n_before}")
    print(f"  Duplicates removed: {n_dupes}")
    print(f"  Final trade count:  {n_after}")
    print(f"  Date range:         {date_start} → {date_end}")

    # Direction check — must be all LONG
    if "Direction" in combined.columns:
        dirs = combined["Direction"].value_counts()
        print(f"\n  Direction breakdown:")
        for d, c in dirs.items():
            print(f"    {d}: {c} ({c/n_after*100:.1f}%)")
        if "SHORT" in dirs and dirs.get("SHORT", 0) > 0:
            print("  ⚠ WARNING: SHORT trades detected — Phase 1D-B should be LONG only!")

    # Symbol check
    if "Symbol" in combined.columns:
        syms = combined["Symbol"].value_counts()
        print(f"\n  Symbols: {dict(syms)}")

    if dry_run:
        print(f"\n  [DRY RUN] — no file written")
        return combined

    combined.to_csv(output, index=False)
    print(f"\n  ✓ Saved merged dataset: {output}")
    print(f"    {n_after} trades ready for ML pipeline")

    return combined


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("file_a",   type=Path, help="First CSV (e.g. historical extension)")
    parser.add_argument("file_b",   type=Path, help="Second CSV (e.g. existing 2015-2025)")
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).parent.parent / "data" / "ICT_ATLAS_Merged_Trades.csv")
    parser.add_argument("--dry-run", action="store_true",
                        help="Preview merge without saving")
    args = parser.parse_args()

    merge(args.file_a, args.file_b, args.output, dry_run=args.dry_run)

    if not args.dry_run:
        print(f"\nNext step:")
        print(f"  python run_pipeline.py --data {args.output}")


if __name__ == "__main__":
    main()
