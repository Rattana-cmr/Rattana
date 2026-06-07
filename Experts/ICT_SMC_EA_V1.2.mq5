//+------------------------------------------------------------------+
//|                                          ICT SMC EA V1.2          |
//|          ICT SMART MONEY CONCEPTS — FULL MODEL V1.2              |
//|    MSS · BOS · LIQUIDITY · SCORE · PARTIAL TP · CSV · SCREEN     |
//|    TRADING STYLE · ULTRA ACTIVE MODE · FILTER REJECTION STATS    |
//|                Created By — RATTANA CHHORM                        |
//+------------------------------------------------------------------+
//
// V1.2 UPGRADE from V1.1
// ═══════════════════════════════════════════════════════════════════
// NEW IN V1.2:
//  [18] TradingStyle preset (Conservative/Balanced/Aggressive/UltraActive)
//       UltraActive: all filters minimal → target 15-25 trades/day
//  [19] Filter Rejection Statistics — per-filter blocked count
//       Displayed on panel; shows exactly which filter blocks trades
//  [20] UseTradeScore toggle (can fully disable score requirement)
//  [21] Effective overrides — style overrides individual inputs
//  [22] UseH1RangeFilter toggle — can disable H1 range minimum
//
// STYLE BEHAVIOUR:
//  Conservative : score≥80 · OTE 65-75% · MSS+BOS+Trend ON  · CD 30m
//  Balanced     : score≥70 · OTE 65-75% · uses input toggles · CD 20m
//  Aggressive   : score≥50 · OTE 55-90% · MSS off·Trend off  · CD 10m
//  UltraActive  : score≥35 · OTE 40-95% · all filters off    · CD 5m
//
// PRESERVED FROM V1.1: all trading logic, SL/TP, partial TP,
//   session filters, daily loss limits, CSV log, screenshots,
//   broker protection, news filter, symbol presets
// ═══════════════════════════════════════════════════════════════════
// FIXED (V1.1):
//  FIX J: OTE zone 65-75%          FIX K: 1M trigger threshold 65%
//  FIX M: BUY 3/3 D1 candles       FIX N: London delay 08:30 GMT
//  FIX O: MaxSLPips 30              FIX P: Friday cut-off 14:00 GMT
//  FIX Q: MinSLPips 10              FIX R: R:R float tolerance 0.001
//  FIX S: Reset CISD on failure     FIX T: MaxDailyLossTrades 3
//  FIX U: HTFLevelRequired=false
// ═══════════════════════════════════════════════════════════════════

#property copyright "RATTANA CHHORM"
#property version   "1.2"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//===================================================================//
//  ENUMERATIONS                                                      //
//===================================================================//
enum ENUM_RISK_MODE
{
   RISK_FIXED_PCT  = 0,   // Fixed % of balance
   RISK_FIXED_LOT  = 1,   // Fixed lot size
   RISK_DYNAMIC_EQ = 2    // Dynamic equity % (adjusts as equity grows)
};

enum ENUM_TP_MODE
{
   TP_FIXED_RR = 0,   // Fixed Reward:Risk ratio
   TP_ATR      = 1,   // ATR multiplier
   TP_HYBRID   = 2    // Min(FixedRR, ATR) — most conservative
};

enum ENUM_OPT_MODE
{
   OPT_CONSERVATIVE = 0,  // Conservative: higher score bar, lower risk
   OPT_BALANCED     = 1,  // Balanced: default settings
   OPT_AGGRESSIVE   = 2   // Aggressive: lower score bar, higher risk
};

enum ENUM_SYMBOL_PRESET
{
   PRESET_AUTO   = 0,   // Auto-detect from symbol name
   PRESET_XAUUSD = 1,   // Gold (XAUUSD)
   PRESET_BTCUSD = 2,   // Bitcoin (BTCUSD)
   PRESET_EURUSD = 3,   // Euro (EURUSD)
   PRESET_GBPUSD = 4    // Pound (GBPUSD)
};

enum ENUM_TRADING_STYLE
{
   STYLE_CONSERVATIVE = 0, // Conservative: strict ICT — 1-5 trades/day
   STYLE_BALANCED     = 1, // Balanced: default settings — 3-8 trades/day
   STYLE_AGGRESSIVE   = 2, // Aggressive: relaxed filters — 8-15 trades/day
   STYLE_ULTRA_ACTIVE = 3  // Ultra Active: maximum frequency — 15-25 trades/day
};

//===================================================================//
//  CONSTANTS                                                         //
//===================================================================//
const int    MAGIC_NUMBER = 888777;
const string EA_NAME      = "ICT SMC EA V1.2";

//===================================================================//
//  INPUTS                                                            //
//===================================================================//

//--- TRADING STYLE -------------------------------------------------
input group "========== TRADING STYLE =========="
input ENUM_TRADING_STYLE TradingStyle = STYLE_BALANCED; // Trading style preset
// Conservative: all ICT filters strict. Balanced: input toggles respected.
// Aggressive: MSS/Trend off, wider OTE. UltraActive: max frequency.

//--- RISK MANAGEMENT -----------------------------------------------
input group "========== RISK MANAGEMENT =========="
input ENUM_RISK_MODE RiskMode           = RISK_FIXED_PCT;
input double   RiskPercent              = 0.5;
input double   FixedLot                 = 0.0;
input double   MaxDailyLossPercent      = 10.0;
input int      MaxTradesPerDay          = 25;    // Raised for UltraActive
input double   RewardRiskRatio          = 2.0;
input double   MaxLotLimit              = 0.10;
input double   MinRewardRiskRatio       = 2.0;

//--- TAKE PROFIT MODE ----------------------------------------------
input group "========== TAKE PROFIT MODE =========="
input ENUM_TP_MODE TPMode               = TP_FIXED_RR;
input double   ATRMultiplierTP          = 3.0;

//--- PARTIAL TAKE PROFIT -------------------------------------------
input group "========== PARTIAL TAKE PROFIT =========="
input bool     UsePartialTP             = true;
input double   PartialClosePercent      = 50.0;
input double   PartialCloseRR          = 1.0;

//--- TRADE FILTERS -------------------------------------------------
input group "========== TRADE FILTERS =========="
input bool     UseTimeFilter            = true;
input int      MaxSpreadPoints          = 80;    // Raised — XAUUSD can be wide
input int      MinStopDistance          = 20;
input int      MaxConsecutiveLosses     = 10;
input int      MaxDailyLossTrades       = 3;
input bool     ResetLossStreakDaily     = true;

//--- ICT STRUCTURE FILTERS ----------------------------------------
input group "========== ICT STRUCTURE FILTERS =========="
input bool     UseMSSFilter             = true;   // [2] Require MSS (H1) — overridden by style
input bool     UseBOSFilter             = true;   // [3] Require BOS (M15) — overridden by style
input bool     RequireLiquiditySweep    = false;  // [4] Require liquidity sweep
input bool     UseSMTFilter             = false;  // SMT divergence
input string   SMTSymbol                = "XAGUSD";

//--- NEWS FILTER ---------------------------------------------------
input group "========== NEWS FILTER =========="
input bool     UseNewsFilter            = false;
input int      NewsBlockBeforeMin       = 30;
input int      NewsBlockAfterMin        = 30;

//--- TRADE QUALITY SCORE ------------------------------------------
input group "========== TRADE QUALITY SCORE =========="
input bool     UseTradeScore            = true;   // Enable minimum score gate (NEW V1.2)
input int      MinimumTradeScore        = 70;     // Min score/100 (overridden by style)

//--- SESSIONS ------------------------------------------------------
input group "========== SESSIONS (GMT TIME) =========="
input bool     AutoDetectGMT            = true;
input int      BrokerGMTOffset          = 0;
input bool     SessionSydney            = false;
input bool     SessionTokyo             = false;
input bool     SessionLondon            = true;
input bool     SessionNewYork           = true;
input bool     OverlapLondonNY          = true;
input bool     OverlapTokyoLondon       = false;

//--- STOP LOSS & TRAILING -----------------------------------------
input group "========== STOP LOSS =========="
input int      SLBufferPips             = 15;
input bool     UseTrailingStop          = false;
input int      TrailingStartPips        = 30;
input int      TrailingStepPips         = 10;

//--- POSITION MANAGEMENT ------------------------------------------
input group "========== POSITION MANAGEMENT =========="
input bool     CloseOnFriday            = true;
input int      FridayCloseHour          = 14;
input bool     UseBreakeven             = false;
input int      BreakevenTriggerPips     = 40;

//--- SWING DETECTION ----------------------------------------------
input group "========== SWING DETECTION =========="
input int      SwingLookbackBarsH1      = 50;
input int      SwingConfirmBarsH1       = 3;
input int      SwingLookbackBarsM15     = 30;
input int      SwingConfirmBarsM15      = 5;
input int      MaxSwingDistancePips     = 500;
input int      MaxSLPips                = 30;
input int      MinSLPips                = 10;
input bool     ShowSwingLines           = true;

//--- ICT TWINS MODEL ----------------------------------------------
input group "========== ICT TWINS MODEL =========="
input bool     UseTwinsModel            = true;
input int      HTFLevelMinutes          = 15;
input double   OTEMinPercent            = 0.65;
input double   OTEMaxPercent            = 0.75;
input double   OTESweetSpotPercent      = 0.705;
input int      MinFVGsRequired          = 0;
input int      HTFToleranceATRMulti     = 2;
input bool     HTFLevelRequired         = false;
input bool     ShowOTEZone              = true;
input int      MinH1RangePips           = 50;
input bool     UseH1RangeFilter         = true;   // NEW V1.2: toggle H1 range check

//--- MSS / BOS / LIQUIDITY ----------------------------------------
input group "========== MSS / BOS / LIQUIDITY =========="
input int      MSSLookbackBars          = 30;
input int      MSSConfirmBars           = 3;
input int      BOSLookbackBars          = 20;
input int      LiquidityLookbackBars    = 50;
input int      LiquidityWickPips        = 3;

//--- SYMBOL PRESET ------------------------------------------------
input group "========== SYMBOL PRESET =========="
input ENUM_SYMBOL_PRESET SymbolPreset   = PRESET_AUTO;

//--- OPTIMIZATION MODE (kept for backward compat) -----------------
input group "========== OPTIMIZATION MODE =========="
input ENUM_OPT_MODE OptMode             = OPT_BALANCED;

//--- LOGGING ------------------------------------------------------
input group "========== LOGGING =========="
input bool     EnableScreenshot         = true;
input bool     EnableCSVLog             = true;

//--- DEBUG --------------------------------------------------------
input group "========== DEBUG =========="
input int      PostTradeCooldownMin     = 20;    // Base cooldown (overridden by style)
input bool     UseDailyTrendFilter      = true;  // D1+H4 trend alignment
input bool     BestHoursOnly            = true;  // 08:30-15:00 GMT
input bool     ForceTrades              = false;
input bool     DebugMode                = false;
input bool     RelaxedMode              = false;

//===================================================================//
//  GLOBAL VARIABLES                                                  //
//===================================================================//

int      ATRHandle         = INVALID_HANDLE;
int      FastEMAHandle     = INVALID_HANDLE;
int      SlowEMAHandle     = INVALID_HANDLE;

datetime LastBarTime       = 0;
datetime LastTradeCloseTime = 0;
int      TodayTradeCount   = 0;
int      TodayLossTrades   = 0;
int      LastTradeDay      = 0;
double   TodayLoss         = 0;
int      consecutiveLosses = 0;
double   PipFactor         = 10.0;
datetime LastDisplayUpdate = 0;

// ICT state machine
bool     htfLevelReached    = false;
bool     mssConfirmed       = false;
bool     mssIsBullish       = false;
bool     bosConfirmed       = false;
bool     bosIsBullish       = false;
bool     liquiditySweepDone = false;
bool     sweepIsBullish     = false;
int      fvgCount1Min       = -1;
datetime LastFVGBarTime     = 0;

// 5M CISD fallback
bool     cisd5MinConfirmed  = false;
bool     cisd5MinIsBearish  = false;
datetime LastCISDTime5Min   = 0;

// 1M entry trigger
bool     cisd1MinConfirmed  = false;
bool     cisd1MinIsBearish  = false;
datetime LastCISDTime1Min   = 0;

// Swings
double   lastSwingHighH1    = 0;
double   lastSwingLowH1     = 0;
double   lastSwingHighM15   = 0;
double   lastSwingLowM15    = 0;

// Trade quality
int      lastTradeScore     = 0;
int      lastFailedStep     = 0;
string   lastFailedStepDesc = "";

// News
bool     newsBlocked        = false;
datetime lastNewsCheck      = 0;

// Statistics
int    statTotalTrades      = 0;
int    statWins             = 0;
int    statLosses           = 0;
double statTotalProfit      = 0.0;
double statTotalLoss        = 0.0;
double statSumRR            = 0.0;
int    consecutiveWins      = 0;

// Equity tracking
double sessionStartEquity   = 0;
double sessionMaxDrawdown   = 0;
double sessionPeakEquity    = 0;

// OTE draw guard
double lastOTEHigh = 0;
double lastOTELow  = 0;

// Effective parameters (set by preset + style)
double effOTEMin      = 0.65;
double effOTEMax      = 0.75;
int    effMaxSLPips   = 30;
int    effMinSLPips   = 10;
double effRiskPct     = 0.5;
int    effMinScore    = 70;

// V1.2: Effective style overrides
bool   effUseMSSFilter      = true;
bool   effUseBOSFilter      = true;
bool   effRequireLiqSweep   = false;
bool   effUseDailyTrend     = true;
bool   effBestHoursOnly     = true;
bool   effUseH1RangeFilter  = true;
int    effCooldown          = 20;
int    effMinH1Range        = 50;

