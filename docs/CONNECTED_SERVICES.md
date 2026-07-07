# Connected Services — NeuroFlow Settings feature

**Status:** Shipped (Google Foundation Sprint, Stage 6) · **Where:** Settings screen,
"Connected Services" section (`lib/presentation/settings_screen.dart`)
**For architecture/technical detail:** `docs/GOOGLE_ARCHITECTURE.md`. **For how to extend
this:** `docs/GOOGLE_INTEGRATION.md`.

---

## 1. What it is

"Connected Services" is a Settings section with two parts:

1. **Google Account** (`_GoogleAccountTile`/`_GoogleAccountCard`) — the one functional
   piece this sprint. Shows connect/disconnect state and lets the user connect or
   disconnect their Google account. Backed by `googleConnectionStateProvider` and
   `GoogleServiceManager.connect()`/`disconnect()`.
2. **More services** (`_MoreServicesList`/`_ComingSoonServiceTile`) — a list of seven rows,
   one per `GoogleServiceId`: Tasks, Calendar, Drive, Gmail, Contacts, Health Connect,
   Gemini. Every row is inert — a "COMING SOON" badge and a disabled `Switch` — because no
   product integration for any of them exists yet.

### What's functional today

- Connect Google (interactive OAuth sign-in via `google_sign_in`)
- Disconnect (soft — keeps account metadata so reconnecting is one tap)
- Silent session restore on app launch
- Expired-session hint ("Session may need reconnecting") when a live API call would 401
- Tapping a "coming soon" row records that the user tapped it (`lastUsedAt`) — nothing
  else happens

### What's "coming soon" (every row, all inert)

Tasks, Calendar, Drive, Gmail, Contacts, Health Connect, Gemini. None of these has a
product API client — `googleapis` remains an unused dependency (see
`docs/GOOGLE_ARCHITECTURE.md` §7 in the underlying design doc's non-goals). Tapping any of
these rows today does not enable anything, request any permission, or make any network
call.

---

## 2. The `ConnectedService` / `GoogleServiceStatus` model

`lib/domain/google_service.dart` defines:

```dart
enum GoogleServiceId { tasks, calendar, drive, gmail, contacts, healthConnect, gemini }

enum GoogleServiceStatus { comingSoon, available, enabled, disabled }

class ConnectedService {
  final GoogleServiceId id;
  final GoogleServiceStatus status;
  final DateTime? enabledAt;
  final DateTime? lastUsedAt;
}
```

There is always exactly one `ConnectedService` row per `GoogleServiceId` — seeded once by
`DriftConnectedServicesRepository` and re-seeded after any factory reset (`clearAll()`).
Status meanings:

- **`comingSoon`** — visible in Settings, not yet implemented. **Every service is this
  status today** — no exceptions.
- **`available`** — implemented and available, but the user hasn't enabled it. Not used yet.
- **`enabled`** — the user enabled it and its scopes are granted. Not used yet.
- **`disabled`** — the user explicitly turned it off after enabling. Not used yet.

`enabledAt` stays `null` until a future sprint actually flips a service to `enabled`.
`lastUsedAt` is set today, though: tapping a "coming soon" row calls
`GoogleServiceManager.enableService(id)`, which calls
`ConnectedServicesRepository.touchLastUsed(id)` — a timestamp-only "the user tapped this"
signal, useful later for prioritizing which coming-soon service to build first. It
deliberately does **not** call `setStatus()`, because that would fabricate a status change
nothing backs.

There is also deliberately no visible feedback on a coming-soon tap — no snackbar, no
dialog, no toggle animation (the `Switch` is rendered disabled via `onChanged: null` and
wrapped in `IgnorePointer` so the tap passes through to the row instead of being
swallowed). This is an intentional ADHD-friendly UX choice: an action with no real effect
should not manufacture a dead-end feedback loop or a false sense of progress.

---

## 3. Why Health Connect and Gemini are in this list

Health Connect and Gemini both appear as rows in the same "Connected services" list even
though neither is a Google-account/OAuth service the way Tasks/Calendar/Drive/Gmail/Contacts
are:

- **Health Connect** is an on-device Android health-data API with no OAuth scope at all —
  conceptually it doesn't belong in a *Google account* services enum. It's kept as a row
  here because product-wise it's still one line in the same "Connected services" list users
  see, but it will never route through `GooglePermissionManager` or a scope request the way
  the other services will. Whoever eventually wires this up should not try to make it fit
  the `requiredScopes`/`GoogleApiFactory.clientFor` seam — that seam is for OAuth-scoped
  Google APIs, and Health Connect isn't one.
- **Gemini** in this list refers to the cloud Gemini API opt-in surfaced elsewhere in
  Settings (task-suggestion AI, a separate consent flow) — it's listed here as a
  placeholder for future consolidation, not because it currently goes through
  `GoogleServiceManager`.

Both are flagged as inert `comingSoon` rows today, identically to the five real
OAuth-scoped services, and both are safe to leave exactly as-is until someone actually
builds their integration.

---

## 4. For whoever ships the first real integration

When a future sprint ships the first real product client (most likely Google Tasks — see
`docs/GOOGLE_INTEGRATION.md` §1 for the full walkthrough), the status transitions that
become meaningful are:

```
comingSoon → available   (the integration ships in code, but the user hasn't turned it on)
available  → enabled     (the user turns it on; scopes requested and granted)
enabled    → disabled    (the user turns it back off)
```

Concretely, at that point:

- `GoogleServiceManager.enableService()` must **stop being a hardcoded no-op that always
  returns `false`.** It needs to actually call `GooglePermissionManager.ensureScopes()`
  (or the manager's equivalent) for that service's required scopes, and on success call
  `ConnectedServicesRepository.setStatus(id, GoogleServiceStatus.enabled)` — not just
  `touchLastUsed()`.
- The Settings UI's disabled `Switch`/`IgnorePointer` treatment for that one row needs to
  become a real, tappable toggle, while every other still-`comingSoon` row keeps its
  current inert rendering.
- Health Connect and Gemini (§3) should stay out of this OAuth-scoped transition path even
  after other services graduate — they need their own status-transition story, not this
  one.

Nothing about the shipped `ConnectedService`/`GoogleServiceStatus` model needs to change to
support this — the enum values, the Drift table, and the seeding logic already anticipate
it. The work is entirely in `GoogleServiceManager.enableService()` and the Settings widget
that currently hardcodes every row as inert.
