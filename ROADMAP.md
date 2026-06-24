# RELL Roadmap v3 — Okuma Deneyimi, Kelime Organizasyonu ve AI

Onceki roadmap (v2: dashboard gorsel katmani — kapaklar, gunluk hedef,
mini kelime karti, Library, onboarding) 2026-06-11'de tamamlandi.
Bu roadmap bir sonraki iterasyonu kapsar: okuma deneyimi, kelime
organizasyonu, review modlari, AI takip sorusu ve istatistik derinligi.

## Faz 1 — Okuma Deneyimi: Odak Modu + Kalici Highlight (tamamlandi)

- [x] Odak modu: ⇧⌘D ile sidebar + inspector + context strip gizleme; onceki panel
      durumunu hatirlayip cikista geri yukler; toolbar butonu (belge acikken)
- [x] `PDFHighlight` + `PDFHighlightStore` (RELLJSONStore, `pdf_highlights.json`,
      PDFNoteStore kalibi; PDFHighlightRect reuse); 5 renk (`HighlightColor`)
- [x] RELLPDFView sag tik → renkli "Highlight" alt menusu (swatch'li); Coordinator
      annotation render (`kUserHighlightKey`), `.pdfHighlightsChanged` ile re-render
- [x] Sidebar "Marker" sekmesi: liste, tikla → sayfaya git, swipe → sil, swatch menu → renk degistir
- [x] Birim testleri: PDFHighlightStore CRUD, siralama, kalicilik, renk fallback

## Faz 2 — Okuma Deneyimi: Hover Sozluk + Ceviri Seridi (tamamlandi)

- [x] Hover popup: RELLPDFView tracking-area + `selectionForWord`, 500ms debounce;
      NSPopover icinde mini tanim. Cache-first: once kayitli kelime / bellek cache,
      miss'te kisa non-streaming definition istegi (`AsyncLimiter` gate, local provider).
      `hoverDictionaryEnabled` ile kapatilabilir
- [x] Cumle ceviri seridi: ≥3 kelimelik secimde PDF altinda ince serit, ana dile
      ceviri (ayri mini istek, ~240 token); kapat butonu + `sentenceTranslationEnabled` toggle
- [x] Ortak `QuickLookupService` (provider config + ModuleType prompt reuse + cache);
      Settings → General "Reading Aids" bolumu; birim testleri (cache yollari)

Not: hover cache kaynagi olarak InspectorViewModel disk cache yerine kayitli kelimeler +
servis-ici bellek cache kullanildi (daha az coupling, ayni "once cache" davranisi).

## Faz 3 — Kelime Organizasyonu: Etiket & Desteler (tamamlandi)

- [x] `SavedWord.tags: [String]` (geriye uyumlu Codable) + `hasTag`
- [x] `SavedWordsStore`: `allTags`, `words(withTag:)`, `tagCount`, `addTag`/`removeTag`,
      `reviewQueue(includeAll:tag:)` (deste icinde due/fallback); birim testleri
- [x] SavedWordsListView: deste filtre menusu, satir context menusunde "Deck" alt menusu
      + satir etiket chip'leri, detay sheet'inde `TagEditorView` (yeni FlowLayout/TagChip)
- [x] QuizView: deste secici (review kuyrugu tag'e gore daralir)
- [x] AnkiExporter: per-word etiketler `extraTags` ile tags sutununa (dedupe + underscore)

Not: DashboardWordCard kasitli olarak deste secici almadi — minimal "bugun due" karti
sade kalsin diye; deste secimi Review Center'da. Istenirse eklenebilir.

## Faz 4 — Review Yuzeyi: Yeni Quiz Modlari + TTS

- [ ] Mod secici: Flashcard (mevcut) / Coktan Secmeli / Yazarak Hatirlama + Cram anahtari
- [ ] Coktan secmeli: dogru tanim + diger kelimelerin tanimlarindan 3 celdirici
- [ ] Yazarak: terim gosterilir, kullanici anlami yazar, normalize karsilastirma +
      kendi kendini derecelendirme
- [ ] Cram modu: `applyReview` cagrilmaz (SRS bozulmaz), yalnizca oturum istatistigi
- [ ] TTS: QuizView karti, SavedWordsListView satirlari ve DashboardWordCard'a telaffuz
      butonu — `SpeechManager.shared.speak` reuse (`speechRate` AppStorage mevcut)

## Faz 5 — AI: Ask AI Takip Sorusu

- [ ] Inspector sonuc panelinin altina "Ask a follow-up…" alani; prompt = mevcut sistem
      prompt + baglam (terim, cumle, aktif modul ciktisi) + soru
- [ ] Mevcut streaming pipeline + `AsyncLimiter` + iptal mantigi reuse; cevap
      `ResultRenderer` plain gorunumuyle
- [ ] Oturum ici soru-cevap gecmisi (session-scoped, InspectorViewModel'de)

## Faz 6 — Istatistik Derinligi

- [ ] Stats sekmesine "Vocabulary" bolumu: `savedAt` uzerinden kumulatif kelime buyume
      cizgisi + mastery dagilim grafigi (Charts zaten kullaniliyor)
- [ ] Belge detayi: Library kartinda sag tik → "Document Stats" sheet'i: okuma suresi
      (`sessionStore` per-document totals mevcut), kayitli kelime/not/bookmark sayilari,
      okuma ilerlemesi

## Backlog (siralanmamis)

- Gunluk hedef bildirimleri (UserNotifications)
- CSV/Quizlet export
- Kelime listesinden toplu etiket atama
- Highlight'lara not ilistirme
