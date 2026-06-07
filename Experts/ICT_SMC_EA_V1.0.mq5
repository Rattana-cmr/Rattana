//+------------------------------------------------------------------+
//|                                         ICT SMC EA V1.0           |
//|               ICT SMART MONEY CONCEPTS - FULL MODEL              |
//|                DUAL TIMEFRAME SWING DETECTION (H1 + M15)         |
//|              BASED ON ICT TWINS MODEL - PRODUCTION BUILD          |
//|                           Created By - RATTANA CHHORM            |
//+------------------------------------------------------------------+
//
// CHANGELOG V1.0 BACKTEST FIX PATCH
// -----------------------------------------------------------------------
// ROOT CAUSE ANALYSIS from 2nd backtest log (56 trades, -4.5% net, PF=0.94):
//   LOG BUG 1 — "Invalid stops" retry loop (March 13):
//     Trade #90 SELL: SL=0.51 price, TP=1.02 price. TP was inside the broker
//     freeze level. EA retried 30+ times/sec until TP drifted out. This also
//     produced 0.1 lot (tiny SL → huge position to meet 0.5% risk).
//   LOG BUG 2 — SKIP:R:R=2.00<min2.00 spam (99 occurrences):
//     Float comparison 2.0 < 2.0 sometimes true → needless SKIP + re-entry.
//   LOG BUG 3 — Failed order does not reset CISD:
//     When trade.Sell() returns false, cisd1MinConfirmed stays true → next
//     tick calls PlaceTrade again → same "Invalid stops" failure → loop.
//
// FIX Q: MinSLPips = 10 pips input added. PlaceTrade skips if SL distance
//         < MinSLPips pips. Eliminates tiny-SL trades that live inside spread.
// FIX R: R:R check tolerance added (−0.001): actualRR < minRR−0.001 instead
//         of strict <. Eliminates the 99 false SKIP prints from fp rounding.
// FIX S: On ANY trade.Buy/Sell failure, cisd1MinConfirmed is immediately
//         reset to false. Breaks the retry loop dead on first failure.
// FIX T: MaxDailyLossTradesInput added (default 3). After N losing trades
//         on same calendar day, EA stops new entries until midnight reset.
//         Prevents the March 25 cluster of 3 consecutive SL hits.
// FIX U: HTFLevelRequired=false (default). Step 1 now auto-passes when false,
//         which is the ROOT CAUSE fix for "EA doesn't trade at all". In trending
//         gold markets price moves away from all reference levels (M15 FVGs are
//         rare, prev bar H/L and D1 H/L checks all fail simultaneously). Added
//         H1/H4 prev-bar high-low as additional reference levels when enabled.
//         HTFToleranceATRMulti default raised 1→2 for wider detection range.
// -----------------------------------------------------------------------
// ROOT CAUSE ANALYSIS from 1st backtest (47 trades, -13.4% net, PF=0.81):
//   - Actual R:R delivered = 1.19 (avg win $29.35 / avg loss $24.70)
//     vs target 2.0 → trades reversing before hitting TP
//   - BUY bias: 34/47 trades = 72% BUY with only 38% WR vs SELL 46% WR
//   - Profit factor 0.81 → needs higher win rate OR better R:R delivery
//
// FIX J: OTE zone tightened 62-79% → 65-75% (cleaner entries near sweet
//         spot, fewer false touches at zone edges that reverse quickly)
// FIX K: 1M momentum threshold raised 55%→65% (stronger trigger required,
//         eliminates weak 1M signals that lead to low R:R trades)
// FIX M: D1 trend filter for BUY strengthened: require 3/3 bullish D1
//         candles for BUY vs 2/3 previously. SELL keeps 2/3 standard.
//         This directly addresses BUY overtrade bias (72% → target 50%)
// FIX N: London open delay added (BestHoursOnly now starts 08:30 not
//         08:00). First 30 min of London = news/manipulation spike noise.
// FIX O: MaxSLPips default tightened 50→30 pips. Limits max loss per
//         trade, improves actual R:R when swing-based SL is too wide.
// FIX P: Friday session cut-off added (14:00 GMT). Avoids late-NY Friday
//         entries that hit weekend gap risk. Entries by weekdays chart
//         showed Friday had most entries (13) with poor R:R delivery.
// -----------------------------------------------------------------------
// PREVIOUS CHANGELOG (V10.1 → V1.0):
// BUY WIN RATE FIX - OTE zone split into BUY zone (lower 35%) and SELL
//   zone (upper 35%). Middle zone is no-trade zone.
// H4 50-EMA added to D1 trend filter (multi-timeframe confirmation).
// RewardRiskRatio raised 1.5→2.0.
// UseBreakeven default OFF (was stealing R:R).
// MinRewardRiskRatio raised to 2.0.
// D1 trend filter - only take trades aligned with daily candle direction.
// BestHoursOnly - restrict to 08:00-15:00 GMT.
// PostTradeCooldown reduced 60→30 min.
// 5M momentum threshold raised 60%→70%.
// CISD replaced with momentum candle detection.
// FVG filter optional (MinFVGsRequired=0 disables).
// Previous day high/low as additional HTF reference levels.
// State machine redesign - Steps 1-5 accumulate context persistently.
// PipFactor auto-detection corrected for XAUUSD 2-digit symbols.
// Statistics tracking with GlobalVariable persistence.
// Draggable dashboard panel.
// -----------------------------------------------------------------------

#property copyright "RATTANA CHHORM"
#property version   "1.0"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//===================== CONSTANTS =====================//
const int    MAGIC_NUMBER = 888777;
const string EA_NAME      = "ICT SMC EA V1.0";

//===================== RISK MANAGEMENT =====================//
input group "========== RISK MANAGEMENT =========="
input double   RiskPercent          = 0.5;    // Risk per trade (%)
input double   FixedLot             = 0.0;    // Fixed lot size (0 = use risk%)
input double   MaxDailyLossPercent  = 10.0;   // Max daily loss (%) - TWINS trades only
input int      MaxTradesPerDay      = 10;     // Max trades per day
input double   RewardRiskRatio      = 2.0;    // Reward/Risk ratio
input double   MaxLotLimit          = 0.10;   // Hard lot ceiling (scale with account)
input double   MinRewardRiskRatio   = 2.0;    // Minimum R:R before placing trade

//===================== TRADE FILTERS =====================//
input group "========== TRADE FILTERS =========="
input bool     UseTimeFilter        = true;   // Use trading hours
input int      MaxSpreadPoints      = 50;     // Max spread (0 = disable)
input int      MinStopDistance      = 20;     // Min SL distance in points
input int      MaxConsecutiveLosses = 10;     // Halt after N consecutive losses (lifetime)
input int      MaxDailyLossTrades   = 3;      // FIX T: Max losing trades per day (0=disabled)
input bool     ResetLossStreakDaily = true;   // Reset streak daily (true) or lifetime (false)

//===================== SESSION CONTROLS =====================//
input group "========== SESSIONS (GMT TIME) =========="
input int      BrokerGMTOffset      = 0;      // Broker GMT offset (e.g. 2 for GMT+2)
input bool     SessionSydney        = false;  // Sydney (22:00-07:00 GMT)
input bool     SessionTokyo         = false;  // Tokyo  (00:00-09:00 GMT)
input bool     SessionLondon        = true;   // London (08:00-17:00 GMT)
input bool     SessionNewYork       = true;   // New York (13:00-22:00 GMT)
input bool     OverlapLondonNY      = true;   // London+NY Overlap (13:00-17:00 GMT) BEST
input bool     OverlapTokyoLondon   = false;  // Tokyo+London Overlap (08:00-09:00 GMT)

//===================== STOP LOSS & TRAILING =====================//
input group "========== STOP LOSS =========="
input int      SLBufferPips         = 15;     // SL buffer in pips behind swing
input bool     UseTrailingStop      = false;  // Enable trailing stop
input int      TrailingStartPips    = 30;     // Start trailing after N pips profit
input int      TrailingStepPips     = 10;     // Trail by N pips

//===================== POSITION MANAGEMENT =====================//
input group "========== POSITION MANAGEMENT =========="
input bool     CloseOnFriday        = true;   // FIX P: Close positions on Friday (default ON)
input int      FridayCloseHour      = 14;     // FIX P: Friday close at 14:00 GMT (was 20)
input bool     UseBreakeven         = false;  // Move SL to breakeven
input int      BreakevenTriggerPips = 40;     // Pips profit to trigger breakeven

//===================== SWING DETECTION =====================//
input group "========== SWING DETECTION =========="
input int      SwingLookbackBarsH1  = 50;     // H1 bars to scan (OTE)
input int      SwingConfirmBarsH1   = 3;      // Bars each side to confirm H1 swing
input int      SwingLookbackBarsM15 = 30;     // M15 bars to scan (SL)
input int      SwingConfirmBarsM15  = 5;      // Bars each side to confirm M15 swing
input int      MaxSwingDistancePips = 500;    // Max swing distance in pips (0=disabled)
input int      MaxSLPips            = 30;     // FIX O: Max SL in pips (was 50, now 30)
input int      MinSLPips            = 10;     // FIX Q: Min SL in pips - skips tiny-SL trades (0=disabled)
input bool     ShowSwingLines       = true;   // Draw M15 swing SL lines

//===================== ICT TWINS MODEL =====================//
input group "========== ICT TWINS MODEL =========="
input bool     UseTwinsModel        = true;   // Enable full ICT TWINS model
input int      HTFLevelMinutes      = 15;     // HTF timeframe (15, 30, 60)
input double   OTEMinPercent        = 0.65;   // FIX J: OTE minimum (was 0.62, now 0.65)
input double   OTEMaxPercent        = 0.75;   // FIX J: OTE maximum (was 0.79, now 0.75)
input double   OTESweetSpotPercent  = 0.705;  // OTE sweet spot (70.5%)
input int      MinFVGsRequired      = 0;      // Min 1-min FVGs required (0=disabled)
input int      HTFToleranceATRMulti = 2;      // HTF tolerance = N x ATR(14)
input bool     HTFLevelRequired     = false;  // FIX U: Require HTF key level (false=auto-pass Step 1)
input bool     ShowOTEZone          = true;   // Draw OTE zone on chart
input int      MinH1RangePips       = 50;     // Min H1 swing range in pips (0=disabled)

//===================== DEBUG =====================//
input group "========== DEBUG =========="
input int      PostTradeCooldownMin = 30;     // Minutes to wait after trade
input bool     UseDailyTrendFilter  = true;   // Only trade in D1 trend direction
input bool     BestHoursOnly        = true;   // FIX N: Trade 08:30-15:00 GMT (was 08:00)
input bool     ForceTrades          = false;  // NEVER true on live accounts
input bool     DebugMode            = false;  // Verbose logging
input bool     RelaxedMode          = false;  // Relaxed testing (MinFVGs=1, wider OTE)

//===================== GLOBAL VARIABLES =====================//
int      ATRHandle        = INVALID_HANDLE;
int      FastEMAHandle    = INVALID_HANDLE;
int      SlowEMAHandle    = INVALID_HANDLE;

datetime LastBarTime      = 0;
datetime LastTradeCloseTime = 0;
int      TodayTradeCount  = 0;
int      TodayLossTrades  = 0;   // FIX T: losing trade count for current day
int      LastTradeDay     = 0;
double   TodayLoss        = 0;
int      consecutiveLosses = 0;
double   PipFactor        = 10.0;
datetime LastDisplayUpdate = 0;

