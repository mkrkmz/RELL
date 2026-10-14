# RELL Roadmap v17 — Her Mac'te Hizli ve Anlasilir (S0 + 4 sprint)

Olusturulma: 2026-10-13 (v1.46.1 sonrasi). Amac: yapay zeka yanit
suresini farkli donanim ve sistem yapilandirmalarinda tutarli ve hizli
kilmak, sure farklarinin sebebini kullaniciya gorunur kilmak ve RELL'i ilk
kez kuran birinin sorunsuz baslamasini saglamak. Iki odak: **"Her Mac'te
iyi"** ve **"Daha hizli yapay zeka"**. Tek surum: **1.47.0**. v16 roadmap'i:
`docs/archive/ROADMAP-v16.md`.

v16 kapandi: S0–S4 tek surum olarak **v1.45.0** (2026-10-09) — kitabin
kenar cubugunda yalniz o kitabin kelimeleri (basliktan eslesen kopyalar ve
Kindle dahil), Kelime defteri penceresi (⌥⌘K; kaynaklar | liste/tablo |
kelime sayfasi), ayni kelimeyi birlestirme (yedekle), Kindle'da yeni kelime
bildirimi, kitap basina Anki destesi, kitaplik kartlarinda kelime sayisi,
macOS 15 deinit cokmesi. 713 test. Ardindan 1.46.1 (2026-10-11): yeni ikon
(Icon Composer), logo, README; CI `macos-26`'ya tasindi.

## Mevcut durum ve hipotezler (2026-10-13, kod incelemesi)

Ayni ayarlar ve ayni saglayiciyla calisan iki Mac arasinda yanit suresi
birkac kat farkli olabiliyor. Asagidaki hipotezler olcumle (S0)
dogrulanacak; cozumler tahmine degil rakama dayanacak:

1. **Apple'in cihaz ici modeli.** `AppleOnDevice` varsayilan acik;
   kullanilabildiginde 5 modul (tanim, anlam, ornekler, es anlamlilar,
   kullanim notlari) ve serbest isler (isinma, ozet, satir arasi anlam,
   CEFR, Ask AI) ona gider — v12 spike'inda ortanca 0,9 sn. Apple
   Intelligence kapali / model inmemis / dil desteklenmiyor / macOS 26
   oncesi ise **hepsi** yapilandirilmis saglayiciya gider. Bu bir RELL
   ayari degil, sistem durumu: RELL ayarlari ayni iken fark buradan dogabilir.
   Ayarlar'daki sebep metni (`AppleOnDevice.unavailableReason`) tek yer.
2. **Koordinasyonsuz istekler.** Yalniz inceleme paneli
   `localRequestGate`'ten (LM Studio/Ollama, en fazla 2) gecer.
   `ReadingLoopModel` (bolum isinmasi, "onceki bolumde" ozeti, satir arasi
   anlam partileri) `chatWithFallback` ile kapisiz gider; `CEFREstimator`,
   `WordEnricher`, `QuickLookupService` her biri kendi 1'lik kapisinda.
   Apple modeli yokken bunlarin hepsi ayni yerel GPU'da panelle yarisir;
   tek tek yanitlarin beklenmedik uzunlukta gecikmesini aciklayabilir.
3. **Model yuklemesi.** LM Studio (JIT yukleme + bosta bekleme suresi) ve
   Ollama (`keep_alive`, varsayilan 5 dk) bosta kalan modeli bellekten
   atabilir; sonraki ilk istek modeli yeniden yukler. RELL bugun
   `keep_alive` gondermiyor, onceden isitma yok.
4. **Donanim.** Fansiz modellerde uzun yukte isil kisma; dusuk bellekte
   buyuk model takasa dusebilir. RELL'in kontrolunde degil, ama gorunur kilinabilir
   (S2 hiz testi, S3 bellege gore model onerisi).

Yan bulgular: `LLMSessionPool` oturumlari zaten paylasiyor (baglanti
yeniden kullanimi var). Otomatik calistirma yalniz son kullanilan modulu
calistirir; hepsini calistir ayri kisayol.

## Teknik cerceve (tum sprintler icin gecerli)

v16 cercevesi aynen devralinir: sifir dis bagimlilik, macOS 15 hedefi, tam
test paketi, **async testler**, makineye bagli test `XCTSkip`,
`Text(String)` katalogu atlar, DS token'lari, bundle id/sandbox'a
dokunulmaz; **once maket** (UI sprintleri HTML maketle baslar, onaysiz kod
yok); "pencereyi buyutmez" testleri; erisilebilirlik taramasi; her
push'tan sonra `gh run list` ile Test ve Build; her sprint sonu canli tur;
olcumler ayni makinede, temel commit'le yan yana (git worktree).
Eklenenler:

- **Hiz iddiasi olcumle.** Her "daha hizli" degisikligi S0'in olcum
  duzeniyle once/sonra rakam verir (ilk kelimeye kadar sure, toplam sure,
  sirada bekleme). Rakam yoksa degisiklik yok.
- **Gizlilik.** Yeni her ag istegi (guncelleme kontrolu) gizlilik
  tablosunda (`PrivacySummarySection`) ayri satir. Tani raporu kelime,
  cumle, kitap adi, API anahtari icermez; hicbir sey kendiliginden
  gonderilmez.
- **Farkli yapilandirmalarda dogrulama.** Apple modeli kapatilarak
  modelsiz yapilandirma gelistirme Mac'inde taklit edilir; sprint
  sonlarinda yayin derlemesi ikinci bir Mac'te de denenir.

**Bilincli olarak v17 disinda:** notarization ve otomatik kurulum
(Apple Developer hesabi gerekiyor), konusma/golgeleme, cumle madenciligi,
yeni okuma ozellikleri, iOS.

---

## Kararlar (2026-10-13)

1. Odak: **Her Mac'te iyi** + **Daha hizli yapay zeka**.
2. Guncelleme kontrolu **varsayilan acik, kapatilabilir**: gunde en fazla
   bir kez GitHub'a yalniz son surum numarasi sorulur; kurmaz, bildirir.
3. Oncelik sirasi: panelde yanit beklenirken arka plan isi **yeni istek
   baslatmaz**, baslamis istegi kesmez. Yalniz LM Studio / Ollama icin;
   bulut ve Apple paralel kalir.

---

## Sprint 0 — "Once olc" (Must, kisa)

- [x] **Istek defteri** — `LLMRequestLog` (bellekte son 200, diske
      yazmaz, metin tutmaz): kaynak (`LLMRequestOrigin`: panel modulu, Ask
      AI, hizli bakis, CEFR, doldurma, isinma, ozet, satir arasi, dilbilgisi,
      sadelestirme, yeniden anlatma, hikaye), motor + model, sirada bekleme,
      ilk kelime, toplam, sonuc (bitti / iptal / hata / hic gonderilmedi).
      `RecordedLLMProvider` sarmalayicisi istegin karar verildigi yerde,
      kuyruktan once kurulur; butun istek yollari (`AppleOnDevice.
      recordedProvider`, `chatWithFallback(origin:)`, doldurma, dilbilgisi)
      bundan gecer. Biten her istek `com.rell.app`/`llm` gunlugune tek satir.
      `LLMRequestLogTests` (7)