// V1.2: Filter rejection statistics (reset daily)
int    rejTotal      = 0;
int    rejHTFLevel   = 0;
int    rejMSS        = 0;
int    rejBOS        = 0;
int    rejSweep      = 0;
int    rejFVG        = 0;
int    rejH1Swing    = 0;
int    rejH1Range    = 0;
int    rejOTE        = 0;
int    rej1MTrig     = 0;
int    rejScore      = 0;
int    rejTrend      = 0;
int    rejSMT        = 0;
int    rejNews       = 0;
datetime rejSeqLastBar = 0;  // guard for per-bar counting in CheckTwinsSequence

// Panel
string   PANEL_PREFIX    = "ICTSMC_";
int      PANEL_X         = 10;
int      PANEL_Y         = 30;
int      PANEL_W         = 310;
int      PANEL_LINE_H    = 14;
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

// Rolling swing lines / OTE
string   SwingLineNames[];
int      SwingLineIndex  = 0;
int      MaxSwingLines   = 10;
string   OTEObjectNames[4];

//===================================================================//
//  PRESET / OPTIMIZATION MODE                                        //
//===================================================================//
void ApplySymbolPreset()
{
   ENUM_SYMBOL_PRESET p = SymbolPreset;
   if(p == PRESET_AUTO)
   {
      string s = _Symbol;
      if(StringFind(s,"XAU")>=0||StringFind(s,"GOLD")>=0) p=PRESET_XAUUSD;
      else if(StringFind(s,"BTC")>=0)                      p=PRESET_BTCUSD;
      else if(StringFind(s,"GBP")>=0)                      p=PRESET_GBPUSD;
      else if(StringFind(s,"EUR")>=0)                      p=PRESET_EURUSD;
   }
   switch(p)
   {
      case PRESET_XAUUSD: effOTEMin=0.65; effOTEMax=0.75; effMaxSLPips=30; effMinSLPips=10; break;
      case PRESET_BTCUSD: effOTEMin=0.62; effOTEMax=0.78; effMaxSLPips=80; effMinSLPips=20; break;
      case PRESET_EURUSD: effOTEMin=0.62; effOTEMax=0.79; effMaxSLPips=25; effMinSLPips=5;  break;
      case PRESET_GBPUSD: effOTEMin=0.62; effOTEMax=0.79; effMaxSLPips=30; effMinSLPips=5;  break;
      default:            effOTEMin=OTEMinPercent; effOTEMax=OTEMaxPercent;
                          effMaxSLPips=MaxSLPips;  effMinSLPips=MinSLPips; break;
   }
}

void ApplyOptimizationMode()
{
   switch(OptMode)
   {
      case OPT_CONSERVATIVE: effMinScore=80; effRiskPct=0.25; break;
      case OPT_BALANCED:     effMinScore=70; effRiskPct=RiskPercent; break;
      case OPT_AGGRESSIVE:   effMinScore=55; effRiskPct=MathMin(RiskPercent*2.0,2.0); break;
   }
}

//===================================================================//
//  V1.2: TRADING STYLE — overrides individual inputs                //
//===================================================================//
void ApplyTradingStyle()
{
   // Start from symbol preset values then apply style
   double baseOTEMin = effOTEMin;
   double baseOTEMax = effOTEMax;

   switch(TradingStyle)
   {
      case STYLE_CONSERVATIVE:
         effMinScore         = 80;
         effRiskPct          = MathMin(RiskPercent, 0.5);
         effCooldown         = 30;
         effMinH1Range       = 50;
         effOTEMin           = baseOTEMin;
         effOTEMax           = baseOTEMax;
         effUseMSSFilter     = true;
         effUseBOSFilter     = true;
         effRequireLiqSweep  = RequireLiquiditySweep;
         effUseDailyTrend    = true;
         effBestHoursOnly    = true;
         effUseH1RangeFilter = true;
         break;

      case STYLE_BALANCED:
         effMinScore         = MinimumTradeScore;
         effRiskPct          = RiskPercent;
         effCooldown         = PostTradeCooldownMin;
         effMinH1Range       = MinH1RangePips;
         effOTEMin           = baseOTEMin;
         effOTEMax           = baseOTEMax;
         effUseMSSFilter     = UseMSSFilter;
         effUseBOSFilter     = UseBOSFilter;
         effRequireLiqSweep  = RequireLiquiditySweep;
         effUseDailyTrend    = UseDailyTrendFilter;
         effBestHoursOnly    = BestHoursOnly;
         effUseH1RangeFilter = UseH1RangeFilter;
         break;

      case STYLE_AGGRESSIVE:
         effMinScore         = 50;
         effRiskPct          = MathMin(RiskPercent * 1.5, 2.0);
         effCooldown         = 10;
         effMinH1Range       = 20;
         effOTEMin           = MathMax(0.55, baseOTEMin - 0.05);
         effOTEMax           = MathMin(0.90, baseOTEMax + 0.05);
         effUseMSSFilter     = false;   // 5M CISD fallback
         effUseBOSFilter     = UseBOSFilter;
         effRequireLiqSweep  = false;
         effUseDailyTrend    = false;
         effBestHoursOnly    = BestHoursOnly;
         effUseH1RangeFilter = (MinH1RangePips > 0);
         break;

      case STYLE_ULTRA_ACTIVE:
         effMinScore         = 35;
         effRiskPct          = RiskPercent;
         effCooldown         = 5;
         effMinH1Range       = 10;
         effOTEMin           = 0.40;
         effOTEMax           = 0.95;
         effUseMSSFilter     = false;   // 5M CISD direction only
         effUseBOSFilter     = false;
         effRequireLiqSweep  = false;
         effUseDailyTrend    = false;
         effBestHoursOnly    = false;   // all session hours
         effUseH1RangeFilter = false;
         break;
   }
}

//===================================================================//
//  DEBUG HELPER                                                      //
//===================================================================//
void DebugPrint(string msg) { if(DebugMode) Print("[DEBUG] ",msg); }

//===================================================================//
//  GMT / SESSION HELPERS                                             //
//===================================================================//
int GetEffectiveGMTOffset()
{
   if(AutoDetectGMT)
      return (int)MathRound((double)(TimeCurrent()-TimeGMT())/3600.0);
   return BrokerGMTOffset;
}

double GetGMTHour()
{
   int offset = GetEffectiveGMTOffset();
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   double h = dt.hour - offset + dt.min/60.0;
   while(h<0)   h+=24.0;
   while(h>=24) h-=24.0;
   return h;
}

bool IsFridayCutoff()
{
   if(!CloseOnFriday) return false;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.day_of_week!=5) return false;
   return (GetGMTHour()>=(double)FridayCloseHour);
}

bool InLondonSession()    { if(!SessionLondon)    return false; double h=GetGMTHour(); return(h>=8.0 &&h<17.0); }
bool InNewYorkSession()   { if(!SessionNewYork)   return false; double h=GetGMTHour(); return(h>=13.0&&h<22.0); }
bool InTokyoSession()     { if(!SessionTokyo)     return false; double h=GetGMTHour(); return(h>=0.0 &&h<9.0);  }
bool InSydneySession()    { if(!SessionSydney)    return false; double h=GetGMTHour(); return(h>=22.0||h<7.0);  }
bool InLondonNYOverlap()  { if(!OverlapLondonNY)  return false; double h=GetGMTHour(); return(h>=13.0&&h<17.0); }
bool InTokyoLondonOverlap(){ if(!OverlapTokyoLondon) return false; double h=GetGMTHour(); return(h>=8.0&&h<9.0); }

bool SessionActiveNow(string which)
{
   double h=GetGMTHour();
   if(which=="London")  return(h>=8.0 &&h<17.0);
   if(which=="NewYork") return(h>=13.0&&h<22.0);
   if(which=="Overlap") return(h>=13.0&&h<17.0);
   if(which=="Sydney")  return(h>=22.0||h<7.0);
   if(which=="Tokyo")   return(h>=0.0 &&h<9.0);
   return false;
}

bool IsTradingTime()
{
   if(!UseTimeFilter) return true;
   if(IsFridayCutoff()) return false;
   if(effBestHoursOnly)   // V1.2: uses effective value (style may override)
   { double g=GetGMTHour(); if(g<8.5||g>=15.0) return false; }
   return (InSydneySession()||InTokyoSession()||InLondonSession()||
           InNewYorkSession()||InLondonNYOverlap()||InTokyoLondonOverlap());
}

bool IsSpreadOK()
{
   if(MaxSpreadPoints<=0) return true;
   double sp=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;
   return(sp<=MaxSpreadPoints);
}

//===================================================================//
//  ATR HELPER                                                        //
//===================================================================//
double GetATR()
{
   double a[1];
   if(CopyBuffer(ATRHandle,0,1,1,a)==1) return a[0];
   return _Point*100;
}

//===================================================================//
//  POSITION CHECK                                                    //
//===================================================================//
bool IsPositionOpen()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t>0&&PositionSelectByTicket(t))
         if(PositionGetString(POSITION_SYMBOL)==_Symbol&&
            PositionGetInteger(POSITION_MAGIC)==MAGIC_NUMBER) return true;
   }
   return false;
}

//===================================================================//
//  HTF LEVEL DETECTION                                               //
//===================================================================//
bool HasReachedHTFLevel()
{
   if(!HTFLevelRequired) return true;
   ENUM_TIMEFRAMES htf;
   switch(HTFLevelMinutes){ case 15:htf=PERIOD_M15;break; case 30:htf=PERIOD_M30;break; default:htf=PERIOD_H1; }
   double price=iClose(_Symbol,htf,0);
   double tol=GetATR()*HTFToleranceATRMulti;
   for(int i=1;i<=20;i++)
   {
      double hi1=iHigh(_Symbol,htf,i), lo1=iLow(_Symbol,htf,i);
      double hi3=iHigh(_Symbol,htf,i+2), lo3=iLow(_Symbol,htf,i+2);
      if(hi1<lo3&&price>=hi1-tol&&price<=lo3+tol) return true;
      if(lo1>hi3&&price>=hi3-tol&&price<=lo1+tol) return true;
   }
   double ph=iHigh(_Symbol,htf,1), pl=iLow(_Symbol,htf,1);
   if(MathAbs(price-ph)<=tol||MathAbs(price-pl)<=tol) return true;
   double h1H=iHigh(_Symbol,PERIOD_H1,1), h1L=iLow(_Symbol,PERIOD_H1,1);
   if(MathAbs(price-h1H)<=tol*2||MathAbs(price-h1L)<=tol*2) return true;
   double h4H=iHigh(_Symbol,PERIOD_H4,1), h4L=iLow(_Symbol,PERIOD_H4,1);
   if(MathAbs(price-h4H)<=tol*4||MathAbs(price-h4L)<=tol*4) return true;
   double dH=iHigh(_Symbol,PERIOD_D1,1), dL=iLow(_Symbol,PERIOD_D1,1), dT=tol*3;
   if(MathAbs(price-dH)<=dT||MathAbs(price-dL)<=dT) return true;
   return false;
}

//===================================================================//
//  MSS DETECTION — Market Structure Shift on H1                     //
//===================================================================//
bool DetectMSS(bool &isBullish)
{
   int need = MSSLookbackBars + MSSConfirmBars*2 + 5;
   MqlRates h1[]; ArraySetAsSeries(h1,true);
   if(CopyRates(_Symbol,PERIOD_H1,0,need,h1)<need) return false;

   double swHigh=0,swLow=0;
   int    swHBar=INT_MAX, swLBar=INT_MAX;

   for(int i=MSSConfirmBars;i<MSSLookbackBars-MSSConfirmBars;i++)
   {
      bool isH=true,isL=true;
      for(int j=i-MSSConfirmBars;j<=i+MSSConfirmBars;j++)
      {
         if(j==i||j<0||j>=need) continue;
         if(h1[j].high>=h1[i].high) isH=false;
         if(h1[j].low <=h1[i].low)  isL=false;
      }
      if(isH&&i<swHBar){swHigh=h1[i].high;swHBar=i;}
      if(isL&&i<swLBar){swLow =h1[i].low; swLBar=i;}
   }

   if(swHBar==INT_MAX||swLBar==INT_MAX) return false;
   double cur=h1[1].close;
   if(swLBar<swHBar && cur>swHigh){ isBullish=true;  return true; }
   if(swHBar<swLBar && cur<swLow) { isBullish=false; return true; }
   return false;
}

//===================================================================//
//  BOS DETECTION — Break of Structure on M15                        //
//===================================================================//
bool DetectBOS(bool &isBullish)
{
   int need = BOSLookbackBars + 5;
   MqlRates m15[]; ArraySetAsSeries(m15,true);
   if(CopyRates(_Symbol,PERIOD_M15,0,need,m15)<need) return false;

   double swHigh=0,swLow=0;
   int    swHBar=INT_MAX,swLBar=INT_MAX;
   int    conf=3;

   for(int i=conf;i<BOSLookbackBars-conf;i++)
   {
      bool isH=true,isL=true;
      for(int j=i-conf;j<=i+conf;j++)
      {
         if(j==i||j<0||j>=need) continue;
         if(m15[j].high>=m15[i].high) isH=false;
         if(m15[j].low <=m15[i].low)  isL=false;
      }
      if(isH&&i<swHBar){swHigh=m15[i].high;swHBar=i;}
      if(isL&&i<swLBar){swLow =m15[i].low; swLBar=i;}
   }

   if(swHBar==INT_MAX&&swLBar==INT_MAX) return false;
   double cur=m15[1].close;
   if(swHigh>0&&cur>swHigh){ isBullish=true;  return true; }
   if(swLow >0&&cur<swLow) { isBullish=false; return true; }
   return false;
}

