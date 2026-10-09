import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/licensing/update_service.dart';

void main() {
  test('an update without a checksum is refused before downloading', () {
    expect(UpdateService.hasVerificationInfo(null), isFalse);
    expect(UpdateService.hasVerificationInfo(''), isFalse);
    expect(UpdateService.hasVerificationInfo('   '), isFalse);
  });

  test('an update with a checksum goes on to the download', () {
    expect(
      UpdateService.hasVerificationInfo(
        '344dd8ea87c0c8bc1b009a18b07f14214bde71fd106ad8f2f807e99d71667978',
      ),
      isTrue,
    );
  });
}
