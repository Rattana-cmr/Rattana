//+------------------------------------------------------------------+
//|                                         SMC SCALPER V2.0         |
//|        TRUE SMART MONEY CONCEPTS M1/M5 SCALPING EA               |
//|  BOS · CHOCH · LIQUIDITY SWEEP · FVG · ORDER BLOCK · HTF         |
//|  NEWS FILTER · SCORE SYSTEM · ADVANCED RISK · ENHANCED PANEL     |
//|               Created By — RATTANA CHHORM                        |
//+------------------------------------------------------------------+
//
// V2.0 MAJOR UPGRADE from V1.0
//  [P1]  BOS + CHOCH + Liquidity Sweep + FVG + Order Block
//  [P2]  Higher Timeframe (HTF) confirmation filter
//  [P3]  Economic News Filter (MT5 Calendar API)
//  [P4]  MaxOpenPositions (1–5)
//  [P5]  Configurable Breakeven (0.5R / 1.0R / 1.5R / 2.0R)
//  [P6]  Three trailing modes (ATR / SwingHL / Fixed pips)
//  [P7]  Enhanced dashboard (Day P&L%, Win Rate, Drawdown,
//         Next Session countdown, HTF Trend, Signal Strength)
//  [P8]  Force Mode large red on-chart warning
//  [P9]  Confluence Entry Score (BOS/CHOCH/Sweep/FVG/OB = 100pts)
//  [P10] Performance: cache values, limit panel refresh rate
//
// MAGIC NUMBER: 999888
// PRESERVED:    ATR SL/TP · Partial TP · Session filter ·
//               Daily loss limit · CSV + Screenshot log
//+------------------------------------------------------------------+

#property copyright "RATTANA CHHORM"
#property version   "2.0"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//===================================================================//
//  ENUMERATIONS
//===================================================================//
enum ENUM_RISK_MODE_SC { SC_RISK_FIXED_PCT=0, SC_RISK_FIXED_LOT=1, SC_RISK_DYNAMIC_EQ=2 };
enum ENUM_TRAIL_MODE   { TRAIL_ATR=0, TRAIL_SWING=1, TRAIL_PIPS=2 };

//===================================================================//
//  CONSTANTS
//===================================================================//
const int    MAGIC_SC  = 999888;
const string EA_SC     = "SMC SCALPER V2.0";
const string PFX_SC    = "Sc2_";
const int    PANEL_REFRESH_TICKS = 5;   // [P10] refresh panel every N ticks

//===================================================================//
//  INPUTS
//===================================================================//

//--- [P1] SMC STRUCTURE DETECTION ----------------------------------
input group "========== [P1] SMC STRUCTURE =========="
input int    SwingLookback        = 20;    // Bars to scan for swings
input int    SwingConfirm         = 2;     // Confirm bars each side
input bool   UseBOS               = true;  // Enable BOS detection
input bool   UseCHOCH             = true;  // Enable CHOCH detection
input bool   UseLiqSweep          = true;  // Enable liquidity sweep
input bool   UseFVG               = true;  // Enable FVG detection
input bool   UseOB                = true;  // Enable order block
input int    StructTimeoutBars    = 30;    // SMC signal expires after N bars
input int    SweepTimeoutBars     = 10;    // Sweep signal expires after N bars
input int    FVGTimeoutBars       = 20;    // FVG zone expires after N bars

//--- [P2] HTF FILTER -----------------------------------------------
input group "========== [P2] HTF FILTER =========="
input bool              UseHTFFilter = true;          // Require HTF trend alignment
input ENUM_TIMEFRAMES   HTFPeriod    = PERIOD_M15;    // HTF (M15 for M1 / H1 for M5)
input int               HTFEMAPeriod = 50;            // HTF EMA trend period

//--- [P9] ENTRY SCORE SYSTEM ---------------------------------------
input group "========== [P9] ENTRY SCORE =========="
input int    MinEntryScore        = 60;    // Min score 0–100 to allow entry (0=off)
input int    ScoreBOS             = 20;    // +pts for BOS aligned
input int    ScoreCHOCH           = 20;    // +pts for CHOCH aligned
input int    ScoreSweep           = 20;    // +pts for liquidity sweep
input int    ScoreFVG             = 20;    // +pts for FVG (price inside zone)
input int    ScoreOB              = 20;    // +pts for order block entry
input bool   RequireFVGEntry      = false; // Only enter when price inside FVG
input bool   RequireOBEntry       = false; // Only enter when price at order block

//--- SL / TP -------------------------------------------------------
input group "========== STOP LOSS / TAKE PROFIT =========="
input double SLMultiATR           = 0.8;   // SL = ATR × this
input double TPMultiATR           = 1.6;   // TP = ATR × this (2:1 R:R default)

//--- PARTIAL TAKE PROFIT -------------------------------------------
input group "========== PARTIAL TAKE PROFIT =========="
input bool   UsePartialSC         = true;  // Close % at PartialRR, then SL→BE
input double PartialPctSC         = 50.0;  // % of position to close
input double PartialRRSC          = 1.0;   // R:R trigger for partial close

//--- [P5] BREAKEVEN ------------------------------------------------
input group "========== [P5] BREAKEVEN =========="
input bool   EnableBE             = true;  // Enable breakeven
input double BreakevenRR          = 1.0;   // R:R level to move SL to entry (0.5/1.0/1.5/2.0)

//--- [P6] TRAILING STOP --------------------------------------------
input group "========== [P6] TRAILING STOP =========="
input bool          UseTrailSC    = false;      // Enable trailing stop
input ENUM_TRAIL_MODE TrailMode   = TRAIL_ATR;  // Trail mode
input double        TrailATRMulti = 0.5;        // ATR × this (TRAIL_ATR)
input int           TrailPips     = 15;         // Fixed pips (TRAIL_PIPS)
input int           TrailSwingBars= 5;          // Look back bars (TRAIL_SWING)

//--- RISK MANAGEMENT -----------------------------------------------
input group "========== RISK MANAGEMENT =========="
input ENUM_RISK_MODE_SC RiskModeSC= SC_RISK_FIXED_PCT;
input double RiskPctSC            = 0.5;   // % balance per trade
input double FixedLotSC           = 0.0;   // Fixed lot (0=use risk%)
input double MaxLotSC             = 0.10;  // Hard lot ceiling
input double MaxDailyLossPctSC    = 10.0;  // Daily loss limit %
input int    MaxTradesPerDaySC    = 30;    // Max trades per day
input int    MaxConsecLossesSC    = 5;     // Stop after N consecutive losses

//--- [P4] MULTIPLE POSITIONS ---------------------------------------
input group "========== [P4] POSITION LIMITS =========="
input int    MaxOpenPositions     = 1;     // Max simultaneous open positions (1–5)

//--- TRADE FILTERS -------------------------------------------------
input group "========== TRADE FILTERS =========="
input int    MaxSpreadSC          = 50;    // Max spread in points
input int    ATRPeriodSC          = 14;    // ATR period
input double MinATRPipsSC         = 1.5;  // Min ATR pips — skip flat market
input int    MaxSLPipsSC          = 20;   // Max SL in pips
input int    MinSLPipsSC          = 2;    // Min SL in pips
input int    CooldownBarsSC       = 2;    // Wait N bars after trade

//--- [P3] NEWS FILTER ----------------------------------------------
input group "========== [P3] NEWS FILTER =========="
input bool   UseNewsFilter        = false; // Block trading near high-impact news
input int    NewsMinBefore        = 30;    // Block N min before news
input int    NewsMinAfter         = 30;    // Block N min after news

