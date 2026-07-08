// V0001 05350 EMA - MA1/MA2 Chart Kontrol Katmani
//
// Bu adimda SADECE MA1 (sabit referans) ve MA2 (degisken, buton/edit
// kutusu ile chart uzerinden kontrol edilen) katmani kodlanmistir.
// Giris, cikis, stop-loss ve filtre mantigi bu asamada YOKTUR,
// ileride ayri adimlarda (brick-by-brick) eklenecektir.
//
// NOT (MT5 point/hassasiyet): Ileride stop seviyesi iceren moduller
// eklendiginde SYMBOL_TRADE_STOPS_LEVEL degerine +10 point'lik bir
// guvenlik tamponu eklenmelidir (onceki bir bug-fix bu yonde yapilmisti).
// Bu modulde emir/stop mantigi olmadigi icin burada kullanilmiyor,
// sadece ileriki adimlar icin referans olarak not edilmistir.
#property strict
#property copyright "V0001 05350 EMA"
#property version   "1.00"

//============================================================
// MA1 - SABIT REFERANS ORTALAMA
// Sadece input parametresinden ayarlanir, chart uzerinden
// degistirilemez. Ileride Sart 1'de "EMA1" referansi olarak
// kullanilacaktir (bu adimda sadece cizim/hesap altyapisi kurulur).
//============================================================
input int                 MA1_Period    = 50;         // MA1 periyodu (sabit referans)
input ENUM_MA_METHOD      MA1_Metodu    = MODE_EMA;    // MA1 hesaplama metodu
input ENUM_APPLIED_PRICE  MA1_FiyatTipi = PRICE_CLOSE; // MA1 uygulanan fiyat

//============================================================
// MA2 - DEGISKEN SISTEM KRITERI
// Baslangic periyodu input'tan gelir, sonrasinda chart uzerindeki
// buton + edit kutusu ile calisma anida degistirilir.
//============================================================
input int                 MA2_BaslangicPeriyodu = 300;      // MA2 baslangic periyodu
input ENUM_MA_METHOD      MA2_Metodu            = MODE_EMA; // MA2 hesaplama metodu
input ENUM_APPLIED_PRICE  MA2_FiyatTipi         = PRICE_CLOSE; // MA2 uygulanan fiyat

// MA2_Period: MA2'nin GUNCEL periyodunu tutan TEK merkezi global degisken.
// NOT: MA2_Period degisikligi ileride Sart 1, Sart 2, Sart 4,
// Filtre 2 tarafindan okunacak - henuz o moduller yazilmadi.
int MA2_Period = 300;

//--- Indicator handle'lari
int MA1_Handle = INVALID_HANDLE;
int MA2_Handle = INVALID_HANDLE;

//--- Chart'a eklenen indikatorlerin kisa adlari (silme islemi icin gerekli)
string MA1IndikatorAdi = "";
string MA2IndikatorAdi = "";

//--- MA2 kontrol paneli (buton + edit) nesne adlari
#define PANEL_PREFIX "V0001_MA2Panel_"
string EtiketAdi = PANEL_PREFIX + "Etiket";
string EditAdi   = PANEL_PREFIX + "Edit";
string ButonAdi  = PANEL_PREFIX + "Buton";

//============================================================
// Yardimci: Bir MA'yi iMA handle'i ile olusturup native olarak
// chart'a ekler (ChartIndicatorAdd). Basariliysa handle ve
// indikatorun chart'taki kisa adini disariya yazar.
//============================================================
bool MAEkle(int periyot, ENUM_MA_METHOD metod, ENUM_APPLIED_PRICE fiyat,
            int &handleCiktisi, string &indikatorAdiCiktisi)
{
   int yeniHandle = iMA(_Symbol, PERIOD_CURRENT, periyot, 0, metod, fiyat);
   if(yeniHandle == INVALID_HANDLE)
   {
      Print("HATA: iMA handle olusturulamadi. Periyot=", periyot, " HataKodu=", GetLastError());
      return false;
   }

   if(!ChartIndicatorAdd(0, 0, yeniHandle))
   {
      Print("HATA: ChartIndicatorAdd basarisiz. Periyot=", periyot, " HataKodu=", GetLastError());
      IndicatorRelease(yeniHandle);
      return false;
   }

   handleCiktisi = yeniHandle;
   int toplamIndikator = ChartIndicatorsTotal(0, 0);
   indikatorAdiCiktisi = ChartIndicatorName(0, 0, toplamIndikator - 1);
   return true;
}

