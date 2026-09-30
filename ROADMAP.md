# RELL Roadmap v13 — Okumak, Sadece Bakmak Degil (S0 + 4 sprint, v1.42 → v1.45)

Olusturulma: 2026-09-30 (v1.41.0 sonrasi). Kullanici istegi: "tamamen taze
fikirler, hem ozellik hem UI". Oneri onaylandi; sprint ici kapsam her sprint
basinda yeniden teyit edilir.

v12 roadmap kapandi: S1 **v1.39.0 "Guven"** (bozuk dosya karantinasi, gunluk
yedekler + disa/ice aktarma, nesil sirali `DebouncedFileWriter`, stream'de
ilk tokendan sonra retry yok, hatali modul cache'lenmez, Anthropic istek
sekli, EPUB JS kapali + `EPUBLinkPolicy`), S2 **v1.40.0 "Sifir kurulum"**
(`AppleOnDevice.route` katmani, Translation framework cumle seridi, gizlilik
ozeti) ve S3 **v1.41.0 "Pencere modeli"** (`ReaderWindowModel`, ContentView
1504 → 669, Inspector yaris duzeltmesi, `StorageKey`, uyari 29 → 0). Uc surum
tag'lendi, CI yesil, DMG'ler uretildi; 533 test. **Acik kalan:** uc sprintin
canli turu kullanicida, Swift 6 dil modu bayragi — ikisi de S0'a devredildi.

Tani: 1.5 → 1.41 arasindaki neredeyse her ozellik **tek bir kelimeye tepki**
veriyor (hover, Inspector modulleri, kaydet, tekrar et). Uygulamada eksik
olan uc sey:

1. **Okumadan once ve sonra** — bolume hazirlik yok, bolum sonunda anlama /
   uretim yok.
2. **Kelimenin hayati** — kaydedilen kelime tekrar ekrani disinda bir daha
   gorunmuyor; kitaplarda kac kez karsilasildigi, hangi cumlelerde gectigi
   kayboluyor.
3. **Uretim** — uygulama hic yazdirmiyor, konusturmuyor.

## Teknik cerceve (tum sprintler icin gecerli)

