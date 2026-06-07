//+------------------------------------------------------------------+
//|                                         SMC SCALPER V1.0         |
//|              M1/M5 HIGH FREQUENCY SCALPING EA                    |
//|   EMA CROSS · RSI · ATR · SESSION · PARTIAL TP · CSV · SCREEN   |
//|               Created By — RATTANA CHHORM                        |
//+------------------------------------------------------------------+
//
// STRATEGY:
//  Signal  : EMA Fast/Slow crossover (bar-close confirmed, no repaint)
//  Trend   : EMA Trend — only trade in trend direction
//  Filter  : RSI momentum — avoid overbought/oversold entries
//  SL/TP   : ATR-based — adapts to current volatility
//  Partial : Close 50% at 1R, move SL to breakeven
//  Sessions: London + New York (configurable)
//
// EXPECTED FREQUENCY (M1, default settings):
//  Active day  : 10–25 trades
//  Quiet day   :  5–12 trades
//  Max/day     : set via MaxTradesPerDayS (default 30)
//
// MAGIC NUMBER: 999888
//+------------------------------------------------------------------+

#property copyright "RATTANA CHHORM"
#property version   "1.0"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//===================================================================//
//  ENUMERATIONS
//===================================================================//
enum ENUM_RISK_MODE_SC
{
   SC_RISK_FIXED_PCT  = 0,  // Fixed % of balance
   SC_RISK_FIXED_LOT  = 1,  // Fixed lot size
   SC_RISK_DYNAMIC_EQ = 2   // Dynamic equity %
};

enum ENUM_SIGNAL_MODE_SC
{
   SC_SIG_EMA_CROSS    = 0,  // EMA Crossover — fires on each cross
   SC_SIG_EMA_SLOPE    = 1,  // EMA Slope — fires every bar both EMAs slope same way
   SC_SIG_PRICE_ACTION = 2   // Engulfing candle — fires on strong reversal bars
};

//===================================================================//
//  CONSTANTS
//===================================================================//
const int    MAGIC_SC  = 999888;
const string EA_SC     = "SMC SCALPER V1.0";
const string PFX_SC    = "Sc1_";

//===================================================================//
//  INPUTS
//===================================================================//

//--- SIGNAL SETTINGS -----------------------------------------------
input group "========== SIGNAL SETTINGS =========="
input ENUM_SIGNAL_MODE_SC SignalMode  = SC_SIG_EMA_CROSS; // Signal type
input int    EMAFast                  = 5;     // Fast EMA period
input int    EMASlow                  = 13;    // Slow EMA period
input int    EMATrend                 = 50;    // Trend EMA period (price filter)
input bool   UseTrendFilterSC         = true;  // Only trade in EMA trend direction
input int    RSIPeriodSC              = 14;    // RSI period
input double RSIBuyMin                = 45.0;  // RSI min for BUY (momentum up)
input double RSIBuyMax                = 75.0;  // RSI max for BUY (not overbought)
input double RSISellMin               = 25.0;  // RSI min for SELL (not oversold)
input double RSISellMax               = 55.0;  // RSI max for SELL (momentum down)
input bool   UseRSIFilterSC           = true;  // Enable RSI filter
input int    ATRPeriodSC              = 14;    // ATR period (volatility measure)

//--- STOP LOSS / TAKE PROFIT ---------------------------------------
input group "========== STOP LOSS / TAKE PROFIT =========="
input double SLMultiATR               = 0.8;   // SL = ATR × this value
input double TPMultiATR               = 1.6;   // TP = ATR × this value (= 2:1 R:R)

//--- PARTIAL TAKE PROFIT -------------------------------------------
input group "========== PARTIAL TAKE PROFIT =========="
input bool   UsePartialSC             = true;  // Close 50% at 1R, rest to full TP
input double PartialPctSC             = 50.0;  // % of position to close at partial
input double PartialRRSC              = 1.0;   // R:R trigger for partial close

//--- RISK MANAGEMENT -----------------------------------------------
input group "========== RISK MANAGEMENT =========="
input ENUM_RISK_MODE_SC RiskModeSC    = SC_RISK_FIXED_PCT; // Risk calculation mode
input double RiskPctSC                = 0.5;   // Risk per trade (% of balance)
input double FixedLotSC               = 0.0;   // Fixed lot (0.0 = use RiskPct mode)
input double MaxLotSC                 = 0.10;  // Hard lot size ceiling (safety cap)
input double MaxDailyLossPctSC        = 10.0;  // Stop trading if daily loss exceeds %
input int    MaxTradesPerDaySC        = 30;    // Max trades allowed per day
input int    MaxConsecLossesSC        = 5;     // Stop after N consecutive losses

//--- TRADE FILTERS -------------------------------------------------
input group "========== TRADE FILTERS =========="
input int    MaxSpreadSC              = 50;    // Max spread in points (0=disable)
input double MinATRPipsSC             = 1.5;  // Min ATR in pips — skip flat market
input int    MaxSLPipsSC              = 20;   // Max SL in pips (FIX O style)
input int    MinSLPipsSC              = 2;    // Min SL in pips (avoid tight stops)
input int    CooldownBarsSC           = 2;    // Wait N bars after trade before next
input bool   OneAtATimeSC             = true;  // Only 1 open position at a time

//--- SESSIONS (GMT TIME) ------------------------------------------
input group "========== SESSIONS (GMT TIME) =========="
input bool   AutoGMT_SC               = true;  // Auto-detect GMT offset
input int    GMTOffsetSC              = 0;     // Manual GMT offset (AutoGMT=false)
input bool   SydneySC                 = false; // Sydney session 22:00–01:00 GMT
input bool   TokyoSC                  = false; // Tokyo session  00:00–04:00 GMT
input bool   LondonSC                 = true;  // London session 08:00–12:00 GMT
input bool   NewYorkSC                = true;  // New York session 13:00–17:00 GMT
input bool   OverlapSC                = true;  // London/NY overlap 13:00–16:00 GMT
input bool   AllHoursSC               = false; // Trade 24 hours (ignore sessions)

