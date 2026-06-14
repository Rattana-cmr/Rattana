# ICT ATLAS EA — Research & Forward Validation Programme

**Instrument:** XAUUSD M15 only  
**Platform:** MetaTrader 5  
**Status:** Phase 4 Forward Validation + V1.1 Shadow Validation (active)  
**Branch:** `claude/ict-atlas-ea-JZZpQ`

---

## What This Project Is

An MQL5 Expert Advisor that trades ICT (Inner Circle Trader) concepts — liquidity sweeps, market structure shifts, fair value gaps, and order blocks — on Gold (XAUUSD) M15. A full research programme (Phases 1–3) identified a profitable, statistically validated configuration. The EA is now in live forward validation while an ML ranking layer is being developed in parallel.

---

## Production Configuration — Phase 1D-B (Locked)

> **Strategy is frozen. No optimisation, no new experiments without explicit authorisation.**

| Parameter | Value |
|-----------|-------|
| Direction | LONG ONLY (`AllowShortEntries=false`) |
| MSS Filter | Required (`UseMSSFilter=true`) |
| London Hours | Blocked (`BlockLondonHours=true`) |
| Max Stop Loss | 200 pips |
| Market Conditions | All (Trending, Ranging, Choppy) |
| Instrument | XAUUSD M15 only |

**Backtest performance (XAUUSD, 2016–2025, $1,000 deposit):**

| Metric | Value |
|--------|-------|
| Total Trades | 425 |
| Net Profit | +$13,998 |
| Profit Factor | 2.564 |
| Win Rate | 56.7% |
| Expectancy | $32.94 / trade |

---

## Repository Structure

```
Rattana/
├── Experts/
│   └── ICT_ATLAS_EA_V1.0.mq5          ← Production EA (V1.1 shadow inputs compiled in)
│
├── Presets/
│   ├── ICT_ATLAS_Phase1D_B_Long_Only.set   ← Locked production preset
│   ├── ICT_ATLAS_V1_1_ShadowValidation.set ← V1.1 shadow validation (use this now)
│   └── [historical research presets...]
│
├── ML/
│   ├── run_pipeline.py                 ← Production ML pipeline (executed trades)
│   ├── run_research_pipeline.py        ← Research ML pipeline (all signals)
│   ├── data/
│   │   ├── ICT_ATLAS_Phase1DB_Trades.csv           ← 425 Phase 1D-B executed trades
│   │   ├── ICT_ATLAS_Research_Signals_Labeled_v2.csv ← 45,429 labeled signals (2009–2024)
│   │   └── [other datasets...]
│   ├── scripts/
│   │   ├── label_signals.py            ← ATR triple-barrier signal labeler
│   │   ├── aggregate_histdata.py       ← HistData M1→M15 aggregator
│   │   ├── export_onnx.py              ← LightGBM→ONNX model exporter
│   │   └── shadow_score.py             ← Monthly shadow validation scorer
│   └── outputs/
│       ├── research_v2/
│       │   ├── models/                 ← Trained RF/XGB/LGB models (v2)
│       │   ├── deploy/                 ← ONNX model + scaler params for EA
│       │   ├── plots/                  ← ROC, SHAP, threshold charts
│       │   ├── reports/                ← CV results, threshold analysis CSVs
│       │   └── shadow/                 ← Shadow validation scored outputs
│       └── research/                   ← v1 outputs (3,865 signals, 2022–2024)
│
└── Reports/
    ├── ICT_ATLAS_Project_Status_LOCKED.md          ← Formal programme lock document
    ├── ICT_ATLAS_Phase4_DataCollection_Plan.md     ← Phase 4 milestone plan
    ├── ICT_ATLAS_Research_Track_Report.md          ← Research ML findings (v1 + v2)
    ├── ICT_ATLAS_V1_1_Deployment_Plan.md           ← V1.1 architecture design
    ├── ICT_ATLAS_V1_1_Shadow_Validation_Procedure.md ← Shadow validation procedure
    └── [phase post-mortems 1B → 3...]
```

---

## Research Programme — Phase Summary

| Phase | Description | Result |
|-------|-------------|--------|
| Phase 1A–1C | Strategy validation with SHORTs | Unprofitable — 93.8% of losses from SHORTs |
| **Phase 1D-B** | LONG ONLY + MSS filter | **+$13,998 / PF 2.564 — production configuration** |
| Phase 2A | TRENDING condition only | Rejected — −$6,018 regression vs Phase 1D-B |
| Phase 2B | BEARISH weekly LONG bias | Rejected — −$11,792 regression vs Phase 1D-B |
| Phase 3 | ML on 425 executed trades | AUC 0.518 — dataset too small, research mode only |
| Phase 4 | Forward validation (active) | ~42 trades/year accumulating |
| Research Track | ML on 45,429 ATR-labeled signals | **XGB AUC 0.635** across 16 years (2009–2024) |
| **V1.1 Shadow** | ML gate shadow validation (active) | Threshold 0.52, dual-track scoring |

---

## ML Research Track — Key Results

The research track trains ML models on all logged signals (executed + non-executed), labeled with ATR triple-barrier outcomes. This is separate from the production pipeline and does not affect live trading.

### Dataset

| Version | Signals | Period | Source |
|---------|---------|--------|--------|
| v1 | 3,865 | 2022–2024 | MT5 demo bars only |
| **v2 (current)** | **45,429** | **2009–2024** | HistData M1 + MT5 bars |

### CV AUC Results (5-fold, v2 dataset)

