# EMA Project - Expert Advisor Gelistirme Dokumani

## Aktif Dosya
- **Dosya adi:** `05-100 EMA 1R-3R V.0.0.0.4.mq5`
- **Platform:** MetaTrader 5 (MQL5)
- **Son versiyon:** v10

## Mevcut Ozellikler

### Strateji
- 5 EMA ile 100 EMA kesisim sistemi (MODE_EMA)
- BUY: Kesisim aninda fiyat 100 EMA ustundeyse
- SELL: Kesisim aninda fiyat 100 EMA altindaysa
- Kesisim tespiti her tick'te anlik yapilir (bar 0 vs bar 1)
- Ayni bar icinde tekrar giris engellenir (lastCrossBar)

### Zaman Dilimi
- SADECE M3 (3 dakikalik) grafikte calisir
- Baska zaman dilimine eklenirse Alert verir ve durur

### Calisma Saatleri
- Islem acma: 07:00 - 23:00 (UTC+3 Istanbul)
- Son 30 dakika (23:00-23:30) yeni islem acilmaz (NoTradeBeforeClose)
- 23:30'da tum acik pozisyonlar otomatik kapatilir
- TimeGMT() + 3*3600 ile UTC+3 hesaplanir
- UseLocalTime=false yapilirsa sunucu saati kullanilir

### Stop Loss (ATR Bazli)
- SL mesafesi = ATR(14) x 2.0
- Maksimum kayip islem basina 10 USD (SL_Dollars)
- ATR SL > 10 USD ise lot otomatik kucultulur
- Formul: lot = SL_Dollars / ((slDist / tickSize) * tickVal)
- SYMBOL_TRADE_TICK_VALUE ve SYMBOL_TRADE_TICK_SIZE kullanilir

### Take Profit
- SL mesafesinin 3 kati (1:3 Risk/Odul)
- TP = 30 USD kar (SL 10 USD ise)

### Risk Yonetimi
- Gunluk maksimum kayip: 40 USD (DailyMaxLoss)
- Limit asilinca tum pozisyonlar kapatilir, gun boyunca islem acilmaz
- Zarar hesabi: kapanmis deal P/L + acik pozisyon floating P/L + swap + commission
- HistorySelect ile gunun deal'leri alinir
- Sayac her gun 07:00'da (seans baslangici) sifirlanir

### Islem Limiti
- Ayni anda maksimum 6 acik islem (tum semboller dahil, Magic Number bazli)
- _Symbol kontrolu yok, sadece MagicNumber ile filtrelenir

### Input Parametreleri
```
LotSize           = 0.1
MagicNumber       = 924100
MA_Fast_Period    = 5
MA_Slow_Period    = 100
ATR_Period        = 14
ATR_Multiplier    = 2.0
SL_Dollars        = 10.0
RR_Ratio          = 3.0
MaxOpenTrades     = 6
DailyMaxLoss      = 40.0
StartHour         = 7
StartMinute       = 0
EndHour           = 23
EndMinute         = 30
NoTradeBeforeClose = 30
UseLocalTime      = true
```

## Versiyon Gecmisi

| Versiyon | Degisiklik |
|----------|-----------|
| v1 | Ilk EA - 9/100 SMA kesisim |
| v2 | M3 zaman dilimi kisitlamasi |
| v3 | Otomatik pip hesabi (digits bazli) |
| v4 | Gunluk zarar limiti (HistorySelect + floating P/L) |
| v5 | Calisma saatleri 07:00-23:30, UTC+3 destegi |
| v6 | Anlik kesisim tespiti (bar 0-1, IsNewBar kaldirildi) |
| v7 | SMA->EMA duzeltmesi, MA tipi secilebilir |
| v8 | MaxTrades=6, RR=1:2, DailyMaxLoss=40 |
| v9 | Dolar bazli SL (pip yerine 10 USD sabit) |
| v10 | ATR bazli SL, otomatik lot kucultme, 5/100 EMA, son 30 dk yasagi |

## Kontrol Sirasi (Her Tick)
1. Saat 07:00-23:00 arasinda mi?
2. Gunluk zarar < -40 USD mi?
3. Acik islem < 6 mi?
4. 5 EMA <-> 100 EMA kesisimi var mi?
5. Fiyat 100 EMA ustunde mi altinda mi?
6. Tumune uygunsa -> islem ac
