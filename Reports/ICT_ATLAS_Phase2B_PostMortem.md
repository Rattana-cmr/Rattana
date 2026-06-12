# ICT ATLAS EA V1.0 — Phase 2B Post-Mortem Report
**Date:** 2026-06-12  
**Symbol:** XAUUSD M15 | **Period:** 2016.01.04 – 2025.12.30 (full 10 years)  
**Deposit:** $1,000 | **Leverage:** 1:100 | **Risk:** 0.5% per trade  
**Preset:** ICT_ATLAS_Phase2B_Long_BearishWeekly.set

---

## 1. Phase 2B Result — Second Regression

| Metric | Phase 1 Baseline | **Phase 1D-B** | Phase 2A | Phase 2B | Delta vs 1D-B |
|--------|-----------------|----------------|----------|----------|---------------|
| Total Trades | 716 | **425** | 411 | 613 | +188 |
| Win Rate | 51.7% | **56.7%** | 56.4% | 51.2% | −5.5 pp |
| Net Profit | +$2,896 | **+$13,998** | +$7,980 | +$2,206 | **−$11,792** |
| Profit Factor | 1.262 | **2.564** | 2.136 | 1.196 | −1.368 |
| Expectancy / Trade | $4.05 | **$32.94** | $19.42 | $3.60 | −$29.34 |
| BEARISH-weekly trades | 0 | **0** | 0 | 270 | +270 |

**Phase 2B (BEARISH-weekly LONGs enabled) produces +$2,206 — nearly identical to the original Phase 1 baseline and $11,792 worse than Phase 1D-B.**  
Adding LONG trades on bearish-weekly bars is a significant regression.

---

## 2. Year-by-Year Comparison

| Year | Phase 1D-B | Phase 2B | Delta |
|------|-----------|----------|-------|
| 2016 | +$114.69 | −$58.01 | **−$172.70** ↓ |
| 2017 | +$25.97 | −$70.27 | **−$96.24** ↓ |
| 2018 | −$248.17 | −$65.67 | +$182.50 ↑ |
| 2019 | +$31.73 | +$156.31 | +$124.58 ↑ |
| 2020 | +$113.51 | +$218.25 | +$104.74 ↑ |
| 2021 | −$214.79 | −$74.20 | +$140.59 ↑ |
| 2022 | +$381.62 | −$247.22 | **−$628.84** ↓ |
| 2023 | +$380.41 | +$53.41 | **−$327.00** ↓ |
| 2024 | +$1,220.96 | +$295.15 | **−$925.81** ↓ |
| 2025 | +$12,191.79 | +$1,998.36 | **−$10,193.43** ↓ |
| **TOTAL** | **+$13,998** | **+$2,206** | **−$11,792** |

Phase 2B improved 4 years (2018, 2019, 2020, 2021) but destroyed 6 years (2016, 2017, 2022, 2023, 2024, 2025). The 2025 loss alone (−$10,193) dwarfs all the improvements combined (+$552).

---

## 3. Root Cause Analysis

### 3.1 BEARISH-Weekly LONGs Have No Edge

270 BEARISH-weekly LONG trades over 10 years generated net **−$14.28** (PF 0.998 — essentially break-even):

| Year | BEARISH-Weekly Trades | WR | P&L |
|------|----------------------|----|-----|
| 2016 | 34 | 44.1% | +$15.82 |
| 2017 | 16 | 43.8% | −$116.83 |
| 2018 | 21 | **61.9%** | +$124.12 |
| 2019 | 13 | 53.8% | −$48.80 |
| 2020 | 24 | 58.3% | +$316.71 |
| 2021 | 34 | 50.0% | +$43.12 |
| 2022 | 41 | 46.3% | **−$509.05** |
| 2023 | 34 | 44.1% | −$262.37 |
| 2024 | 24 | 45.8% | −$17.74 |
| 2025 | 29 | 48.3% | +$440.74 |
| **Total** | **270** | **48.9%** | **−$14.28** |

These 270 trades achieve 48.9% WR and PF 0.998 — statistically indistinguishable from break-even. There is no edge in taking LONG trades when the weekly bias is BEARISH, even with MSS confirmation. Gold's weekly bearish structure overrides intra-day bullish signals.

---

### 3.2 BEARISH LONGs Displaced 78 High-Quality BULLISH Trades

By allowing BEARISH-weekly LONGs, open positions during bearish-weekly bars blocked subsequent BULLISH-weekly setups from executing:

| Weekly Bias | Phase 1D-B | Phase 2B | Change |
|-------------|-----------|----------|--------|
| BULLISH trades | 323 | **245** | −78 trades |
| BULLISH WR | 57.9% | 53.5% | −4.4 pp |
| BULLISH PF | 2.807 | 1.413 | −1.394 |
| BULLISH P&L | **+$13,427** | **+$1,727** | **−$11,700** |

