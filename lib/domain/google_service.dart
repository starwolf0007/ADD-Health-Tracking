// lib/domain/google_service.dart
//
// Pure Dart — no Flutter, no Drift, no plugin imports.
//
// SCOPE NOTE (Google Foundation Sprint, Stages 4-5): only GoogleServiceId
// ships in this task. The full ConnectedService / GoogleServiceStatus domain
// described in STAGE2_COMPONENT_DESIGN.md §2.8 belongs to
// ConnectedServicesRepository, which is a separate, parallel task this
// sprint (not built here — see DECISIONS.md). GoogleServiceId itself has no
// dependency on that repository; it is used today only as
// GoogleApiFactory's client-cache key and GoogleServiceIntegration's
// registration key.

/// The Google services NeuroFlow knows about. Order = future Settings
/// display order. No product client exists for any of these yet — see
/// STAGE2_COMPONENT_DESIGN.md §7 non-goals.
enum GoogleServiceId { tasks, calendar, drive, gmail, contacts, healthConnect, gemini }
