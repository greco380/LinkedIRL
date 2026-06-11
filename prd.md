# Linkup — Product Requirements Document

**Version**: 0.2 (prototype-aligned, adds auth + settings)
**Date**: 2026-05-28
**Owner**: Josh Greco
**Target platform**: iOS 17+ (Swift / SwiftUI)
**Companion prototype**: `linkup-prototype.html` in this directory

## What changed in v0.2

- Added first-time login / signup screen (Apple, Google, LinkedIn, email + password) — section 4.7
- Added persistent account model — section 5
- Added Settings screen, accessed via a gear icon on every tab header — section 4.8
- Added light + dark theme system with full token spec — section 13
- Added LinkedIn connection-import flow (URL + simulated auth + connection count) — section 6
- Updated acceptance criteria (AC11–AC17) for the new surfaces — section 8

---

## 1. Vision

Linkup helps professionals find their LinkedIn 1st-degree connections at the same event — in real time, on a shared map — and gives them a low-friction nudge to actually meet up. The app removes the awkwardness of guessing who's at a conference and the inertia of cold-DMing through LinkedIn.

The core insight: at any given conference, several of your real connections are physically within 500 feet of you, and neither of you knows.

### Non-vision (what Linkup is NOT)
- Not a general-purpose social network. It piggybacks on LinkedIn for identity and graph.
- Not a dating/proximity app. The graph is bounded to 1st-degree professional connections.
- Not a chat app. In-app DM exists only to bridge the moment of meeting in person.
- Not an event discovery tool. Events are just context labels.

---

## 2. Target users & personas

**Primary: The Networking Attendee (Maya)**
A senior IC or manager attending 3–8 conferences per year. Wants to maximize valuable hallway conversations. Currently scans LinkedIn for "who's at X" posts and DMs them. Pain: never knows in real time who's around.

**Secondary: The Founder/Investor (Marcus)**
Goes to events specifically to find people. Already extracts heavy ROI from in-person serendipity. Will adopt any tool that increases hit rate.

**Tertiary: The Conference First-Timer (Aiden)**
Less established network but wants to meet specific connections they've only interacted with online. High intent, low confidence — needs the prefilled message.

---

## 3. Key flows

### Flow A: First-time setup
1. User installs Linkup, opens app → lands on the **Login screen** (section 4.7).
2. User chooses one of four paths:
   - **Continue with Apple** / **Continue with Google** / **Continue with LinkedIn** — OAuth handoff (LinkedIn auto-completes the connection import).
   - **Create account** with full name, email, password (email/password path).
3. After successful auth: location permission request → notification permission → done.
4. Lands on **Discover** tab. If the user did NOT sign in with LinkedIn, an inline prompt suggests connecting LinkedIn from Settings (otherwise the network is empty).
5. User session persists in iOS Keychain; reopening the app skips Login.

**Success check**: User can complete onboarding in under 60 seconds, lands on Discover tab with valid auth tokens stored in Keychain. Closing and reopening the app keeps the user signed in.

### Flow B: Share location at an event
1. User taps **Share my location** on Discover tab.
2. Modal sheet slides up from bottom: hour dial (1–12h, default 2h), optional event name field with suggestions from a curated list and from event hashtags they've used on LinkedIn, Confirm + Cancel.
3. User confirms → modal dismisses → list of 1st-degree connections at the same event populates the bottom split-screen → map fills with avatar pins → toast confirms "Sharing for Nh · [event]".
4. A countdown begins; sharing auto-expires after the chosen duration.
5. While active: a small pill in the Discover header shows "[event] · Nh Nm left".

**Success check**: After confirm, the list shows ≥ 1 connection if any 1st-degree connections are also sharing at the same event name OR within 1 mile geo-radius. Sharing auto-stops at the expiration time and a system notification confirms.

### Flow C: Stop sharing (global or per-person)
- **Global stop**: tap "Stop sharing" in the list header → confirmation toast, sharing ends immediately, list collapses, CTA returns, pins disappear.
- **Per-person stop**: swipe left on any row → "Stop sharing with [name]" button. Tapping hides ONLY this user's view of you on the map and in lists (allowlist subtraction); session continues for everyone else.
- **Mute**: same swipe gesture → "Mute" hides this person from your own map/list and silences any push from them. Mute is symmetric in *your* view only.

