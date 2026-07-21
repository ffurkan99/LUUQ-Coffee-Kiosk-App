# Hesap Kimde mekanik yenileme — tasarım (20 Temmuz 2026)

Bu belge, Hesap Kimde / Who Pays oyununun (`lib/src/who_pays/`) mekanik sorunlarının
düzeltilmesi ve koreografinin yenilenmesi için kullanıcı onaylı tasarımdır.

## Tespit edilen sorunlar

1. **Süre uyuşmazlığı**: `AnimationController` 4000 ms, simülasyon
   `durationMilliseconds = 3400`. Tick eşlemesi 3.4 sn'lik fiziği 4.0 sn'ye
   yaydığı için tüm animasyon %15 ağır çekimde oynuyor.
2. **Çıkış ağzı teleportu**: Tüp duvarı sert `|x| ≤ 3.5` clamp'i; kazanan top
   kilitlenemeden serbest kalırsa tek karede 20+ px yana ışınlanabiliyor.
   Release sonrası `-x·260` merkezleme yayı clamp'siz.
3. **Kazananın erken belli olması**: Settling fazında kazanan top yerçekiminin
   ~10 katı guide kuvvetiyle görünür şekilde alt-merkeze çekilip kapak
   açılmadan ~0.7 sn önce belli oluyor.
4. **"Tekrar Çek" ışınlanması**: Yeni çekilişte tüm toplar tek karede rastgele
   dizilime atlıyor; süreklilik yok.
5. **Kapak açık kalıyor**: Sonuç sonrası `gateProgress = 1` sonsuza dek;
   kaybeden toplar açık deliğin üstünde görünmez zeminde duruyor.
6. **Resume donması**: Arka plandan dönüşte catch-up sınırı nedeniyle kaybeden
   toplar havada donmuş kalıyor (kazanan için yuva garantisi zaten var).
7. **Görsel hizalar**: Kazanan top yuvada cam tabandan 4 px yukarıda; kapak
   42 px genişliğinde ama tüp 50 px; menteşe (y=128) omuz noktasının
   (y≈132.7) üstünde.

## Kullanıcı kararları

- Kazanan **son anda yakalanır**: karıştırma ve çökme sırasında hiçbir top
  ayırt edilmez; emilme kapak açılırken olur.
- **Kapak kapanır + geri emilme sürekliliği**: sonuç sonrası kapak kapanır;
  "Tekrar Çek"te yuvadaki top tüpten fanusa geri emilir, karıştırma mevcut
  pozisyonlardan başlar.
- Görsel hizalar kapsam **içinde**.
- Kapsam **dışı**: renk kartına dokununca sonucun sıfırlanması davranışı,
  telefon boyutunda dialog taşması, ses tasarımı değişikliği.
- Yaklaşım: mevcut `WhoPaysLotterySimulation` sınıfının evrimleştirilmesi
  (modüler yeniden yazım yok). Stabilite önceliklidir; süre kısıtı yok.

## Değişmeyenler

- Kazanan seçimi dialogda `Random.nextInt(personCount)` ile kalır; fizik
  yalnızca sunumdur, sonucu asla etkilemez.
