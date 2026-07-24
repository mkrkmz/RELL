# RELL Roadmap v9 — Core Loop + Learning Engine (5 sprint, v1.29 → v1.33)

Olusturulma: 2026-07-23 (v1.28.0 sonrasi). v8 roadmap tamamlandi (Liquid Glass,
review streak, mid-read TTS hizi); v8'den ertelenen tek kalem (karaoke takibi)
bu roadmap'te Sprint 4'e planli-risk olarak alindi.

Odak: (1) cekirdek okuma dongusundeki surtunmeyi kaldirmak (secim aksiyon
cubugu, zen modu), (2) ogrenme motorunu dunya standardina cekmek (FSRS, lemma
eslestirme, bilinen-kelime kapsama), (3) olcekleme riski #1 olan senkron
persistence'i erkenden cozmek — sonraki tum ozellikler yazma hacmini artiriyor.

## Teknik cerceve (tum sprintler icin gecerli)

- **Sifir dis bagimlilik korunur.** FSRS elle yazilir (~200 satir saf
  fonksiyon), lemma icin Apple `NaturalLanguage` (`NLTagger .lemma`),
  .apkg (Could) icin sistem SQLite3.
- **`ResultParser`'a gorunur prompt etiketleri degismez; modul raw value'lari
  asla yeniden adlandirilmaz** (persistence anahtari).
- Yeni `Codable` alanlar `decodeIfPresent` + default (ileri-guvenli JSON);
  eski SRS alanlari FSRS gecisinde rollback icin korunur.
- Yeni kullanici metinleri `Localizable.xcstrings`'e TR cevirisiyle
  (`Text(String)` tuzagi — enum'larda `localizedTitle`).
- Buyuk body'ler staged `baseContent`/`withX(_:)` deseni (CI tip-denetimi
  tavani); glass yalnizca `dsGlass*` token'lari uzerinden, macOS 26 kapili,
  macOS 15 Material fallback'li.
- **Apple-Developer-kilitli kalemler planlanmaz** (widget, App Group, CloudKit,
  notarization) — uyelik duyurulana kadar Won't. Ayrica bilinclice disarida:
  sayfalanmis EPUB (v10 adayi; scrubber cogu degeri 1/5 maliyetle verir),
  NotificationCenter mimari degisimi, AnkiConnect, embeddings/RAG,
  frekans listeleri.

---

## Sprint 1 — v1.29.0 "Cekirdek dongu + temel" (Must)

Amac: secim surtunmesini kaldirmak; persistence'i sonraki her sey icin guvenli
hale getirmek.

- [x] **Yuzen secim aksiyon cubugu (U1) — PDF**: secimin yaninda glass kapsul
      (Save Word / Analyze / Highlight / Speak / Copy) — yeni
      `UI/SelectionActionBar.swift` (`dsGlassCapsule`, notr glass + duz ikonlar).
      PDF: `NSHostingView` alt-view, `pdfView.convert(selection.bounds)`'tan
      konum, seciminin ustune (yer yoksa altina) + yatay clamp; scroll takibi
      dahili `NSScrollView` contentView bounds observer'i ile; deselect/doc
      degisiminde temiz kapanis. Aksiyonlar mevcut `contextSaveWord`/
      `contextHighlight(.yellow)`/`contextSpeak`/`contextCopy` +
      `.inspectorRunLastModule`. **CANLI DOGRULANDI** (ikinci instance, gercek
      PDF: cubuk secimin ustunde dogru konumda, 5 ikon, glass render tamam)