//--- SESSIONS (GMT) ------------------------------------------------
input group "========== SESSIONS (GMT TIME) =========="
input bool   AutoGMT_SC           = true;
input int    GMTOffsetSC          = 0;
input bool   SydneySC             = false;
input bool   TokyoSC              = false;
input bool   LondonSC             = true;
input bool   NewYorkSC            = true;
input bool   OverlapSC            = true;
input bool   AllHoursSC           = false;

//--- POSITION MANAGEMENT ------------------------------------------
input group "========== POSITION MANAGEMENT =========="
input bool   CloseFridaySC        = true;
input int    FridayHourSC         = 14;

//--- LOGGING -------------------------------------------------------
input group "========== LOGGING =========="
input bool   ScreenshotSC         = true;
input bool   CSVLogSC             = true;

//--- [P8] DEBUG / FORCE -------------------------------------------
input group "========== [P8] DEBUG =========="
input bool   ShowArrowsSC         = true;
input bool   DebugSC              = false;
input bool   ForceSC              = false; // ⚠ TEST ONLY — bypasses ALL filters

//===================================================================//
//  STRUCTS
//===================================================================//
struct SwingLevel  { double price; int bar; datetime time; bool valid; };
struct FVGZone     { double hi; double lo; bool bull; bool active; int barFormed; };
struct OBZone      { double hi; double lo; bool bull; bool active; int barFormed; };

//===================================================================//
//  GLOBAL VARIABLES
//===================================================================//
// Indicator handles
int   hATR_SC      = INVALID_HANDLE;
int   hHTFEMA      = INVALID_HANDLE;

// Timing
datetime lastBarSC   = 0;
datetime lastTradeSC = 0;
int      gmtOffsetSC = 0;
double   pipFactorSC = 10.0;
int      tickCount   = 0;         // [P10]

// SMC State (updated per bar)
SwingLevel  lastSwingHigh;
SwingLevel  lastSwingLow;
bool   bosActive      = false;    bool bosBull   = false; int bosBar    = -999;
bool   chochActive    = false;    bool chochBull = false; int chochBar  = -999;
bool   sweepActive    = false;    bool sweepBull = false; int sweepBar  = -999; double sweepLevel = 0;
FVGZone fvg;
OBZone  ob;
bool   htfBull        = false;    bool htfBear   = false;
int    lastScore      = 0;

// Daily tracking
double   dayStartBal  = 0;
double   peakEquity   = 0;        // [P7] for drawdown
double   dayWins_     = 0;
double   dayTrades_   = 0;
datetime dayDate      = 0;
int      dayTradesCnt = 0;
bool     dayLimitHit  = false;

// Stats
int    statTrades  = 0; int   statWins   = 0; int  statLosses = 0;
int    statConsec  = 0; double statPnL   = 0;

// Partial TP tracking
struct ScPartial { ulong ticket; bool done; };
ScPartial partials[];

// Panel
bool  panHid  = false;  int panX = 20;  int panY = 30;
int   panW    = 300;    int linH = 13;
int   arrowId = 0;

// Display last signal
string sigDir = "---";

// Force warning object name
const string WARN_OBJ = PFX_SC+"ForceWarn";

// Colors
color C_BG  =C'15,15,30'; color C_HDR=C'30,30,60'; color C_GOLD=clrGold;
color C_GRN =clrLime;     color C_RED=clrRed;       color C_TXT=clrSilver;
color C_BLU =C'80,120,220'; color C_BRD=C'60,60,100'; color C_WHT=clrWhite;
color C_ORG =clrOrange;

//===================================================================//
//  ONINIT
//===================================================================//
int OnInit()
{
   if(_Period > PERIOD_M5)
   { Alert(EA_SC+": Use M1 or M5 only!"); return INIT_FAILED; }

   pipFactorSC = (_Digits==2||_Digits==3) ? 100.0 : 10.0;
   gmtOffsetSC = AutoGMT_SC ? (int)((TimeCurrent()-TimeGMT())/3600) : GMTOffsetSC;

   hATR_SC = iATR(_Symbol, _Period, ATRPeriodSC);
   hHTFEMA = iMA(_Symbol, HTFPeriod, HTFEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(hATR_SC==INVALID_HANDLE || hHTFEMA==INVALID_HANDLE)
   { Alert(EA_SC+": Indicator handle failed!"); return INIT_FAILED; }

   trade.SetExpertMagicNumber(MAGIC_SC);
   trade.SetDeviationInPoints(30);
   uint ff=(uint)SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   trade.SetTypeFilling((ff&SYMBOL_FILLING_FOK)!=0?ORDER_FILLING_FOK:
                        (ff&SYMBOL_FILLING_IOC)!=0?ORDER_FILLING_IOC:ORDER_FILLING_RETURN);

   // Load stats
   string k=_Symbol+"_SC20_";
   if(GlobalVariableCheck(k+"T")) statTrades =(int)GlobalVariableGet(k+"T");
   if(GlobalVariableCheck(k+"W")) statWins   =(int)GlobalVariableGet(k+"W");
   if(GlobalVariableCheck(k+"L")) statLosses =(int)GlobalVariableGet(k+"L");
   if(GlobalVariableCheck(k+"C")) statConsec =(int)GlobalVariableGet(k+"C");
   if(GlobalVariableCheck(k+"P")) statPnL    =GlobalVariableGet(k+"P");

   dayDate    = StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   dayStartBal= AccountInfoDouble(ACCOUNT_BALANCE);
   peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   ZeroMemory(lastSwingHigh); ZeroMemory(lastSwingLow);
   ZeroMemory(fvg); ZeroMemory(ob);

   UpdateDisplay();
   Print("=== ",EA_SC," STARTED === ",_Symbol," ",EnumToString(_Period),
         " HTF:",EnumToString(HTFPeriod)," MinScore:",MinEntryScore);
   return INIT_SUCCEEDED;
}

//===================================================================//
//  ONDEINIT
//===================================================================//
void OnDeinit(const int reason)
{
   SaveStats();
   if(hATR_SC !=INVALID_HANDLE) IndicatorRelease(hATR_SC);
   if(hHTFEMA !=INVALID_HANDLE) IndicatorRelease(hHTFEMA);
   ObjectsDeleteAll(0,PFX_SC);
   Print(EA_SC,": Stopped. T=",statTrades," W=",statWins," PnL=",DoubleToString(statPnL,2));
}

//===================================================================//
//  ONTICK
//===================================================================//
void OnTick()
{
   CheckDailyReset();

   // [P10] limit panel refresh
   tickCount++;
   if(tickCount % PANEL_REFRESH_TICKS == 0) UpdateDisplay();

   // [P8] Force warning
   DrawForceWarning();

   // Friday close
   if(CloseFridaySC && IsFridayCutoff())
   { CloseAll("Friday"); UpdateDisplay(); return; }

   // Peak equity tracking [P7]
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > peakEquity) peakEquity = eq;

   // Manage positions every tick
   ManagePositions();

   if(!IsNewBar()) return;

   // ── Per-bar logic ─────────────────────────────────────────────
   UpdateSMCContext();    // rebuild SMC state on new bar

   string blockReason="";
   if(!CanTrade(blockReason))
   { if(DebugSC) Print("BLOCK: ",blockReason); return; }

   // ATR check
   double at[]; ArraySetAsSeries(at,true);
   if(CopyBuffer(hATR_SC,0,0,2,at)<2) return;
   double atrVal  = at[1];
   double atrPips = atrVal/_Point/pipFactorSC;
   if(atrPips < MinATRPipsSC)
   { if(DebugSC) Print("SKIP: ATR=",atrPips,"pips"); return; }

   // Spread check
   double spread=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   if(MaxSpreadSC>0 && spread>MaxSpreadSC)
   { if(DebugSC) Print("SKIP: Spread=",spread); return; }

   // [P3] News filter
   if(UseNewsFilter && IsNewsTime())
   { if(DebugSC) Print("SKIP: News block"); return; }

   // Score
   int scoreBuy=0, scoreSell=0;
   CalcScore(scoreBuy, scoreSell);
   lastScore = MathMax(scoreBuy, scoreSell);

   bool buyOK  = (scoreBuy  >= MinEntryScore || MinEntryScore==0);
   bool sellOK = (scoreSell >= MinEntryScore || MinEntryScore==0);

   // HTF filter [P2]
   if(UseHTFFilter)
   {
      if(buyOK  && !htfBull) buyOK  = false;
      if(sellOK && !htfBear) sellOK = false;
   }

   // FVG precision entry [P9]
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(RequireFVGEntry)
   {
      if(buyOK  && !(fvg.active && fvg.bull && ask>=fvg.lo && ask<=fvg.hi)) buyOK =false;
      if(sellOK && !(fvg.active && !fvg.bull&& bid>=fvg.lo && bid<=fvg.hi)) sellOK=false;
   }
   // OB precision entry [P9]
   if(RequireOBEntry)
   {
      if(buyOK  && !(ob.active && ob.bull  && ask>=ob.lo && ask<=ob.hi)) buyOK =false;
      if(sellOK && !(ob.active && !ob.bull && bid>=ob.lo && bid<=ob.hi)) sellOK=false;
   }

   if(ForceSC) { buyOK=true; sellOK=false; }

   if(buyOK || sellOK)
   {
      bool isBuy = buyOK;
      double entry = isBuy ? ask : bid;
      double sl = isBuy ? entry-atrVal*SLMultiATR : entry+atrVal*SLMultiATR;
      double tp = isBuy ? entry+atrVal*TPMultiATR : entry-atrVal*TPMultiATR;
      sl = NormalizeDouble(sl,_Digits);
      tp = NormalizeDouble(tp,_Digits);

      double slPips=MathAbs(entry-sl)/_Point/pipFactorSC;
      if(slPips<MinSLPipsSC||( MaxSLPipsSC>0&&slPips>MaxSLPipsSC)) return;

      double stopsLev=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
      if(MathAbs(entry-sl)<stopsLev+_Point) return;

      double lot=CalcLot(MathAbs(entry-sl));
      if(lot>0) ExecuteTrade(isBuy, sl, tp, lot, atrVal, isBuy?scoreBuy:scoreSell);
   }
}