//===================================================================//
//  LIQUIDITY SWEEP DETECTION                                         //
//===================================================================//
bool DetectLiquiditySweep(bool &sweepBullish)
{
   int need = LiquidityLookbackBars + 5;
   MqlRates m15[]; ArraySetAsSeries(m15,true);
   if(CopyRates(_Symbol,PERIOD_M15,0,need,m15)<need) return false;

   double wickPts = LiquidityWickPips * PipFactor * _Point;
   double lvlLow=0, lvlHigh=0;
   for(int i=5;i<LiquidityLookbackBars;i++)
   {
      if(lvlLow==0||m15[i].low<lvlLow)   lvlLow=m15[i].low;
      if(lvlHigh==0||m15[i].high>lvlHigh) lvlHigh=m15[i].high;
   }
   if(lvlLow<=0||lvlHigh<=0) return false;

   for(int i=1;i<=4;i++)
   {
      if(m15[i].low < lvlLow - wickPts && m15[i].close > lvlLow)
      { sweepBullish=true;  return true; }
      if(m15[i].high > lvlHigh + wickPts && m15[i].close < lvlHigh)
      { sweepBullish=false; return true; }
   }
   return false;
}

//===================================================================//
//  5M CISD — fallback direction when MSS filter is off              //
//===================================================================//
bool IsCISD5M(bool &isBearish)
{
   bool allUp=true,allDown=true;
   for(int i=1;i<=2;i++)
   {
      double c=iClose(_Symbol,PERIOD_M5,i), o=iOpen(_Symbol,PERIOD_M5,i);
      if(c<=o) allUp=false;
      if(c>=o) allDown=false;
   }
   double curC=iClose(_Symbol,PERIOD_M5,0);
   if(allUp)
   { double sl=iLow(_Symbol,PERIOD_M5,1); for(int i=2;i<=2;i++){double l=iLow(_Symbol,PERIOD_M5,i);if(l<sl)sl=l;}
     if(curC<sl){isBearish=true;return true;} }
   if(allDown)
   { double sh=iHigh(_Symbol,PERIOD_M5,1); for(int i=2;i<=2;i++){double h=iHigh(_Symbol,PERIOD_M5,i);if(h>sh)sh=h;}
     if(curC>sh){isBearish=false;return true;} }
   for(int lb=1;lb<=10;lb++)
   {
      double o=iOpen(_Symbol,PERIOD_M5,lb),cl=iClose(_Symbol,PERIOD_M5,lb);
      double h=iHigh(_Symbol,PERIOD_M5,lb),l=iLow(_Symbol,PERIOD_M5,lb);
      double rng=h-l; if(rng>0&&MathAbs(cl-o)/rng>=0.70)
      {isBearish=(cl<o);return true;}
   }
   return false;
}

//===================================================================//
//  1M ENTRY TRIGGER                                                  //
//===================================================================//
bool IsCISD1M(bool &isBearish)
{
   bool allUp=true,allDown=true;
   double c=iClose(_Symbol,PERIOD_M1,1),o=iOpen(_Symbol,PERIOD_M1,1);
   if(c<=o) allUp=false;
   if(c>=o) allDown=false;
   double curC=iClose(_Symbol,PERIOD_M1,0);
   if(allUp  &&curC<iLow (_Symbol,PERIOD_M1,1)){isBearish=true; return true;}
   if(allDown&&curC>iHigh(_Symbol,PERIOD_M1,1)){isBearish=false;return true;}
   for(int lb=1;lb<=3;lb++)
   {
      double o1=iOpen(_Symbol,PERIOD_M1,lb),c1=iClose(_Symbol,PERIOD_M1,lb);
      double h1=iHigh(_Symbol,PERIOD_M1,lb),l1=iLow(_Symbol,PERIOD_M1,lb);
      double rng=h1-l1; if(rng>0&&MathAbs(c1-o1)/rng>=0.65)
      {isBearish=(c1<o1);return true;}
   }
   return false;
}

//===================================================================//
//  SWING DETECTION — H1 and M15                                     //
//===================================================================//
struct SwingCandidate { double price; int barIndex; };

void FindSwingPointsH1(double &swHigh,double &swLow)
{
   swHigh=0;swLow=0;
   MqlRates h1[]; ArraySetAsSeries(h1,true);
   int need=SwingLookbackBarsH1+SwingConfirmBarsH1+5;
   if(CopyRates(_Symbol,PERIOD_H1,0,need,h1)<need) return;
   double maxD=(MaxSwingDistancePips>0)?MaxSwingDistancePips*PipFactor*_Point:DBL_MAX;
   double cur=iClose(_Symbol,PERIOD_H1,0);
   int bH=INT_MAX,bL=INT_MAX;
   for(int i=SwingConfirmBarsH1;i<SwingLookbackBarsH1-SwingConfirmBarsH1;i++)
   {
      if(MathAbs(h1[i].high-cur)<=maxD){bool ok=true; for(int j=i-SwingConfirmBarsH1;j<=i+SwingConfirmBarsH1;j++){if(j==i||j<0)continue;if(h1[j].high>=h1[i].high){ok=false;break;}} if(ok&&i<bH){swHigh=h1[i].high;bH=i;}}
      if(MathAbs(h1[i].low -cur)<=maxD){bool ok=true; for(int j=i-SwingConfirmBarsH1;j<=i+SwingConfirmBarsH1;j++){if(j==i||j<0)continue;if(h1[j].low<=h1[i].low){ok=false;break;}} if(ok&&i<bL){swLow =h1[i].low; bL=i;}}
   }
}

void FindSwingPointsM15(double &swHigh,double &swLow)
{
   swHigh=0;swLow=0;
   MqlRates m15[]; ArraySetAsSeries(m15,true);
   int need=SwingLookbackBarsM15+SwingConfirmBarsM15+5;
   if(CopyRates(_Symbol,PERIOD_M15,0,need,m15)<need) return;
   double maxD=(MaxSwingDistancePips>0)?MaxSwingDistancePips*PipFactor*_Point:DBL_MAX;
   double cur=iClose(_Symbol,PERIOD_M15,0);
   int bH=INT_MAX,bL=INT_MAX;
   for(int i=SwingConfirmBarsM15;i<SwingLookbackBarsM15-SwingConfirmBarsM15;i++)
   {
      if(MathAbs(m15[i].high-cur)<=maxD){bool ok=true;for(int j=i-SwingConfirmBarsM15;j<=i+SwingConfirmBarsM15;j++){if(j==i||j<0)continue;if(m15[j].high>=m15[i].high){ok=false;break;}}if(ok&&i<bH){swHigh=m15[i].high;bH=i;}}
      if(MathAbs(m15[i].low -cur)<=maxD){bool ok=true;for(int j=i-SwingConfirmBarsM15;j<=i+SwingConfirmBarsM15;j++){if(j==i||j<0)continue;if(m15[j].low<=m15[i].low){ok=false;break;}}if(ok&&i<bL){swLow =m15[i].low; bL=i;}}
   }
}

void FindNearestSwing(bool isBuy,double &swPrice)
{
   swPrice=0;
   FindSwingPointsM15(lastSwingHighM15,lastSwingLowM15);
   if(isBuy  &&lastSwingLowM15 >0) swPrice=lastSwingLowM15;
   if(!isBuy &&lastSwingHighM15>0) swPrice=lastSwingHighM15;
   if(swPrice<=0)
   {
      double atr=GetATR();
      swPrice=isBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID)-atr*1.5:SymbolInfoDouble(_Symbol,SYMBOL_ASK)+atr*1.5;
   }
   if(ShowSwingLines) DrawSwingLine(swPrice,isBuy,"M15");
}

//===================================================================//
//  FVG COUNT ON 1M                                                   //
//===================================================================//
int CountFVGsOn1Min(datetime startTime,datetime endTime)
{
   int count=0;
   MqlRates rates[]; ArraySetAsSeries(rates,false);
   datetime from=startTime-PeriodSeconds(PERIOD_M1)*5;
   int copied=CopyRates(_Symbol,PERIOD_M1,from,endTime+PeriodSeconds(PERIOD_M1),rates);
   if(copied<3) return 0;
   for(int i=0;i<copied-2;i++)
   {
      if(rates[i].time<startTime||rates[i].time>endTime) continue;
      if(rates[i+2].low >rates[i].high) count++;
      if(rates[i+2].high<rates[i].low)  count++;
   }
   return count;
}

int GetEffectiveFVGReq() { return RelaxedMode?0:MinFVGsRequired; }

//===================================================================//
//  OTE ZONE                                                          //
//===================================================================//
bool IsInOTEZone(double price,double hi,double lo)
{
   if(hi<=0||lo<=0||hi<=lo) return false;
   double range=hi-lo;
   return(price>=lo+range*effOTEMin && price<=lo+range*effOTEMax);
}

double GetOTEPrice(double hi,double lo,double lvl)
{
   if(hi<=0||lo<=0) return 0;
   return lo+(hi-lo)*lvl;
}

//===================================================================//
//  SMT DIVERGENCE                                                    //
//===================================================================//
bool CheckSMTDivergence(bool isBuy)
{
   if(!UseSMTFilter) return true;
   if(StringLen(SMTSymbol)<3) return true;
   MqlRates r1[2],r2[2];
   if(CopyRates(_Symbol,  PERIOD_H1,0,2,r1)!=2) return true;
   if(CopyRates(SMTSymbol,PERIOD_H1,0,2,r2)!=2) return true;
   bool symUp =(r1[1].close>r1[1].open);
   bool corrUp=(r2[1].close>r2[1].open);
   bool diverge=(symUp!=corrUp);
   if(isBuy  && diverge) return true;
   if(!isBuy && diverge) return true;
   return false;
}

//===================================================================//
//  NEWS FILTER                                                       //
//===================================================================//
bool IsNewsTime()
{
   if(!UseNewsFilter) return false;
   if(TimeCurrent()-lastNewsCheck < 60) return newsBlocked;
   lastNewsCheck=TimeCurrent();
   datetime from=TimeCurrent()-NewsBlockBeforeMin*60;
   datetime to  =TimeCurrent()+NewsBlockAfterMin*60;
   MqlCalendarValue vals[];
   int cnt=CalendarValueHistory(vals,from,to,NULL,NULL);
   for(int i=0;i<cnt;i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id,ev)) continue;
      if(ev.importance==CALENDAR_IMPORTANCE_HIGH)
      { newsBlocked=true; return true; }
   }
   newsBlocked=false;
   return false;
}

//===================================================================//
//  DAILY TREND ALIGNMENT                                             //
//===================================================================//
bool IsTrendAligned(bool isBuy)
{
   MqlRates d1[4];
   bool d1Up=false,d1Dn=false;
   if(CopyRates(_Symbol,PERIOD_D1,0,4,d1)==4)
   {
      int bull=0,bear=0;
      for(int di=1;di<=3;di++){ if(d1[di].close>d1[di].open)bull++;else bear++; }
      d1Up=isBuy?(bull==3):(bull>=2);
      d1Dn=isBuy?(bear>=2):(bear==3);
   }
   double h4e[1]; bool h4Up=false,h4Dn=false;
   int h4h=iMA(_Symbol,PERIOD_H4,50,0,MODE_EMA,PRICE_CLOSE);
   if(h4h!=INVALID_HANDLE&&CopyBuffer(h4h,0,1,1,h4e)==1)
   {
      IndicatorRelease(h4h);
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      h4Up=(bid>h4e[0]); h4Dn=(bid<h4e[0]);
   }
   if(isBuy)
   { bool anyBull=d1Up||h4Up; bool strongBear=d1Dn&&h4Dn;
     if(strongBear||(!anyBull&&d1Dn)) return false; }
   else
   { bool anyBear=d1Dn||h4Dn; bool strongBull=d1Up&&h4Up;
     if(strongBull||(!anyBear&&d1Up)) return false; }
   return true;
}

//===================================================================//
//  TRADE QUALITY SCORE                                               //
//===================================================================//
int CalculateTradeScore(bool isBuy)
{
   int s=0;
   if(!effUseMSSFilter || mssConfirmed)          s+=20;
   if(!effUseBOSFilter || bosConfirmed)          s+=20;
   if(!effRequireLiqSweep||liquiditySweepDone)   s+=20;
   int fvgR=GetEffectiveFVGReq();
   if(fvgR==0||(fvgCount1Min>=0&&fvgCount1Min>=fvgR)) s+=15;
   s+=15; // OTE always confirmed here
   if(IsTrendAligned(isBuy)) s+=10;
   return s;
}

//===================================================================//
//  BROKER PROTECTION LAYER                                           //
//===================================================================//
bool IsBrokerOrderSafe(bool isBuy,double entry,double sl,double tp,string &reason)
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)){ reason="TERMINAL TRADING DISABLED"; return false; }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))          { reason="EA AUTOTRADING DISABLED";   return false; }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))  { reason="ACCOUNT TRADING DISABLED";  return false; }
   long mode=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   if(mode==SYMBOL_TRADE_MODE_DISABLED) { reason="SYMBOL TRADING DISABLED"; return false; }
   if(mode==SYMBOL_TRADE_MODE_CLOSEONLY){ reason="SYMBOL CLOSE ONLY";        return false; }
   double stopLvl=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   double freeLvl=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)*_Point;
   if(MathAbs(entry-sl)<stopLvl){ reason="SL INSIDE STOP LEVEL"; return false; }
   if(MathAbs(entry-tp)<stopLvl){ reason="TP INSIDE STOP LEVEL"; return false; }
   if(freeLvl>0&&MathAbs(entry-tp)<freeLvl){ reason="TP INSIDE FREEZE LEVEL"; return false; }
   reason=""; return true;
}

