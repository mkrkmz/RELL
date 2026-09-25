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
- [x] **Bozuk dosya karantinasi**: `RELLJSONStore.load` decode hatasinda
      `defaultValue` donuyor (`Models/AppLogger.swift:41`) ve ilk kayit
      bos diziyi dosyanin ustune yaziyor → tum kelime hazinesi gider.
      Yapildi: dosya `<ad>.corrupt-<zaman>.json` olarak **tasinir** (rename,
      bayt'lar aynen), store bos baslar, ilk pencere kalici bir alert ile
      soyler (Finder'da goster / yedekten geri yukle). "Salt-okunur store"
      gerekmedi: dosya kenardayken yeni kayit onu ezemez
- [x] **Donen yedekler**: `saved_words.json` ve not/vurgu store'lari icin
      gunluk kopya, son 7 gun (`Backups/`). Ayarlar'da "Yedegi geri yukle"
- [x] **Kapanista yazma sirasi**: `DebouncedFileWriter.flush()` ana thread'de
      dogrudan yazarken `ioQueue`'da daha eski bir snapshot ucusta olabilir
      ve sonra bitip yeniyi ezer. Duzeltme: nesil sayaci (kilitli), eski
      nesil yazimi atlanir. `ioQueue.sync` KULLANILMAZ (CI kilitlenme dersi)
- [x] **Tam yedek disa/ice aktarma**: tum store'lari bir klasore
      (`RELL Backup <tarih>/`) disa aktar, ayni klasorden geri yukle —
      makine degisimi ve ileride sandbox tasimasi icin de on kosul

**LLM dogrulugu**
- [x] **Stream yeniden denemesi**: `ResilientLLMProvider` stream'i bastan
      tekrarliyor, `InspectorView.swift:452` `+= token` ile ekliyor → yarida
      kopan baglantida cevap iki kez yaziliyor. Kural: ilk token geldiyse
      retry yok, hata gosterilir
- [x] **Hatali modul cache'lenmez**: `snapshotToCache` hatasi olan modulun
      kismi ciktisini diske yaziyor; sonraki acilista "cache hit" olarak
      yarim cevap geliyor
- [~] **4xx yeniden denenmez** (408/409/429 haric) — `Retry-After` okunmadi, 429 ustel beklemeyle yeniden denenir; simdi
      yanlis model adi 3 deneme yapip circuit breaker'i aciyor
- [x] **URLSession tekrar kullanimi**: `makeProvider()` her istekte yeni
      `URLSession` uretiyor ve hic `invalidate` edilmiyor — timeout basina
      paylasilan oturum
- [x] **Anthropic istek sekli (S1 sirasinda bulundu)**: her istek hem
      `temperature` hem `top_p` gonderiyordu — Claude 4.x ikisini birlikte,
      Opus 4.7+/Sonnet 5/Opus 5 ise hicbirini kabul etmez (HTTP 400). Yani
      Anthropic saglayicisi eski varsayilan `claude-sonnet-4-20250514`
      (deprecated) disinda hicbir guncel modelde calismiyordu. `top_p` hic
      gonderilmez, `temperature` yalniz eski modellere; dusunen modellere
      `effort: low` + `max_tokens` payi; varsayilan model `claude-opus-5`
- [x] Testler (29 yeni: `PersistenceSafetyTests`, `LLMTransportTests`,
      `EPUBSecurityTests`; yazma sirasi ve JS kapatma testleri mutant ile
      dogrulandi — duzeltme geri alininca dusuyorlar). `URLProtocol` stub ile SSE parse (`data:` bosluksuz varyant
      dahil), kopan stream, 401/404/429 davranisi, `AnthropicClient` (su an
      %0), `ResilientLLMProvider` (%3). Inceleme sirasindaki iki probe testi
      (bozuk dosya, cift stream) regresyon testi olarak kalici hale gelir

**EPUB guvenligi**
- [x] Kitabin kendi JS'i kapali: `defaultWebpagePreferences
      .allowsContentJavaScript = false`; uygulama script'leri ve mesaj
      handler'lari ayri `WKContentWorld`'de (kitap JS'i `rellSelection`
      mesajini taklit edemez)
- [x] Dis link yalniz `navigationType == .linkActivated` ve `http/https/
      mailto` ise `NSWorkspace.open` — simdi herhangi bir sema (`file://`
      dahil) tiklama olmadan aciliyor (`EPUBViewManager.swift:889`)
- [x] `scroll(toFragment:)` JSON-encode (su an yalniz `'` kacisli)
- [x] ZIP: bildirilen `uncompressedSize` icin ust sinir (orn. 256 MB/entry)
      — `Data(count:)` 4 GB'a kadar onceden ayiriyor

**Kucuk borclar**
- [x] Commit edilmemis katalog degisikligi: 14 metin TR'siz ("Due now",
      "Words saved", "Lifetime accuracy"…) — v1.38 istatistik kutulari
      kataloga girince Xcode topladi, ceviri yapilmadi
