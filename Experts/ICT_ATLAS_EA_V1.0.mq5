//+------------------------------------------------------------------+
//|                                         ICT ATLAS EA V1.0         |
//|           ICT 2022 Mentorship — Institutional Grade               |
//|  Bias · Liquidity · MSS · Displacement · FVG · PD Array          |
//|  Premium/Discount · PO3 · SMT · ADR · Scoring · Trade Mgmt       |
//|                Created By — RATTANA CHHORM                         |
//+------------------------------------------------------------------+
//
// EXECUTION FLOW:
//   Weekly Bias → Daily Bias → Liquidity Sweep → MSS → Displacement
//   → PD Array (FVG / OB / Breaker) → Premium/Discount → Killzone
//   → Entry → Advanced Trade Management
//
// ENGINES:
//  [01] Bias Engine         [11] ADR Filter
//  [02] Liquidity Engine    [12] News Filter
//  [03] Market Structure    [13] Market Condition
//  [04] Displacement        [14] Confluence Scoring
//  [05] FVG Engine          [15] Trade Quality Grade
//  [06] PD Array Engine     [16] Risk Engine
//  [07] Premium/Discount    [17] Trade Management
//  [08] Session Engine      [18] Statistics Engine
//  [09] Power of 3 Engine   [19] Visual/Draw Engine
//  [10] SMT Engine          [20] Debug Panel Engine
//
// PERFORMANCE TARGETS:
//   Win Rate 55-70%  |  Min RR 1:3  |  PF > 1.8  |  DD < 15%
//+------------------------------------------------------------------+

#property copyright "RATTANA CHHORM"
#property version   "1.0"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

CTrade Trade;

//===================================================================
// SECTION 1 — ENUMERATIONS
//===================================================================

enum ENUM_ATLAS_BIAS      { BIAS_BULLISH=1, BIAS_BEARISH=-1, BIAS_NEUTRAL=0 };
enum ENUM_ATLAS_GRADE     { GRADE_APLUS=0, GRADE_A=1, GRADE_B=2, GRADE_C=3, GRADE_NONE=4 };
enum ENUM_ATLAS_SESSION   { SES_NONE=0, SES_ASIAN=1, SES_LONDON=2, SES_NEWYORK=3 };
enum ENUM_ATLAS_CONDITION { COND_TRENDING=0, COND_RANGING=1, COND_CHOPPY=2 };
enum ENUM_ATLAS_RISKMODE  { RISK_PCT=0, RISK_LOT=1 };

enum ENUM_ATLAS_SYMPRESET
{
   SYM_AUTO   = 0,  // Auto-detect
   SYM_XAUUSD = 1,  // XAUUSD (Gold)
   SYM_EURUSD = 2,  // EURUSD
   SYM_GBPUSD = 3,  // GBPUSD
   SYM_USDJPY = 4,  // USDJPY
   SYM_BTCUSD = 5   // BTCUSD
};

enum ENUM_ATLAS_GRADES_ALLOWED
{
   GRADES_APLUS      = 0,  // A+ only (strictest)
   GRADES_A_UP       = 1,  // A+ and A
   GRADES_B_UP       = 2,  // A+, A, B
   GRADES_ALL        = 3   // All grades (C+)
};

enum ENUM_PDA_TYPE
{
   PDA_FVG         = 0,
   PDA_IFVG        = 1,
   PDA_OB          = 2,
   PDA_BREAKER     = 3,
   PDA_MITIGATION  = 4,
   PDA_LIQ_VOID    = 5,
   PDA_NDOG        = 6,
   PDA_NWOG        = 7
};

//===================================================================
// SECTION 2 — INPUT PARAMETERS
//===================================================================

//--- SYMBOL PRESET -------------------------------------------------
input group "══════════ SYMBOL PRESET ══════════"
input ENUM_ATLAS_SYMPRESET SymPreset = SYM_XAUUSD; // Symbol preset

//--- BIAS ENGINE ---------------------------------------------------
input group "══════════ [01] BIAS ENGINE ══════════"
input bool   UseBiasEngine       = true;   // Require HTF bias alignment
input bool   RequireWeeklyBias   = true;   // Require Weekly bias match
input bool   RequireDailyBias    = true;   // Require Daily bias match
input bool   RequireH4Bias       = false;  // Require H4 bias match
input int    BiasSwingLookback   = 5;      // Bars each side for swing detection

//--- LIQUIDITY ENGINE ----------------------------------------------
input group "══════════ [02] LIQUIDITY ENGINE ══════════"
input bool   UseLiquidityEngine  = true;   // Require liquidity sweep before entry
input bool   UseEQHEQL           = true;   // Detect Equal Highs / Equal Lows
input double EQHTolerance        = 5.0;    // EQH/EQL tolerance in pips
input int    LiqLookbackBars     = 50;     // How many bars back to scan for levels
input int    SweepWickMinPips    = 2;      // Min wick beyond level (pips)

//--- MARKET STRUCTURE ENGINE ---------------------------------------
input group "══════════ [03] MARKET STRUCTURE ENGINE ══════════"
input bool   UseMSSFilter        = true;   // MSS mandatory (after sweep)
input bool   UseBOSFilter        = false;  // Require BOS confirmation
input int    MSSwingLookback     = 3;      // Bars each side for MSS swing
input int    MSSLookbackBars     = 30;     // Bars to look back for MSS level

//--- DISPLACEMENT ENGINE ------------------------------------------
input group "══════════ [04] DISPLACEMENT ENGINE ══════════"
input bool   UseDispFilter       = true;   // Require displacement candle
input double DispMinBodyPct      = 0.60;   // Min body as % of candle range (0-1)
input double DispMinATRMulti     = 1.3;    // Min candle range vs ATR
input int    DispLookbackBars    = 5;      // Bars back to find displacement

//--- FVG ENGINE ---------------------------------------------------
input group "══════════ [05] FVG ENGINE ══════════"
input bool   UseFVGFilter        = true;   // Require price to retrace into FVG
input bool   UseFVGEntry         = true;   // Enter on FVG retracement
input bool   UseIFVG             = true;   // Also detect Inverse FVGs
input bool   UseCEentry          = true;   // Use CE (midpoint) as refined entry
input int    FVGMaxAgeBars       = 50;     // Max age of FVG (bars) before invalid
input int    MaxFVGsTracked      = 20;     // Max concurrent FVGs tracked
input bool   UseFVGM5            = false;  // Also scan M5 FVGs

//--- PD ARRAY ENGINE ----------------------------------------------
input group "══════════ [06] PD ARRAY ENGINE ══════════"
input bool   UsePDAEngine        = true;   // Enable PD Array selection
input bool   PDA_UseFVG          = true;   // FVG
input bool   PDA_UseIFVG         = true;   // Inverse FVG
input bool   PDA_UseOB           = true;   // Order Block
input bool   PDA_UseBreaker      = true;   // Breaker Block
input bool   PDA_UseMitigation   = false;  // Mitigation Block
input bool   PDA_UseLiqVoid      = false;  // Liquidity Void
input bool   PDA_UseNDOG         = false;  // New Day Opening Gap
input bool   PDA_UseNWOG         = false;  // New Week Opening Gap
input int    OBLookbackBars      = 10;     // Bars back to find Order Block
input int    MaxPDAsTracked      = 15;     // Max PD arrays tracked

//--- PREMIUM/DISCOUNT ENGINE --------------------------------------
input group "══════════ [07] PREMIUM / DISCOUNT ENGINE ══════════"
input bool   UsePremDiscFilter   = true;   // Require P/D filter
input double DiscountZone        = 0.50;   // Max % for discount (buys ≤ this)
input double PremiumZone         = 0.50;   // Min % for premium  (sells ≥ 1-this)
input int    DealingRangeLookback= 60;     // H4 bars for dealing range (60 = ~15 days)

//--- SESSION ENGINE -----------------------------------------------
input group "══════════ [08] SESSION & KILLZONE ENGINE ══════════"
input bool   UseSessionFilter    = true;   // Require active killzone
input int    BrokerGMTOffset     = 3;      // Broker GMT offset (hours)
input bool   AutoGMTOffset       = true;   // Auto-detect GMT offset
input bool   SessionAsian        = false;  // Trade Asian killzone
input bool   SessionLondon       = true;   // Trade London killzone
input bool   SessionNewYork      = true;   // Trade New York AM killzone
input bool   SessionNYPM         = false;  // Trade NY PM session
input int    AsianStartHour      = 0;      // Asian start (GMT)
input int    AsianEndHour        = 7;      // Asian end (GMT)
input int    LondonStartHour     = 7;      // London killzone start (GMT)
input int    LondonEndHour       = 10;     // London killzone end (GMT)
input int    NYStartHour         = 13;     // NY AM killzone start (GMT)
input int    NYEndHour           = 16;     // NY AM killzone end (GMT)
input int    NYPMStartHour       = 18;     // NY PM start (GMT)
input int    NYPMEndHour         = 20;     // NY PM end (GMT)

//--- POWER OF 3 ENGINE --------------------------------------------
input group "══════════ [09] POWER OF 3 ENGINE ══════════"
input bool   UsePO3Filter        = false;  // Require PO3 pattern (AMD)
input double PO3ManipMinPips     = 10.0;   // Min manipulation sweep size

//--- SMT DIVERGENCE ENGINE ----------------------------------------
input group "══════════ [10] SMT DIVERGENCE ENGINE ══════════"
input bool   UseSMTFilter        = false;  // Enable SMT divergence filter
input string SMTSymbol           = "XAGUSD"; // Correlated symbol
input int    SMTLookbackBars     = 5;      // Bars to compare

//--- ADR FILTER ---------------------------------------------------
input group "══════════ [11] ADR FILTER ══════════"
input bool   UseADRFilter        = true;   // Block if ADR near complete
input int    ADRPeriod           = 14;     // ADR calculation period (days)
input double ADRMaxPct           = 0.80;   // Block trade if ADR% > this

//--- NEWS FILTER --------------------------------------------------
input group "══════════ [12] NEWS FILTER ══════════"
input bool   UseNewsFilter       = true;   // Enable news blocking
input int    NewsBlockBefore     = 30;     // Minutes before news
input int    NewsBlockAfter      = 30;     // Minutes after news
// Note: Enter high-impact news times manually below (up to 8 per day)
input string NewsTime1           = "";     // News time 1 (HH:MM GMT)
input string NewsTime2           = "";     // News time 2 (HH:MM GMT)
input string NewsTime3           = "";     // News time 3 (HH:MM GMT)
input string NewsTime4           = "";     // News time 4 (HH:MM GMT)
input string NewsTime5           = "";     // News time 5 (HH:MM GMT)
input string NewsTime6           = "";     // News time 6 (HH:MM GMT)
input string NewsTime7           = "";     // News time 7 (HH:MM GMT)
input string NewsTime8           = "";     // News time 8 (HH:MM GMT)

//--- MARKET CONDITION FILTER --------------------------------------
input group "══════════ [13] MARKET CONDITION FILTER ══════════"
input bool   UseConditionFilter  = true;   // Enable market condition filter
input bool   TradeInTrend        = true;   // Trade in trending market
input bool   TradeInRanging      = false;  // Trade in ranging market
input bool   TradeInChoppy       = false;  // Trade in choppy market
input int    CondADXPeriod       = 14;     // ADX period
input double CondADXTrend        = 25.0;   // ADX threshold for trending
input double CondADXChoppy       = 18.0;   // ADX threshold below = choppy

//--- SPREAD / SLIPPAGE -------------------------------------------
input group "══════════ [15-16] SPREAD & SLIPPAGE FILTERS ══════════"
input int    MaxSpreadPips       = 50;     // Max spread (pips) — 0 = no check
input int    MaxSlippagePips     = 5;      // Max slippage allowed

//--- CORRELATION FILTER ------------------------------------------
input group "══════════ [17] CORRELATION FILTER ══════════"
input bool   UseCorrelFilter     = false;  // Enable correlation filter
input string CorrelSymbol        = "DXY";  // Correlated symbol to check

//--- CONFLUENCE SCORING SYSTEM -----------------------------------
input group "══════════ [18] CONFLUENCE SCORING SYSTEM ══════════"
input bool   UseScoringSystem    = true;   // Enable scoring system
input int    MinScore            = 80;     // Minimum score to enter trade
// Score weights
input int    ScoreWeeklyBias     = 15;     // Weekly Bias score
input int    ScoreDailyBias      = 15;     // Daily Bias score
input int    ScoreLiqSweep       = 20;     // Liquidity Sweep score
input int    ScoreMSS            = 20;     // MSS score
input int    ScoreDisplacement   = 15;     // Displacement score
input int    ScoreFVG            = 10;     // FVG score
input int    ScoreKillzone       = 10;     // Killzone score
input int    ScoreSMT            = 5;      // SMT Divergence score
input int    ScoreADR            = 5;      // ADR filter score
input int    ScorePO3            = 5;      // Power of 3 score
input int    ScorePremDisc       = 5;      // Premium/Discount score

//--- TRADE QUALITY GRADES ----------------------------------------
input group "══════════ [19] TRADE QUALITY GRADES ══════════"
input ENUM_ATLAS_GRADES_ALLOWED AllowedGrades = GRADES_A_UP; // Minimum grade allowed
input int    GradeAPlus          = 100;    // Score threshold for A+
input int    GradeA              = 80;     // Score threshold for A
input int    GradeB              = 60;     // Score threshold for B

//--- RISK MANAGEMENT ---------------------------------------------
input group "══════════ [25] RISK MANAGEMENT ══════════"
input ENUM_ATLAS_RISKMODE RiskMode = RISK_PCT; // Risk mode
input double RiskPercent         = 0.5;    // Risk % per trade
input double FixedLotSize        = 0.01;   // Fixed lot size (if RISK_LOT)
input double MaxLotCap           = 0.50;   // Hard lot size cap
input int    MaxTradesPerDay     = 10;     // Max trades per day
input int    MaxConsecLosses     = 5;      // Max consecutive losses before pause

//--- ADVANCED TRADE MANAGEMENT -----------------------------------
input group "══════════ [22] ADVANCED TRADE MANAGEMENT ══════════"
input double TP1_RR              = 1.0;    // TP1 reward:risk ratio
input double TP2_RR              = 2.0;    // TP2 reward:risk ratio
input double TP3_RR              = 3.0;    // TP3 reward:risk ratio (runner)
input double TP1_ClosePct        = 40.0;   // % of position to close at TP1
input double TP2_ClosePct        = 40.0;   // % of position to close at TP2
input bool   UseBreakeven        = true;   // Move SL to breakeven after TP1
input int    BreakevenBufferPips = 5;      // Breakeven buffer pips
input bool   UseTrailingStop     = false;  // Enable trailing stop on runner
input int    TrailStartPips      = 50;     // Trail start distance from entry
input int    TrailStepPips       = 15;     // Trail step size
input int    SLBufferPips        = 10;     // Extra pips added to SL
input int    MaxSLPips           = 80;     // Max SL size (pips)
input int    MinSLPips           = 15;     // Min SL size (pips)

//--- DAILY PROFIT LOCK -------------------------------------------
input group "══════════ [23] DAILY PROFIT LOCK ══════════"
input bool   UseProfitLock       = true;   // Enable daily profit lock
input double ProfitLock_ReduceR  = 3.0;    // Reduce risk after +XR daily profit
input double ProfitLock_StopR    = 5.0;    // Stop trading after +XR daily profit
input double ProfitLock_ReducePct= 50.0;   // Reduce risk by this %

//--- DAILY LOSS PROTECTION ----------------------------------------
input group "══════════ [24] DAILY LOSS PROTECTION ══════════"
input bool   UseLossProtect      = true;   // Enable daily loss protection
input double LossProtect_ReduceR = 2.0;    // Reduce risk after -XR daily loss
input double LossProtect_StopR   = 3.0;    // Stop trading after -XR daily loss
input double MaxWeeklyLossR      = 6.0;    // Max weekly loss in R

//--- CLOSE RULES -------------------------------------------------
input group "══════════ TRADE CLOSE RULES ══════════"
input bool   CloseOnFriday       = true;   // Close all trades Friday
input int    FridayCloseHour     = 14;     // Friday close hour (GMT)
input int    CooldownMinutes     = 15;     // Cooldown between trades (min)

//--- VISUAL SETTINGS ---------------------------------------------
input group "══════════ [26] VISUAL CHART TOOLS ══════════"
input bool   DrawPDH_PDL         = true;   // Draw PDH/PDL lines
input bool   DrawPWH_PWL         = true;   // Draw PWH/PWL lines
input bool   DrawSessionRanges   = true;   // Draw Asian/London ranges
input bool   DrawFVGZones        = true;   // Draw FVG zones on chart
input bool   DrawOBZones         = true;   // Draw OB zones on chart
input bool   DrawLiqSweeps       = true;   // Mark liquidity sweep points
input bool   DrawMSSLines        = true;   // Mark MSS levels
input bool   DrawTargets         = true;   // Show projected targets
input color  ColorPDH            = clrLime;
input color  ColorPDL            = clrTomato;
input color  ColorPWH            = clrAqua;
input color  ColorPWL            = clrOrange;
input color  ColorFVGBull        = C'0,80,0';
input color  ColorFVGBear        = C'80,0,0';
input color  ColorOBBull         = C'0,50,100';
input color  ColorOBBear         = C'80,30,0';

//--- DEBUG PANEL -------------------------------------------------
input group "══════════ [27] DEBUG PANEL ══════════"
input bool   ShowPanel           = true;   // Show debug panel
input int    PanelX              = 12;     // Panel X position
input int    PanelY              = 30;     // Panel Y position
input bool   ShowStatPanel       = true;   // Show statistics section
input bool   DebugLogs           = true;   // Print decision log every bar

//--- AGGRESSIVE MODE ---------------------------------------------
input group "══════════ [29] AGGRESSIVE MODE ══════════"
input bool   AggressiveMode      = false;  // Enable aggressive mode (high frequency)
input int    AggrMinScore        = 55;     // Min score in aggressive mode
input bool   AggrMSSOptional     = true;   // MSS not required in aggressive mode
input bool   AggrDispOptional    = false;  // Displacement not required in aggressive
input double AggrDispMinBodyPct  = 0.40;   // Aggressive displacement: min body %
input double AggrDispMinATRMulti = 0.80;   // Aggressive displacement: min ATR multiplier
input bool   AggrRequireFVG      = false;  // Require FVG entry in aggressive mode
input bool   AggrStrictPremDisc  = false;  // Require P/D zone in aggressive mode
input double AggrADRMaxPct       = 1.20;   // ADR max % in aggressive mode
input bool   AggrStrictKillzone  = false;  // Require killzone in aggressive mode
input bool   AllowContinuation   = true;   // Allow continuation trades (no sweep required when in strong trend)
input bool   ExpandKillzones     = false;  // Expand killzone windows by 2h each side
input bool   ScalperMode         = false;  // Scalper mode (very relaxed, M1/M5 structure)

//--- ML DATA COLLECTION ------------------------------------------
input group "══════════ [28] ML DATA COLLECTION ══════════"
input bool   EnableMLExport      = true;   // Enable ML data export to CSV
input bool   MLExportSignals     = true;   // Export all signals (incl. rejected)
input bool   MLExportTrades      = true;   // Export completed trade history
input int    ScalperMinScore     = 40;     // Min score in scalper mode

//===================================================================
// SECTION 3 — DATA STRUCTURES
//===================================================================

struct SBiasState
{
   ENUM_ATLAS_BIAS  weekly;
   ENUM_ATLAS_BIAS  daily;
   ENUM_ATLAS_BIAS  h4;
   ENUM_ATLAS_BIAS  h1;
   double           pwh, pwl, pwm;
   double           pdh, pdl, pdm;
   bool             weeklyPass;
   bool             dailyPass;
   string           reason;
};

struct SLiqLevel
{
   double   price;
   bool     swept;
   bool     bullishSweep;  // true = sell-side sweep (below level), false = buy-side
   bool     valid;
   string   tag;           // "PDH", "PDL", "PWH", "PWL", "EQH", "EQL", "AsianH", etc.
   datetime formed;
   datetime sweepTime;
   int      barIndex;
};

struct SMSSState
{
   bool     bullish;
   bool     bearish;
   double   level;
   datetime time;
   bool     valid;
   double   swingRef;
};

struct SDispState
{
   bool     bullish;
   bool     bearish;
   double   dispHigh;
   double   dispLow;
   double   bodyPct;
   double   atrRatio;
   datetime time;
   bool     valid;
   int      barIndex;
};

struct SFVGZone
{
   double   top;
   double   bottom;
   double   ce;           // Consequent Encroachment (midpoint)
   bool     bullish;
   bool     mitigated;
   bool     ceReached;
   bool     valid;
   datetime created;
   int      ageBars;
   string   objTop, objBot, objFill;
};

