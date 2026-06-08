#!/usr/bin/env python3
"""ICT SMC EA — Complete Input Settings Guide  V1.0–V1.4"""
import openpyxl
from openpyxl.styles import PatternFill, Font, Alignment, Border, Side
from openpyxl.utils import get_column_letter

OUT = "/home/user/Rattana/ICT_SMC_EA_Settings_Guide.xlsx"

# ── colours ──────────────────────────────────────────────────────────
def f(c):   return PatternFill(fill_type='solid', fgColor=c)
def fn(c='FFFFFF', b=False, sz=10): return Font(color=c, bold=b, size=sz, name='Calibri')
def al(h='left', v='center', w=True): return Alignment(horizontal=h, vertical=v, wrap_text=w)
def bd():
    s = Side(style='thin', color='3A3A5A')
    return Border(left=s, right=s, top=s, bottom=s)

HDR  = '0D2137'; GRP = '12243A'; ODD = '161625'; EVN = '1C1C2E'
NEW  = '0A2A0A'; WARN= '2A0A0A'
TW='FFFFFF'; TG='FFD700'; TGR='00DD77'; TR='FF6060'; TB='64AAFF'; TSL='B0B0C0'; TOR='FFA040'
C50H='252500'; C50='1C1C00'; C100H='002500'; C100='001C00'
VERS=['V1.0','V1.1','V1.2','V1.3','V1.4']

# ── helper: write a cell ─────────────────────────────────────────────
def wc(ws, r, c, val, bg=ODD, fc=TW, bold=False, sz=10, h='left', wrap=True, merge=0):
    cell = ws.cell(row=r, column=c, value=str(val) if val is not None else '')
    cell.fill = f(bg); cell.font = fn(fc, bold, sz)
    cell.alignment = al(h, 'center', wrap); cell.border = bd()
    if merge > 1:
        ws.merge_cells(start_row=r, start_column=c, end_row=r, end_column=c+merge-1)

