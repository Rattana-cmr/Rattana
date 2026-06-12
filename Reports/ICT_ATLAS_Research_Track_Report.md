# ICT ATLAS EA — Research Track Report

**Date:** June 2026  
**Status:** ACTIVE RESEARCH — Separate from Phase 1D-B production strategy  
**Dataset:** 3,865 ATR triple-barrier labeled LONG signals (XAUUSD M15, 2022–2024)  
**Pipeline:** `ML/run_research_pipeline.py`

---

## Executive Summary

The signal-based research track has demonstrated genuine, statistically reliable predictive signal — a result not achieved by the Phase 3 executed-trade pipeline. XGBoost achieves CV AUC 0.718 on win_loss and 0.856 on TP3 prediction, well above the 0.58 production readiness threshold. The results are stable across folds (tight standard deviations) indicating real pattern learning rather than noise.

Key finding: **volatility and market-condition features dominate predictive power over rule-based entry filters.** Several current Atlas filters show neutral or slightly negative contribution to ATR-normalised outcomes.

---

## Methodology

### Signal Labeling — ATR Triple-Barrier

For each LONG signal logged by the EA:
- **Entry price** = Close of M15 bar at signal timestamp
- **1R distance** = ATR14_Pips at signal time (already available in signals file)
- **Upper barriers**: Entry + 1R (TP1), + 2R (TP2), + 3R (TP3)
- **Lower barrier**: Entry − 1R (stop loss)
- **Time barrier**: 20 bars (5 hours) — labelled as neutral if no breach

Labels are computed from actual M15 OHLC data. No lookahead beyond the signal bar.

### Dataset Composition

| Category | Count | Win Rate |
|----------|-------|----------|
| All LONG signals labeled | 3,865 | 51.6% |
| Executed Phase 1D-B trades | 194 | 47.9% |
| MSS-rejected signals | 3,671 | 51.8% |
| Outcome: TP1 hit | 1,996 | — |
| Outcome: TP2 hit | 1,202 | — |
| Outcome: TP3 hit | 762 | — |
| Outcome: SL hit | 1,763 | — |
| Time barrier (no decision) | 106 | — |

---

## Model Results

### CV AUC — 5-fold Stratified Cross-Validation

| Target | Random Forest | XGBoost | LightGBM |
|--------|--------------|---------|----------|
| win_loss (TP1 before SL) | 0.688 ± 0.020 | **0.718 ± 0.018** | 0.703 ± 0.010 |
| tp2_hit (TP2 before SL) | 0.750 ± 0.019 | **0.796 ± 0.022** | 0.792 ± 0.022 |
| tp3_hit (TP3 before SL) | 0.810 ± 0.011 | **0.856 ± 0.008** | 0.846 ± 0.011 |

**Comparison to Phase 3 production pipeline (425 executed trades):**

| Target | Phase 3 AUC | Research Track AUC | Improvement |
|--------|------------|-------------------|-------------|
| win_loss (best model) | 0.518 | **0.718** | +0.200 |
| tp2_hit | 0.479 | **0.796** | +0.317 |
| tp3_hit | 0.500 | **0.856** | +0.356 |

All three models exceed the Phase 4 production readiness threshold (AUC ≥ 0.58) on win_loss.

---

## Feature Importance

### Top 15 Features — SHAP Mean |Value| (LightGBM, win_loss)

| Rank | Feature | Mean |SHAP| | Interpretation |
|------|---------|-------------|----------------|
| 1 | adx | 0.152 | Trend strength — high ADX = cleaner directional move |
| 2 | atr50 | 0.147 | Long-term volatility baseline |
| 3 | atr_ratio | 0.131 | Short/long volatility ratio — compression precedes expansion |
| 4 | atr14 | 0.090 | Current volatility |
| 5 | month | 0.081 | Seasonal patterns |
| 6 | spread_pct_atr | 0.079 | Spread cost relative to move size |
| 7 | vol_regime | 0.076 | ADX × ATR composite |
| 8 | h4_bias | 0.074 | H4 timeframe directional bias |
| 9 | hour | 0.074 | Time of day / session |
| 10 | sweep_count | 0.073 | Total liquidity sweeps present |
| 11 | h1_bias | 0.071 | H1 timeframe directional bias |
| 12 | spread_pips | 0.061 | Absolute spread cost |
| 13 | daily_bias | 0.054 | Daily bias alignment |
| 14 | day_of_week | 0.048 | Weekday pattern |
| 15 | pwl_sweep | 0.048 | Previous week low sweep |

**Consistent with Phase 3:** The top features are market-condition measures (ADX, ATR ratio, volatility regime), not rule-based structural features (MSS, Displacement, FVG). H4 bias and sweep structure contribute but rank lower.

---

## Filter Contribution Analysis

For each Atlas entry filter, signals are split into WITH vs WITHOUT groups. Win rate difference shows whether the filter adds positive or negative edge to ATR-normalised outcomes.

