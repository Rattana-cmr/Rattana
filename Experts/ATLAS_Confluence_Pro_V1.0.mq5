//+------------------------------------------------------------------+
//|                                  ATLAS CONFLUENCE PRO V1.0       |
//|                    INDIVIDUAL SESSION CONTROLS                   |
//|                           Created By - Stephen REEN              |
//+------------------------------------------------------------------+
#property copyright "Stephen REEN"
#property version   "1.0"
#property strict

#include <Trade/Trade.mqh>

#define DPFX "CONF_"

CTrade trade;

//===================== RISK MANAGEMENT =====================//
input group "========== RISK MANAGEMENT =========="
input double   RiskPercent            = 0.5;      // Risk per trade (%)
input double   FixedLot               = 0.0;      // Fixed lot (0 = use risk%)
input double   MaxLotSize             = 0.05;     // Hard cap on lot size
input double   MaxDailyLossPercent    = 10.0;     // Max daily loss (%)
input int      MaxTradesPerDay        = 10;       // Max trades per day
input int      MaxOpenPositions       = 3;        // Max concurrent open positions
input double   RewardRiskRatio        = 1.5;      // Reward:Risk ratio

//===================== TRADE FILTERS =====================//
input group "========== TRADE FILTERS =========="
input bool     UseTimeFilter          = false;    // Trading hours (false = 24/7)
input int      MaxSpreadPoints        = 0;        // Max spread (0 = disable)
input int      MinStopDistance        = 20;       // Min stop distance in points
input int      MaxConsecutiveLosses   = 10;       // Stop after N consecutive losses
input int      PostTradeCooldownMin   = 15;       // Cooldown after open/close before next entry (min, 0=disable)

//===================== INDIVIDUAL SESSIONS =====================//
input group "========== INDIVIDUAL SESSIONS (GMT TIME) =========="
input bool     SessionSydney          = false;    // Sydney (22:00-07:00 GMT)
input bool     SessionTokyo           = false;    // Tokyo (00:00-09:00 GMT)
input bool     SessionLondon          = true;     // London (08:00-17:00 GMT)
input bool     SessionNewYork         = true;     // New York (13:00-22:00 GMT)

//===================== OVERLAP SESSIONS =====================//
input group "========== OVERLAP SESSIONS =========="
input bool     OverlapLondonNY        = true;     // London+NY Overlap (13:00-17:00 GMT)
input bool     OverlapTokyoLondon     = false;    // Tokyo+London Overlap (08:00-09:00 GMT)

//===================== ENTRY FILTERS =====================//
input group "========== ENTRY FILTERS =========="
input bool     UseH4Filter            = false;    // H4 trend must align with H1
input bool     UseRSIFilter           = false;    // RSI filter
input int      RSIPeriod              = 14;       // RSI period (H1)
input int      RSIOverbought          = 65;       // Max RSI for BUY (not overbought)
input int      RSIOversold            = 35;       // Min RSI for SELL (not oversold)
input bool     UsePullbackFilter      = false;    // Price must be near 50 EMA
input double   PullbackATRMultiplier  = 2.5;      // Max ATR distance from 50 EMA
input bool     UseATRFilter           = false;    // Volatility gate
input double   ATRMinPoints           = 50.0;     // Min ATR (avoid dead markets)
input double   ATRMaxPoints           = 500.0;    // Max ATR (avoid news spikes)

//===================== STOP LOSS =====================//
input group "========== STOP LOSS =========="
input int      SLBufferPips           = 15;       // SL buffer behind swing (pips)
input int      MaxSLPips              = 200;      // Cap SL distance from entry (pips, 0=disable)
input bool     UseTrailingStop        = false;    // Enable trailing stop
input int      TrailingStartPips      = 30;       // Start trailing after N pips profit
input int      TrailingStepPips       = 10;       // Trail step in pips

//===================== POSITION MANAGEMENT =====================//
input group "========== POSITION MANAGEMENT =========="
input bool     CloseOnFriday          = false;    // Close positions on Friday
input int      FridayCloseHour        = 20;       // Friday close hour (GMT)
input bool     UseBreakeven           = false;    // Move SL to breakeven
input int      BreakevenTriggerPips   = 20;       // Pips profit to trigger breakeven
input bool     UsePartialClose        = false;    // Partial close at profit target
input int      PartialClosePips       = 50;       // Pips profit to trigger partial close
input int      PartialClosePercent    = 50;       // Percent of position to close

//===================== SWING DETECTION =====================//
input group "========== SWING DETECTION =========="
input int      SwingLookbackBars      = 50;       // H1 bars to scan
input int      SwingConfirmBars       = 5;        // Bars each side to confirm
input bool     ShowSwingLines         = true;     // Draw swing lines on chart

//===================== DEBUG =====================//
input group "========== DEBUG =========="
input bool     ForceTrades            = false;    // Force trades (testing only)
input bool     UsePythonRisk          = false;    // AI risk control

//===================== MULTI-SYMBOL (EXTRA) =====================//
input group "========== MULTI-SYMBOL (EXTRA) =========="
input string   ExtraTradeSymbols      = "GBPUSD,EURUSD,XAGUSD"; // CSV list of extra symbols. Empty = single-symbol behavior
input bool     ExtraSymbolsEnabled    = true;     // Master kill-switch for the extra-symbol engine
input double   ExtraRiskPercent       = 0.0;      // Risk % per trade for extras. 0 = reuse RiskPercent
input int      ExtraMaxTradesPerDay   = 0;        // Per-extra-symbol daily trade cap. 0 = use MaxTradesPerDay
input bool     ExtraDebugLog          = false;    // Print debug info for the extra-symbol engine

//===================== REGIME FILTER (TREND STRENGTH) =====================//
input group "========== REGIME FILTER (TREND STRENGTH) =========="
input bool            UseRegimeFilter  = false;      // Only trade when trending (ADX gate). Skips ranging/chop regimes.
input ENUM_TIMEFRAMES RegimeTF         = PERIOD_H4;  // Timeframe the trend-strength (ADX) is measured on
input int             RegimeADXPeriod  = 14;         // ADX period (Wilder standard = 14)
input double          RegimeMinADX     = 22.0;       // Minimum ADX to allow entries (below = ranging; textbook trend ~20-25)

//===================== GLOBAL VARIABLES =====================//
int ATRHandle;
int FastEMAHandle;
int SlowEMAHandle;
int H4FastEMAHandle;
int H4SlowEMAHandle;
int RSIHandle;
int ADXHandle = INVALID_HANDLE;   // [regime] trend-strength gate
datetime LastBarTime  = 0;
datetime LastTradeCloseOrOpenTime = 0;
int TodayTradeCount   = 0;
int LastTradeDay      = 0;
double TodayLoss      = 0;
int consecutiveLosses = 0;
int SwingLineCount    = 0;

int  PanelX         = 10;
int  PanelY         = 25;
bool PanelCollapsed = false;
bool PanelDragging  = false;
int  DragOffsetX    = 0;
int  DragOffsetY    = 0;

//===================== MULTI-SYMBOL (EXTRA) STATE =====================//
#define CONF_MAGIC 888777
struct ConfSymState
{
   string   name;
   int      atrHandle, fastEMAHandle, slowEMAHandle, h4FastEMAHandle, h4SlowEMAHandle, rsiHandle, adxHandle;
   double   pipFactor;
   datetime lastBarTime, lastTradeCloseOrOpenTime;
   int      todayTradeCount, lastTradeDay, consecutiveLosses;
   bool     isActive;
};
ConfSymState extraSym[];
int          extraSymbolCount = 0;

//+------------------------------------------------------------------+
//| REGIME FILTER — ADX trend-strength gate                         |
//| Reads the ADX main line; fails OPEN (returns -1 -> never blocks) |
//| on a data gap so a transient read never halts trading.          |
//+------------------------------------------------------------------+
double GetADXFor(int handle)
{
   double a[1];
   if(handle != INVALID_HANDLE && CopyBuffer(handle, 0, 1, 1, a) == 1) return a[0];
   return -1.0;
}
bool RegimeBlocksEntry(int adxHandle)
{
   if(!UseRegimeFilter) return false;
   double adx = GetADXFor(adxHandle);
   return (adx >= 0.0 && adx < RegimeMinADX);
}

