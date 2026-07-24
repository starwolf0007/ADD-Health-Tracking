import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/hevy_integration_controller.dart';
import 'package:neuroflow/app/hevy_providers.dart';
import 'package:neuroflow/data/database.dart';
import 'package:neuroflow/data/hevy_repository.dart';
import 'package:neuroflow/platform/hevy/hevy_api_client.dart';
import 'package:neuroflow/presentation/health_integrations_screen.dart';
import 'package:neuroflow/presentation/theme.dart';

void main() {
  testWidgets('shows initial disconnected and empty states', (tester) async {
    await _pump(tester, gateway: FakeGateway());
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('No imported workouts yet.'), findsOneWidget);
  });

  testWidgets('successful verification connects without rendering API key', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await _pump(tester, gateway: gateway);
    await tester.enterText(
      find.byKey(const Key('hevyApiKeyField')),
      ' secret-key ',
    );
    await tester.tap(find.byKey(const Key('hevyConnectButton')));
    await tester.pumpAndSettle();

    expect(gateway.savedKey, 'secret-key');
    expect(find.text('Connected'), findsOneWidget);
    expect(find.textContaining('secret-key'), findsNothing);
    expect(find.byKey(const Key('hevyApiKeyField')), findsNothing);
  });

  testWidgets('rejected key is cleared and raw response is hidden', (
    tester,
  ) async {
    final gateway = FakeGateway(
      verifyError: const HevyApiException(
        'private response body: rejected-secret',
        statusCode: 401,
      ),
    );
    await _pump(tester, gateway: gateway);
    await tester.enterText(
      find.byKey(const Key('hevyApiKeyField')),
      'rejected-secret',
    );
    await tester.tap(find.byKey(const Key('hevyConnectButton')));
    await tester.pumpAndSettle();

    expect(gateway.clearCalls, 1);
    expect(gateway.savedKey, isNull);
    expect(find.text('That Hevy API key wasn’t accepted.'), findsOneWidget);
    expect(find.textContaining('private response body'), findsNothing);
    expect(find.textContaining('rejected-secret'), findsNothing);
  });

  testWidgets('sync transitions and duplicate taps start one import', (
    tester,
  ) async {
    final completer = Completer<void>();
    final gateway = FakeGateway(configured: true, syncCompleter: completer);
    await _pump(tester, gateway: gateway);

    final button = find.byKey(const Key('hevySyncButton'));
    await tester.tap(button);
    await tester.tap(button, warnIfMissed: false);
    await tester.pump();
    expect(find.text('Syncing'), findsOneWidget);
    expect(gateway.syncCalls, 1);

    gateway.syncMetadata = HevySyncMetadataRow(
      id: 'hevy',
      lastAttemptAt: DateTime(2026, 7, 18),
      lastSuccessAt: DateTime(2026, 7, 18),
      lastError: null,
      lastImportedCount: 2,
    );
    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text('Sync complete'), findsOneWidget);
    expect(find.textContaining('Last synced'), findsOneWidget);
  });

  testWidgets('failed sync keeps cached workouts and hides exception details', (
    tester,
  ) async {
    final gateway = FakeGateway(
      configured: true,
      syncError: const HevyApiException('server body: private-token'),
    );
    await _pump(
      tester,
      gateway: gateway,
      workouts: [_summary('Cached workout', DateTime(2026, 7, 18))],
    );
    await tester.tap(find.byKey(const Key('hevySyncButton')));
    await tester.pumpAndSettle();

    expect(find.text('Cached workout'), findsOneWidget);
    expect(
      find.text(
        'NeuroFlow couldn’t reach Hevy. Your saved workouts are still available.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('private-token'), findsNothing);
  });

  testWidgets('disconnect clears credential and retains workout list', (
    tester,
  ) async {
    final gateway = FakeGateway(configured: true);
    await _pump(
      tester,
      gateway: gateway,
      workouts: [_summary('Stored locally', DateTime(2026, 7, 18))],
    );
    await tester.tap(find.byKey(const Key('hevyDisconnectButton')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Imported workouts will remain'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Disconnect').last);
    await tester.pumpAndSettle();

    expect(gateway.clearCalls, 1);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Stored locally'), findsOneWidget);
  });

  testWidgets('recent workouts render newest first with descriptive counts', (
    tester,
  ) async {
    await _pump(
      tester,
      gateway: FakeGateway(),
      workouts: [
        _summary('Newest', DateTime(2026, 7, 18)),
        _summary('Older', DateTime(2026, 7, 17)),
      ],
    );

    expect(
      tester.getTopLeft(find.text('Newest')).dy,
      lessThan(tester.getTopLeft(find.text('Older')).dy),
    );
    expect(find.text('2 exercises\n3 sets'), findsNWidgets(2));
    expect(find.textContaining('60 min'), findsNWidgets(2));
  });

  testWidgets('shows integration and workout loading states', (tester) async {
    final gateway = FakeGateway(initializationCompleter: Completer<bool>());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hevyIntegrationGatewayProvider.overrideWithValue(gateway),
          importedWorkoutCountProvider.overrideWith((ref) async => 0),
          recentHevyWorkoutsProvider.overrideWith(
            (ref) => const Stream<List<HevyWorkoutSummary>>.empty(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const HealthIntegrationsScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
  });

  testWidgets('connected screen visual proof', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeGateway(configured: true)
      ..syncMetadata = HevySyncMetadataRow(
        id: 'hevy',
        lastAttemptAt: DateTime(2026, 7, 18, 10, 30),
        lastSuccessAt: DateTime(2026, 7, 18, 10, 30),
        lastError: null,
        lastImportedCount: 2,
      );
    await _pump(
      tester,
      gateway: gateway,
      workouts: [
        _summary('Morning strength', DateTime(2026, 7, 18, 8)),
        _summary('Easy movement', DateTime(2026, 7, 17, 17)),
      ],
    );

    await expectLater(
      find.byType(HealthIntegrationsScreen),
      matchesGoldenFile('goldens/health_integrations_connected.png'),
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeGateway gateway,
  List<HevyWorkoutSummary> workouts = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hevyIntegrationGatewayProvider.overrideWithValue(gateway),
        importedWorkoutCountProvider.overrideWith(
          (ref) async => workouts.length,
        ),
        recentHevyWorkoutsProvider.overrideWith(
          (ref) => Stream.value(workouts),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const HealthIntegrationsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

HevyWorkoutSummary _summary(String title, DateTime start) => HevyWorkoutSummary(
      id: title,
      title: title,
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
      exerciseCount: 2,
      setCount: 3,
    );

class FakeGateway implements HevyIntegrationGateway {
  bool configured;
  final Object? verifyError;
  final Object? syncError;
  final Completer<void>? syncCompleter;
  final Completer<bool>? initializationCompleter;
  String? savedKey;
  int clearCalls = 0;
  int syncCalls = 0;
  HevySyncMetadataRow? syncMetadata;

  FakeGateway({
    this.configured = false,
    this.verifyError,
    this.syncError,
    this.syncCompleter,
    this.initializationCompleter,
  });

  @override
  Future<void> clearCredential() async {
    clearCalls += 1;
    configured = false;
    savedKey = null;
  }

  @override
  Future<bool> isConfigured() =>
      initializationCompleter?.future ?? Future.value(configured);

  @override
  Future<HevySyncMetadataRow?> metadata() async => syncMetadata;

  @override
  Future<void> saveCredential(String value) async {
    savedKey = value;
  }

  @override
  Future<void> sync() async {
    syncCalls += 1;
    if (syncError != null) throw syncError!;
    await syncCompleter?.future;
  }

  @override
  Future<void> verify() async {
    if (verifyError != null) throw verifyError!;
    configured = true;
  }
}
