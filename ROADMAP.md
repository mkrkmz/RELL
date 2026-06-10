# RELL Roadmap

Oncelikler: (1) arayuzu daha iyi ve kullanisli hale getirmek, (2) yerel LLM'de hiz ve kesilme problemlerini cozmek.

## Faz 1 — LLM Hiz + Kesilme (aktif)

Kok nedenler:
- Token limitleri kucuk modeller (Gemma 3 4B) icin ayarlanmis; 12B+ modelde gereksiz kesilmeye yol aciyor (`LLM/ModuleType.swift`)
- Kesilme tespiti `finish_reason` yerine "3.5 karakter/token x %90" sezgisiyle yapiliyor (`App/InspectorView.swift`)
- "Run All" 5 istegi ayni anda LM Studio'ya gonderiyor; yerel GPU kuyrukta boguluyor (`App/InspectorView+Grid.swift`)
- Streaming sirasinda her flush'ta tum sonuc hiyerarsisi yeniden render ediliyor (`App/InspectorView+ResultPanel.swift`, `UI/ResultRenderer.swift`)

Is kalemleri:
- [x] Token limitlerini 12B+ modele gore genislet (~1.5-2x)
- [x] SSE'de `finish_reason` decode et; truncation rozetini buna bagla
- [x] Yerel saglayicilarda modul isteklerini sinirli eszamanlilikla calistir (maks 2 — `AsyncLimiter`)
- [x] Streaming render maliyetini dusur (scroll throttle ~6/sn, flush araligi 120ms/80 karakter)
- [x] Sistem prompt'unu kisalt (modul prompt format kaliplari ResultParser'a bagli — bilerek dokunulmadi)

## Faz 2 — Streaming Goruntuleme Optimizasyonu (tamamlandi)

- [x] Parse sonuclarini memoize et (`ParsedResultCache` — collocations + usage notes; satir bolme parser'lari ucuz, memoize edilmedi)
- [x] LLM ciktilari icin kalici disk cache (`llm_output_cache.json`, kapasite 50, LRU sirasi korunarak)
- [x] Ayar degisikliginde secici invalidation: native dil cache anahtarina eklendi; provider/model/dil degisimi cache'i silmiyor (yalnizca sunucu URL degisimi siler)

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
