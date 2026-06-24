//+------------------------------------------------------------------+
//|            LONDON MOMENTUM SCALPER V1.0.mq5                      |
//|            EMA9/21 Cross  +  M15 HTF EMA50 Filter                |
//|            Session : London  08:00 – 12:00 GMT                   |
//|            Author  : RATTANA CHHORM                              |
//+------------------------------------------------------------------+
#property copyright "RATTANA CHHORM"
#property version   "1.0"
#property strict

#include <Trade\Trade.mqh>

//===================================================================//
//  CONSTANTS & ENUMS
//===================================================================//
enum ENUM_RISK_LMS { LMS_RISK_PCT=0, LMS_RISK_FIXED_LOT=1 };

const int    MAGIC_LMS  = 111222;
const string EA_LMS     = "LONDON MOMENTUM V1.0";
const string CSV_LMS    = "XAUUSD_LMS_V1.0_CapCom.csv";

CTrade trade;

//===================================================================//
//  INPUTS
//===================================================================//

//--- [P1] EMA SIGNAL
input group "========== [P1] EMA SIGNAL =========="
input int    EMAFastPeriod  = 9;     // Fast EMA period (signal line)
input int    EMASlowPeriod  = 21;    // Slow EMA period (trend line)
input bool   CrossModeOnly  = true;  // true=fire only on cross bar  false=fire while fast>slow

//--- [P2] HTF FILTER
input group "========== [P2] HTF FILTER =========="
input bool            UseHTFFilter  = true;        // Enable HTF EMA trend filter
input ENUM_TIMEFRAMES HTFPeriod     = PERIOD_M15;  // HTF timeframe
input int             HTFEMAPeriod  = 50;          // HTF EMA period

//--- [P3] STOP LOSS / TAKE PROFIT
input group "========== [P3] STOP LOSS / TAKE PROFIT =========="
input double SLMultiATR = 0.8;   // SL = ATR × multiplier
input double TPMultiATR = 1.6;   // TP = ATR × multiplier

//--- [P4] PARTIAL TAKE PROFIT
input group "========== [P4] PARTIAL TAKE PROFIT =========="
input bool   UsePartialLMS  = true;  // Enable partial close at first target
input double PartialPctLMS  = 50.0;  // % of position to close at partial TP
input double PartialRR_LMS  = 1.0;   // R:R ratio to trigger partial close

//--- [P5] BREAKEVEN
input group "========== [P5] BREAKEVEN =========="
input bool   EnableBE     = true;  // Move SL to entry after partial TP
input double BreakevenRR  = 1.0;   // R:R ratio to trigger breakeven

//--- [P6] TRAILING STOP
input group "========== [P6] TRAILING STOP =========="
input bool   UseTrailLMS     = false; // Enable ATR trailing stop
input double TrailATRMulti   = 0.5;  // Trail distance = ATR × multiplier

//--- [P7] RISK MANAGEMENT
input group "========== [P7] RISK MANAGEMENT =========="
input ENUM_RISK_LMS RiskModeLMS      = LMS_RISK_PCT; // Risk mode
input double        RiskPctLMS       = 0.5;          // % balance risk per trade
input double        FixedLotLMS      = 0.01;         // Fixed lot size (LMS_RISK_FIXED_LOT)
input double        MaxLotLMS        = 0.10;         // Max lot ceiling
input double        MaxDailyLossPct  = 10.0;         // Max daily loss %
input int           MaxTradesPerDay  = 30;           // Max trades per day
input int           MaxConsecLosses  = 5;            // Pause after N consecutive losses

//--- [P8] TRADE FILTERS
input group "========== [P8] TRADE FILTERS =========="
input int    ATRPeriodLMS  = 14;   // ATR period
input double MinATRPips    = 1.5;  // Minimum ATR in pips to allow entry
input int    MaxSpreadLMS  = 50;   // Maximum spread in points
input double MaxSLPips     = 20.0; // Maximum SL in pips
input double MinSLPips     = 2.0;  // Minimum SL in pips
input int    CooldownBars  = 2;    // Bars to wait after a trade fires

