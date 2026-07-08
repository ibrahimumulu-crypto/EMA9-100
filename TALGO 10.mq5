// TALGO 10 - Zigzag Yapi Gorsellestirme
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
#property copyright "TALGO 10"
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
color MA1_CizgiRengi = clrBlack;    // MA1 (EMA1) sabit cizgi rengi
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

// Son swing ve yapi takip degiskenleri
double   SonSwingHighFiyat = 0;
double   SonSwingLowFiyat  = 0;
double   SonHHFiyat = 0;
datetime SonHHZamani = 0;
double   SonLLFiyat = 0;
datetime SonLLZamani = 0;
double   SonLHFiyat = 0;
datetime SonLHZamani = 0;
double   SonHLFiyat = 0;
datetime SonHLZamani = 0;
int      YapiTrendYonu = 0; // 1=yukselis (HH+HL), -1=dusus (LL+LH), 0=belirsiz
ENUM_YAPI_TIPI SonSwingHighTipi = YAPI_YOK;
ENUM_YAPI_TIPI SonSwingLowTipi  = YAPI_YOK;
bool     BOSYukariTetiklendi = false;
bool     BOSAsagiTetiklendi  = false;
bool     MSBYukariTetiklendi = false;
bool     MSBAsagiTetiklendi  = false;

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
}

//============================================================
// TALGO 9: Onaylanan swing noktasini siniflandirir (HH/HL/LL/LH),
// dizilere kaydeder, chart uzerine etiket cizer, BOS/MSB takip
// degiskenlerini gunceller.
//============================================================
void YapiSwingIsle(datetime zaman, double fiyat, int yon, int barIndex)
{
   if(!YapiATRFiltresiGec(fiyat, barIndex))
      return;

   ENUM_YAPI_TIPI tip = YAPI_YOK;

   if(yon == 1)
   {
      if(SonSwingHighFiyat == 0)
         tip = YAPI_HH;
      else
         tip = (fiyat > SonSwingHighFiyat) ? YAPI_HH : YAPI_LH;
      SonSwingHighFiyat = fiyat;
      SonSwingHighTipi = tip;
   }
   else
   {
      if(SonSwingLowFiyat == 0)
         tip = YAPI_HL;
      else
         tip = (fiyat > SonSwingLowFiyat) ? YAPI_HL : YAPI_LL;
      SonSwingLowFiyat = fiyat;
      SonSwingLowTipi = tip;
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

   if(tip == YAPI_HH)
   {
      SonHHFiyat = fiyat;
      SonHHZamani = zaman;
      BOSYukariTetiklendi = false;
   }
   else if(tip == YAPI_LL)
   {
      SonLLFiyat = fiyat;
      SonLLZamani = zaman;
      BOSAsagiTetiklendi = false;
   }
   else if(tip == YAPI_LH)
   {
      SonLHFiyat = fiyat;
      SonLHZamani = zaman;
      MSBYukariTetiklendi = false;
   }
   else if(tip == YAPI_HL)
   {
      SonHLFiyat = fiyat;
      SonHLZamani = zaman;
      MSBAsagiTetiklendi = false;
   }

   if(SonSwingHighTipi == YAPI_HH && SonSwingLowTipi == YAPI_HL)
      YapiTrendYonu = 1;
   else if(SonSwingHighTipi == YAPI_LH && SonSwingLowTipi == YAPI_LL)
      YapiTrendYonu = -1;

   string etiketMetni = "";
   color etiketRenk = clrWhite;
   if(tip == YAPI_HH)      { etiketMetni = "HH"; etiketRenk = clrLime; }
   else if(tip == YAPI_HL) { etiketMetni = "HL"; etiketRenk = clrLime; }
   else if(tip == YAPI_LL) { etiketMetni = "LL"; etiketRenk = clrRed; }
   else if(tip == YAPI_LH) { etiketMetni = "LH"; etiketRenk = clrRed; }

   YapiEtiketCiz(zaman, fiyat, etiketMetni, (yon == 1), etiketRenk);

   // TALGO 10: Onceki swing noktasindan bu noktaya zigzag segmenti ciz
   if(YapiSwingSayisi >= 2)
   {
      int oncekiIdx = YapiSwingSayisi - 2;
      YapiZigzagSegmentCiz(YapiSwingZamanlari[oncekiIdx], YapiSwingFiyatlari[oncekiIdx], zaman, fiyat);
   }
}

//============================================================
// TALGO 9: BOS (Break of Structure) kontrolu. Kapanisin onceki
// HH'yi yukari veya onceki LL'yi asagi kirmasi.
//============================================================
void YapiBOSKontrolEt(int barIndex)
{
   double kapanis = iClose(_Symbol, PERIOD_CURRENT, barIndex);
   datetime zaman = iTime(_Symbol, PERIOD_CURRENT, barIndex);

   if(SonHHFiyat > 0 && !BOSYukariTetiklendi && kapanis > SonHHFiyat)
   {
      YapiBOSCizgiCiz(SonHHZamani, zaman, SonHHFiyat, clrLime);
      BOSYukariTetiklendi = true;
      YapiBOSSayisi++;
      ArrayResize(YapiBOSSeviyeleri, YapiBOSSayisi);
      ArrayResize(YapiBOSZamanlari, YapiBOSSayisi);
      ArrayResize(YapiBOSYonleri, YapiBOSSayisi);
      YapiBOSSeviyeleri[YapiBOSSayisi - 1] = SonHHFiyat;
      YapiBOSZamanlari[YapiBOSSayisi - 1] = zaman;
      YapiBOSYonleri[YapiBOSSayisi - 1] = 1;
   }

   if(SonLLFiyat > 0 && !BOSAsagiTetiklendi && kapanis < SonLLFiyat)
   {
      YapiBOSCizgiCiz(SonLLZamani, zaman, SonLLFiyat, clrRed);
      BOSAsagiTetiklendi = true;
      YapiBOSSayisi++;
      ArrayResize(YapiBOSSeviyeleri, YapiBOSSayisi);
      ArrayResize(YapiBOSZamanlari, YapiBOSSayisi);
      ArrayResize(YapiBOSYonleri, YapiBOSSayisi);
      YapiBOSSeviyeleri[YapiBOSSayisi - 1] = SonLLFiyat;
      YapiBOSZamanlari[YapiBOSSayisi - 1] = zaman;
      YapiBOSYonleri[YapiBOSSayisi - 1] = -1;
   }
}

//============================================================
// TALGO 9: MSB (Market Structure Break) kontrolu.
// Dusus trendinde kapanis > son LH → yukari MSB (trend donusu)
// Yukselis trendinde kapanis < son HL → asagi MSB (trend donusu)
//============================================================
void YapiMSBKontrolEt(int barIndex)
{
   double kapanis = iClose(_Symbol, PERIOD_CURRENT, barIndex);
   datetime zaman = iTime(_Symbol, PERIOD_CURRENT, barIndex);

   if(YapiTrendYonu == -1 && SonLHFiyat > 0 && !MSBYukariTetiklendi && kapanis > SonLHFiyat)
   {
      YapiMSBCizgiCiz(SonLHZamani, zaman, SonLHFiyat);
      MSBYukariTetiklendi = true;
      YapiMSBSayisi++;
      ArrayResize(YapiMSBSeviyeleri, YapiMSBSayisi);
      ArrayResize(YapiMSBZamanlari, YapiMSBSayisi);
      ArrayResize(YapiMSBYonleri, YapiMSBSayisi);
      YapiMSBSeviyeleri[YapiMSBSayisi - 1] = SonLHFiyat;
      YapiMSBZamanlari[YapiMSBSayisi - 1] = zaman;
      YapiMSBYonleri[YapiMSBSayisi - 1] = 1;
   }

   if(YapiTrendYonu == 1 && SonHLFiyat > 0 && !MSBAsagiTetiklendi && kapanis < SonHLFiyat)
   {
      YapiMSBCizgiCiz(SonHLZamani, zaman, SonHLFiyat);
      MSBAsagiTetiklendi = true;
      YapiMSBSayisi++;
      ArrayResize(YapiMSBSeviyeleri, YapiMSBSayisi);
      ArrayResize(YapiMSBZamanlari, YapiMSBSayisi);
      ArrayResize(YapiMSBYonleri, YapiMSBSayisi);
      YapiMSBSeviyeleri[YapiMSBSayisi - 1] = SonHLFiyat;
      YapiMSBZamanlari[YapiMSBSayisi - 1] = zaman;
      YapiMSBYonleri[YapiMSBSayisi - 1] = -1;
   }
}

//============================================================
// TALGO 9: Gecmis barlardaki swing noktalarini tarar, siniflandirir,
// BOS/MSB kontrolu yapar ve chart uzerine cizer. OnInit'te cagrilir.
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
         YapiSwingIsle(mumZamani, fiyat, 1, i);
      }

      if(YapiSwingLowMu(i, YapiSwingN))
      {
         double fiyat = iLow(_Symbol, PERIOD_CURRENT, i);
         YapiSwingIsle(mumZamani, fiyat, -1, i);
      }

      YapiBOSKontrolEt(i);
      YapiMSBKontrolEt(i);
   }

   for(int i = YapiSwingN - 1; i >= 1; i--)
   {
      YapiBOSKontrolEt(i);
      YapiMSBKontrolEt(i);
   }
}