//+------------------------------------------------------------------+
//| INITIALIZATION                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ATRHandle       = iATR(_Symbol, PERIOD_M15, 14);
   FastEMAHandle   = iMA(_Symbol, PERIOD_H1, 50,  0, MODE_EMA, PRICE_CLOSE);
   SlowEMAHandle   = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
   H4FastEMAHandle = iMA(_Symbol, PERIOD_H4, 50,  0, MODE_EMA, PRICE_CLOSE);
   H4SlowEMAHandle = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   RSIHandle       = iRSI(_Symbol, PERIOD_H1, RSIPeriod, PRICE_CLOSE);
   ADXHandle       = iADX(_Symbol, RegimeTF, RegimeADXPeriod);  // [regime]

   trade.SetExpertMagicNumber(888777);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(_Symbol);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   Print("========================================");
   Print("ATLAS Confluence Pro V1.0 - Created By Stephen REEN");
   Print("H4 Filter:      ", UseH4Filter       ? "ON" : "OFF");
   Print("RSI Filter:     ", UseRSIFilter       ? "ON" : "OFF");
   Print("Pullback Filter:", UsePullbackFilter  ? "ON" : "OFF");
   Print("ATR Filter:     ", UseATRFilter       ? "ON" : "OFF");
   Print("Time Filter:    ", UseTimeFilter      ? "ON" : "OFF (24/7)");
   Print("Partial Close:  ", UsePartialClose    ? "ON" : "OFF");
   Print("Swing: H1 lookback=", SwingLookbackBars, " confirm=+-", SwingConfirmBars, " bars");
   Print("========================================");

   ParseExtraSymbolList();   // [multi-symbol] build the extra-symbol engine (no-op when disabled/empty)

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINITIALIZATION                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ATRHandle       != INVALID_HANDLE) IndicatorRelease(ATRHandle);
   if(FastEMAHandle   != INVALID_HANDLE) IndicatorRelease(FastEMAHandle);
   if(SlowEMAHandle   != INVALID_HANDLE) IndicatorRelease(SlowEMAHandle);
   if(H4FastEMAHandle != INVALID_HANDLE) IndicatorRelease(H4FastEMAHandle);
   if(H4SlowEMAHandle != INVALID_HANDLE) IndicatorRelease(H4SlowEMAHandle);
   if(RSIHandle       != INVALID_HANDLE) IndicatorRelease(RSIHandle);
   if(ADXHandle       != INVALID_HANDLE) IndicatorRelease(ADXHandle);  // [regime]
   for(int i = 0; i < extraSymbolCount; i++)   // [multi-symbol] release extra-symbol handles
   {
      if(extraSym[i].atrHandle       != INVALID_HANDLE) IndicatorRelease(extraSym[i].atrHandle);
      if(extraSym[i].fastEMAHandle   != INVALID_HANDLE) IndicatorRelease(extraSym[i].fastEMAHandle);
      if(extraSym[i].slowEMAHandle   != INVALID_HANDLE) IndicatorRelease(extraSym[i].slowEMAHandle);
      if(extraSym[i].h4FastEMAHandle != INVALID_HANDLE) IndicatorRelease(extraSym[i].h4FastEMAHandle);
      if(extraSym[i].h4SlowEMAHandle != INVALID_HANDLE) IndicatorRelease(extraSym[i].h4SlowEMAHandle);
      if(extraSym[i].rsiHandle       != INVALID_HANDLE) IndicatorRelease(extraSym[i].rsiHandle);
      if(extraSym[i].adxHandle       != INVALID_HANDLE) IndicatorRelease(extraSym[i].adxHandle);  // [regime]
   }
   ObjectsDeleteAll(0, "SwingLine_");
   ObjectsDeleteAll(0, DPFX);
   Comment("");
   Print("ATLAS Confluence Pro V1.0 SHUTDOWN");
}

//+------------------------------------------------------------------+
//| SESSION CHECKS                                                   |
//+------------------------------------------------------------------+
bool InSydneySession()
{
   if(!SessionSydney) return false;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   double t = dt.hour + dt.min / 60.0;
   return (t >= 22.00 || t < 7.00);
}

bool InTokyoSession()
{
   if(!SessionTokyo) return false;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   double t = dt.hour + dt.min / 60.0;
   return (t >= 0.00 && t < 9.00);
}

bool InLondonSession()
{
   if(!SessionLondon) return false;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   double t = dt.hour + dt.min / 60.0;
   return (t >= 8.00 && t < 17.00);
}

bool InNewYorkSession()
{
   if(!SessionNewYork) return false;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   double t = dt.hour + dt.min / 60.0;
   return (t >= 13.00 && t < 22.00);
}

bool InLondonNYOverlap()
{
   if(!OverlapLondonNY) return false;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   double t = dt.hour + dt.min / 60.0;
   return (t >= 13.00 && t < 17.00);
}

bool InTokyoLondonOverlap()
{
   if(!OverlapTokyoLondon) return false;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   double t = dt.hour + dt.min / 60.0;
   return (t >= 8.00 && t < 9.00);
}

//+------------------------------------------------------------------+
//| CHECK TRADING TIME                                               |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   if(!UseTimeFilter) return true;
   if(InSydneySession())      return true;
   if(InTokyoSession())       return true;
   if(InLondonSession())      return true;
   if(InNewYorkSession())     return true;
   if(InLondonNYOverlap())    return true;
   if(InTokyoLondonOverlap()) return true;
   return false;
}