# ═══════════════════════════════════════════════════════════════════════
# PARAMETER DATA
# ═══════════════════════════════════════════════════════════════════════
# grp, name, type, v10,v11,v12,v13,v14, what, f50,fn50, f100,fn100, warning
P = [
  # ── TRADING STYLE ──────────────────────────────────────────────────
  ('TRADING STYLE','TradingStyle','Enum','—','—','BALANCED','SMART_ACTIVE','SMART_ACTIVE',
   'Master preset that overrides many individual settings.\n'
   '• Conservative: score≥80, all ICT strict, CD 30m  (1-5 trades/day)\n'
   '• Balanced: respects input toggles, score≥70  (3-8 trades/day)\n'
   '• Aggressive: MSS/Trend OFF, OTE 55-90%, score≥50  (8-15 trades/day)\n'
   '• Smart Active (V1.3+): all ICT ON, better detection, score≥55  (8-15 trades/day)\n'
   '• Smart Active+ (V1.4): all ICT ON, OTE 55-90%, score≥45  (15-25 trades/day)\n'
   '• Ultra Active: filters minimal, max frequency',
   'STYLE_CONSERVATIVE','Safest for $50 — strictest entries, fewer but higher-quality trades. Protects small capital from overtrading.',
   'STYLE_BALANCED','Good balance of trade frequency and quality for $100.',
   'Overrides many individual inputs. Settings below marked * may not take effect.'),

  # ── RISK MANAGEMENT ────────────────────────────────────────────────
  ('RISK MANAGEMENT','RiskMode','Enum','—','FIXED_PCT','FIXED_PCT','FIXED_PCT','FIXED_PCT',
   'How position size is calculated:\n'
   '• RISK_FIXED_PCT: lot = (balance × risk%) ÷ (SL pips × pip value)\n'
   '• RISK_FIXED_LOT: always use FixedLot value (ignores RiskPercent)\n'
   '• RISK_DYNAMIC_EQ: same as FIXED_PCT but uses equity not balance',
   'RISK_FIXED_LOT','Use fixed 0.01 lot on $50. Percentage mode can give lot sizes below broker minimum.',
   'RISK_FIXED_PCT','Percentage mode scales correctly with $100 account.',
   'Not in V1.0 — V1.0 always uses RISK_FIXED_PCT equivalent'),

  ('RISK MANAGEMENT','RiskPercent','%','0.5','0.5','0.5','0.5','0.5',
   'Percentage of account balance to risk per single trade.\n'
   'Only used when RiskMode = RISK_FIXED_PCT or RISK_DYNAMIC_EQ.\n'
   'Example: $100 × 1.0% = $1.00 max risk per trade.',
   '1.0','Not used when RiskMode=FIXED_LOT. Keep ≥1.0 as fallback anyway.',
   '1.0','$100 × 1.0% = $1 risk/trade. Appropriate for early-stage live trading.',
   ''),

  ('RISK MANAGEMENT','FixedLot','lot','0.0','0.0','0.0','0.0','0.0',
   'Fixed lot size used when RiskMode = RISK_FIXED_LOT.\n'
   '0.0 = use RiskPercent calculation instead.\n'
   'Minimum lot on most brokers for XAUUSD: 0.01',
   '0.01','Set 0.01 and combine with RiskMode = RISK_FIXED_LOT for predictable micro-account risk.',
   '0.01','Use 0.01 as safety floor with FIXED_LOT, or 0.0 to let RiskPercent calculate.',
   ''),

  ('RISK MANAGEMENT','MaxDailyLossPercent','%','10.0','10.0','10.0','10.0','10.0',
   'EA stops trading for the day when total daily P&L loss reaches this % of balance.\n'
   'Example: $50 × 6% = $3.00 maximum loss per day.\n'
   'Resets at midnight broker time.',
   '6.0','$50 × 6% = $3 daily stop. Default 10% = $5 on $50 which is too aggressive for a micro start.',
   '6.0','$100 × 6% = $6 daily stop. Keeps drawdown manageable while allowing normal trade volume.',
   ''),

  ('RISK MANAGEMENT','MaxTradesPerDay','int','10','10','25','25','25',
   'Maximum new trades allowed per day. Counter resets at midnight.\n'
   'Should match your TradingStyle target frequency:\n'
   '  Conservative 1-5 | Balanced 3-8 | SmartActive 8-15 | SmartActive+ 15-25',
   '5','Limit to 5/day on $50 — fewer chances to overexpose small capital.',
   '10','10/day works for V1.0-V1.2. Raise to 15-20 for V1.3/V1.4 Smart Active styles.',
   ''),

  ('RISK MANAGEMENT','RewardRiskRatio','ratio','2.0','2.0','2.0','2.0','2.0',
   'Target profit relative to stop loss distance.\n'
   '2.0 = TP is 2× the SL distance (2:1 R:R).\n'
   'At 2:1 R:R you break even with only 34% win rate.',
   '2.0','Never go below 2.0 on $50 — you need the mathematical edge.',
   '2.0','Keep 2.0. Do not reduce below 1.5 or the edge disappears.',
   ''),

  ('RISK MANAGEMENT','MaxLotLimit','lot','0.10','0.10','0.10','0.10','0.10',
   'Hard ceiling on position size regardless of risk calculation.\n'
   'Prevents oversized positions from glitches or very tight SL signals.\n'
   'Scale this with your account size.',
   '0.01','Lock at 0.01 — never allow more than minimum lot on $50.',
   '0.02','0.02 allows slightly larger positions as $100 account grows.',
   ''),

  ('RISK MANAGEMENT','MinRewardRiskRatio','ratio','2.0','2.0','2.0','2.0','2.0',
   'Trade is skipped if the actual calculated R:R is below this value.\n'
   'Rejects setups where SL is too wide vs the target TP.\n'
   'Small float tolerance (-0.001) avoids rounding false-skips (FIX R).',
   '2.0','Always require 2:1 minimum R:R.',
   '1.8','Can relax slightly to 1.8 to allow more setups.',
   ''),

  # ── TAKE PROFIT MODE ───────────────────────────────────────────────
  ('TAKE PROFIT MODE','TPMode','Enum','—','FIXED_RR','FIXED_RR','FIXED_RR','FIXED_RR',
   'How take profit level is calculated:\n'
   '• TP_FIXED_RR: TP = entry ± (SL distance × RewardRiskRatio)\n'
   '• TP_ATR: TP = entry ± (ATR(14) × ATRMultiplierTP)\n'
   '• TP_HYBRID: TP = min(FixedRR, ATR) — most conservative of the two',
   'TP_FIXED_RR','Fixed R:R is predictable and simple. Best for small accounts.',
   'TP_FIXED_RR','Fixed R:R keeps trade math consistent.',
   'Not in V1.0'),

  ('TAKE PROFIT MODE','ATRMultiplierTP','x','—','3.0','3.0','3.0','3.0',
   'ATR multiplier used only when TPMode = TP_ATR or TP_HYBRID.\n'
   'TP = current ATR(14) × this value.\n'
   'ATR adapts to current market volatility automatically.',
   '3.0','Keep default — only relevant if you switch TPMode to TP_ATR.',
   '3.0','Keep default.',
   'Only used when TPMode ≠ TP_FIXED_RR'),

  # ── PARTIAL TAKE PROFIT ────────────────────────────────────────────
  ('PARTIAL TAKE PROFIT','UsePartialTP','bool','—','true','true','true','true',
   'When true: closes PartialClosePercent% of position at PartialCloseRR × R:R,\n'
   'then moves SL to breakeven for the remaining portion.\n'
   'Example: 50% closed at 1R → remaining 50% runs risk-free to full 2R TP.',
   'true','Highly recommended for $50 — locks in 50% profit at 1R, remainder runs free.',
   'true','Recommended for all account sizes.',
   'Not in V1.0'),

  ('PARTIAL TAKE PROFIT','PartialClosePercent','%','—','50.0','50.0','50.0','50.0',
   'Percentage of position to close at the partial TP level.\n'
   '50.0 = close half the position when 1R profit is reached.',
   '50.0','Standard 50% partial close.',
   '50.0','Keep 50%. Going to 100% removes the benefit of running the remainder.',
   ''),

  ('PARTIAL TAKE PROFIT','PartialCloseRR','R','—','1.0','1.0','1.0','1.0',
   'R:R level at which partial close triggers.\n'
   '1.0 = trigger when profit = 1× the SL distance.\n'
   'After partial close, SL is moved to breakeven.',
   '1.0','Trigger at 1R — ensures 50% is locked even if remainder hits breakeven.',
   '1.0','Standard. Adjust to 1.5 if you prefer to run a bit further before locking.',
   ''),

  # ── TRADE FILTERS ──────────────────────────────────────────────────
  ('TRADE FILTERS','UseTimeFilter','bool','true','true','true','true','true',
   'When true: EA only trades during active trading sessions (set below).\n'
   'When false: EA trades 24/5 regardless of time.',
   'true','Always keep ON — avoid low-liquidity hours.',
   'true','Keep ON.',
   ''),

  ('TRADE FILTERS','MaxSpreadPoints','pts','50','50','80','80','80',
   'Maximum spread (bid-ask gap) in broker points allowed before a trade.\n'
   'Protects against wide spreads during news or low liquidity.\n'
   'XAUUSD typical spread: 20-40 pts normal, 80-200 pts during news.\n'
   '0 = disable check.',
   '80','80 pts covers normal gold spreads. Wider = possible during news events.',
   '80','80 is appropriate for XAUUSD. Reduce to 50 if broker has tight spreads.',
   ''),

  ('TRADE FILTERS','MinStopDistance','pts','20','20','20','20','20',
   'Minimum SL distance from entry price in broker points.\n'
   'Brokers enforce a "freeze level" — orders too close to price are rejected.\n'
   'Must exceed your broker\'s stop level to avoid order rejection.',
   '20','Keep default 20 points.',
   '20','Keep default.',
   ''),

  ('TRADE FILTERS','MaxConsecutiveLosses','int','10','10','10','10','10',
   'EA halts trading after N consecutive losses.\n'
   'Lifetime counter unless ResetLossStreakDaily = true.\n'
   'Circuit breaker against runaway losing streaks.',
   '5','Lower to 5 on $50 — stops the EA before 5 losses damage the account too much.',
   '7','7 consecutive losses is a solid circuit breaker for $100.',
   ''),

  ('TRADE FILTERS','MaxDailyLossTrades','int','3','3','3','3','3',
   'Stop trading for the day after N losing trades (not the same as MaxDailyLossPercent).\n'
   'Resets at midnight. FIX T: prevents clusters of consecutive daily losses.',
   '2','Stop after 2 losing trades on $50 — preserves capital for the next day.',
   '3','Standard 3 losing-trade daily stop.',
   ''),

  ('TRADE FILTERS','ResetLossStreakDaily','bool','true','true','true','true','true',
   'true = MaxConsecutiveLosses counter resets every midnight.\n'
   'false = counter accumulates for lifetime of the EA session.',
   'true','Reset daily — fresh start each morning.',
   'true','Keep true.',
   ''),

  # ── ICT STRUCTURE FILTERS ──────────────────────────────────────────
  ('ICT STRUCTURE FILTERS','UseMSSFilter','bool','—','true','true','true','true',
   'Require a Market Structure Shift on H1 before entry.\n'
   'MSS = H1 price breaks above a previous swing high (bullish MSS)\n'
   'or below a swing low (bearish MSS) — confirms direction change.\n'
   '* Overridden OFF by STYLE_AGGRESSIVE and STYLE_ULTRA_ACTIVE',
   'true','Keep ON — MSS confirms the move is real, not noise.',
   'true','Always ON for quality signals.',
   'Not in V1.0. Overridden by TradingStyle in V1.2+'),

  ('ICT STRUCTURE FILTERS','UseBOSFilter','bool','—','true','true','true','true',
   'Require Break of Structure on M15 for lower-timeframe confirmation.\n'
   'BOS = M15 price breaks above recent swing high (after bullish MSS).\n'
   'Adds a second confirmation layer on a lower timeframe.',
   'true','Keep ON.',
   'true','Keep ON.',
   'Not in V1.0'),

  ('ICT STRUCTURE FILTERS','RequireLiquiditySweep','bool','—','false','false','false','false',
   'Require a liquidity sweep (stop hunt) before entry.\n'
   'Smart money sweeps retail stop orders above swing highs / below swing lows\n'
   'before reversing the move.\n'
   'false = optional; true = must detect sweep (very rare, reduces frequency to ~1-2/week)',
   'false','Keep false — liquidity sweeps are rare. Enabling reduces trades dramatically.',
   'false','Keep false unless you specifically want high-rarity setups.',
   ''),

  ('ICT STRUCTURE FILTERS','UseSMTFilter','bool','—','false','false','false','false',
   'SMT (Smart Money Divergence) filter.\n'
   'Compares price structure between this symbol and SMTSymbol.\n'
   'BUY if this symbol makes lower low but correlated symbol does not.\n'
   'Usually: XAUUSD vs XAGUSD divergence.',
   'false','Keep OFF for simplicity.',
   'false','Keep OFF unless you specifically trade SMT setups.',
   'Not in V1.0'),

  ('ICT STRUCTURE FILTERS','SMTSymbol','string','—','XAGUSD','XAGUSD','XAGUSD','XAGUSD',
   'Correlated symbol for SMT divergence. Only active when UseSMTFilter = true.\n'
   'Gold → XAGUSD (silver). Indices → use correlated index.',
   'XAGUSD','Keep default.',
   'XAGUSD','Keep default.',
   'Symbol must exist on your broker'),

  # ── NEWS FILTER ────────────────────────────────────────────────────
  ('NEWS FILTER','UseNewsFilter','bool','—','false','false','false','false',
   'Block trading before/after high-impact economic news events.\n'
   'Uses MT5 Calendar API. Requires "Allow WebRequest" in MT5 settings.',
   'false','Disable in Strategy Tester (calendar limited). Enable for live trading.',
   'false','Optional but recommended for live, especially around NFP/FOMC.',
   'Not in V1.0. Requires Allow WebRequest enabled in MT5'),

  ('NEWS FILTER','NewsBlockBeforeMin','min','—','30','30','30','30',
   'Minutes BEFORE a high-impact news event to stop accepting new trades.',
   '30','Standard 30-minute pre-news block.',
   '30','Keep 30 minutes.',
   ''),

  ('NEWS FILTER','NewsBlockAfterMin','min','—','30','30','30','30',
   'Minutes AFTER a high-impact news event before resuming trades.\n'
   'Spreads and volatility remain elevated for 15-30 min post-news.',
   '30','30-minute post-news cooldown.',
   '30','Keep 30 minutes.',
   ''),

  # ── TRADE QUALITY SCORE ────────────────────────────────────────────
  ('TRADE QUALITY SCORE','UseTradeScore','bool','—','—','true','true','true',
   'Enable the minimum score gate.\n'
   'When false: score is shown on panel but never blocks trades.\n'
   'When true: trade skipped if score < MinimumTradeScore.\n'
   '(In V1.1, MinimumTradeScore = 0 effectively disables the gate)',
   'true','Keep ON — score filter is your quality gate on small accounts.',
   'true','Keep ON.',
   'Only in V1.2+. In V1.1 set MinimumTradeScore=0 to disable'),

  ('TRADE QUALITY SCORE','MinimumTradeScore','0-100','—','70','70','70','70',
   'Minimum score (0-100) required to place a trade.\n'
   'Score built from: session quality, spread tightness, OTE precision,\n'
   'liquidity presence, FVG count, D1/H4 trend alignment.\n'
   'Overridden by TradingStyle preset in V1.2+.',
   '70','70 blocks low-quality setups without being too restrictive.',
   '65','Slightly relax to 65 for more trades on $100 while keeping quality.',
   'Overridden by TradingStyle in V1.2+'),

  # ── SESSIONS ───────────────────────────────────────────────────────
  ('SESSIONS (GMT)','AutoDetectGMT','bool','—','true','true','true','true',
   'Auto-detect broker GMT offset using: offset = (TimeCurrent - TimeGMT) / 3600.\n'
   'Works correctly on live accounts. In Strategy Tester always shows GMT+0 (normal).',
   'true','Keep ON for live trading.',
   'true','Keep ON.',
   'Always shows GMT+0 in Strategy Tester — this is expected, not a bug'),

  ('SESSIONS (GMT)','BrokerGMTOffset','hrs','0','0','0','0','0',
   'Manual GMT offset when AutoDetectGMT = false.\n'
   'EU brokers: GMT+2 (winter) / GMT+3 (summer DST).',
   '0','Leave 0 when AutoDetectGMT = true.',
   '0','Leave 0 when AutoDetectGMT = true.',
   ''),

  ('SESSIONS (GMT)','SessionSydney','bool','false','false','false','false','false',
   'Allow trading during Sydney session: 22:00-07:00 GMT.\n'
   'Low volume for XAUUSD. Not recommended for gold.',
   'false','Keep OFF — very low liquidity for gold.',
   'false','Keep OFF.',
   ''),

  ('SESSIONS (GMT)','SessionTokyo','bool','false','false','false','false','false',
   'Allow trading during Tokyo session: 00:00-09:00 GMT.\n'
   'Moderate XAUUSD activity. Enable for V1.4 SmartActive+ expanded coverage.',
   'false','Keep OFF on $50.',
   'false','Can enable for V1.4 SmartActive+ to expand session hours.',
   ''),

  ('SESSIONS (GMT)','SessionLondon','bool','true','true','true','true','true',
   'Allow trading during London session: 08:00-17:00 GMT.\n'
   'Highest liquidity period. Best session for XAUUSD and FX.',
   'true','Always ON.',
   'true','Always ON.',
   ''),

  ('SESSIONS (GMT)','SessionNewYork','bool','true','true','true','true','true',
   'Allow trading during New York session: 13:00-22:00 GMT.\n'
   'High volatility with strong ICT move potential.',
   'true','Always ON.',
   'true','Always ON.',
   ''),

  ('SESSIONS (GMT)','OverlapLondonNY','bool','true','true','true','true','true',
   'Allow trading during London/NY overlap: 13:00-17:00 GMT.\n'
   'Best 4 hours of the day — highest liquidity AND volatility combined.',
   'true','Definitely ON — highest quality ICT entries happen in this window.',
   'true','Always ON.',
   ''),

  ('SESSIONS (GMT)','OverlapTokyoLondon','bool','false','false','false','false','false',
   'Allow trading during Tokyo/London overlap: 08:00-09:00 GMT.\n'
   'Only 1 hour. Already covered by SessionLondon.',
   'false','Keep OFF.',
   'false','Keep OFF.',
   ''),

  # ── STOP LOSS ──────────────────────────────────────────────────────
  ('STOP LOSS','SLBufferPips','pips','15','15','15','15','15',
   'Extra pip buffer beyond the swing high/low for SL placement.\n'
   'Example: swing low at 2000.00, buffer=15 → SL placed ~15 pips below.\n'
   'Prevents SL from being hit by normal wick noise at the swing level.',
   '10','Reduce to 10 pips on $50 — tightens SL and reduces $ loss per trade.',
   '15','Default 15 pips provides good buffer against stop hunts.',
   ''),

  ('STOP LOSS','UseTrailingStop','bool','false','false','false','false','false',
   'Enable trailing stop loss.\n'
   'When true: SL moves up (for BUY) after TrailingStartPips profit.\n'
   'UsePartialTP is a more consistent alternative.',
   'false','Keep OFF — UsePartialTP is more effective for ICT style.',
   'false','Keep OFF unless backtest proves improvement.',
   ''),

  ('STOP LOSS','TrailingStartPips','pips','30','30','30','30','30',
   'Profit in pips before trailing stop activates.\n'
   'Only used when UseTrailingStop = true.',
   '30','Only relevant if UseTrailingStop = true.',
   '30','Only relevant if UseTrailingStop = true.',
   'Only used when UseTrailingStop = true'),

  ('STOP LOSS','TrailingStepPips','pips','10','10','10','10','10',
   'How many pips to trail behind current price.\n'
   'Smaller = tighter trail; Larger = more room for fluctuation.',
   '10','Only relevant if UseTrailingStop = true.',
   '10','Only relevant if UseTrailingStop = true.',
   'Only used when UseTrailingStop = true'),

  # ── POSITION MANAGEMENT ────────────────────────────────────────────
  ('POSITION MANAGEMENT','CloseOnFriday','bool','true','true','true','true','true',
   'Automatically close all open positions on Friday at FridayCloseHour GMT.\n'
   'Prevents weekend gap risk — price can jump 50-200 pips over weekends.',
   'true','Always ON — weekend gaps can easily wipe $50.',
   'true','Always ON.',
   ''),

  ('POSITION MANAGEMENT','FridayCloseHour','GMT hr','14','14','14','14','14',
   'GMT hour on Friday when positions are closed.\n'
   '14:00 GMT = before thin NY afternoon and approaching weekend gap risk.',
   '14','14:00 GMT is optimal.',
   '14','Keep 14:00 GMT.',
   ''),

  ('POSITION MANAGEMENT','UseBreakeven','bool','false','false','false','false','false',
   'Move SL to entry price after BreakevenTriggerPips profit.\n'
   'UsePartialTP is the superior alternative — use one or the other.',
   'false','Keep OFF — UsePartialTP at 1R is better.',
   'false','Keep OFF.',
   'Conflicts with UsePartialTP'),

  ('POSITION MANAGEMENT','BreakevenTriggerPips','pips','40','40','40','40','40',
   'Pips of profit required before SL moves to breakeven.\n'
   'Only used when UseBreakeven = true.',
   '30','Only relevant if UseBreakeven = true.',
   '40','Only relevant if UseBreakeven = true.',
   'Only used when UseBreakeven = true'),

  # ── SWING DETECTION ────────────────────────────────────────────────
  ('SWING DETECTION','SwingLookbackBarsH1','bars','50','50','50','50','50',
   'H1 bars to scan backward when finding swing highs/lows for OTE zone.\n'
   '50 bars ≈ 2 days of H1 history.',
   '50','Keep default.',
   '50','Keep default.',
   ''),

  ('SWING DETECTION','SwingConfirmBarsH1','bars','3','3','3','3','3',
   'Bars on EACH SIDE required to confirm an H1 swing point.\n'
   '3 = swing must be highest/lowest of 7 bars total.\n'
   'Overridden by effMSSConfirm in V1.3+ Smart Active styles.',
   '3','Default is fine — overridden by TradingStyle in V1.3+.',
   '3','Keep default.',
   'In V1.3+: overridden to 2 (SmartActive) or 1 (SmartActive+) by style'),

  ('SWING DETECTION','SwingLookbackBarsM15','bars','30','30','30','30','30',
   'M15 bars to scan for the SL anchor swing.\n'
   '30 bars ≈ 7.5 hours of M15.',
   '30','Keep default.',
   '30','Keep default.',
   ''),

  ('SWING DETECTION','SwingConfirmBarsM15','bars','5','5','5','5','5',
   'Bars each side to confirm an M15 swing (used for SL placement).\n'
   '5 = swing must be highest/lowest of 11 bars.',
   '5','Keep default.',
   '5','Keep default.',
   ''),

  ('SWING DETECTION','MaxSwingDistancePips','pips','500','500','500','500','500',
   'Maximum allowed H1 swing range in pips.\n'
   'Rejects abnormally large swings that suggest unusual market conditions.\n'
   '0 = no maximum.',
   '300','Tighter at 300 pips on $50 — extreme ranges often precede reversals.',
   '500','Keep default.',
   ''),

  ('SWING DETECTION','MaxSLPips','pips','30','30','30','30','30',
   'Maximum SL distance in pips. Trade skipped if SL > this value.\n'
   'FIX O: prevents large SL from consuming disproportionate % of small accounts.',
   '20','20 pips max SL on $50 keeps maximum loss tightly controlled.',
   '25','25-30 pips appropriate for $100.',
   ''),

  ('SWING DETECTION','MinSLPips','pips','10','10','10','10','10',
   'Minimum SL distance in pips.\n'
   'FIX Q: skips trades with SL so tight it lives inside the spread.',
   '10','Keep default.',
   '10','Keep default.',
   ''),

  ('SWING DETECTION','ShowSwingLines','bool','true','true','true','true','true',
   'Draw M15 swing high/low lines on the chart.\n'
   'Shows where the EA anchored the SL.',
   'true','Keep ON for visual monitoring.',
   'true','Keep ON.',
   ''),

  # ── ICT TWINS MODEL ────────────────────────────────────────────────
  ('ICT TWINS MODEL','UseTwinsModel','bool','true','true','true','true','true',
   'Enable the full ICT Twins sequential entry model.\n'
   'Steps: HTF Level → MSS → BOS → Liquidity → OTE Zone → CISD → 1M Trigger.\n'
   'This IS the core strategy. Must always be ON.',
   'true','Always ON.',
   'true','Always ON.',
   ''),

  ('ICT TWINS MODEL','HTFLevelMinutes','min','15','15','15','15','15',
   'Timeframe for HTF reference level detection.\n'
   '15 = M15. EA checks proximity to M15 FVGs, prev-day H/L, H1/H4 levels.',
   '15','Keep default M15.',
   '15','Keep default.',
   ''),

  ('ICT TWINS MODEL','OTEMinPercent','0-1','0.65','0.65','0.65','0.65','0.65',
   'OTE zone minimum as % of the H1 swing range (measured from the base).\n'
   '0.65 = 65% retracement into the swing.\n'
   'Overridden by TradingStyle in V1.2+.',
   '0.65','Keep default. Overridden by TradingStyle in V1.2+ anyway.',
   '0.65','Keep default.',
   'Overridden by TradingStyle in V1.2+'),

  ('ICT TWINS MODEL','OTEMaxPercent','0-1','0.75','0.75','0.75','0.75','0.75',
   'OTE zone maximum as % of H1 swing range.\n'
   '0.75 = creates classic 65-75% OTE window (10% wide).\n'
   'V1.3 SmartActive widens to 60-85%; V1.4 SmartActive+ widens to 55-90%.',
   '0.75','Keep default. Overridden by TradingStyle.',
   '0.75','Keep default.',
   'Overridden by TradingStyle in V1.2+'),

  ('ICT TWINS MODEL','OTESweetSpotPercent','0-1','0.705','0.705','0.705','0.705','0.705',
   'The golden ratio point within the OTE zone (70.5%).\n'
   'Entries very close to 70.5% receive bonus quality score points.',
   '0.705','Keep default.',
   '0.705','Keep default.',
   ''),

  ('ICT TWINS MODEL','MinFVGsRequired','int','0','0','0','0','0',
   'Minimum 1-minute Fair Value Gaps required near entry.\n'
   '0 = FVG check disabled (recommended — FVGs are plentiful when setup is valid).',
   '0','Keep 0 — FVG requirement with higher values reduces frequency too much.',
   '0','Keep 0.',
   ''),

  ('ICT TWINS MODEL','HTFToleranceATRMulti','x','2','2','2','2','2',
   'Price must be within N × ATR(14) of an HTF level to qualify as "at the level".\n'
   '2 = within 2 ATRs of the reference level.',
   '2','Default 2 ATRs is balanced.',
   '2','Keep default.',
   ''),

  ('ICT TWINS MODEL','HTFLevelRequired','bool','false','false','false','false','false',
   'Require price to be near a high-timeframe reference level before MSS step.\n'
   'FIX U: default false (auto-pass Step 1).\n'
   'true = strictest mode. In trending markets EA may not trade for days.',
   'false','Keep false. Setting true on trending gold = EA stops trading.',
   'false','Keep false.',
   'Setting true on strong trends = EA will not trade'),

  ('ICT TWINS MODEL','ShowOTEZone','bool','true','true','true','true','true',
   'Draw OTE zone rectangle on chart.\n'
   'Shows exactly where EA expects price to enter for a valid trade.',
   'true','Keep ON for visual confirmation.',
   'true','Keep ON.',
   ''),

  ('ICT TWINS MODEL','MinH1RangePips','pips','50','50','50','50','50',
   'Minimum H1 swing range (high to low) in pips.\n'
   'Filters out sideways/choppy markets where the swing is too small.\n'
   '0 = no minimum.',
   '30','Relax to 30 pips on $50 — 50 pip default was too strict, reducing frequency.',
   '40','40 pips balances quality vs frequency for $100.',
   ''),

  ('ICT TWINS MODEL','UseH1RangeFilter','bool','—','—','true','true','true',
   'Toggle the H1 range minimum pip check.\n'
   'false = skip MinH1RangePips check entirely.',
   'true','Keep ON.',
   'true','Keep ON.',
   'Not in V1.0 and V1.1'),

  ('ICT TWINS MODEL','MinH1RangeATRMulti','x','—','—','—','0.8','0.8',
   'H1 swing range must be ≥ (H1 ATR × this multiplier).\n'
   'Active in STYLE_SMART_ACTIVE and STYLE_SMART_ACTIVE_PLUS.\n'
   'Replaces the fixed pip check with a volatility-adaptive check.\n'
   '0.8 = range ≥ 80% of one H1 ATR period.',
   '0.8','Keep default. Filters extreme chop while allowing normal volatility.',
   '0.7','Relax to 0.7 for slightly more trades on $100.',
   'Only in V1.3 and V1.4'),

  # ── MSS / BOS / LIQUIDITY ──────────────────────────────────────────
  ('MSS / BOS / LIQUIDITY','MSSLookbackBars','bars','—','30','30','30','30',
   'H1 bars to scan backward when detecting Market Structure Shift.\n'
   '30 H1 bars ≈ 30 hours of history.',
   '30','Keep default.',
   '30','Keep default.',
   'Not in V1.0'),

  ('MSS / BOS / LIQUIDITY','MSSConfirmBars','bars','—','3','3','3','3',
   'Bars each side to confirm an H1 swing for MSS detection.\n'
   'In V1.3+ overridden to: 2 (SmartActive), 1 (SmartActive+) by style.',
   '3','Default — overridden by TradingStyle anyway.',
   '3','Keep default.',
   'Overridden by effMSSConfirm in V1.3+'),

  ('MSS / BOS / LIQUIDITY','BOSLookbackBars','bars','—','20','20','20','20',
   'M15 bars to scan when detecting Break of Structure.\n'
   '20 M15 bars ≈ 5 hours of M15 history.',
   '20','Keep default.',
   '20','Keep default.',
   'Not in V1.0'),

  ('MSS / BOS / LIQUIDITY','LiquidityLookbackBars','bars','—','50','50','50','50',
   'M15 bars to scan for liquidity levels (swing highs/lows).\n'
   'Used to detect if price swept these levels before entry.',
   '50','Keep default.',
   '50','Keep default.',
   'Not in V1.0'),

  ('MSS / BOS / LIQUIDITY','LiquidityWickPips','pips','—','3','3','3','3',
   'Minimum wick size beyond a liquidity level to confirm a sweep.\n'
   'Wick ≥ 3 pips beyond swing level = liquidity sweep confirmed.',
   '3','Keep default 3 pips.',
   '3','Keep default.',
   'Not in V1.0'),

  # ── SYMBOL PRESET ──────────────────────────────────────────────────
  ('SYMBOL PRESET','SymbolPreset','Enum','—','PRESET_AUTO','PRESET_AUTO','PRESET_AUTO','PRESET_AUTO',
   'Pre-configured OTE and SL parameters for known symbols:\n'
   '• PRESET_AUTO: auto-detects from symbol name (recommended)\n'
   '• PRESET_XAUUSD: Gold — OTE 65-75%, MaxSL 30 pips\n'
   '• PRESET_BTCUSD: Bitcoin — OTE 62-78%, MaxSL 80 pips\n'
   '• PRESET_EURUSD: Euro — OTE 62-79%, MaxSL 25 pips\n'
   '• PRESET_GBPUSD: Pound — OTE 62-79%, MaxSL 30 pips',
   'PRESET_AUTO','Auto detects XAUUSD from symbol name.',
   'PRESET_AUTO','Keep auto.',
   'Not in V1.0'),

  # ── OPTIMIZATION MODE ──────────────────────────────────────────────
  ('OPTIMIZATION MODE','OptMode','Enum','—','OPT_BALANCED','OPT_BALANCED','OPT_BALANCED','OPT_BALANCED',
   'Secondary layer applied after TradingStyle (V1.2+) or standalone (V1.1):\n'
   '• OPT_CONSERVATIVE: score +10, risk 0.25%\n'
   '• OPT_BALANCED: no change from defaults\n'
   '• OPT_AGGRESSIVE: score -15, risk ×2',
   'OPT_CONSERVATIVE','Extra score filtering helps on $50.',
   'OPT_BALANCED','Balanced is fine for $100.',
   'Not in V1.0. In V1.2+ TradingStyle takes precedence'),

  # ── LOGGING ────────────────────────────────────────────────────────
  ('LOGGING','EnableScreenshot','bool','—','true','true','true','true',
   'Save a chart screenshot on every trade open and close.\n'
   'Files saved to MT5/MQL5/Files/ folder.',
   'true','Keep ON for trade journal.',
   'true','Keep ON.',
   'Not in V1.0'),

  ('LOGGING','EnableCSVLog','bool','—','true','true','true','true',
   'Export every trade to a CSV file.\n'
   'Columns: time, symbol, direction, entry, SL, TP, lot, score, result.',
   'true','Keep ON — CSV lets you analyze patterns.',
   'true','Keep ON.',
   'Not in V1.0'),

  # ── DEBUG / ADVANCED ───────────────────────────────────────────────
  ('DEBUG / ADVANCED','PostTradeCooldownMin','min','30','30','20','20','20',
   'Minutes to wait after closing a trade before next entry.\n'
   'Prevents back-to-back trades in the same move.\n'
   'Overridden by TradingStyle: Conservative=30, Balanced=20, SmartActive=10, SmartActive+=5.',
   '30','30 min on V1.0-V1.1; let TradingStyle control on V1.2+.',
   '20','20 min default on V1.2+.',
   'Overridden by TradingStyle in V1.2+'),

  ('DEBUG / ADVANCED','UseDailyTrendFilter','bool','true','true','true','true','true',
   'Only trade in the direction of the D1 trend.\n'
   'Uses D1 candle direction + H4 50-EMA + H4 200-EMA alignment.\n'
   'BUY requires 3/3 bullish D1 candles (FIX M). SELL requires 2/3.\n'
   'Overridden OFF by STYLE_AGGRESSIVE.',
   'true','Keep ON — trading with D1 trend is core ICT principle.',
   'true','Keep ON.',
   'Overridden to OFF by STYLE_AGGRESSIVE'),

  ('DEBUG / ADVANCED','BestHoursOnly','bool','true','true','true','true','true',
   'FIX N: Restrict trading to 08:30-15:00 GMT.\n'
   'These are the highest-quality ICT entry hours.\n'
   'Overridden to false by STYLE_SMART_ACTIVE_PLUS (V1.4) for all-session coverage.',
   'true','Keep ON for $50 — focus on best-quality hours.',
   'true','Keep ON unless using V1.4 SmartActive+.',
   'Overridden to false by STYLE_SMART_ACTIVE_PLUS in V1.4'),

  ('DEBUG / ADVANCED','ForceTrades','bool','false','false','false','false','false',
   '⚠ TESTING ONLY: bypasses ALL filters and forces trade entries.\n'
   'Used in development to verify order execution.\n'
   'NEVER set to true on live accounts or real backtests.',
   'false','ALWAYS false. Never change this on live.',
   'false','ALWAYS false.',
   '⚠ DANGER: Setting true = random trades with no logic applied'),

  ('DEBUG / ADVANCED','DebugMode','bool','false','false','false','false','false',
   'Enable verbose logging to MT5 journal.\n'
   'Prints step-by-step logic for every tick.\n'
   'Useful for diagnosing why EA is not trading.',
   'false','Keep OFF in production. Enable temporarily to diagnose issues.',
   'false','Keep OFF.',
   'Generates massive journal output — can slow Strategy Tester significantly'),

  ('DEBUG / ADVANCED','RelaxedMode','bool','false','false','false','false','false',
   'Testing mode applying relaxed parameters.\n'
   'Only for verifying setup works in Strategy Tester.\n'
   'Not recommended for real backtests or live trading.',
   'false','Always false in production.',
   'false','Always false.',
   ''),
]

