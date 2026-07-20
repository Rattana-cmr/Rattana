"""
Inference module: load a saved model and score a new trade row.
Used for live trade filtering based on ML confidence.
"""

import numpy as np
import pandas as pd
import joblib
from pathlib import Path


def load_model(model_path: str | Path):
    return joblib.load(model_path)


def predict_trade(model_obj: dict, trade_row: pd.DataFrame) -> dict:
    """
    Score a single trade row (or batch) using a saved model object.

    model_obj: dict with keys {"model", "scaler", "features", "threshold"}
    trade_row: DataFrame with the same columns as the training data

    Returns: {"probability": float, "take_trade": bool, "threshold": float}
    """
    from src.data_prep import build_features

    X = build_features(trade_row)[model_obj["features"]]
    X_s = model_obj["scaler"].transform(X)
    prob = model_obj["model"].predict_proba(X_s)[:, 1]

    return {
        "probability": prob.tolist(),
        "take_trade": (prob >= model_obj["threshold"]).tolist(),
        "threshold": model_obj["threshold"],
    }


def batch_score(model_path: str | Path, trades_csv: str | Path) -> pd.DataFrame:
    """
    Score all trades in a CSV file and return a DataFrame with probabilities.
    """
    import sys
    sys.path.insert(0, str(Path(__file__).parent.parent))

    from src.data_prep import load_trades, build_features

    obj = load_model(model_path)
    df  = load_trades(trades_csv)
    X   = build_features(df)

    X_s  = obj["scaler"].transform(X[obj["features"]])
    prob = obj["model"].predict_proba(X_s)[:, 1]

    result = df[["SetupID", "OpenTime", "Trade_Result", "RR_Achieved", "Profit_USD"]].copy()
    result["ML_Probability"] = prob
    result["ML_Take_Trade"]  = prob >= obj["threshold"]
    result["ML_Threshold"]   = obj["threshold"]
    return result


if __name__ == "__main__":
    import sys
    model_path  = sys.argv[1] if len(sys.argv) > 1 else "outputs/models/LightGBM_winloss_final.pkl"
    trades_path = sys.argv[2] if len(sys.argv) > 2 else "data/ICT_ATLAS_Phase1DB_Trades.csv"

    result = batch_score(model_path, trades_path)
    print(f"Scored {len(result)} trades")
    print(f"Take: {result['ML_Take_Trade'].sum()} / Skip: {(~result['ML_Take_Trade']).sum()}")
    print(result.head(10).to_string(index=False))