//--- [P9] SESSION  (GMT TIME — AutoGMT must stay false for Capital.com)
input group "========== [P9] SESSION (GMT TIME) =========="
input bool   AutoGMT_LMS    = false;  // Auto-detect GMT offset  **keep false**
input int    GMTOffset_LMS  = 0;      // Manual GMT offset (broker server – GMT)
input bool   LondonLMS      = true;   // London session  08:00 – 12:00 GMT
input bool   AllHoursLMS    = false;  // Override: trade all hours

//--- [P10] POSITION MANAGEMENT
input group "========== [P10] POSITION MANAGEMENT =========="
input int    MaxOpenLMS    = 1;     // Max simultaneous open positions
input bool   CloseFriday   = true;  // Close all positions before weekend
input int    FridayHour    = 14;    // Friday close hour (GMT)

//--- [P11] LOGGING
input group "========== [P11] LOGGING =========="
input bool   CSVLogLMS    = true;  // Write trade log CSV (Common\Files folder)
input bool   ShowArrowsLMS = true; // Draw entry arrows on chart

//--- [P12] DEBUG
input group "========== [P12] DEBUG =========="
input bool   DebugLMS = false; // Print debug messages to Experts log

//===================================================================//
//  GLOBAL VARIABLES
//===================================================================//
int    hFast  = INVALID_HANDLE;  // EMA fast handle
int    hSlow  = INVALID_HANDLE;  // EMA slow handle
int    hATR   = INVALID_HANDLE;  // ATR handle
int    hHTF   = INVALID_HANDLE;  // HTF EMA handle

datetime lastBarTime  = 0;
datetime lastTradeTime = 0;
int      gmtOff        = 0;
double   pipFactor     = 10.0;   // for pips conversion (XAUUSD 2-digit → 100)

// Signal flags (updated each new bar)
bool sigBull = false;
bool sigBear = false;
bool htfBull = false;
bool htfBear = false;

// Daily tracking
double   dayOpenBalance = 0;
datetime dayDateLMS     = 0;
int      dayTrades      = 0;
bool     dayLimitHit    = false;
int      consecLoss     = 0;

// Session stats
int    statTotal = 0;
int    statWins  = 0;
double statPnL   = 0;

// Partial TP tracking
struct PartialRec { ulong ticket; bool done; };
PartialRec partials[];

// Trailing stop ATR reference
struct TrailRec { ulong ticket; double atrRef; };
TrailRec trails[];