# ── STYLE TABLE ─────────────────────────────────────────────────────
STYLES = [
  ('V1.0','n/a','—','—','No preset. Manual inputs only.','—','—','—','—','Default mode','—','30 min'),
  ('V1.1','n/a','—','—','No preset. Manual inputs only.','—','—','—','—','Default mode','—','30 min'),
  ('V1.2','Conservative','ON','ON','Strictest ICT — all filters strict, 1-5 trades/day','ON','ON','OFF','65-75%','score≥80','OPT_CONSERVATIVE','30 min'),
  ('V1.2','Balanced','inputs','inputs','Uses your individual input toggles, 3-8 trades/day','inputs','inputs','inputs','65-75%','score≥70','OPT_BALANCED','20 min'),
  ('V1.2','Aggressive','OFF','inputs','MSS/Trend off, wider OTE, 8-15 trades/day','OFF','OFF','OFF','55-90%','score≥50','OPT_AGGRESSIVE','10 min'),
  ('V1.2','Ultra Active','OFF','OFF','Filters minimal, max frequency, 15-25 trades/day','OFF','OFF','OFF','40-95%','score≥35','any','5 min'),
  ('V1.3','Smart Active (NEW)','ON','ON','ALL ICT ON, improved detection, 8-15 trades/day','ON','optional','ON','60-85%','score≥55','OPT_BALANCED','10 min'),
  ('V1.4','Smart Active+ (NEW)','ON','ON','ALL ICT ON, OTE 55-90%, all sessions, 15-25 trades/day','ON','optional','ON','55-90%','score≥45','OPT_BALANCED','5 min'),
]

