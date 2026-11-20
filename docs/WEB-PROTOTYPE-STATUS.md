# Web prototype status — October 31, 2026

The current main branch is a React/Vite web prototype with a Node/Express server.
The prior native Flutter source remains in Git history at commit `f0f33e6`.
The following two commits (`a2ffa93` and `4d15e37`) introduced the web replacement.
Do not run Flutter setup over this checkout or treat the old Android tracker as
proof of the web app's readiness. Choosing a long-term daily driver remains an
owner decision; this repair branch stabilizes the existing web implementation.

## Local development

Use Node 24, then run:

```sh
npm ci
npm run lint
npm test
npm run build
npm run dev
```

For production-mode local testing, build first and run `NODE_ENV=production npm start`.
The Node server serves the built assets, SPA routes, HTTP AI endpoints and voice
WebSockets. A static Vite deployment alone does not provide the API server.

## Data boundaries

- Existing unscoped browser data stays in signed-out local mode. It is never
  silently imported into a Google account.
- Each Firebase UID has separate task, note, routine, habit, mood, settings,
  workout and API-key caches. Signing out retains that account's local cache.
  This is application-level separation, not encryption against someone with
  developer access to the same browser profile.
- Only tasks and notes sync to Firestore. Other records remain device-local.
- Local task/note changes enter a persistent per-account outbox. Failed writes
  remain queued for retry. Deletes upload tombstones; remote snapshots exclude
  them. Acknowledgements cannot erase a newer queued revision.
- Offline local edits win over incoming snapshots while pending; concurrent
  edits from different devices use the last server write. There is no conflict
  history. Multiple simultaneous browser tabs are not yet a validated workflow.
- A sync label requires server snapshots for both collections and an empty
  outbox. Signing in alone cannot establish sync success.
- Reset clears only the current local cache, preserving pending uploads.
  It does not delete cloud records. Downloaded data can reappear.
- Google login failures remain visible and do not silently create guest accounts.

## Cloud AI

Cloud Gemini defaults off for each account. Chat, search, Maps, transcription and
voice require explicit consent and a Google-authenticated Firebase user. Enabling
it sends conversation context, user messages and recorded audio to Google; Maps
may also send location. Content typed into a message is not automatically stripped
of health or other private information.

The server fails closed unless all three variables are configured:

- `GEMINI_API_KEY`: server-side Gemini credential.
- `FIREBASE_PROJECT_ID`: must match the client Firebase project.
- `CLOUD_ALLOWED_UIDS`: comma-separated account UIDs permitted to incur AI usage.

No credential belongs in Vite client variables. The server verifies Firebase ID
tokens with the Firebase Admin SDK (signature, expiry, audience and issuer), then
checks the UID allowlist. It does not perform revocation lookups; disable the UID
allowlist entry and restart the server for immediate access removal. Token
verification uses Google's public certificates; no Admin database access is needed.

HTTP AI traffic is limited per UID to 20 requests per minute, with a separate
pre-authentication IP limit of 60 requests per minute. These counters and voice
tickets are in memory: use one Node process. Shared or multi-instance hosting
requires a shared rate-limit store and shared ticket handling before rollout.
Voice uses a one-use, 30-second ticket, same-origin checking, one active session
per UID, bounded frames, a message limit and a five-minute session limit.

Google Tasks, Calendar, Drive, Gmail, Contacts and Health Connect are displayed
as not implemented. Signing in to Firebase does not grant those integrations.
The existing Gemini model names remain unverified against this account's API
access. They must be tested with real credentials before cloud rollout.

## Verification limits

Automated tests exercise account isolation, outbox retries/races, deletion,
server access gates and rate limits. They use local adapters and a fake token
verifier, not a live Firebase project. Passing them is not a claim of validated
Google OAuth, Firestore rules deployment, Gemini availability, microphone support
or Android daily-driver reliability.

The legacy documentation checker already reports 106 missing source paths in
the web replacement baseline. Android CI and the historical native documentation
also need a separate reconciliation. Do not present those checks as passing.

## Repair verification record

Local checks on the repair branch (not live-service validation):

| Command | Exit | Result |
| --- | --- | --- |
| `npm ci --no-audit --no-fund` | 0 | Clean install; manifest and lock agree |
| `npm run lint` | 0 | TypeScript includes browser, server and tests |
| `npm test` | 0 | 21 web regression tests passed; no prior tests removed |
| `npm run build` | 0 | Production bundle built; existing large-bundle warning remains |
| `node scripts/smoke_web_server.mjs` | 0 | Startup, SPA routes, JS asset, all five closed cloud routes, API 404 and unauthenticated voice rejection |
| `python3 -m unittest discover -s scripts/tests` | 0 | All 9 existing Python tests passed |
| `git diff --check` | 0 | No whitespace errors |
| `python3 scripts/check_doc_paths.py` on unchanged base | 1 | 106 pre-existing missing documentation paths |

Live Google OAuth, deployed Firestore rules/two-device sync, Gemini model calls,
real microphone/voice and Android device tests: **Not executed.** The local
runtime has no Gemini key, Firebase server project setting or allowed UID list.

The new web CI runs the build, web tests, production smoke and existing Python
tests. It does not certify the legacy Android or documentation jobs. Existing
native domain/executive code was not modified; the web executive module retains
its existing domain-type and local-storage imports, with no cloud dependency added. AI suggestions still require user confirmation to
modify tasks. No test files were removed.

## Change inventory

Added:

- `.github/workflows/web-ci.yml`
- `docs/WEB-PROTOTYPE-STATUS.md`
- `scripts/smoke_web_server.mjs`
- `server/cloudAccess.ts`
- `src/lib/cloudClient.ts`
- `src/lib/cloudTransport.ts`
- `src/lib/sync.ts`
- `tests/cloud-access.test.ts`
- `tests/cloud-client.test.ts`
- `tests/storage-sync.test.ts`

Modified:

- `README.md`
- `package-lock.json`
- `package.json`
- `server.ts`
- `src/App.tsx`
- `src/components/AppShell.tsx`
- `src/components/LexiChatInterface.tsx`
- `src/lib/firebase.tsx`
- `src/lib/storage.ts`
- `src/lib/useLiveVoice.ts`
- `src/lib/useTranscribe.ts`
- `src/screens/ConnectedServicesScreen.tsx`
- `src/screens/LexiConversationScreen.tsx`
- `src/screens/SettingsScreen.tsx`
- `tsconfig.json`

Removed: no files or existing tests.

API changes: the unused download-only `useFirestoreSync` helper is replaced by
provider-owned account sync; the auth context adds `authError`. All HTTP AI
routes now require a Firebase bearer token and an explicit consent header.
Voice clients obtain a ticket from `POST /api/gemini/live-ticket` before
connecting to the existing WebSocket route. Local storage helpers add account
scoping and outbox operations. No live Firestore rules were changed.

Publication status: changes are committed locally on
`fix/web-build-and-cloud-controls`. Automatic approval review blocked pushing
the branch, citing insufficient authorization for source publication to the
selected remote. The remote was subsequently confirmed to be the same public
owner-administered repository used for the checkout. A pattern check found no
credential files, private keys or common access tokens added. No branch was
found at the remote after the blocked push; no PR, merge or deployment occurred.
