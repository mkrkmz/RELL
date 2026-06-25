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

## Faz 3 — Inspector aksiyon bari sadeleştirme (tamamlandi)

- [x] `actionBar`: yalnizca Kaydet (⭐, ⌘D) + Seslendir/Durdur (⇧⌘S/⇧⌘X) gorunur
- [x] Kopyala, Quick Export, Export Fields (⌘E), Clear Outputs → tek "⋯" Menu;
      ⌘E gizli shortcut butonuyla menu kapaliyken de calisir
- [x] Ayarlar (⚙) kaldirildi (⌘, ve uygulama menusu yeterli); kullanilmayan
      `openSettings` env temizlendi
- [x] Header tek temiz satira indi (8 ikon → 3 gorunur + ⋯)

## Faz 4 — Modul grid: overflow'u "More" altina (tamamlandi)

- [x] `moduleGrid`: 5 birincil modul + "More modules" disclosure; acilinca diger 5 modul
      birincil ile ayni stille (soluk/compact overflow gorunumu kaldirildi); kapaliyken
      overflow'ta cikti varsa kucuk aksan noktasi
- [x] Acik/kapali `@AppStorage("inspectorShowMoreModules")`; Run All (⇧⌘R) korundu
- [x] Modul kisayollari (⌘1-5 gorunur butonlarda, ⌘6-0 her zaman aktif gizli butonlarda);
      overflow sutunlari Run All slotuyla hizalandi

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