//--- POSITION MANAGEMENT ------------------------------------------
input group "========== POSITION MANAGEMENT =========="
input bool   CloseFridaySC            = true;  // Close all positions Friday cut-off
input int    FridayHourSC             = 14;    // Friday close hour (GMT)
input bool   TrailStopSC              = false; // Enable ATR trailing stop
input double TrailATRMulti            = 0.5;   // Trail distance = ATR × this value

//--- LOGGING ------------------------------------------------------
input group "========== LOGGING =========="
input bool   ScreenshotSC             = true;  // Screenshot on trade open/close
input bool   CSVLogSC                 = true;  // Export every trade to CSV file

//--- DEBUG --------------------------------------------------------
input group "========== DEBUG =========="
input bool   ShowArrowsSC             = true;  // Draw buy/sell arrows on chart
input bool   DebugSC                  = false; // Print detailed debug messages
input bool   ForceSC                  = false; // Bypass ALL filters (TEST ONLY!)

//===================================================================//
//  GLOBAL VARIABLES
//===================================================================//
int      hEMAFast_SC  = INVALID_HANDLE;
int      hEMASlow_SC  = INVALID_HANDLE;
int      hEMATrend_SC = INVALID_HANDLE;
int      hRSI_SC      = INVALID_HANDLE;
int      hATR_SC      = INVALID_HANDLE;

// Timing / bar tracking
datetime lastBarSC     = 0;
datetime lastTradeSC   = 0;
int      gmtOffsetSC   = 0;
double   pipFactorSC   = 10.0;

// Daily tracking
double   dayStartBal   = 0.0;
datetime dayDate       = 0;
int      dayTrades     = 0;
bool     dayLimitHit   = false;

// Statistics (persisted via GlobalVariables)
int      statTrades    = 0;
int      statWins      = 0;
int      statLosses    = 0;
int      statConsec    = 0;
double   statPnL       = 0.0;

// Partial TP tracking
struct ScPartial { ulong ticket; bool done; };
ScPartial partialSC[];

// Last signal display
string   sigDirSC      = "---";
double   sigPriceSC    = 0;
int      arrowIdSC     = 0;

// Panel state
bool     panHidSC      = false;
int      panXSC        = 20;
int      panYSC        = 30;
int      panWSC        = 280;
int      linHSC        = 13;

// Colors
color    C_BG    = C'15,15,30';
color    C_HDR   = C'30,30,60';
color    C_GOLD  = clrGold;
color    C_GRN   = clrLime;
color    C_RED   = clrRed;
color    C_TXT   = clrSilver;
color    C_BLU   = C'80,120,220';
color    C_BRD   = C'60,60,100';
color    C_WHT   = clrWhite;

//===================================================================//
//  ONINIT
//===================================================================//
int OnInit()
{
   // Timeframe guard — M1 or M5 only
   if(_Period != PERIOD_M1 && _Period != PERIOD_M5)
   {
      Alert(EA_SC+": Please use M1 or M5 timeframe!");
      return INIT_FAILED;
   }

   // PipFactor — 100 for 2-digit symbols (XAUUSD), 10 for 5-digit (EURUSD)
   if(_Digits == 2 || _Digits == 3)      pipFactorSC = 100.0;
   else if(_Digits == 4 || _Digits == 5) pipFactorSC = 10.0;
   else                                   pipFactorSC = 10.0;

   // GMT offset
   gmtOffsetSC = AutoGMT_SC ? (int)((TimeCurrent() - TimeGMT()) / 3600) : GMTOffsetSC;

   // Create indicator handles
   hEMAFast_SC  = iMA(_Symbol, _Period, EMAFast,  0, MODE_EMA, PRICE_CLOSE);
   hEMASlow_SC  = iMA(_Symbol, _Period, EMASlow,  0, MODE_EMA, PRICE_CLOSE);
   hEMATrend_SC = iMA(_Symbol, _Period, EMATrend, 0, MODE_EMA, PRICE_CLOSE);
   hRSI_SC      = iRSI(_Symbol, _Period, RSIPeriodSC, PRICE_CLOSE);
   hATR_SC      = iATR(_Symbol, _Period, ATRPeriodSC);

   if(hEMAFast_SC  == INVALID_HANDLE || hEMASlow_SC == INVALID_HANDLE ||
      hEMATrend_SC == INVALID_HANDLE || hRSI_SC     == INVALID_HANDLE ||
      hATR_SC      == INVALID_HANDLE)
   {
      Alert(EA_SC+": Failed to create indicator handles!");
      return INIT_FAILED;
   }

   // CTrade setup
   trade.SetExpertMagicNumber(MAGIC_SC);
   trade.SetDeviationInPoints(30);

   // Order filling — auto-detect what broker supports
   ENUM_ORDER_TYPE_FILLING filling = ORDER_FILLING_IOC;
   uint fillFlags = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fillFlags & SYMBOL_FILLING_FOK) != 0)       filling = ORDER_FILLING_FOK;
   else if((fillFlags & SYMBOL_FILLING_IOC) != 0)  filling = ORDER_FILLING_IOC;
   else                                              filling = ORDER_FILLING_RETURN;
   trade.SetTypeFilling(filling);

   // Load persisted stats from GlobalVariables
   string k = _Symbol + "_SC10_";
   if(GlobalVariableCheck(k+"T")) statTrades  = (int)GlobalVariableGet(k+"T");
   if(GlobalVariableCheck(k+"W")) statWins    = (int)GlobalVariableGet(k+"W");
   if(GlobalVariableCheck(k+"L")) statLosses  = (int)GlobalVariableGet(k+"L");
   if(GlobalVariableCheck(k+"C")) statConsec  = (int)GlobalVariableGet(k+"C");
   if(GlobalVariableCheck(k+"P")) statPnL     = GlobalVariableGet(k+"P");

   // Daily tracking init
   dayDate     = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);

   UpdateDisplaySC();

   Print("=== ", EA_SC, " STARTED === Symbol:", _Symbol, " TF:", EnumToString(_Period));
   Print("EMA: F", EMAFast, "/S", EMASlow, "/T", EMATrend,
         " RSI:", RSIPeriodSC, " ATR:", ATRPeriodSC, " PipFactor:", pipFactorSC);
   Print("Signal:", SC_SignalModeStr(SignalMode), " Risk:", RiskPctSC, "% MaxLot:", MaxLotSC);

   return INIT_SUCCEEDED;
}

