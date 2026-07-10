// TALGO 0023
//
// V0002 degisiklikleri (onceki V0001 kodundan devam):
// - MA2 kontrol paneli CORNER_LEFT_UPPER'dan CORNER_RIGHT_UPPER'a
//   tasindi (eski yerlesim chart'in sol-ust kosesindeki native
//   sembol/OHLC yazisiyla cakisiyordu, bu yuzden panel goze
//   carpmiyor/calismiyor gibi goruluyordu).
// - Buton tiklamasi Print ile terminale loglanir (dogrulama icin).
// - EMA1 (MA1) ile MA2'nin kesistigi mumlarda gorsel ok isareti
//   eklendi (SADECE gorsel - Sart 1 hesaplama mantigi degildir).
//
// TALGO 4: MA1/MA2 artik ChartIndicatorAdd ile DEGIL, renkli OBJ_TREND
// segmentleriyle biz ciziyoruz (EMA1=siyah, EMA2=koyu pembe). Sebep:
// native "Moving Average" indikatorunun rengi disaridan (EA'dan)
// degistirilemiyor - iMA()'da renk parametresi yok, ObjectSetInteger
// sadece OBJ_* nesnelerinde calisir. Hesaplama yine native iMA() ile.
//
// TALGO 5: MA1_Period varsayilan 50'den 1'e dusuruldu (zaten MODE_EMA).
// Panel Y konumu +40px asagi kaydirild (EA isim yazisinla cakismamasi icin).
// Etiketlerde "MA" yerine "EMA" kullanildi.
//
// Giris, cikis, stop-loss ve filtre mantigi bu asamada YOKTUR,
// ileride ayri adimlarda (brick-by-brick) eklenecektir.
//
// NOT (MT5 point/hassasiyet): Ileride stop seviyesi iceren moduller
// eklendiginde SYMBOL_TRADE_STOPS_LEVEL degerine +10 point'lik bir
// guvenlik tamponu eklenmelidir (onceki bir bug-fix bu yonde yapilmisti).
// Bu modulde emir/stop mantigi olmadigi icin burada kullanilmiyor,
// sadece ileriki adimlar icin referans olarak not edilmistir.
#property strict
#property copyright "TALGO 0021"
#property version   "2.00"

//============================================================
// MA1 - SABIT REFERANS ORTALAMA
// Sadece input parametresinden ayarlanir, chart uzerinden
// degistirilemez. Ileride Sart 1'de "EMA1" referansi olarak
// kullanilacaktir (bu adimda sadece cizim/hesap altyapisi kurulur).
//============================================================
input int                 MA1_Period    = 1;          // MA1 (EMA1) periyodu (sabit referans)
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

//--- TALGO 2: EMA1/MA2 kesisim gorsellestirme (SADECE gorsel isaretleme,
// Sart 1 hesaplama mantigi bu adimda yazilmiyor)
#define KESISIM_PREFIX "V0001_Kesisim_"
datetime SonKontrolEdilenMumZamani = 0; // ayni mumu tekrar tekrar islememek icin

//--- TALGO 4: MA1/MA2 ozel renkli cizgi ayarlari (native ChartIndicatorAdd
// yerine OBJ_TREND segmentleriyle biz ciziyoruz - renk kontrolu icin)
#define MA1_CIZGI_PREFIX "V0001_MA1Cizgi_"
#define MA2_CIZGI_PREFIX "V0001_MA2Cizgi_"
color MA1_CizgiRengi = clrWhite;    // MA1 (EMA1) sabit cizgi rengi
color MA2_CizgiRengi = clrBlueViolet; // MA2 cizgi rengi - periyot degisse de SABIT kalir
int   GecmisCizimBarSiniri = 2000;  // performans icin gecmise donuk cizilecek maksimum bar sayisi

// TALGO 0013: EMA gorunurluk toggle
bool     emaGorunur = true;
string   ToggleCOAdi = PANEL_PREFIX + "ToggleCO";

// TALGO 0021: ATR tabanli yapi (HH/HL/LH/LL) modulu
#define YAPI_ETIKET_PREFIX "T21_Etiket_"
#define YAPI_KUTU_PREFIX   "T21_Kutu_"
#define YAPI_ZIGZAG_PREFIX "T21_Zigzag_"

enum ENUM_YAPI_TIPI { YAPI_YOK=0, YAPI_HH=1, YAPI_HL=2, YAPI_LL=3, YAPI_LH=4 };

string YapiLabelAdi  = PANEL_PREFIX + "YapiLabel";
string YapiEditAdi   = PANEL_PREFIX + "YapiEdit";
string YapiButonAdi  = PANEL_PREFIX + "YapiApply";
string YapiToggleAdi = PANEL_PREFIX + "YapiCO";

input int    YapiATRPeriyodu = 14;
input double YapiATRCarpani  = 2.0;

double AktifATRCarpani = 2.0;
int    YapiATRHandle   = INVALID_HANDLE;

int      ZigzagYon = 0;
double   ZigzagEkstrem = 0;
datetime ZigzagEkstremZamani = 0;
int      ZigzagEkstremBarIndex = 0;

double         YapiSwingFiyatlari[];
datetime       YapiSwingZamanlari[];
int            YapiSwingYonleri[];
ENUM_YAPI_TIPI YapiSwingTipleri[];
int            YapiSwingSayisi = 0;

datetime SonOnayZamani = 0;
datetime SonYapiBarZamani = 0;

int      YapiTrendYonu = 0;
double   SonHHFiyat = 0;
double   SonHLFiyat = 0;
double   SonLLFiyat = 0;
double   SonLHFiyat = 0;

