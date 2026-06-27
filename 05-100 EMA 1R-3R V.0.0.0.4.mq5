//+------------------------------------------------------------------+
//|                              05-100 EMA 1R-3R V.0.0.0.4.mq5     |
//|                                                                  |
//|       5/100 EMA Crossover Expert Advisor (M3 Only)               |
//+------------------------------------------------------------------+
#property copyright "EMA5-100"
#property version   "10.00"
#property strict

#include <Trade\Trade.mqh>

input double LotSize            = 0.1;
input int    MagicNumber         = 924100;
input int    MA_Fast_Period      = 5;
input int    MA_Slow_Period      = 100;
input int    ATR_Period           = 14;
input double ATR_Multiplier      = 2.0;
input double SL_Dollars           = 10.0;
input double RR_Ratio             = 3.0;
input int    MaxOpenTrades       = 6;
input double DailyMaxLoss        = 40.0;
input int    StartHour           = 7;
input int    StartMinute         = 0;
input int    EndHour             = 23;
input int    EndMinute           = 30;
input int    NoTradeBeforeClose  = 30;
input bool   UseLocalTime        = true;

CTrade   trade;
int      handleFast;
int      handleSlow;
int      handleATR;
bool     dailyLimitHit;
int      lastResetDay;
bool     endOfDayClosed;
datetime lastCrossBar;

//+------------------------------------------------------------------+
int OnInit()
{
   if(Period() != PERIOD_M3)
   {
      Alert("EMA5_100_CrossOver: Bu EA sadece M3 grafikte calisir! ",
            "Lutfen M3 (3 dakikalik) grafige ekleyin.");
      Print("HATA: EA M3 disinda bir zaman diliminde baslatildi. Durduruluyor.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(MagicNumber);

   handleFast = iMA(_Symbol, PERIOD_M3, MA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleSlow = iMA(_Symbol, PERIOD_M3, MA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleATR  = iATR(_Symbol, PERIOD_M3, ATR_Period);

   if(handleFast == INVALID_HANDLE || handleSlow == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("Indicator handle creation failed");
      return INIT_FAILED;
   }

   dailyLimitHit  = false;
   endOfDayClosed = false;
   lastResetDay   = -1;
   lastCrossBar   = 0;

   int gmtOffsetHour = (int)TimeGMTOffset() / 3600;
   string tzInfo = UseLocalTime
      ? "UTC+3 (Istanbul) | GMT offset: " + IntegerToString(gmtOffsetHour) + "h"
      : "Server time";

   int noTradeMin = EndHour * 60 + EndMinute - NoTradeBeforeClose;
   Print("EMA CrossOver v10.00 | ", _Symbol,
         " | EMA ", IntegerToString(MA_Fast_Period),
         "/", IntegerToString(MA_Slow_Period),
         " | ATR(", IntegerToString(ATR_Period), ")x",
         DoubleToString(ATR_Multiplier, 1),
         " | ", tzInfo,
         " | Islem: ", IntegerToString(StartHour), ":",
         StringFormat("%02d", StartMinute), "-",
         IntegerToString(noTradeMin / 60), ":",
         StringFormat("%02d", noTradeMin % 60),
         " | Kapanis: ", IntegerToString(EndHour), ":",
         StringFormat("%02d", EndMinute),
         " | MaxLoss: ", DoubleToString(DailyMaxLoss, 2), " USD");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleFast != INVALID_HANDLE) IndicatorRelease(handleFast);
   if(handleSlow != INVALID_HANDLE) IndicatorRelease(handleSlow);
   if(handleATR  != INVALID_HANDLE) IndicatorRelease(handleATR);
}

//+------------------------------------------------------------------+
void OnTick()
{
   int currentHour, currentMinute;
   GetLocalHourMinute(currentHour, currentMinute);
   int currentTotalMin = currentHour * 60 + currentMinute;
   int startTotalMin   = StartHour * 60 + StartMinute;
   int endTotalMin     = EndHour * 60 + EndMinute;
   int noTradeTotalMin = endTotalMin - NoTradeBeforeClose;

   CheckDailyReset(currentTotalMin, startTotalMin);

   if(currentTotalMin >= endTotalMin && !endOfDayClosed)
   {
      CloseAllPositions();
      endOfDayClosed = true;
      Print("Gun sonu: Tum pozisyonlar kapatildi.");
   }

   if(currentTotalMin < startTotalMin || currentTotalMin >= noTradeTotalMin)
      return;

   if(dailyLimitHit)
      return;

   double dailyPL = GetDailyPL();
   if(dailyPL <= -DailyMaxLoss)
   {
      CloseAllPositions();
      dailyLimitHit = true;
      Alert("Gunluk zarar limiti asildi! Islemler durduruldu. Zarar: ",
            DoubleToString(dailyPL, 2), " USD");
      Print("GUNLUK LIMIT: ", DoubleToString(dailyPL, 2),
            " USD | Limit: -", DoubleToString(DailyMaxLoss, 2), " USD");
      return;
   }

   if(CountOpenTrades() >= MaxOpenTrades)
      return;

   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   if(CopyBuffer(handleFast, 0, 0, 2, fast) < 2) return;
   if(CopyBuffer(handleSlow, 0, 0, 2, slow) < 2) return;

   bool crossUp   = (fast[1] <= slow[1]) && (fast[0] > slow[0]);
   bool crossDown = (fast[1] >= slow[1]) && (fast[0] < slow[0]);

   if(!crossUp && !crossDown)
      return;

   datetime currentBar = iTime(_Symbol, PERIOD_M3, 0);
   if(currentBar == lastCrossBar)
      return;

   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(handleATR, 0, 0, 1, atr) < 1) return;

   double close    = iClose(_Symbol, PERIOD_M3, 0);
   int    digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickVal <= 0 || tickSize <= 0 || atr[0] <= 0) return;

   double slDist    = NormalizeDouble(ATR_Multiplier * atr[0], digits);

   long   stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double spread    = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   double minDist   = NormalizeDouble((stopLevel + 2) * _Point, digits);

   if(slDist < minDist)
      slDist = minDist;

   double slCostUSD = (slDist / tickSize) * tickVal * LotSize;
   double tradeLot  = LotSize;

   if(slCostUSD > SL_Dollars)
      tradeLot = NormalizeDouble(SL_Dollars / ((slDist / tickSize) * tickVal), 2);

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(tradeLot < minLot)
      tradeLot = minLot;

   if(close > slow[0])
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(ask - slDist, digits);
      double tp  = NormalizeDouble(ask + slDist * RR_Ratio, digits);

      if(MathAbs(ask - tp) < minDist)
         tp = NormalizeDouble(ask + minDist, digits);

      Print("BUY Signal | StopLevel: ", stopLevel, " | Spread: ", spread / _Point,
            " pts | MinDist: ", minDist / _Point, " pts | slDist: ", slDist / _Point,
            " pts | SL: ", sl, " | TP: ", tp, " | Ask: ", ask,
            " | Bid: ", SymbolInfoDouble(_Symbol, SYMBOL_BID));

      if(!IsStopValid(ask, sl, tp))
      {
         Print("BUY IPTAL: SL/TP stop level kontrolunden gecemedi");
         return;
      }

      if(trade.Buy(tradeLot, _Symbol, ask, sl, tp, "EMA Cross BUY"))
         lastCrossBar = currentBar;
   }
   else if(close < slow[0])
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(bid + slDist, digits);
      double tp  = NormalizeDouble(bid - slDist * RR_Ratio, digits);

      if(MathAbs(bid - tp) < minDist)
         tp = NormalizeDouble(bid - minDist, digits);

      Print("SELL Signal | StopLevel: ", stopLevel, " | Spread: ", spread / _Point,
            " pts | MinDist: ", minDist / _Point, " pts | slDist: ", slDist / _Point,
            " pts | SL: ", sl, " | TP: ", tp,
            " | Ask: ", SymbolInfoDouble(_Symbol, SYMBOL_ASK), " | Bid: ", bid);

      if(!IsStopValid(bid, sl, tp))
      {
         Print("SELL IPTAL: SL/TP stop level kontrolunden gecemedi");
         return;
      }

      if(trade.Sell(tradeLot, _Symbol, bid, sl, tp, "EMA Cross SELL"))
         lastCrossBar = currentBar;
   }
}