//+------------------------------------------------------------------+
//| CHECK SPREAD                                                     |
//+------------------------------------------------------------------+
bool IsSpreadOK()
{
   if(MaxSpreadPoints <= 0) return true;
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                    SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   if(spread > MaxSpreadPoints)
   {
      Print("Spread too high: ", spread, " > ", MaxSpreadPoints);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| FRIDAY CLOSE                                                     |
//+------------------------------------------------------------------+
void CheckFridayClose()
{
   if(!CloseOnFriday) return;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   if(dt.day_of_week == 5 && dt.hour >= FridayCloseHour)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && PositionSelectByTicket(ticket))
         {
            if(PositionGetInteger(POSITION_MAGIC) == CONF_MAGIC)  // all magic positions (chart + extras)
            {
               trade.PositionClose(ticket);
               Print("Friday close: ticket ", ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| TRAILING STOP                                                    |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
   if(!UseTrailingStop) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != CONF_MAGIC) continue;
      string posSym = PositionGetString(POSITION_SYMBOL);
      double pt = SymbolInfoDouble(posSym, SYMBOL_POINT);
      int    dg = (int)SymbolInfoInteger(posSym, SYMBOL_DIGITS);
      double pf = PipFactorFor(posSym);

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentPrice = type == POSITION_TYPE_BUY ?
                           SymbolInfoDouble(posSym, SYMBOL_BID) :
                           SymbolInfoDouble(posSym, SYMBOL_ASK);
      double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL  = PositionGetDouble(POSITION_SL);
      double currentTP  = PositionGetDouble(POSITION_TP);

      double profitPips = type == POSITION_TYPE_BUY ?
                         (currentPrice - openPrice) / pt / pf :
                         (openPrice - currentPrice) / pt / pf;

      if(profitPips >= TrailingStartPips)
      {
         double newSL = type == POSITION_TYPE_BUY ?
                       currentPrice - TrailingStepPips * pf * pt :
                       currentPrice + TrailingStepPips * pf * pt;
         newSL = NormalizeDouble(newSL, dg);

         if((type == POSITION_TYPE_BUY  && newSL > currentSL) ||
            (type == POSITION_TYPE_SELL && newSL < currentSL))
         {
            if(trade.PositionModify(ticket, newSL, currentTP))
               Print("Trailing stop updated: ticket ", ticket, " SL=", newSL);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| BREAKEVEN                                                        |
//+------------------------------------------------------------------+
void ApplyBreakeven()
{
   if(!UseBreakeven) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != CONF_MAGIC) continue;
      string posSym = PositionGetString(POSITION_SYMBOL);
      double pt = SymbolInfoDouble(posSym, SYMBOL_POINT);
      int    dg = (int)SymbolInfoInteger(posSym, SYMBOL_DIGITS);
      double pf = PipFactorFor(posSym);

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL    = PositionGetDouble(POSITION_SL);
      double currentTP    = PositionGetDouble(POSITION_TP);
      double currentPrice = type == POSITION_TYPE_BUY ?
                           SymbolInfoDouble(posSym, SYMBOL_BID) :
                           SymbolInfoDouble(posSym, SYMBOL_ASK);

      double profitPips = type == POSITION_TYPE_BUY ?
                         (currentPrice - openPrice) / pt / pf :
                         (openPrice - currentPrice) / pt / pf;

      if(profitPips >= BreakevenTriggerPips)
      {
         double beSL = type == POSITION_TYPE_BUY ?
                      openPrice + 1 * pt :
                      openPrice - 1 * pt;
         beSL = NormalizeDouble(beSL, dg);

         if((type == POSITION_TYPE_BUY  && beSL > currentSL) ||
            (type == POSITION_TYPE_SELL && beSL < currentSL))
         {
            if(trade.PositionModify(ticket, beSL, currentTP))
               Print("Breakeven set: ticket ", ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| PARTIAL CLOSE                                                    |
//| Uses GlobalVariable per ticket to ensure it fires only once.    |
//+------------------------------------------------------------------+
void ApplyPartialClose()
{
   if(!UsePartialClose) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != CONF_MAGIC) continue;
      string posSym = PositionGetString(POSITION_SYMBOL);
      double pt = SymbolInfoDouble(posSym, SYMBOL_POINT);
      double pf = PipFactorFor(posSym);

      string pcKey = "CONF_PC_" + IntegerToString(ticket);
      if(GlobalVariableCheck(pcKey)) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = type == POSITION_TYPE_BUY ?
                           SymbolInfoDouble(posSym, SYMBOL_BID) :
                           SymbolInfoDouble(posSym, SYMBOL_ASK);

      double profitPips = type == POSITION_TYPE_BUY ?
                         (currentPrice - openPrice) / pt / pf :
                         (openPrice - currentPrice) / pt / pf;

      if(profitPips >= PartialClosePips)
      {
         double volume    = PositionGetDouble(POSITION_VOLUME);
         double minLot    = SymbolInfoDouble(posSym, SYMBOL_VOLUME_MIN);
         double lotStep   = SymbolInfoDouble(posSym, SYMBOL_VOLUME_STEP);
         double closeVol  = NormalizeDouble(volume * PartialClosePercent / 100.0, 2);
         closeVol         = MathMax(minLot, MathFloor(closeVol / lotStep) * lotStep);

         if(closeVol >= minLot && closeVol < volume)
         {
            if(trade.PositionClosePartial(ticket, closeVol))
            {
               GlobalVariableSet(pcKey, 1);
               Print("Partial close: ticket ", ticket, " | ", closeVol, " lots at +", DoubleToString(profitPips, 1), " pips");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ATR POINTS                                                       |
//+------------------------------------------------------------------+
double GetATRPoints()
{
   double atr[1];
   if(CopyBuffer(ATRHandle, 0, 1, 1, atr) == 1)
      return atr[0] / _Point;
   return 20;
}

//+------------------------------------------------------------------+
//| H1 TREND DIRECTION                                               |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
   double fast[1], slow[1];
   if(CopyBuffer(FastEMAHandle, 0, 1, 1, fast) != 1) return 0;
   if(CopyBuffer(SlowEMAHandle, 0, 1, 1, slow) != 1) return 0;
   if(fast[0] > slow[0]) return 1;
   if(fast[0] < slow[0]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| H4 TREND DIRECTION                                               |
//+------------------------------------------------------------------+
int GetH4TrendDirection()
{
   double fast[1], slow[1];
   if(CopyBuffer(H4FastEMAHandle, 0, 1, 1, fast) != 1) return 0;
   if(CopyBuffer(H4SlowEMAHandle, 0, 1, 1, slow) != 1) return 0;
   if(fast[0] > slow[0]) return 1;
   if(fast[0] < slow[0]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| M15 CANDLE DIRECTION                                             |
//+------------------------------------------------------------------+
int GetCandleDirection()
{
   MqlRates rates[2];
   if(CopyRates(_Symbol, PERIOD_M1, 0, 2, rates) != 2) return 0;
   if(rates[0].close > rates[0].open) return 1;
   if(rates[0].close < rates[0].open) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| RSI VALUE (for display)                                          |
//+------------------------------------------------------------------+
double GetRSIValue()
{
   double rsi[1];
   if(CopyBuffer(RSIHandle, 0, 1, 1, rsi) == 1)
      return rsi[0];
   return 50;
}

//+------------------------------------------------------------------+
//| RSI FILTER                                                       |
//| BUY: RSI must be below overbought level (not chasing a top)     |
//| SELL: RSI must be above oversold level (not chasing a bottom)   |
//+------------------------------------------------------------------+
bool IsRSIOK(bool isBuy)
{
   if(!UseRSIFilter) return true;
   double rsi = GetRSIValue();
   if(isBuy  && rsi >= RSIOverbought) { Print("RSI too high for BUY: ", DoubleToString(rsi, 1)); return false; }
   if(!isBuy && rsi <= RSIOversold)   { Print("RSI too low for SELL: ", DoubleToString(rsi, 1)); return false; }
   return true;
}

//+------------------------------------------------------------------+
//| PULLBACK FILTER                                                  |
//| Entry must be within PullbackATRMultiplier * ATR of the 50 EMA. |
//| Prevents chasing entries far from structure.                    |
//+------------------------------------------------------------------+
bool IsPullbackValid(bool isBuy, double entry)
{
   if(!UsePullbackFilter) return true;
   double fast[1];
   if(CopyBuffer(FastEMAHandle, 0, 1, 1, fast) != 1) return true;
   double maxDist = PullbackATRMultiplier * GetATRPoints() * _Point;
   if(isBuy  && (entry - fast[0]) > maxDist) { Print("Price too far above EMA for BUY");  return false; }
   if(!isBuy && (fast[0] - entry) > maxDist) { Print("Price too far below EMA for SELL"); return false; }
   return true;
}

//+------------------------------------------------------------------+
//| ATR VOLATILITY GATE                                              |
//+------------------------------------------------------------------+
bool IsVolatilityOK()
{
   if(!UseATRFilter) return true;
   double atrPoints = GetATRPoints();
   if(atrPoints < ATRMinPoints) { Print("ATR too low: ",  atrPoints, " < ", ATRMinPoints); return false; }
   if(atrPoints > ATRMaxPoints) { Print("ATR too high: ", atrPoints, " > ", ATRMaxPoints); return false; }
   return true;
}

//+------------------------------------------------------------------+
//| DRAW SWING LINE                                                  |
//+------------------------------------------------------------------+
void DrawSwingLine(double price, bool isBuy, string source)
{
   if(!ShowSwingLines) return;
   SwingLineCount++;
   string name = "SwingLine_" + IntegerToString(SwingLineCount);
   if(SwingLineCount > 6)
      ObjectDelete(0, "SwingLine_" + IntegerToString(SwingLineCount - 6));
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? clrDodgerBlue : clrOrangeRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetString (0, name, OBJPROP_TOOLTIP,
                   (isBuy ? "SWING LOW: " : "SWING HIGH: ") +
                   DoubleToString(price, _Digits) + " [" + source + "]");
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| FIND NEAREST SWING HIGH/LOW                                      |
//|                                                                  |
//| Returns the most RECENT valid swing (not the absolute extreme).  |
//| Nearest swing gives a tighter, more logical SL placement and     |
//| keeps lot sizes and R:R realistic.                               |
//+------------------------------------------------------------------+
void FindNearestSwing(bool isBuy, double &swingPrice)
{
   swingPrice = 0;

   //--- PASS 1: H1 — major structure --------------------------------
   MqlRates h1[];
   ArraySetAsSeries(h1, true);
   int h1Need = SwingLookbackBars + SwingConfirmBars + 5;

   if(CopyRates(_Symbol, PERIOD_H1, 0, h1Need, h1) >= SwingLookbackBars)
   {
      if(isBuy)
      {
         for(int i = SwingConfirmBars; i < SwingLookbackBars - SwingConfirmBars; i++)
         {
            bool isSwingLow = true;
            for(int j = i - SwingConfirmBars; j <= i + SwingConfirmBars; j++)
            {
               if(j == i || j < 0) continue;
               if(h1[j].low <= h1[i].low) { isSwingLow = false; break; }
            }
            if(isSwingLow)
            {
               swingPrice = h1[i].low;
               DrawSwingLine(swingPrice, true, "H1");
               Print("Swing LOW  [H1 bar -", i, "]: ", DoubleToString(swingPrice, _Digits));
               return;
            }
         }
      }
      else
      {
         for(int i = SwingConfirmBars; i < SwingLookbackBars - SwingConfirmBars; i++)
         {
            bool isSwingHigh = true;
            for(int j = i - SwingConfirmBars; j <= i + SwingConfirmBars; j++)
            {
               if(j == i || j < 0) continue;
               if(h1[j].high >= h1[i].high) { isSwingHigh = false; break; }
            }
            if(isSwingHigh)
            {
               swingPrice = h1[i].high;
               DrawSwingLine(swingPrice, false, "H1");
               Print("Swing HIGH [H1 bar -", i, "]: ", DoubleToString(swingPrice, _Digits));
               return;
            }
         }
      }
   }

   //--- PASS 2: M15 fallback ----------------------------------------
   Print("Swing: H1 not found, trying M15 fallback");
   MqlRates m15[];
   ArraySetAsSeries(m15, true);
   int m15Lookback = 150;
   int m15Confirm  = 4;

   if(CopyRates(_Symbol, PERIOD_M15, 0, m15Lookback + m15Confirm + 5, m15) >= m15Lookback)
   {
      if(isBuy)
      {
         for(int i = m15Confirm; i < m15Lookback - m15Confirm; i++)
         {
            bool isSwingLow = true;
            for(int j = i - m15Confirm; j <= i + m15Confirm; j++)
            {
               if(j == i || j < 0) continue;
               if(m15[j].low <= m15[i].low) { isSwingLow = false; break; }
            }
            if(isSwingLow)
            {
               swingPrice = m15[i].low;
               DrawSwingLine(swingPrice, true, "M15");
               Print("Swing LOW  [M15 bar -", i, "]: ", DoubleToString(swingPrice, _Digits));
               return;
            }
         }
      }
      else
      {
         for(int i = m15Confirm; i < m15Lookback - m15Confirm; i++)
         {
            bool isSwingHigh = true;
            for(int j = i - m15Confirm; j <= i + m15Confirm; j++)
            {
               if(j == i || j < 0) continue;
               if(m15[j].high >= m15[i].high) { isSwingHigh = false; break; }
            }
            if(isSwingHigh)
            {
               swingPrice = m15[i].high;
               DrawSwingLine(swingPrice, false, "M15");
               Print("Swing HIGH [M15 bar -", i, "]: ", DoubleToString(swingPrice, _Digits));
               return;
            }
         }
      }
   }

   //--- PASS 3: ATR fallback ----------------------------------------
   Print("No swing found on H1 or M15 — will fall back to ATR");
   swingPrice = 0;
}

//+------------------------------------------------------------------+
//| CALCULATE STOP LOSS                                              |
//+------------------------------------------------------------------+
double CalculateStopLoss(bool isBuy, double entry)
{
   double swingPrice = 0;
   FindNearestSwing(isBuy, swingPrice);

   double buffer = SLBufferPips * 10 * _Point;

   if(swingPrice > 0)
   {
      double sl = isBuy ? swingPrice - buffer : swingPrice + buffer;
      if(isBuy  && sl >= entry) { Print("Swing SL above entry — using ATR fallback"); swingPrice = 0; }
      if(!isBuy && sl <= entry) { Print("Swing SL below entry — using ATR fallback"); swingPrice = 0; }
      if(swingPrice > 0)
      {
         if(MaxSLPips > 0)
         {
            double maxDist = MaxSLPips * 10 * _Point;
            double slDist  = MathAbs(entry - sl);
            if(slDist > maxDist)
            {
               Print("Swing SL capped: ", DoubleToString(slDist / _Point / 10, 0), " → ", MaxSLPips, " pips");
               sl = isBuy ? entry - maxDist : entry + maxDist;
            }
         }
         return sl;
      }
   }

   double atrValue   = GetATRPoints() * _Point;
   double fallbackSL = isBuy ? entry - atrValue * 1.5 : entry + atrValue * 1.5;
   if(MaxSLPips > 0)
   {
      double maxDist_ = MaxSLPips * 10 * _Point;
      double slDist_  = MathAbs(entry - fallbackSL);
      if(slDist_ > maxDist_)
      {
         Print("ATR SL capped: ", DoubleToString(slDist_ / _Point / 10, 0), " → ", MaxSLPips, " pips");
         fallbackSL = isBuy ? entry - maxDist_ : entry + maxDist_;
      }
   }
   Print("Swing not found — using ATR fallback");
   return fallbackSL;
}

//+------------------------------------------------------------------+
//| CALCULATE TAKE PROFIT                                            |
//+------------------------------------------------------------------+
double CalculateTakeProfit(bool isBuy, double entry, double sl)
{
   double risk = MathAbs(entry - sl);
   return isBuy ? entry + risk * RewardRiskRatio : entry - risk * RewardRiskRatio;
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE                                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(FixedLot > 0)
   {
      double lot = MathMax(minLot, MathMin(maxLot, FixedLot));
      return NormalizeDouble(MathFloor(lot / lotStep) * lotStep, 2);
   }

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;

   if(tickValue <= 0 || tickSize <= 0 || riskMoney <= 0) return minLot;

   double lossPerLot = (slPoints * _Point / tickSize) * tickValue;
   if(lossPerLot <= 0) return minLot;

   double volume = riskMoney / lossPerLot;
   volume = MathMax(minLot, MathMin(maxLot, volume));
   volume = MathFloor(volume / lotStep) * lotStep;
   volume = NormalizeDouble(volume, 2);

   if(volume < minLot)    volume = minLot;
   if(MaxLotSize > 0 && volume > MaxLotSize) volume = MaxLotSize;

   return volume;
}

//+------------------------------------------------------------------+
//| DAILY COUNTERS                                                   |
//+------------------------------------------------------------------+
void UpdateDailyCounters()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day != LastTradeDay)
   {
      TodayTradeCount   = 0;
      TodayLoss         = 0;
      consecutiveLosses = 0;
      LastTradeDay      = dt.day;
      Print("Daily counters reset");
   }
}

//+------------------------------------------------------------------+
//| DAILY LOSS LIMIT                                                 |
//+------------------------------------------------------------------+
bool IsDailyLossLimitHit()
{
   if(MaxDailyLossPercent <= 0) return false;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime todayStart = StructToTime(dt);

   if(HistorySelect(todayStart, TimeCurrent()))
   {
      TodayLoss = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal > 0 && HistoryDealGetString(deal, DEAL_SYMBOL) == _Symbol)
         {
            double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
            if(profit < 0) TodayLoss += MathAbs(profit);
         }
      }
   }
   return TodayLoss >= AccountInfoDouble(ACCOUNT_BALANCE) * MaxDailyLossPercent / 100;
}

//+------------------------------------------------------------------+
//| STOP DISTANCE CHECK                                              |
//+------------------------------------------------------------------+
bool IsStopDistanceOK(double slPoints)
{
   if(MinStopDistance <= 0) return true;
   return slPoints >= MinStopDistance;
}

//+------------------------------------------------------------------+
//| CAN TRADE                                                        |
//+------------------------------------------------------------------+
bool CanTrade()
{
   UpdateDailyCounters();
   if(IsDailyLossLimitHit())
   {
      Print("BLOCKED: Daily loss limit | TodayLoss=$", DoubleToString(TodayLoss, 2),
            " >= $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE) * MaxDailyLossPercent / 100, 2),
            " (", DoubleToString(MaxDailyLossPercent, 1), "% of balance)");
      return false;
   }
   if(TodayTradeCount >= MaxTradesPerDay)
   {
      Print("BLOCKED: Max trades/day reached | ", TodayTradeCount, "/", MaxTradesPerDay);
      return false;
   }
   if(consecutiveLosses >= MaxConsecutiveLosses)
   {
      Print("BLOCKED: Max consecutive losses reached | ", consecutiveLosses, "/", MaxConsecutiveLosses);
      return false;
   }
   if(!IsSpreadOK())                             return false;

   int openCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == 888777)
            openCount++;
      }
   }
   if(openCount >= MaxOpenPositions)
   {
      Print("BLOCKED: Max open positions | ", openCount, "/", MaxOpenPositions);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| PLACE TRADE                                                      |
//+------------------------------------------------------------------+
void PlaceTrade()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
   {
      Print("Failed to get tick");
      return;
   }

   // FORCE TRADES MODE
   if(ForceTrades)
   {
      static int forceCounter = 0;
      forceCounter++;
      bool isBuy = (forceCounter % 2 == 1);

      double entry    = isBuy ? tick.ask : tick.bid;
      double sl       = CalculateStopLoss(isBuy, entry);
      double tp       = CalculateTakeProfit(isBuy, entry, sl);
      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);

      double slPoints = MathAbs(entry - sl) / _Point;
      double volume   = CalculateLotSize(slPoints);
      if(volume <= 0) { Print("Invalid volume"); return; }

      int minStop = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      if(slPoints < minStop) { Print("Stop too close: ", slPoints, " < ", minStop); return; }

      bool result = isBuy ?
                   trade.Buy(volume, _Symbol, entry, sl, tp, "ATLAS Confluence Pro BUY") :
                   trade.Sell(volume, _Symbol, entry, sl, tp, "ATLAS Confluence Pro SELL");

      if(result)
      {
         TodayTradeCount++;
         Print("========================================");
         Print("FORCE TRADE: ", isBuy ? "BUY" : "SELL");
         Print("   Entry: ", DoubleToString(entry, _Digits));
         Print("   SL: ", DoubleToString(sl, _Digits), " (", DoubleToString(slPoints, 0), " pts)");
         Print("   TP: ", DoubleToString(tp, _Digits));
         Print("   Volume: ", DoubleToString(volume, 2));
         Print("========================================");
      }
      else
         Print("Trade failed: ", trade.ResultRetcodeDescription());
      return;
   }

   // NORMAL TRADING MODE
   if(RegimeBlocksEntry(ADXHandle)) { Print("Regime: ranging (ADX<", DoubleToString(RegimeMinADX,0), ") — skipping"); return; }  // [regime]
   int h1Trend = GetTrendDirection();
   int h4Trend = GetH4TrendDirection();
   int candle  = GetCandleDirection();

   if(h1Trend == 0)                                        { Print("H1: No clear trend"); return; }
   if(UseH4Filter && h4Trend != 0 && h4Trend != h1Trend)  { Print("H4 trend conflicts with H1 — skipping"); return; }

   bool isBuy  = (h1Trend == 1  && candle == 1);
   bool isSell = (h1Trend == -1 && candle == -1);
   if(!isBuy && !isSell)                                   { Print("Candle doesn't match trend — skipping"); return; }

   double entry = isBuy ? tick.ask : tick.bid;

   if(!IsVolatilityOK())          return;
   if(!IsRSIOK(isBuy))            return;
   if(!IsPullbackValid(isBuy, entry)) return;

   double sl = CalculateStopLoss(isBuy, entry);
   double tp = CalculateTakeProfit(isBuy, entry, sl);
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   double slPoints = MathAbs(entry - sl) / _Point;
   if(!IsStopDistanceOK(slPoints)) { Print("Stop too close: ", slPoints, " < ", MinStopDistance); return; }

   // Safety: warn if minimum lot would risk more than 5% of balance (account too small for this symbol)
   {
      double minLot_    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double tickVal_   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSz_    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double balance_   = AccountInfoDouble(ACCOUNT_BALANCE);
      if(tickVal_ > 0 && tickSz_ > 0 && balance_ > 0)
      {
         double lossPerLot_ = (slPoints * _Point / tickSz_) * tickVal_;
         double minLotLoss_ = minLot_ * lossPerLot_;
         if(minLotLoss_ > balance_ * 0.05)
            Print("WARNING: Min lot risks $", DoubleToString(minLotLoss_, 2),
                  " (", DoubleToString(minLotLoss_ / balance_ * 100.0, 1),
                  "% of balance).");
      }
   }

   double volume = CalculateLotSize(slPoints);
   if(volume <= 0) { Print("Invalid volume"); return; }

   bool result = isBuy ?
                trade.Buy(volume, _Symbol, entry, sl, tp, "ATLAS Confluence Pro BUY") :
                trade.Sell(volume, _Symbol, entry, sl, tp, "ATLAS Confluence Pro SELL");

   if(result)
   {
      TodayTradeCount++;
      LastTradeCloseOrOpenTime = TimeCurrent();
      Print("========================================");
      Print("TRADE: ", isBuy ? "BUY" : "SELL");
      Print("   Entry:  ", DoubleToString(entry, _Digits));
      Print("   SL:     ", DoubleToString(sl, _Digits), " (", DoubleToString(slPoints, 0), " pts)");
      Print("   TP:     ", DoubleToString(tp, _Digits));
      Print("   Volume: ", DoubleToString(volume, 2));
      Print("   H4:     ", (h4Trend == 1 ? "BULL" : (h4Trend == -1 ? "BEAR" : "FLAT")));
      Print("   RSI:    ", DoubleToString(GetRSIValue(), 1));
      Print("========================================");
   }
   else
      Print("Trade failed: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| DASHBOARD CONSTANTS                                              |
//+------------------------------------------------------------------+
#define DW     274

#define C_BG_DARK  ((color)C'12,14,22')
#define C_BG_HDR   ((color)C'18,28,58')
#define C_BG_ALT   ((color)C'17,20,32')
#define C_ACCENT   ((color)C'218,162,0')
#define C_SECTION  ((color)C'95,115,160')
#define C_LABEL    ((color)C'150,163,185')
#define C_TXT      ((color)C'225,230,242')
#define C_GREEN    ((color)C'45,198,72')
#define C_RED      ((color)C'238,62,62')
#define C_YELLOW   ((color)C'238,208,38')
#define C_DIVIDER  ((color)C'32,42,62')

//+------------------------------------------------------------------+
string TimeFrameStr()
{
   switch(Period())
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      default:         return EnumToString(Period());
   }
}

void DashRect(string n, int x, int y, int w, int h, color bg)
{
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN,      true);
      ObjectSetInteger(0, n, OBJPROP_BACK,        false);
      ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,     h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,   bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR,     bg);
}

void DashText(string n, int x, int y, string txt, color clr, int sz = 8, bool bold = false)
{
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, n, OBJPROP_BACK,       false);
   }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, n, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, n, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,  sz);
   ObjectSetString (0, n, OBJPROP_FONT,      bold ? "Arial Bold" : "Arial");
}

void DashRow(string key, int y, string lbl, string val, color valClr)
{
   DashText(DPFX+"L_"+key, PanelX+12,  y, lbl, C_LABEL, 8, false);
   DashText(DPFX+"V_"+key, PanelX+162, y, val, valClr,  8, true);
}

void DashSect(string key, int y, string title)
{
   DashText(DPFX+"H_"+key, PanelX+12, y, title, C_SECTION, 7, true);
}

void DashVisible(string n, bool visible)
{
   if(ObjectFind(0, n) >= 0)
      ObjectSetInteger(0, n, OBJPROP_TIMEFRAMES,
                       visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
}

void DashButton(string n, int x, int y, string txt)
{
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN,     false);
      ObjectSetInteger(0, n, OBJPROP_BACK,       false);
   }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, n, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, n, OBJPROP_COLOR,     C_TXT);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,  9);
   ObjectSetString (0, n, OBJPROP_FONT,      "Arial Bold");
}

//+------------------------------------------------------------------+
//| UPDATE DISPLAY                                                   |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double pnl     = equity - balance;
   int    h1Trend = GetTrendDirection();
   int    h4Trend = GetH4TrendDirection();
   int    candle  = GetCandleDirection();
   double rsi     = GetRSIValue();
   double atr     = GetATRPoints();
   double spread  = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                     SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;

   int openPos = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk > 0 && PositionSelectByTicket(tk))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == 888777)
            openPos++;
   }

   string h4Str  = (h4Trend ==  1 ? "▲ BULLISH" : (h4Trend == -1 ? "▼ BEARISH" : "─ FLAT"));
   string h1Str  = (h1Trend ==  1 ? "▲ BULLISH" : (h1Trend == -1 ? "▼ BEARISH" : "─ FLAT"));
   string cdlStr = (candle  ==  1 ? "▲ BULLISH" : (candle  == -1 ? "▼ BEARISH" : "○  DOJI"));
   color  h4Col  = (h4Trend ==  1 ? C_GREEN : (h4Trend == -1 ? C_RED : C_LABEL));
   color  h1Col  = (h1Trend ==  1 ? C_GREEN : (h1Trend == -1 ? C_RED : C_LABEL));
   color  cdlCol = (candle  ==  1 ? C_GREEN : (candle  == -1 ? C_RED : C_LABEL));
   color  pnlCol = (pnl > 0 ? C_GREEN : (pnl < 0 ? C_RED : C_TXT));
   color  rsiCol = (rsi >= 70 ? C_RED : (rsi <= 30 ? C_GREEN : C_TXT));
   color  lssCol = (consecutiveLosses >= (int)(MaxConsecutiveLosses * 0.7) ? C_RED :
                   (consecutiveLosses >= (int)(MaxConsecutiveLosses * 0.4) ? C_YELLOW : C_TXT));

   bool   exp    = !PanelCollapsed;
   int    fullH  = 406;
   int    hdrH   = 55;
   int    panelH = exp ? fullH : hdrH;

   // ── Backgrounds ───────────────────────────────────────
   DashRect(DPFX+"FR",    PanelX-1, PanelY-1, DW+2, panelH+2, C_ACCENT);
   DashRect(DPFX+"MAIN",  PanelX,   PanelY,   DW,   panelH,   C_BG_DARK);
   DashRect(DPFX+"HDR",   PanelX,   PanelY,   DW,   52,       C_BG_HDR);
   DashRect(DPFX+"GLINE", PanelX,   PanelY+52,DW,   3,        C_ACCENT);
   DashRect(DPFX+"S_ACC", PanelX,   PanelY+55,DW,   74,       C_BG_DARK);
   DashRect(DPFX+"S_MKT", PanelX,   PanelY+132,DW,  118,      C_BG_ALT);
   DashRect(DPFX+"S_TRD", PanelX,   PanelY+253,DW,  76,       C_BG_DARK);
   DashRect(DPFX+"S_RSK", PanelX,   PanelY+332,DW,  74,       C_BG_ALT);

   // ── Header (always visible) ───────────────────────────
   DashText(DPFX+"TITLE", PanelX+12, PanelY+9,
            "ATLAS Confluence Pro V1.0", C_ACCENT, 10, true);
   DashText(DPFX+"SUB",   PanelX+12, PanelY+31,
            "Stephen REEN     " + _Symbol + "," + TimeFrameStr(),
            C_LABEL, 8, false);
   DashButton(DPFX+"BTN", PanelX+DW-28, PanelY+12,
              exp ? "[ - ]" : "[ + ]");

   // ── Account ───────────────────────────────────────────
   DashSect("ACC", PanelY+60, "ACCOUNT");
   DashRow("BAL", PanelY+75,  "Balance",
           "$" + DoubleToString(balance, 2), C_TXT);
   DashRow("EQU", PanelY+93,  "Equity",
           "$" + DoubleToString(equity, 2),  C_TXT);
   DashRow("PNL", PanelY+111, "Open P&L",
           (pnl >= 0 ? "+" : "-") + "$" + DoubleToString(MathAbs(pnl), 2), pnlCol);

   // ── Market Analysis ───────────────────────────────────
   DashSect("MKT", PanelY+137, "MARKET ANALYSIS");
   DashRow("H4T", PanelY+152, "H4 Trend",  h4Str, h4Col);
   DashRow("H1T", PanelY+170, "H1 Trend",  h1Str, h1Col);
   DashRow("CDL", PanelY+188, "M1 Candle", cdlStr, cdlCol);
   DashRow("RSI", PanelY+206, "RSI (H1)",
           DoubleToString(rsi, 1), rsiCol);
   DashRow("ATR", PanelY+224, "ATR",
           DoubleToString(atr, 0) + " pts", C_TXT);
   DashRow("SPR", PanelY+242, "Spread",
           DoubleToString(spread, 0) + " pts", C_TXT);

   // ── Trade Status ──────────────────────────────────────
   DashSect("TRD", PanelY+258, "TRADE STATUS");
   DashRow("OPN", PanelY+273, "Open Pos",
           IntegerToString(openPos) + " / " + IntegerToString(MaxOpenPositions),
           openPos > 0 ? C_YELLOW : C_TXT);
   DashRow("TOD", PanelY+291, "Today",
           IntegerToString(TodayTradeCount) + " / " + IntegerToString(MaxTradesPerDay), C_TXT);
   DashRow("CSL", PanelY+309, "Loss Streak",
           IntegerToString(consecutiveLosses) + " / " + IntegerToString(MaxConsecutiveLosses),
           lssCol);

   // ── Risk Parameters ───────────────────────────────────
   DashSect("RSK", PanelY+337, "RISK PARAMETERS");
   DashRow("LOT", PanelY+352, "Max Lot",
           DoubleToString(MaxLotSize, 2), C_TXT);
   DashRow("RRR", PanelY+370, "R:R Ratio",
           "1 : " + DoubleToString(RewardRiskRatio, 1), C_TXT);
   DashRow("MSL", PanelY+388, "Max SL",
           IntegerToString(MaxSLPips) + " pips", C_TXT);

   // ── Show / hide sections ──────────────────────────────
   string sections[] = {
      "S_ACC","S_MKT","S_TRD","S_RSK",
      "H_ACC","H_MKT","H_TRD","H_RSK",
      "L_BAL","V_BAL","L_EQU","V_EQU","L_PNL","V_PNL",
      "L_H4T","V_H4T","L_H1T","V_H1T","L_CDL","V_CDL",
      "L_RSI","V_RSI","L_ATR","V_ATR","L_SPR","V_SPR",
      "L_OPN","V_OPN","L_TOD","V_TOD","L_CSL","V_CSL",
      "L_LOT","V_LOT","L_RRR","V_RRR","L_MSL","V_MSL"
   };
   for(int i = 0; i < ArraySize(sections); i++)
      DashVisible(DPFX+sections[i], exp);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTION — tracks consecutive losses                    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != CONF_MAGIC) return;
   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   string dealSym    = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   double dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);

   // [multi-symbol] Route the close to the chart symbol or the matching extra slot.
   int xidx = (dealSym == _Symbol) ? -1 : FindConfSymIndex(dealSym);
   if(dealSym != _Symbol && xidx < 0) return;  // not a symbol this EA manages

   if(xidx < 0)   // chart symbol — unchanged behavior
   {
      if(dealProfit < 0) consecutiveLosses++; else consecutiveLosses = 0;
      Print("Trade closed | Profit: ", DoubleToString(dealProfit, 2),
            " | Consecutive losses: ", consecutiveLosses);
      LastTradeCloseOrOpenTime = TimeCurrent();
   }
   else           // extra symbol
   {
      if(dealProfit < 0) extraSym[xidx].consecutiveLosses++; else extraSym[xidx].consecutiveLosses = 0;
      extraSym[xidx].lastTradeCloseOrOpenTime = TimeCurrent();
      if(ExtraDebugLog)
         Print("[", dealSym, "] EXTRA closed | Profit: ", DoubleToString(dealProfit, 2),
               " | Consecutive losses: ", extraSym[xidx].consecutiveLosses);
   }

   // Batch reset: when all positions for THIS symbol close, restart its cycle
   int remaining = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk > 0 && PositionSelectByTicket(tk))
         if(PositionGetString(POSITION_SYMBOL) == dealSym &&
            PositionGetInteger(POSITION_MAGIC) == CONF_MAGIC)
            remaining++;
   }
   if(remaining == 0)
   {
      if(xidx < 0) TodayTradeCount = 0;
      else         extraSym[xidx].todayTradeCount = 0;
      Print(dealSym, ": all positions closed — batch reset 0/", MaxOpenPositions);
   }

   // Clean up the partial-close marker for this ticket so GlobalVariables don't accumulate forever
   string pcKey = "CONF_PC_" + IntegerToString((long)trans.position);
   if(GlobalVariableCheck(pcKey)) GlobalVariableDel(pcKey);
}