//===================================================================//
//  UPDATE SMC CONTEXT (called once per bar)
//===================================================================//
void UpdateSMCContext()
{
   int bars = iBars(_Symbol,_Period);
   if(bars < SwingLookback+SwingConfirm+5) return;

   FindSwings();
   if(UseBOS)      DetectBOS();
   if(UseCHOCH)    DetectCHOCH();
   if(UseLiqSweep) DetectSweep();
   if(UseFVG)      DetectFVG();
   if(UseOB)       DetectOB();
   GetHTFTrend();

   // Expire old signals [P10]
   int curBar = bars;
   if(bosActive   && MathAbs(curBar-bosBar)   > StructTimeoutBars)  bosActive   = false;
   if(chochActive && MathAbs(curBar-chochBar) > StructTimeoutBars)  chochActive = false;
   if(sweepActive && MathAbs(curBar-sweepBar) > SweepTimeoutBars)   sweepActive = false;
   if(fvg.active  && MathAbs(curBar-fvg.barFormed) > FVGTimeoutBars) fvg.active = false;
   if(ob.active   && MathAbs(curBar-ob.barFormed)  > StructTimeoutBars) ob.active= false;

   // FVG consumed: price traded through it
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(fvg.active)
   {
      if(fvg.bull && bid < fvg.lo) fvg.active=false;
      if(!fvg.bull && bid> fvg.hi) fvg.active=false;
   }
   // OB consumed
   if(ob.active)
   {
      if(ob.bull  && bid < ob.lo)  ob.active=false;
      if(!ob.bull && bid > ob.hi)  ob.active=false;
   }
}

//===================================================================//
//  FIND SWINGS
//===================================================================//
void FindSwings()
{
   // Find most recent confirmed swing high and low
   int lookback = SwingLookback;
   int confirm  = SwingConfirm;

   lastSwingHigh.valid = false;
   lastSwingLow.valid  = false;

   for(int i = confirm+1; i < lookback+confirm && !lastSwingHigh.valid; i++)
   {
      double h = iHigh(_Symbol,_Period,i);
      bool ok = true;
      for(int j=1; j<=confirm && ok; j++)
         if(iHigh(_Symbol,_Period,i-j)>=h || iHigh(_Symbol,_Period,i+j)>=h) ok=false;
      if(ok)
      {
         lastSwingHigh.price = h;
         lastSwingHigh.bar   = i;
         lastSwingHigh.time  = iTime(_Symbol,_Period,i);
         lastSwingHigh.valid = true;
      }
   }

   for(int i = confirm+1; i < lookback+confirm && !lastSwingLow.valid; i++)
   {
      double l = iLow(_Symbol,_Period,i);
      bool ok = true;
      for(int j=1; j<=confirm && ok; j++)
         if(iLow(_Symbol,_Period,i-j)<=l || iLow(_Symbol,_Period,i+j)<=l) ok=false;
      if(ok)
      {
         lastSwingLow.price = l;
         lastSwingLow.bar   = i;
         lastSwingLow.time  = iTime(_Symbol,_Period,i);
         lastSwingLow.valid = true;
      }
   }
}

//===================================================================//
//  DETECT BOS (Break of Structure)
//===================================================================//
void DetectBOS()
{
   double c1 = iClose(_Symbol,_Period,1);
   int    curBars = iBars(_Symbol,_Period);

   // Bullish BOS: close breaks above recent swing high
   if(lastSwingHigh.valid && c1 > lastSwingHigh.price)
   {
      if(!bosActive || !bosBull)
      {
         bosActive = true; bosBull = true;
         bosBar    = curBars;
         if(DebugSC) Print("BOS BULL @ ",iTime(_Symbol,_Period,1)," level=",lastSwingHigh.price);
      }
   }
   // Bearish BOS: close breaks below recent swing low
   else if(lastSwingLow.valid && c1 < lastSwingLow.price)
   {
      if(!bosActive || bosBull)
      {
         bosActive = true; bosBull = false;
         bosBar    = curBars;
         if(DebugSC) Print("BOS BEAR @ ",iTime(_Symbol,_Period,1)," level=",lastSwingLow.price);
      }
   }
}

