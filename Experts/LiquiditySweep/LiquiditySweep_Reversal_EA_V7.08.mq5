//+------------------------------------------------------------------+
//|                                LiquiditySweep_Reversal_EA.mq5    |
//|                     HIGH FREQUENCY - 15-30 trades/day           |
//|                     Version 7.8                                 |
//+------------------------------------------------------------------+
#property copyright "Liquidity Sweep EA"
#property version   "7.80"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_TREND_FILTER
{
   FILTER_NONE = 0,
   SMA_20 = 20,
   SMA_50 = 50,
   SMA_200 = 200
};

enum ENUM_AGGRESSIVE_LEVEL
{
   AGGRESSIVE_OFF = 0,
   AGGRESSIVE_MEDIUM = 1,
   AGGRESSIVE_HIGH = 2,
   AGGRESSIVE_ULTRA = 3
};

enum ENUM_POSITION_DIRECTION
{
   DIR_NONE = 0,
   DIR_LONG = 1,
   DIR_SHORT = 2
};

enum ENUM_BOS_MODE
{
   BOS_NORMAL  = 0,   // Swing point + close beyond required
   BOS_RELAXED = 1,   // Swing point only (no close required)
   BOS_BYPASS  = 2    // No confirmation — immediate entry after sweep
};

//+------------------------------------------------------------------+
//| Input parameters – HIGH FREQUENCY OPTIMIZED                      |
//+------------------------------------------------------------------+
input group "=== Multi-Symbol Scanner ==="
input string   InpSymbolList     = "EURUSD,GBPUSD,USDJPY,AUDUSD,NZDUSD,USDCAD,USDCHF";
input string   InpAdditionalSymbols = "EURJPY,GBPJPY,AUDJPY,CADJPY";
input bool     InpIncludeGold    = true;
input bool     InpIncludeIndices = false;

input group "=== Timeframe Settings ==="
input ENUM_TIMEFRAMES InpSweepTF = PERIOD_M5;
input ENUM_TIMEFRAMES InpConfTF  = PERIOD_M1;
input bool     InpUseM1Sweep     = false;

input group "=== Liquidity Pool Settings ==="
input int      InpLookbackN      = 30;
input double   InpDeltaPips      = 2.0;
input double   InpSweepMinPips   = 3.0;
input double   InpSweepATRRatio  = 0.15;  // sweep must also clear this fraction of current ATR — filters weak sweeps during volatile/news conditions without tightening calm-market entries

input group "=== Entry & Risk Settings ==="
input double   InpRiskPercent    = 0.3;
input double   InpFixedLotSize   = 0.0;  // 0 = auto-calculate from risk%; otherwise use this fixed lot size
input double   InpSlBufferPips   = 2.0;
input double   InpMaxSlippage    = 5;
input bool     InpUseFVG         = false;
input bool     InpDirectBOSEntry = true;
input double   InpTP_R           = 1.5;
input double   InpMinRR          = 1.2;
input double   InpPartialTP_R    = 1.0;
input double   InpMaxSlPips      = 15.0;  // Hard SL cap in pips (0 = no cap)

input group "=== Trade Management ==="
input int      InpMaxDailyTrades  = 0;  // 0 = unlimited (trade continuously until market/session close)
input int      InpMaxTradesPerSymbol = 0;  // per-symbol daily cap (0 = auto from global/symbols)
input double   InpMaxDailyNetR    = 8.0;  // informational target only — no longer pauses trading
input double   InpMaxDailyLossR   = -3.0;  // safety stop — trading pauses for the day if hit
input int      InpMaxOpenPositions = 12;
input int      InpMaxCorrelatedPositions = 10;
input bool     InpUseCorrelationFilter = false;
input int      InpCancelAfterSec  = 45;
input bool     InpUseTrailingStop = true;
input double   InpTrailingStart   = 1.0;  // delay trailing until past the partial-TP point so winners aren't clipped early
input double   InpTrailingStep    = 0.5;  // wider trail buffer (was 0.2) so normal pullbacks don't stop runners out
input bool     InpUseBreakEven    = true;
input double   InpBreakEvenR      = 0.5;

input group "=== Advanced Features ==="
input ENUM_AGGRESSIVE_LEVEL InpAggressiveMode = AGGRESSIVE_ULTRA;
input bool     InpAllowReEntry    = true;
input int      InpMaxEntriesPerSweep = 3;
input ENUM_TREND_FILTER InpTrendFilter = FILTER_NONE;
input double   InpMinATR          = 1.0;
input double   InpMaxSpreadMultiplier = 2.0;

input group "=== ULTRA MODE OPTIONS ==="
input ENUM_BOS_MODE InpBOSMode   = BOS_BYPASS;

input group "=== Performance Tracking ==="
input bool     InpAutoDisablePoorSymbols = true;
input double   InpMinWinRate       = 35.0;
input int      InpMinTradesForDecision = 50;

input group "=== Session Filter (Multi-Session, GMT) ==="
input bool     InpUseSessionFilter   = true;   // master switch — false = trade 24h
input bool     InpSessionAsianOn     = true;   // Sydney/Tokyo
input int      InpAsianStartHour     = 23;
input int      InpAsianStartMin      = 0;
input int      InpAsianEndHour       = 8;
input int      InpAsianEndMin        = 0;
input bool     InpSessionLondonOn    = true;
input int      InpLondonStartHour    = 7;
input int      InpLondonStartMin     = 0;
input int      InpLondonEndHour      = 16;
input int      InpLondonEndMin       = 0;
input bool     InpSessionNewYorkOn   = true;
input int      InpNewYorkStartHour   = 12;
input int      InpNewYorkStartMin    = 0;
input int      InpNewYorkEndHour     = 21;
input int      InpNewYorkEndMin      = 0;

input group "=== Spread Limits (pips) ==="
input double   InpSpreadLimitEURUSD = 1.5;
input double   InpSpreadLimitGBPUSD = 2.0;
input double   InpSpreadLimitUSDJPY = 1.5;
input double   InpSpreadLimitXAUUSD = 3.5;
input double   InpSpreadLimitDefault = 2.0;

input group "=== Dashboard Settings ==="
input bool     InpShowDashboard    = true;
input int      InpDashboardCorner  = 0;  // 0=top-left  1=top-right  2=bottom-right  3=bottom-left
input int      InpDashboardXOffset = 10;
input int      InpDashboardYOffset = 10;

input group "=== Expert Settings ==="
input ulong    InpMagicNumber      = 20250609;
input string   InpComment          = "LSweep_HF";
input bool     InpDebugMode        = true;

//+------------------------------------------------------------------+
//| Structures                                                       |
//+------------------------------------------------------------------+
struct SymbolPerformance
{
   string   name;
   int      totalTrades;
   int      winningTrades;
   double   totalR;
   double   winRate;
   double   avgRR;
   bool     isDisabled;
   double   avgSpread;
   int      spreadSamples;
};

struct SymbolData
{
   string          name;
   double          pipSize;
   double          minLot;
   double          maxLot;
   double          lotStep;
   double          spreadLimit;
   double          currentSpread;
   double          avgSpread;
   double          atr;
   double          trend;
   bool            isActive;
   bool            hasSetup;
   ENUM_POSITION_DIRECTION setupDirection;
   ENUM_POSITION_DIRECTION positionDirection;
   bool            setupValid;
   datetime        sweepBarTime;
   datetime        signalTime;
   string          currentSweepId;
   double          sweepExtreme;
   double          lpLevel;
   double          entryPrice;
   double          stopLoss;
   double          takeProfit;
   double          partialTP;
   double          totalLot;
   double          riskAmount;
   ulong           positionTicket;
   ulong           positionTicket2;
   ulong           dealTicket;
   datetime        lastTradeTime;
   int             tradesToday;
   double          dailyR;
   int             entriesThisSweep;
   datetime        lastSweepTime;
   datetime        lastBOSTime;
   int             atrHandle;
   bool            partialClosed;
   bool            breakEvenActivated;
   double          riskAmount2;      // risk stored for positionTicket2
   SymbolPerformance perf;
};

struct TradeStats
{
   int      tradesToday;
   double   avgTradesPerDay;
   double   avgTradesPerSymbol;
   int      dailyHistory[30];
   datetime lastUpdate;
};

struct FilterStats
{
   int lpPass;      int lpFail;
   int sweepPass;   int sweepFail;
   int trendPass;   int trendFail;
   int bosPass;     int bosFail;
   int correlPass;  int correlFail;
   int riskPass;    int riskFail;
   int orderPass;   int orderFail;
};

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CTrade         Trade;
MqlTick        currentTick;
SymbolData     symbols[];
string         symbolList[];
datetime       lastBarTime[];
datetime       todayStart = 0;
double         globalDailyR = 0;
int            globalDailyTrades = 0;
int            consecutiveLosses = 0;
ulong          closedPositionsToday[];
int            activePositions = 0;
TradeStats     tradeStats;
FilterStats    filterStats;          // lifetime totals — printed in OnDeinit
int            dailyLpFound    = 0;  // resets each day — shown on dashboard
int            dailySweepFound = 0;
int            dailyBosConf    = 0;
int            dailyRejections = 0;
string         activeSessionName = "None";  // updated by CheckSession() — shown on dashboard
bool           dashboardCollapsed = false;  // toggled by the [-]/[+] button on the dashboard

