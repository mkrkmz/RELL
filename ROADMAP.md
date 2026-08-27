# RELL Roadmap v10 — Dengeli Karisim (4 sprint, v1.35 → v1.38)

Olusturulma: 2026-08-05 (v1.34.2 sonrasi). v9 roadmap tamamlandi (bes sprintin
besi de release edildi: v1.29.0 secim aksiyon cubugu + async persistence,
v1.30.0 zen modu + undo/redo + kitap-geneli ilerleme, v1.31.0 FSRS-4.5 + lemma
eslestirme + kapsama, v1.32.0 karaoke, v1.33.0 erisilebilirlik). Ardindan
v1.34.x: hover sozluk dil secimi + iki okuyucu hatasi (PDF acilista cokme,
bolunmus EPUB'larda yalniz baslik gorunmesi, EPUB okuma kolonunun sola
yaslanmasi).

Odak: kullanici "dengeli karisim" secti — her sprint bir tema:
(1) tekrar modlari, (2) kelime erisimi, (3) okuma UX, (4) export/entegrasyon.

Kesifte cikan belirleyici bulgu: **yazma modu zaten mevcut** (`QuizMode.typed`,
cloze + `QuizMatching.matchesTerm` — v9'da farkinda olunmadan shipped). v9'un
"L5 yazarak tekrar" kalemi buyuk olcude bitmis; eksik olan otomatik notlama.
Asil yeni mod **dinleme modu**.

## Teknik cerceve (tum sprintler icin gecerli)

- **Sifir dis bagimlilik korunur.** `.apkg` icin sistem `import SQLite3`
  (projedeki ilk C-API yuzeyi), lemma icin Apple `NaturalLanguage`, sistem
  sozlugu icin CoreServices `DCSCopyTextDefinition`.
- Her release oncesi **TAM test paketi** CI ile birebir komutla kosulur
  (odakli paket YETMEZ — v1.29 dersi). Yeni testler **async metod**; senkron
  `@MainActor` bloklayan test CI runner'ini kilitler.
- Yeni kullanici metinleri `Localizable.xcstrings`'e TR cevirisiyle
  (`Text(String)` tuzagi — enum'larda `localizedTitle`).
- **`ResultParser`'a gorunur prompt etiketleri degismez; modul raw value'lari
  asla yeniden adlandirilmaz** (persistence anahtari).
- Yeni `Codable` alanlar `decodeIfPresent` + default (ileri-guvenli JSON).
- DS token'lari; glass yalniz chrome, **icerige DOGRUDAN uygulanir** (arkaya
  `.background` katmani degil — v1.33 dersi), interactive yalniz basilabilir
  yuzeyde.
- EPUB'da bize ait body-level CSS `!important` (yayinci CSS'i `body`'yi sinif
  uzerinden stillendiriyor — v1.34.2 dersi).
- `.PDFViewDocumentChanged` icinden **senkron PDFView navigasyonu yasak**
  (thumbnail collection view eski belgenin sayisiyla cokuyor — v1.34.1 dersi).
- **ContentView dosya bolunmesi planlanmaz** — private `@State` extension'a
  tasimayi engelliyor, kapsullemeyi kozmetik kazanc icin acmak dogru degil
  (v1.33'te denendi, geri alindi).

**Bilinclice v10 disinda:** eslestirme oyunu (v11 adayi, cikarilan
`QuizSession` uzerine kurulur), sayfalanmis EPUB, kisiye ozel FSRS agirlik
optimizasyonu, AnkiConnect, embeddings/RAG, frekans listeleri, PDF koyu-tema
figur korumasi. Apple-Developer-kilitli kalemler (widget, App Group, CloudKit,
notarization) uyelik duyurulana kadar Won't.

---

## Sprint 1 — v1.35.0 "Tekrar modlari" (Must)

Amac: v9'dan kalan tekrar-modu rosterini test edilebilir bir oturum modeli
uzerinde tamamlamak.

- [ ] **QuizSession cikarimi (T-R1)**: yeni `Models/QuizSession.swift`
      (`@Observable`) — queue, currentIndex, tally'ler, cram, kart-basina durum
      (isFlipped/typedAnswer/mcOptions/mcSelectedIndex/showAllBackSections) ve
      **objektif dogruluk sayaci** (su an `typedResultView`'da inline hesaplanip
      atiliyor). `UI/QuizView.swift` view builder'lari (`cardFace`,
      `revealContent`, `backSections`, `ratingRow`) YERINDE kalir — bu bir model
      cikarimi, dosya bolme degil. `prepareCard`/`advance`/`recordRating`
      session'a devreder. Birim testleri async. **Kapi: tam paket yesil**