//+------------------------------------------------------------------+
//| CHART EVENTS — toggle collapse + drag                           |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
   // ── Toggle collapse ──────────────────────────────────
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == DPFX+"BTN")
   {
      PanelCollapsed = !PanelCollapsed;
      UpdateDisplay();
      return;
   }

   // ── Drag (mouse move) ────────────────────────────────
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int  mx   = (int)lparam;
      int  my   = (int)dparam;
      bool lBtn = ((int)StringToInteger(sparam) & 1) != 0;

      if(lBtn)
      {
         if(!PanelDragging)
         {
            if(mx >= PanelX && mx <= PanelX + DW &&
               my >= PanelY && my <= PanelY + 55)
            {
               PanelDragging = true;
               DragOffsetX   = mx - PanelX;
               DragOffsetY   = my - PanelY;
            }
         }
         if(PanelDragging)
         {
            PanelX = mx - DragOffsetX;
            PanelY = my - DragOffsetY;
            PanelX = MathMax(0, PanelX);
            PanelY = MathMax(0, PanelY);
            UpdateDisplay();
         }
      }
      else
      {
         PanelDragging = false;
      }
   }
}

//+==================================================================+
//| [MULTI-SYMBOL] EXTRA-SYMBOL ENGINE                              |
//| Additive parallel engine: trades extra symbols from one chart   |
//| attachment alongside the chart symbol. The chart-symbol path is  |
//| left untouched; extras run the same confluence logic against     |
//| per-symbol indicator handles and never draw on the chart.        |
//+==================================================================+

