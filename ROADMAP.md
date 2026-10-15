# RELL Roadmap v18 — Sakin ve Tutarli Bir Arayuz (S0 + 6 sprint)

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
4. (S2 maketi) Kendi modullerin S2'den hemen sonra ayri sprint (S3);
   okuma ekrani S4, kelime defteri S5, kapanis S6.

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

Maket onayi (2026-10-15): bes karar — bes buton stili DS'te; ekranda en
fazla bir ana buton, yalniz ilerleten iste (satir ici Kaydet/Dinle/Anki
sakin); tek hover kurali; cam yalniz kabukta, metnin ustunde hic;
ayni yerde kalan butonun stili S1'de, yerlesim S2–S4'te.

- [x] **Ortak buton stilleri** — `DSButtonStyles.swift`: `.dsQuiet`
      (zeminsiz, ikon aksan, etiket metin rengi), `.dsIcon` /
      `.dsIconSecondary` / `DSIconButtonStyle(tint:)`, `.dsChip(isOn:)` ve
      `.dsChipTile(isOn:tint:)`; ana ve ikincil sistemin `.borderedProminent`
      / `.bordered`'i. Tasindi: secim cubugu, Inspector kelime karti (dolu
      Kaydet + renkli Dinle/Anki → sakin), sonuc dugmeleri (cam → ikon),
      modul kutucuklari (cam → cip kutucugu), kutuphane, kelime listesi
      arac cubugu, seslendirme cubugu, yer imleri ve notlar (gri dolgulu
      kareler → ikon), ayarlardaki sifirla dugmeleri, Kindle/guncelleme
      seritleri. `.plain` 72 → 54 (kalanlar liste satiri, kart, metin alani
      ici "temizle" ya da S4'un ekranlari)
- [x] **Ana buton kurali** — acilis rehberinde "Sistem Ayarlari'ni Ac" ve
      "Baglantiyi Test Et", ana ekrandaki guncelleme "Indir" ikincil oldu
      (ekranin tek ana butonu Devam / Ac)
- [x] **Hover ve hareket dili** — `DS.Interaction.wash` (fare uzerinde
      %6, koyuda %8; basili %11 / %14), `DS.Animation.fast`, Hareketi
      Azalt'ta animasyon yok, kapali %38; hepsi `DSWashedButton`'da tek yerde
- [x] **Cam kurali** — metnin ustundeki cumle cevirisi seridi, PDF ve
      EPUB arama cubuklari opak (`dsReadingOverlay`, sayfa temasini izler);
      Inspector dugmeleri cam degil. Kenar cubugu, Inspector zemini, Hizli
      Arama paneli cam kaldi. Sinav ekrani S4'te
- [x] **Kural disi degerler** — renkler `DS.Color.warning` / yeni
      `DS.Color.kindle`; yazi tipleri yeni `DS.Typography.serifTitle`,
      `monoBody`, `monoCallout`; boşluklar DS adimlariyla birebir ayni
      toplamlarda (yeni `DS.Spacing.hairline` = 1), kose yuvarlakliklari yeni
      `DS.Radius.cell` / `hairline` / `cover`. Ilk taramanin disindaki
      `Export/` klasorunde 4 deger daha bulundu ve tasindi
- [x] **Denetim testi** — `DesignSystemAuditTests`: kaynakta cig yazi
      tipi, sayiyla bosluk / kose yuvarlakligi, adla renk (`DS.` disinda)
      yasak; `// DS-exempt: <sebep>` ayni satirda ya da iki ust satirda.
      CLAUDE.md'deki "grep denetimi" hic kurulmamisti; artik CI'da.
      Mutasyon: eklenen `.padding(.horizontal, 6)` testi dusuruyor.
      Tam paket 760 yesil
- [ ] Canli tur (kullanici)

## Sprint 2 — "Inspector'i sadelestirmek" (Must, **maketle baslar**)

Maket onayi (2026-10-15, 2. surum — kullanicinin onerisiyle): moduller
kelime kartinin icinde, Kaydet/Dinle/Anki ile ayni sade dugmeler; kartta
iki satir (ustte islemler, altta moduller); hangi modulun kartta, hangisinin
••• menusunde duracagini kullanici secer (Karti Duzenle…, sag tik, 📌);
sigmayan kendiliginden •••'e gecer, satir bolunmez; sonuc basligi tek
satir (modul adi, Kisa/Ayrintili, Yenile, Kopyala); bir modul hep acik;
Ask AI tek satir, kullaninca acilir; modul adlari Turkce. Cumle karti ayni
yapida (Acikla, Dilbilgisi, Sadelestir, Yeniden Anlat), kendi listesiyle.
Kart duzeni moduller icin genel kimlik kullanir: S3'teki kendi modullerin
ayni yere takilir.

- [ ] Kart duzeni modeli (saf): kartta / •••'de, sira, sigan sayisi
- [ ] Kelime ve cumle karti; "Aciklamalar" bolumu ve kutucuk satiri kalkar
- [ ] Karti Duzenle… sayfasi; sag tik ve 📌; Ayarlar ▸ Okuma ▸ Inspector
- [ ] Sonuc basligi tek satir; bir modul hep acik ("Getir" otomatik
      calistirma kapaliyken)
- [ ] Ask AI acilir-kapanir
- [ ] Modul kisa adlari katalogdan (bugun Turkce arayuzde Ingilizce)
- [ ] Mevcut kisayollar (⌘R, ⇧⌘C, ⇧⌘R, ⌘D, ⇧⌘S) ve menuler korunur
- [ ] `LayoutGuard` testleri (kisa sutun, en kucuk pencere, uzun sonuc,
      Ask AI acik, cumle secimi)

## Sprint 3 — "Kendi modullerin" (Should, **maketle baslar**)

Karar (2026-10-15): S2'den hemen sonra, ayri sprint. Yerlesik moduller
kapali bir liste (`ModuleType`) ve onbellek, kayitli kelimeler, Anki,
Apple yonlendirmesi, Eksikleri Doldur, seviye tahmini, ozel ayristiricilar
ve modul basina ayarlara bagli; kendi modullerin bunlara karismaz.

- [ ] Ayri tur: ad, ikon, yer tutuculu istem (`{kelime}`, `{cumle}`, `{ana
      dil}`, `{hedef dil}`), yanit dili, uzunluk, motor (varsayilan
      saglayici; Apple istege bagli); kendi dosyasinda, yedeklerde
- [ ] Ayarlar ▸ Istemler'de duzenleyici, ornek kelimeyle "Dene"; Inspector'da
      yalniz Karti Duzenle… ▸ "Yeni Modul…"
- [ ] Inspector karti, kuyruk ve alt satir; onbellek anahtari istemin
      icerigini icerir; kelimeyle saklama (bicim degismez); Anki istege bagli
- [ ] Girmez: Eksikleri Doldur, seviye tahmini, ozel ayristiricilar
- [ ] Gizlilik tablosunda satir; yanit uzunlugu siniri; silinen modulun
      kayitli yanitlari adiyla kalir

## Sprint 4 — "Okuma ekrani ve yuzen ogeler" (Must, **maketle baslar**)

- [ ] Imlec sozlugu balonu, baglam seridi, Zen arac cubugu, gorunum
      paneli (yazi tipi, tema), secim cubugu ayni sakin dilde
- [ ] Uc sayfa temasinda okunurluk; yuzen ogeler metni kapatmaz

## Sprint 5 — "Kelime defteri ve calisma odasi" (Should, **maketle baslar**)

- [ ] Kelime sayfasi (hafiza gucu, sonraki tekrar, karsilasmalar),
      defter listesi ve tablosu, calisma karti ve ozeti icin gorsel
      yenileme
- [ ] Erisilebilirlik: renk tek bilgi tasiyicisi degil, klavye akislari

## Sprint 6 — "Kapanis"

- [ ] Kapanis (Must): tam test, soguk acilis (1.47.2 ile yan yana), canli
      tur, CHANGELOG 1.48.0 + Yenilikler 1.48
- [ ] **1.48.0** yayini

---

## Genel dogrulama (her sprint sonu)

Tam test paketi (CI komutuyla birebir, `make ci-test`), regresyon testleri
mutasyonla dogrulanir, push sonrasi Test ve Build is akislari yesil, canli
tur (RELL acikken ikinci kopya calistirilmaz), xcstrings TR tamamlama.
