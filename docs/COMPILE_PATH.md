# NeuroFlow — Path to First Compile

**Use this with a tool that has real Flutter/Dart execution access** — Claude Code, VS Code with Copilot, or a terminal directly. Nothing in this project has been compiled or run yet; this is the concrete sequence to get there. Every status label below follows spec §16: Proposed / Implemented / **Verified** — nothing is Verified until this sequence actually succeeds.

---

## 0. Get the reconciled repo state — safely, not just cleanly

**Revised process (the direct force-push in an earlier draft of this doc had a real gap — no backup tag, no isolation before validating).** This version fixes both.

```bash
git clone https://github.com/starwolf0007/ADD-Health-Tracking.git repo
cd repo

# Backup FIRST — recoverable regardless of what happens next.
git tag pre-reconciliation-backup origin/main
git push origin pre-reconciliation-backup

# Validate in isolation — don't touch main until the toolchain says it's clean.
git checkout -b reconciliation-validation
git remote add bundle-source /path/to/ADD-Health-Tracking-v1.12.bundle
git fetch bundle-source
git reset --hard bundle-source/main
```

Run the full sequence below (steps 1–5) **on this branch, not on `main`**. Only after `flutter analyze` and `flutter run` both succeed:

```bash
# BEFORE force-pushing, inspect what you're about to lose and gain:
git log --oneline origin/main..reconciliation-validation  # commits you're adding
git log --oneline reconciliation-validation..origin/main  # commits being replaced

# Review both lists. If anything in the "being replaced" list needs to be kept, cherry-pick it now:
git cherry-pick <commit-sha>  # repeat for each commit worth keeping

# Only then proceed with the force-push:
git checkout main
git reset --hard reconciliation-validation
git push origin main --force
```

**Why this matters:** If `origin/main` has recent commits (CI fixes, hotfixes, work from another session), you now have a chance to preserve them before they're abandoned. This adds ~60 seconds of review but prevents losing critical changes.

This is the single reconciled lineage (spec §15) — the parallel `lib/data/` tree, the duplicate `providers.dart`, and everything else found diverged has been resolved into this one tree. Confirm after pushing:

```bash
git log --oneline           # should show one linear history, not two
find lib -name "*.dart" | wc -l
```

## 1. Scaffold the native shells

Never done — the repo has never had `android/`/`ios/` directories generated.

```bash
flutter create . --platforms=android,ios --org com.neuroflow
```

This will NOT overwrite existing `lib/` files (Flutter's create is additive for existing projects), but **check the diff on `pubspec.yaml` before committing** — `flutter create` sometimes touches it.

## 2. Install dependencies

```bash
flutter pub get
```

**Expected friction points, not surprises if they happen:**
- `googleapis_auth`'s `AccessCredentials`/`AccessToken` constructor shape was written from confident-but-unverified knowledge (flagged in `calendar_service.dart`). If this doesn't compile, that's the first place to look.
- `NetworkType.notRequired` vs `NetworkType.not_required` in `background_scheduler.dart` — flagged as an open disagreement between two prior implementations, not resolved. Whichever the installed `workmanager` version actually exports, fix it here.

## 3. Generate Drift code

```bash
dart run build_runner build -d
```

This generates `database.g.dart` from `lib/platform/local/database.dart` (schema v5: Tasks, SyncQueue, DailyStats, Habits, HabitCheckIns). If this fails, the schema itself has a real bug — report the exact error, don't guess a fix blind.

**Verify Drift generated clean — check for warnings:**

```bash
dart run build_runner build -d 2>&1 | grep -i "warning\|error"
```

Drift sometimes generates code that passes the build but warns downstream. Catch and address these now, before step 4.

## 4. Static analysis — the first real signal

```bash
flutter analyze
```

**This is the moment eleven-plus rounds of "written, not compiled" gets tested for real.** Expect some errors — that's normal and fine, not a crisis. Fix them file by file, verify with `flutter analyze` again after each fix rather than batch-guessing multiple fixes at once.

## 5. First run

```bash
flutter run
```

Target: the app launches, shows the Today screen (empty state — "Today's clear" — is a completely valid first result, not a failure), and the capture sheet opens and creates a task.

## 6. What does NOT need to work yet

Don't chase these in pursuit of "first compile" — they're correctly dormant or deferred, not broken:
- Google Tasks/Calendar sync (OAuth not activated — dormant by design, §12.2)
- Health signal fetches (same — dormant until OAuth)
- The Lexi on-device bridge (no stable package exists yet — §14 top build risk, expected gap)
- `TodayContext`/4-element header visual assembly, `HabitsWidget` wired into the screen (state layer + widget exist; integration is the named next step, not part of "does it compile")

---

## Reporting back (per §16 discipline)

When this sequence runs, report status using the three labels, not prose confidence:
- **Verified:** ran the exact command, it succeeded, paste the actual output.
- **Implemented, not yet Verified:** code exists, this step wasn't reached yet.
- If something fails: paste the **actual error text**, not a description of the error. "It didn't compile" is not a status report; the compiler's own output is.

**One distinction worth holding onto:** Copilot's inline diagnostics (real analyzer squiggles) carry the compiler's authority — trust them. Copilot's *generative* suggestions (autocomplete, chat responses proposing code) don't — they're inference, same tier as any chat-based proposal, until something actually compiles them.

**Future step, not blocking this one:** once first compile succeeds, a real pre-commit hook (`dart analyze` before every commit) and eventually CI would make this kind of drift structurally harder to reproduce — worth doing, not worth setting up before there's ever been one successful local compile to protect.