- [x] CI: `test.yml` yalniz PR'da kosuyor, is akisi dogrudan `main` →
      testler ilk kez tag'de kosuyor (v1.36 ve v1.38 release'leri boyle
      dustu). `push: main`'e de ekle
- [ ] **Canli tur (kullaniciya kaldi, ekran kilitliydi)**: Ayarlar ▸ Genel ▸
      Yedekler bolumu; bir EPUB acip secim/hover/vurgu/karaoke'nin JS
      kapaliyken calistigi; bir Claude modeliyle Inspector istegi
- [x] Dogrulama: tam birim paketi CI komutuyla **505 test, 0 hata, 1
      atlanan**; derleyici uyarisi 30 → 29 (yeni kodda uyari yok);
      `-exportLocalizations` ile cevirisiz kalan yalniz format dizeleri

## Sprint 2 — v1.40.0 "Sifir kurulum" (Must, once 1 gunluk spike)

Amac: ilk acilista LM Studio indirmeden, API anahtari girmeden calisan bir
uygulama. Bugun onboarding'in ilk adimi bir sunucu kurmak. (Not: gelistiricinin
kendi kurulumu Ollama uzerinden bulut model — `gemma4:31b-cloud`; yani hover,
cumle cevirisi ve CEFR tahmini zaten her secimde agdan gidiyor. Translation
kalemi bu kurulumda da gecikmeyi ve istek sayisini dusurur.)

