import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/platform/notifications/notification_service.dart';

void main() {
  test('notification operations safely no-op before platform initialization',
      () async {
    final service = NotificationService();

    expect(await service.areNotificationsEnabled(), isNull);
    expect(await service.requestNotificationPermission(), isNull);

    await service.showActiveTaskTimer(
      taskTitle: 'Test task',
      startedAt: DateTime(2026, 7, 12, 9),
    );
    await service.cancelActiveTaskTimer();
    await service.cancelReminder(101);
    await service.cancelAll();
  });
}
