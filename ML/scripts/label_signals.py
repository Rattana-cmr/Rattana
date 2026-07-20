"""
label_signals.py — ATR Triple-Barrier labeling for XAUUSD signal dataset.

For each LONG signal within the M15 bar coverage window:
  - Entry price  = Close of the signal bar
  - 1R distance  = ATR14_Pips at signal time
  - Upper barrier (TP): Entry + k×ATR14  (k = 1, 2, 3)
  - Lower barrier (SL): Entry − 1×ATR14
  - Time barrier: 20 bars (5 hours on M15)

Labels:
  tp1_hit  = 1 if High crossed Entry+1R before Low crossed Entry-1R
  tp2_hit  = 1 if High crossed Entry+2R before Low crossed Entry-1R
  tp3_hit  = 1 if High crossed Entry+3R before Low crossed Entry-1R
  win_loss = tp1_hit  (reached +1R = winner)
  mfe_r    = max favorable excursion in R-multiples
  mae_r    = max adverse excursion in R-multiples
  bars_to_outcome = bars until first barrier breach (or time barrier)

Usage:
    python label_signals.py [--signals PATH] [--bars PATH] [--output PATH]
                            [--lookahead N] [--min-atr PIPS]
"""

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from tqdm import tqdm

sys.path.insert(0, str(Path(__file__).parent.parent))


# ── Constants ─────────────────────────────────────────────────────────────────

DEFAULT_SIGNALS = Path(__file__).parent.parent / "data" / "ICT_ATLAS_All_Signals_XAUUSD.csv" / "ICT_ATLAS_All_Signals_XAUUSD.csv"
DEFAULT_BARS    = Path(__file__).parent.parent / "data" / "XAUUSD_M15_Bars.csv"
DEFAULT_OUTPUT  = Path(__file__).parent.parent / "data" / "ICT_ATLAS_Research_Signals_Labeled.csv"


# ── Labeling Engine ───────────────────────────────────────────────────────────

def label_one(entry: float, atr: float, forward_bars: pd.DataFrame) -> dict:
    """
    Apply ATR triple-barrier labeling to a single signal.
    forward_bars: M15 OHLC rows AFTER the signal bar (in order).
    """
    if atr <= 0 or len(forward_bars) == 0:
        return None

    sl_level  = entry - atr        # -1R
    tp1_level = entry + 1.0 * atr  # +1R
    tp2_level = entry + 2.0 * atr  # +2R
    tp3_level = entry + 3.0 * atr  # +3R

    tp1_hit = tp2_hit = tp3_hit = 0
    sl_hit  = 0
    mfe_r   = 0.0
    mae_r   = 0.0
    bars_to_outcome = len(forward_bars)  # default = time barrier

    for i, (_, bar) in enumerate(forward_bars.iterrows()):
        high = bar["High"]
        low  = bar["Low"]

        # Track MFE/MAE
        mfe_r = max(mfe_r, (high - entry) / atr)
        mae_r = max(mae_r, (entry - low)  / atr)

        # Check SL first (conservative — if same bar hits both, SL wins)
        hit_sl  = low  <= sl_level
        hit_tp1 = high >= tp1_level
        hit_tp2 = high >= tp2_level
        hit_tp3 = high >= tp3_level

        if hit_sl and not (hit_tp1):
            sl_hit = 1
            bars_to_outcome = i + 1
            break

        if hit_tp1:
            tp1_hit = 1
            bars_to_outcome = i + 1
            if hit_tp2:
                tp2_hit = 1
            if hit_tp3:
                tp3_hit = 1
            # Continue scanning for tp2/tp3 if not yet hit
            if tp2_hit and tp3_hit:
                break
            # Keep scanning for higher TPs (SL already passed this bar)
            if not tp2_hit or not tp3_hit:
                # Scan remaining bars for tp2/tp3
                for _, bar2 in forward_bars.iloc[i+1:].iterrows():
                    mfe_r = max(mfe_r, (bar2["High"] - entry) / atr)
                    mae_r = max(mae_r, (entry - bar2["Low"])  / atr)
                    if not tp2_hit and bar2["High"] >= tp2_level:
                        tp2_hit = 1
                    if not tp3_hit and bar2["High"] >= tp3_level:
                        tp3_hit = 1
                    if bar2["Low"] <= sl_level:
                        break  # SL hit while hunting higher TP
                    if tp2_hit and tp3_hit:
                        break
            break

        if hit_sl:  # SL on same bar as no TP
            sl_hit = 1
            bars_to_outcome = i + 1
            break

    return {
        "win_loss":        tp1_hit,
        "tp1_hit":         tp1_hit,
        "tp2_hit":         tp2_hit,
        "tp3_hit":         tp3_hit,
        "sl_hit":          sl_hit,
        "mfe_r":           round(mfe_r, 3),
        "mae_r":           round(mae_r, 3),
        "bars_to_outcome": bars_to_outcome,
        "entry_price":     round(entry, 5),
        "atr_1r":          round(atr, 4),
    }