// ICT TWINS state
datetime LastCISDTime5Min  = 0;
datetime LastCISDTime1Min  = 0;
double   lastSwingHighH1   = 0;
double   lastSwingLowH1    = 0;
double   lastSwingHighM15  = 0;
double   lastSwingLowM15   = 0;
int      fvgCount1Min      = -1;
bool     htfLevelReached   = false;
bool     cisd5MinConfirmed = false;
bool     cisd1MinConfirmed = false;
bool     cisd5MinIsBearish = false;
bool     cisd1MinIsBearish = false;

// Statistics
int    statTotalTrades  = 0;
int    statWins         = 0;
int    statLosses       = 0;
double statTotalProfit  = 0.0;
double statTotalLoss    = 0.0;
double statSumRR        = 0.0;

int    consecutiveWins  = 0;

// Drawdown tracking
double sessionStartEquity  = 0;
double sessionMaxDrawdown  = 0;
double sessionPeakEquity   = 0;

// Last failed step
int    lastFailedStep      = 0;
string lastFailedStepDesc  = "";

// OTE redraw guard
double lastOTEHigh = 0;
double lastOTELow  = 0;

// Rolling swing line names
string   SwingLineNames[];
int      SwingLineIndex  = 0;
int      MaxSwingLines   = 10;

// OTE zone object names
string   OTEObjectNames[4];

// ── DRAGGABLE DASHBOARD ──────────────────────────────────────────
string   PANEL_PREFIX    = "ICTSMC_";
int      PANEL_X         = 10;
int      PANEL_Y         = 30;
int      PANEL_W         = 280;
int      PANEL_LINE_H    = 16;
color    PANEL_BG        = C'20,20,28';
color    PANEL_BORDER    = C'60,60,80';
color    PANEL_HDR_BG    = C'30,30,50';
color    PANEL_TXT       = clrSilver;
color    PANEL_GREEN     = clrLimeGreen;
color    PANEL_RED       = C'255,80,80';
color    PANEL_GOLD      = clrGold;
color    PANEL_BLUE      = C'100,160,255';
bool     panelDragging   = false;
bool     panelHidden     = false;
int      dragOffsetX     = 0;
int      dragOffsetY     = 0;
int      panelTotalLines = 0;

//+------------------------------------------------------------------+
//| DEBUG PRINT HELPER                                               |
//+------------------------------------------------------------------+
void DebugPrint(string msg)
{
   if(DebugMode) Print("[DEBUG] ", msg);
}

//+------------------------------------------------------------------+
//| INITIALIZATION                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ATRHandle     = iATR(_Symbol, PERIOD_M15, 14);
   FastEMAHandle = iMA(_Symbol, PERIOD_H1, 50,  0, MODE_EMA, PRICE_CLOSE);
   SlowEMAHandle = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);

   if(ATRHandle     == INVALID_HANDLE ||
      FastEMAHandle == INVALID_HANDLE ||
      SlowEMAHandle == INVALID_HANDLE)
   {
      Alert(EA_NAME + ": Indicator handle creation failed. EA stopped.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(MAGIC_NUMBER);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(_Digits == 5 || _Digits == 3)
      PipFactor = 10.0;
   else if(_Digits == 2)
      PipFactor = 100.0;
   else
      PipFactor = 1.0;

   ArrayResize(SwingLineNames, MaxSwingLines);
   for(int i = 0; i < MaxSwingLines; i++) SwingLineNames[i] = "";
   for(int i = 0; i < 4; i++) OTEObjectNames[i] = "";

   Print("========================================");
   Print(EA_NAME, " - ICT SMART MONEY CONCEPTS EA");
   Print("Symbol: ", _Symbol, " | Digits: ", _Digits, " | PipFactor: ", PipFactor);
   Print("BrokerGMTOffset: ", BrokerGMTOffset);
   Print("HTF: ", HTFLevelMinutes, "min | OTE: ", OTEMinPercent*100, "%-", OTEMaxPercent*100, "%");
   Print("MaxSLPips: ", MaxSLPips, " | FIX O applied");
   Print("FIX J: OTE zone tightened to 65-75%");
   Print("FIX K: 1M trigger threshold raised to 65%");
   Print("FIX M: BUY requires 3/3 bullish D1 candles");
   Print("FIX N: London delay 08:30 GMT start");
   Print("FIX P: Friday cut-off at ", FridayCloseHour, ":00 GMT");
   Print("FIX U: HTFLevelRequired=", HTFLevelRequired ? "ON (strict)" : "OFF (Step 1 auto-pass)");
   if(ForceTrades) Print("*** WARNING: ForceTrades=ON - testing only! ***");
   if(RelaxedMode) Print("*** RELAXED MODE ON - testing only! ***");
   Print("========================================");

   // Restore persisted statistics
   string pfx = EA_NAME + "_" + _Symbol + "_";
   if(GlobalVariableCheck(pfx+"Trades"))  statTotalTrades = (int)GlobalVariableGet(pfx+"Trades");
   if(GlobalVariableCheck(pfx+"Wins"))    statWins        = (int)GlobalVariableGet(pfx+"Wins");
   if(GlobalVariableCheck(pfx+"Losses"))  statLosses      = (int)GlobalVariableGet(pfx+"Losses");
   if(GlobalVariableCheck(pfx+"Profit"))  statTotalProfit = GlobalVariableGet(pfx+"Profit");
   if(GlobalVariableCheck(pfx+"Loss"))    statTotalLoss   = GlobalVariableGet(pfx+"Loss");
   if(GlobalVariableCheck(pfx+"SumRR"))   statSumRR       = GlobalVariableGet(pfx+"SumRR");
   Print("Statistics restored: Trades=", statTotalTrades, " Wins=", statWins, " Losses=", statLosses);

   sessionStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   sessionPeakEquity  = sessionStartEquity;

   PanelLoadPosition();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINITIALIZATION                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ATRHandle     != INVALID_HANDLE) IndicatorRelease(ATRHandle);
   if(FastEMAHandle != INVALID_HANDLE) IndicatorRelease(FastEMAHandle);
   if(SlowEMAHandle != INVALID_HANDLE) IndicatorRelease(SlowEMAHandle);

   for(int i = 0; i < MaxSwingLines; i++)
      if(SwingLineNames[i] != "") ObjectDelete(0, SwingLineNames[i]);

   for(int i = 0; i < 4; i++)
      if(OTEObjectNames[i] != "") ObjectDelete(0, OTEObjectNames[i]);

   string pfx = EA_NAME + "_" + _Symbol + "_";
   GlobalVariableSet(pfx+"Trades",  statTotalTrades);
   GlobalVariableSet(pfx+"Wins",    statWins);
   GlobalVariableSet(pfx+"Losses",  statLosses);
   GlobalVariableSet(pfx+"Profit",  statTotalProfit);
   GlobalVariableSet(pfx+"Loss",    statTotalLoss);
   GlobalVariableSet(pfx+"SumRR",   statSumRR);

   PanelDeleteAll();
   ObjectsDeleteAll(0, "Twins_");
   Comment("");
}

//+------------------------------------------------------------------+
//| OnTrade - win/loss tracking via POSITION_ID                     |
//+------------------------------------------------------------------+
void OnTrade()
{
   if(!HistorySelect(TimeCurrent() - 86400, TimeCurrent())) return;

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL)       != _Symbol)      continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC)       != MAGIC_NUMBER) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY)       != DEAL_ENTRY_OUT) continue;

      static ulong lastProcessed = 0;
      if(ticket == lastProcessed) break;
      lastProcessed = ticket;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);

      statTotalTrades++;
      statTotalProfit += (profit > 0) ? profit : 0;
      statTotalLoss   += (profit < 0) ? MathAbs(profit) : 0;

      ulong posID  = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      string rrKey = "TWINS_RR_" + IntegerToString(posID);

      if(profit > 0)
      {
         statWins++;
         consecutiveLosses = 0;
         consecutiveWins++;
         if(GlobalVariableCheck(rrKey))
         {
            statSumRR += GlobalVariableGet(rrKey);
            GlobalVariableDel(rrKey);
         }
      }
      else if(profit < 0)
      {
         statLosses++;
         consecutiveLosses++;
         consecutiveWins = 0;
         TodayLossTrades++;   // FIX T: count losing trades today
         if(GlobalVariableCheck(rrKey)) GlobalVariableDel(rrKey);
      }

      LastTradeCloseTime = TimeCurrent();
      cisd5MinConfirmed  = false;
      cisd1MinConfirmed  = false;
      htfLevelReached    = false;
      fvgCount1Min       = -1;

      double curEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(curEquity > sessionPeakEquity) sessionPeakEquity = curEquity;
      double dd = sessionPeakEquity - curEquity;
      if(dd > sessionMaxDrawdown) sessionMaxDrawdown = dd;

      string pfx = EA_NAME + "_" + _Symbol + "_";
      GlobalVariableSet(pfx+"Trades",  statTotalTrades);
      GlobalVariableSet(pfx+"Wins",    statWins);
      GlobalVariableSet(pfx+"Losses",  statLosses);
      GlobalVariableSet(pfx+"Profit",  statTotalProfit);
      GlobalVariableSet(pfx+"Loss",    statTotalLoss);
      GlobalVariableSet(pfx+"SumRR",   statSumRR);

      break;
   }
}

//+------------------------------------------------------------------+
//| POSITION CHECK                                                   |
//+------------------------------------------------------------------+
bool IsPositionOpen()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL)  == _Symbol &&
            PositionGetInteger(POSITION_MAGIC)  == MAGIC_NUMBER)
            return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| SESSION FILTERS WITH BROKER GMT OFFSET                          |
//+------------------------------------------------------------------+
double GetGMTHour()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   double gmtHour = dt.hour - BrokerGMTOffset + dt.min / 60.0;
   while(gmtHour < 0)   gmtHour += 24.0;
   while(gmtHour >= 24) gmtHour -= 24.0;
   return gmtHour;
}

bool InSydneySession()     { if(!SessionSydney)      return false; double h=GetGMTHour(); return(h>=22.0||h<7.0);  }
bool InTokyoSession()      { if(!SessionTokyo)       return false; double h=GetGMTHour(); return(h>=0.0 &&h<9.0);  }
bool InLondonSession()     { if(!SessionLondon)      return false; double h=GetGMTHour(); return(h>=8.0 &&h<17.0); }
bool InNewYorkSession()    { if(!SessionNewYork)     return false; double h=GetGMTHour(); return(h>=13.0&&h<22.0); }
bool InLondonNYOverlap()   { if(!OverlapLondonNY)   return false; double h=GetGMTHour(); return(h>=13.0&&h<17.0); }
bool InTokyoLondonOverlap(){ if(!OverlapTokyoLondon)return false; double h=GetGMTHour(); return(h>=8.0 &&h<9.0);  }

bool SessionActiveNow(string which)
{
   double h = GetGMTHour();
   if(which == "London")  return (h >= 8.0  && h < 17.0);
   if(which == "NewYork") return (h >= 13.0 && h < 22.0);
   if(which == "Overlap") return (h >= 13.0 && h < 17.0);
   if(which == "Sydney")  return (h >= 22.0 || h < 7.0);
   if(which == "Tokyo")   return (h >= 0.0  && h < 9.0);
   return false;
}

// FIX P: Check if it's Friday cut-off time
bool IsFridayCutoff()
{
   if(!CloseOnFriday) return false;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week != 5) return false;
   double gmt = GetGMTHour();
   return (gmt >= (double)FridayCloseHour);
}

