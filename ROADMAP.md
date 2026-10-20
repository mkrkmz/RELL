# RELL Roadmap v19 — Kelimeden Cumleye (S0 + 6 sprint)

**Durum: onaylandi (2026-10-19); S0–S4 kapandi; S5 kodlandi (VoiceOver turu ve canli tur bekliyor).**

Olusturulma: 2026-10-19 (1.48.1 sonrasi). Amac: RELL okutuyor ve
kelimeyi hatirlatiyor ama kullandirmiyor. Bu roadmap once mevcut
modullerin yanit kalitesini olcerek iyilestirir, sonra kelimeyi cumleye
tasir (cumle kaydetme, kelimeyle cumle kurma, bolum sonunda anlama
kontrolu, sesli tekrar) ve uygulamayi daha cok kisi icin hazirlar
(yeni arayuz dilleri, gunluk hedef, ekran okuyucu turu). Tek surum:
**1.49.0**. v18 roadmap'i: `docs/archive/ROADMAP-v18.md`.

v18 kapandi: **1.48.0** (2026-10-16) — tek buton ailesi ve tasarim
sistemi denetimi CI'da; moduller Inspector'in kelime kartinda,
hangisinin kartta kalacagi kullanicinin secimi; kendi istemiyle yazilan
moduller; okuma ekraninda yuzen ogeler icin tek yuzey ve uc yer kurali;
tek durum dili, kelime sayfasinda hafiza, canli calisma odasi.
**1.48.1** (2026-10-16): uygulamanin adi RELL, imlec balonu sayfanin
icinde ve kelimenin yaninda, kelime kartinda sozlukten kisa anlam.
Dersler: `NSPopover` verilen dikdortgene sadik kalmadi (olculdu, ~240 pt
sapma); Release derlemesi yalniz Release'te calisan optimizasyonla
coktu, Build is akisi artik Release derliyor; iki yesil calisma bir
dalgali testin cozuldugunu kanitlamaz.

## Durum (2026-10-19, kod taramasi)

| Olcu | Deger |
|---|---|
| Swift dosyasi | 218 (~46.900 satir) |
| Birim testi | 805 |
| Arayuz dili | 2 (Ingilizce, Turkce), 1.540 metin |
| Calisma dili | 12 |
| 860 satiri asan dosya | 5 |
| Kodda TODO / FIXME | 0 |

Modul istemlerinin denetimi (bu roadmap'in S1'i icin):

- **Onbellek baglami bilmiyor (hata).** Anahtar kelime, mod, uzunluk,
  dil ve modelden olusuyor; baglam cumlesi yok. Ayni kelime baska bir
  cumlede secildiginde ilk cumlenin "bu baglamda" aciklamasi geliyor.
- **Onbellek istem surumunu bilmiyor (hata).** Istem degisince diskteki
  onbellek eski yaniti gostermeye devam ediyor.
- **Ogrenci seviyesi kullanilmiyor.** Seviye yalniz ozet, isinma ve
  kendi modullerde var; on yerlesik modulde yok.
- **Baglamdaki anlam eksik.** Ornek, esdizim ve es anlamli modulleri
  cumleyi gormuyor; "bu baglamda" bolumu cogu zaman yalnizca cumleyi
  ceviriyor.
- **Tanim bicimi** sozcuk turu istemiyor; **animsatici** ses benzerligini
  hedef dilde ariyor; **etimoloji** emin olmadiginda koken uydurabiliyor;
  kucuk modeller icin konan token sinirlarinda kesilme olculmedi.

## Teknik cerceve (tum sprintler icin gecerli)

v18 cercevesi aynen devralinir: sifir dis bagimlilik, macOS 15 hedefi,
tam test paketi, async testler, makineye bagli test `XCTSkip`,
`Text(String)` katalogu atlar, xcstrings bos nesne bicimi korunur, DS
token'lari ve denetim testi, bundle id ve veri klasoru degismez; once
maket (her UI sprinti HTML maketle baslar, onaysiz kod yok); her
push'tan sonra Test ve Build; olcumler ayni makinede, temel commit'le
yan yana; testten once calisan RELL varsa komut durur; derlemeler ayri
bir DerivedData klasorune. Eklenenler:

