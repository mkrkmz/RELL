# RELL Roadmap v18 — Sakin ve Tutarli Bir Arayuz (S0 + 5 sprint)

Olusturulma: 2026-10-15 (v1.47.2 hazirligi sonrasi). Amac: islevleri
olgunlasmis bir uygulamanin arayuzunu tek bir sakin, tutarli dile
toplamak — once ortak tasarim temeli, sonra en cok kullanilan uc yuzey
(Inspector, okuma ekrani, kelime defteri ve calisma odasi). Yaninda kisa
bir guvenilirlik borcu sprinti. Tek surum: **1.48.0**. v17 roadmap'i:
`docs/archive/ROADMAP-v17.md`.

v17 kapandi: **1.47.0** ve **1.47.1** (2026-10-14) — her yapay zeka
istegi kayit altinda (`LLMRequestLog`), bu Mac'teki modeller ve Apple'in
cihaz ici modeli icin oncelik kuyrugu (Apple tek istek, arka plan isi
senin istegine yol verir), model on yukleme ve sicak tutma, yanitin alt
satiri (motor, sure, yavaslik sebebi), Ayarlar ▸ Yapay Zeka ▸ Hiz (hiz
testi, oneriler, son istekler), tani raporu, guncelleme denetimi, yeni
ilk acilis. 1.47.2 hazir (yayinlanmadi): uzun yanitta Inspector'in yedek
duzene dusmesi duzeltildi, sade secim cubugu ve kapatma ayari. Ders:
"paralel calisir" varsayimi olculmeden yapilmaz (Apple modeli tek tek
isliyor); `ViewThatFits` ideal boyla olcer, kaydirma alaninin ideal boyu
icerigin tamamidir.

## Durum (2026-10-15, kod taramasi)

| Olcu | Deger |
|---|---|
| Swift dosyasi | 208 |
| DS disi yazi tipi cagrisi (`.font(.system`, DS-exempt disinda) | 5 |
| Dogrudan renk degeri (`Color.red`, `Color(red:)` …) | 13 |
| Sayiyla verilmis bosluk / kose yuvarlakligi | 30 / 7 |
| `.buttonStyle(.plain)` ile elle cizilmis buton | 72 (ortak "sakin buton" stili yok) |
| `.onHover` kullanimi | 16 (her biri kendi vurgusunu ciziyor) |
| Cam (`glassEffect` / `dsGlass`) kullanimi | 20 |
| Inspector (`InspectorView*.swift`) | ~2100 satir, iki duzenli (`ViewThatFits` yedegi) |
| Kelime sayfasi / sinav ekrani | 696 / 1041 satir |

- 1.47.2'deki secim cubugu ilk "sakin buton" ornegi: zemin yok, renk
  yalniz ikonda, isaretcinin altinda hafif vurgu. Bu dil henuz baska
  yerde yok.
- Inspector bes katman ust uste diziyor (kelime karti, mod/ayrinti, modul
  izgarasi, sonuc + alt satir, Ask AI); yer kalmayinca butun panel kayan
  yedek duzene geciyor.

## Teknik cerceve (tum sprintler icin gecerli)

v17 cercevesi aynen devralinir: sifir dis bagimlilik, macOS 15 hedefi,
tam test paketi, **async testler**, makineye bagli test `XCTSkip`,
`Text(String)` katalogu atlar, xcstrings bos nesne bicimi korunur, DS
token'lari, bundle id/sandbox'a dokunulmaz; **once maket** (her UI sprinti
HTML maketle baslar, onaysiz kod yok); "pencereyi buyutmez" testleri;
erisilebilirlik taramasi; her push'tan sonra `gh run list` ile Test ve
Build; her sprint sonu canli tur; olcumler ayni makinede, temel commit'le
yan yana; testten once calisan RELL varsa komut durur. Eklenenler:

- **Once temel, sonra yuzey.** S1'deki ortak bilesenler (buton stilleri,
  hover, hareket, cam kurali) S2–S4'te kullanilir; bir yuzey kendi ozel
  stilini yeniden icat etmez.
- **Davranis korunur.** Bir ozelligin yeri degisirse eski yolu (menu,
  kisayol) calismaya devam eder; ozellik ekleme/cikarma yalniz acik
  kararla.
- **Uc sayfa temasi + iki sistem gorunumu.** Her maket ve gorsel kontrol
  beyaz, sepya ve koyu sayfada; acik ve koyu sistem gorunumunde.

**Bilincli olarak v18 disinda:** yeni ozellikler (konusma pratigi, cumle
madenciligi), Apple-Developer-kilitli kalemler (notarization, widget,
CloudKit), iOS.

---

## Kararlar (2026-10-15)