# ═══════════════════════════════════════════════════════════════════════
# BUILD WORKBOOK
# ═══════════════════════════════════════════════════════════════════════
wb = openpyxl.Workbook()

# ── Sheet 1: README ─────────────────────────────────────────────────
ws = wb.active
ws.title = "README"
ws.sheet_properties.tabColor = "0D2137"
ws.column_dimensions['A'].width = 90

readme_lines = [
  ("ICT SMC EA — Complete Input Settings Guide", HDR, TG, True, 16),
  ("Versions: V1.0 · V1.1 · V1.2 · V1.3 · V1.4  |  Starting Capital: $50 and $100", HDR, TSL, False, 11),
  ("Created by: RATTANA CHHORM", HDR, TSL, False, 10),
  ("", HDR, TW, False, 10),
  ("HOW TO USE THIS WORKBOOK", GRP, TG, True, 12),
  ("", GRP, TW, False, 10),
  ("  Sheet: README           → This page. Overview and instructions.", ODD, TSL, False, 10),
  ("  Sheet: Style Guide      → TradingStyle preset comparison table.", ODD, TSL, False, 10),
  ("  Sheet: All Settings     → Full parameter reference — all versions side by side.", ODD, TSL, False, 10),
  ("  Sheet: $50 Quick Start  → Recommended settings for $50 starting capital.", ODD, TSL, False, 10),
  ("  Sheet: $100 Quick Start → Recommended settings for $100 starting capital.", ODD, TSL, False, 10),
  ("", ODD, TW, False, 10),
  ("ACCOUNT SIZE NOTES", GRP, TG, True, 12),
  ("", GRP, TW, False, 10),
  ("  $50 Account:", ODD, TB, True, 10),
  ("    • Use RiskMode = RISK_FIXED_LOT with FixedLot = 0.01 (minimum lot)", ODD, TSL, False, 10),
  ("    • MaxLotLimit = 0.01 — hard cap at minimum lot", ODD, TSL, False, 10),
  ("    • MaxDailyLossPercent = 6.0  ($3 max daily loss)", ODD, TSL, False, 10),
  ("    • MaxDailyLossTrades = 2  (stop after 2 losing trades per day)", ODD, TSL, False, 10),
  ("    • MaxTradesPerDay = 5  (conservative frequency)", ODD, TSL, False, 10),
  ("    • TradingStyle = STYLE_CONSERVATIVE  (V1.2+)", ODD, TSL, False, 10),
  ("    • MaxSLPips = 20, MinH1RangePips = 30", ODD, TSL, False, 10),
  ("    • XAUUSD: 0.01 lot × 20 pip SL ≈ $0.20 loss per trade (0.4% of $50)", ODD, TSL, False, 10),
  ("", EVN, TW, False, 10),
  ("  $100 Account:", EVN, TGR, True, 10),
  ("    • Use RiskMode = RISK_FIXED_PCT with RiskPercent = 1.0%  ($1 risk per trade)", EVN, TSL, False, 10),
  ("    • MaxLotLimit = 0.02", EVN, TSL, False, 10),
  ("    • MaxDailyLossPercent = 6.0  ($6 max daily loss)", EVN, TSL, False, 10),
  ("    • MaxDailyLossTrades = 3", EVN, TSL, False, 10),
  ("    • MaxTradesPerDay = 10  (balanced frequency)", EVN, TSL, False, 10),
  ("    • TradingStyle = STYLE_BALANCED  (V1.2+)", EVN, TSL, False, 10),
  ("    • MaxSLPips = 25, MinH1RangePips = 40", EVN, TSL, False, 10),
  ("", ODD, TW, False, 10),
  ("TRADING STYLE SUMMARY (V1.2+)", GRP, TG, True, 12),
  ("", GRP, TW, False, 10),
  ("  STYLE_CONSERVATIVE : score≥80 · OTE 65-75% · all ICT ON · CD 30min · 1-5 trades/day", ODD, TSL, False, 10),
  ("  STYLE_BALANCED     : score≥70 · OTE 65-75% · uses input toggles · CD 20min · 3-8 trades/day", ODD, TSL, False, 10),
  ("  STYLE_AGGRESSIVE   : score≥50 · OTE 55-90% · MSS/Trend OFF · CD 10min · 8-15 trades/day", EVN, TSL, False, 10),
  ("  STYLE_SMART_ACTIVE : score≥55 · OTE 60-85% · all ICT ON · CD 10min · 8-15 trades/day (V1.3+)", EVN, TGR, False, 10),
  ("  STYLE_SMART_ACTIVE+: score≥45 · OTE 55-90% · all ICT ON · CD 5min · 15-25 trades/day (V1.4)", ODD, TB, False, 10),
  ("  STYLE_ULTRA_ACTIVE : score≥35 · OTE 40-95% · filters minimal · CD 5min (V1.3+)", ODD, TSL, False, 10),
  ("", ODD, TW, False, 10),
  ("RECOMMENDED VERSIONS", GRP, TG, True, 12),
  ("", GRP, TW, False, 10),
  ("  V1.0 → Base model. Only for reference — use V1.1+ for live.", ODD, TSL, False, 10),
  ("  V1.1 → Stable with MSS/BOS/Score/PartialTP. Good for conservative testing.", ODD, TSL, False, 10),
  ("  V1.2 → Adds TradingStyle presets and rejection statistics.", ODD, TSL, False, 10),
  ("  V1.3 → Improved detection algorithms. Use STYLE_SMART_ACTIVE for 8-15 trades/day.", ODD, TGR, False, 10),
  ("  V1.4 → Use STYLE_SMART_ACTIVE_PLUS for 15-25 trades/day with all ICT logic intact.", TB, TB, True, 10),
]

