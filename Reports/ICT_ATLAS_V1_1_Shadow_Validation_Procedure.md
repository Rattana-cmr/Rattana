# ICT ATLAS EA V1.1 — Shadow Validation Procedure

**Date:** June 2026  
**Status:** APPROVED — Pending implementation  
**Threshold:** 0.52  
**Authorised by:** Project owner, June 2026  
**Separate from:** Atlas Scalper Phase 8 shadow validation  

---

## Objective

Shadow validation answers one question before live gating is activated:

> **Does the model's TAKEN / REJECTED classification predict actual trade outcomes in live forward testing?**

The Phase 1D-B strategy continues executing all qualifying signals unchanged. The ML score is logged at each signal but does not affect trade execution. After sufficient data accumulates, TAKEN and REJECTED win rates are compared to determine whether the gate adds real edge.

---

## What Changes for Shadow Mode (EA V1.1 Shadow)

| Component | Phase 1D-B (current) | V1.1 Shadow |
|-----------|---------------------|-------------|
| Entry logic | Unchanged | **Unchanged** |
| Exit logic | Unchanged | **Unchanged** |
| Position sizing | Unchanged | **Unchanged** |
| ML gate | None | **Logging only — not filtering** |
| CSV export | Existing fields | **+ ML_Score, ML_Decision, ML_Threshold, ML_Version** |

No trades are skipped in shadow mode. Every trade that would have been taken under Phase 1D-B is still taken.

---

## Monthly Scoring Procedure

After exporting the updated trade CSV from MT5:

```bash
# 1. Export trade history from MT5 as CSV (same format as existing)
#    Save to: ML/data/ICT_ATLAS_Phase1DB_Trades.csv

# 2. Run the shadow scorer
python ML/scripts/shadow_score.py

# 3. Review report in: ML/outputs/research_v2/shadow/shadow_summary.csv
# 4. Record results in the Monthly Log table below
```

The scorer reads the trade CSV, scores each trade with the v2 LightGBM model, classifies as TAKEN (≥ 0.52) or REJECTED (< 0.52), and reports win rate and statistical significance.

---

## Success Criteria for Live Gate Activation

**All four criteria must be satisfied simultaneously before activating the ML gate.**

| # | Criterion | Threshold | Rationale |
|---|-----------|-----------|-----------|
| 1 | Forward-test trades scored | ≥ 50 | Minimum for meaningful statistics (~14 months at 42/yr) |
| 2 | TAKEN win rate | > Baseline win rate | Gate must outperform ungated baseline |
| 3 | Discrimination p-value | < 0.10 (one-sided) | Statistical evidence that TAKEN ≠ REJECTED |
| 4 | TAKEN win rate | > 52% | Absolute floor — must exceed coin flip with margin |

**Supplementary checks (informational, not blocking):**

| Check | Target |
|-------|--------|
| TAKEN profit factor | > Phase 1D-B PF (2.564) |
| REJECTED win rate | < TAKEN win rate |
| ML score distribution stable | Mean score ± 0.05 of training mean (0.500) |
| No model degradation | Scores still discriminating (not clustering at 0.5) |

---

## What Constitutes Failure

If after 100 forward-test trades **any** of the following persist, initiate a review before proceeding:

- TAKEN win rate ≤ baseline win rate
- p-value > 0.25 with n ≥ 100 (model shows no discrimination)
- Mean ML score on live trades deviates > 0.10 from 0.500 (distribution shift)
- TAKEN group has ≥ 5 consecutive losses (check for regime change)

Failure does not automatically abort the V1.1 programme. It triggers a formal review of whether the feature set or threshold needs adjustment.

---

## Activation Decision Process

When success criteria are met, the following steps are required before live gating:

1. **Formal confirmation:** Run `shadow_score.py` and confirm all four criteria satisfied
2. **Model verification:** Run `python ML/scripts/export_onnx.py` to regenerate ONNX and validate outputs match Python (max diff must be < 0.001)
3. **EA code review:** V1.1 MQL5 changes reviewed before compilation
4. **Backtest check:** Run V1.1 EA on Phase 1D-B backtest period (2016–2025) and confirm gate behaviour matches shadow scorer predictions on the same data
5. **Authorization:** Explicit written approval from project owner
6. **Deploy:** Set `UseMLFilter=true` in EA, `MLConfidenceThreshold=0.52`

