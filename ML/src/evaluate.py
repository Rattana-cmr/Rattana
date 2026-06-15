"""
Evaluation utilities: metrics tables, ROC/PR curves, threshold analysis,
and the trade-selection simulation.
"""

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
import seaborn as sns
from sklearn.metrics import (
    roc_curve, auc, precision_recall_curve,
    ConfusionMatrixDisplay, confusion_matrix,
)
from sklearn.preprocessing import StandardScaler


# ── Metrics Summary ───────────────────────────────────────────────────────────

def cv_summary(cv_results: dict, model_name: str, target: str) -> pd.DataFrame:
    rows = []
    for metric, values in cv_results.items():
        rows.append({
            "Model": model_name,
            "Target": target,
            "Metric": metric,
            "Mean": np.mean(values),
            "Std": np.std(values),
            "Min": np.min(values),
            "Max": np.max(values),
        })
    return pd.DataFrame(rows)


def metrics_table(all_results: list[dict]) -> pd.DataFrame:
    """Combine CV results from all model×target combinations into one table."""
    frames = []
    for r in all_results:
        df = cv_summary(r["cv"], r["model_name"], r["target"])
        frames.append(df)
    combined = pd.concat(frames, ignore_index=True)
    return combined


# ── ROC Curve ────────────────────────────────────────────────────────────────

def plot_roc_curves(models_data: list[dict], target: str,
                    ax: plt.Axes | None = None) -> plt.Figure:
    """
    Plot ROC curves for multiple models on the same axes.
    models_data: list of {"name": str, "y_true": array, "y_prob": array}
    """
    if ax is None:
        fig, ax = plt.subplots(figsize=(6, 5))
    else:
        fig = ax.figure

    colors = ["#2196F3", "#FF5722", "#4CAF50"]
    for i, m in enumerate(models_data):
        fpr, tpr, _ = roc_curve(m["y_true"], m["y_prob"])
        score = auc(fpr, tpr)
        ax.plot(fpr, tpr, color=colors[i % len(colors)],
                label=f"{m['name']} (AUC={score:.3f})", lw=2)

    ax.plot([0, 1], [0, 1], "k--", lw=1, alpha=0.5)
    ax.set_xlabel("False Positive Rate")
    ax.set_ylabel("True Positive Rate")
    ax.set_title(f"ROC Curve — {target}")
    ax.legend(loc="lower right", fontsize=9)
    ax.set_xlim([0, 1])
    ax.set_ylim([0, 1.02])
    return fig


def plot_pr_curves(models_data: list[dict], target: str,
                   ax: plt.Axes | None = None) -> plt.Figure:
    """Precision-Recall curves."""
    if ax is None:
        fig, ax = plt.subplots(figsize=(6, 5))
    else:
        fig = ax.figure

    colors = ["#2196F3", "#FF5722", "#4CAF50"]
    for i, m in enumerate(models_data):
        p, r, _ = precision_recall_curve(m["y_true"], m["y_prob"])
        ap = np.trapezoid(p[::-1], r[::-1])
        ax.plot(r, p, color=colors[i % len(colors)],
                label=f"{m['name']} (AP={ap:.3f})", lw=2)

    baseline = m["y_true"].mean()
    ax.axhline(baseline, color="gray", linestyle="--", lw=1,
               label=f"Baseline ({baseline:.2f})")
    ax.set_xlabel("Recall")
    ax.set_ylabel("Precision")
    ax.set_title(f"Precision-Recall — {target}")
    ax.legend(loc="upper right", fontsize=9)
    return fig


# ── Threshold Analysis ────────────────────────────────────────────────────────

