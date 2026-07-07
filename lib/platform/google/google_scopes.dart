// lib/platform/google/google_scopes.dart
//
// Canonical OAuth scope constants. Nothing requests these this sprint (see
// STAGE2_COMPONENT_DESIGN.md §7 non-goals) — they exist so future service
// integrations don't need to hunt down scope strings.

class GoogleScopes {
  GoogleScopes._();

  static const tasks = 'https://www.googleapis.com/auth/tasks';
  static const calendarEvents =
      'https://www.googleapis.com/auth/calendar.events';
  static const driveFile = 'https://www.googleapis.com/auth/drive.file';
  static const gmailReadonly =
      'https://www.googleapis.com/auth/gmail.readonly';
  static const contactsReadonly =
      'https://www.googleapis.com/auth/contacts.readonly';
}
