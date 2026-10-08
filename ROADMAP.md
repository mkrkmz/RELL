# RELL Roadmap v15 — Kaydettigin Kelimeyi Ogren (S0 + 4 sprint)

Olusturulma: 2026-10-08 (v1.43.0 sonrasi). Kullanici karari: okuma ve kelime
kaydetme deneyimi yeterince iyilesti; **tek odak kaydedilen kelimelerin
calisilmasi, ogrenilmesi ve tekrar edilmesi**. Taze fikir katalogundan
yalniz uc fikir alindi: A1 (i+1 cumleler — "kullanisli olursa"), C2 (Kindle
kelime defteri; kullanicinin Kindle'i var), D1 (Kisayollar — Apple
Developer hesabi olmadan calisirsa). Tek surum: **1.44.0**. v14 roadmap'i:
`docs/archive/ROADMAP-v14.md`.

v14 kapandi: S0–S4 tek surum olarak **v1.43.0** (2026-10-02) — sakin baglam
seridi + "Bu bolum" hapi, etiketli secim cubugu + tek secim menusu, metin
ustunde opak okuma yuzeyi, Zen arac cubugunda, kelime-once Inspector + cumle
araclari, Bugun ekrani + kitaplik raflari/listesi, sade kelime listesi,
Yenilikler, 6 sekmeli Ayarlar, okuma dongusu turu, VoiceOver taramasi,
tutarli Turkce ("Inspector", "tekrar bekleyen", "sen"). 642 test. Ders: CI
Test is akisi 9 commit kirmizi kaldi — her push'tan sonra kontrol edilir.

## Durum (2026-10-08, kullanicinin verisi, salt okunur)

| Olcu | Deger |
|---|---|
| Kayitli kelime | 59 |
| Calisilan dilde tanimi olan (`definitionEN`) | 21 |
| Turkce anlami olan (`meaningTR`) | 18 |
| Hic aciklamasi olmayan | **26 (%44)** |
| CEFR seviyesi olan | 58 |
| Mod "word" / "Word" | 21 / 38 (tutarsiz) |

- Kartin arka yuzu yalniz daha once calistirilmis modulleri gosterir
  (`QuizView.savedModules`); hizli kaydedilen kelimede bos gelir. Coktan
  secmeli ve eslestirme tanim ister, bu kelimeleri atlar.
- Tekrar uc yerde: kenar cubugu sekmesi (`WordsView`), 460×620 "Vocabulary
  Review" penceresi, okuyucu sheet'i. Odakli bir calisma alani yok.
- Apple sozlugu (`SystemDictionary`, `DCSCopyTextDefinition`) bu Mac'te
  Ingilizce–Turkce sozlukten cevap veriyor: Turkce anlam + IPA cevrimdisi
  doldurulabilir; calisilan dilde tanim icin buyuk olasilikla model gerekir.

## Teknik cerceve (tum sprintler icin gecerli)

v14 cercevesi aynen devralinir: sifir dis bagimlilik, macOS 15 hedefi, tam
test paketi, async testler, makineye bagli test `XCTSkip`, `Text(String)`
katalogu atlar, DS token'lari, bundle id/sandbox'a dokunulmaz; **once maket**
(her UI sprinti HTML maketle baslar, onaysiz kod yok); sutunlarda yerlesim
kurali + "pencereyi buyutmez" testleri; metin ustunde `.dsReadingOverlay()`;
erisilebilirlik taramasi (`AccessibilityAuditTests`); her push'tan sonra
`gh run list` ile Test is akisi; her sprint sonu canli tur. Eklenenler:

- **Doldurma zamanlamaya dokunmaz.** Aciklama doldurmak FSRS'e yazmaz;
  yalniz `llmOutputs` (ve gerekirse yeni alanlar) doldurulur, var olanin
  uzerine yazilmaz, kaynak isaretlenir.
- **Maliyet kullanicinin kontrolunde** (karar 1): Apple sozlugu, cihaz ici
  model ve yerel sunucu (LM Studio/Ollama) kendiliginden calisabilir; bulut
  saglayici (OpenAI/Anthropic) yalniz acik "Eksikleri doldur" eylemiyle.
- Yapay zekaya giden her yeni istek Gizlilik ozetinde (`PrivacySummarySection`)
  listelenir.
- Kalici veri bicimi degisirse eski dosya kayipsiz okunur (decode testleri);
  tek seferlik veri duzeltmeleri yedek alindiktan sonra yapilir.

**Bilincli olarak v15 disinda:** okuma tarafindaki yeni ozellikler (fikir
havuzu ve v15 katalogundaki diger fikirler), iOS, Apple-Developer-kilitli
kalemler (notarization, widget, App Group, CloudKit).

---

## Sprint 0 — "Zemin ve olcumler" (Must, kisa)

Amac: kod yazmadan once belirsizlikleri kullanicinin verisiyle kapatmak.

- [ ] **Doldurma kaynaklari olcumu** — kullanicinin 59 kelimesinde: Apple
      sozlugu kacinin Turkce anlamini ve IPA'sini veriyor, ne hizda; cihaz
      ici model ve yapilandirilmis saglayici tanimlari ne kalitede, ne hizda
- [ ] **Kindle vocab.db** — Kindle USB ile bagliyken
      `system/vocabulary/vocab.db` yapisi (salt okunur)
- [ ] **Kisayollar denemesi** — App Intents, Apple Developer imzasi olmadan
      derlenen uygulamada Kisayollar'da gorunuyor mu; gorunmuyorsa D1 girmez
- [ ] **Temizlik** — "word"/"Word" mod tutarsizliginin kaynagi duzeltilir,
      kayitli veri bir kez normalize edilir