//+------------------------------------------------------------------+
//| Logging helper                                                   |
//+------------------------------------------------------------------+
void LogDecision(string symbol, string step, bool passed, string detail = "")
{
   // Track lifetime filter stats regardless of debug mode
   if(step == "LiquidityPool") { if(passed) { filterStats.lpPass++; dailyLpFound++; } else filterStats.lpFail++; }
   else if(step == "Sweep")    { if(passed) { filterStats.sweepPass++; dailySweepFound++; } else filterStats.sweepFail++; }
   else if(step == "Trend")    { if(passed) filterStats.trendPass++; else filterStats.trendFail++; }
   else if(step == "BOS")      { if(passed) { filterStats.bosPass++; dailyBosConf++; } else filterStats.bosFail++; }
   else if(step == "Correlation") { if(passed) filterStats.correlPass++; else { filterStats.correlFail++; dailyRejections++; } }
   else if(step == "RiskCalc") { if(passed) filterStats.riskPass++; else { filterStats.riskFail++; dailyRejections++; } }
   else if(step == "EntryApproved") { if(!passed) dailyRejections++; }

   if(!InpDebugMode) return;
   string status = passed ? "PASS" : "FAIL";
   string msg = symbol + " | " + step + " | " + status;
   if(detail != "") msg += " | " + detail;
   Print(msg);
}

//+------------------------------------------------------------------+
//| InitTradeStats — defined before OnInit to avoid forward-ref      |
//+------------------------------------------------------------------+
void InitTradeStats()
{
   tradeStats.tradesToday = 0;
   tradeStats.avgTradesPerDay = 0;
   tradeStats.avgTradesPerSymbol = 0;
   tradeStats.lastUpdate = TimeCurrent();
   for(int i = 0; i < 30; i++)
      tradeStats.dailyHistory[i] = 0;
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Trade.SetExpertMagicNumber(InpMagicNumber);
   Trade.SetMarginMode();
   Trade.SetTypeFillingBySymbol(Symbol());
   Trade.SetDeviationInPoints((int)InpMaxSlippage);

   BuildSymbolList();

   int symbolCnt = ArraySize(symbolList);
   ArrayResize(symbols, symbolCnt);
   ArrayResize(lastBarTime, symbolCnt);
   ArrayResize(closedPositionsToday, 0);

   for(int i = 0; i < symbolCnt; i++)
      InitSymbolData(i);

   ReconcilePositions();

   InitTradeStats();

   if(InpShowDashboard)
      CreateDashboard();

   Print("========================================");
   Print("LIQUIDITY SWEEP EA v7.8 - HIGH FREQUENCY");
   Print("Monitoring: ", IntegerToString(symbolCnt), " symbols");
   Print("Aggressive Mode: ", EnumToString(InpAggressiveMode));
   Print("Correlation Filter: ", InpUseCorrelationFilter ? "ON (max " + IntegerToString(InpMaxCorrelatedPositions) + ")" : "OFF");
   Print("Max Open Positions: ", IntegerToString(InpMaxOpenPositions));
   Print("BOS Mode: ", EnumToString(InpBOSMode));
   if(InpUseSessionFilter)
   {
      Print("Session Filter (GMT): Asian=",   InpSessionAsianOn   ? (IntegerToString(InpAsianStartHour)   + ":" + IntegerToString(InpAsianStartMin)   + "-" + IntegerToString(InpAsianEndHour)   + ":" + IntegerToString(InpAsianEndMin))   : "OFF",
            " | London=", InpSessionLondonOn  ? (IntegerToString(InpLondonStartHour)  + ":" + IntegerToString(InpLondonStartMin)  + "-" + IntegerToString(InpLondonEndHour)  + ":" + IntegerToString(InpLondonEndMin))  : "OFF",
            " | NewYork=", InpSessionNewYorkOn ? (IntegerToString(InpNewYorkStartHour) + ":" + IntegerToString(InpNewYorkStartMin) + "-" + IntegerToString(InpNewYorkEndHour) + ":" + IntegerToString(InpNewYorkEndMin)) : "OFF");
   }
   else
      Print("Session Filter: OFF (trading 24h)");
   Print("Debug Mode: ON - detailed logging enabled");
   Print("========================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i = 0; i < ArraySize(symbols); i++)
      if(symbols[i].atrHandle != INVALID_HANDLE)
         IndicatorRelease(symbols[i].atrHandle);
   DeleteDashboard();
   Comment("");

   int totalPass = filterStats.lpPass + filterStats.sweepPass + filterStats.bosPass +
                   filterStats.correlPass + filterStats.riskPass + filterStats.orderPass;
   int totalFail = filterStats.lpFail + filterStats.sweepFail + filterStats.trendFail +
                   filterStats.bosFail + filterStats.correlFail + filterStats.riskFail + filterStats.orderFail;

   Print("========== FILTER STATISTICS (lifetime) ==========");
   Print(StringFormat("  LiquidityPool : PASS=%d  FAIL=%d", filterStats.lpPass,    filterStats.lpFail));
   Print(StringFormat("  Sweep         : PASS=%d  FAIL=%d", filterStats.sweepPass, filterStats.sweepFail));
   Print(StringFormat("  Trend         : PASS=%d  FAIL=%d", filterStats.trendPass, filterStats.trendFail));
   Print(StringFormat("  BOS           : PASS=%d  FAIL=%d", filterStats.bosPass,   filterStats.bosFail));
   Print(StringFormat("  Correlation   : PASS=%d  FAIL=%d", filterStats.correlPass,filterStats.correlFail));
   Print(StringFormat("  RiskCalc      : PASS=%d  FAIL=%d", filterStats.riskPass,  filterStats.riskFail));
   Print(StringFormat("  OrderSend     : PASS=%d  FAIL=%d", filterStats.orderPass, filterStats.orderFail));
   Print(StringFormat("  TOTAL PASS=%d  TOTAL FAIL=%d", totalPass, totalFail));
   Print("===================================================");
   Print("EA deinitialized");
}

//+------------------------------------------------------------------+
//| Chart events – dashboard collapse/expand toggle                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == "DB_Toggle")
   {
      dashboardCollapsed = (bool)ObjectGetInteger(0, "DB_Toggle", OBJPROP_STATE);
      ObjectSetString(0, "DB_Toggle", OBJPROP_TEXT, dashboardCollapsed ? "+" : "-");
      if(InpShowDashboard) UpdateDashboard();
      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| Symbol list builder                                              |
//+------------------------------------------------------------------+
void BuildSymbolList()
{
   ArrayResize(symbolList, 0);
   string tempList[100];
   int symCount = 0;
   string remaining = InpSymbolList;

   while(StringLen(remaining) > 0 && symCount < 100)
   {
      int commaPos = StringFind(remaining, ",");
      string symbol;
      if(commaPos == -1)
      {
         symbol = remaining;
         remaining = "";
      }
      else
      {
         symbol = StringSubstr(remaining, 0, commaPos);
         remaining = StringSubstr(remaining, commaPos + 1);
      }
      StringTrimLeft(symbol);
      StringTrimRight(symbol);
      if(StringLen(symbol) > 0 && SymbolSelect(symbol, true))
      {
         bool exists = false;
         for(int i = 0; i < symCount; i++)
            if(tempList[i] == symbol) { exists = true; break; }
         if(!exists)
         {
            tempList[symCount] = symbol;
            symCount++;
         }
      }
   }

   if(InpAggressiveMode >= AGGRESSIVE_HIGH && StringLen(InpAdditionalSymbols) > 0)
   {
      remaining = InpAdditionalSymbols;
      while(StringLen(remaining) > 0)
      {
         int commaPos = StringFind(remaining, ",");
         string symbol;
         if(commaPos == -1)
         {
            symbol = remaining;
            remaining = "";
         }
         else
         {
            symbol = StringSubstr(remaining, 0, commaPos);
            remaining = StringSubstr(remaining, commaPos + 1);
         }
         StringTrimLeft(symbol);
         StringTrimRight(symbol);
         if(StringLen(symbol) > 0 && SymbolSelect(symbol, true))
         {
            bool exists = false;
            for(int i = 0; i < symCount; i++)
               if(tempList[i] == symbol) { exists = true; break; }
            if(!exists)
            {
               tempList[symCount] = symbol;
               symCount++;
            }
         }
      }
   }

   if(InpIncludeGold && SymbolSelect("XAUUSD", true))
   {
      bool exists = false;
      for(int i = 0; i < symCount; i++)
         if(tempList[i] == "XAUUSD") { exists = true; break; }
      if(!exists)
      {
         tempList[symCount] = "XAUUSD";
         symCount++;
      }
   }

   // NOTE: InpIncludeIndices is reserved for a future index-symbol block here

   ArrayResize(symbolList, symCount);
   for(int i = 0; i < symCount; i++)
      symbolList[i] = tempList[i];
}

//+------------------------------------------------------------------+
//| Initialize symbol data                                           |
//+------------------------------------------------------------------+
void InitSymbolData(int idx)
{
   symbols[idx].name = symbolList[idx];
   symbols[idx].pipSize = GetPipSize(symbols[idx].name);
   symbols[idx].minLot = SymbolInfoDouble(symbols[idx].name, SYMBOL_VOLUME_MIN);
   symbols[idx].maxLot = SymbolInfoDouble(symbols[idx].name, SYMBOL_VOLUME_MAX);
   symbols[idx].lotStep = SymbolInfoDouble(symbols[idx].name, SYMBOL_VOLUME_STEP);
   symbols[idx].spreadLimit = GetSpreadLimit(symbols[idx].name);
   symbols[idx].currentSpread = 0;
   symbols[idx].avgSpread = 0;
   symbols[idx].isActive = true;
   symbols[idx].hasSetup = false;
   symbols[idx].setupDirection = DIR_NONE;
   symbols[idx].positionDirection = DIR_NONE;
   symbols[idx].setupValid = false;
   symbols[idx].positionTicket = 0;
   symbols[idx].positionTicket2 = 0;
   symbols[idx].dealTicket = 0;
   symbols[idx].tradesToday = 0;
   symbols[idx].dailyR = 0;
   symbols[idx].entriesThisSweep = 0;
   symbols[idx].lastSweepTime = 0;
   symbols[idx].lastBOSTime = 0;
   symbols[idx].sweepBarTime = 0;
   symbols[idx].currentSweepId = "";
   symbols[idx].atr = 0;
   symbols[idx].trend = 0;
   symbols[idx].riskAmount = 0;
   symbols[idx].partialClosed = false;
   symbols[idx].breakEvenActivated = false;
   symbols[idx].riskAmount2 = 0;
   symbols[idx].lastTradeTime = 0;
   symbols[idx].signalTime = 0;
   symbols[idx].totalLot = 0;

   symbols[idx].perf.name = symbols[idx].name;
   symbols[idx].perf.totalTrades = 0;
   symbols[idx].perf.winningTrades = 0;
   symbols[idx].perf.totalR = 0;
   symbols[idx].perf.winRate = 0;
   symbols[idx].perf.avgRR = 0;
   symbols[idx].perf.isDisabled = false;
   symbols[idx].perf.avgSpread = 0;
   symbols[idx].perf.spreadSamples = 0;

   symbols[idx].atrHandle = iATR(symbols[idx].name, InpSweepTF, 14);
   if(symbols[idx].atrHandle == INVALID_HANDLE)
      Print("Failed to create ATR handle for ", symbols[idx].name);
}

//+------------------------------------------------------------------+
//| Re-adopt positions already open at startup (EA restart/recompile  |
//| while a trade was live) so trailing/breakeven/partial-close and   |
//| R-tracking resume instead of leaving the position untracked.      |
//+------------------------------------------------------------------+
void ReconcilePositions()
{
   for(int p = 0; p < PositionsTotal(); p++)
   {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      string posSymbol = PositionGetString(POSITION_SYMBOL);
      int idx = -1;
      for(int i = 0; i < ArraySize(symbols); i++)
         if(symbols[i].name == posSymbol) { idx = i; break; }
      if(idx < 0)
      {
         Print("WARNING: open position on ", posSymbol, " (ticket ", ticket, ") is not in the current symbol list — it will not be managed");
         continue;
      }

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl         = PositionGetDouble(POSITION_SL);
      double tp         = PositionGetDouble(POSITION_TP);
      double volume     = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_DIRECTION dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) ? DIR_SHORT : DIR_LONG;

      double riskAmount = 0;
      if(sl > 0)
      {
         double tickSize  = SymbolInfoDouble(posSymbol, SYMBOL_TRADE_TICK_SIZE);
         double tickValue = SymbolInfoDouble(posSymbol, SYMBOL_TRADE_TICK_VALUE);
         if(tickSize > 0 && tickValue > 0)
            riskAmount = (MathAbs(openPrice - sl) / tickSize) * tickValue * volume;
      }

      if(symbols[idx].positionTicket == 0)
      {
         symbols[idx].positionTicket = ticket;
         symbols[idx].riskAmount = riskAmount;
      }
      else if(symbols[idx].positionTicket2 == 0)
      {
         symbols[idx].positionTicket2 = ticket;
         symbols[idx].riskAmount2 = riskAmount;
      }
      else
      {
         Print("WARNING: more than 2 open positions found on ", posSymbol, " — ticket ", ticket, " will not be managed");
         continue;
      }

      symbols[idx].positionDirection  = dir;
      symbols[idx].entryPrice         = openPrice;
      symbols[idx].stopLoss           = sl;
      symbols[idx].takeProfit         = tp;
      symbols[idx].totalLot           = volume;
      // Can't tell from the position alone whether a partial close already
      // happened pre-restart, so assume not — worst case is one extra
      // partial-close attempt on a position that already had one.
      symbols[idx].partialClosed      = false;
      symbols[idx].breakEvenActivated = false;

      int digits = (int)SymbolInfoInteger(posSymbol, SYMBOL_DIGITS);
      Print("Reconciled open position: ", posSymbol, " ticket=", IntegerToString(ticket),
            " dir=", (dir == DIR_SHORT ? "SHORT" : "LONG"),
            " entry=", DoubleToString(openPrice, digits),
            " risk=$", DoubleToString(riskAmount, 2));
   }
}

//+------------------------------------------------------------------+
//| Basic helpers                                                    |
//+------------------------------------------------------------------+
double GetPipSize(string symbol)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(symbol == "XAUUSD") return point * 10;
   return (digits == 3 || digits == 5) ? point * 10 : point;
}