- **Istemler olcerek degisir.** Her istem degisikligi degerlendirme
  setinde eskisiyle yan yana raporlanir; rapor onaylanmadan birlestirilmez.
- **Istem surumu onbellek anahtarinda.** Bir modulun istemi degisince
  surumu artar; eski yanit gosterilmez. Kayitli kelimelerdeki yanitlar
  degismez.
- **Ayristirici etiketleri sabit.** Esdizimlerdeki `*Example:*` /
  `*Translation:*` ve kullanim notlarindaki `FREQ:` / `REG:` /
  `CONFUSE:` / `CAUTION:` Ingilizce kalir; yalniz gorunum yerellesir.
- **FSRS'e yalniz hatirlama yazar.** Cumle kurma, anlama kontrolu ve
  sesli tekrar zamanlamaya dokunmaz; cumle kartinin tekrari yazar.
- **Yeni yapay zeka ozellikleri** gizlilik tablosunda satir alir,
  kuyruga uyar (kullanicinin istedigi once), Apple'in cihaz ici modeline
  yonlendirme olculerek karar verilir.
- **Mikrofon:** ses yalniz cihazda islenir, kaydedilmez, hicbir yere
  gonderilmez; izin istenmeden mikrofon acilmaz.
- **Agir yerel model denemeleri** (buyuk model, paralel uzun is) onceden
  sorulur.

**Bilincli olarak v19 disinda:** dosya ya da iCloud uzerinden esitleme,
karakter ve yer rehberi, altyazi ice aktarma, kenar notlari,
Apple-Developer-kilitli kalemler (notarization, widget, CloudKit), iOS.

---

## Kararlar (2026-10-19)

1. Odak: modullerin kalitesi, ardindan kelimeden cumleye; yaninda
   "herkes icin hazir" kalemleri (esitleme olmadan).
2. Sira: borc (S0), istemler (S1), cumle kaydetme (S2), cumle kurma ve
   anlama kontrolu (S3), sesli tekrar (S4, deneme gecerse), herkes icin
   hazir (S5), kapanis (S6).
3. Sesli tekrar once bir gunluk denemeyle sinanir; imzasiz uygulamada
   izin ya da cihaz ici tanima calismazsa S4 acikca dusurulur.
4. Imlec balonu sozlukten gelen yaniti kelime karti gibi kisa anlamla
   gosterir.
5. Tek surum 1.49.0; acil duzeltmeler yama surumuyle.

---

## Sprint 0 — "Borc" (Must, kisa)

- [x] **Onbellek baglami** — baglami okuyan modullerin (tanim, anlam, es
      anlamlilar, kullanim notlari; kelime modunda) yaniti cumleyle
      birlikte anahtarlanir; digerleri kelimenin butun cumlelerinde ortak
      kalir. Test: ayni kelime iki cumlede, baglamsiz yanit baglamli
      yerine gecmez
- [x] **Istem surumu** onbellek anahtarinda (`PromptTemplates.revision`);
      eski kayitlar surum 0 sayilir ve bir daha gosterilmez
- [x] **Imlec balonu** sozlukten gelen yaniti kelime karti gibi kisa
      anlamla gosterir (ortak `HoverAnswer.shortMeaning`)
- [x] **Buyuk dosyalar** davranis degismeden bolundu: EPUB gorunum
      yoneticisi 1.062 → 614 satir, calisma ekrani 1.049 → 365, PDF
      koordinatoru 921 → 588; yalniz tasinan kodun eristigi uyeler
      `private` olmaktan cikti. Tam paket yesil