//===================================================================//
//  ONDEINIT
//===================================================================//
void OnDeinit(const int reason)
{
   SaveStatsSC();

   if(hEMAFast_SC  != INVALID_HANDLE) IndicatorRelease(hEMAFast_SC);
   if(hEMASlow_SC  != INVALID_HANDLE) IndicatorRelease(hEMASlow_SC);
   if(hEMATrend_SC != INVALID_HANDLE) IndicatorRelease(hEMATrend_SC);
   if(hRSI_SC      != INVALID_HANDLE) IndicatorRelease(hRSI_SC);
   if(hATR_SC      != INVALID_HANDLE) IndicatorRelease(hATR_SC);

   ObjectsDeleteAll(0, PFX_SC);
   Print(EA_SC, ": Stopped. Reason=", reason,
         " Trades=", statTrades, " W=", statWins, " L=", statLosses,
         " PnL=", DoubleToString(statPnL, 2));
}

//===================================================================//
//  ONTICK
//===================================================================//
void OnTick()
{
   // Daily reset check
   CheckDailyResetSC();

   // Friday close
   if(CloseFridaySC && IsFridayCutoffSC())
   { CloseAllSC("FridayClose"); UpdateDisplaySC(); return; }

   // Manage open positions every tick (partial TP, trailing stop)
   ManagePosSC();

   // Signals only fire on new bar (bar-close confirmed, avoids repaint)
   if(!IsNewBarSC()) { UpdateDisplaySC(); return; }

   // ── Entry check ──────────────────────────────────────────────
   string blockReason = "";
   if(!CanTradeSC(blockReason))
   {
      if(DebugSC) Print("BLOCK: ", blockReason);
      UpdateDisplaySC();
      return;
   }

   // Copy indicator buffers (series order: [0]=current bar, [1]=last closed, [2]=2 bars ago)
   double fa[3], sl_[3], tr[3], rs[3], at[3];
   ArraySetAsSeries(fa,  true); ArraySetAsSeries(sl_, true);
   ArraySetAsSeries(tr,  true); ArraySetAsSeries(rs,  true);
   ArraySetAsSeries(at,  true);

   if(CopyBuffer(hEMAFast_SC,  0, 0, 3, fa)  < 3) return;
   if(CopyBuffer(hEMASlow_SC,  0, 0, 3, sl_) < 3) return;
   if(CopyBuffer(hEMATrend_SC, 0, 0, 3, tr)  < 3) return;
   if(CopyBuffer(hRSI_SC,      0, 0, 3, rs)  < 3) return;
   if(CopyBuffer(hATR_SC,      0, 0, 3, at)  < 3) return;

   // Spread check
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(MaxSpreadSC > 0 && spread > MaxSpreadSC)
   { if(DebugSC) Print("SKIP: Spread=", spread); UpdateDisplaySC(); return; }

   // ATR volatility check (skip flat market)
   double atrVal   = at[1];
   double atrPips  = atrVal / _Point / pipFactorSC;
   if(atrPips < MinATRPipsSC)
   { if(DebugSC) Print("SKIP: ATR too low=", atrPips, " pips"); UpdateDisplaySC(); return; }

   // ── Generate signals ─────────────────────────────────────────
   bool buyOK = false, sellOK = false;

   if(SignalMode == SC_SIG_EMA_CROSS)
   {
      // Crossover on bar[1] vs bar[2] (last two closed bars — no repaint)
      bool xUp   = (fa[1] > sl_[1]) && (fa[2] <= sl_[2]);
      bool xDown = (fa[1] < sl_[1]) && (fa[2] >= sl_[2]);
      bool tUp   = !UseTrendFilterSC || (fa[1] > tr[1]);
      bool tDown = !UseTrendFilterSC || (fa[1] < tr[1]);
      bool rBuy  = !UseRSIFilterSC   || (rs[1] >= RSIBuyMin  && rs[1] <= RSIBuyMax);
      bool rSell = !UseRSIFilterSC   || (rs[1] >= RSISellMin && rs[1] <= RSISellMax);
      buyOK  = xUp   && tUp   && rBuy;
      sellOK = xDown && tDown && rSell;
   }
   else if(SignalMode == SC_SIG_EMA_SLOPE)
   {
      // Both EMAs sloping same direction on last closed bar — higher frequency
      bool sUp   = (fa[1] > fa[2]) && (sl_[1] > sl_[2]);
      bool sDown = (fa[1] < fa[2]) && (sl_[1] < sl_[2]);
      bool tUp   = !UseTrendFilterSC || (fa[1] > tr[1]);
      bool tDown = !UseTrendFilterSC || (fa[1] < tr[1]);
      bool rBuy  = !UseRSIFilterSC   || (rs[1] >= RSIBuyMin  && rs[1] <= RSIBuyMax);
      bool rSell = !UseRSIFilterSC   || (rs[1] >= RSISellMin && rs[1] <= RSISellMax);
      buyOK  = sUp   && tUp   && rBuy;
      sellOK = sDown && tDown && rSell;
   }
   else // SC_SIG_PRICE_ACTION — bullish/bearish engulfing
   {
      MqlRates rates[3];
      ArraySetAsSeries(rates, true);
      if(CopyRates(_Symbol, _Period, 0, 3, rates) < 3) { UpdateDisplaySC(); return; }

      double c1O = rates[1].open, c1C = rates[1].close;
      double c2O = rates[2].open, c2C = rates[2].close;

      bool bullEng = (c1C > c1O) && (c2C < c2O) && (c1C > c2O) && (c1O < c2C); // full engulf
      bool bearEng = (c1C < c1O) && (c2C > c2O) && (c1C < c2O) && (c1O > c2C);
      bool tUp   = !UseTrendFilterSC || (fa[1] > tr[1]);
      bool tDown = !UseTrendFilterSC || (fa[1] < tr[1]);
      bool rBuy  = !UseRSIFilterSC   || (rs[1] >= RSIBuyMin  && rs[1] <= RSIBuyMax);
      bool rSell = !UseRSIFilterSC   || (rs[1] >= RSISellMin && rs[1] <= RSISellMax);
      buyOK  = bullEng && tUp   && rBuy;
      sellOK = bearEng && tDown && rSell;
   }

   // Force trades override (TEST ONLY)
   if(ForceSC) { buyOK = true; sellOK = false; }

   // ── Execute entry ─────────────────────────────────────────────
   if(buyOK || sellOK)
   {
      bool isBuy = buyOK;
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double entry = isBuy ? ask : bid;

      double sl = isBuy ? entry - atrVal * SLMultiATR
                        : entry + atrVal * SLMultiATR;
      double tp = isBuy ? entry + atrVal * TPMultiATR
                        : entry - atrVal * TPMultiATR;

      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);

      // SL range check
      double slPips = MathAbs(entry - sl) / _Point / pipFactorSC;
      if(slPips < MinSLPipsSC)
      { if(DebugSC) Print("SKIP: SL too small=", slPips, "pips"); UpdateDisplaySC(); return; }
      if(MaxSLPipsSC > 0 && slPips > MaxSLPipsSC)
      { if(DebugSC) Print("SKIP: SL too wide=",  slPips, "pips"); UpdateDisplaySC(); return; }

      // Broker stops level check
      double stopsLev = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      if(MathAbs(entry - sl) < stopsLev + _Point)
      { if(DebugSC) Print("SKIP: SL inside stops level"); UpdateDisplaySC(); return; }

      double lot = CalcLotSC(MathAbs(entry - sl));
      if(lot <= 0) { UpdateDisplaySC(); return; }

      ExecuteTradeSC(isBuy, sl, tp, lot, atrVal);
   }

   UpdateDisplaySC();
}