for i, (text, bg, fc, bold, sz) in enumerate(readme_lines, 1):
    cell = ws.cell(row=i, column=1, value=text)
    cell.fill = f(bg); cell.font = fn(fc, bold, sz)
    cell.alignment = al('left', 'center', False)
    ws.row_dimensions[i].height = 18

print("README sheet done.")

# ── Sheet 2: Style Guide ─────────────────────────────────────────────
ws2 = wb.create_sheet("Style Guide")
ws2.sheet_properties.tabColor = "1A3A1A"

SGCOLS = ['Version','Style','MSS','BOS','Trend','Liq Sweep','H1 Range','OTE Window','Min Score','Cooldown','Target Trades/Day']
SGWIDTHS = [8,22,7,7,7,12,10,14,10,12,18]
for i,(h,w) in enumerate(zip(SGCOLS,SGWIDTHS),1):
    ws2.column_dimensions[get_column_letter(i)].width = w
    wc(ws2,1,i,h,HDR,TG,True,11,'center')
ws2.row_dimensions[1].height = 22

SGDATA = [
  ('V1.0','(no preset)','Manual','Manual','Manual','Manual','Manual','65-75%','70','30 min','~1-5/day'),
  ('V1.1','(no preset)','Manual','Manual','Manual','Manual','Manual','65-75%','70','30 min','~1-5/day'),
  ('V1.2','Conservative','ON','ON','ON','Manual','ON','65-75%','80','30 min','1-5/day'),
  ('V1.2','Balanced','Input','Input','Input','Input','Input','65-75%','70','20 min','3-8/day'),
  ('V1.2','Aggressive','OFF','Input','OFF','OFF','Input','55-90%','50','10 min','8-15/day'),
  ('V1.2','Ultra Active','OFF','OFF','OFF','OFF','OFF','40-95%','35','5 min','15-25/day'),
  ('V1.3','Conservative','ON','ON','ON','Manual','ON','65-75%','80','30 min','1-5/day'),
  ('V1.3','Balanced','Input','Input','Input','Input','Input','65-75%','70','20 min','3-8/day'),
  ('V1.3','Aggressive','OFF','Input','OFF','OFF','Input','55-90%','50','10 min','8-15/day'),
  ('V1.3','Smart Active ★','ON','ON','ON','Optional','ATR-adaptive','60-85%','55','10 min','8-15/day'),
  ('V1.3','Ultra Active','OFF','OFF','OFF','OFF','OFF','40-95%','35','5 min','15-25/day'),
  ('V1.4','Conservative','ON','ON','ON','Manual','ON','65-75%','80','30 min','1-5/day'),
  ('V1.4','Balanced','Input','Input','Input','Input','Input','65-75%','70','20 min','3-8/day'),
  ('V1.4','Aggressive','OFF','Input','OFF','OFF','Input','55-90%','50','10 min','8-15/day'),
  ('V1.4','Smart Active ★','ON','ON','ON','Optional','ATR-adaptive','60-85%','55','10 min','8-15/day'),
  ('V1.4','Smart Active+ ★★','ON','ON','ON','Optional','ATR-adaptive','55-90%','45','5 min','15-25/day'),
  ('V1.4','Ultra Active','OFF','OFF','OFF','OFF','OFF','40-95%','35','5 min','15-25/day'),
]
for r, row in enumerate(SGDATA, 2):
    ver = row[0]; style = row[1]
    if '★★' in style: bg = '0A1A2A'
    elif '★' in style: bg = '0A2A0A'
    elif 'Ultra' in style: bg = '2A0A0A'
    elif 'Conservative' in style: bg = '1A1A2A'
    else: bg = ODD if r%2==0 else EVN
    for c, val in enumerate(row, 1):
        fc_ = TG if c==1 else (TGR if '★' in style else (TR if 'Ultra' in style else TSL))
        if c in (3,4,5,6,7):
            fc_ = TGR if val=='ON' else (TR if val=='OFF' else TOR)
        wc(ws2, r, c, val, bg, fc_, bold=('★' in style), h='center')
    ws2.row_dimensions[r].height = 18

