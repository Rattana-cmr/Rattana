//+------------------------------------------------------------------+
//|                                          ICT SMC EA V1.5          |
//|          ICT SMART MONEY CONCEPTS — FULL MODEL V1.5              |
//|  BUG FIXES · BETTER MATH · DEALING RANGE · H4 EMA CACHE          |
//|                Created By — RATTANA CHHORM                        |
//+------------------------------------------------------------------+
// V1.3 UPGRADE — Better algorithms, not disabled filters
// [23] STYLE_SMART_ACTIVE: MSS+BOS+Trend all ON, relaxed detection
// [24] DetectMSS: effMSSConfirm(2), current-bar check, displacement candle
// [25] DetectBOS: effBOSConf(2), current-bar check, displacement candle
// [26] IsCISD1M: pin-bar + 3-bar momentum + effBodyThresh(0.60)
// [27] IsCISD5M: effBodyThresh adaptive
// [28] H1 Range: ATR-adaptive (effUseATRRange + effMinRangeATR)
// [29] PrintFilterSummary() — cumulative report printed on deinit
// [30] Cumulative rejection counters (never reset, full backtest view)
// V1.4 UPGRADE — STYLE_SMART_ACTIVE_PLUS
// [31] STYLE_SMART_ACTIVE_PLUS: all ICT ON, OTE 55-90%, score 45
//      MSS/BOS confirm 1 bar, cooldown 5 min, BestHoursOnly OFF
//      Target: 15–25 trades/day across all active sessions
// V1.5 UPGRADES — Bug Fixes + Better Math
// [32] FIX: H4 EMA handle cached in OnInit (was leaked every tick)
// [33] FIX: DetectLiquiditySweep uses swing-based pools (was range extremes)
// [34] FIX: CalculateTradeScore — no free points for disabled filters
// [35] FIX: PartialTP default 35% at 1.5R (was 50% at 1R — negative EV)
// [36] FIX: UpdateDailyCounters preserves MSS/BOS/structural state
// [37] FIX: UltraActive OTE 55-90% (was 40-95%), effMinScore=0
// [38] NEW: CheckDealingRange — buys in discount, sells in premium (optional)
//+------------------------------------------------------------------+
#property copyright "RATTANA CHHORM"
#property version   "1.5"
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//===================================================================//
enum ENUM_RISK_MODE  { RISK_FIXED_PCT=0, RISK_FIXED_LOT=1, RISK_DYNAMIC_EQ=2 };
enum ENUM_TP_MODE    { TP_FIXED_RR=0,   TP_ATR=1,         TP_HYBRID=2       };
enum ENUM_OPT_MODE   { OPT_CONSERVATIVE=0, OPT_BALANCED=1, OPT_AGGRESSIVE=2 };
enum ENUM_SYMBOL_PRESET { PRESET_AUTO=0, PRESET_XAUUSD=1, PRESET_BTCUSD=2, PRESET_EURUSD=3, PRESET_GBPUSD=4 };
enum ENUM_TRADING_STYLE
{
   STYLE_CONSERVATIVE = 0, // Conservative: all filters strict, score 80
   STYLE_BALANCED     = 1, // Balanced: respects input toggles, score 70
   STYLE_AGGRESSIVE   = 2, // Aggressive: MSS/Trend off, wider OTE, score 50
   STYLE_SMART_ACTIVE      = 3, // Smart Active: all ICT ON, better detection, score 55
   STYLE_SMART_ACTIVE_PLUS = 4, // Smart Active+: all ICT ON, OTE 55-90%, score 45, 15-25/day [NEW]
   STYLE_ULTRA_ACTIVE      = 5  // Ultra Active: filters minimal, max frequency
};

//===================================================================//
const int    MAGIC_NUMBER = 888777;
const string EA_NAME      = "ICT SMC EA V1.5";

//===================================================================//
//  INPUTS
//===================================================================//
input group "========== TRADING STYLE =========="
input ENUM_TRADING_STYLE TradingStyle = STYLE_SMART_ACTIVE;

input group "========== RISK MANAGEMENT =========="
input ENUM_RISK_MODE RiskMode      = RISK_FIXED_PCT;
input double RiskPercent           = 0.5;
input double FixedLot              = 0.0;
input double MaxDailyLossPercent   = 10.0;
input int    MaxTradesPerDay       = 25;
input double RewardRiskRatio       = 2.0;
input double MaxLotLimit           = 0.10;
input double MinRewardRiskRatio    = 2.0;

input group "========== TAKE PROFIT MODE =========="
input ENUM_TP_MODE TPMode          = TP_FIXED_RR;
input double ATRMultiplierTP       = 3.0;

input group "========== PARTIAL TAKE PROFIT =========="
input bool   UsePartialTP          = true;
input double PartialClosePercent   = 35.0;   // [V1.5] 35% (was 50% — 50%@1R has negative EV)
input double PartialCloseRR        = 1.5;    // [V1.5] 1.5R (was 1.0R)

input group "========== TRADE FILTERS =========="
input bool   UseTimeFilter         = true;
input int    MaxSpreadPoints       = 80;
input int    MinStopDistance       = 20;
input int    MaxConsecutiveLosses  = 10;
input int    MaxDailyLossTrades    = 3;
input bool   ResetLossStreakDaily  = true;

input group "========== ICT STRUCTURE FILTERS =========="
input bool   UseMSSFilter          = true;
input bool   UseBOSFilter          = true;
input bool   RequireLiquiditySweep = false;
input bool   UseSMTFilter          = false;
input string SMTSymbol             = "XAGUSD";
input bool   UseDealingRange       = false;  // [V1.5] Buy in discount only / Sell in premium only

input group "========== NEWS FILTER =========="
input bool   UseNewsFilter         = false;
input int    NewsBlockBeforeMin    = 30;
input int    NewsBlockAfterMin     = 30;

input group "========== TRADE QUALITY SCORE =========="
input bool   UseTradeScore         = true;
input int    MinimumTradeScore     = 70;

input group "========== SESSIONS (GMT TIME) =========="
input bool   AutoDetectGMT         = true;
input int    BrokerGMTOffset       = 0;
input bool   SessionSydney         = false;
input bool   SessionTokyo          = false;
input bool   SessionLondon         = true;
input bool   SessionNewYork        = true;
input bool   OverlapLondonNY       = true;
input bool   OverlapTokyoLondon    = false;

input group "========== STOP LOSS =========="
input int    SLBufferPips          = 15;
input bool   UseTrailingStop       = false;
input int    TrailingStartPips     = 30;
input int    TrailingStepPips      = 10;

input group "========== POSITION MANAGEMENT =========="
input bool   CloseOnFriday         = true;
input int    FridayCloseHour       = 14;
input bool   UseBreakeven          = false;
input int    BreakevenTriggerPips  = 40;

input group "========== SWING DETECTION =========="
input int    SwingLookbackBarsH1   = 50;
input int    SwingConfirmBarsH1    = 3;
input int    SwingLookbackBarsM15  = 30;
input int    SwingConfirmBarsM15   = 5;
input int    MaxSwingDistancePips  = 500;
input int    MaxSLPips             = 30;
input int    MinSLPips             = 10;
input bool   ShowSwingLines        = true;

input group "========== ICT TWINS MODEL =========="
input bool   UseTwinsModel         = true;
input int    HTFLevelMinutes       = 15;
input double OTEMinPercent         = 0.65;
input double OTEMaxPercent         = 0.75;
input double OTESweetSpotPercent   = 0.705;
input int    MinFVGsRequired       = 0;
input int    HTFToleranceATRMulti  = 2;
input bool   HTFLevelRequired      = false;
input bool   ShowOTEZone           = true;
input int    MinH1RangePips        = 50;
input bool   UseH1RangeFilter      = true;
input double MinH1RangeATRMulti    = 0.8; // [NEW V1.3] H1 range >= N * H1-ATR (SmartActive)

input group "========== MSS / BOS / LIQUIDITY =========="
input int    MSSLookbackBars       = 30;
input int    MSSConfirmBars        = 3;
input int    BOSLookbackBars       = 20;
input int    LiquidityLookbackBars = 50;
input int    LiquidityWickPips     = 3;

input group "========== SYMBOL PRESET =========="
input ENUM_SYMBOL_PRESET SymbolPreset = PRESET_AUTO;

input group "========== OPTIMIZATION MODE =========="
input ENUM_OPT_MODE OptMode        = OPT_BALANCED;

input group "========== LOGGING =========="
input bool   EnableScreenshot      = true;
input bool   EnableCSVLog          = true;

input group "========== DEBUG =========="
input int    PostTradeCooldownMin  = 20;
input bool   UseDailyTrendFilter   = true;
input bool   BestHoursOnly         = true;
input bool   ForceTrades           = false;
input bool   DebugMode             = false;
input bool   RelaxedMode           = false;

//===================================================================//
//  GLOBALS
//===================================================================//
int      ATRHandle      = INVALID_HANDLE;
int      ATRHandleH1    = INVALID_HANDLE;   // [V1.3] H1 ATR for adaptive range
int      FastEMAHandle  = INVALID_HANDLE;
int      SlowEMAHandle  = INVALID_HANDLE;
int      H4EMAHandle    = INVALID_HANDLE;   // [V1.5] H4 EMA cached (was leaked every tick)

datetime LastBarTime        = 0;
datetime LastTradeCloseTime = 0;
int      TodayTradeCount    = 0;
int      TodayLossTrades    = 0;
int      LastTradeDay       = 0;
double   TodayLoss          = 0;
int      consecutiveLosses  = 0;
double   PipFactor          = 10.0;
datetime LastDisplayUpdate  = 0;

bool     htfLevelReached    = false;
bool     mssConfirmed       = false;
bool     mssIsBullish       = false;
bool     bosConfirmed       = false;
bool     bosIsBullish       = false;
bool     liquiditySweepDone = false;
bool     sweepIsBullish     = false;
int      fvgCount1Min       = -1;
datetime LastFVGBarTime     = 0;

bool     cisd5MinConfirmed  = false;
bool     cisd5MinIsBearish  = false;
datetime LastCISDTime5Min   = 0;
bool     cisd1MinConfirmed  = false;
bool     cisd1MinIsBearish  = false;
datetime LastCISDTime1Min   = 0;

double   lastSwingHighH1    = 0;
double   lastSwingLowH1     = 0;
double   lastSwingHighM15   = 0;
double   lastSwingLowM15    = 0;

int      lastTradeScore     = 0;
int      lastFailedStep     = 0;
string   lastFailedStepDesc = "";

bool     newsBlocked        = false;
datetime lastNewsCheck      = 0;

int    statTotalTrades  = 0;
int    statWins         = 0;
int    statLosses       = 0;
double statTotalProfit  = 0.0;
double statTotalLoss    = 0.0;
double statSumRR        = 0.0;
int    consecutiveWins  = 0;

double sessionStartEquity  = 0;
double sessionMaxDrawdown  = 0;
double sessionPeakEquity   = 0;

double lastOTEHigh = 0;
double lastOTELow  = 0;

// Effective parameters (set by preset + style)
double effOTEMin     = 0.65;
double effOTEMax     = 0.75;
int    effMaxSLPips  = 30;
int    effMinSLPips  = 10;
double effRiskPct    = 0.5;
int    effMinScore   = 70;

// V1.2 style overrides
bool   effUseMSSFilter     = true;
bool   effUseBOSFilter     = true;
bool   effRequireLiqSweep  = false;
bool   effUseDailyTrend    = true;
bool   effBestHoursOnly    = true;
bool   effUseH1RangeFilter = true;
int    effCooldown         = 20;
int    effMinH1Range       = 50;

// V1.3 detection overrides
int    effMSSConfirm   = 3;    // swing confirm bars for MSS (2=SmartActive)
int    effBOSConf      = 3;    // swing confirm bars for BOS (2=SmartActive)
double effBodyThresh   = 0.65; // CISD/momentum body % (0.60=SmartActive)
bool   effUseATRRange  = false;// ATR-adaptive H1 range check
double effMinRangeATR  = 0.8;  // H1 range >= this * H1-ATR

// V1.2 daily rejection stats (reset each day, shown on panel)
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
datetime rejSeqLastBar = 0;

// V1.3 cumulative rejection stats (never reset — full backtest summary)
int    cumRejTotal    = 0;
int    cumRejHTFLevel = 0;
int    cumRejMSS      = 0;
int    cumRejBOS      = 0;
int    cumRejSweep    = 0;
int    cumRejFVG      = 0;
int    cumRejH1Swing  = 0;
int    cumRejH1Range  = 0;
int    cumRejOTE      = 0;
int    cumRej1MTrig   = 0;
int    cumRejScore    = 0;
int    cumRejTrend    = 0;
int    cumRejSMT      = 0;
int    cumRejNews     = 0;

// Panel
string PANEL_PREFIX  = "ICTSMC_";
int    PANEL_X       = 10;
int    PANEL_Y       = 30;
int    PANEL_W       = 310;
int    PANEL_LINE_H  = 14;
color  PANEL_BG      = C'20,20,28';
color  PANEL_BORDER  = C'60,60,80';
color  PANEL_HDR_BG  = C'30,30,50';
color  PANEL_TXT     = clrSilver;
color  PANEL_GREEN   = clrLimeGreen;
color  PANEL_RED     = C'255,80,80';
color  PANEL_GOLD    = clrGold;
color  PANEL_BLUE    = C'100,160,255';
bool   panelDragging = false;
bool   panelHidden   = false;
int    dragOffsetX   = 0;
int    dragOffsetY   = 0;

string SwingLineNames[];
int    SwingLineIndex = 0;
int    MaxSwingLines  = 10;
string OTEObjectNames[4];

//===================================================================//
//  PRESET / OPT MODE
//===================================================================//
void ApplySymbolPreset()
{
   ENUM_SYMBOL_PRESET p=SymbolPreset;
   if(p==PRESET_AUTO){string s=_Symbol;
      if(StringFind(s,"XAU")>=0||StringFind(s,"GOLD")>=0) p=PRESET_XAUUSD;
      else if(StringFind(s,"BTC")>=0) p=PRESET_BTCUSD;
      else if(StringFind(s,"GBP")>=0) p=PRESET_GBPUSD;
      else if(StringFind(s,"EUR")>=0) p=PRESET_EURUSD;}
   switch(p){
      case PRESET_XAUUSD: effOTEMin=0.65;effOTEMax=0.75;effMaxSLPips=30;effMinSLPips=10;break;
      case PRESET_BTCUSD: effOTEMin=0.62;effOTEMax=0.78;effMaxSLPips=80;effMinSLPips=20;break;
      case PRESET_EURUSD: effOTEMin=0.62;effOTEMax=0.79;effMaxSLPips=25;effMinSLPips=5; break;
      case PRESET_GBPUSD: effOTEMin=0.62;effOTEMax=0.79;effMaxSLPips=30;effMinSLPips=5; break;
      default: effOTEMin=OTEMinPercent;effOTEMax=OTEMaxPercent;effMaxSLPips=MaxSLPips;effMinSLPips=MinSLPips;break;}
}
void ApplyOptimizationMode()
{
   switch(OptMode){
      case OPT_CONSERVATIVE: effMinScore=80;effRiskPct=0.25;break;
      case OPT_BALANCED:     effMinScore=70;effRiskPct=RiskPercent;break;
      case OPT_AGGRESSIVE:   effMinScore=55;effRiskPct=MathMin(RiskPercent*2.0,2.0);break;}
}