double GetSpreadLimit(string symbol)
{
   if(symbol == "EURUSD") return InpSpreadLimitEURUSD;
   if(symbol == "GBPUSD") return InpSpreadLimitGBPUSD;
   if(symbol == "USDJPY") return InpSpreadLimitUSDJPY;
   if(symbol == "XAUUSD") return InpSpreadLimitXAUUSD;
   return InpSpreadLimitDefault;
}

bool GetSymbolTick(string symbol, MqlTick &tick)
{
   return SymbolInfoTick(symbol, tick);
}

bool IsNewBar(int idx, ENUM_TIMEFRAMES tf)
{
   datetime currentBarTime = iTime(symbols[idx].name, tf, 0);
   if(currentBarTime != lastBarTime[idx])
   {
      lastBarTime[idx] = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Session check — true if ANY enabled session window is active.   |
//| Handles windows that cross midnight (e.g. Asian 23:00-08:00).   |
//+------------------------------------------------------------------+
bool InSessionWindow(int currentMinutes, int startH, int startM, int endH, int endM)
{
   int startMinutes = startH * 60 + startM;
   int endMinutes   = endH * 60 + endM;
   if(startMinutes == endMinutes) return true;  // 24h window
   if(startMinutes < endMinutes)
      return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
   return (currentMinutes >= startMinutes || currentMinutes < endMinutes);  // wraps midnight
}

bool CheckSession()
{
   if(!InpUseSessionFilter) { activeSessionName = "ALL (filter off)"; return true; }
   MqlDateTime dtGMT;
   TimeToStruct(TimeGMT(), dtGMT);
   int currentMinutes = dtGMT.hour * 60 + dtGMT.min;

   bool active = false;
   string names = "";
   if(InpSessionAsianOn && InSessionWindow(currentMinutes, InpAsianStartHour, InpAsianStartMin, InpAsianEndHour, InpAsianEndMin))
      { active = true; names += "Asian "; }
   if(InpSessionLondonOn && InSessionWindow(currentMinutes, InpLondonStartHour, InpLondonStartMin, InpLondonEndHour, InpLondonEndMin))
      { active = true; names += "London "; }
   if(InpSessionNewYorkOn && InSessionWindow(currentMinutes, InpNewYorkStartHour, InpNewYorkStartMin, InpNewYorkEndHour, InpNewYorkEndMin))
      { active = true; names += "NewYork "; }
   activeSessionName = active ? names : "None";

   // Log only when status changes — not every tick — to keep journal clean
   if(InpDebugMode)
   {
      static bool lastSessionActive = false;
      static string lastSessionName = "";
      if(active != lastSessionActive || activeSessionName != lastSessionName)
      {
         MqlDateTime dtLocal;
         TimeToStruct(TimeCurrent(), dtLocal);
         Print("Session ", active ? "OPEN (" + activeSessionName + ")" : "CLOSED",
               " | Broker ", dtLocal.hour, ":", dtLocal.min,
               " | GMT ", dtGMT.hour, ":", dtGMT.min);
         lastSessionActive = active;
         lastSessionName = activeSessionName;
      }
   }
   return active;
}

//+------------------------------------------------------------------+
//| ATR, Trend, Liquidity pool helpers                               |
//+------------------------------------------------------------------+
bool CheckATR(int idx)
{
   if(symbols[idx].atrHandle == INVALID_HANDLE) return true;
   double atrValue[1];
   if(CopyBuffer(symbols[idx].atrHandle, 0, 0, 1, atrValue) < 1) return true;
   symbols[idx].atr = atrValue[0];
   double minATR = GetMinATR() * symbols[idx].pipSize;
   return (symbols[idx].atr >= minATR);
}

double GetMinATR()
{
   switch(InpAggressiveMode)
   {
      case AGGRESSIVE_ULTRA: return InpMinATR * 0.4;
      case AGGRESSIVE_HIGH:  return InpMinATR * 0.6;
      case AGGRESSIVE_MEDIUM: return InpMinATR * 0.8;
      default: return InpMinATR;
   }
}

bool CheckTrend(int idx)
{
   if(InpTrendFilter == FILTER_NONE) return true;
   int period = (int)InpTrendFilter;
   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(symbols[idx].name, InpSweepTF, 0, period + 1, close) < period + 1)
      return true;
   double sma = 0;
   for(int i = 1; i <= period; i++) sma += close[i];
   sma /= period;
   symbols[idx].trend = sma;
   if(symbols[idx].setupDirection == DIR_SHORT)
      return (close[0] < sma);
   else if(symbols[idx].setupDirection == DIR_LONG)
      return (close[0] > sma);
   return true;
}

double FindLiquidityPoolLevel(int idx, bool findHigh, ENUM_TIMEFRAMES tf)
{
   double arr[];
   int bars = InpLookbackN;
   ArraySetAsSeries(arr, true);
   if(findHigh)
   {
      if(CopyHigh(symbols[idx].name, tf, 1, bars, arr) < bars) return 0;
   }
   else
   {
      if(CopyLow(symbols[idx].name, tf, 1, bars, arr) < bars) return 0;
   }
   double deltaPrice = InpDeltaPips * symbols[idx].pipSize;
   int bestClusterSize = 0;
   double bestLevel = 0;
   for(int i = 0; i < bars; i++)
   {
      double testLevel = arr[i];
      int clusterCount = 0;
      for(int j = 0; j < bars; j++)
         if(MathAbs(testLevel - arr[j]) <= deltaPrice) clusterCount++;
      if(clusterCount > bestClusterSize)
      {
         bestClusterSize = clusterCount;
         bestLevel = testLevel;
      }
   }
   int minCluster = (InpAggressiveMode >= AGGRESSIVE_MEDIUM) ? 2 : 3;
   if(bestClusterSize >= minCluster) return bestLevel;
   // ULTRA: no repeated level found in the lookback window — fall back to the
   // single most extreme high/low so the funnel never stalls at pool detection
   if(InpAggressiveMode == AGGRESSIVE_ULTRA)
      return findHigh ? arr[ArrayMaximum(arr)] : arr[ArrayMinimum(arr)];
   return 0;
}

double GetSweepMinPips(int idx)
{
   double base = InpSweepMinPips;
   switch(InpAggressiveMode)
   {
      case AGGRESSIVE_ULTRA: base *= 0.4; break;
      case AGGRESSIVE_HIGH:  base *= 0.6; break;
      case AGGRESSIVE_MEDIUM: base *= 0.8; break;
      default: break;
   }
   double atrPips = symbols[idx].atr / symbols[idx].pipSize;
   double atrFloor = atrPips * InpSweepATRRatio;
   return MathMax(base, atrFloor);
}

ENUM_TIMEFRAMES GetSweepTF()
{
   if(InpUseM1Sweep || InpAggressiveMode == AGGRESSIVE_ULTRA)
      return PERIOD_M1;
   return InpSweepTF;
}

//+------------------------------------------------------------------+
//| Daily reset and trade statistics                                 |
//+------------------------------------------------------------------+
void UpdateDailyReset()
{
   datetime currentDayStart = iTime(_Symbol, PERIOD_D1, 0);
   if(todayStart != currentDayStart)
   {
      todayStart = currentDayStart;
      globalDailyR = 0;
      globalDailyTrades = 0;
      consecutiveLosses = 0;
      ArrayResize(closedPositionsToday, 0);
      for(int i = 0; i < ArraySize(symbols); i++)
      {
         symbols[i].tradesToday = 0;
         symbols[i].dailyR = 0;
      }
      dailyLpFound    = 0;
      dailySweepFound = 0;
      dailyBosConf    = 0;
      dailyRejections = 0;
      UpdateTradeStats();
      if(InpDebugMode) Print("Daily reset");
   }
}

void UpdateTradeStats()
{
   int currentDay = (int)((TimeCurrent() - todayStart) / 86400);
   if(currentDay >= 30) currentDay = 29;
   if(currentDay >= 0) tradeStats.dailyHistory[currentDay] = globalDailyTrades;
   tradeStats.tradesToday = globalDailyTrades;
   int totalDays = 0;
   int totalTrades = 0;
   for(int i = 0; i < 7 && i < 30; i++)
   {
      if(i <= currentDay && currentDay >= 0)
      {
         totalTrades += tradeStats.dailyHistory[i];
         totalDays++;
      }
   }
   tradeStats.avgTradesPerDay = (totalDays > 0) ? (double)totalTrades / totalDays : 0;
   int activeSymbolCount = 0;
   int totalSymbolTrades = 0;
   for(int i = 0; i < ArraySize(symbols); i++)
   {
      if(symbols[i].perf.totalTrades > 0)
      {
         totalSymbolTrades += symbols[i].perf.totalTrades;
         activeSymbolCount++;
      }
   }
   tradeStats.avgTradesPerSymbol = (activeSymbolCount > 0) ? (double)totalSymbolTrades / activeSymbolCount : 0;
}

int GetSymbolDailyLimit()
{
   if(InpMaxTradesPerSymbol > 0) return InpMaxTradesPerSymbol;
   if(InpMaxDailyTrades <= 0) return INT_MAX;  // global cap unlimited -> per-symbol cap unlimited too
   int activeSymbols = 0;
   for(int i = 0; i < ArraySize(symbols); i++)
      if(!symbols[i].perf.isDisabled) activeSymbols++;
   if(activeSymbols == 0) return InpMaxDailyTrades;
   return MathMax(3, InpMaxDailyTrades / activeSymbols) + 2;
}

double NormalizeLot(int idx, double lot)
{
   double minLot = symbols[idx].minLot;
   double maxLot = symbols[idx].maxLot;
   double step = symbols[idx].lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   if(step > 0) lot = MathRound(lot / step) * step;
   return lot;
}

int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Correlation (optional)                                           |
//+------------------------------------------------------------------+
double GetUSDExposure(string symbol, bool isLong)
{
   if(StringFind(symbol, "EURUSD") >= 0) return isLong ? -1 : 1;
   if(StringFind(symbol, "GBPUSD") >= 0) return isLong ? -1 : 1;
   if(StringFind(symbol, "AUDUSD") >= 0) return isLong ? -1 : 1;
   if(StringFind(symbol, "NZDUSD") >= 0) return isLong ? -1 : 1;
   if(StringFind(symbol, "USDJPY") >= 0) return isLong ? 1 : -1;
   if(StringFind(symbol, "USDCAD") >= 0) return isLong ? 1 : -1;
   if(StringFind(symbol, "USDCHF") >= 0) return isLong ? 1 : -1;
   return 0;
}

bool CheckCorrelationLimit(int idx)
{
   if(!InpUseCorrelationFilter) return true;
   if(InpMaxCorrelatedPositions == 0) return true;
   double thisExposure = GetUSDExposure(symbols[idx].name, symbols[idx].setupDirection == DIR_LONG);
   if(thisExposure == 0) return true;
   int sameDirectionCount = 0;
   for(int i = 0; i < ArraySize(symbols); i++)
   {
      if(symbols[i].positionTicket != 0)
      {
         double existingExposure = GetUSDExposure(symbols[i].name, symbols[i].positionDirection == DIR_LONG);
         if(existingExposure != 0 && existingExposure == thisExposure)
            sameDirectionCount++;
      }
   }
   bool ok = (sameDirectionCount < InpMaxCorrelatedPositions);
   if(InpDebugMode && !ok)
      LogDecision(symbols[idx].name, "Correlation", false, "Exposure=" + DoubleToString(thisExposure,1) + " Count=" + IntegerToString(sameDirectionCount));
   return ok;
}

//+------------------------------------------------------------------+
//| Main processing                                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDailyReset();
   activePositions = CountOpenPositions();

   // Manage already-open positions every tick regardless of whether new
   // entries are currently gated — trailing stop/break-even/partial close
   // must never freeze just because a daily/session limit is active.
   for(int i = 0; i < ArraySize(symbols); i++)
      if(symbols[i].positionTicket != 0)
         ManagePositions(i);

   if(InpShowDashboard) UpdateDashboard();
   if(InpMaxDailyTrades > 0 && globalDailyTrades >= InpMaxDailyTrades) return;
   // InpMaxDailyNetR is informational only — hitting the target no longer
   // pauses trading; only the loss limit below and a manual stop do.
   if(globalDailyR <= InpMaxDailyLossR) return;
   // Session is global — check once here, not per-symbol
   if(!CheckSession()) return;
   if(activePositions >= InpMaxOpenPositions) return;
   for(int i = 0; i < ArraySize(symbols); i++)
   {
      if(!symbols[i].isActive) continue;
      if(InpAutoDisablePoorSymbols && !symbols[i].perf.isDisabled &&
         symbols[i].perf.totalTrades >= InpMinTradesForDecision &&
         symbols[i].perf.winRate < (InpMinWinRate / 100.0))
      {
         symbols[i].perf.isDisabled = true;
         Print(symbols[i].name, " DISABLED - Win rate: ", DoubleToString(symbols[i].perf.winRate * 100, 1), "%");
         continue;
      }
      if(symbols[i].perf.isDisabled) continue;
      if(symbols[i].tradesToday >= GetSymbolDailyLimit()) continue;
      ProcessSymbol(i);
   }
}

