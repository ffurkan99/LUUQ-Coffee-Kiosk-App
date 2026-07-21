# Hesap Kimde fizik-öncelikli kazanan seçimi — tasarım (21 Temmuz 2026)

Bu belge, Hesap Kimde / Who Pays oyununda kazanan seçim mekanizmasının tersine
çevrilmesi için kullanıcı onaylı tasarımdır. Önceki tasarımın
(`2026-07-20-hesap-kimde-mechanics-design.md`) "Değişmeyenler" bölümündeki
"kazanan dialogda Random.nextInt ile seçilir; fizik yalnızca sunumdur" ilkesini
**bilinçli olarak iptal eder** ve yerine tam tersini koyar.

## Sorun

Kazanan, fizik başlamadan önce `Random.nextInt(personCount)` ile seçiliyor
(`main.dart` `_spin()`); simülasyon bu önceden seçilmiş topu koreografiyle
ağza taşıyor. Koreografi ne kadar cilalanırsa cilalansın kullanıcı gözünde
sonuç aynı: "deliğe en yakın top değil, rastgele seçilmiş bir top düşüyor."
Kullanıcının istediği mekanizma: **gerçekten deliğe giren top kazansın.**

## Kullanıcı kararları

- Yaklaşım A onaylandı: **fizik kazananı belirler**; dialog sonucu animasyon
  bitiminde simülasyondan okur. Ekranda düşen top = ilan edilen kazanan;
  ayrışma yapısal olarak imkânsız.
- **Nötr çekim garantisi** onaylandı: kapak açıldığında ağzın üstünde top
  yoksa, TÜM toplara eşit uygulanan ve zamanla artan bir taban
  eğimi/drenaj kuvveti yığını ağza kaydırır; yine deliğe en yakın top düşer.
  Çekiliş süresi sabit kalır.
- Elenenler: (B) gizli ön-koşum — görsel koşum kare düşmelerinde
  sapabileceği için ilan edilen ile düşen top ayrışabilir; (C) mevcut
  koreografiyi güçlendirmek — kullanıcı tarafından reddedildi.

## Değişmeyenler

- Faz süreleri ve toplam süreler: spinUp 0.18 / mixing 2.05 / settling 2.55 /
  capture 3.00 / dropping 3.32 / toplam 3.40 sn; redraw intake +0.45 = 3.85 sn.
- Sabit adım 1/120 sn, kare başına en çok 8 adım, hız limiti 760 px/s,
  `mixingDragRate = 0.22`, `collisionPasses = 8`, `wallRestitution = 0.93`.
- Sinematik hız tavanları ve iniş yastığı (postMixTerminalFallSpeed,
  plowKickCap, seatCushion) aynen kalır; yakalanan topa uygulanırlar.
- Kazanan-farkındalıklı kapak kapanışı (`_gateCloseBeganAt`,
  `gateSweepClearY`) aynen kalır; referansı `winnerIndex` yerine
  `capturedBallIndex` olur.
- Ses mekanizması, görünüm katmanı mimarisi, "Tekrar Çek" sürekliliği
  (exportState/intake) aynen kalır.
- Sonuç kartının animasyon bitiminde gösterilmesi aynen kalır.

## Yeni model

### Simülasyon (`lib/src/who_pays/lottery_simulation.dart`)

1. **API tersine döner.** Constructor'dan `winnerIndex` kalkar. Yerine çıktı:
   `int? capturedBallIndex` — iki yoldan atanır: (a) doğal yol — bir topun
   merkezi ağızdan tüp girişine (`tubeEntryY`) geçtiği an; (b) son çare —
   garanti penceresi dolduğunda ağza o anda en yakın top seçilir ve içeri
   alınır. Bir kez atanınca değişmez. Çekiliş tamamlandığında
   (`phase == seated`) null olması yapısal olarak imkânsızdır.

