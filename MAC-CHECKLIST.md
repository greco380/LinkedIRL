# Mac Checklist — Agents Done → App Review Submission

For Josh. Run top to bottom. Each step has the command/URL and what success looks like.

## 1. Add the Supabase Swift Package
- [ ] Xcode → File → Add Package Dependencies… → URL: `https://github.com/supabase-community/supabase-swift`
- [ ] Dependency Rule: Up to Next Major from `2.0.0`.
- [ ] Add products **Supabase** and **Auth** to the **Linkup** target only (not LinkupTests).
- Success: `import Supabase` compiles in `SupabaseClient.swift`; build succeeds.

## 2. Apply Supabase migrations 0003 → 0007
- [ ] Via Supabase MCP `apply_migration` for each file, OR `supabase db push` after `supabase link`.
- [ ] Verify: `select count(*) from chat_message;` returns 0 (table exists). Check `live_presence` has columns `lat`, `lng`, `accuracy_m`. Check `linkup_account` has `linkedin_picture_url`, `push_token`, `auth_user_id`.
- Success: every SELECT above runs without error.

## 3. Deploy Edge Functions
- [ ] `supabase functions deploy linkedin-oauth --no-verify-jwt` (the flag is required — the iOS app calls these endpoints without a Supabase JWT; see backend/linkedin/README.md §4)
- [ ] `supabase functions deploy apns --no-verify-jwt` (same reason: the pg_net trigger posts without a JWT unless you set `app.apns_function_token`)
- [ ] `curl https://<ref>.supabase.co/functions/v1/linkedin-oauth/version` → `{"version":"linkup-linkedin-oauth@2026-06-09-v3"}`.
- [ ] `curl https://<ref>.supabase.co/functions/v1/apns/version` → `{"version":"linkup-apns@2026-06-09-v1"}`.
- Success: both `/version` calls return the strings above.

## 4. Set Supabase secrets
- [ ] `supabase secrets set LINKEDIN_CLIENT_ID=… LINKEDIN_CLIENT_SECRET=… LINKEDIN_REDIRECT_URI=linkup://linkedin-oauth`
- [ ] `supabase secrets set APNS_KEY_ID=… APNS_TEAM_ID=… APNS_TOPIC=com.linkup.app APNS_ENVIRONMENT=sandbox`
- [ ] `supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"` — full PEM including BEGIN/END lines.
- Success: `supabase secrets list` shows all eight keys.

## 5. Wire the message-push trigger
- [ ] In Supabase SQL editor: `alter database postgres set app.apns_function_url = 'https://<ref>.supabase.co/functions/v1/apns/apns/send';`
- [ ] Optional bearer: `alter database postgres set app.apns_function_token = '<token>';`
- Success: insert a test row into `chat_message`; tail Edge Function logs for `apns` and see the push attempt.

## 6. Apple Developer Portal
- [ ] App ID `com.linkup.app` with capabilities: **Sign In with Apple**, **Push Notifications**.
- [ ] Keys → "+" → APNs Auth Key → download the `.p8`. Note the Key ID + Team ID.
- [ ] Register custom URL scheme `linkup://linkedin-oauth` in the app's URL types (if not already).
- [ ] Provisioning profile includes the App ID + APNs entitlement; download + install.
- Success: profile lists both capabilities; `.p8` is on disk.

## 7. LinkedIn Developer Portal
- [ ] App → Auth tab → confirm Authorized redirect URL = `linkup://linkedin-oauth`.
- [ ] Copy **Client ID** + **Client Secret**. Paste Client ID into `Info.plist` (step 8) AND `supabase secrets set LINKEDIN_CLIENT_ID=…`. Client Secret goes ONLY into Supabase secrets — never in iOS.
- Success: Supabase secrets list includes `LINKEDIN_CLIENT_ID` and `LINKEDIN_CLIENT_SECRET`.

## 8. Fill placeholders in `Linkup/Resources/Info.plist`
- [ ] `LINKEDIN_CLIENT_ID` — from LinkedIn portal.
- [ ] `GOOGLE_OAUTH_CLIENT_ID` + matching `CFBundleURLTypes` entry — from Google Cloud Console.
- [ ] `GOOGLE_OAUTH_REDIRECT_SCHEME` — reversed-client-id form.
- [ ] `SUPABASE_ANON_KEY` — Supabase → Settings → API → anon/public.
- [ ] (Confirm `LINKUP_API_BASE_URL` already points at the deployed `linkedin-oauth` function.)
- Success: grep `Info.plist` for `#######` returns no matches.

## 9. Host privacy + terms
- [ ] Publish `legal/privacy-policy.md` at `https://linkup.app/privacy` and `legal/terms-of-service.md` at `https://linkup.app/terms` (or another host — then update `LINKUP_PRIVACY_URL` / `LINKUP_TERMS_URL` in `Info.plist`).
- Success: both URLs return 200 in a private browser window.

## 10. Lawyer review
- [ ] Have counsel review both files in `legal/` before public hosting.
- Success: counsel sign-off email on file.

## 11. App icon artwork
- [ ] Drop final artwork into `Linkup/Assets.xcassets/AppIcon.appiconset/` covering every documented iOS size.
- Success: Xcode → asset catalog shows no missing-icon warnings.

## 12. Xcode build + test
- [ ] Clean build folder (⇧⌘K). Build (⌘B).
- [ ] ⌘U → all `LinkupTests` green.
- [ ] Run on a physical device. Verify sign-up, LinkedIn verify, CSV import, start sharing, see self on map.
- [ ] Run on a SECOND device with a second account. Verify cross-device discovery + sending a DM both ways + push arrives.
- Success: two-device DM round-trip works; see `ALPHA-2-DEVICE-RUNBOOK.md` for the script.

## 13. TestFlight build
- [ ] Archive → upload to App Store Connect.
- [ ] Internal alpha first; invite Josh + 2-3 testers. Confirm push arrives on a TestFlight build (sandbox APNs).
- [ ] Then external for App Review.
- Success: build appears in TestFlight; alpha testers can install + sign in.

## 14. App Store Connect listing
- [ ] Screenshots for every required size class (6.7"/6.5"/5.5" iPhone at minimum).
- [ ] App description, keywords, support URL, marketing URL, privacy URL, terms URL.
- [ ] App Privacy questionnaire — must MATCH `Linkup/PrivacyInfo.xcprivacy` exactly.
- [ ] Age rating: **12+** (in-app user-generated chat is in scope).
- Success: red dots on the listing form are all cleared.

## 15. Submit for App Review
- [ ] Submit. Demo account credentials + reviewer notes included (mention the CSV-import flow).
- Success: status flips to "Waiting for Review".

## 16. Flip aps-environment to production
- [ ] Before the archive that goes to App Store (not TestFlight), edit `Linkup.entitlements`: change `aps-environment` from `development` to `production`.
- [ ] Also flip Supabase secret: `supabase secrets set APNS_ENVIRONMENT=production`.
- Success: production archive uploaded; sandbox APNs no longer used.
