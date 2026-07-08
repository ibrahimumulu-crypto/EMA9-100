# Proje Kuralları — MT5 EA Geliştirme

## Genel Metodoloji
- Bu projede brick-by-brick (tuğla üstüne tuğla) yöntemiyle ilerliyoruz.
- Her adım onaylanmadan bir sonrakine geçilmez.
- Her onaylı değişiklik bir versiyon numarası alır: V0001, V0002, ... (format: V0001 05350 EMA)

## Kod Değişikliği Kuralları
- Mevcut kodu ASLA baştan yazma (overwrite/create) yapma.
- Sadece istenen değişikliği ilgili fonksiyon/blok içinde yap (edit).
- Değişiklik dışındaki kodu, değişken isimlerini, yorum stilini bire bir koru.
- Eğer büyük bir yeniden yapılandırma gerçekten gerekliyse, önce nedenini açıkla ve onay iste — onay almadan dosyanın tamamını değiştirme.
- Yapılan her değişikliği kısaca özetle: ne değişti, nerede değişti.

## Dil ve Stil
- Tüm değişken, fonksiyon ve yorum isimleri Türkçe olacak.
- MT5 float/point hassasiyetine dikkat: StopLevel buffer +10 point kullan (önceki bug fix referans).

## Kapsam
- Her prompt'ta sadece belirtilen modül/katman kodlanır, başka hiçbir strateji mantığına (giriş/çıkış/filtre/stop) dokunulmaz, aksi belirtilmedikçe.