//===================================================================//
//  MANAGE OPEN POSITIONS — called every tick
//===================================================================//
void ManagePosSC()
{
   double at[2];
   ArraySetAsSeries(at, true);
   bool atrOK = (CopyBuffer(hATR_SC, 0, 0, 2, at) >= 2);

   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong tkt = PositionGetTicket(i);
      if(!PositionSelectByTicket(tkt)) continue;
      if(PositionGetInteger(POSITION_MAGIC)  != MAGIC_SC) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)  continue;

      double pOpen = PositionGetDouble(POSITION_PRICE_OPEN);
      double pSL   = PositionGetDouble(POSITION_SL);
      double pTP   = PositionGetDouble(POSITION_TP);
      double pNow  = PositionGetDouble(POSITION_PRICE_CURRENT);
      double pLots = PositionGetDouble(POSITION_VOLUME);
      bool   isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

      // ── Partial TP ───────────────────────────────────────────────
      if(UsePartialSC)
      {
         bool pdone = false;
         for(int p = 0; p < ArraySize(partialSC); p++)
            if(partialSC[p].ticket == tkt) { pdone = partialSC[p].done; break; }

         if(!pdone)
         {
            double slDist   = MathAbs(pOpen - pSL);
            double partLvl  = isBuy ? pOpen + slDist * PartialRRSC
                                    : pOpen - slDist * PartialRRSC;
            bool   hit      = isBuy ? (pNow >= partLvl) : (pNow <= partLvl);

            if(hit)
            {
               double minVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               double stepVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
               double closeLots = MathFloor(pLots * PartialPctSC / 100.0 / stepVol) * stepVol;
               closeLots = MathMax(minVol, closeLots);

               if(closeLots < pLots)
               {
                  PartialCloseSC(tkt, closeLots);

                  // Move SL to breakeven
                  double newSL = NormalizeDouble(pOpen, _Digits);
                  double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point + _Point;
                  bool slOK = isBuy ? (newSL < pNow - minDist) : (newSL > pNow + minDist);
                  if(slOK && MathAbs(newSL - pSL) > _Point)
                     trade.PositionModify(tkt, newSL, pTP);

                  // Mark done
                  bool found = false;
                  for(int p = 0; p < ArraySize(partialSC); p++)
                     if(partialSC[p].ticket == tkt) { partialSC[p].done = true; found = true; break; }
                  if(!found)
                  {
                     int sz = ArraySize(partialSC);
                     ArrayResize(partialSC, sz+1);
                     partialSC[sz].ticket = tkt;
                     partialSC[sz].done   = true;
                  }
                  Print("PARTIAL TP: Closed ", closeLots, " lots @ ", pNow, " | SL→BE");
               }
            }
         }
      }

      // ── Trailing Stop ────────────────────────────────────────────
      if(TrailStopSC && atrOK)
      {
         double trail   = at[0] * TrailATRMulti;
         double newSL   = NormalizeDouble(isBuy ? pNow - trail : pNow + trail, _Digits);
         bool   better  = isBuy ? (newSL > pSL + _Point) : (newSL < pSL - _Point);
         if(better)
         {
            double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
            bool   valid   = isBuy ? (newSL < pNow - minDist) : (newSL > pNow + minDist);
            if(valid) trade.PositionModify(tkt, newSL, pTP);
         }
      }
   }
}

