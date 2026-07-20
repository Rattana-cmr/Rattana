# ICT ATLAS EA V1.0 — Phase 1C Post-Mortem Report
**Date:** 2026-06-12  
**Symbol:** XAUUSD M15 | **Period:** 2016.01.01 – 2021.11.01 (account blown, test stopped early)  
**Deposit:** $1,000 | **Leverage:** 1:100 | **Risk:** 0.5% per trade

---

## 1. Phase 1C Result — Critical Failure

| Metric | Phase 1 Baseline | Phase 1C | Delta |
|--------|-----------------|----------|-------|
| Date range completed | 2016–2025 (10 yrs) | **2016–2021 only** | Account blown before 2022 |
| Total Trades | 716 | 355 | −361 |
| Win Rate | 51.7% | **42.0%** | −9.7 pp |
| Net Profit | +$2,896 | **−$1,013** | −$3,910 |
| Profit Factor | 1.262 | **0.764** | −0.498 |
| Max Drawdown | ~50.9% | **101.1%** | Account destroyed |
| Final Equity | $3,897 | **−$13** | Account at zero |

**The account was blown by November 2021 — 4 years before the test end date.**  
The equity curve shows a steady decline from day 1 with no recovery. All 5 Phase 1C filters are verified working correctly. The problem is not implementation — it is strategy design.

---

## 2. All 5 Filters Confirmed Working

| Filter | Signal Rejections | Verification |
|--------|-----------------|-------------|
| UseMSSFilter = TRUE | 95,412 rejections | All 355 trades have Score_MSS = 20 (MSS=YES) |
| RequirePremDiscAlign = TRUE | 6,213 rejections | 0 LONG-in-DISCOUNT, 4 SHORT-in-PREMIUM (rounding) |
| BlockLondonHours = TRUE | — | Session data confirms no London-hour trades |
| BlockShortInTrend = TRUE | 3,371 rejections | All SHORT trades in RANGING or CHOPPY only |
| MaxSLPips = 200 | — | Wider SL trades captured |

The filters work exactly as coded. The failure is in the **logic** of the filter combination, not the implementation.

---

## 3. Root Cause Analysis

### 3.1 The SHORT + DISCOUNT Disaster

**Phase 1C SHORTs: 139 trades | WR 38.1% | PF 0.596 | −$817.14**

The combination of `BlockShortInTrend + RequirePremDiscAlign` created a fatal trap:

| What `BlockShortInTrend` does | What `RequirePremDiscAlign` does |
|-------------------------------|----------------------------------|
| Blocks SHORTs when TRENDING + ADX ≥ 25 | Requires SHORTs to be in DISCOUNT zone |
| Removes the only competitive SHORT context | Forces SHORTs into range lows in a bull market |

**Combined effect:** SHORTs are only allowed when:
- Market is RANGING or CHOPPY (NOT trending)
- Price is at the LOW end of the dealing range (DISCOUNT)
- Result = shorting at range lows in a structural Gold bull market = consistently losing

| MarketCondition | SHORT+DISCOUNT trades | WR | P&L |
|-----------------|----------------------|-----|-----|
| RANGING | 120 | 39.2% | −$667 |
| CHOPPY | 15 | 26.7% | −$150 |
| TRENDING | **0** | — | — (blocked) |

**42 of 139 SHORT trades occurred with BULLISH weekly bias** — the EA was shorting at range lows during a bullish weekly trend. Pure counter-trend in a Gold bull market.

| Year | SHORT+DISCOUNT | WR | P&L |
|------|---------------|-----|-----|
| 2016 | 25 | 60% | +$16 |
| 2017 | 19 | 47% | −$114 |
| 2018 | 19 | 32% | −$133 |
| 2019 | 19 | **21%** | −$259 |
| 2020 | 35 | 29% | −$186 |
| 2021 | 18 | 39% | −$132 |

2019 was catastrophic at 21% win rate — Gold was in a strong bull trend, SHORTs at discount were immediately reversed.

---

### 3.2 LONG + PREMIUM Underperformance

**Phase 1C LONGs: 216 trades | WR 44.4% | PF 0.913 | −$196.15**

Expected from Phase 1 analysis: PREMIUM LONGs = 58.7% WR. Actual: 44.4% WR. Why?

**The MSS filter changes WHICH premium trades are taken.**

Phase 1 PREMIUM trades (58.7% WR) = any PREMIUM-zone trade (FVG/OB/breakout/continuation mix).  
Phase 1C PREMIUM trades (44.4% WR) = ONLY those where MSS breakout also confirmed.

MSS-confirmed + PREMIUM = entry AFTER a structural shift, at elevated prices:
- Works in a sustained bull trend (2022–2025): price keeps going up after MSS breakout
- Fails in ranging markets (2016–2021): price reverts after breakout, SL hit

| Year | LONG+PREMIUM | WR | P&L |
|------|-------------|-----|-----|
| 2016 | 36 | 47% | +$74 |
| 2017 | 35 | 46% | −$111 |
| 2018 | 38 | 37% | −$109 |
| 2019 | 36 | 42% | −$3 |
| 2020 | 37 | 57% | +$140 |
| 2021 | 34 | 38% | −$188 |

