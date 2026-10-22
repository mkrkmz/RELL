# RELL Roadmap v20 — Tutarli Temel, Genis Okuma (S0 + 5 sprint)

**Durum: onaylandi (2026-10-22); S0 kodlandi (UI testleri ve canli tur bekliyor).**

Olusturulma: 2026-10-21 (1.49.0 sonrasi). Amac: v19'un eklediklerini
tasarim sisteminin diline oturtmak, ardindan okuma ve konusma
araclarini daha cok kitaba ve dile yaymak. S0, tasarim denetiminin
bulgularindan ve birikmis borctan olusur; sonraki sprintler oneridir ve
siralari onayla kesinlesir. Tek surum: **1.50.0**. v19 roadmap'i:
`docs/archive/ROADMAP-v19.md`.

v19 kapandi: **1.49.0** (2026-10-21) — moduller cumledeki anlam ve
ogrencinin seviyesi icin yanit veriyor (30 maddelik setle olculdu);
cumleler kaydediliyor ve dinlenerek calisiliyor; kelimeyle cumle kurma ve
bolum sonunda anlama kontrolu; cumleyi dinle, sesli tekrar et; Ispanyolca
ve Almanca arayuz (beta); iki parcali gunluk hedef; VoiceOver iyilestirmeleri.
Dersler: okuma penceresinin SwiftUI ortamina eklenen tek bir deger Debug
derlemede soguk acilisa ~200 ms ekledi (commit commit ve deneyle bulundu);
acilis karsilastirmalarinda her derleme ayni bicimde imzalanir; testler
arayuz dilinden bagimsiz yazilir.

## Durum (2026-10-21, kod taramasi)

| Olcu | Deger |
|---|---|
| Swift dosyasi | 247 (~51.100 satir) |
| Birim testi | 884 (95 dosya) |
| Arayuz dili | 4 (Ingilizce, Turkce; Ispanyolca ve Almanca beta), 1.574 metin |
| Calisma dili | 12 |
| 860 satiri asan dosya | 3 (kelime sayfasi 994, kelime deposu 870, kitaplik 865) |
| Kodda TODO / FIXME | 0 |

Tasarim denetimi (2026-10-21): `DESIGN.md` depodaki tasarim sisteminden
cikarildi (lint 0 hata; dtcg disa aktarimi dort kategoriyi uretti). Bes
yuzey kendi tasarim kanitina gore denetlendi: okuma ekrani, Inspector,
calisma odasi, kelime defteri, ana ekran ve kitaplik (Ayarlar da tarandi).
Kanitlanan bulgular ve uygulama planlari `design-plans/` altinda:

| Plan | Bulgu | Yuzey |
|---|---|---|
| 01 | 1.49'da eklenen satir eylemleri (Dinle, Daha Yavas, Yeniden Yaz, Cumleyi Kaydet, Atla, Cumle Kur, Sesli Tekrar Et) cerceveli dugme; kural "satirdaki eylemler sakin" | okuma ekrani, calisma odasi, kelime defteri |
| 02 | Bolum sonu anlama kontrolu teklifi sayfanin altina biniyor; kural "alt serit sayfayi kisaltir, metnin ustune binmez" | okuma ekrani (EPUB) |
| 03 | Dinleme halkasinda ham bosluk degeri (`-5`) | sesli tekrar |
| 04 | Ask AI'daki "Cevabi kopyala" `.plain`; ayni Inspector'daki "Sonucu kopyala" DS ikon dugmesi | Inspector |
| 05 | Sonuc govdesi, yukleme ve bos durum ayni kart kabugunu elle kuruyor | Inspector |

Ana ekran, kitaplik ve Ayarlar'da desteklenen bulgu yok. Denetim disi bir
celiski: `DS.Gradient`'in aciklamasi "uygulamadaki tek uc degrade, gerisi
duz" diyor; v18 S5'te onaylanan calisma odasi ise bant, puan dugmeleri ve
ozet zemininde degrade kullaniyor.

## Teknik cerceve (tum sprintler icin gecerli)