# footer note
note_r = len(SGDATA)+3
wc(ws2, note_r, 1,
   '★ Smart Active = All ICT filters ON, better detection algorithms  |  ★★ Smart Active+ = All ICT ON + expanded sessions + OTE 55-90%',
   GRP, TB, False, 9, 'left', False, 10)
print("Style Guide sheet done.")

# ── Sheet 3: All Settings ────────────────────────────────────────────
ws3 = wb.create_sheet("All Settings")
ws3.sheet_properties.tabColor = "0D2137"

COL_WIDTHS3 = [20, 22, 8, 9, 9, 9, 9, 9, 50, 22, 22, 35]
COL_HDRS3   = ['Group','Parameter','Type','V1.0 Default','V1.1 Default','V1.2 Default','V1.3 Default','V1.4 Default',
               'What It Does','$50 Recommended','$100 Recommended','Notes / Warning']
for i,(h,w) in enumerate(zip(COL_HDRS3,COL_WIDTHS3),1):
    ws3.column_dimensions[get_column_letter(i)].width = w
    wc(ws3,1,i,h,HDR,TG,True,11,'center')
ws3.row_dimensions[1].height = 22
ws3.freeze_panes = 'A2'

cur_grp = None
r = 2
for row in P:
    grp,name,typ,v10,v11,v12,v13,v14,what,f50,fn50,f100,fn100,warn = row
    if grp != cur_grp:
        for c in range(1,13):
            wc(ws3, r, c, grp if c==1 else '', GRP, TG, True, 10, 'left')
        ws3.row_dimensions[r].height = 18
        r += 1
        cur_grp = grp

    is_new = (v10=='—' and v11=='—' and v12=='—') or (v10=='—' and v11=='—' and v12!='—' and v13 not in ('—','') and v14 not in ('—',''))
    is_v14 = (v13=='—' or (v10=='—' and v11=='—' and v12=='—' and v13=='—'))
    row_bg = NEW if (v10=='—' and v11=='—' and v12=='—' and v13!='—') else (WARN if '⚠' in warn else (ODD if r%2==0 else EVN))

    wc(ws3,r,1,grp,row_bg,TSL,False,9)
    wc(ws3,r,2,name,row_bg,TW,True,10)
    wc(ws3,r,3,typ,row_bg,TSL,False,9,'center')
    for c_,val in zip(range(4,9),[v10,v11,v12,v13,v14]):
        fc_ = TR if val=='—' else (TGR if val not in ('—','false','0','0.0') else TSL)
        wc(ws3,r,c_,val,row_bg,fc_,False,9,'center')
    wc(ws3,r,9,what,row_bg,TSL,False,9)
    wc(ws3,r,10,f50,C50,TG,False,9)
    wc(ws3,r,11,f100,C100,TGR,False,9)
    wc(ws3,r,12,warn if warn else '—',WARN if warn and '⚠' in warn else row_bg, TR if warn and '⚠' in warn else TSL,False,9)
    ws3.row_dimensions[r].height = 60
    r += 1

