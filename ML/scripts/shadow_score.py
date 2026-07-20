"""
shadow_score.py — Offline shadow validation scorer for Atlas EA V1.1.

Two validation tracks:

  --mode trades   (default) Executed Phase 1D-B trades only.
                  Reads ICT_ATLAS_Phase1DB_Trades.csv. Outcome from Trade_Result.
                  ~42 signals/year. Clinically relevant for gate activation.

  --mode signals  All Atlas signals (executed + non-executed), ATR-labeled.
                  Reads ICT_ATLAS_Research_Signals_Labeled_v2.csv or a fresh
                  labeled CSV from label_signals.py. ~2,880 signals/year.
                  Provides rapid discrimination evidence (statistical significance
                  achievable in 2–4 months vs 14+ months for trades-only track).

Run monthly after exporting updated trade history and M15 bars from MT5.

Usage:
    # Executed-trade track (primary — gate activation criterion):
    python ML/scripts/shadow_score.py --mode trades

    # All-signals track (accelerated discrimination evidence):
    python ML/scripts/shadow_score.py --mode signals --signals PATH_TO_LABELED_CSV
"""

import argparse
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from scipy import stats

sys.path.insert(0, str(Path(__file__).parent.parent))

MODEL_PATH    = Path(__file__).parent.parent / "outputs" / "research_v2" / "models" / "LightGBM_win_loss.pkl"
TRADES_PATH   = Path(__file__).parent.parent / "data" / "ICT_ATLAS_Phase1DB_Trades.csv"
SIGNALS_PATH  = Path(__file__).parent.parent / "data" / "ICT_ATLAS_Research_Signals_Labeled_v2.csv"
OUTPUT_DIR    = Path(__file__).parent.parent / "outputs" / "research_v2" / "shadow"

THRESHOLD = 0.52


# ── Feature builder (mirrors run_research_pipeline.py) ────────────────────────

BIAS_MAP    = {"BULLISH": 1, "NEUTRAL": 0, "BEARISH": -1}
COND_MAP    = {"TRENDING": 2, "RANGING": 1, "CHOPPY": 0}
SESSION_MAP = {"NEWYORK": 1, "NONE": 0}
PREMDSC_MAP = {"PREMIUM": 1, "OK": 0, "DISCOUNT": -1, "BLOCKED": -2}
ADR_MAP     = {"OK": 1, "BLOCKED": 0}
YN_MAP      = {"YES": 1, "NO": 0}
DAY_MAP     = {"Monday": 0, "Tuesday": 1, "Wednesday": 2, "Thursday": 3, "Friday": 4}


def build_features_from_trades(df: pd.DataFrame) -> pd.DataFrame:
    """Build ML feature matrix from Phase 1D-B trade CSV format."""
    X = pd.DataFrame(index=df.index)

    df["ts"] = pd.to_datetime(df["OpenTime"])
    X["hour"]        = df["ts"].dt.hour
    X["month"]       = df["ts"].dt.month
    X["day_of_week"] = df["ts"].dt.dayofweek   # 0=Mon

    # These columns may exist in the trade CSV under different names;
    # map what we have, fill zeros for what is missing.
    def col(name, default=0):
        if name in df.columns:
            return df[name]
        return pd.Series(default, index=df.index)

    X["session_ny"]    = col("Session").map(SESSION_MAP).fillna(0)
    X["weekly_bias"]   = col("WeeklyBias").map(BIAS_MAP).fillna(0)
    X["daily_bias"]    = col("DailyBias").map(BIAS_MAP).fillna(0)
    X["h4_bias"]       = col("H4Bias").map(BIAS_MAP).fillna(0)
    X["h1_bias"]       = col("H1Bias").map(BIAS_MAP).fillna(0)
    X["bias_alignment"] = (
        (X["weekly_bias"] == 1).astype(int) + (X["daily_bias"] == 1).astype(int) +
        (X["h4_bias"]     == 1).astype(int) + (X["h1_bias"]    == 1).astype(int)
    )

    sweep_cols = ["PDH_Sweep","PDL_Sweep","PWH_Sweep","PWL_Sweep",
                  "Asian_Sweep","EQH_Sweep","EQL_Sweep"]
    for c in sweep_cols:
        X[c.lower()] = col(c).map(YN_MAP).fillna(0)
    X["sweep_count"] = X[[c.lower() for c in sweep_cols]].sum(axis=1)

    X["displacement"]   = col("Displacement").map(YN_MAP).fillna(0)
    X["fvg_present"]    = col("FVG_Present").map(YN_MAP).fillna(0)
    X["ob_present"]     = col("OB_Present").map(YN_MAP).fillna(0)
    X["adr_ok"]         = col("ADR_Status").map(ADR_MAP).fillna(0)
    X["prem_disc"]      = col("PremDisc_Status").map(PREMDSC_MAP).fillna(0)
    X["market_cond"]    = col("MarketCondition").map(COND_MAP).fillna(1)
    X["mss_present"]    = col("MSS").map(YN_MAP).fillna(1)   # MSS required in Phase 1D-B

    X["atr14"]          = col("ATR14_Pips", 20.0)
    X["atr50"]          = col("ATR50_Pips", 28.0)
    X["atr_ratio"]      = (X["atr14"] / X["atr50"].replace(0, np.nan)).fillna(1.0)
    X["spread_pips"]    = col("Spread_Pips", 0.3)
    X["spread_pct_atr"] = col("SpreadPctATR", 1.5)
    X["adx"]            = col("ADX_Value", 25.0)
    X["vol_regime"]     = X["adx"] * X["atr14"]
    X["spread_quality"] = (1.0 - (X["spread_pips"] / X["atr14"].replace(0, np.nan)).fillna(0)).clip(0, 1)

    score_cols = ["Score_Weekly","Score_Daily","Score_LiqSweep","Score_MSS",
                  "Score_Displacement","Score_FVG","Score_Killzone","Score_SMT",
                  "Score_ADR","Score_PO3","Score_PremDisc"]
    for c in score_cols:
        X[c.lower()] = col(c, 0)
    X["confluence_score"] = col("ConfluenceScore", 0)
    X["score_h4align"]    = col("Score_H4Align", 0)
    X["score_h1align"]    = col("Score_H1Align", 0)
    X["ob_score"]         = col("OB_Score", 0)
    X["cond_score"]       = col("Cond_Score", 0)

    return X.fillna(0)


