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

### Parity Audit — All 48 Features Confirmed

The ONNX model requires exactly 48 features (verified from `feature_order.txt` and `scaler_params.csv`). The earlier design document incorrectly stated 15 features. **All 48 are confirmed available in the EA at signal time.** Features 44–47, which were previously unverified, are stored in the `SScoreCard` struct (`gScore`) and already logged in the All Signals CSV.

**Encoding maps (Python → MQL5):**

| Python map | Values | MQL5 equivalent |
|-----------|--------|-----------------|
| `BIAS_MAP` | BULLISH=1, NEUTRAL=0, BEARISH=-1 | `BIAS_BULLISH=1, BIAS_NEUTRAL=0, BIAS_BEARISH=-1` |
| `YN_MAP` | YES=1, NO=0 | `1 : 0` boolean cast |
| `COND_MAP` | TRENDING=2, RANGING=1, CHOPPY=0 | `gScore.condScore` (already encoded) |
| `PREMDSC_MAP` | PREMIUM=1, OK/EQUILIBRIUM/UNKNOWN=0, DISCOUNT=−1, BLOCKED=−2 | GetPDLabel() → int |
| `ADR_MAP` | OK=1, BLOCKED=0 | `gADR.blocked ? 0 : 1` |
| `SESSION_MAP` | NEWYORK=1, else=0 | `GetCurrentSession()==SES_NEWYORK ? 1 : 0` |
| `DAY_MAP` | Monday=0 … Friday=4 | `dt.day_of_week - 1` (MQL5: Mon=1..Fri=5) |

> **Note:** `GetPDLabel()` returns "EQUILIBRIUM" when price is between zones. Python maps this to 0 (NaN→fillna(0)), same as "OK". MQL5 must encode "EQUILIBRIUM" as 0 to match.

### Complete 48-Feature Mapping Table

