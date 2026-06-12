# ICT ATLAS EA — Phase 4: Data Collection Plan

**Status:** ACTIVE — Data collection in progress  
**Started:** June 2026  
**Branch:** `claude/ict-atlas-ea-JZZpQ`

---

## Objectives

Accumulate sufficient trade data from the validated Phase 1D-B strategy to enable reliable ML-based trade selection. The rule-based edge is already confirmed. Phase 4 is purely a data collection exercise — no strategy logic changes, no ML methodology changes.

---

## Strategy Configuration — FROZEN

**Preset:** `Presets/ICT_ATLAS_Phase1D_B_Long_Only.set`

| Parameter | Value | Reason |
|-----------|-------|--------|
| AllowShortEntries | false | LONG ONLY — core Phase 1D-B result |
| UseMSSFilter | true | MSS-confirmed entries only |
| BlockLondonHours | true | Reduces spread noise |
| MaxSLPips | 200 | Caps extreme SL outliers |
| TradeInRanging | true | All market conditions allowed |
| TradeInChoppy | true | All market conditions allowed |
| BlockShortInBullTrend | false | Redundant when AllowShortEntries=false |

**No modifications to EA logic, preset parameters, or ML pipeline are authorised during Phase 4.**

---

## Milestone Schedule

| Milestone | Trade Count | Action |
|-----------|------------|--------|
| M1 | 1,000 trades | Rerun ML pipeline, compare to Phase 3 baseline |
| M2 | 2,500 trades | Rerun ML pipeline, assess feature stability |
| M3 | 5,000 trades | Rerun ML pipeline, evaluate production readiness |

---

## Retraining Procedure (at each milestone)

1. Export completed trade log from MT5 as CSV — same format as `ML/data/ICT_ATLAS_Phase1DB_Trades.csv`
2. Replace (or append to) the data file:
   ```bash
   # Replace entirely (recommended):
   cp <new_export>.csv ML/data/ICT_ATLAS_Phase1DB_Trades.csv

   # Or concatenate backtest + live data:
   # (remove duplicate header row from the appended file)
   ```
3. Run the existing pipeline — no code changes required:
   ```bash
   cd ML
   python run_pipeline.py
   ```
4. Compare outputs to Phase 3 baseline (recorded below)

---

## Phase 3 Baseline (425 trades)

These are the reference metrics against which all future milestones will be compared.

### CV AUC — win/loss target (10-fold stratified)

| Model | AUC Mean | AUC Std |
|-------|----------|---------|
| Random Forest | 0.518 | ±0.078 |
| XGBoost | 0.463 | ±0.093 |
| LightGBM | 0.492 | ±0.095 |

### SHAP Feature Ranking (LightGBM, win/loss)

| Rank | Feature | Mean |SHAP| |
|------|---------|-------------|
| 1 | atr_ratio | 0.440 |
| 2 | vol_regime | 0.313 |
| 3 | adx | 0.244 |
| 4 | atr50 | 0.201 |
| 5 | hour | 0.184 |
| 6 | spread_quality | 0.182 |
| 7 | sweep_count | 0.170 |
| 8 | pwl_sweep | 0.165 |
| 9 | bias_alignment | 0.158 |
| 10 | displacement | 0.141 |

### Strategy Performance Baseline

| Metric | Value |
|--------|-------|
| Total trades | 425 |
| Win rate | 56.7% |
| Total profit | +$13,998 |
| Profit factor | 2.564 |
| Expectancy | $32.94 / trade |

---

## Milestone Tracking

### M1 — 1,000 Trades

| Metric | Phase 3 (425) | M1 (1,000) | Delta |
|--------|--------------|------------|-------|
| RF AUC | 0.518 | — | — |
| XGB AUC | 0.463 | — | — |
| LGB AUC | 0.492 | — | — |
| Top Feature #1 | atr_ratio | — | — |
| Top Feature #2 | vol_regime | — | — |
| Win Rate | 56.7% | — | — |
| Expectancy | $32.94 | — | — |

*Fill in after M1 pipeline run.*

---

### M2 — 2,500 Trades

| Metric | M1 (1,000) | M2 (2,500) | Delta |
|--------|-----------|-----------|-------|
| RF AUC | — | — | — |
| XGB AUC | — | — | — |
| LGB AUC | — | — | — |
| Top Feature #1 | — | — | — |
| Top Feature #2 | — | — | — |

*Fill in after M2 pipeline run.*

---

### M3 — 5,000 Trades

| Metric | M2 (2,500) | M3 (5,000) | Delta |
|--------|-----------|-----------|-------|
| RF AUC | — | — | — |
| XGB AUC | — | — | — |
| LGB AUC | — | — | — |
| Top Feature #1 | — | — | — |
| Top Feature #2 | — | — | — |

*Fill in after M3 pipeline run.*

---

## Production Readiness Criteria

ML trade filtering will be evaluated for production use when **all** of the following are met:

| Criterion | Threshold | Status |
|-----------|-----------|--------|
| CV AUC (best model, win/loss) | ≥ 0.580 sustained | Not yet |
| CV AUC standard deviation | ≤ 0.050 | Not yet |
| Sample size | ≥ 1,000 trades | Not yet |
| Top 5 SHAP features stable across 3 consecutive runs | Feature overlap ≥ 4/5 | Not yet |
| Filtered strategy expectancy vs baseline | ≥ +25% improvement | Not yet |
| Filtered strategy profit factor vs baseline | ≥ 2.50 maintained | Not yet |

---

## Phase 5 (Contingent on Production Readiness)

Once production readiness criteria are met:

1. Add `MLConfidenceThreshold` input to `ICT_ATLAS_EA_V1.0.mq5`
2. EA calls inference at each valid entry signal
3. Entry taken only if ML probability ≥ threshold
4. Recommended initial threshold range: 0.55–0.60 (keeps ~50–55% of trades)
5. Full re-evaluation against Phase 1D-B baseline before live deployment

**Phase 5 is not authorised until all production readiness criteria above are met.**

---

## Notes

- The 47-feature set in `ML/src/data_prep.py` is fixed for Phase 4 to ensure consistent comparison across milestones
- All features use entry-bar data only — no lookahead leakage
- Feature engineering code should not be modified between milestone runs
- If the EA logic must change for operational reasons during Phase 4, a new baseline run must be established before milestone comparisons are meaningful

---

*Phase 3 completed June 2026. Phase 3 full report: `Reports/ICT_ATLAS_Phase3_ML_Report.md`*
