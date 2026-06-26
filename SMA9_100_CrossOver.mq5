//+------------------------------------------------------------------+
//|                                          SMA9_100_CrossOver.mq5  |
//|                                                                  |
//|        9/100 MA Crossover Expert Advisor (M3 Only) - v7.00       |
//+------------------------------------------------------------------+
#property copyright "MA9-100"
#property version   "8.00"
#property strict

#include <Trade\Trade.mqh>

input double         LotSize       = 0.1;
input int            MagicNumber    = 924100;
input int            MA_Fast_Period = 9;
input int            MA_Slow_Period = 100;
input ENUM_MA_METHOD MA_Method      = MODE_EMA;
input int            SL_Pips        = 10;
input double         RR_Ratio       = 2.0;
input int            MaxOpenTrades  = 6;
input double         DailyMaxLoss   = 40.0;
input int            StartHour      = 7;
input int            StartMinute    = 0;
input int            EndHour        = 23;
input int            EndMinute      = 30;
input bool           UseLocalTime   = true;

CTrade   trade;
int      handleFast;
int      handleSlow;
double   pipSize;
bool     dailyLimitHit;
int      lastResetDay;
bool     endOfDayClosed;
datetime lastCrossBar;

//+------------------------------------------------------------------+
int OnInit()
{
   if(Period() != PERIOD_M3)
   {
      Alert("Bu EA sadece M3 grafikte calisir! ",
            "Lutfen M3 (3 dakikalik) grafige ekleyin.");
      Print("HATA: EA M3 disinda bir zaman diliminde baslatildi. Durduruluyor.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(MagicNumber);

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(digits == 3 || digits == 5)
      pipSize = point * 10;
   else
      pipSize = point;

   handleFast = iMA(_Symbol, PERIOD_M3, MA_Fast_Period, 0, MA_Method, PRICE_CLOSE);
   handleSlow = iMA(_Symbol, PERIOD_M3, MA_Slow_Period, 0, MA_Method, PRICE_CLOSE);

   if(handleFast == INVALID_HANDLE || handleSlow == INVALID_HANDLE)
   {
      Print("MA indicator handle creation failed");
      return INIT_FAILED;
   }

   dailyLimitHit  = false;
   endOfDayClosed = false;
   lastResetDay   = -1;
   lastCrossBar   = 0;

   string maName;
   switch(MA_Method)
   {
      case MODE_EMA:  maName = "EMA"; break;
      case MODE_SMA:  maName = "SMA"; break;
      case MODE_SMMA: maName = "SMMA"; break;
      case MODE_LWMA: maName = "LWMA"; break;
      default:        maName = "MA";  break;
   }

   int gmtOffsetSec = (int)TimeGMTOffset();
   int gmtOffsetHour = gmtOffsetSec / 3600;
   string tzInfo = UseLocalTime
      ? "UTC+3 (Istanbul) | GMT offset: " + IntegerToString(gmtOffsetHour) + "h"
      : "Server time";

   Print("MA CrossOver v8.00 | ", _Symbol,
         " | ", maName, " ", IntegerToString(MA_Fast_Period),
         "/", IntegerToString(MA_Slow_Period),
         " | ", tzInfo,
         " | Seans: ", IntegerToString(StartHour), ":",
         StringFormat("%02d", StartMinute), "-",
         IntegerToString(EndHour), ":",
         StringFormat("%02d", EndMinute),
         " | MaxLoss: ", DoubleToString(DailyMaxLoss, 2), " USD");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleFast != INVALID_HANDLE) IndicatorRelease(handleFast);
   if(handleSlow != INVALID_HANDLE) IndicatorRelease(handleSlow);
}

//+------------------------------------------------------------------+
void OnTick()
{
   int currentHour, currentMinute;
   GetLocalHourMinute(currentHour, currentMinute);
   int currentTotalMin = currentHour * 60 + currentMinute;
   int startTotalMin   = StartHour * 60 + StartMinute;
   int endTotalMin     = EndHour * 60 + EndMinute;

   CheckDailyReset(currentTotalMin, startTotalMin);

   if(currentTotalMin >= endTotalMin && !endOfDayClosed)
   {
      CloseAllPositions();
      endOfDayClosed = true;
      Print("Seans sonu: ", IntegerToString(EndHour), ":",
            StringFormat("%02d", EndMinute),
            " | Tum pozisyonlar kapatildi.");
   }

   if(currentTotalMin < startTotalMin || currentTotalMin >= endTotalMin)
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

   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   if(CopyBuffer(handleFast, 0, 0, 2, fast) < 2) return;
   if(CopyBuffer(handleSlow, 0, 0, 2, slow) < 2) return;

   double fastPrev = fast[1];
   double fastCurr = fast[0];
   double slowPrev = slow[1];
   double slowCurr = slow[0];

   bool crossUp   = (fastPrev <= slowPrev) && (fastCurr > slowCurr);
   bool crossDown = (fastPrev >= slowPrev) && (fastCurr < slowCurr);

   if(!crossUp && !crossDown)
      return;

   datetime currentBar = iTime(_Symbol, PERIOD_M3, 0);
   if(currentBar == lastCrossBar)
      return;

   if(CountOpenTrades() >= MaxOpenTrades)
      return;

   double close  = iClose(_Symbol, PERIOD_M3, 0);
   double high   = iHigh(_Symbol, PERIOD_M3, 0);
   double low    = iLow(_Symbol, PERIOD_M3, 0);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(close > slowCurr)
   {
      double sl     = NormalizeDouble(low - SL_Pips * pipSize, digits);
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double slDist = ask - sl;
      double tp     = NormalizeDouble(ask + slDist * RR_Ratio, digits);

      if(trade.Buy(LotSize, _Symbol, ask, sl, tp, "MA Cross BUY"))
         lastCrossBar = currentBar;
   }
   else if(close < slowCurr)
   {
      double sl     = NormalizeDouble(high + SL_Pips * pipSize, digits);
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double slDist = sl - bid;
      double tp     = NormalizeDouble(bid - slDist * RR_Ratio, digits);

      if(trade.Sell(LotSize, _Symbol, bid, sl, tp, "MA Cross SELL"))
         lastCrossBar = currentBar;
   }
}

//+------------------------------------------------------------------+
void GetLocalHourMinute(int &hour, int &minute)
{
   if(UseLocalTime)
   {
      datetime gmtTime = TimeGMT();
      datetime istanbul = gmtTime + 3 * 3600;
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
