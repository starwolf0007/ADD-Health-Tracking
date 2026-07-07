# NeuroFlow — Google Cloud Setup Checklist

To enable Google integrations in development and production, follow these steps in the Google Cloud Console.

## 1. Create a Google Cloud Project
- [ ] Go to [Google Cloud Console](https://console.cloud.google.com/).
- [ ] Create a new project: `NeuroFlow`.

## 2. Configure OAuth Consent Screen
- [ ] Go to **APIs & Services > OAuth consent screen**.
- [ ] User Type: **External**.
- [ ] App Name: `NeuroFlow`.
- [ ] User support email: (Your Email).
- [ ] Scopes: Add `openid`, `https://www.googleapis.com/auth/userinfo.email`, `https://www.googleapis.com/auth/userinfo.profile`.
- [ ] Test users: Add your developer email.

## 3. Enable APIs
Enable the following APIs for future sprints:
- [ ] **Google Tasks API**
- [ ] **Google Calendar API**
- [ ] **Google Drive API**
- [ ] **Health Connect API** (Android-specific)

## 4. Create Android OAuth Client
- [ ] Go to **APIs & Services > Credentials**.
- [ ] Click **Create Credentials > OAuth client ID**.
- [ ] Application type: **Android**.
- [ ] Name: `NeuroFlow Android (Debug)`.
- [ ] Package name: `com.example.neuroflow` (Verify in `android/app/build.gradle`).
- [ ] **SHA-1 certificate fingerprint**:
    - Run: `./gradlew signingReport` in the `android/` directory.
    - Copy the SHA-1 from the `debug` variant.

## 5. Security & Signing (Production)
- [ ] Create a separate OAuth client for the **Release** SHA-1.
- [ ] If using **Google Play App Signing**, get the SHA-1 from the Play Console (Setup > App integrity).
- [ ] **SHA-256**: While SHA-1 is used for OAuth identification, keep the SHA-256 handy for Firebase/App Links.

## 6. Local Configuration
- [ ] Do **NOT** hardcode `clientId` in Dart. The `google_sign_in` plugin handles this automatically on Android if the `google-services.json` is present or if the package name/SHA-1 matches.
- [ ] Download `google-services.json` from Firebase (if using Firebase) and place it in `android/app/`.