//===================================================================//
//  V1.3 TRADING STYLE
//===================================================================//
void ApplyTradingStyle()
{
   double baseMin=effOTEMin, baseMax=effOTEMax;
   // Reset detection params to strict defaults first
   effMSSConfirm=MSSConfirmBars; effBOSConf=3;
   effBodyThresh=0.65; effUseATRRange=false; effMinRangeATR=MinH1RangeATRMulti;

   switch(TradingStyle)
   {
      case STYLE_CONSERVATIVE:
         effMinScore=80; effRiskPct=MathMin(RiskPercent,0.5); effCooldown=30; effMinH1Range=50;
         effOTEMin=baseMin; effOTEMax=baseMax;
         effUseMSSFilter=true; effUseBOSFilter=true; effRequireLiqSweep=RequireLiquiditySweep;
         effUseDailyTrend=true; effBestHoursOnly=true; effUseH1RangeFilter=true;
         effMSSConfirm=3; effBOSConf=3; effBodyThresh=0.65; effUseATRRange=false;
         break;

      case STYLE_BALANCED:
         effMinScore=MinimumTradeScore; effRiskPct=RiskPercent; effCooldown=PostTradeCooldownMin;
         effMinH1Range=MinH1RangePips; effOTEMin=baseMin; effOTEMax=baseMax;
         effUseMSSFilter=UseMSSFilter; effUseBOSFilter=UseBOSFilter; effRequireLiqSweep=RequireLiquiditySweep;
         effUseDailyTrend=UseDailyTrendFilter; effBestHoursOnly=BestHoursOnly; effUseH1RangeFilter=UseH1RangeFilter;
         effMSSConfirm=MSSConfirmBars; effBOSConf=3; effBodyThresh=0.65; effUseATRRange=false;
         break;

      case STYLE_AGGRESSIVE:
         effMinScore=50; effRiskPct=MathMin(RiskPercent*1.5,2.0); effCooldown=10; effMinH1Range=20;
         effOTEMin=MathMax(0.55,baseMin-0.05); effOTEMax=MathMin(0.90,baseMax+0.05);
         effUseMSSFilter=false; effUseBOSFilter=UseBOSFilter; effRequireLiqSweep=false;
         effUseDailyTrend=false; effBestHoursOnly=BestHoursOnly; effUseH1RangeFilter=(MinH1RangePips>0);
         effMSSConfirm=2; effBOSConf=2; effBodyThresh=0.60; effUseATRRange=true; effMinRangeATR=0.6;
         break;

      case STYLE_SMART_ACTIVE:
         // All ICT filters ON — better detection, not disabled
         effMinScore=55; effRiskPct=RiskPercent; effCooldown=10; effMinH1Range=15;
         effOTEMin=0.60; effOTEMax=0.85;               // wider OTE as user requested
         effUseMSSFilter=true;                          // MSS ON
         effUseBOSFilter=true;                          // BOS ON
         effRequireLiqSweep=false;                      // Liquidity optional
         effUseDailyTrend=true;                         // Trend ON
         effBestHoursOnly=true; effUseH1RangeFilter=true;
         effMSSConfirm=2;                               // 2 bars vs 3 — faster MSS
         effBOSConf=2;                                  // 2 bars vs 3 — faster BOS
         effBodyThresh=0.60;                            // 60% body vs 65% — more triggers
         effUseATRRange=true; effMinRangeATR=0.8;       // adaptive range
         break;

      case STYLE_SMART_ACTIVE_PLUS:
         // All ICT filters ON — maximum frequency with ICT logic preserved
         effMinScore=45; effRiskPct=RiskPercent; effCooldown=5; effMinH1Range=10;
         effOTEMin=0.55; effOTEMax=0.90;               // 55-90% OTE window
         effUseMSSFilter=true;                          // MSS ON
         effUseBOSFilter=true;                          // BOS ON
         effRequireLiqSweep=false;                      // Liquidity optional
         effUseDailyTrend=true;                         // Trend ON
         effBestHoursOnly=false;                        // ALL active sessions
         effUseH1RangeFilter=true;
         effMSSConfirm=1;                               // 1 bar — fastest valid MSS
         effBOSConf=1;                                  // 1 bar — earliest BOS confirm
         effBodyThresh=0.55;                            // 55% body threshold
         effUseATRRange=true; effMinRangeATR=0.6;       // ATR range, relaxed to 0.6x
         break;

      case STYLE_ULTRA_ACTIVE:
         effMinScore=0;  // [V1.5] bypass score entirely — intent is maximum frequency
         effRiskPct=RiskPercent; effCooldown=5; effMinH1Range=10;
         effOTEMin=0.55; effOTEMax=0.90;  // [V1.5] was 0.40-0.95 (meaninglessly wide)
         effUseMSSFilter=false; effUseBOSFilter=false; effRequireLiqSweep=false;
         effUseDailyTrend=false; effBestHoursOnly=false; effUseH1RangeFilter=false;
         effMSSConfirm=2; effBOSConf=2; effBodyThresh=0.55; effUseATRRange=false;
         break;
   }
}

//===================================================================//
void DebugPrint(string msg) { if(DebugMode) Print("[DEBUG] ",msg); }

//===================================================================//
//  GMT / SESSION
//===================================================================//
int GetEffectiveGMTOffset()
{ return AutoDetectGMT?(int)MathRound((double)(TimeCurrent()-TimeGMT())/3600.0):BrokerGMTOffset; }

double GetGMTHour()
{
   int offset=GetEffectiveGMTOffset();
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   double h=dt.hour-offset+dt.min/60.0;
   while(h<0) h+=24.0; while(h>=24) h-=24.0; return h;
}

bool IsFridayCutoff()
{ if(!CloseOnFriday) return false; MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
  if(dt.day_of_week!=5) return false; return(GetGMTHour()>=(double)FridayCloseHour); }

bool InLondonSession()    { if(!SessionLondon)    return false; double h=GetGMTHour(); return(h>=8.0 &&h<17.0); }
bool InNewYorkSession()   { if(!SessionNewYork)   return false; double h=GetGMTHour(); return(h>=13.0&&h<22.0); }
bool InTokyoSession()     { if(!SessionTokyo)     return false; double h=GetGMTHour(); return(h>=0.0 &&h<9.0);  }
bool InSydneySession()    { if(!SessionSydney)    return false; double h=GetGMTHour(); return(h>=22.0||h<7.0);  }
bool InLondonNYOverlap()  { if(!OverlapLondonNY)  return false; double h=GetGMTHour(); return(h>=13.0&&h<17.0); }
bool InTokyoLondonOverlap(){ if(!OverlapTokyoLondon) return false; double h=GetGMTHour(); return(h>=8.0&&h<9.0); }

bool SessionActiveNow(string which)
{ double h=GetGMTHour();
  if(which=="London")  return(h>=8.0&&h<17.0); if(which=="NewYork") return(h>=13.0&&h<22.0);
  if(which=="Overlap") return(h>=13.0&&h<17.0); if(which=="Sydney") return(h>=22.0||h<7.0);
  if(which=="Tokyo")   return(h>=0.0&&h<9.0);  return false; }

bool IsTradingTime()
{ if(!UseTimeFilter) return true; if(IsFridayCutoff()) return false;
  if(effBestHoursOnly){ double g=GetGMTHour(); if(g<8.5||g>=15.0) return false; }
  return(InSydneySession()||InTokyoSession()||InLondonSession()||
         InNewYorkSession()||InLondonNYOverlap()||InTokyoLondonOverlap()); }