bool IsTradingTime()
{
   if(!UseTimeFilter) return true;

   // FIX P: No new entries on Friday after cut-off
   if(IsFridayCutoff()) return false;

   if(BestHoursOnly)
   {
      double gmt = GetGMTHour();
      // FIX N: Start at 08:30 instead of 08:00 (skip London open noise)
      if(gmt < 8.5 || gmt >= 15.0) return false;
   }
   return (InSydneySession() || InTokyoSession() || InLondonSession() ||
           InNewYorkSession() || InLondonNYOverlap() || InTokyoLondonOverlap());
}

bool IsSpreadOK()
{
   if(MaxSpreadPoints <= 0) return true;
   double spread = (SymbolInfoDouble(_Symbol,SYMBOL_ASK) - SymbolInfoDouble(_Symbol,SYMBOL_BID)) / _Point;
   return (spread <= MaxSpreadPoints);
}

//+------------------------------------------------------------------+
//| ATR HELPER                                                       |
//+------------------------------------------------------------------+
double GetATR()
{
   double atr[1];
   if(CopyBuffer(ATRHandle, 0, 1, 1, atr) == 1) return atr[0];
   return _Point * 100;
}

//+------------------------------------------------------------------+
//| HTF LEVEL DETECTION                                              |
//+------------------------------------------------------------------+
bool HasReachedHTFLevel()
{
   if(!HTFLevelRequired) return true;   // FIX U: disabled → always pass Step 1

   ENUM_TIMEFRAMES htf;
   switch(HTFLevelMinutes)
   {
      case 15: htf = PERIOD_M15; break;
      case 30: htf = PERIOD_M30; break;
      case 60: htf = PERIOD_H1;  break;
      default: htf = PERIOD_M15;
   }

   double price     = iClose(_Symbol, htf, 0);
   double tolerance = GetATR() * HTFToleranceATRMulti;

   for(int i = 1; i <= 20; i++)
   {
      double hi1 = iHigh(_Symbol, htf, i);
      double lo1 = iLow (_Symbol, htf, i);
      double hi3 = iHigh(_Symbol, htf, i+2);
      double lo3 = iLow (_Symbol, htf, i+2);

      if(hi1 < lo3 && price >= hi1 - tolerance && price <= lo3 + tolerance) return true;
      if(lo1 > hi3 && price >= hi3 - tolerance && price <= lo1 + tolerance) return true;
   }

   double prevHigh = iHigh(_Symbol, htf, 1);
   double prevLow  = iLow (_Symbol, htf, 1);
   if(MathAbs(price - prevHigh) <= tolerance) return true;
   if(MathAbs(price - prevLow)  <= tolerance) return true;

   // H1 prev-bar high/low — real HTF reference (2x ATR tolerance)
   double h1High = iHigh(_Symbol, PERIOD_H1, 1);
   double h1Low  = iLow (_Symbol, PERIOD_H1, 1);
   if(MathAbs(price - h1High) <= tolerance * 2) return true;
   if(MathAbs(price - h1Low)  <= tolerance * 2) return true;

   // H4 prev-bar high/low — institutional reference (4x ATR tolerance)
   double h4High = iHigh(_Symbol, PERIOD_H4, 1);
   double h4Low  = iLow (_Symbol, PERIOD_H4, 1);
   if(MathAbs(price - h4High) <= tolerance * 4) return true;
   if(MathAbs(price - h4Low)  <= tolerance * 4) return true;

   double dayHigh = iHigh(_Symbol, PERIOD_D1, 1);
   double dayLow  = iLow (_Symbol, PERIOD_D1, 1);
   double dayTol  = tolerance * 3;
   if(MathAbs(price - dayHigh) <= dayTol) return true;
   if(MathAbs(price - dayLow)  <= dayTol) return true;

   return false;
}

//+------------------------------------------------------------------+
//| CISD DETECTION                                                   |
//+------------------------------------------------------------------+
bool IsCISD(ENUM_TIMEFRAMES tf, bool &isBearish, int minSequence = 2)
{
   bool allUp   = true;
   bool allDown = true;

   for(int i = 1; i <= minSequence; i++)
   {
      double c = iClose(_Symbol, tf, i);
      double o = iOpen (_Symbol, tf, i);
      if(c <= o) allUp   = false;
      if(c >= o) allDown = false;
   }

   double curClose = iClose(_Symbol, tf, 0);

   if(allUp)
   {
      double seqLow = iLow(_Symbol, tf, 1);
      for(int i = 2; i <= minSequence; i++)
      { double l = iLow(_Symbol, tf, i); if(l < seqLow) seqLow = l; }
      if(curClose < seqLow) { isBearish = true;  return true; }
   }
   if(allDown)
   {
      double seqHigh = iHigh(_Symbol, tf, 1);
      for(int i = 2; i <= minSequence; i++)
      { double h = iHigh(_Symbol, tf, i); if(h > seqHigh) seqHigh = h; }
      if(curClose > seqHigh) { isBearish = false; return true; }
   }
   return false;
}

//+------------------------------------------------------------------+
//| SWING SCORING - most recent confirmed swing                      |
//+------------------------------------------------------------------+
struct SwingCandidate
{
   double price;
   int    barIndex;
   double range;
};

void FindSwingPointsH1(double &swingHigh, double &swingLow)
{
   swingHigh = 0;
   swingLow  = 0;

   MqlRates h1[];
   ArraySetAsSeries(h1, true);
   int need = SwingLookbackBarsH1 + SwingConfirmBarsH1 + 5;
   if(CopyRates(_Symbol, PERIOD_H1, 0, need, h1) < need) return;

   double maxPipDist   = (MaxSwingDistancePips > 0)
                         ? MaxSwingDistancePips * PipFactor * _Point
                         : DBL_MAX;
   double currentPrice = iClose(_Symbol, PERIOD_H1, 0);

   SwingCandidate bestHigh; bestHigh.price = 0; bestHigh.barIndex = INT_MAX; bestHigh.range = 0;
   SwingCandidate bestLow;  bestLow.price  = 0; bestLow.barIndex  = INT_MAX; bestLow.range  = 0;

   for(int i = SwingConfirmBarsH1; i < SwingLookbackBarsH1 - SwingConfirmBarsH1; i++)
   {
      if(MathAbs(h1[i].high - currentPrice) <= maxPipDist)
      {
         bool isHigh = true;
         for(int j = i - SwingConfirmBarsH1; j <= i + SwingConfirmBarsH1; j++)
         {
            if(j == i || j < 0) continue;
            if(h1[j].high >= h1[i].high) { isHigh = false; break; }
         }
         if(isHigh && i < bestHigh.barIndex)
         {
            bestHigh.price    = h1[i].high;
            bestHigh.barIndex = i;
         }
      }

      if(MathAbs(h1[i].low - currentPrice) <= maxPipDist)
      {
         bool isLow = true;
         for(int j = i - SwingConfirmBarsH1; j <= i + SwingConfirmBarsH1; j++)
         {
            if(j == i || j < 0) continue;
            if(h1[j].low <= h1[i].low) { isLow = false; break; }
         }
         if(isLow && i < bestLow.barIndex)
         {
            bestLow.price    = h1[i].low;
            bestLow.barIndex = i;
         }
      }
   }

   swingHigh = bestHigh.price;
   swingLow  = bestLow.price;

   if(DebugMode && swingHigh > 0 && swingLow > 0)
      DebugPrint("H1 Swings: High=" + DoubleToString(swingHigh, _Digits) +
                 " (bar " + IntegerToString(bestHigh.barIndex) + ")" +
                 " Low=" + DoubleToString(swingLow, _Digits) +
                 " (bar " + IntegerToString(bestLow.barIndex) + ")");
}

void FindSwingPointsM15(double &swingHigh, double &swingLow)
{
   swingHigh = 0;
   swingLow  = 0;

   MqlRates m15[];
   ArraySetAsSeries(m15, true);
   int need = SwingLookbackBarsM15 + SwingConfirmBarsM15 + 5;
   if(CopyRates(_Symbol, PERIOD_M15, 0, need, m15) < need) return;

   double maxPipDist   = (MaxSwingDistancePips > 0)
                         ? MaxSwingDistancePips * PipFactor * _Point
                         : DBL_MAX;
   double currentPrice = iClose(_Symbol, PERIOD_M15, 0);

   int bestHighBar = INT_MAX, bestLowBar = INT_MAX;

   for(int i = SwingConfirmBarsM15; i < SwingLookbackBarsM15 - SwingConfirmBarsM15; i++)
   {
      if(MathAbs(m15[i].high - currentPrice) <= maxPipDist)
      {
         bool isHigh = true;
         for(int j = i - SwingConfirmBarsM15; j <= i + SwingConfirmBarsM15; j++)
         {
            if(j == i || j < 0) continue;
            if(m15[j].high >= m15[i].high) { isHigh = false; break; }
         }
         if(isHigh && i < bestHighBar) { swingHigh = m15[i].high; bestHighBar = i; }
      }

      if(MathAbs(m15[i].low - currentPrice) <= maxPipDist)
      {
         bool isLow = true;
         for(int j = i - SwingConfirmBarsM15; j <= i + SwingConfirmBarsM15; j++)
         {
            if(j == i || j < 0) continue;
            if(m15[j].low <= m15[i].low) { isLow = false; break; }
         }
         if(isLow && i < bestLowBar) { swingLow = m15[i].low; bestLowBar = i; }
      }
   }
}

//+------------------------------------------------------------------+
//| SWING PRICE FOR SL (with ATR fallback)                          |
//+------------------------------------------------------------------+
void FindNearestSwing(bool isBuy, double &swingPrice)
{
   swingPrice = 0;
   FindSwingPointsM15(lastSwingHighM15, lastSwingLowM15);

   if(isBuy  && lastSwingLowM15  > 0) swingPrice = lastSwingLowM15;
   if(!isBuy && lastSwingHighM15 > 0) swingPrice = lastSwingHighM15;

   if(swingPrice <= 0)
   {
      double atr = GetATR();
      swingPrice = isBuy
         ? SymbolInfoDouble(_Symbol, SYMBOL_BID) - atr * 1.5
         : SymbolInfoDouble(_Symbol, SYMBOL_ASK) + atr * 1.5;
      DebugPrint("M15 swing not found - using ATR fallback SL: " + DoubleToString(swingPrice, _Digits));
   }

   if(ShowSwingLines) DrawSwingLine(swingPrice, isBuy, "M15");
}

