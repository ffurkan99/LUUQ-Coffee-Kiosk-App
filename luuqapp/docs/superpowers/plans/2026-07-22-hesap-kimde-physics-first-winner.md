# Hesap Kimde Fizik-Öncelikli Kazanan Seçimi — Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kazananı fizik belirler: kapak açıldığında ağızdan gerçekten düşen top `capturedBallIndex` olur; dialog sonucu simülasyondan okur.

**Architecture:** `WhoPaysLotterySimulation`'dan `winnerIndex` girdisi kalkar, `int? capturedBallIndex` çıktısı gelir. Yakalama öncesi tüm kuvvetler nötrdür (endeks koşullu dal ateşlenemez, sayaçla kanıtlanır); kapak açılınca ağız sektörü delik olur, huniye ilk giren top atanır, kapak arkasından kapanır. Ağız boş kalırsa rampalanan nötr drenaj; mutlak son çare "ağza en yakın top atanır".

**Tech Stack:** Flutter/Dart, sabit adımlı deterministik fizik (1/120 sn), flutter_test + golden testler.

Spec: `docs/superpowers/specs/2026-07-21-hesap-kimde-physics-first-winner-design.md`

## Global Constraints

- Faz sınırları değişmez: spinUp 0.18 / mixing 2.05 / settling 2.55 / capture 3.00 / dropping 3.32 / süre 3.40 sn; redraw 3.85 sn.
- Spec-pinned: `maxBallSpeed=760`, `mixingDragRate=0.22`, `collisionPasses=8`, `wallRestitution=0.93`, sabit adım 1/120, kare başına ≤8 adım.
- Sinematik tavanlar korunur: `postMixTerminalFallSpeed=560`, `plowKickCap=320`, `postMixSeparationCap=5`, seat cushion 36/11 — artık yakalanan topa uygulanır.
- Kazanan-farkındalıklı kapanış korunur: `_gateCloseStart=3.10`, `_gateCloseLength=0.14`, `gateSweepClearY=158` — referans `capturedBallIndex`.
- Komutlar `rtk` ÖNEKSİZ çalıştırılır (rtk bu makinede kurulu değil).
- Çalışma dalı: `feat/physics-first-winner` (master'dan).

---

### Task 1: Simülasyon çekirdeği — API tersine çevirme + nötr yakalama

**Files:**
- Modify: `lib/src/who_pays/lottery_simulation.dart`
- Test: `test/who_pays_lottery_simulation_test.dart`

**Interfaces (Produces):**
- Ctor: `WhoPaysLotterySimulation({required int personCount, required int seed, WhoPaysInitialState? initialState, @Deprecated('physics decides the winner') int? winnerIndex})` — `winnerIndex` yok sayılır, Task 2'de silinir.
- `int? get capturedBallIndex` — canlı koşumda atama anından itibaren; reduced-motion'da gölge çözümden. `phase == seated` iken asla null dönmez.
- `int targetedForceApplications` — atama ÖNCESİ endeks-koşullu kuvvet uygulaması sayacı (eski `winnerGuideApplications` yerine); testler 0 kalmasını kanıtlar.

**Adımlar (TDD; her adım sonunda dosya derlenir):**

- [ ] **1.1 Dal aç:** `git checkout -b feat/physics-first-winner`

- [ ] **1.2 RED — çekirdek sözleşme testleri.** `test/who_pays_lottery_simulation_test.dart` içine yeni grup (eski kazanan-hedefli grupların yerini alacak):

```dart
group('physics-first capture', () {
  void advanceInFrames(WhoPaysLotterySimulation sim, double end) {
    var t = sim.timelineSeconds;
    while (t < end - 1e-9) {
      t = math.min(t + 1 / 60, end);
      sim.advanceTo(t);
    }
  }

  for (final personCount in [2, 3, 4, 6]) {
    for (final seed in [11, 47, 20260722, 987654, 31415]) {
      test('draw $personCount/$seed captures exactly one ball and seats it',
          () {
        final sim =
            WhoPaysLotterySimulation(personCount: personCount, seed: seed);
        final crossedThroat = <int>{};
        var t = 0.0;
        while (t < sim.durationSeconds - 1e-9) {
          t = math.min(t + 1 / 60, sim.durationSeconds);
          sim.advanceTo(t);
          for (var i = 0; i < personCount; i++) {
            if (sim.balls[i].position.dy >=
                WhoPaysLotterySimulation.funnelBottomY) {
              crossedThroat.add(i);
            }
          }
        }
        final captured = sim.capturedBallIndex;
        expect(captured, isNotNull);
        expect(crossedThroat, {captured});
        expect(
          (sim.balls[captured!].position -
                  const Offset(0, WhoPaysLotterySimulation.winnerSeatY))
              .distance,
          lessThan(24),
        );
      });
    }
  }

  test('no index-conditioned force fires before capture assignment', () {
    final sim = WhoPaysLotterySimulation(personCount: 6, seed: 424242);
    var t = 0.0;
    while (t < sim.durationSeconds - 1e-9) {
      t = math.min(t + 1 / 60, sim.durationSeconds);
      sim.advanceTo(t);
      if (sim.capturedBallIndex == null) {
        expect(sim.targetedForceApplications, 0,
            reason: 'neutrality broken at t=$t');
      }
    }
    expect(sim.capturedBallIndex, isNotNull);
  });
});
```

- [ ] **1.3 RED doğrula:** `flutter test test/who_pays_lottery_simulation_test.dart` → derleme hatası (`winnerIndex` zorunlu, `capturedBallIndex` yok).

- [ ] **1.4 GREEN — simülasyonu tersine çevir.** `lottery_simulation.dart` değişiklikleri:

**(a) Ctor & alanlar:** `required this.winnerIndex` → `@Deprecated(...) int? winnerIndex` (yok sayılır, alan silinir). Yeni alanlar:

```dart
int? _capturedBallIndex;
int? _reducedMotionCaptured;
final WhoPaysInitialState? _initialState; // gölge kopya için saklanır

int? get capturedBallIndex => _capturedBallIndex ?? _reducedMotionCaptured;
int targetedForceApplications = 0; // winnerGuideApplications'ın yerine
```

**(b) Silinen mekanizmalar (atama öncesi tarafsızlık):** kazanan-özel duvar-sarmal emiş bloğu (`captureNearMouthAngle`, `suctionRampMax`, `winnerCaptureDragRate` sabitleriyle), kapak sırtı KUVVETİ (`gateRidgeStrength`, `gateRidgeHalfWidth`; `gateRidgeTopY` keepout koşulu için kalır), atama öncesi keepout tahliyesi, kazanan rotor muafiyeti ve "ağır top" çarpışma dalının atama öncesi halleri. Kalanlar `_capturedBallIndex`'e koşullanır ve her ateşlemede `targetedForceApplications++` yapılmaz — sayaç yalnızca `_capturedBallIndex == null` iken endeks-koşullu dal çalışırsa artar (yapısal olarak ulaşılmaz olmalı; testler 0'ı kanıtlar).

