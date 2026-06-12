"""
SHAP analysis utilities for tree-based models.
Generates summary plots, dependence plots, and waterfall charts.
"""

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import shap


def compute_shap(model, X_scaled: np.ndarray,
                 feature_names: list[str]) -> shap.Explanation:
    """Compute SHAP values using TreeExplainer."""
    explainer = shap.TreeExplainer(model)
    shap_values = explainer(X_scaled, check_additivity=False)

    # For binary classifiers, take the positive-class SHAP values
    if hasattr(shap_values, "values") and shap_values.values.ndim == 3:
        sv = shap.Explanation(
            values=shap_values.values[:, :, 1],
            base_values=shap_values.base_values[:, 1],
            data=shap_values.data,
            feature_names=feature_names,
        )
        return sv

    if feature_names and hasattr(shap_values, "feature_names"):
        shap_values.feature_names = feature_names
    return shap_values


def plot_shap_summary(shap_vals: shap.Explanation,
                      title: str = "SHAP Summary") -> plt.Figure:
    # beeswarm does not support ax= in newer SHAP; use plt.gcf() pattern
    plt.figure(figsize=(9, 7))
    shap.plots.beeswarm(shap_vals, max_display=20, show=False, plot_size=None)
    plt.title(title, fontsize=12, fontweight="bold")
    plt.tight_layout()
    return plt.gcf()


def plot_shap_bar(shap_vals: shap.Explanation,
                  title: str = "SHAP Feature Importance") -> plt.Figure:
    plt.figure(figsize=(8, 6))
    shap.plots.bar(shap_vals, max_display=20, show=False)
    plt.title(title, fontsize=12, fontweight="bold")
    plt.tight_layout()
    return plt.gcf()


def plot_shap_waterfall(shap_vals: shap.Explanation, idx: int = 0,
                        title: str = "") -> plt.Figure:
    plt.figure(figsize=(9, 6))
    shap.plots.waterfall(shap_vals[idx], show=False)
    plt.title(title or f"SHAP Waterfall — Sample {idx}", fontsize=11)
    plt.tight_layout()
    return plt.gcf()


def plot_shap_dependence(shap_vals: shap.Explanation,
                         feature: str, X_df: pd.DataFrame,
                         title: str = "") -> plt.Figure:
    plt.figure(figsize=(7, 5))
    shap.plots.scatter(shap_vals[:, feature], show=False)
    plt.title(title or f"SHAP Dependence — {feature}", fontsize=11)
    plt.tight_layout()
    return plt.gcf()


def top_shap_features(shap_vals: shap.Explanation, n: int = 15) -> pd.DataFrame:
    """Return a DataFrame of mean |SHAP| values sorted descending."""
    mean_abs = np.abs(shap_vals.values).mean(axis=0)
    names = shap_vals.feature_names or [f"f{i}" for i in range(len(mean_abs))]
    df = pd.DataFrame({"Feature": names, "Mean_Abs_SHAP": mean_abs})
    return df.sort_values("Mean_Abs_SHAP", ascending=False).head(n).reset_index(drop=True)