//===================================================================//
//  STATE MACHINE — CONTEXT BUILDING (per M15 bar)                   //
//  V1.2: uses eff* flags; increments rejection counters             //
//===================================================================//
void UpdateContextState()
{
   // STEP 1: HTF Level
   if(HasReachedHTFLevel())
   {
      if(!htfLevelReached)
      { htfLevelReached=true; Print("STEP 1 PASS: HTF Level"); lastFailedStep=0; lastFailedStepDesc=""; }
   }
   else
   {
      if(htfLevelReached) htfLevelReached=false;
      rejHTFLevel++; rejTotal++;
      lastFailedStep=1; lastFailedStepDesc="HTF Level"; return;
   }

   // STEP 2: MSS on H1 (or 5M CISD fallback when effUseMSSFilter=false)
   if(effUseMSSFilter)
   {
      bool mssB=false;
      if(DetectMSS(mssB))
      {
         if(!mssConfirmed||mssIsBullish!=mssB)
         { mssConfirmed=true; mssIsBullish=mssB; cisd5MinConfirmed=true; cisd5MinIsBearish=!mssB;
           cisd1MinConfirmed=false; fvgCount1Min=-1;
           Print("STEP 2 PASS: MSS "+(mssB?"BULLISH":"BEARISH")); }
      }
      else
      {
         if(mssConfirmed){ mssConfirmed=false; DebugPrint("STEP 2: MSS lost"); }
         rejMSS++; rejTotal++;
         lastFailedStep=2; lastFailedStepDesc="MSS (H1)"; return;
      }
   }
   else
   {
      bool tempBear=false;
      bool foundCISD5=IsCISD5M(tempBear);
      if(!foundCISD5)
      {
         for(int lb=1;lb<=10;lb++)
         {
            double o5=iOpen(_Symbol,PERIOD_M5,lb),cl5=iClose(_Symbol,PERIOD_M5,lb);
            double h5=iHigh(_Symbol,PERIOD_M5,lb),l5=iLow(_Symbol,PERIOD_M5,lb);
            double rng5=h5-l5;
            if(rng5>0&&MathAbs(cl5-o5)/rng5>=0.70){tempBear=(cl5<o5);foundCISD5=true;break;}
         }
      }
      if(foundCISD5)
      {
         datetime bt5=iTime(_Symbol,PERIOD_M5,0);
         if(LastCISDTime5Min!=bt5)
         { LastCISDTime5Min=bt5; cisd5MinConfirmed=true; cisd5MinIsBearish=tempBear;
           mssConfirmed=true; mssIsBullish=!tempBear;
           cisd1MinConfirmed=false; fvgCount1Min=-1;
           Print("STEP 2 PASS: 5M CISD "+(tempBear?"BEARISH":"BULLISH")); }
      }
      if(!mssConfirmed)
      { rejMSS++; rejTotal++; lastFailedStep=2; lastFailedStepDesc="5M Direction"; return; }
   }

   // STEP 3: BOS on M15
   if(effUseBOSFilter)
   {
      bool bosB=false;
      if(DetectBOS(bosB))
      {
         if(!bosConfirmed||bosIsBullish!=bosB)
         { bosConfirmed=true; bosIsBullish=bosB; Print("STEP 3 PASS: BOS "+(bosB?"BULLISH":"BEARISH")); }
      }
      else
      {
         if(bosConfirmed){ bosConfirmed=false; DebugPrint("STEP 3: BOS lost"); }
         rejBOS++; rejTotal++;
         lastFailedStep=3; lastFailedStepDesc="BOS (M15)"; return;
      }
   }
   else bosConfirmed=true;

   // STEP 4: Liquidity Sweep
   if(effRequireLiqSweep)
   {
      bool swpB=false;
      if(DetectLiquiditySweep(swpB))
      {
         if(!liquiditySweepDone)
         { liquiditySweepDone=true; sweepIsBullish=swpB; Print("STEP 4 PASS: Liquidity Sweep"); }
      }
      else if(!liquiditySweepDone)
      { rejSweep++; rejTotal++; lastFailedStep=4; lastFailedStepDesc="Liquidity Sweep"; return; }
   }
   else liquiditySweepDone=true;

   // STEP 5: 1M FVG count
   if(fvgCount1Min<0)
   {
      datetime cStart=LastCISDTime5Min-PeriodSeconds(PERIOD_M5);
      datetime cEnd  =LastCISDTime5Min;
      if(cEnd<=0){ datetime b5[1]; if(CopyTime(_Symbol,PERIOD_M5,1,1,b5)==1){cEnd=b5[0];cStart=b5[0]-PeriodSeconds(PERIOD_M5);} }
      fvgCount1Min=CountFVGsOn1Min(cStart,cEnd);
      DebugPrint("STEP 5: FVG count="+IntegerToString(fvgCount1Min));
   }
   int fvgReq=GetEffectiveFVGReq();
   if(fvgReq>0&&fvgCount1Min<fvgReq)
   { rejFVG++; rejTotal++; lastFailedStep=5; lastFailedStepDesc="1M FVG Count"; return; }

   // STEP 6: H1 Swings for OTE
   FindSwingPointsH1(lastSwingHighH1,lastSwingLowH1);
   if(lastSwingHighH1<=0||lastSwingLowH1<=0||lastSwingHighH1<=lastSwingLowH1)
   { rejH1Swing++; rejTotal++; lastFailedStep=6; lastFailedStepDesc="H1 Swings"; return; }

   if(effUseH1RangeFilter && effMinH1Range>0)
   {
      double rangePips=(lastSwingHighH1-lastSwingLowH1)/_Point/PipFactor;
      if(rangePips<effMinH1Range)
      { rejH1Range++; rejTotal++; lastFailedStep=6; lastFailedStepDesc="H1 Range Too Small"; return; }
   }

   // STEP 7: M15 Swings for SL
   FindSwingPointsM15(lastSwingHighM15,lastSwingLowM15);
   if(ShowOTEZone) DrawOTEZone(lastSwingHighH1,lastSwingLowH1);
}

//===================================================================//
//  LIVE ENTRY CHECK — per tick                                       //
//  V1.2: uses eff* flags; per-bar rejection counting                //
//===================================================================//
bool CheckTwinsSequence(bool &isBuy)
{
   if(UseTimeFilter&&!IsTradingTime()) return false;
   if(!htfLevelReached||!mssConfirmed||!bosConfirmed||!liquiditySweepDone||
      fvgCount1Min<0||lastSwingHighH1<=0||lastSwingLowH1<=0)
   { DebugPrint("Entry: context not ready"); return false; }

   double curPrice=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double range=lastSwingHighH1-lastSwingLowH1;
   double oteLow =lastSwingLowH1+range*(RelaxedMode?effOTEMin-0.02:effOTEMin);
   double oteHigh=lastSwingLowH1+range*(RelaxedMode?effOTEMax+0.02:effOTEMax);

   // Per-bar guard for rejection counting
   datetime curBar=iTime(_Symbol,PERIOD_M15,0);
   bool newBar=(curBar!=rejSeqLastBar);

   if(curPrice<oteLow||curPrice>oteHigh)
   {
      if(newBar){ rejOTE++; rejTotal++; rejSeqLastBar=curBar; }
      lastFailedStep=8; lastFailedStepDesc="OTE Zone"; return false;
   }

   bool tempBear1=false;
   bool found1=IsCISD1M(tempBear1);
   if(!found1)
   {
      for(int lb=1;lb<=3;lb++)
      {
         double o1=iOpen(_Symbol,PERIOD_M1,lb),c1=iClose(_Symbol,PERIOD_M1,lb);
         double h1=iHigh(_Symbol,PERIOD_M1,lb),l1=iLow(_Symbol,PERIOD_M1,lb);
         double rng1=h1-l1;
         if(rng1>0&&MathAbs(c1-o1)/rng1>=0.65){tempBear1=(c1<o1);found1=true;break;}
      }
   }
   if(found1)
   {
      datetime bt1=iTime(_Symbol,PERIOD_M1,0);
      if(LastCISDTime1Min!=bt1)
      { LastCISDTime1Min=bt1; cisd1MinConfirmed=true; cisd1MinIsBearish=tempBear1; }
   }
   if(!cisd1MinConfirmed)
   {
      if(newBar){ rej1MTrig++; rejTotal++; rejSeqLastBar=curBar; }
      lastFailedStep=9; lastFailedStepDesc="1M Entry Trigger"; return false;
   }

   double oteBottom=lastSwingLowH1+range*effOTEMin;
   double oteTop   =lastSwingLowH1+range*effOTEMax;
   double oteRange =oteTop-oteBottom;
   bool priceInBuy =(curPrice<=oteBottom+oteRange*0.35);
   bool priceInSell=(curPrice>=oteTop  -oteRange*0.35);

   if(!priceInBuy&&!priceInSell){ lastFailedStep=9; lastFailedStepDesc="OTE Middle (no-trade)"; return false; }
   isBuy=priceInBuy;

   if(mssIsBullish!=isBuy)    { lastFailedStep=9; lastFailedStepDesc="MSS/OTE Conflict"; return false; }
   if(cisd1MinIsBearish==isBuy){ lastFailedStep=9; lastFailedStepDesc="1M/OTE Conflict"; return false; }

   if(effUseDailyTrend&&!IsTrendAligned(isBuy))
   {
      if(newBar){ rejTrend++; rejTotal++; rejSeqLastBar=curBar; }
      lastFailedStep=10; lastFailedStepDesc="MTF Trend"; return false;
   }
   if(UseSMTFilter&&!CheckSMTDivergence(isBuy))
   {
      if(newBar){ rejSMT++; rejTotal++; rejSeqLastBar=curBar; }
      lastFailedStep=10; lastFailedStepDesc="SMT Divergence"; return false;
   }
   if(IsNewsTime())
   {
      if(newBar){ rejNews++; rejTotal++; rejSeqLastBar=curBar; }
      lastFailedStep=10; lastFailedStepDesc="News Blocked"; return false;
   }

   int score=CalculateTradeScore(isBuy);
   lastTradeScore=score;
   if(UseTradeScore && effMinScore>0 && score<effMinScore)
   {
      if(newBar){ rejScore++; rejTotal++; rejSeqLastBar=curBar; }
      lastFailedStep=10; lastFailedStepDesc="Score "+IntegerToString(score)+"/"+IntegerToString(effMinScore); return false;
   }

   if(newBar) rejSeqLastBar=curBar;
   lastFailedStep=0; lastFailedStepDesc="";
   static datetime lastLog=0; datetime cb=iTime(_Symbol,PERIOD_M15,0);
   if(lastLog!=cb){ lastLog=cb; Print(">>> ENTRY READY: "+(isBuy?"BUY":"SELL")+" Score="+IntegerToString(score)+" <<<"); }
   return true;
}

//===================================================================//
//  DAILY COUNTERS                                                    //
//===================================================================//
void UpdateDailyCounters()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.day==LastTradeDay) return;
   TodayTradeCount=0; TodayLossTrades=0; TodayLoss=0;
   if(ResetLossStreakDaily) consecutiveLosses=0;
   LastTradeDay=dt.day;
   htfLevelReached=false; mssConfirmed=false; bosConfirmed=false; liquiditySweepDone=false;
   cisd5MinConfirmed=false; cisd1MinConfirmed=false; fvgCount1Min=-1;
   lastSwingHighH1=0; lastSwingLowH1=0; lastSwingHighM15=0; lastSwingLowM15=0;
   // V1.2: reset rejection stats daily
   rejTotal=0; rejHTFLevel=0; rejMSS=0; rejBOS=0; rejSweep=0;
   rejFVG=0; rejH1Swing=0; rejH1Range=0; rejOTE=0; rej1MTrig=0;
   rejScore=0; rejTrend=0; rejSMT=0; rejNews=0;
   rejSeqLastBar=0;
}

bool IsDailyLossLimitHit()
{
   if(MaxDailyLossPercent<=0) return false;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   dt.hour=0; dt.min=0; dt.sec=0; datetime todayStart=StructToTime(dt);
   TodayLoss=0;
   if(HistorySelect(todayStart,TimeCurrent()))
   {
      for(int i=HistoryDealsTotal()-1;i>=0;i--)
      {
         ulong deal=HistoryDealGetTicket(i);
         if(deal==0||HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol||
            HistoryDealGetInteger(deal,DEAL_MAGIC)!=MAGIC_NUMBER||
            HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
         double p=HistoryDealGetDouble(deal,DEAL_PROFIT);
         if(p<0) TodayLoss+=MathAbs(p);
      }
   }
   double balance=AccountInfoDouble(ACCOUNT_BALANCE), equity=AccountInfoDouble(ACCOUNT_EQUITY);
   return(TodayLoss>=MathMin(balance,equity)*MaxDailyLossPercent/100.0);
}

bool CanTrade()
{
   UpdateDailyCounters();
   static datetime lastLog=0; bool canLog=(TimeCurrent()-lastLog>=60);
   if(IsDailyLossLimitHit()){if(canLog){Print("CANTRADE: Daily loss limit");lastLog=TimeCurrent();}return false;}
   if(TodayTradeCount>=MaxTradesPerDay){if(canLog){Print("CANTRADE: Max trades");lastLog=TimeCurrent();}return false;}
   if(MaxDailyLossTrades>0&&TodayLossTrades>=MaxDailyLossTrades){if(canLog){Print("CANTRADE: Loss trades limit");lastLog=TimeCurrent();}return false;}
   if(consecutiveLosses>=MaxConsecutiveLosses){if(canLog){Print("CANTRADE: Consecutive losses");lastLog=TimeCurrent();}return false;}
   if(!IsSpreadOK()){if(canLog){DebugPrint("CANTRADE: Spread");lastLog=TimeCurrent();}return false;}
   if(IsPositionOpen()) return false;
   if(effCooldown>0&&LastTradeCloseTime>0&&
      TimeCurrent()-LastTradeCloseTime<(datetime)(effCooldown*60))   // V1.2: effCooldown
   {if(canLog){Print("CANTRADE: Cooldown (",effCooldown,"m)");lastLog=TimeCurrent();}return false;}
   return true;
}

//===================================================================//
//  LOT SIZE                                                          //
//===================================================================//
double CalculateLotSize(double slPoints)
{
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double lotStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(slPoints<=0) return minLot;

   if(RiskMode==RISK_FIXED_LOT||FixedLot>0)
   {
      double lot=MathMax(minLot,MathMin(MathMin(maxLot,MaxLotLimit),FixedLot>0?FixedLot:0.01));
      return NormalizeDouble(MathFloor(lot/lotStep)*lotStep,2);
   }

   double tickVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSz =SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickVal<=0||tickSz<=0) return minLot;

   double base=(RiskMode==RISK_DYNAMIC_EQ)?AccountInfoDouble(ACCOUNT_EQUITY):AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney=base*effRiskPct/100.0;
   double lossPerLot=(slPoints*_Point/tickSz)*tickVal;
   if(lossPerLot<=0) return minLot;

   double vol=riskMoney/lossPerLot;
   vol=MathMax(minLot,MathMin(MathMin(maxLot,MaxLotLimit),vol));
   return NormalizeDouble(MathFloor(vol/lotStep)*lotStep,2);
}