void ProcessSymbol(int idx)
{
   string sym = symbols[idx].name;
   if(!GetSymbolTick(sym, currentTick)) return;
   double spreadValue = (currentTick.ask - currentTick.bid) / symbols[idx].pipSize;
   symbols[idx].currentSpread = spreadValue;
   bool spreadOK = (spreadValue <= symbols[idx].spreadLimit);
   LogDecision(sym, "Spread", spreadOK, DoubleToString(spreadValue,1) + " / " + DoubleToString(symbols[idx].spreadLimit,1));
   if(!spreadOK) return;
   // Session already checked once in OnTick — no redundant per-symbol check here
   bool atrOK = CheckATR(idx);
   LogDecision(sym, "ATR", atrOK, DoubleToString(symbols[idx].atr / symbols[idx].pipSize,1) + " pips");
   if(!atrOK) return;
   // Position management now runs unconditionally at the top of OnTick()
   ENUM_TIMEFRAMES sweepTF = GetSweepTF();
   if(!IsNewBar(idx, sweepTF)) return;
   FindSetup(idx, sweepTF);
}

//+------------------------------------------------------------------+
//| FindSetup, Confirmation, Risk, Execute (with Ultra BOS bypass)   |
//+------------------------------------------------------------------+
void FindSetup(int idx, ENUM_TIMEFRAMES tf)
{
   if(symbols[idx].positionTicket != 0) return;
   string sym = symbols[idx].name;
   double high[], low[], close[], open[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open, true);
   int bars = 5;
   if(CopyHigh(sym, tf, 1, bars, high) < bars) return;
   if(CopyLow(sym, tf, 1, bars, low) < bars) return;
   if(CopyClose(sym, tf, 1, bars, close) < bars) return;
   if(CopyOpen(sym, tf, 1, bars, open) < bars) return;
   double sweepMin = GetSweepMinPips(idx) * symbols[idx].pipSize;
   datetime currentBarTime = iTime(sym, tf, 0);
   double lpHigh = FindLiquidityPoolLevel(idx, true, tf);
   double lpLow = FindLiquidityPoolLevel(idx, false, tf);

   // BOS_BYPASS: skip body-direction check — any sweep candle qualifies
   // BOS_NORMAL / BOS_RELAXED: require bearish/bullish close for quality filtering
   bool checkBody = (InpBOSMode != BOS_BYPASS);

   bool shortOK = (lpHigh > 0 && close[0] < lpHigh && high[0] > lpHigh + sweepMin &&
                   (!checkBody || close[0] < open[0]));
   bool longOK  = (lpLow  > 0 && close[0] > lpLow  && low[0]  < lpLow  - sweepMin &&
                   (!checkBody || close[0] > open[0]));

   if(shortOK)
   {
      LogDecision(sym, "LiquidityPool", true, "High pool at " + DoubleToString(lpHigh,5));
      LogDecision(sym, "Sweep", true, "Bearish sweep");
      symbols[idx].setupDirection = DIR_SHORT;
      symbols[idx].lpLevel = lpHigh;
      symbols[idx].sweepExtreme = high[0];
      symbols[idx].sweepBarTime = currentBarTime;
      symbols[idx].setupValid = true;
      symbols[idx].signalTime = TimeCurrent();
      symbols[idx].partialClosed = false;
   }
   else if(longOK)
   {
      LogDecision(sym, "LiquidityPool", true, "Low pool at " + DoubleToString(lpLow,5));
      LogDecision(sym, "Sweep", true, "Bullish sweep");
      symbols[idx].setupDirection = DIR_LONG;
      symbols[idx].lpLevel = lpLow;
      symbols[idx].sweepExtreme = low[0];
      symbols[idx].sweepBarTime = currentBarTime;
      symbols[idx].setupValid = true;
      symbols[idx].signalTime = TimeCurrent();
      symbols[idx].partialClosed = false;
   }
   else
   {
      LogDecision(sym, "LiquidityPool", false, "No pool / no sweep");
      return;
   }

   string sweepKey = (symbols[idx].setupDirection == DIR_SHORT ? "H" : "L") +
                     DoubleToString(symbols[idx].lpLevel,8) + "_" + IntegerToString(currentBarTime);
   if(symbols[idx].currentSweepId != sweepKey)
   {
      symbols[idx].currentSweepId = sweepKey;
      symbols[idx].entriesThisSweep = 0;
   }
   if(InpAllowReEntry && symbols[idx].entriesThisSweep >= InpMaxEntriesPerSweep)
   {
      LogDecision(sym, "ReEntryLimit", false, "Max entries reached");
      return;
   }

   bool trendOK = CheckTrend(idx);
   LogDecision(sym, "Trend", trendOK);
   if(!trendOK) return;

   bool confirmed = false;
   switch(InpBOSMode)
   {
      case BOS_BYPASS:
         confirmed = true;
         LogDecision(sym, "BOS", true, "BYPASS - direct entry");
         break;
      case BOS_RELAXED:
         confirmed = CheckConfirmation(idx, true);
         LogDecision(sym, "BOS", confirmed, "RELAXED - swing point only");
         break;
      default: // BOS_NORMAL
         confirmed = CheckConfirmation(idx, false);
         LogDecision(sym, "BOS", confirmed, "NORMAL - swing + close required");
         break;
   }
   if(!confirmed) return;

   bool correlOK = CheckCorrelationLimit(idx);
   LogDecision(sym, "Correlation", correlOK);
   if(!correlOK) return;

   if(!CheckRiskAndEntry(idx))
   {
      LogDecision(sym, "RiskCalc", false, "Lot size zero");
      return;
   }

   // Enforce minimum R:R before executing
   double riskDist = MathAbs(symbols[idx].entryPrice - symbols[idx].stopLoss);
   double rewardDist = MathAbs(symbols[idx].takeProfit - symbols[idx].entryPrice);
   double actualRR = (riskDist > 0) ? rewardDist / riskDist : 0;
   if(actualRR < InpMinRR)
   {
      LogDecision(sym, "MinRR", false, "RR=" + DoubleToString(actualRR,2) + " < " + DoubleToString(InpMinRR,2));
      return;
   }

   LogDecision(sym, "RiskCalc", true, "Lot=" + DoubleToString(symbols[idx].totalLot,2) + " RR=" + DoubleToString(actualRR,2));
   LogDecision(sym, "EntryApproved", true, "Executing trade");
   ExecuteTrade(idx);
}

