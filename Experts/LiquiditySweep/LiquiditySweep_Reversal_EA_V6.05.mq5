//+------------------------------------------------------------------+
//|                                LiquiditySweep_Reversal_EA.mq5    |
//|                     HIGH FREQUENCY - 15-30 trades/day           |
//|                     Version 6.4 - FULLY COMPILABLE              |
//+------------------------------------------------------------------+
#property copyright "Liquidity Sweep EA"
#property version   "6.40"
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

input group "=== Entry & Risk Settings ==="
input double   InpRiskPercent    = 0.3;
input double   InpSlBufferPips   = 2.0;
input double   InpMaxSlippage    = 5;
input bool     InpUseFVG         = false;
input bool     InpDirectBOSEntry = true;
input double   InpTP_R           = 1.5;
input double   InpMinRR          = 1.2;
input double   InpPartialTP_R    = 1.0;
input double   InpMaxSlPips      = 15.0;  // Hard SL cap in pips (0 = no cap)

input group "=== Trade Management ==="
input int      InpMaxDailyTrades  = 30;
input double   InpMaxDailyNetR    = 8.0;
input double   InpMaxDailyLossR   = -3.0;
input int      InpMaxOpenPositions = 12;
input int      InpMaxCorrelatedPositions = 10;
input bool     InpUseCorrelationFilter = false;
input int      InpCancelAfterSec  = 45;
input bool     InpUseTrailingStop = true;
input double   InpTrailingStart   = 0.5;
input double   InpTrailingStep    = 0.2;
input bool     InpUseBreakEven    = true;
input double   InpBreakEvenR      = 0.5;

input group "=== Advanced Features ==="
input ENUM_AGGRESSIVE_LEVEL InpAggressiveMode = AGGRESSIVE_ULTRA;
input bool     InpAllowReEntry    = true;
input int      InpMaxEntriesPerSweep = 3;
input ENUM_TREND_FILTER InpTrendFilter = FILTER_NONE;
input double   InpMinATR          = 1.5;
input double   InpMaxSpreadMultiplier = 2.0;

input group "=== ULTRA MODE OPTIONS ==="
input ENUM_BOS_MODE InpBOSMode   = BOS_BYPASS;

input group "=== Performance Tracking ==="
input bool     InpAutoDisablePoorSymbols = true;
input double   InpMinWinRate       = 35.0;
input int      InpMinTradesForDecision = 20;

input group "=== Session Filter ==="
input bool     InpUseSessionFilter = true;
input int      InpSessionStartHour = 7;   // GMT hour
input int      InpSessionStartMin  = 0;
input int      InpSessionEndHour   = 23;  // GMT hour
input int      InpSessionEndMin    = 0;

input group "=== Spread Limits (pips) ==="
input double   InpSpreadLimitEURUSD = 1.5;
input double   InpSpreadLimitGBPUSD = 2.0;
input double   InpSpreadLimitUSDJPY = 1.5;
input double   InpSpreadLimitXAUUSD = 3.5;
input double   InpSpreadLimitDefault = 2.0;

input group "=== Dashboard Settings ==="
input bool     InpShowDashboard    = true;
input int      InpDashboardCorner  = 1;
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

