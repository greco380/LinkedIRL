# Linkup — Project Handoff

Last updated: 2026-06-10 (session 5 — pre-alpha review: build + deploy blockers fixed).

This document is the single onboarding page for any agent picking up this project. Read it first, then `prd.md` if you need product depth, then the file you're about to touch. **Mac-side work is tracked separately in `MAC-CHECKLIST.md`** — that's Josh's checklist, not an agent's.

## What was completed in session 5 (2026-06-10 — pre-alpha code review)

- **Build blocker fixed:** `SupabaseClient.swift` and `LocationService.swift` existed on disk but were missing from `project.pbxproj` (file refs + Sources phase) — the app could not compile. Both added; `PrivacyInfo.xcprivacy` added to the Resources phase so it actually ships in the bundle; `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` set on both configs so the icon applies.
- **Deploy blocker fixed:** both Edge Functions routed on the raw `url.pathname`, but Supabase includes the function name as the first path segment (`/linkedin-oauth/presence/upsert`), so every deployed route would 404. Both `backend/linkedin/linkedin-oauth.ts` and `backend/apns/index.ts` now strip `/functions/v1` and the function-name prefix before routing (local `deno run` unchanged). Redeploy both functions.
- **MAC-CHECKLIST step 3** now includes `--no-verify-jwt` on both deploys (it was missing; without it every unauthenticated iOS call gets a 401).
- `LinkedInOAuthConfiguration.load()` now rejects `#######` Info.plist placeholders (previously only `REPLACE_WITH`), so an unconfigured LinkedIn client id surfaces a clear error instead of a broken OAuth page.
- `AppStore.connection(withID:)` now resolves live presences too, so incoming-message notifications and recent-chat rows show real peer names instead of "LinkedIn connection".
- **Real-export validation:** Josh's actual `Connections.csv` (786 rows, UTF-8, "Notes:" preamble, diacritics, quoted commas) was run through a faithful port of the Swift parser: 776 connections import cleanly; the 6 skipped rows are anonymized members with no name/URL (correct); 0 date-parse failures.
- **Backend deployed live (2026-06-11):** migrations 0002→0007 applied via MCP (only 0001 had ever been applied); both Edge Functions deployed with `verify_jwt=false`; `/version` + `/health` smoke tests pass. Still manual: LinkedIn secrets in dashboard, `app.apns_function_url` GUC (MCP role lacks ALTER DATABASE permission).
- **Venue map replaced (2026-06-11):** `VenueMapView`'s synthetic 3×3 hall grid swapped for `ConferenceFloorPlanView` (same file, `DiscoverView.swift` — deliberately NOT a new file to avoid pbxproj edits): a vector recreation of Josh's real conference expo floor plan (5 diagonal-split topic zones, ~35 booth blocks, networking bars / launch pad / cafe / registration / entrance) on a normalized [0,1] grid so connection pins (mapX/mapY) overlay unchanged. Booth numbers intentionally omitted (unreadable at phone scale). Per-event floor plans are a future enhancement — every event currently shows this one layout.

## What was completed in session 4 (2026-06-09 — v1 push)

Backend:
- **Messaging endpoints** in `backend/linkedin/linkedin-oauth.ts`: `POST /messages/send`, `/messages/poll`, `/messages/threads`, `/messages/delete` (single-message OR one-sided thread delete). Build `linkup-linkedin-oauth@2026-06-09-v3`.
- **Account deletion** — `POST /account/delete` deletes every row keyed to the account (chat, presence, observations, connections, profiles, imports, account row) and calls `supabase.auth.admin.deleteUser`. Apple §5.1.1(v).
- **APNs Edge Function** scaffolded at `backend/apns/index.ts` — ES256 JWT signer, HTTP/2 send, `/apns/send` + legacy compat routes, in-memory token cache. Build `linkup-apns@2026-06-09-v1`.
- **Server-side CSV upload** — `POST /linkedin/archive/upload` accepts the raw `Connections.csv` (multipart or text) and reuses the JSON sync pipeline. The Swift parser is the canonical reference; the Deno port matches it test-for-test.
- **LinkedIn picture URL** threaded from OIDC userinfo through `linkup_account.linkedin_picture_url` and back to iOS.
- **Migrations 0003 → 0007**: `chat_message` + RLS, message push trigger (`pg_net` + GUC), Supabase Auth RLS for every table, `linkedin_picture_url` column, `live_presence` lat/lng/accuracy columns with range constraints.