2. **Total tarafsızlık.** `capturedBallIndex` atanana kadar hiçbir topa
   endekse-özel kuvvet, muafiyet veya istisna uygulanmaz. Silinecekler:
   kazanan-özel duvar-sarmal emiş (radial yay + teğetsel süpürme), kazanan
   rotor muafiyeti, kazanan çarpışma/keepout muafiyetleri, guarantee-window
   düz yayı (kazanan-hedefli hali). `winnerGuideApplications` sayacı
   "yakalama öncesi endekse-özel uygulama" sayacına dönüşür ve testle 0'a
   sabitlenir.

3. **Yakalama akışı.**
   - settling (2.05–2.55): toplar KAPALI kapağın üstüne yığılır. Geçen tur
     eklenen ağız-üstü park yasağı (keepout ridge) yakalama öncesi dönemden
     kaldırılır — ağzın üstünde top olması artık istenen durumdur.
   - capture (2.55–3.00): kapak 2.55–2.70'te açılır. Ağız bölgesindeki top
     yerçekimiyle kendiliğinden düşer. Ağız boşsa nötr drenaj devreye girer:
     tüm toplara eşit, ağza doğru yönlü, zamanla rampalanan hafif kuvvet;
     en yakın top doğal olarak girer.
   - Garanti: kalan sürede giren olmadıysa nötr drenaj son pencerede
     güçlenir; mutlak son çare olarak ağza **o anda en yakın** top
     `capturedBallIndex` olarak atanır ve içeri alınır — kural yine "en
     yakın kazanır", endeks-önseli yoktur. Bu atamadan itibaren hedefli
     kuvvet yalnızca yakalanan topa uygulanabilir (tarafsızlık sözleşmesi
     "atama öncesi" dönemini kapsar).
   - Top `tubeEntryY`'yi geçince: `capturedBallIndex` atanır; ağız diğer
     toplara kapanır (keepout artık "ikinci top sızmasın" görevinde);
     kapak topun arkasından kapanır (mevcut winner-aware kapanış,
     capturedBallIndex ile); tüp inişi + yuva yastığı mevcut haliyle.
   - Erken düşme normaldir: top ~2.6 sn'de bile düşebilir; erken oturur,
     kalan sürede makine sakinleşir. Geç-varış kuyruğunun (%15) bu modelde
     büyük ölçüde kaybolması beklenir; ölçülecek.

4. **Tek top girer.** Ağız açıklığı tek top genişliğindedir;
   `capturedBallIndex` atanır atanmaz diğer toplar için ağız kapanır.
   Testle doğrulanır: hiçbir çekilişte ikinci bir top `tubeEntryY`'yi
   geçemez.

5. **exportState / intake.** `seatedBallIndex = capturedBallIndex`. Redraw
   intake koreografisi (yuvadaki topun fanusa geri emilmesi) aynen çalışır.

6. **Reduced motion.** `advanceReducedMotion` ilk çağrıda aynı seed ve aynı
   başlangıç durumuyla **iç gölge kopya** kurar, onu sona kadar koşar
   (deterministik, ≤ ~460 sabit adım, < 5 ms) ve `capturedBallIndex`'i
   gölgeden okur. Ana örneğin `balls` listesi mutasyona uğramaz; crossfade
   sunumu ve exportState'in kuruluş-anı dizilimi ihraç etmesi (redraw
   sürekliliği) aynen korunur. Gölge kopya burada güvenlidir çünkü reduced
   motion fizik koşumu render etmez — ayrışabileceği bir görsel koşum
   yoktur. Test: aynı seed'de gölge yol ile normal koşum aynı kazananı
   verir.

### main.dart bağlantısı

- `_spin()` kazanan seçmez; `_winnerIndex = _rand.nextInt(...)` satırı
  silinir.
- `_LotteryMachine.winnerIndex` prop'u kalkar. `onComplete` kazananı taşır:
  `ValueChanged<int> onComplete` — `_LotteryMachineState` tamamlanma anında
  `_simulation.capturedBallIndex!` değerini yukarı verir; dialog
  `_result = winner + 1` yapar. Erişilebilirlik metinleri (`Semantics`)
  kazananı aynı kaynaktan okur.
- Kişi sayısı değişimi, sonuç sıfırlama, renk seçimi akışları değişmez.

### Adalet (fairness)