struct SPDArray
{
   ENUM_PDA_TYPE type;
   double   high;
   double   low;
   bool     bullish;
   bool     mitigated;
   bool     valid;
   datetime time;
   string   objName;
};

struct SPO3State
{
   bool     accumDone;
   bool     manipDone;
   bool     distribActive;
   bool     bullish;
   double   accumHigh, accumLow;
   double   manipLevel;
   bool     valid;
};

struct SSMTState
{
   bool     bullishDivergence;
   bool     bearishDivergence;
   bool     valid;
   double   price1, price2;
   double   correl1, correl2;
};

struct SADRState
{
   double   adrPips;
   double   todayRangePips;
   double   completionPct;
   bool     blocked;
};

struct SMarketCond
{
   ENUM_ATLAS_CONDITION condition;
   double   adxValue;
   bool     valid;
};

struct SScoreCard
{
   int   weeklyBias;
   int   dailyBias;
   int   liqSweep;
   int   mss;
   int   displacement;
   int   fvg;
   int   killzone;
   int   smt;
   int   adrScore;
   int   po3;
   int   premDisc;
   int   total;
   string failReasons[15];
   int    failCount;
};

struct SRiskState
{
   double   dailyStartBalance;
   double   weeklyStartBalance;
   double   dailyPnL;
   double   weeklyPnL;
   double   dailyR;
   double   weeklyR;
   int      dailyTrades;
   int      consecLosses;
   bool     tradingAllowed;
   bool     riskReduced;
   double   effectiveRiskPct;
   string   stopReason;
};

struct SActiveTrade
{
   ulong    ticket;
   double   entryPrice;
   double   sl;
   double   tp1, tp2, tp3;
   double   riskAmt;
   double   rValue;        // 1R distance in price
   bool     tp1Hit;
   bool     tp2Hit;
   bool     beSet;
   bool     isLong;
   string   model;
   ENUM_ATLAS_SESSION session;
   ENUM_ATLAS_GRADE   grade;
   int      score;
   datetime openTime;
   double   lot;
   // MFE/MAE (updated each tick while position is open)
   double   mfePips;
   double   maePips;
   // Signal context snapshot (for trade history CSV)
   ENUM_ATLAS_BIAS snapWeekly, snapDaily, snapH4, snapH1;
   bool  snapPDHSwept, snapPDLSwept, snapPWHSwept, snapPWLSwept;
   bool  snapAsianSwept, snapEQHSwept, snapEQLSwept;
   bool  snapMSS, snapDisp, snapFVGPresent, snapOBPresent;
   string snapADR, snapPD, snapCond;
   bool   snapNewsBlocked;
   double snapATR14, snapATR50;
   double snapSpread;
   double snapADX;
   string setupID;
};

struct STradeStats
{
   int     total;
   int     wins;
   int     losses;
   double  grossProfit;
   double  grossLoss;
   double  sumRR;
   double  maxDD;
   double  peakEquity;
   // Per session
   int     londonTotal, londonWins;
   int     nyTotal,     nyWins;
   int     asianTotal,  asianWins;
   // Per model
   int     pdlModelTotal, pdlModelWins;
   int     pdhModelTotal, pdhModelWins;
   double  pdlModelSumRR;
   double  pdhModelSumRR;
   // Avg SL tracking
   double  sumSLPips;
   int     slCount;
};

//===================================================================
// SECTION 4 — CONSTANTS & GLOBALS
//===================================================================

const string EA_NAME      = "ICT ATLAS EA V1.0";
const int    MAGIC        = 202401;
const string OBJ_PREFIX   = "ATLAS_";

// Engine state globals
SBiasState    gBias;
SLiqLevel     gLiqLevels[60];
int           gLiqCount    = 0;
bool          gSweepDone   = false;
bool          gSweepBull   = false;   // true = sell-side sweep (bullish setup)
datetime      gSweepTime   = 0;
SMSSState     gMSS;
SDispState    gDisp;
SFVGZone      gFVGs[20];
int           gFVGCount    = 0;
SPDArray      gPDAs[15];
int           gPDACount    = 0;
SPO3State     gPO3;
SSMTState     gSMT;
SADRState     gADR;
SMarketCond   gCond;
SScoreCard    gScore;
SRiskState    gRisk;
SActiveTrade  gTrade;
STradeStats   gStats;

// Dealing range for Premium/Discount
double        gDRHigh    = 0;
double        gDRLow     = 0;

// Asian/London session ranges
double        gAsianH = 0, gAsianL = 0;
double        gLondonH = 0, gLondonL = 0;
double        gNYH = 0, gNYL = 0;
bool          gAsianBuilt = false, gLondonBuilt = false, gNYBuilt = false;

// Bar tracking
datetime      gLastBarM15  = 0;
datetime      gLastBarD1   = 0;
datetime      gLastBarW1   = 0;
datetime      gLastTradeClose = 0;
int           gLastTradeDay   = -1;

// Indicator handles
int           gATR14    = INVALID_HANDLE;
int           gATR50    = INVALID_HANDLE;
int           gADX14    = INVALID_HANDLE;
double        gPartialProfit = 0;

// Panel
int           gPanelX   = 12;
int           gPanelY   = 30;
const int     PANEL_W   = 330;
const int     PANEL_LH  = 14;
color         COL_BG    = C'18,20,28';
color         COL_HDR   = C'28,32,52';
color         COL_BORDER = C'55,60,88';
color         COL_TXT   = clrSilver;
color         COL_GREEN  = C'80,210,80';
color         COL_RED    = C'240,70,70';
color         COL_GOLD   = C'220,180,60';
color         COL_BLUE   = C'80,140,240';
color         COL_PASS   = C'60,200,60';
color         COL_FAIL   = C'220,60,60';

// Final decision cache
string        gFinalDecision  = "INITIALIZING";
string        gRejectReason   = "";
bool          gSetupReady     = false;
bool          gSetupBull      = false;
ENUM_ATLAS_GRADE gCurGrade    = GRADE_NONE;

// Panel row helper state (avoids lambda)
int           gPanY  = 0;
int           gPanLH = PANEL_LH;
int           RowY(int r) { return gPanY + r * gPanLH + 2; }

// Effective symbol params (set by preset)
double        gPipFactor   = 10.0;
double        gEffMaxSL    = 50.0;
double        gEffMinSL    = 8.0;

// News times cache
datetime      gNewsTimes[8];
int           gNewsCount = 0;

bool          gPanelCollapsed = false;
bool gSecBias=true, gSecSweep=true,  gSecChain=true,    gSecFVG=false;
bool gSecFilter=true, gSecSession=false, gSecScore=true;
bool gSecDecision=true, gSecRisk=true, gSecStats=false;

// Per-day signal accounting
int           gDailyChecked  = 0;   // bars where a valid setup was found
int           gDailyRejected = 0;   // valid setups rejected (SL/lot/order fail)
int           gDailyExec     = 0;   // trades actually placed today

// Per-filter rejection counters (lifetime, resets on EA restart)
int           gRejSweep   = 0;
int           gRejMSS     = 0;
int           gRejDisp    = 0;
int           gRejFVG     = 0;
int           gRejSession = 0;
int           gRejADR     = 0;
int           gRejPD      = 0;
int           gRejSLSize  = 0;
int           gRejScore   = 0;
int           gRejOther   = 0;
string        gLastRejectReason = "";

// ML data collection
int           gMLSignalFile  = INVALID_HANDLE;
int           gMLTradeFile   = INVALID_HANDLE;
datetime      gLastSignalBar = 0;
string        gCurSetupID    = "";
int           gSetupCounter  = 0;

//===================================================================
// SECTION 5 — UTILITY FUNCTIONS
//===================================================================

double PipSize()  { return _Point * gPipFactor; }
double Pips(double p) { return p * PipSize(); }
double ToPips(double d) { return (gPipFactor > 0) ? d / PipSize() : d / _Point; }

void SetupPipFactor()
{
   if(_Digits == 5 || _Digits == 3) gPipFactor = 10.0;
   else if(_Digits == 2)            gPipFactor = 100.0;
   else                             gPipFactor = 1.0;
}

void ApplySymbolPreset()
{
   ENUM_ATLAS_SYMPRESET p = SymPreset;
   if(p == SYM_AUTO)
   {
      string s = _Symbol;
      if(StringFind(s,"XAU") >= 0 || StringFind(s,"GOLD") >= 0) p = SYM_XAUUSD;
      else if(StringFind(s,"BTC") >= 0)  p = SYM_BTCUSD;
      else if(StringFind(s,"GBP") >= 0)  p = SYM_GBPUSD;
      else if(StringFind(s,"EUR") >= 0)  p = SYM_EURUSD;
      else if(StringFind(s,"JPY") >= 0)  p = SYM_USDJPY;
   }
   switch(p)
   {
      case SYM_XAUUSD: gEffMaxSL = MathMax(120.0, (double)MaxSLPips); gEffMinSL = 8; break;
      case SYM_EURUSD: gEffMaxSL = 30; gEffMinSL = 5;  break;
      case SYM_GBPUSD: gEffMaxSL = 35; gEffMinSL = 5;  break;
      case SYM_USDJPY: gEffMaxSL = 30; gEffMinSL = 5;  break;
      case SYM_BTCUSD: gEffMaxSL = 100;gEffMinSL = 20; break;
      default:         gEffMaxSL = MaxSLPips; gEffMinSL = MinSLPips; break;
   }
}

int GetGMTOffset()
{
   if(!AutoGMTOffset)
      return BrokerGMTOffset;
   // MQL5 built-in: TimeCurrent() = broker server time, TimeGMT() = actual UTC
   // Their difference gives the true broker GMT offset.
   int offset = (int)((TimeCurrent() - TimeGMT()) / 3600);
   return offset;
}

datetime ToGMT(datetime t)
{
   return t - (datetime)(GetGMTOffset() * 3600);
}

bool IsSwingHigh(ENUM_TIMEFRAMES tf, int shift, int lookback)
{
   double h = iHigh(_Symbol, tf, shift);
   if(h <= 0) return false;
   for(int i = 1; i <= lookback; i++)
   {
      if(iHigh(_Symbol, tf, shift + i) >= h) return false;
      if(shift - i >= 0 && iHigh(_Symbol, tf, shift - i) > h) return false;
   }
   return true;
}

bool IsSwingLow(ENUM_TIMEFRAMES tf, int shift, int lookback)
{
   double l = iLow(_Symbol, tf, shift);
   if(l <= 0) return false;
   for(int i = 1; i <= lookback; i++)
   {
      if(iLow(_Symbol, tf, shift + i) <= l) return false;
      if(shift - i >= 0 && iLow(_Symbol, tf, shift - i) < l) return false;
   }
   return true;
}

double GetATR(ENUM_TIMEFRAMES tf, int period, int shift = 1)
{
   double buf[1];
   int h = iATR(_Symbol, tf, period);
   if(h == INVALID_HANDLE) return 0;
   if(CopyBuffer(h, 0, shift, 1, buf) != 1) return 0;
   IndicatorRelease(h);
   return buf[0];
}

double GetADX(int period, int shift = 1)
{
   if(gADX14 == INVALID_HANDLE) return 0;
   double buf[1];
   if(CopyBuffer(gADX14, 0, shift, 1, buf) != 1) return 0;
   return buf[0];
}

double GetATRMain(int shift = 1)
{
   if(gATR14 == INVALID_HANDLE) return 0;
   double buf[1];
   if(CopyBuffer(gATR14, 0, shift, 1, buf) != 1) return 0;
   return buf[0];
}

double GetATR50(int shift = 1)
{
   if(gATR50 == INVALID_HANDLE) return 0;
   double buf[1];
   if(CopyBuffer(gATR50, 0, shift, 1, buf) != 1) return 0;
   return buf[0];
}

double GetCurrentSpreadPips()
{
   return ToPips(SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID));
}

string DayOfWeekStr(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   switch(dt.day_of_week)
   {
      case 1: return "Monday";
      case 2: return "Tuesday";
      case 3: return "Wednesday";
      case 4: return "Thursday";
      case 5: return "Friday";
      default: return "Weekend";
   }
}

bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MAGIC)
         return true;
   }
   return false;
}

ulong GetOpenTicket()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MAGIC)
         return PositionGetInteger(POSITION_TICKET);
   }
   return 0;
}

double CalcLotSize(double slPips)
{
   if(RiskMode == RISK_LOT) return NormalizeDouble(MathMin(FixedLotSize, MaxLotCap), 2);
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt   = balance * gRisk.effectiveRiskPct / 100.0;
   double tickVal   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double slPrice   = slPips * PipSize();
   if(tickVal <= 0 || tickSize <= 0 || slPrice <= 0) return FixedLotSize;
   double lot = riskAmt / (slPrice / tickSize * tickVal);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / step) * step;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathMax(lot, minLot);
   lot = MathMin(lot, MathMin(maxLot, MaxLotCap));
   return NormalizeDouble(lot, 2);
}

string BiasStr(ENUM_ATLAS_BIAS b)
{
   switch(b)
   {
      case BIAS_BULLISH: return "BULLISH";
      case BIAS_BEARISH: return "BEARISH";
      default:           return "NEUTRAL";
   }
}

string GradeStr(ENUM_ATLAS_GRADE g)
{
   switch(g)
   {
      case GRADE_APLUS: return "A+";
      case GRADE_A:     return "A";
      case GRADE_B:     return "B";
      case GRADE_C:     return "C";
      default:          return "--";
   }
}

void AddFailReason(string reason)
{
   if(gScore.failCount < 15)
   {
      gScore.failReasons[gScore.failCount] = reason;
      gScore.failCount++;
   }
}

//===================================================================
// SECTION 6 — [01] BIAS ENGINE
//===================================================================

ENUM_ATLAS_BIAS DetectStructureBias(ENUM_TIMEFRAMES tf, int lookbackBars, int swingLookback)
{
   // Find last 4 swings to determine HH/HL vs LL/LH
   double swingH[4], swingL[4];
   int   hCount = 0, lCount = 0;

   for(int i = swingLookback; i < lookbackBars && (hCount < 4 || lCount < 4); i++)
   {
      if(hCount < 4 && IsSwingHigh(tf, i, swingLookback))
         swingH[hCount++] = iHigh(_Symbol, tf, i);
      if(lCount < 4 && IsSwingLow(tf, i, swingLookback))
         swingL[lCount++] = iLow(_Symbol, tf, i);
   }

   if(hCount < 2 || lCount < 2) return BIAS_NEUTRAL;

   bool hh = swingH[0] > swingH[1];   // recent high > previous high
   bool hl = swingL[0] > swingL[1];   // recent low  > previous low
   bool ll = swingL[0] < swingL[1];
   bool lh = swingH[0] < swingH[1];

   if(hh && hl) return BIAS_BULLISH;
   if(ll && lh) return BIAS_BEARISH;
   return BIAS_NEUTRAL;
}

void RunBiasEngine()
{
   // Previous Week High / Low / Mid
   gBias.pwh = iHigh(_Symbol, PERIOD_W1, 1);
   gBias.pwl = iLow (_Symbol, PERIOD_W1, 1);
   gBias.pwm = gBias.pwl + (gBias.pwh - gBias.pwl) * 0.5;

   // Previous Day High / Low / Mid
   gBias.pdh = iHigh(_Symbol, PERIOD_D1, 1);
   gBias.pdl = iLow (_Symbol, PERIOD_D1, 1);
   gBias.pdm = gBias.pdl + (gBias.pdh - gBias.pdl) * 0.5;

   double curClose = iClose(_Symbol, PERIOD_M15, 1);

   // Weekly bias: price vs PWM + W1 structure
   ENUM_ATLAS_BIAS wStr = DetectStructureBias(PERIOD_W1, 20, 2);
   if(curClose > gBias.pwm && wStr != BIAS_BEARISH)
      gBias.weekly = BIAS_BULLISH;
   else if(curClose < gBias.pwm && wStr != BIAS_BULLISH)
      gBias.weekly = BIAS_BEARISH;
   else
      gBias.weekly = BIAS_NEUTRAL;

   // Daily bias: price vs PDM + D1 structure
   ENUM_ATLAS_BIAS dStr = DetectStructureBias(PERIOD_D1, 30, 3);
   if(curClose > gBias.pdm && dStr != BIAS_BEARISH)
      gBias.daily = BIAS_BULLISH;
   else if(curClose < gBias.pdm && dStr != BIAS_BULLISH)
      gBias.daily = BIAS_BEARISH;
   else
      gBias.daily = BIAS_NEUTRAL;

   // H4 / H1 structural bias
   gBias.h4 = DetectStructureBias(PERIOD_H4, 40, BiasSwingLookback);
   gBias.h1 = DetectStructureBias(PERIOD_H1, 50, BiasSwingLookback);

   // Dealing range: first try swing-based (most recent H4 swing high/low pair)
   // This ensures range captures the current move, not just a fixed window.
   double drH = 0, drL = 0;
   for(int i = 1; i <= DealingRangeLookback && (drH == 0 || drL == 0); i++)
   {
      if(drH == 0 && IsSwingHigh(PERIOD_H4, i, 2))
         drH = iHigh(_Symbol, PERIOD_H4, i);
      if(drL == 0 && IsSwingLow(PERIOD_H4, i, 2))
         drL = iLow(_Symbol, PERIOD_H4, i);
   }
   // Include current (live) H4 bar in the range so price at new highs
   // doesn't permanently read as "extreme premium".
   double liveH4H = iHigh(_Symbol, PERIOD_H4, 0);
   double liveH4L = iLow (_Symbol, PERIOD_H4, 0);
   if(drH > 0 && drL > 0 && drH > drL)
   {
      gDRHigh = MathMax(drH, liveH4H);
      gDRLow  = MathMin(drL, liveH4L);
   }
   else
   {
      // Fallback: max/min over full lookback including live bar
      double fbH = liveH4H, fbL = liveH4L;
      for(int i = 1; i <= DealingRangeLookback; i++)
      {
         fbH = MathMax(fbH, iHigh(_Symbol, PERIOD_H4, i));
         fbL = MathMin(fbL, iLow (_Symbol, PERIOD_H4, i));
      }
      gDRHigh = fbH;
      gDRLow  = fbL;
   }
}

//===================================================================
// SECTION 7 — [02] LIQUIDITY ENGINE
//===================================================================

void CompactLiqLevels()
{
   // Expire swept levels older than 48h and non-structural levels older than 7 days.
   // Structural key levels (PDH/PDL/PWH/PWL) are never auto-expired here.
   datetime now = TimeCurrent();
   for(int i = 0; i < gLiqCount; i++)
   {
      if(!gLiqLevels[i].valid) continue;
      string t = gLiqLevels[i].tag;
      bool isKey = (t == "PDH" || t == "PDL" || t == "PWH" || t == "PWL");
      // Remove swept levels after 48h
      if(gLiqLevels[i].swept && (now - gLiqLevels[i].sweepTime) > 172800)
         gLiqLevels[i].valid = false;
      // Remove EQH/EQL/Asian/London levels after 7 days
      if(!isKey && !gLiqLevels[i].swept && (now - gLiqLevels[i].formed) > 604800)
         gLiqLevels[i].valid = false;
   }
   // Compact array in-place
   int newCount = 0;
   for(int i = 0; i < gLiqCount; i++)
      if(gLiqLevels[i].valid) gLiqLevels[newCount++] = gLiqLevels[i];
   gLiqCount = newCount;
}

void AddLiqLevel(double price, string tag)
{
   if(price <= 0) return;
   // Auto-clean before attempting to add if array is getting full
   if(gLiqCount >= 45) CompactLiqLevels();
   if(gLiqCount >= 60) return;

   for(int i = 0; i < gLiqCount; i++)
      if(MathAbs(gLiqLevels[i].price - price) < Pips(3) && gLiqLevels[i].tag == tag)
         return;   // already tracked

   gLiqLevels[gLiqCount].price      = price;
   gLiqLevels[gLiqCount].tag        = tag;
   gLiqLevels[gLiqCount].swept      = false;
   gLiqLevels[gLiqCount].valid      = true;
   gLiqLevels[gLiqCount].formed     = TimeCurrent();
   gLiqLevels[gLiqCount].sweepTime  = 0;
   gLiqLevels[gLiqCount].barIndex   = 0;
   gLiqCount++;
}

