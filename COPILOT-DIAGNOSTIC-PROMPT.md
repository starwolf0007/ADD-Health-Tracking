You are diagnosing a Flutter/Dart project (NeuroFlow) that has never been
compiled. Your job right now is DIAGNOSIS ONLY — do not rewrite files, do not
"helpfully" restructure anything, do not guess at fixes before you have real
compiler output. Report back what is actually broken, with exact error text.

Run these commands IN ORDER and paste the full output of each one before
moving to the next. Do not skip a step even if an earlier one looks clean.

1. flutter doctor -v
   (Confirm the toolchain itself is sane before touching the project.)

2. flutter pub get
   (Dependency resolution. If this fails, STOP and report the exact error —
   don't touch pubspec.yaml until we see what it says.)

3. dart run build_runner build --delete-conflicting-outputs
   (This generates lib/data/database.g.dart. Expect this to take a minute.
   If it fails, paste the FULL error, not a summary — Drift codegen errors
   usually point at one exact table/column.)

4. flutter analyze
   (Report the full list of errors, not just the count. Group them by file.)

For each error `flutter analyze` reports, tell me:
   - the exact file and line number
   - the exact error text
   - your one-sentence read on the likely cause (import mismatch, missing
     generated code, null-safety issue, deprecated API, etc.)

Do NOT fix anything yet. Do NOT skip errors that "look minor." Do NOT
consolidate multiple distinct errors into one guess. If you're not sure why
an error is happening, say so explicitly rather than proposing a fix that
might be wrong — a wrong guess here costs more time than an honest "not sure."

After all four steps, give me:
   - PASS/FAIL for each step
   - the full, unedited error list from step 4
   - which errors you're confident about the fix for, and which you're not

Then stop and wait. We'll decide the fix order together once we know what's
actually broken — not before.
