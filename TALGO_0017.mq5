// TALGO 0013
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
#property copyright "TALGO 0013"
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

//============================================================
// TALGO 9 - YAPI KATMANI INPUT PARAMETRELERI
// Swing tespiti, gurultu filtresi ve gorsel yapi cizimi ayarlari.
// Bu katman SALT GORSELDiR - mevcut EMA/MA/panel koduna dokunmaz.
//============================================================
input int    YapiSwingN      = 5;    // Swing tespiti icin sag/sol mum sayisi
input double YapiATREsigi    = 0.5;  // ATR gurultu filtresi carpani
input int    YapiATRPeriyodu = 14;   // Yapi katmani ATR periyodu

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

//--- TALGO 9: Yapi katmani (HH/HL/LL/LH + BOS + MSB) global degiskenler
#define YAPI_ETIKET_PREFIX "TALGO9_YapiEtiket_"
#define YAPI_BOS_PREFIX    "TALGO9_YapiBOS_"
#define YAPI_MSB_PREFIX    "TALGO9_YapiMSB_"
#define YAPI_ZIGZAG_PREFIX "TALGO10_YapiZigzag_"

enum ENUM_YAPI_TIPI
{
   YAPI_YOK = 0,
   YAPI_HH  = 1,
   YAPI_HL  = 2,
   YAPI_LL  = 3,
   YAPI_LH  = 4
};

// Swing noktalari dizileri - ileride Sart 3, Cikis 1, trailing stop erisecek
double         YapiSwingFiyatlari[];
datetime       YapiSwingZamanlari[];
int            YapiSwingYonleri[];      // 1=swing high, -1=swing low
ENUM_YAPI_TIPI YapiSwingTipleri[];
int            YapiSwingSayisi = 0;

// BOS verileri - ileride diger moduller erisecek
double         YapiBOSSeviyeleri[];
datetime       YapiBOSZamanlari[];
int            YapiBOSYonleri[];        // 1=yukari, -1=asagi
int            YapiBOSSayisi = 0;

// MSB verileri - ileride diger moduller erisecek
double         YapiMSBSeviyeleri[];
datetime       YapiMSBZamanlari[];
int            YapiMSBYonleri[];        // 1=yukari, -1=asagi
int            YapiMSBSayisi = 0;

// TALGO 11: Bekleyen swing tamponu (alternation enforcement)
int      BekleyenYon     = 0;       // 1=high bekliyor, -1=low bekliyor, 0=bos
double   BekleyenFiyat   = 0;
datetime BekleyenZamani  = 0;
int      BekleyenBarIndex = 0;

// TALGO 11: Onceki onaylanmis swing seviyeleri (siniflandirma icin)
double   OncekiSwingHighFiyat = 0;
double   OncekiSwingLowFiyat  = 0;

// TALGO 11: Trend yonu ve son siniflandirilmis seviyeler
int      YapiTrendYonu = 0; // 1=yukselis (HH+HL), -1=dusus (LL+LH), 0=belirsiz
double   SonHHFiyat = 0; datetime SonHHZamani = 0;
double   SonHLFiyat = 0; datetime SonHLZamani = 0;
double   SonLLFiyat = 0; datetime SonLLZamani = 0;
double   SonLHFiyat = 0; datetime SonLHZamani = 0;

// TALGO 11: MSB tek bayrak (tetiklendikten sonra trend donene kadar reset)
bool     MSBTetiklendi = false;

// TALGO 11: Son zigzag noktasi (trend-uyumlu zigzag icin)
double   SonZigzagFiyat  = 0;
datetime SonZigzagZamani = 0;

// TALGO 0013: EMA gorunurluk toggle
bool     emaGorunur = true;
string   ToggleCOAdi = PANEL_PREFIX + "ToggleCO";
bool     yapiGorunur = true;
string   ToggleGHHAdi = PANEL_PREFIX + "ToggleGHH";