- [ ] v14 takibi: soguk acilis ortancasi 549 → 576 ms — nedenine bakis

## Sprint 1 — "Kelimeleri tamamla" (Must)

Amac: her kayitli kelimenin calisilabilir bir karti olsun — tanim, anlam,
telaffuz, ornek cumle. **Maketle baslar.**

- [ ] **Doldurma servisi** — alan alan en ucuz guvenilir kaynaktan: Apple
      sozlugu → cihaz ici model → yapay zeka saglayicisi. Var olanin uzerine
      yazmaz, kaynagi isaretler; CEFR tahminindeki toplu is deseni (ilerleme,
      iptal)
- [ ] **Kelime listesinde "Eksikleri doldur"** — eksik sayisi, alan secimi,
      ilerleme, iptal; kelime sayfasinda tek kelime icin ayni eylem
- [ ] **Bos kart yuzu kalmasin** — aciklama yoksa kartin arkasi Apple
      sozlugu sonucunu gosterir ve "Doldur" sunar; coktan secmeli/eslestirme
      doldurulmus aciklamalari kullanir
- [ ] **Kaydederken doldur** (Should) — karar 1'deki kaynak kuraliyla
- [ ] Testler: kaynak sirasi, uzerine yazmama, iptal, eski veri decode

## Sprint 2 — "Calisma odasi" (Must)

Amac: kelime calismasi ayri, odakli ve tam ekran bir yere tasinsin
(karar 2: ayri pencere). **Maketle baslar.**

- [ ] **Calisma penceresi** — "Vocabulary Review" penceresinin yerini alir
      (ayni `id: "review"`, eski yollar calisir): buyuk acilir, tam ekrana
      gecer, Esc oturumu bitirir; ana ekran, ⌘K ve Git menusu buraya acar
- [ ] **Oturum kurulumu ve sonu** — kac kelime, kaynak (tum / bu kitap /
      deste / zorlu), yeni + tekrar dengesi; sonda dogru/yanlis, bugun
      oturanlar, yarin bekleyenler
- [ ] **Buyuk kart duzeni** — bes mod genis alanda; kelime buyuk, kitaptaki
      cumlesi altinda, ses; klavye (Space cevir, 1–4 puanla, ←/→)
- [ ] **Kenar cubugundaki tekrar** (Should, karar 3) — hizli tekrar olarak
      kalir + "Tam ekranda calis"
- [ ] Testler: oturum secimi, klavye eylemleri, pencere boyutlari

## Sprint 3 — "Daha iyi ogrenme dongusu" (Must)

Amac: tekrar, kelimenin asamasina gore dogru alistirmayi secsin.
**Maketle baslar.**

- [ ] **Yeni kelime tanitimi** — ilk kez gelen kelime once tanitilir (anlam,
      cumle, ses), sonra ayni oturumda ilk kez sorulur
- [ ] **Asamaya gore karisik mod** — yeni: tanima (coktan secmeli);
      ogreniliyor: bosluk doldurma ve yazma; oturmus: dinleyip yazma; tek mod
      secimi korunur
- [ ] **Kitaplarindan baglam (A1)** (Should) — kelime icin okunan
      kitaplardan geri kalanini bildigin (i+1) cumleler; bosluk doldurma her
      tekrarda farkli cumle
- [ ] **Zorlu kelimeler** (Should) — sik unutulanlar isaretlenir, ayri
      oturum, akilda tutma ipucu otomatik doldurulur

## Sprint 4 — "Kelime getiren kapilar ve kapanis"

- [ ] **Kindle kelime defteri** (Must) — vocab.db sec ya da bagli Kindle'i
      bul; kelimeler, Kindle cumleleri ve kitap adlariyla gelir; kopyalar
      atlanir; S1 doldurmasi eksikleri tamamlar
- [ ] **Kisayollar** (Should, S0 olumluysa) — "Kelime kaydet", "Calismaya
      basla", "Kac kelime bekliyor?"
- [ ] Kapanis (Must): tam test, performans karsilastirmasi, canli tur,
      CHANGELOG, **1.44.0** (tag oncesi kullaniciya sorulur)

---

## Kararlar (2026-10-08, kullanici onayi)

1. Kaydederken doldurma: Apple sozlugu + cihaz ici model (+ yerel sunucu)
   kendiliginden; bulut saglayici yalniz "Eksikleri doldur" ile.
2. Tam ekran: ayri Calisma penceresi.
3. Kenar cubugundaki Tekrar sekmesi kalir + "Tam ekranda calis".
4. Kindle: S0'da kullanici cihazini baglar; dosya yalniz okunur.

## Fikir havuzu (v15'e alinmadi)

v14 havuzu (golgeleme, cumle kaydetme, kelime haritasi, karakter rehberi,
okuma cetveli, PDF bolum hazirligi, anlama kontrolu, kenar notlari, seviye
testi) + v15 katalogundan: baglamdan tahmin, dikte, hata defteri, bolum
sohbeti, okuma gunlugu, altyazi okuyucu, CSV/Anki listesi, kitap onerisi,
Servisler menusu, haftalik ozet, okuma hizi.

## Genel dogrulama (her sprint sonu)

- Tam birim test paketi + "pencereyi buyutmez" testleri; performans tabani
  kotulesmez
- `main` push, `gh run list` ile Test **ve** Build is akisi yesil
- Maketle karsilastirmali ekran gorselleri (acik/koyu)
- Kullanici canli turu (kontrol listesiyle)
- `Localizable.xcstrings`: yeni metinler TR ile ("sen" hitabi)