| Target | Random Forest | XGBoost | LightGBM |
|--------|--------------|---------|----------|
| win_loss (TP1 before SL) | 0.591 ± 0.007 | **0.635 ± 0.004** | 0.628 ± 0.004 |
| tp2_hit (TP2 before SL) | 0.639 ± 0.006 | **0.690 ± 0.006** | 0.684 ± 0.007 |
| tp3_hit (TP3 before SL) | 0.681 ± 0.007 | **0.742 ± 0.007** | 0.732 ± 0.006 |

All models exceed the Phase 4 production readiness threshold (AUC ≥ 0.58).

### Top Features (SHAP, LightGBM win_loss, v2)

ATR14, Spread_Pips, ATR50, Month, Hour, ATR_Ratio, DayOfWeek, SpreadPctATR, Vol_Regime, ADX.  
Rule-based filters (MSS, Displacement, FVG) do not appear in the top 15.

### Threshold Discrimination at 0.52 (in-sample, executed Phase 1D-B trades)

| Group | Trades | Win Rate | Profit Factor | Expectancy |
|-------|--------|----------|---------------|------------|
| All trades (baseline) | 948 | 50.1% | 1.10 | +0.047R |
| ML TAKEN (score ≥ 0.52) | 389 (41%) | **66.3%** | **2.04** | **+0.339R** |
| ML REJECTED (score < 0.52) | 559 (59%) | 38.8% | 0.71 | −0.156R |

*In-sample figures — true OOS performance will be lower.*

---

## V1.1 Shadow Validation

The ML gate is being validated in shadow mode before any live filtering.

**How it works:**
- EA runs Phase 1D-B unchanged (all qualifying signals execute)
- Every signal logged with `ML_Score`, `ML_Decision`, `ML_Threshold` fields
- Monthly Python scoring compares would-be TAKEN vs REJECTED outcomes

**Preset to use:** `Presets/ICT_ATLAS_V1_1_ShadowValidation.set`

**Monthly procedure:**
```bash
# After exporting CSVs and M15 bars from MT5:

# Label new signals (all-signals rapid track)
python ML/scripts/label_signals.py \
  --signals ML/data/ICT_ATLAS_All_Signals_XAUUSD.csv \
  --bars    ML/data/XAUUSD_M15_Bars.csv \
  --output  ML/data/ICT_ATLAS_Forward_Signals_Labeled.csv

# Score all-signals track (rapid — 2,880 signals/yr)
python ML/scripts/shadow_score.py --mode signals \
  --signals ML/data/ICT_ATLAS_Forward_Signals_Labeled.csv

# Score executed-trade track (primary gate criterion — 42 trades/yr)
python ML/scripts/shadow_score.py --mode trades
```

**Gate activation criteria (both tracks must pass):**

| Track | Criterion |
|-------|-----------|
| All-signals (rapid) | ≥200 signals, TAKEN WR > 52%, p < 0.05 — expected Q3 2026 |
| Executed-trade (primary) | ≥50 trades, TAKEN WR > baseline, p < 0.10 — expected Q3 2027 |

---

## Running the ML Pipelines

```bash
# Production ML pipeline (executed Phase 1D-B trades)
python ML/run_pipeline.py

# Research ML pipeline (all ATR-labeled signals — v2 dataset)
python ML/run_research_pipeline.py \
  --data ML/data/ICT_ATLAS_Research_Signals_Labeled_v2.csv \
  --output-dir ML/outputs/research_v2

# Re-label signals with extended bar data
python ML/scripts/label_signals.py \
  --signals ML/data/ICT_ATLAS_All_Signals_XAUUSD.csv \
  --bars    ML/data/XAUUSD_M15_Extended.csv

# Regenerate ONNX model for EA deployment
python ML/scripts/export_onnx.py
```

---

## Deployed ML Artefacts (V1.1)

| Artefact | Location |
|----------|----------|
| ONNX model (304 KB) | `ML/outputs/research_v2/deploy/ICT_ATLAS_LGB_winloss_v2.onnx` |
| Scaler parameters | `ML/outputs/research_v2/deploy/scaler_params.csv` |
| Feature order | `ML/outputs/research_v2/deploy/feature_order.txt` |
| Validation cases | `ML/outputs/research_v2/deploy/validation_cases.csv` |

ONNX validation: **max diff = 0.000000** vs Python output — exact match confirmed.

---

## What Is Locked

The following require explicit authorisation to change:

- EA strategy logic (entry/exit conditions)
- Phase 1D-B preset parameters
- ML pipeline architecture or feature set
- Training dataset scope (XAUUSD 2015+ only)
- Live ML filtering (`UseMLFilter=false` until gate activation criteria met)

## What Is Permitted

- Bug fixes discovered in forward testing
- Annual ML pipeline rerun with updated trade export
- Monthly shadow scoring and log updates
- EA compilation with minor V1.1 additions (shadow inputs only)

---

## Key Reports

| Report | Description |
|--------|-------------|
| `Reports/ICT_ATLAS_Project_Status_LOCKED.md` | Formal programme lock — all phase outcomes |
| `Reports/ICT_ATLAS_Research_Track_Report.md` | ML research findings v1 and v2 |
| `Reports/ICT_ATLAS_V1_1_Deployment_Plan.md` | V1.1 architecture, ONNX, threshold analysis |
| `Reports/ICT_ATLAS_V1_1_Shadow_Validation_Procedure.md` | Shadow procedure, success criteria, monthly log |
| `Reports/ICT_ATLAS_Phase4_DataCollection_Plan.md` | Phase 4 milestones and dataset validation log |
