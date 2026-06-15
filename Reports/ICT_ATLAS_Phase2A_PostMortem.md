# ICT ATLAS EA V1.0 — Phase 2A Post-Mortem Report
**Date:** 2026-06-12  
**Symbol:** XAUUSD M15 | **Period:** 2016.01.04 – 2025.12.22 (full 10 years)  
**Deposit:** $1,000 | **Leverage:** 1:100 | **Risk:** 0.5% per trade  
**Preset:** ICT_ATLAS_Phase2A_Long_Trending_Only.set

---

## 1. Phase 2A Result — Regression from Phase 1D-B

| Metric | Phase 1 Baseline | **Phase 1D-B** | Phase 2A | Delta vs 1D-B |
|--------|-----------------|----------------|----------|---------------|
| Total Trades | 716 | **425** | 411 | −14 |
| Win Rate | 51.7% | **56.7%** | 56.4% | −0.3 pp |
| Net Profit | +$2,896 | **+$13,998** | +$7,980 | **−$6,018** |
| Profit Factor | 1.262 | **2.564** | 2.136 | −0.428 |
| Expectancy / Trade | $4.05 | **$32.94** | $19.42 | −$13.52 |
| TRENDING trades | — | 287 | 411 | +124 |
| RANGING trades | — | 111 | 0 | −111 |
| CHOPPY trades | — | 27 | 0 | −27 |

**Phase 2A (TRENDING only) produces $7,980 vs Phase 1D-B's $13,998 — $6,018 worse.**  
Filtering to TRENDING conditions only is a regression, not an improvement.

---

## 2. Year-by-Year Comparison

| Year | Phase 1D-B | Phase 2A | Delta |
|------|-----------|----------|-------|
| 2016 | +$114.69 | +$134.40 | +$19.71 ↑ |
| 2017 | +$25.97 | −$13.10 | −$39.07 ↓ |
| 2018 | −$248.17 | −$272.60 | −$24.43 ↓ |
| 2019 | +$31.73 | +$78.82 | +$47.09 ↑ |
| 2020 | +$113.51 | +$67.72 | −$45.79 ↓ |
| 2021 | −$214.79 | −$235.44 | −$20.65 ↓ |
| 2022 | +$381.62 | +$192.44 | **−$189.18 ↓** |
| 2023 | +$380.41 | +$188.78 | **−$191.63 ↓** |
| 2024 | +$1,220.96 | +$827.35 | **−$393.61 ↓** |
| 2025 | +$12,191.79 | +$7,011.60 | **−$5,180.19 ↓** |
| **TOTAL** | **+$13,998** | **+$7,980** | **−$6,018** |

Phase 2A is worse in 7 out of 10 years. The damage compounds through 2022–2025.

---

## 3. Root Cause Analysis

### 3.1 Removed Profitable RANGING and CHOPPY Trades

Phase 1D-B condition breakdown showed these trades as net-positive:

| Condition | Phase 1D-B Trades | Phase 1D-B P&L | Phase 2A | Loss |
|-----------|------------------|----------------|---------|------|
| RANGING | 111 | **+$796** | 0 | −$796 |
| CHOPPY | 27 | **+$2,843** (PF 7.914) | 0 | −$2,843 |
| **Subtotal removed** | 138 | **+$3,639** | — | **−$3,639** |

The CHOPPY trades were the second-best performing group in Phase 1D-B (PF 7.914). These are rare MSS breakouts that trigger during low-ADX "choppy" conditions but produce explosive follow-through — precisely the kind of high-conviction, low-frequency setups that generate outsized RR. Removing them costs $2,843.

---

### 3.2 Replacement TRENDING Trades Are Lower Quality

By blocking RANGING and CHOPPY setups, the EA had more open "free" bars to evaluate → captured 124 additional TRENDING setups:

| | TRENDING Trades | TRENDING P&L |
|--|----------------|-------------|
| Phase 1D-B | 287 | +$10,359 |
| Phase 2A | **411** | **+$7,980** |
| Difference | +124 more | **−$2,379** |