v19 cercevesi aynen devralinir: sifir dis bagimlilik, macOS 15 hedefi,
tam test paketi, async testler, makineye bagli test `XCTSkip`,
`Text(String)` katalogu atlar, xcstrings bos nesne bicimi korunur, DS
token'lari ve denetim testi, bundle id ve veri klasoru degismez; once
maket (her UI sprinti HTML maketle baslar, onaysiz kod yok); her push'tan
sonra Test ve Build; olcumler ayni makinede, temel commit'le yan yana;
testten once calisan RELL varsa komut durur; derlemeler ayri bir
DerivedData klasorune; istemler olcerek degisir ve surumleri onbellek
anahtarinda; ayristirici etiketleri sabit; FSRS'e yalniz hatirlama yazar;
yeni yapay zeka ozellikleri gizlilik tablosunda ve kuyrukta; ses yalniz
cihazda islenir. Eklenenler:

- **`DESIGN.md` tasarimin yazili kaynagi.** Her UI sprintinin maketi ve
  kodu ona gore denetlenir; bir karar degisince once `DESIGN.md`
  guncellenir. Tasarim denetimi her UI sprintinin kapanisinda bir kez
  tekrarlanir (kanitlanmayan bulgu yazilmaz).
- **Yeni bilesen, mevcut dugme ailesiyle.** Satirdaki eylemler `.dsQuiet`,
  ikon dugmeleri `.dsIcon`; sistemin varsayilan cerceveli dugmesi yalniz
  tek basina duran adimda. (1.49'un bulgulari bu kuralin atlanmasindan.)
- **Testler dilden bagimsiz.** Test sureci sabit bir dilde calisir;
  gorunen metni karsilastiran test, metni ayni katalog anahtarindan uretir.
- **Acilis olcumu her sprint kapanisinda.** Onceki surumle yan yana, ayni
  imzayla; ~%10'u asan fark kapanistan once aciklanir.

**Bilincli olarak v20 disinda:** dosya ya da iCloud uzerinden esitleme,
sayfali EPUB, `.apkg` disa aktarma, Apple-Developer-kilitli kalemler
(notarization, widget, CloudKit), iOS.

---

## Kararlar (2026-10-22)

1. **Odak ve sira:** S0 tutarlilik (Must) → S1 okuma araclari → S2
   konusma → S3 yanit kalitesi → S4 yeni kaynaklar ve diller → S5
   kapanis. S1–S4 Should; sprint basinda yeniden tartilir.
2. **Degrade kurali:** degrade yalniz `DS.Gradient`'te ve calisma
   odasinin onayli yuzeylerinde (v18 S5); `DS.Gradient` aciklamasi ve
   `DESIGN.md` buna gore.
3. **Arapca ve Japonca arayuz:** v20'de degil; once Ispanyolca ve
   Almancanin ana dili konusan birince gozden gecirilmesi.

---

## Sprint 0 — "Tutarli temel" (Must)

- [x] **Tasarim denetimi bulgulari** — `design-plans/` 01–05 uygulandi:
      1.49'un satir eylemleri sakin (Dinle, Daha Yavas, Yeniden Yaz,
      Cumleyi Kaydet, Atla, Cumle Kur, Sesli Tekrar Et); bolum sonu
      teklifi alt seritte; dinleme halkasi tokenle; "Cevabi kopyala" DS
      ikon dugmesi; Inspector sonuc yuzeyleri `dsCard`. `WindowLayoutTests`
      yesil
- [x] **`DESIGN.md` depoda** — commit'lendi; gelistirici rehberi ona
      baglandi. `DesignDocumentTests` bosluk ve kose adimlarini, iki sabit
      tonu ve sayfa temasi tablosunu `DS` / `PageTheme` ile karsilastirir
      (mutasyonla dogrulandi)
- [x] **Degrade kurali** — karar 2'ye gore `DS.Gradient` aciklamasi ve
      `DESIGN.md` guncellendi
- [x] **Test dili sabit** — `make test`, `ci-test`, `ui-test` ve CI
      `-testLanguage en -testRegion US` ile; arayuz dili testi uygulamanin
      kendi ayarini okur (calismanin dil argumani onu golgelemez)
- [x] **Buyuk dosyalar** — davranis degismeden bolundu: kelime sayfasi
      994 → 605, kelime deposu 870 → 608, kitaplik 865 → 366; en buyuk
      dosya artik 798 satir
- [ ] **Erisilebilirlik denetimi bir kez** — istege bagli UI testi
      (`TEST_RUNNER_RELL_A11Y_AUDIT=1`) dort ekranda calistirilir;
      cikan bulgular burada duzeltilir ya da S1'e yazilir. Bekliyor: bu
      Mac'te UI testlerinin otomasyon kipi kullanici dogrulamasi istiyor