- [x] **Spike (kapi)** — 2026-09-24, macOS 27, gercek prompt'lar, 5 dil
      cifti (TR→EN, EN→DE, TR→DE, EN→JA, EN→ES) x 10 modul + cumle cevirisi.
      **Kapi modul bazinda gecildi.**
      - Gecikme: medyan 0.9 sn, p90 2.8 sn, en fazla 3.0 sn
      - Diller: 12'nin 10'u; **Arapca ve Rusca desteklenmiyor**
      - Guclu: tanim, anlam (TR), ornekler, es anlamlilar, kullanim notlari
        (parser etiketleri FREQ:/REG: korunuyor), cumle cevirisi
      - Sinirda: esdizimler (koseli parantez sizintisi, "English only"
        ifadesi), kelime ailesi (uydurma "resiliencing")
      - Guvenilmez: **telaffuz** (DE/JA/ES IPA'si tamamen yanlis),
        **etimoloji** (uydurma koken: "Verstandnis Latince"),
        **hatirlatici** (anlamsiz)
- [x] **Apple cihaz-ici katman** (macOS 26+): ayri bir `LLMProviderType`
      yerine yapilandirilmis saglayicinin ONUNDE bir katman
      (`AppleOnDevice.route`, saf fonksiyon). Kullanici karari 1a: guvenilir
      modul Apple'da, zayif modul yapilandirilmis saglayiciya. Ayarlar'da
      anahtar (varsayilan acik) + kullanilamama nedeni; onboarding "hazir"
      der. Apple istekleri retry/circuit breaker/yerel kuyruktan gecmez
- [x] Modul bazinda yedek: telaffuz, etimoloji, hatirlatici, esdizim,
      kelime ailesi → yapilandirilmis saglayici; o da ulasilamazsa hata
      mesaji nedenini soyler (ikinci bir saglayici ayari eklenmedi — mevcut
      saglayici yedek rolunde)
- [x] **Cumle cevirisi Translation framework'u ile** (macOS 15+, kullanici
      karari 2a: varsayilan; Ayarlar ▸ Genel'de secilebilir): cevrimdisi,
      ucretsiz, hizli; dil paketi yoksa sistem indirme istemi. LLM yolu
      yedek olarak kalir. Bugun her secim, bulut saglayicida ucretli bir
      istek (`sentenceTranslationEnabled` varsayilan `true`)
- [x] Gizlilik ozeti (Ayarlar ▸ AI, canli yonlendirmeden hesaplanir): hangi ozellik hangi saglayiciya ne gonderiyor
      (hover, ceviri, CEFR tahmini, sayfa analizi) — tek bakista
- [x] Testler (10): yonlendirme kurallari, her modulun bilincli
      siniflandirilmasi, canli streaming delta'lari ve dil destegi
      (modelsiz makinede `XCTSkip`), Translation dil kodlari, cache
- [x] Dogrulama: tam paket **515 test, 0 hata**; uyari 29 (yeni kodda yok)
- [ ] **Canli tur (kullaniciya kaldi)**: Xcode'dan acilmis eski bir kopya
      (ayni bundle id, ayni veri) aciktti; iki kopya ayni dosyalara yazdigi
      icin yenisi kapatildi. Kontrol: Ayarlar ▸ AI (anahtar + ozet), bir
      kelimede tanim Apple'dan / etimoloji saglayicidan, cumle seridinde
      dil paketi istemi

## Sprint 3 — v1.41.0 "Pencere modeli" (Could)

Amac: en cok degisen iki gorunumu test edilebilir hale getirmek. v11'deki
"ContentView bolunmez" karari **dosya bolme** icindi (private `@State`
extension'a tasinamiyor); buradaki oneri farkli: state'i bir modele tasimak.

- [x] `ReaderWindowModel` (`@Observable @MainActor`, pencere basina):
      yoneticiler, panel/odak/zen durumu ve gecisleri, bul cubugu, PDF sayfa
      konumlari + acilista geri yukleme. Gecisler saf; animasyon view'da.
      State modelde oldugu icin dosya bolme de mumkun oldu:
      **`ContentView` 1504 → 669 satir** + `ContentView+ContextStrip/
      Toolbar/Actions/Commands.swift`. 11 test. Sayfa konumlari ayni
      anahtar ve JSON bicimiyle (eski deger okunuyor, testli)
- [x] LLM istek orkestrasyonu `InspectorViewModel.start`/`startFollowUp`'a.
      Tasirken bulunan yaris: yeniden calistirilan modulun iptal edilen eski
      istegi bitince yenisinin `loading`/`activeTasks`/ciktisini eziyordu
      (Ask AI'da da). Calisma kimligiyle kapandi; iki yaris testi koruma
      kaldirilinca dusuyor. 7 test
- [x] `StorageKey`: 30 cipla anahtar tek enum'da, degerler testle sabit
- [x] **Uyarilar 29 → 0** (test hedefinde 18 → 0). Swift 6 dil modunda
      uygulama hedefi **derleniyor**; `SWIFT_VERSION` bilincli olarak 5'te
      birakildi: Swift 6, ObjC API'lerine verilen closure'lara calisma
      zamani izolasyon denetimi ekler (Spotlight tamamlama blogu gibi arka
      plan cagrilari cokebilir) — once canli tur. `decidePolicyFor` imzasi
      SDK ile birebir eslestirildi
- [x] Dogrulama: tam paket **533 test, 0 hata**, temiz derleme 0 uyari
- [ ] **Canli tur (kullaniciya kaldi)**: odak/zen giris-cikis, zen'den
      yesil butonla cikis, PDF'i yeniden acinca son sayfa, bul cubugu,
      Inspector'da bir modulu calisirken yeniden baslatma
- [ ] Sonraki adim (v13 adayi): Swift 6 modunu ac — once ObjC tamamlama
      bloklarini (CSSearchableIndex, UNUserNotificationCenter, NSWorkspace)
      canli turda dogrula

---

## Hijyen

- [x] `Configurations/*.xcconfig` silindi (projeye hic bagli degildi;
      sandbox'i acik gosteriyordu, gercekte kapali)
- [x] `ARCHITECTURE.md` guncellendi (v1.39–v1.41 bilesenleri, 50'lik
      cache, Keychain); README (sifir kurulum, yedekler, rozet)
- [x] `HANDOFF_SUMMARY.md` ve `docs/phase-*-issues.md` → `docs/archive/`
- [ ] Dogrulanacak: `open -g` ile baslatilan uygulama pencere acmadi
- [ ] Test hedefleri `MACOSX_DEPLOYMENT_TARGET = 26.2` (uygulama 15.0);
      CI komut satirinda eziyor — dokunulmadi

## Genel dogrulama (her sprint sonu)

- Build + **tam birim test paketi** (UI testleri haric), CI ile birebir komut
- `Localizable.xcstrings`: yeni metinler TR cevirisiyle; katalog JSON gecerli;
  commit edilmemis katalog degisikligi birakilmaz
- DS denetimi; macOS 15 fallback yolu derleniyor
- CHANGELOG (kullanici-odakli dil) → tag `vX.Y.Z` → push → **CI release
  run'i izlenir**, DMG uretimi teyit edilir
