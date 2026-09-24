# RELL Roadmap v12 — Once Guven, Sonra Sifir Kurulum (3 sprint, v1.39 → v1.41)

Olusturulma: 2026-09-24 (v1.38.0 sonrasi, ~4 haftalik aradan sonra sifirdan
kod incelemesiyle). Kullanici karari (2026-09-24): sira onaylandi, kapsama
metrigi oldugu gibi kalir, `.apkg` export Won't.

Inceleme zemini (Xcode 27.0, macOS 27): temiz Debug build basarili, **30
derleyici uyarisi** (hepsi Swift 6 esanlilik); tam birim paketi **476 test,
0 hata, 1 atlanan**; uygulama kod kapsamasi **%20.9** (FSRS %100,
ResultParser %91, SavedWordsStore %71; InspectorView/PDFKitView/
AnthropicClient %0, LLMResilience %3); SwiftLint 118 kucuk uyari. Asagidaki
iki kritik hata gecici testle **tekrar uretildi**: son bayti kesilen
`saved_words.json` → 0 kelime yuklendi → tek kayittan sonra diskte yalniz
yeni kelime kaldi; yarida kopan stream → `"Hello worldHello world"`.

v11 roadmap kapandi: S1 (Turkce arayuz, 281 metin + `Text(String)` denetimi,
`QuizView` 1204→918) ve S2 (eslestirme oyunu, zamanlamaya yazmaz) birlikte
**v1.38.0** olarak cikti — S2'nin plandaki v1.39 etiketi kullanilmadi. S3
(export / `.apkg`) hic baslamadi; ucuncu devirde kullanici karariyla Won't. v1.38.0'in ilk release run'i test hatasiyla dustu, test
duzeltmesinden sonra tag yeniden itildi (v1.36'dan sonra ikinci kez).

Odak: inceleme, gorunur bir ozellikten once **sessiz veri kaybi ve yanlis
cevap** uretebilen uc hata buldu (bozuk JSON'da kelime hazinesinin silinmesi,
kapanista eski verinin yeniyi ezmesi, stream yeniden denemesinde cevabin iki
kez yazilip diske cache'lenmesi) ve kitabin kendi JavaScript'inin
kullanicinin tiklamasi olmadan uygulama/dosya acabildigi bir EPUB yuzeyi.
Bunlar once. Sonra en buyuk urun firsati: LM Studio kurmadan calisan bir
uygulama (Apple'in cihaz-ici modeli + Translation framework'u).

## Teknik cerceve (tum sprintler icin gecerli)

- **Sifir dis bagimlilik korunur.** Foundation Models, Translation, NaturalLanguage, CoreServices — hepsi sistem framework'u.
- **Deployment target macOS 15 kalir.** macOS 26+ API'leri (`FoundationModels`)
  `#available` / `@available` arkasinda; 15 yolu derlenir ve calisir.
- Her release oncesi **TAM birim test paketi** CI ile birebir komutla kosulur.
  Yeni testler **async metod**; senkron `@MainActor` bloklayan test CI
  runner'ini kilitler. Makineye bagli test dusmez, `XCTSkip` ile atlanir
  (NL lemmatizer, macOS sozlukleri, Apple Intelligence modeli, Translation
  dil paketleri temiz CI runner'inda yok).
- **Persistence kurali (yeni):** hicbir store, okuyamadigi bir dosyanin
  ustune yazmaz. Bozuk dosya karantinaya alinir, kullaniciya soylenir.
- **LLM kurali (yeni):** kismi/hatali bir cevap asla cache'e (bellek veya
  disk) girmez; stream, ilk token geldikten sonra yeniden denenmez.
- **Anlik cevap katmani model cagrisini tamamen bastirir.** Oraya eklenen her
  kaynak (Translation framework dahil) "Yanit Dili" ayarina uymak zorunda.
- Yeni kullanici metinleri `Localizable.xcstrings`'e TR cevirisiyle.
  **`Text(String)` katalogu ATLAR** — enum'larda `localizedTitle`.
- `ResultParser`'a gorunur prompt etiketleri, modul raw value'lari ve
  `@AppStorage` anahtarini besleyen enum raw value'lari **asla** yeniden
  adlandirilmaz. Yeni `Codable` alanlar `decodeIfPresent` + default.
- DS token'lari; ham `.font(.system(size:))` yok, istisna `// DS-exempt:`.
- `Slider(step:)` buyuk araliklarda kullanilmaz; tam ekranda ust pikseller
  menu cubugunundur (v1.37 dersleri).
- Yeni dosyalar hedefe kendiliginden girer — `project.pbxproj` duzenlenmez.
- **Bundle id ve App Sandbox'a dokunulmaz.** Ikisi de degisirse Application
  Support yolu / UserDefaults / Keychain yer degistirir → veri tasima
  gerekir. Apple Developer uyeligiyle (notarization) birlikte, tek seferde.

**Bilinclice v12 disinda:** `.apkg` export (SQLite wrapper, ZIP writer,
zamanlama tohumu — uc roadmap boyunca devredildi, kullanici karariyla Won't;
TSV/CSV/Quizlet export'u yeterli), kapsama metriginin yeniden
kalibrasyonu (kullanici karari: oldugu gibi kalsin), sayfalanmis EPUB, AnkiConnect, embeddings/RAG,
kisiye ozel FSRS agirlik optimizasyonu, PDF koyu-tema figur korumasi,
iOS/iPadOS. Apple-Developer-kilitli kalemler (notarization, widget, App Group,
CloudKit, sandbox acma, bundle id duzeltme) uyelik gelene kadar Won't.

---

## Sprint 1 — v1.39.0 "Guven" (Must)

Amac: uygulama kullanicinin verisini hicbir kosulda sessizce kaybetmesin,
yanlis cevabi kalici hale getirmesin, ve acilan bir kitap uygulamayi
kullanicinin adina disari yonlendiremesin.

**Veri**
- [ ] **Bozuk dosya karantinasi**: `RELLJSONStore.load` decode hatasinda
      `defaultValue` donuyor (`Models/AppLogger.swift:41`) ve ilk kayit
      bos diziyi dosyanin ustune yaziyor → tum kelime hazinesi gider.
      Duzeltme: hatali dosyayi `<ad>.corrupt-<tarih>.json` olarak kopyala,
      store'u "salt-okunur / kurtarma" durumuna al, toast ile soyle.
      Test: bozuk JSON → load → save → orijinal bayt'lar hala diskte
- [ ] **Donen yedekler**: `saved_words.json` ve not/vurgu store'lari icin
      gunluk kopya, son 7 gun (`Backups/`). Ayarlar'da "Yedegi geri yukle"
- [ ] **Kapanista yazma sirasi**: `DebouncedFileWriter.flush()` ana thread'de
      dogrudan yazarken `ioQueue`'da daha eski bir snapshot ucusta olabilir
      ve sonra bitip yeniyi ezer. Duzeltme: nesil sayaci (kilitli), eski
      nesil yazimi atlanir. `ioQueue.sync` KULLANILMAZ (CI kilitlenme dersi)
- [ ] **Tam yedek disa/ice aktarma**: tum store'lari bir klasore
      (`RELL Backup <tarih>/`) disa aktar, ayni klasorden geri yukle —
      makine degisimi ve ileride sandbox tasimasi icin de on kosul

**LLM dogrulugu**
- [ ] **Stream yeniden denemesi**: `ResilientLLMProvider` stream'i bastan
      tekrarliyor, `InspectorView.swift:452` `+= token` ile ekliyor → yarida
      kopan baglantida cevap iki kez yaziliyor. Kural: ilk token geldiyse
      retry yok, hata gosterilir
- [ ] **Hatali modul cache'lenmez**: `snapshotToCache` hatasi olan modulun
      kismi ciktisini diske yaziyor; sonraki acilista "cache hit" olarak
      yarim cevap geliyor
- [ ] **4xx yeniden denenmez** (408/429 haric; 429'da `Retry-After`); simdi
      yanlis model adi 3 deneme yapip circuit breaker'i aciyor
- [ ] **URLSession tekrar kullanimi**: `makeProvider()` her istekte yeni
      `URLSession` uretiyor ve hic `invalidate` edilmiyor — timeout basina
      paylasilan oturum
- [ ] **Anthropic istek sekli (S1 sirasinda bulundu)**: her istek hem
      `temperature` hem `top_p` gonderiyordu — Claude 4.x ikisini birlikte,
      Opus 4.7+/Sonnet 5/Opus 5 ise hicbirini kabul etmez (HTTP 400). Yani
      Anthropic saglayicisi eski varsayilan `claude-sonnet-4-20250514`
      (deprecated) disinda hicbir guncel modelde calismiyordu. `top_p` hic
      gonderilmez, `temperature` yalniz eski modellere; dusunen modellere
      `effort: low` + `max_tokens` payi; varsayilan model `claude-opus-5`
- [ ] Testler: `URLProtocol` stub ile SSE parse (`data:` bosluksuz varyant
      dahil), kopan stream, 401/404/429 davranisi, `AnthropicClient` (su an
      %0), `ResilientLLMProvider` (%3). Inceleme sirasindaki iki probe testi
      (bozuk dosya, cift stream) regresyon testi olarak kalici hale gelir

**EPUB guvenligi**
- [ ] Kitabin kendi JS'i kapali: `defaultWebpagePreferences
      .allowsContentJavaScript = false`; uygulama script'leri ve mesaj
      handler'lari ayri `WKContentWorld`'de (kitap JS'i `rellSelection`
      mesajini taklit edemez)
- [ ] Dis link yalniz `navigationType == .linkActivated` ve `http/https/
      mailto` ise `NSWorkspace.open` — simdi herhangi bir sema (`file://`
      dahil) tiklama olmadan aciliyor (`EPUBViewManager.swift:889`)
- [ ] `scroll(toFragment:)` JSON-encode (su an yalniz `'` kacisli)
- [ ] ZIP: bildirilen `uncompressedSize` icin ust sinir (orn. 256 MB/entry)
      — `Data(count:)` 4 GB'a kadar onceden ayiriyor

**Kucuk borclar**
- [ ] Commit edilmemis katalog degisikligi: 14 metin TR'siz ("Due now",
      "Words saved", "Lifetime accuracy"…) — v1.38 istatistik kutulari
      kataloga girince Xcode topladi, ceviri yapilmadi
- [ ] CI: `test.yml` yalniz PR'da kosuyor, is akisi dogrudan `main` →
      testler ilk kez tag'de kosuyor (v1.36 ve v1.38 release'leri boyle
      dustu). `push: main`'e de ekle

## Sprint 2 — v1.40.0 "Sifir kurulum" (Must, once 1 gunluk spike)

Amac: ilk acilista LM Studio indirmeden, API anahtari girmeden calisan bir
uygulama. Bugun onboarding'in ilk adimi bir sunucu kurmak. (Not: gelistiricinin
kendi kurulumu Ollama uzerinden bulut model — `gemma4:31b-cloud`; yani hover,
cumle cevirisi ve CEFR tahmini zaten her secimde agdan gidiyor. Translation
kalemi bu kurulumda da gecikmeyi ve istek sayisini dusurur.)

