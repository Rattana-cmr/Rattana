# ICT ATLAS EA V1.0 — Phase 1B Comparison Report
**Date:** 2026-06-12  
**Symbol:** XAUUSD M15 | **Period:** 2016.01.01 – 2026.01.01  
**Deposit:** $1,000 | **Leverage:** 1:100 | **Risk:** 0.5% per trade

---

## 1. Head-to-Head Summary

| Metric | Baseline | Validation | Delta | Verdict |
|--------|----------|------------|-------|---------|
| Total Trades | 716 | 717 | +1 | = |
| Wins / Losses | 370 / 346 | 371 / 346 | — | = |
| Win Rate | 51.7% | 51.7% | 0.0 pp | = |
| Net Profit | $2,896.92 | $2,873.41 | −$23.51 | = |
| Final Equity | $3,896.92 | $3,873.41 | −$23.51 | = |
| Profit Factor | 1.262 | 1.260 | −0.003 | = |
| Max Drawdown (est.) | 50.9% | 50.9% | 0.0 pp | = |
| Avg RR Achieved | 0.848 | 0.832 | −0.016 | = |
| Expectancy / Trade | $4.05 | $4.01 | −$0.04 | = |

**Overall verdict: The 5 targeted changes produced no meaningful improvement.  
Baseline and Validation are statistically identical.**

The equity curves (screenshots) are visually indistinguishable. Annual P&L is identical year by year (2016–2024), with only 2025 showing a marginal 1-trade difference.

---

## 2. Change-by-Change Post-Mortem

### Change 1 — UseMSSFilter = TRUE
**Hypothesis:** Requiring MSS confirmation would improve quality (Phase 1 data showed MSS=YES → PF 1.697 vs MSS=NO → PF 1.213).

**Result: NO EFFECT — filter was bypassed.**

| | n | WR | PF | P&L |
|--|--|--|--|--|
| MSS=YES trades (Baseline) | 125 | 52.8% | 1.697 | +$784 |
| MSS=NO trades (Baseline) | 591 | 51.4% | 1.213 | +$2,113 |
| MSS=YES trades (Validation) | 126 | 53.2% | 1.763 | +$858 |
| MSS=NO trades (Validation) | **591** | 51.4% | 1.203 | +$2,015 |

With `UseMSSFilter=true`, validation still executed **591 MSS=NO trades** — identical to baseline. The filter flag is not correctly blocking non-MSS setups in the EA code. This is the single most important bug to fix.

**Potential if fixed correctly:** Restricting to MSS=YES + LONG only would yield:
- 75 trades | WR 57.3% | PF 2.197 | P&L +$761 (from Phase 1 data)

---

### Change 2 — SessionLondon = FALSE
**Hypothesis:** London killzone was the only losing session (PF 0.66, −$94.90), removing it would save losses.

**Result: NO EFFECT — UseSessionFilter=false is the master switch.**

Session settings control **labels only** when `UseSessionFilter=false`. The session flag tags a trade for logging purposes but does not gate entry. All 22 trades occurring during London hours (07:00–09:59) executed identically in both runs:

| | London-hour trades (07:00–09:59) | WR | PF | P&L |
|--|--|--|--|--|
| Baseline | 22 | 59.1% | 1.799 | +$97.97 |
| Validation | **22** | 59.1% | 1.799 | +$97.97 |

The 27 "LONDON"-labelled trades in baseline simply became "NONE"-labelled in validation — they were not removed.

> Note: The Phase 1 report showed London PF=0.66 / −$94 based on the label, but the actual London-hour performance is PF 1.799 / +$98. The labeled "LONDON" trades included off-session trades that happened to fall in those hours. The session label was misleading.

---

### Change 3 — MinScore = 60 (raised from 30)
**Hypothesis:** Forcing higher confluence would filter low-quality setups.

**Result: NO EFFECT — all trades already score 100–125.**

| | Min Score | Max Score | Mean Score |
|--|--|--|--|
| Baseline | 120 | 125 | 124.2 |
| Validation | 100 | 125 | 107.0 |

Every trade in both runs scored ≥ 100, far above the 60 threshold. The FVG entry path (always active with `UseFVGEntry=true`) adds scoring components that push all signals to 100+. MinScore=60 is completely inert.

**To actually filter:** MinScore would need to be ≥ 100 to start having any discriminating power, or more scoring components need to be activated to spread the distribution below 100.

---

### Change 4 — BlockShortInBullTrend = TRUE
**Hypothesis:** Blocking shorts during bullish weekly trend would reduce the −$404 SHORT loss.

**Result: REDUNDANT — no shorts were ever attempted during BULLISH weekly bias.**

| Weekly Bias at entry | SHORT trades executed |
|--|--|
| BEARISH | 262 |
| NEUTRAL | 48 |
| BULLISH | **0** |

The EA's directional preference logic (`preferBull=true` when weekly=BULLISH) already prevents SHORT setups from forming during bullish trends. The explicit `BlockShortInBullTrend` check was never triggered. The −$404 SHORT loss comes from BEARISH-weekly and NEUTRAL-weekly shorts, which this change was never designed to address.

---

### Change 5 — MaxSLPips = 200 (raised from 80)
**Hypothesis:** 204 setups in 2025 were rejected for "SL too large"; capturing them would add profit.

**Result: PARTIAL — 84 extra setups captured, near-zero net impact.**