void RunLiquidityEngine()
{
   // Update key price levels
   AddLiqLevel(gBias.pdh, "PDH");
   AddLiqLevel(gBias.pdl, "PDL");
   AddLiqLevel(gBias.pwh, "PWH");
   AddLiqLevel(gBias.pwl, "PWL");
   AddLiqLevel(gAsianH,   "AsianH");
   AddLiqLevel(gAsianL,   "AsianL");
   if(gLondonBuilt)
   {
      AddLiqLevel(gLondonH, "LondonH");
      AddLiqLevel(gLondonL, "LondonL");
   }

   // Detect Equal Highs / Lows from M15 swings
   if(UseEQHEQL)
   {
      double swingH[10], swingL[10];
      int hc = 0, lc = 0;
      for(int i = MSSwingLookback; i < LiqLookbackBars && (hc < 10 || lc < 10); i++)
      {
         if(hc < 10 && IsSwingHigh(PERIOD_M15, i, MSSwingLookback))
            swingH[hc++] = iHigh(_Symbol, PERIOD_M15, i);
         if(lc < 10 && IsSwingLow(PERIOD_M15, i, MSSwingLookback))
            swingL[lc++] = iLow(_Symbol, PERIOD_M15, i);
      }
      // Compare pairs for equal levels
      for(int a = 0; a < hc - 1; a++)
         for(int b = a + 1; b < hc; b++)
            if(MathAbs(swingH[a] - swingH[b]) <= Pips(EQHTolerance))
               AddLiqLevel((swingH[a] + swingH[b]) * 0.5, "EQH");

      for(int a = 0; a < lc - 1; a++)
         for(int b = a + 1; b < lc; b++)
            if(MathAbs(swingL[a] - swingL[b]) <= Pips(EQHTolerance))
               AddLiqLevel((swingL[a] + swingL[b]) * 0.5, "EQL");
   }

   // Aggressive mode: also add recent M15 short-term swing H/L as internal liquidity targets
   if(AggressiveMode || ScalperMode)
   {
      int stStrength = 2;
      for(int i = stStrength + 1; i <= 30; i++)
      {
         if(IsSwingHigh(PERIOD_M15, i, stStrength))
            AddLiqLevel(iHigh(_Symbol, PERIOD_M15, i), "STH");
         if(IsSwingLow(PERIOD_M15, i, stStrength))
            AddLiqLevel(iLow(_Symbol, PERIOD_M15, i), "STL");
      }
   }

   // Check for sweeps — scan last N completed bars so late EA loads don't miss events.
   // In aggressive mode: smaller wick required, scan more bars.
   bool aggrMode = AggressiveMode || ScalperMode;
   double minWick   = aggrMode ? Pips(0.3) : Pips(SweepWickMinPips);
   int    scanBars  = aggrMode ? 5 : 2;

   // DO NOT reset gSweepDone here — sweep state must persist across bars until
   // a trade fires, a daily reset occurs, or the sweep expires (stale check below).
   for(int bar = 1; bar <= scanBars; bar++)
   {
      double barHigh  = iHigh (_Symbol, PERIOD_M15, bar);
      double barLow   = iLow  (_Symbol, PERIOD_M15, bar);
      double barClose = iClose(_Symbol, PERIOD_M15, bar);
      datetime barTime = iTime(_Symbol, PERIOD_M15, bar);

      for(int i = 0; i < gLiqCount; i++)
      {
         if(!gLiqLevels[i].valid || gLiqLevels[i].swept) continue;
         double lvl = gLiqLevels[i].price;

         // Sell-side sweep: wick below level, close back above → bullish setup
         if(barLow < lvl - minWick && barClose > lvl)
         {
            gLiqLevels[i].swept        = true;
            gLiqLevels[i].bullishSweep = true;
            gLiqLevels[i].sweepTime    = barTime;
            gSweepDone = true;
            gSweepBull = true;
            gSweepTime = barTime;
            if(DrawLiqSweeps) DrawSweepMark(lvl, barTime, true);
         }
         // Buy-side sweep: wick above level, close back below → bearish setup
         else if(barHigh > lvl + minWick && barClose < lvl)
         {
            gLiqLevels[i].swept        = true;
            gLiqLevels[i].bullishSweep = false;
            gLiqLevels[i].sweepTime    = barTime;
            gSweepDone = true;
            gSweepBull = false;
            gSweepTime = barTime;
            if(DrawLiqSweeps) DrawSweepMark(lvl, barTime, false);
         }
      }
   }
   // Reset sweep chain only when stale (no trade fired within expiry window)
   int sweepExpiryHours = aggrMode ? 8 : 4;
   if(gSweepDone && TimeCurrent() - gSweepTime > (datetime)(sweepExpiryHours * 3600))
   {
      gSweepDone  = false;
      gMSS.valid  = false;
      gDisp.valid = false;
      if(DebugLogs) Print("SWEEP EXPIRED after ",sweepExpiryHours,"h — resetting chain");
   }
}

//===================================================================
// SECTION 8 — [03] MARKET STRUCTURE ENGINE
//===================================================================

void RunMSSEngine()
{
   if(!gSweepDone) { gMSS.valid = false; return; }
   if(gMSS.valid)  return;   // persist once confirmed — wait for displacement

   // After a sweep, look for MSS on M15
   // Bullish setup: after sell-side sweep, find swing high above current price
   // MSS = close above that swing high
   ENUM_TIMEFRAMES tf = PERIOD_M15;
   double curClose = iClose(_Symbol, tf, 1);
   int    lb       = MSSLookbackBars;

   if(gSweepBull)
   {
      // Find most recent internal swing high before the sweep
      for(int i = 2; i < lb; i++)
      {
         if(IsSwingHigh(tf, i, MSSwingLookback))
         {
            double swH = iHigh(_Symbol, tf, i);
            if(curClose > swH)
            {
               gMSS.bullish  = true;
               gMSS.bearish  = false;
               gMSS.level    = swH;
               gMSS.time     = iTime(_Symbol, tf, 1);
               gMSS.swingRef = swH;
               gMSS.valid    = true;
               if(DrawMSSLines) DrawMSSLine(swH, gMSS.time, true);
               return;
            }
            break;  // only check most recent swing
         }
      }
   }
   else
   {
      // Bearish MSS: close below most recent internal swing low after buy-side sweep
      for(int i = 2; i < lb; i++)
      {
         if(IsSwingLow(tf, i, MSSwingLookback))
         {
            double swL = iLow(_Symbol, tf, i);
            if(curClose < swL)
            {
               gMSS.bearish  = true;
               gMSS.bullish  = false;
               gMSS.level    = swL;
               gMSS.time     = iTime(_Symbol, tf, 1);
               gMSS.swingRef = swL;
               gMSS.valid    = true;
               if(DrawMSSLines) DrawMSSLine(swL, gMSS.time, false);
               return;
            }
            break;
         }
      }
   }
}

//===================================================================
// SECTION 9 — [04] DISPLACEMENT ENGINE
//===================================================================

void RunDisplacementEngine()
{
   if(!gMSS.valid) { gDisp.valid = false; return; }
   if(gDisp.valid)  return;   // persist once confirmed — don't re-evaluate every bar

   double atr = GetATRMain(1);
   if(atr <= 0) return;

   ENUM_TIMEFRAMES tf = PERIOD_M15;
   int lb = DispLookbackBars;

   for(int i = 1; i <= lb; i++)
   {
      double o = iOpen (_Symbol, tf, i);
      double c = iClose(_Symbol, tf, i);
      double h = iHigh (_Symbol, tf, i);
      double l = iLow  (_Symbol, tf, i);
      double range = h - l;
      double body  = MathAbs(c - o);
      if(range <= 0) continue;

      double bodyPct  = body / range;
      double atrRatio = range / atr;

      if(bodyPct  < DispMinBodyPct)   continue;
      if(atrRatio < DispMinATRMulti)  continue;

      bool isBullDisp = (c > o) && gSweepBull;
      bool isBearDisp = (c < o) && !gSweepBull;

      if(isBullDisp || isBearDisp)
      {
         gDisp.bullish   = isBullDisp;
         gDisp.bearish   = isBearDisp;
         gDisp.dispHigh  = h;
         gDisp.dispLow   = l;
         gDisp.bodyPct   = bodyPct;
         gDisp.atrRatio  = atrRatio;
         gDisp.time      = iTime(_Symbol, tf, i);
         gDisp.barIndex  = i;
         gDisp.valid     = true;
         return;
      }
   }
}

//===================================================================
// SECTION 10 — [05] FVG ENGINE
//===================================================================

void ScanFVGs()
{
   ENUM_TIMEFRAMES tf = PERIOD_M15;
   int maxScan = MathMin(FVGMaxAgeBars, 40);

   for(int i = 1; i < maxScan; i++)
   {
      // Check if this bar's FVG is already tracked
      datetime bt = iTime(_Symbol, tf, i + 1);
      bool alreadyTracked = false;
      for(int k = 0; k < gFVGCount; k++)
         if(MathAbs(gFVGs[k].ce - (iHigh(_Symbol,tf,i+2) + iLow(_Symbol,tf,i)) * 0.5) < _Point * 2)
         { alreadyTracked = true; break; }
      if(alreadyTracked) continue;
      if(gFVGCount >= MaxFVGsTracked) break;

      double h3 = iHigh(_Symbol, tf, i + 2);
      double l3 = iLow (_Symbol, tf, i + 2);
      double l1 = iLow (_Symbol, tf, i);
      double h1 = iHigh(_Symbol, tf, i);

      // Bullish FVG — always scan; direction filter applied at entry in PriceInFVG()
      if(h3 < l1)
      {
         SFVGZone z;
         z.bottom   = h3;
         z.top      = l1;
         z.ce       = h3 + (l1 - h3) * 0.5;
         z.bullish  = true;
         z.mitigated= false;
         z.ceReached= false;
         z.valid    = true;
         z.created  = iTime(_Symbol, tf, i + 1);
         z.ageBars  = i;
         z.objTop   = ""; z.objBot = ""; z.objFill = "";
         gFVGs[gFVGCount++] = z;
         if(DrawFVGZones) DrawFVGZone(gFVGCount - 1);
         continue;
      }

      // Bearish FVG — always scan; direction filter applied at entry
      double l1b = iLow(_Symbol,  tf, i + 2);
      double h1b = iHigh(_Symbol, tf, i);
      if(l1b > h1b)
      {
         SFVGZone z;
         z.top      = l1b;
         z.bottom   = h1b;
         z.ce       = h1b + (l1b - h1b) * 0.5;
         z.bullish  = false;
         z.mitigated= false;
         z.ceReached= false;
         z.valid    = true;
         z.created  = iTime(_Symbol, tf, i + 1);
         z.ageBars  = i;
         z.objTop   = ""; z.objBot = ""; z.objFill = "";
         gFVGs[gFVGCount++] = z;
         if(DrawFVGZones) DrawFVGZone(gFVGCount - 1);
      }
   }

   // Update mitigation status
   double curH = iHigh (_Symbol, tf, 1);
   double curL = iLow  (_Symbol, tf, 1);
   double curC = iClose(_Symbol, tf, 1);

   for(int i = 0; i < gFVGCount; i++)
   {
      if(!gFVGs[i].valid || gFVGs[i].mitigated) continue;
      // Bullish FVG mitigated if price trades into bottom
      if(gFVGs[i].bullish && curL <= gFVGs[i].bottom)
         gFVGs[i].mitigated = true;
      // Bearish FVG mitigated if price trades into top
      if(!gFVGs[i].bullish && curH >= gFVGs[i].top)
         gFVGs[i].mitigated = true;
      // Track CE touch
      if(gFVGs[i].bullish && curL <= gFVGs[i].ce)
         gFVGs[i].ceReached = true;
      if(!gFVGs[i].bullish && curH >= gFVGs[i].ce)
         gFVGs[i].ceReached = true;
      // Age invalidation
      gFVGs[i].ageBars++;
      if(gFVGs[i].ageBars > FVGMaxAgeBars) gFVGs[i].valid = false;
   }
}

// Returns true if price is currently inside a valid unmitigated FVG
// aligned with the trade direction
bool PriceInFVG(bool bullish, double& fvgTop, double& fvgBot, double& fvgCE)
{
   double curC = iClose(_Symbol, PERIOD_M15, 0);
   int checked = 0;
   int wrongDir = 0, mitigated = 0, tooFar = 0;
   for(int i = 0; i < gFVGCount; i++)
   {
      SFVGZone z = gFVGs[i];
      if(!z.valid) continue;
      if(z.mitigated) { mitigated++; continue; }
      if(z.bullish != bullish) { wrongDir++; continue; }
      checked++;
      if(curC >= z.bottom && curC <= z.top)
      {
         fvgTop = z.top;
         fvgBot = z.bottom;
         fvgCE  = z.ce;
         return true;
      }
      else tooFar++;
   }
   if(DebugLogs && checked > 0)
      Print(StringFormat("FVG check: %d %s FVGs active, price=%.5f outside all zones (%d too far)",
            checked, bullish?"BULL":"BEAR", curC, tooFar));
   else if(DebugLogs && checked == 0 && gFVGCount > 0)
      Print(StringFormat("FVG check: no valid %s FVGs (%d wrong dir, %d mitigated)",
            bullish?"BULL":"BEAR", wrongDir, mitigated));
   return false;
}

//===================================================================
// SECTION 11 — [06] PD ARRAY ENGINE
//===================================================================

void ScanOrderBlocks()
{
   if(!PDA_UseOB) return;
   ENUM_TIMEFRAMES tf = PERIOD_M15;
   if(!gDisp.valid) return;

   int dispBar = gDisp.barIndex;
   bool bullish = gDisp.bullish;

   // Search for last candle of opposite color before displacement
   for(int i = dispBar + 1; i <= dispBar + OBLookbackBars; i++)
   {
      double o = iOpen (_Symbol, tf, i);
      double c = iClose(_Symbol, tf, i);
      double h = iHigh (_Symbol, tf, i);
      double l = iLow  (_Symbol, tf, i);
      bool   isBearish = (c < o);
      bool   isBullish = (c > o);

      if(bullish && isBearish)
      {
         // Bullish OB: last bearish candle before bullish displacement
         SPDArray pda;
         pda.type      = PDA_OB;
         pda.high      = h;
         pda.low       = l;
         pda.bullish   = true;
         pda.mitigated = false;
         pda.valid     = true;
         pda.time      = iTime(_Symbol, tf, i);
         pda.objName   = "";
         if(gPDACount < MaxPDAsTracked) gPDAs[gPDACount++] = pda;
         if(DrawOBZones) DrawOBZone(gPDACount - 1);
         break;
      }
      if(!bullish && isBullish)
      {
         // Bearish OB
         SPDArray pda;
         pda.type      = PDA_OB;
         pda.high      = h;
         pda.low       = l;
         pda.bullish   = false;
         pda.mitigated = false;
         pda.valid     = true;
         pda.time      = iTime(_Symbol, tf, i);
         pda.objName   = "";
         if(gPDACount < MaxPDAsTracked) gPDAs[gPDACount++] = pda;
         if(DrawOBZones) DrawOBZone(gPDACount - 1);
         break;
      }
   }
}

void ScanBreakerBlocks()
{
   if(!PDA_UseBreaker) return;
   // A Breaker = former OB that has been fully mitigated and flipped
   for(int i = 0; i < gPDACount; i++)
   {
      if(gPDAs[i].type != PDA_OB || !gPDAs[i].valid) continue;
      double curC = iClose(_Symbol, PERIOD_M15, 1);
      // Bullish OB becomes bearish breaker when price closes fully below it
      if(gPDAs[i].bullish && curC < gPDAs[i].low && !gPDAs[i].mitigated)
      {
         gPDAs[i].mitigated = true;
         if(PDA_UseBreaker && gPDACount < MaxPDAsTracked)
         {
            SPDArray brk;
            brk.type    = PDA_BREAKER;
            brk.high    = gPDAs[i].high;
            brk.low     = gPDAs[i].low;
            brk.bullish = false;  // flipped bearish
            brk.mitigated = false;
            brk.valid   = true;
            brk.time    = TimeCurrent();
            brk.objName = "";
            gPDAs[gPDACount++] = brk;
         }
      }
      if(!gPDAs[i].bullish && curC > gPDAs[i].high && !gPDAs[i].mitigated)
      {
         gPDAs[i].mitigated = true;
         if(PDA_UseBreaker && gPDACount < MaxPDAsTracked)
         {
            SPDArray brk;
            brk.type    = PDA_BREAKER;
            brk.high    = gPDAs[i].high;
            brk.low     = gPDAs[i].low;
            brk.bullish = true;   // flipped bullish
            brk.mitigated = false;
            brk.valid   = true;
            brk.time    = TimeCurrent();
            brk.objName = "";
            gPDAs[gPDACount++] = brk;
         }
      }
   }
}

void ScanNDOG_NWOG()
{
   // New Day/Week Opening Gap — gap between previous close and current open
   if(PDA_UseNDOG)
   {
      double prevClose = iClose(_Symbol, PERIOD_D1, 1);
      double todayOpen = iOpen (_Symbol, PERIOD_D1, 0);
      if(MathAbs(todayOpen - prevClose) > Pips(3) && gPDACount < MaxPDAsTracked)
      {
         SPDArray pda;
         pda.type    = PDA_NDOG;
         pda.high    = MathMax(todayOpen, prevClose);
         pda.low     = MathMin(todayOpen, prevClose);
         pda.bullish = todayOpen > prevClose;
         pda.mitigated = false;
         pda.valid   = true;
         pda.time    = iTime(_Symbol, PERIOD_D1, 0);
         pda.objName = "";
         gPDAs[gPDACount++] = pda;
      }
   }
   if(PDA_UseNWOG)
   {
      double prevWClose = iClose(_Symbol, PERIOD_W1, 1);
      double curWOpen   = iOpen (_Symbol, PERIOD_W1, 0);
      if(MathAbs(curWOpen - prevWClose) > Pips(5) && gPDACount < MaxPDAsTracked)
      {
         SPDArray pda;
         pda.type    = PDA_NWOG;
         pda.high    = MathMax(curWOpen, prevWClose);
         pda.low     = MathMin(curWOpen, prevWClose);
         pda.bullish = curWOpen > prevWClose;
         pda.mitigated = false;
         pda.valid   = true;
         pda.time    = iTime(_Symbol, PERIOD_W1, 0);
         pda.objName = "";
         gPDAs[gPDACount++] = pda;
      }
   }
}

// Check if price is in any valid PDA aligned with direction
bool PriceInPDA(bool bullish, double& pdaHigh, double& pdaLow)
{
   double curC = iClose(_Symbol, PERIOD_M15, 0);
   for(int i = 0; i < gPDACount; i++)
   {
      if(!gPDAs[i].valid || gPDAs[i].mitigated) continue;
      if(gPDAs[i].bullish != bullish)            continue;
      if(curC >= gPDAs[i].low && curC <= gPDAs[i].high)
      {
         pdaHigh = gPDAs[i].high;
         pdaLow  = gPDAs[i].low;
         return true;
      }
   }
   return false;
}

//===================================================================
// SECTION 12 — [07] PREMIUM/DISCOUNT ENGINE
//===================================================================

bool InDiscount()
{
   if(gDRHigh <= gDRLow) return false;
   double pct = (iClose(_Symbol, PERIOD_M15, 0) - gDRLow) / (gDRHigh - gDRLow);
   return pct <= DiscountZone;
}

bool InPremium()
{
   if(gDRHigh <= gDRLow) return false;
   double pct = (iClose(_Symbol, PERIOD_M15, 0) - gDRLow) / (gDRHigh - gDRLow);
   return pct >= (1.0 - PremiumZone);
}

double GetPremDiscPct()
{
   if(gDRHigh <= gDRLow) return 0.5;
   return (iClose(_Symbol, PERIOD_M15, 0) - gDRLow) / (gDRHigh - gDRLow);
}

//===================================================================
// SECTION 13 — [08] SESSION ENGINE
//===================================================================

ENUM_ATLAS_SESSION GetCurrentSession()
{
   datetime gmt = ToGMT(TimeCurrent());
   MqlDateTime dt;
   TimeToStruct(gmt, dt);
   int h = dt.hour;
   int m = dt.min;
   double hf = h + m / 60.0;
   double expand = ExpandKillzones ? 2.0 : 0.0;

   if(SessionAsian  && hf >= AsianStartHour  - expand && hf < AsianEndHour  + expand) return SES_ASIAN;
   if(SessionLondon && hf >= LondonStartHour - expand && hf < LondonEndHour + expand) return SES_LONDON;
   if(SessionNewYork && hf >= NYStartHour    - expand && hf < NYEndHour     + expand) return SES_NEWYORK;
   if(SessionNYPM   && hf >= NYPMStartHour   - expand && hf < NYPMEndHour   + expand) return SES_NEWYORK;
   return SES_NONE;
}

bool InKillzone() { return GetCurrentSession() != SES_NONE; }

