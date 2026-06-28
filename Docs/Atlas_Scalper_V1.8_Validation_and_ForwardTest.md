# ICT Atlas Scalper Pro V1.8 — Validation Record & Forward-Test Guide

## What was validated

The strategy was tested **gold-only (XAUUSD, M15)** across five independent
4-month windows spanning ~2.5 years, first without and then with an
**ADX trend-strength regime filter** (Wilder ADX(14) on H4, threshold 22 —
a textbook trending threshold, deliberately NOT tuned to the test data).

Tester settings: Every tick, "profit in pips" OFF, $1,000 / 1:100,
Zero-latency ideal execution (no spread/commission modeled).

| Window | No filter | + ADX filter |
|---|---|---|
| Jan–Apr 2025 | +$671 / PF 1.87 | **+$1,114 / PF 3.41** |
| Mar–Jun 2026 | +$551 / PF 1.87 | **+$659 / PF 2.24** |
| Jul–Oct 2024 | +$254 / PF 1.45 | **+$342 / PF 1.74** |
| Jan–Apr 2024 | +$39  / PF 1.05 | **+$162 / PF 1.36** |
| Nov '25–Feb '26 (chop) | −$209 / PF 0.75 | **−$41 / PF 0.94** |
| **Aggregate** | **+$1,306** | **+$2,236 (+71%)** |

### Conclusion
- The core edge is **real but regime-dependent**: profitable when gold
  trends, weak/losing when gold ranges.
- The ADX filter **improved all five windows** (more profit, higher PF,
  lower drawdown) and cut the worst-case loss by ~80%. Uniform improvement
  from an untuned, principled rule is strong evidence it is a genuine
  enhancement, not curve-fitting.
- The filter does NOT make the chop window profitable (still −$41 / PF 0.94)
  — it makes the worst regime survivable rather than damaging.

## Official validated config

- **Symbol:** XAUUSD, M15
- **Extras:** OFF (silver/cable lost money; EURUSD was only marginal)
- **Regime filter:** ON — `UseRegimeFilter=true`, `RegimeTF=H4`,
  `RegimeADXPeriod=14`, `RegimeMinADX=22`
- Preset: `Presets/ICT_Atlas_Scalper_Pro_V1.8_SmartActivePlus_24x5.set`

### Do NOT
- Do not tune `RegimeMinADX` to force the chop window positive — that is
  where robust becomes over-fit. Its value is that it works untuned at 22.
- Do not re-enable silver/cable extras; both lost money in testing.

## Forward-test (the only remaining gate before real money)

Backtests use ideal execution and known history. The one test that cannot
be curve-fit is forward time with real costs. Run this BEFORE funding live:

1. Open a **demo account** with the broker you intend to trade live.
2. Pre-download XAUUSD history; attach the EA to an **XAUUSD M15** chart.
3. Load the validated preset above (gold-only, regime filter ON).
4. Enable **Algo Trading** and let it run **4–8 weeks** untouched.
5. Track: net profit, profit factor, max drawdown, and whether live
   behavior matches the backtest cadence (~0.4–0.5 trades/day on gold).

### Pass / fail
- **Profitable and PF ≥ ~1.3 after 4–8 weeks of real-time demo** → the edge
  survives real spread/slippage; consider a small live allocation.
- **Negative or erratic** → the backtest edge did not survive real costs;
  do not fund it.

Real spread/commission will shave every backtest number — the strong
windows (PF 1.7–3.4) have cushion; the thin spots will not. Size risk
accordingly and never risk more than you can lose.
