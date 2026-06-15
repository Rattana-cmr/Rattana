# ICT ATLAS EA — Formal Project Status

**Status: LOCKED — Phase 1D-B Production Configuration**  
**Locked: June 2026**  
**Branch: `claude/ict-atlas-ea-JZZpQ`**

---

## Research Summary

The ICT ATLAS EA research program completed all planned phases across Phases 1–3, including cross-instrument validation and extended historical dataset analysis. The program successfully identified a profitable, statistically validated configuration.

---

## Validated Configuration — Phase 1D-B

**File:** `Presets/ICT_ATLAS_Phase1D_B_Long_Only.set`  
**EA:** `Experts/ICT_ATLAS_EA_V1.0.mq5`

| Parameter | Value |
|-----------|-------|
| Direction | LONG ONLY (`AllowShortEntries=false`) |
| MSS Filter | Required (`UseMSSFilter=true`) |
| London Hours | Blocked (`BlockLondonHours=true`) |
| Max SL | 200 pips (`MaxSLPips=200`) |
| Market Conditions | All allowed (Trending, Ranging, Choppy) |
| Instrument | XAUUSD only |

**Backtest performance (2016–2025, XAUUSD M15):**

| Metric | Value |
|--------|-------|
| Total Trades | 425 |
| Net Profit | +$13,998 |
| Profit Factor | 2.564 |
| Win Rate | 56.7% |
| Expectancy | $32.94 / trade |

---

## Research Findings

### Phase 1 — Strategy Validation
- Phase 1A–1C: Unprofitable due to SHORT entries (93.8% of losses from SHORT trades)
- Phase 1D-B (LONG ONLY + MSS): Breakthrough — +$13,998 over 10 years, PF 2.564

### Phase 2 — Rule-Based Experiments (All Rejected)
- Phase 2A (TRENDING only): +$7,980 — regression of -$6,018 vs Phase 1D-B
- Phase 2B (BEARISH weekly LONGs): +$2,206 — regression of -$11,792 vs Phase 1D-B

### Phase 3 — Machine Learning
- Models: Random Forest, XGBoost, LightGBM
- CV AUC (win/loss): 0.518 ± 0.078 (near random — dataset too small)
- Conclusion: 425 trades insufficient for reliable ML generalisation
- All models remain in research mode — not for live filtering

### Dataset Validation (June 2026)
- XAUUSD pre-2015 (2004–2014): PF 1.03, $2.10 expectancy — **rejected** (different market regime)
- EURUSD 2015–2025: PF 0.90, -$0.26 expectancy — **rejected** (net loser, wrong instrument)
- Training data locked to **XAUUSD 2015+ only**

---

## Locked Decisions

The following are locked and require new evidence and separate approval to change:

| Item | Status |
|------|--------|
| Strategy logic | FROZEN — no entry/exit filter changes |
| Phase 1D-B preset | FROZEN — no parameter changes |
| ML pipeline methodology | FROZEN — no architecture changes |
| Training dataset scope | FROZEN — XAUUSD 2015+ only |
| Live ML filtering | PROHIBITED — models not ready |
| New instrument experiments | PROHIBITED — requires new evidence |
| Rule-based optimisations | PROHIBITED — requires new evidence |
| Scoring modifications | PROHIBITED — requires new evidence |

---

## Active Obligations — Phase 4 Forward Validation

| Obligation | Detail |
|-----------|--------|
| EA running | Phase 1D-B preset, XAUUSD M15 |
| Export framework | Maintain CSV logging, SetupID linkage, dataset integrity |
| Annual ML rerun | `python ML/run_pipeline.py` once per year with updated trade export |
| Bug fixes | Document and fix bugs found in forward testing — no strategic changes |

---

## Annual Review — Metrics to Report

At each annual review (or at +50 / +100 / +200 trade milestones):

- ROC-AUC (all three models)
- Precision / Recall / F1
- Feature Importance ranking
- SHAP Analysis (top 15 features)
- Threshold Analysis

**Trigger for Phase 5 evaluation:** CV AUC ≥ 0.58 sustained, sample size ≥ 1,000 trades.

---

## Phase 5 — Contingent (Not Yet Authorised)

When and if production readiness criteria are met:
1. Add `MLConfidenceThreshold` input to `ICT_ATLAS_EA_V1.0.mq5`
2. EA calls inference at entry signal
3. Entry taken only if ML probability ≥ threshold
4. Full re-evaluation before live deployment

**Phase 5 requires explicit re-authorisation.**

---

## Key Artefacts

| Artefact | Location |
|----------|----------|
| Production EA | `Experts/ICT_ATLAS_EA_V1.0.mq5` |
| Production preset | `Presets/ICT_ATLAS_Phase1D_B_Long_Only.set` |
| Phase 1D-B report | `Reports/ICT_ATLAS_Phase1D_B_PostMortem.md` |
| Phase 3 ML report | `Reports/ICT_ATLAS_Phase3_ML_Report.md` |
| Phase 4 data plan | `Reports/ICT_ATLAS_Phase4_DataCollection_Plan.md` |
| ML pipeline | `ML/run_pipeline.py` |
| Trained models | `ML/outputs/models/` |
| Training data | `ML/data/ICT_ATLAS_Phase1DB_Trades.csv` |

---

*This document represents the formal conclusion of the ICT ATLAS EA research program as of June 2026. The strategy has a validated rule-based edge. ML research continues in the background as data accumulates.*
