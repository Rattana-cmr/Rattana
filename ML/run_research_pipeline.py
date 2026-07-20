"""
ICT ATLAS EA — Research Track ML Pipeline
==========================================
Trains RF, XGBoost, LightGBM on the ATR Triple-Barrier labeled signal dataset.
This is a SEPARATE research track — completely independent of Phase 1D-B.

Targets:
  win_loss  = price reached +1R before -1R (within 20 bars)
  tp2_hit   = price reached +2R before -1R
  tp3_hit   = price reached +3R before -1R

Usage:
    python run_research_pipeline.py [--data PATH] [--output-dir PATH]
"""

import sys
import warnings
warnings.filterwarnings("ignore")
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from sklearn.preprocessing import StandardScaler
from sklearn.base import clone

sys.path.insert(0, str(Path(__file__).parent))
from src.models   import get_classifiers, cv_classify, save_model
from src.evaluate import plot_roc_curves, plot_pr_curves, plot_feature_importance, threshold_analysis, plot_threshold_analysis
from src.shap_utils import compute_shap, plot_shap_summary, plot_shap_bar, top_shap_features

DATA_PATH  = Path(__file__).parent / "data" / "ICT_ATLAS_Research_Signals_Labeled.csv"
OUTPUT_DIR = Path(__file__).parent / "outputs" / "research"

BIAS_MAP    = {"BULLISH": 1, "NEUTRAL": 0, "BEARISH": -1}
COND_MAP    = {"TRENDING": 2, "RANGING": 1, "CHOPPY": 0}
SESSION_MAP = {"NEWYORK": 1, "NONE": 0}
PREMDSC_MAP = {"PREMIUM": 1, "OK": 0, "DISCOUNT": -1, "BLOCKED": -2}
ADR_MAP     = {"OK": 1, "BLOCKED": 0}
YN_MAP      = {"YES": 1, "NO": 0}
DAY_MAP     = {"Monday": 0, "Tuesday": 1, "Wednesday": 2, "Thursday": 3, "Friday": 4}

CLASSIFY_TARGETS = ["win_loss", "tp2_hit", "tp3_hit"]
N_SPLITS         = 5   # fewer folds due to smaller dataset
RANDOM_STATE     = 42


def build_features(df: pd.DataFrame) -> pd.DataFrame:
    X = pd.DataFrame(index=df.index)

    df["ts"] = pd.to_datetime(df["Timestamp"], format="%Y.%m.%d %H:%M:%S")
    X["hour"]        = df["ts"].dt.hour
    X["month"]       = df["ts"].dt.month
    X["day_of_week"] = df["DayOfWeek"].map(DAY_MAP)
    X["session_ny"]  = df["Session"].map(SESSION_MAP).fillna(0)

    X["weekly_bias"] = df["WeeklyBias"].map(BIAS_MAP)
    X["daily_bias"]  = df["DailyBias"].map(BIAS_MAP)
    X["h4_bias"]     = df["H4Bias"].map(BIAS_MAP)
    X["h1_bias"]     = df["H1Bias"].map(BIAS_MAP)
    X["bias_alignment"] = (
        (X["weekly_bias"] == 1).astype(int) +
        (X["daily_bias"]  == 1).astype(int) +
        (X["h4_bias"]     == 1).astype(int) +
        (X["h1_bias"]     == 1).astype(int)
    )

    sweep_cols = ["PDH_Sweep","PDL_Sweep","PWH_Sweep","PWL_Sweep",
                  "Asian_Sweep","EQH_Sweep","EQL_Sweep"]
    for col in sweep_cols:
        X[col.lower()] = df[col].map(YN_MAP)
    X["sweep_count"] = X[[c.lower() for c in sweep_cols]].sum(axis=1)

    X["displacement"]  = df["Displacement"].map(YN_MAP)
    X["fvg_present"]   = df["FVG_Present"].map(YN_MAP)
    X["ob_present"]    = df["OB_Present"].map(YN_MAP)
    X["adr_ok"]        = df["ADR_Status"].map(ADR_MAP).fillna(0)
    X["prem_disc"]     = df["PremDisc_Status"].map(PREMDSC_MAP).fillna(0)
    X["market_cond"]   = df["MarketCondition"].map(COND_MAP)
    X["mss_present"]   = df["MSS"].map(YN_MAP)  # KEY feature — MSS present or not

    X["atr14"]         = df["ATR14_Pips"]
    X["atr50"]         = df["ATR50_Pips"]
    X["atr_ratio"]     = (df["ATR14_Pips"] / df["ATR50_Pips"].replace(0, np.nan)).fillna(1.0)
    X["spread_pips"]   = df["Spread_Pips"]
    X["spread_pct_atr"] = df["SpreadPctATR"]
    X["adx"]           = df["ADX_Value"]
    X["vol_regime"]    = X["adx"] * X["atr14"]
    X["spread_quality"] = 1.0 - (X["spread_pips"] / X["atr14"].replace(0, np.nan)).fillna(0).clip(0, 1)

    score_cols = ["Score_Weekly","Score_Daily","Score_LiqSweep","Score_MSS",
                  "Score_Displacement","Score_FVG","Score_Killzone","Score_SMT",
                  "Score_ADR","Score_PO3","Score_PremDisc"]
    for col in score_cols:
        X[col.lower()] = df[col]
    X["confluence_score"] = df["ConfluenceScore"]
    X["score_h4align"] = df["Score_H4Align"]
    X["score_h1align"] = df["Score_H1Align"]
    X["ob_score"]      = df["OB_Score"]
    X["cond_score"]    = df["Cond_Score"]

    na = X.isna().sum()
    if na.any():
        X = X.fillna(0)
    return X