// relaxedMode = true  → BOS_RELAXED: swing point only, no close-beyond required
// relaxedMode = false → BOS_NORMAL:  swing point AND subsequent close beyond it
bool CheckConfirmation(int idx, bool relaxedMode)
{
   MqlRates m1[];
   // Look back far enough to always have bars — sweepBarTime may be only seconds old
   datetime startTime = TimeCurrent() - 1800; // 30 min back on M1 = 30 bars guaranteed
   int copied = CopyRates(symbols[idx].name, InpConfTF, startTime, TimeCurrent(), m1);
   if(copied < 3) return false;
   ArraySetAsSeries(m1, true);
   bool bosConfirmed = false;
   int maxScan = MathMin(copied, 20);

   if(symbols[idx].setupDirection == DIR_SHORT)
   {
      for(int i = 2; i < maxScan - 2; i++)
      {
         if(m1[i].low < m1[i-1].low && m1[i].low < m1[i+1].low)
         {
            if(relaxedMode) { bosConfirmed = true; break; }
            for(int j = 0; j < i && j < 10; j++)
               if(m1[j].close < m1[i].low) { bosConfirmed = true; break; }
            if(bosConfirmed) break;
         }
      }
   }
   else
   {
      for(int i = 2; i < maxScan - 2; i++)
      {
         if(m1[i].high > m1[i-1].high && m1[i].high > m1[i+1].high)
         {
            if(relaxedMode) { bosConfirmed = true; break; }
            for(int j = 0; j < i && j < 10; j++)
               if(m1[j].close > m1[i].high) { bosConfirmed = true; break; }
            if(bosConfirmed) break;
         }
      }
   }
   return bosConfirmed;
}

