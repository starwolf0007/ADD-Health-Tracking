// lib/domain/date_utils.dart
//
// Pure-Dart calendar-day helpers. Check-ins, streaks, daily resets and the
// "completed today" count all reason about local calendar days rather than
// instants, so they share these helpers instead of re-deriving midnight math.

/// Midnight (local time) of [dt] — strips the time-of-day component.
DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Midnight (local time) of the current day.
DateTime today() => dateOnly(DateTime.now());

/// Whether [a] and [b] fall on the same local calendar day.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