- [x] **Buyuk kutuphane olcumu** (`LargeLibraryTests`, istege bagli:
      `RELL_LARGE_LIBRARY=1`; 5.000 kelime, 1.000 sayfalik PDF):

      | Is | Sure |
      |---|---|
      | Kelime deposunu yukle / kaydet | 36 / 38 ms |
      | Defterin kaynaklari ve durumlari | 11 ms |
      | Calisma kuyrugu | 7 ms |
      | Bolum kapsama profili | 11 ms |
      | Bolumu kayitli kelimelere karsi tara (ana thread disinda) | 719 ms |
      | Iki kez kaydedilenleri bul | 633 ms → ana thread disina alindi |
      | 1.000 sayfanin metnini oku (arka planda) | 1,1 sn, tepe ~390 MB |

      Esigi asan tek is iki kez kaydedilenleri bulmakti: kelime defterinde
      ana thread'de calisiyordu, artik arka planda
- [~] **Sesli tekrar denemesi** — kismi: cihaz ici tanima Ingilizce (ABD)
      ve Turkce icin hazir (62 dil destekleniyor; Ingiliz Ingilizcesi,
      Almanca, Fransizca, Ispanyolca icin model indirilmemis). Izin akisi
      ve gercek tanima denenmedi; S4'un ilk isi

## Sprint 1 — "Modullerin kalitesi" (Must)

- [x] **Degerlendirme seti** (30 madde): cok anlamli kelimeler, phrasal
      verb'ler, deyimler, cekimli bicimler, alan terimleri, ana dille
      yaniltici benzerler, kitap cumleleri, uc baska hedef dil (Almanca,
      Ispanyolca, Fransizca) — `PromptEvaluationTests` (istege bagli)
- [x] **Rapor araci** — `scripts/prompt-report.py`: eski ve yeni istem
      yan yana (HTML), otomatik denetimler (dil, bicim, kesilme, giris
      cumlesi) ve ayni modelin anlam yargisi; gecici sunucu hatalarinda
      yeniden deneme. CI'da calismaz
- [x] **Istemler (surum 3)** — kelime modunda her modul cumleyi gorur ve
      o anlam icin yanit verir (onbellek de cumleyle anahtarlar); ogrenci
      seviyesi tanim, ornek ve cumle aciklamasinda; tanim ogrenci sozlugu
      biciminde (sozcuk turu + tek cumle); anlam cumledeki karsilik ve
      gerekcesi (cumle cevirisi degil); animsatici ana dilde anahtar kelime
      yontemiyle ve yaniltici benzeri anlam esi saymadan (Eksikleri Doldur
      da dilini denetler); etimoloji yalniz iyi bilinen koken; sozcuk
      ailesi phrasal verb ve deyimlerde ilgili ifadeler; koseli parantez
      yanita gecmez
- [x] Sonuc (30 madde, ayni bulut modeli, anlam yargisi eski → yeni):
      ornekler 18 → 28/30, esdizimler 21 → 26/29, etimoloji 20 → 24/25,
      animsatici 16 → 22/24, sozcuk ailesi 11 → 15/24; tanim, anlam, es
      anlamlilar, kullanim notlari ayni duzeyde. Butun yanitlar dogru dil
      ve bicimde; yanitlar %10–35 kisa
- [x] **Token sinirlari** — kucuk yerel modelin sinirlariyla etimolojinin
      ucte biri kesiliyordu (70 token); etimoloji ve animsatici 110/160
- [x] Kapi: rapor kullanici onayindan gecti (2026-10-20); tam paket 822
      yesil. Kalan zayiflik: sozcuk ailesi, animsaticilarin bir kismi
      zorlama

## Sprint 2 — "Cumle kaydetme" (Must, **maketle baslar**)

- [x] Secim cubugu, sag tik menusu ve Inspector kartinda "Cumleyi Kaydet"
      (bes kelime ve uzeri secimler, ⌘D); cumle ayni kelime deposunda
      `mode = "Sentence"` ile, kaynagi, cevirisi ve modul yanitlariyla
      saklanir. Ceviri kayit aninda doldurulur (seridin onbellegi ya da
      ceviri servisi); eksikse cumle sayfasinda "Cevir"
- [x] Cumleler yalniz kelimelerin katildigi islerin disinda: seviye
      tahmini, kapsama, alti cizme, karsilasmalar, cift kayit taramasi
- [x] Calisma odasinda dinle-anla karti: once ses, metin bulanik; T metni,
      Bosluk ceviriyi acar, S yeniden okur; 1–4 FSRS'e yazar. Cumleler
      yalniz kart ve asamali oturumlarda sorulur; "Cumleler" kaynagi
