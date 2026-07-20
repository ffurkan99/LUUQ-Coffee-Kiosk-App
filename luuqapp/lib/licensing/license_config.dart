class LicenseConfig {
  static const String baseUrl = 'https://luuq.524music.com';

  static const String validateLicenseUrl = '$baseUrl/api/validate-license.php';
  static const String checkStatusUrl = '$baseUrl/api/check-status.php';
  static const String verifyAdminPinUrl = '$baseUrl/api/verify-admin-pin.php';

  static const Duration apiTimeout = Duration(seconds: 8);
}
