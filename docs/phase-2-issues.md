# Faz 2 Issue Listesi

## Sprint 1: Ogrenme Cekirdegi

### 1. `SavedWord` modeline review alanlari ekle
- Efor: M
- Alanlar: `lastReviewedAt`, `reviewCount`, `incorrectCount`, `nextReviewAt`
- Kabul kriterleri:
- Mevcut kayitli kelimeler bozulmadan decode edilir
- Yeni alanlar JSON persistence icinde saklanir
- Varsayilan degerlerle geriye donuk uyumluluk korunur

### 2. Review hesaplama mantigini `SavedWordsStore` icine tasi
- Efor: M
- Kabul kriterleri:
- `Again`, `Good`, `Easy` sonuclari tek merkezden uygulanir
- `pending review`, `reviewed today`, `mastered words` sayilari store uzerinden alinabilir
- Quiz ve liste ayni review kurallarini kullanir

### 3. Saved Words ekranina `Needs Review` filtresi ekle
- Efor: S
- Kabul kriterleri:
- `All`, `Needs Review`, `New`, `Mastered`, `This PDF` filtreleri bulunur
- Arama ve filtre birlikte calisir
- Due kelimeler kullaniciya net sekilde gorunur

### 4. Quiz sonuclarini review durumuna bagla
- Efor: M
- Kabul kriterleri:
- Quiz cevabi kelimenin review alanlarini gunceller
- `Again` verilen kelimeler tekrar kuyruguna doner
- Oturum sonunda temel review ozeti gosterilir

### 5. Stats ekranina ogrenme metrikleri ekle
- Efor: M
- Kabul kriterleri:
- `Reviewed today`, `Pending review`, `Mastered words` metrikleri gorunur
- Okuma istatistikleri korunur
- Dar sidebar genisliginde okunabilir kalir
