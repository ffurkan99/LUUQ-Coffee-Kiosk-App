import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/main.dart'
    show GlobalDialogTracker, UpdateState, updateDialogIdleClosable;

void main() {
  tearDown(() {
    GlobalDialogTracker.isUpdateDialogOpen = false;
    GlobalDialogTracker.isUpdateIdleClosable = false;
    GlobalDialogTracker.isUpdateDownloading = false;
    GlobalDialogTracker.isUpdateVerifying = false;
    GlobalDialogTracker.isUpdateReadyToInstall = false;
    GlobalDialogTracker.isUpdateOpeningInstaller = false;
    GlobalDialogTracker.isAdminPinDialogOpen = false;
    GlobalDialogTracker.isAdminSessionOpen = false;
    GlobalDialogTracker.isCustomerDialogOpen = false;
  });

  test('an untouched update offer lets the idle timer run', () {
    GlobalDialogTracker.isUpdateDialogOpen = true;
    GlobalDialogTracker.isUpdateIdleClosable = updateDialogIdleClosable(
      state: UpdateState.updateAvailable,
      kioskSecured: true,
      externalScreenOpen: false,
    );
    expect(GlobalDialogTracker.shouldPauseIdleTimer(), isFalse);
    // ...but a new menu still waits until the dialog is gone.
    expect(GlobalDialogTracker.shouldDeferMenuChanges(), isTrue);
  });

  test('a broken kiosk lock or an outside screen keeps the dialog open', () {
    expect(
      updateDialogIdleClosable(
        state: UpdateState.failed,
        kioskSecured: false,
        externalScreenOpen: false,
      ),
      isFalse,
    );
    expect(
      updateDialogIdleClosable(
        state: UpdateState.failed,
        kioskSecured: true,
        externalScreenOpen: true,
      ),
      isFalse,
    );
    GlobalDialogTracker.isUpdateDialogOpen = true;
    GlobalDialogTracker.isUpdateIdleClosable = false;
    expect(GlobalDialogTracker.shouldPauseIdleTimer(), isTrue);
  });

  test('download, verification and a ready APK always pause', () {
    for (final state in [
      UpdateState.downloading,
      UpdateState.downloaded,
      UpdateState.verifying,
      UpdateState.readyToInstall,
      UpdateState.openingInstaller,
    ]) {
      expect(
        updateDialogIdleClosable(
          state: state,
          kioskSecured: true,
          externalScreenOpen: false,
        ),
        isFalse,
        reason: '$state',
      );
    }
    GlobalDialogTracker.isUpdateDownloading = true;
    expect(GlobalDialogTracker.shouldPauseIdleTimer(), isTrue);
  });

  test('a customer dialog holds back menu changes without pausing idle', () {
    GlobalDialogTracker.isCustomerDialogOpen = true;
    expect(GlobalDialogTracker.shouldDeferMenuChanges(), isTrue);
    expect(GlobalDialogTracker.shouldPauseIdleTimer(), isFalse);
  });
}