bool IsSpreadOK()
{ if(MaxSpreadPoints<=0) return true;
  return((SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point<=MaxSpreadPoints); }

double GetATR()
{ double a[1]; if(CopyBuffer(ATRHandle,0,1,1,a)==1) return a[0]; return _Point*100; }

// V1.3: H1 ATR for adaptive range check
double GetATRH1()
{ double a[1]; if(ATRHandleH1!=INVALID_HANDLE&&CopyBuffer(ATRHandleH1,0,1,1,a)==1) return a[0];
  return GetATR()*4; }

bool IsPositionOpen()
{ for(int i=PositionsTotal()-1;i>=0;i--)
  { ulong t=PositionGetTicket(i); if(t>0&&PositionSelectByTicket(t))
    if(PositionGetString(POSITION_SYMBOL)==_Symbol&&PositionGetInteger(POSITION_MAGIC)==MAGIC_NUMBER) return true; }
  return false; }

//===================================================================//
//  HTF LEVEL
//===================================================================//
bool HasReachedHTFLevel()
{ if(!HTFLevelRequired) return true;
  ENUM_TIMEFRAMES htf; switch(HTFLevelMinutes){case 15:htf=PERIOD_M15;break;case 30:htf=PERIOD_M30;break;default:htf=PERIOD_H1;}
  double price=iClose(_Symbol,htf,0), tol=GetATR()*HTFToleranceATRMulti;
  for(int i=1;i<=20;i++){double hi1=iHigh(_Symbol,htf,i),lo1=iLow(_Symbol,htf,i),hi3=iHigh(_Symbol,htf,i+2),lo3=iLow(_Symbol,htf,i+2);
    if(hi1<lo3&&price>=hi1-tol&&price<=lo3+tol) return true; if(lo1>hi3&&price>=hi3-tol&&price<=lo1+tol) return true;}
  double ph=iHigh(_Symbol,htf,1),pl=iLow(_Symbol,htf,1);
  if(MathAbs(price-ph)<=tol||MathAbs(price-pl)<=tol) return true;
  double h1H=iHigh(_Symbol,PERIOD_H1,1),h1L=iLow(_Symbol,PERIOD_H1,1);
  if(MathAbs(price-h1H)<=tol*2||MathAbs(price-h1L)<=tol*2) return true;
  double h4H=iHigh(_Symbol,PERIOD_H4,1),h4L=iLow(_Symbol,PERIOD_H4,1);
  if(MathAbs(price-h4H)<=tol*4||MathAbs(price-h4L)<=tol*4) return true;
  double dH=iHigh(_Symbol,PERIOD_D1,1),dL=iLow(_Symbol,PERIOD_D1,1),dT=tol*3;
  if(MathAbs(price-dH)<=dT||MathAbs(price-dL)<=dT) return true; return false; }

//===================================================================//
//  V1.3 IMPROVED MSS DETECTION
//  Uses effMSSConfirm (2 for SmartActive vs 3 for Conservative)
//  Checks current forming bar + displacement candles
//===================================================================//
bool DetectMSS(bool &isBullish)
{
   int conf=effMSSConfirm;
   int need=MSSLookbackBars+conf*2+5;
   MqlRates h1[]; ArraySetAsSeries(h1,true);
   if(CopyRates(_Symbol,PERIOD_H1,0,need,h1)<need) return false;

   double swHigh=0,swLow=0;
   int    swHBar=INT_MAX,swLBar=INT_MAX;

   for(int i=conf;i<MSSLookbackBars-conf;i++)
   {
      bool isH=true,isL=true;
      for(int j=i-conf;j<=i+conf;j++)
      { if(j==i||j<0||j>=need) continue;
        if(h1[j].high>=h1[i].high) isH=false;
        if(h1[j].low <=h1[i].low)  isL=false; }
      if(isH&&i<swHBar){swHigh=h1[i].high;swHBar=i;}
      if(isL&&i<swLBar){swLow =h1[i].low; swLBar=i;}
   }
   if(swHBar==INT_MAX||swLBar==INT_MAX) return false;

   double atr=GetATR();
   // Check current forming bar AND last closed bar (wider window = more signals)
   for(int i=0;i<=1;i++)
   {
      double body=MathAbs(h1[i].close-h1[i].open);
      bool   bull=h1[i].close>h1[i].open;
      // Displacement candle: body > 40% ATR, closes beyond swing level
      if(bull && body>atr*0.4 && h1[i].close>swHigh && swLBar<swHBar)
      { isBullish=true; return true; }
      if(!bull && body>atr*0.4 && h1[i].close<swLow && swHBar<swLBar)
      { isBullish=false; return true; }
   }
   // Standard structural close beyond swing
   double checkH=MathMax(h1[0].close,h1[1].close);
   double checkL=MathMin(h1[0].close,h1[1].close);
   if(swLBar<swHBar && checkH>swHigh){ isBullish=true;  return true; }
   if(swHBar<swLBar && checkL<swLow) { isBullish=false; return true; }
   return false;
}

//===================================================================//
//  V1.3 IMPROVED BOS DETECTION
//  Uses effBOSConf; checks current bar + displacement
//===================================================================//
bool DetectBOS(bool &isBullish)
{
   int conf=effBOSConf;
   int need=BOSLookbackBars+conf*2+5;
   MqlRates m15[]; ArraySetAsSeries(m15,true);
   if(CopyRates(_Symbol,PERIOD_M15,0,need,m15)<need) return false;

   double swHigh=0,swLow=0;
   int    swHBar=INT_MAX,swLBar=INT_MAX;

   for(int i=conf;i<BOSLookbackBars-conf;i++)
   {
      bool isH=true,isL=true;
      for(int j=i-conf;j<=i+conf;j++)
      { if(j==i||j<0||j>=need) continue;
        if(m15[j].high>=m15[i].high) isH=false;
        if(m15[j].low <=m15[i].low)  isL=false; }
      if(isH&&i<swHBar){swHigh=m15[i].high;swHBar=i;}
      if(isL&&i<swLBar){swLow =m15[i].low; swLBar=i;}
   }
   if(swHBar==INT_MAX&&swLBar==INT_MAX) return false;

   double atr=GetATR();
   for(int i=0;i<=1;i++)
   { double body=MathAbs(m15[i].close-m15[i].open); bool bull=m15[i].close>m15[i].open;
     if(bull&&body>atr*0.3&&swHigh>0&&m15[i].close>swHigh){ isBullish=true;  return true; }
     if(!bull&&body>atr*0.3&&swLow>0 &&m15[i].close<swLow) { isBullish=false; return true; } }

   double chkH=MathMax(m15[0].close,m15[1].close);
   double chkL=MathMin(m15[0].close,m15[1].close);
   if(swHigh>0&&chkH>swHigh){ isBullish=true;  return true; }
   if(swLow >0&&chkL<swLow) { isBullish=false; return true; }
   return false;
}

//===================================================================//
//  LIQUIDITY SWEEP
//===================================================================//
bool DetectLiquiditySweep(bool &sweepBullish)
{
   // [V1.5] Swing-based liquidity pools: find swing high/low, check wick-through + close back
   // Old code just used range max/min which is NOT a real liquidity sweep
   int need=LiquidityLookbackBars+5;
   MqlRates m15[]; ArraySetAsSeries(m15,true);
   if(CopyRates(_Symbol,PERIOD_M15,0,need,m15)<need) return false;
   double wickPts=LiquidityWickPips*PipFactor*_Point;
   int conf=2;
   double poolHigh=0,poolLow=0;
   for(int i=conf;i<LiquidityLookbackBars-conf;i++)
   {
      bool isH=true,isL=true;
      for(int j=i-conf;j<=i+conf;j++)
      { if(j==i||j<0||j>=need) continue;
        if(m15[j].high>=m15[i].high) isH=false;
        if(m15[j].low <=m15[i].low)  isL=false; }
      if(isH&&(poolHigh==0||m15[i].high>poolHigh)) poolHigh=m15[i].high;
      if(isL&&(poolLow==0 ||m15[i].low <poolLow))  poolLow =m15[i].low;
   }
   if(poolLow<=0&&poolHigh<=0) return false;
   for(int i=1;i<=4;i++)
   { if(poolLow>0  &&m15[i].low <poolLow -wickPts&&m15[i].close>poolLow) {sweepBullish=true; return true;}
     if(poolHigh>0 &&m15[i].high>poolHigh+wickPts&&m15[i].close<poolHigh){sweepBullish=false;return true;} }
   return false;
}

//===================================================================//
//  V1.3 IMPROVED 5M CISD — uses effBodyThresh
//===================================================================//
bool IsCISD5M(bool &isBearish)
{
   bool allUp=true,allDown=true;
   for(int i=1;i<=2;i++)
   { double c=iClose(_Symbol,PERIOD_M5,i),o=iOpen(_Symbol,PERIOD_M5,i);
     if(c<=o) allUp=false; if(c>=o) allDown=false; }
   double curC=iClose(_Symbol,PERIOD_M5,0);
   if(allUp){ double sl=iLow(_Symbol,PERIOD_M5,1);
     for(int i=2;i<=2;i++){double l=iLow(_Symbol,PERIOD_M5,i);if(l<sl)sl=l;}
     if(curC<sl){isBearish=true;return true;} }
   if(allDown){ double sh=iHigh(_Symbol,PERIOD_M5,1);
     for(int i=2;i<=2;i++){double h=iHigh(_Symbol,PERIOD_M5,i);if(h>sh)sh=h;}
     if(curC>sh){isBearish=false;return true;} }
   // Momentum candle — use effBodyThresh (0.60 for SmartActive vs 0.70 before)
   for(int lb=1;lb<=10;lb++)
   { double o=iOpen(_Symbol,PERIOD_M5,lb),cl=iClose(_Symbol,PERIOD_M5,lb);
     double h=iHigh(_Symbol,PERIOD_M5,lb),l=iLow(_Symbol,PERIOD_M5,lb);
     double rng=h-l; if(rng>0&&MathAbs(cl-o)/rng>=effBodyThresh){isBearish=(cl<o);return true;} }
   return false;
}

//===================================================================//
//  V1.3 IMPROVED 1M ENTRY TRIGGER
//  + pin-bar detection
//  + 3-bar momentum
//  + effBodyThresh adaptive threshold
//===================================================================//
bool IsCISD1M(bool &isBearish)
{
   // Method 1: classic CISD reversal
   bool allUp=true,allDown=true;
   double c=iClose(_Symbol,PERIOD_M1,1),o=iOpen(_Symbol,PERIOD_M1,1);
   if(c<=o) allUp=false; if(c>=o) allDown=false;
   double curC=iClose(_Symbol,PERIOD_M1,0);
   if(allUp  &&curC<iLow (_Symbol,PERIOD_M1,1)){isBearish=true; return true;}
   if(allDown&&curC>iHigh(_Symbol,PERIOD_M1,1)){isBearish=false;return true;}

   // Method 2: momentum candle — adaptive threshold
   for(int lb=1;lb<=3;lb++)
   { double o1=iOpen(_Symbol,PERIOD_M1,lb),c1=iClose(_Symbol,PERIOD_M1,lb);
     double h1=iHigh(_Symbol,PERIOD_M1,lb),l1=iLow(_Symbol,PERIOD_M1,lb);
     double rng=h1-l1; if(rng>0&&MathAbs(c1-o1)/rng>=effBodyThresh){isBearish=(c1<o1);return true;} }

   // Method 3: pin bar — wick >= 2x body, closes in opposite half [V1.3]
   for(int lb=1;lb<=3;lb++)
   { double o1=iOpen(_Symbol,PERIOD_M1,lb),c1=iClose(_Symbol,PERIOD_M1,lb);
     double h1=iHigh(_Symbol,PERIOD_M1,lb),l1=iLow(_Symbol,PERIOD_M1,lb);
     double body=MathAbs(c1-o1);
     double upWick=h1-MathMax(c1,o1), dnWick=MathMin(c1,o1)-l1;
     if(body>0&&upWick>=2.0*body&&c1<(h1+l1)/2.0){isBearish=true; return true;}  // shooting star
     if(body>0&&dnWick>=2.0*body&&c1>(h1+l1)/2.0){isBearish=false;return true;} } // hammer

   // Method 4: 3-bar momentum [V1.3]
   bool m4bull=(iClose(_Symbol,PERIOD_M1,1)>iOpen(_Symbol,PERIOD_M1,1)&&
                iClose(_Symbol,PERIOD_M1,2)>iOpen(_Symbol,PERIOD_M1,2)&&
                iClose(_Symbol,PERIOD_M1,3)>iOpen(_Symbol,PERIOD_M1,3));
   bool m4bear=(iClose(_Symbol,PERIOD_M1,1)<iOpen(_Symbol,PERIOD_M1,1)&&
                iClose(_Symbol,PERIOD_M1,2)<iOpen(_Symbol,PERIOD_M1,2)&&
                iClose(_Symbol,PERIOD_M1,3)<iOpen(_Symbol,PERIOD_M1,3));
   if(m4bull){isBearish=false;return true;}
   if(m4bear){isBearish=true; return true;}
   return false;
}

//===================================================================//
//  SWING DETECTION
//===================================================================//
void FindSwingPointsH1(double &swHigh,double &swLow)
{ swHigh=0;swLow=0;
  MqlRates h1[];ArraySetAsSeries(h1,true);
  int need=SwingLookbackBarsH1+SwingConfirmBarsH1+5;
  if(CopyRates(_Symbol,PERIOD_H1,0,need,h1)<need) return;
  double maxD=(MaxSwingDistancePips>0)?MaxSwingDistancePips*PipFactor*_Point:DBL_MAX;
  double cur=iClose(_Symbol,PERIOD_H1,0); int bH=INT_MAX,bL=INT_MAX;
  for(int i=SwingConfirmBarsH1;i<SwingLookbackBarsH1-SwingConfirmBarsH1;i++)
  { if(MathAbs(h1[i].high-cur)<=maxD){bool ok=true;for(int j=i-SwingConfirmBarsH1;j<=i+SwingConfirmBarsH1;j++){if(j==i||j<0)continue;if(h1[j].high>=h1[i].high){ok=false;break;}}if(ok&&i<bH){swHigh=h1[i].high;bH=i;}}
    if(MathAbs(h1[i].low-cur)<=maxD){bool ok=true;for(int j=i-SwingConfirmBarsH1;j<=i+SwingConfirmBarsH1;j++){if(j==i||j<0)continue;if(h1[j].low<=h1[i].low){ok=false;break;}}if(ok&&i<bL){swLow=h1[i].low;bL=i;}}}}

void FindSwingPointsM15(double &swHigh,double &swLow)
{ swHigh=0;swLow=0;
  MqlRates m15[];ArraySetAsSeries(m15,true);
  int need=SwingLookbackBarsM15+SwingConfirmBarsM15+5;
  if(CopyRates(_Symbol,PERIOD_M15,0,need,m15)<need) return;
  double maxD=(MaxSwingDistancePips>0)?MaxSwingDistancePips*PipFactor*_Point:DBL_MAX;
  double cur=iClose(_Symbol,PERIOD_M15,0); int bH=INT_MAX,bL=INT_MAX;
  for(int i=SwingConfirmBarsM15;i<SwingLookbackBarsM15-SwingConfirmBarsM15;i++)
  { if(MathAbs(m15[i].high-cur)<=maxD){bool ok=true;for(int j=i-SwingConfirmBarsM15;j<=i+SwingConfirmBarsM15;j++){if(j==i||j<0)continue;if(m15[j].high>=m15[i].high){ok=false;break;}}if(ok&&i<bH){swHigh=m15[i].high;bH=i;}}
    if(MathAbs(m15[i].low-cur)<=maxD){bool ok=true;for(int j=i-SwingConfirmBarsM15;j<=i+SwingConfirmBarsM15;j++){if(j==i||j<0)continue;if(m15[j].low<=m15[i].low){ok=false;break;}}if(ok&&i<bL){swLow=m15[i].low;bL=i;}}}}

void FindNearestSwing(bool isBuy,double &swPrice)
{ swPrice=0; FindSwingPointsM15(lastSwingHighM15,lastSwingLowM15);
  if(isBuy&&lastSwingLowM15>0)  swPrice=lastSwingLowM15;
  if(!isBuy&&lastSwingHighM15>0) swPrice=lastSwingHighM15;
  if(swPrice<=0){ double atr=GetATR();
    swPrice=isBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID)-atr*1.5:SymbolInfoDouble(_Symbol,SYMBOL_ASK)+atr*1.5; }
  if(ShowSwingLines) DrawSwingLine(swPrice,isBuy,"M15"); }

//===================================================================//
//  FVG / OTE / SMT / NEWS / TREND
//===================================================================//
int CountFVGsOn1Min(datetime startTime,datetime endTime)
{ int count=0; MqlRates rates[];ArraySetAsSeries(rates,false);
  datetime from=startTime-PeriodSeconds(PERIOD_M1)*5;
  int copied=CopyRates(_Symbol,PERIOD_M1,from,endTime+PeriodSeconds(PERIOD_M1),rates);
  if(copied<3) return 0;
  for(int i=0;i<copied-2;i++)
  { if(rates[i].time<startTime||rates[i].time>endTime) continue;
    if(rates[i+2].low>rates[i].high) count++;
    if(rates[i+2].high<rates[i].low)  count++; }
  return count; }

int GetEffectiveFVGReq() { return RelaxedMode?0:MinFVGsRequired; }

bool IsInOTEZone(double price,double hi,double lo)
{ if(hi<=0||lo<=0||hi<=lo) return false; double r=hi-lo;
  return(price>=lo+r*effOTEMin&&price<=lo+r*effOTEMax); }

bool CheckSMTDivergence(bool isBuy)
{ if(!UseSMTFilter) return true; if(StringLen(SMTSymbol)<3) return true;
  MqlRates r1[2],r2[2];
  if(CopyRates(_Symbol,PERIOD_H1,0,2,r1)!=2) return true;
  if(CopyRates(SMTSymbol,PERIOD_H1,0,2,r2)!=2) return true;
  return(r1[1].close>r1[1].open)!=(r2[1].close>r2[1].open); }

bool IsNewsTime()
{ if(!UseNewsFilter) return false;
  if(TimeCurrent()-lastNewsCheck<60) return newsBlocked; lastNewsCheck=TimeCurrent();
  datetime from=TimeCurrent()-NewsBlockBeforeMin*60, to=TimeCurrent()+NewsBlockAfterMin*60;
  MqlCalendarValue vals[]; int cnt=CalendarValueHistory(vals,from,to,NULL,NULL);
  for(int i=0;i<cnt;i++){ MqlCalendarEvent ev; if(!CalendarEventById(vals[i].event_id,ev)) continue;
    if(ev.importance==CALENDAR_IMPORTANCE_HIGH){newsBlocked=true;return true;} }
  newsBlocked=false; return false; }

bool IsTrendAligned(bool isBuy)
{ MqlRates d1[4]; bool d1Up=false,d1Dn=false;
  if(CopyRates(_Symbol,PERIOD_D1,0,4,d1)==4)
  { int bull=0,bear=0; for(int di=1;di<=3;di++){if(d1[di].close>d1[di].open)bull++;else bear++;}
    d1Up=isBuy?(bull==3):(bull>=2); d1Dn=isBuy?(bear>=2):(bear==3); }
  double h4e[1]; bool h4Up=false,h4Dn=false;
  // [V1.5] Use cached H4EMAHandle — was creating+releasing a new handle every tick
  if(H4EMAHandle!=INVALID_HANDLE&&CopyBuffer(H4EMAHandle,0,1,1,h4e)==1)
  { double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID); h4Up=(bid>h4e[0]); h4Dn=(bid<h4e[0]); }
  if(isBuy){bool anyBull=d1Up||h4Up;bool strongBear=d1Dn&&h4Dn;if(strongBear||(!anyBull&&d1Dn))return false;}
  else     {bool anyBear=d1Dn||h4Dn;bool strongBull=d1Up&&h4Up;if(strongBull||(!anyBear&&d1Up))return false;}
  return true; }

int CalculateTradeScore(bool isBuy)
{ int s=0;
  // [V1.5] Only award points when filter is ON and confirmed — disabled filters give 0
  // Old code gave free 20pts per disabled filter, making score meaningless in UltraActive
  if(effUseMSSFilter && mssConfirmed)          s+=20;
  if(effUseBOSFilter && bosConfirmed)          s+=20;
  if(effRequireLiqSweep && liquiditySweepDone) s+=20;
  int fvgR=GetEffectiveFVGReq();
  if(fvgR==0) s+=5; else if(fvgCount1Min>=0&&fvgCount1Min>=fvgR) s+=15;
  s+=15; if(IsTrendAligned(isBuy)) s+=10; return s; }

bool IsBrokerOrderSafe(bool isBuy,double entry,double sl,double tp,string &reason)
{ if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)){reason="TERMINAL DISABLED";return false;}
  if(!MQLInfoInteger(MQL_TRADE_ALLOWED)){reason="EA DISABLED";return false;}
  if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)){reason="ACCOUNT DISABLED";return false;}
  long mode=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
  if(mode==SYMBOL_TRADE_MODE_DISABLED){reason="SYMBOL DISABLED";return false;}
  if(mode==SYMBOL_TRADE_MODE_CLOSEONLY){reason="CLOSE ONLY";return false;}
  double sl2=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
  double fl =SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)*_Point;
  if(MathAbs(entry-sl)<sl2){reason="SL INSIDE STOP LEVEL";return false;}
  if(MathAbs(entry-tp)<sl2){reason="TP INSIDE STOP LEVEL";return false;}
  if(fl>0&&MathAbs(entry-tp)<fl){reason="TP INSIDE FREEZE";return false;}
  reason=""; return true; }

