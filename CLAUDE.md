# ICT ATLAS EA — Project Brief for Claude Code

## Project Status: PHASE 4 — FORWARD VALIDATION

**Strategy locked. No optimisation. No new experiments.**

---

## What This Project Is

An MQL5 Expert Advisor for MetaTrader 5 that trades ICT (Inner Circle Trader) concepts on XAUUSD M15. The research program (Phases 1–3) is complete. The EA is in forward validation mode.

## Production Configuration

- **EA:** `Experts/ICT_ATLAS_EA_V1.0.mq5`
- **Preset:** `Presets/ICT_ATLAS_Phase1D_B_Long_Only.set`
- **Key settings:** LONG ONLY, MSS required, BlockLondonHours, MaxSL=200 pips
- **Instrument:** XAUUSD M15 only
- **Performance:** +$13,998 / PF 2.564 / WR 56.7% over 10-year backtest

## What Is Locked

Do NOT change any of the following without explicit user authorisation:

- EA strategy logic (entry/exit conditions)
- Phase 1D-B preset parameters
- ML pipeline architecture or feature set
- Training dataset scope (XAUUSD 2015+ only)

## What Is Allowed

- Bug fixes discovered during forward testing
- Annual ML pipeline rerun when user provides updated trade export
- Maintenance of export framework and CSV logging integrity

## ML Pipeline

- Location: `ML/`
- Entry point: `python ML/run_pipeline.py`
- Models: RF, XGBoost, LightGBM — all in research mode, not for live filtering
- Current CV AUC: 0.518 (425 trades — dataset too small)
- Trigger for live use: CV AUC ≥ 0.58 AND sample ≥ 1,000 trades

## Annual Review Process

When the user uploads a new trade export CSV:
1. Place it at `ML/data/ICT_ATLAS_Phase1DB_Trades.csv`
2. Run `python ML/run_pipeline.py`
3. Report: AUC, Precision, Recall, Feature Importance, SHAP, Threshold Analysis
4. Compare to Phase 3 baseline (AUC 0.518)

## Research Track (Separate from Production)

A signal-based research track is active. It uses ATR triple-barrier labeling on all logged signals — not just executed trades. **Never mix research track outputs with Phase 1D-B production decisions.**

- Entry point: `python ML/run_research_pipeline.py`
- Labeling: `python ML/scripts/label_signals.py`
- Current results: XGB AUC 0.718 (win_loss), 0.856 (tp3_hit) on 3,865 signals
- Key finding: PWL Sweep (+10.4%), EQL Sweep (+4.3%), ADX, ATR ratio are top predictors
- Outputs: `ML/outputs/research/`
- Report: `Reports/ICT_ATLAS_Research_Track_Report.md`

To expand: export new All Signals CSV from MT5 backtest + M15 bars, re-run label_signals.py.

## Key Reports

- Full project status: `Reports/ICT_ATLAS_Project_Status_LOCKED.md`
- Phase 3 ML findings: `Reports/ICT_ATLAS_Phase3_ML_Report.md`
- Phase 4 data plan: `Reports/ICT_ATLAS_Phase4_DataCollection_Plan.md`
- Research track findings: `Reports/ICT_ATLAS_Research_Track_Report.md`

## Branch

All work on: `claude/ict-atlas-ea-JZZpQ`
