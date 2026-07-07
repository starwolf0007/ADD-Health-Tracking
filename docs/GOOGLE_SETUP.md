# Google Cloud Setup — NeuroFlow (Android)

**Sprint:** Google Foundation Sprint, Stage 3 (preparation docs only — no credentials in this repo, ever).
**Applies to:** `google_sign_in ^6.2.1` + `googleapis ^13.1.0` on Android (reference platform).

> **Golden rule:** No client secrets, no `google-services.json`, no keystores, no
> `key.properties` in source control. All of these are gitignored (see repo `.gitignore`).
> Runtime tokens live only in `FlutterSecureStorage` (`flutter_secure_storage ^9.2.1`).

---

## 0. Repo facts you need before starting

| Fact | Value | Source |
|---|---|---|
| Intended Android package / applicationId | `com.neuroflow` | `android/app/src/main/kotlin/com/neuroflow/MainActivity.kt` (`package com.neuroflow`) |
| Native shell status | **Not yet scaffolded** — `android/app/build.gradle` does not exist yet | `COMPILE_PATH.md` §1 (`flutter create . --platforms=android,ios --org com.neuroflow`) |
| Sign-in plugin | `google_sign_in: ^6.2.1` | `pubspec.yaml` |
| API client | `googleapis: ^13.1.0` | `pubspec.yaml` |
| Token storage | `flutter_secure_storage: ^9.2.1` | `pubspec.yaml` |

**⚠️ applicationId caveats — resolve before creating the OAuth client:**

1. There is no `build.gradle` yet, so the applicationId is *intended*, not compiled-in.
   After running the scaffold step, **verify** the real value:
   ```bash
   grep -n "applicationId" android/app/build.gradle
   ```
   Note: `flutter create . --org com.neuroflow` with project name `neuroflow` will
   generate `applicationId "com.neuroflow.neuroflow"` by default. The committed
   `MainActivity.kt` lives at `kotlin/com/neuroflow/` with `package com.neuroflow`,
   which is the intended identity — after scaffolding, edit `build.gradle`
   (`applicationId` + `namespace`) down to `com.neuroflow` so it matches, or move
   MainActivity. **Whatever ends up in `build.gradle` is what you register with Google.**
2. Known repo inconsistency: `docs/android_setup_snippets.md` and
   `android/app/src/main/kotlin/dev/neuroflow/` (AlarmBridge, WearBridge) use
   `dev.neuroflow`. The active `MainActivity.kt` uses `com.neuroflow`. One package
   must win before OAuth registration; this doc assumes **`com.neuroflow`**.

---

## 1. Create the Google Cloud project

- [ ] Go to <https://console.cloud.google.com/> signed in with the account that will own the project long-term (prefer a dedicated dev account or org account over a personal one — project ownership transfer is painful).
- [ ] Create a new project:
  - **Name:** `neuroflow-dev` (suggestion; create a separate `neuroflow-prod` later — keeps test users, quotas, and verification status isolated).
  - **Project ID:** accept the generated one or set e.g. `neuroflow-dev-<suffix>`; it is immutable after creation.
  - **Organization:** if you have a Google Workspace org, put the project under it (enables "Internal" consent screens and centralized IAM). With a plain Gmail account there is no org — that forces the consent screen user type to **External** (see §2).
- [ ] Note the **Project ID** and **Project Number** (Console → Dashboard) — you'll want them in the placeholders table (§7).
- [ ] Enable APIs (Console → APIs & Services → Library). For **this sprint, none are strictly required** for bare sign-in, but enable now to avoid a second trip:
  - [ ] **Google Tasks API** (future sprint — sync)
  - [ ] **Google Calendar API** (future sprint — sync)

## 2. OAuth consent screen

Console → APIs & Services → OAuth consent screen.

- [ ] **User type:** `External` (required unless the project is in a Workspace org and the app is org-internal only — NeuroFlow is a consumer app, so External).
- [ ] **App name:** `NeuroFlow`
- [ ] **User support email:** your dev address (e.g. `starwolf0007@gmail.com`).
- [ ] **Developer contact email:** same.
- [ ] Logo: skip for now — uploading a logo can trigger the verification requirement earlier than you want.
- [ ] **Scopes — this sprint, declare ONLY the sign-in basics:**
  - [ ] `openid`
  - [ ] `.../auth/userinfo.email` (`email`)
  - [ ] `.../auth/userinfo.profile` (`profile`)

  These three are **non-sensitive**; the app works unverified with them (users just see the "unverified app" screen).

  **Do NOT add yet** (future sprints — added here, on this same consent screen, when sync ships):
  - `https://www.googleapis.com/auth/tasks` (Google Tasks sync sprint) — *sensitive scope*
  - `https://www.googleapis.com/auth/calendar.readonly` or `.../calendar.events` (Calendar sprint) — *sensitive/restricted-adjacent*

  Adding those later will require Google's app verification (privacy policy URL, scope justification video, days-to-weeks review). Keep this sprint's footprint to openid/email/profile so nothing blocks development.
