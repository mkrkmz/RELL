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
      | Soguk acilis (UI testi, 5 acilis) | 549 ms (519–575, sapma %3,3) |

      ¹ Ana thread disinda, okunan sayfa basina bir kez — sorun degil; maliyet
      her taramada kelimelerin kok anahtarlarinin yeniden hesaplanmasi
      (onbellege alinabilir). XCUITest, ayni bundle id'li calisan uygulamayi
      kapatir — `make ui-test` kullanicinin RELL'i kapaliyken kosulur
      (ad-hoc imzayla; imzasiz calistirici macOS'ta baslatilamiyor). UI
      testleri `-RELLTestHost` ile acilir (gecici veri)
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
- [x] **Canli tur (kullanici)** — tamam (2026-10-01). Ilk turda okuyucu
      penceresi en kucuk boyutta coktu: baglam seridinin sag tarafi dar
      genislikte kesilen ciplerle yeniden pazarlik ediyordu + 900 pt sabit
      minimum bolunmus gorunumun kendi minimumunun altindaydi. Duzeltme
      (545b725): serit sabit yukseklik, icerik overlay'de, cip sayisi
      genislikten; okuyucu minimumu bolunmus gorunumden. `WindowLayoutTests`
      gercek pencereyi en kucuge indirir (ara cozum ViewThatFits de bu
      testte coktu). Ikinci tur temiz. Kontrol listesi: (1) pencereyi en kucuk boyuta getirip uzun
      bir cumle sec: Inspector cokmeden kaydirilabilir olmali; normal boyutta
      gorunum degismemeli. (2) EPUB'da betik tasimasinin etkiledigi her sey:
      kayitli kelime alt cizgisi, vurgular, uzerine gelme sozlugu, secim
      cubugu, karaoke (Seslendir), ⌥⌘G anlamlar
- [x] Soguk acilis olcumu — 549 ms (kullanicinin RELL'i kapaliyken; gercek
      veri dosyalarina dokunulmadi)

## Sprint 1 — "Okuyucu kabugu" (Must)

Amac: sayfa disindaki her sey sakinlessin; okuyucu sayfaya odaklansin,
araclar istenince bulunabilsin. **Maketle baslar.**

- [x] **Baglam seridi** — iki bolge: solda belge + konum (bolum/sayfa, %,
      kalan sure), sagda tek bir "bu bolum" hapi (hazirlik, bilinen %,
      bekleyen); tiklayinca hepsini gosteren bir panel. Sayaclar (not, kayit)
      kenar cubuguna. Dar pencerede kesilmez
- [x] **Secim cubugu** — birincil eylemler etiketli (Kaydet, Analiz), digerleri
      tek bir "Araclar" menusunde gruplu ve **adlariyla** (Sadelestir, Yeniden
      Anlat, Vurgula ▸ renkler, Seslendir, Kopyala). Pasaj araclari kisa
      secimde gorunur ama pasif ve nedenini soyler
- [x] **Sag tik menusu** — secim cubuguyla ayni eylemler, ayni sirada (bugun
      PDF ve EPUB menuleri farkli)
- [x] **Odak/Zen/anlamlar tutarliligi** — Gorunum menusu, ⌘K ve Zen cubugu ayni
      komut setini gosterir; eksikler tamamlanir
- [x] Testler: "pencereyi buyutmez" (serit, cubuk), menu/palet komut esitligi
- [x] Uygulama (maket onayi 2026-10-01; kararlar: secim ozeti cipi kalkti,
      Not Ekle yalniz PDF, Zen cubugunda uc ikon). Serit: sag tarafta tek
      "Bu bolum" hapi (`chapterPill`) + panel (`ChapterPanel`, isinma listesi
      icinde); sayaclar kenar cubugu rozetlerinde zaten vardi. Menuler tek
      kaynaktan: `SelectionMenu` (PDF+EPUB ayni sira; pasif oge `subtitle` ile
      nedenini soyler, WebKit'in otomatik etkinlestirmesine karsi
      `validateMenuItem`). Cubuk: Kaydet/Analiz etiketli + Seslendir + Araclar
      menusu (vurgu rengi secilebilir). ⌘K: yakinlastirma, sayfa duzeni, tema
      (`viewPaletteItems`). Zen cubugu: anlamlar, tema, seslendir.
      `ReaderShellTests` (7 test; mutation-check: sira degisimi ve pasif oge
      dogrulamasi yakalaniyor). `make ci-test` 627 test, 0 hata
- [x] Canli tur bulgusu (2026-10-02): metnin ustunde yuzen cam cubuklar
      (secim, seslendirme, Zen) arkadaki satirlari kirip etiketlere
      karistiriyordu, her temada. Kural: cam yalniz arkasinda okunan metin
      olmayan kabukta; metin ustunde yuzen kontroller `.dsReadingOverlay()`
      — ayni kapsul/cizgi/golge, opak dolgu sayfa temasindan
      (`PageTheme.overlaySurface`), yazilar temaya gore acik/koyu. Gri temada
      dolgu sayfadan koyu (#333336) ki ayrissin. Alti temada render ile
      kontrol edildi. Arama cubuklari ve ceviri seridi metnin ustunde degil,
      camda kaldi
- [x] Canli tur bulgusu: Zen'de (tam ekran) gizli arac cubugunun yuksekligi
      ustte bos siyah bant olarak kaliyordu → `.windowToolbarFullScreenVisibility(.onHover)`
      yalniz Zen'de; okuma sutununun 8 pt kenar boslugu Zen'de 0. Centik
      seridi (kamera) sistem davranisi, degismez. Ikinci deneme: `.onHover` bandi
      kaldirmadi (bant pencerenin kendi ust guvenli alani, imlecle gri
      gorunuyor) → Zen'de okuma sutunu `.ignoresSafeArea(.container, .top)`.
      Ayni turda: orijinal temada okuma yuzeyi her zaman beyaz (koyu sistemde
      beyaz sayfa ustunde koyu cubuk delik gibi duruyordu); sozluk kutusu
      (NSPopover) icerigi `.dsReadingOverlayFill()` + temaya uygun gorunum. Ucuncu deneme: guvenli
      alani tumden yok saymak sayfayi kamera centiginin arkasina tasidi ve
      Zen cubugu eski yerinde kaldi → Zen cubugu okuma sutununa overlay,
      ikisi birlikte `padding(.top, screen.safeAreaInsets.top)` (centik
      yuksekligi; centiksiz ekranda 0) + ust guvenli alan yok sayilir.
      Olcum (gecici NSLog, kullanicinin Zen'i, 1512x982 ekran): tam ekran
      pencere 949 pt — centigin (32 pt) altindan basliyor; contentView ust
      guvenli alani 52 pt (gizli arac cubugu). Yani centik boslugu cift
      sayiliyordu → kaldirildi; son hal: Zen cubugu overlay + yalniz
      `.ignoresSafeArea(.container, .top)`. Ders: tam ekran geometrisinde
      tahmin yerine ilk denemede olc. Sonra: Zen cubugunun dugmeleri tiklanmiyordu —
      tam ekranda imlec ustteyken macOS baslik cubugunu (52 pt) sayfanin
      ustune indiriyor, ozel cubuk onun altinda kaliyordu (hit-test olcumu:
      pencere icinde engel yok). Cozum: ozel `ZenModeBar` kaldirildi; Zen'de
      arac cubugu gizlenmiyor, icerigi Zen kontrolleriyle degisiyor
      (`ZenToolbar.swift`, `windowToolbarContent`), tam ekranda
      `.onHover` — Safari gibi menu cubuguyla birlikte iner
- [x] **Canli tur (kullanici)** — tamam (2026-10-02; bulgular yukarida: cam
      ustu metin, Zen boslugu, Zen dugmeleri). Kontrol listesi: (1) serit: genis ve dar pencerede "Bu
      bolum" hapi, tiklayinca panel, "N kelimeyi gor" → liste → "Ozete don";
      (2) secim cubugu: kelime ve paragraf secimi, Araclar menusu (pasif
      ogelerin altindaki neden), Vurgula ▸ renkler; (3) sag tik PDF ve EPUB'da
      ayni sira; (4) ⌘K'de "Sayfa Temasi:", "Sayfa Duzeni:", "Yakinlastir";
      (5) Zen cubugu ikonlari

## Sprint 2 — "Inspector" (Must)

Amac: Inspector'u bir **calisma alani** yapmak: once kelime, sonra derinlik;
cumle secildiginde o cumle icin araclar. **Maketle baslar.**

- [x] **Bilgi mimarisi** — kelime secimi: kelime karti (ust) → hizli eylemler
      (kaydet, dinle, Anki) → "Aciklamalar" (modul cipleri + sonuc) → Ask AI.
      Ifade/cumle secimi: cumle + ceviri → "Araclar" (Dilbilgisi, Sadelestir,
      Yeniden Anlat) → modul sonucu
- [x] **Modul izgarasi** — sik kullanilan modullerin gorunur, digerlerinin
      "Daha fazla" altinda olmasi; otomatik calistirma ayari ayni kalir
      (v13'te kullanici kararina birakilmisti — maket asamasinda onaylanir)
- [x] **Sonuc okunabilirligi** — modul ciktilarinda baslik/govde tipografisi,
      ornek cumlelerde kelime vurgusu, kopyala/kaydet eylemleri tek yerde
- [x] **Saglamlik** — tum sabit bolge yeni kurala gore (esnek ya da sinirli
      ScrollView); her bolum icin "pencereyi buyutmez" testi
- [x] **Tema uyumu** — Inspector arka plani sayfa temasini izleyebilir (ayar;
      varsayilan sistem gorunumu)
- [x] Uygulama (maket onayi 2026-10-02; kararlar: otomatik calistirma kalir,
      Kelime/Cumle secimden otomatik — `ExplainMode.automatic(for:)`, elle
      ⋯ menusunde; Telaffuz "Daha fazla"ya; cumle kartinda ceviri seridin
      onbelleginden — `QuickLookupService.translationRevision` ile, ikinci
      istek yok; tema uyumu varsayilan kapali). Kart: yazili Kaydet/Dinle/
      Anki + son terimler menusu; cumle: kart + "Araclar" (mercek,
      Sadelestir, Yeniden Anlat); "Aciklamalar": 4 cip + "Daha fazla"
      menusu (`ModuleType.inspectorFront/inspectorMore`, ⇧⌘R gizli dugme).
      Yaris: otomatik mod degisimi onChange ile ikinci kez onbellek
      yukleyip `resetAll()` ile otomatik calistirmayi iptal ediyordu →
      `modeChangedWithSelection`. Baglam kartlari markdown. Sonuc
      basligindaki "kelimenin kaydina ekle" (makette) eklenmedi — yeni
      davranis olurdu; kaydet karttan. Testler: `InspectorLayoutTests` (3),
      LayoutGuard +2 (cumle+ceviri+araclar, tema uyumu). Gorsel kontrol
      gecici render ile. `make ci-test` 632 test, 0 hata
- [x] **Canli tur (kullanici)** — tamam (2026-10-02, sorunsuz). (1) kelime sec: kart dugmeleri (Kaydet ⌘D,
      Dinle/Durdur ⇧⌘S/⇧⌘X, Anki), saat menusu (son terimler), ⋯ menusu
      ("Soyle Acikla"); (2) cumle sec: ceviri kartta (serit aciksa),
      Araclar: Dilbilgisi, Sadelestir, Yeniden Anlat; (3) 4 cip + Daha fazla
      menusu (aktif modul cipte gorunur, ⇧⌘R); otomatik calistirma kelimeden
      cumleye gecince calisiyor mu; (4) Ayarlar ▸ Gorunum ▸ "Inspector sayfa
      temasini izlesin" + sepya/gece; (5) en kucuk pencerede Inspector

## Sprint 3 — "Ana ekran, kitaplik ve kelimeler" (Should)

Amac: uygulamayi acinca ne yapilacagi, nereye gidilecegi tek bakista;
araclar bir yerde. **Maketle baslar.**

- [x] **Bugun = merkez** — kaldigin yer, bugunun tekrarlari, okuma hedefi ve
      bir **"Araclar"** satiri (Makale ice aktar, Kelimelerinden hikaye,
      Tekrar penceresi) — daginik sheet'lere tek giris
- [x] **Kitaplik** — kapak izgarasi/liste gecisi, zorluk/kapsama rozeti,
      koleksiyonlar daha gorunur; ice aktarilan makaleler ve hikayeler ayri
      rafta ("Makaleler", "Hikayeler")
- [x] **Kelimeler** — liste satirlari sadelesir (durum, seviye, son
      karsilasma), filtreler tek satirda; kelime sayfasi kenar cubugundan da
      acilir
- [x] **Bos durumlar** — her bos ekran ne yapilacagini soyler ve tek eylem
      sunar
- [x] **Yenilikler** — guncellemeden sonraki ilk acilista kisa bir "Bu
      surumde" sayfasi (CHANGELOG ozetinden, TR)
- [x] Uygulama (maket onayi 2026-10-02; kararlar: tekrar + hedef yan yana,
      liste gorunumu varsayilan izgara, satirdan tarih/alan/mod kalkti —
      bayrak yalniz hedef dilden farkliysa, Yenilikler bir kez kendiliginden).
      Bugun: "Devam" hapi, `DashboardToolsRow`, etkinlik karti dikey (grafik
      altta). Kitaplik: `LibraryCard.Style` grid/list, raflar
      `RecentDocument.shelf` (Articles/Stories klasorunden), raf bos
      durumlari eylemli; `CoverageBadge` ortak. Kelimeler: satir uc bilgi +
      `WordEncounterStore.latestByWord` (liste basina tek gecis); etiketler
      satirdan kalkti (FlowLayout sutunda — v14 kuralina aykiriydi); filtre:
      durum + siralama + tek "Filtre" menusu, etkin filtre cipleri. Bos
      durumlar: yer imi (⌘B, `.toggleBookmarkCommand`), arama/filtre
      temizle, vurgu/not yonergeleri. Yenilikler: `WhatsNew` (elle yazilir,
      "major.minor"; yerel derleme 1.0 → yalniz Yardim menusunden),
      `WhatsNewSheet`. xcstrings: kacisli tirnakli anahtarlar icin bos nesne
      deseni duzeltildi. Testler `HomeLibraryWordsTests` (6). Gorsel kontrol
      gecici render ile. `make ci-test` 638 test, 0 hata
- [x] **Canli tur (kullanici)** — tamam (2026-10-02, sorunsuz). (1) ana ekran: Devam, tekrar + hedef yan
      yana, Araclar satiri (uc dugme); (2) kitaplik: Tumunu gor ›, izgara/
      liste, raflar (Makaleler, Hikayeler; bos raf dugmesi); (3) kelimeler:
      satir, Filtre menusu, etkin filtre cipi kaldirma, bos liste dugmeleri;
      (4) yer imleri bos: "Bu Sayfayi Isaretle"; (5) Yardim ▸ RELL'deki
      Yenilikler

## Sprint 4 — "Cila: ayarlar, tanitim, erisilebilirlik" (Should)

Amac: ilk acilistan Ayarlar'a kadar butunluk; herkes icin kullanilabilirlik.

- [x] **Ayarlar** — Genel bolunur: Okuma, Ogrenme (seviye, ozet, hazirlik,
      anlamlar), AI (saglayici, cihaz-ici, gizlilik), Veri (yedekler);
      `@AppStorage` anahtarlari degismez
- [x] **Tanitim** — onboarding'e okuma dongusunu gosteren kisa tur (sec →
      anla → kaydet → tekrar), atlanabilir; Yardim menusunden tekrar acilir
- [x] **Erisilebilirlik turu** — tum ikon dugmeleri etiketli; VoiceOver ile ana
      akis (belge ac → kelime sec → kaydet → tekrar) bastan sona; klavye
      odagi Inspector ve sheet'lerde; kontrast (tum sayfa temalari)
- [ ] **Gorsel tutarlilik** — kart stilleri ve vurgu gradyani tek kaliba;
      sabit padding'ler ve ham fontlar DS token'larina; acik/koyu ve 6 sayfa
      temasinda ekran gorselleriyle kontrol
- [x] **Turkce metin turu** — gorunen tum metinlerin TR karsiligi gozden
      gecirilir (kisa, tutarli terimler)
- [x] **Gorsel tutarlilik** — tam karsiligi olan sayisal padding'ler (2/4/8 →
      xxs/xs/sm, 12 yer) token'a gecti; 1/3/5/6/7 rozet ici optik ayar ve
      14/18/22 liste girintisi bilerek kaldi; ham font yok (tek cagri zaten
      DS-exempt). Kart cizgisi tek kalinlik (`CardStroke.lineWidth` 0.6;
      kartlar 1, paneller 0.6, elle yapilanlar 0.5–0.8 idi); elle yazilmis 5
      kart `dsCard`/`dsPanel`'e gecti; gradyanlar zaten DS'te. 6 tema × acik/
      koyu matrisi gecici render ile kontrol edildi: okuma yuzeyi ve tema
      izleyen Inspector tutarli. Supheli: koyu temalarda modul ciplerinin
      yazisi soluk — cipler cam efektli, render cami gercek pencere gibi
      cizmiyor olabilir; canli turda bakilacak
- [x] **Hitap** (kullanici karari "sen"): "siz" kalibindaki 24 TR metin
      "sen"e cevrildi (emir ve -iniz ekleri taranarak; iyelik ekli
      yanlis alarmlar elendi)
- [x] Uygulama (maket onayi 2026-10-02; kararlar: 6 sekme, tur yeni
      kullaniciya + Yardim menusu, "Inspector", "tekrar bekleyen", tek
      surum 1.43.0). Ayarlar: `ReadingSettingsView` (eski Genel dosyasi,
      `SettingsTab.general` ham degeri korundu), `LearningSettingsView`
      (sekme adi "Study" — "Learning" anahtari kelime durumu
      "Ogreniliyor"), `DataSettingsView`; okuma hedefi Ogrenme'de; veri
      kurtarma uyarisi Veri'ye gider. Tur: `ReadingLoopTour` (4 sayfa,
      resimli), onboarding'in son adimi + Yardim ▸ Tanitim Turu. A11y:
      adsiz ikon dugmeleri etiketlendi (20+), bos baslikli `Button("",
      systemImage:)` 5 yer → "Close", `AccessibilityAuditTests` kaynaklari
      tarar (mutation-check: etiket silinince kirildi); Esc: kitaplik
      sheet'leri, Sadelestir, Yenilikler. Olu `InspectorView.iconButton`
      silindi. TR: Denetci → Inspector, vadesi gelen → tekrar bekleyen.
      Testler +4 (`SettingsAndTourTests`, `AccessibilityAuditTests`).
      `make ci-test` 642 test, 0 hata
- [x] Performans tabanina gore (2026-10-02, ayni Mac, Debug, 5 tekrar):
      EPUB 20,6 ms (21) · tepe bellek ~80 MB (~91) · PDF 17,1 (17) · tarama
      133,6 (140) · profil 9,5 (10) · hazirlik 13,4 (14) · depo 5,0 (5) ·
      makale 28,5 (31). Gerileme yok. Soguk acilis (RELL kapaliyken, iki tur
      × 5): ilk acilis her turda aykiri (680, 807 ms); ortanca 549 → 576 ms
      (+%5). Ana ekran artik daha fazla ciziyor (araclar, yan yana kartlar);
      kucuk ama gercek olabilecek bir artis, esik koyulmadi
- [x] CI duzeltmesi: Test is akisi 545b725'ten (WindowLayoutTests eklendi)
      beri kirmiziydi ve sprint sonlarinda kontrol edilmedi — "CI gecmeden
      sprint kapanmaz" kurali ihlal edildi. Neden: CI'in macOS 15.7'sinde
      okuyucu penceresi testi test surecini cokertiyor ("malloc: pointer
      being freed was not allocated", oncesinde "Cannot use Scene methods …
      without SwiftUI Lifecycle") — sahne SwiftUI yasam dongusu disinda elle
      kurulan NSWindow'da; korudugu kisit dongusu degil. Test macOS 15'te
      gerekceli XCTSkip, macOS 26+'da calisir. Ders: her push'tan sonra
      `gh run list` ile Test is akisi kontrol edilir
- [ ] Kapanis: canli tur, tek surum 1.43.0 (onayli;
      tag oncesi kullaniciya sorulur)

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
