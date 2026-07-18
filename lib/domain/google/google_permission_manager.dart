// lib/domain/google/google_permission_manager.dart

abstract class GooglePermissionManager {
  /// Checks if all the given scopes have been granted.
  Future<bool> hasScopes(List<String> scopes);

  /// Requests the given scopes from the user.
  Future<bool> requestScopes(List<String> scopes);

  /// Standard scopes required by specific services.
  static const tasksScopes = ['https://www.googleapis.com/auth/tasks'];
  static const calendarScopes = [
    'https://www.googleapis.com/auth/calendar.readonly'
  ];
  static const driveScopes = ['https://www.googleapis.com/auth/drive.file'];
}