| Index | Feature | CSV Column | EA Variable / Expression | Type |
|-------|---------|------------|--------------------------|------|
| 0 | `hour` | `Timestamp` | `TimeHour(signalTime)` | Derived |
| 1 | `month` | `Timestamp` | `TimeMonth(signalTime)` | Derived |
| 2 | `day_of_week` | `DayOfWeek` | `dt.day_of_week - 1` (Mon=0…Fri=4) | Derived |
| 3 | `session_ny` | `Session` | `GetCurrentSession()==SES_NEWYORK ? 1 : 0` | Derived |
| 4 | `weekly_bias` | `WeeklyBias` | `BiasToInt(gBias.weekly)` | Logged |
| 5 | `daily_bias` | `DailyBias` | `BiasToInt(gBias.daily)` | Logged |
| 6 | `h4_bias` | `H4Bias` | `BiasToInt(gBias.h4)` | Logged |
| 7 | `h1_bias` | `H1Bias` | `BiasToInt(gBias.h1)` | Logged |
| 8 | `bias_alignment` | *(derived)* | Count of TFs where bias==BULLISH (0–4) | Derived |
| 9 | `pdh_sweep` | `PDH_Sweep` | `WasTagSwept("PDH") ? 1 : 0` | Logged |
| 10 | `pdl_sweep` | `PDL_Sweep` | `WasTagSwept("PDL") ? 1 : 0` | Logged |
| 11 | `pwh_sweep` | `PWH_Sweep` | `WasTagSwept("PWH") ? 1 : 0` | Logged |
| 12 | `pwl_sweep` | `PWL_Sweep` | `WasTagSwept("PWL") ? 1 : 0` | Logged |
| 13 | `asian_sweep` | `Asian_Sweep` | `(WasTagSwept("AsianH")\|\|WasTagSwept("AsianL")) ? 1 : 0` | Logged |
| 14 | `eqh_sweep` | `EQH_Sweep` | `WasTagSwept("EQH") ? 1 : 0` | Logged |
| 15 | `eql_sweep` | `EQL_Sweep` | `WasTagSwept("EQL") ? 1 : 0` | Logged |
| 16 | `sweep_count` | *(derived)* | Sum of features[9..15] | Derived |
| 17 | `displacement` | `Displacement` | `gDisp.valid && gDisp.bullish==bullish ? 1 : 0` | Logged |
| 18 | `fvg_present` | `FVG_Present` | `fvgPresent ? 1 : 0` | Logged |
| 19 | `ob_present` | `OB_Present` | `obPresent ? 1 : 0` | Logged |
| 20 | `adr_ok` | `ADR_Status` | `gADR.blocked ? 0 : 1` | Logged |
| 21 | `prem_disc` | `PremDisc_Status` | `GetPDLabel()` → PREMIUM=1, OK/EQUIL=0, DISC=−1, BLOCKED=−2 | Logged |
| 22 | `market_cond` | `MarketCondition` | TRENDING=2, RANGING=1, CHOPPY=0 | Logged |
| 23 | `mss_present` | `MSS` | `gMSS.valid && gMSS.bullish==bullish ? 1 : 0` | Logged |
| 24 | `atr14` | `ATR14_Pips` | `atr14_pips` | Logged |
| 25 | `atr50` | `ATR50_Pips` | `atr50_pips` | Logged |
| 26 | `atr_ratio` | *(derived)* | `atr50_pips > 0 ? atr14_pips / atr50_pips : 1.0` | Derived |
| 27 | `spread_pips` | `Spread_Pips` | `spread_pips` | Logged |
| 28 | `spread_pct_atr` | `SpreadPctATR` | `spdPct` | Logged |
| 29 | `adx` | `ADX_Value` | `adx_value` | Logged |
| 30 | `vol_regime` | *(derived)* | `adx_value * atr14_pips` | Derived |
| 31 | `spread_quality` | *(derived)* | `MathMax(0, 1.0 - spread_pips / MathMax(atr14_pips, 0.001))` | Derived |
| 32 | `score_weekly` | `Score_Weekly` | `gScore.weeklyBias` | Logged |
| 33 | `score_daily` | `Score_Daily` | `gScore.dailyBias` | Logged |
| 34 | `score_liqsweep` | `Score_LiqSweep` | `gScore.liqSweep` | Logged |
| 35 | `score_mss` | `Score_MSS` | `gScore.mss` | Logged |
| 36 | `score_displacement` | `Score_Displacement` | `gScore.displacement` | Logged |
| 37 | `score_fvg` | `Score_FVG` | `gScore.fvg` | Logged |
| 38 | `score_killzone` | `Score_Killzone` | `gScore.killzone` | Logged |
| 39 | `score_smt` | `Score_SMT` | `gScore.smt` | Logged |
| 40 | `score_adr` | `Score_ADR` | `gScore.adrScore` | Logged |
| 41 | `score_po3` | `Score_PO3` | `gScore.po3` | Logged |
| 42 | `score_premdisc` | `Score_PremDisc` | `gScore.premDisc` | Logged |
| 43 | `confluence_score` | `ConfluenceScore` | `gScore.total` | Logged |
| 44 | `score_h4align` | `Score_H4Align` | `gScore.h4Align` (+1/0/−1) | **Logged** |
| 45 | `score_h1align` | `Score_H1Align` | `gScore.h1Align` (+1/0/−1) | **Logged** |
| 46 | `ob_score` | `OB_Score` | `gScore.obScore` (0 or 1) | **Logged** |
| 47 | `cond_score` | `Cond_Score` | `gScore.condScore` (0=CHOPPY, 1=RANGING, 2=TRENDING) | **Logged** |

**Summary:** 35 features are logged directly in the All Signals CSV. 8 are derived at signal time from logged values (hour, month, day_of_week, session_ny, bias_alignment, sweep_count, atr_ratio, vol_regime, spread_quality). Zero features require new EA instrumentation.

### MQL5 Feature Vector Construction (Corrected — 48 features)