//===================================================================//
//  EXECUTE TRADE
//===================================================================//
void ExecuteTradeSC(bool isBuy, double sl, double tp, double lot, double atrVal)
{
   string comment = EA_SC + (isBuy ? " BUY" : " SELL");
   bool   ok      = isBuy ? trade.Buy (lot, _Symbol, 0, sl, tp, comment)
                          : trade.Sell(lot, _Symbol, 0, sl, tp, comment);

   if(ok)
   {
      ulong  tkt   = trade.ResultOrder();
      double fill  = trade.ResultPrice();
      double slPip = MathAbs(fill - sl) / _Point / pipFactorSC;

      Print(">>> TRADE: ", isBuy?"BUY":"SELL",
            " Lot=", lot, " Entry=", fill,
            " SL=", sl, " (", DoubleToString(slPip,1), "pips)",
            " TP=", tp, " ATR=", DoubleToString(atrVal/_Point/pipFactorSC,1), "pips");

      // Update counters
      dayTrades++;
      statTrades++;
      lastTradeSC  = TimeCurrent();
      sigDirSC     = isBuy ? "BUY" : "SELL";
      sigPriceSC   = fill;

      // Register partial TP tracking slot
      int sz = ArraySize(partialSC);
      ArrayResize(partialSC, sz+1);
      partialSC[sz].ticket = tkt;
      partialSC[sz].done   = false;

      // Draw arrow on chart
      if(ShowArrowsSC)
      {
         string aName = PFX_SC+"Arr"+IntegerToString(arrowIdSC++);
         if(ObjectCreate(0, aName, OBJ_ARROW, 0, TimeCurrent(), fill))
         {
            ObjectSetInteger(0, aName, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
            ObjectSetInteger(0, aName, OBJPROP_COLOR,     isBuy ? clrDodgerBlue : clrOrangeRed);
            ObjectSetInteger(0, aName, OBJPROP_WIDTH,     2);
            ObjectSetInteger(0, aName, OBJPROP_ANCHOR,    isBuy ? ANCHOR_BOTTOM : ANCHOR_TOP);
         }
      }

      // Screenshot
      if(ScreenshotSC)
      {
         string fn = _Symbol+"_Scalper_"+(isBuy?"BUY":"SELL")+"_"
                     +TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES)+".png";
         StringReplace(fn, ":", "-"); StringReplace(fn, " ", "_");
         ChartScreenShot(0, fn, 1280, 720);
      }

      // CSV log
      if(CSVLogSC) WriteCSVEntrySC(tkt, isBuy, fill, sl, tp, lot, atrVal);
   }
   else
   {
      Print("TRADE FAILED: Code=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
}

//===================================================================//
//  PARTIAL CLOSE
//===================================================================//
void PartialCloseSC(ulong tkt, double lots)
{
   if(!PositionSelectByTicket(tkt)) return;
   ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.position  = tkt;
   req.symbol    = _Symbol;
   req.volume    = lots;
   req.type      = (pt == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price     = (pt == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   req.deviation = 30;
   req.magic     = MAGIC_SC;
   req.type_filling = (ENUM_ORDER_TYPE_FILLING)trade.RequestTypeFilling();

   if(!OrderSend(req, res))
      Print("PartialClose FAILED: code=", res.retcode, " ticket=", tkt);
}

//===================================================================//
//  LOT SIZE CALCULATION
//===================================================================//
double CalcLotSC(double slDist)
{
   double lot;

   if(FixedLotSC > 0.0 || RiskModeSC == SC_RISK_FIXED_LOT)
   {
      lot = (FixedLotSC > 0) ? FixedLotSC : 0.01;
   }
   else
   {
      double base = (RiskModeSC == SC_RISK_DYNAMIC_EQ)
                    ? AccountInfoDouble(ACCOUNT_EQUITY)
                    : AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmt = base * RiskPctSC / 100.0;

      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize <= 0 || tickValue <= 0) { Print("ERROR: invalid tick data"); return 0.01; }

      lot = riskAmt / (slDist / tickSize * tickValue);
   }

   // Apply ceiling
   if(MaxLotSC > 0) lot = MathMin(lot, MaxLotSC);
   return NormLotSC(lot);
}

double NormLotSC(double lot)
{
   double minL  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(MathMax(minL, MathMin(maxL, lot)) / step) * step;
   return NormalizeDouble(lot, 2);
}

//===================================================================//
//  CAN TRADE CHECK
//===================================================================//
bool CanTradeSC(string &reason)
{
   if(ForceSC) return true;

   // Daily loss limit
   if(dayLimitHit) { reason = "DailyLossLimit"; return false; }
   double curBal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double dayLoss = dayStartBal - curBal;
   if(dayLoss > 0 && (dayLoss / dayStartBal * 100.0) >= MaxDailyLossPctSC)
   { dayLimitHit = true; reason = "DailyLossExceeded"; return false; }

   // Max trades per day
   if(dayTrades >= MaxTradesPerDaySC) { reason = "MaxTradesPerDay"; return false; }

   // Consecutive losses
   if(statConsec >= MaxConsecLossesSC) { reason = "MaxConsecLosses"; return false; }

   // One position at a time
   if(OneAtATimeSC && CountPosSC() > 0) { reason = "PosOpen"; return false; }

   // Session filter
   if(!AllHoursSC && !IsSessionSC()) { reason = "OutsideSession"; return false; }

   // Cooldown bars
   if(CooldownBarsSC > 0 && lastTradeSC > 0)
   {
      int coolSec = CooldownBarsSC * PeriodSeconds(_Period);
      if((int)(TimeCurrent() - lastTradeSC) < coolSec)
      { reason = "Cooldown"; return false; }
   }

   return true;
}

//===================================================================//
//  COUNT EA POSITIONS
//===================================================================//
int CountPosSC()
{
   int n = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong tkt = PositionGetTicket(i);
      if(!PositionSelectByTicket(tkt)) continue;
      if(PositionGetInteger(POSITION_MAGIC) == MAGIC_SC &&
         PositionGetString(POSITION_SYMBOL) == _Symbol) n++;
   }
   return n;
}

//===================================================================//
//  NEW BAR CHECK
//===================================================================//
bool IsNewBarSC()
{
   datetime t = iTime(_Symbol, _Period, 0);
   if(t == lastBarSC) return false;
   lastBarSC = t;
   return true;
}

//===================================================================//
//  DAILY RESET
//===================================================================//
void CheckDailyResetSC()
{
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(today > dayDate)
   {
      dayDate     = today;
      dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
      dayTrades   = 0;
      dayLimitHit = false;
      statConsec  = 0;
      Print(EA_SC, ": Daily reset. StartBal=", dayStartBal);
   }
}

//===================================================================//
//  SESSION CHECK
//===================================================================//
bool IsSessionSC()
{
   int gh = (int)(((TimeCurrent() / 3600) + gmtOffsetSC) % 24);
   if(gh < 0) gh += 24;

   bool sydney  = SydneySC  && (gh >= 22 || gh < 2);
   bool tokyo   = TokyoSC   && (gh >= 0  && gh < 4);
   bool london  = LondonSC  && (gh >= 8  && gh < 12);
   bool ny      = NewYorkSC && (gh >= 13 && gh < 17);
   bool overlap = OverlapSC && (gh >= 13 && gh < 16);

   return sydney || tokyo || london || ny || overlap;
}

//===================================================================//
//  FRIDAY CUTOFF
//===================================================================//
bool IsFridayCutoffSC()
{
   MqlDateTime tm;
   TimeCurrent(tm);
   if(tm.day_of_week != 5) return false;
   int gh = (int)(((TimeCurrent() / 3600) + gmtOffsetSC) % 24);
   return gh >= FridayHourSC;
}

void CloseAllSC(string reason)
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong tkt = PositionGetTicket(i);
      if(!PositionSelectByTicket(tkt)) continue;
      if(PositionGetInteger(POSITION_MAGIC) == MAGIC_SC &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         trade.PositionClose(tkt);
   }
   Print(EA_SC, ": CloseAll — reason=", reason);
}

//===================================================================//
//  TRADE TRANSACTION — track wins / losses
//===================================================================//
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dk = trans.deal;
   if(!HistoryDealSelect(dk)) return;
   if(HistoryDealGetInteger(dk, DEAL_MAGIC)  != MAGIC_SC)     return;
   if(HistoryDealGetInteger(dk, DEAL_ENTRY)  != DEAL_ENTRY_OUT) return;
   if(HistoryDealGetString (dk, DEAL_SYMBOL) != _Symbol)      return;

   double profit = HistoryDealGetDouble(dk, DEAL_PROFIT)
                 + HistoryDealGetDouble(dk, DEAL_SWAP)
                 + HistoryDealGetDouble(dk, DEAL_COMMISSION);

   statPnL += profit;

   if(profit >= 0) { statWins++;   statConsec = 0; }
   else            { statLosses++; statConsec++;    }

   SaveStatsSC();

   // Close screenshot
   if(ScreenshotSC)
   {
      string fn = _Symbol+"_Scalper_CLOSE_"
                  +TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES)
                  +"_"+(profit>=0?"WIN":"LOSS")+".png";
      StringReplace(fn,":","-"); StringReplace(fn," ","_");
      ChartScreenShot(0, fn, 1280, 720);
   }
}