1. Odak: Inspector'i sadelestirmek, okuma ekrani ve yuzen ogeler, kelime
   defteri ve calisma odasi, tasarim sistemi turu; yaninda guvenilirlik
   borcu.
2. Sira: tasarim sistemi once (S1), ardindan Inspector, okuma ekrani,
   kelime defteri.
3. Tek surum 1.48.0; 1.47.2 S0'da ayri yayinlanir (onayla).

---

## Sprint 0 — "Guvenilirlik borcu" (Must, kisa)

- [x] **Test ayar dosyalari** — sebep: `removePersistentDomain` alani
      bosaltiyor ama 42 baytlik bos dosyasini birakiyor; her test her
      calismada yeni UUID adli suite actigi icin 659 dosya birikmisti.
      `scratchDefaults()` (test sinifi basina sabit ad, testten once ve
      sonra bosaltilir) 9 kullanimin hepsinde; test sunucusunun suite'i
      sabit `rell-test-host`, her calismada bosaltilir. Iki ardisik tam
      calismada dosya sayisi 8'de sabit. Eski 659 artik onayla silindi
- [x] **Ornek kitaplar** — gelistirme makinesindeki kitaplara bagli uc
      EPUB testi (bolumlenmis kitap ×2, siradan kitap; 70–150 sn, diger
      makinelerde atlaniyordu) `MiniEPUB` ile uretilen kucuk kitaplara
      gecti: basliklari ayri sayfada bir kitap ve siradan bir kitap. Uc
      test 0,1 sn
- [x] Gozlem: `DocumentCoverStoreTests` tam paket yuku altinda bir kez
      dustu (PDF kapagi zaman asimi), tek basina ve ikinci tam calismada
      yesil — dalgali; S5'te tekrar bakilir
- [x] **1.47.2** yayinlandi (2026-10-15; Release is akisi yesil, DMG + zip, Latest)

## Sprint 1 — "Tasarim sistemi turu" (Must, **maketle baslar**)

- [ ] **Ortak buton stilleri** — sakin (zeminsiz, ikon renkli, hover'da
      hafif vurgu; secim cubugundan), ana, ikincil, yalniz ikon; `DS`
      altinda `ButtonStyle`'lar; 72 elle cizilmis butonun uygun olanlari
      tasinir
- [ ] **Hover ve hareket dili** — tek hover vurgusu, `DS.Animation`
      sureleri, Reduce Motion
- [ ] **Cam kurali** — Liquid Glass yalniz metin ustunde olmayan kabukta
      (arac cubugu, kenar cubugu, sayfa disi paneller); metin ustu opak
      (`dsReadingOverlay`) kalir; 20 kullanim taranir
- [ ] **Kural disi degerler** — 5 yazi tipi, 13 renk, 30 bosluk, 7 kose
      yuvarlakligi DS token'ina; grep denetimi (pre-commit) genisler
- [ ] Koyu tema ve odak halkasi taramasi; "pencereyi buyutmez" testleri

## Sprint 2 — "Inspector'i sadelestirmek" (Must, **maketle baslar**)

- [ ] Moduller tek serit ya da sekmeler; sonuc tam yukseklikte; Ask AI
      acilir-kapanir; kelime karti yenilenir — yedek duzen yalniz gercekten
      kisa pencerede
- [ ] Mevcut kisayollar (⌘R, ⇧⌘C, ⇧⌘R, Esc) ve menuler korunur
- [ ] `LayoutGuard` testleri (kisa sutun, en kucuk pencere, uzun sonuc)

## Sprint 3 — "Okuma ekrani ve yuzen ogeler" (Must, **maketle baslar**)

- [ ] Imlec sozlugu balonu, baglam seridi, Zen arac cubugu, gorunum
      paneli (yazi tipi, tema), secim cubugu ayni sakin dilde
- [ ] Uc sayfa temasinda okunurluk; yuzen ogeler metni kapatmaz

## Sprint 4 — "Kelime defteri ve calisma odasi" (Should, **maketle baslar**)

- [ ] Kelime sayfasi (hafiza gucu, sonraki tekrar, karsilasmalar),
      defter listesi ve tablosu, calisma karti ve ozeti icin gorsel
      yenileme
- [ ] Erisilebilirlik: renk tek bilgi tasiyicisi degil, klavye akislari

## Sprint 5 — "Kapanis"

- [ ] Kapanis (Must): tam test, soguk acilis (1.47.2 ile yan yana), canli
      tur, CHANGELOG 1.48.0 + Yenilikler 1.48
- [ ] **1.48.0** yayini

---

## Genel dogrulama (her sprint sonu)

Tam test paketi (CI komutuyla birebir, `make ci-test`), regresyon testleri
mutasyonla dogrulanir, push sonrasi Test ve Build is akislari yesil, canli
tur (RELL acikken ikinci kopya calistirilmaz), xcstrings TR tamamlama.