//===================================================================//
//  OnInit
//===================================================================//
int OnInit()
{
   //--- Timeframe guard
   if(_Period > PERIOD_M5)
   {
      Alert(EA_LMS+": Please attach to M1 or M5 chart.");
      return INIT_FAILED;
   }

   //--- Pip factor  (XAUUSD quote has 2 decimal places → 1 pip = 0.01 → factor 100)
   pipFactor = (_Digits == 2 || _Digits == 3) ? 100.0 : 10.0;

   //--- GMT offset
   gmtOff = AutoGMT_LMS
            ? (int)MathRound((TimeCurrent() - TimeGMT()) / 3600.0)
            : GMTOffset_LMS;

   //--- Indicator handles
   hFast = iMA(_Symbol, _Period,    EMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hSlow = iMA(_Symbol, _Period,    EMASlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hATR  = iATR(_Symbol, _Period,   ATRPeriodLMS);
   hHTF  = iMA(_Symbol, HTFPeriod,  HTFEMAPeriod,  0, MODE_EMA, PRICE_CLOSE);

   if(hFast==INVALID_HANDLE || hSlow==INVALID_HANDLE ||
      hATR ==INVALID_HANDLE || hHTF ==INVALID_HANDLE)
   {
      Alert(EA_LMS+": Indicator handle creation failed!");
      return INIT_FAILED;
   }

   //--- Trade object
   trade.SetExpertMagicNumber(MAGIC_LMS);
   trade.SetDeviationInPoints(30);
   uint fm = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   trade.SetTypeFilling(
      (fm & SYMBOL_FILLING_FOK) != 0 ? ORDER_FILLING_FOK :
      (fm & SYMBOL_FILLING_IOC) != 0 ? ORDER_FILLING_IOC :
                                        ORDER_FILLING_RETURN);

   //--- Daily init
   dayDateLMS    = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   dayOpenBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   Print("=== ",EA_LMS," INITIALIZED === ",_Symbol,
         " ",EnumToString(_Period),
         " GMT+",gmtOff);
   return INIT_SUCCEEDED;
}

//===================================================================//
//  OnDeinit
//===================================================================//
void OnDeinit(const int reason)
{
   if(hFast != INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow != INVALID_HANDLE) IndicatorRelease(hSlow);
   if(hATR  != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hHTF  != INVALID_HANDLE) IndicatorRelease(hHTF);
   ObjectsDeleteAll(0, "LMS_");
   Print(EA_LMS,": Stopped. Total=",statTotal,
         " Wins=",statWins," PnL=",DoubleToString(statPnL,2));
}

//===================================================================//
//  OnTick  — main loop
//===================================================================//
void OnTick()
{
   //--- 1. Daily housekeeping + loss-limit monitor
   CheckDailyReset();

   //--- 2. Manage existing positions (partial TP / BE / trail)
   ManagePositions();

   //--- 3. Entry logic only fires on a new bar
   if(!IsNewBar()) return;

   //--- 4. Weekend close
   if(CloseFriday && IsFridayCutoff()) { CloseAll("Friday weekend"); return; }

   //--- 5. Session guard
   if(!IsInSession()) return;

   //--- 6. Hard limits
   if(dayLimitHit)                      return;
   if(dayTrades >= MaxTradesPerDay)     return;
   if(consecLoss >= MaxConsecLosses)    return;

   //--- 7. Cooldown after last trade
   if(CooldownBars > 0 && lastTradeTime > 0)
   {
      if((int)(TimeCurrent()-lastTradeTime) < CooldownBars*PeriodSeconds(_Period))
         return;
   }

   //--- 8. Max simultaneous positions
   if(CountPositions() >= MaxOpenLMS) return;

   //--- 9. ATR filter — avoid low-volatility noise
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(hATR,0,0,3,atrBuf) < 3) return;
   double atrVal  = atrBuf[1];
   double atrPips = atrVal / _Point / pipFactor;
   if(atrPips < MinATRPips)
   {
      if(DebugLMS) Print("[LMS] ATR skip: ",DoubleToString(atrPips,2),"p");
      return;
   }

   //--- 10. Spread filter
   long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(MaxSpreadLMS > 0 && sp > MaxSpreadLMS)
   {
      if(DebugLMS) Print("[LMS] Spread skip: ",sp);
      return;
   }

   //--- 11. Compute EMA + HTF signals
   UpdateSignals();

   //--- 12. Apply HTF filter to each direction
   bool buyOK  = sigBull;
   bool sellOK = sigBear;
   if(UseHTFFilter)
   {
      if(!htfBull) buyOK  = false;
      if(!htfBear) sellOK = false;
   }
   if(!buyOK && !sellOK) return;

   //--- 13. Resolve direction (EMA cross is mutually exclusive, but be safe)
   bool isBuy;
   if(buyOK && sellOK) return;   // contradicting signals — skip this bar
   isBuy = buyOK;

   //--- 14. Price & SL/TP
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = isBuy ? ask : bid;
   double sl    = NormalizeDouble(isBuy ? entry - atrVal*SLMultiATR
                                        : entry + atrVal*SLMultiATR, _Digits);
   double tp    = NormalizeDouble(isBuy ? entry + atrVal*TPMultiATR
                                        : entry - atrVal*TPMultiATR, _Digits);

   //--- 15. SL size filter
   double slPips = MathAbs(entry-sl) / _Point / pipFactor;
   if(slPips < MinSLPips)
   {
      if(DebugLMS) Print("[LMS] SL too tight: ",DoubleToString(slPips,2),"p");
      return;
   }
   if(MaxSLPips > 0 && slPips > MaxSLPips)
   {
      if(DebugLMS) Print("[LMS] SL too wide: ",DoubleToString(slPips,2),"p");
      return;
   }

   //--- 16. Broker minimum stop level
   double minStop = (double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(MathAbs(entry-sl) < minStop + _Point) return;

   //--- 17. Lot size
   double lot = CalcLot(MathAbs(entry-sl));
   if(lot < SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)) return;

   //--- 18. Open the trade
   DoTrade(isBuy, sl, tp, lot, atrVal);
}

//===================================================================//
//  UpdateSignals  — EMA cross + HTF direction
//===================================================================//
void UpdateSignals()
{
   sigBull = false;
   sigBear = false;

   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   if(CopyBuffer(hFast,0,0,4,fast) < 4) return;
   if(CopyBuffer(hSlow,0,0,4,slow) < 4) return;

   if(CrossModeOnly)
   {
      //--- Fire only on the exact bar of the cross (bar[1] just crossed)
      sigBull = (fast[1] > slow[1] && fast[2] <= slow[2]);
      sigBear = (fast[1] < slow[1] && fast[2] >= slow[2]);
   }
   else
   {
      //--- Fire on every bar while EMA9 is above/below EMA21 (trend-following)
      sigBull = (fast[1] > slow[1]);
      sigBear = (fast[1] < slow[1]);
   }

   //--- HTF EMA direction
   double htfEma[];
   ArraySetAsSeries(htfEma, true);
   if(CopyBuffer(hHTF,0,0,2,htfEma) < 2) return;
   double htfClose = iClose(_Symbol, HTFPeriod, 1);
   htfBull = (htfClose > htfEma[1]);
   htfBear = (htfClose < htfEma[1]);

   if(DebugLMS)
      Print("[LMS] F=",DoubleToString(fast[1],5)," S=",DoubleToString(slow[1],5),
            " Cross:",CrossModeOnly,"  Bull=",sigBull," Bear=",sigBear,
            "  HTF Bull=",htfBull," Bear=",htfBear);
}

//===================================================================//
//  Session check
//===================================================================//
bool IsInSession()
{
   if(AllHoursLMS) return true;
   int gh = (int)(((TimeCurrent()/3600) + gmtOff) % 24);
   if(gh < 0) gh += 24;
   return (LondonLMS && gh >= 8 && gh < 12);
}

//===================================================================//
//  New-bar gate
//===================================================================//
bool IsNewBar()
{
   datetime t = iTime(_Symbol, _Period, 0);
   if(t == lastBarTime) return false;
   lastBarTime = t;
   return true;
}

//===================================================================//
//  Friday cutoff
//===================================================================//
bool IsFridayCutoff()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week != 5) return false;
   int gh = (int)(((TimeCurrent()/3600) + gmtOff) % 24);
   if(gh < 0) gh += 24;
   return (gh >= FridayHour);
}

