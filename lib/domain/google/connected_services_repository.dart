// lib/domain/google/connected_services_repository.dart

enum GoogleService {
  tasks,
  calendar,
  drive,
  healthConnect,
  gmail,
  contacts,
  gemini,
}

abstract class ConnectedServicesRepository {
  /// Stream of enabled services.
  Stream<Set<GoogleService>> get enabledServices;

  /// Returns whether a specific service is enabled.
  Future<bool> isServiceEnabled(GoogleService service);

  /// Enables or disables a specific service.
  Future<void> setServiceEnabled(GoogleService service, bool enabled);
}
