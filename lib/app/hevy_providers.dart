import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:neuroflow/app/database_providers.dart';
import 'package:neuroflow/app/hevy_integration_controller.dart';
import 'package:neuroflow/data/database.dart';
import 'package:neuroflow/data/hevy_repository.dart';
import 'package:neuroflow/platform/hevy/hevy_api_client.dart';
import 'package:neuroflow/platform/hevy/hevy_credentials_store.dart';
import 'package:neuroflow/platform/hevy/hevy_sync_service.dart';

final hevyCredentialsStoreProvider = Provider<HevyCredentialsStore>((ref) {
  return const HevyCredentialsStore(FlutterSecureStorage());
});

final hevyHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final hevyApiClientProvider = Provider<HevyApiClient>((ref) {
  return HevyApiClient(
    httpClient: ref.watch(hevyHttpClientProvider),
    credentials: ref.watch(hevyCredentialsStoreProvider),
  );
});

final hevyRepositoryProvider = Provider<HevyRepository>((ref) {
  return HevyRepository(ref.watch(databaseProvider));
});

final hevySyncServiceProvider = Provider<HevySyncService>((ref) {
  final repository = ref.watch(hevyRepositoryProvider);
  return HevySyncService(
    api: ref.watch(hevyApiClientProvider),
    sink: repository,
    metadata: repository,
  );
});

final hevyIntegrationGatewayProvider = Provider<HevyIntegrationGateway>((ref) {
  return _LiveHevyIntegrationGateway(
    credentials: ref.watch(hevyCredentialsStoreProvider),
    api: ref.watch(hevyApiClientProvider),
    repository: ref.watch(hevyRepositoryProvider),
    syncService: ref.watch(hevySyncServiceProvider),
  );
});

final importedWorkoutCountProvider = FutureProvider<int>((ref) {
  return ref.watch(hevyRepositoryProvider).watchImportedWorkoutCount().first;
});

final recentHevyWorkoutsProvider = StreamProvider<List<HevyWorkoutSummary>>((
  ref,
) {
  return ref.watch(hevyRepositoryProvider).watchRecentWorkouts();
});

final hevyIntegrationControllerProvider =
    AsyncNotifierProvider<HevyIntegrationController, HevyIntegrationState>(
  () => HevyIntegrationController(
    hevyIntegrationGatewayProvider,
    importedWorkoutCountProvider,
  ),
);

class _LiveHevyIntegrationGateway implements HevyIntegrationGateway {
  final HevyCredentialsStore credentials;
  final HevyApiClient api;
  final HevyRepository repository;
  final HevySyncService syncService;

  const _LiveHevyIntegrationGateway({
    required this.credentials,
    required this.api,
    required this.repository,
    required this.syncService,
  });

  @override
  Future<void> clearCredential() => credentials.clear();

  @override
  Future<bool> isConfigured() => credentials.isConfigured;

  @override
  Future<HevySyncMetadataRow?> metadata() => repository.getSyncMetadata();

  @override
  Future<void> saveCredential(String value) => credentials.saveApiKey(value);

  @override
  Future<void> sync() => syncService.importAll();

  @override
  Future<void> verify() => api.verifyConnection();
}
