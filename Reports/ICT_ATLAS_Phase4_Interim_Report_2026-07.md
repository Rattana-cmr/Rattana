# ICT ATLAS EA — Phase 4 Interim Report (July 2026)

**Report date:** 2026-07-20
**Programme running since:** 2026-06-19 (31 days)
**Data analysed:** InstaForex demo 94688339 — `ICT_ATLAS_All_Signals_XAUUSD_94688339.csv`
**Data window:** 2026-07-14 10:00 → 2026-07-20 06:00 (4.5 trading days; account was recreated mid-programme, so this file covers the current account only)

---

## Deployment Status

| Item | Status |
|---|---|
| EA build | V1.1 shadow mode (`UseMLShadow=true`, `UseMLFilter=false`) |
| ONNX validation | PASSED — maxDiff = 0.000000 vs Python (200 cases) |
| CSV logging | Working, per-account filenames (`_94688339`) |
| Preset | Phase 1D-B LONG ONLY — confirmed enforced (all 240 SHORT signals blocked) |
| Terminals | InstaForex only (Capital.com reassigned to a separate strategy) |

## Signal Summary (4.5 trading days)

| Metric | Value |
|---|---|
| Bars evaluated (setups logged) | 240 |
| Rows logged (LONG + SHORT per bar) | 480 |
| SHORT signals blocked by LONG-only rule | 240 (100% — correct) |
| LONG signals ML-scored | 65 |
| Trades executed | 1 (2026-07-20 06:00, LONG, score 125, A+, ML 0.654 — still open) |
| Rejections — no setup | 175 |
| Rejections — SL too small (<8p) | 15 |
| Rejections — other (killzone/etc.) | 49 |

Signal generation rate: ~65 ML-scored LONG signals per week is far above the ~1/week trade rate — the scored-signal dataset will hit the 50-signal shadow-review threshold almost immediately. **Shadow gate review can be pulled forward from Nov–Dec 2026 to late August 2026** once 3–4 weeks of scores from a stable account have accumulated.

## ML Shadow Score Distribution (65 scored LONG signals)

| Statistic | Value |
|---|---|
| Mean | 0.551 |
| Median | 0.582 |
| Std dev | 0.177 |
| Min / Max | 0.166 / 0.847 |
| Above 0.52 gate (would-pass) | 40 / 65 (62%) |

Distribution by decile: 0.1×1, 0.2×8, 0.3×5, 0.4×9, 0.5×15, 0.6×13, 0.7×9, 0.8×5

**Assessment:** healthy. Scores span the full range and respond to market context (not stuck at a constant), the centre of mass sits just above the 0.52 threshold, and the executed A+ trade scored 0.654 — comfortably above the gate. If the filter had been live this week, it would have kept ~62% of valid signals, in line with the design target of 50–55%+ retention.

## Trade History

No closed trades yet on this account — the trade log populates at position close. The single open position (BUY 0.01 @ 4021.47, SL 3949.04, TP 4239.32) was correctly snapshotted in the signals log with its ML score.

## Issues Found & Fixed During This Period

| Issue | Fix | Commit |
|---|---|---|
| Two terminals shared one CSV via FILE_COMMON → file-lock conflict | Filenames namespaced by account login | `26d33bc` |
| Debug prints flooded log every tick | Throttled to once per bar per direction | `3435bb8` |
| Rejected orders retried every tick (no backoff) | 30s cooldown after broker rejection | `d9c876b` |
| Header row never written to live CSVs (`FILE_READ\|FILE_WRITE` auto-creates file, bypassing the new-file branch) | Detect empty file via `FileTell()==0` and write header | this commit |

All fixes are logging/robustness only — **no strategy logic changed**. Phase 1D-B parameters remain frozen.

## Next Steps

1. **Now:** deploy the header fix at the next convenient EA restart (not urgent — data is unaffected, only the header row is missing).
2. **Late August 2026:** shadow gate review — score distribution stability, would-pass rate, maxDiff spot-check (~50+ scored signals expected by then).
3. **June–July 2027:** first annual ML retrain — export full trade history, rerun `python ML/run_pipeline.py`, compare AUC to Phase 3 baseline (0.518), fill in the Phase 4 milestone table.

*No `UseMLFilter` activation is authorised until the production-readiness criteria in `ICT_ATLAS_Phase4_DataCollection_Plan.md` are met.*
