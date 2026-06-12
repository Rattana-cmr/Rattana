# ICT ATLAS EA — Comprehensive Dataset Analysis Report

**Symbol:** XAUUSD (Gold)  
**Timeframe:** M15  
**Backtest Period:** 2016.01.01 – 2025.12.31 (10 Years)  
**Initial Deposit:** $1,000 USD  
**Report Generated:** 2026-06-12  

---

## Table of Contents

1. [Dataset Summary](#1-dataset-summary)
2. [Performance Analysis](#2-performance-analysis)
3. [Feature Analysis](#3-feature-analysis)
4. [Trade Quality Analysis](#4-trade-quality-analysis)
5. [Setup Analysis](#5-setup-analysis)
6. [Machine Learning Preparation](#6-machine-learning-preparation)
7. [Findings & Recommendations](#7-findings--recommendations)

---

## 1. Dataset Summary

| Metric | Value |
|--------|-------|
| Total Signals Evaluated | **925** |
| Total Trades Executed | **708** (716 closed & logged in CSV) |
| Total Rejected Signals | **217** |
| Win Rate | **51.7%** (370W / 346L) |
| Profit Factor | **1.262** |
| Net Profit (CSV) | **$2,896.92** |
| Gross Profit | $13,936.65 |
| Gross Loss | −$11,039.73 |
| Max Drawdown (trade sequence) | −$704.85 |
| Average RR Achieved | **0.848R** |
| Average MFE | 24.9 pips |
| Average MAE | 16.5 pips |
| MFE / MAE Ratio | **1.504** |
| Average Trade Duration | **74.4 hours** (3.1 days) |

### Exit Reason Distribution

| Exit Reason | Count | % | Win Rate | Net P&L |
|-------------|-------|----|----------|---------|
| ExpertAdvisor (Friday / EA close) | 419 | 58.5% | **66.3%** | +$6,531.05 |
| StopLoss | 265 | 37.0% | 22.6% | −$8,303.64 |
| TakeProfit (TP3 runner) | 32 | 4.5% | **100.0%** | +$4,669.51 |

> **Key Insight:** Friday closes are the single biggest profit driver (+$6,531). Stop losses are the single biggest profit destroyer (−$8,303). The TP runner exit, while rare (32 trades), generates $146 average profit per trade — the highest-quality exit of all three types. SL management is the most critical area for improvement.

---

## 2. Performance Analysis

### 2.1 Grade Performance

> **Note:** All 716 logged trades are Grade **A+** (ConfluenceScore 120–125). The minimum score threshold of 30 is too low — every executed trade passes easily. The scoring system currently provides **zero discrimination** between setups. Consider raising `MinScore` to 60–80 to force meaningful selectivity.

---

### 2.2 Session Performance

| Session | Trades | Win Rate | Net P&L | Profit Factor | Avg RR |
|---------|--------|----------|---------|---------------|--------|
| NONE (off-session) | 629 | 52.1% | +$2,788.66 | 1.27 | 0.933 |
| NEW YORK | 60 | 50.0% | +$203.16 | 1.34 | 0.821 |
| **LONDON** | **27** | **44.4%** | **−$94.90** | **0.66** | **−1.081** |

> **Finding:** London is the **only losing session** (PF = 0.66). Consider disabling London killzone (`Trade London killzone = false`) or applying stricter filters during London hours.

---

### 2.3 Market Condition Performance

| Condition | Trades | Win Rate | Net P&L | Profit Factor | Avg RR |
|-----------|--------|----------|---------|---------------|--------|
| RANGING | 169 | **55.0%** | +$1,232.17 | **1.517** | **1.516** |
| TRENDING | 481 | 51.4% | +$1,652.81 | 1.224 | 0.704 |
| CHOPPY | 66 | 45.5% | +$11.94 | 1.009 | 0.189 |

#### Direction × Market Condition Cross-Analysis

| Market | LONG | SHORT |
|--------|------|-------|
| TRENDING | 59.0% WR / +$2,694 ✅ | 41.3% WR / −$1,041 ❌ |
| RANGING | 53.8% WR / +$705 ✅ | 56.4% WR / +$527 ✅ |
| CHOPPY | 39.5% WR / −$98 ❌ | 53.6% WR / +$110 ✅ |

> **Most Important Finding:** SHORT trades in TRENDING markets are highly destructive (−$1,041 net, 41.3% WR). LONG in TREND is the core edge (+$2,694, 59.0% WR). A filter blocking SHORT trades when MarketCondition = TRENDING and ADX > 25 would significantly improve performance.

---

### 2.4 Bias Performance

#### By Weekly Bias

| Weekly Bias | Trades | Win Rate | Net P&L | Profit Factor | Avg RR |
|-------------|--------|----------|---------|---------------|--------|
| BULLISH | 317 | **56.8%** | +$2,846.69 | **1.60** | 1.651 |
| NEUTRAL | 133 | 49.6% | +$212.48 | 1.13 | 0.524 |
| BEARISH | 266 | 46.6% | −$162.25 | 0.96 | 0.052 |

#### By Daily Bias

| Daily Bias | Trades | Win Rate | Net P&L | Profit Factor | Avg RR |
|------------|--------|----------|---------|---------------|--------|
| **BULLISH** | 301 | **61.1%** | **+$3,124.29** | **1.82** | 2.105 |
| NEUTRAL | 178 | 44.9% | +$249.95 | 1.08 | −0.004 |
| BEARISH | 237 | 44.7% | −$477.32 | 0.89 | −0.109 |

#### By H4 Bias

| H4 Bias | Trades | Win Rate | Net P&L | Profit Factor |
|---------|--------|----------|---------|---------------|
| NEUTRAL | 387 | 55.8% | +$2,790.38 | 1.53 |
| BEARISH | 162 | 48.8% | +$518.76 | 1.22 |
| BULLISH | 167 | 44.9% | −$412.22 | 0.88 |

#### By H1 Bias

| H1 Bias | Trades | Win Rate | Net P&L | Profit Factor | Avg RR |
|---------|--------|----------|---------|---------------|--------|
| BULLISH | 198 | 54.0% | +$2,012.18 | 1.74 | 1.517 |
| NEUTRAL | 339 | 52.5% | +$1,075.02 | 1.19 | 1.137 |
| BEARISH | 179 | 47.5% | −$190.28 | 0.93 | −0.439 |

#### Bias Alignment vs Counter-Trend

| Timeframe | Aligned With Trade | Win Rate | Net P&L | Counter Trade | Win Rate | Net P&L |
|-----------|-------------------|----------|---------|---------------|----------|---------|
| Weekly | 583 trades | 52.1% | +$2,684 | 133 trades | 49.6% | +$212 |
| Daily | 422 trades | **53.6%** | +$1,824 | 294 trades | 49.0% | +$1,073 |
| H4 | 195 trades | **45.6%** | **−$205** ❌ | 521 trades | **53.9%** | **+$3,102** ✅ |
| H1 | 247 trades | 49.4% | +$1,275 | 469 trades | 52.9% | +$1,622 |

> **Surprising Finding:** Trading AGAINST the H4 bias outperforms trading WITH it (53.9% WR / +$3,102 vs 45.6% WR / −$205). This is expected ICT behavior — H4 creates the draw on liquidity, M15 provides the counter-H4 entry. The EA is correctly exploiting this ICT concept.

#### Weekly + Daily Combined

| Alignment | Trades | Win Rate | Net P&L |
|-----------|--------|----------|---------|
| Weekly AND Daily both aligned | 322 | **54.3%** | +$1,622 |
| Either not aligned | 394 | 49.5% | +$1,275 |

---

### 2.5 Direction Performance

| Direction | Trades | Win Rate | Net P&L | Profit Factor | Avg RR |
|-----------|--------|----------|---------|---------------|--------|
| **LONG** | 402 | **56.0%** | **+$3,301.24** | **1.58** | 1.600 |
| SHORT | 314 | 46.2% | −$404.32 | 0.92 | −0.115 |

> SHORT trades as a whole are **unprofitable** over 10 years on XAUUSD. This reflects the structural gold bull market since 2019. SHORT trades should require additional confirmation filters.

---

### 2.6 Day-of-Week Performance

| Day | Trades | Win Rate | Net P&L | Profit Factor |
|-----|--------|----------|---------|---------------|
| Tuesday | 57 | **61.4%** | +$334.52 | **1.64** |
| Friday | 19 | 57.9% | +$30.92 | 1.51 |
| Monday | 554 | 51.4% | +$2,559.32 | 1.26 |
| Thursday | 43 | 48.8% | +$154.12 | 1.54 |
| Wednesday | 43 | 41.9% | −$181.96 | 0.62 |

> Monday dominates the trade count (554 trades) because the EA primarily detects Monday open setups. Tuesday has the highest win rate (61.4%) despite small sample size. Wednesday is the weakest day (41.9% WR, −$181).

---

## 3. Feature Analysis

### 3.1 ICT Structure Features

#### MSS (Market Structure Shift)

| MSS | Trades | Win Rate | Net P&L | Profit Factor |
|-----|--------|----------|---------|---------------|
| Present | 125 | 52.8% | +$784.32 | **1.697** |
| Absent | 591 | 51.4% | +$2,112.60 | 1.213 |

> MSS Present trades have a meaningfully higher PF (1.697). Worth requiring — consider setting `MSS Mandatory = true`.

---

#### FVG (Fair Value Gap)

| FVG | Trades | Win Rate | Net P&L | Profit Factor |
|-----|--------|----------|---------|---------------|
| Present | 433 | 52.4% | +$1,705.11 | 1.238 |
| Absent | 283 | 50.5% | +$1,191.81 | 1.308 |

> FVG Present and Absent are nearly identical. The FVG filter has marginal discriminating power at current settings.

---

#### Order Block (OB)

| OB | Trades | Win Rate | Net P&L | Profit Factor |
|----|--------|----------|---------|---------------|
| Present | 146 | 49.3% | +$204.89 | 1.138 |
| **Absent** | **570** | **52.3%** | **+$2,692.03** | **1.282** |

> **OB Present underperforms OB Absent.** The Order Block requirement is selecting noisier setups rather than better ones. Consider relaxing or removing this filter.

---

#### Liquidity Sweep (Any Type)

| Sweep | Trades | Win Rate | Net P&L | Profit Factor |
|-------|--------|----------|---------|---------------|
| Any Sweep Present | 212 | 50.0% | +$171.94 | 1.067 |
| **No Sweep** | **504** | **52.4%** | **+$2,724.98** | **1.321** |

> Sweep-present trades underperform no-sweep trades. Similar to OB, the Liquidity Sweep requirement as a mandatory condition is not adding edge.

---

### 3.2 Premium / Discount Zone

| Zone | Trades | Win Rate | Net P&L | Profit Factor |
|------|--------|----------|---------|---------------|
| **PREMIUM** | 373 | **58.7%** | **+$3,048.08** | **1.636** |
| DISCOUNT | 343 | 44.0% | −$151.16 | 0.976 |

> **Most powerful single binary feature in the entire dataset.** Premium zone LONG trades have 58.7% WR and account for virtually all net profit. Discount zone is break-even (PF = 0.976). The EA must strongly prefer PREMIUM for LONG entries and DISCOUNT for SHORT entries.

---

### 3.3 ADR Filter

| ADR Status | Trades | Win Rate | Net P&L |
|------------|--------|----------|---------|
| OK | 604 | 51.5% | +$2,435.13 |
| BLOCKED | 112 | 52.7% | +$461.79 |

> ADR-blocked trades still perform well (52.7% WR). The current ADR threshold (0.8 ADR% block) is not adding value. Either tighten the threshold (e.g., block at ADR% > 0.6) or remove the filter entirely.

---

### 3.4 News Filter

All 708 executed trades had `News_Blocked = NO`. The news filter **never activated** across 10 years of backtesting — no news times were configured in the input settings. This feature had zero impact. To use this filter, news times must be manually entered.

---

## 4. Trade Quality Analysis

### 4.1 MFE / MAE Statistics

| Metric | All Trades | WIN | LOSS |
|--------|-----------|-----|------|
| Avg MFE | 24.9 pips | **37.7 pips** | 11.1 pips |
| Median MFE | 16.5 pips | — | — |
| Avg MAE | 16.5 pips | 9.0 pips | **24.6 pips** |
| Median MAE | 13.0 pips | — | — |
| MFE / MAE Ratio | 1.504 | — | — |
| Avg Planned RR | 3.000 | — | — |
| Avg Achieved RR | 0.848 | +8.418 | −7.247 |
| Median Achieved RR | 0.446 | — | — |

> Winners move 37.7p in your favor and barely 9p against. Losers move only 11.1p in your favor before reversing 24.6p. The MFE on winners suggests TP targets could be pushed higher — many winners likely ran well past the TP before being Friday-closed.

---

### 4.2 Exit Reason Performance

| Exit Reason | Count | % | Win Rate | Avg Duration | Net P&L |
|-------------|-------|---|----------|--------------|---------|
| TakeProfit | 32 | 4.5% | **100.0%** | 65.3 hours | +$4,669.51 |
| ExpertAdvisor | 419 | 58.5% | **66.3%** | 91.1 hours | +$6,531.05 |
| StopLoss | 265 | 37.0% | 22.6% | 49.1 hours | −$8,303.64 |

---

### 4.3 Year-by-Year Performance

| Year | Trades | Win Rate | Net P&L | Profit Factor | Comment |
|------|--------|----------|---------|---------------|---------|
| 2016 | 79 | 40.5% | **−$352.72** | 0.66 | Bearish gold, worst year |
| 2017 | 67 | 53.7% | +$142.88 | 1.26 | Recovery |
| 2018 | 68 | 52.9% | +$36.31 | 1.06 | Break-even |
| 2019 | 70 | 44.3% | **−$161.08** | 0.77 | Choppy, second worst |
| 2020 | 82 | 52.4% | +$118.34 | 1.11 | COVID breakout year |
| 2021 | 64 | 53.1% | +$54.41 | 1.06 | Consolidation |
| 2022 | 65 | 56.9% | +$423.11 | 1.44 | Strong year |
| 2023 | 66 | **60.6%** | +$714.63 | **1.67** | **Best year** |
| 2024 | 70 | 55.7% | +$601.20 | 1.36 | Gold bull market |
| 2025 | 85 | 49.4% | +$1,319.84 | 1.52 | Highest profit despite volatility |

> The EA shows **clear improvement over time**, particularly from 2022 onward. The 2016 and 2019 losses correspond to bearish/choppy gold markets. 2025 generated the highest absolute profit despite 204 high-volatility setups being rejected due to MaxSLSize = 80 limit.

---

### 4.4 ATR Volatility Analysis

| ATR Quintile | Avg ATR14 | Trades | Win Rate | Net P&L |
|--------------|-----------|--------|----------|---------|
| Q1 (Low vol) | 0.80 pips | 144 | 52.8% | +$454.45 |
| Q2 (Mod-low) | 1.26 pips | 144 | **59.0%** | +$332.80 |
| Q3 (Medium) | 1.72 pips | 144 | 49.3% | +$556.92 |
| Q4 (Mod-high) | 2.49 pips | 141 | 47.5% | +$385.01 |
| Q5 (High vol) | 5.23 pips | 143 | 49.7% | **+$1,167.74** |

> Q2 (moderate volatility) wins most often (59% WR). Q5 high-volatility wins less often but generates the most absolute profit ($1,168) due to larger move sizes. Consider allowing wider SL in high-volatility environments to capture more Q4–Q5 setups.

---

## 5. Setup Analysis

### 5.1 Top 10 Best Performing SetupIDs

| SetupID | Net P&L | RR Achieved |
|---------|---------|-------------|
| ATLAS_20251222_010000_0923 | +$366.63 | 30.19R |
| ATLAS_20250120_010000_0643 | +$317.59 | 30.01R |
| ATLAS_20251110_010000_0915 | +$317.16 | 30.01R |
| ATLAS_20250210_010000_0650 | +$268.74 | 30.00R |
| ATLAS_20241111_010000_0628 | +$224.46 | 30.02R |
| ATLAS_20240701_010000_0602 | +$215.52 | 30.02R |
| ATLAS_20231218_010000_0566 | +$213.60 | 30.11R |
| ATLAS_20230925_010000_0549 | +$210.85 | 30.01R |
| ATLAS_20250929_010000_0787 | +$205.30 | 30.02R |
| ATLAS_20251013_010000_0789 | +$200.88 | 30.00R |

> All top performers share: **Monday entry, LONG direction, 2023–2025, RR ≈ 30** (TP3 runner hit). These are gold bull market continuation moves — the highest-reward setups in the dataset.

---

### 5.2 Top 10 Worst Performing SetupIDs

| SetupID | Net P&L | RR Achieved |
|---------|---------|-------------|
| ATLAS_20251124_010000_0917 | −$125.70 | −10.00R |
| ATLAS_20251229_014500_0924 | −$116.56 | −10.00R |
| ATLAS_20250407_010000_0663 | −$113.88 | −10.00R |
| ATLAS_20241230_010000_0637 | −$109.24 | −10.00R |
| ATLAS_20250422_010000_0747 | −$106.36 | −10.02R |
| ATLAS_20250127_010000_0644 | −$106.00 | −10.04R |
| ATLAS_20250106_010000_0639 | −$105.84 | −10.00R |
| ATLAS_20241125_010000_0631 | −$102.45 | −10.01R |
| ATLAS_20250203_010000_0648 | −$94.92 | −10.02R |
| ATLAS_20240722_010000_0605 | −$90.95 | −10.00R |

> All worst performers share: **StopLoss exit, RR ≈ −10, large absolute loss**. These are full-risk SL hits where price moved immediately against the position. Most are in 2024–2025 high-volatility periods.

---

### 5.3 Confluence Score Analysis

| Score Band | Trades | Win Rate | Net P&L |
|------------|--------|----------|---------|
| 100+ | 716 | 51.7% | +$2,896.92 |

> **All 716 trades fall in the 100+ band** — ConfluenceScore has zero variance (all signals score 120–125 with current settings). This means the confluence scoring system is providing no discrimination. This is the most critical data quality issue for ML training. Individual component scores must be logged separately in Phase 2.

---

## 6. Machine Learning Preparation

### 6.1 Model Performance (5-Fold Cross-Validation)

| Model | AUC Score | Std Dev | Interpretation |
|-------|-----------|---------|----------------|
| Random Forest | **0.5682** | ±0.037 | Moderate predictive signal |
| LightGBM | 0.5441 | ±0.038 | Moderate predictive signal |
| XGBoost | 0.5382 | ±0.016 | Moderate predictive signal |

> AUC of 0.54–0.57 (vs 0.50 = random) is **normal for financial markets** with 716 samples. All three models detect real but weak patterns. With more data (5,000+ trades from live collection) and richer features (individual component scores, price action quality, volume), AUC should improve toward 0.65+.

---

### 6.2 Feature Importance Rankings

#### Random Forest Importance

| Rank | Feature | Importance | Tier |
|------|---------|-----------|------|
| 1 | ATR14_Pips_Entry | 0.1674 | ⭐⭐⭐ HIGH |
| 2 | ADX_Entry | 0.1524 | ⭐⭐⭐ HIGH |
| 3 | ATR50_Pips_Entry | 0.1299 | ⭐⭐⭐ HIGH |
| 4 | Spread_Pips_Entry | 0.1266 | ⭐⭐⭐ HIGH |
| 5 | PremDisc_Status | 0.0803 | ⭐⭐⭐ HIGH |
| 6 | DailyBias | 0.0595 | ⭐⭐ MED |
| 7 | H4Bias | 0.0537 | ⭐⭐ MED |
| 8 | WeeklyBias | 0.0332 | ⭐⭐ MED |
| 9 | H1Bias | 0.0329 | ⭐⭐ MED |
| 10 | Direction | 0.0297 | ⭐⭐ MED |
| 11 | MarketCondition | 0.0285 | ⭐⭐ MED |
| 12 | FVG_Present | 0.0117 | ⭐ LOW |
| 13 | Displacement | 0.0117 | ⭐ LOW |
| 14 | ADR_Status | 0.0100 | ⭐ LOW |
| 15 | OB_Present | 0.0098 | ⭐ LOW |
| 16+ | MSS, Sweeps, Session, ConfluenceScore | < 0.01 | ⭐ LOW |

---

#### XGBoost Importance

| Rank | Feature | Importance | Tier |
|------|---------|-----------|------|
| 1 | ConfluenceScore | 0.0614 | ⭐⭐⭐ HIGH |
| 2 | PremDisc_Status | 0.0591 | ⭐⭐⭐ HIGH |
| 3 | PWL_Sweep | 0.0462 | ⭐⭐ MED |
| 4 | ADR_Status | 0.0455 | ⭐⭐ MED |
| 5 | PWH_Sweep | 0.0449 | ⭐⭐ MED |
| 6 | Displacement | 0.0446 | ⭐⭐ MED |
| 7 | ATR14_Pips_Entry | 0.0419 | ⭐⭐ MED |
| 8 | Direction | 0.0414 | ⭐⭐ MED |
| 9 | EQH_Sweep | 0.0413 | ⭐⭐ MED |
| 10 | DailyBias | 0.0411 | ⭐⭐ MED |

---

#### LightGBM Importance

| Rank | Feature | Importance | Tier |
|------|---------|-----------|------|
| 1 | ATR14_Pips_Entry | 625 | ⭐⭐⭐ HIGH |
| 2 | ADX_Entry | 617 | ⭐⭐⭐ HIGH |
| 3 | ATR50_Pips_Entry | 562 | ⭐⭐⭐ HIGH |
| 4 | Spread_Pips_Entry | 371 | ⭐⭐⭐ HIGH |
| 5 | H1Bias | 104 | ⭐⭐ MED |
| 6 | H4Bias | 89 | ⭐⭐ MED |
| 7 | DailyBias | 71 | ⭐⭐ MED |
| 8 | WeeklyBias | 61 | ⭐⭐ MED |
| 9 | PremDisc_Status | 48 | ⭐⭐ MED |
| 10 | Direction | 42 | ⭐⭐ MED |

---

### 6.3 Consensus Feature Ranking (Average Rank Across All 3 Models)

| Rank | Feature | Avg Rank | Tier | Action |
|------|---------|----------|------|--------|
| #1 | **ATR14_Pips_Entry** | 3.0 | ⭐⭐⭐ HIGH | Encode as VolatilityRegime label |
| #2 | **PremDisc_Status** | 5.3 | ⭐⭐⭐ HIGH | Critical filter — require alignment |
| #3 | **ATR50_Pips_Entry** | 5.7 | ⭐⭐⭐ HIGH | Longer-term vol context |
| #4 | **ADX_Entry** | 6.3 | ⭐⭐⭐ HIGH | Trend strength predictor |
| #5 | **Spread_Pips_Entry** | 7.0 | ⭐⭐⭐ HIGH | Trade cost environment |
| #6 | **DailyBias** | 7.7 | ⭐⭐ MED | Most important directional filter |
| #7 | **H4Bias** | 8.3 | ⭐⭐ MED | Counter-H4 trades outperform |
| #8 | **Direction** | 9.3 | ⭐⭐ MED | LONG structurally preferred |
| #9 | **WeeklyBias** | 10.0 | ⭐⭐ MED | Supports directional edge |
| #10 | ADR_Status | 10.3 | ⭐ LOW | Marginal value |
| #11 | H1Bias | 12.3 | ⭐ LOW | Some value |
| #12 | PWL_Sweep | 12.3 | ⭐ LOW | Weak |
| #13 | Displacement | 13.3 | ⭐ LOW | Weak |
| #14 | ConfluenceScore | 14.0 | ⭐ LOW | Zero variance in current data |
| #15 | EQH_Sweep | 15.3 | ⭐ LOW | Weak |
| #16 | FVG_Present | 16.3 | ⭐ LOW | Weak |
| #17 | MarketCondition | 16.3 | ⭐ LOW | Weak individually |
| #18 | PDH_Sweep | 17.0 | ⭐ LOW | Weak |
| #19 | MSS | 17.7 | ⭐ LOW | Weak individually |
| #20 | PWH_Sweep | 17.7 | ⭐ LOW | Weak |
| #21 | EQL_Sweep | 18.0 | ⭐ LOW | Weak |
| #22 | Asian_Sweep | 18.7 | ⭐ LOW | Weak |
| #23 | Session | 20.0 | ⭐ LOW | Weak |
| #24 | OB_Present | 21.0 | ⭐ LOW | Weak — consider removing |
| #25 | PDL_Sweep | 22.0 | ⭐ LOW | Weak |
| #26 | PlannedRR | 26.0 | ⭐ LOW | Zero variance (always 3.0) |

---

## 7. Findings & Recommendations

### 7.1 Conditions That Produce Highest Expectancy

| Condition | Win Rate | Net P&L | Priority |
|-----------|----------|---------|----------|
| Daily Bias = BULLISH + Direction = LONG + Zone = PREMIUM | ~61%+ | Highest | 🔴 Critical |
| MarketCondition = RANGING | 55.0% | +$1,232 | 🟠 High |
| ExpertAdvisor exit (hold over weekend) | 66.3% | +$6,531 | 🟠 High |
| Weekly Bias = BULLISH | 56.8% | +$2,847 | 🟡 Medium |
| Tuesday entries | 61.4% | +$335 | 🟡 Medium |
| ATR Q2 (moderate volatility) | 59.0% | +$333 | 🟡 Medium |

---

### 7.2 Filters to STRENGTHEN

| Filter | Current State | Recommendation | Expected Impact |
|--------|--------------|----------------|-----------------|
| **PremDisc_Status** | Not required | **Require PREMIUM for LONG, DISCOUNT for SHORT** | +8–10% edge improvement |
| **Daily Bias** | Not required | Require aligned Daily Bias | +6% WR improvement |
| **MSS = YES** | Optional | Set `MSS Mandatory = true` | PF: 1.213 → 1.697 |
| **SHORT in TREND** | Allowed | Block SHORT when ADX > 25 + TRENDING | Save −$1,041 |
| **MinConfluenceScore** | 30 | Raise to 60–80 | Better selectivity |
| **Weekly Bias** | Not required | Weight toward BULLISH weekly for LONG | Improve WIN% |

---

### 7.3 Filters to RELAX or REMOVE

| Filter | Current State | Recommendation | Reason |
|--------|--------------|----------------|--------|
| **Order Block (OB_Present)** | Required | Remove as requirement | OB trades underperform (PF 1.138 < no-OB PF 1.282) |
| **Liquidity Sweep** | Optional | Remove as requirement | Sweep trades underperform (PF 1.067 < no-sweep PF 1.321) |
| **MaxSLSize = 80 pips** | Hard limit | Raise to 200 or 0 (unlimited) | Caused 204 rejections in 2025 high-volatility periods |
| **London Session** | Enabled | **Disable** (`Trade London killzone = false`) | Only losing session (PF 0.66, −$95) |
| **ADR Filter** | Active (0.8) | Tighten to 0.6 or remove | BLOCKED trades still win 52.7% — filter adds no value |
| **News Filter** | Configured | Set news times or remove | Never activated in 10-year backtest |

---

### 7.4 Market Environments — Summary

| Environment | Action | Reason |
|-------------|--------|--------|
| RANGING | ✅ Trade both directions | Best PF (1.52), best RR (1.516) |
| TRENDING + LONG | ✅ Trade aggressively | 59% WR, +$2,694 net |
| TRENDING + SHORT | ❌ Block or require extra confirmation | 41.3% WR, −$1,041 net |
| CHOPPY + SHORT | ⚠️ Allow with caution | 53.6% WR, only +$110 |
| CHOPPY + LONG | ❌ Block | 39.5% WR, −$98 net |

---

### 7.5 Setups Most Suitable for AI-Assisted Selection

For Phase 2 ML model training, encode these features explicitly:

```
1. VolatilityRegime  → Bin ATR14 into LOW / MED / HIGH / EXTREME
2. PremDisc_Status   → Encode as PREMIUM=+1 / NEUTRAL=0 / DISCOUNT=-1
3. BiasScore         → Weekly + Daily + H1 alignment: 0 to 3 scale
4. H4_CounterFlag    → 1 if direction OPPOSES H4 (positive edge)
5. TrendDirection    → LONG=1 / SHORT=-1 (gold is structurally bullish)
6. ADX_Band          → Binned: CHOPPY(<18) / WEAK(18-25) / TREND(25-40) / STRONG(40+)
7. SpreadPctATR      → Trade cost relative to volatility
8. MSS_Quality       → 0/1 (MSS confirmed = higher PF)
9. ZoneAlignment     → PREMIUM_LONG or DISCOUNT_SHORT = 1, else = 0
10. SessionQuality   → NONE=2 / NEWYORK=1 / LONDON=0
```

---

### 7.6 Phase 1b Recommendation (Optional Re-Run)

Before Phase 2 live collection begins, consider one additional backtest with:

| Input Change | From | To | Reason |
|-------------|------|----|--------|
| MaxSLSize | 80 | 0 (unlimited) | Capture 204 missed 2025 high-vol setups |
| Trade London killzone | true | **false** | Eliminate losing session |
| MinScore | 30 | **60** | Improve setup quality discrimination |
| MSS Mandatory | false | **true** | Exploit MSS edge (PF 1.697) |

This would expand the dataset by approximately 200+ trades and eliminate the highest-noise signals.

---

### 7.7 Data Quality Issues for Phase 2

| Issue | Impact | Fix |
|-------|--------|-----|
| ConfluenceScore has zero variance (all = 120–125) | ConfluenceScore is useless for ML | Log individual component scores separately |
| PlannedRR always = 3.0 | Zero ML value | Log actual TP1/TP2/TP3 distances in pips |
| No partial close tracking in Trade CSV | Cannot analyze TP1/TP2 hit rates | Add TP1_Hit, TP2_Hit columns to Trade History |
| 204 rejected 2025 signals not in outcome data | Model cannot learn from high-vol conditions | Re-run with MaxSLSize = 0 |
| ExitReason has only 3 values (SL/TP/EA) | Cannot distinguish Friday close vs BE vs TP1/TP2 | Add sub-reason: FridayClose, BreakevenClose, PartialTP |

---

*Report generated from: `ICT_ATLAS_All_Signals_XAUUSD.csv` (925 rows) and `ICT_ATLAS_Trade_History_XAUUSD.csv` (716 rows)*  
*Analysis tools: Python 3, pandas, scikit-learn, XGBoost, LightGBM*