//+------------------------------------------------------------------+
//| FVG COUNT ON 1MIN                                                |
//+------------------------------------------------------------------+
int CountFVGsOn1Min(datetime startTime, datetime endTime)
{
   int count = 0;
   MqlRates rates[];
   ArraySetAsSeries(rates, false);

   datetime from = startTime - PeriodSeconds(PERIOD_M1) * 5;
   int copied = CopyRates(_Symbol, PERIOD_M1, from, endTime + PeriodSeconds(PERIOD_M1), rates);
   if(copied < 3) return 0;

   for(int i = 0; i < copied - 2; i++)
   {
      if(rates[i].time < startTime) continue;
      if(rates[i].time > endTime)   break;
      if(rates[i+2].low  > rates[i].high) count++;
      if(rates[i+2].high < rates[i].low)  count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| OTE ZONE                                                         |
//+------------------------------------------------------------------+
bool IsInOTEZone(double price, double hi, double lo)
{
   if(hi <= 0 || lo <= 0 || hi <= lo) return false;
   double range = hi - lo;
   return (price >= lo + range * OTEMinPercent &&
           price <= lo + range * OTEMaxPercent);
}

double GetOTEPrice(double hi, double lo, double level)
{
   if(hi <= 0 || lo <= 0) return 0;
   return lo + (hi - lo) * level;
}

//+------------------------------------------------------------------+
//| DRAW OTE ZONE ON CHART                                          |
//+------------------------------------------------------------------+
void DrawOTEZone(double hi, double lo)
{
   if(!ShowOTEZone || hi <= 0 || lo <= 0) return;
   if(hi == lastOTEHigh && lo == lastOTELow) return;
   lastOTEHigh = hi;
   lastOTELow  = lo;

   string names[4] = {"Twins_OTE_High","Twins_OTE_Sweet","Twins_OTE_Low","Twins_OTE_Fill"};
   double levels[3];
   levels[0] = GetOTEPrice(hi, lo, OTEMaxPercent);
   levels[1] = GetOTEPrice(hi, lo, OTESweetSpotPercent);
   levels[2] = GetOTEPrice(hi, lo, OTEMinPercent);

   color  cols[3] = {clrOrangeRed, clrGold, clrDodgerBlue};
   string lbls[3];
   lbls[0] = "OTE " + DoubleToString(OTEMaxPercent*100,0) + "%";
   lbls[1] = "OTE 70.5% (Sweet)";
   lbls[2] = "OTE " + DoubleToString(OTEMinPercent*100,0) + "%";

   for(int i = 0; i < 4; i++) OTEObjectNames[i] = names[i];

   for(int i = 0; i < 3; i++) ObjectDelete(0, names[i]);
   ObjectDelete(0, names[3]);

   for(int i = 0; i < 3; i++)
   {
      ObjectCreate(0, names[i], OBJ_HLINE, 0, 0, levels[i]);
      ObjectSetInteger(0, names[i], OBJPROP_COLOR,  cols[i]);
      ObjectSetInteger(0, names[i], OBJPROP_WIDTH,  1);
      ObjectSetInteger(0, names[i], OBJPROP_STYLE,  STYLE_DOT);
      ObjectSetString (0, names[i], OBJPROP_TOOLTIP, lbls[i] + ": " + DoubleToString(levels[i], _Digits));
   }

   datetime t1 = TimeCurrent() - PeriodSeconds(PERIOD_H1) * 10;
   datetime t2 = TimeCurrent() + PeriodSeconds(PERIOD_H1) * 20;
   ObjectCreate(0, names[3], OBJ_RECTANGLE, 0, t1, levels[0], t2, levels[2]);
   ObjectSetInteger(0, names[3], OBJPROP_COLOR,  clrGold);
   ObjectSetInteger(0, names[3], OBJPROP_FILL,   true);
   ObjectSetInteger(0, names[3], OBJPROP_BACK,   true);
   ObjectSetInteger(0, names[3], OBJPROP_WIDTH,  1);
   ObjectSetInteger(0, names[3], OBJPROP_STYLE,  STYLE_SOLID);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| EFFECTIVE FVG REQUIREMENT                                        |
//+------------------------------------------------------------------+
int GetEffectiveFVGRequirement()
{
   return RelaxedMode ? 0 : MinFVGsRequired;
}

//+------------------------------------------------------------------+
//| STATE MACHINE STEPS 1-5: BUILD CONTEXT                         |
//+------------------------------------------------------------------+
void UpdateContextState()
{
   if(HasReachedHTFLevel())
   {
      if(!htfLevelReached)
      {
         htfLevelReached = true;
         Print("STEP 1 PASS: HTF Level Reached");
         lastFailedStep = 0; lastFailedStepDesc = "";
      }
   }
   else
   {
      if(htfLevelReached)
      {
         htfLevelReached = false;
         DebugPrint("STEP 1: HTF level lost - rescanning");
      }
      lastFailedStep = 1; lastFailedStepDesc = "HTF Level";
      return;
   }

   // STEP 2: 5M Momentum Direction
   bool tempBearish5 = false;
   bool foundCISD5   = false;

   if(IsCISD(PERIOD_M5, tempBearish5, 2))
      foundCISD5 = true;

   if(!foundCISD5)
   {
      for(int lb = 1; lb <= 10; lb++)
      {
         double o5 = iOpen (_Symbol, PERIOD_M5, lb);
         double cl5= iClose(_Symbol, PERIOD_M5, lb);
         double h5 = iHigh (_Symbol, PERIOD_M5, lb);
         double l5 = iLow  (_Symbol, PERIOD_M5, lb);
         double body5  = MathAbs(cl5 - o5);
         double range5 = h5 - l5;
         if(range5 > 0 && body5 / range5 >= 0.70)
         {
            tempBearish5 = (cl5 < o5);
            foundCISD5   = true;
            break;
         }
      }
   }

   if(foundCISD5)
   {
      datetime barTime5 = iTime(_Symbol, PERIOD_M5, 0);
      if(LastCISDTime5Min != barTime5)
      {
         LastCISDTime5Min  = barTime5;
         cisd5MinConfirmed = true;
         cisd5MinIsBearish = tempBearish5;
         cisd1MinConfirmed = false;
         fvgCount1Min      = -1;
         Print("STEP 2 PASS: 5M Direction (" + (tempBearish5 ? "BEARISH" : "BULLISH") + ")");
      }
   }
   if(!cisd5MinConfirmed)
   {
      lastFailedStep = 2; lastFailedStepDesc = "5M Direction";
      return;
   }

   // STEP 3: Count 1M FVGs
   if(fvgCount1Min < 0)
   {
      datetime cisdStart = LastCISDTime5Min - PeriodSeconds(PERIOD_M5);
      datetime cisdEnd   = LastCISDTime5Min;
      fvgCount1Min = CountFVGsOn1Min(cisdStart, cisdEnd);
      DebugPrint("STEP 3: FVG count = " + IntegerToString(fvgCount1Min));
   }
   int fvgRequired = GetEffectiveFVGRequirement();
   if(fvgRequired > 0 && fvgCount1Min < fvgRequired)
   {
      lastFailedStep = 3; lastFailedStepDesc = "1M FVG Count";
      return;
   }

   // STEP 4: H1 swings for OTE
   FindSwingPointsH1(lastSwingHighH1, lastSwingLowH1);
   if(lastSwingHighH1 <= 0 || lastSwingLowH1 <= 0 || lastSwingHighH1 <= lastSwingLowH1)
   {
      lastFailedStep = 4; lastFailedStepDesc = "H1 Swings";
      return;
   }
   if(MinH1RangePips > 0)
   {
      double rangePips = (lastSwingHighH1 - lastSwingLowH1) / _Point / PipFactor;
      double effectiveMin = (MinH1RangePips > 0) ? MinH1RangePips : 30;
      if(rangePips < effectiveMin)
      {
         lastFailedStep = 4; lastFailedStepDesc = "H1 Range Too Small";
         return;
      }
   }

   // STEP 5: M15 swings for SL
   FindSwingPointsM15(lastSwingHighM15, lastSwingLowM15);

   if(ShowOTEZone) DrawOTEZone(lastSwingHighH1, lastSwingLowH1);
}

//+------------------------------------------------------------------+
//| STATE MACHINE STEPS 6-8: LIVE ENTRY CHECK                      |
//+------------------------------------------------------------------+
bool CheckTwinsSequence(bool &isBuy)
{
   if(UseTimeFilter && !IsTradingTime()) return false;

   if(!htfLevelReached || !cisd5MinConfirmed || fvgCount1Min < 0 ||
      lastSwingHighH1 <= 0 || lastSwingLowH1 <= 0)
   {
      DebugPrint("Entry check: context not ready yet");
      return false;
   }

   // STEP 6: Price in OTE zone
   double curPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double range    = lastSwingHighH1 - lastSwingLowH1;
   double oteLow   = lastSwingLowH1 + range * (RelaxedMode ? OTEMinPercent - 0.02 : OTEMinPercent);
   double oteHigh  = lastSwingLowH1 + range * (RelaxedMode ? OTEMaxPercent + 0.02 : OTEMaxPercent);

   if(curPrice < oteLow || curPrice > oteHigh)
   {
      lastFailedStep = 6; lastFailedStepDesc = "OTE Zone";
      return false;
   }

   // STEP 7: 1M Entry Trigger
   // FIX K: raised 1M momentum threshold from 55% to 65%
   bool tempBearish1 = false;
   bool foundCISD1   = false;

   if(IsCISD(PERIOD_M1, tempBearish1, 1))
      foundCISD1 = true;

   if(!foundCISD1)
   {
      for(int lb = 1; lb <= 3; lb++)
      {
         double o1 = iOpen (_Symbol, PERIOD_M1, lb);
         double cl1= iClose(_Symbol, PERIOD_M1, lb);
         double h1 = iHigh (_Symbol, PERIOD_M1, lb);
         double l1 = iLow  (_Symbol, PERIOD_M1, lb);
         double body1  = MathAbs(cl1 - o1);
         double range1 = h1 - l1;
         if(range1 > 0 && body1 / range1 >= 0.65)  // FIX K: was 0.55
         {
            tempBearish1 = (cl1 < o1);
            foundCISD1   = true;
            break;
         }
      }
   }

   if(foundCISD1)
   {
      datetime barTime1 = iTime(_Symbol, PERIOD_M1, 0);
      if(LastCISDTime1Min != barTime1)
      {
         LastCISDTime1Min  = barTime1;
         cisd1MinConfirmed = true;
         cisd1MinIsBearish = tempBearish1;
         DebugPrint("STEP 7 PASS: 1M Entry Trigger (" + (tempBearish1 ? "BEARISH" : "BULLISH") + ")");
      }
   }
   if(!cisd1MinConfirmed)
   {
      lastFailedStep = 7; lastFailedStepDesc = "1M Entry Trigger";
      return false;
   }

   // STEP 8: Direction agreement
   double oteBottom   = lastSwingLowH1 + range * OTEMinPercent;
   double oteTop      = lastSwingLowH1 + range * OTEMaxPercent;
   double oteRange    = oteTop - oteBottom;
   double buyZoneTop  = oteBottom + oteRange * 0.35;
   double sellZoneBtm = oteTop   - oteRange * 0.35;

   bool priceInBuyZone  = (curPrice <= buyZoneTop);
   bool priceInSellZone = (curPrice >= sellZoneBtm);

   if(!priceInBuyZone && !priceInSellZone)
   {
      lastFailedStep = 8; lastFailedStepDesc = "OTE Middle (no-trade zone)";
      return false;
   }

   isBuy = priceInBuyZone;

   if(cisd5MinIsBearish == isBuy)
   {
      lastFailedStep = 8; lastFailedStepDesc = "5M/OTE Conflict";
      return false;
   }

   if(cisd1MinIsBearish == isBuy)
   {
      lastFailedStep = 8; lastFailedStepDesc = "1M/OTE Conflict";
      return false;
   }

   // STEP 8b: Multi-timeframe trend filter
   // FIX M: BUY requires 3/3 bullish D1 candles (was 2/3) to reduce BUY overtrade bias
   if(UseDailyTrendFilter)
   {
      MqlRates d1[4];
      bool d1IsUp = false, d1IsDn = false;
      if(CopyRates(_Symbol, PERIOD_D1, 0, 4, d1) == 4)
      {
         int bullCount = 0, bearCount = 0;
         for(int di = 1; di <= 3; di++)
         {
            if(d1[di].close > d1[di].open) bullCount++;
            else bearCount++;
         }
         // FIX M: BUY needs all 3 D1 candles bullish; SELL keeps 2/3
         d1IsUp = isBuy ? (bullCount == 3) : (bullCount >= 2);
         d1IsDn = isBuy ? (bearCount >= 2) : (bearCount == 3);
      }

      bool h4IsUp = false, h4IsDn = false;
      double h4ema[1];
      int h4Handle = iMA(_Symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
      if(h4Handle != INVALID_HANDLE && CopyBuffer(h4Handle, 0, 1, 1, h4ema) == 1)
      {
         IndicatorRelease(h4Handle);
         double curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         h4IsUp = (curBid > h4ema[0]);
         h4IsDn = (curBid < h4ema[0]);
      }

      if(isBuy)
      {
         bool anyBullConfirm = d1IsUp || h4IsUp;
         bool strongBear = d1IsDn && h4IsDn;
         if(strongBear || (!anyBullConfirm && d1IsDn))
         {
            lastFailedStep = 9; lastFailedStepDesc = "MTF Trend (BUY vs Bear)";
            return false;
         }
      }
      else
      {
         bool anyBearConfirm = d1IsDn || h4IsDn;
         bool strongBull = d1IsUp && h4IsUp;
         if(strongBull || (!anyBearConfirm && d1IsUp))
         {
            lastFailedStep = 9; lastFailedStepDesc = "MTF Trend (SELL vs Bull)";
            return false;
         }
      }
   }

   lastFailedStep = 0; lastFailedStepDesc = "";

   static datetime lastEntryLog = 0;
   datetime curBar = iTime(_Symbol, PERIOD_M15, 0);
   if(lastEntryLog != curBar)
   {
      lastEntryLog = curBar;
      Print(">>> ENTRY READY: ", isBuy ? "BUY" : "SELL",
            " | 5M=", cisd5MinIsBearish?"BEAR":"BULL",
            " | 1M=", cisd1MinIsBearish?"BEAR":"BULL", " <<<");
   }
   return true;
}

//+------------------------------------------------------------------+
//| FRIDAY CLOSE                                                     |
//+------------------------------------------------------------------+
void CheckFridayClose()
{
   if(!CloseOnFriday) return;
   if(!IsFridayCutoff()) return;

   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
            trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| TRAILING STOP                                                    |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
   if(!UseTrailingStop) return;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0||!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol||
         PositionGetInteger(POSITION_MAGIC)!=MAGIC_NUMBER) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL     = PositionGetDouble(POSITION_SL);
      double curTP     = PositionGetDouble(POSITION_TP);
      double price     = (type==POSITION_TYPE_BUY)
                         ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                         : SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      double profitPips = (type==POSITION_TYPE_BUY)
                          ? (price-openPrice)/_Point/PipFactor
                          : (openPrice-price)/_Point/PipFactor;

      if(profitPips < TrailingStartPips) continue;

      double newSL = (type==POSITION_TYPE_BUY)
                     ? NormalizeDouble(price - TrailingStepPips*PipFactor*_Point, _Digits)
                     : NormalizeDouble(price + TrailingStepPips*PipFactor*_Point, _Digits);

      bool mod = (type==POSITION_TYPE_BUY  && (curSL==0||newSL>curSL)) ||
                 (type==POSITION_TYPE_SELL && (curSL==0||newSL<curSL));
      if(mod) trade.PositionModify(ticket, newSL, curTP);
   }
}

//+------------------------------------------------------------------+
//| BREAKEVEN                                                        |
//+------------------------------------------------------------------+
void ApplyBreakeven()
{
   if(!UseBreakeven) return;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0||!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol||
         PositionGetInteger(POSITION_MAGIC)!=MAGIC_NUMBER) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL     = PositionGetDouble(POSITION_SL);
      double curTP     = PositionGetDouble(POSITION_TP);
      double price     = (type==POSITION_TYPE_BUY)
                         ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                         : SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      double profitPips = (type==POSITION_TYPE_BUY)
                          ? (price-openPrice)/_Point/PipFactor
                          : (openPrice-price)/_Point/PipFactor;

      if(profitPips < BreakevenTriggerPips) continue;

      double beSL = (type==POSITION_TYPE_BUY)
                    ? NormalizeDouble(openPrice + 2*_Point, _Digits)
                    : NormalizeDouble(openPrice - 2*_Point, _Digits);

      bool mod = (type==POSITION_TYPE_BUY  && (curSL==0||beSL>curSL)) ||
                 (type==POSITION_TYPE_SELL && (curSL==0||beSL<curSL));
      if(mod) trade.PositionModify(ticket, beSL, curTP);
   }
}

