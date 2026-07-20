"""
Data loading, cleaning, feature engineering for ICT ATLAS Phase 1D-B ML pipeline.
All features are derived from information available at trade ENTRY — no leakage.
"""

import pandas as pd
import numpy as np
from pathlib import Path


# ── Constants ────────────────────────────────────────────────────────────────

BIAS_MAP    = {"BULLISH": 1, "NEUTRAL": 0, "BEARISH": -1}
COND_MAP    = {"TRENDING": 2, "RANGING": 1, "CHOPPY": 0}
SESSION_MAP = {"NEWYORK": 1, "NONE": 0}
DAY_MAP     = {"Monday": 0, "Tuesday": 1, "Wednesday": 2, "Thursday": 3, "Friday": 4}
PREMDSC_MAP = {"PREMIUM": 1, "OK": 0, "DISCOUNT": -1, "BLOCKED": -2}
ADR_MAP     = {"OK": 1, "BLOCKED": 0}
YN_MAP      = {"YES": 1, "NO": 0}

# Columns that are constant in Phase 1D-B (all LONG, all MSS=YES, all A+)
CONSTANT_COLS = ["Direction", "Symbol", "MSS", "Grade", "Score_MSS"]

# Columns that are outcomes / would cause leakage
LEAKAGE_COLS = [
    "Profit_USD", "Profit_Pct", "RR_Achieved", "MFE_Pips", "MAE_Pips",
    "MinutesInTrade", "BarsInTrade", "ExitReason",
    "Trade_Result", "TP1_Hit", "TP2_Hit", "TP3_Hit", "BreakEven_Triggered",
]

# Identifier / price level columns (not predictive features)
META_COLS = [
    "SetupID", "Ticket", "OpenTime", "CloseTime",
    "EntryPrice", "StopLoss", "TakeProfit", "LotSize", "RiskPct",
]


# ── Loading ───────────────────────────────────────────────────────────────────

def load_trades(path: str | Path) -> pd.DataFrame:
    df = pd.read_csv(path, parse_dates=["OpenTime", "CloseTime"])
    print(f"Loaded {len(df)} trades, {df.shape[1]} columns.")
    return df


# ── Target Variables ──────────────────────────────────────────────────────────

def build_targets(df: pd.DataFrame) -> pd.DataFrame:
    """
    Construct all ML target variables.
    TP1/TP2/TP3 are derived from RR_Achieved (EA tracking is unreliable).
    """
    t = pd.DataFrame(index=df.index)
    t["win_loss"]   = (df["Trade_Result"] == "WIN").astype(int)
    t["rr_achieved"] = df["RR_Achieved"].clip(-5, 10)   # clip extreme outliers
    t["tp1_hit"]    = (df["RR_Achieved"] >= 1.0).astype(int)
    t["tp2_hit"]    = (df["RR_Achieved"] >= 2.0).astype(int)
    t["tp3_hit"]    = (df["RR_Achieved"] >= 3.0).astype(int)
    return t


# ── Feature Engineering ───────────────────────────────────────────────────────

