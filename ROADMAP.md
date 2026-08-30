# RELL Roadmap v11 — Once Kullaniciya Dokunanlar (3 sprint, v1.38 → v1.40)

Olusturulma: 2026-08-28 (v1.37.0 sonrasi). v10 roadmap kapandi: v1.35.0 tekrar
modlari (dinleme + otomatik notlama + `QuizSession`), v1.36.0 lemma-farkinda
vurgulama + kitap-geneli kapsama (ve iki vurgulama hatasi), v1.37.0 okuma UX
(sayfa scrubber, pinch→font, swipe→bolum) + sistem sozlugu katmani + T3 borcu.
v10'un export ailesi (SQLite wrapper, ZIP writer, `.apkg` Faz 1-2) kullanici
karariyla bu roadmap'e devredildi.

Odak: kullanici "once kullaniciya dokunanlar" secti — gorunur kalite once,
oyun ortada, en riskli is (export) sona. Sirasi bilincli: Turkce arayuz
eksikligi her acilista goruluyor, eslestirme oyunu yeni bir sey katiyor,
`.apkg` ise disariya bagimli tek kalem (gercek Anki import dogrulamasi).

## Teknik cerceve (tum sprintler icin gecerli)

- **Sifir dis bagimlilik korunur.** `.apkg` icin sistem `import SQLite3`
  (projedeki ilk C-API yuzeyi), sozluk icin CoreServices, lemma icin Apple
  `NaturalLanguage`.
- Her release oncesi **TAM birim test paketi** CI ile birebir komutla kosulur.
  Yeni testler **async metod**; senkron `@MainActor` bloklayan test CI
  runner'ini kilitler.
- **Makineye bagli test dusmez, atlanir** (`XCTSkip`): NL'in Almanca
  lemmatizer'i ve macOS sozlukleri indirilebilir/kullaniciya bagli varliklar,
  temiz bir CI runner'inda yoklar (v1.36 CI arizasi). Test, uygulamanin kendi
  kuralini dogrular; Apple'in icerigini degil.
- **Anlik cevap katmani model cagrisini tamamen bastirir.** Oraya eklenen her
  kaynak "Yanit Dili" ayarina uymak zorunda (v1.37 sozluk katmani dersi).
- Yeni kullanici metinleri `Localizable.xcstrings`'e TR cevirisiyle.
  **`Text(String)` katalogu ATLAR** — enum'larda `localizedTitle`, yardimci
  fonksiyonlarda `LocalizedStringKey` parametresi.
- **`ResultParser`'a gorunur prompt etiketleri degismez; modul raw value'lari
  ve `@AppStorage` anahtarlarini besleyen enum raw value'lari asla yeniden
  adlandirilmaz** (persistence anahtari).
- Yeni `Codable` alanlar `decodeIfPresent` + default (ileri-guvenli JSON).
- DS token'lari; glass yalniz chrome, **icerige DOGRUDAN uygulanir**;
  interactive yalniz basilabilir yuzeyde.
- **`Slider(value:in:step:)` AppKit tick mark cizer** — sayfa sayisi kadar
  centik ikinci bir track gibi gorunur. Buyuk araliklarda `step` kullanma,
  yuvarlamayi setter'da yap (v1.37).
- **Tam ekranda ust pikseller menu cubuguna aittir**; hover/pointer esikleri
  gorunumun gercekten cizildigi koordinat uzayinda olculur, content view'in
  tepesinden degil (v1.37 zen cubugu dersi).
- Yeni dosyalar hedefe kendiliginden girer (`PBXFileSystemSynchronizedRootGroup`)
  — `project.pbxproj` duzenlenmez.
- UI testleri kosarken uygulamanin ayri bir kopyasi acik olmamali;
  `XCUIApplication` onu sonlandiramaz ve test duser.
