//+------------------------------------------------------------------+
//|                                          EMA9_100_CrossOver.mq5  |
//|                                                                  |
//|          9 SMA / 100 SMA Crossover Expert Advisor (M3 Only)      |
//+------------------------------------------------------------------+
#property copyright "EMA9-100"
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>

input double LotSize       = 0.1;
input int    MagicNumber    = 924100;
input int    MA_Fast_Period = 9;
input int    MA_Slow_Period = 100;
input int    SL_Pips        = 10;
input double RR_Ratio       = 3.0;
input int    MaxOpenTrades  = 4;

CTrade trade;
int    handleFast;
int    handleSlow;
double pipSize;

//+------------------------------------------------------------------+
int OnInit()
{
   if(Period() != PERIOD_M3)
   {
      Alert("EMA9_100_CrossOver: Bu EA sadece M3 grafikte calisir! ",
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

   Print("EMA9_100_CrossOver v3.00 | ", _Symbol,
         " | Digits: ", digits,
         " | 1 Pip: ", DoubleToString(pipSize, digits));
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

      trade.Buy(LotSize, _Symbol, ask, sl, tp, "EMA Cross BUY");
   }
   else if(close < slowCurr)
   {
      double sl     = NormalizeDouble(high + SL_Pips * pipSize, digits);
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double slDist = sl - bid;
      double tp     = NormalizeDouble(bid - slDist * RR_Ratio, digits);

      trade.Sell(LotSize, _Symbol, bid, sl, tp, "EMA Cross SELL");
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
      if(PositionGetSymbol(i) == _Symbol)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            count++;
      }
   }
   return count;
}
//+------------------------------------------------------------------+