double         SonZigzagFiyat = 0;
datetime       SonZigzagZamani = 0;
ENUM_YAPI_TIPI SonZigzagTipi = YAPI_YOK;

bool yapiGorunur = true;

#define YAPI_MIN_BAR_MESAFE 3
#define YAPI_MIN_ATR_ORAN   0.5

//============================================================
// Yardimci: Bir MA'yi iMA handle'i ile olusturur.
// TALGO 4: ChartIndicatorAdd ARTIK KULLANILMIYOR - asagidaki
// MASegmentCiz/MAGecmisiCiz fonksiyonlari cizimi renkli OBJ_TREND
// segmentleriyle yapiyor (bkz. dosya basindaki TALGO 4 notu).
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

   handleCiktisi = yeniHandle;
   indikatorAdiCiktisi = "";
   return true;
}

//============================================================
// TALGO 4: MA1/MA2'yi renkli OBJ_TREND segmentleriyle cizer. Ayni
// segment (ayni bitis zamani) tekrar cizilmez (ObjectFind kontrolu).
//============================================================
void MASegmentCiz(string prefix, color renk, datetime zaman1, double deger1, datetime zaman2, double deger2)
{
   string segmentAdi = prefix + (string)zaman2;
   if(ObjectFind(0, segmentAdi) >= 0)
      return;

   ObjectCreate(0, segmentAdi, OBJ_TREND, 0, zaman1, deger1, zaman2, deger2);
   ObjectSetInteger(0, segmentAdi, OBJPROP_COLOR, renk);
   ObjectSetInteger(0, segmentAdi, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, segmentAdi, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, segmentAdi, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, segmentAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, segmentAdi, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, segmentAdi, OBJPROP_BACK, false);

   // TALGO 0013: EMA gizliyken yeni olusan segmentler de gizli baslasın
   if(!emaGorunur)
      ObjectSetInteger(0, segmentAdi, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
}

//============================================================
// Verilen handle'in gecmis degerlerini (en fazla GecmisCizimBarSiniri
// kadar) bastan sona renkli segmentler olarak ciz. MA2 periyodu
// degistiginde TUM gecmis degerler degistigi icin once eski segmentler
// silinir (ObjectsDeleteAll), sonra yeniden cizilir - renk HER ZAMAN
// disaridan verilen 'renk' parametresiyle sabit kalir.
//============================================================
void MAGecmisiCiz(int handle, string prefix, color renk)
{
   ObjectsDeleteAll(0, prefix);

   int mevcutBarSayisi = Bars(_Symbol, PERIOD_CURRENT);
   int barSiniri = MathMin(GecmisCizimBarSiniri, mevcutBarSayisi - 1);
   if(barSiniri <= 0)
      return;

   double degerler[];
   ArraySetAsSeries(degerler, true);
   if(CopyBuffer(handle, 0, 0, barSiniri + 1, degerler) != barSiniri + 1)
      return;

   for(int i = 0; i < barSiniri; i++)
   {
      datetime zaman1 = iTime(_Symbol, PERIOD_CURRENT, i + 1);
      datetime zaman2 = iTime(_Symbol, PERIOD_CURRENT, i);
      MASegmentCiz(prefix, renk, zaman1, degerler[i + 1], zaman2, degerler[i]);
   }
}

//============================================================
// Yeni kapanan mum icin MA cizgisine tek bir segment ekler (OnTick'te
// her yeni mumda cagrilir - tum gecmisi tekrar cizmez, performansli).
//============================================================
void MAYeniBarCiz(int handle, string prefix, color renk)
{
   double degerler[];
   ArraySetAsSeries(degerler, true);
   if(CopyBuffer(handle, 0, 1, 2, degerler) != 2)
      return;

   datetime zaman1 = iTime(_Symbol, PERIOD_CURRENT, 2);
   datetime zaman2 = iTime(_Symbol, PERIOD_CURRENT, 1);
   MASegmentCiz(prefix, renk, zaman1, degerler[1], zaman2, degerler[0]);
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

   // TALGO 4: yeni periyotla MA2 cizgisini KOYU PEMBE renkte yeniden ciz
   // (renk periyottan bagimsiz, her zaman MA2_CizgiRengi kullanilir)
   MAGecmisiCiz(MA2_Handle, MA2_CIZGI_PREFIX, MA2_CizgiRengi);

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
// TALGO 2: EMA1 (MA1) ile MA2'nin son kapanan mumda kesisip
// kesismedigini kontrol eder, kesisim varsa ok isareti cizer.
// SADECE gorsel isaretleme - Sart 1'in hesaplama mantigi degildir.
//============================================================
void KesisimKontrolEt()
{
   double ma1Degerleri[], ma2Degerleri[];
   ArraySetAsSeries(ma1Degerleri, true);
   ArraySetAsSeries(ma2Degerleri, true);

   // index0 = son kapanan mum (shift 1), index1 = bir onceki mum (shift 2)
   if(CopyBuffer(MA1_Handle, 0, 1, 2, ma1Degerleri) != 2)
      return;
   if(CopyBuffer(MA2_Handle, 0, 1, 2, ma2Degerleri) != 2)
      return;

   bool oncekiMumdaAltinda = ma1Degerleri[1] < ma2Degerleri[1];
   bool oncekiMumdaUstunde = ma1Degerleri[1] > ma2Degerleri[1];
   bool simdikiMumdaUstunde = ma1Degerleri[0] > ma2Degerleri[0];
   bool simdikiMumdaAltinda = ma1Degerleri[0] < ma2Degerleri[0];

   datetime mumZamani = iTime(_Symbol, PERIOD_CURRENT, 1);

   if(oncekiMumdaAltinda && simdikiMumdaUstunde)
   {
      double fiyat = iLow(_Symbol, PERIOD_CURRENT, 1);
      KesisimOkuCiz(mumZamani, fiyat, true); // yukari kesisim - yesil ok
   }
   else if(oncekiMumdaUstunde && simdikiMumdaAltinda)
   {
      double fiyat = iHigh(_Symbol, PERIOD_CURRENT, 1);
      KesisimOkuCiz(mumZamani, fiyat, false); // asagi kesisim - kirmizi ok
   }
}

//============================================================
// Belirtilen mum zamaninda yukari (yesil) ya da asagi (kirmizi)
// kesisim oku cizer. Ayni mum icin tekrar cizim yapmaz.
//============================================================
void KesisimOkuCiz(datetime mumZamani, double fiyat, bool yukariKesisim)
{
   string okAdi = KESISIM_PREFIX + (string)mumZamani + (yukariKesisim ? "_Y" : "_A");
   if(ObjectFind(0, okAdi) >= 0)
      return; // bu mum icin ok zaten cizilmis

   double mumYuksekligi = iHigh(_Symbol, PERIOD_CURRENT, 1) - iLow(_Symbol, PERIOD_CURRENT, 1);
   double bosluk = (mumYuksekligi > 0) ? mumYuksekligi * 0.3 : _Point * 10;
   double okFiyati = yukariKesisim ? (fiyat - bosluk) : (fiyat + bosluk);

   ObjectCreate(0, okAdi, OBJ_ARROW, 0, mumZamani, okFiyati);
   ObjectSetInteger(0, okAdi, OBJPROP_ARROWCODE, yukariKesisim ? 233 : 234);
   ObjectSetInteger(0, okAdi, OBJPROP_COLOR, yukariKesisim ? clrLime : clrRed);
   ObjectSetInteger(0, okAdi, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, okAdi, OBJPROP_ANCHOR, yukariKesisim ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, okAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, okAdi, OBJPROP_HIDDEN, true);
}

//============================================================
// TALGO 0021: Zigzag segment cizer (OBJ_TREND).
//============================================================
void YapiZigzagSegmentCiz(datetime z1, double f1, datetime z2, double f2, color cizgiRenk)
{
   string ad = YAPI_ZIGZAG_PREFIX + (string)z2;
   if(ObjectFind(0, ad) >= 0)
      ObjectDelete(0, ad);

   ObjectCreate(0, ad, OBJ_TREND, 0, z1, f1, z2, f2);
   ObjectSetInteger(0, ad, OBJPROP_COLOR, cizgiRenk);
   ObjectSetInteger(0, ad, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, ad, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, ad, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, ad, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, ad, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, ad, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, ad, OBJPROP_BACK, false);

   if(!yapiGorunur)
      ObjectSetInteger(0, ad, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
}

//============================================================
// TALGO 0021: Etiket cizer (ok + kutu + yazi = 3 obje).
//============================================================
void YapiEtiketCiz(datetime zaman, double fiyat, string metin, bool usteMi, ENUM_YAPI_TIPI tip)
{
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(YapiATRHandle, 0, 0, 1, atrBuf) != 1) return;
   double okOffset   = atrBuf[0] * 0.03;
   double kutuOffset = atrBuf[0] * 0.15;

   color kutuRenk = usteMi ? clrRoyalBlue : clrCrimson;

   string okAdiY = YAPI_KUTU_PREFIX + (string)zaman + "_ok_" + metin;
   if(ObjectFind(0, okAdiY) >= 0) ObjectDelete(0, okAdiY);
   double okFiyat = usteMi ? fiyat + okOffset : fiyat - okOffset;
   ObjectCreate(0, okAdiY, OBJ_ARROW, 0, zaman, okFiyat);
   ObjectSetInteger(0, okAdiY, OBJPROP_ARROWCODE, usteMi ? 234 : 233);
   ObjectSetInteger(0, okAdiY, OBJPROP_COLOR, kutuRenk);
   ObjectSetInteger(0, okAdiY, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, okAdiY, OBJPROP_ANCHOR, usteMi ? ANCHOR_BOTTOM : ANCHOR_TOP);
   ObjectSetInteger(0, okAdiY, OBJPROP_BACK, false);
   ObjectSetInteger(0, okAdiY, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, okAdiY, OBJPROP_HIDDEN, true);

   string bgAdi = YAPI_KUTU_PREFIX + (string)zaman + "_bg_" + metin;
   if(ObjectFind(0, bgAdi) >= 0) ObjectDelete(0, bgAdi);
   double bgFiyat = usteMi ? fiyat + kutuOffset : fiyat - kutuOffset;
   ObjectCreate(0, bgAdi, OBJ_ARROW, 0, zaman, bgFiyat);
   ObjectSetInteger(0, bgAdi, OBJPROP_ARROWCODE, 167);
   ObjectSetInteger(0, bgAdi, OBJPROP_COLOR, kutuRenk);
   ObjectSetInteger(0, bgAdi, OBJPROP_WIDTH, 4);
   ObjectSetInteger(0, bgAdi, OBJPROP_ANCHOR, usteMi ? ANCHOR_BOTTOM : ANCHOR_TOP);
   ObjectSetInteger(0, bgAdi, OBJPROP_BACK, true);
   ObjectSetInteger(0, bgAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bgAdi, OBJPROP_HIDDEN, true);

   string txtAdi = YAPI_ETIKET_PREFIX + (string)zaman + "_" + metin;
   if(ObjectFind(0, txtAdi) >= 0) ObjectDelete(0, txtAdi);
   ObjectCreate(0, txtAdi, OBJ_TEXT, 0, zaman, bgFiyat);
   ObjectSetString(0, txtAdi, OBJPROP_TEXT, metin);
   ObjectSetString(0, txtAdi, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, txtAdi, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, txtAdi, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, txtAdi, OBJPROP_ANCHOR, usteMi ? ANCHOR_BOTTOM : ANCHOR_TOP);
   ObjectSetInteger(0, txtAdi, OBJPROP_BACK, false);
   ObjectSetInteger(0, txtAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, txtAdi, OBJPROP_HIDDEN, true);

   if(!yapiGorunur)
   {
      ObjectSetInteger(0, okAdiY, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, bgAdi, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, txtAdi, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   }
}

//============================================================
// TALGO 0021: Trend-aware swing classification state machine.
//============================================================
void YapiSwingOnayla(datetime zaman, double fiyat, int yon)
{
   ENUM_YAPI_TIPI tip = YAPI_YOK;
   color zigzagRenk = clrGray;

   if(YapiTrendYonu == 0)
   {
      if(yon == 1)
      {
         if(SonLLFiyat == 0)
         {
            SonHHFiyat = fiyat;
            tip = YAPI_HH;
            zigzagRenk = clrRoyalBlue;
         }
         else
         {
            SonLHFiyat = fiyat;
            tip = YAPI_LH;
            YapiTrendYonu = -1;
            zigzagRenk = clrOrangeRed;
         }
      }
      else
      {
         if(SonHHFiyat == 0)
         {
            SonLLFiyat = fiyat;
            tip = YAPI_LL;
            zigzagRenk = clrOrangeRed;
         }
         else
         {
            SonHLFiyat = fiyat;
            tip = YAPI_HL;
            YapiTrendYonu = 1;
            zigzagRenk = clrOrangeRed;
         }
      }
   }
   else if(YapiTrendYonu == 1)
   {
      if(yon == 1)
      {
         if(fiyat > SonHHFiyat)
         {
            SonHHFiyat = fiyat;
            tip = YAPI_HH;
            zigzagRenk = clrRoyalBlue;
         }
         else
            return;
      }
      else
      {
         if(fiyat > SonHLFiyat)
         {
            SonHLFiyat = fiyat;
            tip = YAPI_HL;
            zigzagRenk = clrOrangeRed;
         }
         else
         {
            SonLLFiyat = fiyat;
            SonLHFiyat = SonHHFiyat;
            YapiTrendYonu = -1;
            tip = YAPI_LL;
            zigzagRenk = clrOrangeRed;
         }
      }
   }
   else
   {
      if(yon == -1)
      {
         if(fiyat < SonLLFiyat)
         {
            SonLLFiyat = fiyat;
            tip = YAPI_LL;
            zigzagRenk = clrRoyalBlue;
         }
         else
            return;
      }
      else
      {
         if(fiyat < SonLHFiyat)
         {
            SonLHFiyat = fiyat;
            tip = YAPI_LH;
            zigzagRenk = clrOrangeRed;
         }
         else
         {
            SonHHFiyat = fiyat;
            SonHLFiyat = SonLLFiyat;
            YapiTrendYonu = 1;
            tip = YAPI_HH;
            zigzagRenk = clrRoyalBlue;
         }
      }
   }

   if(tip == YAPI_YOK)
      return;

   if(SonZigzagZamani != 0)
      YapiZigzagSegmentCiz(SonZigzagZamani, SonZigzagFiyat, zaman, fiyat, zigzagRenk);

   SonZigzagFiyat = fiyat;
   SonZigzagZamani = zaman;
   SonZigzagTipi = tip;

   string etiketMetni = "";
   bool usteMi = false;
   if(tip == YAPI_HH)      { etiketMetni = "HH"; usteMi = true; }
   else if(tip == YAPI_HL) { etiketMetni = "HL"; usteMi = false; }
   else if(tip == YAPI_LL) { etiketMetni = "LL"; usteMi = false; }
   else if(tip == YAPI_LH) { etiketMetni = "LH"; usteMi = true; }

   YapiEtiketCiz(zaman, fiyat, etiketMetni, usteMi, tip);

   int yeniSayac = YapiSwingSayisi + 1;
   ArrayResize(YapiSwingFiyatlari, yeniSayac);
   ArrayResize(YapiSwingZamanlari, yeniSayac);
   ArrayResize(YapiSwingYonleri, yeniSayac);
   ArrayResize(YapiSwingTipleri, yeniSayac);
   YapiSwingFiyatlari[YapiSwingSayisi] = fiyat;
   YapiSwingZamanlari[YapiSwingSayisi] = zaman;
   YapiSwingYonleri[YapiSwingSayisi] = yon;
   YapiSwingTipleri[YapiSwingSayisi] = tip;
   YapiSwingSayisi = yeniSayac;
}

//============================================================
// TALGO 0021: ATR tabanli zigzag taramasi.
//============================================================
void YapiATRZigzagTara(int baslangicBar, int bitisBar)
{
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);

   for(int i = baslangicBar; i >= bitisBar; i--)
   {
      if(CopyBuffer(YapiATRHandle, 0, i, 1, atrBuf) != 1) continue;
      if(atrBuf[0] <= 0) continue;
      double esik = atrBuf[0] * AktifATRCarpani;

      double barHigh = iHigh(_Symbol, PERIOD_CURRENT, i);
      double barLow  = iLow(_Symbol, PERIOD_CURRENT, i);
      datetime barZaman = iTime(_Symbol, PERIOD_CURRENT, i);

      if(ZigzagYon == 0)
      {
         ZigzagEkstrem = barHigh;
         ZigzagEkstremZamani = barZaman;
         ZigzagEkstremBarIndex = i;
         ZigzagYon = 1;
         continue;
      }

      if(ZigzagYon == 1)
      {
         if(barHigh > ZigzagEkstrem)
         {
            ZigzagEkstrem = barHigh;
            ZigzagEkstremZamani = barZaman;
            ZigzagEkstremBarIndex = i;
         }

         if(ZigzagEkstrem - barLow >= esik)
         {
            bool filtrePassed = true;

            if(SonOnayZamani > 0)
            {
               int mesafe = Bars(_Symbol, PERIOD_CURRENT,
                                 MathMin(SonOnayZamani, ZigzagEkstremZamani),
                                 MathMax(SonOnayZamani, ZigzagEkstremZamani));
               if(mesafe - 1 < YAPI_MIN_BAR_MESAFE)
                  filtrePassed = false;
            }

            if(filtrePassed && YapiSwingSayisi > 0)
            {
               double fark = MathAbs(ZigzagEkstrem - YapiSwingFiyatlari[YapiSwingSayisi - 1]);
               if(fark < atrBuf[0] * YAPI_MIN_ATR_ORAN)
                  filtrePassed = false;
            }

            if(filtrePassed)
            {
               YapiSwingOnayla(ZigzagEkstremZamani, ZigzagEkstrem, 1);
               SonOnayZamani = ZigzagEkstremZamani;
            }

            ZigzagYon = -1;
            ZigzagEkstrem = barLow;
            ZigzagEkstremZamani = barZaman;
            ZigzagEkstremBarIndex = i;
         }
      }
      else
      {
         if(barLow < ZigzagEkstrem)
         {
            ZigzagEkstrem = barLow;
            ZigzagEkstremZamani = barZaman;
            ZigzagEkstremBarIndex = i;
         }

         if(barHigh - ZigzagEkstrem >= esik)
         {
            bool filtrePassed = true;

            if(SonOnayZamani > 0)
            {
               int mesafe = Bars(_Symbol, PERIOD_CURRENT,
                                 MathMin(SonOnayZamani, ZigzagEkstremZamani),
                                 MathMax(SonOnayZamani, ZigzagEkstremZamani));
               if(mesafe - 1 < YAPI_MIN_BAR_MESAFE)
                  filtrePassed = false;
            }

            if(filtrePassed && YapiSwingSayisi > 0)
            {
               double fark = MathAbs(ZigzagEkstrem - YapiSwingFiyatlari[YapiSwingSayisi - 1]);
               if(fark < atrBuf[0] * YAPI_MIN_ATR_ORAN)
                  filtrePassed = false;
            }

            if(filtrePassed)
            {
               YapiSwingOnayla(ZigzagEkstremZamani, ZigzagEkstrem, -1);
               SonOnayZamani = ZigzagEkstremZamani;
            }

            ZigzagYon = 1;
            ZigzagEkstrem = barHigh;
            ZigzagEkstremZamani = barZaman;
            ZigzagEkstremBarIndex = i;
         }
      }
   }
}

//============================================================
// TALGO 0021: Gecmis barlari tarayarak yapi'yi sifirdan olusturur.
//============================================================
void YapiGecmisiTara()
{
   if(YapiATRHandle == INVALID_HANDLE) return;
   int sinir = MathMin(GecmisCizimBarSiniri, Bars(_Symbol, PERIOD_CURRENT) - 1);
   if(sinir < 10) return;
   ZigzagYon = 0;
   YapiATRZigzagTara(sinir, 1);
   SonYapiBarZamani = iTime(_Symbol, PERIOD_CURRENT, 1);
}

//============================================================
// TALGO 0021: Yeni bar olustugunda zigzag durumunu gunceller.
//============================================================
void YapiYeniBarIsle()
{
   if(Bars(_Symbol, PERIOD_CURRENT) < 3) return;
   if(YapiATRHandle == INVALID_HANDLE) return;

   datetime barZaman = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(barZaman <= SonYapiBarZamani) return;
   SonYapiBarZamani = barZaman;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(YapiATRHandle, 0, 1, 1, atrBuf) != 1) return;
   if(atrBuf[0] <= 0) return;
   double esik = atrBuf[0] * AktifATRCarpani;

   double barHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double barLow  = iLow(_Symbol, PERIOD_CURRENT, 1);

   if(ZigzagYon == 0)
   {
      ZigzagEkstrem = barHigh;
      ZigzagEkstremZamani = barZaman;
      ZigzagEkstremBarIndex = 1;
      ZigzagYon = 1;
      return;
   }

   if(ZigzagYon == 1)
   {
      if(barHigh > ZigzagEkstrem)
      {
         ZigzagEkstrem = barHigh;
         ZigzagEkstremZamani = barZaman;
         ZigzagEkstremBarIndex = 1;
      }

      if(ZigzagEkstrem - barLow >= esik)
      {
         bool filtrePassed = true;

         if(SonOnayZamani > 0)
         {
            int mesafe = Bars(_Symbol, PERIOD_CURRENT,
                              MathMin(SonOnayZamani, ZigzagEkstremZamani),
                              MathMax(SonOnayZamani, ZigzagEkstremZamani));
            if(mesafe - 1 < YAPI_MIN_BAR_MESAFE)
               filtrePassed = false;
         }

         if(filtrePassed && YapiSwingSayisi > 0)
         {
            double fark = MathAbs(ZigzagEkstrem - YapiSwingFiyatlari[YapiSwingSayisi - 1]);
            if(fark < atrBuf[0] * YAPI_MIN_ATR_ORAN)
               filtrePassed = false;
         }

         if(filtrePassed)
         {
            YapiSwingOnayla(ZigzagEkstremZamani, ZigzagEkstrem, 1);
            SonOnayZamani = ZigzagEkstremZamani;
         }

         ZigzagYon = -1;
         ZigzagEkstrem = barLow;
         ZigzagEkstremZamani = barZaman;
         ZigzagEkstremBarIndex = 1;
      }
   }
   else
   {
      if(barLow < ZigzagEkstrem)
      {
         ZigzagEkstrem = barLow;
         ZigzagEkstremZamani = barZaman;
         ZigzagEkstremBarIndex = 1;
      }

      if(barHigh - ZigzagEkstrem >= esik)
      {
         bool filtrePassed = true;

         if(SonOnayZamani > 0)
         {
            int mesafe = Bars(_Symbol, PERIOD_CURRENT,
                              MathMin(SonOnayZamani, ZigzagEkstremZamani),
                              MathMax(SonOnayZamani, ZigzagEkstremZamani));
            if(mesafe - 1 < YAPI_MIN_BAR_MESAFE)
               filtrePassed = false;
         }

         if(filtrePassed && YapiSwingSayisi > 0)
         {
            double fark = MathAbs(ZigzagEkstrem - YapiSwingFiyatlari[YapiSwingSayisi - 1]);
            if(fark < atrBuf[0] * YAPI_MIN_ATR_ORAN)
               filtrePassed = false;
         }

         if(filtrePassed)
         {
            YapiSwingOnayla(ZigzagEkstremZamani, ZigzagEkstrem, -1);
            SonOnayZamani = ZigzagEkstremZamani;
         }

         ZigzagYon = 1;
         ZigzagEkstrem = barHigh;
         ZigzagEkstremZamani = barZaman;
         ZigzagEkstremBarIndex = 1;
      }
   }
}

//============================================================
// TALGO 0021: Tum yapi nesnelerini sil, sifirla, yeniden tara.
//============================================================
void YapiSifirlaVeCiz()
{
   ObjectsDeleteAll(0, YAPI_ETIKET_PREFIX);
   ObjectsDeleteAll(0, YAPI_KUTU_PREFIX);
   ObjectsDeleteAll(0, YAPI_ZIGZAG_PREFIX);

   ArrayResize(YapiSwingFiyatlari, 0);
   ArrayResize(YapiSwingZamanlari, 0);
   ArrayResize(YapiSwingYonleri, 0);
   ArrayResize(YapiSwingTipleri, 0);
   YapiSwingSayisi = 0;

   ZigzagYon = 0;
   ZigzagEkstrem = 0;
   ZigzagEkstremZamani = 0;
   ZigzagEkstremBarIndex = 0;
   SonOnayZamani = 0;
   SonYapiBarZamani = 0;

   YapiTrendYonu = 0;
   SonHHFiyat = 0;
   SonHLFiyat = 0;
   SonLLFiyat = 0;
   SonLHFiyat = 0;

   SonZigzagFiyat = 0;
   SonZigzagZamani = 0;
   SonZigzagTipi = YAPI_YOK;

   YapiGecmisiTara();
   ChartRedraw();
}

//============================================================
// TALGO 0013: Tum MA1/MA2 cizgi segmentlerinin gorunurlugunu ayarlar.
// gorunur=true → OBJ_ALL_PERIODS, gorunur=false → OBJ_NO_PERIODS
// Hesaplama handle'lari ve CopyBuffer etkilenmez, sadece gorsel.
//============================================================
void EMAGorunurlukAyarla(bool gorunur)
{
   long zamanDilimi = gorunur ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
   int toplam = ObjectsTotal(0, 0, OBJ_TREND);
   for(int i = toplam - 1; i >= 0; i--)
   {
      string ad = ObjectName(0, i, 0, OBJ_TREND);
      if(StringFind(ad, MA1_CIZGI_PREFIX) == 0 || StringFind(ad, MA2_CIZGI_PREFIX) == 0)
         ObjectSetInteger(0, ad, OBJPROP_TIMEFRAMES, zamanDilimi);
   }
}

//============================================================
// TALGO 0021: Tum yapi nesnelerinin gorunurlugunu ayarlar.
//============================================================
void YapiGorunurlukAyarla(bool gorunur)
{
   long zamanDilimi = gorunur ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
   int toplam = ObjectsTotal(0, 0, -1);
   for(int i = toplam - 1; i >= 0; i--)
   {
      string ad = ObjectName(0, i, 0, -1);
      if(StringFind(ad, YAPI_ETIKET_PREFIX) == 0 ||
         StringFind(ad, YAPI_KUTU_PREFIX) == 0 ||
         StringFind(ad, YAPI_ZIGZAG_PREFIX) == 0)
         ObjectSetInteger(0, ad, OBJPROP_TIMEFRAMES, zamanDilimi);
   }
}

//============================================================
// MA2 kontrol panelini (etiket + edit kutusu + buton) chart
// uzerinde olusturur.
//============================================================
void PanelOlustur()
{
   // V0002: Panel CORNER_RIGHT_UPPER'a tasindi - sol-ust kosedeki native
   // sembol/OHLC yazisiyla cakismasin diye, en az 15px margin birakildi.
   ObjectCreate(0, EtiketAdi, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_XDISTANCE, 217);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_YDISTANCE, 5);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_COLOR, clrWhite);
   ObjectSetString(0, EtiketAdi, OBJPROP_TEXT, "EMA2 Periyot:");
   ObjectSetInteger(0, EtiketAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_HIDDEN, true);

   ObjectCreate(0, EditAdi, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, EditAdi, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, EditAdi, OBJPROP_XDISTANCE, 193);
   ObjectSetInteger(0, EditAdi, OBJPROP_YDISTANCE, 25);
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
   ObjectSetInteger(0, ButonAdi, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, ButonAdi, OBJPROP_XDISTANCE, 128);
   ObjectSetInteger(0, ButonAdi, OBJPROP_YDISTANCE, 25);
   ObjectSetInteger(0, ButonAdi, OBJPROP_XSIZE, 60);
   ObjectSetInteger(0, ButonAdi, OBJPROP_YSIZE, 20);
   ObjectSetString(0, ButonAdi, OBJPROP_TEXT, "Apply");
   ObjectSetInteger(0, ButonAdi, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, ButonAdi, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, ButonAdi, OBJPROP_BGCOLOR, clrSilver);
   ObjectSetInteger(0, ButonAdi, OBJPROP_STATE, false);
   ObjectSetInteger(0, ButonAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, ButonAdi, OBJPROP_HIDDEN, true);

   // TALGO 0013: C/O toggle butonu - Apply butonunun hemen solunda, ayni satir
   ObjectCreate(0, ToggleCOAdi, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, ToggleCOAdi, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, ToggleCOAdi, OBJPROP_XDISTANCE, 63);
   ObjectSetInteger(0, ToggleCOAdi, OBJPROP_YDISTANCE, 25);
   ObjectSetInteger(0, ToggleCOAdi, OBJPROP_XSIZE, 40);
   ObjectSetInteger(0, ToggleCOAdi, OBJPROP_YSIZE, 20);
   ObjectSetString(0, ToggleCOAdi, OBJPROP_TEXT, "C/O");
   ObjectSetInteger(0, ToggleCOAdi, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, ToggleCOAdi, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, ToggleCOAdi, OBJPROP_BGCOLOR, clrSilver);
   ObjectSetInteger(0, ToggleCOAdi, OBJPROP_STATE, false);
   ObjectSetInteger(0, ToggleCOAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, ToggleCOAdi, OBJPROP_HIDDEN, true);

   // TALGO 0021: Yapi paneli - Row 3 (Y=55) + Row 4 (Y=75)
   ObjectCreate(0, YapiLabelAdi, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, YapiLabelAdi, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, YapiLabelAdi, OBJPROP_XDISTANCE, 217);
   ObjectSetInteger(0, YapiLabelAdi, OBJPROP_YDISTANCE, 55);
   ObjectSetString(0, YapiLabelAdi, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, YapiLabelAdi, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, YapiLabelAdi, OBJPROP_COLOR, clrWhite);
   ObjectSetString(0, YapiLabelAdi, OBJPROP_TEXT, "ATR Zigzag:");
   ObjectSetInteger(0, YapiLabelAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, YapiLabelAdi, OBJPROP_HIDDEN, true);

   ObjectCreate(0, YapiEditAdi, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, YapiEditAdi, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, YapiEditAdi, OBJPROP_XDISTANCE, 193);
   ObjectSetInteger(0, YapiEditAdi, OBJPROP_YDISTANCE, 75);
   ObjectSetInteger(0, YapiEditAdi, OBJPROP_XSIZE, 60);
   ObjectSetInteger(0, YapiEditAdi, OBJPROP_YSIZE, 20);
   ObjectSetString(0, YapiEditAdi, OBJPROP_TEXT, DoubleToString(AktifATRCarpani, 1));
   ObjectSetInteger(0, YapiEditAdi, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, YapiEditAdi, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, YapiEditAdi, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, YapiEditAdi, OBJPROP_ALIGN, ALIGN_CENTER);
   ObjectSetInteger(0, YapiEditAdi, OBJPROP_READONLY, false);
   ObjectSetInteger(0, YapiEditAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, YapiEditAdi, OBJPROP_HIDDEN, true);

   ObjectCreate(0, YapiButonAdi, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, YapiButonAdi, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, YapiButonAdi, OBJPROP_XDISTANCE, 128);
   ObjectSetInteger(0, YapiButonAdi, OBJPROP_YDISTANCE, 75);
   ObjectSetInteger(0, YapiButonAdi, OBJPROP_XSIZE, 60);
   ObjectSetInteger(0, YapiButonAdi, OBJPROP_YSIZE, 20);
   ObjectSetString(0, YapiButonAdi, OBJPROP_TEXT, "Apply");
   ObjectSetInteger(0, YapiButonAdi, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, YapiButonAdi, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, YapiButonAdi, OBJPROP_BGCOLOR, clrSilver);
   ObjectSetInteger(0, YapiButonAdi, OBJPROP_STATE, false);
   ObjectSetInteger(0, YapiButonAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, YapiButonAdi, OBJPROP_HIDDEN, true);

   ObjectCreate(0, YapiToggleAdi, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, YapiToggleAdi, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, YapiToggleAdi, OBJPROP_XDISTANCE, 63);
   ObjectSetInteger(0, YapiToggleAdi, OBJPROP_YDISTANCE, 75);
   ObjectSetInteger(0, YapiToggleAdi, OBJPROP_XSIZE, 40);
   ObjectSetInteger(0, YapiToggleAdi, OBJPROP_YSIZE, 20);
   ObjectSetString(0, YapiToggleAdi, OBJPROP_TEXT, "C/O");
   ObjectSetInteger(0, YapiToggleAdi, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, YapiToggleAdi, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, YapiToggleAdi, OBJPROP_BGCOLOR, clrSilver);
   ObjectSetInteger(0, YapiToggleAdi, OBJPROP_STATE, false);
   ObjectSetInteger(0, YapiToggleAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, YapiToggleAdi, OBJPROP_HIDDEN, true);

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
   // TALGO 4: MA1 (EMA1) cizgisini SIYAH renkte ciz
   // MA1 cizimi devre disi — handle ve hesaplama aktif, gorsel segment yok
   // MAGecmisiCiz(MA1_Handle, MA1_CIZGI_PREFIX, MA1_CizgiRengi);

   MA2_Period = MA2_BaslangicPeriyodu;
   if(!MAEkle(MA2_Period, MA2_Metodu, MA2_FiyatTipi, MA2_Handle, MA2IndikatorAdi))
   {
      Print("HATA: MA2 (degisken sistem kriteri) olusturulamadi.");
      return INIT_FAILED;
   }
   // TALGO 4: MA2 cizgisini KOYU PEMBE renkte ciz
   MAGecmisiCiz(MA2_Handle, MA2_CIZGI_PREFIX, MA2_CizgiRengi);

   PanelOlustur();

   // TALGO 0021: ATR handle olustur ve yapi modulu baslat
   AktifATRCarpani = YapiATRCarpani;
   YapiATRHandle = iATR(_Symbol, PERIOD_CURRENT, YapiATRPeriyodu);
   if(YapiATRHandle == INVALID_HANDLE)
      Print("UYARI: Yapi ATR handle olusturulamadi");
   YapiGecmisiTara();

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
   ObjectDelete(0, ToggleCOAdi); // TALGO 0013

   // TALGO 0021: Yapi paneli ve nesneleri temizle
   ObjectDelete(0, YapiLabelAdi);
   ObjectDelete(0, YapiEditAdi);
   ObjectDelete(0, YapiButonAdi);
   ObjectDelete(0, YapiToggleAdi);
   ObjectsDeleteAll(0, YAPI_ETIKET_PREFIX);
   ObjectsDeleteAll(0, YAPI_KUTU_PREFIX);
   ObjectsDeleteAll(0, YAPI_ZIGZAG_PREFIX);
   if(YapiATRHandle != INVALID_HANDLE)
      IndicatorRelease(YapiATRHandle);

   // TALGO 2: kesisim oklarini da temizle
   ObjectsDeleteAll(0, KESISIM_PREFIX);

   // TALGO 4: MA1/MA2 renkli cizgi segmentlerini de temizle
   ObjectsDeleteAll(0, MA1_CIZGI_PREFIX);
   ObjectsDeleteAll(0, MA2_CIZGI_PREFIX);

   ChartRedraw();
}