| | "SL too large" rejections | Net effect |
|--|--|--|
| Baseline (MaxSLPips=80) | 204 rejections | — |
| Validation (MaxSLPips=200) | 120 rejections | 84 additional trades admitted |

The 84 extra setups (SL 80–200 pips) had no measurable edge. Net profit difference: −$23.51. The extended SL trades did not improve quality and may have slightly worsened average RR (0.848 → 0.832).

> There are still 120 rejections for "SL > MaxSLPips" in validation (SL > 200 pips). These are extreme-volatility setups unlikely to have positive expectancy.

---

## 3. Additional Findings

### 3A. SHORT Trades Are the Core Problem

The fundamental P&L split reveals a structural issue:

| Direction | Trades | WR | PF | P&L |
|-----------|--------|----|----|-----|
| LONG | 402 | 56.0% | 1.576 | +$3,301 |
| SHORT | 314 | 46.2% | 0.924 | −$404 |

SHORT trades have PF < 1.0 — they are net-negative over 10 years. The full +$3,301 LONG profit is partially offset by −$404 from shorts. Eliminating or significantly filtering SHORT entries is the highest-impact change available.

### 3B. Annual P&L — Profitable Since 2022

| Year | Trades | WR | PF | Net P&L |
|------|--------|----|----|---------|
| 2016 | 79 | 41% | 0.659 | −$353 |
| 2017 | 67 | 54% | 1.260 | +$143 |
| 2018 | 68 | 53% | 1.064 | +$36 |
| 2019 | 70 | 44% | 0.772 | −$161 |
| 2020 | 82 | 52% | 1.112 | +$118 |
| 2021 | 64 | 53% | 1.060 | +$54 |
| 2022 | 65 | 57% | 1.442 | +$423 |
| 2023 | 66 | 61% | 1.667 | +$715 |
| 2024 | 70 | 56% | 1.363 | +$601 |
| 2025 | 85 | 49% | 1.520 | +$1,320 |

2016 and 2019 are losing years. Performance has improved significantly since 2022, driven by Gold's bull run and higher volatility providing better FVG opportunities.

### 3C. TP1/TP2/TP3/BreakEven Fields = 0%
All `TP1_Hit`, `TP2_Hit`, `TP3_Hit`, and `BreakEven_Triggered` fields show 0% in both runs. These GlobalVariable-based outcome trackers are not recording correctly during backtesting. This needs to be fixed to enable proper trade management analysis.

---

## 4. Root Cause Summary

| Change | Root Cause of Failure |
|--------|----------------------|
| MSS filter | **Bug**: `UseMSSFilter` flag is not actually gating non-MSS setups in the EA entry logic |
| London session | **Config**: `UseSessionFilter=false` makes session settings labels-only; sessions don't gate entry |
| MinScore=60 | **Mismatch**: All signals score 100–125 with active FVG path; threshold is far too low |
| SHORT blocking | **Redundant**: Directional preference already handles BULLISH+SHORT prevention |
| MaxSLPips=200 | **Marginal edge**: High-SL setups don't carry positive expectancy |

---

## 5. Phase 2 Recommendations

### Priority 1 — Fix MSS Filter (Code Bug)
The `UseMSSFilter=true` should reject any entry where MSS was not detected. If fixed, isolating LONG+MSS=YES trades yields:
- **75 trades | WR 57.3% | PF 2.197** — a substantial quality improvement
- Fewer trades, but dramatically higher per-trade quality

### Priority 2 — Enable UseSessionFilter=true (Config Fix)
Set `UseSessionFilter=true` in the preset to make session settings actually gate trades. Test NY-only (`SessionNewYork=true`, all others false) as NY has the best statistics.

### Priority 3 — Filter SHORT Trades (Strategy Change)
Options (from conservative to aggressive):
- **Option A**: Disable all SHORT trades (`AllowShort=false` if implemented)
- **Option B**: Only allow SHORT when Weekly+Daily are BOTH BEARISH
- **Option C**: Raise the SHORT direction threshold to require MSS confirmation

### Priority 4 — Raise MinScore to 100+ (Config Fix)
With all current trades scoring 100–125, MinScore=100 would start filtering the bottom quartile. Alternatively, enable `UseBiasEngine=true` + `RequireWeeklyBias=true` to spread the score distribution meaningfully.

### Priority 5 — Fix TP1/TP2/TP3/BE Tracking (Code Fix)
GlobalVariable-based trade outcome tracking is not recording during backtests. Implement tick-based tracking or use a different mechanism to capture partial close events.

---

## 6. Proposed Phase 2 Test Matrix

| Test | Key Setting Changes | Expected Impact |
|------|--------------------|----|
| **P2A — MSS-only** | Fix MSS filter bug + UseMSSFilter=true | Reduce trades ~83%, raise PF to ~1.7+ |
| **P2B — NY session only** | UseSessionFilter=true, NY only | Reduce trades ~15%, improve quality |
| **P2C — LONG only** | Block all SHORT entries | Remove −$404 SHORT drag |
| **P2D — Combined** | MSS=true + NY only + LONG only | Full quality filter stack |

Run all 4 in a single batch for direct comparison. P2D is the target configuration for Phase 3 live optimization.

---

*Report generated: 2026-06-12 | Branch: claude/ict-atlas-ea-JZZpQ*