// Per-symbol pip factor (Confluence's chart path hardcodes /10 for 5/3-digit FX)
double PipFactorFor(string sym)
{
   int d = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(d == 5 || d == 3) return 10.0;
   if(d == 2)           return 100.0;
   return 1.0;
}

// Account-wide daily loss cap: sums realized losses across ALL symbols this EA's
// magic number closed today. Fixes the multiplicative-risk bug where N symbols
// could each lose up to MaxDailyLossPercent of the whole account independently.
bool IsAccountDailyLossLimitHit()
{
   if(MaxDailyLossPercent <= 0) return false;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime todayStart = StructToTime(dt);
   double lossAcct = 0;
   if(HistorySelect(todayStart, TimeCurrent()))
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         if(HistoryDealGetInteger(deal, DEAL_MAGIC) != CONF_MAGIC) continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
         if(profit < 0) lossAcct += MathAbs(profit);
      }
   return lossAcct >= AccountInfoDouble(ACCOUNT_BALANCE) * MaxDailyLossPercent / 100.0;
}

int FindConfSymIndex(string sym)
{
   for(int i = 0; i < extraSymbolCount; i++) if(extraSym[i].name == sym) return i;
   return -1;
}

// Generic EMA trend (fast vs slow). Works for H1 or H4 via the handle pair.
int GetEMATrend(int fastH, int slowH)
{
   double fast[1], slow[1];
   if(CopyBuffer(fastH, 0, 1, 1, fast) != 1) return 0;
   if(CopyBuffer(slowH, 0, 1, 1, slow) != 1) return 0;
   if(fast[0] > slow[0]) return 1;
   if(fast[0] < slow[0]) return -1;
   return 0;
}

