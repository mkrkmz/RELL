# RELL Roadmap

Oncelikler: (1) arayuzu daha iyi ve kullanisli hale getirmek, (2) yerel LLM'de hiz ve kesilme problemlerini cozmek.

## Faz 1 — LLM Hiz + Kesilme (aktif)

Kok nedenler:
- Token limitleri kucuk modeller (Gemma 3 4B) icin ayarlanmis; 12B+ modelde gereksiz kesilmeye yol aciyor (`LLM/ModuleType.swift`)
- Kesilme tespiti `finish_reason` yerine "3.5 karakter/token x %90" sezgisiyle yapiliyor (`App/InspectorView.swift`)
- "Run All" 5 istegi ayni anda LM Studio'ya gonderiyor; yerel GPU kuyrukta boguluyor (`App/InspectorView+Grid.swift`)
- Streaming sirasinda her flush'ta tum sonuc hiyerarsisi yeniden render ediliyor (`App/InspectorView+ResultPanel.swift`, `UI/ResultRenderer.swift`)

Is kalemleri:
- [ ] Token limitlerini 12B+ modele gore genislet (~1.5-2x)
- [ ] SSE'de `finish_reason` decode et; truncation rozetini buna bagla
- [ ] Yerel saglayicilarda modul isteklerini sinirli eszamanlilikla calistir (maks 2)
- [ ] Streaming render maliyetini dusur (sade Text, scroll debounce, flush araligi 120ms/80 karakter)
- [ ] Sistem prompt ve modul prompt'larini kisalt (format talimat yuku ~140 token)

## Faz 2 — Streaming Goruntuleme Optimizasyonu

- [ ] Parse sonuclarini memoize et (her delta'da tum buffer'i yeniden regex'lemek yerine `onChange` + `@State`)
- [ ] Collocation/Examples/UsageNotes parser'larini stream bitiminde tek sefer calistir
- [ ] LLM ciktilari icin kalici disk cache (uygulama kapaninca LRU cache kayboluyor)
- [ ] Ayar degisikliginde tum cache'i silmek yerine yalnizca etkilenen anahtarlari sil

## Faz 3 — UI/UX Iyilestirme

- [ ] Monolitik view'lari parcala:
  - `UI/SavedWordsListView.swift` (615 satir) → SearchBar / FilterBar / WordRow ayri dosyalar
  - `App/EmptyStateView.swift` icindeki 4 gomulu struct ayri dosyalara
  - `UI/QuizView.swift` durum makinesini sadelestir
- [ ] SavedWordsListView filtre/siralamayi her render'da hesaplamak yerine cache'le
- [ ] Design System'e buton stilleri (`DSButtonStyle`) ve form alani bilesenleri ekle; Settings gorunumlerini bunlarla birlestir
- [ ] Erisilebilirlik: tum etkilesimli ogelere `accessibilityLabel`/`accessibilityValue` (SidebarView a11y isinin devami), `.help()` tutarliligi
- [ ] ForEach kimliklerini stabilize et (`ForEach(filteredWords, id: \.id)`)
- [ ] PDFKitView highlight yenilemeyi debounce et (sayfa degisiminde tum kelimeler taraniyor)

## Faz 4 — Kalite / Altyapi

- [ ] Yerellestime: `String(localized:)` + Localizable.xcstrings (su an hardcoded Ingilizce)
- [ ] `print()` → `os.Logger` ile yapilandirilmis loglama
- [ ] Force unwrap temizligi (`Models/SavedWordsStore.swift:24`, `Models/ReadingSessionStore.swift:24`)
- [ ] Test kapsamini genislet (LLMClient SSE parser, prompt uretimi, truncation tespiti)
