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

- [ ] **Kitap kimligi** — `BookIdentity`: dosya adi / Kindle basligi →
      karsilastirma anahtari (yazar, "PhD", isbn, "Anna's Archive", `_`,
      yil gibi gurultu atilir; baslik on eki eslesmesi). `SavedWord`'e
      istege bagli `documentPath` (yeni kayitlarda; eski kayitlar
      `pdfFilename`'den eslesir). Olcum: 590 kelime × 7 belge × Kindle
      basliklari — dogru/yanlis eslesme tablosu, ROADMAP'e islenir
- [ ] **macOS 15 deinit cokmesi** (Should) — v15'te bekleyen gorev: ic ice
      izole deinit'ler (`ReaderWindowModel` → yoneticiler,
      `SavedWordsStore` → `DebouncedFileWriter`) okuyucu penceresi
      kapanirken macOS 15'te cokebilir; `nonisolated deinit`, CI'da
      senkron test ile kanit, `WindowLayoutTests` okuyucu testi macOS
      15'te yeniden acilir
- [ ] v15 takibi (Should): soguk acilis olcumu (S0 v15: ortanca 498 ms)

## Sprint 1 — "Kitabin kelimeleri" (Must, **maketle baslar**)

- [ ] **Kenar cubugunda kitap kelimeleri** — iki grup (karar 1): bu
      kitaptan kaydedilenler (basliktan eslesenler dahil, karar 2) ve bu
      kitapta karsilasilanlar; sayilar, arama ve filtreler kitap icinde;
      "This Document" filtresi kalkar; altta "Tum kelimeler…" baglantisi
- [ ] **Bu kitabi calis** — kenar cubugundaki Tekrar yalniz bu kitabin
      kelimelerini sorar; "Tam ekranda calis" calisma odasini kaynak "Bu
      kitap" ile acar (basliktan eslesen Kindle kelimeleri dahil)
- [ ] **Eslesmeyi kapatma** — kitap basina "Baska kaynaklarla birlestirme"
- [ ] Testler: kitap kelimeleri, iki grup, kaynak; kenar cubugu pencereyi
      buyutmez

## Sprint 2 — "Kelime defteri penceresi" (Must, **maketle baslar**)

- [ ] **Kelime defteri** — yeni pencere (calisma odasi gibi): solda liste
      (arama, durum/seviye/deste/dil + **kitap** filtresi, eksikleri
      doldur, Kindle, disa aktar, coklu secim), sagda secili kelimenin
      sayfasi (sheet yerine yan yana); ana ekran Tools karosu, ⌘K, Git
      menusu; Spotlight'tan kelime acmak bu pencereye gider
- [ ] **Tablo gorunumu** — liste/tablo anahtari; siralanabilir sutunlar:
      kelime, anlam, seviye, durum, sonraki tekrar, kitap; coklu secimle
      toplu islemler
- [ ] Testler: pencere en kucuk boyutta buyumez, tablo siralamasi

## Sprint 3 — "Duzen" (Should)

- [ ] **Kitaplikta kelime sayilari** — ana ekran ve kitaplik kartlarinda
      kitap basina kayitli / tekrar bekleyen; tiklayinca kelime defteri o
      kitapla acilir
- [ ] **Ayni kelimeyi birlestir** — ayni kokten kayitlar ("gleaming" /
      "gleam"): kelime defterinde oneri, onayla birlestirme (cumleler,
      karsilasmalar, tekrar gecmisi, desteler korunur; FSRS durumu daha
      ileride olandan), oncesinde yedek
- [ ] **Kindle'da yeni kelime var** — Kindle baglaninca son aktarimdan beri
      eklenenler ana ekranda sessizce; tek tikla yalniz yeniler
- [ ] **Kitap bazinda Anki** — disa aktarimda kitap alt destesi
      (`RELL::Why We Sleep`)

## Sprint 4 — "Kapanis"

- [ ] Kapanis (Must): tam test, performans karsilastirmasi, canli tur,
      CHANGELOG + Yenilikler, **1.45.0** (tag oncesi kullaniciya sorulur)

---

## Genel dogrulama (her sprint sonu)

Tam test paketi (CI komutuyla birebir, `make ci-test`), regresyon testleri
mutasyonla dogrulanir, push sonrasi Test ve Build is akislari yesil,
kullanicinin canli turu (RELL acikken ikinci kopya calistirilmaz),
xcstrings TR tamamlama.
