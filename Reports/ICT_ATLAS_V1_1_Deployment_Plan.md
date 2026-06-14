# ICT ATLAS EA V1.1 — ML-Gated Execution Architecture

**Date:** June 2026  
**Status:** DESIGN — Not yet authorised for live deployment  
**Prerequisite:** Research Track v2 frozen (45,429 signals, XGB AUC 0.635, LGB AUC 0.628)  
**Separate from:** Atlas Scalper Phase 8 shadow validation  

---

## Executive Summary

This document defines the architecture for Atlas EA V1.1 — a version that adds an ML probability gate as a final filter on top of the existing Phase 1D-B entry logic. The strategy rules remain fully frozen. The ML model acts as a ranking layer only: it can reject signals, but cannot create them.

**Recommended starting threshold: 0.52**  
At this threshold, applied to the 948 executed Phase 1D-B signals in the v2 dataset, the model retains 41% of trades at a predicted win rate of 66.3% — versus the Phase 1D-B baseline of 50.1%. This is the best balance of trade frequency and measurable edge improvement.

---

## Architecture Overview

```
Market Data (XAUUSD M15)
        │
        ▼
┌─────────────────────────┐
│  Phase 1D-B Entry Logic │  ← FROZEN (unchanged)
│  MSS + all filters      │
└──────────┬──────────────┘
           │ Signal generated
           ▼
┌─────────────────────────┐
│  Feature Extraction     │  ← New in V1.1
│  (15 ML inputs)         │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│  LightGBM ONNX Model    │  ← New in V1.1
│  P(win_loss) score      │
└──────────┬──────────────┘
           │
     ┌─────┴─────┐
     │           │
   P ≥ thr    P < thr
     │           │
     ▼           ▼
  Execute      Skip + Log
  trade        (ML reject)
     │
     ▼
┌─────────────────────────┐
│  Risk / Position Size   │  ← Unchanged (Phase 1D-B rules)
│  Logging + CSV export   │  ← Extended with ML fields
└─────────────────────────┘
```

---

## Component 1 — Phase 1D-B Entry Logic (Unchanged)

No changes to the existing signal generation. The EA continues to evaluate:

- MSS confirmed (`UseMSSFilter=true`)
- LONG ONLY (`AllowShortEntries=false`)
- London blocked (`BlockLondonHours=true`)
- MaxSL=200 pips
- All market conditions permitted

The ML layer receives the signal **only after all existing filters pass**. The model never promotes a signal that the EA has already rejected.

---

## Component 2 — Feature Extraction (New in V1.1)

### Features Required

The LightGBM model uses 15 primary features. All are computable from data already available at signal time — no lookahead, no external calls.

| Feature | Source in EA | Already Logged? |
|---------|-------------|-----------------|
| `atr14` | ATR(14) in pips | Yes — `ATR14_Pips` |
| `spread_pips` | Current spread | Yes — `Spread_Pips` |
| `atr50` | ATR(50) in pips | Yes — `ATR50_Pips` |
| `month` | Signal timestamp | Yes — `Timestamp` |
| `hour` | Signal timestamp | Yes — `Timestamp` |
| `atr_ratio` | ATR14 / ATR50 | Computed: `ATR14_Pips / ATR50_Pips` |
| `day_of_week` | Signal timestamp | Yes — `DayOfWeek` |
| `spread_pct_atr` | Spread / ATR14 | Yes — `SpreadPctATR` |
| `vol_regime` | ADX × ATR14 | Computed: `ADX_Value × ATR14_Pips` |
| `adx` | ADX(14) | Yes — `ADX_Value` |
| `bias_alignment` | Sum of bullish TF biases | Computed from existing bias fields |
| `sweep_count` | Count of active sweeps | Computed from 7 sweep flags |
| `spread_quality` | 1 − (spread/ATR14) | Computed from existing fields |
| `h1_bias` | H1 bias (mapped: Bull=1, Neut=0, Bear=-1) | Yes — `H1Bias` |
| `prem_disc` | PremDisc_Status (mapped) | Yes — `PremDisc_Status` |

**All 15 features are already computed by the EA or derivable from logged fields.** No new data sources are required.

### MQL5 Feature Vector Construction

