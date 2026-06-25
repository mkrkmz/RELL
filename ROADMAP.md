# RELL Roadmap v4 — Panel Sadeleştirme (UI/UX)

Odak: yan panelleri (sol sidebar + sag inspector) islevsellik kaybetmeden
gorsel olarak sadelestirmek. v1-v3 roadmap'leri tamamlandi.

Tasarim kararlari (kullaniciyla netlestirildi):
- Sol sidebar: 8 sekme → 4 (Stats sidebar'dan cikar)
- Sag inspector aksiyon bari: ikincil aksiyonlar "⋯" menusune; ⚙ kaldirilir (⌘,)
- Modul grid: overflow 5 modul "More" disclosure altina; soluk/parlak ayrimi kalkar
- Hicbir ozellik kaybolmaz; tum kisayollar korunur

## Faz 1 — Sidebar: 8 sekme → 4 (tamamlandi)

Hedef sekmeler: **Pages · Contents · Annotations · Words**

- [x] `AnnotationsView` container: segmented [Marks · Highlights · Notes],
      mevcut `PDFBookmarksView` / `HighlightsView` / `PDFNotesView`; son alt-sekme `@AppStorage`
- [x] `WordsView` container: segmented [Words · Review], `SavedWordsListView` / `QuizView`;
      Review segmentinde due sayisi
- [x] `SidebarTab` 4 case'e indi; badge: Annotations = bookmark+highlight+note, Words = due
- [x] "Marks/Marker" karisikligi bitti; etiketler tam boyut

## Faz 2 — Stats'i sidebar'dan cikar (tamamlandi, Faz 1 ile birlikte)

- [x] Sidebar'dan Stats sekmesi kaldirildi (SidebarView artik sessionStore almiyor)
- [x] ContentView toolbar'inda "Stats" butonu (chart.bar) → `ReadingStatsView` sheet
- [x] `ReadingStatsView` icerigi aynen korundu

## Faz 3 — Inspector aksiyon bari sadeleştirme

- [ ] `actionBar`: yalnizca Kaydet (⭐, ⌘D) + Seslendir/Durdur (⇧⌘S/⇧⌘X) gorunur kalir
- [ ] Kopyala, Quick Export, Export fields (⌘E), Clear outputs → tek "⋯" Menu altina
      (kisayollar menu item'larinda korunur)
- [ ] Ayarlar (⚙) toolbar'dan kaldirilir — ⌘, ve uygulama menusu zaten var
- [ ] Header tek temiz satira iner

## Faz 4 — Modul grid: overflow'u "More" altina

- [ ] `moduleGrid`: 5 birincil modul + "More" disclosure; acilinca diger 5 modul
      ayni stille gosterilir (soluk "overflow" gorunumu kaldirilir)
- [ ] Acik/kapali durum `@AppStorage` ile hatirlanir; Run All (⇧⌘R) korunur
- [ ] Modul kisayollari (⌘1-0) korunur

## Faz 5 — Inspector yuzey katmanlarini duzlestir

- [ ] Ic-ice bordered kart sayisini azalt (header/control/grid/overflow/result → daha az
      cerceve, tek elevation seviyesi, bosluga dayali ayrim)
- [ ] `controlStrip`: mode + detail tek temiz satir; recent terms daha sessiz yerlesim
- [ ] DS token tutarliligi; gereksiz `.overlay(stroke)` katmanlari temizlenir

## Dogrulama

- Build + birim testleri (UI test haric)
- Manuel: sidebar 4 sekme akiyor mu; Annotations/Words alt-segmentleri dogru iceriği
  gosteriyor mu; Stats sheet aciliyor mu; inspector ⋯ menusu tum eski aksiyonlari
  iceriyor mu; modul "More" acilip kapaniyor mu; tum kisayollar calisiyor mu

## Backlog (siralanmamis)

- Gunluk hedef bildirimleri, CSV/Quizlet export, toplu etiketleme, highlight'lara not