//===================================================================//
//  SAVE STATS TO GLOBALVARIABLES
//===================================================================//
void SaveStatsSC()
{
   string k = _Symbol + "_SC10_";
   GlobalVariableSet(k+"T", statTrades);
   GlobalVariableSet(k+"W", statWins);
   GlobalVariableSet(k+"L", statLosses);
   GlobalVariableSet(k+"C", statConsec);
   GlobalVariableSet(k+"P", statPnL);
}

//===================================================================//
//  CSV LOG
//===================================================================//
void WriteCSVEntrySC(ulong tkt, bool isBuy, double entry, double sl, double tp,
                     double lot, double atrVal)
{
   string fn = _Symbol + "_SMC_Scalper_V1.0.csv";
   int    fh = FileOpen(fn, FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
   if(fh == INVALID_HANDLE) return;
   FileSeek(fh, 0, SEEK_END);
   FileWrite(fh,
      IntegerToString(tkt),
      TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS),
      isBuy ? "BUY" : "SELL",
      DoubleToString(entry, _Digits),
      DoubleToString(sl,    _Digits),
      DoubleToString(tp,    _Digits),
      DoubleToString(lot,   2),
      DoubleToString(atrVal / _Point / pipFactorSC, 1),
      IntegerToString(dayTrades),
      EnumToString(_Period)
   );
   FileClose(fh);
}

