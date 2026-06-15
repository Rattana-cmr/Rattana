"""
Model definitions, cross-validation training, and persistence.
Supports RF, XGBoost, LightGBM for both classification and regression.
"""

import numpy as np
import pandas as pd
import joblib
from pathlib import Path

from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline
from sklearn.model_selection import StratifiedKFold, KFold, cross_validate
from sklearn.metrics import (
    roc_auc_score, average_precision_score,
    precision_score, recall_score, f1_score,
    mean_absolute_error, r2_score, mean_squared_error,
)
from sklearn.calibration import CalibratedClassifierCV

import xgboost as xgb
import lightgbm as lgb

# Suppress LightGBM verbose output
import warnings
warnings.filterwarnings("ignore", category=UserWarning, module="lightgbm")


# ── Model Definitions ─────────────────────────────────────────────────────────

def get_classifiers(random_state: int = 42) -> dict:
    return {
        "RandomForest": RandomForestClassifier(
            n_estimators=500,
            max_depth=6,
            min_samples_leaf=5,
            max_features="sqrt",
            class_weight="balanced",
            random_state=random_state,
            n_jobs=-1,
        ),
        "XGBoost": xgb.XGBClassifier(
            n_estimators=300,
            max_depth=4,
            learning_rate=0.05,
            subsample=0.8,
            colsample_bytree=0.8,
            scale_pos_weight=1,   # set per-target during training
            eval_metric="logloss",
            use_label_encoder=False,
            random_state=random_state,
            verbosity=0,
        ),
        "LightGBM": lgb.LGBMClassifier(
            n_estimators=300,
            max_depth=4,
            learning_rate=0.05,
            subsample=0.8,
            colsample_bytree=0.8,
            class_weight="balanced",
            random_state=random_state,
            verbose=-1,
            n_jobs=-1,
        ),
    }


def get_regressors(random_state: int = 42) -> dict:
    return {
        "RandomForest": RandomForestRegressor(
            n_estimators=500,
            max_depth=6,
            min_samples_leaf=5,
            max_features="sqrt",
            random_state=random_state,
            n_jobs=-1,
        ),
        "XGBoost": xgb.XGBRegressor(
            n_estimators=300,
            max_depth=4,
            learning_rate=0.05,
            subsample=0.8,
            colsample_bytree=0.8,
            random_state=random_state,
            verbosity=0,
        ),
        "LightGBM": lgb.LGBMRegressor(
            n_estimators=300,
            max_depth=4,
            learning_rate=0.05,
            subsample=0.8,
            colsample_bytree=0.8,
            random_state=random_state,
            verbose=-1,
            n_jobs=-1,
        ),
    }


# ── Cross-Validation ──────────────────────────────────────────────────────────

def cv_classify(model, X: pd.DataFrame, y: pd.Series,
                n_splits: int = 10, random_state: int = 42) -> dict:
    """
    Stratified K-Fold cross-validation for a classifier.
    Returns dict of metric arrays (one value per fold).
    """
    skf = StratifiedKFold(n_splits=n_splits, shuffle=True, random_state=random_state)

    results = {m: [] for m in ["roc_auc", "avg_precision", "precision", "recall", "f1"]}

    for train_idx, val_idx in skf.split(X, y):
        X_tr, X_val = X.iloc[train_idx], X.iloc[val_idx]
        y_tr, y_val = y.iloc[train_idx], y.iloc[val_idx]

        # Scale numerics
        scaler = StandardScaler()
        X_tr_s  = scaler.fit_transform(X_tr)
        X_val_s = scaler.transform(X_val)

        m = clone_model(model)
        m.fit(X_tr_s, y_tr)
        proba = m.predict_proba(X_val_s)[:, 1]
        pred  = (proba >= 0.5).astype(int)

        results["roc_auc"].append(roc_auc_score(y_val, proba))
        results["avg_precision"].append(average_precision_score(y_val, proba))
        results["precision"].append(precision_score(y_val, pred, zero_division=0))
        results["recall"].append(recall_score(y_val, pred, zero_division=0))
        results["f1"].append(f1_score(y_val, pred, zero_division=0))

    return {k: np.array(v) for k, v in results.items()}


def cv_regress(model, X: pd.DataFrame, y: pd.Series,
               n_splits: int = 10, random_state: int = 42) -> dict:
    """K-Fold cross-validation for a regressor."""
    kf = KFold(n_splits=n_splits, shuffle=True, random_state=random_state)

    results = {m: [] for m in ["mae", "rmse", "r2"]}

    for train_idx, val_idx in kf.split(X):
        X_tr, X_val = X.iloc[train_idx], X.iloc[val_idx]
        y_tr, y_val = y.iloc[train_idx], y.iloc[val_idx]

        scaler = StandardScaler()
        X_tr_s  = scaler.fit_transform(X_tr)
        X_val_s = scaler.transform(X_val)

        m = clone_model(model)
        m.fit(X_tr_s, y_tr)
        pred = m.predict(X_val_s)

        results["mae"].append(mean_absolute_error(y_val, pred))
        results["rmse"].append(np.sqrt(mean_squared_error(y_val, pred)))
        results["r2"].append(r2_score(y_val, pred))

    return {k: np.array(v) for k, v in results.items()}


def clone_model(model):
    from sklearn.base import clone
    return clone(model)


# ── Final Model Training ──────────────────────────────────────────────────────

def train_final(model, X: pd.DataFrame, y: pd.Series, scale: bool = True):
    """Train a single model on the full dataset. Returns (fitted_model, scaler)."""
    scaler = StandardScaler()
    X_s = scaler.fit_transform(X) if scale else X.values
    model.fit(X_s, y)
    return model, scaler


# ── Persistence ───────────────────────────────────────────────────────────────

def save_model(model, scaler, path: str | Path):
    joblib.dump({"model": model, "scaler": scaler}, path)
    print(f"Saved → {path}")


def load_model(path: str | Path):
    obj = joblib.load(path)
    return obj["model"], obj["scaler"]