void UpdateSessionRanges()
{
   datetime gmt = ToGMT(TimeCurrent());
   MqlDateTime dt;
   TimeToStruct(gmt, dt);
   int h = dt.hour;

   // Build Asian range (00-07 GMT)
   if(h >= AsianStartHour && h < AsianEndHour)
   {
      double curH = iHigh (_Symbol, PERIOD_M15, 0);
      double curL = iLow  (_Symbol, PERIOD_M15, 0);
      if(!gAsianBuilt) { gAsianH = curH; gAsianL = curL; gAsianBuilt = true; }
      else { gAsianH = MathMax(gAsianH, curH); gAsianL = MathMin(gAsianL, curL); }
   }
   // Reset Asian at start of London
   if(h == LondonStartHour && dt.min == 0) { gAsianBuilt = false; gLondonBuilt = false; }

   if(h >= LondonStartHour && h < LondonEndHour)
   {
      double curH = iHigh (_Symbol, PERIOD_M15, 0);
      double curL = iLow  (_Symbol, PERIOD_M15, 0);
      if(!gLondonBuilt) { gLondonH = curH; gLondonL = curL; gLondonBuilt = true; }
      else { gLondonH = MathMax(gLondonH, curH); gLondonL = MathMin(gLondonL, curL); }
   }
}

//===================================================================
// SECTION 14 — [09] POWER OF 3 ENGINE
//===================================================================

void RunPO3Engine()
{
   // AMD: Accumulation (Asian range), Manipulation (London sweep), Distribution (NY)
   if(!gAsianBuilt) { gPO3.valid = false; return; }

   ENUM_ATLAS_SESSION ses = GetCurrentSession();
   double curC = iClose(_Symbol, PERIOD_M15, 1);

   gPO3.accumDone  = gAsianBuilt;
   gPO3.accumHigh  = gAsianH;
   gPO3.accumLow   = gAsianL;

   // Manipulation: London sweeps Asian range
   if(ses == SES_LONDON || ses == SES_NEWYORK)
   {
      bool sweepAbove = iHigh(_Symbol, PERIOD_M15, 1) > gAsianH + Pips(PO3ManipMinPips);
      bool sweepBelow = iLow (_Symbol, PERIOD_M15, 1) < gAsianL - Pips(PO3ManipMinPips);

      if(sweepAbove && !gPO3.manipDone)
      {
         gPO3.manipDone    = true;
         gPO3.bullish      = false;  // faked above → bearish distribution expected
         gPO3.manipLevel   = gAsianH;
      }
      else if(sweepBelow && !gPO3.manipDone)
      {
         gPO3.manipDone    = true;
         gPO3.bullish      = true;   // faked below → bullish distribution expected
         gPO3.manipLevel   = gAsianL;
      }
   }

   // Distribution: NY session moves in expected direction
   if(gPO3.manipDone && ses == SES_NEWYORK)
   {
      gPO3.distribActive = true;
      gPO3.valid         = true;
   }
}

//===================================================================
// SECTION 15 — [10] SMT DIVERGENCE ENGINE
//===================================================================

void RunSMTEngine()
{
   gSMT.valid = false;
   if(!UseSMTFilter) return;
   if(SMTSymbol == "" || SMTSymbol == _Symbol) return;

   // Get most recent swing on both symbols
   double swL1  = iLow(_Symbol, PERIOD_M15, 1);
   double swL2  = iLow(SMTSymbol, PERIOD_M15, 1);
   double swH1  = iHigh(_Symbol, PERIOD_M15, 1);
   double swH2  = iHigh(SMTSymbol, PERIOD_M15, 1);

   double prevL1 = 0, prevL2 = 0, prevH1 = 0, prevH2 = 0;
   for(int i = 2; i <= SMTLookbackBars + 2; i++)
   {
      if(prevL1 == 0 && IsSwingLow(PERIOD_M15, i, 2))
         prevL1 = iLow(_Symbol, PERIOD_M15, i);
      if(prevL2 == 0 && IsSwingLow(PERIOD_M15, i, 2))
         prevL2 = iLow(SMTSymbol, PERIOD_M15, i);
      if(prevH1 == 0 && IsSwingHigh(PERIOD_M15, i, 2))
         prevH1 = iHigh(_Symbol, PERIOD_M15, i);
      if(prevH2 == 0 && IsSwingHigh(PERIOD_M15, i, 2))
         prevH2 = iHigh(SMTSymbol, PERIOD_M15, i);
      if(prevL1 > 0 && prevL2 > 0 && prevH1 > 0 && prevH2 > 0) break;
   }

   if(prevL1 <= 0 || prevL2 <= 0) return;

   // Bullish SMT: symbol makes lower low, correlated does not (divergence)
   bool bullSMT = (swL1 < prevL1) && (swL2 > prevL2);
   // Bearish SMT: symbol makes higher high, correlated does not
   bool bearSMT = (swH1 > prevH1) && (swH2 < prevH2);

   if(bullSMT || bearSMT)
   {
      gSMT.bullishDivergence = bullSMT;
      gSMT.bearishDivergence = bearSMT;
      gSMT.valid = true;
   }
}

//===================================================================
// SECTION 16 — [11] ADR ENGINE
//===================================================================

void RunADREngine()
{
   gADR.blocked = false;
   if(!UseADRFilter) return;

   int period = ADRPeriod;
   double sumRange = 0;
   for(int i = 1; i <= period; i++)
   {
      double h = iHigh(_Symbol, PERIOD_D1, i);
      double l = iLow (_Symbol, PERIOD_D1, i);
      sumRange += ToPips(h - l);
   }
   gADR.adrPips = (period > 0) ? sumRange / period : 0;

   double todH = iHigh(_Symbol, PERIOD_D1, 0);
   double todL = iLow (_Symbol, PERIOD_D1, 0);
   gADR.todayRangePips   = ToPips(todH - todL);
   gADR.completionPct    = (gADR.adrPips > 0) ? gADR.todayRangePips / gADR.adrPips : 0;
   gADR.blocked          = gADR.completionPct >= ADRMaxPct;
}

//===================================================================
// SECTION 17 — [12] NEWS ENGINE
//===================================================================

void ParseNewsTimes()
{
   gNewsCount = 0;
   string times[8];
   times[0] = NewsTime1; times[1] = NewsTime2; times[2] = NewsTime3;
   times[3] = NewsTime4; times[4] = NewsTime5; times[5] = NewsTime6;
   times[6] = NewsTime7; times[7] = NewsTime8;

   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   MqlDateTime dt;
   TimeToStruct(today, dt);

   for(int i = 0; i < 8; i++)
   {
      if(times[i] == "") continue;
      int h = 0, m = 0;
      if(StringFind(times[i], ":") >= 0)
      {
         string parts[];
         StringSplit(times[i], ':', parts);
         if(ArraySize(parts) == 2)
         {
            h = (int)StringToInteger(parts[0]);
            m = (int)StringToInteger(parts[1]);
         }
      }
      dt.hour = h; dt.min = m; dt.sec = 0;
      gNewsTimes[gNewsCount++] = StructToTime(dt);
   }
}

bool IsNewsBlocked()
{
   if(!UseNewsFilter || gNewsCount == 0) return false;
   datetime gmt = ToGMT(TimeCurrent());
   int blockBefore = NewsBlockBefore * 60;
   int blockAfter  = NewsBlockAfter  * 60;
   for(int i = 0; i < gNewsCount; i++)
   {
      datetime diff = gmt - gNewsTimes[i];
      if(diff >= -blockBefore && diff <= blockAfter) return true;
   }
   return false;
}

int NewsMinutesToEvent()
{
   if(gNewsCount == 0) return 9999;
   datetime gmt = ToGMT(TimeCurrent());
   int minDiff = 9999;
   for(int i = 0; i < gNewsCount; i++)
   {
      int diff = (int)(gNewsTimes[i] - gmt);
      if(diff > 0 && diff < minDiff) minDiff = diff;
   }
   return minDiff / 60;
}

//===================================================================
// SECTION 18 — [13] MARKET CONDITION ENGINE
//===================================================================

void RunConditionEngine()
{
   double adx = GetADX(CondADXPeriod, 1);
   gCond.adxValue = adx;
   if(adx >= CondADXTrend)      gCond.condition = COND_TRENDING;
   else if(adx >= CondADXChoppy) gCond.condition = COND_RANGING;
   else                          gCond.condition = COND_CHOPPY;
   gCond.valid = true;
}

bool ConditionAllowsTrade()
{
   if(!UseConditionFilter) return true;
   switch(gCond.condition)
   {
      case COND_TRENDING: return TradeInTrend;
      case COND_RANGING:  return TradeInRanging;
      case COND_CHOPPY:   return TradeInChoppy;
   }
   return true;
}

//===================================================================
// SECTION 19 — [14] CONFLUENCE SCORING + [15] GRADE ENGINE
//===================================================================

// Helper: check displacement with custom thresholds (for aggressive mode)
bool CheckDispWithThresholds(bool bullish, double minBody, double minATR)
{
   if(!gSweepDone || gSweepBull != bullish) return false;
   double atr = GetATRMain(1);
   if(atr <= 0) return false;
   for(int i = 1; i <= DispLookbackBars; i++)
   {
      double range = iHigh(_Symbol,PERIOD_M15,i) - iLow(_Symbol,PERIOD_M15,i);
      double body  = MathAbs(iClose(_Symbol,PERIOD_M15,i) - iOpen(_Symbol,PERIOD_M15,i));
      if(range <= 0) continue;
      if(body/range < minBody) continue;
      if(range/atr  < minATR)  continue;
      bool isBullDisp = (iClose(_Symbol,PERIOD_M15,i) > iOpen(_Symbol,PERIOD_M15,i)) && bullish;
      bool isBearDisp = (iClose(_Symbol,PERIOD_M15,i) < iOpen(_Symbol,PERIOD_M15,i)) && !bullish;
      if(isBullDisp || isBearDisp) return true;
   }
   return false;
}

void CalcConfluenceScore(bool bullish)
{
   gScore.weeklyBias    = 0;
   gScore.dailyBias     = 0;
   gScore.liqSweep      = 0;
   gScore.mss           = 0;
   gScore.displacement  = 0;
   gScore.fvg           = 0;
   gScore.killzone      = 0;
   gScore.smt           = 0;
   gScore.adrScore      = 0;
   gScore.po3           = 0;
   gScore.premDisc      = 0;
   gScore.total         = 0;
   gScore.failCount     = 0;

   bool aggrMode     = AggressiveMode || ScalperMode;
   bool sweepPresent = gSweepDone && gSweepBull == bullish;

   // Weekly bias
   if(!RequireWeeklyBias || (bullish ? gBias.weekly == BIAS_BULLISH : gBias.weekly == BIAS_BEARISH))
      gScore.weeklyBias = ScoreWeeklyBias;
   else AddFailReason("Weekly Bias: " + BiasStr(gBias.weekly) +
                      (bullish ? " (need BULLISH)" : " (need BEARISH)"));

   // Daily bias — with H4+H1 override for NEUTRAL days:
   //   Full score  : Daily direction matches
   //   Half score  : Daily is NEUTRAL but H4 + H1 both confirm direction
   //   Zero + fail : Daily actively opposes direction
   bool dailyMatch    = bullish ? gBias.daily == BIAS_BULLISH : gBias.daily == BIAS_BEARISH;
   bool dailyNeutral  = (gBias.daily == BIAS_NEUTRAL);
   bool h4Confirm     = bullish ? gBias.h4 == BIAS_BULLISH : gBias.h4 == BIAS_BEARISH;
   bool h1Confirm     = bullish ? gBias.h1 == BIAS_BULLISH : gBias.h1 == BIAS_BEARISH;
   bool dailyOpposed  = !dailyMatch && !dailyNeutral;
   if(!RequireDailyBias || dailyMatch)
      gScore.dailyBias = ScoreDailyBias;
   else if(dailyNeutral && h4Confirm && h1Confirm)
      gScore.dailyBias = ScoreDailyBias / 2;   // half credit: NEUTRAL + H4+H1 aligned
   else if(aggrMode && dailyNeutral)
      gScore.dailyBias = ScoreDailyBias / 2;   // aggressive: neutral day gets half credit
   else AddFailReason("Daily Bias: " + BiasStr(gBias.daily) +
                      (dailyOpposed ? (bullish?" (OPPOSED-BEARISH)":" (OPPOSED-BULLISH)")
                                    : (bullish?" (need BULLISH)":" (need BEARISH)")));

   // Liquidity sweep — always required (core ICT event), but continuation trades bypass
   if(!UseLiquidityEngine || sweepPresent)
      gScore.liqSweep = ScoreLiqSweep;
   else if(aggrMode && AllowContinuation && (gBias.weekly == (bullish?BIAS_BULLISH:BIAS_BEARISH)))
      gScore.liqSweep = ScoreLiqSweep / 2;   // continuation trade: half credit, no sweep
   else AddFailReason("Liq Sweep: Missing");

   // MSS — optional in aggressive mode (gives partial score)
   bool mssMatch = gMSS.valid && gMSS.bullish == bullish;
   if(!UseMSSFilter || mssMatch)
      gScore.mss = ScoreMSS;
   else if(aggrMode && AggrMSSOptional && sweepPresent)
      gScore.mss = ScoreMSS / 2;   // aggressive: sweep confirmed, MSS pending = half credit
   else AddFailReason("MSS: Not confirmed");

   // Displacement — relaxed thresholds in aggressive mode
   bool dispMatch = gDisp.valid && gDisp.bullish == bullish;
   if(!UseDispFilter || dispMatch)
      gScore.displacement = ScoreDisplacement;
   else if(aggrMode && CheckDispWithThresholds(bullish, AggrDispMinBodyPct, AggrDispMinATRMulti))
      gScore.displacement = ScoreDisplacement;   // aggressive displacement passed
   else if(aggrMode && AggrDispOptional)
      gScore.displacement = 0;   // no fail reason — just 0 pts
   else AddFailReason("Displacement: Not confirmed");

   // FVG — not required in aggressive mode
   double fTop, fBot, fCE;
   bool inFVG = PriceInFVG(bullish, fTop, fBot, fCE);
   bool fvgRequired = UseFVGFilter && !(aggrMode && !AggrRequireFVG);
   if(!fvgRequired || inFVG)
      gScore.fvg = ScoreFVG;
   else AddFailReason("FVG: Price not in FVG");

   // Killzone — in aggressive mode: outside session gives 0 pts (not a fail)
   bool inKZ = InKillzone();
   if(!UseSessionFilter || inKZ)
      gScore.killzone = ScoreKillzone;
   else if(aggrMode && !AggrStrictKillzone)
      gScore.killzone = 0;   // not in KZ but aggressive: just skip the points
   else AddFailReason("Killzone: Outside session");

   // SMT
   if(!UseSMTFilter || (gSMT.valid && (bullish ? gSMT.bullishDivergence : gSMT.bearishDivergence)))
      gScore.smt = ScoreSMT;

   // ADR — aggressive mode uses wider limit
   double adrLimit = aggrMode ? AggrADRMaxPct : ADRMaxPct;
   bool adrBlocked = UseADRFilter && (gADR.completionPct > adrLimit);
   if(!adrBlocked)
      gScore.adrScore = ScoreADR;
   else AddFailReason("ADR: " + DoubleToString(gADR.completionPct * 100, 0) + "% complete");

   // Power of 3
   if(!UsePO3Filter || (gPO3.valid && gPO3.bullish == bullish))
      gScore.po3 = ScorePO3;

   // Premium/Discount — relaxed in aggressive mode
   bool pdPass = bullish ? InDiscount() : InPremium();
   bool pdRequired = UsePremDiscFilter && !(aggrMode && !AggrStrictPremDisc);
   if(!pdRequired || pdPass)
      gScore.premDisc = ScorePremDisc;
   else AddFailReason("P/D: Not in " + (bullish ? "Discount" : "Premium"));

   gScore.total = gScore.weeklyBias + gScore.dailyBias + gScore.liqSweep +
                  gScore.mss + gScore.displacement + gScore.fvg +
                  gScore.killzone + gScore.smt + gScore.adrScore +
                  gScore.po3 + gScore.premDisc;
}

ENUM_ATLAS_GRADE CalcGrade(int score)
{
   if(score >= GradeAPlus) return GRADE_APLUS;
   if(score >= GradeA)     return GRADE_A;
   if(score >= GradeB)     return GRADE_B;
   return GRADE_C;
}

bool GradeAllowed(ENUM_ATLAS_GRADE g)
{
   switch(AllowedGrades)
   {
      case GRADES_APLUS: return g == GRADE_APLUS;
      case GRADES_A_UP:  return g <= GRADE_A;
      case GRADES_B_UP:  return g <= GRADE_B;
      case GRADES_ALL:   return true;
   }
   return false;
}

//===================================================================
// SECTION 20 — [16] RISK ENGINE
//===================================================================

void InitRiskState()
{
   gRisk.dailyStartBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
   gRisk.weeklyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   gRisk.dailyPnL           = 0;
   gRisk.weeklyPnL          = 0;
   gRisk.dailyR             = 0;
   gRisk.weeklyR            = 0;
   gRisk.dailyTrades        = 0;
   gRisk.consecLosses       = 0;
   gRisk.tradingAllowed     = true;
   gRisk.riskReduced        = false;
   gRisk.effectiveRiskPct   = RiskPercent;
   gRisk.stopReason         = "";
}

void UpdateRiskState()
{
   // Check daily reset
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   if(now.day_of_year != gLastTradeDay)
   {
      gLastTradeDay            = now.day_of_year;
      gRisk.dailyStartBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
      gRisk.dailyPnL           = 0;
      gRisk.dailyR             = 0;
      gRisk.dailyTrades        = 0;
      gRisk.tradingAllowed     = true;
      gRisk.riskReduced        = false;
      gRisk.effectiveRiskPct   = RiskPercent;
      gRisk.stopReason         = "";
      gDailyChecked  = 0;
      gDailyRejected = 0;
      gDailyExec     = 0;
   }

   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   gRisk.dailyPnL  = balance - gRisk.dailyStartBalance;
   gRisk.weeklyPnL = balance - gRisk.weeklyStartBalance;

   // Estimate 1R = RiskPercent% of start balance
   double oneR = gRisk.dailyStartBalance * RiskPercent / 100.0;
   if(oneR > 0)
   {
      gRisk.dailyR  = gRisk.dailyPnL  / oneR;
      gRisk.weeklyR = gRisk.weeklyPnL / oneR;
   }

   // Daily profit lock
   if(UseProfitLock)
   {
      if(gRisk.dailyR >= ProfitLock_StopR)
      { gRisk.tradingAllowed = false; gRisk.stopReason = "Daily Profit Target Reached"; return; }
      if(gRisk.dailyR >= ProfitLock_ReduceR && !gRisk.riskReduced)
      {
         gRisk.riskReduced      = true;
         gRisk.effectiveRiskPct = RiskPercent * (1.0 - ProfitLock_ReducePct / 100.0);
      }
   }

   // Daily loss protection
   if(UseLossProtect)
   {
      if(gRisk.dailyR <= -LossProtect_StopR)
      { gRisk.tradingAllowed = false; gRisk.stopReason = "Daily Loss Limit Reached"; return; }
      if(gRisk.dailyR <= -LossProtect_ReduceR && !gRisk.riskReduced)
      {
         gRisk.riskReduced      = true;
         gRisk.effectiveRiskPct = RiskPercent * 0.5;
      }
   }

   // Weekly loss
   if(gRisk.weeklyR <= -MaxWeeklyLossR)
   { gRisk.tradingAllowed = false; gRisk.stopReason = "Weekly Loss Limit Reached"; return; }

   // Max trades per day
   if(gRisk.dailyTrades >= MaxTradesPerDay)
   { gRisk.tradingAllowed = false; gRisk.stopReason = "Max Daily Trades"; return; }

   // Consecutive losses
   if(gRisk.consecLosses >= MaxConsecLosses)
   { gRisk.tradingAllowed = false; gRisk.stopReason = "Max Consecutive Losses"; return; }
}

bool CanTrade()
{
   if(!gRisk.tradingAllowed) return false;
   if(HasOpenPosition())     return false;
   if(MaxSpreadPips > 0)
   {
      double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID));
      if(ToPips(spread) > MaxSpreadPips) return false;
   }
   if(CooldownMinutes > 0 && gLastTradeClose > 0 &&
      (TimeCurrent() - gLastTradeClose) < (datetime)(CooldownMinutes * 60)) return false;
   // Friday close-out window
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(CloseOnFriday && dt.day_of_week == 5)
   {
      datetime gmt = ToGMT(TimeCurrent());
      TimeToStruct(gmt, dt);
      if(dt.hour >= FridayCloseHour) return false;
   }
   return true;
}

//===================================================================
// SECTION 21 — FULL SETUP VALIDATION
//===================================================================