# ── Statistics ─────────────────────────────────────────────────────────────────

def chi2_test(a_wins, a_n, b_wins, b_n):
    """One-sided chi-squared test: P(accepted WR > rejected WR)."""
    a_loss = a_n - a_wins
    b_loss = b_n - b_wins
    if a_n == 0 or b_n == 0:
        return float("nan"), float("nan")
    table = np.array([[a_wins, a_loss], [b_wins, b_loss]])
    chi2, p, _, _ = stats.chi2_contingency(table)
    return chi2, p


def equity_curve(outcomes):
    """Build cumulative R equity curve (win=+1, loss=-1, neutral=-0.2)."""
    pnl = np.where(outcomes == 1, 1.0, -1.0)
    return np.cumsum(pnl)


# ── Main ───────────────────────────────────────────────────────────────────────

def run(trades_path: Path, output_dir: Path, threshold: float):
    output_dir.mkdir(parents=True, exist_ok=True)

    print("\n" + "="*60)
    print(" Atlas EA V1.1 — Shadow Validation Scorer")
    print("="*60)

    # Load model
    with open(MODEL_PATH, "rb") as f:
        bundle = joblib.load(f)
    model, scaler = bundle["model"], bundle["scaler"]

    # Load trades
    trades = pd.read_csv(trades_path)
    print(f"\nTrades loaded: {len(trades):,}  ({trades_path.name})")

    # Determine win/loss outcome
    if "Trade_Result" in trades.columns:
        trades["outcome"] = (trades["Trade_Result"].str.upper() == "WIN").astype(int)
    elif "TP1_Hit" in trades.columns:
        trades["outcome"] = trades["TP1_Hit"].astype(int)
    elif "win_loss" in trades.columns:
        trades["outcome"] = trades["win_loss"].astype(int)
    elif "Profit_USD" in trades.columns:
        trades["outcome"] = (trades["Profit_USD"] > 0).astype(int)
    else:
        raise ValueError(f"Cannot find win/loss column. Available: {list(trades.columns)}")

    # Normalise ATR column names (trade CSV uses _Entry suffix)
    col_map = {"ATR14_Pips_Entry": "ATR14_Pips", "ATR50_Pips_Entry": "ATR50_Pips",
               "Spread_Pips_Entry": "Spread_Pips", "SpreadPctATR_Entry": "SpreadPctATR",
               "ADX_Entry": "ADX_Value"}
    trades = trades.rename(columns={k: v for k, v in col_map.items() if k in trades.columns})

    # Build features and score
    X   = build_features_from_trades(trades)
    X_s = scaler.transform(X)
    trades["ml_score"]    = model.predict_proba(X_s)[:, 1]
    trades["ml_decision"] = (trades["ml_score"] >= threshold).map({True: "TAKEN", False: "REJECTED"})
    trades["ml_threshold"] = threshold
    trades["ml_version"]   = "v2"

    taken    = trades[trades["ml_decision"] == "TAKEN"]
    rejected = trades[trades["ml_decision"] == "REJECTED"]

    # Summary statistics
    def stats_block(subset, label):
        if len(subset) == 0:
            return {}
        wr   = subset["outcome"].mean() * 100
        wins = subset["outcome"].sum()
        gl   = len(subset) - wins
        pf   = wins / gl if gl > 0 else float("inf")
        exp  = subset["outcome"].apply(lambda x: 1.0 if x else -1.0).mean()
        return {"label": label, "n": len(subset), "wins": int(wins), "losses": int(gl),
                "win_rate": wr, "profit_factor": pf, "expectancy_r": exp}

    all_s  = stats_block(trades, "All trades (no gate)")
    take_s = stats_block(taken,  f"TAKEN (score >= {threshold})")
    rej_s  = stats_block(rejected, f"REJECTED (score < {threshold})")

    chi2, p_val = chi2_test(take_s.get("wins", 0), take_s.get("n", 0),
                             rej_s.get("wins", 0),  rej_s.get("n", 0))

    print(f"\n{'─'*60}")
    print(f" SHADOW VALIDATION REPORT — Threshold {threshold}")
    print(f"{'─'*60}")
    for s in [all_s, take_s, rej_s]:
        if not s: continue
        print(f"\n  {s['label']}")
        print(f"    Trades:      {s['n']}")
        print(f"    Win Rate:    {s['win_rate']:.1f}%  ({s['wins']}W / {s['losses']}L)")
        print(f"    Profit Factor: {s['profit_factor']:.3f}")
        print(f"    Expectancy:  {s['expectancy_r']:+.3f}R")

    print(f"\n  Discrimination test (TAKEN vs REJECTED win rates):")
    print(f"    Chi2 = {chi2:.3f}   p-value = {p_val:.4f}")
    if p_val < 0.05:
        print(f"    *** SIGNIFICANT — model discriminates at p < 0.05")
    elif p_val < 0.10:
        print(f"    *   MARGINAL — model shows discrimination at p < 0.10")
    else:
        print(f"    NOT YET SIGNIFICANT — continue accumulating data")

    # Minimum sample check
    n_taken = take_s.get("n", 0)
    print(f"\n  Sample progress toward activation criteria:")
    print(f"    Trades scored:   {len(trades)} / 50 minimum")
    print(f"    TAKEN trades:    {n_taken}")
    print(f"    p-value:         {p_val:.4f} (target: < 0.10)")
    if n_taken > 0:
        print(f"    TAKEN win rate:  {take_s['win_rate']:.1f}% (target: > 52%)")

    activation_ready = (
        len(trades) >= 50 and
        p_val < 0.10 and
        take_s.get("win_rate", 0) > 52.0
    )
    print(f"\n  Gate activation: {'✓ CRITERIA MET — proceed to live gating' if activation_ready else '✗ NOT YET READY'}")

    # Save scored trades
    out_trades = output_dir / "shadow_trades_scored.csv"
    trades.to_csv(out_trades, index=False)

    # Save summary
    summary = pd.DataFrame([all_s, take_s, rej_s])
    summary["chi2"]    = chi2
    summary["p_value"] = p_val
    summary["n_total"] = len(trades)
    summary["threshold"] = threshold
    out_summary = output_dir / "shadow_summary.csv"
    summary.to_csv(out_summary, index=False)

    print(f"\n  ✓ Scored trades saved: {out_trades.name}")
    print(f"  ✓ Summary saved:       {out_summary.name}")
    print("="*60)