def build_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Build feature matrix from entry-time columns only.
    Returns a DataFrame with clean numeric features.
    """
    X = pd.DataFrame(index=df.index)

    # ── Time features ──
    X["hour"]      = df["OpenTime"].dt.hour
    X["month"]     = df["OpenTime"].dt.month
    X["day_of_week"] = df["DayOfWeek"].map(DAY_MAP)

    # ── Session ──
    X["session_ny"] = df["Session"].map(SESSION_MAP).fillna(0)

    # ── Bias alignment ──
    X["weekly_bias"]  = df["WeeklyBias"].map(BIAS_MAP)
    X["daily_bias"]   = df["DailyBias"].map(BIAS_MAP)
    X["h4_bias"]      = df["H4Bias"].map(BIAS_MAP)
    X["h1_bias"]      = df["H1Bias"].map(BIAS_MAP)

    # Combined bias strength (count of aligned timeframes for LONG direction)
    X["bias_alignment"] = (
        (X["weekly_bias"] == 1).astype(int) +
        (X["daily_bias"]  == 1).astype(int) +
        (X["h4_bias"]     == 1).astype(int) +
        (X["h1_bias"]     == 1).astype(int)
    )

    # ── Liquidity sweeps ──
    sweep_cols = ["PDH_Sweep", "PDL_Sweep", "PWH_Sweep", "PWL_Sweep",
                  "Asian_Sweep", "EQH_Sweep", "EQL_Sweep"]
    for col in sweep_cols:
        X[col.lower()] = df[col].map(YN_MAP)
    X["sweep_count"] = X[[c.lower() for c in sweep_cols]].sum(axis=1)

    # ── Structure ──
    X["displacement"]  = df["Displacement"].map(YN_MAP)
    X["fvg_present"]   = df["FVG_Present"].map(YN_MAP)
    X["ob_present"]    = df["OB_Present"].map(YN_MAP)

    # ── Market context ──
    X["adr_ok"]        = df["ADR_Status"].map(ADR_MAP).fillna(0)
    X["prem_disc"]     = df["PremDisc_Status"].map(PREMDSC_MAP).fillna(0)
    X["market_cond"]   = df["MarketCondition"].map(COND_MAP)

    # ── Volatility & spread ──
    X["atr14"]         = df["ATR14_Pips_Entry"]
    X["atr50"]         = df["ATR50_Pips_Entry"]
    X["atr_ratio"]     = (df["ATR14_Pips_Entry"] / df["ATR50_Pips_Entry"].replace(0, np.nan)).fillna(1.0)
    X["spread_pips"]   = df["Spread_Pips_Entry"]
    X["spread_pct_atr"] = df["SpreadPctATR_Entry"]
    X["adx"]           = df["ADX_Entry"]

    # ── Confluence scores (individual components) ──
    score_cols = [
        "Score_Weekly", "Score_Daily", "Score_LiqSweep", "Score_Displacement",
        "Score_FVG", "Score_Killzone", "Score_SMT", "Score_ADR",
        "Score_PO3", "Score_PremDisc",
    ]
    for col in score_cols:
        X[col.lower()] = df[col]

    X["confluence_score"] = df["ConfluenceScore"]

    # ── New Phase 1C+ ML score columns ──
    X["score_h4align"]  = df["Score_H4Align"]   # +1 / 0 / -1
    X["score_h1align"]  = df["Score_H1Align"]   # +1 / 0 / -1
    X["ob_score"]       = df["OB_Score"]         # 0 / 1
    X["cond_score"]     = df["Cond_Score"]       # 0=CHOPPY / 1=RANGING / 2=TRENDING

    # ── Derived composite features ──
    X["vol_regime"]    = X["adx"] * X["atr14"]  # ADX × ATR = volatility-momentum
    X["spread_quality"] = 1.0 - (X["spread_pips"] / X["atr14"].replace(0, np.nan)).fillna(0).clip(0, 1)

    # PlannedRR is constant (3.0) in Phase 1D-B but keep in case it varies
    X["planned_rr"] = df["PlannedRR"]

    # Verify no NaN
    na_counts = X.isna().sum()
    if na_counts.any():
        print("Warning: NaN values found:\n", na_counts[na_counts > 0])
        X = X.fillna(0)

    return X


# ── Full Preprocessing Pipeline ───────────────────────────────────────────────

def prepare(path: str | Path):
    """
    Full pipeline: load → engineer features → build targets.
    Returns (X, targets, raw_df).
    """
    df = load_trades(path)
    X = build_features(df)
    targets = build_targets(df)

    print(f"\nFeature matrix: {X.shape}")
    print(f"Targets:\n{targets.describe().T[['mean','std','min','max']].round(3)}")

    return X, targets, df


def feature_names(X: pd.DataFrame) -> list[str]:
    return list(X.columns)


if __name__ == "__main__":
    import sys
    path = sys.argv[1] if len(sys.argv) > 1 else "../data/ICT_ATLAS_Phase1DB_Trades.csv"
    X, targets, df = prepare(path)
    print("\nFirst 3 rows of features:")
    print(X.head(3).T)
