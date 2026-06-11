# RELL Roadmap — UI ve Yeni Ozellikler

Odak: dashboard'un sade temelini koruyarak gorsellik ve ozellik katmak.
Onceki roadmap'in LLM performans isleri (finish_reason, istek kuyrugu, kalici cache,
parse memoizasyonu) tamamlandi ve buradan cikarildi.

## Faz 1 — Dashboard Gorsel Katman: PDF Kapaklari (tamamlandi)

- [x] `DocumentCoverStore`: ilk sayfadan async kapak render (PDFKit thumbnail),
      bellek (NSCache) + disk (`Application Support/RELL/covers/`) cache, mtime ile tazelik
- [x] Hero karttaki ikon kutusu yerine kapak gorseli (placeholder ikonla fade-in)
- [x] Recent satirlarinda mini kapak

## Faz 2 — Gunluk Hedef + Haftalik Aktivite

- [ ] Ayarlanabilir gunluk okuma hedefi (dakika, AppStorage); header'da progress ring + bugunku sure
- [ ] 7 gunluk mini bar chart (Charts, `sessionStore.last7Days` reuse)
- [ ] Seri gostergesi: flame + hedefle dolan halka (footer metni yerine gorsel oge)
- [ ] Hedef tamamlama mikro-kutlamasi (kisa spring animasyon)

## Faz 3 — Dashboard Mini Kelime Karti

- [ ] Review satirinin yerine tek due kelimelik flip kart: on yuz terim, arka yuz kayitli tanim
- [ ] Again/Good/Easy → `savedWordsStore.applyReview` (QuizView ile ayni SRS), bitince siradaki kelime
- [ ] Tum due'lar bitince "All caught up" durumu; tam oturum icin Review butonu kalir

## Faz 4 — Library Gorunumu

- [ ] `RecentDocumentStore.maxDocuments` 12 → 48
- [ ] Recent bolumune "View all" → kapak grid'li Library sayfasi
- [ ] Grid karti: kapak + baslik + ilerleme cubugu + son acilma; arama ve siralama
- [ ] Sag tik: Show in Finder, Remove from Library

## Faz 5 — Onboarding

- [ ] Ilk acilista 3 adimli sheet (AppStorage `hasCompletedOnboarding`):
      dil cifti secimi → LM Studio baglanti testi (mevcut connection-test reuse) → kisa ozellik turu
- [ ] Atlanabilir; Settings'ten yeniden acilabilir

## Backlog (siralanmamis)

- Kelime etiketleri/desteleri; etikete gore review ve Anki export
- Quiz kartlarinda TTS/telaffuz butonu
- Cram modu, Quizlet export