//===================================================================//
//  REJECTION HELPERS — increment both daily and cumulative counters
//===================================================================//
void RejHTFLevel(){ rejHTFLevel++;rejTotal++;cumRejHTFLevel++;cumRejTotal++; }
void RejMSS()     { rejMSS++;    rejTotal++;cumRejMSS++;    cumRejTotal++; }
void RejBOS()     { rejBOS++;    rejTotal++;cumRejBOS++;    cumRejTotal++; }
void RejSweep()   { rejSweep++;  rejTotal++;cumRejSweep++;  cumRejTotal++; }
void RejFVG()     { rejFVG++;    rejTotal++;cumRejFVG++;    cumRejTotal++; }
void RejH1Swing() { rejH1Swing++;rejTotal++;cumRejH1Swing++;cumRejTotal++; }
void RejH1Range() { rejH1Range++;rejTotal++;cumRejH1Range++;cumRejTotal++; }
void RejOTE()     { rejOTE++;    rejTotal++;cumRejOTE++;    cumRejTotal++; }
void Rej1MTrig()  { rej1MTrig++; rejTotal++;cumRej1MTrig++; cumRejTotal++; }
void RejScore()   { rejScore++;  rejTotal++;cumRejScore++;  cumRejTotal++; }
void RejTrend()   { rejTrend++;  rejTotal++;cumRejTrend++;  cumRejTotal++; }
void RejSMT()     { rejSMT++;    rejTotal++;cumRejSMT++;    cumRejTotal++; }
void RejNews()    { rejNews++;   rejTotal++;cumRejNews++;   cumRejTotal++; }

//===================================================================//
//  STATE MACHINE
//===================================================================//
void UpdateContextState()
{
   if(HasReachedHTFLevel())
   { if(!htfLevelReached){htfLevelReached=true;Print("STEP 1 PASS: HTF Level");lastFailedStep=0;lastFailedStepDesc="";} }
   else{ if(htfLevelReached) htfLevelReached=false; RejHTFLevel(); lastFailedStep=1;lastFailedStepDesc="HTF Level";return; }

   if(effUseMSSFilter)
   { bool mssB=false;
     if(DetectMSS(mssB))
     { if(!mssConfirmed||mssIsBullish!=mssB)
       {mssConfirmed=true;mssIsBullish=mssB;cisd5MinConfirmed=true;cisd5MinIsBearish=!mssB;
        cisd1MinConfirmed=false;fvgCount1Min=-1;Print("STEP 2 PASS: MSS "+(mssB?"BULL":"BEAR"));} }
     else{ if(mssConfirmed){mssConfirmed=false;DebugPrint("STEP 2: MSS lost");}
           RejMSS(); lastFailedStep=2;lastFailedStepDesc="MSS (H1)";return; } }
   else
   { bool tb=false; bool found=IsCISD5M(tb);
     if(!found){ for(int lb=1;lb<=10;lb++){double o5=iOpen(_Symbol,PERIOD_M5,lb),cl5=iClose(_Symbol,PERIOD_M5,lb);
       double h5=iHigh(_Symbol,PERIOD_M5,lb),l5=iLow(_Symbol,PERIOD_M5,lb),rng5=h5-l5;
       if(rng5>0&&MathAbs(cl5-o5)/rng5>=effBodyThresh){tb=(cl5<o5);found=true;break;}}}
     if(found){ datetime bt5=iTime(_Symbol,PERIOD_M5,0);
       if(LastCISDTime5Min!=bt5){LastCISDTime5Min=bt5;cisd5MinConfirmed=true;cisd5MinIsBearish=tb;
         mssConfirmed=true;mssIsBullish=!tb;cisd1MinConfirmed=false;fvgCount1Min=-1;
         Print("STEP 2 PASS: 5M CISD "+(tb?"BEAR":"BULL"));}}
     if(!mssConfirmed){RejMSS();lastFailedStep=2;lastFailedStepDesc="5M Direction";return;} }

   if(effUseBOSFilter)
   { bool bosB=false;
     if(DetectBOS(bosB))
     { if(!bosConfirmed||bosIsBullish!=bosB){bosConfirmed=true;bosIsBullish=bosB;Print("STEP 3 PASS: BOS "+(bosB?"BULL":"BEAR"));} }
     else{ if(bosConfirmed){bosConfirmed=false;DebugPrint("STEP 3: BOS lost");}
           RejBOS(); lastFailedStep=3;lastFailedStepDesc="BOS (M15)";return; } }
   else bosConfirmed=true;

   if(effRequireLiqSweep)
   { bool swpB=false;
     if(DetectLiquiditySweep(swpB)){ if(!liquiditySweepDone){liquiditySweepDone=true;sweepIsBullish=swpB;Print("STEP 4 PASS: Sweep");} }
     else if(!liquiditySweepDone){ RejSweep(); lastFailedStep=4;lastFailedStepDesc="Liquidity Sweep";return; } }
   else liquiditySweepDone=true;

   if(fvgCount1Min<0)
   { datetime cStart=LastCISDTime5Min-PeriodSeconds(PERIOD_M5),cEnd=LastCISDTime5Min;
     if(cEnd<=0){datetime b5[1];if(CopyTime(_Symbol,PERIOD_M5,1,1,b5)==1){cEnd=b5[0];cStart=b5[0]-PeriodSeconds(PERIOD_M5);}}
     fvgCount1Min=CountFVGsOn1Min(cStart,cEnd); }
   int fvgReq=GetEffectiveFVGReq();
   if(fvgReq>0&&fvgCount1Min<fvgReq){ RejFVG(); lastFailedStep=5;lastFailedStepDesc="1M FVG Count";return; }

   FindSwingPointsH1(lastSwingHighH1,lastSwingLowH1);
   if(lastSwingHighH1<=0||lastSwingLowH1<=0||lastSwingHighH1<=lastSwingLowH1)
   { RejH1Swing(); lastFailedStep=6;lastFailedStepDesc="H1 Swings";return; }

   // V1.3: ATR-adaptive H1 range check
   if(effUseATRRange)
   { double rangeActual=lastSwingHighH1-lastSwingLowH1, h1atr=GetATRH1();
     if(h1atr>0&&rangeActual<h1atr*effMinRangeATR)
     { RejH1Range(); lastFailedStep=6;lastFailedStepDesc="H1 Range (ATR)";return; } }
   else if(effUseH1RangeFilter&&effMinH1Range>0)
   { double rp=(lastSwingHighH1-lastSwingLowH1)/_Point/PipFactor;
     if(rp<effMinH1Range){ RejH1Range(); lastFailedStep=6;lastFailedStepDesc="H1 Range (pips)";return; } }

   FindSwingPointsM15(lastSwingHighM15,lastSwingLowM15);
   if(ShowOTEZone) DrawOTEZone(lastSwingHighH1,lastSwingLowH1);
}

//===================================================================//
//  [V1.5] DEALING RANGE CHECK — buy in discount, sell in premium
//  Uses last 6 H4 bars (~24h) to define the institutional dealing range
//===================================================================//
bool CheckDealingRange(bool isBuy)
{
   if(!UseDealingRange) return true;
   double rangeHigh=0, rangeLow=0;
   for(int i=1;i<=6;i++)
   {
      double h=iHigh(_Symbol,PERIOD_H4,i), l=iLow(_Symbol,PERIOD_H4,i);
      if(rangeHigh==0||h>rangeHigh) rangeHigh=h;
      if(rangeLow==0 ||l<rangeLow)  rangeLow=l;
   }
   if(rangeHigh<=rangeLow) return true;
   double eq=(rangeHigh+rangeLow)/2.0;
   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   return isBuy ? (price<=eq) : (price>=eq);
}

//===================================================================//
//  LIVE ENTRY CHECK
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

   datetime curBar=iTime(_Symbol,PERIOD_M15,0);
   bool newBar=(curBar!=rejSeqLastBar);

   if(curPrice<oteLow||curPrice>oteHigh)
   { if(newBar){RejOTE();rejSeqLastBar=curBar;} lastFailedStep=8;lastFailedStepDesc="OTE Zone";return false; }

   bool tb1=false; bool found1=IsCISD1M(tb1);
   if(found1){ datetime bt1=iTime(_Symbol,PERIOD_M1,0);
     if(LastCISDTime1Min!=bt1){LastCISDTime1Min=bt1;cisd1MinConfirmed=true;cisd1MinIsBearish=tb1;} }
   if(!cisd1MinConfirmed)
   { if(newBar){Rej1MTrig();rejSeqLastBar=curBar;} lastFailedStep=9;lastFailedStepDesc="1M Entry Trigger";return false; }

   double oteBottom=lastSwingLowH1+range*effOTEMin, oteTop=lastSwingLowH1+range*effOTEMax;
   double oteRange=oteTop-oteBottom;
   bool priceInBuy =(curPrice<=oteBottom+oteRange*0.35);
   bool priceInSell=(curPrice>=oteTop  -oteRange*0.35);
   if(!priceInBuy&&!priceInSell){ lastFailedStep=9;lastFailedStepDesc="OTE Middle";return false; }
   isBuy=priceInBuy;

   if(mssIsBullish!=isBuy)    { lastFailedStep=9;lastFailedStepDesc="MSS/OTE Conflict";return false; }
   if(cisd1MinIsBearish==isBuy){ lastFailedStep=9;lastFailedStepDesc="1M/OTE Conflict"; return false; }

   // [V1.5] Dealing range: only buy in discount zone, only sell in premium zone
   if(!CheckDealingRange(isBuy))
   { if(newBar){RejOTE();rejSeqLastBar=curBar;} lastFailedStep=9;lastFailedStepDesc="Dealing Range";return false; }

   if(effUseDailyTrend&&!IsTrendAligned(isBuy))
   { if(newBar){RejTrend();rejSeqLastBar=curBar;} lastFailedStep=10;lastFailedStepDesc="MTF Trend";return false; }
   if(UseSMTFilter&&!CheckSMTDivergence(isBuy))
   { if(newBar){RejSMT();rejSeqLastBar=curBar;} lastFailedStep=10;lastFailedStepDesc="SMT";return false; }
   if(IsNewsTime())
   { if(newBar){RejNews();rejSeqLastBar=curBar;} lastFailedStep=10;lastFailedStepDesc="News";return false; }

   int score=CalculateTradeScore(isBuy); lastTradeScore=score;
   if(UseTradeScore&&effMinScore>0&&score<effMinScore)
   { if(newBar){RejScore();rejSeqLastBar=curBar;} lastFailedStep=10;lastFailedStepDesc="Score "+IntegerToString(score)+"/"+IntegerToString(effMinScore);return false; }

   if(newBar) rejSeqLastBar=curBar;
   lastFailedStep=0;lastFailedStepDesc="";
   static datetime lastLog=0; datetime cb=iTime(_Symbol,PERIOD_M15,0);
   if(lastLog!=cb){lastLog=cb;Print(">>> ENTRY READY: "+(isBuy?"BUY":"SELL")+" Score=",score," <<<");}
   return true;
}

//===================================================================//
//  DAILY COUNTERS
//===================================================================//
void UpdateDailyCounters()
{ MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); if(dt.day==LastTradeDay) return;
  TodayTradeCount=0;TodayLossTrades=0;TodayLoss=0;
  if(ResetLossStreakDaily) consecutiveLosses=0; LastTradeDay=dt.day;
  // [V1.5] Only reset trade/session counters — preserve MSS/BOS/structural state
  // Old code reset mssConfirmed/bosConfirmed at midnight, killing valid overnight setups
  cisd1MinConfirmed=false;fvgCount1Min=-1;  // reset entry trigger only
  // Reset daily rejection counters only (cumulative untouched)
  rejTotal=0;rejHTFLevel=0;rejMSS=0;rejBOS=0;rejSweep=0;
  rejFVG=0;rejH1Swing=0;rejH1Range=0;rejOTE=0;rej1MTrig=0;
  rejScore=0;rejTrend=0;rejSMT=0;rejNews=0;rejSeqLastBar=0; }

bool IsDailyLossLimitHit()
{ if(MaxDailyLossPercent<=0) return false;
  MqlDateTime dt;TimeToStruct(TimeCurrent(),dt);dt.hour=0;dt.min=0;dt.sec=0;datetime ts=StructToTime(dt);
  TodayLoss=0; if(HistorySelect(ts,TimeCurrent()))
  { for(int i=HistoryDealsTotal()-1;i>=0;i--)
    { ulong d=HistoryDealGetTicket(i); if(d==0) continue;
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol||HistoryDealGetInteger(d,DEAL_MAGIC)!=MAGIC_NUMBER||
         HistoryDealGetInteger(d,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      double p=HistoryDealGetDouble(d,DEAL_PROFIT); if(p<0) TodayLoss+=MathAbs(p); } }
  double b=AccountInfoDouble(ACCOUNT_BALANCE),e=AccountInfoDouble(ACCOUNT_EQUITY);
  return(TodayLoss>=MathMin(b,e)*MaxDailyLossPercent/100.0); }

bool CanTrade()
{ UpdateDailyCounters();
  static datetime lastLog=0; bool canLog=(TimeCurrent()-lastLog>=60);
  if(IsDailyLossLimitHit()){if(canLog){Print("CANTRADE: Daily loss");lastLog=TimeCurrent();}return false;}
  if(TodayTradeCount>=MaxTradesPerDay){if(canLog){Print("CANTRADE: Max trades");lastLog=TimeCurrent();}return false;}
  if(MaxDailyLossTrades>0&&TodayLossTrades>=MaxDailyLossTrades){if(canLog){Print("CANTRADE: Loss limit");lastLog=TimeCurrent();}return false;}
  if(consecutiveLosses>=MaxConsecutiveLosses){if(canLog){Print("CANTRADE: ConsecLoss");lastLog=TimeCurrent();}return false;}
  if(!IsSpreadOK()){if(canLog){DebugPrint("CANTRADE: Spread");lastLog=TimeCurrent();}return false;}
  if(IsPositionOpen()) return false;
  if(effCooldown>0&&LastTradeCloseTime>0&&TimeCurrent()-LastTradeCloseTime<(datetime)(effCooldown*60))
  {if(canLog){Print("CANTRADE: Cooldown ",effCooldown,"m");lastLog=TimeCurrent();}return false;}
  return true; }

//===================================================================//
//  LOT SIZE
//===================================================================//
double CalculateLotSize(double slPoints)
{ double minL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),maxL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
  if(slPoints<=0) return minL;
  if(RiskMode==RISK_FIXED_LOT||FixedLot>0){ double lot=MathMax(minL,MathMin(MathMin(maxL,MaxLotLimit),FixedLot>0?FixedLot:0.01)); return NormalizeDouble(MathFloor(lot/step)*step,2); }
  double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE),ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
  if(tv<=0||ts<=0) return minL;
  double base=(RiskMode==RISK_DYNAMIC_EQ)?AccountInfoDouble(ACCOUNT_EQUITY):AccountInfoDouble(ACCOUNT_BALANCE);
  double risk=base*effRiskPct/100.0, lpl=(slPoints*_Point/ts)*tv;
  if(lpl<=0) return minL;
  double vol=MathMax(minL,MathMin(MathMin(maxL,MaxLotLimit),risk/lpl));
  return NormalizeDouble(MathFloor(vol/step)*step,2); }