//+------------------------------------------------------------------+
//| ROLLING SWING LINE DRAWING                                       |
//+------------------------------------------------------------------+
void DrawSwingLine(double price, bool isBuy, string source)
{
   if(!ShowSwingLines) return;
   if(SwingLineNames[SwingLineIndex] != "")
      ObjectDelete(0, SwingLineNames[SwingLineIndex]);

   string name = "SwingLine_" + source + "_" + IntegerToString(SwingLineIndex);
   SwingLineNames[SwingLineIndex] = name;
   SwingLineIndex = (SwingLineIndex + 1) % MaxSwingLines;

   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? clrDodgerBlue : clrOrangeRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| LOT SIZE CALCULATION                                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(slPoints <= 0) return minLot;

   if(FixedLot > 0)
   {
      double lot = MathMax(minLot, MathMin(MathMin(maxLot, MaxLotLimit), FixedLot));
      return NormalizeDouble(MathFloor(lot/lotStep)*lotStep, 2);
   }

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;

   if(tickValue <= 0 || tickSize <= 0) return minLot;

   double lossPerLot = (slPoints * _Point / tickSize) * tickValue;
   if(lossPerLot <= 0) return minLot;

   double volume = riskMoney / lossPerLot;
   volume = MathMax(minLot, MathMin(MathMin(maxLot, MaxLotLimit), volume));
   volume = MathFloor(volume/lotStep)*lotStep;
   return NormalizeDouble(volume, 2);
}

//+------------------------------------------------------------------+
//| DAILY COUNTERS                                                   |
//+------------------------------------------------------------------+
void UpdateDailyCounters()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day == LastTradeDay) return;

   TodayTradeCount   = 0;
   TodayLossTrades   = 0;   // FIX T: reset daily loss trade counter
   TodayLoss         = 0;
   if(ResetLossStreakDaily) consecutiveLosses = 0;
   LastTradeDay      = dt.day;

   htfLevelReached   = false;
   cisd5MinConfirmed = false;
   cisd1MinConfirmed = false;
   fvgCount1Min      = -1;
   lastSwingHighH1   = 0; lastSwingLowH1  = 0;
   lastSwingHighM15  = 0; lastSwingLowM15 = 0;
}

bool IsDailyLossLimitHit()
{
   if(MaxDailyLossPercent <= 0) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime todayStart = StructToTime(dt);

   TodayLoss = 0;
   if(HistorySelect(todayStart, TimeCurrent()))
   {
      for(int i = HistoryDealsTotal()-1; i >= 0; i--)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         if(HistoryDealGetString (deal, DEAL_SYMBOL) != _Symbol)      continue;
         if(HistoryDealGetInteger(deal, DEAL_MAGIC)  != MAGIC_NUMBER) continue;
         if(HistoryDealGetInteger(deal, DEAL_ENTRY)  != DEAL_ENTRY_OUT) continue;

         double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
         if(profit < 0) TodayLoss += MathAbs(profit);
      }
   }

   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double maxLoss  = MathMin(balance, equity) * MaxDailyLossPercent / 100.0;
   return (TodayLoss >= maxLoss);
}