- Sabit adım 1/120 sn, kare başına en çok 8 adım, hız limiti 760 px/s.
- Ses mekanizması (çarpma tick'i eşik + cooldown, sonuç sesi) aynen kalır.
- Görünüm katmanı mimarisi (üç painter + RepaintBoundary) aynen kalır.

## Koreografi

İki başlangıç modu vardır:

**İdle başlangıç** (ilk açılış, kişi sayısı değişimi sonrası) — toplam 3400 ms:

| Faz | Aralık (s) | Davranış |
| --- | --- | --- |
| spinUp | 0.00–0.18 | Rotor smoothstep ile tam hıza çıkar (mevcut). |
| mixing | 0.18–2.05 | Tam hız karıştırma. Kazanana özel kuvvet yok. |
| settling | 2.05–2.55 | Rotor smoothstep ile durur; drag 0.22 → 2.0. Tüm toplar tabana çöker; kazanan ayırt edilemez. |
| capture | 2.55–3.00 | Kapak 2.55–2.70'te açılır. Kazanana ağız hedefine emilme yayı; kaybedenlere ağız çevresinde hafif dışa hava yastığı. |
| dropping | 3.00–3.32 | Kazanan huniden tüpe girer, chuteGravity ile yuvaya düşer. Kapak 3.10–3.30'da kapanır. |
| seated | 3.32–3.40 | Her şey durgun; kapak kapalı; kazanan yuvada. |

**Devam başlangıcı** (sonuç ekrandayken "Tekrar Çek") — toplam 3850 ms:

| Faz | Aralık (s) | Davranış |
| --- | --- | --- |
| intake | 0.00–0.45 | Kapak 0.00–0.12'de açılır; yuvadaki top 0.06–0.33 arası tüpten yukarı emilir (dikey ivme −3400 px/s² + sönümleme), dy < 95 olunca fanusta normal fiziğe geçer; kapak 0.34–0.45'te kapanır (top ağzı geçtikten sonra). Diğer toplar önceki dinlenme pozisyonlarında. |
| sonrası | 0.45+ | İdle başlangıçtaki tüm fazlar 0.45 sn kaydırılarak aynen oynar. |

Faz sınırları simülasyonda tek bir `phaseShift` (idle: 0, devam: 0.45) ile
hesaplanır; statik sabitler yerine örnek (instance) üyeleri kullanılır.

## Fizik değişiklikleri

- **Kazanan tarafsızlığı**: capture başlangıcından önce kazanana hiçbir özel
  kuvvet uygulanmaz. Mevcut staging/latch mekanizması (winnerStagingPosition,
  `_winnerLatched`, settling guide yayı) tamamen kaldırılır.
- **Settling drag**: seçim fazındaki 5.2 değeri kalkar; settling boyunca drag
  2.0 (mixing'de 0.22 kalır). Duvar/top restitüsyonlarının settling'deki
  düşük değerleri (0.12 / 0.16) korunur.
- **Emilme (capture)**: hedef nokta ağız merkezi (0, 126). Kazanan ivmesi
  `spring = (hedef − pozisyon)·60 − hız·14`, büyüklüğü capture penceresi
  boyunca 0 → 3200 lineer ramp ile clamp'lenir. Pencerenin son 100 ms'inde
  (t ≥ 2.90) clamp 5200'e çıkar (garanti kuvveti).
- **Hava yastığı**: yalnızca capture fazında ve kapak açıkken
  (gateProgress > 0.5) kaybedenlere (0, 126) merkezli 55 px yarıçaplı bölge
  içinde dışa radyal, en fazla 900 px/s² kuvvet. Ağzı boşaltır, determinizmi
  maskeler. Intake fazında uygulanmaz.
- **Huni**: kazanan için y ∈ [100, 133] bölgesinde izin verilen merkez yarı
  genişliği 38 px → 4 px lineer daralır; y > 133 (tüp) içinde 4 px. İhlalde
  pozisyon duvara projeksiyon + hız yansıması (restitüsyon 0.12). Adım başı
  projeksiyon küçük olduğundan teleport oluşamaz. Mevcut sert
  `chuteCenterHalfWidth = 3.5` clamp'i ve release sonrası clamp'siz `-x·260`
  yayı kaldırılır.
- **Yuva**: `winnerSeatY = 209` (top, alt kapak iç yüzeyine teğet: kap merkezi
  +205, yarıçap 25, top yarıçapı 21 → 205 + 4).
- **İnce ayar payı**: kuvvet sabitleri (yay katsayıları, ramp değerleri,
  hava yastığı büyüklüğü) seed taramalı testleri geçecek şekilde
  uygulama sırasında ayarlanabilir; faz sınırları ve süreler sabittir.
- **Kapak fiziği**: kapak kapalıyken kaybedenler için mevcut dairesel sınır
  (r=107) yeterlidir (top kenarı 128, kapak kirişi 132.7'nin üstünde);
  ek zemin fiziği gerekmez.

## Süreklilik API'si

- `WhoPaysLotterySimulation` yapıcısına opsiyonel `initialState` parametresi:
  `WhoPaysInitialState(chamberPositions: List<Offset>, seatedBallIndex: int?)`.
  `seatedBallIndex != null` ise o top (0, 209)'da başlar ve intake fazı
  eklenir; `chamberPositions` diğer topların başlangıç pozisyonlarıdır.
- `simulation.exportState()` mevcut top pozisyonlarını ve (seated fazındaysa)
  yuvadaki topun indeksini döndürür.
- `durationMilliseconds` artık örnek üyesidir (idle 3400 / devam 3850);
  eski statik sabit idle değeri olarak kalabilir ama controller örnek
  üyesini okur.
- `main.dart` bağlantısı: `_LotteryMachineState.didUpdateWidget` yeni çekiliş
  başlarken önceki simülasyon `seated` fazındaysa `exportState()` sonucunu
  `initialState` olarak geçirir; controller süresi
  `Duration(milliseconds: _simulation.durationMilliseconds)` yapılır
  (reduced-motion'da 180 ms geçersiz kılması korunur).
- İlk açılış ve kişi sayısı değişiminde bugünkü deterministik seed'li temiz
  rastgele yerleşim korunur (golden testler için).

## Resume garantisi

`advanceTo(target)` içinde `target ≥ duration` olduğunda:

- Kazanan (0, 209)'a oturtulur, hızı sıfırlanır (mevcut garanti).
- **Kaybedenler** taban yayı dinlenme slotlarına yerleştirilir: r = 107
  çemberi üzerinde π/2 merkezli, 0.42 rad aralıklı slotlar (0.42 rad ≈ 45 px
  yay > 42 px top çapı, çakışma imkânsız); toplar mevcut açısal
  pozisyonlarına en yakın boş slota atanır (deterministik: indeks sırasıyla).
- `gateProgress = 0`, `rotorSpeed = 0`.

Sonuç: arka plandan dönüşte hiçbir top havada kalmaz.

## Kapak semantiği

`gateProgress`: 0 = kapalı, 1 = açık (mevcutla aynı yön). Yeni zaman
çizelgesinde açılış ve kapanış smoothstep ile animasyonlanır (yukarıdaki
tablolar). Görselde kapak tüpün tam genişliğini (50 px) kapatır; menteşe omuz
noktasına (−25, +132.7, merkeze göre) taşınır; kapalı hâl kiriş üzerinde
yatar, açık hâl 90° aşağı döner.

## Reduced motion

Mevcut fade-swap yaklaşımı korunur (180 ms; yarıda görünmezlik, sonra son
durum). Uyarlamalar: başlangıç görüntüsü `initialState` farkındalıklıdır
(devam başlangıcında önceki kazanan yuvada görünür, sonda fanusta boş bir
taban slotuna yerleşmiş gösterilir); yeni kazanan sonda yuvada; `gateProgress`
tüm süreçte 0 (kapalı) kalır; rotor dönmez.

## Test planı

`test/who_pays_lottery_simulation_test.dart` güncellenir/genişletilir:

- **Sonuç garantisi**: personCount 2–6 × çok sayıda seed × (idle + devam
  başlangıcı) taramasında kazanan süre sonunda (0, 209)'da ve kapak kapalı.
- **Işınlanma-yok invaryantı**: 60 fps adımlamayla tüm zaman çizelgesinde
  hiçbir topun kare başı yer değiştirmesi makul sınırı (ör. 16 px) aşamaz.
- **Tarafsızlık**: capture başlangıcından önce kazanana özel kuvvet kodu
  çalışmaz (simülasyon bunu doğrulanabilir bir sayaç/bayrakla açığa çıkarır).
- **Resume**: karışımın ortasından doğrudan `advanceTo(duration)` çağrısı
  sonrası hiçbir top havada değil (hepsi taban slotlarında veya yuvada).
- **Huni**: kazanan tüpe yalnızca huni sınırları içinde iner; |x| tüpte
  4 px'i aşmaz.

Ek işler: golden dosyaları yeni koreografiye göre yeniden üretilir;
`test/widget_test.dart` sabit 4100 ms pompalama yerine simülasyon süresinden
türetilen değerleri kullanır ve bir "Tekrar Çek" (devam başlangıcı) akışı
eklenir; `dart format`, `flutter analyze` ve `flutter test` temiz geçmeden iş
bitmiş sayılmaz.

## Kabul kriterleri

1. `flutter analyze` sorunsuz, `flutter test` tümü yeşil.
2. 2 ve 6 kişiyle çekiliş: karıştırma/çökme sırasında kazanan ayırt edilemez;
   emilme yalnızca kapak açılırken görülür; top yuvaya cam tabana teğet
   oturur; kapak kapanır.
3. "Tekrar Çek": yuvadaki top tüpten geri emilir, hiçbir top ışınlanmaz,
   toplam süre ~3.85 sn.
4. Animasyon gerçek hızda (controller süresi simülasyon süresine eşit).
5. Uygulama arka plana alınıp döndürüldüğünde toplar havada donmuş kalmaz.

## Riskler

- **Capture güvenilirliği (6 top)**: hava yastığı + ramp'li emilme + son
  100 ms garanti kuvveti + son-kare yuva garantisi katmanlı çözer; seed
  taramalı testler kanıtlar.
- **Golden churn**: koreografi değiştiği için tüm golden'lar yeniden üretilir;
  incelemede kareler gözle doğrulanır.

## Uygulama notları (post-execution, 20 Temmuz 2026)

Aşağıdaki adjudike edilmiş sapmalar orijinal metne göre değişse de gönderilen
(shipped) davranıştır:

1. Emme sabitleri: suctionSpringRate 60→90, suctionDampingRate 14→2.5,
   suctionRampMax 3200 (değişmedi), suctionGuaranteeMax 5200→8000; garanti
   penceresi son 100 ms→son 300 ms (`_guaranteeWindow=0.30`, yük taşıyor —
   0.25'te varış kaçıyor; gelecekteki ayarlarda payı yok).
2. Karışım hissi: wallRestitution 0.58→0.93, çarpışma çözüm geçişi 3→8
   (`collisionPasses`) — depodaki önceden-kırık iki karışım testi (örtüşme
   ve duvara yapışma) ancak bu değerlerle geçiyor; spec'in sabitlediği 760
   hız limiti ve 0.22 mixing drag korunuyor.
3. Kazanan, capture fazından itibaren rotor temasından muaf (yapısal): düz
   hat emiş, duran rotorun kanadına/göbeğine sıkışıyordu; rotor topların
   arkasında ve yarı saydam olduğundan görsel etkisi yok.
4. Kazanan, capture sırasında fanustayken 0.6 drag kullanır
   (`winnerCaptureDragRate`); kaybedenler 2.0'da kalır.
5. Işınlanma-yok invaryantı faz-ölçekli: rotor aktifken 32 px/kare (meşru
   kanat darbesi), settling'den sonra 24 px/kare (spec'teki "ör. 16 px"
   örneği yerine).
6. Resume yerleştirme tetikleyicisi yalnız droppedCatchUp (hız>150 koşulu,
   sürekli oynatımın son karesindeki meşru artık hız yüzünden kaldırıldı).
   Kabul edilen sınırlama: bitişten <66 ms önce inen iki-çağrılık resume,
   kaybedenleri havada bırakabilir.
7. Rotor açısı exportState'e dahil değil: yeniden çekilişin ilk karesinde
   rotor ~13° atlar (3 kanatlı simetriyle fark edilmesi güç) — kabul
   edilmiş cila sınırı.

### Ek — 21 Temmuz 2026: duvar-sarmal yakalama

Kullanıcı isteğiyle yakalama koreografisi değişti: kazanan artık ağza kuş
uçuşu çekilmek yerine önce cama yaslanıp (radyal yay) fanusun eğrisi
boyunca süpürülerek (teğetsel kuvvet; açısal fark ±π'ye sarılı) ağza iner;
ağza `captureNearMouthAngle` (0.45 rad) kala huniye bırakan düz yaya geçer.
Beraberinde: çökme fazında iniş yardımı (`settleAssistGravityFactor` 1.3,
tüm toplara eşit — tarafsızlık korunur); son-çare penceresi 0.30 → 0.10 sn
(ana teslimatçı duvar kuvvetidir); hava yastığı radyal üflemeden
yana-süpürücüye çevrildi ve kazanan tüpe girene dek açık kalacak şekilde
genişletildi (85 px / 1400); yakalama sırasında kazanan çarpışmada "ağır
top"tur (kaybeden kenara itilir, aktarılan hız `plowKickCap` 320 px/s ile
sınırlı). Yeni invariant testi: kazanan yakalama boyunca duvara yakın kalır
(r ≥ 85 / tüpte / ağız bölgesinde) — merkezden ve duran rotor kanatlarının
içinden kestirme geçemez.

Aynı gün, sinematik pürüzler (kod-içi kinematik taramayla ölçülerek):
karışım sonrası tüm toplara düşey terminal hız (`postMixTerminalFallSpeed`
560 px/s — fanus yüksekliğinden serbest düşüş ~494 üretir), kazanana
yakalama boyunca hız tavanı (`winnerCaptureMaxSpeed` 540), yuvadan önce
40 px'lik iniş yastığı (`seatCushionZone`/`seatCushionDragRate` — çarpış
~550'den ~180 px/s'e indi, tek karede durma kalktı) ve karışım sonrası
çakışma/kanat ayrıştırma itmelerine kare başına 5 px tavan eklendi.
Rotor yavaşlarken kanadın topa hızlı vurması bilinçli olarak korunur —
ekranda nedeni görünen meşru fiziktir (ışınlanma-yok testinin rotor-aktif
32 px sınırı içinde).

Aynı gün, "delik üstünde duran top" tutarsızlığı: kazanan önceden seçili
olduğundan, kapak açıldığında ağzın tam üstünde dinlenen bir kaybeden
"asıl düşmesi gereken top" gibi görünüp seçimi saçmalaştırabiliyordu.
Çözüm nötr bir kapak sırtı: ağız kutusu (|x| < `mouthKeepoutHalfWidth` 34,
dy > `gateRidgeTopY` 84) karışım sonrası dinlenilemez bölgedir — içine
oturan top, pass döngüsü İÇİNDE ve adım başına `postMixSeparationCap`
(5 px) bütçesiyle yana tahliye edilir (tümsekten kayma gibi; kazanan
yakalamadan itibaren, intake topu prolog boyunca muaftır; karışım öncesi
herkes eşit — tarafsızlık testli). "Park" tanımı testte kalıcılıktır
(kutuda ≥9 ardışık kare); kazananın buldozeri kaybedeni bir anlığına ağız
üstünden süpürebilir — bu geçiş meşru fiziktir.