int      YapiATRHandle = INVALID_HANDLE;

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
// TALGO 9: Verilen bar index'inin swing high olup olmadigini kontrol
// eder. Sag ve sol N mumun high degeri bu mumunkinden kucuk olmali.
//============================================================
bool YapiSwingHighMi(int barIndex, int n)
{
   double highDegeri = iHigh(_Symbol, PERIOD_CURRENT, barIndex);
   if(highDegeri == 0) return false;

   for(int j = 1; j <= n; j++)
   {
      if(iHigh(_Symbol, PERIOD_CURRENT, barIndex + j) >= highDegeri)
         return false;
      if(barIndex - j >= 0 && iHigh(_Symbol, PERIOD_CURRENT, barIndex - j) >= highDegeri)
         return false;
   }
   return true;
}

//============================================================
// TALGO 9: Verilen bar index'inin swing low olup olmadigini kontrol
// eder. Sag ve sol N mumun low degeri bu mumunkinden buyuk olmali.
//============================================================
bool YapiSwingLowMu(int barIndex, int n)
{
   double lowDegeri = iLow(_Symbol, PERIOD_CURRENT, barIndex);
   if(lowDegeri == 0) return false;

   for(int j = 1; j <= n; j++)
   {
      if(iLow(_Symbol, PERIOD_CURRENT, barIndex + j) <= lowDegeri)
         return false;
      if(barIndex - j >= 0 && iLow(_Symbol, PERIOD_CURRENT, barIndex - j) <= lowDegeri)
         return false;
   }
   return true;
}

//============================================================
// TALGO 9: ATR gurultu filtresi. Yeni swing ile onceki swing
// arasindaki mesafe ATR x esik degerinden buyuk olmali.
// barIndex: ATR degerini hangi mumdan okuyacagini belirler.
//============================================================
bool YapiATRFiltresiGec(double yeniFiyat, int barIndex)
{
   if(YapiSwingSayisi == 0)
      return true;

   double atrDeger[];
   ArraySetAsSeries(atrDeger, true);
   if(YapiATRHandle == INVALID_HANDLE || CopyBuffer(YapiATRHandle, 0, barIndex, 1, atrDeger) != 1)
      return true;

   double sonFiyat = YapiSwingFiyatlari[YapiSwingSayisi - 1];
   double mesafe = MathAbs(yeniFiyat - sonFiyat);

   return (mesafe >= atrDeger[0] * YapiATREsigi);
}

//============================================================
// TALGO 9: Chart uzerine yapi etiketi (HH/HL/LL/LH) cizer.
// Swing high etiketleri mumun ustunde, swing low mumun altinda.
//============================================================
void YapiEtiketCiz(datetime zaman, double fiyat, string metin, bool usteMi, color renk)
{
   string etiketAdi = YAPI_ETIKET_PREFIX + (string)zaman + "_" + metin;
   if(ObjectFind(0, etiketAdi) >= 0)
      return;

   double bosluk = _Point * 10;
   double etiketFiyat = usteMi ? (fiyat + bosluk) : (fiyat - bosluk);

   ObjectCreate(0, etiketAdi, OBJ_TEXT, 0, zaman, etiketFiyat);
   ObjectSetString(0, etiketAdi, OBJPROP_TEXT, metin);
   ObjectSetInteger(0, etiketAdi, OBJPROP_COLOR, renk);
   ObjectSetInteger(0, etiketAdi, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, etiketAdi, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, etiketAdi, OBJPROP_ANCHOR, usteMi ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, etiketAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, etiketAdi, OBJPROP_HIDDEN, true);
   if(!yapiGorunur)
      ObjectSetInteger(0, etiketAdi, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
}

//============================================================
// TALGO 9: BOS cizgisi - yatay kesikli cizgi (STYLE_DASH).
// Kirilan swing seviyesinden kirilis noktasina kadar.
//============================================================
void YapiBOSCizgiCiz(datetime swingZamani, datetime kirilisZamani, double fiyat, color renk)
{
   string cizgiAdi = YAPI_BOS_PREFIX + (string)kirilisZamani + "_" + DoubleToString(fiyat, _Digits);
   if(ObjectFind(0, cizgiAdi) >= 0)
      return;

   ObjectCreate(0, cizgiAdi, OBJ_TREND, 0, swingZamani, fiyat, kirilisZamani, fiyat);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_COLOR, renk);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_BACK, true);
   if(!yapiGorunur)
      ObjectSetInteger(0, cizgiAdi, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
}

