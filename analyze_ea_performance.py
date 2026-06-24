"""
ICT SMC EA Performance Analyzer
================================
Processes trade history and signal log CSVs produced by the ML framework
(ICT_SMC_Trade_History_<Symbol>.csv and ICT_SMC_All_Signals_<Symbol>.csv)
and generates the full ForceTrade ON vs OFF comparison report.

Usage (two-file comparison):
    python analyze_ea_performance.py --off <force_off_history.csv> --on <force_on_history.csv>

Usage (single file):
    python analyze_ea_performance.py --single <history.csv>

Optional: include signal log for filter-rejection analysis:
    python analyze_ea_performance.py --off V16_OFF_TradeHistory.csv
                                     --on  V16_ON_TradeHistory.csv
                                     --sig-off V16_OFF_Signals.csv
                                     --sig-on  V16_ON_Signals.csv
"""

import csv
import sys
import os
import argparse
from datetime import datetime
from collections import defaultdict

# ---------------------------------------------------------------------------
# CSV column definitions (must match EA's WriteTradeHistoryLog header)
# OpenTime, CloseTime, Symbol, Direction, Entry, SL, TP,
# Risk_Pct, LotSize, MSS, BOS, LiqSweep, OTE_Pct, Session, Hour,
# DayOfWeek, Score, AI_Confidence, Result, Profit_USD, Profit_R,
# MFE_Pips, MAE_Pips, MFE_R, MAE_R
# ---------------------------------------------------------------------------

TIME_FMT = "%Y.%m.%d %H:%M"   # MT5 default: "2024.01.15 09:30"
TIME_FMT2 = "%Y-%m-%d %H:%M"  # alternate fallback


def parse_time(s):
    for fmt in (TIME_FMT, TIME_FMT2, "%Y.%m.%d %H:%M:%S"):
        try:
            return datetime.strptime(s.strip(), fmt)
        except ValueError:
            pass
    return None