bool CanTrade()
{
   UpdateDailyCounters();

   static datetime lastCanTradeLog = 0;
   bool canLog = (TimeCurrent() - lastCanTradeLog >= 60);

   if(IsDailyLossLimitHit())
   {
      if(canLog) { Print("CANTRADE: Daily loss limit ($", DoubleToString(TodayLoss,2), ")"); lastCanTradeLog = TimeCurrent(); }
      return false;
   }
   if(TodayTradeCount >= MaxTradesPerDay)
   {
      if(canLog) { Print("CANTRADE: Max trades (", TodayTradeCount, "/", MaxTradesPerDay, ")"); lastCanTradeLog = TimeCurrent(); }
      return false;
   }
   // FIX T: stop new entries after N losing trades today (prevents cluster losses)
   if(MaxDailyLossTrades > 0 && TodayLossTrades >= MaxDailyLossTrades)
   {
      if(canLog) { Print("CANTRADE: Daily loss trades limit (", TodayLossTrades, "/", MaxDailyLossTrades, ")"); lastCanTradeLog = TimeCurrent(); }
      return false;
   }
   if(consecutiveLosses >= MaxConsecutiveLosses)
   {
      if(canLog) { Print("CANTRADE: Consecutive losses (", consecutiveLosses, ")"); lastCanTradeLog = TimeCurrent(); }
      return false;
   }
   if(!IsSpreadOK())
   {
      if(canLog) { DebugPrint("CANTRADE: Spread too wide"); lastCanTradeLog = TimeCurrent(); }
      return false;
   }
   if(IsPositionOpen()) return false;

   if(PostTradeCooldownMin > 0 &&
      LastTradeCloseTime > 0 &&
      TimeCurrent() - LastTradeCloseTime < (datetime)(PostTradeCooldownMin * 60))
   {
      if(canLog)
      {
         int secsLeft = (int)((PostTradeCooldownMin * 60) - (TimeCurrent() - LastTradeCloseTime));
         Print("CANTRADE: Cooldown active (", secsLeft / 60, "m ", secsLeft % 60, "s remaining)");
         lastCanTradeLog = TimeCurrent();
      }
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| TRADE PLACEMENT                                                  |
//+------------------------------------------------------------------+
void PlaceTrade(bool isBuy = true)
{
   if(IsPositionOpen()) return;

   long tradeMode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED || tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
   {
      DebugPrint("PlaceTrade: market closed or closeonly - skipping");
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;

   if(ForceTrades)
   {
      static int forceCounter = 0;
      forceCounter++;
      isBuy = (forceCounter % 2 == 1);
      Print("FORCE MODE: Trade #", forceCounter, " → ", isBuy ? "BUY" : "SELL");
   }
   else if(!UseTwinsModel)
   {
      double fast[1], slow[1];
      if(CopyBuffer(FastEMAHandle,0,1,1,fast)!=1||
         CopyBuffer(SlowEMAHandle,0,1,1,slow)!=1) return;
      MqlRates rates[2];
      if(CopyRates(_Symbol,PERIOD_M15,0,2,rates)!=2) return;

      bool trendUp  = (fast[0]>slow[0]);
      bool trendDn  = (fast[0]<slow[0]);
      bool candleUp = (rates[1].close>rates[1].open);
      bool candleDn = (rates[1].close<rates[1].open);

      if(trendUp && candleUp)      isBuy = true;
      else if(trendDn && candleDn) isBuy = false;
      else return;
   }

   double entry = isBuy ? tick.ask : tick.bid;

   double swingPrice = 0;
   FindNearestSwing(isBuy, swingPrice);

   double buffer = SLBufferPips * PipFactor * _Point;
   double sl = isBuy
               ? NormalizeDouble(swingPrice - buffer, _Digits)
               : NormalizeDouble(swingPrice + buffer, _Digits);

   if(isBuy  && sl >= entry) { Print("SKIP: SL >= entry (BUY)");  return; }
   if(!isBuy && sl <= entry) { Print("SKIP: SL <= entry (SELL)"); return; }

   double slPoints = MathAbs(entry - sl) / _Point;
   if(slPoints < MinStopDistance)
   { Print("SKIP: SL too close (", slPoints, " pts)"); return; }

   // FIX O: Cap SL at MaxSLPips (now 30 pips default)
   if(MaxSLPips > 0)
   {
      double maxSLPoints = MaxSLPips * PipFactor;
      if(slPoints > maxSLPoints)
      {
         double atr = GetATR();
         sl = isBuy
            ? NormalizeDouble(entry - atr * 1.5, _Digits)
            : NormalizeDouble(entry + atr * 1.5, _Digits);
         slPoints = MathAbs(entry - sl) / _Point;
         DebugPrint("SL capped by MaxSLPips to ATR: " + DoubleToString(sl, _Digits));
      }
   }

   // FIX Q: Reject if SL is too small in pips (prevents tiny-SL trades with huge lots
   //         that live inside the spread and trigger "Invalid stops" on broker)
   if(MinSLPips > 0)
   {
      double slPips = slPoints / PipFactor;
      if(slPips < (double)MinSLPips)
      {
         Print("SKIP: SL too small (", DoubleToString(slPips,2), " pips < min ", MinSLPips, ")");
         cisd1MinConfirmed = false;   // FIX S: break retry loop
         return;
      }
   }

   double fixedTP = isBuy
      ? NormalizeDouble(entry + slPoints*_Point*RewardRiskRatio, _Digits)
      : NormalizeDouble(entry - slPoints*_Point*RewardRiskRatio, _Digits);
   double tp = fixedTP;

   double actualRR = MathAbs(tp - entry) / MathAbs(entry - sl);
   // FIX R: use 0.001 tolerance to avoid float comparison 2.0 < 2.0 firing falsely
   if(actualRR < MinRewardRiskRatio - 0.001)
   { Print("SKIP: R:R=", DoubleToString(actualRR,4), " < min ", DoubleToString(MinRewardRiskRatio,2)); cisd1MinConfirmed = false; return; }

   if(isBuy  && tp <= entry) { Print("SKIP: TP below entry (BUY)");  return; }
   if(!isBuy && tp >= entry) { Print("SKIP: TP above entry (SELL)"); return; }

   double volume = CalculateLotSize(slPoints);
   if(volume <= 0) { Print("SKIP: Invalid lot size"); return; }

   string oteDir = "?";
   if(lastSwingHighH1 > 0 && lastSwingLowH1 > 0)
   {
      double midOTE = lastSwingLowH1 + (lastSwingHighH1 - lastSwingLowH1) * OTESweetSpotPercent;
      double curP   = isBuy ? tick.ask : tick.bid;
      oteDir = (curP <= midOTE) ? "BUY" : "SELL";
   }
   string dir5M    = cisd5MinIsBearish ? "BEAR(SELL)" : "BULL(BUY)";
   string dir1M    = cisd1MinIsBearish ? "BEAR(SELL)" : "BULL(BUY)";
   string dirFinal = isBuy ? "BUY" : "SELL";
   Print("DIRECTION AUDIT | OTE=", oteDir, " | 5M=", dir5M, " | 1M=", dir1M, " | FINAL=", dirFinal);

   Print("══════════════════════════════════════════");
   Print(EA_NAME, " TRADE");
   Print("Direction : ", isBuy ? "BUY" : "SELL");
   Print("Entry     : ", DoubleToString(entry, _Digits));
   Print("SL        : ", DoubleToString(sl, _Digits), " (", DoubleToString(slPoints,0), " pts)");
   Print("TP        : ", DoubleToString(tp, _Digits), " | R:R=", DoubleToString(actualRR,2));
   Print("Lot Size  : ", DoubleToString(volume, 2));
   Print("H1 Swing  : H=", DoubleToString(lastSwingHighH1,_Digits), " L=", DoubleToString(lastSwingLowH1,_Digits));
   Print("M15 Swing : H=", DoubleToString(lastSwingHighM15,_Digits), " L=", DoubleToString(lastSwingLowM15,_Digits));
   Print("══════════════════════════════════════════");

   bool result = isBuy
      ? trade.Buy (volume, _Symbol, entry, sl, tp, "ICT SMC BUY V1.0")
      : trade.Sell(volume, _Symbol, entry, sl, tp, "ICT SMC SELL V1.0");

   if(result)
   {
      TodayTradeCount++;
      cisd5MinConfirmed = false;
      cisd1MinConfirmed = false;
      fvgCount1Min      = -1;

      ulong openDeal = trade.ResultDeal();
      if(openDeal > 0)
      {
         if(HistoryDealSelect(openDeal))
         {
            ulong posID = HistoryDealGetInteger(openDeal, DEAL_POSITION_ID);
            GlobalVariableSet("TWINS_RR_" + IntegerToString(posID), actualRR);
            Print("TRADE PLACED SUCCESSFULLY | Planned R:R=", DoubleToString(actualRR,2),
                  " | PosID=", posID);
         }
      }
   }
   else
   {
      Print("TRADE FAILED: ", trade.ResultRetcodeDescription());
      // FIX S: reset 1M trigger on any failure to break the per-tick retry loop.
      // Without this, the next tick re-enters PlaceTrade and hits the same error.
      cisd1MinConfirmed = false;
   }
}

//+------------------------------------------------------------------+
//| PANEL HELPERS                                                    |
//+------------------------------------------------------------------+
void PanelLoadPosition()
{
   string kx = PANEL_PREFIX + "PX", ky = PANEL_PREFIX + "PY";
   if(GlobalVariableCheck(kx)) PANEL_X = (int)GlobalVariableGet(kx);
   if(GlobalVariableCheck(ky)) PANEL_Y = (int)GlobalVariableGet(ky);
}

void PanelSavePosition()
{
   GlobalVariableSet(PANEL_PREFIX + "PX", PANEL_X);
   GlobalVariableSet(PANEL_PREFIX + "PY", PANEL_Y);
}

void PanelDeleteAll()
{
   ObjectsDeleteAll(0, PANEL_PREFIX);
   Comment("");
}

void PanelDeleteBody()
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, PANEL_PREFIX) == 0 &&
         nm != PANEL_PREFIX + "Header"    &&
         nm != PANEL_PREFIX + "ToggleBtn" &&
         nm != PANEL_PREFIX + "HdrBG"     &&
         nm != PANEL_PREFIX + "Title"     &&
         nm != PANEL_PREFIX + "Author")
         ObjectDelete(0, nm);
   }
}

