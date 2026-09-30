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
cevirme hissedilir sekilde yavaslamaz (< 16 ms ana thread).

- [ ] **Karsilasma Gunlugu** — kayitli bir kelime okunan sayfada gectiginde
      (kitap, sayfa/bolum, cumle, tarih) sessizce kaydedilir. Kaynak: zaten
      her sayfada calisan `TermMatcher` / `LemmaMatcher` (cekimli bicimler
      dahil). Ayni sayfa ayni gun bir kez sayilir. FSRS'e yazmaz
- [ ] **Kelime Sayfasi (UI)** — `SavedWordDetailSheet` sheet olmaktan cikip
      tam bir sayfa: ustte buyuk kelime + IPA + ses + CEFR rozeti; altinda
      karsilasma zaman cizelgesi ("3 kitapta 7 kez"), cumleler galerisi
      (tiklayinca kitapta o yere gider), kelime ailesi, FSRS "sonraki tekrar /
      hafiza gucu" gostergesi
- [ ] **Cloze modu** (`QuizMode.cloze`) — kart, kelimenin *senin okudugun*
      cumlesini bosluklu gosterir; sonraki tekrarlarda Karsilasma
      Gunlugu'nden *farkli* bir cumle secilir (baglam cesitliligi). Yazilan
      cevap otomatik notlanir (`isObjectivelyGraded`), FSRS'e yazar.
      `QuizMode` raw value'lari degismez, yeni case eklenir
- [ ] Should: **Cumle madenciligi** — secim cubugunda "Cumleyi kaydet": cumle
      karti (`SavedWord.kind`, default `.word`, `decodeIfPresent`). Tekrarda
      once TTS ile dinle, sonra anlamini hatirla
- [ ] Testler: karsilasma tekillestirme ve ust sinir, bozuk `encounters.json`
      karantinasi, eski `saved_words.json`'un `kind` olmadan okunmasi, cloze
      cumle secimi (tekrar etmez), cloze'un FSRS'e yazdigi / karsilasmanin
      yazmadigi (mutation-check)

## Sprint 2 — v1.43.0 "Okuma dongusu" (Must)

Amac: okumanin oncesi ve sonrasi. Uygulamayi acinca "bugun ne yapacagim"
sorusunun cevabi tek bakista.

**Spike:** "onceki bolumde" ozeti ve bolum hazirligi siralamasi icin
cihaz-ici model vs saglayici; spoiler sizintisi (ozet, okunmamis sayfalari
gormemeli — yalniz okunan metin gonderilir) ve CEFR seviyesine uyum.

- [ ] **Bolum Hazirligi ("Isinma")** — bolume girerken, bolumde en cok gecen
      ve bilmedigin 5–8 kelime kucuk bir kartta: anlam, bolumdeki ilk cumlesi,
      "simdi ogren / atla / zaten biliyorum". Siralama = frekans × bilinmezlik,
      `LexicalProfileService` / `BookCoverageService` uzerinden; anlamlar
      anlik katmandan. Ayarlardan kapatilabilir
- [ ] **"Onceki bolumde…"** — kitaba ≥ 3 gun sonra donunce, son okunan
      sayfalardan spoiler'siz 3 cumlelik ozet, hedef dilde, kullanicinin
      seviyesinde. Tetikleyici `ReadingSessionStore`. Tek tikla kapatilir
- [ ] **"Bugun" ekrani (UI)** — mevcut dashboard (`EmptyStateView` icindeki
      `DashboardHeader` / `DashboardWordCard` / `DashboardActivityCard`) tek
      dikey akisa: *Kaldigin yer* (buyuk kapak + ilerleme + devam et),
      *Bugunun tekrarlari* (sayi + tek buton), *Bolum hazirligi*, seri
- [ ] Should: **Karakter & Yer Rehberi ("Kim kimdi?")** — `NLTagger(.nameType)`
      ile kisi/yer adlari; kenar panelinde liste; tiklayinca LLM *yalniz su
      ana kadar okunan kisma dayanarak* kisa tanim verir
- [ ] Could: **Kenar Notlari (marginalia)** — Inspector acmadan, sayfa
      kenarinda o sayfadaki kayitli kelimelerin kisa karsiliklari; Zen mod
      ile uyumlu, acilir/kapanir
- [ ] Could: **Anlama Kontrolu** — bolum sonunda 3 soru, hedef dilde cevap,
      icerik + dil geri bildirimi; FSRS'e yazmaz
- [ ] Testler: hazirlik siralamasi (bilinen/kayitli kelime disarida),
      ozet tetikleyici esigi, ozet isteginin yalniz okunan araligi tasidigi

## Sprint 3 — v1.44.0 "Metni sana uydur" (Must)

Amac: zor metni, onu birakmadan okunur kilmak. Sprintin en gorunur ozelligi.

