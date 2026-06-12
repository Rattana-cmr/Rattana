"""
ICT ATLAS EA — Phase 3 ML Pipeline
===================================
Trains RF, XGBoost, LightGBM for 5 targets using the Phase 1D-B trade dataset.
Outputs: model files, evaluation CSVs, SHAP plots, threshold report.

Usage:
    python run_pipeline.py [--data PATH] [--output-dir PATH]
"""

import argparse
import sys
from pathlib import Path
import warnings
warnings.filterwarnings("ignore")

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# Add src to path
sys.path.insert(0, str(Path(__file__).parent))

from src.data_prep  import prepare
from src.models     import get_classifiers, get_regressors, cv_classify, cv_regress, train_final, save_model
from src.evaluate   import cv_summary, threshold_analysis, plot_threshold_analysis, plot_feature_importance, plot_roc_curves, plot_pr_curves
from src.shap_utils import compute_shap, plot_shap_summary, plot_shap_bar, top_shap_features

from sklearn.preprocessing import StandardScaler


# ── Configuration ─────────────────────────────────────────────────────────────

DATA_PATH   = Path(__file__).parent / "data" / "ICT_ATLAS_Phase1DB_Trades.csv"
OUTPUT_DIR  = Path(__file__).parent / "outputs"

CLASSIFY_TARGETS = ["win_loss", "tp1_hit", "tp2_hit", "tp3_hit"]
REGRESS_TARGETS  = ["rr_achieved"]
N_SPLITS         = 10
RANDOM_STATE     = 42


# ── Helpers ───────────────────────────────────────────────────────────────────

def fmt(val):
    return f"{val:.4f}"


def summarise_cv(cv: dict) -> str:
    parts = []
    for m, vals in cv.items():
        parts.append(f"{m}: {np.mean(vals):.3f}±{np.std(vals):.3f}")
    return " | ".join(parts)


# ── Main Pipeline ─────────────────────────────────────────────────────────────