The 124 extra TRENDING trades are net-losing (-$2,379). These are lower-quality TRENDING setups that were previously displaced by RANGING/CHOPPY trades. The act of blocking RANGING/CHOPPY does not promote higher quality — it simply allows marginal TRENDING setups to execute.

---

### 3.3 Compounding Damage: Lower Early Equity → Smaller 2025 Lots

Phase 2A builds less equity in 2016–2024 → smaller position sizes in 2025:

| Period | Phase 1D-B Equity | Phase 2A Equity | Approx. Difference |
|--------|------------------|-----------------|-------------------|
| End 2021 | ~$823 | ~$760 | −$63 |
| End 2024 | ~$2,629 | ~$1,777 | −$852 |
| 2025 P&L | +$12,192 | +$7,012 | −$5,180 |

Both Phase 2A and Phase 1D-B execute 50 trades in 2025 with nearly identical win rates (76% vs 74%). The $5,180 difference is almost entirely from compounding: Phase 1D-B entered 2025 with more equity → larger lots → larger profits per trade.

---

## 4. The CHOPPY Paradox

The CHOPPY trades (ADX < 18) in Phase 1D-B achieved PF 7.914 — the highest of all three market conditions. This seems counterintuitive but makes sense:

- Low-ADX "choppy" markets occasionally produce a sudden, explosive MSS breakout
- The MSS filter specifically requires a structural shift — exactly the event that breaks a choppy regime
- When MSS fires during a choppy market, it signals the END of the range and the START of a new trend
- These setups produce very large RR because price moves from a compressed range into an extended trend
- Only 27 trades over 10 years — very selective, very profitable when triggered

**Removing CHOPPY trades removed the EA's most explosive setup type.**

---

## 5. Signals

| Category | Count |
|----------|-------|
| Total evaluated | ~157K+ |
| SHORT entries disabled | 65,918 |
| MSS not confirmed | 30,434 |
| Market Condition: RANGING blocked | 468 |
| Market Condition: CHOPPY blocked | 326 |
| Trades executed | 411 |

---

## 6. Verdict: Phase 1D-B Remains Optimal

| Configuration | Net Profit | PF | Trades | Verdict |
|--------------|-----------|----|----|---------|
| Baseline | +$2,896 | 1.262 | 716 | Reference |
| Phase 1D-B (LONG + all conditions) | **+$13,998** | **2.564** | **425** | **OPTIMAL** |
| Phase 2A (LONG + TRENDING only) | +$7,980 | 2.136 | 411 | Regression |

**Phase 1D-B (`AllowShortEntries=false`, all market conditions) is the optimal Phase 1 configuration.** Adding the TRENDING-only filter reduces profit by $6,018 and is not recommended.

---

## 7. What to Test Next

### Option A — Phase 2B: Allow BEARISH-Weekly Counter-LONGs
Phase 1D-B currently executes zero trades when weekly bias = BEARISH (SHORT blocked → no counter-LONG attempted). 2018 and 2021 are losing years partly because bearish-weekly weeks produce no setups at all.

**Proposed change:** When `AllowShortEntries=false` and weekly=BEARISH, attempt LONG if daily+H4=BULLISH (mean reversion from key level). This could improve 2018 (−$248) and 2021 (−$215).

### Option B — Phase 2C: Score Filter
All current trades score 100–125. Raise `MinScore=105` or `MinScore=110` to filter the bottom quartile and see if per-trade quality improves without losing too many winning setups.

### Option C — Proceed to Phase 3 ML
Phase 1D-B is the validated optimal preset. The dataset (157K+ signal rows, 425 trade rows) is ready for ML model training. Use Phase 1D-B as the training base for the Random Forest / XGBoost / LightGBM signal quality classifier.

**Recommendation:** Proceed directly to Phase 3 ML development using Phase 1D-B dataset. Phase 1D-B is the validated optimal configuration and further rule-based filtering has diminishing returns.

---

*Phase 2A confirmed: TRENDING-only filter is a regression. The CHOPPY trades (PF 7.914) and RANGING trades (PF 1.288) in Phase 1D-B are both net-positive and should not be removed. Phase 1D-B (`AllowShortEntries=false`) remains the optimal configuration for Phase 1 validation.*