//===================================================================//
//  PANEL HELPER FUNCTIONS
//===================================================================//
void ScRect(string nm, int x, int y, int w, int h, color bg, color brd)
{
   string n = PFX_SC + nm;
   if(ObjectFind(0,n) < 0) ObjectCreate(0,n, OBJ_RECTANGLE_LABEL, 0,0,0);
   ObjectSetInteger(0,n, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0,n, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0,n, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0,n, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0,n, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0,n, OBJPROP_COLOR,      brd);
   ObjectSetInteger(0,n, OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,n, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n, OBJPROP_BACK,       false);
   ObjectSetInteger(0,n, OBJPROP_SELECTABLE, false);
}

void ScLbl(string nm, int x, int y, string txt, color clr, int sz=8)
{
   string n = PFX_SC + nm;
   if(ObjectFind(0,n) < 0) ObjectCreate(0,n, OBJ_LABEL, 0,0,0);
   ObjectSetInteger(0,n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0,n, OBJPROP_YDISTANCE, y);
   ObjectSetString (0,n, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0,n, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0,n, OBJPROP_FONTSIZE,  sz);
   ObjectSetString (0,n, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0,n, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n, OBJPROP_BACK,      false);
   ObjectSetInteger(0,n, OBJPROP_SELECTABLE,false);
}

void ScLblC(string nm, int y, string txt, color clr, int sz=8)
{
   string n  = PFX_SC + nm;
   int    cx = panXSC + panWSC / 2;
   if(ObjectFind(0,n) < 0) ObjectCreate(0,n, OBJ_LABEL, 0,0,0);
   ObjectSetInteger(0,n, OBJPROP_XDISTANCE, cx);
   ObjectSetInteger(0,n, OBJPROP_YDISTANCE, y);
   ObjectSetString (0,n, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0,n, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0,n, OBJPROP_FONTSIZE,  sz);
   ObjectSetString (0,n, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0,n, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n, OBJPROP_ANCHOR,    ANCHOR_UPPER);
   ObjectSetInteger(0,n, OBJPROP_BACK,      false);
   ObjectSetInteger(0,n, OBJPROP_SELECTABLE,false);
}

