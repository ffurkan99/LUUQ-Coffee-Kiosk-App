# Çalışma Anında Lisans Devre Dışı Bırakma Hatası

Tarih: 19 Temmuz 2026

## Özet

Sunucuda lisans pasife alındığında uygulama ilk açılışta doğru şekilde müşteri
arayüzünü kapatıyordu; ancak uygulama çalışırken lisans pasife alınırsa 30
saniyelik kontrol devam etmesine rağmen kiosk açık kalıyordu.

Sorun polling zamanlayıcısında veya cihaz kimliğinde değildi. Backend ile
istemcinin HTTP durum kodu yorumları birbiriyle uyuşmuyordu.

## Gerçek Kök Neden

Canlı `check-status.php` isteği pasif lisans için şu cevabı döndürüyordu:

```text
HTTP 400 Bad Request
active=false
reason=license_inactive
message=Bu lisans pasif durumda.
```

`LicenseService.checkStatus()` yalnız `HTTP 200` cevap gövdelerini lisans
cevabı olarak ayrıştırıyordu. Bütün diğer HTTP durumları, gövdedeki geçerli
lisans sonucuna bakılmadan `server_error` durumuna çevriliyordu.

`FeatureSyncService.syncNow()` ise ağ veya sunucu kesintisinde çalışan kiosk
oturumunu yanlışlıkla kapatmamak için `network_error` ve `server_error`
sonuçlarında mevcut oturumu koruyordu. Böylece akış şu hale geliyordu:

```text
Backend: HTTP 400 + license_inactive
    -> LicenseService: server_error
    -> FeatureSyncService: sunucu arızası kabul et, oturumu koru
    -> Müşteri arayüzü açık kalır
```

Terminalde görülen `API check-status` ve `check-status app_version` satırları
yalnızca isteğin başladığını gösteriyordu; cevabın başarıyla işlendiğini
göstermiyordu.

## Uygulanan Çözüm

`LicenseService.checkStatus()` aşağıdaki kurallarla güncellendi:

- `HTTP 200` cevapları mevcut katı şema kontrolüyle işlenmeye devam eder.
- `HTTP 400`, yalnız cevap şeması geçerliyse, `active=false` içeriyorsa ve
  `reason` uygulamanın tanıdığı lisans durumlarından biriyse yetkili pasif
  lisans cevabı sayılır.
- Kabul edilen nedenler: `device_revoked`, `invalid_license`,
  `license_inactive`, `license_expired`, `device_limit_reached`,
  `trial_already_used` ve `trial_expired`.
- Bilinmeyen veya bozuk `400`, diğer `4xx`, bütün `5xx` cevapları ve taşıma
  hataları lisans iptali olarak yorumlanmaz.
- Geçerli pasif cevap işlendiğinde durum `active=false` olarak yayımlanır,
  özellikler kilitlenir ve `FeatureSyncService` müşteri ekranını kaldırarak
  lisans aktivasyon ekranına yönlendirir.

Bu değişiklik 30 saniyelik polling aralığını, online-only açılış politikasını
ve backend payload sözleşmesini değiştirmedi.

## Doğrulama

- Fake HTTP ile `400 + license_inactive` açılış testi eklendi.
- Çalışan müşteri arayüzünün aynı cevap sonrasında lisans ekranına
  yönlendirildiği widget testi eklendi.
- Bilinmeyen `400` cevabının `server_error` kalması test edildi.
- Tüm testler geçti: `73/73`.
- `flutter analyze` temiz tamamlandı.
- Android ve Windows release build'leri başarılı tamamlandı.
- Canlı aktif -> pasif geçişinde manuel kontrol çağrısı yapılmadan gerçek
  polling izlendi. Sonuç `active=false`, `reason=license_inactive` oldu;
  müşteri ekranı dispose edildi, aktivasyon ekranı açıldı ve sync timer durdu.

## Gelecekte Aynı Hatayı Önleme Kuralları

1. HTTP durum kodu ile iş alanı sonucunu birbirine karıştırma. Backend bir iş
   alanı sonucunu `4xx` ile döndürüyorsa gövde, yalnız açık ve katı bir sözleşme
   dahilinde değerlendirilmelidir.
2. `HTTP != 200` durumunu otomatik olarak `server_error` yapmadan önce endpoint
   sözleşmesini ve gerçek canlı cevabı doğrula.
3. Ağ/sunucu hatası ile doğrulanmış lisans iptalini farklı durumlar olarak
   koru. Taşıma hatasında çalışan oturumu koruma politikası, gerçek iptal
   cevabını yutmamalıdır.
4. Açılış doğrulaması ve çalışma-anı polling akışını ayrı ayrı test et. Birinin
   doğru çalışması diğerinin de doğru olduğunu göstermez.
5. Her lisans entegrasyonu değişikliğinde şu regresyonları çalıştır:
   geçerli lisans, `license_inactive`, expired, revoked, bilinmeyen `400`, bozuk
   JSON, `5xx`, timeout, DNS ve TLS hatası.
6. Terminal loglarında yalnız isteğin başladığını değil, hassas veri yazmadan
   HTTP sınıfını ve normalize edilmiş sonucu da gözlemlenebilir kıl. Lisans
   anahtarı, tam cihaz kimliği veya ham cevap gövdesi loglanmamalıdır.
7. Backend davranışı değiştirilirse istemciye tahminle yeni status/reason
   ekleme; sözleşmeyi doğrula ve önce contract/regresyon testi ekle.

## İlgili Kod

- `lib/licensing/license_service.dart`
  - `LicenseService._authoritativeInactiveReasons`
  - `LicenseService._isAuthoritativeInactiveResponse()`
  - `LicenseService.checkStatus()`
- `lib/licensing/feature_sync_service.dart`
  - `FeatureSyncService.syncNow()`
- `test/license_startup_test.dart`
  - `HTTP 400 license_inactive is an authoritative inactive response`
  - `unknown HTTP 400 response remains a server error`
  - `runtime sync redirects after HTTP 400 license deactivation`

Satır numaraları zamanla değişebileceği için incelemelerde yukarıdaki sınıf,
metot ve test adları esas alınmalıdır.