//===================================================================//
//  PARTIAL TP
//===================================================================//
void PartialClosePosition(ulong ticket,double closeLots)
{ if(!PositionSelectByTicket(ticket)) return;
  ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
  double curP=pt==POSITION_TYPE_BUY?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
  MqlTradeRequest req={};MqlTradeResult res={};
  req.action=TRADE_ACTION_DEAL;req.symbol=_Symbol;req.volume=NormalizeDouble(closeLots,2);
  req.type=(pt==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;req.price=curP;req.deviation=30;
  req.magic=MAGIC_NUMBER;req.position=ticket;req.comment="ICT SMC V1.5 Partial TP";
  if(!OrderSend(req,res)) Print("Partial close failed: ",res.retcode); }

void CheckPartialTP()
{ if(!UsePartialTP) return;
  for(int i=PositionsTotal()-1;i>=0;i--)
  { ulong tk=PositionGetTicket(i); if(!PositionSelectByTicket(tk)) continue;
    if(PositionGetString(POSITION_SYMBOL)!=_Symbol||PositionGetInteger(POSITION_MAGIC)!=MAGIC_NUMBER) continue;
    string key="TWINS_PTL_"+IntegerToString(tk); if(GlobalVariableCheck(key)) continue;
    ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double entry=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),slD=MathAbs(entry-sl);
    if(slD<=0) continue;
    double price=pt==POSITION_TYPE_BUY?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
    if((pt==POSITION_TYPE_BUY?(price-entry):(entry-price))/slD<PartialCloseRR) continue;
    double vol=PositionGetDouble(POSITION_VOLUME),cv=NormalizeDouble(vol*PartialClosePercent/100.0,2);
    double minL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN); if(cv<minL) continue;
    PartialClosePosition(tk,cv); GlobalVariableSet(key,1);
    double beSL=pt==POSITION_TYPE_BUY?NormalizeDouble(entry+2*_Point,_Digits):NormalizeDouble(entry-2*_Point,_Digits);
    double cSL=PositionGetDouble(POSITION_SL),cTP=PositionGetDouble(POSITION_TP);
    bool mov=(pt==POSITION_TYPE_BUY&&(cSL==0||beSL>cSL))||(pt==POSITION_TYPE_SELL&&(cSL==0||beSL<cSL));
    if(mov) trade.PositionModify(tk,beSL,cTP); Print("PARTIAL TP: ",DoubleToString(cv,2),"lots | SL→BE"); }}

//===================================================================//
//  LOGGING
//===================================================================//
void WriteCSVLog(string type,ulong posID,bool isBuy,double entry,double sl,double tp,double lot,double profit,int score,string comment="")
{ if(!EnableCSVLog) return;
  string fname=EA_NAME+"_"+_Symbol+"_trades.csv";
  int fh=FileOpen(fname,FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON,',');
  if(fh==INVALID_HANDLE){Print("CSV failed: ",GetLastError());return;}
  FileSeek(fh,0,SEEK_END);
  MqlDateTime dt;TimeToStruct(TimeCurrent(),dt);
  string ts=StringFormat("%04d.%02d.%02d %02d:%02d:%02d",dt.year,dt.mon,dt.day,dt.hour,dt.min,dt.sec);
  FileWrite(fh,type,ts,IntegerToString(posID),(isBuy?"BUY":"SELL"),DoubleToString(entry,_Digits),DoubleToString(sl,_Digits),DoubleToString(tp,_Digits),DoubleToString(lot,2),DoubleToString(profit,2),IntegerToString(score),comment);
  FileClose(fh); }

void TakeScreenshot(string suffix)
{ if(!EnableScreenshot) return;
  MqlDateTime dt;TimeToStruct(TimeCurrent(),dt);
  string fname=StringFormat("%s_%s_%04d%02d%02d_%02d%02d%02d_%s.png",EA_NAME,_Symbol,dt.year,dt.mon,dt.day,dt.hour,dt.min,dt.sec,suffix);
  int w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS),h=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
  if(!ChartScreenShot(0,fname,w,h,ALIGN_LEFT)) Print("Screenshot failed: ",GetLastError()); }

//===================================================================//
//  V1.3 FILTER SUMMARY — printed to journal on deinit
//===================================================================//
void PrintFilterSummary()
{
   // Find dominant blocker
   int maxRej=0; string topBlocker="None";
   if(cumRejMSS>maxRej)    {maxRej=cumRejMSS;    topBlocker="MSS (H1)";}
   if(cumRejBOS>maxRej)    {maxRej=cumRejBOS;     topBlocker="BOS (M15)";}
   if(cumRejOTE>maxRej)    {maxRej=cumRejOTE;     topBlocker="OTE Zone";}
   if(cumRejH1Range>maxRej){maxRej=cumRejH1Range; topBlocker="H1 Range";}
   if(cumRejTrend>maxRej)  {maxRej=cumRejTrend;   topBlocker="Daily Trend";}
   if(cumRejScore>maxRej)  {maxRej=cumRejScore;    topBlocker="Score";}
   if(cumRejSweep>maxRej)  {maxRej=cumRejSweep;   topBlocker="Liquidity Sweep";}
   if(cumRej1MTrig>maxRej) {maxRej=cumRej1MTrig;  topBlocker="1M Trigger";}
   if(cumRejNews>maxRej)   {maxRej=cumRejNews;    topBlocker="News Filter";}
   if(cumRejHTFLevel>maxRej){maxRej=cumRejHTFLevel;topBlocker="HTF Level";}
   if(cumRejFVG>maxRej)    {maxRej=cumRejFVG;     topBlocker="FVG Count";}
   if(cumRejSMT>maxRej)    {maxRej=cumRejSMT;     topBlocker="SMT Divergence";}

   Print("╔══════════════════════════════════════════╗");
   Print("║  ",EA_NAME,"  FILTER REJECTION SUMMARY");
   Print("╠══════════════════════════════════════════╣");
   Print("║  TradingStyle : ",EnumToString(TradingStyle));
   Print("║  OTE Range    : ",DoubleToString(effOTEMin*100,0),"% - ",DoubleToString(effOTEMax*100,0),"%");
   Print("║  MSS Confirm  : ",effMSSConfirm," bars  |  BOS Confirm: ",effBOSConf," bars");
   Print("║  Body Thresh  : ",DoubleToString(effBodyThresh*100,0),"%  |  ATR Range: ",effUseATRRange?"ON":"OFF");
   Print("╠══════════════════════════════════════════╣");
   Print("║  MSS Blocks   : ",cumRejMSS);
   Print("║  BOS Blocks   : ",cumRejBOS);
   Print("║  OTE Blocks   : ",cumRejOTE);
   Print("║  H1 Range     : ",cumRejH1Range);
   Print("║  Trend Blocks : ",cumRejTrend);
   Print("║  Score Blocks : ",cumRejScore);
   Print("║  1M Trigger   : ",cumRej1MTrig);
   Print("║  Liquidity    : ",cumRejSweep);
   Print("║  FVG Blocks   : ",cumRejFVG);
   Print("║  HTF Level    : ",cumRejHTFLevel);
   Print("║  News Blocks  : ",cumRejNews);
   Print("║  SMT Blocks   : ",cumRejSMT);
   Print("╠══════════════════════════════════════════╣");
   Print("║  TOTAL BLOCKED: ",cumRejTotal," bars");
   Print("║  TRADES TAKEN : ",statTotalTrades,"  (W:",statWins," L:",statLosses,")");
   if(cumRejTotal>0)
   { double hitRate=(double)statTotalTrades/(statTotalTrades+cumRejTotal)*100.0;
     Print("║  HIT RATE     : ",DoubleToString(hitRate,1),"% of opportunities converted"); }
   Print("║  TOP BLOCKER  : *** ",topBlocker," (",maxRej," bars) ***");
   Print("╚══════════════════════════════════════════╝");
}

//===================================================================//
//  TRADE PLACEMENT
//===================================================================//
void PlaceTrade(bool isBuy=true)
{ if(IsPositionOpen()) return;
  long tradeMode=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
  if(tradeMode==SYMBOL_TRADE_MODE_DISABLED||tradeMode==SYMBOL_TRADE_MODE_CLOSEONLY) return;
  MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
  if(ForceTrades){static int fCnt=0;fCnt++;isBuy=(fCnt%2==1);Print("FORCE #",fCnt," ",(isBuy?"BUY":"SELL"));}
  double entry=isBuy?tick.ask:tick.bid;
  double swingPrice=0; FindNearestSwing(isBuy,swingPrice);
  double buffer=SLBufferPips*PipFactor*_Point;
  double sl=isBuy?NormalizeDouble(swingPrice-buffer,_Digits):NormalizeDouble(swingPrice+buffer,_Digits);
  if(isBuy&&sl>=entry){Print("SKIP: SL>=entry");return;} if(!isBuy&&sl<=entry){Print("SKIP: SL<=entry");return;}
  double slPts=MathAbs(entry-sl)/_Point; if(slPts<MinStopDistance){Print("SKIP: SL too close");return;}
  if(effMaxSLPips>0){double mx=effMaxSLPips*PipFactor; if(slPts>mx){double atr=GetATR();
    sl=isBuy?NormalizeDouble(entry-atr*1.5,_Digits):NormalizeDouble(entry+atr*1.5,_Digits);slPts=MathAbs(entry-sl)/_Point;}}
  if(effMinSLPips>0){double slP=slPts/PipFactor; if(slP<(double)effMinSLPips){Print("SKIP: SL too small ",DoubleToString(slP,1));cisd1MinConfirmed=false;return;}}
  double atr=GetATR();
  double fixRR=isBuy?NormalizeDouble(entry+slPts*_Point*RewardRiskRatio,_Digits):NormalizeDouble(entry-slPts*_Point*RewardRiskRatio,_Digits);
  double atrTP=isBuy?NormalizeDouble(entry+atr*ATRMultiplierTP,_Digits):NormalizeDouble(entry-atr*ATRMultiplierTP,_Digits);
  double tp=fixRR; if(TPMode==TP_ATR) tp=atrTP; else if(TPMode==TP_HYBRID) tp=isBuy?MathMin(fixRR,atrTP):MathMax(fixRR,atrTP);
  double rr=MathAbs(tp-entry)/MathAbs(entry-sl);
  if(rr<MinRewardRiskRatio-0.001){Print("SKIP: R:R=",DoubleToString(rr,3)," < ",MinRewardRiskRatio);cisd1MinConfirmed=false;return;}
  if(isBuy&&tp<=entry){Print("SKIP: TP below entry");return;} if(!isBuy&&tp>=entry){Print("SKIP: TP above entry");return;}
  string reason=""; if(!IsBrokerOrderSafe(isBuy,entry,sl,tp,reason)){Print("BROKER: ",reason);cisd1MinConfirmed=false;return;}
  double volume=CalculateLotSize(slPts); if(volume<=0){Print("SKIP: lot=0");return;}
  Print("══ ",EA_NAME," | ",EnumToString(TradingStyle)," | ",(isBuy?"BUY":"SELL")," | Score=",lastTradeScore," | R:R=",DoubleToString(rr,2));
  bool result=isBuy?trade.Buy(volume,_Symbol,entry,sl,tp,"ICT SMC BUY V1.5"):trade.Sell(volume,_Symbol,entry,sl,tp,"ICT SMC SELL V1.5");
  if(result)
  { TodayTradeCount++;
    cisd5MinConfirmed=false;cisd1MinConfirmed=false;mssConfirmed=false;bosConfirmed=false;liquiditySweepDone=false;fvgCount1Min=-1;
    ulong od=trade.ResultDeal();
    if(od>0&&HistoryDealSelect(od)){ulong posID=(ulong)HistoryDealGetInteger(od,DEAL_POSITION_ID);
      GlobalVariableSet("TWINS_RR_"+IntegerToString(posID),rr);
      WriteCSVLog("OPEN",posID,isBuy,entry,sl,tp,volume,0,lastTradeScore,"Score:"+IntegerToString(lastTradeScore));}
    TakeScreenshot(isBuy?"BUY_OPEN":"SELL_OPEN"); }
  else{Print("TRADE FAILED: ",trade.ResultRetcodeDescription());cisd1MinConfirmed=false;} }

void ApplyTrailingStop()
{ if(!UseTrailingStop) return;
  for(int i=PositionsTotal()-1;i>=0;i--)
  { ulong tk=PositionGetTicket(i); if(tk==0||!PositionSelectByTicket(tk)) continue;
    if(PositionGetString(POSITION_SYMBOL)!=_Symbol||PositionGetInteger(POSITION_MAGIC)!=MAGIC_NUMBER) continue;
    ENUM_POSITION_TYPE tp2=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double op=PositionGetDouble(POSITION_PRICE_OPEN),cSL=PositionGetDouble(POSITION_SL),cTP=PositionGetDouble(POSITION_TP);
    double price=tp2==POSITION_TYPE_BUY?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
    double pp=tp2==POSITION_TYPE_BUY?(price-op)/_Point/PipFactor:(op-price)/_Point/PipFactor;
    if(pp<TrailingStartPips) continue;
    double nSL=tp2==POSITION_TYPE_BUY?NormalizeDouble(price-TrailingStepPips*PipFactor*_Point,_Digits):NormalizeDouble(price+TrailingStepPips*PipFactor*_Point,_Digits);
    bool mod=(tp2==POSITION_TYPE_BUY&&(cSL==0||nSL>cSL))||(tp2==POSITION_TYPE_SELL&&(cSL==0||nSL<cSL));
    if(mod) trade.PositionModify(tk,nSL,cTP); }}

void ApplyBreakeven()
{ if(!UseBreakeven) return;
  for(int i=PositionsTotal()-1;i>=0;i--)
  { ulong tk=PositionGetTicket(i); if(tk==0||!PositionSelectByTicket(tk)) continue;
    if(PositionGetString(POSITION_SYMBOL)!=_Symbol||PositionGetInteger(POSITION_MAGIC)!=MAGIC_NUMBER) continue;
    ENUM_POSITION_TYPE tp2=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double op=PositionGetDouble(POSITION_PRICE_OPEN),cSL=PositionGetDouble(POSITION_SL),cTP=PositionGetDouble(POSITION_TP);
    double price=tp2==POSITION_TYPE_BUY?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
    double pp=tp2==POSITION_TYPE_BUY?(price-op)/_Point/PipFactor:(op-price)/_Point/PipFactor;
    if(pp<BreakevenTriggerPips) continue;
    double beSL=tp2==POSITION_TYPE_BUY?NormalizeDouble(op+2*_Point,_Digits):NormalizeDouble(op-2*_Point,_Digits);
    bool mod=(tp2==POSITION_TYPE_BUY&&(cSL==0||beSL>cSL))||(tp2==POSITION_TYPE_SELL&&(cSL==0||beSL<cSL));
    if(mod) trade.PositionModify(tk,beSL,cTP); }}