App Store readiness:
- `legal/privacy-policy.md` + `legal/terms-of-service.md` — full drafts, lawyer review required before hosting.
- `Linkup/PrivacyInfo.xcprivacy` — required-reason API declarations + tracking domains stub.
- `Linkup.entitlements` populated (Sign In with Apple, aps-environment = `development`, location).
- `Info.plist` fixes: corrected Edge Function URL key (`LINKUP_API_BASE_URL`), added `SUPABASE_URL` + `SUPABASE_ANON_KEY` placeholders, added `LINKUP_PRIVACY_URL` / `LINKUP_TERMS_URL`, added `NSUserNotificationsUsageDescription`.

iOS:
- **Supabase Auth** replaces the UserDefaults auth path. `Linkup/Services/SupabaseClient.swift` is a singleton wrapper that gracefully nils out until the SPM package is added + the anon key filled. `AuthService.swift` routes email / Apple / Google through `supabase.auth.*` when configured, falls back to local otherwise.
- **CoreLocation** real GPS — `LocationService.swift` publishes `lastLocation`, drops fixes worse than 100 m, adapts cadence on background. Feeds `/presence/upsert` with `latitude/longitude/accuracyMeters`.
- **Real cross-device messaging** — `AppStore.swift` swaps canned replies for `/messages/send` + a 7 s `/messages/poll` loop, with optimistic send + `ChatMessage.SendStatus` (`sending` / `sent` / `failed`).
- **Delete-account** row in Settings (with confirmation alert) wired to `AuthService.deleteAccount` → `requestAccountDeletion` + local wipe.
- **Delete-message** (context menu) + **Delete-chat** (header menu) in `ChatThreadView`, both with confirmation dialogs.
- **LinkedIn profile picture** rendered in ProfileSheet and Settings avatar via `AvatarView`'s new `pictureURL: URL?` parameter and `AsyncImage` fallback to initials.

## Open follow-ups (real work, not just config)

- **SPM dependency Josh adds in Xcode** — `https://github.com/supabase-community/supabase-swift` (Supabase + Auth products, Up to Next Major from 2.0.0). Until added, `SupabaseClient.shared` stays nil and `AuthService` keeps the legacy local-UserDefaults path. See `MAC-CHECKLIST.md` step 1.
- **Real LinkedIn API connection fetch is still gated.** `r_1st_connections` remains unrequested by design. CSV archive is the source of truth for connection lists. Don't try to "improve" the OAuth flow by re-adding the scope.
- **Polling vs WebSocket.** Messaging currently polls every 7 s. Supabase Realtime would be a v1.1 swap; the API surface is already correct for it. See `LinkupBackendService.pollMessages`.
- **Analytics integration** — none today. Add Mixpanel / Amplitude / PostHog post-launch.
- **Push trigger config** — migration 0004 installed the trigger but it's a no-op until `app.apns_function_url` is set as a Postgres GUC. See `MAC-CHECKLIST.md` step 5.
- **Old persisted `linkup.messages` decoding** — `ChatMessage.status` has a default; verify on a device with pre-session-4 storage.

## 1. What Linkup is