- [ ] **Publishing status:** leave in `Testing`.
  - [ ] Add **test users** (up to 100): every Google account that will sign in during development, including `starwolf0007@gmail.com`.
  - In Testing mode, refresh behavior differs: **refresh tokens expire after 7 days** for external testing apps. Expect periodic re-consent until the app is published/verified — do not "fix" this in code.
- [ ] Later (pre-launch, not this sprint): publish to Production + submit for verification once product scopes are added.

## 3. Android OAuth client ID

Console → APIs & Services → Credentials → **Create credentials → OAuth client ID → Android**.

You will create **one Android client per (package name, signing certificate) pair** — see the matrix in §4. Start with debug:

- [ ] **Package name:** `com.neuroflow` — must match `applicationId` in `android/app/build.gradle` **exactly** (verify per §0; if the scaffold produced `com.neuroflow.neuroflow` and you didn't change it, register that instead).
- [ ] **SHA-1 fingerprint** of the signing certificate.

### Getting the fingerprints

**Debug keystore** (auto-generated by the Android SDK at first build):

```bash
keytool -list -v \
  -keystore ~/.android/debug.keystore \
  -alias androiddebugkey \
  -storepass android -keypass android
```

**Release/upload keystore** (create one when you first need release builds; keep it OUT of the repo — `*.jks` / `*.keystore` / `key.properties` are gitignored):

```bash
keytool -list -v \
  -keystore /path/to/neuroflow-upload.jks \
  -alias upload
# prompts for the store password — never write it into any tracked file
```

**Or let Gradle print everything at once** (works after the native shell is scaffolded; shows SHA-1 and SHA-256 for every configured variant):

```bash
cd android && ./gradlew signingReport
```

- [ ] Create **Android client — debug**: package `com.neuroflow` + debug SHA-1.
- [ ] Create **Android client — upload/release**: package `com.neuroflow` + upload keystore SHA-1 (when the upload keystore exists).
- [ ] Register the **SHA-256** values too where prompted (Play/Firebase use SHA-256 for App Links and integrity; OAuth client creation asks for SHA-1 but keep both on file in the placeholders table §7).

> `google_sign_in` on Android does **not** need the Android client ID passed in code —
> Google Play services matches your app by package name + signing SHA at runtime.
> If you later need a `serverClientId` (for backend token exchange / `idToken`
> audience), that is a separate **Web application** client ID, not the Android one.

## 4. Google Play App Signing — the three-certificate matrix

When you enroll in **Play App Signing** (default and effectively mandatory for new apps), Google **re-signs** the app you upload with a Google-held key. The APK your users actually install is therefore signed by a certificate **you never touch locally** — and OAuth matches on the certificate of the *installed* APK.

| Build / channel | Signed by | SHA source | Needs its own Android OAuth client? |
|---|---|---|---|
| Local debug builds (`flutter run`) | Debug keystore (`~/.android/debug.keystore`) | `keytool` / `signingReport` | ✅ Yes |
| Local release builds, and the AAB you upload | Upload keystore (`neuroflow-upload.jks`) | `keytool` / `signingReport` | ✅ Yes (useful for sideloaded release testing) |
| Anything installed **from Google Play** (internal testing track included!) | **Play App Signing key** (Google-held) | Play Console → **Test and release → Setup → App integrity → App signing key certificate** | ✅ Yes — **this is the one people forget** |

- [ ] After the first Play upload, copy the **App signing key certificate** SHA-1/SHA-256 from Play Console → App integrity.
- [ ] Create a **third** Android OAuth client: package `com.neuroflow` + Play signing SHA-1.
- [ ] Symptom of forgetting this: sign-in works in local builds but every Play-installed build fails with `ApiException: 10` (§8).

All three clients live in the same Cloud project and the same consent screen — multiple Android clients with the same package but different SHAs is the expected, supported setup.

## 5. Redirect URIs / custom schemes — why Android needs none

On Android, `google_sign_in ^6.2.1` delegates to the **Google Play services native sign-in flow**. Identity is proven by the OS: Play services verifies the calling app's package name + signing certificate against the registered Android OAuth clients and returns tokens directly to the app. There is **no browser redirect**, therefore:

- [ ] Confirm: **no redirect URI to configure, no custom URL scheme, no manifest intent-filter** for sign-in on Android. Nothing to add to `AndroidManifest.xml` for this sprint.

For contrast (future sprints, do not do now):
- **iOS:** requires an iOS OAuth client and a **reversed client ID URL scheme** in `Info.plist` (e.g. `com.googleusercontent.apps.123-abc`).
- **Web:** requires a Web client with explicit **Authorized JavaScript origins** and **redirect URIs**.

## 6. `google-services.json`

Strictly speaking, plain `google_sign_in` works **without** `google-services.json` (it's the Firebase config file). If/when the project adds Firebase or you follow Google's standard setup path:

- [ ] Download it from the Cloud/Firebase console for package `com.neuroflow`.
- [ ] Place it at **`android/app/google-services.json`** (exactly there — the Gradle plugin looks for it in the app module).
- [ ] It is **gitignored** (see `.gitignore`: `**/android/app/google-services.json`). Never commit it; it embeds your client IDs and project identifiers.
- [ ] For onboarding without secrets, a placeholder with obviously fake values lives at **`docs/google-services.json.example`**. Copy it and replace every `REPLACE_ME_*` value with the real download — or better, just download the real file from the console.
- [ ] Each engineer/CI environment obtains its own copy from the console (or from a secret manager for CI) — the file is per-project config, not per-developer, but it must travel outside git.

## 7. Configuration placeholders — the complete list

| Value | Placeholder name | Where it lives | Committed? |
|---|---|---|---|
| GCP Project ID | `NEUROFLOW_GCP_PROJECT_ID` | Console / team password manager | ❌ Never |
| GCP Project Number | `NEUROFLOW_GCP_PROJECT_NUMBER` | Console / team password manager | ❌ Never |
| Android OAuth client ID (debug) | `NEUROFLOW_ANDROID_CLIENT_ID_DEBUG` | Cloud Console only — **not referenced in code** (Play services resolves by package+SHA) | ❌ Never |
| Android OAuth client ID (upload) | `NEUROFLOW_ANDROID_CLIENT_ID_UPLOAD` | Cloud Console only | ❌ Never |
| Android OAuth client ID (Play signing) | `NEUROFLOW_ANDROID_CLIENT_ID_PLAY` | Cloud Console only | ❌ Never |
| Web/server client ID (future `serverClientId`) | `NEUROFLOW_WEB_CLIENT_ID` | Build-time injection (`--dart-define=NEUROFLOW_WEB_CLIENT_ID=...`) when needed | ❌ Never hardcoded |
| `google-services.json` | n/a (whole file) | `android/app/google-services.json`, gitignored; example at `docs/google-services.json.example` | ❌ Never |
| Upload keystore + passwords | `neuroflow-upload.jks`, `android/key.properties` | Local disk / secret manager; both gitignored | ❌ Never |
| OAuth access/refresh tokens (runtime) | n/a | **`FlutterSecureStorage` only** — never SharedPreferences, never logs, never Drift DB | ❌ Never |

**Policy, stated once and bindingly:** no client ID, secret, keystore, password, or token appears in Dart, Kotlin, Gradle files, or any committed file. Client IDs that must reach the app at runtime are injected via `--dart-define`; everything user-specific lives in `FlutterSecureStorage`.

## 8. Troubleshooting

| Symptom | Meaning | Fix |
|---|---|---|
| `PlatformException` / `ApiException: 10` (`DEVELOPER_ERROR`) | **SHA/package mismatch** — the certificate that signed the running APK (or its package name) has no matching Android OAuth client | Run `./gradlew signingReport`, compare the SHA-1 of the *variant you actually launched* against Cloud Console clients. Play-installed build? You forgot the Play App Signing SHA (§4). Also re-check the applicationId really is `com.neuroflow` (§0 caveat). Changes can take a few minutes to propagate. |
| `ApiException: 12501` (`SIGN_IN_CANCELLED`) | User dismissed the account picker — **or** it was auto-dismissed, which is frequently a disguised config error | If the user genuinely cancelled: not an error, handle silently. If it fires instantly with no picker shown: treat as error 10 and audit SHAs/consent screen; also confirm the signing account is listed as a **test user** (§2) while in Testing mode. |
| `ApiException: 7` (`NETWORK_ERROR`) | Device can't reach Google | Check connectivity/emulator DNS; verify the emulator image includes **Google Play services** (use a "Google Play" system image, not AOSP); retry with backoff. |
| Works in debug, fails in release | Different keystore → different SHA | Register the upload keystore SHA (§3) — and the Play signing SHA for store installs (§4). |
| Refresh token dies after 7 days | Consent screen still in `Testing` with External user type | Expected. Re-consent during dev; goes away after publishing/verification. |

---

### Sprint exit checklist

- [ ] Cloud project created, Project ID recorded (outside git)
- [ ] Consent screen: External, Testing, scopes = openid/email/profile only, test users added
- [ ] Android OAuth client (debug SHA) created for the **verified** applicationId
- [ ] `.gitignore` covers `google-services.json`, `*.jks`, `*.keystore`, `key.properties` ✅ (done in this sprint)
- [ ] No credential of any kind committed — `git grep -i "apps.googleusercontent.com"` returns nothing outside docs examples