void CheckFridayClose()
{ if(!CloseOnFriday||!IsFridayCutoff()) return;
  for(int i=PositionsTotal()-1;i>=0;i--)
  { ulong tk=PositionGetTicket(i); if(tk>0&&PositionSelectByTicket(tk))
    if(PositionGetString(POSITION_SYMBOL)==_Symbol&&PositionGetInteger(POSITION_MAGIC)==MAGIC_NUMBER) trade.PositionClose(tk); }}

//===================================================================//
//  DRAWING
//===================================================================//
void DrawOTEZone(double hi,double lo)
{ if(hi<=0||lo<=0||hi<=lo) return;
  if(MathAbs(hi-lastOTEHigh)<_Point*2&&MathAbs(lo-lastOTELow)<_Point*2) return;
  lastOTEHigh=hi;lastOTELow=lo;
  for(int i=0;i<4;i++){if(OTEObjectNames[i]!="")ObjectDelete(0,OTEObjectNames[i]);}
  double range=hi-lo,oteLow=lo+range*effOTEMin,oteHigh=lo+range*effOTEMax;
  double oteRange=oteHigh-oteLow,buyTop=oteLow+oteRange*0.35,sellBtm=oteHigh-oteRange*0.35;
  datetime t0=iTime(_Symbol,PERIOD_H1,20),t1=iTime(_Symbol,PERIOD_H1,0)+(datetime)(PeriodSeconds(PERIOD_H1)*10);
  string names[]={"OTEZO_BG","OTEZO_BUY","OTEZO_SELL","OTEZO_MID"};
  double prices[4][2]={{oteLow,oteHigh},{oteLow,buyTop},{sellBtm,oteHigh},{buyTop,sellBtm}};
  color  colors[4]={C'50,70,35',C'20,110,55',C'110,35,20',C'60,60,30'};
  for(int i=0;i<4;i++){OTEObjectNames[i]=names[i];ObjectCreate(0,names[i],OBJ_RECTANGLE,0,t0,prices[i][0],t1,prices[i][1]);
    ObjectSetInteger(0,names[i],OBJPROP_COLOR,colors[i]);ObjectSetInteger(0,names[i],OBJPROP_BACK,true);
    ObjectSetInteger(0,names[i],OBJPROP_FILL,true);ObjectSetInteger(0,names[i],OBJPROP_SELECTABLE,false);}
  ChartRedraw(0); }

void DrawSwingLine(double price,bool isBuy,string source)
{ if(!ShowSwingLines) return;
  if(SwingLineNames[SwingLineIndex]!="") ObjectDelete(0,SwingLineNames[SwingLineIndex]);
  string name="SwingLine_"+source+"_"+IntegerToString(SwingLineIndex);
  SwingLineNames[SwingLineIndex]=name; SwingLineIndex=(SwingLineIndex+1)%MaxSwingLines;
  ObjectCreate(0,name,OBJ_HLINE,0,0,price);
  ObjectSetInteger(0,name,OBJPROP_COLOR,isBuy?clrDodgerBlue:clrOrangeRed);
  ObjectSetInteger(0,name,OBJPROP_WIDTH,1);ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH);ChartRedraw(0); }

//===================================================================//
//  PANEL HELPERS
//===================================================================//
void PanelLoadPosition(){string kx=PANEL_PREFIX+"PX",ky=PANEL_PREFIX+"PY";if(GlobalVariableCheck(kx))PANEL_X=(int)GlobalVariableGet(kx);if(GlobalVariableCheck(ky))PANEL_Y=(int)GlobalVariableGet(ky);}
void PanelSavePosition(){GlobalVariableSet(PANEL_PREFIX+"PX",PANEL_X);GlobalVariableSet(PANEL_PREFIX+"PY",PANEL_Y);}
void PanelDeleteAll(){ObjectsDeleteAll(0,PANEL_PREFIX);Comment("");}
void PanelDeleteBody(){int tot=ObjectsTotal(0);for(int i=tot-1;i>=0;i--){string nm=ObjectName(0,i);if(StringFind(nm,PANEL_PREFIX)==0&&nm!=PANEL_PREFIX+"Header"&&nm!=PANEL_PREFIX+"ToggleBtn"&&nm!=PANEL_PREFIX+"HdrBG"&&nm!=PANEL_PREFIX+"Title"&&nm!=PANEL_PREFIX+"Author"&&nm!=PANEL_PREFIX+"BG")ObjectDelete(0,nm);}}
void PanelRect(string name,int x,int y,int w,int h,color bg,color border=clrNONE){string full=PANEL_PREFIX+name;if(ObjectFind(0,full)<0){ObjectCreate(0,full,OBJ_RECTANGLE_LABEL,0,0,0);ObjectSetInteger(0,full,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,full,OBJPROP_HIDDEN,true);}ObjectSetInteger(0,full,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,full,OBJPROP_YDISTANCE,y);ObjectSetInteger(0,full,OBJPROP_XSIZE,w);ObjectSetInteger(0,full,OBJPROP_YSIZE,h);ObjectSetInteger(0,full,OBJPROP_BGCOLOR,bg);ObjectSetInteger(0,full,OBJPROP_BORDER_TYPE,BORDER_FLAT);ObjectSetInteger(0,full,OBJPROP_COLOR,border==clrNONE?bg:border);ObjectSetInteger(0,full,OBJPROP_BACK,false);ObjectSetInteger(0,full,OBJPROP_CORNER,CORNER_LEFT_UPPER);}
void PanelLabel(string name,int x,int y,string text,color clr,int sz=8,string font="Consolas"){string full=PANEL_PREFIX+name;if(ObjectFind(0,full)<0){ObjectCreate(0,full,OBJ_LABEL,0,0,0);ObjectSetInteger(0,full,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,full,OBJPROP_HIDDEN,true);ObjectSetInteger(0,full,OBJPROP_CORNER,CORNER_LEFT_UPPER);}ObjectSetInteger(0,full,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,full,OBJPROP_YDISTANCE,y);ObjectSetString(0,full,OBJPROP_TEXT,text);ObjectSetInteger(0,full,OBJPROP_COLOR,clr);ObjectSetInteger(0,full,OBJPROP_FONTSIZE,sz);ObjectSetString(0,full,OBJPROP_FONT,font);}
void PanelLabelC(string name,int y,string text,color clr,int sz=8,string font="Consolas"){string full=PANEL_PREFIX+name;int cx=PANEL_X+PANEL_W/2;if(ObjectFind(0,full)<0){ObjectCreate(0,full,OBJ_LABEL,0,0,0);ObjectSetInteger(0,full,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,full,OBJPROP_HIDDEN,true);ObjectSetInteger(0,full,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,full,OBJPROP_ANCHOR,ANCHOR_UPPER);}ObjectSetInteger(0,full,OBJPROP_XDISTANCE,cx);ObjectSetInteger(0,full,OBJPROP_YDISTANCE,y);ObjectSetString(0,full,OBJPROP_TEXT,text);ObjectSetInteger(0,full,OBJPROP_COLOR,clr);ObjectSetInteger(0,full,OBJPROP_FONTSIZE,sz);ObjectSetString(0,full,OBJPROP_FONT,font);}

