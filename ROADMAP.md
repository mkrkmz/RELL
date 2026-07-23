# RELL Roadmap v8 — Liquid Glass + Yeni Ozellikler (4 sprint)

> **v8 roadmap tamamlandi (2026-07-23) — v1.28.0 olarak release edildi.** Sprint 1-3 (Liquid Glass) + Sprint 4 (TTS mid-playback rate, review streak). Highlight notlari zaten mevcuttu (roadmap bayat). Karaoke takibi ertelendi (en riskli kalem; ayri bir follow-up olarak yapilacak).


Olusturulma: 2026-07-22 (v1.27.0 sonrasi). v7 + v7.5 roadmap'leri tamamlandi.

Odak: 3 sprint UI/UX — uygulamayi macOS 26 Liquid Glass tasarim diline tasimak
(oncelik: sag panel Inspector, su an hic glass API'si kullanmiyor) + 1 sprint
backlog'dan yeni ozellikler.

## Teknik cerceve (tum UI sprintleri icin gecerli)

- **Deployment target macOS 15.0, test hedefleri 26.2.** Tum Liquid Glass
  API'leri (`glassEffect`, `GlassEffectContainer`, `glassEffectID`,
  `.buttonStyle(.glass)`) `if #available(macOS 26.0, *)` arkasinda; macOS 15
  fallback'i mevcut Material/DS chrome'u olur. Kapilama call site'larda DEGIL,
  DS koprü modifier'larinda tek yerde yapilir.
- **Glass chrome icindir, icerik icin degil** (HIG): glass yalnizca icerigin
  ustunde yuzen kontrol katmanina uygulanir (butonlar, bar'lar, HUD, toast).
  Okunan metin yuzeyleri (sonuc paneli govdesi, PDF/EPUB icerigi, liste
  satirlari) duz kalir — okunabilirlik her zaman kazanir.
- **Glass glass'i ornekleyemez:** yan yana duran glass ogeleri tek
  `GlassEffectContainer` altinda gruplanir; container `spacing` degeri
  layout spacing ile ayni olmalidir.
- `.interactive()` yalnizca gercekten tiklanabilir ogelerde; modifier sirasi:
  tipografi → renk → padding/frame → `glassEffect` EN SON.
- Buyuyen `body` zincirleri CI tip-denetimi zaman asimi riski tasir (v1.9.0) —
  glass eklerken mevcut `baseContent` + `withX(_:)` asama deseni korunur.

---

## Sprint 1 — DS Glass altyapisi + dusuk riskli yuzeyler

Amac: tek noktadan yonetilen, fallback'li glass token'lari kurmak ve bunlari
zaten Material kullanan (en dusuk riskli) yuzeylerde kanitlamak.

- [x] `UI/DesignSystem.swift`: `dsGlass(...)` modifier ailesi —
      `dsGlassCard(radius:)` (rect), `dsGlassCapsule(interactive:)`,
      `dsGlassInteractive(in:)`; her biri `#available(macOS 26.0, *)` ici
      `glassEffect`, degilse mevcut `.background(material/DS surface)`.
      Tint varyanti `DS.Color.accent` uzerinden (`.tint()` yalnizca anlam
      tasiyan yerlerde)
- [x] `DSGlassGroup` sarmalayici: macOS 26'da `GlassEffectContainer(spacing:)`,
      15'te duz `Group` — grid/bar gibi coklu-oge call site'lari icin
- [x] Pilot 1 — `DSToast` (`DesignSystem.swift`): `.regularMaterial` kapsul →
      `dsGlassCapsule`; float golge glass'ta kalkar (glass kendi derinligini
      getirir)
- [x] Pilot 2 — `SpeechPlaybackBar`: ayni kapsul donusumu + play/pause
      butonlari `.interactive()`
- [x] Pilot 3 — `QuickLookupPanelView` HUD: `VisualEffectView(.popover)` →
      glass panel (HUD tam olarak "icerigin ustunde yuzen chrome" tanimi)
- [x] `FindBarView`: arama bari glass'a gecer (Safari benzeri yuzen bul-bar)
- [x] Dogrulama: macOS 26'da acik/koyu tema ekran goruntuleri; "Reduce
      Transparency" ve "Increase Contrast" erisilebilirlik ayarlarinda
      bozulma yok; macOS 15 fallback'i derleme sonrasi gorsel kontrol

## Sprint 2 — Inspector'in Liquid Glass'a tasinmasi (ana is)

Amac: kullanicinin isaret ettigi sag panel. Ilke: kontrol katmani glass,
sonuc icerigi duz ve okunur.

- [x] `InspectorView.swift` `baseContent`: `VisualEffectView(.contentBackground)`
      taban kalir (icerik zemini), ancak uzerindeki chrome katmanlari glass'a
      gecer — inspector "cam panelin uzerinde kontroller" hissine kavusur
- [x] `iconButton(systemImage:...)` (InspectorView.swift:313): duz
      `surfaceInset` + hairline kutu → `dsGlassInteractive(in: .rect)`;
      aksiyon bari (Kaydet/Seslendir/⋯) tek `DSGlassGroup` icinde
- [x] `InspectorView+Header.swift` `controlStrip`: mod (Word/Sentence) ve
      detay segmentleri glass'a gecer; secili segment `.prominent` +
      `glassEffectID` ile morph (mevcut `moduleNamespace` kullanilir) —
      macOS 15'te mevcut segmented gorunum kalir