//===================================================================//
//  PARTIAL CLOSE                                                     //
//===================================================================//
void PartialClosePosition(ulong ticket,double closeLots)
{
   if(!PositionSelectByTicket(ticket)) return;
   ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double curPrice=pt==POSITION_TYPE_BUY?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol;
   req.volume=NormalizeDouble(closeLots,2);
   req.type=(pt==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   req.price=curPrice; req.deviation=30;
   req.magic=MAGIC_NUMBER; req.position=ticket;
   req.comment="ICT SMC V1.2 Partial TP";
   if(!OrderSend(req,res)) Print("Partial close failed: ",res.retcode," ",res.comment);
}

void CheckPartialTP()
{
   if(!UsePartialTP) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol||PositionGetInteger(POSITION_MAGIC)!=MAGIC_NUMBER) continue;
      string key="TWINS_PTL_"+IntegerToString(ticket);
      if(GlobalVariableCheck(key)) continue;
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   =PositionGetDouble(POSITION_SL);
      double slDist=MathAbs(entry-sl);
      if(slDist<=0) continue;
      double price=pt==POSITION_TYPE_BUY?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double profit=pt==POSITION_TYPE_BUY?(price-entry):(entry-price);
      if(profit/slDist<PartialCloseRR) continue;
      double vol=PositionGetDouble(POSITION_VOLUME);
      double closeVol=NormalizeDouble(vol*PartialClosePercent/100.0,2);
      double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      if(closeVol<minLot) continue;
      PartialClosePosition(ticket,closeVol);
      GlobalVariableSet(key,1);
      double beSL=pt==POSITION_TYPE_BUY?NormalizeDouble(entry+2*_Point,_Digits):NormalizeDouble(entry-2*_Point,_Digits);
      double curSL=PositionGetDouble(POSITION_SL), curTP=PositionGetDouble(POSITION_TP);
      bool move=(pt==POSITION_TYPE_BUY&&(curSL==0||beSL>curSL))||(pt==POSITION_TYPE_SELL&&(curSL==0||beSL<curSL));
      if(move) trade.PositionModify(ticket,beSL,curTP);
      Print("PARTIAL TP: Closed ",DoubleToString(closeVol,2)," lots at 1R | SL→BE");
   }
}

//===================================================================//
//  LOGGING                                                           //
//===================================================================//
void WriteCSVLog(string type,ulong posID,bool isBuy,double entry,double sl,double tp,double lot,double profit,int score,string comment="")
{
   if(!EnableCSVLog) return;
   string fname=EA_NAME+"_"+_Symbol+"_trades.csv";
   int fh=FileOpen(fname,FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON,',');
   if(fh==INVALID_HANDLE){ Print("CSV open failed: ",GetLastError()); return; }
   FileSeek(fh,0,SEEK_END);
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   string ts=StringFormat("%04d.%02d.%02d %02d:%02d:%02d",dt.year,dt.mon,dt.day,dt.hour,dt.min,dt.sec);
   FileWrite(fh,type,ts,IntegerToString(posID),(isBuy?"BUY":"SELL"),
             DoubleToString(entry,_Digits),DoubleToString(sl,_Digits),DoubleToString(tp,_Digits),
             DoubleToString(lot,2),DoubleToString(profit,2),IntegerToString(score),comment);
   FileClose(fh);
}

void TakeScreenshot(string suffix)
{
   if(!EnableScreenshot) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   string fname=StringFormat("%s_%s_%04d%02d%02d_%02d%02d%02d_%s.png",
                             EA_NAME,_Symbol,dt.year,dt.mon,dt.day,dt.hour,dt.min,dt.sec,suffix);
   int w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   int h=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   if(!ChartScreenShot(0,fname,w,h,ALIGN_LEFT)) Print("Screenshot failed: ",GetLastError());
}

//===================================================================//
//  TRADE PLACEMENT                                                   //
//===================================================================//
void PlaceTrade(bool isBuy=true)
{
   if(IsPositionOpen()) return;
   long tradeMode=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   if(tradeMode==SYMBOL_TRADE_MODE_DISABLED||tradeMode==SYMBOL_TRADE_MODE_CLOSEONLY) return;

   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;

   if(ForceTrades)
   {
      static int fCnt=0; fCnt++;
      isBuy=(fCnt%2==1); Print("FORCE MODE: Trade #",fCnt," → ",(isBuy?"BUY":"SELL"));
   }

   double entry=isBuy?tick.ask:tick.bid;
   double swingPrice=0; FindNearestSwing(isBuy,swingPrice);
   double buffer=SLBufferPips*PipFactor*_Point;
   double sl=isBuy?NormalizeDouble(swingPrice-buffer,_Digits):NormalizeDouble(swingPrice+buffer,_Digits);

   if(isBuy &&sl>=entry){ Print("SKIP: SL>=entry (BUY)");  return; }
   if(!isBuy&&sl<=entry){ Print("SKIP: SL<=entry (SELL)"); return; }

   double slPoints=MathAbs(entry-sl)/_Point;
   if(slPoints<MinStopDistance){ Print("SKIP: SL too close (",slPoints," pts)"); return; }

   if(effMaxSLPips>0)
   { double maxSLP=effMaxSLPips*PipFactor;
     if(slPoints>maxSLP)
     { double atr=GetATR();
       sl=isBuy?NormalizeDouble(entry-atr*1.5,_Digits):NormalizeDouble(entry+atr*1.5,_Digits);
       slPoints=MathAbs(entry-sl)/_Point; } }

   if(effMinSLPips>0)
   { double slPips=slPoints/PipFactor;
     if(slPips<(double)effMinSLPips)
     { Print("SKIP: SL too small (",DoubleToString(slPips,2)," pips)");
       cisd1MinConfirmed=false; return; } }

   double atr=GetATR();
   double fixRR=isBuy?NormalizeDouble(entry+slPoints*_Point*RewardRiskRatio,_Digits)
                     :NormalizeDouble(entry-slPoints*_Point*RewardRiskRatio,_Digits);
   double atrTP=isBuy?NormalizeDouble(entry+atr*ATRMultiplierTP,_Digits)
                     :NormalizeDouble(entry-atr*ATRMultiplierTP,_Digits);
   double tp=fixRR;
   if(TPMode==TP_ATR)    tp=atrTP;
   else if(TPMode==TP_HYBRID) tp=isBuy?MathMin(fixRR,atrTP):MathMax(fixRR,atrTP);

   double actualRR=MathAbs(tp-entry)/MathAbs(entry-sl);
   if(actualRR<MinRewardRiskRatio-0.001)
   { Print("SKIP: R:R=",DoubleToString(actualRR,4)," < min ",MinRewardRiskRatio); cisd1MinConfirmed=false; return; }
   if(isBuy &&tp<=entry){ Print("SKIP: TP below entry"); return; }
   if(!isBuy&&tp>=entry){ Print("SKIP: TP above entry"); return; }

   string reason="";
   if(!IsBrokerOrderSafe(isBuy,entry,sl,tp,reason))
   { Print("BROKER BLOCK: ",reason); cisd1MinConfirmed=false; return; }

   double volume=CalculateLotSize(slPoints);
   if(volume<=0){ Print("SKIP: Invalid lot size"); return; }

   Print("══════════════════════════════════════════");
   Print(EA_NAME," TRADE | Style=",EnumToString(TradingStyle));
   Print("Direction : ",(isBuy?"BUY":"SELL")," | Score=",lastTradeScore,"/100");
   Print("Entry     : ",DoubleToString(entry,_Digits));
   Print("SL        : ",DoubleToString(sl,_Digits)," (",DoubleToString(slPoints,0)," pts)");
   Print("TP        : ",DoubleToString(tp,_Digits)," | R:R=",DoubleToString(actualRR,2));
   Print("Lot Size  : ",DoubleToString(volume,2)," | Cooldown=",effCooldown,"m");
   Print("══════════════════════════════════════════");

   bool result=isBuy?trade.Buy (volume,_Symbol,entry,sl,tp,"ICT SMC BUY V1.2")
                    :trade.Sell(volume,_Symbol,entry,sl,tp,"ICT SMC SELL V1.2");

   if(result)
   {
      TodayTradeCount++;
      cisd5MinConfirmed=false; cisd1MinConfirmed=false;
      mssConfirmed=false; bosConfirmed=false; liquiditySweepDone=false; fvgCount1Min=-1;
      ulong openDeal=trade.ResultDeal();
      if(openDeal>0&&HistoryDealSelect(openDeal))
      {
         ulong posID=(ulong)HistoryDealGetInteger(openDeal,DEAL_POSITION_ID);
         GlobalVariableSet("TWINS_RR_"+IntegerToString(posID),actualRR);
         WriteCSVLog("OPEN",posID,isBuy,entry,sl,tp,volume,0,lastTradeScore,"Score:"+IntegerToString(lastTradeScore));
      }
      TakeScreenshot(isBuy?"BUY_OPEN":"SELL_OPEN");
   }
   else
   { Print("TRADE FAILED: ",trade.ResultRetcodeDescription()); cisd1MinConfirmed=false; }
}

//===================================================================//
//  TRAILING STOP                                                     //
//===================================================================//
void ApplyTrailingStop()
{
   if(!UseTrailingStop) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0||!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol||PositionGetInteger(POSITION_MAGIC)!=MAGIC_NUMBER) continue;
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL=PositionGetDouble(POSITION_SL), curTP=PositionGetDouble(POSITION_TP);
      double price=type==POSITION_TYPE_BUY?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double profitPips=type==POSITION_TYPE_BUY?(price-openPrice)/_Point/PipFactor:(openPrice-price)/_Point/PipFactor;
      if(profitPips<TrailingStartPips) continue;
      double newSL=type==POSITION_TYPE_BUY?NormalizeDouble(price-TrailingStepPips*PipFactor*_Point,_Digits)
                                           :NormalizeDouble(price+TrailingStepPips*PipFactor*_Point,_Digits);
      bool mod=(type==POSITION_TYPE_BUY&&(curSL==0||newSL>curSL))||(type==POSITION_TYPE_SELL&&(curSL==0||newSL<curSL));
      if(mod) trade.PositionModify(ticket,newSL,curTP);
   }
}

//===================================================================//
//  BREAKEVEN                                                         //
//===================================================================//
void ApplyBreakeven()
{
   if(!UseBreakeven) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0||!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol||PositionGetInteger(POSITION_MAGIC)!=MAGIC_NUMBER) continue;
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL=PositionGetDouble(POSITION_SL), curTP=PositionGetDouble(POSITION_TP);
      double price=type==POSITION_TYPE_BUY?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double profitPips=type==POSITION_TYPE_BUY?(price-openPrice)/_Point/PipFactor:(openPrice-price)/_Point/PipFactor;
      if(profitPips<BreakevenTriggerPips) continue;
      double beSL=type==POSITION_TYPE_BUY?NormalizeDouble(openPrice+2*_Point,_Digits):NormalizeDouble(openPrice-2*_Point,_Digits);
      bool mod=(type==POSITION_TYPE_BUY&&(curSL==0||beSL>curSL))||(type==POSITION_TYPE_SELL&&(curSL==0||beSL<curSL));
      if(mod) trade.PositionModify(ticket,beSL,curTP);
   }
}

//===================================================================//
//  FRIDAY CLOSE                                                      //
//===================================================================//
void CheckFridayClose()
{
   if(!CloseOnFriday||!IsFridayCutoff()) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0&&PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL)==_Symbol&&PositionGetInteger(POSITION_MAGIC)==MAGIC_NUMBER)
            trade.PositionClose(ticket);
   }
}

//===================================================================//
//  CHART DRAWING                                                     //
//===================================================================//
void DrawOTEZone(double hi,double lo)
{
   if(hi<=0||lo<=0||hi<=lo) return;
   if(MathAbs(hi-lastOTEHigh)<_Point*2&&MathAbs(lo-lastOTELow)<_Point*2) return;
   lastOTEHigh=hi; lastOTELow=lo;
   for(int i=0;i<4;i++){ if(OTEObjectNames[i]!="")ObjectDelete(0,OTEObjectNames[i]); }

   double range=hi-lo;
   double oteLow =lo+range*effOTEMin, oteHigh=lo+range*effOTEMax;
   double oteRange=oteHigh-oteLow;
   double buyTop  =oteLow+oteRange*0.35, sellBtm=oteHigh-oteRange*0.35;
   datetime t0=iTime(_Symbol,PERIOD_H1,20);
   datetime t1=iTime(_Symbol,PERIOD_H1,0)+(datetime)(PeriodSeconds(PERIOD_H1)*10);

   string names[]={"OTEZO_BG","OTEZO_BUY","OTEZO_SELL","OTEZO_MID"};
   double prices[4][2]={{oteLow,oteHigh},{oteLow,buyTop},{sellBtm,oteHigh},{buyTop,sellBtm}};
   color  colors[4]={C'50,70,35',C'20,110,55',C'110,35,20',C'60,60,30'};
   for(int i=0;i<4;i++)
   {
      OTEObjectNames[i]=names[i];
      ObjectCreate(0,names[i],OBJ_RECTANGLE,0,t0,prices[i][0],t1,prices[i][1]);
      ObjectSetInteger(0,names[i],OBJPROP_COLOR,colors[i]); ObjectSetInteger(0,names[i],OBJPROP_BACK,true);
      ObjectSetInteger(0,names[i],OBJPROP_FILL,true);       ObjectSetInteger(0,names[i],OBJPROP_SELECTABLE,false);
   }
   ChartRedraw(0);
}