int GetCandleDirFor(string sym)
{
   MqlRates rates[2];
   if(CopyRates(sym, PERIOD_M1, 0, 2, rates) != 2) return 0;
   if(rates[0].close > rates[0].open) return 1;
   if(rates[0].close < rates[0].open) return -1;
   return 0;
}

double GetATRPointsFor(int atrH, double pt)
{
   double atr[1];
   if(atrH != INVALID_HANDLE && CopyBuffer(atrH, 0, 1, 1, atr) == 1) return atr[0] / pt;
   return 20;
}

double GetRSIFor(int rsiH)
{
   double rsi[1];
   if(rsiH != INVALID_HANDLE && CopyBuffer(rsiH, 0, 1, 1, rsi) == 1) return rsi[0];
   return 50;
}

// Nearest-swing SL anchor for an extra symbol (mirrors FindNearestSwing, no drawing).
void FindNearestSwingFor(string sym, bool isBuy, double &swingPrice)
{
   swingPrice = 0;
   MqlRates h1[]; ArraySetAsSeries(h1, true);
   int h1Need = SwingLookbackBars + SwingConfirmBars + 5;
   if(CopyRates(sym, PERIOD_H1, 0, h1Need, h1) >= SwingLookbackBars)
   {
      for(int i = SwingConfirmBars; i < SwingLookbackBars - SwingConfirmBars; i++)
      {
         bool ok = true;
         for(int j = i - SwingConfirmBars; j <= i + SwingConfirmBars; j++)
         {
            if(j == i || j < 0) continue;
            if(isBuy) { if(h1[j].low  <= h1[i].low)  { ok = false; break; } }
            else      { if(h1[j].high >= h1[i].high) { ok = false; break; } }
         }
         if(ok) { swingPrice = isBuy ? h1[i].low : h1[i].high; return; }
      }
   }
   MqlRates m15[]; ArraySetAsSeries(m15, true);
   int m15Lookback = 150, m15Confirm = 4;
   if(CopyRates(sym, PERIOD_M15, 0, m15Lookback + m15Confirm + 5, m15) >= m15Lookback)
   {
      for(int i = m15Confirm; i < m15Lookback - m15Confirm; i++)
      {
         bool ok = true;
         for(int j = i - m15Confirm; j <= i + m15Confirm; j++)
         {
            if(j == i || j < 0) continue;
            if(isBuy) { if(m15[j].low  <= m15[i].low)  { ok = false; break; } }
            else      { if(m15[j].high >= m15[i].high) { ok = false; break; } }
         }
         if(ok) { swingPrice = isBuy ? m15[i].low : m15[i].high; return; }
      }
   }
   swingPrice = 0;
}

