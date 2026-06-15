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

## Two Validation Tracks

The shadow validation runs in parallel across two data streams:

| Track | Data source | Signal volume | Statistical power | Purpose |
|-------|------------|--------------|-------------------|---------|
| **All-signals** (rapid) | All Atlas signals, ATR-labeled | ~2,880/yr | High — significance in 2–4 months | Early discrimination evidence |
| **Executed-trades** (primary) | Phase 1D-B trade history | ~42/yr | Low — significance in 14+ months | Gate activation criterion |

The all-signals track does not replace the executed-trade criterion. It provides fast confidence that the model is not broken in live conditions, reducing the risk of waiting 14 months before learning the gate doesn't work.

---

## Monthly Scoring Procedure

```bash
# ── Step 1: Export from MT5 ──────────────────────────────────────
# A. Export All Signals CSV (ICT_ATLAS_All_Signals_XAUUSD.csv) — already logging live
# B. Run ExportBars.mq5 on XAUUSD M15 chart → XAUUSD_M15_Bars.csv
#    (drag script onto XAUUSD M15 chart in MT5, copy file to ML/data/)

# ── Step 2: Label new signals (for all-signals track) ────────────
python ML/scripts/label_signals.py \
  --signals ML/data/ICT_ATLAS_All_Signals_XAUUSD.csv \
  --bars    ML/data/XAUUSD_M15_Bars.csv \
  --output  ML/data/ICT_ATLAS_Forward_Signals_Labeled.csv

# ── Step 3a: All-signals track (rapid) ───────────────────────────
python ML/scripts/shadow_score.py --mode signals \
  --signals ML/data/ICT_ATLAS_Forward_Signals_Labeled.csv

# ── Step 3b: Executed-trade track (primary) ───────────────────────
# Export Trade_History CSV from MT5, save to ML/data/ICT_ATLAS_Phase1DB_Trades.csv
python ML/scripts/shadow_score.py --mode trades

# ── Step 4: Record results in Monthly Log below ───────────────────
```

---

## Success Criteria for Live Gate Activation

### All-Signals Rapid Validation (must pass first)

| # | Criterion | Threshold |
|---|-----------|-----------|
| R1 | Forward signals scored | ≥ 200 (~1 month at 2,880/yr) |
| R2 | TAKEN win rate | > REJECTED win rate |
| R3 | Discrimination p-value | < 0.05 |
| R4 | TAKEN win rate | > 52% |

Passing rapid validation is a prerequisite — if the model fails to discriminate on 200 signals, proceeding to executed-trade gating is not justified.

### Executed-Trade Gate Activation (all four required)

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

## Realistic Timeline (Revised — Dual Track)

| Milestone | Track | Volume | Estimated Date |
|-----------|-------|--------|---------------|
| First all-signals scoring | All-signals | 200 signals | **~Q3 2026 (1 month)** |
| Rapid validation complete | All-signals | 500 signals | **~Q4 2026 (2–3 months)** |
| First executed-trade scoring | Trades | 15 trades | Q4 2026 |
| Executed-trade minimum | Trades | 50 trades | ~Q3 2027 |
| Gate activation possible | Trades | 50+ trades + p < 0.10 | ~Q3–Q4 2027 |
| Phase 5 evaluation threshold | Trades | 1,000 trades | ~2039 |

**The all-signals track compresses the evidence-gathering window from 14+ months to 1–3 months.** If rapid validation passes (expected, given the in-sample results), the 14-month executed-trade wait is undertaken with high confidence rather than uncertainty.

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