void DrawSwingLine(double price,bool isBuy,string source)
{
   if(!ShowSwingLines) return;
   if(SwingLineNames[SwingLineIndex]!="") ObjectDelete(0,SwingLineNames[SwingLineIndex]);
   string name="SwingLine_"+source+"_"+IntegerToString(SwingLineIndex);
   SwingLineNames[SwingLineIndex]=name;
   SwingLineIndex=(SwingLineIndex+1)%MaxSwingLines;
   ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,isBuy?clrDodgerBlue:clrOrangeRed);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH);
   ChartRedraw(0);
}

//===================================================================//
//  PANEL HELPERS                                                     //
//===================================================================//
void PanelLoadPosition()
{
   string kx=PANEL_PREFIX+"PX",ky=PANEL_PREFIX+"PY";
   if(GlobalVariableCheck(kx)) PANEL_X=(int)GlobalVariableGet(kx);
   if(GlobalVariableCheck(ky)) PANEL_Y=(int)GlobalVariableGet(ky);
}
void PanelSavePosition()
{
   GlobalVariableSet(PANEL_PREFIX+"PX",PANEL_X);
   GlobalVariableSet(PANEL_PREFIX+"PY",PANEL_Y);
}
void PanelDeleteAll(){ ObjectsDeleteAll(0,PANEL_PREFIX); Comment(""); }
void PanelDeleteBody()
{
   int total=ObjectsTotal(0);
   for(int i=total-1;i>=0;i--)
   {
      string nm=ObjectName(0,i);
      if(StringFind(nm,PANEL_PREFIX)==0&&
         nm!=PANEL_PREFIX+"Header"&&nm!=PANEL_PREFIX+"ToggleBtn"&&
         nm!=PANEL_PREFIX+"HdrBG" &&nm!=PANEL_PREFIX+"Title"&&
         nm!=PANEL_PREFIX+"Author"&&nm!=PANEL_PREFIX+"BG") ObjectDelete(0,nm);
   }
}
void PanelRect(string name,int x,int y,int w,int h,color bg,color border=clrNONE)
{
   string full=PANEL_PREFIX+name;
   if(ObjectFind(0,full)<0)
   { ObjectCreate(0,full,OBJ_RECTANGLE_LABEL,0,0,0);
     ObjectSetInteger(0,full,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,full,OBJPROP_HIDDEN,true); }
   ObjectSetInteger(0,full,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,full,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,full,OBJPROP_XSIZE,w);      ObjectSetInteger(0,full,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,full,OBJPROP_BGCOLOR,bg);   ObjectSetInteger(0,full,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,full,OBJPROP_COLOR,border==clrNONE?bg:border);
   ObjectSetInteger(0,full,OBJPROP_BACK,false);   ObjectSetInteger(0,full,OBJPROP_CORNER,CORNER_LEFT_UPPER);
}
void PanelLabel(string name,int x,int y,string text,color clr,int fontSize=8,string font="Consolas")
{
   string full=PANEL_PREFIX+name;
   if(ObjectFind(0,full)<0)
   { ObjectCreate(0,full,OBJ_LABEL,0,0,0);
     ObjectSetInteger(0,full,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,full,OBJPROP_HIDDEN,true);
     ObjectSetInteger(0,full,OBJPROP_CORNER,CORNER_LEFT_UPPER); }
   ObjectSetInteger(0,full,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,full,OBJPROP_YDISTANCE,y);
   ObjectSetString (0,full,OBJPROP_TEXT,text);    ObjectSetInteger(0,full,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,full,OBJPROP_FONTSIZE,fontSize); ObjectSetString(0,full,OBJPROP_FONT,font);
}
void PanelLabelC(string name,int y,string text,color clr,int fontSize=8,string font="Consolas")
{
   string full=PANEL_PREFIX+name;
   int cx=PANEL_X+PANEL_W/2;
   if(ObjectFind(0,full)<0)
   { ObjectCreate(0,full,OBJ_LABEL,0,0,0);
     ObjectSetInteger(0,full,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,full,OBJPROP_HIDDEN,true);
     ObjectSetInteger(0,full,OBJPROP_CORNER,CORNER_LEFT_UPPER);
     ObjectSetInteger(0,full,OBJPROP_ANCHOR,ANCHOR_UPPER); }
   ObjectSetInteger(0,full,OBJPROP_XDISTANCE,cx); ObjectSetInteger(0,full,OBJPROP_YDISTANCE,y);
   ObjectSetString (0,full,OBJPROP_TEXT,text);     ObjectSetInteger(0,full,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,full,OBJPROP_FONTSIZE,fontSize); ObjectSetString(0,full,OBJPROP_FONT,font);
}