- [x] Kelime defterinde "Cumleler" kaynagi; cumle sayfasi: buyuk cumle,
      dinle, ceviri, icindeki kelimeler (kayitlilar durumuyla, digerleri
      "+ Kaydet" ile cumle baglamiyla), hafiza, kaynak
- [x] Anki disa aktarmada cumle karti (on yuz cumle; arka yuz ceviri,
      icindeki kayitli kelimeler ve notlar) ve "Cumleleri dahil et"
- [x] Yedekler ve gizlilik: cumleler kelime dosyasinda, ceviri mevcut
      "Cumle cevirisi" satirinin yolundan gider; yeni dosya ya da hedef yok
- [x] Kapi: tam paket 833 yesil; canli tur kullanici onayindan gecti
      (2026-10-20)

## Sprint 3 — "Kelimeyle cumle kur, okudugunu anla" (Must, **maketle baslar**)

- [x] **Cumle kurma** — calisma odasinda "Cumle Kur" alistirmasi (3 / 5 / 10
      kelime, varsayilan 5; once tekrari bekleyenler) ve kelime sayfasinda
      "Cumle Kur". Kelime, kisa anlami ve kitaptaki cumlesi ustte; model
      duzeltir, fark kelime kelime gosterilir; hukum (dogal / duzeltildi /
      baska anlamda), ana dilde neden ve ayni anlamda dogal bir ornek.
      Hukum modelin soylediginden degil gercek farktan cikar. Duzeltilmis
      cumle tek tikla cumle karti olur. Oturum ozeti: ilk denemede dogal
      olanlar ve en sik duzeltme. Zamanlamaya yazmaz
- [x] Kelime sayfasinda "bu kelimenin gectigi cumleler"
- [x] **Anlama kontrolu** — EPUB'da bolumun sonunda sakin bir teklif
      (400 kelimeden kisa bolumde yok, bolum basina bir kez, ayarlardan
      kapanir); "Bu bolum / Bu sayfa" panelinde her zaman. PDF'te aralik
      oturumun basladigi sayfadan su anki sayfaya, en fazla 12 sayfa, ileri
      hic gitmez. Uc soru (ana fikir, ayrinti, neden), cevap hedef dilde;
      A1–A2'de istege bagli ana dilde (yalniz icerik). Her cevap icin icerik
      hukmu, dil duzeltmesi, dayandigi cumle ve "Kitapta Goster"; kitapta
      birebir bulunmayan alinti gosterilmez. Bos cevap "atlandi" sayilir.
      Son sonuc panelde kalir. Zamanlamaya yazmaz
- [x] Gizlilik tablosunda "Cumle kurma" ve "Anlama kontrolleri"; ikisi de
      etkilesimli kuyrukta, sorular "Basla" ile uretilir (arka planda
      hazirlanmaz). Etiketler (VERDICT / CORRECTED / WHY / EXAMPLE / TOPIC,
      Q1–Q3, ANSWER / NOTE / QUOTE) Ingilizce ve sabit
- [x] Kapi: tam paket 855 yesil; canli tur kullanici onayindan gecti
      (2026-10-20)

## Sprint 4 — "Sesli tekrar" (Should, S0 denemesi gecerse, **maketle baslar**)

- [x] Cumleyi dinle, tekrar et: cumle okunur, bitince mikrofon acilir
      (ayardan kapanir), konusurken duyulan metin canli gorunur; 1,5 sn
      sessizlikte, 6 sn hic ses yoksa ya da 20 sn'de durur. Sonuc kelime
      kelime: dogru (yesil, ✓), atlanan (gri, ustu cizili), farkli duyulan
      (kirmizi, noktali, altinda duyulan). Buyuk/kucuk harf, noktalama ve
      sayinin yazilisi fark sayilmaz; bes harf ve ustu kelimede tek harf
      farki ayni kelime (colour / color). Sesteslerle ilgili not bir kez
