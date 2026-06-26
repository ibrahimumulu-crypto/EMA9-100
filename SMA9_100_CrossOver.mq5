//+------------------------------------------------------------------+
//|                                          SMA9_100_CrossOver.mq5  |
//|                                                                  |
//|          9 SMA / 100 SMA Crossover Expert Advisor (M3 Only)      |
//+------------------------------------------------------------------+
#property copyright "SMA9-100"
#property version   "4.00"
#property strict

#include <Trade\Trade.mqh>

input double LotSize       = 0.1;
input int    MagicNumber    = 924100;
input int    MA_Fast_Period = 9;
input int    MA_Slow_Period = 100;
input int    SL_Pips        = 10;
input double RR_Ratio       = 3.0;
input int    MaxOpenTrades  = 4;
input double DailyMaxLoss   = 100.0;

CTrade trade;
int    handleFast;
int    handleSlow;
double pipSize;
bool   dailyLimitHit;
int    lastResetDay;

//+------------------------------------------------------------------+
int OnInit()
{
   if(Period() != PERIOD_M3)
   {
      Alert("SMA9_100_CrossOver: Bu EA sadece M3 grafikte calisir! ",
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

   handleFast = iMA(_Symbol, PERIOD_M3, MA_Fast_Period, 0, MODE_SMA, PRICE_CLOSE);
   handleSlow = iMA(_Symbol, PERIOD_M3, MA_Slow_Period, 0, MODE_SMA, PRICE_CLOSE);

   if(handleFast == INVALID_HANDLE || handleSlow == INVALID_HANDLE)
   {
      Print("MA indicator handle creation failed");
      return INIT_FAILED;
   }

   dailyLimitHit = false;
   MqlDateTime now;
   TimeCurrent(now);
   lastResetDay = now.day_of_year;

   Print("SMA9_100_CrossOver v4.00 | ", _Symbol,
         " | Digits: ", digits,
         " | 1 Pip: ", DoubleToString(pipSize, digits),
         " | DailyMaxLoss: ", DoubleToString(DailyMaxLoss, 2), " USD");
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
   CheckDailyReset();

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

   if(!IsNewBar())
      return;

   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   if(CopyBuffer(handleFast, 0, 1, 2, fast) < 2) return;
   if(CopyBuffer(handleSlow, 0, 1, 2, slow) < 2) return;

   double fastPrev = fast[1];
   double fastCurr = fast[0];
   double slowPrev = slow[1];
   double slowCurr = slow[0];

   bool crossUp   = (fastPrev <= slowPrev) && (fastCurr > slowCurr);
   bool crossDown = (fastPrev >= slowPrev) && (fastCurr < slowCurr);

   if(!crossUp && !crossDown)
      return;

   if(CountOpenTrades() >= MaxOpenTrades)
      return;

   double close  = iClose(_Symbol, PERIOD_M3, 1);
   double high   = iHigh(_Symbol, PERIOD_M3, 1);
   double low    = iLow(_Symbol, PERIOD_M3, 1);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(close > slowCurr)
   {
      double sl     = NormalizeDouble(low - SL_Pips * pipSize, digits);
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double slDist = ask - sl;
      double tp     = NormalizeDouble(ask + slDist * RR_Ratio, digits);

      trade.Buy(LotSize, _Symbol, ask, sl, tp, "SMA Cross BUY");
   }
   else if(close < slowCurr)
   {
      double sl     = NormalizeDouble(high + SL_Pips * pipSize, digits);
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double slDist = sl - bid;
      double tp     = NormalizeDouble(bid - slDist * RR_Ratio, digits);

      trade.Sell(LotSize, _Symbol, bid, sl, tp, "SMA Cross SELL");
   }
}

//+------------------------------------------------------------------+
void CheckDailyReset()
{
   MqlDateTime now;
   TimeCurrent(now);

   if(now.day_of_year != lastResetDay)
   {
      lastResetDay  = now.day_of_year;
      dailyLimitHit = false;
      Print("Yeni gun basladi. Gunluk zarar sayaci sifirlandi.");
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
bool IsNewBar()
{
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_M3, 0);
   if(currentBar == lastBar)
      return false;
   lastBar = currentBar;
   return true;
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
