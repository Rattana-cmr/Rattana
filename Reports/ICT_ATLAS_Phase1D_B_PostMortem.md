# ICT ATLAS EA V1.0 — Phase 1D-B Post-Mortem Report
**Date:** 2026-06-12  
**Symbol:** XAUUSD M15 | **Period:** 2016.01.04 – 2025.12.22 (FULL 10 YEARS COMPLETED)  
**Deposit:** $1,000 | **Leverage:** 1:100 | **Risk:** 0.5% per trade  
**Preset:** ICT_ATLAS_Phase1D_B_Long_Only.set

---

## 1. Phase 1D-B Result — BREAKTHROUGH

| Metric | Phase 1 Baseline | Phase 1C | Phase 1D | **Phase 1D-B** | Delta vs Baseline |
|--------|-----------------|----------|----------|----------------|-------------------|
| Date range completed | 2016–2025 ✓ | 2016–2021 ✗ | 2016–2021 ✗ | **2016–2025 ✓** | Full 10 years |
| Total Trades | 716 | 355 | 388 | **425** | −291 |
| Win Rate | 51.7% | 42.0% | 42.3% | **56.7%** | +5.0 pp |
| Net Profit | +$2,896 | −$1,013 | −$957 | **+$13,998** | **+$11,102** |
| Profit Factor | 1.262 | 0.764 | 0.785 | **2.564** | +1.302 |
| Gross Profit | $11,453 | $3,617 | $3,487 | **$22,948** | +$11,495 |
| Gross Loss | −$8,557 | −$4,630 | −$4,444 | **−$8,951** | −$394 |
| Expectancy / Trade | $4.05 | −$2.85 | −$2.47 | **$32.94** | **+$28.89** |
| SHORT trades | 314 | 139 | 187 | **0** | All eliminated |
| LONG trades | 402 | 216 | 201 | **425** | +23 |

**The single change — `AllowShortEntries=false` — transformed a destroyed account (+4 phase failures) into a +$13,998 result. The account grew from $1,000 to ~$14,998 over 10 years.**

---

## 2. All Filters Confirmed Working

| Filter | Rejections / Verification |
|--------|--------------------------|
| AllowShortEntries = FALSE | 64,089 SHORT entries disabled — **zero SHORT trades executed** |
| UseMSSFilter = TRUE | 29,047 MSS rejections — all 425 trades have MSS=YES |
| BlockLondonHours = TRUE | Zero trades during 07:00–09:59 confirmed |
| No BEARISH-weekly LONGs | 0 BEARISH weekly bias trades — preferBull=false means no counter-LONG either |

---

## 3. Year-by-Year Performance

| Year | Trades | WR | PF | Net P&L | Cumulative |
|------|--------|----|----|---------|------------|
| 2016 | 40 | 52.5% | 1.274 | +$114.69 | +$114 |
| 2017 | 34 | 55.9% | 1.066 | +$25.97 | +$141 |
| 2018 | 36 | 30.6% | 0.509 | **−$248.17** | −$107 |
| 2019 | 42 | 45.2% | 1.084 | +$31.73 | −$75 |
| 2020 | 50 | 62.0% | 1.150 | +$113.51 | +$38 |
| 2021 | 44 | 59.1% | 0.661 | **−$214.79** | −$177 |
| 2022 | 37 | 59.5% | 1.773 | +$381.62 | +$205 |
| 2023 | 42 | 54.8% | 1.429 | +$380.41 | +$585 |
| 2024 | 50 | 62.0% | 1.777 | +$1,220.96 | +$1,806 |
| 2025 | 50 | **76.0%** | **5.189** | **+$12,191.79** | **+$13,998** |

**Key observation:** 2018 and 2021 are losing years, but the drawdowns are small enough (~−$248, ~−$215) that the account survives. In Phase 1C and Phase 1D, the account was blown in 2021. Phase 1D-B survives and reaches the explosive 2022–2025 bull market.

---

## 4. 2025 — Exceptional Performance

Gold's parabolic move in late 2025 produced extraordinary results with high-ADX TRENDING setups:

| Month | Trades | WR | P&L |
|-------|--------|-----|-----|
| Jan | 6 | 83.3% | +$1,179 |
| Feb | 4 | 75.0% | +$666 |
| Mar | 5 | **100%** | +$1,285 |
| Apr | 2 | **100%** | +$1,010 |
| May | 4 | 50.0% | +$36 |
| Jun | 4 | 25.0% | −$89 |
| Jul | 6 | 50.0% | −$722 |
| Aug | 2 | **100%** | +$405 |
| Sep | 5 | **100%** | +$1,903 |
| Oct | 3 | **100%** | +$1,933 |
| Nov | 5 | 60.0% | +$2,375 |
| Dec | 4 | **100%** | +$2,211 |
| **Total** | **50** | **76.0%** | **+$12,192** |

The compounding effect (risk % of growing equity) amplified gains: by late 2025, position sizes were much larger than the initial 0.02 lots.

---

## 5. Market Condition Breakdown

| Condition | Trades | WR | PF | P&L | % of Profit |
|-----------|--------|----|----|-----|-------------|
| TRENDING | 287 | 59.2% | 2.793 | +$10,359 | 74.0% |
| RANGING | 111 | 48.6% | 1.288 | +$796 | 5.7% |
| CHOPPY | 27 | 63.0% | 7.914 | +$2,843 | 20.3% |

TRENDING conditions drive 74% of profit. CHOPPY trades are surprisingly strong (PF 7.914) — likely because CHOPPY markets occasionally produce explosive MSS breakouts with large follow-through. RANGING is profitable but modest.