//============================================================
// MA2'yi yeni bir periyot ile yeniden olusturur:
// - Once yeni handle/indikator basariyla eklenir
// - Basariliysa eski handle/indikator kaldirilir ve MA2_Period guncellenir
// - Basarisizsa eski MA2 aynen korunur (crash olmaz)
//============================================================
void MA2YenidenCiz(int yeniPeriyot)
{
   int eskiHandle = MA2_Handle;
   string eskiIndikatorAdi = MA2IndikatorAdi;

   int yeniHandle;
   string yeniIndikatorAdi;

   if(!MAEkle(yeniPeriyot, MA2_Metodu, MA2_FiyatTipi, yeniHandle, yeniIndikatorAdi))
   {
      Alert("MA2 periyodu guncellenemedi, eski deger korunuyor: ", MA2_Period);
      return;
   }

   if(eskiIndikatorAdi != "")
      ChartIndicatorDelete(0, 0, eskiIndikatorAdi);
   if(eskiHandle != INVALID_HANDLE)
      IndicatorRelease(eskiHandle);

   MA2_Handle       = yeniHandle;
   MA2IndikatorAdi  = yeniIndikatorAdi;
   MA2_Period       = yeniPeriyot;

   ChartRedraw();
}

//============================================================
// Girilen metnin gecerli bir MA periyodu (pozitif tam sayi) olup
// olmadigini kontrol eder. Gecersizse false doner (0, negatif,
// sayi olmayan metin, bos metin vs.)
//============================================================
bool MetniPeriyodaCevir(string metin, int &periyotCiktisi)
{
   StringTrimLeft(metin);
   StringTrimRight(metin);

   if(StringLen(metin) == 0)
      return false;

   for(int i = 0; i < StringLen(metin); i++)
   {
      ushort karakter = StringGetCharacter(metin, i);
      if(karakter < '0' || karakter > '9')
         return false;
   }

   long deger = StringToInteger(metin);
   if(deger <= 0 || deger > 100000)
      return false;

   periyotCiktisi = (int)deger;
   return true;
}

//============================================================
// MA2 kontrol panelini (etiket + edit kutusu + buton) chart
// uzerinde olusturur.
//============================================================
void PanelOlustur()
{
   ObjectCreate(0, EtiketAdi, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_COLOR, clrWhite);
   ObjectSetString(0, EtiketAdi, OBJPROP_TEXT, "MA2 Periyot:");
   ObjectSetInteger(0, EtiketAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_HIDDEN, true);

   ObjectCreate(0, EditAdi, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, EditAdi, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, EditAdi, OBJPROP_XDISTANCE, 90);
   ObjectSetInteger(0, EditAdi, OBJPROP_YDISTANCE, 15);
   ObjectSetInteger(0, EditAdi, OBJPROP_XSIZE, 60);
   ObjectSetInteger(0, EditAdi, OBJPROP_YSIZE, 20);
   ObjectSetString(0, EditAdi, OBJPROP_TEXT, IntegerToString(MA2_Period));
   ObjectSetInteger(0, EditAdi, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, EditAdi, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, EditAdi, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, EditAdi, OBJPROP_ALIGN, ALIGN_CENTER);
   ObjectSetInteger(0, EditAdi, OBJPROP_READONLY, false);
   ObjectSetInteger(0, EditAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, EditAdi, OBJPROP_HIDDEN, true);

   ObjectCreate(0, ButonAdi, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, ButonAdi, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, ButonAdi, OBJPROP_XDISTANCE, 155);
   ObjectSetInteger(0, ButonAdi, OBJPROP_YDISTANCE, 15);
   ObjectSetInteger(0, ButonAdi, OBJPROP_XSIZE, 60);
   ObjectSetInteger(0, ButonAdi, OBJPROP_YSIZE, 20);
   ObjectSetString(0, ButonAdi, OBJPROP_TEXT, "Uygula");
   ObjectSetInteger(0, ButonAdi, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, ButonAdi, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, ButonAdi, OBJPROP_BGCOLOR, clrSilver);
   ObjectSetInteger(0, ButonAdi, OBJPROP_STATE, false);
   ObjectSetInteger(0, ButonAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, ButonAdi, OBJPROP_HIDDEN, true);

   ChartRedraw();
}