- **ContentView dosya bolunmesi planlanmaz** — private `@State` extension'a
  tasimayi engelliyor (v1.33'te denendi, geri alindi).

**Bilinclice v11 disinda:** sayfalanmis EPUB (kullanici bu tura almadi),
kapsama metriginin okunusu (kullanici karari: dursun — bkz. Bilinen kisit),
kisiye ozel FSRS agirlik optimizasyonu, AnkiConnect, embeddings/RAG, frekans
listeleri, PDF koyu-tema figur korumasi, ContentView bolunmesi.
Apple-Developer-kilitli kalemler (widget, App Group, CloudKit, notarization)
uyelik duyurulana kadar Won't.

**Bilinen kisit (v11'de dokunulmuyor):** kitap kapsamasi yalnizca kaydedilen
kelimelere gore olculuyor, "bildigin kelimeler"e gore degil. Kucuk bir kelime
hazinesiyle her kitap ~%2 ve kirmizi cikiyor. Kullanici karari: kelime hazinesi
buyudukce kendiliginden anlamli hale gelsin; taban liste / esik / kalibrasyon
secenekleri v12'ye.

---

## Sprint 1 — v1.38.0 "Turkce arayuz + tekrar ekraninin borcu" (Must)

Amac: uygulamanin yarisi Ingilizce gorunmesin, ve eslestirme oyunu 1145
satirlik bir dosyanin ustune eklenmesin.

- [x] **i18n borcu (262 metin)**: katalogdaki 673 anahtarin 277'sinde `tr`
      yok; bunlarin 262'si gercek kullanici metni, kalan 15'i noktalama/format
      (`·`, `%@ %@`, `%lld`) — onlar oldugu gibi birakilir.
      **Dokunulmaz:** collocations `*Example:*`/`*Translation:*`, usage-notes
      `FREQ:/REG:/CONFUSE:/CAUTION:` etiketleri (ResultParser hedefleri),
      modul raw value'lari, `SavedWordsSortOrder`/`SavedWordsFilter` raw
      value'lari (@AppStorage anahtari)
- [x] **`Text(String)` denetimi**: katalogun hic gormedigi metinler var —
      `SavedWordsListView`'daki `metaRow("Mode", …)` boyleydi (v1.36'da
      bulundu, Xcode anahtari budadi). `Text(` cagrisina `String` parametresi
      geciren yardimci fonksiyonlari tara; ya `LocalizedStringKey` parametresine
      cevir ya da cagri yerinde `String(localized:)` ile sar
- [~] **TR arayuz gecisi**: OLCULDU, GOZLE BAKILMADI — 42 tek-satirlik
      kontrol etiketinden yalnizca ikisi 3 karakterden fazla uzuyor ("Words
      you know", "Speak"), ikisi de icerigine gore boyutlanan kaplarda. Cok
      uzayanlar yardim metni ve erisilebilirlik etiketleri (sarmalaniyor).
      Ekran erisilemedigi icin gercek gorsel tur kullaniciya kaldi
- [x] **`QuizView` bolunmesi (1145 → hedef ~600)**: `SavedWordsListView`
      deseni (v1.37'de 1041→503, hicbir private acilmadan). Kart yuzu/arka
      bolumleri, rating satiri, sonuc ekrani kendi dosyalarina; model tarafi
      `QuizSession`'da zaten duruyor. **Sprint 2'den ONCE bitmeli**
- [x] Dogrulama: katalog gecerli JSON (706 anahtar, cevirisiz kalan 12'sinin
      hepsi noktalama/format); tam birim test paketi yesil; katalog
      karsilastirmasi ile hicbir anahtarin kaybolmadigi dogrulandi. Bes modun
      TR arayuzde uctan uca turu kullaniciya kaldi (ekran erisilemedi)

## Sprint 2 — v1.39.0 "Eslestirme oyunu" (Must)

Amac: v10'da cikarilan `QuizSession` uzerine, tanimayi calistiran hafif bir
mod. Roadmap v10'un kendi v11 adayi.

- [x] **`QuizMode.matching`**: N cift (varsayilan 5, "daha fazla" ile 8),
      solda terim / sagda karsilik, tiklayarak eslestir. Yanlis eslestirme
      sayaci; tum ciftler eslesince tur biter
- [x] **Karsilik kaynagi**: "Yanit Dili" ayarini izler — target'ta
      `usableDefinition`, native'te `meaningTR` (v1.35 kurali: placeholder
      yerine nil, `reviewDefinition` KULLANILMAZ). Karsiligi olmayan kelime
      cifte girmez
- [x] **Karar: eslestirme zamanlamaya YAZMAZ** (cram gibi). Gerekce: 5 kartlik
      bir izgarada tanimak, tek basina hatirlamakla ayni sey degil; FSRS'e
      `good` yazmak araligi hak edilmemis sekilde uzatir. Sonuc ekraninda
      dogruluk gosterilir, `applyReview` cagrilmaz. Cram akisinin mevcut
      "zamanlamaya dokunmadan calis" deseni yeniden kullanilir
- [x] **Mod gizleme**: yeterli uygun cift yoksa (min 4) mod gorunmez —
      `listening`'in sesi olmayan dilde gizlenmesi deseni
- [x] **Erisilebilirlik**: klavyeyle eslestirme (Tab + Space/Return), her
      hucrede `accessibilityLabel`, eslesme sonucu `accessibilityValue`
      (v1.33 pass'inin standardi)
- [x] **Testler (async)**: cift uretimi (kaynak dili + karsilik dolu olma
      kurali), yanlis sayaci, tur tamamlanma, yetersiz kart durumu
- [~] Dogrulama: zamanlamaya yazmama karari testle sabit
      (`testMatchingModeDoesNotAffectTheSchedule`), tur ilerleme ve kisa-artik
      durumlari testli. Izgaranin canli turu (okunurluk, yanlis eslestirmede
      titreme, tur gecisi) kullaniciya kaldi — ekran erisilemedi

## Sprint 3 — v1.40.0 "Export" (Should, v10'dan devir)

Amac: TSV'nin yapamadigini yapmak — Anki'ye zamanlamasiyla birlikte gitmek.
Disariya bagimli tek sprint; gercek Anki import'u kapi.

- [ ] **SQLite wrapper (T-E1)**: kucuk `SQLiteDatabase` (sistem
      `import SQLite3`) + birim testleri
- [ ] **ZIP writer (T-E2)**: `ZIPArchive.swift` salt-okunur (239 satir);
      kardes writer (stored method 0 + CRC-32 Anki'ye yeter) + round-trip
      testi (yaz → mevcut reader okusun)
- [ ] **.apkg Faz 1 (L-E1)**: `ExportFormat.apkg` + **paralel Data/URL yolu**
      (mevcut boru hatti uctan uca `String`; TSV/CSV/Quizlet aynen kalir).
      Sema col/notes/cards/revlog; ince noktalar `col.models`/`col.decks`
      JSON, `notes.csum`/`sfld`; media `{}`. Kartlar YENI durumda.
      **Kapi: gercek Anki desktop'a import dogrulamasi**
- [ ] **.apkg Faz 2 — zamanlama tohumu (L-E2, PLANLI RISK, ~2 gun timebox)**:
      FSRS (`stability`/`difficulty`/`nextReviewAt`) → `cards.due/ivl/factor`,
      `reviewEvents` → `revlog`. **Onceden karar verilen fallback: yalniz
      Faz 1 ship'lenir**
- [ ] Dokumantasyon kapanisi: ROADMAP durum, CHANGELOG, ARCHITECTURE (SQLite
      wrapper + ZIP writer)
- [ ] Dogrulama: `.apkg` → Anki desktop import → kart tekrari; Faz 2'de
      due/interval makul; **S1-S2 ozellikleri tam regresyon**

---

## Genel dogrulama (her sprint sonu)

- Build + **tam birim test paketi** (UI testleri haric), CI ile birebir komut
- `Localizable.xcstrings`: yeni metinler TR cevirisiyle; katalog JSON gecerli
- DS denetimi: ham `.font(.system(size:))` / ham material yok, istisnalar
  `// DS-exempt:` yorumlu
- macOS 15 fallback yolu derleniyor
- CHANGELOG (kullanici-odakli dil) → tag `vX.Y.Z` → push → **CI release run'i
  izlenir**, DMG uretimi teyit edilir
