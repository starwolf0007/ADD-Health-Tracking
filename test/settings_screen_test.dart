import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/platform/settings_service.dart';
import 'package:neuroflow/presentation/settings_screen.dart';
import 'package:neuroflow/presentation/theme.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('Done saves the name and dismisses the keyboard', (tester) async {
    await _pump(tester);
    final field = find.byKey(const ValueKey('about-you-name-field'));

    await tester.tap(field);
    await tester.enterText(field, '  Bryan  ');
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );
    expect(await SettingsService().getDisplayName(), 'Bryan');
  });

  testWidgets('tapping outside saves the name and dismisses focus',
      (tester) async {
    await _pump(tester);
    final field = find.byKey(const ValueKey('about-you-name-field'));

    await tester.tap(field);
    await tester.enterText(field, 'Pat');
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('INTEGRATIONS'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );
    expect(await SettingsService().getDisplayName(), 'Pat');
  });
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        advisorTierProvider.overrideWith(() => AdvisorTierNotifier()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
