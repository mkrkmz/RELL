# RELL Roadmap v14 — Ayni Ozellikler, Cok Daha Iyi Bir Uygulama (S0 + 4 sprint)

Olusturulma: 2026-10-01 (v1.42.0 sonrasi). Kullanici karari: **yeni ozellik
yok** — mevcut ozellikleri daha kullanisli ve estetik bir arayuzle sunmak,
deneyimi ust seviyeye cikarmak ve uygulamayi saglamlastirmak. Golgeleme v14'te
yok (kullanici karari). v13 roadmap'i: `docs/archive/ROADMAP-v13.md`.

v13 kapandi: S0–S5 tek surum olarak **v1.42.0** (2026-10-01) — Swift 6 modu,
karsilasma gunlugu + kelime sayfasi + baglam rotasyonlu cloze, donuste ozet,
bolum hazirligi, Bugun ekrani, satir arasi anlamlar, seviyene gore
sadelestirme, yeniden anlatma, web makalesi ice aktarma, kelimelerinden
hikaye, komut paleti, dilbilgisi mercegi, menu cubugu/bildirim tekrari, test
izolasyonu. 608 test. Surum notlari artik CHANGELOG'dan "What's new" ile
basliyor; eski 42 surum geriye donuk guncellendi.

**v13'un dersleri (bu roadmap'in sebebi):** ozellikler calisiyor ama
kullanici bazilarini **bulamadi** (Sadelestir/Yeniden Anlat yalniz 6+
kelimelik secimde 7 adsiz ikonlu bir cubukta); arayuz **kalabaliklasti**
(baglam seridinde 8 oge, Inspector'da 6 katman); Inspector'in sabit bolgesi
**iki kez cokme** uretti (AppKit constraint dongusu); kodun tamami ilk kez
yayin push'unda CI'da derlendi ve **CI'in Xcode 26.3'u** yerelde gecen iki
hatayi yakaladi; sprintlerin ucunde canli tur yapilamadi (ekran kilitli).

## Denetim (2026-10-01, kod + canli tur ekran goruntuleri)

| Alan | Bulgu |
|---|---|
| Kesfedilebilirlik | Sadelestir/Yeniden Anlat yalniz secim cubugunda (sonradan ⌘K'ye eklendi). Zen/Odak/Anlamlar paletten ve bazi menulerden eksik. Onboarding v13 ozelliklerinin hicbirini tanitmiyor; uygulama icinde "Yenilikler" yok |
| Okuyucu kabugu | Baglam seridi: belge, konum+sure, hazirlik cipi, not, kayit, bekleyen, bilinen %, secim ozeti — tek satirda, sag kenarda kesiliyor. Secim cubugu 5–7 adsiz ikon |
| Inspector | Kart/baslik + kontrol seridi + son terimler + modul izgarasi + sonuc + Ask AI ust uste; yalniz sonuc paneli esniyor → sabit bolge kirilgan (v13'te 2 cokme) |
| Araclar | Sadelestir, Yeniden Anlat, Hikaye, Ice Aktar dort ayri sheet + farkli menuler; ortak bir "araclar" yeri yok |
| Gorsel tutarlilik | Koyu Inspector ile acik sayfa temasi yan yana; kartlarda karisik dolgu/gradyan; 41 sabit sayili padding, 3 ham font |
| Ayarlar | Genel sekmesi 10 bolum, 8 anahtar — okuma, ogrenme, AI ve veri karisik |
| Erisilebilirlik | 334 dugmeye karsilik 47 `accessibilityLabel`; ikon dugmelerinin bir kismi VoiceOver'da adsiz. Klavye ile gezinme denetlenmedi |
| Kod sagligi | 1.000+ satirlik 4 dosya (EPUBViewManager 1076, EPUBReaderView 1035 — cogu gomulu JS, PDFKitView 1005, QuizView 937) |
| Surec | CI ile yerel derleyici farki (26.3 / 27); surum notu is akisi uctan uca denenmedi; performans hic olculmedi |

## Teknik cerceve (tum sprintler icin gecerli)

v13 cercevesi aynen devralinir (sifir dis bagimlilik, macOS 15 hedefi, tam
test paketi, async testler, makineye bagli test `XCTSkip`, persistence ve LLM
kurallari, `Text(String)` katalogu atlar, DS token'lari, bundle id/sandbox'a
dokunulmaz). Eklenenler:

- **Once tasarim, sonra kod.** Her UI sprinti, degisecek ekranlarin onceki/
  sonraki halini gosteren bir **gorsel maket** (HTML artifact) ile baslar;
  kullanici onaylamadan kod yazilmaz. Maket DS token'larinin gercek
  degerleriyle cizilir.
- **Yeni ozellik yok.** Bir ekran yeniden duzenlenirken davranis korunur;
  ozellik ekleme/cikarma yalniz kullanici karariyla. Bir ozelligin yeri
  degisirse eski yolu bir surum boyunca calismaya devam eder (menu, kisayol).
- **Sutunlarda yerlesim kurali (v13 dersi):** Inspector, okuyucu ve kenar
  cubugu gibi AppKit'in boyutlandirdigi sutunlarda yuksekligi degisen her
  icerik ya esnek bolgede ya da `maxHeight`'li bir `ScrollView`'dadir;
  genislige gore boyut degistiren ozel `Layout` yalniz sabit genislikli
  sheet'lerde. Her yeniden duzenlenen yuzey icin **"pencereyi buyutmez"**
  testi (S0'daki yardimci ile).
- **Her sprint sonu:** `main` push edilir ve CI testi (Xcode 26.x) gecmeden
  sprint kapanmaz; kullanici **canli turu** sprint icindeki bir kontrol
  listesiyle yapar.
- **Erisilebilirlik varsayilan:** yeni ya da yeniden duzenlenen her ikon
  dugmesinin `accessibilityLabel`'i ve `.help`'i olur; renk tek bilgi
  tasiyicisi degildir; ana akislar klavyeyle yapilabilir.
- Yeni kullanici metinleri TR ile; surum notu CHANGELOG bolumunden uretilir —
  CHANGELOG kullaniciya yazilir ve tag'den once commit'lenir.

**Bilincli olarak v14 disinda:** Golgeleme, cumle kaydetme, kelime haritasi,
karakter rehberi, okuma cetveli ve diger yeni ozellikler (fikir havuzunda);
iOS; Apple-Developer-kilitli kalemler (notarization, widget, App Group,
CloudKit).

---

## Sprint 0 — "Zemin" (Must, kisa)

Amac: UI degisikliklerini guvenle yapabilmek icin olcum ve guvenlik agi.

- [x] **Yerlesim dongusu korumasi** — `LayoutGuard.settledHeight`: gorunumu
      sabit boyutlu bir pencerede barindirir, pencerenin buyuyup buyumedigini
      olcer. **Ilk uygulamada gizli bir cokme buldu:** Inspector'in tamami
      cumle seciliyken en az 638 pt, kelimede 492 pt istiyordu; en kucuk
      pencere (600 pt) sutuna ~548 birakir → pencere kucultulunce cokme.
      Duzeltme: `ViewThatFits` — sigarsa bugunku duzen, sigmazsa ayni icerik
      tek ScrollView'da (sonuc paneli 260 pt). Testler: Inspector (cumle,
      kelime), Dilbilgisi; duzeltmeden once dusuyorlardi. Baglam seridi ve
      secim cubugu S1'de yeniden yapilirken eklenecek
- [x] **Performans tabani** — `PerformanceBaselineTests` (olcer, esik
      koymaz; fixture'lar kodda uretilir). Taban (2026-10-01, Debug, gelistirici
      Mac'i, 5 tekrar ortalamasi):

      | Is | Sure |
      |---|---|
      | 40 bolumluk EPUB'i ac + her bolumun metni | 21 ms (tepe bellek ~91 MB) |
      | 277 sayfalik PDF'i ac + 20 sayfa metni | 17 ms |
      | Bir bolumu 1.000 kayitli kelimeye karsi tara (karsilasma) | 140 ms ¹ |
      | Bolum kapsama profili | 10 ms |
      | Bolum hazirligi adaylari | 14 ms |
      | 1.000 kelimelik kelime deposunu yukle | 5 ms |
      | Uzun bir makaleyi ayikla | 31 ms |
      | Soguk acilis (UI testi) | olculmedi ² |

      ¹ Ana thread disinda, okunan sayfa basina bir kez — sorun degil; maliyet
      her taramada kelimelerin kok anahtarlarinin yeniden hesaplanmasi
      (onbellege alinabilir). ² XCUITest, ayni bundle id'li calisan
      uygulamayi kapatir — kullanicinin acik RELL'i varken kosulmaz. UI
      testleri artik `-RELLTestHost` ile acilir (gecici veri)
- [x] **CI esitligi** — `make ci-test` CI'daki komutun aynisi (macOS 15 hedefi,
      temiz derleme klasoru). CONTRIBUTING: sprint sonu kurali, Xcode 26.3'un
      reddettigi iki kalip, sutun yerlesim kurali
- [x] **Surum notu is akisinin uctan uca denenmesi** — elle tetiklenen
      calisma da `release_notes.md` uretip artifact olarak yukluyor (adim
      artifact yuklemesinin onune alindi). v1.42.0 uzerinde denendi: not
      "What's new in RELL 1.42.0" ile basliyor, DMG derlendi, surum sayfasi
      degismedi
- [x] **Kod sagligi** — okuyucunun 5 betigi `Reader/EPUB/Scripts/*.js`'e
      tasindi: her betigin calisma zamanindaki metni dokulup paketteki
      dosyayla bayt bayt karsilastirildi (kacis degismedi); EPUBReaderView
      1.035 → 451 satir. PDFKitView Coordinator'i ayri dosyada (1.005 → 91 +
      931). Yeni test: betikler pakette ve Swift'in cagirdigi fonksiyonlari
      tanimliyor
- [x] Dogrulama: `make ci-test` 618 test, 0 hata; CI (Xcode 26.x) 618 test,
      0 hata, 7 atlanan (makineye bagli)
- [ ] **Canli tur (kullanici)** — (1) pencereyi en kucuk boyuta getirip uzun
      bir cumle sec: Inspector cokmeden kaydirilabilir olmali; normal boyutta
      gorunum degismemeli. (2) EPUB'da betik tasimasinin etkiledigi her sey:
      kayitli kelime alt cizgisi, vurgular, uzerine gelme sozlugu, secim
      cubugu, karaoke (Seslendir), ⌥⌘G anlamlar
- [ ] Soguk acilis olcumu — kullanicinin RELL'i kapaliyken `make ui-test`

## Sprint 1 — "Okuyucu kabugu" (Must)

Amac: sayfa disindaki her sey sakinlessin; okuyucu sayfaya odaklansin,
araclar istenince bulunabilsin. **Maketle baslar.**

- [ ] **Baglam seridi** — iki bolge: solda belge + konum (bolum/sayfa, %,
      kalan sure), sagda tek bir "bu bolum" hapi (hazirlik, bilinen %,
      bekleyen); tiklayinca hepsini gosteren bir panel. Sayaclar (not, kayit)
      kenar cubuguna. Dar pencerede kesilmez
- [ ] **Secim cubugu** — birincil eylemler etiketli (Kaydet, Analiz), digerleri
      tek bir "Araclar" menusunde gruplu ve **adlariyla** (Sadelestir, Yeniden
      Anlat, Vurgula ▸ renkler, Seslendir, Kopyala). Pasaj araclari kisa
      secimde gorunur ama pasif ve nedenini soyler
- [ ] **Sag tik menusu** — secim cubuguyla ayni eylemler, ayni sirada (bugun
      PDF ve EPUB menuleri farkli)
- [ ] **Odak/Zen/anlamlar tutarliligi** — Gorunum menusu, ⌘K ve Zen cubugu ayni
      komut setini gosterir; eksikler tamamlanir
- [ ] Testler: "pencereyi buyutmez" (serit, cubuk), menu/palet komut esitligi

## Sprint 2 — "Inspector" (Must)

Amac: Inspector'u bir **calisma alani** yapmak: once kelime, sonra derinlik;
cumle secildiginde o cumle icin araclar. **Maketle baslar.**

- [ ] **Bilgi mimarisi** — kelime secimi: kelime karti (ust) → hizli eylemler
      (kaydet, dinle, Anki) → "Aciklamalar" (modul cipleri + sonuc) → Ask AI.
      Ifade/cumle secimi: cumle + ceviri → "Araclar" (Dilbilgisi, Sadelestir,
      Yeniden Anlat) → modul sonucu
- [ ] **Modul izgarasi** — sik kullanilan modullerin gorunur, digerlerinin
      "Daha fazla" altinda olmasi; otomatik calistirma ayari ayni kalir
      (v13'te kullanici kararina birakilmisti — maket asamasinda onaylanir)
- [ ] **Sonuc okunabilirligi** — modul ciktilarinda baslik/govde tipografisi,
      ornek cumlelerde kelime vurgusu, kopyala/kaydet eylemleri tek yerde
- [ ] **Saglamlik** — tum sabit bolge yeni kurala gore (esnek ya da sinirli
      ScrollView); her bolum icin "pencereyi buyutmez" testi
- [ ] **Tema uyumu** — Inspector arka plani sayfa temasini izleyebilir (ayar;
      varsayilan sistem gorunumu)

## Sprint 3 — "Ana ekran, kitaplik ve kelimeler" (Should)

Amac: uygulamayi acinca ne yapilacagi, nereye gidilecegi tek bakista;
araclar bir yerde. **Maketle baslar.**

- [ ] **Bugun = merkez** — kaldigin yer, bugunun tekrarlari, okuma hedefi ve
      bir **"Araclar"** satiri (Makale ice aktar, Kelimelerinden hikaye,
      Tekrar penceresi) — daginik sheet'lere tek giris
- [ ] **Kitaplik** — kapak izgarasi/liste gecisi, zorluk/kapsama rozeti,
      koleksiyonlar daha gorunur; ice aktarilan makaleler ve hikayeler ayri
      rafta ("Makaleler", "Hikayeler")
- [ ] **Kelimeler** — liste satirlari sadelesir (durum, seviye, son
      karsilasma), filtreler tek satirda; kelime sayfasi kenar cubugundan da
      acilir
- [ ] **Bos durumlar** — her bos ekran ne yapilacagini soyler ve tek eylem
      sunar
- [ ] **Yenilikler** — guncellemeden sonraki ilk acilista kisa bir "Bu
      surumde" sayfasi (CHANGELOG ozetinden, TR)

## Sprint 4 — "Cila: ayarlar, tanitim, erisilebilirlik" (Should)

Amac: ilk acilistan Ayarlar'a kadar butunluk; herkes icin kullanilabilirlik.

- [ ] **Ayarlar** — Genel bolunur: Okuma, Ogrenme (seviye, ozet, hazirlik,
      anlamlar), AI (saglayici, cihaz-ici, gizlilik), Veri (yedekler);
      `@AppStorage` anahtarlari degismez
- [ ] **Tanitim** — onboarding'e okuma dongusunu gosteren kisa tur (sec →
      anla → kaydet → tekrar), atlanabilir; Yardim menusunden tekrar acilir
- [ ] **Erisilebilirlik turu** — tum ikon dugmeleri etiketli; VoiceOver ile ana
      akis (belge ac → kelime sec → kaydet → tekrar) bastan sona; klavye
      odagi Inspector ve sheet'lerde; kontrast (tum sayfa temalari)
- [ ] **Gorsel tutarlilik** — kart stilleri ve vurgu gradyani tek kaliba;
      sabit padding'ler ve ham fontlar DS token'larina; acik/koyu ve 6 sayfa
      temasinda ekran gorselleriyle kontrol
- [ ] **Turkce metin turu** — gorunen tum metinlerin TR karsiligi gozden
      gecirilir (kisa, tutarli terimler)
- [ ] Kapanis: tam test, performans tabanina gore karsilastirma, canli tur,
      CHANGELOG; tek surum ya da sprint basina surum — kullanici karari

---

## Fikir havuzu (v14'e alinmadi)

Golgeleme (mikrofon/konusma izni), cumle kaydetme, kelime haritasi, karakter
& yer rehberi, okuma cetveli, PDF icin bolum hazirligi (icindekilerden),
anlama kontrolu, kenar notlari, seviye testi.

## Genel dogrulama (her sprint sonu)

- Tam birim test paketi + "pencereyi buyutmez" testleri; performans tabani
  kotulesmez
- `main` push, CI testi yesil (Xcode 26.x)
- Maketle karsilastirmali ekran gorselleri (acik/koyu)
- Kullanici canli turu (kontrol listesiyle)
- `Localizable.xcstrings`: yeni metinler TR ile