//+------------------------------------------------------------------+
//| Logging helper                                                   |
//+------------------------------------------------------------------+
void LogDecision(string symbol, string step, bool passed, string detail = "")
{
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

   InitTradeStats();

   if(InpShowDashboard)
      CreateDashboard();

   Print("========================================");
   Print("LIQUIDITY SWEEP EA v6.4 - HIGH FREQUENCY");
   Print("Monitoring: ", IntegerToString(symbolCnt), " symbols");
   Print("Aggressive Mode: ", EnumToString(InpAggressiveMode));
   Print("Correlation Filter: ", InpUseCorrelationFilter ? "ON (max " + IntegerToString(InpMaxCorrelatedPositions) + ")" : "OFF");
   Print("Max Open Positions: ", IntegerToString(InpMaxOpenPositions));
   Print("BOS Mode: ", EnumToString(InpBOSMode));
   Print("Session Filter (GMT): ", InpUseSessionFilter ? IntegerToString(InpSessionStartHour) + ":" + IntegerToString(InpSessionStartMin) + " - " + IntegerToString(InpSessionEndHour) + ":" + IntegerToString(InpSessionEndMin) : "OFF");
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
   Print("EA deinitialized");
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
//| Session check (compares against GMT hours)                       |
//+------------------------------------------------------------------+
bool CheckSession()
{
   if(!InpUseSessionFilter) return true;
   MqlDateTime dtGMT;
   TimeToStruct(TimeGMT(), dtGMT);
   int currentMinutes = dtGMT.hour * 60 + dtGMT.min;
   int startMinutes = InpSessionStartHour * 60 + InpSessionStartMin;
   int endMinutes = InpSessionEndHour * 60 + InpSessionEndMin;
   bool active = (currentMinutes >= startMinutes && currentMinutes < endMinutes);

   // Log only when status changes — not every tick — to keep journal clean
   if(InpDebugMode)
   {
      static bool lastSessionActive = false;
      if(active != lastSessionActive)
      {
         MqlDateTime dtLocal;
         TimeToStruct(TimeCurrent(), dtLocal);
         Print("Session ", active ? "OPEN" : "CLOSED",
               " | Broker ", dtLocal.hour, ":", dtLocal.min,
               " | GMT ", dtGMT.hour, ":", dtGMT.min,
               " | Window ", InpSessionStartHour, ":", InpSessionStartMin,
               " - ", InpSessionEndHour, ":", InpSessionEndMin);
         lastSessionActive = active;
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
   return 0;
}

double GetSweepMinPips()
{
   double base = InpSweepMinPips;
   switch(InpAggressiveMode)
   {
      case AGGRESSIVE_ULTRA: return base * 0.4;
      case AGGRESSIVE_HIGH:  return base * 0.6;
      case AGGRESSIVE_MEDIUM: return base * 0.8;
      default: return base;
   }
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
   if(globalDailyTrades >= InpMaxDailyTrades) return;
   if(globalDailyR >= InpMaxDailyNetR) return;
   if(globalDailyR <= InpMaxDailyLossR) return;
   // Session is global — check once here, not per-symbol
   if(!CheckSession()) return;
   activePositions = CountOpenPositions();
   if(activePositions >= InpMaxOpenPositions) return;
   if(InpShowDashboard) UpdateDashboard();
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
   ManagePositions(idx);
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
   double sweepMin = GetSweepMinPips() * symbols[idx].pipSize;
   datetime currentBarTime = iTime(sym, tf, 0);
   double lpHigh = FindLiquidityPoolLevel(idx, true, tf);
   double lpLow = FindLiquidityPoolLevel(idx, false, tf);

   if(lpHigh > 0 && close[0] < lpHigh && close[0] < open[0] && high[0] > lpHigh + sweepMin)
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
   else if(lpLow > 0 && close[0] > lpLow && close[0] > open[0] && low[0] < lpLow - sweepMin)
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
      LogDecision(sym, "LiquidityPool", false, "No pool");
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
   datetime startTime = symbols[idx].sweepBarTime;
   if(startTime == 0) startTime = TimeCurrent() - 600;
   int copied = CopyRates(symbols[idx].name, InpConfTF, startTime, TimeCurrent(), m1);
   if(copied < 10) return false;
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
   MqlRates m1[];
   datetime startTime = symbols[idx].sweepBarTime;
   if(startTime == 0) startTime = TimeCurrent() - 600;
   int copied = CopyRates(symbols[idx].name, InpConfTF, startTime, TimeCurrent(), m1);
   if(copied < 10) return false;
   ArraySetAsSeries(m1, true);

   // Use current market price as entry so TP/SL are accurate relative to execution price
   MqlTick tick;
   if(!SymbolInfoTick(symbols[idx].name, tick)) return false;
   double newEntry = (symbols[idx].setupDirection == DIR_SHORT) ? tick.bid : tick.ask;

   if(!InpDirectBOSEntry && InpUseFVG)
   {
      for(int i = 0; i < MathMin(copied,15)-2; i++)
      {
         if(symbols[idx].setupDirection == DIR_SHORT && m1[i].low > m1[i+2].high)
         { newEntry = (m1[i].low + m1[i+2].high)/2.0; break; }
         else if(symbols[idx].setupDirection == DIR_LONG && m1[i].high < m1[i+2].low)
         { newEntry = (m1[i].high + m1[i+2].low)/2.0; break; }
      }
   }
   if(newEntry == 0) newEntry = (symbols[idx].setupDirection == DIR_SHORT) ? tick.bid : tick.ask;
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
   double riskPercent = InpRiskPercent;
   if(consecutiveLosses >= 5) riskPercent = InpRiskPercent * 0.25;
   else if(consecutiveLosses >= 3) riskPercent = InpRiskPercent * 0.5;
   double riskMoney = (riskPercent / 100.0) * AccountInfoDouble(ACCOUNT_BALANCE);
   symbols[idx].totalLot = riskMoney / lossPerLot;
   symbols[idx].riskAmount = riskMoney;
   symbols[idx].totalLot = NormalizeLot(idx, symbols[idx].totalLot);
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
      ulong dealTicket = symbolTrade.ResultDeal();
      symbols[idx].dealTicket = dealTicket;
      if(dealTicket > 0 && HistoryDealSelect(dealTicket))
      {
         ulong positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            // Must select before reading properties — PositionGetTicket alone
            // does not guarantee the context is set on all broker/build combos
            if(ticket > 0 && PositionSelectByTicket(ticket) &&
               PositionGetInteger(POSITION_IDENTIFIER) == (long)positionId)
            {
               if(symbols[idx].positionTicket == 0) symbols[idx].positionTicket = ticket;
               else if(symbols[idx].positionTicket2 == 0) symbols[idx].positionTicket2 = ticket;
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
      Print(symbols[idx].name, " Trade failed: ", symbolTrade.ResultRetcodeDescription());
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

// Translate InpDashboardCorner + offsets into absolute top-left pixel
// coords for the panel, then always use CORNER_LEFT_UPPER for every
// object so text never renders off-screen and y always goes downward.
int GetPanelX()
{
   if(InpDashboardCorner == 1 || InpDashboardCorner == 2)
      return (int)(ChartGetInteger(0, CHART_WIDTH_IN_PIXELS) - InpDashboardXOffset - 264);
   return InpDashboardXOffset;
}

int GetPanelY()
{
   if(InpDashboardCorner == 2 || InpDashboardCorner == 3)
      return (int)(ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS) - InpDashboardYOffset - 230);
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

//+------------------------------------------------------------------+
//| Dashboard create / update                                        |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   DeleteDashboard();
   int x = GetPanelX();
   int y = GetPanelY();
   int width  = 264;
   int height = 230;

   if(ObjectCreate(0, "DB_Rect", OBJ_RECTANGLE_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, "DB_Rect", OBJPROP_CORNER,       CORNER_LEFT_UPPER);
      ObjectSetInteger(0, "DB_Rect", OBJPROP_XDISTANCE,    x);
      ObjectSetInteger(0, "DB_Rect", OBJPROP_YDISTANCE,    y);
      ObjectSetInteger(0, "DB_Rect", OBJPROP_XSIZE,        width);
      ObjectSetInteger(0, "DB_Rect", OBJPROP_YSIZE,        height);
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
      ObjectSetString(0,  "DB_Title", OBJPROP_TEXT,      "LIQUIDITY SWEEP EA PRO");
   }
   if(ObjectCreate(0, "DB_Version", OBJ_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, "DB_Version", OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, "DB_Version", OBJPROP_XDISTANCE, x + 8);
      ObjectSetInteger(0, "DB_Version", OBJPROP_YDISTANCE, y + 18);
      ObjectSetInteger(0, "DB_Version", OBJPROP_COLOR,     clrGray);
      ObjectSetInteger(0, "DB_Version", OBJPROP_FONTSIZE,  8);
      ObjectSetString(0,  "DB_Version", OBJPROP_FONT,      "Arial");
      ObjectSetString(0,  "DB_Version", OBJPROP_TEXT,      "v6.5 HF | BOS: " + EnumToString(InpBOSMode));
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
   ObjectSetInteger(0, "DB_Version", OBJPROP_XDISTANCE, x + 8);
   ObjectSetInteger(0, "DB_Version", OBJPROP_YDISTANCE, y + 18);

   int line = 30;
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
   CreateOrUpdateLabel("DB_Trades", x + 8, y + line, 0, clrWhite,
      "Trades: " + IntegerToString(globalDailyTrades) + "/" + IntegerToString(InpMaxDailyTrades));
   line += 15;
   CreateOrUpdateLabel("DB_Open", x + 8, y + line, 0, clrWhite,
      "Open: " + IntegerToString(activePositions) + "/" + IntegerToString(InpMaxOpenPositions));
   line += 15;
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
   line += 12;
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
   if(signalCount == 0)
      CreateOrUpdateLabel("DB_NoSignals", x + 12, y + line, 0, clrDimGray, "No active signals");
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
                  double r = (symbols[i].riskAmount > 0) ? profit / symbols[i].riskAmount : 0;
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
                  if(trans.position == symbols[i].positionTicket) symbols[i].positionTicket = 0;
                  else if(trans.position == symbols[i].positionTicket2) symbols[i].positionTicket2 = 0;
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
