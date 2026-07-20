# ICT ATLAS EA V1.0 — Phase 1D Post-Mortem Report
**Date:** 2026-06-12  
**Symbol:** XAUUSD M15 | **Period:** 2016.01.01 – 2021.12.06 (account blown, test stopped early)  
**Deposit:** $1,000 | **Leverage:** 1:100 | **Risk:** 0.5% per trade  
**Preset:** ICT_ATLAS_Phase1D_MSS_Only.set

---

## 1. Phase 1D Result — Second Critical Failure

| Metric | Phase 1 Baseline | Phase 1C | Phase 1D | Delta vs Baseline |
|--------|-----------------|----------|----------|-------------------|
| Date range completed | 2016–2025 (10 yrs) | 2016–2021 only | **2016–2021 only** | Account blown again |
| Total Trades | 716 | 355 | **388** | −328 |
| Win Rate | 51.7% | 42.0% | **42.3%** | −9.4 pp |
| Net Profit | +$2,896 | −$1,013 | **−$957** | −$3,854 |
| Profit Factor | 1.262 | 0.764 | **0.785** | −0.477 |
| Max Drawdown | ~50.9% | ~101.1% | **~99.7%** | Account destroyed |
| Final Equity | $3,897 | ~$0 | **~$43** | Account at zero |

**The account was blown by December 2021 — identical to Phase 1C outcome.**  
Phase 1D marginally improved PF from 0.764 to 0.785, but the equity curve shape is identical: steady decline from day 1, no recovery, capital destroyed before reaching the profitable 2022–2025 period.

---

## 2. All Filters Confirmed Working

| Filter | Signal Rejections | Verification |
|--------|-----------------|-------------|
| UseMSSFilter = TRUE | 36,235 rejections | All 388 trades have MSS=YES |
| BlockLondonHours = TRUE | — | 0 trades between 07:00–09:59 confirmed |
| BlockShortInBullTrend = TRUE (ADX≥25) | 8,708 rejections | Working — blocked bull-weekly+high-ADX shorts |

All filters work correctly. The failure is in strategy direction, not implementation.

---

## 3. Root Cause Analysis

### 3.1 SHORTs Are the Sole Source of Destruction

**Phase 1D P&L split by direction:**

| Direction | Trades | WR | PF | P&L |
|-----------|--------|----|----|-----|
| LONG | 201 | 46.3% | 0.971 | **−$59.56** |
| SHORT | 187 | 38.5% | 0.624 | **−$897.73** |

**SHORTs account for 93.8% of all losses.** Without SHORT trades, the account loses only −$59.56 over 6 years — essentially break-even — and would survive to capture the profitable 2022–2025 bull market.

---

### 3.2 BlockShortInBullTrend Partially Worked, But Not Enough

The `BlockShortInBullTrend=true + BullTrendADXMin=25` filter blocked 8,708 SHORT signals during bullish weekly trend with high ADX. However:

| Weekly Bias at SHORT entry | Trades | WR | P&L |
|---------------------------|--------|-----|-----|
| BEARISH | 95 | 44.2% | −$485.06 |
| NEUTRAL | 41 | **26.8%** | −$365.20 |
| BULLISH | 51 | 37.3% | −$47.47 |

The **NEUTRAL weekly bias SHORTs are catastrophic** — 26.8% WR, −$365.20. These were not blocked by `BlockShortInBullTrend` because the weekly bias is NEUTRAL, not BULLISH. Even BEARISH-weekly SHORTs lost −$485.06.

**The fundamental problem:** Gold was in a structural bull market 2016–2021. SHORTs fail regardless of weekly bias label:
- BEARISH weekly → Gold reverses bullish intra-week anyway
- NEUTRAL weekly → No edge; Gold's upward drift dominates
- BULLISH weekly (residual 51 trades) → Pure counter-trend

---

### 3.3 SHORTs Lose at Every ADX Level

ADX-based filtering cannot save SHORT trades because the problem is directional, not volatility-based:

