# RELL Roadmap v16 — Kelimeler Kitabinda, Hepsi Bir Yerde (S0 + 4 sprint)

Olusturulma: 2026-10-09 (v1.44.0 sonrasi). Kullanicinin istegi: bir kitabin
kenar cubugunda **yalniz o kitabin kelimeleri** olsun; **tum kayitli
kelimeler** ana ekrandaki Tools'tan acilan ayri bir alanda, calisma odasi
gibi kendi penceresinde dursun. Kullanici bu duzeni tamamlayan alti oneriyi
de secti (asagida). Tek surum: **1.45.0**. v15 roadmap'i:
`docs/archive/ROADMAP-v15.md`.

v15 kapandi: S0–S4 tek surum olarak **v1.44.0** (2026-10-09) — Eksikleri
doldur (Apple sozlugu → cihaz ici model → saglayici, kaynak isaretli,
kaydederken doldurma), Calisma odasi (tam ekran pencere, oturum kurulumu,
buyuk kart, ←/→/S, ozet), yeni kelime tanitimi, "Asamaya gore" mod, i+1
cumleler, zorlu kelimeler + akilda tutma ipucu, Kindle kelime defteri
aktarimi. 689 test. Dersler: ayristiricilar kullanicinin gercek verisinde
denenir; macOS 15'te ic ice izole deinit coker (testler async); App Intents
takim kimligi ister.

## Durum (2026-10-09, kullanicinin verisi, salt okunur)

| Olcu | Deger |
|---|---|
| Kayitli kelime | 590 |
| Kaynagi kitaplikta acik bir belge olan | **55** |
| Kindle'dan gelen (kitap adi, dosya degil) | ~530 (The Hunger Games 293, Why We Sleep 214, …) |
| Kitaplikta belge | 7 (ayni "Why We Sleep" iki dosya: `Matthew Walker PhD - Why We Sleep_…`, `Why We Sleep_ Unlocking…`) |
| Okurken karsilasma kaydi | 212 |

- Kelime listesi bugun yalniz okuyucunun kenar cubugunda (`WordsView` →
  `SavedWordsListView`) ve **tum** kelimeleri gosterir; "This Document"
  yalniz bir filtre. Ana ekranda kenar cubugu yok: tum kelimelere ana
  ekrandan ulasilamiyor.
