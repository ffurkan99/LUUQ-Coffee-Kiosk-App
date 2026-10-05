import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:luuqapp/licensing/license_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'device_id': 'test-device-id',
      'device_fingerprint_hash': 'test-device-fingerprint',
    });
    PackageInfo.setMockInitialValues(
      appName: 'LUUQ',
      packageName: 'com.luuq.kiosk',
      version: '1.1.0',
      buildNumber: '13',
      buildSignature: '',
    );
  });

  Future<String?> validateWith(int statusCode, Object body) {
    return http.runWithClient(
      () async =>
          (await LicenseService.instance.validateLicense('LUUQ-AAAA-BBBB'))
              .reason,
      () => MockClient(
        (_) async =>
            http.Response(body is String ? body : jsonEncode(body), statusCode),
      ),
    );
  }

  test('4xx rejections surface the server reason, not server_error', () async {
    expect(
      await validateWith(400, {'active': false, 'reason': 'invalid_license'}),
      'invalid_license',
    );
    expect(
      await validateWith(400, {
        'active': false,
        'reason': 'device_limit_reached',
      }),
      'device_limit_reached',
    );
    expect(
      await validateWith(409, {
        'active': false,
        'reason': 'device_reenrollment_required',
        'reset_required': true,
      }),
      'device_reenrollment_required',
    );
  });

  test('5xx and non-JSON bodies stay server_error', () async {
    expect(await validateWith(500, {'reason': 'server_error'}), 'server_error');
    expect(await validateWith(403, '<html>blocked</html>'), 'server_error');
    expect(
      await validateWith(400, {'reason': 'Bad <b>reason</b>'}),
      'server_error',
    );
  });

  test('re-enrollment reasons have a localized message', () {
    for (final reason in [
      'device_reenrollment_required',
      'menu_profile_reenrollment_required',
      'device_binding_mismatch',
      'rate_limited',
    ]) {
      expect(
        LicenseService.getLocalizedError(reason),
        isNot(LicenseService.getLocalizedError('definitely_unknown')),
      );
    }
  });
}