**(c) Nötr drenaj (yeni sabitler):**

```dart
/// Nötr drenaj: kapak açıkken TÜM toplara eşit, ağza yönlü, rampalanan
/// kuvvet. Ağzın üstünde top yoksa yığını ağza kaydırır — yine en yakın
/// top düşer (endeks önseli yok).
static const double drainRampMax = 900.0;
```

`_stepPhysics` içinde, atama öncesi ve `capturing && stepGateProgress > 0.5` iken her topa:

```dart
final ramp = ((drawTime - _settlingEnd) / (_captureEnd - _settlingEnd))
    .clamp(0.0, 1.0);
final toMouth = mouthTarget - ball.position;
if (toMouth.distance > 1) {
  acceleration += toMouth / toMouth.distance * (drainRampMax * ramp);
}
```

**(d) Ağız deliği + atama.** `_resolveBoundaries(drawTime)` → `_resolveBoundaries(drawTime, stepGateProgress)`. Bir top şu koşulla huni yoluna girer (çember clamp'i atlanır, huni duvarları uygulanır): `mouthOpen && (canEnter) && dy >= tubeEntryY && |dx| <= funnelHalfWidthAt(dy)`, burada `mouthOpen = drawTime >= _settlingEnd && stepGateProgress > 0.5` ve `canEnter = _capturedBallIndex == null || index == _capturedBallIndex` (intake topu mevcut muafiyetini korur). Adım sonunda atama taraması:

```dart
void _assignCaptureIfEntered(double drawTime, double stepGateProgress) {
  if (_capturedBallIndex != null) return;
  if (drawTime < _settlingEnd || stepGateProgress <= 0.5) return;
  int? best;
  var bestDistance = double.infinity;
  for (var index = 0; index < balls.length; index++) {
    final p = balls[index].position;
    if (p.dy < tubeEntryY || p.dx.abs() > funnelHalfWidthAt(p.dy)) continue;
    final d = (p - mouthTarget).distance;
    if (d < bestDistance) {
      bestDistance = d;
      best = index;
    }
  }
  if (best != null) _capturedBallIndex = best;
}
```

**(e) Son çare (garanti).** `_stepPhysics` başında: `drawTime >= _captureEnd - _guaranteeWindow` ve atama yoksa, ağza (mouthTarget'a) en yakın top atanır. Atanmış ama henüz tüpte olmayan topa hedefli düz yay uygulanır (bu dal `_capturedBallIndex != null` koşullu — tarafsızlık sözleşmesine uygun):

```dart
// atanmış top henüz huniye inmediyse (son-çare transiti):
pull = (mouthTarget - ball.position) * suctionSpringRate -
    ball.velocity * suctionDampingRate;
acceleration += _clampMagnitude(pull, suctionGuaranteeMax);
dragRate = capturedTransitDragRate; // = 0.6 (eski winnerCaptureDragRate)
```

Atanmış top rotor temasından ve top-top çarpışmasında "ağır top" kuralıyla mevcut şekilde muaf/öncelikli olur (referans capturedIndex). `winnerCaptureMaxSpeed` tavanı atanmış topa uygulanır.

**(f) Atama SONRASI keepout:** mevcut `_ridgeShiftBudget` tahliyesi yalnız `_capturedBallIndex != null && index != _capturedBallIndex` iken çalışır ("ikinci top sızmasın"). Kaybeden yana-süpürme yastığı (`cushionRadius/cushionMax`) ve `_capturedReachedTube` (eski `_winnerReachedTube`) akışı aynen, captured referanslı.

**(g) advanceTo:** kapanış tetiği ve donma-karesi garantisi captured'a bağlanır:

```dart
final captured = _capturedBallIndex;
if (_gateCloseBeganAt == null &&
    target - _phaseShift >= _gateCloseStart &&
    captured != null &&
    balls[captured].position.dy >= gateSweepClearY) {
  _gateCloseBeganAt = timelineSeconds;
}
if (target >= durationSeconds) {
  _capturedBallIndex ??= _nearestToMouth(); // resume-jump son çaresi
  balls[_capturedBallIndex!]
    ..position = const Offset(0, winnerSeatY)
    ..velocity = Offset.zero;
  _gateCloseBeganAt ??= timelineSeconds - _gateCloseLength;
  if (droppedCatchUp) _settleLosersToFloor();
}
```

**(h) exportState / _settleLosersToFloor / _reducedMotionEndPositions:** `winnerIndex` → `capturedBallIndex` (null ise exportState `seatedBallIndex: null`).

**(i) Reduced-motion gölgesi:**

```dart
int _resolveReducedMotionCaptured() {
  final cached = _reducedMotionCaptured;
  if (cached != null) return cached;
  final shadow = WhoPaysLotterySimulation(
    personCount: personCount,
    seed: seed,
    initialState: _initialState,
  );
  var t = 0.0;
  while (t < shadow.durationSeconds - 1e-9) {
    t = math.min(t + 1 / 60, shadow.durationSeconds);
    shadow.advanceTo(t);
  }
  return _reducedMotionCaptured = shadow._capturedBallIndex!;
}
```

`advanceReducedMotion` sonunda (`value >= 0.5` dalında) `_resolveReducedMotionCaptured()` kullanılır; ana örneğin `balls` listesi mutasyona uğramaz.

- [ ] **1.5 Mevcut testleri dönüştür.** Aynı dosyada mekanik + anlamsal dönüşümler:
  - Tüm `winnerIndex: N` ctor argümanları silinir.
  - "winner … is seated" 20'li süpürme + redraw süpürmesi → 1.2'deki "captures exactly one ball" kalıbı (redraw varyantı initialState ile).
  - "no winner-specific force" → 1.2'deki tarafsızlık testi (eski silinir).
  - "no loser parks over the gate mouth" → atama SONRASINA kapsamlanır: atamadan +0.1 sn sonrasından itibaren, captured olmayan top ağız kutusunda (|x|≤24, dy≥86) ≥9 ardışık kare kalamaz.
  - "gate never closes through the winner" 12 senaryosu → captured referanslı (kapak azalırken captured top dy∈(112,154) bandında olamaz).
  - Monoton iniş, huni duvarı, resume, exportState, redraw intake, reduced-motion testleri captured referanslı olur; reduced-motion testine `capturedBallIndex` non-null beklentisi eklenir.
  - YENİ: gölge-canlı eşdeğerliği — aynı seed'de canlı koşumun kazananı ile taze örnekte `advanceReducedMotion(1.0)` sonrası `capturedBallIndex` aynı olmalı.
- [ ] **1.6 GREEN doğrula:** `flutter test test/who_pays_lottery_simulation_test.dart` → tümü geçer.
- [ ] **1.7 Commit:** `git add -A && git commit -m "feat(who_pays): physics-first capture — the ball that falls IS the winner"`

### Task 2: main.dart bağlantısı + deprecated parametrenin kaldırılması + golden

**Files:**
- Modify: `lib/main.dart` (≈4703-4714 `_spin`, 4967-4980 çağrı, 5115-5277 `_LotteryMachine`), `lib/src/who_pays/lottery_simulation.dart` (deprecated param silinir), `test/who_pays_lottery_golden_test.dart:73-77`
- Test: `flutter test` (tam paket) + `--update-goldens`

**Interfaces:**
- Consumes: `capturedBallIndex` (Task 1).
- Produces: `_LotteryMachine({required personCount, playerColors, isAnimating, showResult, required ValueChanged<int> onComplete})` — winnerIndex prop'u YOK.

- [ ] **2.1** `_spin()`: `_winnerIndex = _rand.nextInt(_personCount);` satırı silinir (`_rand` başka kullanıcısı yoksa o da silinir). `_winnerIndex` alanı kalır ama yalnız `onComplete` doldurur.
- [ ] **2.2** `_LotteryMachine`: `winnerIndex` prop'u ve `_safeWinnerIndex` silinir; `onComplete` `ValueChanged<int>` olur. Status listener:

```dart
if (status == AnimationStatus.completed && mounted) {
  _spinSound.playResult();
  final captured = _simulation.capturedBallIndex;
  assert(captured != null, 'seated draw must have a captured ball');
  widget.onComplete(captured ?? 0);
}
```

Dialog tarafı: `onComplete: (winner) { setState(() { _winnerIndex = winner; _result = winner + 1; _isAnimating = false; }); }`. `Semantics` etiketi kazananı `_simulation.capturedBallIndex`'ten okur.
- [ ] **2.3** Simülasyondan `@Deprecated` `winnerIndex` parametresi tamamen silinir; golden testte `winnerIndex: 2,` satırı silinir.
- [ ] **2.4** Goldenlar yeniden üretilir: `flutter test --update-goldens test/who_pays_lottery_golden_test.dart`; PNG'ler gözle kontrol (capture karesinde ağza inen top, result karesinde yuvada top).
- [ ] **2.5** `flutter analyze` temiz + `flutter test` tam paket yeşil.
- [ ] **2.6 Commit:** `feat(who_pays): dialog reads the winner from the simulation`

### Task 3: Adalet taraması + kalıcı adalet testi

**Files:**
- Create (geçici, merge öncesi silinir): `test/_diag_fairness_survey_test.dart`
- Test: `test/who_pays_lottery_simulation_test.dart` (kalıcı gevşek test)
- Modify: spec dosyasına ölçüm addendum'u

- [ ] **3.1** Diag taraması: kişi sayısı {2,3,4,6} × seed 1..600 taze çekiliş + {2,6} × seed 1..300 redraw (önceki çekilişin exportState'i ile); her endeksin kazanma payı, son-çare (guarantee-atama) oranı ve atama zamanı dağılımı raporlanır.
- [ ] **3.2** Bant kontrolü: her pay 1/n'in 0.55–1.6 katı içinde mi? İçindeyse 3.4'e geç. DEĞİLSE: `_initializeBalls`'a seed'li dizilim karıştırması eklenir — pozisyon listesi üretilir, `positions.shuffle(_random)` ile endekslere atanır — ve tarama tekrarlanır.
- [ ] **3.3** Kalıcı test (deterministik, gevşek):

```dart
test('capture outcomes are distributed fairly across players', () {
  for (final personCount in [2, 6]) {
    final wins = List<int>.filled(personCount, 0);
    for (var seed = 1; seed <= 240; seed++) {
      final sim =
          WhoPaysLotterySimulation(personCount: personCount, seed: seed);
      var t = 0.0;
      while (t < sim.durationSeconds - 1e-9) {
        t = math.min(t + 1 / 60, sim.durationSeconds);
        sim.advanceTo(t);
      }
      wins[sim.capturedBallIndex!]++;
    }
    final expected = 240 / personCount;
    for (final count in wins) {
      expect(count, greaterThan(expected * 0.45));
      expect(count, lessThan(expected * 1.75));
    }
  }
}, timeout: const Timeout(Duration(minutes: 3)));
```

- [ ] **3.4** Ölçümler spec addendum'una yazılır; diag dosyası silinir; commit: `test(who_pays): fairness distribution locked`

### Task 4: Kinematik kalite taraması + son doğrulama

**Files:**
- Create (geçici): `test/_diag_quality_survey_test.dart` (önceki turun metodolojisi: gateClips, seatImpact, seatTime, hesitation, jitter + YENİ lastResortRate, secondEntryAttempts)
- Modify: gerekiyorsa `lottery_simulation.dart` sabit ayarı (drainRampMax vb.), spec addendum

- [ ] **4.1** 120 koşuluk tarama (40 seed × {2,4,6}); hedefler: gateClips 0, ikinci giriş 0, seatImpact p50 ≤ 300 px/s, son-çare oranı < %25, oturma zamanı p50 < 3.2 sn.
- [ ] **4.2** Hedef tutmayan metrik için sabit ayarı (öncelik: drainRampMax, sonra guarantee süreleri İÇİ dengeler — faz sınırları değişmez) + tarama tekrarı.
- [ ] **4.3** Diag silinir; `flutter analyze` temiz; `flutter test` tam paket yeşil; spec addendum commit'i: `feat(who_pays): capture quality pass`
- [ ] **4.4** superpowers:finishing-a-development-branch ile master'a merge.

## Self-Review Notları

- Spec kapsaması: API tersine çevirme (T1a), total tarafsızlık (T1b + sayaç), nötr drenaj (T1c), son çare (T1e), tek-top (T1d/f + throat testi), kapanış (T1g), exportState/intake (T1h), reduced-motion gölgesi (T1i + eşdeğerlik testi), main.dart (T2), adalet (T3), riskler tablosu (T3/T4 metrikleri). Gap yok.
- Tip tutarlılığı: `capturedBallIndex` getter null-able; `onComplete` `ValueChanged<int>`; `_resolveBoundaries(drawTime, stepGateProgress)`.