**Spike:** EPUB'da `<ruby>` enjeksiyonunun reflow, scroll konumu, bookmark
yaklasikligi, karaoke ve saved-word vurgusuyla etkilesimi; 300 sayfalik
kitapta bolum acilis suresi. Kapi: bolum acilisi +%20'den fazla uzamaz.

- [ ] **Satir Arasi Parilti (ruby gloss, EPUB)** — bilinmeyen kelimelerin
      ustunde minik ana-dil karsiligi (furigana gibi). Esik ayarli: kapali /
      yalniz kayitli-ogreniliyor / kapsama disi her sey. Mevcut EPUB vurgu
      enjeksiyonu yolundan (uygulama `WKContentWorld`'u; kitap JS'i kapali
      kalir). Karsiliklar sistem sozlugu / cihaz-ici model / cache; "Yanit
      Dili" kuralina uyar. Gorunum menusunden ⌥⌘G ile ac/kapa
- [ ] **Seviyeye Indir** — paragraf sec → kullanicinin CEFR seviyesinde
      yeniden yaz, yan yana (orijinal | sade); sade metinde de hover ve kaydet
- [ ] **Inspector "Kelime Karti" (UI)** — modul izgarasinin ustunde kompakt
      kahraman kart (kelime, IPA, tek satir anlam, kaydet/dinle). Cogu bakista
      modul calistirmak gerekmez; izgara "daha fazla" altinda. `body`
      asamali desenle (`baseContent` + `withX`) buyur
- [ ] Should: **Dilbilgisi Mercegi** — cumle sec → `NLTagger(.lexicalClass)`
      ile sozcuk turleri renklenir (offline, aninda; renk + etiket, yalniz
      renk degil) + istege bagli LLM "bu yapinin adi ve neden"
- [ ] Should: **Komut Paleti (⌘K)** — kitaplar, kayitli kelimeler,
      sayfa/bolum, menu komutlari ve moduller tek arama kutusunda
- [ ] Could: **Okuma Cetveli** — aktif satir disi hafifce soluklasir (EPUB
      CSS, PDF overlay); Zen mod ile
- [ ] Testler: gloss esik mantigi (saf fonksiyon), ruby HTML uretiminin
      kacis/escaping'i, komut paleti siralamasi

## Sprint 4 — v1.45.0 "Uretim ve disarisi" (Should)

Amac: yazdirmak, konusturmak, kitaplik disindaki metni iceri almak. En
riskli kalemler bilincli olarak sonda.

**Spike:** (a) mikrofon: sandbox'ta `com.apple.security.device.audio-input`
entitlement'i + `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription`
ile `SFSpeechRecognizer` on-device calisiyor mu — bundle id ve sandbox
degismeden. (b) web: 10 haber/blog sitesinde basit readability sezgisinin
basari orani. Kapi: (a) izin akisi calisir, (b) ≥ 7/10 okunur cikti.

- [ ] **Yeniden Anlat (Retell)** — paragraf sec → "kendi cumlelerinle anlat"
      editoru → LLM duzeltir, kelime duzeyinde diff (silinen / eklenen, renk +
      ustu cizili, yalniz renk degil); duzeltilen kelimeler tek tikla kaydedilir
- [ ] **Web makalesi ice aktarma** — URL yapistir / Servisler menusu →
      okunabilir metin yerel mini-EPUB'a donusur (`EPUBDocument` yolu), kapakla
      kutuphaneye duser. `URLSession` + readability sezgisi; script/iframe
      atilir, EPUB JS kapali kurali korunur
- [ ] Should: **Golgeleme (Shadowing)** — cumleyi TTS okur, kullanici tekrar
      eder; on-device transkript, kelime kelime hizalanmis fark. Spike (a)
      gecilmezse Won't
- [ ] Should: **Kelimelerinden Hikaye** — vadesi gelen 8–12 kelimeyi kullanan,
      kullanicinin seviyesinde kisa oyku; RELL'in kendi okuyucusunda mini-EPUB
      olarak acilir (hover, kaydet, alti cizili kelimeler calisir). FSRS'e yazmaz
- [ ] Could: **Bildirimden tekrar** — `DailyReminderManager` bildirimi eyleme
      donusur: kelime + "Biliyorum / Goster"; cevap FSRS'e yazar
- [ ] Could: **Menu cubugunda siradaki kelime** — mevcut `MenuBarExtra`'ya
      cevrilen kart
- [ ] Could: **Kelime Takimyildizi** — kayitli kelimeler grafigi (aile /
      esanlam / ayni kitap), dugum rengi = hafiza gucu; `Canvas`, deneysel
- [ ] Testler: diff hizalama (saf fonksiyon), readability cikarimi (yerel
      HTML fixture'lari, ag yok), hikaye isteginin kelime listesini tasidigi

---

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