iOS app for finding your LinkedIn 1st-degree connections at the same conference/event in real time, on a shared map. Two main tabs — **Discover** (map + list, pre-share CTA → confirm duration + event → see avatars) and **Messages** (per-connection profile sheet + in-app DM with a prefilled "I'm at [event] too" message). Coral primary (#FF5E3A), warm cream background (#FFFBF6), navy text, amber accent.

Owner: Josh (greco.joshua@gmail.com).

## 2. Status at a glance

- iOS SwiftUI app **feature-complete for v1**: auth (Supabase Auth or local), discover/share with real GPS, real cross-device messaging, profile, settings, notifications, delete-account, delete-chat, delete-message.
- LinkedIn import paths:
  - **CSV archive** (`LinkedInNetworkImportService`) — source of truth for the connection list. Can sync via JSON (`/linkedin/archive/sync`) or raw CSV (`/linkedin/archive/upload`).
  - **API/OAuth** (`LinkedInAPIImportService` + Edge Function) — identity verification + picture only. Does NOT fetch connections.
- **Supabase persistence live.** Project `Linkup` (`ghkzdhdwnpppeivwyaej`, org **Forge AI Advisory**). Migrations 0001 → 0007 versioned in `backend/supabase/migrations/`. RLS on every table with Supabase-Auth-aware policies.
- **Edge Functions ready to deploy.** Two functions now: `linkedin-oauth` (the everything-else worker) and `apns`. See `MAC-CHECKLIST.md` step 3.
- **`LinkupTests` target** (16+ tests) for CSV parsing, models, PKCE. `⌘U` on the Mac before a clean build.

## 3. Tech stack & file layout

```
Linkedin Connections/
├── HANDOFF.md                    # This file (agent onboarding)
├── MAC-CHECKLIST.md              # Josh's Mac-side checklist
├── prd.md                        # Product source of truth
├── ALPHA-2-DEVICE-RUNBOOK.md     # Two-device alpha test runbook
├── README.md
├── linkup-prototype.html         # Browser prototype (visual reference)
├── legal/
│   ├── privacy-policy.md
│   └── terms-of-service.md
├── Linkup.xcodeproj/
└── Linkup/
    ├── LinkupApp.swift
    ├── PrivacyInfo.xcprivacy
    ├── Linkup.entitlements
    ├── Resources/Info.plist      # Has ####### placeholders Josh fills
    ├── Models/LinkupModels.swift
    ├── Services/
    │   ├── SupabaseClient.swift          # SPM-gated singleton (session 4)
    │   ├── AuthService.swift             # Supabase Auth + Apple + Google + delete
    │   ├── LocationService.swift         # CoreLocation feed (session 4)
    │   ├── KeychainSessionStore.swift
    │   ├── LinkedInAPIImportService.swift
    │   ├── LinkedInNetworkImportService.swift
    │   ├── LinkupBackendService.swift    # All Edge Function client calls
    │   ├── NotificationService.swift
    │   └── PermissionService.swift
    ├── Store/{AppStore, SampleData}.swift
    ├── Theme/LinkupTheme.swift
    └── Views/                            # Discover, Messages, Settings, Profile, Components

LinkupTests/                       # ⌘U on Mac before clean build
backend/
├── apns/index.ts                  # APNs sender (session 4)
├── supabase/migrations/
│   ├── 0001_linkup_core_schema.sql
│   ├── 0002_live_presence.sql
│   ├── 0003_messages.sql
│   ├── 0004_message_push_trigger.sql
│   ├── 0005_supabase_auth_rls.sql
│   ├── 0006_linkedin_picture.sql
│   └── 0007_presence_geo.sql
└── linkedin/
    ├── linkedin-oauth.ts          # Multi-route Edge Function (build v3)
    ├── README.md                  # Deploy runbook
    └── sample-Connections.csv
```

## 4. Session history (skim only)

- **Session 1 (2026-05-30, backend agent).** Dropped `/v2/connections` + `r_1st_connections`. Added PKCE (S256). Added `GET /version`. Added structured error logging at every LinkedIn boundary. iOS picked up matching PKCE generation + scope.
- **Session 2 (2026-05-30, persistence agent).** Applied core schema (5 tables, RLS, indexes, trigger) live on Supabase. Added Edge-Function-side persistence for identity verify + `/linkedin/archive/sync`. Hardened CSV parser (BOM, quoted commas, CRLF). Added `LinkupTests` target with 16 tests. Migration `0001`.
- **Session 3 (split into three sub-agents on 2026-06-09).**
  - *Backend sub-agent:* migrations 0003 → 0007 (messaging, message push trigger, Supabase Auth RLS, LinkedIn picture, presence geo). Messaging + LinkedIn-picture endpoints in `linkedin-oauth.ts`. New `apns` Edge Function.
  - *App Store sub-agent:* `legal/` docs, `PrivacyInfo.xcprivacy`, `.entitlements`, `Info.plist` URL key + Supabase + legal + notifications keys.
  - *iOS sub-agent:* `SupabaseClient`, `AuthService` rewrite, `LocationService`, real messaging + delete + LinkedIn picture in UI.
- **Session 4 (2026-06-09, this pass — finalisation).** Two backend endpoints landed (`/messages/delete`, `/account/delete`). Build bumped to v3. `HANDOFF.md` collapsed. `MAC-CHECKLIST.md` written.

## 5. What's left for the next agent (post-v1 / v1.1)

Order is loose — pick what unblocks the next user-facing feature.

- ✅ Persistence schema + RLS — DONE (sessions 2 + 3).
- ✅ Identity verify persistence + CSV sync — DONE (session 2).
- ✅ LinkedIn picture fetch — DONE (session 3).
- ✅ Real-time discovery (live_presence) — DONE (session 3 backend + iOS).
- ✅ APNs scaffold + Postgres trigger — DONE (session 3); deploy is in `MAC-CHECKLIST.md`.
- ✅ Real cross-device messaging — DONE (session 3 backend + iOS, session 4 delete endpoints).
- ✅ Supabase Auth + Apple delete-account compliance — DONE (sessions 3 + 4).
- ⏭️ **Realtime swap.** Replace `/messages/poll` with a Supabase Realtime channel keyed on `chat_message.recipient_account_id`. Keep `/poll` as a fallback for the first foreground frame.
- ⏭️ **Server-driven discovery refresh.** Same channel idea for `live_presence`.
- ⏭️ **Read receipts.** `chat_message.read_at` column exists; iOS never PATCHes it. Add `POST /messages/read` + a Realtime subscriber on the sender side.
- ⏭️ **Analytics integration.** Mixpanel or PostHog. Funnel = signup → CSV import → first share → first message.
- ⏭️ **Google OAuth wiring.** Same shape as LinkedIn but easier; placeholders already in Info.plist.
- ⏭️ **Background presence refresh.** Currently presence stops when sharing window expires; consider a silent-push tickle if the user briefly backgrounds the app.
- ⏭️ **App icon artwork.** None today. Apple needs every documented size.

## 6. Open manual items — DO NOT auto-fill

These are Josh's. Placeholders in code are `#######` markers. An agent NEVER pastes values into these.

- `Info.plist` → `LINKEDIN_CLIENT_ID` (LinkedIn Developer Portal → Auth)
- `Info.plist` → `LINKUP_API_BASE_URL` (Supabase function URL, after deploy)
- `Info.plist` → `GOOGLE_OAUTH_CLIENT_ID` + `GOOGLE_OAUTH_REDIRECT_SCHEME` (Google Cloud Console)
- `Info.plist` → `SUPABASE_URL` + `SUPABASE_ANON_KEY` (Supabase project settings → API). Until set, the Supabase Auth path stays dormant.
- Supabase secrets: `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`, `LINKEDIN_REDIRECT_URI` (= `linkup://linkedin-oauth`).
- Supabase secrets for APNs: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` (PEM contents of the `.p8`), `APNS_TOPIC` (= bundle id), `APNS_ENVIRONMENT` (`sandbox` for dev, `production` for App Store).
- Postgres GUC pointing the trigger at the apns function: `alter database postgres set app.apns_function_url = '<the function URL>'`. Until set, message inserts succeed but no push fires.
- LinkedIn Developer Portal → Authorized redirect URLs → confirm `linkup://linkedin-oauth` is registered.
- Apple Developer Portal → APNs Auth Key (.p8), App ID with SIWA + Push capabilities, provisioning profile.

Not a manual item: `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are auto-injected into Edge Functions — never copy them into iOS.

## 7. Known gotchas

- **iOS sandbox can't compile.** This Cowork agent runs Linux without `xcodebuild`. All Swift was logic-validated, not compiled. First Mac action: ⌘U, then clean build.
- **Deno deploy fetches `@supabase/supabase-js` from esm.sh.** Needs network at deploy time.
- **Date format.** Backend strips ms (`...Z` not `....123Z`). iOS uses `.iso8601`. If you ever emit ms, iOS decoding fails silently → debug there.
- **LinkedIn `r_1st_connections` is intentionally not requested.** CSV archive is the canonical source. Don't re-add the scope.
- **Sample CSV in repo is synthetic.** Josh's real export is NOT committed (privacy). For real-data tests, ask Josh to drop a CSV in a local-only `.test-data/`.
- **Service-role bypasses RLS.** All current Edge Function writes use service role. Once iOS moves to direct PostgREST calls with the user's JWT, the policies in `0005` take over automatically.

## 8. User collaboration style (important)

Josh's standing instructions:

1. Ask clarifying questions until ≥95% confident.
2. Restate the goal in your own words and outline the solution. **Pause for go-ahead before writing code.**
3. Present at least two viable design approaches with pros/cons/effort.
4. Break work into milestones with dependencies, time estimates, success checks.
5. Default to libraries / patterns / conventions Josh has used before. Justify any departures.

Skipping any of these creates rework. Apply on every non-trivial task.

## 9. Source-of-truth pointers

- Visual: `linkup-prototype.html`.
- Product: `prd.md`.
- Backend deploy: `backend/linkedin/README.md`.
- Two-device alpha: `ALPHA-2-DEVICE-RUNBOOK.md`.
- Mac-side launch path: `MAC-CHECKLIST.md`.
- Project memory entries: `[[linkup-project]]`, `[[user-collaboration-style]]`.