v12 cercevesi **aynen** devralinir (sifir dis bagimlilik; deployment target
macOS 15, 26+ API'leri `#available` arkasinda; tam test paketi CI komutuyla;
yeni testler async; makineye bagli test `XCTSkip`; bozuk dosyanin ustune
yazilmaz; kismi LLM cevabi cache'e girmez; anlik katman "Yanit Dili"ne uyar;
`Text(String)` katalogu atlar; parser etiketleri / raw value'lar / StorageKey
degerleri yeniden adlandirilmaz; yeni `Codable` alan `decodeIfPresent` +
default; DS token'lari; `project.pbxproj` elle duzenlenmez; bundle id ve
sandbox'a dokunulmaz). Eklenenler:

- **FSRS'e yalniz hatirlama yazar.** Karsilasma, anlama kontrolu, hikaye,
  eslestirme, yeniden anlatma → zamanlamaya dokunmaz. Cloze ve bildirimden
  verilen cevap yazar (hatirlama sayilir).
- **Yazma gurultusu kurali:** okuma sirasinda uretilen veri (karsilasmalar)
  ayri dosyaya (`encounters.json`), `DebouncedFileWriter` ile, kelime basina
  ust sinirla (son 50) yazilir; `saved_words.json` sismez. Her yeni dosya
  `PersistenceBackup` kapsamina ve karantina yoluna eklenir.
- **Gizlilik tablosu:** her yeni LLM ozelligi `PrivacySummarySection`'a satir
  olarak girer; web ice aktarma ve mikrofon acikca listelenir.
- **Cihaz-ici yonlendirme:** ozet / soru / yeniden yazma / hikaye icin spike
  ile guvenilirlik olculur; guvenilmezse `AppleOnDevice.route` yapilandirilmis
  saglayiciya duser (v1.40 deseni, modul bazinda karar).
- **Her sprint bir spike ile baslar** (asagida); spike kapisi gecilmezse kalem
  bir sonraki sprinte veya Won't'a gider — sessizce kucultulmez.
- **Canli tur tek kopyayla:** kullanicinin Xcode'dan acik kopyasi varken ikinci
  kopya calistirilmaz (ayni bundle id, ayni veri).

**Bilincli olarak v13 disinda:** `.apkg` export (Won't), sayfali EPUB,
kapsama metriginin yeniden kalibrasyonu, embeddings/RAG, kisiye ozel FSRS
agirlik optimizasyonu, AnkiConnect, iOS/iPadOS, PDF'te ruby gloss.
Apple-Developer-kilitli kalemler (notarization, widget, App Group, CloudKit,
sandbox/bundle id) uyelik gelene kadar Won't.

---

## Sprint 0 — v1.41.1 "Borc" (Must, kisa)

- [ ] **Canli tur** (v1.39–v1.41'den kalan): Ayarlar ▸ Genel ▸ Yedekler; JS
      kapali EPUB'da secim/hover/vurgu/karaoke; bir Claude modeliyle Inspector;
      Ayarlar ▸ AI anahtar + ozet; tanim Apple'dan / etimoloji saglayicidan;
      cumle seridinde dil paketi istemi; odak/zen giris-cikis; PDF'i yeniden
      acinca son sayfa; calisan modulu yeniden baslatma. **Swift 6 icin
      ekle:** gunluk hatirlatmayi ac/kaydet (bildirim zamanlama yolu),
      ⌃⌥Space, TTS ile sayfa okuma. (2026-09-30: kullanici tam ekran bir
      uygulamadaydi, pencere gorunur Space'e alinamadi — gorsel tur yapilamadi)
- [x] **Swift 6 dil modu** (uygulama hedefi `SWIFT_VERSION = 6.0`, test
      hedefleri 5'te): arka plan kuyrugunda cagrilan iki ObjC tamamlama
      blogu ana-aktor izolasyonunu miras aliyordu — Swift 6'da calisma
      zamani tuzagi. `SpotlightIndexer.reindexAllWords` `nonisolated`,
      `DailyReminderManager.schedule` async `center.add` kullaniyor.
      Delegate'ler (`UNUserNotificationCenter`, `AVSpeechSynthesizer`,
      `WKNavigation`, `WKScriptMessage`) zaten `nonisolated`; `DispatchQueue`
      closure'lari `@Sendable`. Swift 6 modulune karsi derlenen test
      hedefinde `@MainActor` eksik 20 sinif desene cekildi (metotlar
      `async`), bir `wait(for:)` → `await fulfillment`. Temiz derleme 0
      uyari; **533 test, 0 hata, 1 atlanan**. Arka plan canli kontrolu:
      acilis + Spotlight yeniden indeksleme, EPUB acma, normal cikis —
      cokme yok
- [ ] Hijyen devri: `open -g` ile pencere acilmamasi; test hedeflerinin
      `MACOSX_DEPLOYMENT_TARGET = 26.2` farki

## Sprint 1 — v1.42.0 "Kelimenin hayati" (Must)

Amac: kaydedilen kelime, okudugun her yerde izini birakan bir nesneye donussun.
Bu sprint S2–S4'un veri temelidir.

**Spike:** 277 sayfalik PDF ve uzun bir EPUB'da, sayfa/bolum basina eslesme +
kayit maliyeti (ms) ve bir okuma oturumunun urettigi yazma sayisi. Kapi: sayfa
cevirme hissedilir sekilde yavaslamaz (< 16 ms ana thread). **Sonuc:** tarama
(lemma + cumle bolme) ve EPUB metin cikarma tamamen ana thread disinda;
ana thread'de yalniz dwell sonrasi bir `page.string` + dizi ekleme. Sayfa
cevirmede is yok — `.task(id:)` dwell'i pasaj degisince iptal ediyor.
Yazma: okunan sayfa basina en fazla bir kez (ayni kelime/yer/gun tekillesir).

- [x] **Karsilasma Gunlugu** — `WordEncounterStore` (`word_encounters.json`,
      yedek + karantina kapsaminda) + saf `EncounterScanner`. Sayfa 8 sn,
      bolum 15 sn ekranda kalinca okunmus sayilir (`ContentView+Encounters`,
      `.task(id:)` ile — kaydirip gecilen sayfa sayilmaz). Cekimli bicimler
      dahil; ayni kelime+yer+gun tek kayit; kelime basina son 50; silinen
      kelimelerin kayitlari budanir; kelimenin kaydedildigi cumle sayilmaz.
      FSRS'e yazmaz. **Canli turda bulunan:** PDF'te ilk gecis cogu zaman
      sayfa basligi ("REM-Sleep Dreaming") — artik en az 6 kelimelik ilk
      duzyazi cumlesi tercih ediliyor, yoksa ilk gecis
- [x] **Kelime Sayfasi (UI)** — `SavedWordDetailSheet` yeniden tasarlandi
      (520×680): ust bolum (kelime, ses, CEFR, ustalik, tanim), "su an
      hatirlama olasiligin" gostergesi (FSRS retrievability) + sonraki tekrar,
      "okumalarinda karsina cikti" listesi (cekimli bicim kalin; kaynak,
      sayfa, ne zaman, ×adet), kaydettigin yer, Ayrintilar altinda
      etiket/not/ciktilar. Cumleye tiklamak kitabi o sayfada acar
      (`DocumentJump`: konum once okuma konumu olarak yazilir, sonra
      `openWindow`; acik pencere bildirimle atlar). Tam sayfa pencere yerine
      buyuk sheet: ayri pencere ortam/pencere yonetimini buyutuyordu
- [x] **Cloze — bilincli sapma:** `QuizMode.cloze` eklenmedi, cunku mevcut
      "Type" modu zaten kaydedilen cumleden cloze'du; ikinci mod ayni isi
      yapardi. Yeni olan baglam cesitliligi: `ClozeContext` kart cumlesini
      kaydedilen cumle + karsilasma cumleleri arasinda tekrar sayisina gore
      dondurur, kaynagi kartta gosterir. Yalniz kelimenin kaydedildigi
      bicimde gectigi cumleler — cevap o bicime gore notlaniyor. FSRS yolu
      degismedi (Type zaten yaziyordu)
- [ ] Should: **Cumle madenciligi** — ertelendi (kullanici karari bekliyor).
      Etki alani genis: `SavedWord` cumle olunca vurgulama (butun cumle alti
      cizili), kapsama/lemma anahtarlari, CEFR tahmini, coktan secmeli ve
      eslestirme modlari, Anki disa aktarimi ayri ele alinmali
- [x] Testler (25 yeni, `WordEncounterTests` + `WordPageTests`):
      tekillestirme, ust sinir, budama, dil kapsami, kalicilik, bozuk dosya
      karantinasi, yedek listesi, baslik yerine duzyazi, cekimli bicim,
      cloze rotasyonu ve cekimli-bicim atlama, PDF atlama konumu, tekil
      ozet. Mutation-check: tekillestirme, dil filtresi, cloze rotasyonu,
      bicim atlama — geri alininca dusuyorlar
- [x] Dogrulama: tam paket **558 test, 0 hata, 1 atlanan**; 0 uyari;
      katalog 23 yeni TR metin. Canli: PDF'te dwell → kayit, Kelime
      Sayfasi, s.145 → s.143 atlama

## Sprint 2 — v1.43.0 "Okuma dongusu" (Must)

Amac: okumanin oncesi ve sonrasi. Uygulamayi acinca "bugun ne yapacagim"
sorusunun cevabi tek bakista.

**Spike:** "onceki bolumde" ozeti ve bolum hazirligi siralamasi icin
cihaz-ici model vs saglayici; spoiler sizintisi (ozet, okunmamis sayfalari
gormemeli — yalniz okunan metin gonderilir) ve CEFR seviyesine uyum.
**Sonuc:** bir bolum ~28k karakter (~7k token) — cihaz-ici modelin 4096
token'lik penceresine sigmaz; yer iminden onceki son ~6000 karakter yeterli.
Cihaz-ici ~3 sn, dogru, sade B1; ama Suc ve Ceza'da 3 denemeden 1'i guardrail
reddi → `AppleOnDevice.chatWithFallback` (cihaz-ici, olmazsa saglayici).
LM Studio (gemma-4-e4b) 3–11 sn; dusunen model 300 token'da bos cevap
dondu → 1200 token payi. Hazirlik: uygulama yalniz kayitli kelimeleri
biliyor; siklik siralamasi kolay kelime veriyor (understand, moment) →
adaylar nadir icerik lemmalari (≥6 harf, isim degil), zoru model seciyor.
Kullanici karari: seviye ayari, varsayilan B1.

- [x] **Seviyen** — Ayarlar ▸ Genel (`StorageKey.learnerLevel`, varsayilan
      B1); ozet ve hazirlik bu seviyeye gore yazilir (S3 "Seviyeye Indir"
      de kullanacak)
- [x] **"Onceki bolumde…"** — kitap ≥ 3 gun sonra acilinca sayfanin
      ustunde yuzen kart (`ReadingRecap` saf + `ReadingLoopModel`).
      Metin: PDF'te yer imine kadar son 4 sayfa, EPUB'da bolumun kaydedilen
      konuma kadarki kismi (+ bolum basindaysa onceki bolum), son 6000
      karakter — yer iminden sonrasi hic gonderilmez (testli, mutation-check).
      Onsoz satirlari ("I am a foundation model…") temizlenir; hata sessiz.
      Ayarlardan kapatilir. **Canli turda bulunan cokme:** kart okuyucunun
      ustundeki VStack'teydi; buyuyunce WKWebView'i yeniden boyutlandirip
      AppKit yerlesim dongusune soktu ("more Update Constraints passes than
      views" → SIGTRAP). Kart artik okuyucunun uzerinde overlay — okuyucu
      cercevesi hic degismiyor; tekrar denemede cokme yok
- [x] **Bolum Hazirligi** — EPUB bolumu acilinca baglam seridinde "N
      kelimeyle isin" cipi; acilir listede tanim (hover sozlugunun cevap
      dilinde), bolumdeki ilk cumle, Kaydet / Tumunu Kaydet. Kitap+bolum
      basina bellekte onbellek; basarisiz istek onbellege girmez.
      **Sapma:** yalniz EPUB — PDF'te bolum siniri yok (icindekiler
      uzerinden ayrica bakilabilir). Roadmap "tamamen offline" diyordu;
      siklik verisi olmadan zor kelime secilemiyor, secim modelde
- [x] **"Bugun" ekrani (UI)** — hedefli degisiklik: dashboard zaten kaldigin
      yer / tekrar / hedef / seri kartlarini tasiyordu, ayri plan karti ayni
      sayilari ikinci kez gosterirdi. Baslik "Bugun", sira gunun isine gore
      (kaldigin yer → tekrarlar → okuma hedefi), kaldigin yer kartinda "N
      gundur acmadin — acinca kisa ozet goreceksin"
- [ ] Should: **Karakter & Yer Rehberi** — S3'e devredildi
- [ ] Could: **Kenar Notlari**, **Anlama Kontrolu** — alinmadi
- [x] Gizlilik ozeti: "Ozetler ve bolum hazirligi" satiri; alt yazi ozetin
      son bir iki sayfayi gonderdigini soyluyor. 19 yeni TR metin
- [x] Testler (12 yeni, `ReadingLoopTests`): ozet esigi ve ilerleme sarti,
      yer imi siniri (spoiler), kelimeden baslayan kuyruk, onsoz temizligi,
      aday secimi (isim/kisa/kayitli disarida, alfabetik), siki parse,
      cumle esleme. Mutation-check: spoiler siniri, kayitli kelime disleme.
      S1'den kalan zamana bagli bir test (iki yazilis mikro saniye arayla)
      aralikli dusuyordu — tarihler sabitlendi
- [x] Dogrulama: tam paket **570 test, 0 hata, 1 atlanan** (iki kez); 0
      uyari. Canli: Bugun ekrani, Why We Sleep EPUB'da ozet karti (dogru B1
      ozet) + "5 kelime" cipi. **Dogrulanmadi:** hazirlik listesinin
      gorunumu — pencere baska bir Space'teydi, popover acilmadi

## Sprint 3 — v1.44.0 "Metni sana uydur" (Must)

Amac: zor metni, onu birakmadan okunur kilmak. Sprintin en gorunur ozelligi.

**Spike:** EPUB'da `<ruby>` enjeksiyonunun reflow, scroll konumu, bookmark
yaklasikligi, karaoke ve saved-word vurgusuyla etkilesimi; 300 sayfalik
kitapta bolum acilis suresi. Kapi: bolum acilisi +%20'den fazla uzamaz.
**Sonuc:** gercek `<ruby><rt>` elenecek — `rt` metni `textContent`'e girer;
vurgu capalari, arama ve karaoke karakter sayisina dayandigi icin hepsi
kayar. Anlam CSS ile cizildi (`::after { content: attr(data-rell-gloss) }`):
metin degismiyor (testli, mutation-check: `rt` eklenince test dusuyor).
Bolum acilisi degismiyor — anlamlar bolum yuklendikten sonra ayri bir
istekle gelir ve mevcut isaretleme gecisine katilir. Kayitli ciktilar
uzun duzyazi ("A beverage is any liquid…") — ustune sigacak 1–3 kelime
sezgiyle cikmiyor; bolum basina tek toplu istek (cihaz-ici ~1.5 sn,
cikti bicimi temiz: `sleep | uyku`), oturum boyu onbellek.

- [x] **Anlamlar kelimenin ustunde (EPUB)** — Gorunum ▸ "Anlamlari
      Kelimelerin Ustunde Goster" (⌥⌘G, varsayilan kapali). Kapsam: bolumde
      gecen ve hala ogrenilen kayitli kelimeler + bolum hazirligi kelimeleri
      (bunlar alt cizgisiz). Cekimli bicim sozluk biciminin anlamini alir.
      "Yanit Dili"ne uyar. Anlam acikken satir araligi 2.35. Canli: "sleep"
      ustunde "uyku", 11 anlam ~2 sn. Acilip kapanirken okuma konumu oransal
      korunuyor — **dogrulanmadi**: WebKit'in scroll anchoring'i test
      ortaminda zaten koruyordu, test ayrim yapmadigi icin cikarildi; canlida
      acilista hafif kayma goruldu
- [x] **Seviyeye Indir** — secim cubugunda 6+ kelimelik secimde "Seviyene
      gore sadelestir" → yan yana sheet (orijinal | seviyende), seviye
      seciciyle yeniden yazma (secici genel ayari degistirir), kopyala,
      sesli oku. PDF + EPUB. **Sapma:** sade metinde hover/kaydet yok —
      sheet icinde okuyucu motoru yok; metin secilebilir. **Canli
      dogrulanmadi:** sentetik cift tiklama WKWebView'da secim olusturmuyor
- [x] **Inspector "Kelime Karti" (UI)** — tek kelimelik secimde baslik karta
      donusur: buyuk kelime, ses, (kayitliysa) CEFR + durum ikonu,
      hover sozlugunun onbellekli tek satirlik anlami ("Yanit Dili"ne uyar),
      "N kez karsilastin". **Sapma:** modul izgarasi "daha fazla" altina
      alinmadi — otomatik calistirma ayarini ve yerlesik akisi degistirir,
      kullaniciyla konusulacak. **Canli dogrulanmadi** (ayni neden)
- [ ] Should: **Dilbilgisi Mercegi**, **Komut Paleti (⌘K)**, S2'den
      **Karakter & Yer Rehberi** — alinmadi
- [ ] Could: **Okuma Cetveli** — alinmadi
- [x] Testler (12 yeni: `InterlinearGlossTests` 8, `ReadingLoopTests` +4):
      gloss parse/uzunluk/cekim, gercek okuyucu yapilandirmasinda cizim
      (textContent sabit, `::after` icerigi, hazirlik kelimesi alt cizgisiz,
      kapatinca temizlik, tirnakli anlam), cihaz-ici model hatti (model
      yoksa XCTSkip), sadelestirme uygunlugu/kirpma/temizlik, kart ilk
      cumlesi. 9 yeni TR metin
- [x] Dogrulama: tam paket **582 test, 0 hata, 1 atlanan**; 0 uyari
- Not: `defaults` komutu eski sandbox kapsayicisindaki tercih dosyasini
  okuyup yaziyor; uygulama `~/Library/Preferences` altindakini kullaniyor
  (canli testte yanlis dosyaya yazilan anahtar geri alindi)

## Sprint 4 — v1.45.0 "Uretim ve disarisi" (Should)

Amac: yazdirmak, konusturmak, kitaplik disindaki metni iceri almak. En
riskli kalemler bilincli olarak sonda.

**Spike:** (a) mikrofon: sandbox'ta `com.apple.security.device.audio-input`
entitlement'i + `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription`
ile `SFSpeechRecognizer` on-device calisiyor mu — bundle id ve sandbox
degismeden. (b) web: 10 haber/blog sitesinde basit readability sezgisinin
basari orani. Kapi: (a) izin akisi calisir, (b) ≥ 7/10 okunur cikti.
**Sonuc (b):** ilk surum 2/10 — iki hata: tidy XHTML ad alaninda
`elements(forLocalName:uri: nil)` hicbir sey eslestirmiyordu; BBC gibi
siteler her paragrafi ayri div'e sariyor. Readability puanlamasi (paragraf
uzunlugu ebeveyne, ½ buyuk ebeveyne, ⅓ ustune), bagalanti yogunlugu, HTTP/
meta karakter seti (tidy bayttan Latin-1 okuyup "â€™" uretiyordu), cift
gizli etiket kurali → **8/10** (BBC, Guardian, NPR, DW, Verge, Aeon, Le Monde,
El Pais; Ars ve Spiegel JS/ucretli). **(a) yapilmadi** — asagiya bakin.

- [x] **Yeniden Anlat (Retell)** — secim cubugunda 6+ kelimede "Kendi
      cumlelerinle anlat" → sheet: pasaj (gizlenebilir), editor, "Kontrol
      et" → duzeltilmis metin kelime duzeyinde fark (silinen kirmizi+ustu
      cizili, eklenen yesil+kalin — yalniz renk degil) + ana dilde kisa not;
      duzeltmedeki yeni kelimeler tek tikla kaydedilir. `CORRECTED:`/`NOTE:`
      etiketleri parser-bagli, Ingilizce sabit. FSRS'e yazmaz. Esitlikte
      once silinen sonra eklenen kelime (test buldu)