- [ ] **Yazma modunda otomatik notlama (L-R1)**: `@AppStorage("typedAutoGrade")`
      varsayilan ACIK — objektif ✓→`.good`, ✗→`.again` + otomatik ilerleme.
      Kapaliyken mevcut oz-degerlendirme akisi korunur (FSRS 4 notlu; objektif ✓
      Easy/Hard'i ayirt edemez, v1.31'de eklenen sinyal atilmamali). Dogruluk
      `QuizSession`'a; sonuc ekranina objektif-dogruluk istatistigi
- [ ] **SpeechManager tamamlanma sinyali + ses probe'u (T-R2)**: tamamlanma
      bildirimi (`onFinish` veya state→`.idle` + **basladi-guard'i**; timer YOK)
      ve public `hasVoice(for: Language)` — `preferredVoice` su an sessizce nil
      donup sistem sesine dusuyor (yanlis dilde telaffuz)
- [ ] **Dinleme modu (L-R2)**: yeni `QuizMode.listening` — kelime **kendi
      `SavedWord.language`** sesiyle okunur (global hedef dil degil), tekrar cal
      icin mevcut `UI/SpeakButton.swift`, cevap yazilip
      `QuizMatching.matchesTerm` ile kontrol, reveal `usableDefinition` desenini
      izler (placeholder yerine nil — `reviewDefinition` KULLANILMAZ). Hedef
      dilde ses yoksa mod gizlenir
- [ ] **Mod secici → `Menu`**: segmented Picker 4 modda sikisiyor
- [ ] Dogrulama: dort mod uctan uca + cram; auto-grade acik/kapali iki yol;
      Almanca kelimeyle dinleme; sesi olmayan dilde modun gorunmemesi; sonuc
      ekrani dogruluk istatistigi

## Sprint 2 — v1.36.0 "Kelime erisimi" (Must)

Amac: lemma-farkinda metin-ici vurgulama + kitap-bazli kapsama. O kod zaten
aciliyor, iki canli vurgulama hatasi da burada kapatilir.

- [x] **HATA: PDF kelime-siniri**: `PDFKitView.addHighlights` substring
      esliyor — "run" kaydedince "brunt" vurgulaniyor; EPUB JS
      (`rellFindTermRanges`) Unicode kelime-siniri kullaniyor, iki okuyucu
      ayrisiyor. PDF'e ayni kural (CJK substring istisnasi korunur)
- [x] **HATA: dil filtresi**: iki okuyucu da TUM dillerin kelimelerini
      vurguluyor (Almanca kelimeler Ingilizce kitapta). Terim kaynagi belge/
      kelime diline filtrelenir — `SavedWordsStore.lemmaKeySets(for:)` bunu
      zaten dogru yapiyor, vurgulama yollari kullanmiyor
- [x] **Lemma-farkinda vurgulama (L-V1)**: `LemmaMatcher`'a
      `surfaceForms(in:matchingKeys:language:)` (mevcut `enumerateTags` dongusu
      surface+lemma'yi zaten yan yana hesapliyor, surface'i emit etmiyor).
      Boru hatti: sayfa/bolum metni **main-disinda** lemmatize (detached-task +
      generation deseni — `LexicalProfileService`) → `lemmaKeySets` ile kesistir
      → sayfada gercekten gecen **yuzey formlari** mevcut `[String]` API'lerine
      ver. Sayfa-basina cache. Yan fayda: terim listesi kisalir, EPUB 500-terim
      cap'i rahatlar
- [x] **Kapsama yuzeyleri (L-V2)**: kitap-geneli `LexicalProfile` (Codable)
      kitap acilisinda lazy + main-disi hesap, `RecentDocument`'e opsiyonel alan
      (decodeIfPresent). Yuzeyler: `DocumentStats` + statCell, `LibraryCard`
      kapak overlay'i, `ReadingStatsView`'a bir kart
- [x] Dogrulama: "run" kaydet → "ran"/"running" iki formatta vurgulu, "brunt"
      degil; Almanca kelime Ingilizce kitapta vurgulanmiyor; kapsama yeniden
      acista stabil; buyuk PDF scroll perf'i bozulmamis

## Sprint 3 — v1.37.0 "Okuma UX" (Should)

Amac: Mac-native navigasyon hissi. Iki model-agir sprint arasinda bilincli
dusuk-riskli sprint.

- [ ] **PDF sayfa scrubber (U-X1)**: `App/PageIndicatorView.swift`'te Slider
      varyanti (`PDFViewManager` API'si hazir: pageCount/currentPageIndex/
      goToPage). **Lokal drag state sart** — observer suruklerken index'i
      guncelliyor, feedback dongusu olusur
- [ ] **Zen scrubber (U-X2)**: `App/ZenModeBar.swift`'te baslik↔cikis
      arasindaki Spacer slotu; zen'de toolbar gizli oldugu icin tek zen-ici
      navigasyon bu
- [ ] **EPUB pinch→font (U-X3)**: `RELLEPUBWebView`'a `magnify(with:)`;
      birikimli magnification → `epubFontSize` (12…28 clamp).
      **`allowsMagnification = false` geri alinir** — v1.30 U4'un native
      zoom'unu semantik font boyutuyla BILINCLI degistirir (CHANGELOG'a not)