```mql5
// All variables assumed live at signal evaluation time
float feat[48];

MqlDateTime dt;
TimeToStruct(signalTime, dt);

// Time
feat[0]  = (float)dt.hour;
feat[1]  = (float)dt.mon;
feat[2]  = (float)(dt.day_of_week - 1);  // Mon=0..Fri=4

// Session
feat[3]  = (float)(GetCurrentSession() == SES_NEWYORK ? 1 : 0);

// Bias (BULL=1, NEUT=0, BEAR=-1)
feat[4]  = (float)(gBias.weekly == BIAS_BULLISH ? 1 : gBias.weekly == BIAS_BEARISH ? -1 : 0);
feat[5]  = (float)(gBias.daily  == BIAS_BULLISH ? 1 : gBias.daily  == BIAS_BEARISH ? -1 : 0);
feat[6]  = (float)(gBias.h4     == BIAS_BULLISH ? 1 : gBias.h4     == BIAS_BEARISH ? -1 : 0);
feat[7]  = (float)(gBias.h1     == BIAS_BULLISH ? 1 : gBias.h1     == BIAS_BEARISH ? -1 : 0);
feat[8]  = (float)((gBias.weekly==BIAS_BULLISH?1:0)+(gBias.daily==BIAS_BULLISH?1:0)
                  +(gBias.h4==BIAS_BULLISH?1:0)+(gBias.h1==BIAS_BULLISH?1:0));  // bias_alignment

// Sweep flags (YES=1, NO=0)
feat[9]  = (float)(WasTagSwept("PDH")    ? 1 : 0);
feat[10] = (float)(WasTagSwept("PDL")    ? 1 : 0);
feat[11] = (float)(WasTagSwept("PWH")    ? 1 : 0);
feat[12] = (float)(WasTagSwept("PWL")    ? 1 : 0);
feat[13] = (float)((WasTagSwept("AsianH")||WasTagSwept("AsianL")) ? 1 : 0);
feat[14] = (float)(WasTagSwept("EQH")    ? 1 : 0);
feat[15] = (float)(WasTagSwept("EQL")    ? 1 : 0);
feat[16] = feat[9]+feat[10]+feat[11]+feat[12]+feat[13]+feat[14]+feat[15];  // sweep_count

// Setup flags
feat[17] = (float)(gDisp.valid && gDisp.bullish == bullish ? 1 : 0);
feat[18] = (float)(fvgPresent ? 1 : 0);
feat[19] = (float)(obPresent  ? 1 : 0);
feat[20] = (float)(gADR.blocked ? 0 : 1);  // adr_ok

// PremDisc: PREMIUM=1, OK/EQUILIBRIUM/UNKNOWN=0, DISCOUNT=-1, BLOCKED=-2
string pdLabel = GetPDLabel();
feat[21] = (float)(pdLabel=="PREMIUM" ? 1 : pdLabel=="DISCOUNT" ? -1 : pdLabel=="BLOCKED" ? -2 : 0);

// Market condition: TRENDING=2, RANGING=1, CHOPPY=0
feat[22] = (float)(gCond.condition==COND_TRENDING ? 2 : gCond.condition==COND_RANGING ? 1 : 0);
feat[23] = (float)(gMSS.valid && gMSS.bullish == bullish ? 1 : 0);  // mss_present

// ATR / volatility
feat[24] = (float)atr14_pips;
feat[25] = (float)atr50_pips;
feat[26] = (float)(atr50_pips > 0 ? atr14_pips / atr50_pips : 1.0);  // atr_ratio
feat[27] = (float)spread_pips;
feat[28] = (float)spdPct;  // spread_pct_atr
feat[29] = (float)adx_value;
feat[30] = (float)(adx_value * atr14_pips);  // vol_regime
feat[31] = (float)MathMax(0.0, 1.0 - spread_pips / MathMax(atr14_pips, 0.001));  // spread_quality

// Confluence component scores (direct from gScore struct)
feat[32] = (float)gScore.weeklyBias;
feat[33] = (float)gScore.dailyBias;
feat[34] = (float)gScore.liqSweep;
feat[35] = (float)gScore.mss;
feat[36] = (float)gScore.displacement;
feat[37] = (float)gScore.fvg;
feat[38] = (float)gScore.killzone;
feat[39] = (float)gScore.smt;
feat[40] = (float)gScore.adrScore;
feat[41] = (float)gScore.po3;
feat[42] = (float)gScore.premDisc;
feat[43] = (float)gScore.total;       // confluence_score
feat[44] = (float)gScore.h4Align;    // +1/0/-1
feat[45] = (float)gScore.h1Align;    // +1/0/-1
feat[46] = (float)gScore.obScore;    // 0 or 1
feat[47] = (float)gScore.condScore;  // 0=CHOPPY, 1=RANGING, 2=TRENDING
```

### Scaling

The model was trained with `StandardScaler` — mean and std per feature are saved in `ML/outputs/research_v2/deploy/scaler_params.csv`. Each feature must be z-scored before inference:

```
scaled[i] = (feat[i] - mean[i]) / std[i]
```

The 48 means and stds are embedded in the EA as compile-time float arrays (exported by `export_onnx.py`).

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
- [ ] Add `MLConfidenceThreshold` input (default=0.52, range 0.40–0.70) — **already done**
- [ ] Add `UseMLFilter` input (default=false for shadow mode) — **already done**
- [ ] Implement feature vector construction (**48 features**, exact encoding per Component 2 table)
- [ ] Implement scaler (embed 48-element MEAN/STD arrays from `scaler_params.csv`)
- [ ] Integrate `OnnxCreate()` in `OnInit()` + `OnnxRun()` at signal time
- [ ] MT5 validation: run 200 cases from `validation_cases.csv` through `OnnxRun()`, confirm max diff < 0.001 vs Python
- [ ] Extend CSV export with ML fields — **already done** (ML_Score, ML_Decision, ML_Threshold)
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