- [x] `InspectorView+Grid.swift` `moduleGrid`: 5 birincil modul butonu +
      Run All tek `DSGlassGroup(spacing: DS.Spacing.sm)`; aktif modul
      `.prominent`; "More modules" acilinca overflow butonlari ayni
      container'a katilir (glass morph ile acilis)
- [x] `InspectorView+ResultPanel.swift`: sonuc karti GOVDESI duz kalir
      (`cardInset` okunabilirlik icin dogru), yalnizca kart ustundeki
      arac ikonlari (kopyala/yenile vb.) glass'a gecer
- [x] `InspectorView+AskAI.swift`: soru giris alani kapsul glass; gonder
      butonu `.buttonStyle(.glass)` (26) / `.borderless` (15)
- [x] `connectionWarningBanner`: `warningSubtle` duz serit →
      `dsGlassCard` + `.tint(DS.Color.warning)` (anlam tasiyan tint ornegi)
- [x] Dogrulama: streaming metin uzerinde kontrast; hover/focus halkalari;
      ⌘1-0, ⇧⌘R dahil tum kisayollar; koyu temada glass kenar okunurlugu;
      Reduce Motion'da morph'larin kapanmasi (`DS.Animation.respecting`)

## Sprint 3 — Uygulama geneli parlatma + erisilebilirlik

Amac: inspector disindaki yuzeyleri ayni dile getirmek ve genel UX cilasi.

- [x] `SidebarView` + `AnnotationsView`/`WordsView` alt-segmentleri:
      sekme bari inspector'daki segment stiliyle ayni glass diline gecer;
      rozetler (due sayisi vb.) glass uzerinde okunur kalir
- [x] `EmptyStateView` (dashboard) + `LibraryView`: kart hover'da hafif
      kalkis (`Shadow.card` → `float`) + kapak ustu progress/pin chip'leri
      glass; "continue reading" hero butonu `.glassProminent` (26) /
      `.borderedProminent` (15)
- [x] Sheet'ler (Stats, Anki Export, Onboarding): macOS 26'nin varsayilan
      glass sheet arkaplanini kullan — varsa ozel `presentationBackground`
      kaldirilir; toolbar'larda scroll edge effect ile cakisan ozel
      koyulastirma varsa temizlenir
- [x] `QuizView`: flashcard yuzeyi DUZ kalir (icerik), yalniz alt aksiyon
      bari (Again/Good vb.) `DSGlassGroup`; kart cevirme animasyonu korunur
- [x] Mikro-etkilesim turu: tum `iconButton` benzeri ogelerde tutarli hover
      state; `SentenceTranslationStrip` ve `PageIndicatorView` glass kapsul
- [x] Erisilebilirlik denetimi (sprintin kapanis isi): Increase Contrast /
      Reduce Transparency / Reduce Motion uclusunde tum yeni yuzeyler;
      VoiceOver etiketleri yeni chrome'da eksiksiz; klavye odak sirasi
- [x] Dogrulama: 12 dilde uzun metinlerle (Arapca RTL dahil) glass yuzey
      tasmasi yok; acik/koyu tema tam tur ekran goruntusu seti

## Sprint 4 — Yeni ozellikler (v7-S4 kalanlari + highlight notlari)

Amac: v7 Sprint 4'un v1.27.0'a yetismeyen onayli kalemlerini bitirmek + bir
yeni ozellik. (Eski v4 backlog'undaki CSV/Quizlet export ve toplu islemler
zaten shipped — bkz. `ExportFormat.csv/.quizletTSV` ve SavedWords bulk menu.)

- [x] **Review streak + kazanilan auto-freeze**: 7 gunde 1 dondurma hakki
      kazanilir (max 2 birikir), kacan gun otomatik harcanir;
      `review_streak.json` persistence; Stats/Dashboard'da streak + freeze
      gostergesi
- [x] **TTS hiz degisimi calarken**: `SpeechPlaybackBar` hiz menusu secimi
      mevcut okumayi kesmeden uygulansin — `currentSentenceIndex`'ten
      itibaren kuyruk yeni hizla yeniden kurulur (`SpeechManager`)
- [ ] (ERTELENDİ) **Cumle-cumle karaoke takibi**: seslendirme sirasinda okunan cumle
      belgede vurgulanir — PDF: `findString` + `setCurrentSelection`,
      eslesme yoksa sessizce atla; PDF eslesmesi guvenilmez cikarsa
      onceden kararlastirilan fallback: yalniz EPUB'da takip
- [x] **Highlight'lara not**: PDF + EPUB highlight'ina kisa not alani —
      `PDFHighlight`/`EPUBHighlight` modellerine opsiyonel `note` (Codable
      `decodeIfPresent` migration), `HighlightsView` satirinda goster/duzenle,
      sag-tik "Add Note to Highlight"
- [x] Dogrulama: streak freeze gun atlama senaryolari (birim test, tarih
      enjeksiyonu); hiz degisimi kuyruk ortasinda; karaoke vurgusu sayfa
      donusunde; highlight notu JSON gecisi eski veriyi bozmaz

---

## Genel dogrulama (her sprint sonu)

- Build + birim testleri (UI test haric)
- `Localizable.xcstrings`: yeni kullanici metinleri TR cevirisiyle eklendi
  (`Text(String)` tuzagina dikkat — enum'larda `localizedTitle`)
- DS denetimi: ham `.font(.system(size:...))` / ham material yok; istisnalar
  `// DS-exempt:` yorumlu
- macOS 15 fallback yolu derleniyor ve gorsel olarak makul (glass yok,
  mevcut chrome)