def run(data_path: Path, output_dir: Path):
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "models").mkdir(exist_ok=True)
    (output_dir / "plots").mkdir(exist_ok=True)
    (output_dir / "reports").mkdir(exist_ok=True)

    # ── Load data ──
    print("\n" + "="*60)
    print(" ICT ATLAS Phase 3 ML Pipeline")
    print("="*60)
    X, targets, df = prepare(data_path)
    feature_cols = list(X.columns)
    n = len(X)

    print(f"\nDataset: {n} trades | {len(feature_cols)} features")
    print(f"\nTarget class balance:")
    for col in CLASSIFY_TARGETS:
        pos = targets[col].mean()
        print(f"  {col:12s}: {pos*100:.1f}% positive  ({targets[col].sum()}/{n})")

    all_cv_rows = []

    # ── Classification targets ──
    print("\n" + "─"*60)
    print(" CLASSIFICATION MODELS")
    print("─"*60)

    classifiers = get_classifiers(RANDOM_STATE)
    best_clf_results = {}   # target → {model_name, y_prob, y_true}
    feature_importance_clf = {}  # model_name → Series

    for target_name in CLASSIFY_TARGETS:
        y = targets[target_name]
        print(f"\n▶ Target: {target_name}  (positive={y.mean()*100:.1f}%)")

        target_probs = {}
        for model_name, model in classifiers.items():
            cv = cv_classify(model, X, y, N_SPLITS, RANDOM_STATE)
            print(f"  {model_name:12s}: {summarise_cv(cv)}")

            row = {
                "target": target_name, "model": model_name, "type": "classification"
            }
            for metric, vals in cv.items():
                row[f"{metric}_mean"] = np.mean(vals)
                row[f"{metric}_std"]  = np.std(vals)
            all_cv_rows.append(row)

            # Train final model for SHAP + threshold analysis
            scaler = StandardScaler()
            X_s = scaler.fit_transform(X)
            from sklearn.base import clone
            m = clone(model)
            m.fit(X_s, y)
            proba = m.predict_proba(X_s)[:, 1]
            target_probs[model_name] = {"y_prob": proba, "y_true": y.values, "model": m, "scaler": scaler}

            # Save model
            save_model(m, scaler, output_dir / "models" / f"{model_name}_{target_name}.pkl")

        best_clf_results[target_name] = target_probs

        # ROC & PR plots
        plot_data = [{"name": mn, "y_true": v["y_true"], "y_prob": v["y_prob"]}
                     for mn, v in target_probs.items()]
        fig = plot_roc_curves(plot_data, target_name)
        fig.savefig(output_dir / "plots" / f"roc_{target_name}.png", dpi=120, bbox_inches="tight")
        plt.close(fig)

        fig = plot_pr_curves(plot_data, target_name)
        fig.savefig(output_dir / "plots" / f"pr_{target_name}.png", dpi=120, bbox_inches="tight")
        plt.close(fig)

    # ── Regression target ──
    print("\n" + "─"*60)
    print(" REGRESSION MODELS (Expected RR)")
    print("─"*60)

    regressors = get_regressors(RANDOM_STATE)
    for target_name in REGRESS_TARGETS:
        y = targets[target_name]
        print(f"\n▶ Target: {target_name}  (mean={y.mean():.3f}, std={y.std():.3f})")

        for model_name, model in regressors.items():
            cv = cv_regress(model, X, y, N_SPLITS, RANDOM_STATE)
            print(f"  {model_name:12s}: {summarise_cv(cv)}")

            row = {
                "target": target_name, "model": model_name, "type": "regression"
            }
            for metric, vals in cv.items():
                row[f"{metric}_mean"] = np.mean(vals)
                row[f"{metric}_std"]  = np.std(vals)
            all_cv_rows.append(row)

            # Save final model
            scaler = StandardScaler()
            X_s = scaler.fit_transform(X)
            from sklearn.base import clone
            m = clone(model)
            m.fit(X_s, y)
            save_model(m, scaler, output_dir / "models" / f"{model_name}_{target_name}.pkl")

    # ── Feature Importance ──
    print("\n" + "─"*60)
    print(" FEATURE IMPORTANCE — Win/Loss Target")
    print("─"*60)

    y_wl = targets["win_loss"]
    importances = {}
    for model_name, clf in classifiers.items():
        scaler = StandardScaler()
        X_s = scaler.fit_transform(X)
        from sklearn.base import clone
        m = clone(clf)
        m.fit(X_s, y_wl)
        imp = pd.Series(m.feature_importances_, index=feature_cols)
        importances[model_name] = imp
        top10 = imp.nlargest(10)
        print(f"\n  {model_name} top 10:")
        for feat, val in top10.items():
            print(f"    {feat:25s}: {val:.4f}")

    fig = plot_feature_importance(importances, top_n=20, title="Feature Importance — Win/Loss")
    fig.savefig(output_dir / "plots" / "feature_importance_winloss.png", dpi=120, bbox_inches="tight")
    plt.close(fig)

    # ── SHAP Analysis (LightGBM on win_loss) ──
    print("\n" + "─"*60)
    print(" SHAP ANALYSIS — LightGBM / Win/Loss")
    print("─"*60)

    lgbm_data = best_clf_results["win_loss"]["LightGBM"]
    shap_vals = compute_shap(lgbm_data["model"],
                             lgbm_data["scaler"].transform(X),
                             feature_cols)

    top_feats = top_shap_features(shap_vals, n=15)
    print("\nTop 15 features by mean |SHAP|:")
    print(top_feats.to_string(index=False))

    fig = plot_shap_summary(shap_vals, "SHAP Summary — LightGBM / Win/Loss")
    fig.savefig(output_dir / "plots" / "shap_summary_lgbm_winloss.png", dpi=120, bbox_inches="tight")
    plt.close(fig)

    fig = plot_shap_bar(shap_vals, "SHAP Feature Importance — LightGBM / Win/Loss")
    fig.savefig(output_dir / "plots" / "shap_bar_lgbm_winloss.png", dpi=120, bbox_inches="tight")
    plt.close(fig)

    # Waterfall for top WIN and top LOSS trade
    wins_idx  = np.where(y_wl.values == 1)[0]
    loss_idx  = np.where(y_wl.values == 0)[0]
    proba_all = lgbm_data["y_prob"]
    best_win  = wins_idx[np.argmax(proba_all[wins_idx])]
    best_loss = loss_idx[np.argmax(proba_all[loss_idx])]   # loss with highest prob (false positive)

    for idx, label in [(best_win, "top_win"), (best_loss, "top_false_positive")]:
        fig = plot_shap_bar(shap_vals[idx:idx+1], f"SHAP Waterfall — {label}")
        fig.savefig(output_dir / "plots" / f"shap_waterfall_{label}.png", dpi=120, bbox_inches="tight")
        plt.close(fig)

    # ── Threshold Analysis ──
    print("\n" + "─"*60)
    print(" THRESHOLD ANALYSIS — LightGBM / Win/Loss")
    print("─"*60)

    proba  = lgbm_data["y_prob"]
    y_true = lgbm_data["y_true"]
    profits = df["Profit_USD"].values

    thr_df = threshold_analysis(y_true, proba, profits)
    print(f"\n{'Thr':>5} {'N':>5} {'Kept%':>6} {'WR%':>6} {'Profit':>9} {'PF':>6} {'Exp':>8}")
    print("-" * 55)
    for _, row in thr_df.iterrows():
        print(f"{row.Threshold:5.2f} {int(row.N_Trades):5d} {row.Pct_Kept:6.1f}% "
              f"{row.Win_Rate:5.1f}% ${row.Total_Profit:8.0f} {row.Profit_Factor:5.3f} ${row.Expectancy:6.2f}")

    fig = plot_threshold_analysis(thr_df, "LightGBM Win/Loss Predictor")
    fig.savefig(output_dir / "plots" / "threshold_analysis.png", dpi=120, bbox_inches="tight")
    plt.close(fig)

    # ── Save Results ──
    cv_df = pd.DataFrame(all_cv_rows)
    cv_df.to_csv(output_dir / "reports" / "cv_results.csv", index=False)
    thr_df.to_csv(output_dir / "reports" / "threshold_analysis.csv", index=False)
    top_feats.to_csv(output_dir / "reports" / "shap_top_features.csv", index=False)

    imp_df = pd.DataFrame({k: v for k, v in importances.items()}).reset_index()
    imp_df.columns = ["Feature"] + list(importances.keys())
    imp_df["Mean_Importance"] = imp_df[list(importances.keys())].mean(axis=1)
    imp_df.sort_values("Mean_Importance", ascending=False, inplace=True)
    imp_df.to_csv(output_dir / "reports" / "feature_importance.csv", index=False)

    # ── Print final summary ──
    print("\n" + "="*60)
    print(" RESULTS SUMMARY")
    print("="*60)
    summary = cv_df[cv_df["type"] == "classification"].groupby(["target", "model"]).first().reset_index()
    for target in CLASSIFY_TARGETS:
        t = summary[summary["target"] == target]
        print(f"\n{target}:")
        if "roc_auc_mean" in t.columns:
            for _, row in t.iterrows():
                print(f"  {row['model']:12s}: AUC={row['roc_auc_mean']:.3f}±{row['roc_auc_std']:.3f}  "
                      f"Prec={row.get('precision_mean', 0):.3f}  Rec={row.get('recall_mean', 0):.3f}  "
                      f"F1={row.get('f1_mean', 0):.3f}")

    print(f"\n{'─'*60}")
    print(" Threshold recommendation (LightGBM Win/Loss):")
    best_row = thr_df[(thr_df["Pct_Kept"] >= 55) & (thr_df["Pct_Kept"] <= 75)].iloc[0] \
               if len(thr_df[(thr_df["Pct_Kept"] >= 55) & (thr_df["Pct_Kept"] <= 75)]) > 0 \
               else thr_df.iloc[len(thr_df)//2]
    print(f"  Threshold: {best_row.Threshold:.2f}")
    print(f"  Trades kept: {best_row.N_Trades} ({best_row.Pct_Kept:.1f}%)")
    print(f"  Win rate: {best_row.Win_Rate:.1f}%")
    print(f"  Expectancy: ${best_row.Expectancy:.2f}/trade")
    print(f"  Profit factor: {best_row.Profit_Factor:.3f}")

    print(f"\n✓ All outputs saved to: {output_dir.resolve()}")
    print("  models/       — saved model + scaler pairs (.pkl)")
    print("  plots/        — ROC, PR, SHAP, threshold charts (.png)")
    print("  reports/      — CV results, feature importance, threshold analysis (.csv)")


# ── Entry Point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, default=DATA_PATH)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)
    args = parser.parse_args()
    run(args.data, args.output_dir)