---

## 6. Weekly Bias Breakdown

| Weekly Bias | Trades | WR | PF | P&L |
|-------------|--------|----|----|-----|
| BULLISH | 323 | 57.9% | 2.807 | +$13,427 |
| NEUTRAL | 102 | 52.9% | 1.376 | +$571 |
| BEARISH | **0** | — | — | $0 |

All 425 trades are LONG. When the weekly bias is BEARISH, `preferBull=false` means the primary direction is SHORT, which is blocked by `AllowShortEntries=false`. The counter-direction would be LONG, but since the primary was SHORT (now blocked), no trade is attempted — confirmed by 0 BEARISH-weekly trades. This is correct behavior.

---

## 7. RR Distribution

| RR Band | Trades | % |
|---------|--------|---|
| RR ≥ 3.0 | 136 | 32.0% |
| RR 2.0–3.0 | 43 | 10.1% |
| RR 1.0–2.0 | 38 | 8.9% |
| RR < 1.0 | 208 | 48.9% |
| **Avg RR** | — | **1.401** |

48.9% of trades close below RR 1.0 (stop-loss or breakeven), but 32% hit RR 3.0+ — the asymmetric payoff profile means a minority of large winners cover all losses and generate substantial profit. This is characteristic of ICT-style FVG entries with 3R targets.

---

## 8. Phase Comparison — The Journey

| Phase | Key Change | Result | Lesson |
|-------|-----------|--------|--------|
| Baseline | No filters | +$2,896 | LONGs profitable, SHORTs drag |
| Phase 1B | 5 changes (bugs) | +$2,873 | All changes inert |
| Phase 1C | MSS + P/D align + SHORT filters | −$1,013, blown 2021 | Wrong SHORT filtering combo |
| Phase 1D | MSS + London + BullTrend SHORT block | −$957, blown 2021 | SHORTs still killing |
| **Phase 1D-B** | **LONG ONLY** | **+$13,998 ✓** | **Eliminate SHORTs = breakthrough** |

**The core insight across all phases:** LONGs with MSS confirmation in Gold are strongly profitable. SHORTs have been net-negative in every configuration across 10 years. The MSS filter + LONG-only combination is the viable strategy.

---

## 9. Signal Volume

| Category | Count |
|----------|-------|
| Total signals evaluated | 157,651 |
| SHORT entries disabled | 64,089 (40.6%) |
| MSS not confirmed | 29,047 (18.4%) |
| SL too small | 374 (0.2%) |
| Trades executed | 425 (0.3%) |

The high signal volume (157K) reflects that the EA evaluates every M15 bar for both directions, logging SHORT rejections explicitly. This is valuable ML training data — 64,089 rows showing conditions where SHORT was structurally blocked.

---

## 10. Issues to Investigate

### 10.1 BEARISH Weekly = No LONG Trades
Currently, when weekly bias is BEARISH:
- `preferBull=false` → primary direction = SHORT → blocked
- Counter = LONG → not attempted (code falls through to "no setup")

**Problem:** A BEARISH weekly week does not mean LONGs are impossible. Price still makes intra-week bounces. The EA currently skips ALL trades during bearish weeks.

**Option to test:** Allow LONG counter-trend entries when weekly=BEARISH but daily+H4=BULLISH (mean reversion from key levels). This would add trades in bearish weeks and potentially improve 2018/2021 years.

### 10.2 2018 and 2021 Still Losing
- 2018: 36 trades | WR 30.6% | −$248
- 2021: 44 trades | WR 59.1% | −$215 (high WR but large losses — TP partial closes not optimal)

These are manageable drawdowns (account never blown), but investigating these years could further improve the strategy.

### 10.3 AllowShortEntries=false Skips BEARISH-Weekly Bars Entirely
The current implementation means bars with BEARISH weekly bias generate no trade and no meaningful signal log. For ML training, these bars still contain useful feature data.

---

## 11. Recommended Next Steps

### Phase 2A — LONG ONLY + TRENDING Only
Based on market condition data:
- TRENDING: +$10,359 (74% of profit, PF 2.793)
- Add `TradeInRanging=false + TradeInChoppy=false`
- Expected: fewer trades but higher PF, potentially higher absolute profit in trending years

### Phase 2B — BEARISH Weekly Counter-LONG
- Allow LONG entries when weekly=BEARISH but daily=BULLISH (mean reversion)
- Expected: adds 50–80 trades, fills in the 2018/2021 gap years

### Phase 2C — Score Distribution Improvement
- Enable `UseBiasEngine=true` + `RequireWeeklyBias=true` to spread scores below 100
- Raise `MinScore=100` to filter bottom quartile
- Expected: further quality improvement, higher WR

### Phase 3 — ML Model Development
Phase 1D-B produces a high-quality dataset for ML training:
- 157,651 signal rows (features: MSS, bias alignment, ADX, ATR, market condition, etc.)
- 425 trade rows with full outcome data (profit, RR, MFE, MAE, minutes held)
- Clear binary target: WIN/LOSS with RR achieved
- Rich feature set including Score_H4Align, Score_H1Align, OB_Score, Cond_Score

The Phase 1D-B dataset is the recommended training base for the Random Forest / XGBoost / LightGBM models planned for Phase 2 ML development.

---

*Phase 1D-B confirmed: eliminating SHORT trades is the single most impactful change in the entire Phase 1 series. The MSS-confirmed LONG-only strategy on XAUUSD M15 produces +$13,998 over 10 years vs +$2,896 baseline — a 4.83× improvement in net profit and 8.1× improvement in per-trade expectancy ($32.94 vs $4.05).*