- [x] Okuma ekraninda secili cumleden (en az uc kelime): secim cubugunda
      mikrofon, sag tik menusu, Konusma ▸ Secimi Sesli Tekrar Et (⌃⌘R);
      sonuc alt seritte. Calisma odasinda cevrilmis cumle kartinda (R);
      1–4 her zamanki gibi yazar, sesli tekrar yazmaz. Cumle sayfasinda
      "Sesli Tekrar Et" ve son sonuc. Tek kelimelerde yok
- [x] Ses kaydedilmez, yalniz cihaz ici tanima; kayitli cumle yalniz
      sayiyi ve zorlanilan kelimeleri saklar (duyulan metin de saklanmaz).
      Ilk basista RELL'in kendi aciklamasi, sonra macOS'un iki izni.
      Izin reddedilirse ya da dil icin cihaz ici tanima yoksa mikrofon
      gizlenir; Ayarlar ▸ Okuma ▸ Sesli Tekrar'da neden ve cozum yolu.
      Gizlilik tablosunda "Sesli tekrar · Bu Mac"
- [x] Kapi: tam paket 869 yesil; izin akisi ve gercek tanima kullanicinin
      Mac'inde canli turdan gecti (2026-10-20)

## Sprint 5 — "Herkes icin hazir" (Should, **maketle baslar**)

- [x] **Yeni arayuz dilleri** — Ispanyolca ve Almanca, 1.574 metnin
      tamami; bicim belirtecleri betikle ve testle denetlenir. Ayarlar ▸
      Gorunum ▸ Arayuz Dili (Sistem, English, Turkce, Espanol, Deutsch),
      yeniden acilista gecerli, "Simdi Yeniden Baslat". Ana dili konusan
      biri gozden gecirene kadar "beta"; Yardim ▸ "Bir Ceviriyi Duzelt…"
      GitHub'da kisisel bilgi icermeyen bir sablon acar. Izin metinleri de
      uc dilde
- [ ] Ceviri, ana dili Ispanyolca ve Almanca olan biri tarafindan gozden
      gecirilir (beta etiketi o zaman kalkar)
- [x] **Gunluk hedef** — okuma (dakika) ve tekrar (10/20/30/50 kart ya da
      kapali, varsayilan 20); bekleyen kart hedeften azsa hepsi bitince
      tamam. Ana ekranda iki halka, hedef serisi ve son yedi gun (✓ / ½ /
      bos). Seri bundan sonra iki parca tamamlaninca sayilir; onceki gunler
      eski kuralla (okuma), mevcut seri sifirlanmaz. Her gunun durumu
      dakikada bir kaydedilir. Hatirlatma artik yedi ayri gunluk bildirim:
      hedef tamamsa o gun gonderilmez, bugunku kalanini soyler. Menu
      cubugunda "Bugun" satiri
- [x] **Ekran okuyucu turu, kod tarafi** — dokunma hareketiyle calisan 15
      yer VoiceOver'a dugme olarak tanitildi (yakinlastirma yuzdesi, sayfa
      gostergesi, yer imi/not/vurgu satirlari, kartlar, toplu disa
      aktarma); calisma odasinda kart degisince, Inspector'da modul
      yaniti gelince, cumle kurma, anlama kontrolu ve sesli tekrar sonucu
      VoiceOver'a duyurulur. Apple'in otomatik erisilebilirlik denetimi
      istege bagli UI testi olarak (`TEST_RUNNER_RELL_A11Y_AUDIT=1 make
      ui-test`)
- [ ] VoiceOver ile canli tur (kullanici) ve bulunanlarin duzeltilmesi

## Sprint 6 — "Kapanis"

- [ ] Kapanis (Must): tam test, soguk acilis (1.48.1 ile yan yana), canli
      tur, CHANGELOG 1.49.0 + Yenilikler 1.49
- [ ] **1.49.0** yayini (onayla)

---

## Genel dogrulama (her sprint sonu)

Tam test paketi (CI komutuyla birebir, `make ci-test`), regresyon testleri
mutasyonla dogrulanir, push sonrasi Test ve Build (Release) is akislari
yesil, canli tur (RELL acikken ikinci kopya calistirilmaz), xcstrings TR
tamamlama.