//============================================================
// TALGO 9: Yeni mum olustugunda swing tespiti ve BOS/MSB
// kontrolu yapar. OnTick'te her yeni mumda cagrilir.
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
      YapiSwingIsle(mumZamani, fiyat, 1, kontrolBarIndex);
   }

   if(YapiSwingLowMu(kontrolBarIndex, YapiSwingN))
   {
      double fiyat = iLow(_Symbol, PERIOD_CURRENT, kontrolBarIndex);
      YapiSwingIsle(mumZamani, fiyat, -1, kontrolBarIndex);
   }

   YapiBOSKontrolEt(1);
   YapiMSBKontrolEt(1);
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
   ObjectSetInteger(0, EtiketAdi, OBJPROP_XDISTANCE, 170);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_YDISTANCE, 5);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_COLOR, clrWhite);
   ObjectSetString(0, EtiketAdi, OBJPROP_TEXT, "EMA2 Periyot:");
   ObjectSetInteger(0, EtiketAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_HIDDEN, true);

   ObjectCreate(0, EditAdi, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, EditAdi, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, EditAdi, OBJPROP_XDISTANCE, 146);
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
   ObjectSetInteger(0, ButonAdi, OBJPROP_XDISTANCE, 83);
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
   MAGecmisiCiz(MA1_Handle, MA1_CIZGI_PREFIX, MA1_CizgiRengi);

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
   if(id != CHARTEVENT_OBJECT_CLICK || sparam != ButonAdi)
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
   MAYeniBarCiz(MA1_Handle, MA1_CIZGI_PREFIX, MA1_CizgiRengi);
   MAYeniBarCiz(MA2_Handle, MA2_CIZGI_PREFIX, MA2_CizgiRengi);

   KesisimKontrolEt();

   // TALGO 9: Yapi katmani yeni bar islemesi
   YapiYeniBarIsle();

   ChartRedraw();
}