//============================================================
// OnChartEvent - MA2 "Uygula" butonuna tiklamayi yakalar
//============================================================
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   // TALGO 0013: C/O toggle butonu tiklandi mi?
   if(sparam == ToggleCOAdi)
   {
      ObjectSetInteger(0, ToggleCOAdi, OBJPROP_STATE, false);
      emaGorunur = !emaGorunur;
      EMAGorunurlukAyarla(emaGorunur);
      Print("EMA gorunurluk toggle: ", (emaGorunur ? "GORUNUR" : "GIZLI"));
      ChartRedraw();
      return;
   }

   // TALGO 0021: Yapi C/O toggle
   if(sparam == YapiToggleAdi)
   {
      ObjectSetInteger(0, YapiToggleAdi, OBJPROP_STATE, false);
      yapiGorunur = !yapiGorunur;
      YapiGorunurlukAyarla(yapiGorunur);
      Print("Yapi gorunurluk: ", (yapiGorunur ? "GORUNUR" : "GIZLI"));
      ChartRedraw();
      return;
   }

   // TALGO 0021: Yapi Apply butonu
   if(sparam == YapiButonAdi)
   {
      ObjectSetInteger(0, YapiButonAdi, OBJPROP_STATE, false);
      string yapiMetin = ObjectGetString(0, YapiEditAdi, OBJPROP_TEXT);
      double yeniCarpan = StringToDouble(yapiMetin);
      if(yeniCarpan < 0.5) yeniCarpan = 0.5;
      if(yeniCarpan > 5.0) yeniCarpan = 5.0;
      AktifATRCarpani = yeniCarpan;
      ObjectSetString(0, YapiEditAdi, OBJPROP_TEXT, DoubleToString(AktifATRCarpani, 1));
      YapiSifirlaVeCiz();
      Print("ATR carpani guncellendi: ", AktifATRCarpani);
      return;
   }

   if(sparam != ButonAdi)
      return;

   // TALGO 2: tiklama gercekten yakalandi mi diye Experts sekmesinden
   // dogrulanabilsin diye log satiri (hangi obje adiyla eslesti)
   Print("MA2 butonuna tiklandi. Eslesen obje adi='", sparam, "' ButonAdi='", ButonAdi, "'");

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
// OnTick - Giris/cikis/filtre mantigi bu adimda YOK.
// Sadece yeni mum olustugunda EMA1/MA2 kesisim gorsellestirmesi
// tetiklenir (TALGO 2).
//============================================================
void OnTick()
{
   datetime suankiMumZamani = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(suankiMumZamani == SonKontrolEdilenMumZamani)
      return; // henuz yeni mum yok, tekrar kontrol etme

   SonKontrolEdilenMumZamani = suankiMumZamani;

   // TALGO 4: MA1/MA2 renkli cizgilerini yeni mumla uzat
   // MA1 cizimi devre disi — handle ve hesaplama aktif, gorsel segment yok
   // MAYeniBarCiz(MA1_Handle, MA1_CIZGI_PREFIX, MA1_CizgiRengi);
   MAYeniBarCiz(MA2_Handle, MA2_CIZGI_PREFIX, MA2_CizgiRengi);

   KesisimKontrolEt();

   // TALGO 0021: Yeni bar'da ATR zigzag kontrolu
   YapiYeniBarIsle();

   ChartRedraw();
}