| ADX Range | SHORT Trades | WR | P&L |
|-----------|-------------|-----|-----|
| < 20 | 30 | 40.0% | −$115.09 |
| 20–25 | 58 | 37.9% | −$267.69 |
| 25–30 | 31 | 35.5% | −$371.36 |
| 30+ | 68 | 39.7% | −$143.59 |

SHORTs lose at every ADX level. No ADX threshold can fix a directional problem.

---

### 3.4 The Profitable Subset Hidden in the Data

Despite the overall failure, one specific subset is consistently profitable:

| Subset | Trades | WR | PF | P&L |
|--------|--------|----|----|-----|
| LONG + TRENDING | 136 | 51.5% | 1.170 | **+$232.21** |
| LONG + TRENDING + BULLISH weekly | 76 | **56.6%** | **1.754** | **+$489.76** |
| LONG + RANGING | 56 | 35.7% | 0.576 | −$241.42 |
| LONG + CHOPPY | 9 | 33.3% | 0.445 | −$50.35 |

**LONG+TRENDING is profitable every year except 2018 and 2021:**

| Year | L+TREND Trades | WR | P&L |
|------|---------------|-----|-----|
| 2016 | 22 | 50.0% | +$62.16 |
| 2017 | 19 | 63.2% | +$71.25 |
| 2018 | 18 | 50.0% | −$35.71 |
| 2019 | 25 | 56.0% | +$46.41 |
| 2020 | 27 | 44.4% | +$168.41 |
| 2021 | 25 | 48.0% | −$80.31 |

Even with the 2016–2021 ranging period, LONG+TRENDING generates +$232.21. If it survived to 2022–2025, it would capture the full bull market upside.

---

### 3.5 The Core Problem: SHORTs Offset Every LONG Gain

| Year | LONG P&L | SHORT P&L | Net P&L |
|------|---------|----------|---------|
| 2016 | +$51.11 | −$130.26 | −$79.15 |
| 2017 | −$16.18 | −$56.63 | −$72.81 |
| 2018 | −$44.04 | −$70.07 | −$114.11 |
| 2019 | +$8.74 | **−$296.17** | −$287.43 |
| 2020 | +$35.96 | −$227.36 | −$191.40 |
| 2021 | −$95.15 | −$117.24 | −$212.39 |

2019 SHORTs alone: 27 trades, **WR 14.8%**, −$296.17. Gold was in a powerful bull run from mid-2019; every SHORT was immediately reversed.

---

## 4. Signal Analysis

| Signal Category | Count |
|-----------------|-------|
| Total signals evaluated | 45,609 |
| MSS not confirmed (hard-blocked) | 36,235 (79.4%) |
| SHORT blocked (BULLISH weekly + ADX≥25) | 8,708 (19.1%) |
| SL too small | 278 (0.6%) |
| Trades executed | 388 |

The signal volume is much lower than Phase 1C (45,609 vs 110,327) because `RequirePremDiscAlign=false` means P/D alignment is no longer a separate rejection gate — signals pass through faster and MSS is the primary filter.

---

## 5. Phase 1D vs Phase 1C Comparison

| Metric | Phase 1C | Phase 1D | Delta |
|--------|----------|----------|-------|
| Trades | 355 | 388 | +33 |
| Win Rate | 42.0% | 42.3% | +0.3 pp |
| Net Profit | −$1,013 | −$957 | +$56 |
| Profit Factor | 0.764 | 0.785 | +0.021 |
| SHORT P&L | −$817 | −$898 | −$81 (worse) |
| LONG P&L | −$196 | −$60 | +$136 (better) |
| Signal count | 110,327 | 45,609 | −64,718 |

Phase 1D is marginally better than Phase 1C (+$56 net), primarily because removing `RequirePremDiscAlign` allowed more LONG trades to execute in normal conditions rather than only in PREMIUM zone. However, removing `BlockShortInTrend` added more SHORT trades (especially in TRENDING conditions), which added −$515 from SHORT+TRENDING alone.

---

## 6. What Each Phase Taught Us