bool ValidateSetup(bool bullish)
{
   bool aggrMode = AggressiveMode || ScalperMode;

   // Hard block: killzone in strict mode only (aggressive bypasses this)
   if(UseSessionFilter && !aggrMode && !InKillzone())
   {
      AddFailReason("Killzone: Outside session");
      return false;
   }

   // Hard block: liquidity sweep always required (core ICT requirement)
   // Exception: AllowContinuation with weekly bias aligned — sweep not mandatory
   bool sweepOK = (gSweepDone && gSweepBull == bullish);
   bool contOK  = aggrMode && AllowContinuation &&
                  (gBias.weekly == (bullish ? BIAS_BULLISH : BIAS_BEARISH));
   if(UseLiquidityEngine && !sweepOK && !contOK)
   {
      AddFailReason("Liq Sweep: Missing");
      if(DebugLogs) Print("SETUP BLOCKED: No liquidity sweep for ",bullish?"BULL":"BEAR");
      return false;
   }

   CalcConfluenceScore(bullish);
   gCurGrade = CalcGrade(gScore.total);

   // Score threshold — mode-dependent
   int minScoreNow = MinScore;
   if(ScalperMode)      minScoreNow = ScalperMinScore;
   else if(AggressiveMode) minScoreNow = AggrMinScore;

   if(UseScoringSystem && gScore.total < minScoreNow)
   {
      AddFailReason("Score: " + IntegerToString(gScore.total) + " < " + IntegerToString(minScoreNow));
      return false;
   }

   if(!aggrMode && !GradeAllowed(gCurGrade))
   {
      AddFailReason("Grade: " + GradeStr(gCurGrade) + " below minimum");
      return false;
   }

   if(UseConditionFilter && !ConditionAllowsTrade())
   {
      AddFailReason("Market Condition: " + EnumToString(gCond.condition));
      return false;
   }

   if(UseNewsFilter && IsNewsBlocked())
   {
      AddFailReason("News: Blocked");
      return false;
   }

   // Score threshold is the gate — fail reasons are for panel display only
   return true;
}

//===================================================================
// SECTION 22 — [17] TRADE ENTRY ENGINE
//===================================================================

bool PlaceTrade(bool bullish)
{
   bool aggrMode = AggressiveMode || ScalperMode;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = bullish ? ask : bid;

   // SL calculation: aggressive = tight local 5-bar swing; conservative = PDH/PDL structural
   double slPrice = 0;
   if(aggrMode)
   {
      // Tight SL: local swing extreme within last 5 bars
      if(bullish)
      {
         double lo = iLow(_Symbol, PERIOD_M15, 1);
         for(int i = 2; i <= 5; i++) lo = MathMin(lo, iLow(_Symbol, PERIOD_M15, i));
         slPrice = lo - Pips(SLBufferPips);
      }
      else
      {
         double hi = iHigh(_Symbol, PERIOD_M15, 1);
         for(int i = 2; i <= 5; i++) hi = MathMax(hi, iHigh(_Symbol, PERIOD_M15, i));
         slPrice = hi + Pips(SLBufferPips);
      }
   }
   else
   {
      // Structural SL: PDH/PDL with recent wick extension
      if(bullish)
      {
         double sweepLow = gBias.pdl;
         for(int i = 1; i <= 10; i++) sweepLow = MathMin(sweepLow, iLow(_Symbol, PERIOD_M15, i));
         slPrice = sweepLow - Pips(SLBufferPips);
      }
      else
      {
         double sweepHigh = gBias.pdh;
         for(int i = 1; i <= 10; i++) sweepHigh = MathMax(sweepHigh, iHigh(_Symbol, PERIOD_M15, i));
         slPrice = sweepHigh + Pips(SLBufferPips);
      }
   }

   double slPips = ToPips(MathAbs(entry - slPrice));

   if(slPips < gEffMinSL)
   {
      Print("TRADE BLOCKED: SL too small = ", DoubleToString(slPips,1), " pips (min=", DoubleToString(gEffMinSL,1), ")");
      AddFailReason("SL too small: " + DoubleToString(slPips,1) + "p");
      gRejSLSize++;
      gLastRejectReason = "SL too small: " + DoubleToString(slPips,1) + "p";
      return false;
   }
   if(slPips > gEffMaxSL)
   {
      Print("TRADE BLOCKED: SL too large = ", DoubleToString(slPips,1), " pips (max=", DoubleToString(gEffMaxSL,1), ")");
      AddFailReason("SL too large: " + DoubleToString(slPips,1) + "p");
      gRejSLSize++;
      gLastRejectReason = "SL too large: " + DoubleToString(slPips,1) + "p";
      return false;
   }

   double rValue = MathAbs(entry - slPrice);
   double tp1    = bullish ? entry + rValue * TP1_RR : entry - rValue * TP1_RR;
   double tp2    = bullish ? entry + rValue * TP2_RR : entry - rValue * TP2_RR;
   double tp3    = bullish ? entry + rValue * TP3_RR : entry - rValue * TP3_RR;

   double lot    = CalcLotSize(slPips);
   if(lot <= 0)
   {
      Print("TRADE BLOCKED: Lot size = 0 (SL=", DoubleToString(slPips,1), "p)");
      return false;
   }

   Trade.SetDeviationInPoints((ulong)(MaxSlippagePips * (int)gPipFactor));

   bool ok = bullish
      ? Trade.Buy (lot, _Symbol, 0, slPrice, tp3, EA_NAME)
      : Trade.Sell(lot, _Symbol, 0, slPrice, tp3, EA_NAME);

   if(!ok)
   {
      Print("TRADE BLOCKED: Order rejected — ", Trade.ResultRetcodeDescription());
      return false;
   }

   ulong ticket = Trade.ResultOrder();
   gRisk.dailyTrades++;
   gDailyExec++;
   gLastTradeClose = 0;
   gStats.sumSLPips += slPips;
   gStats.slCount++;

   gTrade.ticket    = ticket;
   gTrade.entryPrice= entry;
   gTrade.sl        = slPrice;
   gTrade.tp1       = tp1;
   gTrade.tp2       = tp2;
   gTrade.tp3       = tp3;
   gTrade.riskAmt   = lot * slPips * PipSize() *
                      SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) /
                      SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   gTrade.rValue    = rValue;
   gTrade.tp1Hit    = false;
   gTrade.tp2Hit    = false;
   gTrade.beSet     = false;
   gTrade.isLong    = bullish;
   gTrade.session   = GetCurrentSession();
   gTrade.grade     = gCurGrade;
   gTrade.score     = gScore.total;
   gTrade.openTime  = TimeCurrent();
   gTrade.model     = gSweepBull ? "PDL+MSS+FVG" : "PDH+MSS+FVG";
   gTrade.lot       = lot;
   // MFE/MAE reset
   gTrade.mfePips   = 0;
   gTrade.maePips   = 0;
   // Signal snapshot for trade history CSV
   gTrade.snapWeekly     = gBias.weekly;
   gTrade.snapDaily      = gBias.daily;
   gTrade.snapH4         = gBias.h4;
   gTrade.snapH1         = gBias.h1;
   gTrade.snapPDHSwept   = WasTagSwept("PDH");
   gTrade.snapPDLSwept   = WasTagSwept("PDL");
   gTrade.snapPWHSwept   = WasTagSwept("PWH");
   gTrade.snapPWLSwept   = WasTagSwept("PWL");
   gTrade.snapAsianSwept = WasTagSwept("AsianH") || WasTagSwept("AsianL");
   gTrade.snapEQHSwept   = WasTagSwept("EQH");
   gTrade.snapEQLSwept   = WasTagSwept("EQL");
   gTrade.snapMSS        = gMSS.valid;
   gTrade.snapDisp       = gDisp.valid;
   bool _fvg=false; for(int _i=0;_i<gFVGCount;_i++) if(gFVGs[_i].valid&&!gFVGs[_i].mitigated&&gFVGs[_i].bullish==bullish){_fvg=true;break;}
   bool _ob=false;  for(int _i=0;_i<gPDACount;_i++) if(gPDAs[_i].valid&&!gPDAs[_i].mitigated&&gPDAs[_i].bullish==bullish){_ob=true;break;}
   gTrade.snapFVGPresent = _fvg;
   gTrade.snapOBPresent  = _ob;
   gTrade.snapADR        = GetADRLabel();
   gTrade.snapPD         = GetPDLabel();
   gTrade.snapCond       = GetCondLabel();
   gTrade.snapNewsBlocked= IsNewsBlocked();
   gTrade.snapATR14      = ToPips(GetATRMain(1));
   gTrade.snapATR50      = ToPips(GetATR50(1));
   gTrade.snapSpread     = GetCurrentSpreadPips();
   gTrade.snapADX        = GetADX(CondADXPeriod, 1);
   gTrade.setupID        = gCurSetupID;

   string key = "ATLAS_" + IntegerToString(ticket);
   GlobalVariableSet(key + "_tp1",  tp1);
   GlobalVariableSet(key + "_tp2",  tp2);
   GlobalVariableSet(key + "_tp3",  tp3);
   GlobalVariableSet(key + "_rv",   rValue);
   GlobalVariableSet(key + "_long", bullish ? 1 : 0);

   // Reset engines for next trade
   gSweepDone = false;
   gMSS.valid = false;
   gDisp.valid = false;
   gSetupReady = false;

   string modeTag = ScalperMode ? "[SCALPER] " : (AggressiveMode ? "[AGGR] " : "");
   Print(StringFormat("TRADE EXECUTED: %s%s %s | Lot=%.2f | Entry=%.5f | SL=%.5f (%.1fp) | Score=%d | Grade=%s",
         modeTag, bullish?"BUY":"SELL", _Symbol, lot, entry, slPrice, slPips, gScore.total, GradeStr(gCurGrade)));
   return true;
}

//===================================================================
// SECTION 23 — [17] TRADE MANAGEMENT ENGINE
//===================================================================

void ManageTrades()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;

      ulong  ticket = PositionGetInteger(POSITION_TICKET);
      bool   isLong = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double curP   = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                             : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // MFE / MAE tracking
      if(gTrade.ticket == ticket)
      {
         double favor = ToPips(isLong ? curP - entry : entry - curP);
         double adver = ToPips(isLong ? entry - curP : curP - entry);
         if(favor > gTrade.mfePips) gTrade.mfePips = favor;
         if(adver > gTrade.maePips) gTrade.maePips = adver;
      }

      string key   = "ATLAS_" + IntegerToString(ticket);
      bool   haveGV= GlobalVariableCheck(key + "_tp1");

      double tp1 = haveGV ? GlobalVariableGet(key + "_tp1") : 0;
      double tp2 = haveGV ? GlobalVariableGet(key + "_tp2") : 0;
      double rv  = haveGV ? GlobalVariableGet(key + "_rv")  : 0;

      if(rv <= 0 || tp1 <= 0) continue;

      double vol   = PositionGetDouble(POSITION_VOLUME);
      bool tp1Hit  = haveGV ? (bool)GlobalVariableGet(key + "_t1h") : false;
      bool tp2Hit  = haveGV ? (bool)GlobalVariableGet(key + "_t2h") : false;
      bool beSet   = haveGV ? (bool)GlobalVariableGet(key + "_be")  : false;

      // TP1 partial close
      if(!tp1Hit && ((isLong && curP >= tp1) || (!isLong && curP <= tp1)))
      {
         double closeLot = NormalizeDouble(vol * TP1_ClosePct / 100.0,
                              (int)MathRound(-MathLog10(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP))));
         closeLot = MathMax(closeLot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
         if(closeLot > 0 && closeLot < vol)
         {
            if(isLong) Trade.Sell(closeLot, _Symbol, 0, 0, 0, "TP1-Partial");
            else       Trade.Buy (closeLot, _Symbol, 0, 0, 0, "TP1-Partial");
            GlobalVariableSet(key + "_t1h", 1);
            Print("ATLAS TP1 partial close: ", closeLot, " lots");
         }
      }

      // TP2 partial close
      if(tp1Hit && !tp2Hit && tp2 > 0 &&
         ((isLong && curP >= tp2) || (!isLong && curP <= tp2)))
      {
         double closeLot = NormalizeDouble(vol * TP2_ClosePct / 100.0,
                              (int)MathRound(-MathLog10(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP))));
         closeLot = MathMax(closeLot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
         if(closeLot > 0 && closeLot < vol)
         {
            if(isLong) Trade.Sell(closeLot, _Symbol, 0, 0, 0, "TP2-Partial");
            else       Trade.Buy (closeLot, _Symbol, 0, 0, 0, "TP2-Partial");
            GlobalVariableSet(key + "_t2h", 1);
            Print("ATLAS TP2 partial close: ", closeLot, " lots");
         }
      }

      // Breakeven
      if(UseBreakeven && tp1Hit && !beSet)
      {
         double bePriceLong  = entry + Pips(BreakevenBufferPips);
         double bePriceShort = entry - Pips(BreakevenBufferPips);
         double newSL = isLong ? bePriceLong : bePriceShort;

         bool beValid = isLong  ? (newSL > sl + _Point)
                                : (newSL < sl - _Point);
         if(beValid)
         {
            if(Trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
            {
               GlobalVariableSet(key + "_be", 1);
               Print("ATLAS Breakeven set: ", newSL);
            }
         }
      }

      // Trailing stop on runner (after TP2)
      if(UseTrailingStop && tp2Hit)
      {
         double startDist = Pips(TrailStartPips);
         double stepDist  = Pips(TrailStepPips);

         if(isLong && curP - entry >= startDist)
         {
            double trailSL = curP - stepDist;
            if(trailSL > sl + _Point)
               Trade.PositionModify(ticket, trailSL, PositionGetDouble(POSITION_TP));
         }
         else if(!isLong && entry - curP >= startDist)
         {
            double trailSL = curP + stepDist;
            if(trailSL < sl - _Point)
               Trade.PositionModify(ticket, trailSL, PositionGetDouble(POSITION_TP));
         }
      }
   }
}

void CheckFridayClose()
{
   if(!CloseOnFriday) return;
   datetime gmt = ToGMT(TimeCurrent());
   MqlDateTime dt;
   TimeToStruct(gmt, dt);
   if(dt.day_of_week == 5 && dt.hour >= FridayCloseHour)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetSymbol(i) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MAGIC)
         {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            Trade.PositionClose(ticket);
         }
      }
   }
}

//===================================================================
// SECTION 24 — [18] STATISTICS ENGINE
//===================================================================

void OnTradeClose(ulong ticket, double profit, bool isLong, double rr)
{
   gStats.total++;
   if(profit > 0) { gStats.wins++;   gStats.grossProfit += profit; gRisk.consecLosses = 0; }
   else           { gStats.losses++; gStats.grossLoss   += MathAbs(profit); gRisk.consecLosses++; }
   gStats.sumRR += rr;

   ENUM_ATLAS_SESSION ses = gTrade.session;
   if(ses == SES_LONDON)
   { gStats.londonTotal++; if(profit > 0) gStats.londonWins++; }
   else if(ses == SES_NEWYORK)
   { gStats.nyTotal++;     if(profit > 0) gStats.nyWins++; }
   else if(ses == SES_ASIAN)
   { gStats.asianTotal++;  if(profit > 0) gStats.asianWins++; }

   if(StringFind(gTrade.model, "PDL") >= 0)
   { gStats.pdlModelTotal++; if(profit > 0) gStats.pdlModelWins++; gStats.pdlModelSumRR += rr; }
   else
   { gStats.pdhModelTotal++; if(profit > 0) gStats.pdhModelWins++; gStats.pdhModelSumRR += rr; }

   // Persist via GlobalVariable
   string pfx = "ATLAS_" + _Symbol + "_";
   GlobalVariableSet(pfx+"Total",  gStats.total);
   GlobalVariableSet(pfx+"Wins",   gStats.wins);
   GlobalVariableSet(pfx+"Losses", gStats.losses);
   GlobalVariableSet(pfx+"GP",     gStats.grossProfit);
   GlobalVariableSet(pfx+"GL",     gStats.grossLoss);
   GlobalVariableSet(pfx+"SumRR",  gStats.sumRR);

   gLastTradeClose = TimeCurrent();
}

void LoadStats()
{
   string pfx = "ATLAS_" + _Symbol + "_";
   if(GlobalVariableCheck(pfx+"Total"))  gStats.total       = (int)GlobalVariableGet(pfx+"Total");
   if(GlobalVariableCheck(pfx+"Wins"))   gStats.wins        = (int)GlobalVariableGet(pfx+"Wins");
   if(GlobalVariableCheck(pfx+"Losses")) gStats.losses      = (int)GlobalVariableGet(pfx+"Losses");
   if(GlobalVariableCheck(pfx+"GP"))     gStats.grossProfit = GlobalVariableGet(pfx+"GP");
   if(GlobalVariableCheck(pfx+"GL"))     gStats.grossLoss   = GlobalVariableGet(pfx+"GL");
   if(GlobalVariableCheck(pfx+"SumRR"))  gStats.sumRR       = GlobalVariableGet(pfx+"SumRR");
}

double GetWinRate()
{ return gStats.total > 0 ? 100.0 * gStats.wins / gStats.total : 0; }

double GetProfitFactor()
{ return gStats.grossLoss > 0 ? gStats.grossProfit / gStats.grossLoss : 0; }

double GetAvgRR()
{ return (gStats.wins + gStats.losses) > 0 ? gStats.sumRR / (gStats.wins + gStats.losses) : 0; }

//===================================================================
// SECTION 25 — [19] VISUAL / DRAW ENGINE
//===================================================================

void DrawHLine(string name, double price, color clr, int style=STYLE_DASH, int width=1, string lbl="")
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,  clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,  style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,  width);
   ObjectSetString (0, name, OBJPROP_TOOLTIP, lbl != "" ? lbl : name);
}

void DrawSweepMark(double price, datetime t, bool bull)
{
   string name = OBJ_PREFIX + "SWP_" + IntegerToString((int)t);
   if(ObjectFind(0, name) >= 0) return;
   ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, bull ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, bull ? COL_GREEN : COL_RED);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

void DrawMSSLine(double price, datetime t, bool bull)
{
   string name = OBJ_PREFIX + "MSS_" + IntegerToString((int)t);
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, bull ? C'0,180,120' : C'180,60,60');
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASHDOT);
   ObjectSetString (0, name, OBJPROP_TOOLTIP, bull ? "Bullish MSS" : "Bearish MSS");
}

void DrawFVGZone(int idx)
{
   if(idx < 0 || idx >= gFVGCount) return;
   SFVGZone z   = gFVGs[idx];
   string   nm  = OBJ_PREFIX + "FVG_" + IntegerToString(idx);
   datetime t1  = z.created;
   datetime t2  = t1 + 60 * 60 * 48;  // extend 48h
   color    clr = z.bullish ? ColorFVGBull : ColorFVGBear;
   if(ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, t1, z.top, t2, z.bottom);
   ObjectSetInteger(0, nm, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, nm, OBJPROP_FILL,      true);
   ObjectSetInteger(0, nm, OBJPROP_BACK,      true);
   ObjectSetInteger(0, nm, OBJPROP_STYLE,     STYLE_SOLID);
   ObjectSetString (0, nm, OBJPROP_TOOLTIP,   (z.bullish ? "Bull FVG" : "Bear FVG") +
                                              " [" + DoubleToString(z.bottom,_Digits) +
                                              " - " + DoubleToString(z.top,_Digits) + "]");
   gFVGs[idx].objFill = nm;
}

void DrawOBZone(int idx)
{
   if(idx < 0 || idx >= gPDACount) return;
   SPDArray pda = gPDAs[idx];
   string   nm  = OBJ_PREFIX + "OB_" + IntegerToString(idx);
   datetime t1  = pda.time;
   datetime t2  = t1 + 60 * 60 * 72;
   color    clr = pda.bullish ? ColorOBBull : ColorOBBear;
   if(ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, t1, pda.high, t2, pda.low);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_FILL,  true);
   ObjectSetInteger(0, nm, OBJPROP_BACK,  true);
   ObjectSetString (0, nm, OBJPROP_TOOLTIP, (pda.bullish ? "Bull OB" : "Bear OB") +
                                            " [" + DoubleToString(pda.low,_Digits) +
                                            " - " + DoubleToString(pda.high,_Digits) + "]");
   gPDAs[idx].objName = nm;
}

void DrawKeyLevels()
{
   if(DrawPDH_PDL)
   {
      DrawHLine(OBJ_PREFIX+"PDH", gBias.pdh, ColorPDH, STYLE_DASH, 1, "PDH");
      DrawHLine(OBJ_PREFIX+"PDL", gBias.pdl, ColorPDL, STYLE_DASH, 1, "PDL");
   }
   if(DrawPWH_PWL)
   {
      DrawHLine(OBJ_PREFIX+"PWH", gBias.pwh, ColorPWH, STYLE_DOT, 2, "PWH");
      DrawHLine(OBJ_PREFIX+"PWL", gBias.pwl, ColorPWL, STYLE_DOT, 2, "PWL");
   }
   if(DrawSessionRanges && gAsianBuilt)
   {
      DrawHLine(OBJ_PREFIX+"AsianH", gAsianH, clrSkyBlue,  STYLE_DOT, 1, "Asian High");
      DrawHLine(OBJ_PREFIX+"AsianL", gAsianL, clrLightBlue, STYLE_DOT, 1, "Asian Low");
   }
}