def run(signals_path: Path, bars_path: Path, output_path: Path,
        lookahead: int = 20, min_atr: float = 0.3):

    print("\n" + "="*60)
    print(" ATR Triple-Barrier Signal Labeling")
    print("="*60)

    # ── Load data ──
    sig = pd.read_csv(signals_path)
    bars = pd.read_csv(bars_path)

    sig["ts"]  = pd.to_datetime(sig["Timestamp"], format="%Y.%m.%d %H:%M:%S")
    bars["ts"] = pd.to_datetime(bars["Date"],      format="%Y.%m.%d %H:%M")
    bars = bars.sort_values("ts").reset_index(drop=True)

    print(f"\nSignals loaded:  {len(sig):,}")
    print(f"Bars loaded:     {len(bars):,}  ({bars['Date'].iloc[0]} → {bars['Date'].iloc[-1]})")

    # ── Filter to LONG signals within bar window ──
    long = sig[sig["Direction"] == "LONG"].copy()
    long = long[long["ATR14_Pips"] >= min_atr]  # remove near-zero ATR rows
    bar_start = bars["ts"].min()
    bar_end   = bars["ts"].max()
    long = long[(long["ts"] >= bar_start) & (long["ts"] <= bar_end - pd.Timedelta(minutes=15*lookahead))]
    long = long.reset_index(drop=True)

    print(f"\nLONG signals in bar window (ATR≥{min_atr}): {len(long):,}")
    print(f"Lookahead: {lookahead} bars ({lookahead*15} minutes)")

    # Build bar timestamp index for fast lookup
    bar_ts_arr = bars["ts"].values

    # ── Label each signal ──
    records = []
    skipped = 0

    for _, row in tqdm(long.iterrows(), total=len(long), desc="Labeling"):
        sig_ts = row["ts"]

        # Find index of signal bar in bars array
        idx = np.searchsorted(bar_ts_arr, sig_ts, side="left")
        if idx >= len(bars):
            skipped += 1
            continue

        # Entry = Close of signal bar (or next bar if exact match not found)
        entry_bar = bars.iloc[idx] if bars.iloc[idx]["ts"] == sig_ts else \
                    (bars.iloc[idx] if idx < len(bars) else None)
        if entry_bar is None:
            skipped += 1
            continue

        entry = entry_bar["Close"]
        atr   = row["ATR14_Pips"]

        # Forward bars
        fwd_end = min(idx + 1 + lookahead, len(bars))
        forward = bars.iloc[idx+1:fwd_end]

        if len(forward) < 3:
            skipped += 1
            continue

        label = label_one(entry, atr, forward)
        if label is None:
            skipped += 1
            continue

        record = {
            "SetupID":      row["SetupID"],
            "Timestamp":    row["Timestamp"],
            "DayOfWeek":    row["DayOfWeek"],
            "Trade_Executed": row["Trade_Executed"],
            "Rejected_Step":  row.get("Rejected_Step", ""),
            # Features (same as production ML pipeline)
            "WeeklyBias":   row["WeeklyBias"],
            "DailyBias":    row["DailyBias"],
            "H4Bias":       row["H4Bias"],
            "H1Bias":       row["H1Bias"],
            "PDH_Sweep":    row["PDH_Sweep"],
            "PDL_Sweep":    row["PDL_Sweep"],
            "PWH_Sweep":    row["PWH_Sweep"],
            "PWL_Sweep":    row["PWL_Sweep"],
            "Asian_Sweep":  row["Asian_Sweep"],
            "EQH_Sweep":    row["EQH_Sweep"],
            "EQL_Sweep":    row["EQL_Sweep"],
            "MSS":          row["MSS"],
            "Displacement": row["Displacement"],
            "FVG_Present":  row["FVG_Present"],
            "OB_Present":   row["OB_Present"],
            "ADR_Status":   row["ADR_Status"],
            "PremDisc_Status": row["PremDisc_Status"],
            "Session":      row["Session"],
            "MarketCondition": row["MarketCondition"],
            "ConfluenceScore": row["ConfluenceScore"],
            "ATR14_Pips":   row["ATR14_Pips"],
            "ATR50_Pips":   row["ATR50_Pips"],
            "Spread_Pips":  row["Spread_Pips"],
            "SpreadPctATR": row["SpreadPctATR"],
            "ADX_Value":    row["ADX_Value"],
            "Score_Weekly": row["Score_Weekly"],
            "Score_Daily":  row["Score_Daily"],
            "Score_LiqSweep": row["Score_LiqSweep"],
            "Score_MSS":    row["Score_MSS"],
            "Score_Displacement": row["Score_Displacement"],
            "Score_FVG":    row["Score_FVG"],
            "Score_Killzone": row["Score_Killzone"],
            "Score_SMT":    row["Score_SMT"],
            "Score_ADR":    row["Score_ADR"],
            "Score_PO3":    row["Score_PO3"],
            "Score_PremDisc": row["Score_PremDisc"],
            "Score_H4Align": row["Score_H4Align"],
            "Score_H1Align": row["Score_H1Align"],
            "OB_Score":     row["OB_Score"],
            "Cond_Score":   row["Cond_Score"],
        }
        record.update(label)
        records.append(record)

    df_out = pd.DataFrame(records)

    print(f"\nLabeled:  {len(df_out):,}")
    print(f"Skipped:  {skipped:,}")
    print(f"\nOutcome distribution:")
    print(f"  win_loss (tp1): {df_out['win_loss'].mean()*100:.1f}% positive")
    print(f"  tp2_hit:        {df_out['tp2_hit'].mean()*100:.1f}% positive")
    print(f"  tp3_hit:        {df_out['tp3_hit'].mean()*100:.1f}% positive")
    print(f"  sl_hit:         {df_out['sl_hit'].mean()*100:.1f}%")
    print(f"  time barrier:   {((df_out['sl_hit']==0)&(df_out['win_loss']==0)).mean()*100:.1f}%")
    print(f"\n  MFE (mean R):   {df_out['mfe_r'].mean():.3f}")
    print(f"  MAE (mean R):   {df_out['mae_r'].mean():.3f}")

    # Executed vs non-executed comparison
    ex  = df_out[df_out["Trade_Executed"] == "YES"]
    nex = df_out[df_out["Trade_Executed"] == "NO"]
    print(f"\nExecuted trades in labeled set:     {len(ex)}")
    print(f"  win_loss: {ex['win_loss'].mean()*100:.1f}%  |  tp2: {ex['tp2_hit'].mean()*100:.1f}%  |  tp3: {ex['tp3_hit'].mean()*100:.1f}%")
    print(f"Non-executed signals in labeled set: {len(nex)}")
    print(f"  win_loss: {nex['win_loss'].mean()*100:.1f}%  |  tp2: {nex['tp2_hit'].mean()*100:.1f}%  |  tp3: {nex['tp3_hit'].mean()*100:.1f}%")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    df_out.to_csv(output_path, index=False)
    print(f"\n✓ Saved: {output_path}")
    return df_out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--signals",   type=Path, default=DEFAULT_SIGNALS)
    parser.add_argument("--bars",      type=Path, default=DEFAULT_BARS)
    parser.add_argument("--output",    type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--lookahead", type=int,  default=20,
                        help="Max bars to scan forward (default 20 = 5hrs on M15)")
    parser.add_argument("--min-atr",   type=float, default=0.3,
                        help="Minimum ATR14_Pips to include signal (default 0.3)")
    args = parser.parse_args()
    run(args.signals, args.bars, args.output, args.lookahead, args.min_atr)


if __name__ == "__main__":
    main()