- [x] **U1 — EPUB**: JS `selectionchange` → `getBoundingClientRect` mesaja
      eklendi + secim varken scroll'da rect'i yeniden postlayan rAF-throttle'li
      dinleyici (`EPUBReaderView` selectionScript). `EPUBViewManager` mesaj
      handler'i rect + `reposition` bayragini parse eder; ayni
      `UI/SelectionActionBar.swift` WKWebView'a `NSHostingView` alt-view olarak
      host edilir. WKWebView **flipped** (client rect dogrudan subview
      koordinati — hover NSPopover ayni konvansiyonu kullanir), bar seciminin
      ustune (yer yoksa altina). Aksiyonlar `(webView as? RELLEPUBWebView)`'in
      mevcut `onContextSaveWord/Highlight(.yellow)/Speak` closure'larina +
      `.inspectorRunLastModule`; Copy = `NSPasteboard`. `openChapter`'da gizlenir.
      **CANLI DOGRULANDI** (Why We Sleep EPUB: cubuk secimin ustunde dogru
      konumda, 5 ikon, deselect'te gizlenir). Not: acik EPUB zemininde glass
      kapsul PDF koyu zeminine gore daha soluk — ileride opaklik rotusu olabilir
- [x] **Async debounced persistence (T1)**: yeni `Models/DebouncedFileWriter.swift`
      — encode closure main'de (1×/pencere), atomic `Data.write` off-main
      (util queue); `flush()` senkron; `PersistenceCoordinator.flushAll()` +
      `applicationWillTerminate` hook. 8 JSON store migrate edildi
      (SavedWords + PDF/EPUB highlight/note, EPUB bookmark, ReadingSession,
      RecentDocument×2). Test = writeThrough (debounce 0). PDFBookmark
      (UserDefaults) kapsam disi. 7 writer birim testi + tum store testleri yesil
- [x] **SRS regresyon agi (T2/1)**: yeni `SRSSchedulingTests.swift` — 16 test,
      `applyReview` tam dal kapsamasi (again/good/easy × new/learning/mastered,
      ease clamp 1.3/3.5, +10dk/+8s kesin, eksik-kelime nil) — FSRS'ten ONCE
- [x] Risk azaltim uygulandi: PDF once ship'lendi + dogrulandi; EPUB takip
- [x] Dogrulama: build + tum ilgili test paketleri yesil; PDF cubugu canli
      dogrulandi; ikinci instance kill → termination flush temiz calisti
      (`flushAll`); "Analyze" TR cevirisi (`Analiz Et`) katalogda

## Sprint 2 — v1.30.0 "Zen okuma" (Must + Should)

Amac: dunya standardinda immersive okuma modu + Mac-native gezinme hissi.

- [ ] **Zen modu (U2)**: tam ekran + otomatik gizlenen chrome (hover/timer
      reveal), PDF icin ortalanmis okuma sutunu, context strip gizli; tek
      toggle + kisayol. `ContentView`'de yeni staged wrapper + ayri
      `App/ZenModeOverlay.swift` dosyasi (tip-denetim tavanina dikkat);
      `ReaderMenuCommands`'a kisayol
- [ ] **Ilerleme scrubber'i + kalan sure (U3)**: PDF sayfa scrubber'i;
      EPUB kitap-geneli konum modeli (spine metin-uzunlugu agirlikli,
      `EPUBDocument`) + "bolumde X dk kaldi" tahmini; scrubber otomatik
      gizlenen chrome icinde
- [ ] **Trackpad jestleri (U4)**: PDF pinch-zoom (`allowsMagnification = true`
      sinirli), EPUB magnification jesti → tipografi font boyutu; iki parmak
      swipe sayfa/bolum gecisi
- [ ] **Undo/redo (U5)**: highlight/not/bookmark store'larinda `UndoManager`
      kaydi (⌘Z/⇧⌘Z)
- [ ] **Konum-geri-yukleme (T5)**: 0.3s `Task.sleep` sezgiseli yerine
      document-ready sinyalleri (PDFView document-load notification;
      EPUB `didFinish` + JS ready ping)
- [ ] Dogrulama: zen giris/cikis iki formatta; chrome reveal; scrubber
      dogrulugu; trackpad pinch; her anotasyon turunde ⌘Z; yeniden acilista
      konum flash-jump yok

## Sprint 3 — v1.31.0 "Ogrenme motoru" (Must)

Amac: amiral gemisi ogrenme yukseltmesi — FSRS + lemma + kapsama.

- [ ] **FSRS zamanlayici (L1)**: yeni `Models/FSRSScheduler.swift` (saf
      fonksiyonlar, FSRS-4.5 parametreleri); `SavedWord`'e opsiyonel
      `stability`/`difficulty`/`fsrsState` (`decodeIfPresent`); `applyReview`
      FSRS'e delege, lazy per-word migration (mevcut interval/ease'den
      stability tohumlanir; eski alanlar rollback icin korunur); review
      UI'larinda opsiyonel 4. "Hard" notu (`QuizView`, dashboard karti);
      golden-vector + migration birim testleri
- [ ] **Lemma-farkinda eslestirme (L2)**: yeni `Models/LemmaMatcher.swift`
      (`NLTagger`, kelimenin `language` alanina gore); EPUB/PDF kayitli-kelime
      vurgulamasi cekimleri yakalar ("ran"→"run"); kayit aninda duplicate
      tespiti; lemma nil ise tam-eslesmeye dusulur; belge basina lemma cache
      (mevcut `LRUCache`)
- [ ] **Bilinen-kelime kapsama %'si (L3)**: yeni
      `Models/LexicalProfileService.swift` — belge metnini arka planda
      tokenize (PDF sayfa metni / EPUB spine metni), known/learning/unknown
      % hesabi, belge basina cache; `LibraryView` rozeti + Stats'ta
      kirilim karti ("bu kitap seviyeme uygun mu?")