//===================================================================//
//  UPDATE DISPLAY
//===================================================================//
void UpdateDisplaySC()
{
   int x    = panXSC;
   int yb   = panYSC;
   int w    = panWSC;
   int lh   = linHSC;
   int hdrH = 42;
   int rt   = 2;
   int px   = x + 6;
   int vx   = x + 128;
   int y    = yb + hdrH + 2;

   // BG — always first (lowest z-order)
   ScRect("BG",    x, yb, w, panHidSC ? hdrH : 500, C_BG, C_BRD);
   ScRect("HdrBG", x, yb, w, hdrH, C_HDR, C_BRD);
   ScLblC("Title",  yb+5,  EA_SC,                      C_GOLD, 11);
   ScLblC("Author", yb+24, "Created by: RATTANA CHHORM",C_WHT,   8);
   ScLbl ("Drag",   px,    yb+4, "[drag]", C'50,50,70', 7);
   ObjectSetInteger(0, PFX_SC+"Drag",   OBJPROP_SELECTABLE, true);
   ScLbl ("Tog",    x+w-52,yb+4, panHidSC?"[show]":"[hide]", C_BLU, 8);
   ObjectSetInteger(0, PFX_SC+"Tog",    OBJPROP_SELECTABLE, true);

   if(panHidSC) { ChartRedraw(0); return; }

   // ── Body rows ─────────────────────────────────────────────────
   int row = 0;
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayPL = eq - dayStartBal;

   ScLbl("BaL",px,y+row*lh+rt,"Balance  :",C_TXT);
   ScLbl("BaV",vx,y+row*lh+rt,DoubleToString(bal,2)+" "+AccountInfoString(ACCOUNT_CURRENCY),C_GOLD); row++;

   ScLbl("EqL",px,y+row*lh+rt,"Equity   :",C_TXT);
   ScLbl("EqV",vx,y+row*lh+rt,DoubleToString(eq,2), eq>=bal?C_GRN:C_RED); row++;

   ScLbl("DpL",px,y+row*lh+rt,"Day P/L  :",C_TXT);
   ScLbl("DpV",vx,y+row*lh+rt,(dayPL>=0?"+":"")+DoubleToString(dayPL,2), dayPL>=0?C_GRN:C_RED); row++;

   // Session
   bool sess = AllHoursSC || IsSessionSC();
   ScLbl("SeL",px,y+row*lh+rt,"Session  :",C_TXT);
   ScLbl("SeV",vx,y+row*lh+rt, sess?"ACTIVE":"CLOSED", sess?C_GRN:C_RED); row++;

   // Spread
   double sprd = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   color  sprdC = (MaxSpreadSC > 0 && sprd > MaxSpreadSC) ? C_RED : C_GRN;
   ScLbl("SpL",px,y+row*lh+rt,"Spread   :",C_TXT);
   ScLbl("SpV",vx,y+row*lh+rt,DoubleToString(sprd,0)+" pts", sprdC); row++;

   // ATR
   double at2[2]; ArraySetAsSeries(at2,true);
   double atrPips = 0;
   if(CopyBuffer(hATR_SC,0,0,2,at2)>=2) atrPips = at2[1]/_Point/pipFactorSC;
   color atrC = atrPips >= MinATRPipsSC ? C_GRN : C_RED;
   ScLbl("AtL",px,y+row*lh+rt,"ATR pips :",C_TXT);
   ScLbl("AtV",vx,y+row*lh+rt,DoubleToString(atrPips,1)+" pips", atrC); row++;

   // EMA direction
   double fa2[2], sl2[2]; ArraySetAsSeries(fa2,true); ArraySetAsSeries(sl2,true);
   string emaDir = "---"; color emaDC = C_TXT;
   if(CopyBuffer(hEMAFast_SC,0,0,2,fa2)>=2 && CopyBuffer(hEMASlow_SC,0,0,2,sl2)>=2)
   { emaDir = fa2[0]>sl2[0]?"BULL":"BEAR"; emaDC = fa2[0]>sl2[0]?C_GRN:C_RED; }
   ScLbl("EmL",px,y+row*lh+rt,"EMA Dir  :",C_TXT);
   ScLbl("EmV",vx,y+row*lh+rt, emaDir, emaDC); row++;

   // RSI
   double rs2[2]; ArraySetAsSeries(rs2,true);
   double rsiV = 50;
   if(CopyBuffer(hRSI_SC,0,0,2,rs2)>=2) rsiV = rs2[0];
   color rsiC = rsiV>55?C_GRN:rsiV<45?C_RED:C_GOLD;
   ScLbl("RsL",px,y+row*lh+rt,"RSI      :",C_TXT);
   ScLbl("RsV",vx,y+row*lh+rt,DoubleToString(rsiV,1), rsiC); row++;

   // Last signal
   color sigC = (sigDirSC=="BUY")?C_GRN:(sigDirSC=="SELL"?C_RED:C_TXT);
   ScLbl("SgL",px,y+row*lh+rt,"Signal   :",C_TXT);
   ScLbl("SgV",vx,y+row*lh+rt, sigDirSC, sigC); row++;

   // Open positions
   int posN = CountPosSC();
   ScLbl("PoL",px,y+row*lh+rt,"Positions:",C_TXT);
   ScLbl("PoV",vx,y+row*lh+rt,IntegerToString(posN), posN>0?C_GOLD:C_TXT); row++;

   // Trades today
   color tdC = dayTrades >= MaxTradesPerDaySC ? C_RED : C_GRN;
   ScLbl("TdL",px,y+row*lh+rt,"Trades/D :",C_TXT);
   ScLbl("TdV",vx,y+row*lh+rt,IntegerToString(dayTrades)+"/"+IntegerToString(MaxTradesPerDaySC),tdC); row++;

   // Win rate
   double wr = (statTrades>0) ? (double)statWins/statTrades*100.0 : 0.0;
   color  wrC = wr>=55?C_GRN:wr>=45?C_GOLD:C_RED;
   ScLbl("WrL",px,y+row*lh+rt,"Win Rate :",C_TXT);
   ScLbl("WrV",vx,y+row*lh+rt,DoubleToString(wr,1)+"% ("+IntegerToString(statTrades)+"T)",wrC); row++;

   // Consec losses
   color csC = statConsec >= MaxConsecLossesSC ? C_RED : statConsec>2 ? C_GOLD : C_GRN;
   ScLbl("CsL",px,y+row*lh+rt,"Con.Loss :",C_TXT);
   ScLbl("CsV",vx,y+row*lh+rt,IntegerToString(statConsec)+"/"+IntegerToString(MaxConsecLossesSC),csC); row++;

   // Total P&L
   ScLbl("TpL",px,y+row*lh+rt,"Total P&L:",C_TXT);
   ScLbl("TpV",vx,y+row*lh+rt,(statPnL>=0?"+":"")+DoubleToString(statPnL,2),statPnL>=0?C_GRN:C_RED); row++;

   // Settings summary
   ScLbl("RkL",px,y+row*lh+rt,"Risk     :",C_TXT);
   ScLbl("RkV",vx,y+row*lh+rt,SC_RiskModeStr(RiskModeSC)+" "+DoubleToString(RiskPctSC,2)+"%",C_GOLD); row++;

   ScLbl("SmL",px,y+row*lh+rt,"Signal   :",C_TXT);
   ScLbl("SmV",vx,y+row*lh+rt,SC_SignalModeStr(SignalMode),C_GOLD); row++;

   ScLbl("FcL",px,y+row*lh+rt,"Force    :",C_TXT);
   ScLbl("FcV",vx,y+row*lh+rt, ForceSC?"ON (TEST)":"OFF", ForceSC?C_RED:C_GRN); row++;

   // Resize BG to actual content
   ObjectSetInteger(0, PFX_SC+"BG", OBJPROP_YSIZE, hdrH + 2 + row*lh + 8);
   ChartRedraw(0);
}

//===================================================================//
//  CHART EVENT — panel drag and hide/show
//===================================================================//
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_DRAG && sparam == PFX_SC+"Drag")
   {
      panXSC = (int)ObjectGetInteger(0, PFX_SC+"Drag", OBJPROP_XDISTANCE);
      panYSC = (int)ObjectGetInteger(0, PFX_SC+"Drag", OBJPROP_YDISTANCE);
      UpdateDisplaySC();
   }
   else if(id == CHARTEVENT_OBJECT_CLICK && sparam == PFX_SC+"Tog")
   {
      panHidSC = !panHidSC;
      UpdateDisplaySC();
   }
}

//===================================================================//
//  STRING HELPERS
//===================================================================//
string SC_RiskModeStr(ENUM_RISK_MODE_SC m)
{
   if(m == SC_RISK_FIXED_PCT)  return "FIXED_PCT";
   if(m == SC_RISK_FIXED_LOT)  return "FIXED_LOT";
   if(m == SC_RISK_DYNAMIC_EQ) return "DYNAMIC_EQ";
   return "UNKNOWN";
}

string SC_SignalModeStr(ENUM_SIGNAL_MODE_SC m)
{
   if(m == SC_SIG_EMA_CROSS)    return "EMA_CROSS";
   if(m == SC_SIG_EMA_SLOPE)    return "EMA_SLOPE";
   if(m == SC_SIG_PRICE_ACTION) return "PRICE_ACTION";
   return "UNKNOWN";
}
//+------------------------------------------------------------------+