- [ ] Kapi: tam paket 888 yesil (CI yesil); acilis 1.49.0 ile yan yana ve
      erisilebilirlik denetimi (ikisi de UI testi, kullanici dogrulamasi
      bekliyor); tasarim denetimi okuma ekraninda tekrar; canli tur

## Sprint 1 — "Okuma araclari" (Should, **maketle baslar**)

- [ ] **PDF'te bolumler** — icindekilerden (PDF anahatti) bolum sinirlari;
      bolum hazirligi ve bolum sonu anlama kontrolu PDF'te de calisir.
      Anahatti olmayan PDF bugunku gibi sayfa araligiyla kalir
- [ ] **Karakter ve yer rehberi** — romanlarda kisi ve yer adlari
      (cihaz ici dil etiketleyicisi); kenar cubugunda liste; bir ada
      tiklayinca yalniz o ana kadar okunan kisma dayanan kisa tanim
      (sonrasi hic gonderilmez, anlama kontrolundeki kuralla)
- [ ] Gizlilik tablosunda satir; kuyruk onceligi

## Sprint 2 — "Daha cok dilde konusma" (Should, **denemeyle baslar**)

- [ ] **Deneme** — macOS 26'nin cihaz ici konusma modelleri uygulama
      icinden indirilebiliyor mu (bugun Almanca, Fransizca, Ispanyolca ve
      Ingiliz Ingilizcesi icin model yok, ozellik gizleniyor). Gecmezse
      bugunku "Ayarlar'da nedeni" davranisi kalir ve sprint dikteye daralir
- [ ] **Indirme** — eksik dil icin Ayarlar ▸ Sesli Tekrar'da "Indir";
      tanima yine yalniz cihazda
- [ ] **Dikte alistirmasi** — calisma odasinda cumle kartinin "dinle ve
      yaz" bicimi: cumle okunur, yazilir, fark kelime kelime (sesli
      tekrarin karsilastirmasiyla); alistirma, zamanlamaya yazmaz

## Sprint 3 — "Yanit kalitesi 2" (Should)

- [ ] **Degerlendirme seti diger dillerde** — 30 maddelik setin
      Ispanyolca, Almanca ve Fransizca hedef dil kolu genisletilir; ayni
      rapor araciyla eski / yeni
- [ ] **En zayif iki modul** — sozcuk ailesi (15/24) ve animsatici
      (22/24) istemleri; olculerek, rapor onayindan sonra
- [ ] **Yanit uzunluklari** (v17'den ertelendi) — kaliteyi ayni tutarak
      kisaltma; yerel buyuk modelle her olcum once sorulur

## Sprint 4 — "Yeni kaynaklar, yeni okurlar" (Should, **maketle baslar**)

- [ ] **Altyazi ice aktarma** — `.srt` / `.vtt` dosyasi kitap gibi acilir
      (web makalesiyle ayni yol); zaman damgalari bolum gibi gruplanir
- [ ] **Seviye denemesi** — ilk acilista istege bagli kisa kelime testi
      (evet / hayir); sonuc ogrenci seviyesini ve kapsama hesabinin
      baslangic kumesini onerir. Once Ingilizce; kelime listelerinin
      kaynagi ve lisansi sprint basinda netlesir
- [ ] **Ceviri gozden gecirmesi** — Ispanyolca ve Almanca icin "Bir
      Ceviriyi Duzelt…" ile gelen duzeltmeler islenir; ana dili konusan
      biri gozden gecirince beta etiketi kalkar

## Sprint 5 — "Kapanis"

- [ ] Kapanis (Must): tam test, soguk acilis (1.49.0 ile yan yana, ayni
      imza), tasarim denetimi (degisen yuzeylerde), canli tur, CHANGELOG
      1.50.0 + Yenilikler 1.50 (dort dilde)
- [ ] **1.50.0** yayini (onayla)

---

## Genel dogrulama (her sprint sonu)

- Tam test paketi (`make ci-test`), RELL kapaliyken; CI'da Test ve Build
- Yeni kurallar mutasyonla dogrulanir (duzeltme geri alininca test kirmizi)
- UI sprintlerinde maket onayi, `DESIGN.md`'ye uygunluk ve canli tur
- Yeni metinler dort dilde katalogda; bicim belirtecleri betikle denetlenir