- [x] **Dogrudan olcum** (2026-10-14, LM Studio, `gemma-4-e4b` Q4_K_M,
      RELL'e benzer tanim istemi, akisli):

      | Durum | Ilk kelime | Toplam |
      |---|---|---|
      | Model yuklu degil (ilk istek) | 12,4 sn | 12,8 sn |
      | Model yuklu, tek basina (5 kelime ortanca) | 0,29 sn | 0,73 sn |
      | Model yuklu, arkada 3 uzun is (1200 token) varken | 3,6 sn | 4,1 sn |

      LM Studio API'den yuklenen modeli **60 dk** bosta kalinca bosaltiyor
      (`lms ps`: TTL 60m, paralel 4); acik RELL'e ragmen model yuklu
      degildi. Sonuc: (1) ilk istekteki model yuklemesi tek basina ~12 sn;
      (2) arka plan isleri (isinma, ozet, satir arasi — Apple modeli yokken
      saglayiciya gider) kelime yanitini ~5 kat geciktiriyor. Apple modeli
      (v12 olcumu, ortanca 0,9 sn) bu islerin cogunu saglayicidan aliyor —
      yapilandirmalar arasindaki farki aciklar. Hipotez 3 ve 2 dogrulandi
- [x] **Ollama** — varsayilan `keep_alive` **5 dk** (`/api/ps`
      `expires_at`, yukleme + 5 dk), baglam 4096. Okurken iki bakis arasi
      5 dakikayi kolayca gecer: Ollama'da model LM Studio'dakinden (60 dk)
      cok daha sik bosaltilir ve ilk istek yeniden yukleme bekler. RELL
      Ollama'ya OpenAI uyumlu `/v1` yolundan gider; `keep_alive` bu yolda
      gonderilemiyor olabilir — S1'de yerel API ile dogrulanir. Ders: buyuk
      yerel modelle eszamanli uzun is olcumu gelistirme makinesini
      kilitledi; bundan sonra yalniz kucuk model, tek kisa istek, sert zaman
      siniri
- [x] **Ollama bulut modeli** (2026-10-14, Ollama 0.40.3,
      `gemma4:31b-cloud`, tek kisa istek x4): ilk kelime 0,3–1,0 sn, toplam
      0,6–1,2 sn; `reasoning_effort` olsun olmasin dusunme parcasi yok.
      Bulut modelinde yerel yukleme/GPU yarisi yok — yavaslik baska yerde
      aranir: Ollama surumu (dusunme ve `reasoning_effort` davranisi),
      Ollama hesabinin bulut kullanim sinirlari, ag. RELL tarafinda iki
      tutarsizlik: `…-cloud` modeller panelde yerel sayiliyor (2'lik kapi)
      ve arka plan isleri (Apple modeli yokken) buluta da gider, kotayi
      tuketir. S1'de ele alinir; tani raporu (S3) Ollama surumunu da yazar
- [x] **Uygulama ici taklit** — kullanicinin canli denemesiyle karsilandi
      (Apple modeli kapali: bulut modeli hizli, yerel 12B ~15 sn); ayrintili
      sure tablosu toplanmadi — S2'deki alt satir ve hiz testi bunu artik
      uygulama icinde gosteriyor
- [ ] Kapi: rakamlar yapilandirmalar arasindaki sure farkini aciklar.
      Aciklamazsa S1 kapsami rakamlara gore yeniden yazilir, sessizce
      kucultulmez

## Sprint 1 — "Daha hizli yapay zeka" (Must)

- [x] **Tek oncelik sirasi** — `LLMScheduler` (+ saf `LLMQueuePolicy`):
      bu Mac'teki modele (LM Studio / Ollama, localhost, `…-cloud` haric)
      giden her istek tek kuyrukta, ayni anda en fazla 2. Oncelik
      (`LLMPriority`): panel / Ask AI / araclar > hizli bakis, kayit anindaki
      CEFR > isinma, ozet, satir arasi, onceden yukleme > toplu doldurma.
      Karar 3: senin istegin beklerken ya da calisirken arka plan yeni
      istek baslatmaz, baslamisi kesilmez; ayrica **bir yer hep sana
      ayrilir** — arka plan en fazla limit−1 yer kullanir, tikladigin kelime
      bir uzun isin arkasinda beklemez. Kuyruk `RecordedLLMProvider`'in
      icinde: kayit + sira tek giris noktasi, bekleme suresi deftere girer.
      Eski `localRequestGate` (panel) ve hizli bakisin kapisi kalkti.
      Apple modeli ve bulut kuyruga girmez. Bulut modelleri artik yerel
      sayilmiyor (`LLMConfiguration.runsOnThisMac`, doldurmayla ortak kural)
- [x] **Eskiyen istegi birak** — kuyruk iptale duyarli: kelime degisince
      sirada bekleyen panel istegi aninda cikar, hic gonderilmez
      (defterde "hic gonderilmedi"); akmakta olan gorev iptaliyle kesilir
- [x] **Model sicak kalsin** — `LocalModelWarmth`: kitap acilinca model
      arka planda yuklenir (LM Studio: kuyruktan tek token; Ollama: kendi
      API'si `/api/generate`, istemsiz — yalniz yukler). Ollama'nin OpenAI
      uyumlu yolu `keep_alive` desteklemiyor (belgesi); bu yuzden her
      istekten sonra ayni cagriyla `keep_alive: 30m` — 5 dk yerine 30 dk.
      Model basina dakikada en fazla bir kez; test sunucusunda kapali
- [ ] **Yanit uzunluklari** — ertelendi: kaliteyi ayni tutarak kisaltmak
      ornek kelimelerle yan yana model calistirmayi gerektiriyor; yerel
      buyuk modelle yapilacak her olcum once onaylanir
- [x] Testler: `LLMSchedulerTests` (9) — oncelik + sira, arka planin
      beklemesi, ayrilmis yer, iptalde kuyruktan cikma, bekleme kaydi ve
      gonderilmeyen istek, yalniz bu Mac'teki model, Ollama istegi,
      dakikada bir. Iki kural mutasyonla dogrulandi (ayrilmis yer, arka
      planin beklemesi); bekleyen testler sureli — bozuk kuyruk testi
      kilitlemez. Tam paket 729 yesil
- [x] Canli dogrulama: S2/S3 canli turlarinda (kullanici) sorun yok;
      once/sonra sayisal olcum yapilmadi (agir yerel olcum kurali)

## Sprint 2 — "Neden yavas, gorunur" (Must, **maketle baslar**)

Maket onayi (2026-10-14): bes karar — sure basliktan alt satira; sirada
bekleme / model yukleme turuncu etiket + "Neden?"; Hiz bolumu AI
sekmesinde Apple bolumunun altinda; hiz testi yalniz dugmeyle, sirayla,
kisa istemle; son istekler metinsiz.

- [x] **Sonucun alt satiri** — `AnswerFooter` (saf) + `AnswerFooterView`:
      motor · model · ilk kelime · toplam; kayitli yanitta "Kayitli yanit ·
      motor · model". Etiket onceligi: >= 1 sn sirada bekleme > bu Mac'te
      onunde is yokken ilk kelime > 5 sn ("model yuklendi") > bulutta ilk
      kelime > 3 sn ("bulut gec basladi"); Apple'a hic. "Neden?" Ayarlar ▸
      Yapay Zeka ▸ Hiz'i acip bolume kaydirir. Tek satir, sabit yukseklik,
      kaydirma alaninin disinda (sutunu buyutmez — testli). Yanitin kaynagi
      `InspectorViewModel.answerSources` (istek kimligi ya da onbellek);
      basliktaki "1.4s" kalkti
- [x] **Ayarlar ▸ Yapay Zeka ▸ Hiz** — `SpeedSection` Apple bolumunun
      hemen altinda. Apple Intelligence kapaliysa sebep + "Sistem
      Ayarlari'ni Ac". **Hiz testi** (`SpeedTest`): her motora sabit bir
      cumleyle iki kisa istek, sirayla, arka plan onceliginde; yukleme
      (ilk − ikinci istek, >= 2 sn), ilk kelime, kelime/sn; Ollama'da model
      boyutu `/api/ps`. **Oneriler** (`SpeedAdvice`, saf): Apple kapali /
      kullanilamiyor, bu Mac'te yavas model (< 12 kelime/sn, boyut ve
      bellek), ilk istek modeli yukledi, bulut gec basladi, motor yanit
      vermedi; uyari yoksa "Her sey yolunda". **Son istekler**: son 8,
      metinsiz
- [x] Durum isigi penceresi: kuyruk (yalniz bu Mac'teki modelde) ve son
      istek; "Hiz…" dugmesi. `LLMScheduler` gozlenebilir
- [x] Testler: `SpeedVisibilityTests` (13) — alt satir ve etiket
      oncelikleri, basarisiz/bitmemis istekte satir yok, dar sutunda tek
      satir, yanitin kaynagi (istek / onbellek), yukleme ve kelime/sn
      hesabi, Ollama boyutu, oneriler. Mutasyon: satirin tek satir kalmasi
      ve "bekledi"nin onceligi. 62 yeni TR metin (xcstrings bos nesne
      bicimi korundu). Tam paket 742 yesil
- [x] Canli tur (kullanici) — tamam

## Sprint 3 — "Her Mac'te iyi" (Must, **maketle baslar**)

Maket onayi (2026-10-14): bes karar — Apple Intelligence adimi yalniz
gerektiginde; baglanti adiminda saglayici secimi + hiz + bellege gore
model onerisi; guncelleme denetimi gunde en fazla bir kez, varsayilan
acik, yerel derlemede yok; tani raporu once gosterilir; raporda metin,
anahtar ve uzak sunucu adresi yok.

- [x] **Acilis rehberi** — adimlar artik listeden: dil → **Apple
      Intelligence** (yalniz Mac calistirabiliyor ama kapali ya da model
      iniyorsa — `AppleOnDevice.couldBeReady`; Sistem Ayarlari'ni Ac +
      Yeniden Kontrol Et) → **yapay zekani bagla** (bugune kadar yalniz LM
      Studio anlatiliyordu: dort saglayici, sunucu, model, gerekirse API
      anahtari; test ilk kelime ve kelime/sn soyler, yavassa uyarir; bu
      Mac'teki model icin bellege gore boyut onerisi
      `SpeedAdvice.modelSizeHint`) → okuma turu. Adim icerigi kaydirilabilir,
      pencere 560×600 (gecici render ile kontrol edildi)
- [x] **Guncelleme denetimi** — `UpdateChecker`: GitHub releases/latest,
      acilistan 5 sn sonra, gunde en fazla bir kez; taslak ve on surum
      sayilmaz; yerel derleme (1.0) ve test sunucusu hic denetlemez. Ana
      ekran seridi (`UpdateNoticeBanner`, surum basina gizlenir), Yardim ▸
      Guncellemeleri Denetle… (notlarla), Ayarlar ▸ Veri ▸ Guncellemeler
      (anahtar + Simdi Denetle), gizlilik tablosunda satir. Indir tarayicida
      surum sayfasini acar; RELL hicbir sey indirmez ya da kurmaz
- [x] **Tani raporu** — `DiagnosticReport` (saf metin + toplama): surum,
      macOS, cip, bellek, Apple Intelligence, saglayici + model + bu Mac /
      uzak, yalniz yerel sunucu adresi, Ollama surumu (`/api/version`),
      zaman asimi, son hiz testi, son 20 istek. Yardim ▸ Tani Raporu… ve
      Hiz bolumunde dugme; once tamami gosterilir, Kopyala panoya koyar
- [x] Yan duzeltme: gizlilik tablosu Ollama'nin bulut modellerini "Bu Mac"
      sayiyordu → "Ollama bulutu (yerel sunucu uzerinden)"
- [x] Testler: `EveryMacTests` (10) — surum karsilastirma, yerel derleme,
      gunde bir, GitHub yaniti, on surum/taslak, rapor icerigi, uzak adresin
      girmemesi (mutasyonla dogrulandi), bellek onerisi. 51 yeni TR metin.
      Tam paket 754 yesil
- [x] Canli tur (kullanici) — tamam

## Sprint 4 — "Kapanis"

- [x] Kapanis (Must): tam test (754 yesil, 2 makineye bagli atlanan),
      soguk acilis (ayni oturumda donusumlu, 1.46.1 worktree'si ile, Debug
      UI testi, 5 olcum): 1.46.1 ortanca ~675/593 ms, simdi ~630/601 ms —
      fark olcum yayilimi icinde. Canli turlar (S1–S3, kullanici).
      CHANGELOG 1.47.0 + Yenilikler 1.47 (5 madde, TR). Ikinci bir Mac'te
      once/sonra dogrulama yayindan sonra (yayin derlemesiyle)
- [x] **1.47.0** yayinlandi (2026-10-14; Release is akisi yesil, DMG + zip, Latest; GitHub releases/latest 1.47.0 donduruyor)

---

## Yayin sonrasi — 1.47.1 (2026-10-14)

Ikinci bir Mac'ten gelen tani raporu yavasligin Ollama'da degil, **Apple'in
cihaz ici modelinde** oldugunu gosterdi: isinma (uzun is) + kelime + hizli
bakis ayni anda Apple'a gitmis, ilk kelime ~107 sn, sonra 13–27 sn. Olcum
(gelistirme Mac'i, kucuk istek): Apple modeli istekleri **tek tek** isliyor —
kisa istek tek basina 3,6 sn, uzun bir isin yaninda 9,1 sn (uzun is bitince).
S1'de Apple'in paralel calistigi varsayimi yanlisti.

- [x] Apple icin ayri kuyruk (`LLMScheduler.apple`, tek yer); calisan arka
      plan isi (yalniz tek seferde yanit alan `chat`) senin istegin icin
      durur ve sonra bastan baslar (kullanici karari). Yerel sunucularda
      baslamis is kesilmez. Saf `LLMQueuePolicy.toPreempt`
- [x] Kitap acilinca `LanguageModelSession.prewarm()`; Apple kayitlari "bu
      Mac" sayilir (alt satirda "model yuklendi"); hiz testinde Apple icin
      yukleme ve "Apple'in modeli bu Mac'te su an yavas" onerisi
- [x] Kart dili: acilis rehberinde "Kisa anlamlar" secimi, varsayilan ana
      dil (kullanici karari); mevcut ayarlar degismez
- [x] Testler: `AppleQueueTests` (5) — politika, isinmanin kelime icin
      durup yeniden baslamasi, yerel sunucuda durmamasi, Apple seridi, Apple
      onerisi. Mutasyon: durdurma ve yeniden baslatma. Tam paket 759 yesil

## Genel dogrulama (her sprint sonu)

Tam test paketi (CI komutuyla birebir, `make ci-test`), regresyon testleri
mutasyonla dogrulanir, push sonrasi Test ve Build is akislari yesil,
canli tur (RELL acikken ikinci kopya calistirilmaz),
xcstrings TR tamamlama.
