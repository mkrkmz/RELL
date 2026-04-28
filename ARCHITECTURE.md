# RELL - Mimari Dokumantasyon

## Genel Bakis

RELL, sadece macOS icin gelistirilmis 3 panelli bir masaustu uygulamasidir: sol tarafta sidebar (sayfa onizleme, yer imleri, kaydedilen kelimeler, istatistikler), ortada PDF okuyucu, sag tarafta inspector (LLM destekli kelime analizi).

```
+-------------+------------------+-----------+
|             |                  |           |
|  Sidebar    |    PDF Reader    | Inspector |
| (daraltilir)|                  |(daraltilir)|
|             |                  |           |
| - Sayfalar  |  - Metin secimi  | - Modul   |
| - Icerik    |  - Baglam menusu |   Izgara  |
| - Yer imleri|  - Arama         | - Sonuc   |
| - Kelimeler |                  |   Paneli  |
| - Istatistik|                  | - Kaydet  |
+-------------+------------------+-----------+
```

## Katman Mimarisi

```
+--------------------------------------------------+
|                  Presentation                     |
|  ContentView, InspectorView, SidebarView, ...     |
+--------------------------------------------------+
           |              |              |
+------------------+  +----------+  +----------+
|  State (Models)  |  | Services    |  | UI System|
| SelectionState   |  | LLMProvider |  | DS       |
| SavedWordsStore  |  | Speech   |  | Result   |
| ReadingSession   |  | Anki     |  | Renderer |
| InspectorVM      |  | Export   |  |          |
+------------------+  +----------+  +----------+
           |              |
+--------------------------------------------------+
|               Persistence / IO                    |
|  JSON Files (App Support) | UserDefaults | URLSession
+--------------------------------------------------+
```

## State Management

### @Observable Pattern

Tum state nesneleri `@Observable` macro ve `@MainActor` ile isaretlenmistir:

```swift
@MainActor @Observable
final class SavedWordsStore { ... }
```

**State Nesneleri:**

| Sinif | Sorumluluk | Yasam Suresi |
|-------|-----------|--------------|
| `SelectionState` | Aktif PDF, secili metin, baglam cumlesi | ContentView @State |
| `SavedWordsStore` | Kelime CRUD + JSON persistence | ContentView @State |
| `ReadingSessionStore` | Okuma oturumu takibi + istatistik | ContentView @State |
| `InspectorViewModel` | LLM istek/yanit yonetimi + LRU cache | InspectorView @State |
| `PDFViewManager` | PDFView koordinasyonu (zoom, sayfa) | ContentView @State |
| `PDFSearchManager` | PDF icinde metin arama | ContentView @State |
| `SpeechManager` | Text-to-speech (singleton) | Static shared |

### Veri Akisi

```
Kullanici metin secer
      |
      v
PDFKitView.Coordinator (NSNotification)
      |
      v
SelectionState.selectedText guncellenir
      |
      v
InspectorView degisikligi gozlemler (90ms debounce)
      |
      v
Kullanici modul butonuna tiklar
      |
      v
InspectorViewModel.fetchModule()
      |
      +-- Cache kontrol (LRU hit?) ---> Aninda goster
      |
      +-- Cache miss --> LLMProvider.stream()
                              |
                              v
                    LM Studio SSE yaniti
                              |
                              v
                    Token token UI guncelle
                              |
                              v
                    outputs[module] = sonuc
                              |
                              v
                    Cache'e kaydet (snapshotToCache)
```

## LLM Entegrasyonu

### API Kontrati

LM Studio, Ollama ve OpenAI-compatible provider'lar OpenAI uyumlu chat completions kontratini kullanir:

**Endpoint:** `POST {serverURL}/v1/chat/completions`

**Istek:**
```json
{
  "model": "google/gemma-3-4b",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."}
  ],
  "temperature": 0.1-0.3,
  "max_tokens": 100-900,
  "top_p": 0.9,
  "stream": true
}
```

**Yapilandirma Degerleri:**
- Varsayilan sunucu: `http://127.0.0.1:1234`
- Varsayilan model: `google/gemma-3-4b`
- Timeout: 30 saniye (10-120 arasi ayarlanabilir)

### Modul Sistemi

10 analiz modulu, her biri farkli prompt, token limiti ve sicaklik degerine sahip:

| Modul | Dil | Format | Sicaklik |
|-------|-----|--------|----------|
| Definition | Ingilizce | plain | 0.1 |
| Meaning | Ana dil | plain | 0.1 |
| Collocations | Karisik | markdown | 0.15 |
| Examples | Ingilizce | plain | 0.2 |
| Pronunciation | Ingilizce | plain | 0.1 |
| Etymology | Ingilizce | plain | 0.1 |
| Mnemonic | Ingilizce | plain | 0.3 |
| Synonyms | Ingilizce | plain | 0.1 |
| Word Family | Ingilizce | plain | 0.1 |
| Usage Notes | Ingilizce | plain | 0.1 |

### Provider Soyutlamasi

```swift
protocol LLMProvider {
    func chat(messages:model:temperature:maxTokens:topP:) async throws -> String
    func stream(messages:model:temperature:maxTokens:topP:onToken:) async throws -> String
}
```

`LLMClient` OpenAI-compatible provider'lari, `AnthropicClient` Claude Messages API'yi uygular. `ResilientLLMProvider` retry, circuit breaker ve kullaniciya okunabilir hata mesajlari icin bu provider'lari sarar.

## Persistence

### JSON Dosya Tabanlı Depolama

Tum veri `~/Library/Application Support/RELL/` altinda:

| Dosya | Model | Limit |
|-------|-------|-------|
| `saved_words.json` | `[SavedWord]` | Limitsiz |
| `reading_sessions.json` | `[ReadingSession]` | 500 oturum |
| `pdf_notes.json` | `[PDFNote]` | Limitsiz |
| `recent_documents.json` | `[RecentDocument]` | 12 belge |

**Yedekleme/Atomik Yazma:** Store'lar ortak `RELLJSONStore` yardimcisiyla JSON encode/decode eder, atomik yazar ve bos/bozuk persistence dosyalarinda uygulamayi bozmak yerine guvenli varsayilana doner. Hatalar `AppLogger.persistence` ile loglanir.

### UserDefaults

Kullanici tercihleri `@AppStorage` ile UserDefaults'ta saklanir:

- Panel genislikleri (`sidebarWidth`, `inspectorWidth`)
- Tema (`appTheme`, `pageTheme`)
- Dil secimi (`nativeLanguage`, `targetLanguage`)
- LLM ayarlari (`llmProviderType`, `llmServerURL`, `llmModel`, `llmRequestTimeout`, `llmAPIKey`)
- Domain tercihi (`domainPreference`)
- Yer imleri (`rell_pdf_bookmarks_v1`)

## Onbellekleme (Cache)

### LRU Cache

`InspectorViewModel` icinde 20 girislik LRU cache:

**Anahtar:** `OutputCacheKey(term, mode, detail, domain)`
**Deger:** Tum modul ciktilari + yukleme/hata durumlari

- Kelimeler arasi geciste cache korunur
- Yeni kelime sorgulandiginda eski girislerin en az kullanilanı silinir
- `snapshotToCache()` — mevcut durumu cache'e yaz
- `loadFromCache()` — cache'ten geri yukle

### Task Yonetimi

```swift
var activeTasks: [ModuleType: Task<Void, Never>]
```

- Her modul icin bagimsiz async task
- Kelime degistiginde tum aktif task'lar iptal edilir
- 90ms debounce ile gereksiz istekler onlenir

## Tasarim Sistemi (DS)

Merkezi `DS` enum'u tum gorsel tokenlari icerir:

- **Renkler:** Sistem-uyumlu (acik/koyu), semantik (success, warning, danger)
- **Tipografi:** 8 stil (largeTitle → caption)
- **Bosluk:** 8 olcek (xxs:2 → xxxl:48)
- **Koseleme:** 5 olcek (xs:4 → xl:20)
- **Animasyon:** standard, fast, spring, springFast, snappy
- **Golge:** subtle, card, float

**View Extension'lari:** `.dsShadow()`, `.dsCard()`, `.dsToast()`, `.dsOverlineLabel()`
**Hazir Bilesenler:** `DSEmptyState`, `DSToast`, `VisualEffectView`

## Dosya Organizasyonu

```
Reader for Language Learner/
  Reader_for_Language_LearnerApp.swift   # @main giris noktasi + menu komutlari
  App/              # Ana UI goruntuleri
  Models/           # @Observable state nesneleri + veri modelleri
  LLM/              # LLM istemcisi, protokol, prompt sablonlari
  Reader/           # PDF bilesenleri
    PDF/            # PDFKit wrapper'lari
    Bookmarks/      # Yer imi goruntusu
    Stats/          # Okuma istatistikleri goruntusu
  UI/               # Tasarim sistemi + sonuc gosterimi
  Settings/         # Ayarlar goruntuleri (General, LLM, Appearance)
  Export/           # Anki entegrasyonu
  Speech/           # Text-to-speech
  Assets.xcassets/  # Gorseller, uygulama ikonu, renkler
```