//===================================================================//
//  DETECT CHOCH (Change of Character)
//===================================================================//
void DetectCHOCH()
{
   // CHOCH: bar 1 closes in opposite direction to current structure
   // Bullish CHOCH: previously bearish (BOS bear), now price closes above swing high
   // Bearish CHOCH: previously bullish (BOS bull), now price closes below swing low
   double c1 = iClose(_Symbol,_Period,1);
   int    curBars = iBars(_Symbol,_Period);

   if(bosActive && !bosBull && lastSwingHigh.valid && c1 > lastSwingHigh.price)
   {
      chochActive = true; chochBull = true; chochBar = curBars;
      if(DebugSC) Print("CHOCH BULL @ ",iTime(_Symbol,_Period,1));
   }
   else if(bosActive && bosBull && lastSwingLow.valid && c1 < lastSwingLow.price)
   {
      chochActive = true; chochBull = false; chochBar = curBars;
      if(DebugSC) Print("CHOCH BEAR @ ",iTime(_Symbol,_Period,1));
   }
}

//===================================================================//
//  DETECT LIQUIDITY SWEEP
//===================================================================//
void DetectSweep()
{
   if(!lastSwingHigh.valid || !lastSwingLow.valid) return;

   double h1  = iHigh (_Symbol,_Period,1);
   double l1  = iLow  (_Symbol,_Period,1);
   double c1  = iClose(_Symbol,_Period,1);
   int    curBars = iBars(_Symbol,_Period);

   // Bull sweep: wick below swing low, close back above
   if(l1 < lastSwingLow.price && c1 > lastSwingLow.price)
   {
      sweepActive = true; sweepBull = true;
      sweepBar    = curBars; sweepLevel = lastSwingLow.price;
      if(DebugSC) Print("SWEEP BULL @ ",iTime(_Symbol,_Period,1)," low=",lastSwingLow.price);
   }
   // Bear sweep: wick above swing high, close back below
   else if(h1 > lastSwingHigh.price && c1 < lastSwingHigh.price)
   {
      sweepActive = true; sweepBull = false;
      sweepBar    = curBars; sweepLevel = lastSwingHigh.price;
      if(DebugSC) Print("SWEEP BEAR @ ",iTime(_Symbol,_Period,1)," high=",lastSwingHigh.price);
   }
}

//===================================================================//
//  DETECT FVG (Fair Value Gap)
//===================================================================//
void DetectFVG()
{
   // Need at least 3 bars: bar2, bar1, bar0
   // Bullish FVG: bar[2].high < bar[0].low  → gap zone = [bar2.high, bar0.low]
   // Bearish FVG: bar[2].low  > bar[0].high → gap zone = [bar0.high, bar2.low]
   double h2=iHigh(_Symbol,_Period,3), l2=iLow(_Symbol,_Period,3);
   double h0=iHigh(_Symbol,_Period,1), l0=iLow(_Symbol,_Period,1);
   int    curBars=iBars(_Symbol,_Period);

   if(h2 < l0)   // Bullish FVG
   {
      fvg.active = true; fvg.bull = true;
      fvg.lo = h2; fvg.hi = l0;
      fvg.barFormed = curBars;
      if(DebugSC) Print("FVG BULL zone=",fvg.lo,"-",fvg.hi);
   }
   else if(l2 > h0)  // Bearish FVG
   {
      fvg.active = true; fvg.bull = false;
      fvg.lo = h0; fvg.hi = l2;
      fvg.barFormed = curBars;
      if(DebugSC) Print("FVG BEAR zone=",fvg.lo,"-",fvg.hi);
   }
}

//===================================================================//
//  DETECT ORDER BLOCK
//===================================================================//
void DetectOB()
{
   if(!bosActive) return;
   int curBars=iBars(_Symbol,_Period);

   // Bullish OB: after bullish BOS, find last bearish candle before the move
   if(bosBull)
   {
      for(int i=2; i<=MathMin(30,SwingLookback); i++)
      {
         if(iClose(_Symbol,_Period,i) < iOpen(_Symbol,_Period,i))  // bearish candle
         {
            ob.active=true; ob.bull=true;
            ob.hi=iHigh(_Symbol,_Period,i); ob.lo=iLow(_Symbol,_Period,i);
            ob.barFormed=curBars;
            if(DebugSC) Print("OB BULL zone=",ob.lo,"-",ob.hi);
            break;
         }
      }
   }
   else  // Bearish OB: last bullish candle before bearish BOS
   {
      for(int i=2; i<=MathMin(30,SwingLookback); i++)
      {
         if(iClose(_Symbol,_Period,i) > iOpen(_Symbol,_Period,i))  // bullish candle
         {
            ob.active=true; ob.bull=false;
            ob.hi=iHigh(_Symbol,_Period,i); ob.lo=iLow(_Symbol,_Period,i);
            ob.barFormed=curBars;
            if(DebugSC) Print("OB BEAR zone=",ob.lo,"-",ob.hi);
            break;
         }
      }
   }
}

//===================================================================//
//  HTF TREND [P2]
//===================================================================//
void GetHTFTrend()
{
   double ema[]; ArraySetAsSeries(ema,true);
   if(CopyBuffer(hHTFEMA,0,0,2,ema)<2) return;
   double price = iClose(_Symbol,HTFPeriod,1);
   htfBull = (price > ema[1]);
   htfBear = (price < ema[1]);
}

//===================================================================//
//  CALC ENTRY SCORE [P9]
//===================================================================//
void CalcScore(int &scoreBuy, int &scoreSell)
{
   scoreBuy=0; scoreSell=0;

   // BOS
   if(bosActive && bosBull)  scoreBuy  += ScoreBOS;
   if(bosActive && !bosBull) scoreSell += ScoreBOS;

   // CHOCH
   if(chochActive && chochBull)  scoreBuy  += ScoreCHOCH;
   if(chochActive && !chochBull) scoreSell += ScoreCHOCH;

   // Liquidity Sweep
   if(sweepActive && sweepBull)  scoreBuy  += ScoreSweep;
   if(sweepActive && !sweepBull) scoreSell += ScoreSweep;

   // FVG (active and price inside zone)
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(fvg.active && fvg.bull  && ask>=fvg.lo && ask<=fvg.hi) scoreBuy  += ScoreFVG;
   if(fvg.active && !fvg.bull && bid>=fvg.lo && bid<=fvg.hi) scoreSell += ScoreFVG;

   // Order Block (active and price at OB)
   if(ob.active && ob.bull  && ask>=ob.lo && ask<=ob.hi) scoreBuy  += ScoreOB;
   if(ob.active && !ob.bull && bid>=ob.lo && bid<=ob.hi) scoreSell += ScoreOB;
}