void DeleteAllDrawings()
{
   ObjectsDeleteAll(0, OBJ_PREFIX);
}

//===================================================================
// SECTION 26 — [20] DEBUG PANEL ENGINE
//===================================================================

void LabelSet(string name, string txt, int x, int y, color clr, int sz=8, string font="Courier New")
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_BACK,      false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
   }
   ObjectSetString (0, name, OBJPROP_TEXT,     txt);
   ObjectSetString (0, name, OBJPROP_FONT,     font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  sz);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
}

void RectSet(string name, int x, int y, int w, int h, color bg, color border)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

string PassFail(bool ok) { return ok ? " PASS" : " FAIL"; }
color  PFColor(bool ok)  { return ok ? COL_PASS : COL_FAIL; }

void SectionHeader(const string key, const string title, int &row, int x, int lh)
{
   string btnName = "ATLASP_BTN_" + key;
   LabelSet("ATLASP_SH_"+key, "--- " + title + " ---", x, RowY(row), COL_BLUE, 7);
   if(ObjectFind(0, btnName) < 0)
   {
      ObjectCreate(0, btnName, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, btnName, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, btnName, OBJPROP_XSIZE,      28);
      ObjectSetInteger(0, btnName, OBJPROP_YSIZE,      lh);
      ObjectSetInteger(0, btnName, OBJPROP_BGCOLOR,    C'40,44,68');
      ObjectSetInteger(0, btnName, OBJPROP_COLOR,      COL_GOLD);
      ObjectSetInteger(0, btnName, OBJPROP_FONTSIZE,   7);
      ObjectSetInteger(0, btnName, OBJPROP_BACK,       false);
      ObjectSetInteger(0, btnName, OBJPROP_SELECTABLE, false);
      ObjectSetString (0, btnName, OBJPROP_FONT,       "Courier New");
   }
   ObjectSetString (0, btnName, OBJPROP_TEXT,      "");
   ObjectSetInteger(0, btnName, OBJPROP_XDISTANCE, x + PANEL_W - 36);
   ObjectSetInteger(0, btnName, OBJPROP_YDISTANCE, RowY(row));
   ObjectSetInteger(0, btnName, OBJPROP_STATE,     false);
   row++;
}

void UpdateSecBtn(const string key, bool expanded)
{
   string n = "ATLASP_BTN_" + key;
   if(ObjectFind(0, n) >= 0)
      ObjectSetString(0, n, OBJPROP_TEXT, expanded ? " - " : " + ");
}