def load_trade_history(filepath):
    """Return list of trade dicts from a TradeHistory CSV."""
    if not os.path.isfile(filepath):
        print(f"  [ERROR] File not found: {filepath}")
        return []
    trades = []
    with open(filepath, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            t = {}
            t["open_time"]  = parse_time(row.get("OpenTime", ""))
            t["close_time"] = parse_time(row.get("CloseTime", ""))
            t["symbol"]     = row.get("Symbol", "").strip()
            t["direction"]  = row.get("Direction", "").strip()
            t["entry"]      = _f(row, "Entry")
            t["sl"]         = _f(row, "SL")
            t["tp"]         = _f(row, "TP")
            t["risk_pct"]   = _f(row, "Risk_Pct")
            t["lotsize"]    = _f(row, "LotSize")
            t["mss"]        = row.get("MSS", "0").strip()
            t["bos"]        = row.get("BOS", "0").strip()
            t["liq_sweep"]  = row.get("LiqSweep", "0").strip()
            t["ote_pct"]    = _f(row, "OTE_Pct")
            t["session"]    = row.get("Session", "").strip()
            t["hour"]       = _i(row, "Hour")
            t["dow"]        = row.get("DayOfWeek", "").strip()
            t["score"]      = _i(row, "Score")
            t["ai_conf"]    = _f(row, "AI_Confidence")
            t["result"]     = row.get("Result", "").strip()
            t["profit_usd"] = _f(row, "Profit_USD")
            t["profit_r"]   = _f(row, "Profit_R")
            t["mfe_pips"]   = _f(row, "MFE_Pips")
            t["mae_pips"]   = _f(row, "MAE_Pips")
            t["mfe_r"]      = _f(row, "MFE_R")
            t["mae_r"]      = _f(row, "MAE_R")
            # derived
            if t["open_time"] and t["close_time"]:
                t["duration_min"] = (t["close_time"] - t["open_time"]).total_seconds() / 60.0
            else:
                t["duration_min"] = None
            trades.append(t)
    return trades


def load_signal_log(filepath):
    """Return list of signal dicts from an All_Signals CSV."""
    if not filepath or not os.path.isfile(filepath):
        return []
    rows = []
    with open(filepath, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(dict(row))
    return rows


def _f(row, key, default=0.0):
    try:
        return float(row.get(key, default) or default)
    except (ValueError, TypeError):
        return default


def _i(row, key, default=0):
    try:
        return int(float(row.get(key, default) or default))
    except (ValueError, TypeError):
        return default


# ---------------------------------------------------------------------------
# Metric calculations
# ---------------------------------------------------------------------------

def calc_metrics(trades, label=""):
    """Calculate all core performance metrics from a list of trade dicts."""
    if not trades:
        return {"label": label, "total": 0}

    wins   = [t for t in trades if t["result"] == "WIN"]
    losses = [t for t in trades if t["result"] == "LOSS"]
    be     = [t for t in trades if t["result"] == "BE"]

    total       = len(trades)
    win_count   = len(wins)
    loss_count  = len(losses)
    win_rate    = win_count / total * 100 if total else 0

    gross_profit = sum(t["profit_usd"] for t in wins)
    gross_loss   = abs(sum(t["profit_usd"] for t in losses))
    net_profit   = sum(t["profit_usd"] for t in trades)
    profit_factor = gross_profit / gross_loss if gross_loss > 0 else float("inf")

    avg_win    = gross_profit / win_count  if win_count  else 0
    avg_loss   = gross_loss  / loss_count if loss_count else 0
    expectancy = (win_rate / 100 * avg_win) - ((1 - win_rate / 100) * avg_loss)

    avg_rr    = sum(t["profit_r"]  for t in trades) / total if total else 0
    avg_mfe_r = sum(t["mfe_r"]    for t in trades) / total if total else 0
    avg_mae_r = sum(t["mae_r"]    for t in trades) / total if total else 0

    durations = [t["duration_min"] for t in trades if t["duration_min"] is not None]
    avg_duration = sum(durations) / len(durations) if durations else 0

    max_dd, dd_pct = calc_drawdown(trades)
    max_cw, max_cl = consecutive_runs(trades)

    return {
        "label":          label,
        "total":          total,
        "wins":           win_count,
        "losses":         loss_count,
        "be":             len(be),
        "win_rate":       win_rate,
        "gross_profit":   gross_profit,
        "gross_loss":     gross_loss,
        "net_profit":     net_profit,
        "profit_factor":  profit_factor,
        "avg_win":        avg_win,
        "avg_loss":       avg_loss,
        "expectancy":     expectancy,
        "avg_rr":         avg_rr,
        "avg_mfe_r":      avg_mfe_r,
        "avg_mae_r":      avg_mae_r,
        "avg_duration":   avg_duration,
        "max_drawdown_usd": max_dd,
        "max_drawdown_pct": dd_pct,
        "max_consec_wins":  max_cw,
        "max_consec_losses": max_cl,
    }


def calc_drawdown(trades, initial_balance=10000.0):
    """
    Simulate equity curve from trade P&L and return
    (max_drawdown_usd, max_drawdown_pct_of_peak).
    """
    equity = initial_balance
    peak   = initial_balance
    max_dd_usd = 0.0
    max_dd_pct = 0.0

    for t in trades:
        equity += t["profit_usd"]
        if equity > peak:
            peak = equity
        dd_usd = peak - equity
        dd_pct = dd_usd / peak * 100 if peak > 0 else 0
        if dd_usd > max_dd_usd:
            max_dd_usd = dd_usd
        if dd_pct > max_dd_pct:
            max_dd_pct = dd_pct

    return max_dd_usd, max_dd_pct


def consecutive_runs(trades):
    """Return (max_consecutive_wins, max_consecutive_losses)."""
    max_cw = cur_cw = 0
    max_cl = cur_cl = 0
    for t in trades:
        if t["result"] == "WIN":
            cur_cw += 1
            cur_cl = 0
        elif t["result"] == "LOSS":
            cur_cl += 1
            cur_cw = 0
        else:  # BE resets streaks
            cur_cw = 0
            cur_cl = 0
        max_cw = max(max_cw, cur_cw)
        max_cl = max(max_cl, cur_cl)
    return max_cw, max_cl


# ---------------------------------------------------------------------------
# Breakdown analyses
# ---------------------------------------------------------------------------

def session_breakdown(trades):
    """Return metrics dict keyed by session name."""
    groups = defaultdict(list)
    for t in trades:
        groups[t["session"] or "UNKNOWN"].append(t)
    return {sess: calc_metrics(ts, sess) for sess, ts in sorted(groups.items())}


def symbol_breakdown(trades):
    """Return metrics dict keyed by symbol."""
    groups = defaultdict(list)
    for t in trades:
        groups[t["symbol"] or "UNKNOWN"].append(t)
    return {sym: calc_metrics(ts, sym) for sym, ts in sorted(groups.items())}


def direction_breakdown(trades):
    """Return metrics keyed by BUY / SELL."""
    groups = defaultdict(list)
    for t in trades:
        groups[t["direction"]].append(t)
    return {d: calc_metrics(ts, d) for d, ts in sorted(groups.items())}


def dow_breakdown(trades):
    """Return metrics keyed by day-of-week."""
    order = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    groups = defaultdict(list)
    for t in trades:
        groups[t["dow"] or "?"].append(t)
    result = {}
    for d in order:
        if d in groups:
            result[d] = calc_metrics(groups[d], d)
    for d in groups:
        if d not in result:
            result[d] = calc_metrics(groups[d], d)
    return result


def filter_breakdown(trades):
    """
    For each ICT filter (MSS, BOS, LiqSweep), compare win rates
    when the filter was active (=1) vs not active (=0).
    """
    result = {}
    for col, name in [("mss", "MSS"), ("bos", "BOS"), ("liq_sweep", "LiqSweep")]:
        on  = [t for t in trades if t[col] == "1"]
        off = [t for t in trades if t[col] == "0"]
        result[name] = {
            "filter_active":   calc_metrics(on,  f"{name}=1"),
            "filter_inactive": calc_metrics(off, f"{name}=0"),
        }
    return result


def score_breakdown(trades, bins=None):
    """Bucket trades by score and show metrics per bucket."""
    if bins is None:
        bins = [(0, 30), (30, 50), (50, 70), (70, 90), (90, 101)]
    result = {}
    for lo, hi in bins:
        label = f"Score {lo}-{hi-1}"
        bucket = [t for t in trades if lo <= t["score"] < hi]
        result[label] = calc_metrics(bucket, label)
    return result


def mfe_mae_analysis(trades):
    """
    Show how often price reached 1R, 1.5R, 2R in winners' favour (MFE)
    and how often it came within 0.5R, 0.25R of SL (MAE).
    """
    total = len(trades)
    if total == 0:
        return {}

    mfe_thresholds = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
    mae_thresholds = [0.25, 0.5, 0.75, 1.0]

    mfe_reach = {th: sum(1 for t in trades if t["mfe_r"] >= th) for th in mfe_thresholds}
    mae_reach = {th: sum(1 for t in trades if t["mae_r"] >= th) for th in mae_thresholds}

    return {
        "mfe_reach_pct": {th: v / total * 100 for th, v in mfe_reach.items()},
        "mae_reach_pct": {th: v / total * 100 for th, v in mae_reach.items()},
    }


def signal_rejection_analysis(signals):
    """Count which step most frequently caused rejection."""
    if not signals:
        return {}
    rejected = [s for s in signals if s.get("Trade_Allowed", "1") == "0"]
    total    = len(signals)
    rej_total = len(rejected)

    reasons = defaultdict(int)
    for s in rejected:
        r = s.get("Rejection_Reason", "Unknown").strip()
        reasons[r] += 1

    return {
        "total_signals":   total,
        "accepted":        total - rej_total,
        "rejected":        rej_total,
        "acceptance_rate": (total - rej_total) / total * 100 if total else 0,
        "rejection_by_step": dict(sorted(reasons.items(), key=lambda x: -x[1])),
    }


# ---------------------------------------------------------------------------
# Rendering helpers
# ---------------------------------------------------------------------------

SEP  = "=" * 72
SEP2 = "-" * 72


def _pct(v):   return f"{v:6.1f}%"
def _usd(v):   return f"${v:9.2f}"
def _r(v):     return f"{v:7.3f}R"
def _n(v):     return f"{int(v):6d}"
def _mins(v):  return f"{v:6.0f} min"


def print_core_metrics(m, indent="  "):
    if m.get("total", 0) == 0:
        print(f"{indent}No trades recorded.")
        return
    pf = m["profit_factor"]
    pf_str = f"{pf:.3f}" if pf != float("inf") else "∞"
    print(f"{indent}Total Trades         : {_n(m['total'])}")
    print(f"{indent}  Wins / Losses / BE  : {m['wins']} / {m['losses']} / {m['be']}")
    print(f"{indent}Win Rate             : {_pct(m['win_rate'])}")
    print(f"{indent}Profit Factor        : {pf_str}")
    print(f"{indent}Net Profit           : {_usd(m['net_profit'])}")
    print(f"{indent}  Gross Profit        : {_usd(m['gross_profit'])}")
    print(f"{indent}  Gross Loss          : {_usd(m['gross_loss'])}")
    print(f"{indent}Max Drawdown         : {_usd(m['max_drawdown_usd'])}  ({_pct(m['max_drawdown_pct'])})")
    print(f"{indent}Expectancy / trade   : {_usd(m['expectancy'])}")
    print(f"{indent}Average RR           : {_r(m['avg_rr'])}")
    print(f"{indent}  Avg MFE             : {_r(m['avg_mfe_r'])}   (how far it went your way)")
    print(f"{indent}  Avg MAE             : {_r(m['avg_mae_r'])}   (how close to SL it came)")
    print(f"{indent}Avg Trade Duration   : {_mins(m['avg_duration'])}")
    print(f"{indent}Max Consec Wins      : {m['max_consec_wins']}")
    print(f"{indent}Max Consec Losses    : {m['max_consec_losses']}")


def print_comparison(m_off, m_on):
    """Side-by-side comparison table for Force=OFF vs Force=ON."""
    rows = [
        ("Total Trades",     f"{m_off['total']:>8}",           f"{m_on['total']:>8}"),
        ("Win Rate",         f"{m_off['win_rate']:>7.1f}%",    f"{m_on['win_rate']:>7.1f}%"),
        ("Profit Factor",    f"{_pf(m_off):>8}",               f"{_pf(m_on):>8}"),
        ("Net Profit",       f"${m_off['net_profit']:>8.2f}",  f"${m_on['net_profit']:>8.2f}"),
        ("Max Drawdown",     f"${m_off['max_drawdown_usd']:>7.2f} ({m_off['max_drawdown_pct']:.1f}%)",
                             f"${m_on['max_drawdown_usd']:>7.2f} ({m_on['max_drawdown_pct']:.1f}%)"),
        ("Expectancy/trade", f"${m_off['expectancy']:>8.2f}",  f"${m_on['expectancy']:>8.2f}"),
        ("Average RR",       f"{m_off['avg_rr']:>8.3f}R",      f"{m_on['avg_rr']:>8.3f}R"),
        ("Avg MFE",          f"{m_off['avg_mfe_r']:>8.3f}R",   f"{m_on['avg_mfe_r']:>8.3f}R"),
        ("Avg MAE",          f"{m_off['avg_mae_r']:>8.3f}R",   f"{m_on['avg_mae_r']:>8.3f}R"),
        ("Avg Duration",     f"{m_off['avg_duration']:>6.0f} min",
                             f"{m_on['avg_duration']:>6.0f} min"),
        ("Max Consec Wins",  f"{m_off['max_consec_wins']:>8}",  f"{m_on['max_consec_wins']:>8}"),
        ("Max Consec Loss",  f"{m_off['max_consec_losses']:>8}", f"{m_on['max_consec_losses']:>8}"),
    ]
    hdr = f"{'Metric':<24}  {'ForceTrade=OFF':>22}  {'ForceTrade=ON':>22}"
    print(SEP2)
    print(hdr)
    print(SEP2)
    for label, v_off, v_on in rows:
        print(f"  {label:<22}  {v_off:>22}  {v_on:>22}")
    print(SEP2)


def _pf(m):
    pf = m.get("profit_factor", 0)
    return "∞" if pf == float("inf") else f"{pf:.3f}"


def print_section_breakdown(title, breakdown_off, breakdown_on=None):
    print(f"\n{title}")
    print(SEP2)
    keys = sorted(set(list(breakdown_off.keys()) + (list(breakdown_on.keys()) if breakdown_on else [])))
    if breakdown_on:
        header = f"  {'Key':<14}  {'OFF: trades':>11}  {'OFF: WR':>8}  {'OFF: PF':>8}  "
        header += f"{'ON: trades':>10}  {'ON: WR':>8}  {'ON: PF':>8}"
        print(header)
        print("  " + "-" * 68)
        for k in keys:
            mo  = breakdown_off.get(k, {"total": 0, "win_rate": 0, "profit_factor": 0})
            mon = breakdown_on.get(k,  {"total": 0, "win_rate": 0, "profit_factor": 0})
            pf_off = _pf(mo)
            pf_on  = _pf(mon)
            print(f"  {k:<14}  {mo['total']:>11}  {mo['win_rate']:>7.1f}%  {pf_off:>8}  "
                  f"{mon['total']:>10}  {mon['win_rate']:>7.1f}%  {pf_on:>8}")
    else:
        print(f"  {'Key':<14}  {'Trades':>8}  {'Win Rate':>9}  {'PF':>8}  {'Net P&L':>10}")
        print("  " + "-" * 55)
        for k in keys:
            m = breakdown_off[k]
            if m["total"] == 0:
                continue
            print(f"  {k:<14}  {m['total']:>8}  {m['win_rate']:>8.1f}%  {_pf(m):>8}  "
                  f"${m['net_profit']:>9.2f}")


def print_filter_section(trades_off, trades_on=None):
    print(f"\nFILTER CORRELATION ANALYSIS")
    print(SEP2)
    print("  Win rate when each ICT filter was confirmed vs not confirmed at trade entry\n")
    datasets = [("ForceTrade=OFF", trades_off)]
    if trades_on:
        datasets.append(("ForceTrade=ON", trades_on))

    for label, trades in datasets:
        print(f"  {label}:")
        fb = filter_breakdown(trades)
        for fname, groups in fb.items():
            on_m  = groups["filter_active"]
            off_m = groups["filter_inactive"]
            if on_m["total"] == 0 and off_m["total"] == 0:
                continue
            print(f"    {fname}=1 : {on_m['total']:4d} trades  WR={on_m['win_rate']:5.1f}%"
                  f"  PF={_pf(on_m):>6}  Net={_usd(on_m['net_profit'])}")
            print(f"    {fname}=0 : {off_m['total']:4d} trades  WR={off_m['win_rate']:5.1f}%"
                  f"  PF={_pf(off_m):>6}  Net={_usd(off_m['net_profit'])}")
        print()


def print_mfe_mae(trades_off, trades_on=None):
    print(f"\nMFE / MAE ANALYSIS  (trade management quality)")
    print(SEP2)
    print("  MFE = how far price moved in your favour  (measures TP placement quality)")
    print("  MAE = how close price came to your SL     (measures SL placement quality)\n")

    for label, trades in [("ForceTrade=OFF", trades_off)] + ([("ForceTrade=ON", trades_on)] if trades_on else []):
        mm = mfe_mae_analysis(trades)
        if not mm:
            continue
        print(f"  {label}:")
        print(f"    % of trades where MFE reached each R multiple:")
        for th, pct in mm["mfe_reach_pct"].items():
            bar = "█" * int(pct / 2)
            print(f"      MFE >= {th:.1f}R : {pct:5.1f}%  {bar}")
        print(f"    % of trades where MAE reached each R multiple:")
        for th, pct in mm["mae_reach_pct"].items():
            bar = "█" * int(pct / 2)
            print(f"      MAE >= {th:.1f}R : {pct:5.1f}%  {bar}")
        print()


def print_rejection_analysis(sig_off, sig_on):
    print(f"\nSIGNAL REJECTION ANALYSIS  (ForceTrade=OFF only — shows which filter blocks most)")
    print(SEP2)
    for label, signals in [("ForceTrade=OFF", sig_off), ("ForceTrade=ON", sig_on)]:
        if not signals:
            continue
        ra = signal_rejection_analysis(signals)
        print(f"  {label}:")
        print(f"    Total signals evaluated : {ra['total_signals']}")
        print(f"    Accepted                : {ra['accepted']}  ({ra['acceptance_rate']:.1f}%)")
        print(f"    Rejected                : {ra['rejected']}")
        print(f"    Rejection by step:")
        for step, count in ra["rejection_by_step"].items():
            pct = count / ra["rejected"] * 100 if ra["rejected"] else 0
            bar = "█" * int(pct / 2)
            print(f"      {step:<35} : {count:5d}  ({pct:5.1f}%)  {bar}")
        print()


def print_interpretation(m_off, m_on):
    """
    Auto-interpret the comparison and print actionable conclusions.
    """
    print(f"\nAUTO-INTERPRETATION")
    print(SEP2)

    if m_off["total"] == 0 or m_on["total"] == 0:
        print("  Insufficient data for interpretation.")
        return

    # Edge source determination
    off_edge = m_off["expectancy"] > 0
    on_edge  = m_on["expectancy"] > 0
    print(f"  Edge source:")
    if off_edge and not on_edge:
        print("  → ICT entry logic IS the source of edge. ForceTrade destroys it.")
        print("    Trade management alone does NOT have positive expectancy.")
    elif on_edge and not off_edge:
        print("  → Trade management (SL/TP/trailing) has positive expectancy independently.")
        print("    ICT entry logic is HURTING performance (over-filtering or wrong direction bias).")
        print("  WARNING: This result is likely regime-dependent. Verify on 2+ years of data.")
    elif off_edge and on_edge:
        print("  → Both modes have positive expectancy. Edge comes from BOTH sources.")
        if m_off["expectancy"] > m_on["expectancy"]:
            print(f"    ICT filters add {m_off['expectancy'] - m_on['expectancy']:.2f}$/trade over ForceTrade.")
            print("    ICT entry logic improves trade management's baseline edge.")
        else:
            print(f"    ForceTrade has higher expectancy by {m_on['expectancy'] - m_off['expectancy']:.2f}$/trade.")
            print("    ICT filters may be over-filtering. Consider relaxing entry conditions.")
    else:
        print("  → Neither mode has positive expectancy. Strategy needs fundamental revision.")

    # Drawdown comparison
    print(f"\n  Drawdown:")
    if m_off["max_drawdown_pct"] < m_on["max_drawdown_pct"]:
        print(f"  → ICT filters REDUCE drawdown by "
              f"{m_on['max_drawdown_pct'] - m_off['max_drawdown_pct']:.1f}pp vs ForceTrade.")
        print("    Entry logic provides capital protection benefit.")
    else:
        print(f"  → ForceTrade has LOWER drawdown by "
              f"{m_off['max_drawdown_pct'] - m_on['max_drawdown_pct']:.1f}pp.")
        print("    High-frequency trading spreads risk but may be misleading (more trades = more exposure).")

    # Trade frequency
    ratio = m_on["total"] / m_off["total"] if m_off["total"] > 0 else float("inf")
    print(f"\n  Trade frequency:")
    print(f"  → ForceTrade generates {ratio:.1f}x more trades than ICT entry logic.")
    if ratio > 20:
        print("    This extreme frequency difference makes direct profit comparison meaningless.")
        print("    Use expectancy/trade and profit factor as the fair comparison metrics.")

    # ForceTrade verdict
    print(f"\n  ForceTrade recommendation:")
    print("  → ForceTrade MUST remain a testing tool only.")
    reasons = [
        "Alternates BUY/SELL every 60 seconds regardless of market state",
        "Results are regime-dependent (profitable in trends, destructive in ranges)",
        "Does not represent ICT strategy quality",
        "High frequency amplifies spread costs on live accounts",
    ]
    for r in reasons:
        print(f"     • {r}")

    # Trade management transferability
    print(f"\n  Trade management components worth keeping in all versions:")
    components = [
        "Swing-based SL (dynamic, follows market structure)",
        "ATR-based TP (adapts to volatility)",
        "Breakeven logic (protects profits after 1R)",
        "Trailing stop (captures extended trends)",
        "Partial TP (locks partial profit at configurable R multiple)",
        "MaxSLPips guard (prevents trading inside spread + noise)",
    ]
    for c in components:
        print(f"     ✓ {c}")


# ---------------------------------------------------------------------------
# Main report entry point
# ---------------------------------------------------------------------------

def generate_report(path_off, path_on, path_sig_off=None, path_sig_on=None, label=""):
    print(f"\n{SEP}")
    title = f"ICT SMC EA PERFORMANCE REPORT"
    if label:
        title += f"  —  {label}"
    print(f"  {title}")
    print(SEP)

    print(f"\nLoading trade history files...")
    trades_off = load_trade_history(path_off)
    trades_on  = load_trade_history(path_on)  if path_on  else []
    sig_off    = load_signal_log(path_sig_off) if path_sig_off else []
    sig_on     = load_signal_log(path_sig_on)  if path_sig_on  else []

    print(f"  ForceTrade=OFF : {len(trades_off)} trades loaded from '{path_off}'")
    if path_on:
        print(f"  ForceTrade=ON  : {len(trades_on)} trades loaded from '{path_on}'")
    if sig_off:
        print(f"  Signals OFF    : {len(sig_off)} rows loaded from '{path_sig_off}'")
    if sig_on:
        print(f"  Signals ON     : {len(sig_on)} rows loaded from '{path_sig_on}'")

    m_off = calc_metrics(trades_off, "ForceTrade=OFF")
    m_on  = calc_metrics(trades_on,  "ForceTrade=ON")  if trades_on else {"total": 0, "label": "ForceTrade=ON"}

    # ── SUMMARY COMPARISON ────────────────────────────────────────────────
    print(f"\n{'SUMMARY COMPARISON':^72}")
    if trades_on:
        print_comparison(m_off, m_on)
    else:
        print(f"\n  ForceTrade=OFF  (single-file mode):")
        print_core_metrics(m_off)

    # ── DETAILED: FORCE OFF ───────────────────────────────────────────────
    print(f"\n{'DETAILED: ForceTrade=OFF':^72}")
    print(SEP2)
    print_core_metrics(m_off)

    if trades_on:
        print(f"\n{'DETAILED: ForceTrade=ON':^72}")
        print(SEP2)
        print_core_metrics(m_on)

    # ── BREAKDOWNS ────────────────────────────────────────────────────────
    sb_off = session_breakdown(trades_off)
    sb_on  = session_breakdown(trades_on) if trades_on else {}
    print_section_breakdown("\nSESSION BREAKDOWN", sb_off, sb_on if trades_on else None)

    db_off = direction_breakdown(trades_off)
    db_on  = direction_breakdown(trades_on) if trades_on else {}
    print_section_breakdown("\nDIRECTION BREAKDOWN  (BUY vs SELL bias)", db_off, db_on if trades_on else None)

    dow_off = dow_breakdown(trades_off)
    dow_on  = dow_breakdown(trades_on) if trades_on else {}
    print_section_breakdown("\nDAY-OF-WEEK BREAKDOWN", dow_off, dow_on if trades_on else None)

    # ── FILTER CORRELATION ────────────────────────────────────────────────
    print_filter_section(trades_off, trades_on if trades_on else None)

    # ── MFE / MAE ─────────────────────────────────────────────────────────
    print_mfe_mae(trades_off, trades_on if trades_on else None)

    # ── SIGNAL REJECTION ──────────────────────────────────────────────────
    if sig_off or sig_on:
        print_rejection_analysis(sig_off, sig_on)

    # ── AUTO-INTERPRETATION ───────────────────────────────────────────────
    if trades_on:
        print_interpretation(m_off, m_on)

    print(f"\n{SEP}")
    print("  END OF REPORT")
    print(SEP)


def single_file_report(path, path_sig=None, label=""):
    """Analyze a single TradeHistory CSV (no ForceTrade comparison)."""
    print(f"\n{SEP}")
    print(f"  ICT SMC EA — SINGLE FILE ANALYSIS  {label}")
    print(SEP)

    trades = load_trade_history(path)
    sigs   = load_signal_log(path_sig) if path_sig else []
    print(f"\n  Loaded {len(trades)} trades from '{path}'")

    m = calc_metrics(trades, label or os.path.basename(path))
    print_core_metrics(m)

    sb = session_breakdown(trades)
    print_section_breakdown("\nSESSION BREAKDOWN", sb)

    db = direction_breakdown(trades)
    print_section_breakdown("\nDIRECTION BREAKDOWN", db)

    dow = dow_breakdown(trades)
    print_section_breakdown("\nDAY-OF-WEEK BREAKDOWN", dow)

    print_filter_section(trades)
    print_mfe_mae(trades)

    scr = score_breakdown(trades)
    print_section_breakdown("\nSCORE BUCKET BREAKDOWN", scr)

    if sigs:
        print_rejection_analysis(sigs, [])

    print(f"\n{SEP}\n  END OF REPORT\n{SEP}")


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="ICT SMC EA Performance Analyzer",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  Compare ForceTrade ON vs OFF:
    python analyze_ea_performance.py --off V16_OFF_TradeHistory.csv --on V16_ON_TradeHistory.csv

  Include signal logs for rejection analysis:
    python analyze_ea_performance.py --off V16_OFF_TradeHistory.csv --on V16_ON_TradeHistory.csv \\
           --sig-off V16_OFF_Signals.csv --sig-on V16_ON_Signals.csv

  Single file (no comparison):
    python analyze_ea_performance.py --single V16_TradeHistory.csv

  Label the report:
    python analyze_ea_performance.py --off ... --on ... --label "V1.6 XAUUSD 2024"
        """
    )
    parser.add_argument("--off",     metavar="FILE", help="TradeHistory CSV with ForceTrade=OFF")
    parser.add_argument("--on",      metavar="FILE", help="TradeHistory CSV with ForceTrade=ON")
    parser.add_argument("--sig-off", metavar="FILE", help="Signals CSV with ForceTrade=OFF")
    parser.add_argument("--sig-on",  metavar="FILE", help="Signals CSV with ForceTrade=ON")
    parser.add_argument("--single",  metavar="FILE", help="Single TradeHistory CSV (no comparison)")
    parser.add_argument("--sig",     metavar="FILE", help="Signals CSV for single-file mode")
    parser.add_argument("--label",   default="",     help="Report label (e.g. 'V1.6 XAUUSD 2024')")

    args = parser.parse_args()

    if args.single:
        single_file_report(args.single, args.sig, args.label)
    elif args.off:
        generate_report(args.off, args.on, args.sig_off, args.sig_on, args.label)
    else:
        # No arguments — show usage and demo with sample data if available
        parser.print_help()
        print("\n\nNo CSV files specified. Run with --help to see usage examples.")
        print("\nQuick start:")
        print("  1. In MT5 Strategy Tester, run the EA with ForceTrades=false, EnableCSVLog=true")
        print("  2. Copy ICT_SMC_Trade_History_XAUUSD.csv from:")
        print("     C:\\Users\\<user>\\AppData\\Roaming\\MetaQuotes\\Terminal\\Common\\Files\\")
        print("  3. Rename it to e.g. V16_OFF_TradeHistory.csv")
        print("  4. Repeat with ForceTrades=true → V16_ON_TradeHistory.csv")
        print("  5. Run: python analyze_ea_performance.py --off V16_OFF_TradeHistory.csv")
        print("                                           --on  V16_ON_TradeHistory.csv")
        print("                                           --label 'V1.6 XAUUSD 2024'")


if __name__ == "__main__":
    main()
