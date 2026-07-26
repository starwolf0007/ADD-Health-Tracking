# NeuroFlow — Calendar-Aware Routines (Scoping Doc)

**Status:** Design scope, not yet built. The weekday rule (below, Tier 0) IS built and shipping now. Tiers 1–3 need Google Calendar integration and are sequenced for after the app has a week of real use.

**Bryan's vision:** the app reads his work + personal calendars and adapts — "you have school next week, start packing your bag," "vacation coming, prep your suitcase," "day off, alarms off," "trip planned, start the packing list."

---

## The honest tiering

This breaks into four tiers of increasing lift. Only Tier 0 needs no Google access.

### Tier 0 — Weekday rules ✅ BUILT

No calendar needed — Bryan's Mon–Fri 6 AM shift is fixed and known. Routines now carry an `activeDays` field ("12345" = weekdays). Morning Launch fires Mon–Fri only; no 5 AM alarm on Saturday. **This ships in the current update.**

Covers: the single most common case (weekday-only work routines) with zero integration cost.

### Tier 1 — Read-only calendar awareness (the first real Google step)

**What it unlocks:** "day off → no work alarm," "holiday → alarms off."

**What it needs:**
- `google_sign_in` + `googleapis` (both already in pubspec, unused so far).
- OAuth consent flow — Bryan signs in once, grants **read-only** calendar scope (`calendar.readonly` or the narrower `calendar.events.readonly`).
- A `CalendarService` in `lib/platform/` that fetches today's + upcoming events.
- Logic: if a work-day has an all-day event matching a holiday/PTO pattern ("Vacation", "Day Off", "Holiday", OOO), suppress the Morning Launch alarm for that day.

**The hard parts (from the earlier sync research):**
- OAuth on Android needs a registered app in Google Cloud Console + SHA-1 fingerprint. Bryan provides credentials; they live in `flutter_secure_storage`, never in code.
- Google's OAuth consent screen is in "testing" mode until verified — refresh tokens expire every 7 days in that mode. Fine for personal use; just means periodic re-auth until the app is verified.
- Token refresh + expiry handling must be graceful — never lose the session mid-morning.

**Scope guard:** read-only. The app never writes to Bryan's calendar in this tier.

### Tier 2 — Event-driven prep reminders

**What it unlocks:** "vacation in 3 days → start your suitcase," "school next week → pack your bag," "trip Friday → prep list."

**What it needs (on top of Tier 1):**
- A lightweight **event classifier** — pattern-matches event titles/types to prep templates (travel → packing list; school → bag; appointment → docs). Starts as keyword rules, not AI.
- A **lead-time engine** — "vacation" triggers a prep nudge N days before (N depends on event type: trip = 3 days, school = 1 week).
- Ties into the existing `NotificationService` for the nudge, and could auto-spawn a prep routine or a set of tasks.

**Design note:** this is where it gets genuinely useful and genuinely ADHD-aware — externalizing "you should start preparing" so it doesn't ambush him the night before. But it's meaningfully more logic than Tier 1. Sequence it after Tier 1 proves the calendar read is solid.

### Tier 3 — Lexi-mediated calendar intelligence

**What it unlocks:** the conversational version — "You have nothing scheduled for the next three days and a trip coming up. Good window to knock out tasks A, B, C." (Bryan's original Lexi vision.)

**What it needs (on top of Tier 2):**
- The Gemini advisor (already stubbed via `PlanAdvisor` seam) reads calendar context + task list and reasons about *when* to suggest things.
- This is the payoff tier — it's where the calendar, the tasks, and Lexi's judgment combine. Earned last, because it depends on everything below it working.

---

## Recommended sequence

1. **Tier 0 (weekday rules)** — shipping now. ✅
2. **One week of real use** — confirm the baseline + weekday routines actually help before adding integration surface.
3. **Tier 1 (read-only calendar)** — the OAuth foundation. Get calendar reads working and reliable. This is the big infrastructure step; everything else builds on it.
4. **Tier 2 (prep reminders)** — the event classifier + lead-time nudges. The first "wow" of calendar-awareness.
5. **Tier 3 (Lexi intelligence)** — conversational scheduling, once the data layer is proven.

## What Bryan needs to provide (when we reach Tier 1)

- A Google Cloud project (I'll walk through creating it) with the Calendar API enabled.
- OAuth client credentials for Android (needs the app's SHA-1 — generated from the signing key).
- Consent to the read-only calendar scope on first sign-in.

Nothing before Tier 1 needs any of this. The weekday rule shipping today is pure local logic.

## Design invariants (carry forward)

- **Read-only by default.** The app reads the calendar; it doesn't write to it unless Bryan explicitly asks for a tier that does.
- **Local-first still holds.** Calendar is a *signal source*, not the source of truth. If the calendar fetch fails, routines still fire on their `activeDays` — the app never breaks because Google is down.
- **Alarms-off is a suppression, not a deletion.** A day-off suppresses the alarm for that day; it doesn't disable the routine.
- **Sensitive data stays local.** Calendar *reads* come in; mood/friction data does not go out through this channel.