//===================================================================//
//  DISPLAY PANEL V1.3
//===================================================================//
void UpdateDisplay()
{ if(TimeCurrent()-LastDisplayUpdate<2) return; LastDisplayUpdate=TimeCurrent();
  double balance=AccountInfoDouble(ACCOUNT_BALANCE),equity=AccountInfoDouble(ACCOUNT_EQUITY),pnl=equity-balance;
  double spread=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;
  bool inSess=IsTradingTime(),spreadOK=IsSpreadOK();
  datetime tSrv=TimeCurrent(),tGMT=TimeGMT();
  int detOff=(int)MathRound((double)(tSrv-tGMT)/3600.0);
  MqlDateTime dtS;TimeToStruct(tSrv,dtS); MqlDateTime dtG;TimeToStruct(tGMT,dtG);
  string srvT=StringFormat("%02d:%02d:%02d",dtS.hour,dtS.min,dtS.sec);
  string gmtT=StringFormat("%02d:%02d:%02d",dtG.hour,dtG.min,dtG.sec);
  string offL="GMT"+(detOff>=0?"+":"")+IntegerToString(detOff);
  bool offOK=(detOff==BrokerGMTOffset);
  double fast[1],slow[1]; string trendStr="FLAT";
  if(CopyBuffer(FastEMAHandle,0,1,1,fast)==1&&CopyBuffer(SlowEMAHandle,0,1,1,slow)==1)
    trendStr=(fast[0]>slow[0])?"BULLISH":(fast[0]<slow[0])?"BEARISH":"FLAT";
  MqlRates rates[2]; string candleStr="DOJI";
  if(CopyRates(_Symbol,PERIOD_M15,0,2,rates)==2)
    candleStr=(rates[1].close>rates[1].open)?"BULLISH":(rates[1].close<rates[1].open)?"BEARISH":"DOJI";
  bool inOTE=IsInOTEZone(SymbolInfoDouble(_Symbol,SYMBOL_BID),lastSwingHighH1,lastSwingLowH1);
  int effFVG=GetEffectiveFVGReq();
  if(equity>sessionPeakEquity&&sessionPeakEquity>0) sessionPeakEquity=equity;
  double curDD=(sessionPeakEquity>0)?sessionPeakEquity-equity:0;
  if(curDD>sessionMaxDrawdown) sessionMaxDrawdown=curDD;
  double wr2=(statTotalTrades>0)?(double)statWins/statTotalTrades*100.0:0;
  double avgRR2=(statWins>0)?statSumRR/statWins:0;
  double pf2=(statTotalLoss>0)?statTotalProfit/statTotalLoss:0;
  double netPnL=statTotalProfit-statTotalLoss;
  if(GlobalVariableCheck(PANEL_PREFIX+"Hidden")) panelHidden=(GlobalVariableGet(PANEL_PREFIX+"Hidden")>0.5);
  PanelLoadPosition();
  int x=PANEL_X,w=PANEL_W,lh=PANEL_LINE_H,px=x+8,vx=px+152,rowTop=2,row=0,hdrH=52,yb=PANEL_Y;
  PanelRect("BG",x,yb,w,panelHidden?hdrH:920,PANEL_BG,PANEL_BORDER);
  PanelRect("HdrBG",x,yb,w,hdrH,PANEL_HDR_BG,PANEL_BORDER);
  PanelLabelC("Title",yb+6,EA_NAME,PANEL_GOLD,12);
  PanelLabelC("Author",yb+28,"Created by: RATTANA CHHORM",clrWhite,9);
  PanelLabel("Header",px,yb+4,"[drag]",C'50,50,70',7); ObjectSetInteger(0,PANEL_PREFIX+"Header",OBJPROP_SELECTABLE,true);
  PanelLabel("ToggleBtn",x+w-50,yb+4,panelHidden?"[show]":"[hide]",PANEL_BLUE,8); ObjectSetInteger(0,PANEL_PREFIX+"ToggleBtn",OBJPROP_SELECTABLE,true);
  if(panelHidden){ChartRedraw(0);return;}
  int y=yb+hdrH;
  PanelRect("HdrBG",x,yb,w,hdrH,PANEL_HDR_BG,PANEL_BORDER); PanelLabelC("Title",yb+6,EA_NAME,PANEL_GOLD,12);
  PanelLabelC("Author",yb+28,"Created by: RATTANA CHHORM",clrWhite,9);
  PanelLabel("ToggleBtn",x+w-50,yb+4,"[hide]",PANEL_BLUE,8); PanelLabel("Header",px,yb+4,"[drag]",C'50,50,70',7);
  row=0;
  PanelLabel("BalL",px,y+row*lh+rowTop,"Balance  :",PANEL_TXT); PanelLabel("BalV",vx,y+row*lh+rowTop,"$"+DoubleToString(balance,2),PANEL_GREEN); row++;
  color eqC=pnl>=0?PANEL_GREEN:PANEL_RED; PanelLabel("EqL",px,y+row*lh+rowTop,"Equity   :",PANEL_TXT); PanelLabel("EqV",vx,y+row*lh+rowTop,"$"+DoubleToString(equity,2)+"  (P/L:$"+DoubleToString(pnl,2)+")",eqC); row++;
  PanelLabel("BkHd",px,y+row*lh+rowTop,"BROKER TIME:",PANEL_GOLD); row++;
  PanelLabel("BkSl",px,y+row*lh+rowTop,"Server Time:",PANEL_TXT); PanelLabel("BkSv",vx,y+row*lh+rowTop,srvT,PANEL_TXT); row++;
  PanelLabel("BkGl",px,y+row*lh+rowTop,"GMT Time   :",PANEL_TXT); PanelLabel("BkGv",vx,y+row*lh+rowTop,gmtT,PANEL_TXT); row++;
  PanelLabel("BkOl",px,y+row*lh+rowTop,"GMT Offset :",PANEL_TXT);
  PanelLabel("BkOv",vx,y+row*lh+rowTop,offL+(offOK?"":" [input:"+IntegerToString(BrokerGMTOffset)+"]"),offOK?PANEL_GOLD:PANEL_RED); row++;
  PanelLabel("SeL",px,y+row*lh+rowTop,"Session  :",PANEL_TXT); PanelLabel("SeV",vx,y+row*lh+rowTop,inSess?"ACTIVE":"CLOSED",inSess?PANEL_GREEN:PANEL_RED); row++;
  color tC=trendStr=="BULLISH"?PANEL_GREEN:trendStr=="BEARISH"?PANEL_RED:PANEL_TXT;
  PanelLabel("TrL",px,y+row*lh+rowTop,"Trend    :",PANEL_TXT); PanelLabel("TrV",vx,y+row*lh+rowTop,trendStr,tC); row++;
  color cC=candleStr=="BULLISH"?PANEL_GREEN:candleStr=="BEARISH"?PANEL_RED:PANEL_TXT;
  PanelLabel("CnL",px,y+row*lh+rowTop,"Candle   :",PANEL_TXT); PanelLabel("CnV",vx,y+row*lh+rowTop,candleStr,cC); row++;
  PanelLabel("SpL",px,y+row*lh+rowTop,"Spread   :",PANEL_TXT); PanelLabel("SpV",vx,y+row*lh+rowTop,DoubleToString(spread,0)+" pts "+(spreadOK?"OK":"BLOCKED"),spreadOK?PANEL_GREEN:PANEL_RED); row++;
  PanelLabel("TdL",px,y+row*lh+rowTop,"Trades   :",PANEL_TXT); PanelLabel("TdV",vx,y+row*lh+rowTop,IntegerToString(TodayTradeCount)+"/"+IntegerToString(MaxTradesPerDay),PANEL_TXT); row++;
  bool dl=(MaxDailyLossTrades>0&&TodayLossTrades>=MaxDailyLossTrades);
  PanelLabel("DLl",px,y+row*lh+rowTop,"Day Loss :",PANEL_TXT); PanelLabel("DLv",vx,y+row*lh+rowTop,IntegerToString(TodayLossTrades)+"/"+IntegerToString(MaxDailyLossTrades)+(dl?" HALTED":""),dl?PANEL_RED:PANEL_TXT); row++;
  PanelLabel("CLl",px,y+row*lh+rowTop,"ConLoss  :",PANEL_TXT); PanelLabel("CLv",vx,y+row*lh+rowTop,IntegerToString(consecutiveLosses)+"/"+IntegerToString(MaxConsecutiveLosses),consecutiveLosses>5?PANEL_RED:PANEL_TXT); row++;
  PanelLabel("WSl",px,y+row*lh+rowTop,"WinStreak:",PANEL_TXT); PanelLabel("WSv",vx,y+row*lh+rowTop,IntegerToString(consecutiveWins),consecutiveWins>0?PANEL_GREEN:PANEL_TXT); row++;
  // ICT Sequence
  PanelLabel("SeqH",px,y+row*lh+rowTop,"ICT SMC V1.5 SEQUENCE:",PANEL_GOLD); row++;
  string s1v=!HTFLevelRequired?"DISABLED":(htfLevelReached?"PASS":"WAIT"); color s1c=!HTFLevelRequired?PANEL_GOLD:(htfLevelReached?PANEL_GREEN:PANEL_TXT);
  PanelLabel("S1l",px,y+row*lh+rowTop,"[1] HTF Level :",PANEL_TXT); PanelLabel("S1v",vx,y+row*lh+rowTop,s1v,s1c); row++;
  string s2lbl=effUseMSSFilter?"[2] MSS H1    :":"[2] 5M CISD   :";
  PanelLabel("S2l",px,y+row*lh+rowTop,s2lbl,PANEL_TXT); PanelLabel("S2v",vx,y+row*lh+rowTop,mssConfirmed?"CONFIRMED ("+(mssIsBullish?"BULL":"BEAR")+")":"waiting...",mssConfirmed?PANEL_GREEN:PANEL_TXT); row++;
  string s3v=!effUseBOSFilter?"OFF":(bosConfirmed?"CONFIRMED ("+(bosIsBullish?"BULL":"BEAR")+")":"waiting..."); color s3c=!effUseBOSFilter?PANEL_GOLD:(bosConfirmed?PANEL_GREEN:PANEL_TXT);
  PanelLabel("S3l",px,y+row*lh+rowTop,"[3] BOS M15   :",PANEL_TXT); PanelLabel("S3v",vx,y+row*lh+rowTop,s3v,s3c); row++;
  string s4v=!effRequireLiqSweep?"OFF":(liquiditySweepDone?"DONE":"waiting..."); color s4c=!effRequireLiqSweep?PANEL_GOLD:(liquiditySweepDone?PANEL_GREEN:PANEL_TXT);
  PanelLabel("S4l",px,y+row*lh+rowTop,"[4] Liquidity :",PANEL_TXT); PanelLabel("S4v",vx,y+row*lh+rowTop,s4v,s4c); row++;
  string s5v=IntegerToString(fvgCount1Min)+"/"+IntegerToString(effFVG)+(RelaxedMode?" (R)":"");
  PanelLabel("S5l",px,y+row*lh+rowTop,"[5] 1M FVGs   :",PANEL_TXT); PanelLabel("S5v",vx,y+row*lh+rowTop,s5v,(fvgCount1Min>=effFVG||effFVG==0)?PANEL_GREEN:PANEL_TXT); row++;
  PanelLabel("S6l",px,y+row*lh+rowTop,"[6] H1 Swings :",PANEL_TXT); PanelLabel("S6v",vx,y+row*lh+rowTop,lastSwingHighH1>0?"PASS":"WAIT",lastSwingHighH1>0?PANEL_GREEN:PANEL_TXT); row++;
  bool m15ok=lastSwingHighM15>0||lastSwingLowM15>0;
  PanelLabel("S7l",px,y+row*lh+rowTop,"[7] M15 Swings:",PANEL_TXT); PanelLabel("S7v",vx,y+row*lh+rowTop,m15ok?"PASS":"ATR FB",m15ok?PANEL_GREEN:PANEL_GOLD); row++;
  PanelLabel("SvH",px,y+row*lh+rowTop,"-- LIVE ENTRY --",C'80,80,100'); row++;
  PanelLabel("SOl",px,y+row*lh+rowTop,"[*] OTE Zone  :",PANEL_TXT); PanelLabel("SOv",vx,y+row*lh+rowTop,inOTE?"PASS":"WAIT",inOTE?PANEL_GREEN:PANEL_TXT); row++;
  PanelLabel("S9l",px,y+row*lh+rowTop,"[*] 1M Trigger:",PANEL_TXT); PanelLabel("S9v",vx,y+row*lh+rowTop,cisd1MinConfirmed?"READY ("+(cisd1MinIsBearish?"BEAR":"BULL")+")":"waiting...",cisd1MinConfirmed?PANEL_GREEN:PANEL_TXT); row++;
  string sdV=(mssConfirmed&&cisd1MinConfirmed)?(mssIsBullish==!cisd1MinIsBearish?"AGREE":"CONFLICT"):"WAIT";
  PanelLabel("SDl",px,y+row*lh+rowTop,"[*] Direction :",PANEL_TXT); PanelLabel("SDv",vx,y+row*lh+rowTop,sdV,sdV=="AGREE"?PANEL_GREEN:sdV=="CONFLICT"?PANEL_RED:PANEL_TXT); row++;
  string scS=IntegerToString(lastTradeScore)+"/100 (min "+(UseTradeScore?IntegerToString(effMinScore):"OFF")+")";
  color scC=(UseTradeScore&&lastTradeScore<effMinScore)?PANEL_RED:(lastTradeScore>0?PANEL_GREEN:PANEL_TXT);
  PanelLabel("SCl",px,y+row*lh+rowTop,"[*] Score     :",PANEL_TXT); PanelLabel("SCv",vx,y+row*lh+rowTop,scS,scC); row++;
  PanelLabel("TFl",px,y+row*lh+rowTop,"[*] D1 Trend  :",PANEL_TXT); PanelLabel("TFv",vx,y+row*lh+rowTop,effUseDailyTrend?"ON":"OFF",effUseDailyTrend?PANEL_TXT:PANEL_GOLD); row++;
  if(UseNewsFilter){PanelLabel("NWl",px,y+row*lh+rowTop,"News Filter:",PANEL_TXT); PanelLabel("NWv",vx,y+row*lh+rowTop,newsBlocked?"BLOCKED":"CLEAR",newsBlocked?PANEL_RED:PANEL_GREEN); row++;}
  string lbv=lastFailedStep>0?"STEP "+IntegerToString(lastFailedStep)+" — "+lastFailedStepDesc:"None";
  PanelLabel("LBl",px,y+row*lh+rowTop,"Last Block   :",PANEL_TXT); PanelLabel("LBv",vx,y+row*lh+rowTop,lbv,lastFailedStep>0?PANEL_GOLD:PANEL_GREEN); row++;
  // V1.3: top blocker highlight
  int maxRej=0; string topB="None";
  if(cumRejMSS>maxRej){maxRej=cumRejMSS;topB="MSS";} if(cumRejBOS>maxRej){maxRej=cumRejBOS;topB="BOS";}
  if(cumRejOTE>maxRej){maxRej=cumRejOTE;topB="OTE";} if(cumRejH1Range>maxRej){maxRej=cumRejH1Range;topB="H1Range";}
  if(cumRejTrend>maxRej){maxRej=cumRejTrend;topB="Trend";} if(cumRejScore>maxRej){maxRej=cumRejScore;topB="Score";}
  if(cumRej1MTrig>maxRej){maxRej=cumRej1MTrig;topB="1MTrig";} if(cumRejSweep>maxRej){maxRej=cumRejSweep;topB="Sweep";}
  PanelLabel("TBl",px,y+row*lh+rowTop,"Top Blocker  :",PANEL_TXT); PanelLabel("TBv",vx,y+row*lh+rowTop,topB+" ("+IntegerToString(maxRej)+")",maxRej>0?PANEL_RED:PANEL_GREEN); row++;
  // Filter rejections
  PanelLabel("FRH",px,y+row*lh+rowTop,"FILTER REJECTIONS (today):",PANEL_GOLD); row++;
  PanelLabel("FR1v",px,y+row*lh+rowTop,"HTF:"+IntegerToString(rejHTFLevel)+" MSS:"+IntegerToString(rejMSS)+" BOS:"+IntegerToString(rejBOS)+" Swp:"+IntegerToString(rejSweep),PANEL_BLUE); row++;
  PanelLabel("FR2v",px,y+row*lh+rowTop,"FVG:"+IntegerToString(rejFVG)+" H1R:"+IntegerToString(rejH1Range)+" OTE:"+IntegerToString(rejOTE)+" 1MT:"+IntegerToString(rej1MTrig),PANEL_BLUE); row++;
  PanelLabel("FR3v",px,y+row*lh+rowTop,"Scr:"+IntegerToString(rejScore)+" Trd:"+IntegerToString(rejTrend)+" SMT:"+IntegerToString(rejSMT)+" Nws:"+IntegerToString(rejNews),PANEL_BLUE); row++;
  PanelLabel("FRTl",px,y+row*lh+rowTop,"Total blocked:",PANEL_TXT); PanelLabel("FRTv",vx,y+row*lh+rowTop,IntegerToString(rejTotal)+" (cum:"+IntegerToString(cumRejTotal)+")",PANEL_TXT); row++;
  // Swings
  PanelLabel("SwH",px,y+row*lh+rowTop,"SWINGS:",PANEL_GOLD); row++;
  PanelLabel("H1l",px,y+row*lh+rowTop,"H1 :",PANEL_TXT); PanelLabel("H1v",px+40,y+row*lh+rowTop,"H="+DoubleToString(lastSwingHighH1,_Digits)+"  L="+DoubleToString(lastSwingLowH1,_Digits),PANEL_BLUE); row++;
  PanelLabel("M1l",px,y+row*lh+rowTop,"M15:",PANEL_TXT); PanelLabel("M1v",px+40,y+row*lh+rowTop,"H="+DoubleToString(lastSwingHighM15,_Digits)+"  L="+DoubleToString(lastSwingLowM15,_Digits),PANEL_BLUE); row++;
  // Sessions
  PanelLabel("SsH",px,y+row*lh+rowTop,"SESSIONS:",PANEL_GOLD); row++;
  if(SessionLondon){bool a=SessionActiveNow("London");PanelLabel("SsLl",px,y+row*lh+rowTop,"London  :",PANEL_TXT);PanelLabel("SsLv",vx,y+row*lh+rowTop,"(08-17) "+(a?"ACTIVE":"CLOSED"),a?PANEL_GREEN:PANEL_RED);row++;}
  if(SessionNewYork){bool a=SessionActiveNow("NewYork");PanelLabel("SsNl",px,y+row*lh+rowTop,"New York:",PANEL_TXT);PanelLabel("SsNv",vx,y+row*lh+rowTop,"(13-22) "+(a?"ACTIVE":"CLOSED"),a?PANEL_GREEN:PANEL_RED);row++;}
  if(OverlapLondonNY){bool a=SessionActiveNow("Overlap");PanelLabel("SsOl",px,y+row*lh+rowTop,"LDN+NY  :",PANEL_TXT);PanelLabel("SsOv",vx,y+row*lh+rowTop,"(13-17) "+(a?"ACTIVE BEST":"CLOSED"),a?PANEL_GREEN:PANEL_RED);row++;}
  if(SessionTokyo){bool a=SessionActiveNow("Tokyo");PanelLabel("SsTl",px,y+row*lh+rowTop,"Tokyo   :",PANEL_TXT);PanelLabel("SsTv",vx,y+row*lh+rowTop,"(00-09) "+(a?"ACTIVE":"CLOSED"),a?PANEL_GREEN:PANEL_RED);row++;}
  if(SessionSydney){bool a=SessionActiveNow("Sydney");PanelLabel("SsYl",px,y+row*lh+rowTop,"Sydney  :",PANEL_TXT);PanelLabel("SsYv",vx,y+row*lh+rowTop,"(22-07) "+(a?"ACTIVE":"CLOSED"),a?PANEL_GREEN:PANEL_RED);row++;}
  PanelLabel("FLl",px,y+row*lh+rowTop,"Entry Hours:",PANEL_TXT); PanelLabel("FLv",vx,y+row*lh+rowTop,effBestHoursOnly?"08:30-15:00 GMT":"(all session)",PANEL_GOLD); row++;
  PanelLabel("FPl",px,y+row*lh+rowTop,"Fri Cutoff :",PANEL_TXT); PanelLabel("FPv",vx,y+row*lh+rowTop,CloseOnFriday?(IntegerToString(FridayCloseHour)+":00 GMT"):"OFF",CloseOnFriday?PANEL_GOLD:PANEL_TXT); row++;
  // Statistics
  PanelLabel("StH",px,y+row*lh+rowTop,"STATISTICS:",PANEL_GOLD); row++;
  PanelLabel("StTl",px,y+row*lh+rowTop,"Trades  :",PANEL_TXT); PanelLabel("StTv",vx,y+row*lh+rowTop,IntegerToString(statTotalTrades)+" (W:"+IntegerToString(statWins)+" L:"+IntegerToString(statLosses)+")",PANEL_TXT); row++;
  PanelLabel("WRl",px,y+row*lh+rowTop,"Win Rate:",PANEL_TXT); PanelLabel("WRv",vx,y+row*lh+rowTop,DoubleToString(wr2,1)+"%",wr2>=55?PANEL_GREEN:wr2>=40?PANEL_GOLD:PANEL_RED); row++;
  PanelLabel("ARl",px,y+row*lh+rowTop,"Avg RR  :",PANEL_TXT); PanelLabel("ARv",vx,y+row*lh+rowTop,DoubleToString(avgRR2,2),avgRR2>=1.5?PANEL_GREEN:PANEL_TXT); row++;
  PanelLabel("PFl",px,y+row*lh+rowTop,"Profit F:",PANEL_TXT); PanelLabel("PFv",vx,y+row*lh+rowTop,DoubleToString(pf2,2),pf2>=1.5?PANEL_GREEN:pf2>=1.0?PANEL_GOLD:PANEL_RED); row++;
  PanelLabel("NPl",px,y+row*lh+rowTop,"Net P&L :",PANEL_TXT); PanelLabel("NPv",vx,y+row*lh+rowTop,"$"+DoubleToString(netPnL,2),netPnL>=0?PANEL_GREEN:PANEL_RED); row++;
  PanelLabel("DDH",px,y+row*lh+rowTop,"DRAWDOWN:",PANEL_GOLD); row++;
  PanelLabel("DCl",px,y+row*lh+rowTop,"Current :",PANEL_TXT); PanelLabel("DCv",vx,y+row*lh+rowTop,"$"+DoubleToString(curDD,2),curDD>0?PANEL_RED:PANEL_GREEN); row++;
  PanelLabel("DMl",px,y+row*lh+rowTop,"Sess Max:",PANEL_TXT); PanelLabel("DMv",vx,y+row*lh+rowTop,"$"+DoubleToString(sessionMaxDrawdown,2),PANEL_TXT); row++;
  // Config
  PanelLabel("RkL",px,y+row*lh+rowTop,"Risk Mode  :",PANEL_TXT); PanelLabel("RkV",vx,y+row*lh+rowTop,EnumToString(RiskMode)+" "+DoubleToString(effRiskPct,2)+"%",PANEL_GOLD); row++;
  PanelLabel("TpL",px,y+row*lh+rowTop,"TP Mode    :",PANEL_TXT); PanelLabel("TpV",vx,y+row*lh+rowTop,EnumToString(TPMode),PANEL_GOLD); row++;
  color stC=TradingStyle==STYLE_SMART_ACTIVE_PLUS?PANEL_BLUE:TradingStyle==STYLE_SMART_ACTIVE?PANEL_GREEN:TradingStyle==STYLE_ULTRA_ACTIVE?PANEL_RED:PANEL_GOLD;
  PanelLabel("TSl",px,y+row*lh+rowTop,"Style      :",PANEL_TXT); PanelLabel("TSv",vx,y+row*lh+rowTop,EnumToString(TradingStyle),stC); row++;
  PanelLabel("CDl",px,y+row*lh+rowTop,"Cooldown   :",PANEL_TXT); PanelLabel("CDv",vx,y+row*lh+rowTop,IntegerToString(effCooldown)+"m | MSS conf:"+IntegerToString(effMSSConfirm)+" BOS conf:"+IntegerToString(effBOSConf),PANEL_GOLD); row++;
  PanelLabel("OTl",px,y+row*lh+rowTop,"OTE Range  :",PANEL_TXT); PanelLabel("OTv",vx,y+row*lh+rowTop,DoubleToString(effOTEMin*100,0)+"%-"+DoubleToString(effOTEMax*100,0)+"%"+(effUseATRRange?" ATR":""),PANEL_GOLD); row++;
  PanelLabel("MSl",px,y+row*lh+rowTop,"Max SL Pips:",PANEL_TXT); PanelLabel("MSv",vx,y+row*lh+rowTop,IntegerToString(effMaxSLPips)+" pips",PANEL_GOLD); row++;
  bool ptp=UsePartialTP; PanelLabel("PTl",px,y+row*lh+rowTop,"Partial TP :",PANEL_TXT); PanelLabel("PTv",vx,y+row*lh+rowTop,ptp?"ON ("+DoubleToString(PartialClosePercent,0)+"% at "+DoubleToString(PartialCloseRR,1)+"R)":"OFF",ptp?PANEL_GREEN:PANEL_TXT); row++;
  PanelLabel("FTl",px,y+row*lh+rowTop,"ForceTrades:",PANEL_TXT); PanelLabel("FTv",vx,y+row*lh+rowTop,ForceTrades?"ON (TEST)":"OFF",ForceTrades?PANEL_RED:PANEL_GREEN); row++;
  PanelLabel("RMl",px,y+row*lh+rowTop,"RelaxedMode:",PANEL_TXT); PanelLabel("RMv",vx,y+row*lh+rowTop,RelaxedMode?"ON (TEST)":"OFF",RelaxedMode?PANEL_GOLD:PANEL_GREEN); row++;
  int finalH=(y-yb)+row*lh+rowTop+8; ObjectSetInteger(0,PANEL_PREFIX+"BG",OBJPROP_YSIZE,finalH); ChartRedraw(0); }