def run_signals(signals_path: Path, output_dir: Path, threshold: float):
    """All-signals shadow track: score ATR-labeled signals from label_signals.py output."""
    output_dir.mkdir(parents=True, exist_ok=True)

    print("\n" + "="*60)
    print(" Atlas EA V1.1 — Shadow Validation (ALL-SIGNALS TRACK)")
    print("="*60)

    with open(MODEL_PATH, "rb") as f:
        bundle = joblib.load(f)
    model, scaler = bundle["model"], bundle["scaler"]

    signals = pd.read_csv(signals_path)
    print(f"\nSignals loaded: {len(signals):,}  ({signals_path.name})")
    print(f"  Executed trades: {(signals['Trade_Executed']=='YES').sum()}")
    print(f"  Non-executed:    {(signals['Trade_Executed']=='NO').sum()}")

    # Score using the research pipeline feature builder (columns match exactly)
    from run_research_pipeline import build_features
    X   = build_features(signals)
    X_s = scaler.transform(X)
    signals["ml_score"]    = model.predict_proba(X_s)[:, 1]
    signals["ml_decision"] = (signals["ml_score"] >= threshold).map({True: "TAKEN", False: "REJECTED"})
    signals["outcome"]     = signals["win_loss"]   # ATR barrier win_loss label

    taken    = signals[signals["ml_decision"] == "TAKEN"]
    rejected = signals[signals["ml_decision"] == "REJECTED"]

    def stats_block(subset, label):
        if len(subset) == 0: return {}
        wr   = subset["outcome"].mean() * 100
        wins = int(subset["outcome"].sum())
        gl   = len(subset) - wins
        pf   = wins / gl if gl > 0 else float("inf")
        exp  = subset["outcome"].apply(lambda x: 1.0 if x else -1.0).mean()
        return {"label": label, "n": len(subset), "wins": wins, "losses": gl,
                "win_rate": wr, "profit_factor": pf, "expectancy_r": exp}

    all_s  = stats_block(signals, "All signals (no gate)")
    take_s = stats_block(taken,   f"TAKEN (score >= {threshold})")
    rej_s  = stats_block(rejected, f"REJECTED (score < {threshold})")

    chi2, p_val = chi2_test(take_s.get("wins", 0), take_s.get("n", 0),
                             rej_s.get("wins", 0),  rej_s.get("n", 0))

    print(f"\n{'─'*60}")
    print(f" ALL-SIGNALS SHADOW REPORT — Threshold {threshold}")
    print(f"{'─'*60}")
    for s in [all_s, take_s, rej_s]:
        if not s: continue
        print(f"\n  {s['label']}")
        print(f"    Signals:       {s['n']:,}")
        print(f"    Win Rate:      {s['win_rate']:.1f}%  ({s['wins']}W / {s['losses']}L)")
        print(f"    Profit Factor: {s['profit_factor']:.3f}")
        print(f"    Expectancy:    {s['expectancy_r']:+.3f}R")

    print(f"\n  Discrimination test (TAKEN vs REJECTED win rates):")
    print(f"    Chi2 = {chi2:.3f}   p-value = {p_val:.4f}")
    if p_val < 0.01:
        print(f"    *** HIGHLY SIGNIFICANT (p < 0.01)")
    elif p_val < 0.05:
        print(f"    **  SIGNIFICANT (p < 0.05)")
    elif p_val < 0.10:
        print(f"    *   MARGINAL (p < 0.10)")
    else:
        print(f"    NOT SIGNIFICANT — model may not be discriminating in live data")

    print(f"\n  Rapid-validation criteria (all-signals track):")
    print(f"    Signals scored:  {len(signals):,} / 200 minimum")
    print(f"    p-value:         {p_val:.4f} (target < 0.05)")
    if take_s.get("n", 0) > 0:
        print(f"    TAKEN win rate:  {take_s['win_rate']:.1f}% (target > 52%)")

    rapid_ok = (
        len(signals) >= 200 and
        p_val < 0.05 and
        take_s.get("win_rate", 0) > 52.0
    )
    print(f"\n  Rapid-validation: {'✓ EVIDENCE SUFFICIENT — proceed to executed-trade gate assessment' if rapid_ok else '✗ CONTINUE ACCUMULATING'}")
    print(f"  Note: rapid-validation supports but does not replace executed-trade gate criteria.")

    out = output_dir / "shadow_signals_scored.csv"
    signals.to_csv(out, index=False)

    summary = pd.DataFrame([all_s, take_s, rej_s])
    summary["chi2"] = chi2; summary["p_value"] = p_val
    summary["n_total"] = len(signals); summary["threshold"] = threshold
    summary["track"] = "all_signals"
    out_s = output_dir / "shadow_signals_summary.csv"
    summary.to_csv(out_s, index=False)

    print(f"\n  ✓ Scored signals saved: {out.name}")
    print(f"  ✓ Summary saved:        {out_s.name}")
    print("="*60)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode",      choices=["trades", "signals"], default="trades",
                        help="trades=executed trades only (gate activation); signals=all labeled signals (rapid validation)")
    parser.add_argument("--trades",    type=Path, default=TRADES_PATH)
    parser.add_argument("--signals",   type=Path, default=SIGNALS_PATH)
    parser.add_argument("--output",    type=Path, default=OUTPUT_DIR)
    parser.add_argument("--threshold", type=float, default=THRESHOLD)
    args = parser.parse_args()

    if args.mode == "signals":
        run_signals(args.signals, args.output, args.threshold)
    else:
        run(args.trades, args.output, args.threshold)


if __name__ == "__main__":
    main()
