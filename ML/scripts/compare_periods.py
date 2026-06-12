"""
compare_periods.py — Compare performance statistics between two trade CSV files.

Usage:
    python compare_periods.py <historical_csv> <current_csv> [--labels A B]

Outputs a side-by-side comparison of:
  Trade Count, Net Profit, Profit Factor, Win Rate, Max Drawdown, Expectancy
"""

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent.parent))


# ── Metrics ───────────────────────────────────────────────────────────────────

def compute_stats(df: pd.DataFrame, label: str) -> dict:
    profits = df["Profit_USD"].values
    wins    = df["Trade_Result"] == "WIN"

    n          = len(df)
    net_profit = profits.sum()
    win_rate   = wins.mean() * 100
    expectancy = profits.mean()

    gross_win  = profits[profits > 0].sum()
    gross_loss = abs(profits[profits < 0].sum())
    pf         = gross_win / gross_loss if gross_loss > 0 else float("inf")

    # Max drawdown on equity curve
    equity = np.cumsum(profits)
    peak   = np.maximum.accumulate(equity)
    dd     = equity - peak
    max_dd = dd.min()

    # RR stats
    rr_mean = df["RR_Achieved"].mean()
    rr_std  = df["RR_Achieved"].std()

    # Date range
    df["OpenTime"] = pd.to_datetime(df["OpenTime"])
    date_start = df["OpenTime"].min().strftime("%Y-%m-%d")
    date_end   = df["OpenTime"].max().strftime("%Y-%m-%d")

    return {
        "Label":          label,
        "Period":         f"{date_start} → {date_end}",
        "Trade Count":    n,
        "Win Rate":       f"{win_rate:.1f}%",
        "Net Profit":     f"${net_profit:,.2f}",
        "Profit Factor":  f"{pf:.3f}",
        "Max Drawdown":   f"${max_dd:,.2f}",
        "Expectancy":     f"${expectancy:.2f}/trade",
        "Avg RR":         f"{rr_mean:.3f} ± {rr_std:.3f}",
        "Trades/Year":    f"{n / max((df['OpenTime'].max() - df['OpenTime'].min()).days / 365.25, 0.1):.1f}",
    }


def tp_rates(df: pd.DataFrame) -> dict:
    rr = df["RR_Achieved"]
    return {
        "TP1 Rate (RR≥1)": f"{(rr >= 1.0).mean()*100:.1f}%",
        "TP2 Rate (RR≥2)": f"{(rr >= 2.0).mean()*100:.1f}%",
        "TP3 Rate (RR≥3)": f"{(rr >= 3.0).mean()*100:.1f}%",
    }


# ── Consistency Check ─────────────────────────────────────────────────────────

def consistency_check(stats_a: dict, stats_b: dict) -> list[str]:
    """Flag metrics that diverge significantly between the two periods."""
    issues = []

    def pct_val(s):
        return float(s.replace("%", ""))

    def dollar_val(s):
        return float(s.replace("$", "").replace(",", "").split("/")[0])

    wr_a = pct_val(stats_a["Win Rate"])
    wr_b = pct_val(stats_b["Win Rate"])
    if abs(wr_a - wr_b) > 15:
        issues.append(f"Win rate divergence: {wr_a:.1f}% vs {wr_b:.1f}% (>{15}% gap)")

    pf_a = dollar_val(stats_a["Profit Factor"].replace("inf", "99"))
    pf_b = dollar_val(stats_b["Profit Factor"].replace("inf", "99"))
    if abs(pf_a - pf_b) > 1.5:
        issues.append(f"Profit factor divergence: {pf_a:.3f} vs {pf_b:.3f} (>1.5 gap)")

    exp_a = dollar_val(stats_a["Expectancy"])
    exp_b = dollar_val(stats_b["Expectancy"])
    if exp_a < 0:
        issues.append(f"Historical period has NEGATIVE expectancy (${exp_a:.2f}) — do NOT merge")
    elif abs(exp_a - exp_b) / max(abs(exp_b), 1) > 0.5:
        issues.append(f"Expectancy divergence: ${exp_a:.2f} vs ${exp_b:.2f} (>50% difference)")

    return issues


# ── Formatting ────────────────────────────────────────────────────────────────

def print_comparison(stats_a: dict, stats_b: dict,
                     tp_a: dict, tp_b: dict,
                     issues: list[str]):
    keys = [k for k in stats_a if k != "Label"]
    col_w = 30

    print("\n" + "=" * 75)
    print(f"  PERIOD COMPARISON: {stats_a['Label']}  vs  {stats_b['Label']}")
    print("=" * 75)
    print(f"{'Metric':<28} {stats_a['Label']:>20} {stats_b['Label']:>20}")
    print("-" * 75)
    for k in keys:
        print(f"  {k:<26} {stats_a[k]:>20} {stats_b[k]:>20}")

    print("\n  TP Hit Rates:")
    for k in tp_a:
        print(f"  {k:<26} {tp_a[k]:>20} {tp_b[k]:>20}")

    print("=" * 75)
    if issues:
        print("\n  ⚠ CONSISTENCY WARNINGS:")
        for issue in issues:
            print(f"    • {issue}")
        print("\n  Recommendation: Review warnings before merging datasets.")
    else:
        print("\n  ✓ Periods are consistent — safe to merge for ML training.")
    print("=" * 75 + "\n")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("historical", type=Path, help="Older period CSV")
    parser.add_argument("current",    type=Path, help="Existing 2015-2025 CSV")
    parser.add_argument("--labels", nargs=2, default=["Historical", "2015-2025"],
                        metavar=("LABEL_A", "LABEL_B"))
    args = parser.parse_args()

    df_a = pd.read_csv(args.historical, parse_dates=["OpenTime", "CloseTime"])
    df_b = pd.read_csv(args.current,    parse_dates=["OpenTime", "CloseTime"])

    print(f"\nLoaded historical: {len(df_a)} trades ({args.labels[0]})")
    print(f"Loaded current:    {len(df_b)} trades ({args.labels[1]})")

    stats_a = compute_stats(df_a, args.labels[0])
    stats_b = compute_stats(df_b, args.labels[1])
    tp_a    = tp_rates(df_a)
    tp_b    = tp_rates(df_b)
    issues  = consistency_check(stats_a, stats_b)

    print_comparison(stats_a, stats_b, tp_a, tp_b, issues)


if __name__ == "__main__":
    main()