bool CheckRiskAndEntry(int idx)
{
   MqlTick tick;
   if(!SymbolInfoTick(symbols[idx].name, tick)) return false;

   // Entry: current market price — tick is always available, no bar history needed
   double newEntry = (symbols[idx].setupDirection == DIR_SHORT) ? tick.bid : tick.ask;

   // FVG override — only fetch bars when actually enabled
   if(!InpDirectBOSEntry && InpUseFVG)
   {
      MqlRates m1[];
      datetime fvgStart = TimeCurrent() - 1800; // look back 30 min max
      int copied = CopyRates(symbols[idx].name, InpConfTF, fvgStart, TimeCurrent(), m1);
      if(copied >= 3)
      {
         ArraySetAsSeries(m1, true);
         for(int i = 0; i < MathMin(copied, 15) - 2; i++)
         {
            if(symbols[idx].setupDirection == DIR_SHORT && m1[i].low > m1[i+2].high)
            { newEntry = (m1[i].low + m1[i+2].high) / 2.0; break; }
            else if(symbols[idx].setupDirection == DIR_LONG && m1[i].high < m1[i+2].low)
            { newEntry = (m1[i].high + m1[i+2].low) / 2.0; break; }
         }
      }
   }

   if(newEntry <= 0) newEntry = (symbols[idx].setupDirection == DIR_SHORT) ? tick.bid : tick.ask;
   symbols[idx].entryPrice = newEntry;

   double buffer = InpSlBufferPips * symbols[idx].pipSize;
   // InpMaxSlPips == 0 means no cap; otherwise clamp SL distance to that pip count
   double slCapPrice = (InpMaxSlPips > 0) ? InpMaxSlPips * symbols[idx].pipSize : DBL_MAX;
   double riskDistance = 0;
   if(symbols[idx].setupDirection == DIR_SHORT)
   {
      symbols[idx].stopLoss = MathMin(symbols[idx].sweepExtreme + buffer,
                                      symbols[idx].entryPrice + slCapPrice);
      riskDistance = symbols[idx].stopLoss - symbols[idx].entryPrice;
   }
   else
   {
      symbols[idx].stopLoss = MathMax(symbols[idx].sweepExtreme - buffer,
                                      symbols[idx].entryPrice - slCapPrice);
      riskDistance = symbols[idx].entryPrice - symbols[idx].stopLoss;
   }
   double minStop = 3 * symbols[idx].pipSize;
   if(riskDistance < minStop)
   {
      if(symbols[idx].setupDirection == DIR_SHORT) symbols[idx].stopLoss = symbols[idx].entryPrice + minStop;
      else symbols[idx].stopLoss = symbols[idx].entryPrice - minStop;
      riskDistance = minStop;
   }
   if(symbols[idx].setupDirection == DIR_SHORT)
   {
      symbols[idx].takeProfit = symbols[idx].entryPrice - (riskDistance * InpTP_R);
      symbols[idx].partialTP = symbols[idx].entryPrice - (riskDistance * InpPartialTP_R);
   }
   else
   {
      symbols[idx].takeProfit = symbols[idx].entryPrice + (riskDistance * InpTP_R);
      symbols[idx].partialTP = symbols[idx].entryPrice + (riskDistance * InpPartialTP_R);
   }
   double tickSize = SymbolInfoDouble(symbols[idx].name, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbols[idx].name, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0) return false;
   double ticks = riskDistance / tickSize;
   double lossPerLot = ticks * tickValue;
   if(lossPerLot <= 0) return false;
   if(InpFixedLotSize > 0)
   {
      symbols[idx].totalLot = InpFixedLotSize;
   }
   else
   {
      double riskPercent = InpRiskPercent;
      if(consecutiveLosses >= 5) riskPercent = InpRiskPercent * 0.25;
      else if(consecutiveLosses >= 3) riskPercent = InpRiskPercent * 0.5;
      double riskMoney = (riskPercent / 100.0) * AccountInfoDouble(ACCOUNT_BALANCE);
      symbols[idx].totalLot = riskMoney / lossPerLot;
   }
   symbols[idx].totalLot = NormalizeLot(idx, symbols[idx].totalLot);
   symbols[idx].riskAmount = symbols[idx].totalLot * lossPerLot;
   return (symbols[idx].totalLot > 0);
}

void ExecuteTrade(int idx)
{
   if(symbols[idx].totalLot <= 0) return;
   if(!SymbolSelect(symbols[idx].name, true)) return;
   MqlTick tick;
   if(!SymbolInfoTick(symbols[idx].name, tick)) return;
   CTrade symbolTrade;
   symbolTrade.SetExpertMagicNumber(InpMagicNumber);
   symbolTrade.SetDeviationInPoints((int)InpMaxSlippage);
   bool result = false;
   if(symbols[idx].setupDirection == DIR_SHORT)
      result = symbolTrade.Sell(symbols[idx].totalLot, symbols[idx].name, tick.bid, symbols[idx].stopLoss, symbols[idx].takeProfit, InpComment);
   else
      result = symbolTrade.Buy(symbols[idx].totalLot, symbols[idx].name, tick.ask, symbols[idx].stopLoss, symbols[idx].takeProfit, InpComment);
   if(result)
   {
      filterStats.orderPass++;
      ulong dealTicket = symbolTrade.ResultDeal();
      symbols[idx].dealTicket = dealTicket;
      if(dealTicket > 0 && HistoryDealSelect(dealTicket))
      {
         ulong positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket > 0 && PositionSelectByTicket(ticket) &&
               PositionGetInteger(POSITION_IDENTIFIER) == (long)positionId)
            {
               if(symbols[idx].positionTicket == 0)
               {
                  symbols[idx].positionTicket = ticket;
                  // riskAmount already set by CheckRiskAndEntry for this ticket
               }
               else if(symbols[idx].positionTicket2 == 0)
               {
                  symbols[idx].positionTicket2 = ticket;
                  symbols[idx].riskAmount2 = symbols[idx].riskAmount; // same lot/risk as ticket1
               }
               break;
            }
         }
      }
      symbols[idx].positionDirection = symbols[idx].setupDirection;
      symbols[idx].entriesThisSweep++;
      symbols[idx].breakEvenActivated = false;
      symbols[idx].lastTradeTime = TimeCurrent();
      globalDailyTrades++;    // counts entries (opens), not completed trades — intentional
      symbols[idx].tradesToday++;
      if(InpDebugMode) Print(symbols[idx].name, " Trade executed. Daily trades: ", IntegerToString(globalDailyTrades));
   }
   else
   {
      filterStats.orderFail++;
      Print(symbols[idx].name, " Trade failed: ", symbolTrade.ResultRetcodeDescription());
   }
   symbols[idx].setupValid = false;
}