//+------------------------------------------------------------------+
void GetLocalHourMinute(int &hour, int &minute)
{
   if(UseLocalTime)
   {
      datetime istanbul = TimeGMT() + 3 * 3600;
      MqlDateTime dt;
      TimeToStruct(istanbul, dt);
      hour   = dt.hour;
      minute = dt.min;
   }
   else
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      hour   = dt.hour;
      minute = dt.min;
   }
}

//+------------------------------------------------------------------+
void CheckDailyReset(int currentTotalMin, int startTotalMin)
{
   MqlDateTime now;
   TimeCurrent(now);
   int today = now.day_of_year;

   if(today != lastResetDay && currentTotalMin >= startTotalMin)
   {
      lastResetDay   = today;
      dailyLimitHit  = false;
      endOfDayClosed = false;
      Print("Yeni seans basladi. Gunluk zarar sayaci sifirlandi.");
   }
}

//+------------------------------------------------------------------+
double GetDailyPL()
{
   double totalPL = 0.0;

   datetime startOfDay = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   HistorySelect(startOfDay, TimeCurrent());

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      totalPL += HistoryDealGetDouble(ticket, DEAL_PROFIT)
               + HistoryDealGetDouble(ticket, DEAL_SWAP)
               + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            totalPL += PositionGetDouble(POSITION_PROFIT)
                     + PositionGetDouble(POSITION_SWAP);
         }
      }
   }

   return totalPL;
}

//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            trade.PositionClose(ticket);
      }
   }
}

//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
bool IsStopValid(double price, double sl, double tp)
{
   long minStop = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = (minStop + 2) * _Point;
   if(sl > 0 && MathAbs(price - sl) < minDist) return false;
   if(tp > 0 && MathAbs(price - tp) < minDist) return false;
   return true;
}
//+------------------------------------------------------------------+