- [ ] Risk: FSRS migration dogrulugu (Sprint 1 test agi + korunan eski
      alanlar); `NLTagger` lemma kalitesi dile gore degisken (nil → exact
      fallback); dev PDF'lerde tokenizasyon maliyeti (background + cache)
- [ ] Dogrulama: eski `saved_words.json` yuklenir ve makul zamanlar; cekimli
      formlar vurgulanir; kapsama rozeti yeniden acilista stabil; bir kelimeyi
      10x review et → interval buyumesi makul

## Sprint 4 — v1.32.0 "Karaoke + aktif hatirlama" (Should; planli-risk sprinti)

Amac: v8'den ertelenen risk kalemini onceden onaylanmis fallback'iyle ship'lemek.

- [ ] **Karaoke TTS (L4)**: `SpeechManager.currentSentenceIndex`'ten
      cumle-siniri callback'i; EPUB: JS-highlight + scroll-follow
      (`EPUBViewManager`); PDF: `findString` + `setCurrentSelection`,
      eslesme yoksa sessizce atla; `SpeechPlaybackBar`'da toggle.
      **PDF karaoke ~2 gun timebox — asilirsa onceden kararli fallback:
      yalniz-EPUB ship, PDF toggle gizli**
- [ ] **Yazma + dinleme review modlari (L5) + QuizView bolunmesi (T3)**:
      1047 satirlik `QuizView` → `FlashcardSessionView` /
      `MatchingSessionView` / yeni `TypingSessionView`; type-the-answer
      (kati/esnek diff) + duy-hatirla modu
- [ ] **Servis testleri (T4)**: SpeechManager kuyruk/hiz-degisimi testleri
      (karaoke dogrulugunu korur), LLMResilience/circuit-breaker testleri
- [ ] **Cumle madenciligi (L6, sprint yesilse)**: secim cubuguna
      "Save Sentence" → baglam karti (cumle + hedef kelime), review +
      export'a dahil
- [ ] Dogrulama: bolum/sayfa sinirinda karaoke; karaoke ortasinda hiz
      degisimi (re-queue highlight index'ini korur); tema kontrasti;
      typing diff esnekligi; bolunme sonrasi flashcard/matching regresyonu

## Sprint 5 — v1.33.0 "Cila, erisilebilirlik, sertlestirme" (Should/Could + tampon)

Amac: kalite tabani + borc odemesi; Sprint 4 tasmasi icin esnek tampon.

- [ ] **Erisilebilirlik turu (U6)**: DS `micro`/`icon` fontlari sistem metin
      boyutuyla olceklenir; renk-tek durum noktalarina SF Symbol/sekil
      fazlaligi; anotasyon/kelime listelerinde VoiceOver etiket + rotor
      (`DesignSystem`, `InspectorView+Grid`, `AnnotationsView`,
      `SavedWordsListView`)
- [ ] **Dosya bolme (T3)**: `SavedWordsListView` (1039) bolunmesi; dokunulan
      yerlerde firsatci ContentView cikarimi
- [ ] Could kalemleri (kapasite oldukca, sirayla): Quick Lookup HUD'a sistem
      Dictionary Services; PDF karanlik modda gorsel korumasi (U7,
      gorsel-yogun bolgelerde inversion atla/yumusat); .apkg export
      (sistem SQLite3)
- [ ] ROADMAP/CHANGELOG/ARCHITECTURE dokuman kapanisi
- [ ] Dogrulama: buyuk-metin sistem ayari; Reduce Transparency / Increase
      Contrast; VoiceOver ile review akisi turu; Sprint 1–4 amiral gemisi
      ozelliklerinin tam regresyonu

---

## Siralama mantigi

T1 persistence FSRS/kapsamadan once (yazma hacmi artmadan cozulur). Secim
cubugu zen'den once (zen chrome'u gizler; secim-yerel aksiyonlar once var
olmali). FSRS yeni review modlarindan once (modlar nihai notlama modeline
kurulur). Karaoke ortada — SpeechManager testleri var olduktan ve arkada iki
shipped release tampon olustuktan sonra.

## Genel dogrulama (her sprint sonu)

- Build + birim testleri (UI test haric)
- `Localizable.xcstrings`: yeni kullanici metinleri TR cevirisiyle eklendi
  (`Text(String)` tuzagina dikkat — enum'larda `localizedTitle`)
- DS denetimi: ham `.font(.system(size:...))` / ham material yok; istisnalar
  `// DS-exempt:` yorumlu
- macOS 15 fallback yolu derleniyor ve gorsel olarak makul
- JSON gecisleri: eski veri dosyalari kayipsiz yukleniyor (`decodeIfPresent`)
