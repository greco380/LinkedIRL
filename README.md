# Linkup iOS

Native SwiftUI implementation of the Linkup PRD in `prd.md`, aligned with the companion `linkup-prototype.html`.

## Open

Open `Linkup.xcodeproj` in Xcode 15 or newer, select an iPhone simulator running iOS 17+, and run the `Linkup` scheme.

## Implementation Notes

- Email/password auth supports account creation, salted SHA-256 password verification, existing-account login, and Keychain session restore.
- Apple auth uses native `ASAuthorizationAppleIDProvider` and the app's Sign in with Apple entitlement.
- Google auth uses `ASWebAuthenticationSession` with OpenID Connect. Replace `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_REDIRECT_SCHEME` in `Info.plist` with real Google iOS OAuth credentials before production use.
- LinkedIn API import uses OAuth from the app and a backend token-exchange worker. Replace `LINKEDIN_CLIENT_ID`, `LINKEDIN_REDIRECT_URI`, `LINKEDIN_OAUTH_CALLBACK_SCHEME`, and `LINKUP_API_BASE_URL` in `Info.plist`; put `LINKEDIN_CLIENT_SECRET` only in the backend environment.
- Push notifications register with APNs, store the device token on the account, schedule share-session warning/expiry notifications, and suppress muted-user message notifications locally.
- A backend APNs sender scaffold lives in `backend/apns` for production remote notifications.
- A backend LinkedIn OAuth/import worker lives in `backend/linkedin` for production LinkedIn API imports.
- Session persistence uses Keychain for the auth token marker and UserDefaults for the local account/settings prototype state.
- LinkedIn profile linking validates and stores the user's LinkedIn profile URL and profile slug.
- LinkedIn connection import uses a guided LinkedIn archive flow, records import metadata and profile observations, hashes optional emails, and persists a per-account network database. The local prototype parses `Connections.csv`; production can swap in a backend ZIP archive worker.
- Location and notification permission prompts are requested after login.
- Discover, share session, event pill countdown, connection map/list, per-person hide, mute, Messages, profile sheet, chat prefill, settings, theme persistence, sign out, and reset prototype are implemented.

## Product Assumptions

- v1 requires the user to share before seeing active connections.
- LinkedIn network lookup does not scrape linkedin.com. The compliant v1 path is guided LinkedIn archive import or an official LinkedIn API integration if access is granted.
- Event matching is strict/free-text for v1; fuzzy canonicalization belongs on the backend.
- Muting is local and one-way, as specified in the PRD.