//===================================================================//
//  Count positions belonging to this EA
//===================================================================//
int CountPositions()
{
   int n = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tkt = PositionGetTicket(i);
      if(PositionSelectByTicket(tkt) &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (int)PositionGetInteger(POSITION_MAGIC) == MAGIC_LMS)
         n++;
   }
   return n;
}

//===================================================================//
//  Lot size calculation
//===================================================================//
double CalcLot(double slDist)
{
   double lot;
   if(RiskModeLMS == LMS_RISK_FIXED_LOT)
   {
      lot = FixedLotLMS;
   }
   else
   {
      double bal   = AccountInfoDouble(ACCOUNT_BALANCE);
      double risk  = bal * RiskPctLMS / 100.0;
      double tval  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tsize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tsize <= 0 || slDist <= 0)
         return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      lot = risk / (slDist / tsize * tval);
   }

   double vMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / vStep) * vStep;
   lot = MathMax(vMin, MathMin(MathMin(MaxLotLMS, vMax), lot));
   return lot;
}

//===================================================================//
//  Execute trade
//===================================================================//
void DoTrade(bool isBuy, double sl, double tp, double lot, double atrVal)
{
   string cmt = EA_LMS + (isBuy ? " BUY" : " SELL");
   bool ok = isBuy ? trade.Buy (lot, _Symbol, 0, sl, tp, cmt)
                   : trade.Sell(lot, _Symbol, 0, sl, tp, cmt);
   if(!ok)
   {
      Print("[LMS] Trade FAILED rc=",trade.ResultRetcode(),
            " ",trade.ResultRetcodeDescription());
      return;
   }

   ulong  orderTkt  = trade.ResultOrder();
   double fillPrice = trade.ResultPrice();
   double slPips    = MathAbs(fillPrice-sl) / _Point / pipFactor;

   Print(">>> ",EA_LMS," ",isBuy?"BUY":"SELL",
         "  Lot=",DoubleToString(lot,2),
         "  E=",DoubleToString(fillPrice,_Digits),
         "  SL=",DoubleToString(sl,_Digits)," (",DoubleToString(slPips,1),"p)",
         "  TP=",DoubleToString(tp,_Digits));

   lastTradeTime = TimeCurrent();
   dayTrades++;
   statTotal++;

   //--- Register for partial-TP management
   if(UsePartialLMS && orderTkt > 0)
   {
      int sz = ArraySize(partials);
      ArrayResize(partials, sz+1);
      partials[sz].ticket = orderTkt;
      partials[sz].done   = false;
   }

   //--- Register for trailing stop
   if(UseTrailLMS && orderTkt > 0)
   {
      int sz = ArraySize(trails);
      ArrayResize(trails, sz+1);
      trails[sz].ticket = orderTkt;
      trails[sz].atrRef  = atrVal;
   }

   //--- Chart arrow
   if(ShowArrowsLMS)
   {
      string nm = "LMS_"+IntegerToString((long)TimeCurrent())+(isBuy?"B":"S");
      ObjectCreate(0, nm, OBJ_ARROW, 0, TimeCurrent(), fillPrice);
      ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,     isBuy ? clrDodgerBlue : clrOrangeRed);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, 2);
   }

   //--- CSV log
   if(CSVLogLMS) WriteCSV(orderTkt, isBuy, fillPrice, sl, tp, lot, atrVal);
}

