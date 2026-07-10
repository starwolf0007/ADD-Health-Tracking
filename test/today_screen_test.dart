import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/presentation/today/today_timeline.dart';
import 'package:neuroflow/presentation/today_screen.dart';

void main() {
  final now = DateTime(2026, 7, 10, 12);

  testWidgets('renders mixed timeline and remains functional without Lexi',
      (tester) async {
    await tester.pumpWidget(_app(_mixedData(lexiAvailable: false), now));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Your plan, on device'), findsOneWidget);
    expect(find.textContaining('Lexi is offline'), findsOneWidget);
    expect(find.text('Calendar sync'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Morning anchor'), 180);
    expect(find.text('Morning anchor'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Flexible writing block').last, 180);
    expect(find.text('Flexible writing block'), findsWidgets);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('shows an empty day state', (tester) async {
    await tester.pumpWidget(_app(
        const TodayTimelineData(
          items: [],
          recommendedTask: null,
          hasCalendarPermission: false,
          lexiAvailable: false,
        ),
        now));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Your day has room'), findsOneWidget);
  });

  testWidgets('Pixel-sized screenshot layout supports large text',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(_app(_mixedData(lexiAvailable: true), now));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('Hey, Bryan'), findsOneWidget);
  });
}

Widget _app(TodayTimelineData data, DateTime now) {
  return ProviderScope(
    overrides: [
      todayTimelineProvider.overrideWith((ref) async => data),
      displayNameProvider.overrideWith((ref) async => 'Bryan'),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: TodayScreen(now: now),
    ),
  );
}

TodayTimelineData _mixedData({required bool lexiAvailable}) {
  final task = Task(
    id: 'task',
    title: 'Flexible writing block',
    notes: 'Draft the opening paragraph',
    energy: EnergyLevel.medium,
    createdAt: DateTime(2026, 7, 10, 8),
  );
  return TodayTimelineData(
    items: [
      TimelineItem(
        id: 'done',
        type: TimelineItemType.task,
        title: 'Breakfast',
        start: DateTime(2026, 7, 10, 8),
        isCompleted: true,
      ),
      TimelineItem(
        id: 'calendar',
        type: TimelineItemType.calendarEvent,
        title: 'Calendar sync',
        start: DateTime(2026, 7, 10, 11, 30),
        end: DateTime(2026, 7, 10, 12, 30),
      ),
      TimelineItem(
        id: 'anchor',
        type: TimelineItemType.fixedAnchor,
        title: 'Morning anchor',
        start: DateTime(2026, 7, 10, 13),
      ),
      TimelineItem(
        id: 'flex',
        type: TimelineItemType.flexibleBlock,
        title: task.title,
        start: DateTime(2026, 7, 10, 14),
        task: task,
      ),
    ],
    recommendedTask: task,
    hasCalendarPermission: true,
    lexiAvailable: lexiAvailable,
  );
}