void PanelRect(string name, int x, int y, int w, int h, color bg, color border=clrNONE)
{
   string full = PANEL_PREFIX + name;
   if(ObjectFind(0, full) < 0)
   {
      ObjectCreate(0, full, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, full, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, full, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, full, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, full, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, full, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, full, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, full, OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0, full, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, full, OBJPROP_COLOR,       border == clrNONE ? bg : border);
   ObjectSetInteger(0, full, OBJPROP_BACK,        false);
   ObjectSetInteger(0, full, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
}

void PanelLabel(string name, int x, int y, string text, color clr, int fontSize=8, string font="Consolas")
{
   string full = PANEL_PREFIX + name;
   if(ObjectFind(0, full) < 0)
   {
      ObjectCreate(0, full, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, full, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, full, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, full, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   }
   ObjectSetInteger(0, full, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, full, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, full, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, full, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, full, OBJPROP_FONTSIZE,  fontSize);
   ObjectSetString (0, full, OBJPROP_FONT,      font);
}

void PanelDivider(string name, int x, int y)
{
   PanelRect(name, x, y, PANEL_W-4, 1, PANEL_BORDER);
}

// Centered label — anchor at top-center of panel, useful for header text
void PanelLabelC(string name, int y, string text, color clr, int fontSize=8, string font="Consolas")
{
   string full = PANEL_PREFIX + name;
   int cx = PANEL_X + PANEL_W / 2;
   if(ObjectFind(0, full) < 0)
   {
      ObjectCreate(0, full, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, full, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, full, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, full, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, full, OBJPROP_ANCHOR,     ANCHOR_UPPER);
   }
   ObjectSetInteger(0, full, OBJPROP_XDISTANCE, cx);
   ObjectSetInteger(0, full, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, full, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, full, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, full, OBJPROP_FONTSIZE,  fontSize);
   ObjectSetString (0, full, OBJPROP_FONT,      font);
}

//+------------------------------------------------------------------+
//| OnChartEvent - drag handler                                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == PANEL_PREFIX + "ToggleBtn")
   {
      panelHidden = !panelHidden;
      GlobalVariableSet(PANEL_PREFIX + "Hidden", panelHidden ? 1 : 0);
      if(panelHidden) PanelDeleteBody();
      LastDisplayUpdate = 0;
      UpdateDisplay();
      return;
   }

   if(id == CHARTEVENT_OBJECT_CLICK && sparam == PANEL_PREFIX + "Header")
   {
      panelDragging = true;
      int mx = (int)lparam, my = (int)dparam;
      dragOffsetX = mx - PANEL_X;
      dragOffsetY = my - PANEL_Y;
   }
   if(id == CHARTEVENT_MOUSE_MOVE && panelDragging)
   {
      PANEL_X = (int)lparam - dragOffsetX;
      PANEL_Y = (int)dparam - dragOffsetY;
      int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      PANEL_X = MathMax(0, MathMin(chartW - PANEL_W, PANEL_X));
      PANEL_Y = MathMax(0, MathMin(chartH - 50, PANEL_Y));
      LastDisplayUpdate = 0;
      UpdateDisplay();
   }
   if(id == CHARTEVENT_MOUSE_MOVE && panelDragging && dparam == 0)
   {
      panelDragging = false;
      PanelSavePosition();
   }
   if(id == CHARTEVENT_CLICK)
   {
      if(panelDragging) { panelDragging = false; PanelSavePosition(); }
   }
}

//+------------------------------------------------------------------+
//| DISPLAY PANEL                                                    |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   if(TimeCurrent() - LastDisplayUpdate < 2) return;
   LastDisplayUpdate = TimeCurrent();

   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double pnl      = equity - balance;
   double spread   = (SymbolInfoDouble(_Symbol,SYMBOL_ASK) - SymbolInfoDouble(_Symbol,SYMBOL_BID)) / _Point;
   bool   inSess   = IsTradingTime();
   double gmtH     = GetGMTHour();
   bool   spreadOK = IsSpreadOK();

   // Auto-detect broker GMT offset from TimeCurrent() vs TimeGMT() — DST-aware
   datetime tSrv = TimeCurrent();
   datetime tGMT = TimeGMT();
   int detectedOffset = (int)MathRound((double)(tSrv - tGMT) / 3600.0);
   MqlDateTime dtSrv; TimeToStruct(tSrv, dtSrv);
   MqlDateTime dtGMT; TimeToStruct(tGMT, dtGMT);
   string srvTimeStr  = StringFormat("%02d:%02d:%02d", dtSrv.hour, dtSrv.min, dtSrv.sec);
   string gmtTimeStr  = StringFormat("%02d:%02d:%02d", dtGMT.hour, dtGMT.min, dtGMT.sec);
   string offsetLabel = "GMT" + (detectedOffset >= 0 ? "+" : "") + IntegerToString(detectedOffset);
   bool   offsetMatch = (detectedOffset == BrokerGMTOffset);

   double fast[1], slow[1];
   string trendStr = "FLAT";
   if(CopyBuffer(FastEMAHandle,0,1,1,fast)==1 && CopyBuffer(SlowEMAHandle,0,1,1,slow)==1)
      trendStr = (fast[0]>slow[0]) ? "BULLISH" : (fast[0]<slow[0]) ? "BEARISH" : "FLAT";

   MqlRates rates[2];
   string candleStr = "DOJI";
   if(CopyRates(_Symbol,PERIOD_M15,0,2,rates)==2)
      candleStr = (rates[1].close>rates[1].open) ? "BULLISH" : (rates[1].close<rates[1].open) ? "BEARISH" : "DOJI";

   bool   inOTE  = IsInOTEZone(SymbolInfoDouble(_Symbol,SYMBOL_BID), lastSwingHighH1, lastSwingLowH1);
   int    effFVG = GetEffectiveFVGRequirement();

   double curEquity = equity;
   if(curEquity > sessionPeakEquity && sessionPeakEquity > 0) sessionPeakEquity = curEquity;
   double curDD = (sessionPeakEquity > 0) ? sessionPeakEquity - curEquity : 0;
   if(curDD > sessionMaxDrawdown) sessionMaxDrawdown = curDD;

   double wr2    = (statTotalTrades>0) ? (double)statWins/statTotalTrades*100.0 : 0;
   double avgRR2 = (statWins>0) ? statSumRR/statWins : 0;
   double pf2    = (statTotalLoss>0) ? statTotalProfit/statTotalLoss : 0;
   double netPnL = statTotalProfit - statTotalLoss;

   if(GlobalVariableCheck(PANEL_PREFIX + "Hidden"))
      panelHidden = (GlobalVariableGet(PANEL_PREFIX + "Hidden") > 0.5);

   PanelLoadPosition();
   int x      = PANEL_X, w = PANEL_W, lh = PANEL_LINE_H;
   int px     = x + 8;
   int vx     = px + 130;
   int rowTop = 4;
   int row    = 0;
   int hdrH   = 52;        // header height for title + author
   int yb     = PANEL_Y;   // panel origin (never changes)

   // ── HEADER — always visible, even when panel is collapsed ──────────────
   PanelRect("HdrBG", x, yb, w, hdrH, PANEL_HDR_BG, PANEL_BORDER);
   PanelLabelC("Title",  yb+6,  EA_NAME,                       PANEL_GOLD,  12);
   PanelLabelC("Author", yb+28, "Created by: RATTANA CHHORM",  clrWhite,     9);
   PanelLabel ("Header", px, yb+4, "[drag]", C'50,50,70', 7);
   ObjectSetInteger(0, PANEL_PREFIX+"Header",    OBJPROP_SELECTABLE, true);
   PanelLabel ("ToggleBtn", x+w-46, yb+4, panelHidden ? "[show]" : "[hide]", PANEL_BLUE, 8);
   ObjectSetInteger(0, PANEL_PREFIX+"ToggleBtn", OBJPROP_SELECTABLE, true);

   if(panelHidden)
   {
      ObjectSetInteger(0, PANEL_PREFIX+"HdrBG", OBJPROP_YSIZE, hdrH);
      ChartRedraw(0);
      return;
   }

   // ── BODY ───────────────────────────────────────────────────────────────
   int y = yb + hdrH;   // content base: rows start here
   PanelRect("BG",    x, yb, w, 800,  PANEL_BG,     PANEL_BORDER);
   PanelRect("HdrBG", x, yb, w, hdrH, PANEL_HDR_BG, PANEL_BORDER);
   PanelLabelC("Title",  yb+6,  EA_NAME,                       PANEL_GOLD, 12);
   PanelLabelC("Author", yb+28, "Created by: RATTANA CHHORM",  clrWhite,    9);
   PanelLabel ("ToggleBtn", x+w-46, yb+4, "[hide]", PANEL_BLUE, 8);
   PanelLabel ("Header",   px,      yb+4, "[drag]", C'50,50,70', 7);

   row = 0;
   PanelDivider("D0", x+2, y+row*lh+rowTop/2); row++;

   PanelLabel("BalL", px,     y+row*lh+rowTop, "Balance  :", PANEL_TXT);
   PanelLabel("BalV", vx, y+row*lh+rowTop, "$"+DoubleToString(balance,2), PANEL_GREEN); row++;
   color eqClr = pnl>=0?PANEL_GREEN:PANEL_RED;
   PanelLabel("EqL",  px,     y+row*lh+rowTop, "Equity   :", PANEL_TXT);
   PanelLabel("EqV",  vx, y+row*lh+rowTop, "$"+DoubleToString(equity,2)+"  (P/L:$"+DoubleToString(pnl,2)+")", eqClr); row++;
   PanelDivider("D1", x+2, y+row*lh+rowTop/2); row++;

   // ── BROKER TIME (auto-detected, DST-aware) ─────────────────────────────
   PanelLabel("BkHd",  px, y+row*lh+rowTop, "BROKER TIME:", PANEL_GOLD); row++;
   PanelLabel("BkSl",  px,     y+row*lh+rowTop, "Server Time:", PANEL_TXT);
   PanelLabel("BkSv",  vx, y+row*lh+rowTop, srvTimeStr, PANEL_TXT); row++;
   PanelLabel("BkGl",  px,     y+row*lh+rowTop, "GMT Time   :", PANEL_TXT);
   PanelLabel("BkGv",  vx, y+row*lh+rowTop, gmtTimeStr, PANEL_TXT); row++;
   PanelLabel("BkOl",  px,     y+row*lh+rowTop, "GMT Offset :", PANEL_TXT);
   string offDisp = offsetLabel + (offsetMatch ? "" : "  [input:"+IntegerToString(BrokerGMTOffset)+"]");
   PanelLabel("BkOv",  vx, y+row*lh+rowTop, offDisp, offsetMatch?PANEL_GOLD:PANEL_RED); row++;
   PanelDivider("D1b", x+2, y+row*lh+rowTop/2); row++;
   // ───────────────────────────────────────────────────────────────────────
   PanelLabel("SeL",  px,     y+row*lh+rowTop, "Session   :", PANEL_TXT);
   PanelLabel("SeV",  vx, y+row*lh+rowTop, inSess?"ACTIVE":"CLOSED", inSess?PANEL_GREEN:PANEL_RED); row++;
   PanelLabel("TrL",  px,     y+row*lh+rowTop, "Trend     :", PANEL_TXT);
   color tClr = trendStr=="BULLISH"?PANEL_GREEN:trendStr=="BEARISH"?PANEL_RED:PANEL_TXT;
   PanelLabel("TrV",  vx, y+row*lh+rowTop, trendStr, tClr); row++;
   PanelLabel("CnL",  px,     y+row*lh+rowTop, "Candle    :", PANEL_TXT);
   color cClr = candleStr=="BULLISH"?PANEL_GREEN:candleStr=="BEARISH"?PANEL_RED:PANEL_TXT;
   PanelLabel("CnV",  vx, y+row*lh+rowTop, candleStr, cClr); row++;
   PanelLabel("SpL",  px,     y+row*lh+rowTop, "Spread    :", PANEL_TXT);
   PanelLabel("SpV",  vx, y+row*lh+rowTop, DoubleToString(spread,0)+" pts "+(spreadOK?"OK":"BLOCKED"), spreadOK?PANEL_GREEN:PANEL_RED); row++;
   PanelLabel("TdL",  px,     y+row*lh+rowTop, "Trades    :", PANEL_TXT);
   PanelLabel("TdV",  vx, y+row*lh+rowTop, IntegerToString(TodayTradeCount)+"/"+IntegerToString(MaxTradesPerDay), PANEL_TXT); row++;
   PanelLabel("DLl",  px,     y+row*lh+rowTop, "Day Losses:", PANEL_TXT);
   bool dlimitHit = (MaxDailyLossTrades>0 && TodayLossTrades>=MaxDailyLossTrades);
   PanelLabel("DLv",  vx, y+row*lh+rowTop, IntegerToString(TodayLossTrades)+"/"+IntegerToString(MaxDailyLossTrades)+(dlimitHit?" HALTED":""), dlimitHit?PANEL_RED:PANEL_TXT); row++;
   PanelLabel("CLl",  px,     y+row*lh+rowTop, "ConLosses :", PANEL_TXT);
   PanelLabel("CLv",  vx, y+row*lh+rowTop, IntegerToString(consecutiveLosses)+"/"+IntegerToString(MaxConsecutiveLosses), consecutiveLosses>5?PANEL_RED:PANEL_TXT); row++;
   PanelLabel("WSl",  px,     y+row*lh+rowTop, "Win Streak:", PANEL_TXT);
   PanelLabel("WSv",  vx, y+row*lh+rowTop, IntegerToString(consecutiveWins), consecutiveWins>0?PANEL_GREEN:PANEL_TXT); row++;
   PanelDivider("D2", x+2, y+row*lh+rowTop/2); row++;

   PanelLabel("SeqH", px, y+row*lh+rowTop, "ICT TWINS SEQUENCE:", PANEL_GOLD); row++;
   PanelLabel("S1l",  px, y+row*lh+rowTop, "[1] HTF Level  :", PANEL_TXT);
   string s1v = !HTFLevelRequired ? "DISABLED" : (htfLevelReached ? "PASS" : "WAIT");
   color  s1c = !HTFLevelRequired ? PANEL_GOLD  : (htfLevelReached ? PANEL_GREEN : PANEL_TXT);
   PanelLabel("S1v",  vx, y+row*lh+rowTop, s1v, s1c); row++;
   string s2v = cisd5MinConfirmed?"CONFIRMED ("+string(cisd5MinIsBearish?"BEAR":"BULL")+")":"waiting...";
   PanelLabel("S2l",  px, y+row*lh+rowTop, "[2] 5M CISD    :", PANEL_TXT);
   PanelLabel("S2v",  vx, y+row*lh+rowTop, s2v, cisd5MinConfirmed?PANEL_GREEN:PANEL_TXT); row++;
   string s3v = IntegerToString(fvgCount1Min)+"/"+IntegerToString(effFVG)+(RelaxedMode?" (R)":"");
   PanelLabel("S3l",  px, y+row*lh+rowTop, "[3] 1M FVGs    :", PANEL_TXT);
   PanelLabel("S3v",  vx, y+row*lh+rowTop, s3v, (fvgCount1Min>=effFVG||effFVG==0)?PANEL_GREEN:PANEL_TXT); row++;
   PanelLabel("S4l",  px, y+row*lh+rowTop, "[4] H1 Swings  :", PANEL_TXT);
   PanelLabel("S4v",  vx, y+row*lh+rowTop, lastSwingHighH1>0?"PASS":"WAIT", lastSwingHighH1>0?PANEL_GREEN:PANEL_TXT); row++;
   bool m15ok = lastSwingHighM15>0||lastSwingLowM15>0;
   PanelLabel("S5l",  px, y+row*lh+rowTop, "[5] M15 Swings :", PANEL_TXT);
   PanelLabel("S5v",  vx, y+row*lh+rowTop, m15ok?"PASS":"ATR FB", m15ok?PANEL_GREEN:PANEL_GOLD); row++;
   PanelLabel("S6l",  px, y+row*lh+rowTop, "[6] OTE Zone   :", PANEL_TXT);
   PanelLabel("S6v",  vx, y+row*lh+rowTop, inOTE?"PASS":"WAIT", inOTE?PANEL_GREEN:PANEL_TXT); row++;
   string s7v = cisd1MinConfirmed?"READY ("+string(cisd1MinIsBearish?"BEAR":"BULL")+")":"waiting...";
   PanelLabel("S7l",  px, y+row*lh+rowTop, "[7] 1M CISD    :", PANEL_TXT);
   PanelLabel("S7v",  vx, y+row*lh+rowTop, s7v, cisd1MinConfirmed?PANEL_GREEN:PANEL_TXT); row++;
   string s8v = (cisd5MinConfirmed&&cisd1MinConfirmed)?(cisd5MinIsBearish==cisd1MinIsBearish?"AGREE":"CONFLICT"):"WAIT";
   PanelLabel("S8l",  px, y+row*lh+rowTop, "[8] Direction  :", PANEL_TXT);
   PanelLabel("S8v",  vx, y+row*lh+rowTop, s8v, s8v=="AGREE"?PANEL_GREEN:s8v=="CONFLICT"?PANEL_RED:PANEL_TXT); row++;
   PanelDivider("D3", x+2, y+row*lh+rowTop/2); row++;

   PanelLabel("SwH",  px, y+row*lh+rowTop, "SWINGS:", PANEL_GOLD); row++;
   PanelLabel("H1l",  px, y+row*lh+rowTop, "H1  :", PANEL_TXT);
   PanelLabel("H1v",  px+50, y+row*lh+rowTop, "H="+DoubleToString(lastSwingHighH1,_Digits)+"  L="+DoubleToString(lastSwingLowH1,_Digits), PANEL_BLUE); row++;
   PanelLabel("M15l", px, y+row*lh+rowTop, "M15 :", PANEL_TXT);
   PanelLabel("M15v", px+50, y+row*lh+rowTop, "H="+DoubleToString(lastSwingHighM15,_Digits)+"  L="+DoubleToString(lastSwingLowM15,_Digits), PANEL_BLUE); row++;
   PanelDivider("D4", x+2, y+row*lh+rowTop/2); row++;

   PanelLabel("SsH",  px, y+row*lh+rowTop, "SESSIONS:", PANEL_GOLD); row++;
   if(SessionSydney)
   {
      bool a = SessionActiveNow("Sydney");
      PanelLabel("SsYl",px,y+row*lh+rowTop,"Sydney    :",PANEL_TXT);
      PanelLabel("SsYv",vx,y+row*lh+rowTop,"(22-07) "+(a?"ACTIVE":"CLOSED"), a?PANEL_GREEN:PANEL_RED); row++;
   }
   if(SessionTokyo)
   {
      bool a = SessionActiveNow("Tokyo");
      PanelLabel("SsTl",px,y+row*lh+rowTop,"Tokyo     :",PANEL_TXT);
      PanelLabel("SsTv",vx,y+row*lh+rowTop,"(00-09) "+(a?"ACTIVE":"CLOSED"), a?PANEL_GREEN:PANEL_RED); row++;
   }
   if(SessionLondon)
   {
      bool a = SessionActiveNow("London");
      PanelLabel("SsLl",px,y+row*lh+rowTop,"London    :",PANEL_TXT);
      PanelLabel("SsLv",vx,y+row*lh+rowTop,"(08-17) "+(a?"ACTIVE":"CLOSED"), a?PANEL_GREEN:PANEL_RED); row++;
   }
   if(SessionNewYork)
   {
      bool a = SessionActiveNow("NewYork");
      PanelLabel("SsNl",px,y+row*lh+rowTop,"New York  :",PANEL_TXT);
      PanelLabel("SsNv",vx,y+row*lh+rowTop,"(13-22) "+(a?"ACTIVE":"CLOSED"), a?PANEL_GREEN:PANEL_RED); row++;
   }
   if(OverlapLondonNY)
   {
      bool a = SessionActiveNow("Overlap");
      PanelLabel("SsOl",px,y+row*lh+rowTop,"LDN+NY    :",PANEL_TXT);
      PanelLabel("SsOv",vx,y+row*lh+rowTop,"(13-17) "+(a?"ACTIVE":"CLOSED")+" BEST", a?PANEL_GREEN:PANEL_RED); row++;
   }
   if(OverlapTokyoLondon)
   {
      bool a = SessionActiveNow("Tokyo") && SessionActiveNow("London");
      PanelLabel("SsTLl",px,y+row*lh+rowTop,"TYO+LDN   :",PANEL_TXT);
      PanelLabel("SsTLv",vx,y+row*lh+rowTop,"(08-09) "+(a?"ACTIVE":"CLOSED"), a?PANEL_GREEN:PANEL_RED); row++;
   }
   // FIX N+P: Show active filter info
   PanelLabel("FLl",  px,     y+row*lh+rowTop, "Entry Start:", PANEL_TXT);
   PanelLabel("FLv",  vx, y+row*lh+rowTop, BestHoursOnly?"08:30 GMT":"(all session)", PANEL_GOLD); row++;
   PanelLabel("FPl",  px,     y+row*lh+rowTop, "Fri Cutoff :", PANEL_TXT);
   PanelLabel("FPv",  vx, y+row*lh+rowTop, CloseOnFriday?(IntegerToString(FridayCloseHour)+":00 GMT"):"OFF", CloseOnFriday?PANEL_GOLD:PANEL_TXT); row++;
   PanelDivider("D5", x+2, y+row*lh+rowTop/2); row++;

   PanelLabel("StH",  px, y+row*lh+rowTop, "STATISTICS (persistent):", PANEL_GOLD); row++;
   string trv = IntegerToString(statTotalTrades)+" (W:"+IntegerToString(statWins)+" L:"+IntegerToString(statLosses)+")";
   PanelLabel("StTl", px,     y+row*lh+rowTop, "Trades      :", PANEL_TXT);
   PanelLabel("StTv", vx, y+row*lh+rowTop, trv, PANEL_TXT); row++;
   PanelLabel("WRl",  px,     y+row*lh+rowTop, "Win Rate    :", PANEL_TXT);
   PanelLabel("WRv",  vx, y+row*lh+rowTop, DoubleToString(wr2,1)+"%", wr2>=50?PANEL_GREEN:wr2>=40?PANEL_GOLD:PANEL_RED); row++;
   PanelLabel("ARl",  px,     y+row*lh+rowTop, "Avg RR      :", PANEL_TXT);
   PanelLabel("ARv",  vx, y+row*lh+rowTop, DoubleToString(avgRR2,2), avgRR2>=1.5?PANEL_GREEN:PANEL_TXT); row++;
   PanelLabel("PFl",  px,     y+row*lh+rowTop, "Profit Factor:", PANEL_TXT);
   PanelLabel("PFv",  vx, y+row*lh+rowTop, DoubleToString(pf2,2), pf2>=1.2?PANEL_GREEN:pf2>=1.0?PANEL_GOLD:PANEL_RED); row++;
   PanelLabel("NPl",  px,     y+row*lh+rowTop, "Net P&L     :", PANEL_TXT);
   PanelLabel("NPv",  vx, y+row*lh+rowTop, "$"+DoubleToString(netPnL,2), netPnL>=0?PANEL_GREEN:PANEL_RED); row++;
   PanelDivider("D6", x+2, y+row*lh+rowTop/2); row++;

   PanelLabel("DDH",  px, y+row*lh+rowTop, "DRAWDOWN:", PANEL_GOLD); row++;
   PanelLabel("DCl",  px,     y+row*lh+rowTop, "Current DD  :", PANEL_TXT);
   PanelLabel("DCv",  vx, y+row*lh+rowTop, "$"+DoubleToString(curDD,2), curDD>0?PANEL_RED:PANEL_GREEN); row++;
   PanelLabel("DMl",  px,     y+row*lh+rowTop, "Session Max :", PANEL_TXT);
   PanelLabel("DMv",  vx, y+row*lh+rowTop, "$"+DoubleToString(sessionMaxDrawdown,2), PANEL_TXT); row++;
   string lbv = lastFailedStep>0?"STEP "+IntegerToString(lastFailedStep)+" - "+lastFailedStepDesc:"None";
   PanelLabel("LBl",  px,     y+row*lh+rowTop, "Last Block  :", PANEL_TXT);
   PanelLabel("LBv",  vx, y+row*lh+rowTop, lbv, lastFailedStep>0?PANEL_GOLD:PANEL_GREEN); row++;
   PanelDivider("D7", x+2, y+row*lh+rowTop/2); row++;

   PanelLabel("SLl",  px,     y+row*lh+rowTop, "SL Buffer   :", PANEL_TXT);
   PanelLabel("SLv",  vx, y+row*lh+rowTop, IntegerToString(SLBufferPips)+" pips M15 swing", PANEL_TXT); row++;
   PanelLabel("OTl",  px,     y+row*lh+rowTop, "OTE Range   :", PANEL_TXT);
   PanelLabel("OTv",  vx, y+row*lh+rowTop, DoubleToString(OTEMinPercent*100,0)+"-"+DoubleToString(OTEMaxPercent*100,0)+"%", PANEL_GOLD); row++;
   PanelLabel("MSl",  px,     y+row*lh+rowTop, "Max SL Pips :", PANEL_TXT);
   PanelLabel("MSv",  vx, y+row*lh+rowTop, IntegerToString(MaxSLPips)+" pips", PANEL_GOLD); row++;
   PanelLabel("FTl",  px,     y+row*lh+rowTop, "ForceTrades :", PANEL_TXT);
   PanelLabel("FTv",  vx, y+row*lh+rowTop, ForceTrades?"ON (TEST)":"OFF", ForceTrades?PANEL_RED:PANEL_GREEN); row++;
   PanelLabel("DMdl", px,     y+row*lh+rowTop, "DebugMode   :", PANEL_TXT);
   PanelLabel("DMdv", vx, y+row*lh+rowTop, DebugMode?"ON":"OFF", DebugMode?PANEL_GOLD:PANEL_TXT); row++;
   PanelLabel("RMl",  px,     y+row*lh+rowTop, "RelaxedMode :", PANEL_TXT);
   PanelLabel("RMv",  vx, y+row*lh+rowTop, RelaxedMode?"ON (TEST)":"OFF", RelaxedMode?PANEL_GOLD:PANEL_GREEN); row++;

   int finalH = (y - yb) + row*lh + rowTop + 8;   // includes header height
   ObjectSetInteger(0, PANEL_PREFIX+"BG", OBJPROP_YSIZE, finalH);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| MAIN TICK ENGINE                                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDisplay();
   CheckFridayClose();
   ApplyBreakeven();
   ApplyTrailingStop();

   if(ForceTrades)
   {
      static datetime lastForce = 0;
      if(TimeCurrent() - lastForce >= 60)
      {
         if(CanTrade())
         {
            lastForce = TimeCurrent();
            PlaceTrade();
         }
      }
      return;
   }

   if(!CanTrade())      return;
   if(!IsTradingTime()) return;

   datetime barTime[1];
   if(CopyTime(_Symbol, PERIOD_M15, 0, 1, barTime) != 1) return;

   if(PostTradeCooldownMin > 0 &&
      LastTradeCloseTime > 0 &&
      TimeCurrent() - LastTradeCloseTime < (datetime)(PostTradeCooldownMin * 60))
   {
      return;
   }

   if(barTime[0] != LastBarTime)
   {
      LastBarTime       = barTime[0];
      cisd1MinConfirmed = false;
      UpdateContextState();
   }

   bool isBuy = true;
   if(CheckTwinsSequence(isBuy))
      PlaceTrade(isBuy);
}
//+------------------------------------------------------------------+
