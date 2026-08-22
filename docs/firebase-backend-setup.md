# NeuroFlow Firebase backend setup

Project: `neuroflow-1e7cd`
Android package: `com.neuroflow`

NeuroFlow remains local-first: Drift is the on-device source of truth. Firebase Authentication provides cloud identity and Firestore is the authenticated remote mirror/backend for cross-device data.

## 1. Android app registration

In Firebase Console > Project settings > General, confirm an Android app exists with package name `com.neuroflow`.

The GitHub test-build workflow already restores `android/app/google-services.json` from the `GOOGLE_SERVICES_JSON` repository secret. Do not commit that file.

For Google Sign-In and Phone Authentication on Firebase-distributed test APKs, add the SHA-1 and SHA-256 fingerprints of the stable `neuroflow-test.jks` signing certificate to the Android app in Firebase Project settings. Use the same permanent test keystore used by GitHub Actions; do not generate another signing key.

Example read-only fingerprint command when the keystore is available locally:

```bash
keytool -list -v -keystore neuroflow-test.jks -alias neuroflow-test
```

Enter the keystore password only into the local terminal prompt. Never paste it into chat, source control, or documentation.

After changing certificate fingerprints, download a fresh `google-services.json` and replace the `GOOGLE_SERVICES_JSON` GitHub Actions secret with the complete new file contents.

## 2. Authentication providers

Firebase Console > Authentication > Sign-in method:

- Enable **Email/Password**.
- Enable **Google** and select the project support email.
- Enable **Phone**.

Phone Authentication sends user-provided phone numbers to Google for spam and abuse prevention. The UI must disclose this appropriately before requesting a number.

For development, configure Firebase Authentication test phone numbers rather than repeatedly sending real SMS messages.

## 3. Cloud Firestore

Create a Cloud Firestore database for `neuroflow-1e7cd` if one does not already exist.

Do not use open test-mode rules for deployed builds. This repository contains `firestore.rules`, which restricts all NeuroFlow cloud data to the authenticated user's own path:

```text
/users/{uid}/...
```

Deploy rules from an authenticated Firebase CLI environment with:

```bash
firebase use neuroflow-1e7cd
firebase deploy --only firestore:rules
```

Review the active project before deploying. This command changes Firestore security rules.

## 4. Flutter plugins

The app uses:

- `firebase_auth`
- `cloud_firestore`
- existing `firebase_core`, `firebase_crashlytics`, and `firebase_analytics`
- existing `google_sign_in` singleton, shared between Google Tasks OAuth and Firebase Google Authentication

After dependency changes, run:

```bash
flutter pub get
flutter analyze
flutter test
```

The next configured Android build should also run through GitHub Actions before merging.

## 5. Cloud data layout

Initial user-scoped layout:

```text
users/{uid}
  tasks/{taskId}
  routines/{routineId}
  dailyStory/{eventId}
```

No mood notes, health values, authentication tokens, Google OAuth tokens, or other sensitive integration credentials should be mirrored by default.

## 6. Architecture boundary

- Drift remains authoritative for immediate local UX and offline operation.
- Firestore writes are explicit until a tested reconciliation/sync engine is added.
- Firebase sign-out does not automatically disconnect the separate Google Tasks integration.
- Cross-device conflict resolution must be defined before automatic two-way sync is enabled.