//============================================================
// TALGO 9: MSB cizgisi - yatay kesikli-noktali cizgi (STYLE_DASHDOT).
// Mavi renk, BOS'tan ayirt etmek icin.
//============================================================
void YapiMSBCizgiCiz(datetime swingZamani, datetime kirilisZamani, double fiyat)
{
   string cizgiAdi = YAPI_MSB_PREFIX + (string)kirilisZamani + "_" + DoubleToString(fiyat, _Digits);
   if(ObjectFind(0, cizgiAdi) >= 0)
      return;

   ObjectCreate(0, cizgiAdi, OBJ_TREND, 0, swingZamani, fiyat, kirilisZamani, fiyat);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_STYLE, STYLE_DASHDOT);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, cizgiAdi, OBJPROP_BACK, true);
   if(!yapiGorunur)
      ObjectSetInteger(0, cizgiAdi, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
}

//============================================================
// TALGO 10: Zigzag segment cizer - onceki swing noktasindan yeni
// swing noktasina duz siyah cizgi. Fiyat yapisinin iskeletini gosterir.
//============================================================
void YapiZigzagSegmentCiz(datetime zaman1, double fiyat1, datetime zaman2, double fiyat2)
{
   string segmentAdi = YAPI_ZIGZAG_PREFIX + (string)zaman2;
   if(ObjectFind(0, segmentAdi) >= 0)
      return;

   ObjectCreate(0, segmentAdi, OBJ_TREND, 0, zaman1, fiyat1, zaman2, fiyat2);
   ObjectSetInteger(0, segmentAdi, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, segmentAdi, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, segmentAdi, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, segmentAdi, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, segmentAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, segmentAdi, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, segmentAdi, OBJPROP_BACK, true);
   if(!yapiGorunur)
      ObjectSetInteger(0, segmentAdi, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
}

//============================================================
// TALGO 11: Ham swing tespiti + bekleyen tampon ile alternation
// (high→low→high→low) zorunlulugu. ATR filtresi gecildikten sonra
// swing'i tampona alir veya ayni yonde daha iyi bir swing ile gunceller.
// Farkli yon geldiginde onceki bekleyeni onaylar, yenisini tampona alir.
//============================================================
void YapiHamSwingIsle(datetime zaman, double fiyat, int yon, int barIndex)
{
   if(!YapiATRFiltresiGec(fiyat, barIndex))
      return;

   if(BekleyenYon == 0)
   {
      BekleyenYon = yon;
      BekleyenFiyat = fiyat;
      BekleyenZamani = zaman;
      BekleyenBarIndex = barIndex;
      return;
   }

   if(yon == BekleyenYon)
   {
      if(yon == 1 && fiyat > BekleyenFiyat)
      {
         BekleyenFiyat = fiyat;
         BekleyenZamani = zaman;
         BekleyenBarIndex = barIndex;
      }
      else if(yon == -1 && fiyat < BekleyenFiyat)
      {
         BekleyenFiyat = fiyat;
         BekleyenZamani = zaman;
         BekleyenBarIndex = barIndex;
      }
      return;
   }

   YapiSwingOnayla(BekleyenZamani, BekleyenFiyat, BekleyenYon, BekleyenBarIndex);

   BekleyenYon = yon;
   BekleyenFiyat = fiyat;
   BekleyenZamani = zaman;
   BekleyenBarIndex = barIndex;
}

//============================================================
// TALGO 11: Onaylanan swing noktasini siniflandirir (HH/HL/LL/LH),
// dizilere kaydeder, etiket cizer, trend-uyumlu zigzag cizer,
// BOS kontrolu INLINE yapar (ayri fonksiyon yok).
//============================================================
void YapiSwingOnayla(datetime zaman, double fiyat, int yon, int barIndex)
{
   ENUM_YAPI_TIPI tip = YAPI_YOK;

   if(yon == 1)
   {
      if(OncekiSwingHighFiyat == 0)
         tip = YAPI_HH;
      else
         tip = (fiyat > OncekiSwingHighFiyat) ? YAPI_HH : YAPI_LH;
      OncekiSwingHighFiyat = fiyat;
   }
   else
   {
      if(OncekiSwingLowFiyat == 0)
         tip = YAPI_HL;
      else
         tip = (fiyat < OncekiSwingLowFiyat) ? YAPI_LL : YAPI_HL;
      OncekiSwingLowFiyat = fiyat;
   }

   YapiSwingSayisi++;
   ArrayResize(YapiSwingFiyatlari, YapiSwingSayisi);
   ArrayResize(YapiSwingZamanlari, YapiSwingSayisi);
   ArrayResize(YapiSwingYonleri, YapiSwingSayisi);
   ArrayResize(YapiSwingTipleri, YapiSwingSayisi);
   int idx = YapiSwingSayisi - 1;
   YapiSwingFiyatlari[idx] = fiyat;
   YapiSwingZamanlari[idx] = zaman;
   YapiSwingYonleri[idx] = yon;
   YapiSwingTipleri[idx] = tip;

   if(tip == YAPI_HH)      { SonHHFiyat = fiyat; SonHHZamani = zaman; }
   else if(tip == YAPI_HL) { SonHLFiyat = fiyat; SonHLZamani = zaman; }
   else if(tip == YAPI_LL) { SonLLFiyat = fiyat; SonLLZamani = zaman; }
   else if(tip == YAPI_LH) { SonLHFiyat = fiyat; SonLHZamani = zaman; }

   // Etiket: HH/HL yesil, LL/LH kirmizi — her zaman cizilir
   string etiketMetni = "";
   color etiketRenk = clrWhite;
   if(tip == YAPI_HH)      { etiketMetni = "HH"; etiketRenk = clrLime; }
   else if(tip == YAPI_HL) { etiketMetni = "HL"; etiketRenk = clrLime; }
   else if(tip == YAPI_LL) { etiketMetni = "LL"; etiketRenk = clrRed; }
   else if(tip == YAPI_LH) { etiketMetni = "LH"; etiketRenk = clrRed; }
   YapiEtiketCiz(zaman, fiyat, etiketMetni, (yon == 1), etiketRenk);

   // Trend belirleme ve BOS (inline)
   bool zigzagaDahil = false;

   if(tip == YAPI_HH)
   {
      if(YapiTrendYonu == 1)
      {
         // Yukseliste yeni HH = BOS
         YapiBOSSayisi++;
         ArrayResize(YapiBOSSeviyeleri, YapiBOSSayisi);
         ArrayResize(YapiBOSZamanlari, YapiBOSSayisi);
         ArrayResize(YapiBOSYonleri, YapiBOSSayisi);
         YapiBOSSeviyeleri[YapiBOSSayisi - 1] = fiyat;
         YapiBOSZamanlari[YapiBOSSayisi - 1] = zaman;
         YapiBOSYonleri[YapiBOSSayisi - 1] = 1;
         // BOS etiketi
         string bosAdi = YAPI_BOS_PREFIX + (string)zaman + "_BOS";
         if(ObjectFind(0, bosAdi) < 0)
         {
            double bosluk = _Point * 20;
            ObjectCreate(0, bosAdi, OBJ_TEXT, 0, zaman, fiyat + bosluk);
            ObjectSetString(0, bosAdi, OBJPROP_TEXT, "BOS");
            ObjectSetInteger(0, bosAdi, OBJPROP_COLOR, clrLime);
            ObjectSetInteger(0, bosAdi, OBJPROP_FONTSIZE, 8);
            ObjectSetString(0, bosAdi, OBJPROP_FONT, "Arial Bold");
            ObjectSetInteger(0, bosAdi, OBJPROP_ANCHOR, ANCHOR_LOWER);
            ObjectSetInteger(0, bosAdi, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, bosAdi, OBJPROP_HIDDEN, true);
         }
      }
      zigzagaDahil = (YapiTrendYonu >= 0);
      if(YapiTrendYonu == 0) YapiTrendYonu = 1;
      MSBTetiklendi = false;
   }
   else if(tip == YAPI_HL)
   {
      zigzagaDahil = (YapiTrendYonu == 1);
      MSBTetiklendi = false;
   }
   else if(tip == YAPI_LL)
   {
      if(YapiTrendYonu == -1)
      {
         // Dususte yeni LL = BOS
         YapiBOSSayisi++;
         ArrayResize(YapiBOSSeviyeleri, YapiBOSSayisi);
         ArrayResize(YapiBOSZamanlari, YapiBOSSayisi);
         ArrayResize(YapiBOSYonleri, YapiBOSSayisi);
         YapiBOSSeviyeleri[YapiBOSSayisi - 1] = fiyat;
         YapiBOSZamanlari[YapiBOSSayisi - 1] = zaman;
         YapiBOSYonleri[YapiBOSSayisi - 1] = -1;
         // BOS etiketi
         string bosAdi = YAPI_BOS_PREFIX + (string)zaman + "_BOS";
         if(ObjectFind(0, bosAdi) < 0)
         {
            double bosluk = _Point * 20;
            ObjectCreate(0, bosAdi, OBJ_TEXT, 0, zaman, fiyat - bosluk);
            ObjectSetString(0, bosAdi, OBJPROP_TEXT, "BOS");
            ObjectSetInteger(0, bosAdi, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, bosAdi, OBJPROP_FONTSIZE, 8);
            ObjectSetString(0, bosAdi, OBJPROP_FONT, "Arial Bold");
            ObjectSetInteger(0, bosAdi, OBJPROP_ANCHOR, ANCHOR_UPPER);
            ObjectSetInteger(0, bosAdi, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, bosAdi, OBJPROP_HIDDEN, true);
         }
      }
      zigzagaDahil = (YapiTrendYonu <= 0);
      if(YapiTrendYonu == 0) YapiTrendYonu = -1;
      MSBTetiklendi = false;
   }
   else if(tip == YAPI_LH)
   {
      zigzagaDahil = (YapiTrendYonu == -1);
      MSBTetiklendi = false;
   }

   // Trend-uyumlu zigzag: sadece trende dahil noktalar baglenir
   if(zigzagaDahil && SonZigzagFiyat > 0)
      YapiZigzagSegmentCiz(SonZigzagZamani, SonZigzagFiyat, zaman, fiyat);

   if(zigzagaDahil)
   {
      SonZigzagFiyat = fiyat;
      SonZigzagZamani = zaman;
   }
}

//============================================================
// TALGO 11: MSB (Market Structure Break) kontrolu — mum bazli.
// Yukseliste kapanis < son HL → asagi MSB (trend donusu)
// Dususte kapanis > son LH → yukari MSB (trend donusu)
//============================================================
void YapiMSBKontrolEt(int barIndex)
{
   if(MSBTetiklendi || YapiTrendYonu == 0)
      return;

   double kapanis = iClose(_Symbol, PERIOD_CURRENT, barIndex);
   datetime zaman = iTime(_Symbol, PERIOD_CURRENT, barIndex);

   if(YapiTrendYonu == 1 && SonHLFiyat > 0 && kapanis < SonHLFiyat)
   {
      YapiMSBCizgiCiz(SonHLZamani, zaman, SonHLFiyat);
      MSBTetiklendi = true;
      YapiTrendYonu = -1;
      YapiMSBSayisi++;
      ArrayResize(YapiMSBSeviyeleri, YapiMSBSayisi);
      ArrayResize(YapiMSBZamanlari, YapiMSBSayisi);
      ArrayResize(YapiMSBYonleri, YapiMSBSayisi);
      YapiMSBSeviyeleri[YapiMSBSayisi - 1] = SonHLFiyat;
      YapiMSBZamanlari[YapiMSBSayisi - 1] = zaman;
      YapiMSBYonleri[YapiMSBSayisi - 1] = -1;
      // MSB etiketi
      string msbAdi = YAPI_MSB_PREFIX + (string)zaman + "_MSB";
      if(ObjectFind(0, msbAdi) < 0)
      {
         ObjectCreate(0, msbAdi, OBJ_TEXT, 0, zaman, kapanis);
         ObjectSetString(0, msbAdi, OBJPROP_TEXT, "MSB");
         ObjectSetInteger(0, msbAdi, OBJPROP_COLOR, clrDodgerBlue);
         ObjectSetInteger(0, msbAdi, OBJPROP_FONTSIZE, 9);
         ObjectSetString(0, msbAdi, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, msbAdi, OBJPROP_ANCHOR, ANCHOR_UPPER);
         ObjectSetInteger(0, msbAdi, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, msbAdi, OBJPROP_HIDDEN, true);
      }
   }

   if(YapiTrendYonu == -1 && SonLHFiyat > 0 && kapanis > SonLHFiyat)
   {
      YapiMSBCizgiCiz(SonLHZamani, zaman, SonLHFiyat);
      MSBTetiklendi = true;
      YapiTrendYonu = 1;
      YapiMSBSayisi++;
      ArrayResize(YapiMSBSeviyeleri, YapiMSBSayisi);
      ArrayResize(YapiMSBZamanlari, YapiMSBSayisi);
      ArrayResize(YapiMSBYonleri, YapiMSBSayisi);
      YapiMSBSeviyeleri[YapiMSBSayisi - 1] = SonLHFiyat;
      YapiMSBZamanlari[YapiMSBSayisi - 1] = zaman;
      YapiMSBYonleri[YapiMSBSayisi - 1] = 1;
      // MSB etiketi
      string msbAdi = YAPI_MSB_PREFIX + (string)zaman + "_MSB";
      if(ObjectFind(0, msbAdi) < 0)
      {
         ObjectCreate(0, msbAdi, OBJ_TEXT, 0, zaman, kapanis);
         ObjectSetString(0, msbAdi, OBJPROP_TEXT, "MSB");
         ObjectSetInteger(0, msbAdi, OBJPROP_COLOR, clrDodgerBlue);
         ObjectSetInteger(0, msbAdi, OBJPROP_FONTSIZE, 9);
         ObjectSetString(0, msbAdi, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, msbAdi, OBJPROP_ANCHOR, ANCHOR_LOWER);
         ObjectSetInteger(0, msbAdi, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, msbAdi, OBJPROP_HIDDEN, true);
      }
   }
}

//============================================================
// TALGO 11: Gecmis barlardaki swing noktalarini tarar, alternation
// tamponunu kullanarak siniflandirir, BOS/MSB cizer. OnInit'te cagrilir.
//============================================================
void YapiGecmisiTara()
{
   int barSayisi = Bars(_Symbol, PERIOD_CURRENT);
   int sinir = MathMin(GecmisCizimBarSiniri, barSayisi - 1);
   if(sinir <= YapiSwingN * 2)
      return;

   for(int i = sinir - YapiSwingN; i >= YapiSwingN; i--)
   {
      datetime mumZamani = iTime(_Symbol, PERIOD_CURRENT, i);

      if(YapiSwingHighMi(i, YapiSwingN))
      {
         double fiyat = iHigh(_Symbol, PERIOD_CURRENT, i);
         YapiHamSwingIsle(mumZamani, fiyat, 1, i);
      }

      if(YapiSwingLowMu(i, YapiSwingN))
      {
         double fiyat = iLow(_Symbol, PERIOD_CURRENT, i);
         YapiHamSwingIsle(mumZamani, fiyat, -1, i);
      }

      YapiMSBKontrolEt(i);
   }

   // Son bekleyen swing varsa onayla (gecmis tarama bittiginde flush)
   if(BekleyenYon != 0)
   {
      YapiSwingOnayla(BekleyenZamani, BekleyenFiyat, BekleyenYon, BekleyenBarIndex);
      BekleyenYon = 0;
      BekleyenFiyat = 0;
      BekleyenZamani = 0;
      BekleyenBarIndex = 0;
   }

   // Kalan barlarda MSB kontrolu
   for(int i = YapiSwingN - 1; i >= 1; i--)
      YapiMSBKontrolEt(i);
}

//============================================================
// TALGO 11: Yeni mum olustugunda swing tespiti (alternation ile)
// ve MSB kontrolu yapar. OnTick'te her yeni mumda cagrilir.
//============================================================
void YapiYeniBarIsle()
{
   int barSayisi = Bars(_Symbol, PERIOD_CURRENT);
   if(barSayisi <= YapiSwingN * 2 + 1)
      return;

   int kontrolBarIndex = YapiSwingN;
   datetime mumZamani = iTime(_Symbol, PERIOD_CURRENT, kontrolBarIndex);

   if(YapiSwingHighMi(kontrolBarIndex, YapiSwingN))
   {
      double fiyat = iHigh(_Symbol, PERIOD_CURRENT, kontrolBarIndex);
      YapiHamSwingIsle(mumZamani, fiyat, 1, kontrolBarIndex);
   }

   if(YapiSwingLowMu(kontrolBarIndex, YapiSwingN))
   {
      double fiyat = iLow(_Symbol, PERIOD_CURRENT, kontrolBarIndex);
      YapiHamSwingIsle(mumZamani, fiyat, -1, kontrolBarIndex);
   }

   YapiMSBKontrolEt(1);
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

void YapiGorunurlukAyarla(bool gorunur)
{
   long zamanDilimi = gorunur ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
   int toplam = ObjectsTotal(0, 0, -1);
   for(int i = toplam - 1; i >= 0; i--)
   {
      string ad = ObjectName(0, i, 0, -1);
      if(StringFind(ad, YAPI_ETIKET_PREFIX) == 0 ||
         StringFind(ad, YAPI_BOS_PREFIX) == 0 ||
         StringFind(ad, YAPI_MSB_PREFIX) == 0 ||
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

   ObjectCreate(0, ToggleGHHAdi, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, ToggleGHHAdi, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, ToggleGHHAdi, OBJPROP_XDISTANCE, 63);
   ObjectSetInteger(0, ToggleGHHAdi, OBJPROP_YDISTANCE, 50);
   ObjectSetInteger(0, ToggleGHHAdi, OBJPROP_XSIZE, 40);
   ObjectSetInteger(0, ToggleGHHAdi, OBJPROP_YSIZE, 20);
   ObjectSetString(0, ToggleGHHAdi, OBJPROP_TEXT, "GHH");
   ObjectSetInteger(0, ToggleGHHAdi, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, ToggleGHHAdi, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, ToggleGHHAdi, OBJPROP_BGCOLOR, clrSilver);
   ObjectSetInteger(0, ToggleGHHAdi, OBJPROP_STATE, false);
   ObjectSetInteger(0, ToggleGHHAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, ToggleGHHAdi, OBJPROP_HIDDEN, true);

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

   // TALGO 9: Yapi katmani ATR handle'i olustur ve gecmisi tara
   YapiATRHandle = iATR(_Symbol, PERIOD_CURRENT, YapiATRPeriyodu);
   if(YapiATRHandle == INVALID_HANDLE)
      Print("UYARI: Yapi katmani ATR handle olusturulamadi, gurultu filtresi devre disi.");
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
   ObjectDelete(0, ToggleGHHAdi);

   // TALGO 2: kesisim oklarini da temizle
   ObjectsDeleteAll(0, KESISIM_PREFIX);

   // TALGO 4: MA1/MA2 renkli cizgi segmentlerini de temizle
   ObjectsDeleteAll(0, MA1_CIZGI_PREFIX);
   ObjectsDeleteAll(0, MA2_CIZGI_PREFIX);

   // TALGO 9: Yapi katmani nesnelerini ve ATR handle'ini temizle
   ObjectsDeleteAll(0, YAPI_ETIKET_PREFIX);
   ObjectsDeleteAll(0, YAPI_BOS_PREFIX);
   ObjectsDeleteAll(0, YAPI_MSB_PREFIX);
   // TALGO 10: Zigzag segmentlerini temizle
   ObjectsDeleteAll(0, YAPI_ZIGZAG_PREFIX);
   if(YapiATRHandle != INVALID_HANDLE)
      IndicatorRelease(YapiATRHandle);

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

   if(sparam == ToggleGHHAdi)
   {
      ObjectSetInteger(0, ToggleGHHAdi, OBJPROP_STATE, false);
      yapiGorunur = !yapiGorunur;
      YapiGorunurlukAyarla(yapiGorunur);
      Print("Yapi gorunurluk toggle: ", (yapiGorunur ? "GORUNUR" : "GIZLI"));
      ChartRedraw();
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

   // TALGO 9: Yapi katmani yeni bar islemesi
   YapiYeniBarIsle();

   ChartRedraw();
}