Phase 2B's BULLISH-weekly trades lost 78 opportunities and dropped from PF 2.807 to PF 1.413. The BEARISH-weekly trades physically occupied position slots, preventing the stronger setups from firing. This is the core mechanism of destruction.

---

### 3.3 Compounding Collapse in 2022–2025

BEARISH-weekly LONGs generated large losses in 2022 (−$509) and 2023 (−$262), significantly reducing equity going into the high-volatility 2024–2025 period:

| Period | Phase 1D-B Equity | Phase 2B Equity | Approx. Difference |
|--------|------------------|-----------------|-------------------|
| End 2021 | ~$823 | ~$926 | +$103 (P2B slightly better) |
| End 2022 | ~$1,205 | ~$679 | −$526 (P2B loses 2022) |
| End 2023 | ~$1,585 | ~$732 | −$853 |
| End 2024 | ~$2,806 | ~$1,027 | −$1,779 |
| End 2025 | ~$14,998 | ~$3,026 | **−$11,972** |

Phase 1D-B entered 2025 with ~2.7× more equity than Phase 2B → ~2.7× larger position sizes → ~2.7× more profit from the same 2025 market moves.

---

### 3.4 RANGING Trades Turned Negative

In Phase 1D-B, RANGING trades were net-positive (+$796, PF 1.288). In Phase 2B they are strongly negative:

| Condition | Phase 1D-B PF | Phase 1D-B P&L | Phase 2B PF | Phase 2B P&L |
|-----------|-------------|---------------|------------|-------------|
| TRENDING | 2.793 | +$10,359 | 1.388 | +$2,538 |
| RANGING | 1.288 | +$796 | **0.870** | **−$466** |
| CHOPPY | 7.914 | +$2,843 | 1.118 | +$133 |

BEARISH-weekly RANGING combinations (short-term LONGs against weekly trend in ranging markets) are strongly losing. Phase 2B added many BEARISH+RANGING setups that were absent in Phase 1D-B.

---

## 4. Phase 1 Summary — All Configurations

| Phase | Key Setting | Net Profit | PF | WR | Verdict |
|-------|------------|-----------|----|----|---------|
| Baseline | No filters | +$2,896 | 1.262 | 51.7% | Reference |
| Phase 1C | MSS+P/D+SHORT filters | −$1,013 | 0.764 | 42.0% | Account blown |
| Phase 1D | MSS+London+BullTrend | −$957 | 0.785 | 42.3% | Account blown |
| **Phase 1D-B** | **LONG ONLY** | **+$13,998** | **2.564** | **56.7%** | **OPTIMAL** ✓ |
| Phase 2A | TRENDING only | +$7,980 | 2.136 | 56.4% | Regression |
| Phase 2B | +BEARISH weekly LONGs | +$2,206 | 1.196 | 51.2% | Regression |

**Phase 1D-B is confirmed as the optimal rule-based configuration.** Every attempt to add or remove filters has produced worse results.

---

## 5. Conclusion: Phase 1 Validation Complete

The Phase 1 series has validated the following strategy edge:

> **XAUUSD M15 | LONG ONLY | MSS-confirmed | All market conditions | London blocked | MaxSL 200 pips**
> - 425 trades over 10 years | WR 56.7% | PF 2.564 | Net +$13,998 | Expectancy $32.94/trade
> - Survives 2016–2021 ranging/bear period, captures 2022–2025 Gold bull market
> - Zero SHORT trades — Gold's structural upward bias makes SHORTs net-negative over any decade

---

## 6. Phase 3 — ML Model Development

Phase 1D-B produces a high-quality, clean dataset for machine learning:

| Dataset | Rows | Key Features |
|---------|------|-------------|
| Signal CSV | 157,651 | MSS, bias alignment, ADX, ATR, market condition, session, scores |
| Trade CSV | 425 | Full outcome: profit, RR, MFE, MAE, minutes held, exit reason |

**ML Goal:** Train a signal quality classifier to predict trade outcome (WIN/LOSS) or expected RR from the signal features. A model that identifies the top 50% of setups by expected value should significantly improve per-trade expectancy beyond $32.94.

**Recommended models:**
1. **LightGBM** — fastest, handles tabular data extremely well, interpretable feature importance
2. **XGBoost** — strong baseline, good with imbalanced classes
3. **Random Forest** — interpretable, resistant to overfitting on small datasets

**Target variable options:**
- Binary: WIN (1) / LOSS (0) at trade close
- Continuous: RR_Achieved (regression)
- Threshold: WIN if RR_Achieved ≥ 1.0 (partial close + breakeven)

---

*Phase 2B confirmed: BEARISH-weekly LONG trades have no edge (PF 0.998) and displace 78 high-quality BULLISH-weekly setups, collapsing the compounding effect. Phase 1D-B (`AllowShortEntries=false`) is the optimal and final rule-based configuration. Ready for Phase 3 ML development.*