```mql5
// Compute ML feature vector at signal time
double features[15];
features[0]  = atr14_pips;
features[1]  = spread_pips;
features[2]  = atr50_pips;
features[3]  = (double)TimeMonth(signal_time);
features[4]  = (double)TimeHour(signal_time);
features[5]  = (atr50_pips > 0) ? atr14_pips / atr50_pips : 1.0;  // atr_ratio
features[6]  = (double)TimeDayOfWeek(signal_time) - 1;              // 0=Mon..4=Fri
features[7]  = spread_pct_atr;
features[8]  = adx_value * atr14_pips;                              // vol_regime
features[9]  = adx_value;
features[10] = bias_bullish_count;                                   // sum of 4 TF biases
features[11] = sweep_count;                                          // sum of 7 sweep flags
features[12] = MathMax(0, 1.0 - (spread_pips / MathMax(atr14_pips, 0.001)));
features[13] = h1_bias_encoded;                                      // 1/0/-1
features[14] = prem_disc_encoded;                                    // 1/0/-1/-2
```

### Scaling

The model was trained with `StandardScaler` — mean and std per feature are saved with the model bundle. Each feature must be z-scored before inference:

```
scaled[i] = (features[i] - mean[i]) / std[i]
```

The scaler parameters (48 means and stds) are exported to a CSV at model build time and embedded in the EA as constants.

---

## Component 3 — Model Inference (ONNX)

### Recommended Approach: ONNX Export

MetaTrader 5 (build 3815+) supports native ONNX model inference. The LightGBM model is exported to ONNX format at the Python pipeline stage and deployed as a file alongside the EA.

**Export command (Python):**

```python
import lightgbm as lgb
from lightgbm import Booster

model.booster_.save_model('ICT_ATLAS_LGB_winloss_v2.txt')
# Convert to ONNX via onnxmltools:
from onnxmltools import convert_lightgbm
from onnxmltools.convert.common.data_types import FloatTensorType
onnx_model = convert_lightgbm(model, 'LightGBM', 
                               [('input', FloatTensorType([None, 15]))])
with open('ICT_ATLAS_LGB_winloss_v2.onnx', 'wb') as f:
    f.write(onnx_model.SerializeToString())
```

**MQL5 inference call:**

```mql5
long onnx_handle = OnnxCreate("ICT_ATLAS_LGB_winloss_v2.onnx", ONNX_DEFAULT);
// ... set input/output shapes
float input_data[1][15];  // batch=1, features=15
// fill input_data from feature vector
OnnxRun(onnx_handle, ONNX_NO_CONVERSION, input_data, output_proba);
double p_win = output_proba[0][1];  // probability of class 1 (win)
```

### Alternative Approach: Python Sidecar (Shadow Validation Only)

For shadow validation before live deployment, a simpler approach avoids ONNX conversion complexity:

1. EA logs signal features to a CSV at signal time
2. Python script reads the CSV, scores with the trained model, writes back a probability CSV
3. EA reads the probability CSV at next bar to decide whether to trade

This is appropriate for shadow validation but not for live trading (latency gap, file dependency).

---

## Component 4 — Threshold Gating

### Signal Flow

```
if P(win_loss) >= MLConfidenceThreshold:
    proceed_to_order_execution()
    log_decision("TAKEN", P)
else:
    skip_trade()
    log_decision("ML_REJECTED", P)
```

The threshold is an EA input parameter (`MLConfidenceThreshold`), defaulting to 0.52.

### Three Candidate Thresholds — Applied to Executed Phase 1D-B Signals

The table below uses the v2 model scored against the 948 executed Phase 1D-B trades in the labeled dataset. These are the most directly relevant figures — they show what the filter would do to trades the EA actually takes.

| Threshold | Trades Kept | % Kept | Est. Trades/Year* | Win Rate (model) | Phase 1D-B Baseline |
|-----------|------------|--------|-------------------|-----------------|---------------------|
| **0.50** | 489 / 948 | 51.6% | **~22/yr** | **62.8%** | 50.1% |
| **0.52** | 389 / 948 | 41.0% | **~17/yr** | **66.3%** | 50.1% |
| **0.54** | 303 / 948 | 32.0% | **~13/yr** | **69.6%** | 50.1% |

*Estimated at ~42 Phase 1D-B executions/year (425 trades / 10 years)