| Filter | Win Rate (ON) | Win Rate (OFF) | Edge | p-value | Signal |
|--------|--------------|---------------|------|---------|--------|
| **PWL Sweep** | **61.1%** | 50.6% | **+10.4%** | 0.0002 | *** |
| **EQL Sweep** | **53.3%** | 49.0% | **+4.3%** | 0.0099 | ** |
| **Asian Sweep** | **52.9%** | 49.6% | **+3.4%** | 0.0457 | * |
| PDL Sweep | 53.1% | 51.5% | +1.6% | 0.608 | — |
| EQH Sweep | 52.6% | 50.7% | +1.9% | 0.248 | — |
| OB Present | 51.7% | 51.6% | +0.0% | 1.000 | — |
| PWH Sweep | 50.0% | 52.0% | -2.0% | 0.385 | — |
| NY Session | 50.1% | 51.8% | -1.6% | 0.600 | — |
| FVG Present | 50.1% | 52.2% | -2.1% | 0.247 | — |
| ADR OK | 51.3% | 53.3% | -2.0% | 0.404 | — |
| PDH Sweep | 46.7% | 52.1% | -5.3% | 0.075 | — |
| Displacement | 47.9% | 51.7% | -3.8% | 0.603 | — |

**Statistically significant findings:**
- **PWL Sweep is the strongest positive filter** — sweeping the previous week low is highly predictive of continued upward movement
- **EQL Sweep adds meaningful positive edge** — equal lows swept suggests stop-hunt complete
- **Asian Sweep provides marginal positive contribution**
- **PDH Sweep has a negative trend** (not statistically significant but worth monitoring)
- **Displacement and FVG do not show positive contribution** in this dataset

### Win Rate by Bias Alignment

**Weekly Bias:**

| Weekly Bias | Win Rate | N |
|-------------|----------|---|
| NEUTRAL | 52.7% | 1,147 |
| BULLISH | 51.2% | 2,621 |
| BEARISH | 50.5% | 97 |

**H4 Bias:**

| H4 Bias | Win Rate | N |
|---------|----------|---|
| NEUTRAL | **54.0%** | 2,063 |
| BULLISH | 50.1% | 1,081 |
| BEARISH | 47.2% | 721 |

H4 NEUTRAL outperforms H4 BULLISH — momentum from a consolidation base may be more reliable than momentum in an already-extended trend.

**Market Condition:**

| Condition | Win Rate | N |
|-----------|----------|---|
| TRENDING | 52.5% | 2,311 |
| RANGING | 50.5% | 1,084 |
| CHOPPY | 50.0% | 470 |

---

## Signal Ranking — Threshold Performance

LightGBM win_loss probability threshold sweep (in-sample, for direction only):

| Threshold | % Signals Kept | Win Rate | Avg R |
|-----------|---------------|----------|-------|
| 0.40 | 71.2% | 69.1% | 1.35 |
| 0.50 | 50.2% | 82.4% | 1.93 |
| 0.55 | 41.8% | 87.0% | 2.14 |
| 0.60 | 30.0% | 92.1% | 2.43 |
| 0.65 | 23.3% | 94.6% | 2.54 |

The model shows strong threshold discrimination — signals ranked in the top 30% have 92% ATR win rates in-sample.

---

## Confidence Scoring Framework

For each signal, a composite confidence score can be derived:

```
Confidence = 0.50 × P(TP1) + 0.30 × P(TP2) + 0.20 × P(TP3)
```

This produces a single score from 0–1 representing the model's conviction in a multi-target outcome. Higher scores indicate higher probability of extended directional movement.

---

## Objectives for Ongoing Research

1. **Expand bar data coverage** — extend M15 bars back beyond 2022 to label more signals (requires broker data, not demo account)
2. **Add more signal data** — run additional XAUUSD backtests to increase labeled signal count beyond 3,865
3. **Cross-validate findings** — confirm filter contribution analysis holds on different time windows
4. **Build ranking system** — implement confidence scoring and evaluate ranking vs. execution quality
5. **Validate against Phase 1D-B outcomes** — test whether high-research-score signals correlate with winning Phase 1D-B trades

---

## Research Track Infrastructure

| Component | Location |
|-----------|----------|
| Labeling engine | `ML/scripts/label_signals.py` |
| Research pipeline | `ML/run_research_pipeline.py` |
| Labeled dataset | `ML/data/ICT_ATLAS_Research_Signals_Labeled.csv` |
| M15 price bars | `ML/data/XAUUSD_M15_Bars.csv` |
| Signals source | `ML/data/ICT_ATLAS_All_Signals_XAUUSD.csv/` |
| Research models | `ML/outputs/research/models/` |
| Research plots | `ML/outputs/research/plots/` |
| Research reports | `ML/outputs/research/reports/` |

---

## Important Caveats

1. **ATR-barrier labels ≠ Phase 1D-B trade outcomes.** These models predict short-term price movement, not EA execution quality. Validation against actual Phase 1D-B trades is required before any live integration.
2. **In-sample threshold analysis.** The 92% win rates at threshold 0.65 reflect training data performance. True OOS performance will be lower.
3. **3,865 samples covers 2022–2024 only.** The models have not seen pre-2022 market regimes.
4. **Phase 1D-B remains frozen.** No research finding should modify the production strategy without a separate authorisation process.

---

*Phase 3 production pipeline: `ML/run_pipeline.py` | Research track: `ML/run_research_pipeline.py`*  
*Production readiness criteria unchanged: CV AUC ≥ 0.58 on executed-trade OOS data.*
