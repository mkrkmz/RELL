# Katki Rehberi

## Gelistirme Ortami Kurulumu

### Gereksinimler

- macOS 15.0+
- Xcode 16.0+
- [LM Studio](https://lmstudio.ai/) (yerel LLM testi icin)
- Git

### Ilk Kurulum

```bash
# Repoyu klonla
git clone <repo-url>
cd RELL

# Xcode projesini ac
open "Reader for Language Learner/Reader for Language Learner.xcodeproj"
```

### LM Studio Yapilandirmasi

LLM ozelliklerini test etmek icin LM Studio gereklidir:

1. LM Studio'yu indirin ve kurun
2. Bir model yukleyin (onerilen: `google/gemma-3-4b`)
3. Developer > Start Server ile sunucuyu baslatin
4. Varsayilan adres: `http://127.0.0.1:1234`

LM Studio olmadan uygulama PDF okuyucu olarak calisir, ancak kelime analizi ozellikleri devre disi kalir.

## Proje Yapisi

Detayli mimari bilgi icin [ARCHITECTURE.md](ARCHITECTURE.md) dosyasina bakin.

## Kod Standartlari

### Swift Stili

- **Adlandirma:** camelCase (degiskenler, fonksiyonlar), PascalCase (tipler, protokoller)
- **Erisim Kontrolu:** Minimum gereken erisim seviyesini kullanin (`private` > `internal` > `public`)
- **State Management:** `@Observable` + `@MainActor` pattern'ini takip edin
- **Async Islemler:** `async/await` kullanin (Combine kullanmayin)
- **Tasarim Tokenleri:** Renk, tipografi, bosluk icin HER ZAMAN `DS` namespace'ini kullanin

### Dosya Organizasyonu

- Yeni view'lar ilgili klasore eklenmelidir (`App/`, `Reader/`, `Settings/`, vb.)
- Buyuk view'lar extension ile bolunebilir (ornek: `InspectorView+Header.swift`)
- Veri modelleri `Models/` altinda, servis katmani ilgili klasorde (`LLM/`, `Speech/`, `Export/`)
- Her dosya tek bir sorumluluga odaklanmalidir

### Commit Mesajlari

```
<tip>: <kisa aciklama>

<opsiyonel detayli aciklama>
```

**Tipler:**
- `feat:` — Yeni ozellik
- `fix:` — Hata duzeltme
- `refactor:` — Davranis degistirmeyen kod duzenleme
- `docs:` — Dokumantasyon
- `test:` — Test ekleme/duzeltme
- `chore:` — Derleme, bagimlilık, yapilandirma degisiklikleri

**Ornekler:**
```
feat: Anki toplu dis aktarim ozelligi eklendi
fix: PDF arama sonuclarinda yanlis sayfa numarasi duzeltildi
refactor: InspectorView header bilesenini ayri dosyaya tasindi
```

### Branch Stratejisi

```
main          # Kararli, her zaman derlenebilir
  |
  +-- feat/   # Yeni ozellikler (feat/anki-bulk-export)
  +-- fix/    # Hata duzeltmeleri (fix/pdf-search-crash)
  +-- refactor/ # Refactoring (refactor/split-content-view)
```

## Derleme ve Test

```bash
# macOS icin derle
make build

# Testleri calistir
make test

# Lint kontrolu (SwiftLint gerektirir)
make lint

# Temizle
make clean
```

Veya dogrudan Xcode ile: `Cmd + B` (derle), `Cmd + U` (test).

## Pull Request Sureci

1. Ilgili branch'ten yeni bir branch olusturun
2. Degisikliklerinizi yapin ve test edin
3. Commit mesajlarinin kurallara uydugunden emin olun
4. PR acin ve aciklama bolumunu doldurun:
   - Ne degisti?
   - Neden degisti?
   - Nasil test edildi?
5. Derleme ve testlerin gectigini dogrulayin
6. Kod incelemesi bekleyin

## Bilinen Sorunlar ve Katki Alanlari

Mevcut iyilestirme alanlari icin proje issue tracker'ina bakin. Ozellikle bu alanlarda katkiya acigiz:

- Test coverage artirimi
- Erisilebirlik (a11y) iyilestirmeleri
- UI yerellesstirme (i18n)
- Performans optimizasyonlari
- Yeni LLM provider desteği (Ollama, OpenAI API)