**Important caveat:** These win rates are model predictions on the training data. True out-of-sample win rates will be lower. A conservative OOS haircut estimate of 8–12 percentage points gives:

| Threshold | OOS Win Rate Estimate | vs Baseline | Annual Trades |
|-----------|----------------------|-------------|---------------|
| 0.50 | ~51–55% | +1–5% | ~22 |
| 0.52 | ~54–58% | +4–8% | ~17 |
| 0.54 | ~57–62% | +7–12% | ~13 |

---

## Component 5 — Risk Management (Unchanged)

No changes to risk management from Phase 1D-B. The ML gate does not modify position size, stop loss, or take profit.

| Parameter | Value | Source |
|-----------|-------|--------|
| Stop Loss | ATR-based, max 200 pips | Phase 1D-B — frozen |
| Take Profit | TP1/TP2/TP3 structure | Phase 1D-B — frozen |
| Position size | Fixed lot / % risk | Phase 1D-B — frozen |
| Max SL | 200 pips | Phase 1D-B — frozen |

---

## Component 6 — Position Sizing Options

Three options for position sizing in V1.1. **Option A is recommended** for initial deployment.

### Option A — Flat Sizing (Recommended)

Same position size as Phase 1D-B regardless of ML score. Simplest to validate; cleanest performance comparison.

```
LotSize = fixed_lot  // unchanged from Phase 1D-B
```

### Option B — Score-Proportional Sizing

Position size scales linearly with the ML probability above threshold.

```
scale    = (P - threshold) / (1.0 - threshold)   // 0 to 1
LotSize  = base_lot + scale * (max_lot - base_lot)
```

Example at threshold=0.52: a score of 0.62 gives scale=0.20 → 20% larger position.

*Risk: amplifies model errors. Not recommended until OOS validation is complete.*

### Option C — Tiered Sizing

Two position tiers based on probability band.

```
if P >= 0.60:
    LotSize = base_lot * 1.5  // high-confidence tier
else:
    LotSize = base_lot        // standard tier
```

*Risk: same as Option B. Defer until validated.*

---

## Component 7 — Logging and Monitoring

### Extended CSV Export Fields (V1.1 additions)

All existing Phase 1D-B CSV export fields are retained. The following columns are added:

| New Column | Value | Description |
|------------|-------|-------------|
| `ML_Score` | 0.000–1.000 | Raw LightGBM win_loss probability |
| `ML_Decision` | TAKEN / REJECTED | Whether trade passed threshold |
| `ML_Threshold` | 0.52 (or active value) | Threshold in use at signal time |
| `ML_Version` | v2 | Model version identifier |

### Monitoring Requirements

**Per-trade:** Log ML_Score for every signal that reaches the ML gate (both taken and rejected). This is the primary dataset for OOS validation.

**Monthly review:** Track:
- Win rate of ML-TAKEN trades vs ML-REJECTED trades
- Mean ML_Score by outcome (win vs loss)
- AUC on accumulated live OOS decisions

**Annual:** Full pipeline rerun when trade count reaches +50 additional trades. Compare OOS AUC to in-sample 0.628.

**Phase 5 trigger (unchanged):** OOS CV AUC ≥ 0.58 sustained on ≥ 1,000 executed trades.

---

## Component 8 — Shadow Validation Protocol

Before modifying live trading, V1.1 should run in shadow mode:

**Shadow mode operation:**
1. EA continues Phase 1D-B execution unchanged (all qualifying signals are taken)
2. EA additionally logs ML_Score for each signal
3. After 50–100 trades, compare outcomes of would-be TAKEN vs would-be REJECTED signals
4. If TAKEN win rate materially exceeds REJECTED win rate with p < 0.05, proceed to live gating

**Shadow period minimum:** 50 trades (approximately 14 months at current rate)

This shadow phase is separate from Atlas Scalper Phase 8 shadow validation.

---

## Deployment Phases

| Phase | Action | Trigger |
|-------|--------|---------|
| **V1.1 Shadow** | Add ML scoring to EA; log scores but do not gate trades | Immediately on authorisation |
| **V1.1 Live Gate** | Activate threshold gating at 0.52 | After 50+ shadow trades validate discrimination |
| **V1.1 Tighten** | Raise threshold to 0.54 | After 100+ gated trades confirm WR improvement |
| **Phase 5** | Full ML integration with production readiness review | OOS AUC ≥ 0.58, ≥ 1,000 trades |