//===================================================================//
//  EXECUTE TRADE
//===================================================================//
void ExecuteTrade(bool isBuy, double sl, double tp, double lot, double atrVal, int score)
{
   string comment = EA_SC+(isBuy?" BUY":" SELL")+" S="+IntegerToString(score);
   bool   ok = isBuy ? trade.Buy (lot,_Symbol,0,sl,tp,comment)
                     : trade.Sell(lot,_Symbol,0,sl,tp,comment);
   if(ok)
   {
      ulong  tkt  = trade.ResultOrder();
      double fill = trade.ResultPrice();
      double slP  = MathAbs(fill-sl)/_Point/pipFactorSC;
      Print(">>> TRADE ",isBuy?"BUY":"SELL"," Score=",score,
            " Lot=",lot," E=",fill," SL=",sl,"(",DoubleToString(slP,1),"p) TP=",tp);

      dayTradesCnt++; statTrades++;
      lastTradeSC=TimeCurrent();
      sigDir = isBuy?"BUY":"SELL";
      dayTrades_++;

      int sz=ArraySize(partials); ArrayResize(partials,sz+1);
      partials[sz].ticket=tkt; partials[sz].done=false;

      if(ShowArrowsSC)
      {
         string an=PFX_SC+"Arr"+IntegerToString(arrowId++);
         if(ObjectCreate(0,an,OBJ_ARROW,0,TimeCurrent(),fill))
         {
            ObjectSetInteger(0,an,OBJPROP_ARROWCODE,isBuy?233:234);
            ObjectSetInteger(0,an,OBJPROP_COLOR,isBuy?clrDodgerBlue:clrOrangeRed);
            ObjectSetInteger(0,an,OBJPROP_WIDTH,2);
            ObjectSetInteger(0,an,OBJPROP_ANCHOR,isBuy?ANCHOR_BOTTOM:ANCHOR_TOP);
         }
      }
      if(ScreenshotSC)
      {
         string fn=_Symbol+"_SC20_"+(isBuy?"BUY":"SELL")+"_"
                   +TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES)+".png";
         StringReplace(fn,":","-"); StringReplace(fn," ","_");
         ChartScreenShot(0,fn,1280,720);
      }
      if(CSVLogSC) WriteCSV(tkt,isBuy,fill,sl,tp,lot,score,atrVal);
   }
   else Print("TRADE FAIL: ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
}

//===================================================================//
//  MANAGE POSITIONS — every tick
//===================================================================//
void ManagePositions()
{
   double at[]; ArraySetAsSeries(at,true);
   bool   atrOK=(CopyBuffer(hATR_SC,0,0,3,at)>=3);

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tkt=PositionGetTicket(i);
      if(!PositionSelectByTicket(tkt)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MAGIC_SC) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)  continue;

      double pOpen=PositionGetDouble(POSITION_PRICE_OPEN);
      double pSL  =PositionGetDouble(POSITION_SL);
      double pTP  =PositionGetDouble(POSITION_TP);
      double pNow =PositionGetDouble(POSITION_PRICE_CURRENT);
      double pLots=PositionGetDouble(POSITION_VOLUME);
      bool   isBuy=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double slDist=MathAbs(pOpen-pSL);

      // ── Partial TP ──────────────────────────────────────────────
      if(UsePartialSC)
      {
         bool pdone=false;
         for(int p=0;p<ArraySize(partials);p++) if(partials[p].ticket==tkt){pdone=partials[p].done;break;}
         if(!pdone)
         {
            double partLvl = isBuy ? pOpen+slDist*PartialRRSC : pOpen-slDist*PartialRRSC;
            bool   hit     = isBuy ? (pNow>=partLvl) : (pNow<=partLvl);
            if(hit)
            {
               double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
               double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
               double cLots=MathFloor(pLots*PartialPctSC/100.0/step)*step;
               cLots=MathMax(minV,cLots);
               if(cLots<pLots) { PartialClose(tkt,cLots); ApplyBE(tkt,pOpen,pTP,pNow,isBuy,slDist); }
               for(int p=0;p<ArraySize(partials);p++) if(partials[p].ticket==tkt){partials[p].done=true;break;}
               Print("PARTIAL TP: closed ",cLots," @ ",pNow," | SL→BE");
            }
         }
      }

      // ── [P5] Configurable Breakeven ─────────────────────────────
      if(EnableBE)
      {
         double beTrigger = isBuy ? pOpen+slDist*BreakevenRR : pOpen-slDist*BreakevenRR;
         bool   beHit     = isBuy ? (pNow>=beTrigger) : (pNow<=beTrigger);
         if(beHit) ApplyBE(tkt,pOpen,pTP,pNow,isBuy,slDist);
      }

      // ── [P6] Trailing Stop ───────────────────────────────────────
      if(UseTrailSC && atrOK)
      {
         double newSL=0;
         if(TrailMode==TRAIL_ATR)
            newSL = isBuy ? pNow-at[0]*TrailATRMulti : pNow+at[0]*TrailATRMulti;
         else if(TrailMode==TRAIL_PIPS)
            newSL = isBuy ? pNow-TrailPips*_Point*pipFactorSC : pNow+TrailPips*_Point*pipFactorSC;
         else // TRAIL_SWING
         {
            double swL=0,swH=0;
            for(int b=1;b<=TrailSwingBars;b++){swL=MathMin(swL==0?iLow(_Symbol,_Period,b):swL,iLow(_Symbol,_Period,b));swH=MathMax(swH,iHigh(_Symbol,_Period,b));}
            newSL = isBuy ? swL : swH;
         }
         newSL=NormalizeDouble(newSL,_Digits);
         bool better=isBuy?(newSL>pSL+_Point):(newSL<pSL-_Point);
         if(better)
         {
            double minD=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
            bool   valid=isBuy?(newSL<pNow-minD):(newSL>pNow+minD);
            if(valid) trade.PositionModify(tkt,newSL,pTP);
         }
      }
   }
}

//===================================================================//
//  APPLY BREAKEVEN
//===================================================================//
void ApplyBE(ulong tkt, double pOpen, double pTP, double pNow, bool isBuy, double slDist)
{
   if(!PositionSelectByTicket(tkt)) return;
   double curSL=PositionGetDouble(POSITION_SL);
   double newSL=NormalizeDouble(pOpen,_Digits);
   bool   better=isBuy?(newSL>curSL+_Point):(newSL<curSL-_Point);
   if(!better) return;
   double minD=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   bool   valid=isBuy?(newSL<pNow-minD):(newSL>pNow+minD);
   if(valid) trade.PositionModify(tkt,newSL,pTP);
}