---

## Realistic Timeline

At approximately 42 trades/year (Phase 1D-B forward rate):

| Milestone | Trades | Estimated Date |
|-----------|--------|---------------|
| First shadow scoring | ~15 | Q4 2026 |
| Minimum threshold reached | 50 | ~Q3 2027 |
| Strong statistical power | 100 | ~Q3 2029 |
| Phase 5 evaluation threshold | 1,000 | ~2039 |

The 50-trade minimum is a floor for starting the statistical assessment, not a guarantee of significance. The discrimination test needs the TAKEN and REJECTED groups to be large enough — at 41% acceptance rate, 50 total trades yields ~21 TAKEN and ~29 REJECTED, which provides limited power. The p < 0.10 threshold is chosen accordingly (rather than the more standard p < 0.05) to allow earlier detection of real signal.

---

## Monthly Log

| Month | Total Trades | TAKEN | REJECTED | TAKEN WR | REJECTED WR | p-value | Criteria Met? |
|-------|-------------|-------|----------|----------|-------------|---------|--------------|
| Jun 2026 (baseline backtest) | 425 | 77 | 348 | 63.6% | 55.2% | 0.219 | No (in-sample reference) |
| — | — | — | — | — | — | — | — |

*Populate after each monthly export. First live entries expected Q3–Q4 2026.*

---

## Deployment Artefacts (Python Side — Complete)

All Python-side deliverables are complete and committed.

| Artefact | Location | Status |
|----------|----------|--------|
| v2 LightGBM model | `ML/outputs/research_v2/models/LightGBM_win_loss.pkl` | ✓ Complete |
| ONNX model | `ML/outputs/research_v2/deploy/ICT_ATLAS_LGB_winloss_v2.onnx` | ✓ Complete |
| Scaler parameters | `ML/outputs/research_v2/deploy/scaler_params.csv` | ✓ Complete |
| Feature order | `ML/outputs/research_v2/deploy/feature_order.txt` | ✓ Complete |
| Validation cases | `ML/outputs/research_v2/deploy/validation_cases.csv` | ✓ Complete (200 cases) |
| ONNX export script | `ML/scripts/export_onnx.py` | ✓ Complete |
| Shadow scorer | `ML/scripts/shadow_score.py` | ✓ Complete |
| Deployment plan | `Reports/ICT_ATLAS_V1_1_Deployment_Plan.md` | ✓ Complete |

**ONNX validation:** max diff = 0.000000 — Python and ONNX outputs match exactly.

---

## MQL5 Implementation Checklist (Not Yet Started)

These EA changes are required for shadow mode. They do not affect trade execution.

- [ ] Add input: `bool UseMLFilter = false;` (shadow default)
- [ ] Add input: `double MLConfidenceThreshold = 0.52;`
- [ ] Add `OnnxCreate()` call in `OnInit()` to load `ICT_ATLAS_LGB_winloss_v2.onnx`
- [ ] Add feature vector construction (48 features, exact order from `feature_order.txt`)
- [ ] Add StandardScaler step (constants from `scaler_params.csv`)
- [ ] Add `OnnxRun()` call and extract `P(win_loss)` from output
- [ ] Add `ML_Score`, `ML_Decision`, `ML_Threshold`, `ML_Version` to CSV export
- [ ] In shadow mode (`UseMLFilter=false`): log score but do not gate
- [ ] In live mode (`UseMLFilter=true`): skip trade if score < threshold
- [ ] Backtest V1.1 on 2016–2025 to verify gate behaviour

---

## Notes

- The baseline table row (425 backtest trades) is an **in-sample reference only** — it demonstrates the scorer works, not that the gate is ready. The acceptance rate in that run (18%) was artificially low because the historical trade CSV lacks some feature columns (they default to zero). Forward-test data with all features populated will show the expected ~41% acceptance rate.
- Monthly scoring runs should use the **full cumulative trade history**, not just new trades, to avoid sample slicing artefacts.
- The threshold of 0.52 is fixed for the shadow period. Do not adjust until criteria are met and a new evaluation is authorised.

---

*Shadow validation script: `python ML/scripts/shadow_score.py`*  
*ONNX export: `python ML/scripts/export_onnx.py`*  
*Deployment plan: `Reports/ICT_ATLAS_V1_1_Deployment_Plan.md`*
