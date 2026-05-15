import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/services/notification_service.dart';

void main() {
  test('NotificationService starts uninitialized', () {
    final svc = NotificationService();
    expect(svc.isInitialized, isFalse);
    expect(svc.permissionGranted, isFalse);
  });
}