Only 2016 and 2020 were profitable (Gold had directional moves those years). 2017–2019 and 2021 were range-bound — MSS breakouts repeatedly failed.

---

### 3.3 The Core Problem: Regime Sensitivity

Phase 1 (baseline) survived 2016–2021 with a modest −$162 because it took MIXED trades in both directions with no directional bias requirement. It ground through the poor years and then captured the 2022–2025 bull market for +$3,058.

Phase 1C created a **trend-dependent** strategy:
- MSS breakout trades require trending conditions to follow through
- PREMIUM entries require the trend to continue from already-elevated prices
- DISCOUNT shorts fail in a structural bull market regardless of MSS

The Phase 1C strategy only works in a STRONG bull market. It destroys capital in ranging/bear conditions — precisely the conditions of 2016–2021.

**The 2022–2025 bull market was the source of ALL Phase 1 profits (+$3,058). Phase 1C destroyed the account before getting there.**

---

## 4. Signal Explosion Explained

Phase 1C logged **110,327 signals** vs Phase 1's **925 signals**.

**Why:**
- Phase 1: Average trade held 74 hours → 86% of time had open positions → `CanTrade()=false` → no signals logged
- Phase 1C: 355 trades with likely similar durations but many more "free" bars → more bars evaluated
- With `UseMSSFilter=true`: nearly every bar logs "MSS not confirmed" as a rejection reason
- 95,412 of 110,011 rejected signals = "MSS not confirmed" — the EA evaluated every available bar for potential MSS

This signal volume is expected behavior. The ML dataset from Phase 1C contains rich data about what conditions lead to rejections, which is valuable for ML training.

---

## 5. What Each Filter Actually Did

| Filter | Intended Effect | Actual Effect | Verdict |
|--------|----------------|---------------|---------|
| MSS Mandatory | Remove low-quality non-MSS setups | ✅ Works — only MSS trades taken | Correct but overfiltering |
| LONG in PREMIUM | Capture high-WR breakout longs | ❌ Works, but MSS+PREMIUM = worse, not better | Logic flaw |
| Block London hours | Remove losing session | ✅ Works — no London trades | Minor benefit |
| Block SHORT in TREND | Remove losing SHORTs in trend | ❌ Creates RANGING shorts only, which are worse | Backfires |
| MaxSLPips=200 | Capture high-vol setups | Partial — but irrelevant given overall failure | Minor |

---

## 6. Phase 1D — Corrected Test Plan

Based on Phase 1C findings, the recommended next test is:

### Phase 1D: MSS-Only LONG Trades

**Key insight from Phase 1 data:**

| Subset | Trades | WR | PF | P&L |
|--------|--------|----|----|-----|
| LONG only (baseline) | 402 | 56.0% | 1.576 | +$3,301 |
| MSS=YES only (baseline) | 125 | 52.8% | 1.697 | +$784 |
| **LONG + MSS=YES (baseline)** | **75** | **57.3%** | **2.197** | **+$761** |

LONG + MSS=YES with only 75 trades over 10 years generated +$761 — that's $10.15/trade expectancy vs $4.05/trade baseline.

### Phase 1D Preset Changes (from baseline):

| Setting | Baseline | Phase 1D | Reason |
|---------|----------|----------|--------|
| `UseMSSFilter` | false | **true** | Hard-block non-MSS (bug now fixed) |
| `BlockShortInBullTrend` | false | **true** + `BullTrendADXMin=25` | Block shorts in bull trend |
| `BlockLondonHours` | false | **true** | Remove London-hour trades |
| `RequirePremDiscAlign` | false | **false** | REMOVE — caused disaster |
| `BlockShortInTrend` | false | **false** | REMOVE — backfired |
| `MaxSLPips` | 80 | **200** | Keep extended SL |
| `MinScore` | 30 | 30 | Keep baseline |

**What Phase 1D tests:** Pure MSS filter (fixed), London block, wider SL — WITHOUT the P/D alignment or TREND-SHORT blocking that destroyed Phase 1C.

### Optional Phase 1D-B: LONG Only

If MSS-only still has SHORT drag, add `AllowShortEntries=false` (if implemented) or raise `BullTrendADXMin=1` to block ALL shorts regardless of ADX.

---

## 7. Action Required

1. **Do NOT use Phase 1C preset** — it will blow any live account
2. **Create Phase 1D preset** (MSS only + London block, NO P/D align, NO trend-short block)
3. **Run Phase 1D backtest** with 2016–2025 full period
4. **Phase 1D-B**: Also test LONG-only variation
5. The 110,327 signal rows in Phase 1C are valuable ML training data — keep them

---

*Phase 1C confirmed: filters work correctly, but the combination created a strategy that only survives in bull market conditions. The 2016–2021 ranging period destroyed the account before the 2022–2025 bull market could generate profits.*