//===================================================================//
//  PARTIAL CLOSE
//===================================================================//
void PartialClose(ulong tkt, double lots)
{
   if(!PositionSelectByTicket(tkt)) return;
   ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.position=tkt; req.symbol=_Symbol; req.volume=lots;
   req.type=(pt==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   req.price=(pt==POSITION_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   req.deviation=30; req.magic=MAGIC_SC;
   req.type_filling=(ENUM_ORDER_TYPE_FILLING)trade.RequestTypeFilling();
   if(!OrderSend(req,res)) Print("PartialClose fail: ",res.retcode);
}

//===================================================================//
//  LOT CALCULATION
//===================================================================//
double CalcLot(double slDist)
{
   double lot;
   if(FixedLotSC>0||RiskModeSC==SC_RISK_FIXED_LOT)
      lot=(FixedLotSC>0)?FixedLotSC:0.01;
   else
   {
      double base=(RiskModeSC==SC_RISK_DYNAMIC_EQ)?AccountInfoDouble(ACCOUNT_EQUITY):AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmt=base*RiskPctSC/100.0;
      double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      double tickVal =SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
      if(tickSize<=0||tickVal<=0) return 0.01;
      lot=riskAmt/(slDist/tickSize*tickVal);
   }
   if(MaxLotSC>0) lot=MathMin(lot,MaxLotSC);
   return NormLot(lot);
}

double NormLot(double lot)
{
   double minL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   return NormalizeDouble(MathFloor(MathMax(minL,MathMin(maxL,lot))/step)*step,2);
}

//===================================================================//
//  CAN TRADE CHECK
//===================================================================//
bool CanTrade(string &reason)
{
   if(ForceSC) return true;
   if(dayLimitHit){reason="DailyLossLimit";return false;}
   double dayLoss=dayStartBal-AccountInfoDouble(ACCOUNT_BALANCE);
   if(dayLoss>0&&(dayLoss/dayStartBal*100.0)>=MaxDailyLossPctSC){dayLimitHit=true;reason="DailyLoss";return false;}
   if(dayTradesCnt>=MaxTradesPerDaySC){reason="MaxTrades";return false;}
   if(statConsec>=MaxConsecLossesSC){reason="ConsecLoss";return false;}
   if(CountPositions()>=MaxOpenPositions){reason="MaxPositions";return false;}
   if(!AllHoursSC&&!IsSession()){reason="OutsideSession";return false;}
   if(CooldownBarsSC>0&&lastTradeSC>0)
   { int cs=CooldownBarsSC*PeriodSeconds(_Period); if((int)(TimeCurrent()-lastTradeSC)<cs){reason="Cooldown";return false;} }
   return true;
}

int CountPositions()
{
   int n=0;
   for(int i=0;i<PositionsTotal();i++)
   { ulong t=PositionGetTicket(i); if(!PositionSelectByTicket(t)) continue;
     if(PositionGetInteger(POSITION_MAGIC)==MAGIC_SC&&PositionGetString(POSITION_SYMBOL)==_Symbol) n++; }
   return n;
}

bool IsNewBar()
{ datetime t=iTime(_Symbol,_Period,0); if(t==lastBarSC) return false; lastBarSC=t; return true; }

void CheckDailyReset()
{
   datetime today=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(today>dayDate)
   { dayDate=today; dayStartBal=AccountInfoDouble(ACCOUNT_BALANCE);
     dayTradesCnt=0; dayWins_=0; dayTrades_=0; dayLimitHit=false; statConsec=0; }
}

//===================================================================//
//  [P3] NEWS FILTER
//===================================================================//
bool IsNewsTime()
{
   MqlCalendarValue vals[];
   datetime from=TimeCurrent()-NewsMinBefore*60;
   datetime to  =TimeCurrent()+NewsMinAfter*60;
   if(CalendarValueHistory(vals,from,to,"","USD")<0) return false;
   for(int i=0;i<ArraySize(vals);i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id,ev)) continue;
      if(ev.importance==CALENDAR_IMPORTANCE_HIGH) return true;
   }
   return false;
}

//===================================================================//
//  SESSION CHECK
//===================================================================//
bool IsSession()
{
   int gh=(int)(((TimeCurrent()/3600)+gmtOffsetSC)%24); if(gh<0)gh+=24;
   return (SydneySC &&(gh>=22||gh<2)) || (TokyoSC&&gh>=0&&gh<4) ||
          (LondonSC &&gh>=8&&gh<12)   || (NewYorkSC&&gh>=13&&gh<17) ||
          (OverlapSC&&gh>=13&&gh<16);
}

bool IsFridayCutoff()
{ MqlDateTime tm; TimeCurrent(tm); if(tm.day_of_week!=5) return false;
  int gh=(int)(((TimeCurrent()/3600)+gmtOffsetSC)%24); return gh>=FridayHourSC; }

void CloseAll(string reason)
{ for(int i=PositionsTotal()-1;i>=0;i--)
  { ulong t=PositionGetTicket(i); if(!PositionSelectByTicket(t)) continue;
    if(PositionGetInteger(POSITION_MAGIC)==MAGIC_SC&&PositionGetString(POSITION_SYMBOL)==_Symbol) trade.PositionClose(t); }
  Print(EA_SC,": CloseAll=",reason); }

//===================================================================//
//  [P7] SESSION COUNTDOWN
//===================================================================//
string NextSessionCountdown()
{
   int gh=(int)(((TimeCurrent()/3600)+gmtOffsetSC)%24); if(gh<0)gh+=24;
   int target=-1; string name="";
   if(gh<8){target=8;name="London";}
   else if(gh<13){target=13;name="New York";}
   else if(gh<22){target=22;name="Sydney";}
   else{target=8;name="London(tmr)";}
   int nowSec =(int)(TimeCurrent()%86400)+(int)(gmtOffsetSC*3600);
   int tarSec = target*3600;
   if(tarSec<=nowSec%86400) tarSec+=86400;
   int rem=tarSec-(nowSec%86400); if(rem<0) rem+=86400;
   return name+" in "+IntegerToString(rem/3600)+"h"+IntegerToString((rem%3600)/60)+"m";
}

//===================================================================//
//  [P8] FORCE MODE WARNING
//===================================================================//
void DrawForceWarning()
{
   if(ForceSC)
   {
      if(ObjectFind(0,WARN_OBJ)<0)
         ObjectCreate(0,WARN_OBJ,OBJ_RECTANGLE_LABEL,0,0,0);
      int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
      int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
      ObjectSetInteger(0,WARN_OBJ,OBJPROP_XDISTANCE,cw/2-200);
      ObjectSetInteger(0,WARN_OBJ,OBJPROP_YDISTANCE,ch-80);
      ObjectSetInteger(0,WARN_OBJ,OBJPROP_XSIZE,400);
      ObjectSetInteger(0,WARN_OBJ,OBJPROP_YSIZE,40);
      ObjectSetInteger(0,WARN_OBJ,OBJPROP_BGCOLOR,clrRed);
      ObjectSetInteger(0,WARN_OBJ,OBJPROP_COLOR,clrRed);
      ObjectSetInteger(0,WARN_OBJ,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,WARN_OBJ,OBJPROP_BACK,false);
      ObjectSetInteger(0,WARN_OBJ,OBJPROP_SELECTABLE,false);

      string wt=WARN_OBJ+"T";
      if(ObjectFind(0,wt)<0) ObjectCreate(0,wt,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,wt,OBJPROP_XDISTANCE,cw/2);
      ObjectSetInteger(0,wt,OBJPROP_YDISTANCE,ch-66);
      ObjectSetString (0,wt,OBJPROP_TEXT,"⚠  WARNING: FORCE MODE ACTIVE — TEST ONLY  ⚠");
      ObjectSetInteger(0,wt,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,wt,OBJPROP_FONTSIZE,11);
      ObjectSetString (0,wt,OBJPROP_FONT,"Arial Bold");
      ObjectSetInteger(0,wt,OBJPROP_ANCHOR,ANCHOR_UPPER);
      ObjectSetInteger(0,wt,OBJPROP_BACK,false);
      ObjectSetInteger(0,wt,OBJPROP_SELECTABLE,false);
   }
   else
   { ObjectDelete(0,WARN_OBJ); ObjectDelete(0,WARN_OBJ+"T"); }
}

//===================================================================//
//  SAVE STATS
//===================================================================//
void SaveStats()
{
   string k=_Symbol+"_SC20_";
   GlobalVariableSet(k+"T",statTrades); GlobalVariableSet(k+"W",statWins);
   GlobalVariableSet(k+"L",statLosses); GlobalVariableSet(k+"C",statConsec);
   GlobalVariableSet(k+"P",statPnL);
}

//===================================================================//
//  ONTRADE TRANSACTION
//===================================================================//
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &req,const MqlTradeResult &res)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   ulong dk=trans.deal; if(!HistoryDealSelect(dk)) return;
   if(HistoryDealGetInteger(dk,DEAL_MAGIC)!=MAGIC_SC) return;
   if(HistoryDealGetInteger(dk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;
   if(HistoryDealGetString(dk,DEAL_SYMBOL)!=_Symbol) return;

   double profit=HistoryDealGetDouble(dk,DEAL_PROFIT)
                +HistoryDealGetDouble(dk,DEAL_SWAP)
                +HistoryDealGetDouble(dk,DEAL_COMMISSION);
   statPnL+=profit;
   if(profit>=0){statWins++;statConsec=0;dayWins_++;}
   else         {statLosses++;statConsec++;}
   SaveStats();

   if(ScreenshotSC)
   { string fn=_Symbol+"_SC20_CLOSE_"+(profit>=0?"WIN":"LOSS")+"_"
               +TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES)+".png";
     StringReplace(fn,":","-");StringReplace(fn," ","_");
     ChartScreenShot(0,fn,1280,720); }
}

