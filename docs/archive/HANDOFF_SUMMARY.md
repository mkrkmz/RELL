# RELL Handoff Summary

Bu dosya, bu sohbet boyunca RELL uzerinde yaptigimiz degisikliklerin toplu ozetidir. Baska bir IDE'de devam ederken hizli baglam saglamasi icin hazirlandi.

## Genel Kapsam

Odak, RELL'in mevcut okuma, kaydetme, not ve quiz yuzeylerini daha tutarli bir ogrenme akisi haline getirmekti. Yeni kalici JSON modeli veya migration eklenmedi. Mevcut `SavedWord`, `PDFNote`, `ReadingSession` ve `RecentDocument` verileri daha gorunur, aksiyon alinabilir ve dashboard/review odakli hale getirildi.

Ana paketler:

- Review Center sprinti
- Workspace / Empty Space dashboard revamp
- Review heatmap kontrolu ve gorsel iyilestirme
- Dashboard'u kompakt tutarken daha renkli, kullanisli ve sik hale getirme
- Ilgili queue/helper unit testleri

## Degisen Dosyalar

Mevcut worktree'de degisen dosyalar:

- `Reader for Language Learner/Reader for Language Learner/App/ContentView.swift`
- `Reader for Language Learner/Reader for Language Learner/App/EmptyStateView.swift`
- `Reader for Language Learner/Reader for Language Learner/App/InspectorView+Header.swift`
- `Reader for Language Learner/Reader for Language Learner/App/SidebarView.swift`
- `Reader for Language Learner/Reader for Language Learner/App/WorkspaceSummaryView.swift` yeni dosya
- `Reader for Language Learner/Reader for Language Learner/Models/SavedWord.swift`
- `Reader for Language Learner/Reader for Language Learner/Models/SavedWordsStore.swift`
- `Reader for Language Learner/Reader for Language Learner/Reader/Notes/PDFNotesView.swift`
- `Reader for Language Learner/Reader for Language Learner/UI/QuizView.swift`
- `Reader for Language Learner/Reader for Language Learner/UI/SavedWordsListView.swift`
- `Reader for Language Learner/Reader for Language LearnerTests/SavedWordTests.swift`
- `Reader for Language Learner/Reader for Language LearnerTests/SavedWordsStoreTests.swift`

Not: `WorkspaceSummaryView.swift` su anda untracked gorunuyor; build/test kapsaminda kullaniliyor.

## Review Center

Sidebar'daki gorunen `Quiz` dili `Review` / `Review Center` terminolojisine tasindi. Swift type adi dusuk risk icin `QuizView` olarak birakildi.

Review Center davranisi:

- Varsayilan queue artik due-first calisiyor.
- Due word yoksa mastered olmayan new/learning kelimeler fallback olarak geliyor.
- `Include all saved words` toggle'i korunuyor ve tum kayitli kelimeleri gosteriyor.
- Baslangic ekrani due count, new/learning/mastered dagilimi ve bugun reviewed sayisini gosteriyor.
- Flashcard ekrani source PDF/page, review status, mastery badge ve progress baglamini daha belirgin veriyor.
- Sonuc ekrani Again/Good/Easy dagilimini, kalan due sayisini ve `Review More`, `Continue Reading`, `Open Saved Words` aksiyonlarini gosteriyor.

## Saved Word / Review Model Helpers

`SavedWord` icine review akisini destekleyen gorunum/test odakli alanlar ve davranislar eklendi:

- `ReviewStatus`
- `reviewHistory`
- `nextReviewAt`
- `hasBeenReviewed`
- `isDue(at:)`
- `reviewStatus`

`SavedWordsStore` icinde review queue ve dashboard icin helper'lar eklendi:

- `pendingReviewCount`
- `reviewedTodayCount`
- `masteredCount`
- `learningCount`
- `newCount`
- `words(for:)`
- `savedCount(for:)`
- `dueCount(for:at:)`
- `dueWords(at:)`
- `reviewFallbackWords()`
- `reviewQueue(includeAll:at:)`
- `reviewActivity(days:endingAt:)`

Heatmap problemi icin kritik nokta: activity artik sadece tek bir gunden degil, `reviewHistory` ve mevcut review event tarihleri uzerinden gunluk bucket'lara ayriliyor. Bu nedenle birden fazla gune yayilan review aktivitesi heatmap'te gorunmeli.

## Workspace / Empty Dashboard

