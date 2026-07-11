import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/presentation/today/lexi_avatar.dart';

void main() {
  testWidgets('registered public Lexi asset renders', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: LexiAvatar(
          visualState: LexiVisualState.idle,
          assetPath: 'assets/lexi/public/lexi_placeholder_public.png',
          semanticLabel: 'Public Lexi placeholder',
        ),
      ),
    ));
    await tester.pump();

    expect(find.bySemanticsLabel('Public Lexi placeholder'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing asset renders fallback safely', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: LexiAvatar(
          visualState: LexiVisualState.focus,
          assetPath: 'assets/lexi/public/missing.png',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.center_focus_strong_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
