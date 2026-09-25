# Faz 3 Issue Listesi

## Sprint 1: Notes Temeli

### 1. PDF highlight ve note veri modelini netlestir
- Efor: M
- Kapsam:
- `PDFNote` icin belge, sayfa, secili metin, not icerigi ve highlight rect bilgileri saklanir
- Belge bazli filtreleme ve siralama store seviyesinde desteklenir
- Kabul kriterleri:
- Note kayitlari uygulama yeniden acildiginda korunur
- Bos veya eksik alanlar uygulamayi bozmaz
- Mevcut note draft akisi persistence ile uyumlu calisir

### 2. Reader icinden not olusturma akisini tamamla
- Efor: M
- Kapsam:
- PDF seciminden `Add Note` ile draft note acilir
- Kullanici secili pasajla birlikte notunu kaydeder
- Kabul kriterleri:
- Context menu uzerinden note olusturma calisir
- Kayit edilen note ilgili PDF ile iliskili gorunur
- Kayit sonrasi secim temizlenir ve kullanici akista kalir

### 3. Sidebar'a belge bazli `Notes` yuzeyi ekle
- Efor: M
- Kapsam:
- Ayrı bir `Notes` sekmesi
- Aktif belge icin note listesi ve note sayaci
- Kabul kriterleri:
- Notes sekmesi aktif PDF'e ait kayitlari listeler
- Bos durumda yonlendirici bir aciklama gorunur
- Note sayisi sidebar uzerinde gorunur

### 4. PDF uzerinde note highlight'larini goster
- Efor: S
- Kapsam:
- Note'a bagli secimler PDF ustunde tekrar vurgulanir
- Kabul kriterleri:
- Ayni belge acildiginda note highlight'lari yeniden cizilir
- Highlight gorunumu secimle karismayacak sekilde ayirt edilebilir olur
- Sayfa gecislerinde annotation senkronu korunur

### 5. Note store icin temel testleri ekle
- Efor: S
- Kabul kriterleri:
- Ekleme, guncelleme, silme senaryolari test edilir
- Belge bazli filtreleme dogrulanir
- JSON encode/decode akisi test altina alinir

## Sprint 2: Notes Deneyimini Guclendirme

### 6. Note kategorileri ekle
- Efor: M
- Kapsam:
- `Vocabulary`, `Insight`, `Review` gibi hafif kategoriler
- Kabul kriterleri:
- Her note varsayilan bir kategoriyle olusur
- Liste ve detay ekraninda kategori gorunur
- Kategori persistence icinde saklanir

### 7. Notes listesine filtre ve arama ekle
- Efor: M
- Kapsam:
- Metin arama
- Kategoriye gore filtreleme
- Belge icinde hizli tarama
- Kabul kriterleri:
- Arama secili belge baglaminda calisir
- Filtre ve arama birlikte kullanilabilir
- Sonuclar buyuk listelerde de akici kalir

### 8. Note detay aksiyonlarini zenginlestir
- Efor: M
- Kapsam:
- Sayfaya don
- `Saved Word` olustur
- Quiz veya review icin isaretle
- Kabul kriterleri:
- Note satirindan ilgili sayfaya donebilme saglanir
- Note icinden ogrenme akislari tetiklenebilir
- Aksiyonlar note verisiyle tutarli calisir

### 9. Reader-note bagini guclendir
- Efor: S
- Kapsam:
- Ayni pasaj icin mevcut note oldugunu gosteren hafif durumlar
- Kabul kriterleri:
- Kullanici yinelenen note riskini fark eder
- Mevcut note varsa ilgili kayda gitmek mumkun olur
- PDF highlight ve notes listesi birbiriyle senkron kalir

### 10. Notes bos durumlarini urunlestir
- Efor: S
- Kabul kriterleri:
- Ilk kullanimda not alma amacini anlatan bos durum bulunur
- Eylem butonu kullaniciyi note olusturmaya yonlendirir
- Bos durum tasarimi mevcut `DS` bilesenleriyle uyumlu olur

## Sprint 3: Workspace ve Devamlilik

### 11. Son acilan belgeler modelini ekle
- Efor: M
- Kapsam:
- Recent documents listesi
- Son acilis zamani
- Belgeye hizli donus
- Kabul kriterleri:
- PDF acildiginda recent listesi guncellenir
- Liste uygulama yeniden acildiginda korunur
- Gecersiz dosya yollarinda uygulama bozulmaz

### 12. `Continue Reading` yuzeyi tasarla
- Efor: M
- Kapsam:
- Empty state veya sidebar icinde son calisma alanina donus
- Kabul kriterleri:
- Kullanici son belgeye tek tikla donebilir
- Son sayfa bilgisi gorunur
- Notes ve saved words ozeti belge kartinda yer alir

### 13. Belge bazli calisma ozeti ekle
- Efor: M
- Kapsam:
- Note sayisi
- Saved words sayisi
- Son calisma tarihi
- Kabul kriterleri:
- Ozet metrikleri aktif belge icin gorunur
- Notes ve ogrenme verisi ayni yerde bulusur
- Dar genislikte de okunabilir kalir

### 14. Kaldigin sayfadan devam et davranisini guclendir
- Efor: S
- Kabul kriterleri:
- Son gorulen sayfa saklanir
- Belge yeniden acildiginda kullanici ayni baglama donebilir
- Bu davranis manuel sayfa degisimleriyle tutarli calisir

### 15. Faz sonu UX rafinmani yap
- Efor: M
- Kapsam:
- Sidebar hiyerarsisi
- Note row gorsel rafinmani
- Daha net bos durumlar ve durum mesajlari
- Kabul kriterleri:
- Yeni notes/workspace yuzeyleri mevcut tasarim sistemiyle uyumlu olur
- Bilgi yogunlugu artarken ekran daginik hissettirmez
- Karanlik ve acik gorunumlerde okunabilirlik korunur

## Onerilen Ilk Paket

Asagidaki 5 issue Faz 3'ün bir sonraki uygulama dalgasi icin en mantikli baslangic paketidir:

1. Note kategorileri ekle
2. Notes listesine filtre ve arama ekle
3. Note detay aksiyonlarini zenginlestir
4. Son acilan belgeler modelini ekle
5. `Continue Reading` yuzeyi tasarla