| Phase | Key Change | Result | Lesson |
|-------|-----------|--------|--------|
| Baseline | No filters | +$2,896 | Bull market 2022-2025 drove all profit |
| Phase 1B | 5 changes (bugs) | +$2,873 | All changes were inert (bugs/config) |
| Phase 1C | MSS + P/D align + London + BlockShortTrend | −$1,013 | P/D align + SHORT filtering = fatal combo |
| Phase 1D | MSS + London + BlockShortBullTrend | −$957 | SHORTs are fundamentally broken regardless |

**Conclusion across all phases:** The SHORT direction has been net-negative in every phase. The LONG direction has been the sole source of profit.

---

## 7. Phase 1D-B — Recommended Next Test: LONG ONLY

### The Evidence

| Scenario | 2016-2021 P&L | Expected 2022-2025 | Full 10yr Projection |
|----------|--------------|-------------------|---------------------|
| All trades (baseline) | −$162 | +$3,058 | +$2,896 |
| Phase 1D (MSS+London) | −$957 | Unknown | Account blown |
| **LONG only (from P1D data)** | **−$60** | **~+$2,000+** | **~+$1,940+** |
| **LONG+TRENDING only (from P1D data)** | **+$232** | **~+$2,500+** | **~+$2,732+** |

### Phase 1D-B Preset Changes (from Phase 1D):

| Setting | Phase 1D | Phase 1D-B | Reason |
|---------|----------|------------|--------|
| `BlockShortInBullTrend` | true | — | Irrelevant — removing all shorts |
| `TradeInRanging` | true | **true → test both** | LONG+RANGING = −$241; consider false |
| `TradeInChoppy` | true | **true → test both** | LONG+CHOPPY = −$50; consider false |
| All SHORT entries | allowed | **BLOCKED** | 93.8% of all losses come from SHORTs |

**Primary test (Phase 1D-B):** Add `AllowShortEntries=false` (if implemented) or set `BlockShortInBullTrend=true + BullTrendADXMin=1` to block ALL shorts regardless of ADX.

**Secondary test (Phase 1E):** LONG ONLY + `TradeInRanging=false + TradeInChoppy=false` — isolate the LONG+TRENDING subset (+$232 in the bad years, expected to compound strongly 2022–2025).

### Phase 1D-B Projected Performance:

- **2016–2021 survival:** −$60 (vs −$957 with SHORTs) — account SURVIVES
- **Reaching 2022–2025:** Captures the Gold bull market
- **Expected 10yr result:** Positive — similar trajectory to baseline but with higher per-trade quality from MSS filter

---

## 8. Action Required

1. **Implement `AllowShortEntries` input** in the EA code (or workaround: `BullTrendADXMin=1` with `BlockShortInBullTrend=true`)
2. **Create Phase 1D-B preset** — LONG ONLY, all other Phase 1D settings kept
3. **Run Phase 1D-B backtest** — full 2016–2025 period
4. **Also run Phase 1E** — LONG ONLY + TRENDING only (`TradeInRanging=false, TradeInChoppy=false`)
5. **Compare Phase 1D-B vs Phase 1E vs Baseline** to identify the optimal configuration

---

## 9. Summary Findings

| Finding | Evidence |
|---------|---------|
| SHORTs are fundamentally broken 2016-2021 | ALL ADX levels, ALL weekly biases losing |
| BlockShortInBullTrend insufficient | Only blocks BULLISH weekly + ADX≥25; NEUTRAL+BEARISH weekly SHORTs still lose |
| LONG+TRENDING is the only profitable regime | +$232 even in 2016-2021 ranging period |
| MSS filter working correctly | 36,235 rejections; all 388 trades have MSS=YES |
| BlockLondonHours working | Zero trades during 07:00–09:59 |
| Account survival requires SHORT elimination | −$60 LONG-only vs −$957 with SHORTs |

**The single change that would have saved both Phase 1C and Phase 1D: block all SHORT entries.**

---

*Phase 1D confirmed: removing P/D alignment helped LONGs (+$136 vs Phase 1C), but SHORTs remain catastrophically negative (−$897) across all market conditions, ADX levels, and weekly biases. Eliminating SHORTs entirely is the required next step.*