double CalculateStopLossExtra(string sym, ConfSymState &st, bool isBuy, double entry)
{
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   double swingPrice = 0;
   FindNearestSwingFor(sym, isBuy, swingPrice);
   double buffer = SLBufferPips * st.pipFactor * pt;
   if(swingPrice > 0)
   {
      double sl = isBuy ? swingPrice - buffer : swingPrice + buffer;
      if(isBuy  && sl >= entry) swingPrice = 0;
      if(!isBuy && sl <= entry) swingPrice = 0;
      if(swingPrice > 0)
      {
         if(MaxSLPips > 0)
         {
            double maxDist = MaxSLPips * st.pipFactor * pt;
            if(MathAbs(entry - sl) > maxDist) sl = isBuy ? entry - maxDist : entry + maxDist;
         }
         return sl;
      }
   }
   double atrValue   = GetATRPointsFor(st.atrHandle, pt) * pt;
   double fallbackSL = isBuy ? entry - atrValue * 1.5 : entry + atrValue * 1.5;
   if(MaxSLPips > 0)
   {
      double maxDist_ = MaxSLPips * st.pipFactor * pt;
      if(MathAbs(entry - fallbackSL) > maxDist_) fallbackSL = isBuy ? entry - maxDist_ : entry + maxDist_;
   }
   return fallbackSL;
}

double CalculateLotSizeExtra(double slPoints, string sym, double riskPct)
{
   double minLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double pt      = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(FixedLot > 0)
   {
      double lot = MathMax(minLot, MathMin(maxLot, FixedLot));
      return NormalizeDouble(MathFloor(lot / lotStep) * lotStep, 2);
   }
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * riskPct / 100.0;
   if(tickValue <= 0 || tickSize <= 0 || riskMoney <= 0) return minLot;
   double lossPerLot = (slPoints * pt / tickSize) * tickValue;
   if(lossPerLot <= 0) return minLot;
   double volume = riskMoney / lossPerLot;
   volume = MathMax(minLot, MathMin(maxLot, volume));
   volume = MathFloor(volume / lotStep) * lotStep;
   volume = NormalizeDouble(volume, 2);
   if(volume < minLot) volume = minLot;
   if(MaxLotSize > 0 && volume > MaxLotSize) volume = MaxLotSize;
   return volume;
}