void UpdatePanel()
{
   if(!ShowPanel) return;

   int x  = gPanelX;
   int y  = gPanelY;
   int lh = PANEL_LH;
   int vx = x + 155;
   int row = 0;
   gPanY = y; gPanLH = lh;

   int hdrH = lh + 16;

   // Delete ghost labels when collapse state changes
   static bool prevCollapsed = false;
   if(prevCollapsed != gPanelCollapsed) { DeletePanel(); prevCollapsed = gPanelCollapsed; }

   // === BACKGROUND (create once; never reset YSIZE every tick — causes flash) ===
   if(ObjectFind(0, "ATLASP_BG") < 0)
   {
      ObjectCreate(0, "ATLASP_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "ATLASP_BG", OBJPROP_CORNER,       CORNER_LEFT_UPPER);
      ObjectSetInteger(0, "ATLASP_BG", OBJPROP_BACK,         false);
      ObjectSetInteger(0, "ATLASP_BG", OBJPROP_SELECTABLE,   false);
      ObjectSetInteger(0, "ATLASP_BG", OBJPROP_BGCOLOR,      COL_BG);
      ObjectSetInteger(0, "ATLASP_BG", OBJPROP_BORDER_COLOR, COL_BORDER);
      ObjectSetInteger(0, "ATLASP_BG", OBJPROP_XSIZE,        PANEL_W);
      ObjectSetInteger(0, "ATLASP_BG", OBJPROP_YSIZE,        hdrH);
   }
   ObjectSetInteger(0, "ATLASP_BG", OBJPROP_XDISTANCE, x-4);
   ObjectSetInteger(0, "ATLASP_BG", OBJPROP_YDISTANCE, y-4);
   ObjectSetInteger(0, "ATLASP_BG", OBJPROP_XSIZE,     PANEL_W);
   RectSet("ATLASP_HDR", x-4, y-4, PANEL_W, hdrH, COL_HDR, COL_BORDER);
   string modeTag = ScalperMode ? " [SCALPER]" : (AggressiveMode ? " [AGGRESSIVE]" : "");
   LabelSet("ATLASP_T",   " ICT ATLAS EA V1.0  |  " + _Symbol + modeTag, x, y+4, COL_GOLD, 9);
   LabelSet("ATLASP_BTN", gPanelCollapsed ? " [+]" : " [-]", x+PANEL_W-36, y+4, COL_GOLD, 9);

   if(gPanelCollapsed)
   {
      static int prevHdrH = 0;
      if(hdrH != prevHdrH) { ObjectSetInteger(0, "ATLASP_BG", OBJPROP_YSIZE, hdrH); prevHdrH = hdrH; }
      ChartRedraw(0);
      return;
   }

   row = 2;
   LabelSet("ATLASP_CR1", "  Created by: RATTANA CHHORM", x, RowY(row++), C'220,220,220', 9);

   const int HR = 1000;  // off-screen row — hides labels without deleting them

   // Pre-compute values needed across multiple sections
   double curPrice    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double fTop2, fBot2, fCE2;
   bool   inFVGNow    = PriceInFVG(gSetupBull, fTop2, fBot2, fCE2);
   int    validFVG = 0, mitFVG = 0;
   double nearFVGDist = 99999;
   bool   nearFVGBull = false;
   for(int i = 0; i < gFVGCount; i++)
   {
      if(!gFVGs[i].valid) continue;
      if(gFVGs[i].mitigated) { mitFVG++; continue; }
      validFVG++;
      double mid = (gFVGs[i].top + gFVGs[i].bottom) * 0.5;
      double dist = MathAbs(curPrice - mid);
      if(dist < nearFVGDist) { nearFVGDist = dist; nearFVGBull = gFVGs[i].bullish; }
   }
   int validOB = 0;
   for(int i = 0; i < gPDACount; i++) if(gPDAs[i].valid && !gPDAs[i].mitigated) validOB++;

   bool weeklyBiasOK = !RequireWeeklyBias || (gSetupBull?gBias.weekly==BIAS_BULLISH:gBias.weekly==BIAS_BEARISH);
   bool dailyBiasOK  = !RequireDailyBias  || (gSetupBull?gBias.daily==BIAS_BULLISH:gBias.daily==BIAS_BEARISH) || (gBias.daily==BIAS_NEUTRAL);
   bool sweepOK2  = !UseLiquidityEngine || (gSweepDone && gSweepBull==gSetupBull);
   bool mssOK2    = !UseMSSFilter  || (gMSS.valid  && gMSS.bullish ==gSetupBull);
   bool dispOK2   = !UseDispFilter || (gDisp.valid && gDisp.bullish==gSetupBull);
   bool fvgOK2    = !UseFVGFilter  || inFVGNow || ((AggressiveMode||ScalperMode) && !AggrRequireFVG);
   bool kzOK2     = !UseSessionFilter || InKillzone() || ((AggressiveMode||ScalperMode) && !AggrStrictKillzone);
   bool adrOK2    = !UseADRFilter  || !gADR.blocked;
   double pdpct2  = GetPremDiscPct() * 100.0;
   bool pdOK2     = !UsePremDiscFilter || (gSetupBull?pdpct2<=50:pdpct2>=50) || ((AggressiveMode||ScalperMode) && !AggrStrictPremDisc);
   bool condOK2   = !UseConditionFilter || ConditionAllowsTrade();
   bool newsOK2   = !UseNewsFilter || !IsNewsBlocked();

   // === BIAS ENGINE ===
   row++;
   SectionHeader("BIAS", "BIAS ENGINE", row, x, lh);
   UpdateSecBtn("BIAS", gSecBias);
   { int r = gSecBias ? row : HR;
     LabelSet("ATLASP_B1L","Weekly Bias :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_B1V", BiasStr(gBias.weekly), vx, RowY(r++), gBias.weekly==BIAS_BULLISH?COL_GREEN:gBias.weekly==BIAS_BEARISH?COL_RED:COL_GOLD, 8);
     LabelSet("ATLASP_B2L","Daily Bias  :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_B2V", BiasStr(gBias.daily),  vx, RowY(r++), gBias.daily==BIAS_BULLISH?COL_GREEN:gBias.daily==BIAS_BEARISH?COL_RED:COL_GOLD, 8);
     LabelSet("ATLASP_B3L","H4 Bias     :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_B3V", BiasStr(gBias.h4),     vx, RowY(r++), gBias.h4==BIAS_BULLISH?COL_GREEN:gBias.h4==BIAS_BEARISH?COL_RED:COL_GOLD, 8);
     LabelSet("ATLASP_B4L","H1 Bias     :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_B4V", BiasStr(gBias.h1),     vx, RowY(r++), gBias.h1==BIAS_BULLISH?COL_GREEN:gBias.h1==BIAS_BEARISH?COL_RED:COL_GOLD, 8);
     LabelSet("ATLASP_B5L","PDH / PDL   :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_B5V", DoubleToString(gBias.pdh,_Digits)+" / "+DoubleToString(gBias.pdl,_Digits), vx, RowY(r++), COL_GOLD, 8);
     LabelSet("ATLASP_B6L","PWH / PWL   :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_B6V", DoubleToString(gBias.pwh,_Digits)+" / "+DoubleToString(gBias.pwl,_Digits), vx, RowY(r++), COL_GOLD, 8);
     if(gSecBias) row = r;
   }

   // === LIQUIDITY SWEEP ===
   row++;
   SectionHeader("SWEEP", "LIQUIDITY SWEEP", row, x, lh);
   UpdateSecBtn("SWEEP", gSecSweep);
   { int r = gSecSweep ? row : HR;
     LabelSet("ATLASP_L1L","Liq Levels  :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_L1V", IntegerToString(gLiqCount)+" tracked", vx, RowY(r++), COL_GOLD, 8);
     string sweepTags[]   = {"PDH","PDL","PWH","PWL","AsianH","AsianL","EQH","EQL","STH","STL"};
     string sweepLabels[] = {"PDH Sweep   :","PDL Sweep   :","PWH Sweep   :","PWL Sweep   :",
                             "AsianH Sweep:","AsianL Sweep:","EQH Sweep   :","EQL Sweep   :",
                             "STH Sweep   :","STL Sweep   :"};
     for(int t = 0; t < 10; t++)
     {
        bool fnd=false, swpt=false;
        for(int i=0;i<gLiqCount;i++) if(gLiqLevels[i].tag==sweepTags[t]) { fnd=true; if(gLiqLevels[i].swept){swpt=true;break;} }
        string sv = !fnd?"N/A":(swpt?"SWEPT":"PENDING");
        color  sc = !fnd?COL_TXT:(swpt?COL_PASS:COL_FAIL);
        LabelSet("ATLASP_LS"+IntegerToString(t)+"L", sweepLabels[t], x, RowY(r), COL_TXT, 8);
        LabelSet("ATLASP_LS"+IntegerToString(t)+"V", sv, vx, RowY(r++), sc, 8);
     }
     if(gSecSweep) row = r;
   }

   // === ICT CHAIN STATE ===
   row++;
   SectionHeader("CHAIN", "ICT CHAIN STATE", row, x, lh);
   UpdateSecBtn("CHAIN", gSecChain);
   { int r = gSecChain ? row : HR;
     string chainState; color chainColor;
     if(!gSweepDone)       { chainState="WAITING FOR SWEEP"; chainColor=COL_FAIL; }
     else if(!gMSS.valid)  { chainState=gSweepBull?"BULL SWEEP->WAIT MSS":"BEAR SWEEP->WAIT MSS"; chainColor=COL_GOLD; }
     else if(!gDisp.valid) { chainState=gMSS.bullish?"MSS BULL->WAIT DISP":"MSS BEAR->WAIT DISP"; chainColor=COL_GOLD; }
     else                  { chainState=gDisp.bullish?"CHAIN COMPLETE: BULL":"CHAIN COMPLETE: BEAR"; chainColor=COL_PASS; }
     LabelSet("ATLASP_C1","  "+chainState, x, RowY(r++), chainColor, 8);
     LabelSet("ATLASP_C2L","Sweep       :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_C2V", gSweepDone?(gSweepBull?"BULL SWEEP":"BEAR SWEEP"):"NONE", vx, RowY(r++), gSweepDone?COL_GREEN:COL_FAIL, 8);
     LabelSet("ATLASP_C3L","MSS         :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_C3V", gMSS.valid?(gMSS.bullish?"BULLISH":"BEARISH"):"NONE", vx, RowY(r++), gMSS.valid?COL_GREEN:COL_FAIL, 8);
     LabelSet("ATLASP_C4L","Displacement:", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_C4V", gDisp.valid?(gDisp.bullish?"BULL":"BEAR")+(gDisp.valid?StringFormat(" %.0f%%bdy",gDisp.bodyPct*100):""):"NONE", vx, RowY(r++), gDisp.valid?COL_GREEN:COL_FAIL, 8);
     if(gSecChain) row = r;
   }

   // === FVG & PD ARRAY ===
   row++;
   SectionHeader("FVG", "FVG & PD ARRAY", row, x, lh);
   UpdateSecBtn("FVG", gSecFVG);
   { int r = gSecFVG ? row : HR;
     LabelSet("ATLASP_F1L","FVGs Active :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_F1V", IntegerToString(validFVG)+" active / "+IntegerToString(mitFVG)+" mitigated", vx, RowY(r++), validFVG>0?COL_GREEN:COL_TXT, 8);
     string nearFVGStr = validFVG>0?(nearFVGBull?"BULL":"BEAR")+" "+DoubleToString(ToPips(nearFVGDist),1)+"p away":"N/A";
     LabelSet("ATLASP_F3L","Nearest FVG :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_F3V", nearFVGStr, vx, RowY(r++), validFVG>0?COL_GOLD:COL_TXT, 8);
     LabelSet("ATLASP_F4L","In FVG Now  :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_F4V", inFVGNow?"YES — ENTRY ZONE":"NO — OUTSIDE FVG", vx, RowY(r++), inFVGNow?COL_PASS:COL_FAIL, 8);
     LabelSet("ATLASP_F2L","OBs Active  :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_F2V", IntegerToString(validOB)+" active", vx, RowY(r++), validOB>0?COL_GREEN:COL_TXT, 8);
     if(gSecFVG) row = r;
   }

   // === FILTER STATUS ===
   row++;
   SectionHeader("FILTER", "FILTER STATUS", row, x, lh);
   UpdateSecBtn("FILTER", gSecFilter);
   { int r = gSecFilter ? row : HR;
     LabelSet("ATLASP_FS1L", "Weekly Bias :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_FS1V", PassFail(weeklyBiasOK), vx, RowY(r++), PFColor(weeklyBiasOK), 8);
     LabelSet("ATLASP_FS2L", "Daily Bias  :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_FS2V", PassFail(dailyBiasOK),  vx, RowY(r++), PFColor(dailyBiasOK),  8);
     LabelSet("ATLASP_FS3L", "Liq Sweep   :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_FS3V", PassFail(sweepOK2),     vx, RowY(r++), PFColor(sweepOK2),     8);
     LabelSet("ATLASP_FS4L", "MSS         :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_FS4V", PassFail(mssOK2),       vx, RowY(r++), PFColor(mssOK2),       8);
     LabelSet("ATLASP_FS5L", "Displacement:", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_FS5V", PassFail(dispOK2),      vx, RowY(r++), PFColor(dispOK2),      8);
     LabelSet("ATLASP_FS6L", "FVG Entry   :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_FS6V", PassFail(fvgOK2),       vx, RowY(r++), PFColor(fvgOK2),       8);
     LabelSet("ATLASP_FS7L", "Session/KZ  :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_FS7V", PassFail(kzOK2),        vx, RowY(r++), PFColor(kzOK2),        8);
     LabelSet("ATLASP_FS8L", "ADR Filter  :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_FS8V", PassFail(adrOK2),       vx, RowY(r++), PFColor(adrOK2),       8);
     LabelSet("ATLASP_FS9L", "P/D Zone    :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_FS9V", PassFail(pdOK2),        vx, RowY(r++), PFColor(pdOK2),        8);
     LabelSet("ATLASP_FS10L","Mkt Cond    :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_FS10V",PassFail(condOK2),      vx, RowY(r++), PFColor(condOK2),      8);
     LabelSet("ATLASP_FS11L","News        :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_FS11V",PassFail(newsOK2),      vx, RowY(r++), PFColor(newsOK2),      8);
     if(gSecFilter) row = r;
   }

   // === SESSION & P/D ===
   row++;
   SectionHeader("SESSION", "SESSION & P/D", row, x, lh);
   UpdateSecBtn("SESSION", gSecSession);
   { int r = gSecSession ? row : HR;
     ENUM_ATLAS_SESSION ses = GetCurrentSession();
     string sesStr = ses==SES_ASIAN?"ASIAN KZ":ses==SES_LONDON?"LONDON KZ":ses==SES_NEWYORK?"NY KZ":"NO SESSION";
     LabelSet("ATLASP_SE1L","Session     :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_SE1V", sesStr, vx, RowY(r++), ses!=SES_NONE?COL_GREEN:COL_FAIL, 8);
     LabelSet("ATLASP_SE2L","ADR         :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_SE2V", DoubleToString(gADR.completionPct*100,0)+"% ("+DoubleToString(gADR.adrPips,0)+"p)", vx, RowY(r++), gADR.blocked?COL_RED:COL_GREEN, 8);
     bool newsBlk = IsNewsBlocked();
     LabelSet("ATLASP_SE3L","News        :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_SE3V", newsBlk?"BLOCKED":"CLEAR", vx, RowY(r++), newsBlk?COL_RED:COL_GREEN, 8);
     LabelSet("ATLASP_SE4L","Market Cond :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_SE4V", EnumToString(gCond.condition)+" (ADX="+DoubleToString(gCond.adxValue,1)+")", vx, RowY(r++), ConditionAllowsTrade()?COL_GREEN:COL_RED, 8);
     double pdpct = GetPremDiscPct()*100.0;
     string pdLabel = pdpct>100?DoubleToString(pdpct,0)+"% EXTREME PREMIUM":pdpct<0?DoubleToString(pdpct,0)+"% EXTREME DISCOUNT":pdpct>=50?DoubleToString(pdpct,0)+"% PREMIUM":DoubleToString(pdpct,0)+"% DISCOUNT";
     LabelSet("ATLASP_SE5L","P/D Zone    :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_SE5V", pdLabel, vx, RowY(r++), (pdpct>100||pdpct<0)?COL_RED:COL_GOLD, 8);
     if(UseSMTFilter) { LabelSet("ATLASP_SM1L","SMT Diverg  :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_SM1V", gSMT.valid?(gSMT.bullishDivergence?"BULL SMT":"BEAR SMT"):"NONE", vx, RowY(r++), gSMT.valid?COL_GREEN:COL_TXT, 8); }
     if(UsePO3Filter) { LabelSet("ATLASP_PO1L","PO3 (AMD)   :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_PO1V", gPO3.valid?(gPO3.bullish?"BULL AMD":"BEAR AMD"):(gPO3.manipDone?"MANIP":"ACCUM"), vx, RowY(r++), gPO3.valid?COL_GREEN:COL_GOLD, 8); }
     if(gSecSession) row = r;
   }

   // === CONFLUENCE SCORE ===
   row++;
   SectionHeader("SCORE", "CONFLUENCE SCORE", row, x, lh);
   UpdateSecBtn("SCORE", gSecScore);
   { int r = gSecScore ? row : HR;
     int maxScore = ScoreWeeklyBias+ScoreDailyBias+ScoreLiqSweep+ScoreMSS+ScoreDisplacement+ScoreFVG+ScoreKillzone+ScoreSMT+ScoreADR+ScorePO3+ScorePremDisc;
     int minScNow = ScalperMode?ScalperMinScore:(AggressiveMode?AggrMinScore:MinScore);
     color sclr = gScore.total>=minScNow?COL_GREEN:gScore.total>=(minScNow/2)?COL_GOLD:COL_RED;
     LabelSet("ATLASP_SC1L","Score       :", x, RowY(r), COL_TXT, 9);
     LabelSet("ATLASP_SC1V", IntegerToString(gScore.total)+" / "+IntegerToString(maxScore)+" (need "+IntegerToString(minScNow)+")", vx, RowY(r++), sclr, 9);
     color gclr = gCurGrade==GRADE_APLUS?COL_GREEN:gCurGrade==GRADE_A?C'180,220,80':gCurGrade==GRADE_B?COL_GOLD:COL_RED;
     LabelSet("ATLASP_SC2L","Grade       :", x, RowY(r), COL_TXT, 9);
     LabelSet("ATLASP_SC2V", GradeStr(gCurGrade), vx, RowY(r++), gclr, 9);
     if(gSecScore) row = r;
   }

   // === FINAL DECISION ===
   row++;
   SectionHeader("DECISION", "FINAL DECISION", row, x, lh);
   UpdateSecBtn("DECISION", gSecDecision);
   { int r = gSecDecision ? row : HR;
     color dclr = gSetupReady?COL_GREEN:COL_RED;
     LabelSet("ATLASP_D1", gSetupReady?"  TRADE READY: "+(gSetupBull?"LONG":"SHORT"):"  NO TRADE", x, RowY(r++), dclr, 9);
     for(int i=0; i<MathMin(gScore.failCount,6); i++)
        LabelSet("ATLASP_DR"+IntegerToString(i), "  >> "+gScore.failReasons[i], x, RowY(r++), COL_RED, 7);
     if(gSetupReady)
        LabelSet("ATLASP_DM", "  Model: "+gTrade.model, x, RowY(r++), COL_GOLD, 7);
     if(gTrade.ticket > 0 && HasOpenPosition())
     {
        double cp       = gTrade.isLong?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        double slPipsNow= ToPips(MathAbs(gTrade.entryPrice - gTrade.sl));
        double liveP    = ToPips(MathAbs(cp - gTrade.entryPrice));
        bool   inProfit = gTrade.isLong?cp>gTrade.entryPrice:cp<gTrade.entryPrice;
        double liveRR   = slPipsNow>0?(inProfit?1.0:-1.0)*liveP/slPipsNow:0;
        color  rrClr    = liveRR>=1.0?COL_GREEN:liveRR>=0?COL_GOLD:COL_RED;
        LabelSet("ATLASP_LVRR","  Live RR: "+DoubleToString(liveRR,2)+"R  SL="+DoubleToString(slPipsNow,1)+"p", x, RowY(r++), rrClr, 8);
     }
     if(gSecDecision) row = r;
   }

   // === RISK STATE ===
   row++;
   SectionHeader("RISK", "RISK STATE", row, x, lh);
   UpdateSecBtn("RISK", gSecRisk);
   { int r = gSecRisk ? row : HR;
     LabelSet("ATLASP_R1L","Daily P&L   :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_R1V", "$"+DoubleToString(gRisk.dailyPnL,2)+" ("+DoubleToString(gRisk.dailyR,2)+"R)", vx, RowY(r++), gRisk.dailyPnL>=0?COL_GREEN:COL_RED, 8);
     LabelSet("ATLASP_RW1L","Weekly P&L  :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_RW1V","$"+DoubleToString(gRisk.weeklyPnL,2)+" ("+DoubleToString(gRisk.weeklyR,2)+"R)", vx, RowY(r++), gRisk.weeklyPnL>=0?COL_GREEN:COL_RED, 8);
     LabelSet("ATLASP_R2L","Trades Today:", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_R2V", IntegerToString(gRisk.dailyTrades)+"/"+IntegerToString(MaxTradesPerDay), vx, RowY(r++), COL_GOLD, 8);
     LabelSet("ATLASP_R2SL","Signals     :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_R2SV", IntegerToString(gDailyChecked)+" chk / "+IntegerToString(gDailyRejected)+" blk / "+IntegerToString(gDailyExec)+" exec", vx, RowY(r++), COL_GOLD, 8);
     LabelSet("ATLASP_R3L","Trading     :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_R3V", gRisk.tradingAllowed?"ALLOWED":"STOPPED: "+gRisk.stopReason, vx, RowY(r++), gRisk.tradingAllowed?COL_GREEN:COL_RED, 8);
     LabelSet("ATLASP_R4L","Risk/Trade  :", x, RowY(r), COL_TXT, 8);
     LabelSet("ATLASP_R4V", DoubleToString(gRisk.effectiveRiskPct,2)+"%"+(gRisk.riskReduced?" (REDUCED)":""), vx, RowY(r++), gRisk.riskReduced?COL_GOLD:COL_TXT, 8);
     if(gSecRisk) row = r;
   }

   // === STATISTICS ===
   if(ShowStatPanel)
   {
      row++;
      SectionHeader("STATS", "STATISTICS", row, x, lh);
      UpdateSecBtn("STATS", gSecStats);
      { int r = gSecStats ? row : HR;
        double wr = GetWinRate();
        LabelSet("ATLASP_ST1L","Trades      :", x, RowY(r), COL_TXT, 8);
        LabelSet("ATLASP_ST1V", IntegerToString(gStats.total)+" (W:"+IntegerToString(gStats.wins)+" L:"+IntegerToString(gStats.losses)+")", vx, RowY(r++), COL_TXT, 8);
        LabelSet("ATLASP_ST2L","Win Rate    :", x, RowY(r), COL_TXT, 8);
        LabelSet("ATLASP_ST2V", DoubleToString(wr,1)+"%", vx, RowY(r++), wr>=60?COL_GREEN:wr>=50?COL_GOLD:COL_RED, 8);
        double pf2 = GetProfitFactor();
        LabelSet("ATLASP_ST3L","Profit Fact :", x, RowY(r), COL_TXT, 8);
        LabelSet("ATLASP_ST3V", DoubleToString(pf2,2), vx, RowY(r++), pf2>=1.8?COL_GREEN:pf2>=1.0?COL_GOLD:COL_RED, 8);
        LabelSet("ATLASP_ST4L","Avg RR      :", x, RowY(r), COL_TXT, 8);
        LabelSet("ATLASP_ST4V", DoubleToString(GetAvgRR(),2)+"R", vx, RowY(r++), COL_GOLD, 8);
        if(gStats.pdlModelTotal > 0 || gStats.pdhModelTotal > 0)
        {
           double pdlWR=gStats.pdlModelTotal>0?100.0*gStats.pdlModelWins/gStats.pdlModelTotal:0;
           double pdlAvgRR=gStats.pdlModelTotal>0?gStats.pdlModelSumRR/gStats.pdlModelTotal:0;
           LabelSet("ATLASP_ST5L","PDL Model   :", x, RowY(r), COL_TXT, 8);
           LabelSet("ATLASP_ST5V", IntegerToString(gStats.pdlModelTotal)+"t  "+DoubleToString(pdlWR,0)+"%WR  "+DoubleToString(pdlAvgRR,2)+"R", vx, RowY(r++), COL_GOLD, 8);
           double pdhWR=gStats.pdhModelTotal>0?100.0*gStats.pdhModelWins/gStats.pdhModelTotal:0;
           double pdhAvgRR=gStats.pdhModelTotal>0?gStats.pdhModelSumRR/gStats.pdhModelTotal:0;
           LabelSet("ATLASP_ST6L","PDH Model   :", x, RowY(r), COL_TXT, 8);
           LabelSet("ATLASP_ST6V", IntegerToString(gStats.pdhModelTotal)+"t  "+DoubleToString(pdhWR,0)+"%WR  "+DoubleToString(pdhAvgRR,2)+"R", vx, RowY(r++), COL_GOLD, 8);
        }
        if(gStats.slCount > 0)
        {
           LabelSet("ATLASP_ST7L","Avg SL Size :", x, RowY(r), COL_TXT, 8);
           LabelSet("ATLASP_ST7V", DoubleToString(gStats.sumSLPips/gStats.slCount,1)+"p  (n="+IntegerToString(gStats.slCount)+")", vx, RowY(r++), COL_GOLD, 8);
        }
        r++;
        LabelSet("ATLASP_RF0","--- REJECTION BREAKDOWN ---", x, RowY(r++), COL_BLUE, 7);
        LabelSet("ATLASP_RF1L","Session     :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_RF1V", IntegerToString(gRejSession), vx, RowY(r++), COL_RED, 8);
        LabelSet("ATLASP_RF2L","MSS         :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_RF2V", IntegerToString(gRejMSS),     vx, RowY(r++), COL_RED, 8);
        LabelSet("ATLASP_RF3L","Displacement:", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_RF3V", IntegerToString(gRejDisp),    vx, RowY(r++), COL_RED, 8);
        LabelSet("ATLASP_RF4L","FVG         :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_RF4V", IntegerToString(gRejFVG),     vx, RowY(r++), COL_RED, 8);
        LabelSet("ATLASP_RF5L","ADR         :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_RF5V", IntegerToString(gRejADR),     vx, RowY(r++), COL_RED, 8);
        LabelSet("ATLASP_RF6L","P/D Zone    :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_RF6V", IntegerToString(gRejPD),      vx, RowY(r++), COL_RED, 8);
        LabelSet("ATLASP_RF7L","SL Size     :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_RF7V", IntegerToString(gRejSLSize),  vx, RowY(r++), COL_RED, 8);
        LabelSet("ATLASP_RF8L","Score/Bias  :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_RF8V", IntegerToString(gRejScore),   vx, RowY(r++), COL_RED, 8);
        LabelSet("ATLASP_RF9L","Sweep       :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_RF9V", IntegerToString(gRejSweep),   vx, RowY(r++), COL_RED, 8);
        if(gLastRejectReason != "")
        { LabelSet("ATLASP_RFLL","Last Rej    :", x, RowY(r), COL_TXT, 8); LabelSet("ATLASP_RFLV", gLastRejectReason, vx, RowY(r++), COL_RED, 7); }
        if(gSecStats) row = r;
      }
   }

   static int prevBGH = -1;
   int newBGH = row * lh + 14;
   if(newBGH != prevBGH) { ObjectSetInteger(0, "ATLASP_BG", OBJPROP_YSIZE, newBGH); prevBGH = newBGH; }
   ChartRedraw(0);
}

void DeletePanel()
{
   ObjectsDeleteAll(0, "ATLASP_");
}

//===================================================================
// SECTION 27 — ONTRADE (closed position handler)
//===================================================================

string GetExitReason(ulong ticket)
{
   string comment = HistoryDealGetString (ticket, DEAL_COMMENT);
   int    reason  = (int)HistoryDealGetInteger(ticket, DEAL_REASON);

   if(StringFind(comment, "TP1-Partial") >= 0) return "TP1_Partial";
   if(StringFind(comment, "TP2-Partial") >= 0) return "TP2_Partial";
   if(StringFind(comment, "Friday")      >= 0) return "FridayClose";

   switch(reason)
   {
      case DEAL_REASON_TP:     return "TakeProfit";
      case DEAL_REASON_SL:     return gTrade.beSet ? "BreakEven"
                                     : (UseTrailingStop && gTrade.tp2Hit ? "TrailingStop" : "StopLoss");
      case DEAL_REASON_CLIENT:
      case DEAL_REASON_MOBILE:
      case DEAL_REASON_WEB:    return "ManualClose";
      case DEAL_REASON_SO:     return "StopOut";
      default:                 return "ExpertAdvisor";
   }
}

// Works in both Strategy Tester (OnTrade doesn't fire) and live trading.
// Called every tick from OnTick(); OnTrade() is kept as a thin live-trading alias.
void CheckForClosedTrades()
{
   if(gTrade.ticket == 0) return;
   if(PositionSelectByTicket(gTrade.ticket)) return; // Position still open

   // Retrieve all deals that belong to this position
   if(!HistorySelectByPosition(gTrade.ticket)) return;

   double   accProfit   = 0;
   ulong    finalDeal   = 0;
   datetime finalTime   = 0;
   string   finalReason = "";

   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong dk = HistoryDealGetTicket(i);
      if(dk == 0) continue;
      if(HistoryDealGetInteger(dk, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(dk, DEAL_PROFIT);
      string reason = GetExitReason(dk);

      accProfit += profit; // Accumulates partials + final close
      if(StringFind(reason, "Partial") < 0) // Final (non-partial) close
      {
         finalDeal   = dk;
         finalTime   = (datetime)HistoryDealGetInteger(dk, DEAL_TIME);
         finalReason = reason;
      }
   }

   if(finalDeal == 0) return;

   double rv = GlobalVariableCheck("ATLAS_"+IntegerToString(gTrade.ticket)+"_rv")
               ? GlobalVariableGet("ATLAS_"+IntegerToString(gTrade.ticket)+"_rv") : 0;
   double rr = (rv > 0 && gTrade.riskAmt > 0) ? accProfit / gTrade.riskAmt : 0;

   OnTradeClose(finalDeal, accProfit, gTrade.isLong, rr);
   LogTradeClose(finalDeal, finalTime, accProfit, rr, finalReason);

   // Cleanup per-position GlobalVariables
   string key = "ATLAS_" + IntegerToString(gTrade.ticket);
   GlobalVariableDel(key+"_tp1"); GlobalVariableDel(key+"_tp2");
   GlobalVariableDel(key+"_tp3"); GlobalVariableDel(key+"_rv");
   GlobalVariableDel(key+"_t1h"); GlobalVariableDel(key+"_t2h");
   GlobalVariableDel(key+"_be");  GlobalVariableDel(key+"_long");

   gTrade.ticket = 0; // Prevent double-logging on subsequent ticks
}

void OnTrade() { CheckForClosedTrades(); }

//===================================================================
// SECTION 31 — ML DATA COLLECTION ENGINE
//===================================================================

bool WasTagSwept(const string tag)
{
   for(int i = 0; i < gLiqCount; i++)
      if(gLiqLevels[i].tag == tag && gLiqLevels[i].swept) return true;
   return false;
}

string GetPDLabel()
{
   if(gDRHigh <= gDRLow) return "UNKNOWN";
   double pct = (SymbolInfoDouble(_Symbol, SYMBOL_BID) - gDRLow) / (gDRHigh - gDRLow);
   if(pct >= (1.0 - PremiumZone)) return "PREMIUM";
   if(pct <= DiscountZone)        return "DISCOUNT";
   return "EQUILIBRIUM";
}

string GetADRLabel()   { return gADR.blocked ? "BLOCKED" : "OK"; }

string GetCondLabel()
{
   switch(gCond.condition)
   {
      case COND_TRENDING: return "TRENDING";
      case COND_RANGING:  return "RANGING";
      default:            return "CHOPPY";
   }
}

string SessionCSV(ENUM_ATLAS_SESSION s)
{
   switch(s)
   {
      case SES_LONDON:  return "LONDON";
      case SES_NEWYORK: return "NEWYORK";
      case SES_ASIAN:   return "ASIAN";
      default:          return "NONE";
   }
}

string YN(bool b)     { return b ? "YES" : "NO"; }

string CSVSafe(const string s)
{
   string r = s;
   StringReplace(r, ",",  ";");
   StringReplace(r, "\"", "'");
   StringReplace(r, "\n", " ");
   return r;
}

string GetRejectedStep(const string reason)
{
   if(StringFind(reason,"Liquidity")>=0||StringFind(reason,"Sweep")>=0) return "SWEEP";
   if(StringFind(reason,"MSS")      >=0) return "MSS";
   if(StringFind(reason,"Disp")     >=0) return "DISPLACEMENT";
   if(StringFind(reason,"FVG")      >=0) return "FVG";
   if(StringFind(reason,"Kill")     >=0||StringFind(reason,"session")>=0) return "SESSION";
   if(StringFind(reason,"ADR")      >=0) return "ADR";
   if(StringFind(reason,"P/D")      >=0) return "PD_ARRAY";
   if(StringFind(reason,"Score")    >=0) return "SCORE";
   if(StringFind(reason,"Grade")    >=0) return "GRADE";
   if(StringFind(reason,"Bias")     >=0) return "BIAS";
   if(StringFind(reason,"News")     >=0) return "NEWS";
   if(StringFind(reason,"Condition")>=0) return "MARKET_CONDITION";
   if(StringFind(reason,"SL t")     >=0) return "SL_SIZE";
   return "OTHER";
}

void InitMLCSVFiles()
{
   if(!EnableMLExport) return;
   // In Strategy Tester, always create a fresh file so backtest data is never
   // mixed with live-session rows that may exist from a prior run.
   bool isTester = (bool)MQLInfoInteger(MQL_TESTER);

   if(MLExportSignals)
   {
      string fname = "ICT_ATLAS_All_Signals_" + _Symbol + ".csv";
      bool needHeader = isTester;

      if(!isTester)
      {
         // Live: append to existing file
         gMLSignalFile = FileOpen(fname, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
         if(gMLSignalFile != INVALID_HANDLE)
            FileSeek(gMLSignalFile, 0, SEEK_END);
         else
            needHeader = true; // File didn't exist — write header below
      }

      if(gMLSignalFile == INVALID_HANDLE)
      {
         // Tester: always overwrite; Live: create if missing
         gMLSignalFile = FileOpen(fname, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
      }
      if(gMLSignalFile != INVALID_HANDLE && needHeader)
         FileWrite(gMLSignalFile,
            "SetupID","Timestamp","DayOfWeek","Symbol","Direction",
            "WeeklyBias","DailyBias","H4Bias","H1Bias",
            "PDH_Sweep","PDL_Sweep","PWH_Sweep","PWL_Sweep",
            "Asian_Sweep","EQH_Sweep","EQL_Sweep",
            "MSS","Displacement","FVG_Present","OB_Present",
            "ADR_Status","PremDisc_Status","Session",
            "MarketCondition","News_Blocked",
            "ConfluenceScore","Grade",
            "Trade_Executed","Rejected_Step","Rejected_Reason",
            "ATR14_Pips","ATR50_Pips","Spread_Pips","SpreadPctATR",
            "ADX_Value","PlannedRR");

      if(gMLSignalFile == INVALID_HANDLE)
         Print("ATLAS ML: Cannot open signal file — ", fname);
      else
         Print("ATLAS ML: Signal log → ", fname, isTester ? " [BACKTEST-FRESH]" : " [LIVE-APPEND]");
   }

   if(MLExportTrades)
   {
      string fname = "ICT_ATLAS_Trade_History_" + _Symbol + ".csv";
      bool needHeader = isTester;

      if(!isTester)
      {
         // Live: append to existing file
         gMLTradeFile = FileOpen(fname, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
         if(gMLTradeFile != INVALID_HANDLE)
            FileSeek(gMLTradeFile, 0, SEEK_END);
         else
            needHeader = true;
      }

      if(gMLTradeFile == INVALID_HANDLE)
      {
         // Tester: always overwrite; Live: create if missing
         gMLTradeFile = FileOpen(fname, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
      }
      if(gMLTradeFile != INVALID_HANDLE && needHeader)
         FileWrite(gMLTradeFile,
            "SetupID","Ticket","OpenTime","CloseTime","DayOfWeek",
            "Symbol","Direction",
            "EntryPrice","StopLoss","TakeProfit","LotSize","RiskPct",
            "Session","ConfluenceScore","Grade",
            "WeeklyBias","DailyBias","H4Bias","H1Bias",
            "PDH_Sweep","PDL_Sweep","PWH_Sweep","PWL_Sweep",
            "Asian_Sweep","EQH_Sweep","EQL_Sweep",
            "MSS","Displacement","FVG_Present","OB_Present",
            "ADR_Status","PremDisc_Status","MarketCondition",
            "ATR14_Pips_Entry","ATR50_Pips_Entry",
            "Spread_Pips_Entry","SpreadPctATR_Entry","ADX_Entry",
            "Profit_USD","Profit_Pct",
            "PlannedRR","RR_Achieved",
            "MFE_Pips","MAE_Pips",
            "MinutesInTrade","BarsInTrade",
            "ExitReason","Trade_Result");

      if(gMLTradeFile == INVALID_HANDLE)
         Print("ATLAS ML: Cannot open trade file — ", fname);
      else
         Print("ATLAS ML: Trade log → ", fname, isTester ? " [BACKTEST-FRESH]" : " [LIVE-APPEND]");
   }
}

void CloseMLCSVFiles()
{
   if(gMLSignalFile != INVALID_HANDLE) { FileClose(gMLSignalFile); gMLSignalFile = INVALID_HANDLE; }
   if(gMLTradeFile  != INVALID_HANDLE) { FileClose(gMLTradeFile);  gMLTradeFile  = INVALID_HANDLE; }
}

void LogSignal(const string setupID, bool executed, bool bullish, const string failStep, const string failReason)
{
   if(!EnableMLExport || !MLExportSignals) return;
   if(gMLSignalFile == INVALID_HANDLE) return;

   bool fvgPresent = false;
   for(int i = 0; i < gFVGCount; i++)
      if(gFVGs[i].valid && !gFVGs[i].mitigated && gFVGs[i].bullish == bullish)
         { fvgPresent = true; break; }
   bool obPresent = false;
   for(int i = 0; i < gPDACount; i++)
      if(gPDAs[i].valid && !gPDAs[i].mitigated && gPDAs[i].bullish == bullish)
         { obPresent = true; break; }

   double atr14  = ToPips(GetATRMain(1));
   double atr50  = ToPips(GetATR50(1));
   double spread = GetCurrentSpreadPips();
   double adx    = GetADX(CondADXPeriod, 1);
   double spdPct = (atr14 > 0) ? spread / atr14 * 100.0 : 0;

   datetime barTime = iTime(_Symbol, PERIOD_M15, 0);
   FileWrite(gMLSignalFile,
      setupID,
      TimeToString(barTime, TIME_DATE|TIME_SECONDS),
      DayOfWeekStr(barTime),
      _Symbol,
      bullish ? "LONG" : "SHORT",
      BiasStr(gBias.weekly), BiasStr(gBias.daily),
      BiasStr(gBias.h4),     BiasStr(gBias.h1),
      YN(WasTagSwept("PDH")), YN(WasTagSwept("PDL")),
      YN(WasTagSwept("PWH")), YN(WasTagSwept("PWL")),
      YN(WasTagSwept("AsianH") || WasTagSwept("AsianL")),
      YN(WasTagSwept("EQH")),  YN(WasTagSwept("EQL")),
      YN(gMSS.valid  && gMSS.bullish  == bullish),
      YN(gDisp.valid && gDisp.bullish == bullish),
      YN(fvgPresent), YN(obPresent),
      GetADRLabel(), GetPDLabel(),
      SessionCSV(GetCurrentSession()),
      GetCondLabel(), YN(IsNewsBlocked()),
      IntegerToString(gScore.total), GradeStr(gCurGrade),
      YN(executed),
      CSVSafe(failStep), CSVSafe(failReason),
      DoubleToString(atr14,  2),
      DoubleToString(atr50,  2),
      DoubleToString(spread, 2),
      DoubleToString(spdPct, 2),
      DoubleToString(adx,    2),
      DoubleToString(TP3_RR, 2));
}

void LogTradeClose(ulong ticket, datetime closeTime, double profit, double rr, const string exitReason)
{
   if(!EnableMLExport || !MLExportTrades) return;
   if(gMLTradeFile == INVALID_HANDLE) return;

   double bal         = AccountInfoDouble(ACCOUNT_BALANCE);
   double profPct     = (bal > 0) ? profit / bal * 100.0 : 0;
   string result      = (profit >  0.001) ? "WIN"
                      : (profit < -0.001) ? "LOSS"
                      :                     "BREAKEVEN";
   long   minInTrade  = (long)((closeTime - gTrade.openTime) / 60);
   int    barsInTrade = (int)(minInTrade / PeriodSeconds(PERIOD_M15) * 60);
   double spdPctATR   = (gTrade.snapATR14 > 0) ? gTrade.snapSpread / gTrade.snapATR14 * 100.0 : 0;

   FileWrite(gMLTradeFile,
      gTrade.setupID,
      IntegerToString((long)ticket),
      TimeToString(gTrade.openTime, TIME_DATE|TIME_SECONDS),
      TimeToString(closeTime,       TIME_DATE|TIME_SECONDS),
      DayOfWeekStr(gTrade.openTime),
      _Symbol,
      gTrade.isLong ? "LONG" : "SHORT",
      DoubleToString(gTrade.entryPrice, _Digits),
      DoubleToString(gTrade.sl,         _Digits),
      DoubleToString(gTrade.tp3,        _Digits),
      DoubleToString(gTrade.lot,        2),
      DoubleToString(RiskPercent,       2),
      SessionCSV(gTrade.session),
      IntegerToString(gTrade.score), GradeStr(gTrade.grade),
      BiasStr(gTrade.snapWeekly), BiasStr(gTrade.snapDaily),
      BiasStr(gTrade.snapH4),     BiasStr(gTrade.snapH1),
      YN(gTrade.snapPDHSwept), YN(gTrade.snapPDLSwept),
      YN(gTrade.snapPWHSwept), YN(gTrade.snapPWLSwept),
      YN(gTrade.snapAsianSwept),
      YN(gTrade.snapEQHSwept), YN(gTrade.snapEQLSwept),
      YN(gTrade.snapMSS), YN(gTrade.snapDisp),
      YN(gTrade.snapFVGPresent), YN(gTrade.snapOBPresent),
      CSVSafe(gTrade.snapADR), CSVSafe(gTrade.snapPD),
      CSVSafe(gTrade.snapCond),
      DoubleToString(gTrade.snapATR14,  2),
      DoubleToString(gTrade.snapATR50,  2),
      DoubleToString(gTrade.snapSpread, 2),
      DoubleToString(spdPctATR,         2),
      DoubleToString(gTrade.snapADX,    2),
      DoubleToString(profit,            2),
      DoubleToString(profPct,           4),
      DoubleToString(TP3_RR,            2),
      DoubleToString(rr,                3),
      DoubleToString(gTrade.mfePips,    1),
      DoubleToString(gTrade.maePips,    1),
      IntegerToString(minInTrade),
      IntegerToString(barsInTrade),
      exitReason,
      result);
}

//===================================================================
// SECTION 28 — MAIN ENGINE TICK
//===================================================================

void RunAllEngines()
{
   RunBiasEngine();
   RunLiquidityEngine();
   RunMSSEngine();
   RunDisplacementEngine();
   ScanFVGs();
   ScanOrderBlocks();
   ScanBreakerBlocks();
   ScanNDOG_NWOG();
   RunPO3Engine();
   RunSMTEngine();
   RunADREngine();
   RunConditionEngine();
   UpdateSessionRanges();
   DrawKeyLevels();
   ParseNewsTimes();
}

void TrackRejection(const string reason)
{
   gLastRejectReason = reason;
   if     (StringFind(reason, "Sweep") >= 0 || StringFind(reason, "sweep") >= 0) gRejSweep++;
   else if(StringFind(reason, "MSS")   >= 0) gRejMSS++;
   else if(StringFind(reason, "Disp")  >= 0) gRejDisp++;
   else if(StringFind(reason, "FVG")   >= 0) gRejFVG++;
   else if(StringFind(reason, "Kill")  >= 0 || StringFind(reason, "session") >= 0) gRejSession++;
   else if(StringFind(reason, "ADR")   >= 0) gRejADR++;
   else if(StringFind(reason, "P/D")   >= 0) gRejPD++;
   else if(StringFind(reason, "SL t")  >= 0) gRejSLSize++;
   else if(StringFind(reason, "Score") >= 0 || StringFind(reason, "Grade") >= 0 ||
           StringFind(reason, "Bias")  >= 0) gRejScore++;
   else gRejOther++;
}

void CheckForEntry()
{
   if(!CanTrade()) return;
   if(!gRisk.tradingAllowed) return;

   static datetime lastCountedBar = 0;
   datetime curBar = iTime(_Symbol, PERIOD_M15, 0);
   bool isNewBar = (curBar != lastCountedBar);

   // Generate a unique SetupID once per new bar
   if(isNewBar)
   {
      gSetupCounter++;
      MqlDateTime dt;
      TimeToStruct(curBar, dt);
      gCurSetupID = StringFormat("ATLAS_%04d%02d%02d_%02d%02d%02d_%04d",
         dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec, gSetupCounter);
   }

   // Determine the primary direction from HTF bias so the panel always
   // shows the most relevant score/fail reasons even when no trade fires.
   ENUM_ATLAS_BIAS combinedBias;
   if(gBias.weekly == gBias.daily && gBias.weekly != BIAS_NEUTRAL)
      combinedBias = gBias.weekly;
   else if(gBias.weekly != BIAS_NEUTRAL)
      combinedBias = gBias.weekly;
   else
      combinedBias = gBias.daily;

   bool preferBull = (combinedBias != BIAS_BEARISH);

   // Evaluate primary direction first and save its score for the panel.
   gScore.failCount = 0;
   bool okPrimary = ValidateSetup(preferBull);
   SScoreCard primaryScore = gScore;
   ENUM_ATLAS_GRADE primaryGrade = CalcGrade(gScore.total);

   if(okPrimary)
   {
      if(isNewBar) { lastCountedBar = curBar; gDailyChecked++; }
      gSetupReady = true;
      gSetupBull  = preferBull;
      gCurGrade   = primaryGrade;
      bool placed = PlaceTrade(preferBull);
      if(!placed) { gSetupReady = false; if(isNewBar) gDailyRejected++; }
      if(DebugLogs) Print("SETUP ", placed?"EXECUTED":"REJECTED", ": ",
                          preferBull?"BULL":"BEAR", " Score=", gScore.total,
                          " Chk=", gDailyChecked, " Rej=", gDailyRejected,
                          " Exec=", gDailyExec);
      if(isNewBar)
      {
         string rejStep   = placed ? "" : GetRejectedStep(gLastRejectReason);
         string rejReason = placed ? "" : gLastRejectReason;
         LogSignal(gCurSetupID, placed, preferBull, rejStep, rejReason);
      }
      return;
   }

   // Try opposite direction (counter-trend only when primary fails)
   gScore.failCount = 0;
   bool okSecond = ValidateSetup(!preferBull);

   if(okSecond)
   {
      if(isNewBar) { lastCountedBar = curBar; gDailyChecked++; }
      gSetupReady = true;
      gSetupBull  = !preferBull;
      gCurGrade   = CalcGrade(gScore.total);
      bool placed = PlaceTrade(!preferBull);
      if(!placed) { gSetupReady = false; if(isNewBar) gDailyRejected++; }
      if(DebugLogs) Print("SETUP ", placed?"EXECUTED":"REJECTED", " (COUNTER): ",
                          !preferBull?"BULL":"BEAR", " Score=", gScore.total);
      if(isNewBar)
      {
         string rejStep   = placed ? "" : GetRejectedStep(gLastRejectReason);
         string rejReason = placed ? "" : gLastRejectReason;
         LogSignal(gCurSetupID, placed, !preferBull, rejStep, rejReason);
      }
      return;
   }

   // No trade — restore primary-direction score so the panel shows
   // WHY the bias-aligned direction was rejected.
   gScore     = primaryScore;
   gCurGrade  = primaryGrade;
   gSetupReady = false;
   if(primaryScore.failCount > 0) TrackRejection(primaryScore.failReasons[0]);

   if(isNewBar)
   {
      lastCountedBar = curBar;
      string step   = primaryScore.failCount > 0 ? GetRejectedStep(primaryScore.failReasons[0]) : "NONE";
      string reason = primaryScore.failCount > 0 ? primaryScore.failReasons[0] : "No setup";
      LogSignal(gCurSetupID, false, preferBull, step, reason);

      if(DebugLogs)
      {
         string reasons = "";
         for(int i = 0; i < MathMin(gScore.failCount, 4); i++)
            reasons += " | " + gScore.failReasons[i];
         Print("SETUP REJECTED: Score=", gScore.total, reasons);
      }
   }
}

//===================================================================
// SECTION 29 — OnInit / OnDeinit / OnTick
//===================================================================

int OnInit()
{
   SetupPipFactor();
   ApplySymbolPreset();
   InitRiskState();
   LoadStats();
   ParseNewsTimes();

   gATR14 = iATR(_Symbol, PERIOD_M15, 14);
   gATR50 = iATR(_Symbol, PERIOD_M15, 50);
   gADX14 = iADX(_Symbol, PERIOD_M15, CondADXPeriod);

   if(gATR14 == INVALID_HANDLE || gATR50 == INVALID_HANDLE || gADX14 == INVALID_HANDLE)
   { Alert(EA_NAME + ": Indicator init failed"); return INIT_FAILED; }

   Trade.SetExpertMagicNumber(MAGIC);
   Trade.SetDeviationInPoints((ulong)(MaxSlippagePips * (int)gPipFactor));
   Trade.SetTypeFillingBySymbol(_Symbol);

   gPanelX = PanelX;
   gPanelY = PanelY;

   // Initialize stats peak equity
   gStats.peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   gLastTradeDay = now.day_of_year;

   Print("══════════════════════════════════════════════");
   Print(EA_NAME, " — ICT 2022 Mentorship Institutional Grade");
   Print("Symbol: ", _Symbol, " | Period: ", EnumToString(_Period));
   Print("Pip factor: ", gPipFactor, " | Max SL: ", gEffMaxSL, "p | Min SL: ", gEffMinSL, "p");
   Print("Risk: ", RiskPercent, "% | Min Score: ", MinScore, " | Grades: ", EnumToString(AllowedGrades));
   Print("══════════════════════════════════════════════");

   InitMLCSVFiles();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   CloseMLCSVFiles();
   if(gATR14 != INVALID_HANDLE) IndicatorRelease(gATR14);
   if(gATR50 != INVALID_HANDLE) IndicatorRelease(gATR50);
   if(gADX14 != INVALID_HANDLE) IndicatorRelease(gADX14);
   DeleteAllDrawings();
   DeletePanel();
   Comment("");
}

void OnTick()
{
   // Check new D1 bar (reset liq levels)
   datetime d1Time[1];
   if(CopyTime(_Symbol, PERIOD_D1, 0, 1, d1Time) == 1 && d1Time[0] != gLastBarD1)
   {
      gLastBarD1 = d1Time[0];
      // Reset daily liquidity levels except PWH/PWL
      for(int i = 0; i < gLiqCount; i++)
         if(gLiqLevels[i].tag == "PDH" || gLiqLevels[i].tag == "PDL")
            gLiqLevels[i].valid = false;
      // Compact
      int newCount = 0;
      for(int i = 0; i < gLiqCount; i++)
         if(gLiqLevels[i].valid) gLiqLevels[newCount++] = gLiqLevels[i];
      gLiqCount = newCount;
      gSweepDone = false;
      gMSS.valid = false;
      gDisp.valid = false;
   }

   // Check new W1 bar
   datetime w1Time[1];
   if(CopyTime(_Symbol, PERIOD_W1, 0, 1, w1Time) == 1 && w1Time[0] != gLastBarW1)
   {
      gLastBarW1 = w1Time[0];
      gLiqCount  = 0;  // Full reset on new week
      gFVGCount  = 0;
      gPDACount  = 0;
      gSweepDone = false;
      gMSS.valid = false;
      gDisp.valid = false;
      gPO3 = SPO3State();
      gStats.peakEquity = MathMax(gStats.peakEquity, AccountInfoDouble(ACCOUNT_EQUITY));
   }

   // New M15 bar — run all engines
   datetime m15Time[1];
   if(CopyTime(_Symbol, PERIOD_M15, 0, 1, m15Time) == 1 && m15Time[0] != gLastBarM15)
   {
      gLastBarM15 = m15Time[0];
      UpdateRiskState();
      RunAllEngines();
   }

   // Every tick
   ManageTrades();
   CheckForClosedTrades();
   CheckFridayClose();
   CheckForEntry();
   UpdatePanel();
}

void OnChartEvent(const int id, const long& lp, const double& dp, const string& sp)
{
   // Panel drag support
   static bool dragging = false;
   static int  dxOff = 0, dyOff = 0;

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sp=="ATLASP_BTN_BIAS")    { gSecBias    =!gSecBias;    ObjectSetInteger(0,sp,OBJPROP_STATE,false); UpdatePanel(); return; }
      if(sp=="ATLASP_BTN_SWEEP")   { gSecSweep   =!gSecSweep;   ObjectSetInteger(0,sp,OBJPROP_STATE,false); UpdatePanel(); return; }
      if(sp=="ATLASP_BTN_CHAIN")   { gSecChain   =!gSecChain;   ObjectSetInteger(0,sp,OBJPROP_STATE,false); UpdatePanel(); return; }
      if(sp=="ATLASP_BTN_FVG")     { gSecFVG     =!gSecFVG;     ObjectSetInteger(0,sp,OBJPROP_STATE,false); UpdatePanel(); return; }
      if(sp=="ATLASP_BTN_FILTER")  { gSecFilter  =!gSecFilter;  ObjectSetInteger(0,sp,OBJPROP_STATE,false); UpdatePanel(); return; }
      if(sp=="ATLASP_BTN_SESSION") { gSecSession =!gSecSession; ObjectSetInteger(0,sp,OBJPROP_STATE,false); UpdatePanel(); return; }
      if(sp=="ATLASP_BTN_SCORE")   { gSecScore   =!gSecScore;   ObjectSetInteger(0,sp,OBJPROP_STATE,false); UpdatePanel(); return; }
      if(sp=="ATLASP_BTN_DECISION"){ gSecDecision=!gSecDecision;ObjectSetInteger(0,sp,OBJPROP_STATE,false); UpdatePanel(); return; }
      if(sp=="ATLASP_BTN_RISK")    { gSecRisk    =!gSecRisk;    ObjectSetInteger(0,sp,OBJPROP_STATE,false); UpdatePanel(); return; }
      if(sp=="ATLASP_BTN_STATS")   { gSecStats   =!gSecStats;   ObjectSetInteger(0,sp,OBJPROP_STATE,false); UpdatePanel(); return; }
   }

   if(id == CHARTEVENT_OBJECT_CLICK && sp == "ATLASP_BTN")
   { gPanelCollapsed = !gPanelCollapsed; UpdatePanel(); return; }

   if(id == CHARTEVENT_OBJECT_CLICK && sp == "ATLASP_T")
   { dragging = true; dxOff = (int)lp - gPanelX; dyOff = (int)dp - gPanelY; }
   if(id == CHARTEVENT_MOUSE_MOVE && dragging)
   {
      gPanelX = (int)lp - dxOff;
      gPanelY = (int)dp - dyOff;
      gPanelX = MathMax(0, MathMin((int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)  - PANEL_W, gPanelX));
      gPanelY = MathMax(0, MathMin((int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS) - 60,       gPanelY));
      UpdatePanel();
   }
   if(id == CHARTEVENT_CLICK || (id == CHARTEVENT_MOUSE_MOVE && dp == 0))
      dragging = false;
}

//===================================================================
// SECTION 30 — STRATEGY TESTER REPORT (OnTester)
//===================================================================

double OnTester()
{
   double wr = GetWinRate();
   double pf = GetProfitFactor();
   double ar = GetAvgRR();

   Print("╔══════════════════════════════════════════════╗");
   Print("║         ICT ATLAS EA — STRATEGY REPORT        ║");
   Print("╠══════════════════════════════════════════════╣");
   Print("║ Total Trades      : ", gStats.total);
   Print("║ Win Rate          : ", DoubleToString(wr, 1), "%");
   Print("║ Wins / Losses     : ", gStats.wins, " / ", gStats.losses);
   Print("║ Profit Factor     : ", DoubleToString(pf, 2));
   Print("║ Average RR        : ", DoubleToString(ar, 2), "R");
   Print("║ Gross Profit      : $", DoubleToString(gStats.grossProfit, 2));
   Print("║ Gross Loss        : $", DoubleToString(gStats.grossLoss, 2));
   Print("╠══════════════════════════════════════════════╣");
   Print("║  SESSION BREAKDOWN");
   Print("║ London   : ", gStats.londonTotal, " trades  WR=",
         (gStats.londonTotal>0?DoubleToString(100.0*gStats.londonWins/gStats.londonTotal,0):"N/A"), "%");
   Print("║ New York : ", gStats.nyTotal, " trades  WR=",
         (gStats.nyTotal>0?DoubleToString(100.0*gStats.nyWins/gStats.nyTotal,0):"N/A"), "%");
   Print("║ Asian    : ", gStats.asianTotal, " trades  WR=",
         (gStats.asianTotal>0?DoubleToString(100.0*gStats.asianWins/gStats.asianTotal,0):"N/A"), "%");
   Print("╠══════════════════════════════════════════════╣");
   Print("║  MODEL BREAKDOWN");
   Print("║ PDL+MSS+FVG : ", gStats.pdlModelTotal, " trades  WR=",
         (gStats.pdlModelTotal>0?DoubleToString(100.0*gStats.pdlModelWins/gStats.pdlModelTotal,0):"N/A"), "%");
   Print("║ PDH+MSS+FVG : ", gStats.pdhModelTotal, " trades  WR=",
         (gStats.pdhModelTotal>0?DoubleToString(100.0*gStats.pdhModelWins/gStats.pdhModelTotal,0):"N/A"), "%");
   Print("╚══════════════════════════════════════════════╝");

   // Return custom fitness: combination of PF and WR
   return pf * (wr / 100.0);
}
//+------------------------------------------------------------------+

