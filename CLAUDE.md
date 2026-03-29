# RELL - Claude Code Proje Rehberi

## Proje Ozeti

RELL (Reader for Language Learner), SwiftUI tabanli macOS PDF okuyucu + yerel LLM entegrasyonu uygulamasidir. Sadece macOS destekler (AppKit API'leri kullanilir: NSViewRepresentable, NSPasteboard, NSColor, NSSavePanel, NSMenu). Dil ogrencileri icin kelime analizi, baglam icindeki aciklama ve Anki dis aktarim ozellikleri sunar.

## Derleme ve Calistirma

```bash
# Xcode ile ac
open "Reader for Language Learner/Reader for Language Learner.xcodeproj"

# Komut satirindan derleme (macOS)
xcodebuild -project "Reader for Language Learner/Reader for Language Learner.xcodeproj" \
  -scheme "Reader for Language Learner" \
  -destination 'platform=macOS' \
  build

# Testleri calistir
xcodebuild -project "Reader for Language Learner/Reader for Language Learner.xcodeproj" \
  -scheme "Reader for Language Learner" \
  -destination 'platform=macOS' \
  test
```

**Gereksinimler:** Xcode 16+, macOS 15+, LM Studio (yerel LLM sunucusu)
**Platform:** Sadece macOS (iOS desteklenmez — AppKit bagimliliklari mevcut)

## Mimari Kurallar

### State Management
- Tum state nesneleri `@Observable` + `@MainActor` kullanir
- Basit tercihler icin `@AppStorage` (UserDefaults)
- Dependency injection icin `@Environment`
- Reducer/action pattern YOK — dogrudan property mutation

### Dosya Organizasyonu
- `App/` — Ana view'lar (ContentView, InspectorView, SidebarView)
- `Models/` — State nesneleri ve veri modelleri
- `LLM/` — LLM istemcisi ve prompt sistemi
- `Reader/` — PDF bilesenleri
- `UI/` — Tasarim sistemi (`DS` namespace) ve yardimci bilesenler
- `Settings/` — Ayarlar goruntuleri
- `Export/` — Anki entegrasyonu
- `Speech/` — TTS yoneticisi

### Kodlama Kurallari
- Tasarim tokenleri icin HER ZAMAN `DS` namespace'ini kullan (DS.Colors, DS.Typography, DS.Spacing, DS.Radius)
- Yeni goruntuler icin mevcut bilesenler: `DSEmptyState`, `DSToast`, `VisualEffectView`, `.dsCard()`, `.dsShadow()`
- Async islemler icin `async/await` pattern (Combine kullanma)
- Dosya I/O `~/Library/Application Support/RELL/` altinda
- Notification-based iletisim: `.openPDFCommand`, `.inspectorRunLastModule`, `.PDFViewPageChanged`

### LLM Sistemi
- `LLMProvider` protokolu ile soyutlama
- `LLMClient` tek implementation (LM Studio HTTP, OpenAI uyumlu)
- Varsayilan sunucu: `http://127.0.0.1:1234`
- Streaming SSE ile token-token UI guncelleme
- Her modul icin bagimsiz task cancellation destegi
- 20 girislik LRU cache (`InspectorViewModel`)

### Desteklenen Diller (12)
English, Turkish, German, French, Spanish, Japanese, Korean, Chinese, Arabic, Portuguese, Russian, Italian

### Modul Turleri (10)
`definitionEN`, `meaningTR`, `collocations`, `examplesEN`, `pronunciationEN`, `etymologyEN`, `mnemonicEN`, `synonymsEN`, `wordFamilyEN`, `usageNotesEN`

## Onemli Dosyalar

| Dosya | Aciklama |
|-------|----------|
| `Reader_for_Language_LearnerApp.swift` | Uygulama giris noktasi, menu komutlari |
| `App/ContentView.swift` | 3 panelli ana layout (607 satir) |
| `Models/InspectorViewModel.swift` | LLM istek yonetimi + LRU cache |
| `Models/SavedWordsStore.swift` | Kelime CRUD + JSON persistence |
| `LLM/LLMClient.swift` | HTTP istemcisi (streaming + non-streaming) |
| `LLM/ModuleType.swift` | 10 modul tanimi, prompt ve token limitleri |
| `LLM/PromptTemplates.swift` | Sistem prompt sablonlari |
| `UI/DesignSystem.swift` | Merkezi tasarim tokenleri (DS) |

## Bilinen Kisitlamalar

- Test coverage sifir (template testler mevcut ama bos)
- Yapilandirilmis loglama yok (`print()` kullaniliyor)
- Erisilebirlik (a11y) destegi yok
- UI metinleri yerellestirilmemis (hardcoded Ingilizce)
- Force unwrap: `SavedWordsStore.swift:24`, `ReadingSessionStore.swift:24`
- Dis bagimlilik yok — sadece Apple system framework'leri