// Full entry evaluation + order for an extra symbol (mirrors PlaceTrade's normal
// mode). Fresh local CTrade per call; no ForceTrades, no chart drawing.
void PlaceTradeExtra(string sym, ConfSymState &st)
{
   MqlTick tick;
   if(!SymbolInfoTick(sym, tick)) return;
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   int    dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   if(RegimeBlocksEntry(st.adxHandle)) return;  // [regime] skip ranging/chop markets
   int h1Trend = GetEMATrend(st.fastEMAHandle, st.slowEMAHandle);
   int h4Trend = GetEMATrend(st.h4FastEMAHandle, st.h4SlowEMAHandle);
   int candle  = GetCandleDirFor(sym);
   if(h1Trend == 0) return;
   if(UseH4Filter && h4Trend != 0 && h4Trend != h1Trend) return;

   bool isBuy  = (h1Trend == 1  && candle == 1);
   bool isSell = (h1Trend == -1 && candle == -1);
   if(!isBuy && !isSell) return;

   double entry = isBuy ? tick.ask : tick.bid;

   // ATR volatility gate
   if(UseATRFilter)
   { double a = GetATRPointsFor(st.atrHandle, pt); if(a < ATRMinPoints || a > ATRMaxPoints) return; }
   // RSI gate
   if(UseRSIFilter)
   { double rsi = GetRSIFor(st.rsiHandle);
     if(isBuy  && rsi >= RSIOverbought) return;
     if(!isBuy && rsi <= RSIOversold)   return; }
   // Pullback gate (price near 50 EMA)
   if(UsePullbackFilter)
   { double fast[1];
     if(CopyBuffer(st.fastEMAHandle, 0, 1, 1, fast) == 1)
     { double maxDist = PullbackATRMultiplier * GetATRPointsFor(st.atrHandle, pt) * pt;
       if(isBuy  && (entry - fast[0]) > maxDist) return;
       if(!isBuy && (fast[0] - entry) > maxDist) return; } }

   double sl = CalculateStopLossExtra(sym, st, isBuy, entry);
   double tp = CalculateTakeProfit(isBuy, entry, sl);
   sl = NormalizeDouble(sl, dg);
   tp = NormalizeDouble(tp, dg);

   double slPoints = MathAbs(entry - sl) / pt;
   if(MinStopDistance > 0 && slPoints < MinStopDistance) return;
   int minStop = (int)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   if(slPoints < minStop) return;

   double riskPct = (ExtraRiskPercent > 0) ? ExtraRiskPercent : RiskPercent;
   double volume  = CalculateLotSizeExtra(slPoints, sym, riskPct);
   if(volume <= 0) return;

   CTrade xtrade;
   xtrade.SetExpertMagicNumber(CONF_MAGIC);
   xtrade.SetDeviationInPoints(30);
   xtrade.SetTypeFillingBySymbol(sym);
   bool result = isBuy ?
                xtrade.Buy(volume, sym, entry, sl, tp, "ATLAS Confluence Pro BUY (" + sym + ")") :
                xtrade.Sell(volume, sym, entry, sl, tp, "ATLAS Confluence Pro SELL (" + sym + ")");
   if(result)
   {
      st.todayTradeCount++;
      st.lastTradeCloseOrOpenTime = TimeCurrent();
      Print("EXTRA TRADE ", sym, ": ", isBuy ? "BUY" : "SELL",
            " | Entry ", DoubleToString(entry, dg), " SL ", DoubleToString(sl, dg),
            " TP ", DoubleToString(tp, dg), " Vol ", DoubleToString(volume, 2));
   }
   else if(ExtraDebugLog)
      Print("[", sym, "] EXTRA trade failed: ", xtrade.ResultRetcodeDescription());
}

// Build extraSym[] from the CSV. Skips blanks, the chart symbol, and duplicates.
void ParseExtraSymbolList()
{
   extraSymbolCount = 0;
   if(!ExtraSymbolsEnabled) return;
   string raw = ExtraTradeSymbols;
   StringTrimLeft(raw); StringTrimRight(raw);
   if(StringLen(raw) == 0) return;
   string parts[];
   int n = StringSplit(raw, ',', parts);
   if(n <= 0) return;
   ArrayResize(extraSym, n);
   for(int i = 0; i < n; i++)
   {
      string s = parts[i];
      StringTrimLeft(s); StringTrimRight(s);
      if(StringLen(s) == 0) continue;
      if(s == _Symbol) continue;
      if(FindConfSymIndex(s) >= 0) continue;
      if(!SymbolSelect(s, true)) { Print("[", s, "] EXTRA: SymbolSelect failed — skipped"); continue; }
      int idx = extraSymbolCount;
      ConfSymState st;
      st.name             = s;
      st.atrHandle        = iATR(s, PERIOD_M15, 14);
      st.fastEMAHandle    = iMA(s, PERIOD_H1, 50,  0, MODE_EMA, PRICE_CLOSE);
      st.slowEMAHandle    = iMA(s, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
      st.h4FastEMAHandle  = iMA(s, PERIOD_H4, 50,  0, MODE_EMA, PRICE_CLOSE);
      st.h4SlowEMAHandle  = iMA(s, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
      st.rsiHandle        = iRSI(s, PERIOD_H1, RSIPeriod, PRICE_CLOSE);
      st.adxHandle        = iADX(s, RegimeTF, RegimeADXPeriod);  // [regime]
      st.isActive = (st.atrHandle != INVALID_HANDLE && st.fastEMAHandle != INVALID_HANDLE &&
                     st.slowEMAHandle != INVALID_HANDLE && st.h4FastEMAHandle != INVALID_HANDLE &&
                     st.h4SlowEMAHandle != INVALID_HANDLE && st.rsiHandle != INVALID_HANDLE);
      if(!st.isActive) Print("[", s, "] EXTRA: indicator handle failed — symbol skipped");
      st.pipFactor = PipFactorFor(s);
      st.lastBarTime = 0; st.lastTradeCloseOrOpenTime = 0;
      st.todayTradeCount = 0; st.lastTradeDay = 0; st.consecutiveLosses = 0;
      extraSym[idx] = st;
      extraSymbolCount++;
   }
   Print("EXTRA ENGINE: ", extraSymbolCount, " symbol(s) active out of ", n, " requested");
}

// Per-symbol tick driver — mirrors OnTick's chart-symbol gating, per symbol.
// Account-wide loss cap is checked once in OnTick before this runs.
void ProcessExtraSymbol(int idx)
{
   if(idx < 0 || idx >= extraSymbolCount) return;
   if(!extraSym[idx].isActive) return;
   string sym = extraSym[idx].name;

   MqlDateTime dnow; TimeToStruct(TimeCurrent(), dnow);
   if(dnow.day != extraSym[idx].lastTradeDay)
   { extraSym[idx].todayTradeCount = 0; extraSym[idx].consecutiveLosses = 0; extraSym[idx].lastTradeDay = dnow.day; }

   int symCap = (ExtraMaxTradesPerDay > 0) ? ExtraMaxTradesPerDay : MaxTradesPerDay;
   if(extraSym[idx].todayTradeCount >= symCap) return;
   if(extraSym[idx].consecutiveLosses >= MaxConsecutiveLosses) return;

   // Per-symbol spread gate
   if(MaxSpreadPoints > 0)
   { double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
     if((SymbolInfoDouble(sym, SYMBOL_ASK) - SymbolInfoDouble(sym, SYMBOL_BID)) / pt > MaxSpreadPoints) return; }

   // Per-symbol open-position cap
   int openCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   { ulong tk = PositionGetTicket(i);
     if(tk > 0 && PositionSelectByTicket(tk))
       if(PositionGetString(POSITION_SYMBOL) == sym && PositionGetInteger(POSITION_MAGIC) == CONF_MAGIC) openCount++; }
   if(openCount >= MaxOpenPositions) return;

   if(!IsTradingTime()) return;
   if(PostTradeCooldownMin > 0 && extraSym[idx].lastTradeCloseOrOpenTime > 0 &&
      TimeCurrent() - extraSym[idx].lastTradeCloseOrOpenTime < (datetime)(PostTradeCooldownMin * 60)) return;

   datetime barTime[1];
   if(CopyTime(sym, PERIOD_M1, 0, 1, barTime) != 1) return;
   if(barTime[0] != extraSym[idx].lastBarTime)
   {
      extraSym[idx].lastBarTime = barTime[0];
      PlaceTradeExtra(sym, extraSym[idx]);
   }
}

//+------------------------------------------------------------------+
//| MAIN TICK                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   ChartSetString(ChartID(), CHART_COMMENT, "ATLAS Confluence Pro V1.0 by Stephen REEN");
   UpdateDisplay();

   CheckFridayClose();
   ApplyBreakeven();
   ApplyTrailingStop();
   ApplyPartialClose();

   // [multi-symbol] Account-wide daily loss cap shared by chart symbol + all extras.
   bool accountDailyLossHit = IsAccountDailyLossLimitHit();
   // Drive the extra-symbol engine BEFORE the chart-symbol early returns below, so
   // extras still trade when the chart symbol's own gates bail out this tick.
   if(ExtraSymbolsEnabled && extraSymbolCount > 0 && !accountDailyLossHit)
      for(int i = 0; i < extraSymbolCount; i++) ProcessExtraSymbol(i);

   if(ForceTrades)
   {
      static datetime lastForce = 0;
      if(TimeCurrent() - lastForce > 60)
      {
         lastForce = TimeCurrent();
         Print("FORCE MODE: Placing test trade");
         PlaceTrade();
      }
      return;
   }

   if(accountDailyLossHit) return;
   if(!CanTrade())      return;
   if(!IsTradingTime()) return;
   if(PostTradeCooldownMin > 0 && LastTradeCloseOrOpenTime > 0 &&
      TimeCurrent() - LastTradeCloseOrOpenTime < (datetime)(PostTradeCooldownMin * 60)) return;

   datetime barTime[1];
   if(CopyTime(_Symbol, PERIOD_M1, 0, 1, barTime) != 1) return;

   if(barTime[0] != LastBarTime)
   {
      LastBarTime = barTime[0];
      PlaceTrade();
   }
}