//+------------------------------------------------------------------+
//| Position management                                              |
//+------------------------------------------------------------------+
void ManagePositions(int idx)
{
   if(symbols[idx].positionTicket == 0) return;
   for(int p = 0; p < 2; p++)
   {
      ulong ticket = (p == 0) ? symbols[idx].positionTicket : symbols[idx].positionTicket2;
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double currentLot = PositionGetDouble(POSITION_VOLUME);
      MqlTick tick;
      if(!SymbolInfoTick(symbols[idx].name, tick)) continue;
      double currentPrice = (symbols[idx].positionDirection == DIR_SHORT) ? tick.bid : tick.ask;
      double profitPips = 0;
      if(symbols[idx].positionDirection == DIR_SHORT)
         profitPips = (openPrice - currentPrice) / symbols[idx].pipSize;
      else
         profitPips = (currentPrice - openPrice) / symbols[idx].pipSize;
      double riskPips = MathAbs(openPrice - symbols[idx].stopLoss) / symbols[idx].pipSize;
      if(riskPips <= 0) continue;
      double profitR = profitPips / riskPips;
      if(!symbols[idx].partialClosed && profitR >= InpPartialTP_R)
      {
         if(currentLot > symbols[idx].minLot * 1.5)
         {
            double closeLot = currentLot * 0.5;
            closeLot = NormalizeLot(idx, closeLot);
            double remainingLot = currentLot - closeLot;
            if(closeLot >= symbols[idx].minLot && remainingLot >= symbols[idx].minLot)
            {
               CTrade closeTrade;
               closeTrade.SetExpertMagicNumber(InpMagicNumber);
               if(closeTrade.PositionClosePartial(ticket, closeLot))
                  symbols[idx].partialClosed = true;
            }
         }
      }
      if(InpUseBreakEven && profitR >= InpBreakEvenR && !symbols[idx].breakEvenActivated)
      {
         CTrade beTrade;
         beTrade.SetExpertMagicNumber(InpMagicNumber);
         if(beTrade.PositionModify(ticket, openPrice, currentTP))
            symbols[idx].breakEvenActivated = true;
      }
      if(InpUseTrailingStop && profitR >= InpTrailingStart)
      {
         double newSL = currentSL;
         double trailDistance = riskPips * InpTrailingStep * symbols[idx].pipSize;
         if(symbols[idx].positionDirection == DIR_SHORT)
         {
            double candidateSL = currentPrice + trailDistance;
            // Never trail SL back above open price (would convert profit to loss)
            if(candidateSL > openPrice) candidateSL = openPrice;
            if((candidateSL < currentSL || currentSL == 0) && candidateSL > 0)
               newSL = candidateSL;
         }
         else
         {
            double candidateSL = currentPrice - trailDistance;
            // Never trail SL back below open price (would convert profit to loss)
            if(candidateSL < openPrice) candidateSL = openPrice;
            if((candidateSL > currentSL || currentSL == 0) && candidateSL > 0)
               newSL = candidateSL;
         }
         if(newSL != currentSL && newSL > 0)
         {
            CTrade trailTrade;
            trailTrade.SetExpertMagicNumber(InpMagicNumber);
            trailTrade.PositionModify(ticket, newSL, currentTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Dashboard helpers                                                |
//+------------------------------------------------------------------+

#define DB_WIDTH            264
#define DB_HEIGHT            360  // expanded panel height
#define DB_HEIGHT_COLLAPSED  28   // title-bar-only height when collapsed (title only, nothing else)

// Translate InpDashboardCorner + offsets into absolute top-left pixel
// coords for the panel, then always use CORNER_LEFT_UPPER for every
// object so text never renders off-screen and y always goes downward.
int GetPanelX()
{
   if(InpDashboardCorner == 1 || InpDashboardCorner == 2)
      return (int)(ChartGetInteger(0, CHART_WIDTH_IN_PIXELS) - InpDashboardXOffset - DB_WIDTH);
   return InpDashboardXOffset;
}

int GetPanelY()
{
   if(InpDashboardCorner == 2 || InpDashboardCorner == 3)
      return (int)(ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS) - InpDashboardYOffset - DB_HEIGHT);
   return InpDashboardYOffset;
}

void DeleteDashboard()
{
   ObjectsDeleteAll(0, "DB_");
}

void CreateOrUpdateLabel(string name, int x, int y, int corner, color clr, string text)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

string BOSModeText(ENUM_BOS_MODE mode)
{
   switch(mode)
   {
      case BOS_NORMAL:  return "Bos_Normal";
      case BOS_RELAXED: return "Bos_Relaxed";
      case BOS_BYPASS:  return "Bos_Bypass";
   }
   return EnumToString(mode);
}

//+------------------------------------------------------------------+
//| Dashboard create / update                                        |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   DeleteDashboard();
   int x = GetPanelX();
   int y = GetPanelY();

   if(ObjectCreate(0, "DB_Rect", OBJ_RECTANGLE_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, "DB_Rect", OBJPROP_CORNER,       CORNER_LEFT_UPPER);
      ObjectSetInteger(0, "DB_Rect", OBJPROP_XDISTANCE,    x);
      ObjectSetInteger(0, "DB_Rect", OBJPROP_YDISTANCE,    y);
      ObjectSetInteger(0, "DB_Rect", OBJPROP_XSIZE,        DB_WIDTH);
      ObjectSetInteger(0, "DB_Rect", OBJPROP_YSIZE,        dashboardCollapsed ? DB_HEIGHT_COLLAPSED : DB_HEIGHT);
      ObjectSetInteger(0, "DB_Rect", OBJPROP_BGCOLOR,      clrBlack);
      ObjectSetInteger(0, "DB_Rect", OBJPROP_BORDER_COLOR, clrDarkGoldenrod);
      ObjectSetInteger(0, "DB_Rect", OBJPROP_BACK,         false);  // foreground: covers candles
   }
   if(ObjectCreate(0, "DB_Title", OBJ_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, "DB_Title", OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, "DB_Title", OBJPROP_XDISTANCE, x + 8);
      ObjectSetInteger(0, "DB_Title", OBJPROP_YDISTANCE, y + 4);
      ObjectSetInteger(0, "DB_Title", OBJPROP_COLOR,     clrGold);
      ObjectSetInteger(0, "DB_Title", OBJPROP_FONTSIZE,  10);
      ObjectSetString(0,  "DB_Title", OBJPROP_FONT,      "Arial Bold");
      ObjectSetString(0,  "DB_Title", OBJPROP_TEXT,      "Liquidity Sweep Reversal Pro");
   }
   if(ObjectCreate(0, "DB_Version", OBJ_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, "DB_Version", OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, "DB_Version", OBJPROP_XDISTANCE, x + 8);
      ObjectSetInteger(0, "DB_Version", OBJPROP_YDISTANCE, y + 28);
      ObjectSetInteger(0, "DB_Version", OBJPROP_COLOR,     clrWhite);
      ObjectSetInteger(0, "DB_Version", OBJPROP_FONTSIZE,  7);
      ObjectSetString(0,  "DB_Version", OBJPROP_FONT,      "Arial");
      ObjectSetString(0,  "DB_Version", OBJPROP_TEXT,      "V7.8 BOS: " + BOSModeText(InpBOSMode));
   }
   if(ObjectCreate(0, "DB_Toggle", OBJ_BUTTON, 0, 0, 0))
   {
      ObjectSetInteger(0, "DB_Toggle", OBJPROP_CORNER,       CORNER_LEFT_UPPER);
      ObjectSetInteger(0, "DB_Toggle", OBJPROP_XDISTANCE,    x + DB_WIDTH - 26);
      ObjectSetInteger(0, "DB_Toggle", OBJPROP_YDISTANCE,    y + 4);
      ObjectSetInteger(0, "DB_Toggle", OBJPROP_XSIZE,        18);
      ObjectSetInteger(0, "DB_Toggle", OBJPROP_YSIZE,        16);
      ObjectSetString(0,  "DB_Toggle", OBJPROP_TEXT,         dashboardCollapsed ? "+" : "-");
      ObjectSetInteger(0, "DB_Toggle", OBJPROP_COLOR,        clrGold);
      ObjectSetInteger(0, "DB_Toggle", OBJPROP_BGCOLOR,      clrBlack);
      ObjectSetInteger(0, "DB_Toggle", OBJPROP_BORDER_COLOR, clrDarkGoldenrod);
      ObjectSetInteger(0, "DB_Toggle", OBJPROP_FONTSIZE,     8);
      ObjectSetInteger(0, "DB_Toggle", OBJPROP_STATE,        dashboardCollapsed);
      ObjectSetInteger(0, "DB_Toggle", OBJPROP_SELECTABLE,   false);
      ObjectSetInteger(0, "DB_Toggle", OBJPROP_BACK,         false);
   }
}

void UpdateDashboard()
{
   if(!InpShowDashboard) return;
   int x = GetPanelX();
   int y = GetPanelY();

   // Keep rect anchored correctly after chart resize
   ObjectSetInteger(0, "DB_Rect", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, "DB_Rect", OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, "DB_Title",   OBJPROP_XDISTANCE, x + 8);
   ObjectSetInteger(0, "DB_Title",   OBJPROP_YDISTANCE, y + 4);
   ObjectSetInteger(0, "DB_Toggle",  OBJPROP_XDISTANCE, x + DB_WIDTH - 26);
   ObjectSetInteger(0, "DB_Toggle",  OBJPROP_YDISTANCE, y + 4);

   if(dashboardCollapsed)
   {
      // Collapsed: show only the title bar - nothing else, including the version line.
      ObjectSetInteger(0, "DB_Rect", OBJPROP_YSIZE, DB_HEIGHT_COLLAPSED);
      ObjectDelete(0, "DB_Version");
      string bodyLabels[] = {"DB_Mode","DB_Status","DB_Trades","DB_Open","DB_DailyR","DB_WinRate",
         "DB_LossStreak","DB_Sep","DB_StatsTitle","DB_LpFound","DB_SwFound","DB_BosConf",
         "DB_Entries","DB_Rejects","DB_Sep2","DB_SignalsTitle","DB_NoSignals"};
      for(int i = 0; i < ArraySize(bodyLabels); i++)
         ObjectDelete(0, bodyLabels[i]);
      for(int s = 1; s <= 5; s++)
         ObjectDelete(0, "DB_Sig" + IntegerToString(s));
      return;
   }

   if(ObjectFind(0, "DB_Version") < 0)
   {
      ObjectCreate(0, "DB_Version", OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "DB_Version", OBJPROP_CORNER,   CORNER_LEFT_UPPER);
      ObjectSetInteger(0, "DB_Version", OBJPROP_COLOR,    clrWhite);
      ObjectSetInteger(0, "DB_Version", OBJPROP_FONTSIZE, 7);
      ObjectSetString(0,  "DB_Version", OBJPROP_FONT,     "Arial");
   }
   ObjectSetInteger(0, "DB_Version", OBJPROP_XDISTANCE, x + 8);
   ObjectSetInteger(0, "DB_Version", OBJPROP_YDISTANCE, y + 28);
   ObjectSetString(0,  "DB_Version", OBJPROP_TEXT,      "V7.8 BOS: " + BOSModeText(InpBOSMode));

   int line = 40;
   string modeText = "";
   switch(InpAggressiveMode)
   {
      case AGGRESSIVE_OFF:    modeText = "Conservative"; break;
      case AGGRESSIVE_MEDIUM: modeText = "Medium";       break;
      case AGGRESSIVE_HIGH:   modeText = "Aggressive";   break;
      case AGGRESSIVE_ULTRA:  modeText = "ULTRA";        break;
   }
   CreateOrUpdateLabel("DB_Mode", x + 8, y + line, 0, clrCyan, "Mode: " + modeText);
   line += 15;
   string statusText = "RUNNING";
   color statusColor = clrLimeGreen;
   if(InpMaxDailyTrades > 0 && globalDailyTrades >= InpMaxDailyTrades) { statusText = "PAUSED: Daily trade limit";  statusColor = clrOrange; }
   else if(globalDailyR <= InpMaxDailyLossR)       { statusText = "PAUSED: Daily loss limit";   statusColor = clrRed;    }
   else if(!CheckSession())                        { statusText = "PAUSED: Outside session";    statusColor = clrGray;   }
   else if(activePositions >= InpMaxOpenPositions) { statusText = "PAUSED: Max open positions"; statusColor = clrOrange; }
   else if(globalDailyR >= InpMaxDailyNetR)        { statusText = "RUNNING (target hit, no cap)"; statusColor = clrLimeGreen; }
   else                                             { statusText = "RUNNING (" + activeSessionName + ")"; }
   CreateOrUpdateLabel("DB_Status", x + 8, y + line, 0, statusColor, "Status: " + statusText);
   line += 15;
   CreateOrUpdateLabel("DB_Trades", x + 8, y + line, 0, clrWhite,
      "Trades: " + IntegerToString(globalDailyTrades) + "/" + (InpMaxDailyTrades > 0 ? IntegerToString(InpMaxDailyTrades) : "unlimited"));
   line += 15;
   CreateOrUpdateLabel("DB_Open", x + 8, y + line, 0, clrWhite,
      "Open: " + IntegerToString(activePositions) + "/" + IntegerToString(InpMaxOpenPositions));
   line += 15 + 8;  // extra gap before the performance section
   double dailyProfit = globalDailyR * (AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0);
   color profitColor = (globalDailyR >= 0) ? clrLimeGreen : clrRed;
   CreateOrUpdateLabel("DB_DailyR", x + 8, y + line, 0, profitColor,
      "Daily R: " + DoubleToString(globalDailyR, 2) + " | $" + DoubleToString(dailyProfit, 0));
   line += 15;
   double totalWinRate = 0, totalAvgRR = 0;
   int activeStatsSymbols = 0;
   for(int i = 0; i < ArraySize(symbols); i++)
      if(symbols[i].perf.totalTrades > 0)
      {
         totalWinRate += symbols[i].perf.winRate;
         totalAvgRR   += symbols[i].perf.avgRR;
         activeStatsSymbols++;
      }
   if(activeStatsSymbols > 0) { totalWinRate /= activeStatsSymbols; totalAvgRR /= activeStatsSymbols; }
   CreateOrUpdateLabel("DB_WinRate", x + 8, y + line, 0, clrCyan,
      "WR: " + DoubleToString(totalWinRate * 100, 1) + "% | RR: " + DoubleToString(totalAvgRR, 2));
   line += 15;
   CreateOrUpdateLabel("DB_LossStreak", x + 8, y + line, 0, clrYellow,
      "Loss streak: " + IntegerToString(consecutiveLosses) +
      "  7D avg: " + DoubleToString(tradeStats.avgTradesPerDay, 1) + "/d");
   line += 15;
   CreateOrUpdateLabel("DB_Sep", x + 8, y + line, 0, clrDimGray,
      "- - - - - - - - - - - - - - - -");
   line += 18;  // wider gap separating the pipeline section
   CreateOrUpdateLabel("DB_StatsTitle", x + 8, y + line, 0, clrGold, "-- TODAY'S PIPELINE --");
   line += 13;
   CreateOrUpdateLabel("DB_LpFound",  x + 8, y + line, 0, clrSilver,
      "LP Found:   " + IntegerToString(dailyLpFound));
   line += 13;
   CreateOrUpdateLabel("DB_SwFound",  x + 8, y + line, 0, clrSilver,
      "Sweeps:     " + IntegerToString(dailySweepFound));
   line += 13;
   CreateOrUpdateLabel("DB_BosConf",  x + 8, y + line, 0, clrSilver,
      "BOS Conf:   " + IntegerToString(dailyBosConf));
   line += 13;
   CreateOrUpdateLabel("DB_Entries",  x + 8, y + line, 0, clrLimeGreen,
      "Entries:    " + IntegerToString(globalDailyTrades));
   line += 13;
   CreateOrUpdateLabel("DB_Rejects",  x + 8, y + line, 0, (dailyRejections > 0 ? clrOrange : clrSilver),
      "Rejected:   " + IntegerToString(dailyRejections));
   line += 13;
   CreateOrUpdateLabel("DB_Sep2", x + 8, y + line, 0, clrDimGray,
      "- - - - - - - - - - - - - - - -");
   line += 18;  // wider gap separating the active-signals section
   CreateOrUpdateLabel("DB_SignalsTitle", x + 8, y + line, 0, clrGold, "-- ACTIVE SIGNALS --");
   line += 14;
   int signalCount = 0;
   for(int i = 0; i < ArraySize(symbols) && signalCount < 5; i++)
   {
      string status = "";
      color  statusColor = clrWhite;
      if(symbols[i].positionTicket != 0)  { status = "ACTIVE"; statusColor = clrLimeGreen; signalCount++; }
      else if(symbols[i].setupValid)      { status = "SETUP";  statusColor = clrYellow;    signalCount++; }
      else if(symbols[i].perf.isDisabled) { status = "OFF";    statusColor = clrRed;       signalCount++; }
      if(status != "")
      {
         CreateOrUpdateLabel("DB_Sig" + IntegerToString(signalCount),
            x + 12, y + line, 0, statusColor, symbols[i].name + "  " + status);
         line += 13;
      }
   }
   // Remove leftover slot labels from a previous tick that had more signals,
   // and the "no signals" label, so stale text never overlaps fresh text
   for(int s = signalCount + 1; s <= 5; s++)
      ObjectDelete(0, "DB_Sig" + IntegerToString(s));
   if(signalCount == 0)
   {
      CreateOrUpdateLabel("DB_NoSignals", x + 12, y + line, 0, clrDimGray, "No active signals");
      line += 13;
   }
   else
      ObjectDelete(0, "DB_NoSignals");

   // Shrink-wrap the panel to the content actually drawn this tick instead
   // of always reserving worst-case space for 5 signals.
   ObjectSetInteger(0, "DB_Rect", OBJPROP_YSIZE, MathMin(DB_HEIGHT, line + 12));
}

//+------------------------------------------------------------------+
//| Trade transaction (R calculation only)                           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(dealTicket == 0) return;
      if(!HistoryDealSelect(dealTicket)) return;
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == InpMagicNumber)
      {
         ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         if(dealEntry == DEAL_ENTRY_OUT)
         {
            double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
            for(int i = 0; i < ArraySize(symbols); i++)
            {
               if(symbols[i].name == symbol)
               {
                  // Use the risk stored for the specific ticket that closed
                  double closedRisk = (trans.position == symbols[i].positionTicket2 && symbols[i].riskAmount2 > 0)
                                      ? symbols[i].riskAmount2
                                      : symbols[i].riskAmount;
                  double r = (closedRisk > 0) ? profit / closedRisk : 0;
                  symbols[i].dailyR += r;
                  symbols[i].perf.totalTrades++;
                  symbols[i].perf.totalR += r;
                  if(profit > 0) symbols[i].perf.winningTrades++;
                  if(symbols[i].perf.totalTrades > 0)
                  {
                     symbols[i].perf.winRate = (double)symbols[i].perf.winningTrades / symbols[i].perf.totalTrades;
                     symbols[i].perf.avgRR = symbols[i].perf.totalR / symbols[i].perf.totalTrades;
                  }
                  globalDailyR += r;
                  if(r < 0) consecutiveLosses++;
                  else consecutiveLosses = 0;
                  if(trans.position == symbols[i].positionTicket)       symbols[i].positionTicket  = 0;
                  else if(trans.position == symbols[i].positionTicket2) { symbols[i].positionTicket2 = 0; symbols[i].riskAmount2 = 0; }
                  if(symbols[i].positionTicket == 0 && symbols[i].positionTicket2 == 0)
                     symbols[i].positionDirection = DIR_NONE;
                  UpdateTradeStats();
                  if(InpDebugMode)
                     Print(symbol, " Closed: ", DoubleToString(profit, 2), " (", DoubleToString(r, 2), "R)");
                  break;
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