---

## Recommendation — Starting Threshold

**Recommended: 0.52**

| Criterion | 0.50 | **0.52** | 0.54 |
|-----------|------|----------|------|
| Annual trades (live) | ~22 | **~17** | ~13 |
| Trade frequency adequate for validation? | Yes | **Yes** | Marginal |
| In-sample win rate on executed signals | 62.8% | **66.3%** | 69.6% |
| Expected OOS win rate range | 51–55% | **54–58%** | 57–62% |
| PF improvement over baseline (2.564) | Marginal | **Meaningful** | Strong |
| Risk if model underperforms OOS | Low | **Moderate** | Higher |

**Rationale for 0.52 over 0.50:** At 0.50, the median Phase 1D-B executed signal has a score of exactly 0.500 — the filter is cutting right at the centre of the distribution, providing only marginal selectivity. The PF improvement at 0.50 (2.63 in-sample) barely clears the Phase 1D-B baseline of 2.564 and will likely fall below it OOS. At 0.52, there is a meaningful buffer.

**Rationale for 0.52 over 0.54:** At 0.54, only ~13 trades/year pass the filter. This is too few for statistical confidence within a reasonable validation window. With a p=0.05 test requiring ~85 observations to detect a 10% win rate improvement, reaching significance at 13 trades/year would take 6+ years. At 17 trades/year (0.52), the window is 5 years — still long, but workable alongside the Phase 5 signal-level dataset which accumulates faster.

---

## Implementation Checklist

### Python Side (ML team)
- [ ] Export LightGBM v2 win_loss model to ONNX (`ML/scripts/export_onnx.py`)
- [ ] Export StandardScaler means/stds to `ML/outputs/research_v2/scaler_params.csv`
- [ ] Validate ONNX output matches Python output on 100 test cases
- [ ] Document feature order and encoding (maps to MQL5 array indices)

### MQL5 Side (EA development)
- [ ] Add `MLConfidenceThreshold` input (default=0.52, range 0.40–0.70)
- [ ] Add `UseMLFilter` input (default=false for shadow mode)
- [ ] Implement feature vector construction (15 features, exact encoding)
- [ ] Implement scaler (load constants from input or compiled-in array)
- [ ] Integrate ONNX inference call
- [ ] Extend CSV export with ML fields
- [ ] Shadow mode: log score always, gate only when `UseMLFilter=true`

### Validation
- [ ] Backtest V1.1 on Phase 1D-B period (2016–2025) to confirm ML gate behaviour matches Python predictions
- [ ] Run forward shadow for minimum 50 trades before activating live gate
- [ ] Monthly review of ML_Score vs actual outcome

---

## Key Artefacts

| Artefact | Location |
|----------|----------|
| v2 LightGBM model | `ML/outputs/research_v2/models/LightGBM_win_loss.pkl` |
| v2 labeled dataset | `ML/data/ICT_ATLAS_Research_Signals_Labeled_v2.csv` |
| Threshold sensitivity | `ML/outputs/research_v2/plots/threshold_sensitivity.png` |
| Threshold analysis CSV | `ML/outputs/research_v2/reports/threshold_analysis.csv` |
| Research track report | `Reports/ICT_ATLAS_Research_Track_Report.md` |
| This document | `Reports/ICT_ATLAS_V1_1_Deployment_Plan.md` |

---

## Important Constraints

1. **Phase 1D-B is frozen.** V1.1 adds a gate only — no changes to entry/exit logic, parameters, or risk rules.
2. **Shadow before live.** The ML gate must not be activated in live trading before shadow validation completes.
3. **Model is not retrained during shadow.** The v2 model is the baseline. Retraining requires a new authorisation cycle.
4. **No position sizing changes until OOS validation is complete.** Option A (flat sizing) only for initial deployment.
5. **This plan requires explicit authorisation before any EA code changes are made.**

---

*Research Track v2: `ML/run_research_pipeline.py` | Dataset: `ML/data/ICT_ATLAS_Research_Signals_Labeled_v2.csv`*  
*Production EA: `Experts/ICT_ATLAS_EA_V1.0.mq5` | V1.1 not yet implemented — design phase only*