Empty Space artik bos ekran + buyuk CTA yerine dashboard gibi calisiyor. `ContentView` tarafindan `EmptyStateView`'a su baglamlar aktariliyor:

- recent documents
- today reading time
- reviewed today count
- note store
- saved words store
- bookmark store
- review sheet action

Yeni / yenilenmis dashboard parcasi:

- `DashboardActionBar`
- `DashboardWorklaneRow`
- `DashboardLaneCard`
- `WorkspaceSummaryView`
- `ReviewHeatmapView`
- `DashboardMetricStrip`
- `DocumentMetricChip`
- `LearningActionRow`
- `CompactRecentDocumentCard`
- `EmptyDashboardPlaceholder`

Son istek uzerine dashboard kompakt kalacak sekilde daha canli hale getirildi:

- Reading, Review ve Notes icin renkli ama sakin work-lane kartlari eklendi.
- Ust aksiyon barinda durum metni ikon ve renkli rail ile daha okunur hale geldi.
- Summary metric strip renkli tint'lerle guclendirildi.
- Recent document kartlari due/saved/notes durumuna gore islevsel renk aksani aliyor.
- Heatmap rengi daha okunur ve calm olacak sekilde success tint'e cekildi.
- `uncodixfy` cizgisine uygun olarak gradient, glow, buyuk hero, fake metric veya asiri dekorasyon eklenmedi.

## Recent Documents / Document Metrics

Recent document kartlari daha kompakt ve aksiyon odakli hale getirildi:

- Belge adi
- sayfa bilgisi
- son acilma bilgisi
- notes/saved/due/bookmark metrikleri
- `Continue` aksiyonu

Kartlar hover/renk aksanini abartmadan kullaniyor. Due varsa warning, saved varsa success, notes varsa purple, yoksa accent tonu kullaniliyor.

## Notes / Saved / Inspector Terminoloji

Notes ve Saved yuzeylerinde review'a giden metinler Review Center diliyle hizalandi.

Inspector header tarafinda secili metin sonrasi aksiyonlar daha netlestirildi:

- Save
- Quick Export
- Full Export
- Speak
- Clear
- Settings

Tooltip/accessibility metinleri ve kayitli kelime durumundaki review queue baglami daha gorunur hale getirildi.

## Tests

Eklenen / genisletilen unit testler:

- `SavedWordTests.swift`
- `SavedWordsStoreTests.swift`

Kapsanan davranislar:

- Review queue due words'u oncelikli secer.
- Due yoksa mastered olmayan fallback words gelir.
- `includeAll` tum saved words'u getirir.
- Review rating sonrasi `pendingReviewCount` ve `reviewedTodayCount` guncellenir.
- Legacy/default decode alanlari bozulmadan calisir.

## Dogrulama Durumu

Son dogrulama komutlari:

- `make build` gecti.
- `make test` gecti.
- `make ui-test` ilk turda stale app/debugserver nedeniyle terminate timeout verdi; eski process temizlenip tekrar kosuldu ve gecti.
- `git diff --check` temiz.

UI test notu:

- Ilk hata kod degisikliginden ziyade macOS/Xcode automation tarafinda stale `Reader for Language Learner` app ve `debugserver` process'lerinden kaynaklandi.
- Temizleme sonrasi `make ui-test` 4 test / 0 failure ile gecti.

## Devam Ederken Dikkat

- Commit veya staging yapilmadi.
- Worktree dirty durumda birakildi.
- `WorkspaceSummaryView.swift` yeni dosya oldugu icin commit oncesi eklenmeli.
- Dashboard tasariminda DS tokenlari kullanilmaya devam edilmeli.
- Yeni persistence modeli eklenmedi; mevcut JSON uyumlulugu korunmali.
- Review heatmap'i manuel test ederken birden fazla gunluk activity icin `reviewHistory`/review event tarihleri uzerinden kontrol etmek iyi olur.

## Onerilen Sonraki Manual QA

- Hic PDF yokken dashboard minimal ve kullanisli gorunuyor mu?
- Recent document kartindan PDF aciliyor mu?
- Due word varken dashboard Review aksiyonu ve Review Center ayni sayiyi gosteriyor mu?
- Iki farkli gunde review yapilmis test datasinda heatmap birden fazla gunu boyuyor mu?
- Light/dark temada dashboard, sidebar ve inspector okunakli mi?
- Minimum pencere genisliginde work-lane kartlari ve recent card metinleri tasmiyor mu?