//===================================================================//
//  CSV LOG
//===================================================================//
void WriteCSV(ulong tkt,bool isBuy,double entry,double sl,double tp,double lot,int score,double atr)
{
   int fh=FileOpen(_Symbol+"_SMC_Scalper_V2.0.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON,',');
   if(fh==INVALID_HANDLE) return;
   FileSeek(fh,0,SEEK_END);
   FileWrite(fh,IntegerToString(tkt),TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES|TIME_SECONDS),
             isBuy?"BUY":"SELL",DoubleToString(entry,_Digits),DoubleToString(sl,_Digits),
             DoubleToString(tp,_Digits),DoubleToString(lot,2),IntegerToString(score),
             DoubleToString(atr/_Point/pipFactorSC,1),EnumToString(_Period));
   FileClose(fh);
}

//===================================================================//
//  PANEL HELPERS
//===================================================================//
void ScRect(string nm,int x,int y,int w,int h,color bg,color brd)
{ string n=PFX_SC+nm; if(ObjectFind(0,n)<0)ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0);
  ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
  ObjectSetInteger(0,n,OBJPROP_XSIZE,w);ObjectSetInteger(0,n,OBJPROP_YSIZE,h);
  ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bg);ObjectSetInteger(0,n,OBJPROP_COLOR,brd);
  ObjectSetInteger(0,n,OBJPROP_BORDER_TYPE,BORDER_FLAT);
  ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
  ObjectSetInteger(0,n,OBJPROP_BACK,false);ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); }

void ScLbl(string nm,int x,int y,string txt,color clr,int sz=8)
{ string n=PFX_SC+nm; if(ObjectFind(0,n)<0)ObjectCreate(0,n,OBJ_LABEL,0,0,0);
  ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
  ObjectSetString(0,n,OBJPROP_TEXT,txt);ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
  ObjectSetInteger(0,n,OBJPROP_FONTSIZE,sz);ObjectSetString(0,n,OBJPROP_FONT,"Consolas");
  ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
  ObjectSetInteger(0,n,OBJPROP_BACK,false);ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); }

void ScLblC(string nm,int y,string txt,color clr,int sz=8)
{ string n=PFX_SC+nm; int cx=panX+panW/2; if(ObjectFind(0,n)<0)ObjectCreate(0,n,OBJ_LABEL,0,0,0);
  ObjectSetInteger(0,n,OBJPROP_XDISTANCE,cx);ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
  ObjectSetString(0,n,OBJPROP_TEXT,txt);ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
  ObjectSetInteger(0,n,OBJPROP_FONTSIZE,sz);ObjectSetString(0,n,OBJPROP_FONT,"Consolas");
  ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_UPPER);
  ObjectSetInteger(0,n,OBJPROP_BACK,false);ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); }