- [ ] **EPUB iki-parmak swipe→bolum (U-X4)**: `scrollWheel(with:)` (phase/
      deltaX veya `isSwipeTrackingFromScrollEventsEnabled`) →
      `nextChapter`/`previousChapter`. `scrollFraction`'a dayanma (250ms
      throttle, jest hissi icin fazla kaba)
- [ ] Dogrulama: buyuk PDF'te normal + zen scrub; pinch fontu degistirir ve
      relaunch'ta kalici; native zoom artik tetiklenmez; swipe iki yonde bolum
      cevirir, kitap uclarinda no-op; ⌘F / secim cubugu / karaoke etkilenmez

## Sprint 4 — v1.38.0 "Export, entegrasyon + kapanis" (Should/Could)

Amac: zamanlama koruyan `.apkg` export, sistem sozlugu katmani, borc odemesi.

- [ ] **SQLite wrapper (T-E1)**: kucuk `SQLiteDatabase` (sistem `import
      SQLite3`) + birim testleri
- [ ] **ZIP writer (T-E2)**: `ZIPArchive.swift` salt-okunur; kardes writer
      (stored method 0 + CRC-32 Anki'ye yeter) + round-trip testi (yaz →
      mevcut reader okusun)
- [ ] **.apkg Faz 1 (L-E1)**: `ExportFormat.apkg` + **paralel Data/URL yolu**
      (mevcut boru hatti uctan uca String). Sema col/notes/cards/revlog; ince
      noktalar `col.models`/`col.decks` JSON, `notes.csum`/`sfld`; media `{}`.
      Kartlar YENI durumda. **Kapi: gercek Anki desktop'a import dogrulamasi**
- [ ] **.apkg Faz 2 — zamanlama tohumu (L-E2, PLANLI RISK, ~2 gun timebox)**:
      FSRS (`stability`/`difficulty`/`nextReviewAt`) → `cards.due/ivl/factor`,
      `reviewEvents` → `revlog`. TSV'nin asla yapamadigi sey.
      **Onceden karar verilen fallback: yalniz Faz 1 ship'lenir**
- [ ] **Sistem sozlugu katmani (L-E3)**: `DCSCopyTextDefinition` →
      `QuickLookupService.cachedDefinition`/`cachedHoverDefinition` (mevcut
      anlik katman) — HUD + iki okuyucunun hover'i bedavaya kazanir. Dil
      mevcudiyeti probe'u (macOS 12 dilin alt kumesini sagliyor; nil → katman
      sessizce atlanir)
- [ ] **T3 borcu: `SavedWordsListView` bolunmesi**: `SavedWordRow` ve
      `SavedWordDetailSheet` kendi dosyalarina, sort/filter enum'lari
      `Models/`'a, `filterControls` cikarilir (~1041 → ~550 satir). Mekanik;
      ContentView'a GENISLETILMEZ
- [ ] Dokumantasyon kapanisi: ROADMAP durum, CHANGELOG, ARCHITECTURE (SQLite
      wrapper, ZIP writer, Dictionary katmani)
- [ ] Dogrulama: `.apkg` → Anki desktop import → kart tekrari; Faz 2'de
      due/interval makul; sozluk EN/DE'de HUD+hover'da, olmayan dilde zarifce
      yok; SavedWords tam regresyon; **S1-S3 amiral ozellikleri tam regresyon**

---

## Genel dogrulama (her sprint sonu)

- Build + **tam birim test paketi** (UI testleri haric), CI ile birebir komut
- `Localizable.xcstrings`: yeni metinler TR cevirisiyle; katalog JSON gecerli
- DS denetimi: ham `.font(.system(size:))` / ham material yok, istisnalar
  `// DS-exempt:` yorumlu
- macOS 15 fallback yolu derleniyor
- CHANGELOG (kullanici-odakli dil) → tag `vX.Y.Z` → push → **CI release run'i
  izlenir**, DMG uretimi teyit edilir