- [ ] **Spike (kapi, ~1 gun)**: `FoundationModels` (`SystemLanguageModel`)
      ile 10 modulu 12 dilde dene. Olc: kalite (etimoloji/IPA zayif
      olabilir), gecikme, desteklenen diller (Turkce/Arapca vb. dogrulanacak),
      baglam siniri. Karar tablosu: hangi modul hangi dilde "Apple" ile
      verilebilir. **Kapi gecilmezse yalniz Translation kalemi ship'lenir**
- [ ] `LLMProviderType.appleOnDevice` (macOS 26+, `availability` kontrollu):
      streaming `LanguageModelSession`, `LLMProvider` uyumu; model yoksa
      (Apple Intelligence kapali, desteklenmeyen dil/cihaz) secenek gorunmez
      ve nedeni soylenir. Onboarding'de mevcutsa varsayilan
- [ ] Modul bazinda yedek saglayici: Apple modelinin zayif oldugu modul
      (spike'a gore) kullanicinin ikinci saglayicisina duser
- [ ] **Cumle cevirisi Translation framework'u ile** (macOS 15+): cevrimdisi,
      ucretsiz, hizli; dil paketi yoksa sistem indirme istemi. LLM yolu
      yedek olarak kalir. Bugun her secim, bulut saglayicida ucretli bir
      istek (`sentenceTranslationEnabled` varsayilan `true`)
- [ ] Gizlilik ekrani: hangi ozellik hangi saglayiciya ne gonderiyor
      (hover, ceviri, CEFR tahmini, sayfa analizi) — tek bakista
- [ ] Testler: saglayici secimi/yedege dusme mantigi saf fonksiyon olarak;
      model/dil paketi olmayan runner'da `XCTSkip`

## Sprint 3 — v1.41.0 "Pencere modeli" (Could)

Amac: en cok degisen iki gorunumu test edilebilir hale getirmek. v11'deki
"ContentView bolunmez" karari **dosya bolme** icindi (private `@State`
extension'a tasinamiyor); buradaki oneri farkli: state'i bir modele tasimak.

- [ ] `ReaderWindowModel` (`@Observable @MainActor`, pencere basina):
      `ContentView`'daki 25 `@State` + 21 `onChange`'in belgeye ait olanlari.
      View yalniz baglar. Hedef `ContentView` < 800 satir
- [ ] LLM istek orkestrasyonu `InspectorView`'dan (`fetchModule` gorunumun
      icinde) `InspectorViewModel`'e — bugun test edilemiyor
- [ ] `@AppStorage` anahtarlari tek `enum` sabitinde (30 anahtar, bazisi
      4 yerde string literal olarak tekrar)
- [ ] **30 esanlilik uyarisini sifirla**, sonra Swift 6 dil modu (bugun
      `SWIFT_VERSION = 5.0`, README rozeti "6.2" diyor). Uyarilarin cogu
      `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` altinda `@MainActor`
      kalmis saf kodun arka planda cagrilmasi: `EPUBDocument` (8, ZIP okuma),
      `BookCoverageService`/`LexicalProfileService`/`InflectedTermService`
      (`Task.detached` icinden), `PDFKitView`/`EPUBViewManager` (yakalanan
      `self`), `SpeechManager` (`AVSpeechSynthesizer`). Cozum cogunlukla
      `nonisolated` isaretlemek; bugun calisiyor ama Swift 6'da hata

---

## Hijyen (herhangi bir sprintle, tek commit)

- `Configurations/*.xcconfig` projeye bagli degil (`baseConfigurationReference`
  yok) — `RELL_DEFAULT_LLM_*` hic okunmuyor. Bagla ya da sil
- `ARCHITECTURE.md` bayat: cache 20 degil 50 giris; API anahtari artik
  Keychain'de, UserDefaults listesinde duruyor
- `HANDOFF_SUMMARY.md` (Mayis) ve `docs/phase-*-issues.md` tarihsel — sil
  veya `docs/archive/`
- Dogrulanacak: `open -g` ile (arka planda) baslatilan uygulama hic pencere
  acmadi, File > New Window gerekti. Normal Dock/Finder acilisinda tekrar
  dene; tekrarlarsa bos durum restorasyonu incelenir
- Test hedefleri `MACOSX_DEPLOYMENT_TARGET = 26.2` (uygulama 15.0); CI
  komut satirinda eziyor, yerelde gizli bir fark

## Genel dogrulama (her sprint sonu)

- Build + **tam birim test paketi** (UI testleri haric), CI ile birebir komut
- `Localizable.xcstrings`: yeni metinler TR cevirisiyle; katalog JSON gecerli;
  commit edilmemis katalog degisikligi birakilmaz
- DS denetimi; macOS 15 fallback yolu derleniyor
- CHANGELOG (kullanici-odakli dil) → tag `vX.Y.Z` → push → **CI release
  run'i izlenir**, DMG uretimi teyit edilir