//===================================================================//
//  [P7] UPDATE DISPLAY (enhanced dashboard)
//===================================================================//
void UpdateDisplay()
{
   int x=panX,yb=panY,w=panW,lh=linH,hdrH=42,rt=2;
   int px=x+6, vx=x+132, y=yb+hdrH+2;

   ScRect("BG",x,yb,w,panHid?hdrH:620,C_BG,C_BRD);
   ScRect("HdrBG",x,yb,w,hdrH,C_HDR,C_BRD);
   ScLblC("Title", yb+5,  EA_SC,                       C_GOLD,11);
   ScLblC("Author",yb+24, "Created by: RATTANA CHHORM", C_WHT, 8);
   ScLbl("Drag",px,yb+4,"[drag]",C'50,50,70',7);
   ObjectSetInteger(0,PFX_SC+"Drag",OBJPROP_SELECTABLE,true);
   ScLbl("Tog",x+w-52,yb+4,panHid?"[show]":"[hide]",C_BLU,8);
   ObjectSetInteger(0,PFX_SC+"Tog",OBJPROP_SELECTABLE,true);
   if(panHid){ChartRedraw(0);return;}

   int row=0;
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq =AccountInfoDouble(ACCOUNT_EQUITY);

   // ── Account ────────────────────────────────────────────────────
   double dayPnL  = eq-dayStartBal;
   double dayPnLpct=(dayStartBal>0)?(dayPnL/dayStartBal*100.0):0;
   double dd      = (peakEquity>0)?((peakEquity-eq)/peakEquity*100.0):0;
   double dayWR   = (dayTrades_>0)?(dayWins_/dayTrades_*100.0):0;

   ScLbl("BaL",px,y+row*lh+rt,"Balance   :",C_TXT);ScLbl("BaV",vx,y+row*lh+rt,DoubleToString(bal,2)+" "+AccountInfoString(ACCOUNT_CURRENCY),C_GOLD);row++;
   ScLbl("EqL",px,y+row*lh+rt,"Equity    :",C_TXT);ScLbl("EqV",vx,y+row*lh+rt,DoubleToString(eq,2),eq>=bal?C_GRN:C_RED);row++;
   // [P7] Day P&L ($)
   ScLbl("DL",px,y+row*lh+rt,"Day P/L $ :",C_TXT);ScLbl("DV",vx,y+row*lh+rt,(dayPnL>=0?"+":"")+DoubleToString(dayPnL,2),dayPnL>=0?C_GRN:C_RED);row++;
   // [P7] Day P&L (%)
   ScLbl("DP",px,y+row*lh+rt,"Day P/L % :",C_TXT);ScLbl("DPV",vx,y+row*lh+rt,(dayPnLpct>=0?"+":"")+DoubleToString(dayPnLpct,2)+"%",dayPnLpct>=0?C_GRN:C_RED);row++;
   // [P7] Current Drawdown
   color ddClr=dd<5?C_GRN:dd<10?C_GOLD:C_RED;
   ScLbl("DDL",px,y+row*lh+rt,"Drawdown  :",C_TXT);ScLbl("DDV",vx,y+row*lh+rt,DoubleToString(dd,2)+"%",ddClr);row++;
   // [P7] Today Win Rate
   color twrC=dayWR>=55?C_GRN:dayWR>=45?C_GOLD:C_RED;
   ScLbl("TWL",px,y+row*lh+rt,"Day WinR  :",C_TXT);ScLbl("TWV",vx,y+row*lh+rt,DoubleToString(dayWR,1)+"% ("+IntegerToString((int)dayTrades_)+"T)",twrC);row++;

   // ── Session ────────────────────────────────────────────────────
   bool sessON=AllHoursSC||IsSession();
   ScLbl("SeL",px,y+row*lh+rt,"Session   :",C_TXT);ScLbl("SeV",vx,y+row*lh+rt,sessON?"ACTIVE":"CLOSED",sessON?C_GRN:C_RED);row++;
   // [P7] Next session countdown
   if(!sessON||!AllHoursSC){ScLbl("NCL",px,y+row*lh+rt,"Next Open :",C_TXT);ScLbl("NCV",vx,y+row*lh+rt,NextSessionCountdown(),C_TXT);row++;}

   // ── Market ─────────────────────────────────────────────────────
   double sprd=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   // [P7] Spread status
   color sprdC=(MaxSpreadSC>0&&sprd>MaxSpreadSC)?C_RED:C_GRN;
   string sprdS=DoubleToString(sprd,0)+" pts "+(MaxSpreadSC>0&&sprd>MaxSpreadSC?"[HIGH]":"[OK]");
   ScLbl("SpL",px,y+row*lh+rt,"Spread    :",C_TXT);ScLbl("SpV",vx,y+row*lh+rt,sprdS,sprdC);row++;

   double at2[]; ArraySetAsSeries(at2,true);
   double atrPips=0; if(CopyBuffer(hATR_SC,0,0,2,at2)>=2) atrPips=at2[1]/_Point/pipFactorSC;
   ScLbl("AtL",px,y+row*lh+rt,"ATR pips  :",C_TXT);ScLbl("AtV",vx,y+row*lh+rt,DoubleToString(atrPips,1)+" pips",atrPips>=MinATRPipsSC?C_GRN:C_RED);row++;

   // ── [P7] HTF Trend ─────────────────────────────────────────────
   string htfStr=htfBull?"BULLISH":htfBear?"BEARISH":"NEUTRAL";
   color  htfC  =htfBull?C_GRN:htfBear?C_RED:C_TXT;
   ScLbl("HtL",px,y+row*lh+rt,"HTF Trend :",C_TXT);ScLbl("HtV",vx,y+row*lh+rt,htfStr+" ("+EnumToString(HTFPeriod)+")",htfC);row++;

   // ── SMC State ──────────────────────────────────────────────────
   ScLbl("B1L",px,y+row*lh+rt,"BOS       :",C_TXT);
   ScLbl("B1V",vx,y+row*lh+rt,bosActive?(bosBull?"BULL":"BEAR"):"---",bosActive?(bosBull?C_GRN:C_RED):C_TXT);row++;
   ScLbl("C1L",px,y+row*lh+rt,"CHOCH     :",C_TXT);
   ScLbl("C1V",vx,y+row*lh+rt,chochActive?(chochBull?"BULL":"BEAR"):"---",chochActive?(chochBull?C_GRN:C_RED):C_TXT);row++;
   ScLbl("S1L",px,y+row*lh+rt,"Sweep     :",C_TXT);
   ScLbl("S1V",vx,y+row*lh+rt,sweepActive?(sweepBull?"BULL":"BEAR"):"---",sweepActive?(sweepBull?C_GRN:C_RED):C_TXT);row++;
   ScLbl("F1L",px,y+row*lh+rt,"FVG       :",C_TXT);
   ScLbl("F1V",vx,y+row*lh+rt,fvg.active?(fvg.bull?"BULL":"BEAR"):"---",fvg.active?(fvg.bull?C_GRN:C_RED):C_TXT);row++;
   ScLbl("O1L",px,y+row*lh+rt,"OB        :",C_TXT);
   ScLbl("O1V",vx,y+row*lh+rt,ob.active?(ob.bull?"BULL":"BEAR"):"---",ob.active?(ob.bull?C_GRN:C_RED):C_TXT);row++;

   // ── [P7] Signal Strength ────────────────────────────────────────
   int scoreBuy=0,scoreSell=0; CalcScore(scoreBuy,scoreSell);
   int  showScore=MathMax(scoreBuy,scoreSell);
   string sigDir2=(scoreBuy>scoreSell)?"BUY ":(scoreSell>scoreBuy)?"SELL":"---";
   color scC=showScore>=MinEntryScore?C_GRN:showScore>=(MinEntryScore/2)?C_GOLD:C_RED;
   ScLbl("ScL",px,y+row*lh+rt,"Score     :",C_TXT);
   ScLbl("ScV",vx,y+row*lh+rt,sigDir2+IntegerToString(showScore)+"/100 (min "+IntegerToString(MinEntryScore)+")",scC);row++;

   // ── Trade Stats ────────────────────────────────────────────────
   ScLbl("SgL",px,y+row*lh+rt,"Signal    :",C_TXT);
   color sigC=(sigDir=="BUY")?C_GRN:(sigDir=="SELL"?C_RED:C_TXT);
   ScLbl("SgV",vx,y+row*lh+rt,sigDir,sigC);row++;
   ScLbl("PoL",px,y+row*lh+rt,"Positions :",C_TXT);
   ScLbl("PoV",vx,y+row*lh+rt,IntegerToString(CountPositions())+"/"+IntegerToString(MaxOpenPositions),CountPositions()>0?C_GOLD:C_TXT);row++;
   color tdC=dayTradesCnt>=MaxTradesPerDaySC?C_RED:C_GRN;
   ScLbl("TdL",px,y+row*lh+rt,"Trades/D  :",C_TXT);ScLbl("TdV",vx,y+row*lh+rt,IntegerToString(dayTradesCnt)+"/"+IntegerToString(MaxTradesPerDaySC),tdC);row++;
   double wr=(statTrades>0)?(double)statWins/statTrades*100.0:0;
   ScLbl("WrL",px,y+row*lh+rt,"Win Rate  :",C_TXT);ScLbl("WrV",vx,y+row*lh+rt,DoubleToString(wr,1)+"% ("+IntegerToString(statTrades)+"T)",wr>=55?C_GRN:wr>=45?C_GOLD:C_RED);row++;
   ScLbl("TpL",px,y+row*lh+rt,"Total P&L :",C_TXT);ScLbl("TpV",vx,y+row*lh+rt,(statPnL>=0?"+":"")+DoubleToString(statPnL,2),statPnL>=0?C_GRN:C_RED);row++;
   ScLbl("RkL",px,y+row*lh+rt,"Risk      :",C_TXT);ScLbl("RkV",vx,y+row*lh+rt,SC_RiskStr(RiskModeSC)+" "+DoubleToString(RiskPctSC,2)+"%",C_GOLD);row++;
   ScLbl("FcL",px,y+row*lh+rt,"ForceMode :",C_TXT);ScLbl("FcV",vx,y+row*lh+rt,ForceSC?"ON ⚠ TEST!":"OFF",ForceSC?C_RED:C_GRN);row++;

   ObjectSetInteger(0,PFX_SC+"BG",OBJPROP_YSIZE,hdrH+2+row*lh+8);
   ChartRedraw(0);
}

//===================================================================//
//  CHART EVENT
//===================================================================//
void OnChartEvent(const int id,const long &lp,const double &dp,const string &sp)
{
   if(id==CHARTEVENT_OBJECT_DRAG&&sp==PFX_SC+"Drag")
   { panX=(int)ObjectGetInteger(0,PFX_SC+"Drag",OBJPROP_XDISTANCE);
     panY=(int)ObjectGetInteger(0,PFX_SC+"Drag",OBJPROP_YDISTANCE); UpdateDisplay(); }
   else if(id==CHARTEVENT_OBJECT_CLICK&&sp==PFX_SC+"Tog")
   { panHid=!panHid; UpdateDisplay(); }
}

//===================================================================//
//  STRING HELPERS
//===================================================================//
string SC_RiskStr(ENUM_RISK_MODE_SC m)
{ if(m==SC_RISK_FIXED_PCT)return "FIXED_PCT"; if(m==SC_RISK_FIXED_LOT)return "FIXED_LOT"; return "DYNAMIC_EQ"; }
//+------------------------------------------------------------------+