print(f"All Settings sheet done. {r-2} parameter rows.")

# ── Sheet 4: $50 Quick Start ─────────────────────────────────────────
def build_account_sheet(wb, title, tab_color, account, amount):
    ws = wb.create_sheet(title)
    ws.sheet_properties.tabColor = tab_color
    col_w = [20, 22, 8, 14, 14, 14, 14, 14, 50, 26, 40]
    col_h = ['Group','Parameter','Type','V1.0','V1.1','V1.2','V1.3','V1.4','What It Does',
             f'Recommended ({account})','Why This Setting']
    for i,(h,w) in enumerate(zip(col_h,col_w),1):
        ws.column_dimensions[get_column_letter(i)].width = w
        wc(ws,1,i,h,HDR,TG,True,11,'center')
    ws.row_dimensions[1].height = 22
    ws.freeze_panes = 'A2'

    # account intro
    ws.merge_cells('A2:K2')
    intro = (f"$50 Account Settings  |  Risk: Fixed 0.01 lot  |  Max daily loss: $3 (6%)  |  Style: CONSERVATIVE (V1.2+)  |  Max trades/day: 5" if amount==50
             else f"$100 Account Settings  |  Risk: 1% per trade (~$1)  |  Max daily loss: $6 (6%)  |  Style: BALANCED (V1.2+)  |  Max trades/day: 10")
    wc(ws,2,1,intro,C50H if amount==50 else C100H, TG,True,11,'center',False,10)
    ws.row_dimensions[2].height = 22

    rec_col = 'f50' if amount==50 else 'f100'
    note_col = 'fn50' if amount==50 else 'fn100'

    cur_grp = None
    r = 3
    for row in P:
        grp,name,typ,v10,v11,v12,v13,v14,what,f50_,fn50_,f100_,fn100_,warn = row
        rec = f50_ if amount==50 else f100_
        note = fn50_ if amount==50 else fn100_

        if grp != cur_grp:
            for c in range(1,12):
                wc(ws, r, c, grp if c==1 else '', GRP, TG, True, 10)
            ws.row_dimensions[r].height = 18
            r += 1
            cur_grp = grp

        row_bg = WARN if '⚠' in warn else (ODD if r%2==0 else EVN)
        wc(ws,r,1,grp,row_bg,TSL,False,9)
        wc(ws,r,2,name,row_bg,TW,True,10)
        wc(ws,r,3,typ,row_bg,TSL,False,9,'center')
        for c_,val in zip(range(4,9),[v10,v11,v12,v13,v14]):
            fc_ = TR if val=='—' else TSL
            wc(ws,r,c_,val,row_bg,fc_,False,9,'center')
        wc(ws,r,9,what,row_bg,TSL,False,9)
        rc_bg = C50H if amount==50 else C100H
        rc_fc = TG if amount==50 else TGR
        wc(ws,r,10,rec,rc_bg,rc_fc,True,10,'center')
        wc(ws,r,11,note,row_bg,TSL,False,9)
        ws.row_dimensions[r].height = 55
        r += 1
    print(f"{title} sheet done.")