def summarise_cv(cv: dict) -> str:
    parts = []
    for m, vals in cv.items():
        parts.append(f"{m}: {np.mean(vals):.3f}±{np.std(vals):.3f}")
    return " | ".join(parts)


def run(data_path: Path, output_dir: Path):
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "models").mkdir(exist_ok=True)
    (output_dir / "plots").mkdir(exist_ok=True)
    (output_dir / "reports").mkdir(exist_ok=True)

    print("\n" + "="*60)
    print(" ICT ATLAS Research Track ML Pipeline")
    print(" ATR Triple-Barrier Signal Dataset")
    print("="*60)

    df = pd.read_csv(data_path)
    X  = build_features(df)
    feature_cols = list(X.columns)
    n = len(df)

    print(f"\nDataset: {n} labeled signals | {len(feature_cols)} features")
    print(f"\nTarget balance:")
    for t in CLASSIFY_TARGETS:
        pos = df[t].mean()
        print(f"  {t:12s}: {pos*100:.1f}% positive ({df[t].sum()}/{n})")

    print(f"\nExecuted vs non-executed:")
    ex  = df[df["Trade_Executed"]=="YES"]
    nex = df[df["Trade_Executed"]=="NO"]
    print(f"  Executed (Phase 1D-B trades): {len(ex)}")
    print(f"    win_loss: {ex['win_loss'].mean()*100:.1f}%  tp2: {ex['tp2_hit'].mean()*100:.1f}%  tp3: {ex['tp3_hit'].mean()*100:.1f}%")
    print(f"  Non-executed (MSS-rejected):  {len(nex)}")
    print(f"    win_loss: {nex['win_loss'].mean()*100:.1f}%  tp2: {nex['tp2_hit'].mean()*100:.1f}%  tp3: {nex['tp3_hit'].mean()*100:.1f}%")

    classifiers = get_classifiers(RANDOM_STATE)
    all_cv_rows = []

    print("\n" + "─"*60)
    print(" CLASSIFICATION — 5-fold Stratified CV")
    print("─"*60)

    best_results = {}

    for target_name in CLASSIFY_TARGETS:
        y = df[target_name]
        print(f"\n▶ Target: {target_name}  (positive={y.mean()*100:.1f}%)")

        target_probs = {}
        for model_name, model in classifiers.items():
            cv = cv_classify(model, X, y, N_SPLITS, RANDOM_STATE)
            print(f"  {model_name:12s}: {summarise_cv(cv)}")

            row = {"target": target_name, "model": model_name, "dataset": "research_signals"}
            for metric, vals in cv.items():
                row[f"{metric}_mean"] = np.mean(vals)
                row[f"{metric}_std"]  = np.std(vals)
            all_cv_rows.append(row)

            scaler = StandardScaler()
            X_s = scaler.fit_transform(X)
            m = clone(model)
            m.fit(X_s, y)
            proba = m.predict_proba(X_s)[:, 1]
            target_probs[model_name] = {"y_prob": proba, "y_true": y.values, "model": m, "scaler": scaler}
            save_model(m, scaler, output_dir / "models" / f"{model_name}_{target_name}.pkl")

        best_results[target_name] = target_probs

        plot_data = [{"name": mn, "y_true": v["y_true"], "y_prob": v["y_prob"]}
                     for mn, v in target_probs.items()]
        fig = plot_roc_curves(plot_data, target_name)
        fig.savefig(output_dir / "plots" / f"roc_{target_name}.png", dpi=120, bbox_inches="tight")
        plt.close(fig)

        fig = plot_pr_curves(plot_data, target_name)
        fig.savefig(output_dir / "plots" / f"pr_{target_name}.png", dpi=120, bbox_inches="tight")
        plt.close(fig)

    # ── Feature Importance ──
    print("\n" + "─"*60)
    print(" FEATURE IMPORTANCE — win_loss target")
    print("─"*60)

    importances = {}
    y_wl = df["win_loss"]
    for model_name, clf in classifiers.items():
        scaler = StandardScaler()
        X_s = scaler.fit_transform(X)
        m = clone(clf)
        m.fit(X_s, y_wl)
        imp = pd.Series(m.feature_importances_, index=feature_cols)
        importances[model_name] = imp
        print(f"\n  {model_name} top 10:")
        for feat, val in imp.nlargest(10).items():
            print(f"    {feat:25s}: {val:.4f}")

    fig = plot_feature_importance(importances, top_n=20, title="Feature Importance — Research Track / win_loss")
    fig.savefig(output_dir / "plots" / "feature_importance_winloss.png", dpi=120, bbox_inches="tight")
    plt.close(fig)

    # ── SHAP ──
    print("\n" + "─"*60)
    print(" SHAP ANALYSIS — LightGBM / win_loss")
    print("─"*60)

    lgbm_data = best_results["win_loss"]["LightGBM"]
    shap_vals  = compute_shap(lgbm_data["model"], lgbm_data["scaler"].transform(X), feature_cols)
    top_feats  = top_shap_features(shap_vals, n=15)
    print("\nTop 15 features by mean |SHAP|:")
    print(top_feats.to_string(index=False))

    fig = plot_shap_summary(shap_vals, "SHAP Summary — Research Track / LightGBM / win_loss")
    fig.savefig(output_dir / "plots" / "shap_summary.png", dpi=120, bbox_inches="tight")
    plt.close(fig)

    fig = plot_shap_bar(shap_vals, "SHAP Feature Importance — Research Track / LightGBM")
    fig.savefig(output_dir / "plots" / "shap_bar.png", dpi=120, bbox_inches="tight")
    plt.close(fig)

    # ── Threshold Analysis ──
    print("\n" + "─"*60)
    print(" THRESHOLD ANALYSIS — LightGBM / win_loss")
    print("─"*60)

    proba  = lgbm_data["y_prob"]
    y_true = lgbm_data["y_true"]
    profits = np.where(y_true == 1, df["mfe_r"].values, -df["mae_r"].values)

    thr_df = threshold_analysis(y_true, proba, profits)
    print(f"\n{'Thr':>5} {'N':>5} {'Kept%':>6} {'WR%':>6} {'Avg R':>8} {'PF':>6}")
    print("-" * 45)
    for _, row in thr_df.iterrows():
        print(f"{row.Threshold:5.2f} {int(row.N_Trades):5d} {row.Pct_Kept:6.1f}% "
              f"{row.Win_Rate:5.1f}% {row.Expectancy:7.3f} {row.Profit_Factor:5.3f}")

    fig = plot_threshold_analysis(thr_df, "Research Track — LightGBM win_loss")
    fig.savefig(output_dir / "plots" / "threshold_analysis.png", dpi=120, bbox_inches="tight")
    plt.close(fig)

    # ── Save results ──
    cv_df = pd.DataFrame(all_cv_rows)
    cv_df.to_csv(output_dir / "reports" / "cv_results.csv", index=False)
    thr_df.to_csv(output_dir / "reports" / "threshold_analysis.csv", index=False)
    top_feats.to_csv(output_dir / "reports" / "shap_top_features.csv", index=False)

    # ── Summary ──
    print("\n" + "="*60)
    print(" RESEARCH TRACK RESULTS SUMMARY")
    print("="*60)
    print(f"\n{'Target':<12} {'Model':<14} {'AUC':>7} {'±':>6} {'AP':>7}")
    print("─" * 50)
    for row in all_cv_rows:
        print(f"  {row['target']:<12} {row['model']:<14} "
              f"{row.get('roc_auc_mean',0):7.3f} ±{row.get('roc_auc_std',0):5.3f} "
              f"{row.get('avg_precision_mean',0):7.3f}")

    print(f"\n✓ All outputs saved to: {output_dir.resolve()}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--data",       type=Path, default=DATA_PATH)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)
    args = parser.parse_args()
    run(args.data, args.output_dir)