- Kelimenin kitabi yalniz `SavedWord.pdfFilename` (uzantisiz dosya adi;
  Kindle'da kitap basligi). Tam esleme: Kindle'daki 214 "Why We Sleep"
  kelimesi RELL'deki ayni kitapla eslesmez; ayni kitabin iki kopyasi
  birbirinin kelimelerini gormez.
- Karsilasmalar (`WordEncounterStore`) belge yolu + baslik tasir: "baska
  yerde kaydedip bu kitapta yeniden gordugun" kelimeler hazir.

## Teknik cerceve (tum sprintler icin gecerli)

v15 cercevesi aynen devralinir: sifir dis bagimlilik, macOS 15 hedefi, tam
test paketi, **async testler**, makineye bagli test `XCTSkip`,
`Text(String)` katalogu atlar, DS token'lari, bundle id/sandbox'a
dokunulmaz; **once maket** (her UI sprinti HTML maketle baslar, onaysiz kod
yok); sutunlarda yerlesim kurali + "pencereyi buyutmez" testleri; metin
ustunde `.dsReadingOverlay()`; erisilebilirlik taramasi; her push'tan sonra
`gh run list` ile Test ve Build; her sprint sonu canli tur; ayristirici /
esleyici kullanicinin gercek verisinde denenir (gecici salt okunur test).
Eklenenler:

- **Kitap kimligi tek yerde.** "Bu kelime hangi kitabin?" sorusu tek bir
  saf fonksiyondan cevaplanir (S0); kenar cubugu, calisma odasi, kelime
  defteri, kitaplik sayilari ve Anki ayni cevabi kullanir.
- **Veri bicimi** degisirse eski dosya kayipsiz okunur; yeni alanlar
  istege bagli (decode testleri). Birlestirme gibi geri donulmez islemler
  onay ister ve oncesinde yedek alinir.

**Bilincli olarak v16 disinda:** yeni okuma ozellikleri, iOS,
Apple-Developer-kilitli kalemler (notarization, widget, App Group,
CloudKit, Kisayollar).

---

## Kararlar (2026-10-09, kullanici onayi)

1. Kitabin kelime listesi: **bu kitaptan kaydedilenler** ustte, **baska
   yerde kaydedilip bu kitapta yeniden karsilasilanlar** ayri grup olarak
   altta.
2. Ayni kitap farkli kaynaklardan (Kindle basligi, ayni kitabin iki dosyasi)
   **basliktan eslestirilir**; yanlis eslesmeye karsi kitap basina
   kapatilabilir.
3. Tum kelimeler **ayri pencere** ("Kelime defteri"): solda liste, sagda
   secili kelimenin sayfasi; ana ekran Tools, ⌘K ve menuden acilir.
4. Secilen oneriler: tablo gorunumu, kitaplikta kelime sayilari, bu kitabi
   calis, ayni kelimeyi birlestir, Kindle'da yeni kelime bildirimi, kitap
   bazinda Anki alt destesi.

---

## Sprint 0 — "Kitap kimligi ve zemin" (Must, kisa)

- [x] **Kitap kimligi** — `BookIdentity` (Models/): ad → sozcukler
      (" -- " sonrasi, "_", "(2017)"/"(1)", "PhD" atilir); kisa adin
      sozcukleri uzun adin icinde art arda geciyorsa ayni kitap; tek sozcuk
      ve 30 sozcukten uzun "baslik" yalniz tam eslesir. `SavedWord.documentPath`
      (istege bagli; okuyucudaki kaydetme yollari yazar), once dosya sonra ad.
      **Olcum** (590 kelime, 7 belge, Kindle basliklari; ayni kural
      Python'da, RELL acikti): 8 eslesme, hepsi dogru, yanlis yok.
      Why We Sleep: dosya adiyla 6/12 → basliktan **232**; Harry Potter 12
      (+26 karsilasilan), Crime and Punishment 12 (+6). Bir hikaye
      karsilasmasinin "basligi" metnin tamami (eski surumun dosyasi;
      hikaye basligi v13'te duzeltilmis) — 30 sozcuk siniri bunu eler.
      `BookIdentityTests` (gercek adlarla)
- [x] **macOS 15 deinit cokmesi** — 48 ana aktor sinifina
      `nonisolated deinit {}` (hicbirinin deinit govdesi yoktu); ikili
      dosyada yalniz uretilen `ResourceBundleClass` kaldi.
      `DeinitIsolationTests` bilerek senkron (store → yazici, servis →
      store, pencere modelleri); `WindowLayoutTests` okuyucu testi macOS
      15'te yeniden acik — CI kaniti
- [x] Soguk acilis (2026-10-09) — ayni makinede, ayni oturumda yan yana
      (`testLaunchPerformance`, 5 olcum): v15 basi a81fcd3 ortanca ~355 ms,
      1.44.0 ~410 ms, S0 (6ad3336) ~390–410 ms. v15 + S0 en fazla ~40–50 ms
      ekledi, olcumlerin yayilimi (330–430) icinde. RELL kapatildiktan hemen
      sonraki ilk uc tur ~600 ms cikti — arka plan isleri; ayni kod biraz
      sonra 410 ms. Ders: tarihsel sayiyla degil, temel commit'i ayni anda
      olcerek karsilastir (git worktree)

## Sprint 1 — "Kitabin kelimeleri" (Must, **maketle baslar**)

Maket onayi (2026-10-09, onerilerle): birlestirme anahtari ••• menusunde
kaynak listesiyle; "yeniden karsilasilan" ilk 5; bekleyen yoksa "Tumunu
calis"; Kindle aktarimi S2'de pencereye; kenar cubugunda disa aktarma
yalniz bu kitap.

- [x] **Kenar cubugunda kitap kelimeleri** — `BookWords` (saf): bu
      kitaptan kaydedilenler (dosya yolu, dosya adi, basliktan esleşen
      kopyalar ve Kindle) + bu kitapta yeniden karsilasilanlar; ayri adlar
      bir kez eslenir (~1 ms/kitap, 590 kelime). Liste: kitap basligi +
      sayilar + ••• (birlestirme anahtari, kaynaklar, bu kitabi calis, bu
      kitabin kelimelerini disa aktar); iki bolum; arama/filtre/eksikleri
      doldur/disa aktarma kitap icinde; "This Document" filtresi kalkti;
      satirda Kindle etiketi. Gercek veri: Why We Sleep 232 + 10 (Kindle
      214, diger kopya 12/6, bu dosya 6/12), Harry Potter 12 + 26
- [x] **Bu kitabi calis** — kenar cubugundaki Tekrar yalniz bu kitabin
      kelimeleri; bekleyen yoksa "Tumunu calis (N)"; "Bu kitabi tam
      ekranda calis" calisma odasini kaynak "Bu kitap" ile acar
      (`studyRoomPresetBookPath`); `StudySource.book` artik basliktan eslesir
- [x] **Eslesmeyi kapatma** — kitap basina, `bookTitleMatchingOff`
- [x] Testler: `BookWordsTests` (4) — kopyalar ve Kindle, yeniden
      karsilasilanlar, anahtar, baslik gorunumu, liste en dar kenar
      cubugunda pencereyi buyutmez. Tam paket 700 yesil
- [x] Canli tur (2026-10-09, sorun yok)

## Sprint 2 — "Kelime defteri penceresi" (Must, **maketle baslar**)

Maket onayi (2026-10-09, onerilerle): uc sutun; pencerede degisiklik
hemen kaydedilir (silme onay ister), kenar cubugundaki sayfa Kaydet/Iptal
ile kalir; acilis liste, secim hatirlanir; ⌥⌘K; toplu doldurma once sozluk
turu, yarida kalan devam eder.

- [x] **Kelime defteri** — `Window("Word Notebook", id: "words")`,
      `WordNotebookView`: sol sutun durumlar (tumu, tekrar bekleyen, hic
      calisilmamis, sik unutulan, anlami eksik) + kitaplar (`WordNotebook.books`,
      adlar basliktan kumelenir: Why We Sleep tek satir) + desteler; orta
      `SavedWordsListView` (havuz + secim + tablo modu; tek tik secer, cift
      tik sayfa acar); sag `SavedWordDetailSheet(isPane:)` — degisen alanlar
      depodaki en guncel kelimenin uzerine yazilir. Girisler: ana ekran
      Tools karosu, ⌘K (komut + kelime sonuclari artik defterde acilir),
      Git menusu ⌥⌘K, kitabin "Tum kelimeler…", Spotlight. Kindle aktarimi
      ve "Tumunu sil" yalniz defterde; kitabin kenar cubugunda "Tum
      kelimeler…"
- [x] **Tablo gorunumu** — `WordTable`: kelime, anlam, seviye, durum,
      sonraki tekrar, kitap; her sutun siralanir
- [x] **Doldurma (karar 5)** — once butun kelimelerde sozluk turu, sonra
      model turu ("Sozluk · x / y", "Modeller · x / y"); yarida kalan
      `fillPendingWordIDs` ile acilista yalniz yerel kaynaklarla surer,
      Durdur unutturur (test sureci kendi defaults'unu kullanir). Neden:
      Kindle'dan gelen 529 kelimenin yalniz 18'i dolmustu
- [x] Testler: `WordNotebookTests` (6) — kitap kumeleri, kaynaklar, sozluk
      once, devam, durdur, pencere en kucuk boyutta buyumez
- [x] Tam test (yerel 706 yesil) + canli tur (2026-10-09, sorun yok).
      CI'da macOS 15: tum split view test penceresinde arac cubugu kadar
      (560 → 588) buyudu; sutunlar ayri ayri olculuyor (liste, tablo,
      kelime sayfasi) — uygulamanin penceresinde arac cubugu bastan var

## Sprint 3 — "Duzen" (Should)

Kullanici maketsiz kodlanmasini istedi (2026-10-09).

- [x] **Kitaplikta kelime sayilari** — `documentStats` artik `BookWords`
      ile (kopyalar ve Kindle dahil) kayitli + tekrar bekleyen; izgara
      kartinda tiklanir rozet ("232 · 9") kelime defterini o kitapla acar
      (`WordNotebook.open(onBookNamed:)`, adi tasimayan dosya basliktan
      bulur); liste kartinda alt satirda sayi, sag tikta "Bu kitabin
      kelimelerini goster"
- [x] **Ayni kelimeyi birlestir** — `WordMerge` (saf): ayni dilde ayni kok
      (`LemmaMatcher`); kalacak olan once en cok tekrar edilen, sonra en
      eski. Birlesim: bos kart alanlari kaynagiyla, desteler, notlar, diger
      cumleler notlara, tekrar gecmisinin tamami, FSRS durumu daha ileride
      olandan, en eski kayit tarihi; karsilasmalar tasinir
      (`WordEncounterStore.reassign`). Defterde "Iki kez kaydedilen"
      kaynagi + `DuplicateWordsView` (radyo ile secim, onayli birlestirme);
      oncesinde `PersistenceBackup.snapshotBeforeChange` (son 5 tutulur).
      Gercek veri: 8 cift (drenched/drench, scowled/scowl…), hepsi dogru, 89 ms
- [x] **Kindle'da yeni kelime var** — `KindleNoticeBanner` ana ekranda:
      acilista ve Kindle takilinca (`didMountNotification`) aktarimin
      getirecegi sayi; "Aktar…" Kindle penceresini acar, kapatinca daha
      fazlasi olana kadar gizli
- [x] **Kitap bazinda Anki** — "Her kitap icin ayri Anki destesi":
      Deck sutunu + `#deck column:5`, `RELL::<kitap>` (basliktaki ":"
      alt deste yaratmasin diye "-")
- [x] Testler: `OrganizeTests` (7). Tam paket 713 yesil
- [x] Canli tur (2026-10-09) — kitaplik rozeti basligin ustune biniyordu
      (kartin tamamina bindirilmisti, beyaz zeminde gri); kapagin sag alt
      kosesine, kapsama rozeti gibi koyu zemine tasindi (4bd55e1)

## Sprint 4 — "Kapanis"

- [x] Kapanis (Must): tam test (713 yesil), performans (ayni oturumda
      donusumlu: 1.44.0 ortanca ~568/579 ms, simdi ~594/592 ms — fark
      olcum yayilimi icinde), canli turlar (S1–S3, kullanici), CHANGELOG
      1.45.0 + Yenilikler 1.45
- [ ] **1.45.0** etiketi (kullanicinin onayiyla)

---

## Genel dogrulama (her sprint sonu)

Tam test paketi (CI komutuyla birebir, `make ci-test`), regresyon testleri
mutasyonla dogrulanir, push sonrasi Test ve Build is akislari yesil,
kullanicinin canli turu (RELL acikken ikinci kopya calistirilmaz),
xcstrings TR tamamlama.