- [x] **Web makalesi ice aktarma** — Dosya ▸ Web Makalesi Ice Aktar… (⇧⌘I),
      panodaki baglanti onerilir. `ArticleExtractor` (saf) → `MiniEPUB`
      (EPUB 3) → `ZIPWriter` (stored + gercek CRC-32; baska okuyucular da
      acar) → Application Support/RELL/Articles, ayni sayfa ikinci kez
      alininca "-2". Yalniz sayfanin kendisi cekilir; resim/betik yok, AI'ya
      bir sey gitmez (gizlilik tablosunda ayri satir). **Canli turda
      bulunan:** paulgraham.com gibi `<p>`'siz, `<br><br>`'li sayfalar
      reddediliyordu → geri donus yolu (dogrudan metni en cok olan oge,
      cift br'den bolunur; `<br>` iceren satir ici `<font>` kapsayici sayilir)
- [ ] Should: **Golgeleme** — alinmadi. Spike (a) proje yapi ayarlarina
      (Info.plist izin aciklamalari) ve macOS izin istemlerine dokunuyor;
      ustune kayit + cihaz-ici transkript + hizalama arayuzu. Kullanici
      karariyla ayri ele alinacak
- [x] Should: **Kelimelerinden Hikaye** — Git ▸ Kelimelerinden Hikaye…:
      tekrar zamani gelen (sonra kuyruktaki) 4–12 kelime, seviyende ~300
      kelimelik oyku → mini EPUB (Application Support/RELL/Stories), RELL'de
      acilir; sonda hangi kelimelerin kullanilmadigi yazar (lemma esleme).
      FSRS'e yazmaz
- [ ] Could: **Bildirimden tekrar**, **Menu cubugunda siradaki kelime**,
      **Kelime Takimyildizi** — alinmadi
- [x] Testler (15 yeni, `OutputAndImportTests`, ag yok — yerel HTML):
      sarili paragraflar, bagalanti/cift etiket, meta karakter seti, br
      geri donusu, kisa sayfa, adres ayristirma, CRC-32 kontrol degeri,
      ZIP gidis-donus, mini EPUB acilir + kacis, dosya adi, Retell parse,
      kelime farki, hikaye parse + kullanilan kelimeler. Mutation-check:
      ata puanlamasi, bagalanti yogunlugu. 29 yeni TR metin
- [x] Dogrulama: tam paket **597 test, 0 hata, 1 atlanan**; 0 uyari.
      **Canli dogrulanmadi:** ice aktarma ve hikaye akislari (ekran kilitli/
      pencere baska Space'te; ilk deneme PG sayfasinda duzgun hata verdi),
      Retell (sentetik cift tiklama WKWebView'da secim olusturmuyor).
      Canli denemeler kutuphaneye ya da diske iz birakmadi

## Sprint 5 — kapanis (kullanici karari: S5 bitince tek surum)

Kapsam (kullanici secimi, 2026-09-30): test izolasyonu + canli tur, Komut
Paleti + Dilbilgisi Mercegi, bildirim/menu cubugu tekrari. Golgeleme, cumle
kaydetme ve modul izgarasini gizleme **v14'e ertelendi**; Karakter Rehberi
ve Okuma Cetveli alinmadi.

- [x] **Test izolasyonu** — `RELLProcess.isTestHost`: test host'unda veri
      klasoru surece ozel gecici klasor; Spotlight, kisayol, bildirim ve
      gunluk yedek atlanir. Dogrulama: tam kosuda gercek veri dosyalarinin
      degisiklik zamanlari ve yedek sayisi degismedi. Regresyon testi
- [x] **Komut Paleti (⌘K)** — Gorunum ▸ Komut Paleti: komutlar, moduller,
      acik kitabin bolumleri, kayitli kelimeler, kutuphane; sayi → o sayfa/
      bolum. Buyuk/kucuk harf ve aksan duyarsiz; siralama saf (`PaletteMatcher`)
- [x] **Dilbilgisi Mercegi** — Inspector'da ifade/cumle seciminde acilir
      "Dilbilgisi": `NLTagger` sozcuk turleri, renk + kelimenin altinda
      etiket (yalniz renk degil); istege bagli "Yapiyi acikla"
- [x] **Bildirimden tekrar** — gunluk hatirlatma, zamani gelen bir kelimeyi
      sorar; banner'da "Bildim / Henuz Degil" → FSRS (hatirlama); cevaptan
      sonra bildirim siradaki kelimeyle yeniden kurulur
- [x] **Menu cubugunda siradaki kelime** — Hizli Arama penceresinin altinda
      kart: anlami goster, "Henuz Degil / Bildim" → FSRS
- [x] Testler: 598 → **604**, 0 hata, 0 uyari; 39 yeni TR metin
- [ ] **Canli tur (yayin oncesi, kullanici gerekli)** — ekran kilitliydi.
      Kontrol listesi: ⌘K; Dilbilgisi; menu cubugu karti; hatirlatmayi
      acip banner eylemleri; kelime karti; Sadelestir; Yeniden Anlat; web
      ice aktarma (⇧⌘I); Kelimelerinden Hikaye; hazirlik listesi; ⌥⌘G'de
      sayfa kaymasi
- [ ] **Yayin** — CHANGELOG "Unreleased — planned as 1.42.0" hazir; canli
      tur + kullanici onayindan sonra baslik → `[1.42.0]`, tag, push, CI
      release run'i izlenir

## Fikir havuzu (sprinte alinmadi)

- **Seviye testi (ilk acilis)** — 3 dakikalik LexTALE-tarzi evet/hayir kelime
  testi → baslangic "bilinen" kumesi; kapsama *hesabi* degismez (onceki karar)
- **Tekrar ekrani: surukleyici mod** — tam ekran kart, arka plan kelimenin
  geldigi kitabin kapak renginden degrade, tamamen klavye (Space / 1–4)

## Genel dogrulama (her sprint sonu)

- Build + **tam birim test paketi** (UI testleri haric), CI ile birebir komut;
  her regresyon testi mutation-check (duzeltme geri alininca duser)
- `Localizable.xcstrings`: `-exportLocalizations` ile yeni metinler toplanir,
  TR eklenir; commit edilmemis katalog degisikligi birakilmaz
- DS denetimi; macOS 15 fallback yolu derleniyor; yeni dosyalar yedek kapsaminda
- Gizlilik ozeti yeni ozellikleri listeliyor
- Canli tur (tek kopya) → CHANGELOG (kullanici-odakli dil) → tag `vX.Y.Z` →
  push → **CI release run'i izlenir**, DMG uretimi teyit edilir