//===================================================================//
//  CHART EVENT
//===================================================================//
void OnChartEvent(const int id,const long& lparam,const double& dparam,const string& sparam)
{ if(id==CHARTEVENT_OBJECT_CLICK&&sparam==PANEL_PREFIX+"ToggleBtn")
  { panelHidden=!panelHidden; GlobalVariableSet(PANEL_PREFIX+"Hidden",panelHidden?1:0);
    if(panelHidden) PanelDeleteBody(); LastDisplayUpdate=0; UpdateDisplay(); return; }
  if(id==CHARTEVENT_OBJECT_CLICK&&sparam==PANEL_PREFIX+"Header")
  {panelDragging=true;dragOffsetX=(int)lparam-PANEL_X;dragOffsetY=(int)dparam-PANEL_Y;}
  if(id==CHARTEVENT_MOUSE_MOVE&&panelDragging)
  { PANEL_X=(int)lparam-dragOffsetX;PANEL_Y=(int)dparam-dragOffsetY;
    int cW=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS),cH=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
    PANEL_X=MathMax(0,MathMin(cW-PANEL_W,PANEL_X));PANEL_Y=MathMax(0,MathMin(cH-50,PANEL_Y));
    LastDisplayUpdate=0;UpdateDisplay(); }
  if(id==CHARTEVENT_MOUSE_MOVE&&panelDragging&&dparam==0){panelDragging=false;PanelSavePosition();}
  if(id==CHARTEVENT_CLICK&&panelDragging){panelDragging=false;PanelSavePosition();} }

//===================================================================//
//  INIT / DEINIT / ONTRADE / ONTICK
//===================================================================//
int OnInit()
{ ApplySymbolPreset(); ApplyOptimizationMode(); ApplyTradingStyle();
  ATRHandle    =iATR(_Symbol,PERIOD_M15,14);
  ATRHandleH1  =iATR(_Symbol,PERIOD_H1,14);     // V1.3
  FastEMAHandle=iMA(_Symbol,PERIOD_H1,50, 0,MODE_EMA,PRICE_CLOSE);
  SlowEMAHandle=iMA(_Symbol,PERIOD_H1,200,0,MODE_EMA,PRICE_CLOSE);
  H4EMAHandle  =iMA(_Symbol,PERIOD_H4,50, 0,MODE_EMA,PRICE_CLOSE); // [V1.5] cached
  if(ATRHandle==INVALID_HANDLE||FastEMAHandle==INVALID_HANDLE||SlowEMAHandle==INVALID_HANDLE||H4EMAHandle==INVALID_HANDLE)
  {Alert(EA_NAME+": Indicator handle failed");return INIT_FAILED;}
  trade.SetExpertMagicNumber(MAGIC_NUMBER); trade.SetDeviationInPoints(30); trade.SetTypeFillingBySymbol(_Symbol);
  if(_Digits==5||_Digits==3) PipFactor=10.0; else if(_Digits==2) PipFactor=100.0; else PipFactor=1.0;
  ArrayResize(SwingLineNames,MaxSwingLines); for(int i=0;i<MaxSwingLines;i++) SwingLineNames[i]="";
  for(int i=0;i<4;i++) OTEObjectNames[i]="";
  Print("════════════════════════════════════════");
  Print(EA_NAME," — ICT SMART MONEY CONCEPTS V1.5");
  Print("Style    : ",EnumToString(TradingStyle));
  Print("OTE      : ",DoubleToString(effOTEMin*100,0),"%-",DoubleToString(effOTEMax*100,0),"%");
  Print("MSS conf : ",effMSSConfirm," bars  BOS conf: ",effBOSConf," bars");
  Print("Body thr : ",DoubleToString(effBodyThresh*100,0),"%  ATR range: ",effUseATRRange?"ON (x"+DoubleToString(effMinRangeATR,1)+")":"OFF");
  Print("Score min: ",UseTradeScore?IntegerToString(effMinScore):"OFF","  Cooldown: ",effCooldown,"m");
  Print("MSS ON: ",effUseMSSFilter,"  BOS ON: ",effUseBOSFilter,"  Trend ON: ",effUseDailyTrend);
  if(ForceTrades) Print("*** ForceTrades=ON ***");
  Print("════════════════════════════════════════");
  string pfx=EA_NAME+"_"+_Symbol+"_";
  if(GlobalVariableCheck(pfx+"Trades")) statTotalTrades=(int)GlobalVariableGet(pfx+"Trades");
  if(GlobalVariableCheck(pfx+"Wins"))   statWins       =(int)GlobalVariableGet(pfx+"Wins");
  if(GlobalVariableCheck(pfx+"Losses")) statLosses     =(int)GlobalVariableGet(pfx+"Losses");
  if(GlobalVariableCheck(pfx+"Profit")) statTotalProfit=GlobalVariableGet(pfx+"Profit");
  if(GlobalVariableCheck(pfx+"Loss"))   statTotalLoss  =GlobalVariableGet(pfx+"Loss");
  if(GlobalVariableCheck(pfx+"SumRR"))  statSumRR      =GlobalVariableGet(pfx+"SumRR");
  sessionStartEquity=AccountInfoDouble(ACCOUNT_EQUITY); sessionPeakEquity=sessionStartEquity;
  PanelLoadPosition(); return INIT_SUCCEEDED; }

void OnDeinit(const int reason)
{ if(ATRHandle    !=INVALID_HANDLE) IndicatorRelease(ATRHandle);
  if(ATRHandleH1  !=INVALID_HANDLE) IndicatorRelease(ATRHandleH1);
  if(FastEMAHandle!=INVALID_HANDLE) IndicatorRelease(FastEMAHandle);
  if(SlowEMAHandle!=INVALID_HANDLE) IndicatorRelease(SlowEMAHandle);
  if(H4EMAHandle  !=INVALID_HANDLE) IndicatorRelease(H4EMAHandle);  // [V1.5]
  for(int i=0;i<MaxSwingLines;i++) if(SwingLineNames[i]!="") ObjectDelete(0,SwingLineNames[i]);
  for(int i=0;i<4;i++) if(OTEObjectNames[i]!="") ObjectDelete(0,OTEObjectNames[i]);
  string pfx=EA_NAME+"_"+_Symbol+"_";
  GlobalVariableSet(pfx+"Trades",statTotalTrades);GlobalVariableSet(pfx+"Wins",statWins);
  GlobalVariableSet(pfx+"Losses",statLosses);GlobalVariableSet(pfx+"Profit",statTotalProfit);
  GlobalVariableSet(pfx+"Loss",statTotalLoss);GlobalVariableSet(pfx+"SumRR",statSumRR);
  PrintFilterSummary();   // V1.3: full report to journal
  PanelDeleteAll(); ObjectsDeleteAll(0,"Twins_"); ObjectsDeleteAll(0,"OTEZO_"); Comment(""); }

void OnTrade()
{ if(!HistorySelect(TimeCurrent()-86400,TimeCurrent())) return;
  for(int i=HistoryDealsTotal()-1;i>=0;i--)
  { ulong tk=HistoryDealGetTicket(i); if(tk==0) continue;
    if(HistoryDealGetString(tk,DEAL_SYMBOL)!=_Symbol||HistoryDealGetInteger(tk,DEAL_MAGIC)!=MAGIC_NUMBER||HistoryDealGetInteger(tk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
    static ulong lp=0; if(tk==lp) break; lp=tk;
    double profit=HistoryDealGetDouble(tk,DEAL_PROFIT);
    statTotalTrades++;statTotalProfit+=(profit>0)?profit:0;statTotalLoss+=(profit<0)?MathAbs(profit):0;
    ulong posID=(ulong)HistoryDealGetInteger(tk,DEAL_POSITION_ID);
    string rrKey="TWINS_RR_"+IntegerToString(posID),ptlKey="TWINS_PTL_"+IntegerToString(posID);
    if(profit>0){statWins++;consecutiveLosses=0;consecutiveWins++;if(GlobalVariableCheck(rrKey)){statSumRR+=GlobalVariableGet(rrKey);GlobalVariableDel(rrKey);}}
    else if(profit<0){statLosses++;consecutiveLosses++;consecutiveWins=0;TodayLossTrades++;if(GlobalVariableCheck(rrKey))GlobalVariableDel(rrKey);}
    if(GlobalVariableCheck(ptlKey)) GlobalVariableDel(ptlKey);
    LastTradeCloseTime=TimeCurrent();
    cisd5MinConfirmed=false;cisd1MinConfirmed=false;mssConfirmed=false;bosConfirmed=false;liquiditySweepDone=false;htfLevelReached=false;fvgCount1Min=-1;
    bool dBuy=(HistoryDealGetInteger(tk,DEAL_TYPE)==DEAL_TYPE_BUY);
    WriteCSVLog("CLOSE",posID,dBuy,HistoryDealGetDouble(tk,DEAL_PRICE),0,0,HistoryDealGetDouble(tk,DEAL_VOLUME),profit,lastTradeScore,profit>=0?"WIN":"LOSS");
    TakeScreenshot(profit>=0?"WIN_CLOSE":"LOSS_CLOSE");
    double eq=AccountInfoDouble(ACCOUNT_EQUITY);
    if(eq>sessionPeakEquity) sessionPeakEquity=eq;
    if(sessionPeakEquity-eq>sessionMaxDrawdown) sessionMaxDrawdown=sessionPeakEquity-eq;
    string pfx=EA_NAME+"_"+_Symbol+"_";
    GlobalVariableSet(pfx+"Trades",statTotalTrades);GlobalVariableSet(pfx+"Wins",statWins);
    GlobalVariableSet(pfx+"Losses",statLosses);GlobalVariableSet(pfx+"Profit",statTotalProfit);
    GlobalVariableSet(pfx+"Loss",statTotalLoss);GlobalVariableSet(pfx+"SumRR",statSumRR); break; } }

void OnTick()
{ UpdateDisplay(); CheckFridayClose(); CheckPartialTP(); ApplyBreakeven(); ApplyTrailingStop();
  if(ForceTrades){static datetime lf=0;if(TimeCurrent()-lf>=60&&CanTrade()){lf=TimeCurrent();PlaceTrade();}return;}
  if(!CanTrade()) return; if(!IsTradingTime()) return;
  datetime barTime[1]; if(CopyTime(_Symbol,PERIOD_M15,0,1,barTime)!=1) return;
  if(effCooldown>0&&LastTradeCloseTime>0&&TimeCurrent()-LastTradeCloseTime<(datetime)(effCooldown*60)) return;
  if(barTime[0]!=LastBarTime){LastBarTime=barTime[0];cisd1MinConfirmed=false;UpdateContextState();}
  bool isBuy=true; if(CheckTwinsSequence(isBuy)) PlaceTrade(isBuy); }
//+------------------------------------------------------------------+

