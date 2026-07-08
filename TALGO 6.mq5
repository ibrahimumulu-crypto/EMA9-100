// TALGO 6 - MA2 Cizgi Rengi BlueViolet
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
#property copyright "TALGO 6"
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
color MA1_CizgiRengi = clrBlack;    // MA1 (EMA1) sabit cizgi rengi
color MA2_CizgiRengi = clrBlueViolet; // MA2 cizgi rengi - periyot degisse de SABIT kalir
int   GecmisCizimBarSiniri = 2000;  // performans icin gecmise donuk cizilecek maksimum bar sayisi

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
   ObjectSetInteger(0, EtiketAdi, OBJPROP_YDISTANCE, 60);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_COLOR, clrWhite);
   ObjectSetString(0, EtiketAdi, OBJPROP_TEXT, "EMA2 Periyot:");
   ObjectSetInteger(0, EtiketAdi, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, EtiketAdi, OBJPROP_HIDDEN, true);

   ObjectCreate(0, EditAdi, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, EditAdi, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, EditAdi, OBJPROP_XDISTANCE, 83);
   ObjectSetInteger(0, EditAdi, OBJPROP_YDISTANCE, 55);
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
   ObjectSetInteger(0, ButonAdi, OBJPROP_YDISTANCE, 80);
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
   ChartRedraw();
}