//===================================================================//
//  DISPLAY PANEL V1.2                                                //
//===================================================================//
void UpdateDisplay()
{
   if(TimeCurrent()-LastDisplayUpdate<2) return;
   LastDisplayUpdate=TimeCurrent();

   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity =AccountInfoDouble(ACCOUNT_EQUITY);
   double pnl    =equity-balance;
   double spread =(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;
   bool   inSess =IsTradingTime();
   bool   spreadOK=IsSpreadOK();

   datetime tSrv=TimeCurrent(), tGMT=TimeGMT();
   int detectedOffset=(int)MathRound((double)(tSrv-tGMT)/3600.0);
   MqlDateTime dtSrv; TimeToStruct(tSrv,dtSrv);
   MqlDateTime dtGMT; TimeToStruct(tGMT,dtGMT);
   string srvTimeStr=StringFormat("%02d:%02d:%02d",dtSrv.hour,dtSrv.min,dtSrv.sec);
   string gmtTimeStr=StringFormat("%02d:%02d:%02d",dtGMT.hour,dtGMT.min,dtGMT.sec);
   string offsetLabel="GMT"+(detectedOffset>=0?"+":"")+IntegerToString(detectedOffset);
   bool   offsetMatch=(detectedOffset==BrokerGMTOffset);

   double fast[1],slow[1];
   string trendStr="FLAT";
   if(CopyBuffer(FastEMAHandle,0,1,1,fast)==1&&CopyBuffer(SlowEMAHandle,0,1,1,slow)==1)
      trendStr=(fast[0]>slow[0])?"BULLISH":(fast[0]<slow[0])?"BEARISH":"FLAT";

   MqlRates rates[2]; string candleStr="DOJI";
   if(CopyRates(_Symbol,PERIOD_M15,0,2,rates)==2)
      candleStr=(rates[1].close>rates[1].open)?"BULLISH":(rates[1].close<rates[1].open)?"BEARISH":"DOJI";

   bool inOTE=IsInOTEZone(SymbolInfoDouble(_Symbol,SYMBOL_BID),lastSwingHighH1,lastSwingLowH1);
   int  effFVG=GetEffectiveFVGReq();

   double curEquity=equity;
   if(curEquity>sessionPeakEquity&&sessionPeakEquity>0) sessionPeakEquity=curEquity;
   double curDD=(sessionPeakEquity>0)?sessionPeakEquity-curEquity:0;
   if(curDD>sessionMaxDrawdown) sessionMaxDrawdown=curDD;

   double wr2=(statTotalTrades>0)?(double)statWins/statTotalTrades*100.0:0;
   double avgRR2=(statWins>0)?statSumRR/statWins:0;
   double pf2=(statTotalLoss>0)?statTotalProfit/statTotalLoss:0;
   double netPnL=statTotalProfit-statTotalLoss;

   if(GlobalVariableCheck(PANEL_PREFIX+"Hidden"))
      panelHidden=(GlobalVariableGet(PANEL_PREFIX+"Hidden")>0.5);

   PanelLoadPosition();
   int x=PANEL_X,w=PANEL_W,lh=PANEL_LINE_H;
   int px=x+8,vx=px+152,rowTop=2,row=0;
   int hdrH=52,yb=PANEL_Y;

   PanelRect("BG", x,yb,w,panelHidden?hdrH:900, PANEL_BG, PANEL_BORDER);

   PanelRect  ("HdrBG",  x,yb,w,hdrH,PANEL_HDR_BG,PANEL_BORDER);
   PanelLabelC("Title",  yb+6,  EA_NAME,                      PANEL_GOLD,12);
   PanelLabelC("Author", yb+28, "Created by: RATTANA CHHORM", clrWhite,   9);
   PanelLabel ("Header",   px,   yb+4,"[drag]",C'50,50,70',7);
   ObjectSetInteger(0,PANEL_PREFIX+"Header",   OBJPROP_SELECTABLE,true);
   PanelLabel ("ToggleBtn",x+w-50,yb+4,panelHidden?"[show]":"[hide]",PANEL_BLUE,8);
   ObjectSetInteger(0,PANEL_PREFIX+"ToggleBtn",OBJPROP_SELECTABLE,true);

   if(panelHidden){ ChartRedraw(0); return; }

   int y=yb+hdrH;
   PanelRect  ("HdrBG", x,yb,w,hdrH,PANEL_HDR_BG,PANEL_BORDER);
   PanelLabelC("Title", yb+6, EA_NAME,                      PANEL_GOLD,12);
   PanelLabelC("Author",yb+28,"Created by: RATTANA CHHORM", clrWhite,   9);
   PanelLabel ("ToggleBtn",x+w-50,yb+4,"[hide]",PANEL_BLUE,8);
   PanelLabel ("Header",   px,   yb+4,"[drag]",C'50,50,70',7);

   row=0;

   // Account
   PanelLabel("BalL",px,y+row*lh+rowTop,"Balance  :",PANEL_TXT);
   PanelLabel("BalV",vx,y+row*lh+rowTop,"$"+DoubleToString(balance,2),PANEL_GREEN); row++;
   color eqClr=pnl>=0?PANEL_GREEN:PANEL_RED;
   PanelLabel("EqL", px,y+row*lh+rowTop,"Equity   :",PANEL_TXT);
   PanelLabel("EqV", vx,y+row*lh+rowTop,"$"+DoubleToString(equity,2)+"  (P/L:$"+DoubleToString(pnl,2)+")",eqClr); row++;

   // Broker time
   PanelLabel("BkHd",px,y+row*lh+rowTop,"BROKER TIME:",PANEL_GOLD); row++;
   PanelLabel("BkSl",px,y+row*lh+rowTop,"Server Time:",PANEL_TXT);
   PanelLabel("BkSv",vx,y+row*lh+rowTop,srvTimeStr,PANEL_TXT); row++;
   PanelLabel("BkGl",px,y+row*lh+rowTop,"GMT Time   :",PANEL_TXT);
   PanelLabel("BkGv",vx,y+row*lh+rowTop,gmtTimeStr,PANEL_TXT); row++;
   PanelLabel("BkOl",px,y+row*lh+rowTop,"GMT Offset :",PANEL_TXT);
   string offDisp=offsetLabel+(offsetMatch?"":" [input:"+IntegerToString(BrokerGMTOffset)+"]");
   PanelLabel("BkOv",vx,y+row*lh+rowTop,offDisp,offsetMatch?PANEL_GOLD:PANEL_RED); row++;

   PanelLabel("SeL",px,y+row*lh+rowTop,"Session  :",PANEL_TXT);
   PanelLabel("SeV",vx,y+row*lh+rowTop,inSess?"ACTIVE":"CLOSED",inSess?PANEL_GREEN:PANEL_RED); row++;
   PanelLabel("TrL",px,y+row*lh+rowTop,"Trend    :",PANEL_TXT);
   color tClr=trendStr=="BULLISH"?PANEL_GREEN:trendStr=="BEARISH"?PANEL_RED:PANEL_TXT;
   PanelLabel("TrV",vx,y+row*lh+rowTop,trendStr,tClr); row++;
   PanelLabel("CnL",px,y+row*lh+rowTop,"Candle   :",PANEL_TXT);
   color cClr=candleStr=="BULLISH"?PANEL_GREEN:candleStr=="BEARISH"?PANEL_RED:PANEL_TXT;
   PanelLabel("CnV",vx,y+row*lh+rowTop,candleStr,cClr); row++;
   PanelLabel("SpL",px,y+row*lh+rowTop,"Spread   :",PANEL_TXT);
   PanelLabel("SpV",vx,y+row*lh+rowTop,DoubleToString(spread,0)+" pts "+(spreadOK?"OK":"BLOCKED"),spreadOK?PANEL_GREEN:PANEL_RED); row++;
   PanelLabel("TdL",px,y+row*lh+rowTop,"Trades   :",PANEL_TXT);
   PanelLabel("TdV",vx,y+row*lh+rowTop,IntegerToString(TodayTradeCount)+"/"+IntegerToString(MaxTradesPerDay),PANEL_TXT); row++;
   bool dlimitHit=(MaxDailyLossTrades>0&&TodayLossTrades>=MaxDailyLossTrades);
   PanelLabel("DLl",px,y+row*lh+rowTop,"Day Loss :",PANEL_TXT);
   PanelLabel("DLv",vx,y+row*lh+rowTop,IntegerToString(TodayLossTrades)+"/"+IntegerToString(MaxDailyLossTrades)+(dlimitHit?" HALTED":""),dlimitHit?PANEL_RED:PANEL_TXT); row++;
   PanelLabel("CLl",px,y+row*lh+rowTop,"ConLoss  :",PANEL_TXT);
   PanelLabel("CLv",vx,y+row*lh+rowTop,IntegerToString(consecutiveLosses)+"/"+IntegerToString(MaxConsecutiveLosses),consecutiveLosses>5?PANEL_RED:PANEL_TXT); row++;
   PanelLabel("WSl",px,y+row*lh+rowTop,"WinStreak:",PANEL_TXT);
   PanelLabel("WSv",vx,y+row*lh+rowTop,IntegerToString(consecutiveWins),consecutiveWins>0?PANEL_GREEN:PANEL_TXT); row++;

   // ICT Sequence
   PanelLabel("SeqH",px,y+row*lh+rowTop,"ICT SMC V1.2 SEQUENCE:",PANEL_GOLD); row++;

   string s1v=!HTFLevelRequired?"DISABLED":(htfLevelReached?"PASS":"WAIT");
   color  s1c=!HTFLevelRequired?PANEL_GOLD:(htfLevelReached?PANEL_GREEN:PANEL_TXT);
   PanelLabel("S1l",px,y+row*lh+rowTop,"[1] HTF Level :",PANEL_TXT);
   PanelLabel("S1v",vx,y+row*lh+rowTop,s1v,s1c); row++;

   string s2label=effUseMSSFilter?"[2] MSS H1    :":"[2] 5M CISD   :";
   string s2v=mssConfirmed?"CONFIRMED ("+(mssIsBullish?"BULL":"BEAR")+")":"waiting...";
   PanelLabel("S2l",px,y+row*lh+rowTop,s2label,PANEL_TXT);
   PanelLabel("S2v",vx,y+row*lh+rowTop,s2v,mssConfirmed?PANEL_GREEN:PANEL_TXT); row++;

   string s3v=!effUseBOSFilter?"OFF":(bosConfirmed?"CONFIRMED ("+(bosIsBullish?"BULL":"BEAR")+")":"waiting...");
   color  s3c=!effUseBOSFilter?PANEL_GOLD:(bosConfirmed?PANEL_GREEN:PANEL_TXT);
   PanelLabel("S3l",px,y+row*lh+rowTop,"[3] BOS M15   :",PANEL_TXT);
   PanelLabel("S3v",vx,y+row*lh+rowTop,s3v,s3c); row++;

   string s4v=!effRequireLiqSweep?"OFF":(liquiditySweepDone?"DONE ("+(sweepIsBullish?"BULL":"BEAR")+")":"waiting...");
   color  s4c=!effRequireLiqSweep?PANEL_GOLD:(liquiditySweepDone?PANEL_GREEN:PANEL_TXT);
   PanelLabel("S4l",px,y+row*lh+rowTop,"[4] Liquidity :",PANEL_TXT);
   PanelLabel("S4v",vx,y+row*lh+rowTop,s4v,s4c); row++;

   string s5v=IntegerToString(fvgCount1Min)+"/"+IntegerToString(effFVG)+(RelaxedMode?" (R)":"");
   PanelLabel("S5l",px,y+row*lh+rowTop,"[5] 1M FVGs   :",PANEL_TXT);
   PanelLabel("S5v",vx,y+row*lh+rowTop,s5v,(fvgCount1Min>=effFVG||effFVG==0)?PANEL_GREEN:PANEL_TXT); row++;

   PanelLabel("S6l",px,y+row*lh+rowTop,"[6] H1 Swings :",PANEL_TXT);
   PanelLabel("S6v",vx,y+row*lh+rowTop,lastSwingHighH1>0?"PASS":"WAIT",lastSwingHighH1>0?PANEL_GREEN:PANEL_TXT); row++;

   bool m15ok=lastSwingHighM15>0||lastSwingLowM15>0;
   PanelLabel("S7l",px,y+row*lh+rowTop,"[7] M15 Swings:",PANEL_TXT);
   PanelLabel("S7v",vx,y+row*lh+rowTop,m15ok?"PASS":"ATR FB",m15ok?PANEL_GREEN:PANEL_GOLD); row++;

   PanelLabel("SvH",px,y+row*lh+rowTop,"-- LIVE ENTRY --",C'80,80,100'); row++;

   PanelLabel("SOl",px,y+row*lh+rowTop,"[★] OTE Zone  :",PANEL_TXT);
   PanelLabel("SOv",vx,y+row*lh+rowTop,inOTE?"PASS":"WAIT",inOTE?PANEL_GREEN:PANEL_TXT); row++;

   string s9v=cisd1MinConfirmed?"READY ("+(cisd1MinIsBearish?"BEAR":"BULL")+")":"waiting...";
   PanelLabel("S9l",px,y+row*lh+rowTop,"[★] 1M Trigger:",PANEL_TXT);
   PanelLabel("S9v",vx,y+row*lh+rowTop,s9v,cisd1MinConfirmed?PANEL_GREEN:PANEL_TXT); row++;

   string sdirV=(mssConfirmed&&cisd1MinConfirmed)?(mssIsBullish==!cisd1MinIsBearish?"AGREE":"CONFLICT"):"WAIT";
   PanelLabel("SDl",px,y+row*lh+rowTop,"[★] Direction :",PANEL_TXT);
   PanelLabel("SDv",vx,y+row*lh+rowTop,sdirV,sdirV=="AGREE"?PANEL_GREEN:sdirV=="CONFLICT"?PANEL_RED:PANEL_TXT); row++;

   string scoreStr=IntegerToString(lastTradeScore)+"/100 (min "+(UseTradeScore?IntegerToString(effMinScore):"OFF")+")";
   color scoreClr=(UseTradeScore&&lastTradeScore<effMinScore)?PANEL_RED:(lastTradeScore>0?PANEL_GREEN:PANEL_TXT);
   PanelLabel("SCl",px,y+row*lh+rowTop,"[★] Score     :",PANEL_TXT);
   PanelLabel("SCv",vx,y+row*lh+rowTop,scoreStr,scoreClr); row++;

   string trendFilter=effUseDailyTrend?"ON":"OFF";
   PanelLabel("TFl",px,y+row*lh+rowTop,"[★] D1 Trend  :",PANEL_TXT);
   PanelLabel("TFv",vx,y+row*lh+rowTop,trendFilter,effUseDailyTrend?PANEL_TXT:PANEL_GOLD); row++;

   if(UseNewsFilter)
   { PanelLabel("NWl",px,y+row*lh+rowTop,"News Filter:",PANEL_TXT);
     PanelLabel("NWv",vx,y+row*lh+rowTop,newsBlocked?"BLOCKED":"CLEAR",newsBlocked?PANEL_RED:PANEL_GREEN); row++; }

   string lbv=lastFailedStep>0?"STEP "+IntegerToString(lastFailedStep)+" — "+lastFailedStepDesc:"None";
   PanelLabel("LBl",px,y+row*lh+rowTop,"Last Block   :",PANEL_TXT);
   PanelLabel("LBv",vx,y+row*lh+rowTop,lbv,lastFailedStep>0?PANEL_GOLD:PANEL_GREEN); row++;

   // V1.2: Filter Rejection Statistics
   PanelLabel("FRH",px,y+row*lh+rowTop,"FILTER REJECTIONS (today):",PANEL_GOLD); row++;
   color hi=PANEL_RED, lo=PANEL_TXT;
   string rejBar = "HTF:"+IntegerToString(rejHTFLevel)
                  +" MSS:"+IntegerToString(rejMSS)
                  +" BOS:"+IntegerToString(rejBOS)
                  +" Swp:"+IntegerToString(rejSweep);
   PanelLabel("FR1v",px,y+row*lh+rowTop,rejBar,PANEL_BLUE); row++;
   string rejBar2= "FVG:"+IntegerToString(rejFVG)
                  +" H1R:"+IntegerToString(rejH1Range)
                  +" OTE:"+IntegerToString(rejOTE)
                  +" 1MT:"+IntegerToString(rej1MTrig);
   PanelLabel("FR2v",px,y+row*lh+rowTop,rejBar2,PANEL_BLUE); row++;
   string rejBar3= "Scr:"+IntegerToString(rejScore)
                  +" Trd:"+IntegerToString(rejTrend)
                  +" SMT:"+IntegerToString(rejSMT)
                  +" Nws:"+IntegerToString(rejNews);
   PanelLabel("FR3v",px,y+row*lh+rowTop,rejBar3,PANEL_BLUE); row++;
   PanelLabel("FRTl",px,y+row*lh+rowTop,"Total blocked:",PANEL_TXT);
   PanelLabel("FRTv",vx,y+row*lh+rowTop,IntegerToString(rejTotal)+" bars",rejTotal>10?PANEL_GOLD:PANEL_TXT); row++;

   // Swings
   PanelLabel("SwH",px,y+row*lh+rowTop,"SWINGS:",PANEL_GOLD); row++;
   PanelLabel("H1l",px,y+row*lh+rowTop,"H1 :",PANEL_TXT);
   PanelLabel("H1v",px+40,y+row*lh+rowTop,"H="+DoubleToString(lastSwingHighH1,_Digits)+"  L="+DoubleToString(lastSwingLowH1,_Digits),PANEL_BLUE); row++;
   PanelLabel("M1l",px,y+row*lh+rowTop,"M15:",PANEL_TXT);
   PanelLabel("M1v",px+40,y+row*lh+rowTop,"H="+DoubleToString(lastSwingHighM15,_Digits)+"  L="+DoubleToString(lastSwingLowM15,_Digits),PANEL_BLUE); row++;

   // Sessions
   PanelLabel("SsH",px,y+row*lh+rowTop,"SESSIONS:",PANEL_GOLD); row++;
   if(SessionLondon)   { bool a=SessionActiveNow("London");  PanelLabel("SsLl",px,y+row*lh+rowTop,"London  :",PANEL_TXT); PanelLabel("SsLv",vx,y+row*lh+rowTop,"(08-17) "+(a?"ACTIVE":"CLOSED"),a?PANEL_GREEN:PANEL_RED); row++; }
   if(SessionNewYork)  { bool a=SessionActiveNow("NewYork"); PanelLabel("SsNl",px,y+row*lh+rowTop,"New York:",PANEL_TXT); PanelLabel("SsNv",vx,y+row*lh+rowTop,"(13-22) "+(a?"ACTIVE":"CLOSED"),a?PANEL_GREEN:PANEL_RED); row++; }
   if(OverlapLondonNY) { bool a=SessionActiveNow("Overlap"); PanelLabel("SsOl",px,y+row*lh+rowTop,"LDN+NY  :",PANEL_TXT); PanelLabel("SsOv",vx,y+row*lh+rowTop,"(13-17) "+(a?"ACTIVE BEST":"CLOSED"),a?PANEL_GREEN:PANEL_RED); row++; }
   if(SessionTokyo)    { bool a=SessionActiveNow("Tokyo");   PanelLabel("SsTl",px,y+row*lh+rowTop,"Tokyo   :",PANEL_TXT); PanelLabel("SsTv",vx,y+row*lh+rowTop,"(00-09) "+(a?"ACTIVE":"CLOSED"),a?PANEL_GREEN:PANEL_RED); row++; }
   if(SessionSydney)   { bool a=SessionActiveNow("Sydney");  PanelLabel("SsYl",px,y+row*lh+rowTop,"Sydney  :",PANEL_TXT); PanelLabel("SsYv",vx,y+row*lh+rowTop,"(22-07) "+(a?"ACTIVE":"CLOSED"),a?PANEL_GREEN:PANEL_RED); row++; }
   PanelLabel("FLl",px,y+row*lh+rowTop,"Entry Hours:",PANEL_TXT);
   PanelLabel("FLv",vx,y+row*lh+rowTop,effBestHoursOnly?"08:30-15:00 GMT":"(all session)",PANEL_GOLD); row++;
   PanelLabel("FPl",px,y+row*lh+rowTop,"Fri Cutoff :",PANEL_TXT);
   PanelLabel("FPv",vx,y+row*lh+rowTop,CloseOnFriday?(IntegerToString(FridayCloseHour)+":00 GMT"):"OFF",CloseOnFriday?PANEL_GOLD:PANEL_TXT); row++;

   // Statistics
   PanelLabel("StH",px,y+row*lh+rowTop,"STATISTICS:",PANEL_GOLD); row++;
   string trv=IntegerToString(statTotalTrades)+" (W:"+IntegerToString(statWins)+" L:"+IntegerToString(statLosses)+")";
   PanelLabel("StTl",px,y+row*lh+rowTop,"Trades  :",PANEL_TXT); PanelLabel("StTv",vx,y+row*lh+rowTop,trv,PANEL_TXT); row++;
   PanelLabel("WRl", px,y+row*lh+rowTop,"Win Rate:",PANEL_TXT); PanelLabel("WRv",vx,y+row*lh+rowTop,DoubleToString(wr2,1)+"%",wr2>=55?PANEL_GREEN:wr2>=40?PANEL_GOLD:PANEL_RED); row++;
   PanelLabel("ARl", px,y+row*lh+rowTop,"Avg RR  :",PANEL_TXT); PanelLabel("ARv",vx,y+row*lh+rowTop,DoubleToString(avgRR2,2),avgRR2>=1.5?PANEL_GREEN:PANEL_TXT); row++;
   PanelLabel("PFl", px,y+row*lh+rowTop,"Profit F:",PANEL_TXT); PanelLabel("PFv",vx,y+row*lh+rowTop,DoubleToString(pf2,2),pf2>=1.5?PANEL_GREEN:pf2>=1.0?PANEL_GOLD:PANEL_RED); row++;
   PanelLabel("NPl", px,y+row*lh+rowTop,"Net P&L :",PANEL_TXT); PanelLabel("NPv",vx,y+row*lh+rowTop,"$"+DoubleToString(netPnL,2),netPnL>=0?PANEL_GREEN:PANEL_RED); row++;

   // Drawdown
   PanelLabel("DDH",px,y+row*lh+rowTop,"DRAWDOWN:",PANEL_GOLD); row++;
   PanelLabel("DCl",px,y+row*lh+rowTop,"Current :",PANEL_TXT); PanelLabel("DCv",vx,y+row*lh+rowTop,"$"+DoubleToString(curDD,2),curDD>0?PANEL_RED:PANEL_GREEN); row++;
   PanelLabel("DMl",px,y+row*lh+rowTop,"Sess Max:",PANEL_TXT); PanelLabel("DMv",vx,y+row*lh+rowTop,"$"+DoubleToString(sessionMaxDrawdown,2),PANEL_TXT); row++;

   // Config
   PanelLabel("RkL",px,y+row*lh+rowTop,"Risk Mode  :",PANEL_TXT); PanelLabel("RkV",vx,y+row*lh+rowTop,EnumToString(RiskMode)+" "+DoubleToString(effRiskPct,2)+"%",PANEL_GOLD); row++;
   PanelLabel("TpL",px,y+row*lh+rowTop,"TP Mode    :",PANEL_TXT); PanelLabel("TpV",vx,y+row*lh+rowTop,EnumToString(TPMode),PANEL_GOLD); row++;
   // V1.2: Show active trading style
   string styleStr=EnumToString(TradingStyle);
   color  styleClr=TradingStyle==STYLE_ULTRA_ACTIVE?PANEL_RED:TradingStyle==STYLE_AGGRESSIVE?PANEL_GOLD:PANEL_GREEN;
   PanelLabel("TSl",px,y+row*lh+rowTop,"Style      :",PANEL_TXT); PanelLabel("TSv",vx,y+row*lh+rowTop,styleStr,styleClr); row++;
   PanelLabel("CDl",px,y+row*lh+rowTop,"Cooldown   :",PANEL_TXT); PanelLabel("CDv",vx,y+row*lh+rowTop,IntegerToString(effCooldown)+"m",PANEL_GOLD); row++;
   PanelLabel("OTl",px,y+row*lh+rowTop,"OTE Range  :",PANEL_TXT); PanelLabel("OTv",vx,y+row*lh+rowTop,DoubleToString(effOTEMin*100,0)+"%-"+DoubleToString(effOTEMax*100,0)+"%",PANEL_GOLD); row++;
   PanelLabel("MSl",px,y+row*lh+rowTop,"Max SL Pips:",PANEL_TXT); PanelLabel("MSv",vx,y+row*lh+rowTop,IntegerToString(effMaxSLPips)+" pips",PANEL_GOLD); row++;
   bool ptpOn=UsePartialTP; PanelLabel("PTl",px,y+row*lh+rowTop,"Partial TP :",PANEL_TXT); PanelLabel("PTv",vx,y+row*lh+rowTop,ptpOn?"ON ("+DoubleToString(PartialClosePercent,0)+"% at "+DoubleToString(PartialCloseRR,1)+"R)":"OFF",ptpOn?PANEL_GREEN:PANEL_TXT); row++;
   PanelLabel("FTl",px,y+row*lh+rowTop,"ForceTrades:",PANEL_TXT); PanelLabel("FTv",vx,y+row*lh+rowTop,ForceTrades?"ON (TEST)":"OFF",ForceTrades?PANEL_RED:PANEL_GREEN); row++;
   PanelLabel("RMl",px,y+row*lh+rowTop,"RelaxedMode:",PANEL_TXT); PanelLabel("RMv",vx,y+row*lh+rowTop,RelaxedMode?"ON (TEST)":"OFF",RelaxedMode?PANEL_GOLD:PANEL_GREEN); row++;

   int finalH=(y-yb)+row*lh+rowTop+8;
   ObjectSetInteger(0,PANEL_PREFIX+"BG",OBJPROP_YSIZE,finalH);
   ChartRedraw(0);
}

//===================================================================//
//  CHART EVENT                                                       //
//===================================================================//
void OnChartEvent(const int id,const long& lparam,const double& dparam,const string& sparam)
{
   if(id==CHARTEVENT_OBJECT_CLICK&&sparam==PANEL_PREFIX+"ToggleBtn")
   {
      panelHidden=!panelHidden;
      GlobalVariableSet(PANEL_PREFIX+"Hidden",panelHidden?1:0);
      if(panelHidden) PanelDeleteBody();
      LastDisplayUpdate=0; UpdateDisplay(); return;
   }
   if(id==CHARTEVENT_OBJECT_CLICK&&sparam==PANEL_PREFIX+"Header")
   { panelDragging=true; dragOffsetX=(int)lparam-PANEL_X; dragOffsetY=(int)dparam-PANEL_Y; }
   if(id==CHARTEVENT_MOUSE_MOVE&&panelDragging)
   {
      PANEL_X=(int)lparam-dragOffsetX; PANEL_Y=(int)dparam-dragOffsetY;
      int cW=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
      int cH=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
      PANEL_X=MathMax(0,MathMin(cW-PANEL_W,PANEL_X));
      PANEL_Y=MathMax(0,MathMin(cH-50,PANEL_Y));
      LastDisplayUpdate=0; UpdateDisplay();
   }
   if(id==CHARTEVENT_MOUSE_MOVE&&panelDragging&&dparam==0)
   { panelDragging=false; PanelSavePosition(); }
   if(id==CHARTEVENT_CLICK&&panelDragging)
   { panelDragging=false; PanelSavePosition(); }
}

//===================================================================//
//  INITIALIZATION                                                    //
//===================================================================//
int OnInit()
{
   ApplySymbolPreset();         // sets effOTEMin/Max, effMaxSLPips, effMinSLPips
   ApplyOptimizationMode();     // sets base effMinScore, effRiskPct
   ApplyTradingStyle();         // V1.2: overrides with style-specific values

   ATRHandle     = iATR(_Symbol,PERIOD_M15,14);
   FastEMAHandle = iMA (_Symbol,PERIOD_H1,50, 0,MODE_EMA,PRICE_CLOSE);
   SlowEMAHandle = iMA (_Symbol,PERIOD_H1,200,0,MODE_EMA,PRICE_CLOSE);

   if(ATRHandle==INVALID_HANDLE||FastEMAHandle==INVALID_HANDLE||SlowEMAHandle==INVALID_HANDLE)
   { Alert(EA_NAME+": Indicator handle failed. EA stopped."); return INIT_FAILED; }

   trade.SetExpertMagicNumber(MAGIC_NUMBER);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(_Symbol);

   if     (_Digits==5||_Digits==3) PipFactor=10.0;
   else if(_Digits==2)             PipFactor=100.0;
   else                            PipFactor=1.0;

   ArrayResize(SwingLineNames,MaxSwingLines);
   for(int i=0;i<MaxSwingLines;i++) SwingLineNames[i]="";
   for(int i=0;i<4;i++) OTEObjectNames[i]="";

   Print("========================================");
   Print(EA_NAME," — ICT SMART MONEY CONCEPTS V1.2");
   Print("Symbol: ",_Symbol," | Digits: ",_Digits," | PipFactor: ",PipFactor);
   Print("TradingStyle: ",EnumToString(TradingStyle));
   Print("effOTEMin=",effOTEMin," effOTEMax=",effOTEMax);
   Print("effMinScore=",effMinScore," effRiskPct=",effRiskPct,"% effCooldown=",effCooldown,"m");
   Print("effUseMSS=",effUseMSSFilter," effUseBOS=",effUseBOSFilter," effUseTrend=",effUseDailyTrend);
   Print("effBestHours=",effBestHoursOnly," effH1Range=",effUseH1RangeFilter,"(",effMinH1Range,"pips)");
   Print("UseTradeScore=",UseTradeScore);
   if(ForceTrades) Print("*** WARNING: ForceTrades=ON ***");
   if(RelaxedMode) Print("*** RELAXED MODE ON ***");
   Print("========================================");

   string pfx=EA_NAME+"_"+_Symbol+"_";
   if(GlobalVariableCheck(pfx+"Trades")) statTotalTrades=(int)GlobalVariableGet(pfx+"Trades");
   if(GlobalVariableCheck(pfx+"Wins"))   statWins       =(int)GlobalVariableGet(pfx+"Wins");
   if(GlobalVariableCheck(pfx+"Losses")) statLosses     =(int)GlobalVariableGet(pfx+"Losses");
   if(GlobalVariableCheck(pfx+"Profit")) statTotalProfit=GlobalVariableGet(pfx+"Profit");
   if(GlobalVariableCheck(pfx+"Loss"))   statTotalLoss  =GlobalVariableGet(pfx+"Loss");
   if(GlobalVariableCheck(pfx+"SumRR"))  statSumRR      =GlobalVariableGet(pfx+"SumRR");

   sessionStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   sessionPeakEquity =sessionStartEquity;
   PanelLoadPosition();
   return INIT_SUCCEEDED;
}

//===================================================================//
//  DEINITIALIZATION                                                  //
//===================================================================//
void OnDeinit(const int reason)
{
   if(ATRHandle    !=INVALID_HANDLE) IndicatorRelease(ATRHandle);
   if(FastEMAHandle!=INVALID_HANDLE) IndicatorRelease(FastEMAHandle);
   if(SlowEMAHandle!=INVALID_HANDLE) IndicatorRelease(SlowEMAHandle);

   for(int i=0;i<MaxSwingLines;i++) if(SwingLineNames[i]!="") ObjectDelete(0,SwingLineNames[i]);
   for(int i=0;i<4;i++) if(OTEObjectNames[i]!="") ObjectDelete(0,OTEObjectNames[i]);

   string pfx=EA_NAME+"_"+_Symbol+"_";
   GlobalVariableSet(pfx+"Trades",statTotalTrades); GlobalVariableSet(pfx+"Wins",  statWins);
   GlobalVariableSet(pfx+"Losses",statLosses);       GlobalVariableSet(pfx+"Profit",statTotalProfit);
   GlobalVariableSet(pfx+"Loss",  statTotalLoss);    GlobalVariableSet(pfx+"SumRR", statSumRR);

   PanelDeleteAll();
   ObjectsDeleteAll(0,"Twins_"); ObjectsDeleteAll(0,"OTEZO_");
   Comment("");
}

//===================================================================//
//  TRADE CLOSED — statistics                                         //
//===================================================================//
void OnTrade()
{
   if(!HistorySelect(TimeCurrent()-86400,TimeCurrent())) return;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetString (ticket,DEAL_SYMBOL)!=_Symbol)       continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC) !=MAGIC_NUMBER)  continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY) !=DEAL_ENTRY_OUT) continue;

      static ulong lastProcessed=0;
      if(ticket==lastProcessed) break;
      lastProcessed=ticket;

      double profit=HistoryDealGetDouble(ticket,DEAL_PROFIT);
      statTotalTrades++;
      statTotalProfit+=(profit>0)?profit:0;
      statTotalLoss  +=(profit<0)?MathAbs(profit):0;

      ulong posID=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
      string rrKey="TWINS_RR_"+IntegerToString(posID);
      string ptlKey="TWINS_PTL_"+IntegerToString(posID);

      if(profit>0)
      { statWins++; consecutiveLosses=0; consecutiveWins++;
        if(GlobalVariableCheck(rrKey)){statSumRR+=GlobalVariableGet(rrKey);GlobalVariableDel(rrKey);} }
      else if(profit<0)
      { statLosses++; consecutiveLosses++; consecutiveWins=0; TodayLossTrades++;
        if(GlobalVariableCheck(rrKey)) GlobalVariableDel(rrKey); }

      if(GlobalVariableCheck(ptlKey)) GlobalVariableDel(ptlKey);

      LastTradeCloseTime=TimeCurrent();
      cisd5MinConfirmed=false; cisd1MinConfirmed=false;
      mssConfirmed=false; bosConfirmed=false; liquiditySweepDone=false;
      htfLevelReached=false; fvgCount1Min=-1;

      bool dealBuy=(HistoryDealGetInteger(ticket,DEAL_TYPE)==DEAL_TYPE_BUY);
      double closePrice=HistoryDealGetDouble(ticket,DEAL_PRICE);
      double closeVol  =HistoryDealGetDouble(ticket,DEAL_VOLUME);
      WriteCSVLog("CLOSE",posID,dealBuy,closePrice,0,0,closeVol,profit,lastTradeScore,profit>=0?"WIN":"LOSS");
      TakeScreenshot(profit>=0?"WIN_CLOSE":"LOSS_CLOSE");

      double curEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      if(curEquity>sessionPeakEquity) sessionPeakEquity=curEquity;
      double dd=sessionPeakEquity-curEquity;
      if(dd>sessionMaxDrawdown) sessionMaxDrawdown=dd;

      string pfx=EA_NAME+"_"+_Symbol+"_";
      GlobalVariableSet(pfx+"Trades",statTotalTrades); GlobalVariableSet(pfx+"Wins",  statWins);
      GlobalVariableSet(pfx+"Losses",statLosses);       GlobalVariableSet(pfx+"Profit",statTotalProfit);
      GlobalVariableSet(pfx+"Loss",  statTotalLoss);    GlobalVariableSet(pfx+"SumRR", statSumRR);
      break;
   }
}

//===================================================================//
//  MAIN TICK ENGINE                                                  //
//===================================================================//
void OnTick()
{
   UpdateDisplay();
   CheckFridayClose();
   CheckPartialTP();
   ApplyBreakeven();
   ApplyTrailingStop();

   if(ForceTrades)
   {
      static datetime lastForce=0;
      if(TimeCurrent()-lastForce>=60&&CanTrade())
      { lastForce=TimeCurrent(); PlaceTrade(); }
      return;
   }

   if(!CanTrade())      return;
   if(!IsTradingTime()) return;

   datetime barTime[1];
   if(CopyTime(_Symbol,PERIOD_M15,0,1,barTime)!=1) return;

   if(effCooldown>0&&LastTradeCloseTime>0&&
      TimeCurrent()-LastTradeCloseTime<(datetime)(effCooldown*60)) return;

   if(barTime[0]!=LastBarTime)
   { LastBarTime=barTime[0]; cisd1MinConfirmed=false; UpdateContextState(); }

   bool isBuy=true;
   if(CheckTwinsSequence(isBuy)) PlaceTrade(isBuy);
}
//+------------------------------------------------------------------+

