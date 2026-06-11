# RELL Roadmap — UI ve Yeni Ozellikler

Odak: dashboard'un sade temelini koruyarak gorsellik ve ozellik katmak.
Onceki roadmap'in LLM performans isleri (finish_reason, istek kuyrugu, kalici cache,
parse memoizasyonu) tamamlandi ve buradan cikarildi.

## Faz 1 — Dashboard Gorsel Katman: PDF Kapaklari (tamamlandi)

- [x] `DocumentCoverStore`: ilk sayfadan async kapak render (PDFKit thumbnail),
      bellek (NSCache) + disk (`Application Support/RELL/covers/`) cache, mtime ile tazelik
- [x] Hero karttaki ikon kutusu yerine kapak gorseli (placeholder ikonla fade-in)
- [x] Recent satirlarinda mini kapak

## Faz 2 — Gunluk Hedef + Haftalik Aktivite (tamamlandi)

- [x] Ayarlanabilir gunluk okuma hedefi (dakika, AppStorage `dailyReadingGoalMinutes`,
      sag tik menusuyle 10-60 dk arasi secim); hero altindaki aktivite kartinda progress ring + bugunku sure
- [x] 7 gunluk mini bar chart (Charts, `sessionStore.last7Days` reuse; hedef cizgisi RuleMark ile)
- [x] Seri gostergesi: flame + okuma serisi (footer'daki review-streak metni kaldirildi)
- [x] Hedef tamamlama mikro-kutlamasi (halka yesile doner, bounce'li checkmark, spring animasyon)

## Faz 3 — Dashboard Mini Kelime Karti (tamamlandi)

- [x] Review satirinin yerine tek due kelimelik flip kart: on yuz terim, arka yuz kayitli tanim
      (tanim onceligi `SavedWord.reviewDefinition` olarak paylasildi, QuizView da kullaniyor)
- [x] Again/Good/Easy → `savedWordsStore.applyReview` (QuizView ile ayni SRS), bitince siradaki kelime
- [x] Tum due'lar bitince "All caught up" durumu + bir sonraki review zamani; "Review all" butonu kalir

## Faz 4 — Library Gorunumu (tamamlandi)

- [x] `RecentDocumentStore.maxDocuments` 12 → 48; `remove(id:)` eklendi
- [x] Recent bolumune "View all" (5+ belge varsa) → kapak grid'li Library sayfasi (Esc/Back ile donus)
- [x] Grid karti: kapak + baslik + ilerleme cubugu + son acilma; arama ve siralama (son acilan / ad / ilerleme)
- [x] Sag tik: Show in Finder, Remove from Library (dashboard recent satirlarinda da)

## Faz 5 — Onboarding

- [ ] Ilk acilista 3 adimli sheet (AppStorage `hasCompletedOnboarding`):
      dil cifti secimi → LM Studio baglanti testi (mevcut connection-test reuse) → kisa ozellik turu
- [ ] Atlanabilir; Settings'ten yeniden acilabilir

## Backlog (siralanmamis)

- Kelime etiketleri/desteleri; etikete gore review ve Anki export
- Quiz kartlarinda TTS/telaffuz butonu
- Cram modu, Quizlet export