//===================================================================//
//  Manage open positions — partial TP, breakeven, trail
//===================================================================//
void ManagePositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tkt = PositionGetTicket(i);
      if(!PositionSelectByTicket(tkt)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC_LMS) continue;

      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl_    = PositionGetDouble(POSITION_SL);
      double tp_    = PositionGetDouble(POSITION_TP);
      double lot_   = PositionGetDouble(POSITION_VOLUME);
      bool   isBuy_ = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double cur    = isBuy_ ? bid : ask;
      double slDist = MathAbs(entry - sl_);
      if(slDist <= 0) continue;

      //=== PARTIAL TP ===
      if(UsePartialLMS)
      {
         for(int j=0; j<ArraySize(partials); j++)
         {
            if(partials[j].ticket == tkt && !partials[j].done)
            {
               double target = isBuy_ ? entry + slDist*PartialRR_LMS
                                      : entry - slDist*PartialRR_LMS;
               if((isBuy_ && cur >= target) || (!isBuy_ && cur <= target))
               {
                  //--- compute close volume
                  double vStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
                  double vMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
                  double cLot  = MathFloor(lot_ * PartialPctLMS/100.0 / vStep) * vStep;
                  if(cLot < vMin) cLot = vMin;
                  if(cLot > lot_) cLot = lot_;
                  if(cLot >= vMin && trade.PositionClosePartial(tkt, cLot))
                     partials[j].done = true;
               }
               break;
            }
         }
      }

      //=== BREAKEVEN ===
      if(EnableBE && MathAbs(sl_ - entry) > _Point*2)
      {
         double beLevel = isBuy_ ? entry + slDist*BreakevenRR
                                 : entry - slDist*BreakevenRR;
         bool hitBE = isBuy_ ? (cur >= beLevel && sl_ < entry - _Point)
                              : (cur <= beLevel && sl_ > entry + _Point);
         if(hitBE)
         {
            double newSL = NormalizeDouble(entry, _Digits);
            if((isBuy_ && newSL > sl_) || (!isBuy_ && newSL < sl_))
               trade.PositionModify(tkt, newSL, tp_);
         }
      }

      //=== TRAILING STOP ===
      if(UseTrailLMS)
      {
         for(int j=0; j<ArraySize(trails); j++)
         {
            if(trails[j].ticket == tkt)
            {
               double dist  = trails[j].atrRef * TrailATRMulti;
               double nsl   = NormalizeDouble(isBuy_ ? cur - dist : cur + dist, _Digits);
               bool improve = isBuy_ ? (nsl > sl_ + _Point) : (nsl < sl_ - _Point);
               if(improve) trade.PositionModify(tkt, nsl, tp_);
               break;
            }
         }
      }
   }
}

