// lib/domain/enum_codec.dart
//
// Pure-Dart helpers for persisting enums as their `name` strings.
//
// Every enum in this app is stored in Drift (and mirrored to Google) using
// the enum value's `name` — e.g. TaskStatus.completed <-> 'completed'. Encoding
// is therefore just `value.name`; decoding needs a fallback for unknown/legacy
// strings, which this helper provides.

/// Returns the [T] whose `name` equals [name], or [fallback] when no value
/// matches (e.g. an unrecognised or legacy persisted string).
///
/// Encoding is intentionally omitted — use `value.name` directly.
T enumFromName<T extends Enum>(
  Iterable<T> values,
  String name, {
  required T fallback,
}) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