def threshold_analysis(y_true: np.ndarray, y_prob: np.ndarray,
                       profits: np.ndarray,
                       thresholds: np.ndarray | None = None) -> pd.DataFrame:
    """
    Simulate trade selection at each probability threshold.
    Shows: threshold, n_trades, win_rate, total_profit, pct_of_base_profit, expectancy.
    """
    if thresholds is None:
        thresholds = np.arange(0.30, 0.86, 0.02)

    base_profit    = profits.sum()
    base_n         = len(profits)
    base_wr        = y_true.mean()
    base_exp       = profits.mean()

    rows = []
    for thr in thresholds:
        mask = y_prob >= thr
        n = mask.sum()
        if n == 0:
            continue
        wr    = y_true[mask].mean()
        total = profits[mask].sum()
        exp   = profits[mask].mean()

        # Profit factor
        wins  = profits[mask][profits[mask] > 0].sum()
        losses = abs(profits[mask][profits[mask] < 0].sum())
        pf    = wins / losses if losses > 0 else np.inf

        rows.append({
            "Threshold":         round(thr, 2),
            "N_Trades":          int(n),
            "Pct_Kept":          round(n / base_n * 100, 1),
            "Win_Rate":          round(wr * 100, 1),
            "Total_Profit":      round(total, 2),
            "Pct_Base_Profit":   round(total / base_profit * 100, 1),
            "Expectancy":        round(exp, 2),
            "Profit_Factor":     round(pf, 3),
        })

    df = pd.DataFrame(rows)
    df.attrs["base_n"]      = base_n
    df.attrs["base_wr"]     = round(base_wr * 100, 1)
    df.attrs["base_profit"] = round(base_profit, 2)
    df.attrs["base_exp"]    = round(base_exp, 2)
    return df


def plot_threshold_analysis(thr_df: pd.DataFrame, title: str = "") -> plt.Figure:
    fig, axes = plt.subplots(2, 2, figsize=(12, 8))
    fig.suptitle(f"Threshold Analysis — {title}", fontsize=13, fontweight="bold")

    ax = axes[0, 0]
    ax.plot(thr_df["Threshold"], thr_df["Win_Rate"], "b-o", markersize=4)
    ax.axhline(thr_df.attrs.get("base_wr", 50), color="gray", linestyle="--", label="Baseline")
    ax.set_title("Win Rate vs Threshold")
    ax.set_ylabel("Win Rate (%)")
    ax.legend()

    ax = axes[0, 1]
    ax.plot(thr_df["Threshold"], thr_df["N_Trades"], "r-o", markersize=4)
    ax.axhline(thr_df.attrs.get("base_n", 0), color="gray", linestyle="--", label="Baseline")
    ax.set_title("Trades Selected vs Threshold")
    ax.set_ylabel("N Trades")
    ax.legend()

    ax = axes[1, 0]
    ax.plot(thr_df["Threshold"], thr_df["Expectancy"], "g-o", markersize=4)
    ax.axhline(thr_df.attrs.get("base_exp", 0), color="gray", linestyle="--", label="Baseline")
    ax.set_title("Expectancy per Trade vs Threshold")
    ax.set_ylabel("$ per trade")
    ax.legend()

    ax = axes[1, 1]
    ax.plot(thr_df["Threshold"], thr_df["Profit_Factor"], "m-o", markersize=4)
    ax.set_title("Profit Factor vs Threshold")
    ax.set_ylabel("Profit Factor")
    ax.axhline(1.0, color="red", linestyle=":", alpha=0.5)

    for ax in axes.flat:
        ax.set_xlabel("Probability Threshold")
        ax.grid(True, alpha=0.3)

    plt.tight_layout()
    return fig


# ── Feature Importance Plot ───────────────────────────────────────────────────

def plot_feature_importance(importances: dict[str, pd.Series],
                            top_n: int = 20, title: str = "") -> plt.Figure:
    """
    Plot feature importances for multiple models side by side.
    importances: {"ModelName": pd.Series(importance, index=feature_names)}
    """
    n_models = len(importances)
    fig, axes = plt.subplots(1, n_models, figsize=(6 * n_models, max(6, top_n * 0.35)))
    if n_models == 1:
        axes = [axes]

    colors = ["#2196F3", "#FF5722", "#4CAF50"]
    for i, (name, imp) in enumerate(importances.items()):
        top = imp.nlargest(top_n)
        axes[i].barh(top.index[::-1], top.values[::-1], color=colors[i % len(colors)])
        axes[i].set_title(f"{name}\nFeature Importance")
        axes[i].set_xlabel("Importance")

    fig.suptitle(title, fontsize=12, fontweight="bold")
    plt.tight_layout()
    return fig