//============================================================
// OnInit - MA1 ve MA2'yi olusturup chart'a ekler, kontrol panelini kurar
//============================================================
int OnInit()
{
   if(MA1_Period <= 0)
   {
      Print("HATA: MA1_Period gecersiz (", MA1_Period, "). Pozitif bir deger girin.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(MA2_BaslangicPeriyodu <= 0)
   {
      Print("HATA: MA2_BaslangicPeriyodu gecersiz (", MA2_BaslangicPeriyodu, "). Pozitif bir deger girin.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(!MAEkle(MA1_Period, MA1_Metodu, MA1_FiyatTipi, MA1_Handle, MA1IndikatorAdi))
   {
      Print("HATA: MA1 (sabit referans) olusturulamadi.");
      return INIT_FAILED;
   }

   MA2_Period = MA2_BaslangicPeriyodu;
   if(!MAEkle(MA2_Period, MA2_Metodu, MA2_FiyatTipi, MA2_Handle, MA2IndikatorAdi))
   {
      Print("HATA: MA2 (degisken sistem kriteri) olusturulamadi.");
      return INIT_FAILED;
   }

   PanelOlustur();
   ChartRedraw();

   return INIT_SUCCEEDED;
}

//============================================================
// OnDeinit - Tum indikator handle'larini ve chart nesnelerini temizler
//============================================================
void OnDeinit(const int reason)
{
   if(MA1IndikatorAdi != "")
      ChartIndicatorDelete(0, 0, MA1IndikatorAdi);
   if(MA2IndikatorAdi != "")
      ChartIndicatorDelete(0, 0, MA2IndikatorAdi);

   if(MA1_Handle != INVALID_HANDLE)
      IndicatorRelease(MA1_Handle);
   if(MA2_Handle != INVALID_HANDLE)
      IndicatorRelease(MA2_Handle);

   ObjectDelete(0, EtiketAdi);
   ObjectDelete(0, EditAdi);
   ObjectDelete(0, ButonAdi);

   ChartRedraw();
}

//============================================================
// OnChartEvent - MA2 "Uygula" butonuna tiklamayi yakalar
//============================================================
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK || sparam != ButonAdi)
      return;

   // Butonun basili gorunumde takilmasini engelle
   ObjectSetInteger(0, ButonAdi, OBJPROP_STATE, false);

   string girilenMetin = ObjectGetString(0, EditAdi, OBJPROP_TEXT);
   int yeniPeriyot;

   if(MetniPeriyodaCevir(girilenMetin, yeniPeriyot))
   {
      MA2YenidenCiz(yeniPeriyot);
   }
   else
   {
      Alert("Gecersiz MA2 periyodu girildi: '", girilenMetin, "'. Eski deger korunuyor: ", MA2_Period);
   }

   // Edit kutusunu her durumda guncel/gecerli periyot ile senkronize et
   ObjectSetString(0, EditAdi, OBJPROP_TEXT, IntegerToString(MA2_Period));
   ChartRedraw();
}

//============================================================
// OnTick - Bu adimda henuz giris/cikis/filtre mantigi yok
//============================================================
void OnTick()
{
}
