import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/providers.dart';

void main() {
  test('day navigation uses calendar dates across DST boundaries', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(selectedDayProvider.notifier);

    notifier.select(DateTime(2026, 3, 9));
    notifier.previousDay();
    expect(container.read(selectedDayProvider), DateTime(2026, 3, 8));

    notifier.select(DateTime(2026, 11, 1));
    notifier.nextDay();
    expect(container.read(selectedDayProvider), DateTime(2026, 11, 2));
  });
}