//===================================================================//
//  Close all positions
//===================================================================//
void CloseAll(string reason)
{
   Print(EA_LMS,": CloseAll — ",reason);
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tkt = PositionGetTicket(i);
      if(!PositionSelectByTicket(tkt)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MAGIC_LMS) continue;
      trade.PositionClose(tkt);
   }
}

//===================================================================//
//  Daily reset + continuous loss-limit check
//===================================================================//
void CheckDailyReset()
{
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(today != dayDateLMS)
   {
      dayDateLMS     = today;
      dayOpenBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      dayTrades      = 0;
      dayLimitHit    = false;
      Print(EA_LMS,": New day — OpenBal=",DoubleToString(dayOpenBalance,2));
   }

   if(!dayLimitHit)
   {
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      double bal     = AccountInfoDouble(ACCOUNT_BALANCE);
      double worst   = MathMin(equity, bal);
      double lossPct = (dayOpenBalance > 0) ? (dayOpenBalance-worst)/dayOpenBalance*100.0 : 0;
      if(lossPct >= MaxDailyLossPct)
      {
         dayLimitHit = true;
         CloseAll("DailyLoss "+DoubleToString(lossPct,1)+"%");
         Print(EA_LMS,": DAILY LOSS LIMIT HIT — ",DoubleToString(lossPct,2),"%");
      }
   }
}

//===================================================================//
//  OnTradeTransaction — track wins/losses for statistics
//===================================================================//
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &req,
                        const MqlTradeResult      &res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal <= 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((int)HistoryDealGetInteger(trans.deal,DEAL_MAGIC) != MAGIC_LMS) return;

   ENUM_DEAL_ENTRY de = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(de == DEAL_ENTRY_OUT || de == DEAL_ENTRY_OUT_BY)
   {
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                    + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                    + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      statPnL += profit;
      if(profit >= 0.0) { statWins++; consecLoss = 0; }
      else              { consecLoss++;               }
   }
}

//===================================================================//
//  CSV trade log
//===================================================================//
void WriteCSV(ulong tkt, bool isBuy, double entry, double sl, double tp,
              double lot, double atrVal)
{
   int fh = FileOpen(CSV_LMS, FILE_WRITE|FILE_READ|FILE_CSV|FILE_COMMON|FILE_ANSI, ',');
   if(fh == INVALID_HANDLE) return;
   FileSeek(fh, 0, SEEK_END);
   string row = IntegerToString((long)tkt) + "," +
                TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "," +
                (isBuy?"BUY":"SELL") + "," +
                DoubleToString(entry, _Digits) + "," +
                DoubleToString(sl,    _Digits) + "," +
                DoubleToString(tp,    _Digits) + "," +
                DoubleToString(lot,   2) + "," +
                DoubleToString(atrVal/_Point/pipFactor, 1) + "," +
                EnumToString(_Period);
   FileWrite(fh, row);
   FileClose(fh);
}
//+------------------------------------------------------------------+