**Success check**: Per-person stop hides location from one peer within 30 seconds (server push to that peer). Mute is a local-only setting that survives app restart.

### Flow D: Find a connection & start a chat
1. User opens **Messages** tab → sees a list of 1st-degree connections at the active event, each with a "Here now" badge.
2. Taps a name → profile sheet slides up: photo, name, headline, three stat cards (connected-since year, # shared events including the current one, years of total experience), bio, "Events you've been at together" with the active event pinned at top, career summary.
3. Taps **Let's chat** → in-app DM screen pushes from the right with prefilled text: *"I'm at [event] too, where should we meet?"*. Cursor placed at end so user can edit. Send button is active.
4. User edits or sends as-is. Sent message appears in thread; recipient gets a push notification.

**Success check**: Time from opening Messages tab to sending a DM is ≤ 4 taps. Prefilled text varies based on whether the user has selected an event.

### Flow E: Receive a chat
1. Push notification: "[Name] is here at [event]: [first 80 chars of message]"
2. Tap → opens Linkup directly into the chat thread.

---

## 4. Screens (UI spec)

All screens reference colors, type, and layouts demonstrated in `linkup-prototype.html`. Defer to that prototype for visual truth; this section documents intent and edge cases.

### 4.1 Discover (pre-share)
- Header: "Discover" (30pt, semibold, -0.5 letter-spacing).
- Map area (rounded 20pt, ~60% of body height): user's pulsing blue location dot only. Floor-plan or street-map background per location source.
- Bottom card: gradient coral → orange Connect CTA with location icon, headline "Connect", body "Share your location to see which of your network are at the event with you.", primary button "Share my location".

### 4.2 Share Location modal
- Bottom sheet, 28pt top corners, opaque cream surface.
- Title "Share your location", subtitle.
- Hour dial: horizontal scrollable strip, scroll-snap with central marker showing 1, 2, 3, 4, 5, 6, 8, 12 hours. Selected value mirrors in a large coral numeral above. Haptic on snap.
- Event input: text field with placeholder "e.g. SaaStr Annual 2026". Below: pill suggestions (top 3 events nearby + recent events user mentioned in LinkedIn posts). Suggestions auto-update as user types.
- Primary "Share for N hours" (coral, full-width). Cancel ghost button below.

### 4.3 Discover (sharing)
- Same header + event pill "[event] · Nh Nm left" with pulsing dot.
- Map: avatar pins (36pt circles with white border, downward triangle tail) at each connection's last known position. Tapping a pin → opens that connection's profile sheet. Pin avatars use per-person color from LinkedIn profile or generated from name hash.
- Bottom split: list header "N at [event]" + Stop sharing button. List rows: 44pt avatar, name + headline, distance pill (e.g. "85 ft" — coral text on cream pill).
- Swipe-left on row: reveals 88pt-wide "Stop sharing" (coral) + 88pt-wide "Mute" (slate).

### 4.4 Messages
- Header: "Messages" + event pill if sharing.
- Section label: "At [event]".
- Rows: 44pt avatar, name with "Here now" badge, last chat snippet OR "Tap to start a conversation", chevron.
- Empty state when not sharing: friendly card directing user to Discover tab.

### 4.5 Profile sheet
- Full-screen slide-up. Close (X) button top-left.
- Hero: 72pt avatar, name (22pt bold), headline.
- Three stat cards in a row: connected-since year, # shared events, years experience.
- Bio paragraph (15pt, line-height 1.55).
- "Events you've been at together" — active event pinned at top with coral icon + "Now" badge, then historic events with calendar icons.
- "Career" — sentence describing years at current company + total experience.
- Sticky bottom: "Let's chat" primary CTA.

### 4.7 Login / Signup screen
- Fills the entire viewport on first launch (no status bar / tab bar visible).
- Top: 64pt rounded coral square containing the Linkup pin glyph (location icon) on the brand gradient.
- Title: "Welcome to Linkup" (Sign in) or "Create your Linkup account" (Create account).
- Sub: "Find your network at every event."
- Segmented control toggling between **Sign in** and **Create account** — switches the form copy, button labels, and shows/hides the Name field.
- Three social buttons stacked, each 50pt tall, in order:
  1. **Continue with Apple** — black, white Apple glyph.
  2. **Continue with Google** — white with system border, multicolor G.
  3. **Continue with LinkedIn** — `#0A66C2`, white `in` glyph. Auto-completes the LinkedIn connection import as a side effect of signing in this way.
- "or" divider.
- Form fields: Full name (only in Create account mode), Email, Password.
- Primary "Sign in" / "Create account" button (coral, full-width).
- Footer copy: "By continuing you agree to Linkup's terms and privacy policy." + "Reset prototype" link (only meaningful in the web prototype — in iOS it's a "Forgot password?" link).
- Auth methods are mutually exclusive: a user has exactly one `authMethod` in the account record. They can subsequently link/unlink LinkedIn separately in Settings.

### 4.8 Settings screen
- Accessed by tapping the gear icon (top-right of any tab header). Pushes from the right (iOS push transition).
- Header: back chevron + "Done" label on the left, "Settings" centered.
- Sections (each is an iOS-style rounded card on `--bg`):

**Account** — 38pt avatar (initials on coral) + Name + email address.

**LinkedIn** — Inline status row (icon + "Connected"/"Not connected" + subtitle). When NOT connected: text field for LinkedIn URL + Connect button. Tapping Connect runs a 3-step simulated authentication ("Authenticating…" → "Fetching your network…" → "Importing connections…") and on success shows the imported connection count in the subtitle. When connected: "Refresh connections" and "Disconnect" buttons.

**Appearance** — single row "Theme" with a segmented control: Light / Dark. Selection applies instantly across the whole app and persists to settings.

**Sharing** —
- "Default duration" — stepper (1–12h) for the value the share-location modal opens with.
- "Who can see you" — segmented: 1st / 1st + 2nd. v1 default: 1st.
- "Auto-share at known events" — toggle. When on, arriving at the venue of a curated event triggers a push notification offering one-tap sharing.

**Notifications** — three toggles:
- Connection arrives at my event
- New messages
- Sharing about to expire (15 min warning)

**Account actions** — "Sign out" (red, in a card) + "Reset prototype" (small link below, web-only).

### 4.9 Chat thread
- Header with back chevron, 32pt avatar, name, status ("At [event]" / "Active recently").
- Banner top of thread: "You and [first-name] are both at [event]." (coral text on cream pill).
- Bubbles: my messages right-aligned (coral fill, white text), their messages left-aligned (cream fill, navy text), 18pt corner radius with one corner squared off toward avatar.
- Composer: rounded text field + circular coral send button.
- On open: composer is pre-filled with *"I'm at [event] too, where should we meet?"* — user can edit or send as-is.

---

## 5. Data model

```swift
enum AuthMethod: String, Codable {
    case email, apple, google, linkedin
}

struct Account {
    let id: UUID
    var displayName: String
    var email: String
    var authMethod: AuthMethod
    var appleSubject: String?     // Apple's sub when authMethod == .apple
    var googleSubject: String?
    var passwordHash: String?     // bcrypt — server-side only
    var linkedInConnected: Bool
    var linkedInURL: String?
    var linkedInImportedAt: Date?
    var linkedInConnectionCount: Int
    var createdAt: Date
}

struct UserSettings: Codable {
    var theme: Theme              // .light / .dark / .system
    var defaultShareHours: Int    // 1–12
    var audience: Audience        // .firstDegree / .firstAndSecondDegree
    var autoShareKnownEvents: Bool
    var notifNewSharer: Bool
    var notifNewMessage: Bool
    var notifExpiring: Bool
}

struct User {
    let id: UUID
    let accountID: UUID           // ← references Account
    let linkedInID: String?       // present only after LinkedIn linked
    var displayName: String
    var headline: String
    var photoURL: URL?
    var bio: String?
    var yearsExperience: Int?
    var currentCompany: String?
    var yearsAtCurrentCompany: Int?
    var pushToken: String?
    var mutedUserIDs: Set<UUID>
}

struct Connection {
    let userID: UUID            // the other person's id
    let connectedAt: Date       // when the LinkedIn connection was formed
    var sharedEventIDs: [UUID]  // events both attended (historical)
}

struct ShareSession {
    let id: UUID
    let userID: UUID
    let startedAt: Date
    let expiresAt: Date
    var eventName: String?
    var eventID: UUID?          // matched against curated event list
    var hiddenFromUserIDs: Set<UUID> // per-person allowlist subtraction
    var lastLocation: CLLocationCoordinate2D?
    var lastLocationAt: Date?
}

struct Event {
    let id: UUID
    let name: String
    let startDate: Date
    let endDate: Date
    let venue: String?
    let centroid: CLLocationCoordinate2D?
}

struct Message {
    let id: UUID
    let threadID: UUID          // canonical (sortedUserIDs).joined
    let senderID: UUID
    let body: String
    let sentAt: Date
    var deliveredAt: Date?
    var readAt: Date?
}
```

### Visibility rules (server-enforced)
A user `A` sees another user `B` on the map iff ALL of:
1. `A` and `B` are LinkedIn 1st-degree connections.
2. `B` has an active `ShareSession` (`now < expiresAt`).
3. `A.userID` is NOT in `B.shareSession.hiddenFromUserIDs`.
4. Either `A.shareSession.eventID == B.shareSession.eventID` (same event), OR — when no event is set on either side — both share sessions' last locations are within 1.0 km of each other. (v1 default to event-only matching; geo fallback is v1.1.)
5. `A` has NOT muted `B` (filter done client-side after server returns the set).

---

## 6. Integrations & external dependencies

### Apple Sign-In
- ASAuthorizationAppleIDProvider. Required for App Store policy when offering 3rd-party social auth.
- Save Apple's `sub` claim as `appleSubject` for re-auth.

### Google Sign-In
- Google Sign-In SDK or Sign in with Google via web flow.

### LinkedIn — two distinct surfaces
**1. Sign in with LinkedIn (authentication)**
- LinkedIn OpenID Connect. Required scopes: `openid`, `profile`, `email`.
- When a user signs in with LinkedIn, this also satisfies the connection-import step below (no separate URL entry needed). The `linkedInConnected` flag is set true automatically.

**2. Linking LinkedIn after non-LinkedIn signup (data import)**
- Settings screen shows a LinkedIn URL field + Connect button. The simulated flow (Auth → Fetch → Import) corresponds to: LinkedIn OAuth scope upgrade if API access permits, OR a fallback for the user to upload a LinkedIn data-export CSV (LinkedIn provides this via account settings).
- **Open question**: API access to 1st-degree connection list. LinkedIn restricts this heavily for new apps. v1 likely uses CSV import + show progress as if it were a live OAuth fetch.

Profile fields we display (headline, bio, current company, photo) come from the OIDC userinfo where available; full headlines/bios may require the user to paste / re-confirm during onboarding.

### Apple Maps / MapKit
- Use MapKit for the map view. Custom annotation views for avatar pins.
- Indoor venue maps: out of scope for v1. Use street-level map. Plan v1.1 partnership with a venue-map provider for top-50 US conferences.

### Push notifications (APNs)
- New message
- Match: "[Name] just started sharing at [event]"
- Sharing-about-to-expire (15 min warning)
- Sharing-expired

### Backend
- Recommended stack: Supabase (auth + Postgres + realtime + edge functions) given the connector already wired in this workspace, OR Firebase. Realtime channel per event for location updates.
- Location updates: client batches updates every 30 seconds while sharing is active and app is foreground; reduces to 2 minutes in background. Drop updates when accuracy is worse than 100 m.

---

## 7. Privacy & consent

These are first-class product requirements, not afterthoughts. The app handles real-time location for real people.

- **Explicit opt-in per session**: location is only ever shared during an active `ShareSession`. There is no background "always-on" mode in v1.
- **Time-boxed by default**: every session has an `expiresAt`. Max session length is 12 hours.
- **Audience-bounded**: location is visible ONLY to 1st-degree LinkedIn connections, never to strangers.
- **Per-person revocation** is one swipe away in the list.
- **Hard kill switch**: a single "Stop sharing" button at the top of the list ends the session instantly.
- **Data retention**: location history is not stored past 24 hours. After session expiry, the last-known location is deleted.
- **Onboarding consent screen**: explicit copy explaining (a) who can see you, (b) how to stop, (c) auto-expiry. Required check before location permission is requested.
- **iOS permission strings** (Info.plist):
  - `NSLocationWhenInUseUsageDescription`: "Linkup uses your location only when you've actively chosen to share — for the time window you choose — and only with your LinkedIn connections at the same event."
  - `NSUserTrackingUsageDescription`: not needed (no third-party tracking in v1).

---

## 8. Acceptance criteria — v1

| # | Criterion | How to verify |
|---|---|---|
| AC1 | User can sign in with LinkedIn and reach Discover tab in ≤ 60 s | Manual run-through on TestFlight build |
| AC2 | Tapping Connect CTA opens modal; selecting 2h + event name + Confirm starts an active session | Integration test on iOS simulator |
| AC3 | While sharing, map shows pins for every 1st-degree connection also sharing at same event name | Two-device manual test |
| AC4 | Session auto-expires at chosen time and user receives a notification | Time-mock test |
| AC5 | Swipe-left on a row reveals exactly two actions; Stop hides user from that peer within 30 s; Mute persists across app restart | Two-device test + relaunch |
| AC6 | Messages tab profile shows headline, photo, connected-since year, shared event count (incl. current), years exp, bio | Manual verification |
| AC7 | Let's chat opens thread with text "I'm at [event] too, where should we meet?" prefilled and editable | UI test asserting text content of composer |
| AC8 | All location data older than 24h is deleted server-side | Backend job log inspection |
| AC9 | Empty state on Messages tab when no active session | UI test |
| AC10 | App passes Apple's location/privacy review on first submission | App Store Connect review status |
| AC11 | First app launch shows Login screen with all four auth methods (Apple, Google, LinkedIn, email/password) | Manual fresh-install check |
| AC12 | After successful login, closing and reopening the app skips Login — session persists in Keychain | Manual relaunch test |
| AC13 | Sign out from Settings returns the user to the Login screen and clears Keychain tokens | UI test |
| AC14 | Settings → Appearance theme switch updates the entire app to the chosen palette in under 200ms with no flash of unstyled content | Visual test in both modes |
| AC15 | Setting persistence: all toggles, theme, and default-duration choices survive an app relaunch | UI test |
| AC16 | LinkedIn connection flow (URL → Authenticate → Fetch → Import) completes and surfaces the imported connection count | Manual integration test |
| AC17 | Gear icon (top-right of every tab header) opens Settings with a push transition; back returns user to the tab they came from | UI test |

---

## 9. Out of scope for v1

- Group chats / pre-arranged meet-ups
- Calendar/event ingestion from third-party (Eventbrite, Luma) — v1 uses a curated list + free-text
- Indoor / venue floor plans beyond stylized maps
- Connection invitations (must already be 1st-degree on LinkedIn)
- Web app — iOS only at launch
- Android port — slated for v1.5

---

## 10. Tech stack (recommended)

- **App**: SwiftUI for views, Combine for state, MapKit for map.
- **State**: An `AppStore` (single source of truth) with sub-stores for `ShareSession`, `Connections`, `Threads`. Use SwiftData or Core Data for local cache.
- **Network**: URLSession + structured concurrency (async/await). Realtime updates via Supabase Realtime websocket subscription.
- **Auth**: ASWebAuthenticationSession for LinkedIn OAuth; tokens in Keychain.
- **Push**: APNs via the chosen backend's push module.
- **Location**: CoreLocation, `requestWhenInUseAuthorization` only.
- **Analytics**: Posthog or Amplitude (event taxonomy below). No third-party SDKs that fingerprint.

### Event taxonomy
- `app_opened`
- `share_session_started` (params: hours, event_set)
- `share_session_stopped` (params: reason — manual / expired / per_person)
- `connection_muted`, `connection_unmuted`
- `profile_opened` (params: source — map_pin / messages_tab / list)
- `chat_opened`
- `chat_message_sent` (params: text_edited_bool)

---

## 11. Milestones

| # | Milestone | Dependencies | Estimate | Success check |
|---|---|---|---|---|
| M1 | Project scaffold + LinkedIn OAuth + onboarding | — | 1 week | TestFlight build shows Discover tab post-auth |
| M2 | Map + ShareSession + location pipeline | M1 | 1.5 weeks | Two devices show each other's pins |
| M3 | List + swipe actions + visibility rules | M2 | 1 week | AC5 passes |
| M4 | Messages tab + profile sheet | M1 | 1 week | AC6 passes |
| M5 | Chat thread + prefilled DM + APNs | M4 | 1.5 weeks | AC7 + AC10 acceptance |
| M6 | Polish, edge cases, App Store review | M1–M5 | 1 week | Submitted for review |

**Total v1 estimate**: ~7 weeks of focused single-engineer work, or 4 weeks with a 2-engineer team.

---

## 12. Open questions

1. **LinkedIn connections data**: API access vs. CSV import vs. invite-only graph for v1?
2. **Reciprocity**: should the user be required to share their own location before they can SEE others sharing? (Current prototype assumes yes — Connect CTA replaces the list.)
3. **Event canonicalization**: free text vs. curated list. If two users type "TechCrunch Disrupt" and "TC Disrupt 2026", do they match? (Recommend: fuzzy match server-side with confirmation.)
4. **Mute symmetry**: when A mutes B, should B still see A's location? (Current spec: yes — mute is one-way / local.)
5. **What if both sides set no event name?** v1.1 1km geo-fallback acceptable, or strict event-required for v1?

---

---

## 13. Theme system (light / dark)

Linkup ships with two fully-designed themes. The theme is owned by `UserSettings.theme` and persists. There is no "system" mode in v1 (user picks explicitly); we may add it in v1.1.

Implementation: SwiftUI environment value (`@Environment(\.linkupTheme)`) backed by a `Theme` struct with the full token set. The prototype's CSS variable names map 1:1 to the Swift tokens.

### Token map (light → dark)

| Token | Light | Dark | Used for |
|---|---|---|---|
| bg | #FFFBF6 | #0F1419 | App background |
| bgSecondary | #F5EFE7 | #1A2230 | Input fields, stat cards, bubble-them |
| surface | #FFFFFF | #1E293B | Raised cards |
| textPrimary | #0F1726 | #F1F5F9 | Headers, names, body |
| textSecondary | #64748B | #94A3B8 | Meta, subtitles |
| textTertiary | #94A3B8 | #64748B | Hints, placeholders |
| textQuaternary | #C9C2B5 | #475569 | Chevrons, disabled |
| primary | #FF5E3A | #FF7050 | Brand coral (slightly lighter in dark for contrast) |
| primaryLight | #FFF1EA | #2E1814 | Tinted backgrounds (badges, banners) |
| primaryDark | #C03A1A | #FFB69E | Text on primary-light |
| mapBg1, mapBg2 | warm tans | navy/slate | Convention floor background |
| mapBooth | #E8DCC9 | #2A364D | Booth blocks |
| mapHall | #FAF5EE | #1F2937 | Walking paths |
| youPin | #0066FF | #4D9FFF | User's own location pin |

### Design rules
- Coral primary is preserved across both themes (only slightly brightened in dark for AA contrast).
- All shadows in dark mode are subtler (the dark background already provides depth). Specifically: drop the `0 8px 24px` CTA shadow opacity from 0.25 → 0.18 in dark mode if AA contrast permits — currently the prototype keeps shadow opacity equal.
- Map floor plan recolors entirely — warm tan booths become cool navy in dark.
- Avatar colors (Maya = coral, David = indigo, etc.) DO NOT change between themes; they are identity colors.
- Apple/Google/LinkedIn social buttons follow their respective brand guidelines and adapt only their background to remain on-brand in dark mode (e.g., Apple button becomes white in dark; LinkedIn deepens slightly).

---

## 14. Persistence (client-side)

| Data | Location | Notes |
|---|---|---|
| Auth tokens (access, refresh) | iOS Keychain | Group-shareable across app extensions |
| `Account` snapshot | SwiftData / UserDefaults | Updated on profile changes |
| `UserSettings` | UserDefaults | Survives reinstall via iCloud Keychain backup |
| Recent chats cache | SwiftData (local) | TTL 30 days |
| Last known location of peers | In-memory only | Never persisted past app kill |
| Image cache | URLCache | Default policy |

The web prototype uses `localStorage` under the key `linkup_v02` to mirror the account + settings + chats. The "Reset prototype" button removes this key and reloads to demonstrate first-launch behavior.

---

## Appendix A — Visual reference

See `linkup-prototype.html` in this directory for the full interactive prototype, including all colors, motions, and interactions described above. The prototype is the source of truth for visual design until a Figma file supersedes it.