build_account_sheet(wb, "$50 Quick Start", "252500", "$50", 50)
build_account_sheet(wb, "$100 Quick Start", "002500", "$100", 100)

# ── Sheet 5: Version Comparison (side-by-side key params) ───────────
ws5 = wb.create_sheet("Version Comparison")
ws5.sheet_properties.tabColor = "16213E"

vc_params = [
  ('Version','V1.0','V1.1','V1.2','V1.3','V1.4'),
  ('EA Name','ICT SMC EA V1.0','ICT SMC EA V1.1','ICT SMC EA V1.2','ICT SMC EA V1.3','ICT SMC EA V1.4'),
  ('TradingStyle Presets','None','None','4 styles','5 styles','6 styles'),
  ('MSS Filter','No','Yes','Yes (style)','Yes (style)','Yes (style)'),
  ('BOS Filter','No','Yes','Yes (style)','Yes (style)','Yes (style)'),
  ('Liquidity Sweep','No','Optional','Optional','Optional','Optional'),
  ('Trade Quality Score','No','Yes (score≥70)','Yes (toggle)','Yes (toggle)','Yes (toggle)'),
  ('Partial Take Profit','No','Yes','Yes','Yes','Yes'),
  ('TP Mode Selection','No','Yes','Yes','Yes','Yes'),
  ('Auto GMT Detection','No','Yes','Yes','Yes','Yes'),
  ('Symbol Presets','No','Yes','Yes','Yes','Yes'),
  ('CSV + Screenshot Log','No','Yes','Yes','Yes','Yes'),
  ('News Filter','No','Yes','Yes','Yes','Yes'),
  ('Filter Rejection Stats','No','No','Yes (daily)','Yes (daily+cumul)','Yes (daily+cumul)'),
  ('PrintFilterSummary','No','No','No','Yes (deinit)','Yes (deinit)'),
  ('ATR-Adaptive H1 Range','No','No','No','Yes (SmartActive)','Yes (SmartActive+)'),
  ('Improved MSS (1-2 bar)','No','No','No','Yes (SmartActive)','Yes (SmartActive+)'),
  ('Pin Bar + 3-Bar Trigger','No','No','No','Yes','Yes'),
  ('OTE Default Window','65-75%','65-75%','65-75%','65-75% (SA: 60-85%)','65-75% (SA+: 55-90%)'),
  ('Default Style','-','-','BALANCED','SMART_ACTIVE','SMART_ACTIVE'),
  ('Target Trades/Day (def)','1-5','1-5','3-8','8-15','8-15'),
  ('Cooldown Default','30 min','30 min','20 min','20 min (SA:10)','20 min (SA+:5)'),
  ('Magic Number','888777','888777','888777','888777','888777'),
  ('Recommended Use','Reference only','Conservative test','Balanced live','Smart active live','Max frequency live'),
]

vc_widths = [28,22,22,22,22,22]
for i,w in enumerate(vc_widths,1):
    ws5.column_dimensions[get_column_letter(i)].width = w

for r, row in enumerate(vc_params,1):
    is_header = r == 1
    for c, val in enumerate(row,1):
        if is_header:
            bg_ = HDR; fc_ = TG; bold_ = True; sz_ = 11
        elif r % 2 == 0:
            bg_ = ODD; fc_ = TW if c==1 else TSL; bold_ = c==1; sz_ = 10
        else:
            bg_ = EVN; fc_ = TW if c==1 else TSL; bold_ = c==1; sz_ = 10
        # highlight V1.3/V1.4 new features
        if c in (4,5) and 'Yes' in str(val) and r > 1:
            if vc_params[r-1][c-2] in ('No','—','-',''):
                bg_ = NEW; fc_ = TGR
        wc(ws5, r, c, val, bg_, fc_, bold_, sz_, 'center' if c>1 else 'left')
    ws5.row_dimensions[r].height = 20

print("Version Comparison sheet done.")

# ── Save ─────────────────────────────────────────────────────────────
wb.save(OUT)
print(f"\nSaved: {OUT}")
