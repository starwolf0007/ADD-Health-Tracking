# Codespace-based test build pipeline

Goal: manual-trigger CI build → signed test APK → Firebase App Distribution →
install on a test device, with no local Flutter toolchain required after this
one-time setup.

The repo-side pieces (`android/app/build.gradle.kts` signing config,
`.gitignore` entries, `.github/workflows/test-build.yml`) are already in this
repository. Everything below is one-time setup the repo owner runs locally —
generating and storing a real signing key, and provisioning GitHub/Firebase/GCP
secrets — which is deliberately not something an agent session performs
unattended: the keystore is permanent (losing it means no future
update-compatible build, ever), and the secrets grant write access to CI and
IAM.

Run steps 1–4 in a GitHub Codespace (or any machine with `keytool`, `gh`, and
`gcloud`) on this repo.

## 1. Generate the stable test keystore

Use one password for both store and key, and avoid it landing in shell
history or process listings:

```bash
read -s -p "Enter a new strong password (won't echo): " KEYSTORE_PASS
echo
keytool -genkeypair -v \
  -keystore neuroflow-test.jks \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias neuroflow-test \
  -storepass:env KEYSTORE_PASS \
  -keypass:env KEYSTORE_PASS \
  -dname "CN=NeuroFlow Test, OU=Personal, O=Bryan, L=Oakland, ST=CA, C=US"
```

Back up `neuroflow-test.jks` itself now — a base64 blob in a password manager
or encrypted note, not just the password. GitHub Secrets are write-only; if
the file is lost, no future update-compatible build can ever be produced:

```bash
base64 -w 0 neuroflow-test.jks | pbcopy 2>/dev/null || base64 -w 0 neuroflow-test.jks
# paste that output into your password manager as "NeuroFlow test keystore (base64)"
```

## 2. Push the keystore + password to GitHub Secrets

```bash
base64 -w 0 neuroflow-test.jks > neuroflow-test.jks.b64
gh secret set TEST_KEYSTORE_BASE64 < neuroflow-test.jks.b64
gh secret set TEST_KEYSTORE_PASSWORD < <(printf '%s' "$KEYSTORE_PASS")
gh secret set TEST_KEY_ALIAS -b "neuroflow-test"

rm neuroflow-test.jks.b64          # keep neuroflow-test.jks locally until the backup is confirmed
unset KEYSTORE_PASS
```

Only delete the local `neuroflow-test.jks` after confirming the base64 backup
actually landed somewhere durable.

## 3. One-time Firebase App Distribution setup

Browser (once):

- Firebase console → Project Settings → confirm the `com.neuroflow` Android
  app exists under the target Firebase project.
- Enable App Distribution for that app if not already on.
- App Distribution → Testers & Groups → create a group named `testers` and
  add your own Google account. Groups don't auto-create on upload.

Terminal (`gcloud` CLI):

```bash
gcloud config set project <your-firebase-project-id>

gcloud iam service-accounts create neuroflow-ci-distribute \
  --display-name="NeuroFlow CI App Distribution"

gcloud projects add-iam-policy-binding <your-firebase-project-id> \
  --member="serviceAccount:neuroflow-ci-distribute@<your-firebase-project-id>.iam.gserviceaccount.com" \
  --role="roles/firebaseappdistro.admin"

gcloud iam service-accounts keys create firebase-ci-key.json \
  --iam-account=neuroflow-ci-distribute@<your-firebase-project-id>.iam.gserviceaccount.com

gh secret set FIREBASE_SERVICE_ACCOUNT_JSON < firebase-ci-key.json
rm firebase-ci-key.json
```

Get the Firebase App ID from Firebase console → Project Settings → General →
your Android app (format `1:XXXXXXXX:android:XXXXXXXXXXXX`):

```bash
gh secret set FIREBASE_APP_ID -b "1:XXXXXXXX:android:XXXXXXXXXXXX"
```

On the test device (once): accept the App Distribution tester email/invite
when it first arrives so future builds show up automatically.

## 4. First run

```bash
gh workflow run test-build.yml
gh run watch
```

Expect the first install on a device that already has NeuroFlow installed
under a different signing key (e.g. a prior debug-signed build) to require an
uninstall first — Android treats different signing keys as different apps for
update purposes, and this loses local Drift data on that device. Every build
after that upgrades cleanly since the signing key stays constant.

## Known gaps

- No build-info screen in-app yet showing the injected `BUILD_COMMIT` /
  `BUILD_DATE` — they're in the binary via `--dart-define` but nothing reads
  them yet.
- Single `testers` group in Firebase — must be created manually before the
  first upload (see step 3).
- `main`-only trigger, no arbitrary-ref input — deliberate, keeps the
  pipeline simple while secrets are involved.
- Firebase upload uses the third-party `wzieba/Firebase-Distribution-Github-Action`,
  which receives the service-account JSON. Swap for the official
  `firebase-tools` CLI (`firebase appdistribution:distribute <apk> --app
  <FIREBASE_APP_ID> --groups testers` with `GOOGLE_APPLICATION_CREDENTIALS`
  pointed at the decoded service-account JSON) if avoiding a third-party
  Action is preferred — same trust boundary, one less external dependency.
