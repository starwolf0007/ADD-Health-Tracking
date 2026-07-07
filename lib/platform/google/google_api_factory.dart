// lib/platform/google/google_api_factory.dart

import 'package:googleapis/tasks/v1.dart';
import 'package:googleapis/calendar/v3.dart';
import 'package:googleapis/drive/v3.dart';
import 'package:neuroflow/domain/google/google_permission_manager.dart';
import 'package:neuroflow/platform/google/google_service_manager.dart';

class GoogleApiFactory {
  final GoogleServiceManager _manager;

  GoogleApiFactory(this._manager);

  Future<TasksApi?> createTasksApi() async {
    final client = await _manager.getAuthenticatedClient(GooglePermissionManager.tasksScopes);
    if (client == null) return null;
    return TasksApi(client);
  }

  Future<CalendarApi?> createCalendarApi() async {
    final client = await _manager.getAuthenticatedClient(GooglePermissionManager.calendarScopes);
    if (client == null) return null;
    return CalendarApi(client);
  }

  Future<DriveApi?> createDriveApi() async {
    final client = await _manager.getAuthenticatedClient(GooglePermissionManager.driveScopes);
    if (client == null) return null;
    return DriveApi(client);
  }
}