- Kazanan artık `seed`in (her çekilişte `Random().nextInt(0x7fffffff)`) ve
  kaotik karışımın deterministik fonksiyonudur. Başlangıç dizilimi seed'le
  rastgele + ~2 sn kaotik karışım → pratik tekdüzelik beklenir.
- Ölçüm zorunludur: enstrümante tarama, kişi sayısı başına ≥ 600 çekiliş
  ({2,3,4,6}); sabit deterministik seed listesiyle her endeksin kazanma
  payı 1/n'in 0.55–1.6 katı bandında olmalı (gerçek tekdüzelikte ~4σ —
  flaky değil). Bant aşılırsa taze çekilişlerde başlangıç pozisyonu ataması
  seed'le karıştırılır (kesin 1/n) ve tarama tekrarlanır.
- Redraw'da pozisyonlar fiziksel süreklilik olduğundan karışım + taze seed'e
  güvenilir (gerçek makine modeli); redraw dağılımı da taramada ölçülür.

### Testler

- Dönüşen testler: 20-vakalık "verilen kazanan yuvaya oturur" süpürmesi →
  "her seed'de tam bir top yakalanır, `capturedBallIndex` fiilen yuvaya
  oturan toptur, oturma pozisyonu Offset(0, winnerSeatY) ± tolerans".
- Yeni testler: total tarafsızlık (yakalama öncesi endekse-özel uygulama
  sayısı 0), tek-top-girer, "kapak kazananı kesmez" (capturedIndex ile),
  ağız-boş senaryoda nötr drenajın en yakın topu düşürdüğü, adalet dağılımı
  (sabit seed listesiyle deterministik, gevşek bant — flaky olmayacak).
- Korunup uyarlananlar: faz/no-teleport/duvar-sadakat (duvar-sadakat testi
  koreografi silindiği için kapsam değiştirir: yakalanan topun ağza girişten
  yuvaya kadar tüp içinde kalması), gate-ridge kalıcılık testi tersine
  döner (yakalama SONRASI ikinci top ağza park edemez).
- Golden'lar yeniden üretilir (kazanan artık seed'in fonksiyonu olduğundan
  mevcut 4 golden'ın sahnesi değişir).

## Riskler ve karşılıklar

| Risk | Karşılık |
| --- | --- |
| İki topun ağza aynı anda sıkışması | Tek top genişliğinde giriş + capturedIndex atanınca keepout; kalıcı test. |
| Hiç top girmemesi | Rampalanan nötr drenaj + son çare "en yakın top" kuralı; kalıcı test (`capturedBallIndex` seated fazında asla null olamaz). |
| Endeks yanlılığı (adalet) | ≥ 600 çekilişlik ölçüm; gerekirse seed'li dizilim karıştırma. |
| Reduced-motion iç koşumu ile normal koşumun ayrışması | Aynı kod yolu, aynı sabit adım; test: aynı seed'de iki yol aynı kazananı verir. |
| Erken düşüşte kapağın topu kesmesi | Mevcut winner-aware kapanış capturedIndex ile aynen; 12-senaryo testi korunur. |

---

## Addendum (2026-07-22): Adalet taraması sonuçları

Enstrümante tarama (600 taze çekiliş × {2,3,4,6} kişi + 300 redraw × {2,6}):

- Taze: n=2 [290,310] · n=3 [189,210,201] · n=4 [158,151,141,150] ·
  n=6 [94,108,113,107,85,93]. Tüm paylar 1/n'in 0.85-1.13 katı — 0.55-1.6
  bandının rahat içinde. **Dizilim karıştırma gerekmedi.**
- Redraw: n=2 [146,154] · n=6 [52,54,53,49,45,47] — dengeli.
- Kalıcı gevşek test eklendi (240 seed × {2,6}, bant 0.45-1.75).
- Yan bulgu: son-çare bölgesine (atama ≥ 2.895 sn) sarkan çekiliş oranı
  kişi sayısıyla ters orantılı: n=2 %46, n=3 %29, n=4 %18, n=6 %6 (redraw
  n=2 %81). Az topta çökme yetersiz — kapak açıldığında toplar hâlâ yüksekte.
  Kalite geçişinin (Task 4) ana hedefi.
